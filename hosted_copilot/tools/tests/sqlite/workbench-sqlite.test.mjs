import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync, spawn } from 'node:child_process';
import { once } from 'node:events';
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { Worker } from 'node:worker_threads';
import { openWorkbenchSqlite } from '../../modules/workbench/WorkbenchSqlite.mjs';
import { migrateNewWorkbenchApplication, migrateWorkbenchApplication, validateWorkbenchApplicationSchema, workbenchSchemaVersion } from '../../modules/workbench/WorkbenchApplicationSchema.mjs';
import { ingestProtectedCapture } from '../../modules/workbench/WorkbenchProtectedSnapshots.mjs';
import { readSelectedCapacityPolicy, readSelectedCapacityConfiguration } from '../../modules/workbench/WorkbenchWorkspace.mjs';
import { beginAnalysisRun, registerEvaluatorProfile, recordEvaluationRequest, commitAssessmentResults, commitReconciliationComponents, failEvaluation, readAssessmentRecoveryPlan, prepareEvaluationInput } from '../../modules/workbench/WorkbenchEvaluations.mjs';
import { registerSourceDefinition, ingestSourceCollection } from '../../modules/workbench/WorkbenchSourceIngestion.mjs';
import { configureProfileLlms, readWorkspaceLlmAssignments } from '../../modules/workbench/WorkbenchLlmAssignments.mjs';
import { continueAssessmentRun, withAssessmentExecutionLock, withExecutionCancellation } from '../../modules/workbench/WorkbenchAssessmentRecovery.mjs';
import { executeAssessmentBatches, measureAssessmentInputBytes } from '../../modules/workbench/WorkbenchAssessmentExecution.mjs';
import { planNativeReconciliation, executeNativeDownstream } from '../../modules/workbench/WorkbenchDownstreamExecution.mjs';
import { commitSynthesisResults } from '../../modules/workbench/WorkbenchReconciliationResults.mjs';
import { prepareAdjudicationInput, recordAdjudicationRequest, commitAdjudicationResults } from '../../modules/workbench/WorkbenchAdjudication.mjs';
import { completeNativeAnalysis } from '../../modules/workbench/WorkbenchAnalysisCompletion.mjs';

const databaseBridgePath = fileURLToPath(new URL('../../modules/workbench/WorkbenchDatabase.mjs', import.meta.url));

const constraintSchema = `
    CREATE TABLE owners (id INTEGER PRIMARY KEY, code TEXT NOT NULL UNIQUE) STRICT;
    CREATE TABLE evidence (
      id INTEGER PRIMARY KEY,
      owner_id INTEGER NOT NULL REFERENCES owners(id),
      score INTEGER NOT NULL CHECK(score BETWEEN 0 AND 100),
      enabled INTEGER NOT NULL CHECK(enabled IN (0, 1))
    ) STRICT;
    INSERT INTO owners VALUES (1, 'fixture-owner');
    INSERT INTO evidence VALUES (1, 1, 50, 1);
`;

function createConstraintFixture(connection) {
  connection.exec(constraintSchema);
}

test('every fresh connection verifies foreign keys, STRICT support and bounded busy handling', () => {
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const connection = openWorkbenchSqlite({ mode: 'memory', busyTimeoutMilliseconds: 25 });
    try {
      assert.equal(connection.get('PRAGMA foreign_keys').foreign_keys, 1);
      assert.equal(connection.get('PRAGMA busy_timeout').timeout, 25);
      createConstraintFixture(connection);
      assert.equal(connection.get("SELECT strict FROM pragma_table_list WHERE name = 'evidence'").strict, 1);
      assert.throws(() => connection.run('INSERT INTO evidence VALUES (?, ?, ?, ?)', [2, 999, 50, 1]), { errcode: 787 });
      assert.throws(() => connection.run('DELETE FROM owners WHERE id = ?', [1]), { errcode: 787 });
      assert.throws(() => connection.run('INSERT INTO evidence VALUES (?, ?, ?, ?)', [2, 1, 'invalid', 1]), { errcode: 3091 });
      assert.throws(() => connection.run('INSERT INTO evidence VALUES (?, ?, ?, ?)', [2, 1, 101, 1]), { errcode: 275 });
      assert.throws(() => connection.run('INSERT INTO evidence VALUES (?, ?, ?, ?)', [2, 1, 50, 2]), { errcode: 275 });
      assert.throws(() => connection.run('INSERT INTO owners VALUES (?, ?)', [2, 'fixture-owner']), { errcode: 2067 });
      assert.throws(() => connection.run('INSERT INTO owners VALUES (?, ?)', [2, null]), { errcode: 1299 });
      assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
    } finally {
      connection.close();
    }
  }
});

test('SQL cannot disable connection safeguards or attach another database', () => {
  const connection = openWorkbenchSqlite({ mode: 'memory' });
  try {
    createConstraintFixture(connection);
    for (const sql of [
      'PRAGMA foreign_keys = OFF',
      'PRAGMA ignore_check_constraints = ON',
      'PRAGMA writable_schema = ON',
      'PRAGMA busy_timeout = 99999',
      "ATTACH DATABASE ':memory:' AS other",
    ]) {
      assert.throws(() => connection.exec(sql), { errcode: 23 });
    }
    assert.equal(connection.get('PRAGMA foreign_keys').foreign_keys, 1);
    assert.equal(connection.all('PRAGMA table_info(evidence)').length, 4);
    assert.equal(connection.all('PRAGMA foreign_key_list(evidence)').length, 1);
    assert.throws(() => connection.run('INSERT INTO evidence VALUES (?, ?, ?, ?)', [2, 999, 50, 1]), { errcode: 787 });
    const quotedValue = "fixture'); DROP TABLE evidence; --";
    connection.run('INSERT INTO owners VALUES (?, ?)', [2, quotedValue]);
    assert.equal(connection.get('SELECT code FROM owners WHERE id = ?', [2]).code, quotedValue);
    assert.equal(connection.get('SELECT count(*) AS count FROM evidence').count, 1);
  } finally {
    connection.close();
  }
});

test('deferred FK failure rolls back the complete transaction', () => {
  const connection = openWorkbenchSqlite({ mode: 'memory' });
  try {
    connection.exec(`
      CREATE TABLE parents (id INTEGER PRIMARY KEY) STRICT;
      CREATE TABLE children (
        id INTEGER PRIMARY KEY,
        parent_id INTEGER NOT NULL REFERENCES parents(id) DEFERRABLE INITIALLY DEFERRED
      ) STRICT;
      CREATE TABLE audit (id INTEGER PRIMARY KEY, action TEXT NOT NULL) STRICT;
      BEGIN IMMEDIATE;
      INSERT INTO children VALUES (1, 999);
      INSERT INTO audit VALUES (1, 'fixture-attempt');
    `);
    assert.throws(() => connection.exec('COMMIT'), { errcode: 787 });
    connection.exec('ROLLBACK');
    assert.equal(connection.get('SELECT count(*) AS count FROM children').count, 0);
    assert.equal(connection.get('SELECT count(*) AS count FROM audit').count, 0);
  } finally {
    connection.close();
  }
});

test('file inspection is read-only across reopenings and never creates missing files', () => {
  const temporary = mkdtempSync(join(tmpdir(), 'hosted-sqlite-connection-'));
  try {
    const databasePath = join(temporary, 'fixture.sqlite');
    const fixture = new DatabaseSync(databasePath, { enableForeignKeyConstraints: true });
    try { createConstraintFixture(fixture); } finally { fixture.close(); }
    const hash = () => createHash('sha256').update(readFileSync(databasePath)).digest('hex');
    const originalHash = hash();
    const originalFiles = readdirSync(temporary).sort();
    for (let attempt = 0; attempt < 2; attempt += 1) {
      const connection = openWorkbenchSqlite({ mode: 'read-only', databasePath });
      try {
        assert.equal(connection.readOnly, true);
        assert.equal(connection.get('PRAGMA foreign_keys').foreign_keys, 1);
        assert.equal(connection.get('PRAGMA query_only').query_only, 1);
        assert.equal(connection.get('SELECT score FROM evidence WHERE id = ?', [1]).score, 50);
        assert.throws(() => connection.exec('UPDATE evidence SET score = 20'), { errcode: 8 });
        assert.throws(() => connection.exec('PRAGMA query_only = OFF'), { errcode: 23 });
        assert.throws(() => connection.exec('PRAGMA journal_mode = WAL'), { errcode: 23 });
        const forbiddenCopy = join(temporary, 'forbidden-copy.sqlite');
        assert.throws(() => connection.run('VACUUM INTO ?', [forbiddenCopy]), { errcode: 23 });
        assert.equal(existsSync(forbiddenCopy), false);
        assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
        assert.equal(connection.get('PRAGMA integrity_check').integrity_check, 'ok');
      } finally {
        connection.close();
      }
      assert.equal(hash(), originalHash);
      assert.deepEqual(readdirSync(temporary).sort(), originalFiles);
    }
    const missingPath = join(temporary, 'missing.sqlite');
    assert.throws(() => openWorkbenchSqlite({ mode: 'read-only', databasePath: missingPath }), { code: 'ENOENT' });
    assert.equal(existsSync(missingPath), false);
    const linkedDirectory = join(temporary, 'linked');
    symlinkSync(temporary, linkedDirectory, process.platform === 'win32' ? 'junction' : 'dir');
    assert.throws(() => openWorkbenchSqlite({ mode: 'read-only', databasePath: join(linkedDirectory, 'fixture.sqlite') }), /links or junctions/);
    rmSync(linkedDirectory);
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
});

test('inspection sees committed WAL data without changing database or WAL bytes', () => {
  const temporary = mkdtempSync(join(tmpdir(), 'hosted-sqlite-wal-'));
  const databasePath = join(temporary, 'fixture.sqlite');
  const writer = new DatabaseSync(databasePath, { enableForeignKeyConstraints: true });
  try {
    writer.exec('PRAGMA journal_mode = WAL; PRAGMA wal_autocheckpoint = 0');
    createConstraintFixture(writer);
    for (const score of [50, 75]) {
      const beforeDatabase = readFileSync(databasePath);
      const beforeWal = readFileSync(databasePath + '-wal');
      const connection = openWorkbenchSqlite({ mode: 'read-only', databasePath });
      try {
        assert.equal(connection.get('PRAGMA journal_mode').journal_mode, 'wal');
        assert.equal(connection.get('SELECT score FROM evidence WHERE id = ?', [1]).score, score);
        assert.throws(() => connection.exec('UPDATE evidence SET score = 20'), { errcode: 8 });
        assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
      } finally {
        connection.close();
      }
      assert.deepEqual(readFileSync(databasePath), beforeDatabase);
      assert.deepEqual(readFileSync(databasePath + '-wal'), beforeWal);
      if (score === 50) writer.exec('UPDATE evidence SET score = 75 WHERE id = 1');
    }
  } finally {
    writer.close();
    rmSync(temporary, { recursive: true, force: true });
  }
});

test('worker-owned connections use the same enforcement policy', { timeout: 10000 }, async () => {
  const worker = new Worker(`
    const { parentPort, workerData } = require('node:worker_threads');
    import(workerData.moduleUrl).then(({ openWorkbenchSqlite }) => {
      const connection = openWorkbenchSqlite({ mode: 'memory' });
      try {
        connection.exec(workerData.schema);
        let rejectionCode = null;
        try { connection.run('INSERT INTO evidence VALUES (?, ?, ?, ?)', [2, 999, 50, 1]); }
        catch (error) { rejectionCode = error.errcode; }
        parentPort.postMessage({ foreignKeys: connection.get('PRAGMA foreign_keys').foreign_keys, rejectionCode });
      } finally { connection.close(); }
    });
  `, {
    eval: true,
    workerData: {
      moduleUrl: new URL('../../modules/workbench/WorkbenchSqlite.mjs', import.meta.url).href,
      schema: constraintSchema,
    },
  });
  try {
    const result = await new Promise((resolveResult, rejectResult) => {
      worker.once('message', resolveResult);
      worker.once('error', rejectResult);
      worker.once('exit', code => rejectResult(new Error(`Worker exited before reporting connection checks (${code}).`)));
    });
    assert.deepEqual(result, { foreignKeys: 1, rejectionCode: 787 });
  } finally {
    await worker.terminate();
  }
});

test('durable workspace creation and reopening retain writes and reject existing or missing destinations', () => {
  const temporary = mkdtempSync(join(tmpdir(), 'hosted-sqlite-durable-'));
  try {
    const databasePath = join(temporary, 'workspace.sqlite');
    const created = openWorkbenchSqlite({ mode: 'create', databasePath, busyTimeoutMilliseconds: 25 });
    try {
      assert.equal(created.readOnly, false);
      assert.equal(created.get('PRAGMA journal_mode').journal_mode, 'wal');
      assert.equal(created.get('PRAGMA synchronous').synchronous, 2);
      createConstraintFixture(created);
      assert.throws(() => created.exec('PRAGMA foreign_keys = OFF'), { errcode: 23 });
    } finally { created.close(); }
    const originalBytes = readFileSync(databasePath);
    assert.throws(() => openWorkbenchSqlite({ mode: 'create', databasePath }), /existing destination is preserved/);
    assert.deepEqual(readFileSync(databasePath), originalBytes);
    const reopened = openWorkbenchSqlite({ mode: 'read-write', databasePath });
    try {
      assert.equal(reopened.get('PRAGMA foreign_keys').foreign_keys, 1);
      assert.equal(reopened.get('SELECT score FROM evidence WHERE id = 1').score, 50);
      reopened.run('UPDATE evidence SET score = ? WHERE id = ?', [75, 1]);
      assert.throws(() => reopened.run('INSERT INTO evidence VALUES (?, ?, ?, ?)', [2, 999, 50, 1]), { errcode: 787 });
      assert.throws(() => reopened.exec('PRAGMA journal_mode = DELETE'), { errcode: 23 });
    } finally { reopened.close(); }
    const inspected = openWorkbenchSqlite({ mode: 'read-only', databasePath });
    try { assert.equal(inspected.get('SELECT score FROM evidence WHERE id = 1').score, 75); }
    finally { inspected.close(); }
    const missingPath = join(temporary, 'missing.sqlite');
    assert.throws(() => openWorkbenchSqlite({ mode: 'read-write', databasePath: missingPath }), { code: 'ENOENT' });
    assert.equal(existsSync(missingPath), false);
    assert.throws(() => openWorkbenchSqlite({ mode: 'create', databasePath: join(temporary, 'missing-parent', 'workspace.sqlite') }), { code: 'ENOENT' });
    const linked = join(temporary, 'linked');
    symlinkSync(temporary, linked, process.platform === 'win32' ? 'junction' : 'dir');
    assert.throws(() => openWorkbenchSqlite({ mode: 'create', databasePath: join(linked, 'new.sqlite') }), /links or junctions/);
    assert.throws(() => openWorkbenchSqlite({ mode: 'read-write', databasePath: join(linked, 'workspace.sqlite') }), /links or junctions/);
    rmSync(linked);
  } finally { rmSync(temporary, { recursive: true, force: true }); }
});

test('ambiguous modes, implicit file creation and invalid timeout inputs fail closed', () => {
  assert.throws(() => openWorkbenchSqlite(), /SQLite mode explicitly/);
  assert.throws(() => openWorkbenchSqlite({ mode: 'read-write', databasePath: 'unused.sqlite' }), /absolute local/);
  assert.throws(() => openWorkbenchSqlite({ mode: 'memory', databasePath: 'unused.sqlite' }), /do not accept/);
  assert.throws(() => openWorkbenchSqlite({ mode: 'read-only', databasePath: 'relative.sqlite' }), /absolute local/);
  assert.throws(() => openWorkbenchSqlite({ mode: 'read-only', databasePath: '\\\\server\\share\\fixture.sqlite' }), /absolute local/);
  assert.throws(() => openWorkbenchSqlite({ mode: 'read-only', databasePath: '//server/share/fixture.sqlite' }), /absolute local/);
  for (const busyTimeoutMilliseconds of [-1, 5001, 0.1, '1000', NaN]) {
    assert.throws(() => openWorkbenchSqlite({ mode: 'memory', busyTimeoutMilliseconds }), /integer between/);
  }
});

function applicationFixture(context, databasePath, schemaVersion = workbenchSchemaVersion) {
  const connection = openWorkbenchSqlite(databasePath ? { mode: 'create', databasePath } : { mode: 'memory' });
  context.after(() => connection.close());
  migrateNewWorkbenchApplication(connection, { schemaVersion });
  connection.exec(`
    INSERT INTO capacity_policies VALUES (1000, 'synthetic-selected-policy', 1, 'character-quarter-estimate-v1', '1', 4, 25, 110000, 25000);
    INSERT INTO team_profiles VALUES (1, 'synthetic', 'Synthetic profile', 1000);
    INSERT INTO actors VALUES (1, 'system', NULL, NULL, 'SYSTEM'), (2, 'person', 'fixture', 'synthetic-person', 'Synthetic person');
    INSERT INTO repositories VALUES (1, 'fixture', NULL, 'synthetic/workspace');
    INSERT INTO repository_contexts VALUES (1, 1, 'refs/heads/synthetic', '1111111111111111111111111111111111111111', '2026-11-05T00:00:00.000Z');
    INSERT INTO workspace_identity(id, database_guid, team_profile_id, origin_context_id, created_by_actor_id, created_at)
      VALUES (1, '12345678-1234-4234-8234-123456789abc', 1, 1, 2, '2026-11-05T00:00:00.000Z');
    INSERT INTO guidance_surfaces VALUES (1, 'implementation', 1, 'Implementation', '.github/instructions/synthetic.instructions.md', 'synthetic-renderer');
    INSERT INTO action_definitions VALUES (1, 'update', 'Update');
    INSERT INTO plan_add_methods VALUES (1, 'manual', 'Manual'), (2, 'bulk', 'Bulk');
    INSERT INTO wording_versions VALUES (1, 'Synthetic wording', '${'1'.repeat(64)}', '2026-11-05T00:00:00.000Z');
    INSERT INTO rules VALUES (1, 'SYNTHETIC-001', 'managed', NULL), (2, 'SYNTHETIC-002', 'managed', NULL), (3, 'SYNTHETIC-003', 'protected', NULL);
    INSERT INTO rule_versions VALUES (1, 1, 1, 1, 'active', NULL, 'synthetic', NULL), (2, 2, 1, 1, 'active', NULL, 'synthetic', NULL);
  `);
  return connection;
}

test('application migration composes the actual component schemas and validates without mutating them', context => {
  const connection = applicationFixture(context);
  const before = connection.all('SELECT * FROM sqlite_schema ORDER BY name');
  assert.deepEqual(validateWorkbenchApplicationSchema(connection), { valid: true, schemaVersion: workbenchSchemaVersion, problems: [] });
  assert.deepEqual(connection.all('SELECT * FROM sqlite_schema ORDER BY name'), before);
  assert.ok(connection.all("SELECT name FROM pragma_table_list WHERE name NOT LIKE 'sqlite_%'").length > 100);
  assert.deepEqual(connection.all("SELECT name FROM pragma_table_list WHERE name NOT LIKE 'sqlite_%' AND strict <> 1"), []);
  assert.equal(connection.isTransaction, false);
  assert.throws(() => migrateNewWorkbenchApplication(connection), /empty database/);
  assert.throws(() => connection.exec('DELETE FROM application_migrations'), /immutable/);
  assert.throws(() => connection.exec("INSERT INTO actors VALUES (3, 'system', NULL, NULL, 'Second SYSTEM')"), /UNIQUE/);
  assert.throws(() => connection.exec("INSERT INTO actors VALUES (3, 'person', NULL, NULL, 'Unresolved person')"), /CHECK/);
});

test('application upgrade preserves revision-one data and installs exact assessment input dependencies', context => {
  const { connection, binding, run, profileId, sourceVersionIds } = nativeAssessmentFixture(context, { sourceCount: 2, schemaVersion: 1 });
  const recorded = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId, sourceVersionIds });
  commitAssessmentResults(connection, { binding, runId: run.runId, evaluationId: recorded.evaluationId,
    inputFingerprint: recorded.inputFingerprint, result: nativeAssessmentResult(recorded) });
  const findingId = Number(connection.run('INSERT INTO findings(evaluation_id, finding_kind, title, rationale) VALUES (?, ?, ?, ?)',
    [recorded.evaluationId, 'synthetic-observation', 'Synthetic finding', 'Existing captured evidence']).lastInsertRowid);
  const assessmentId = connection.get('SELECT id FROM assessment_results ORDER BY id LIMIT 1').id;
  connection.run('INSERT INTO finding_participants(finding_id, participant_role, ordinal, assessment_result_id, evidence_quote) VALUES (?, ?, ?, ?, ?)',
    [findingId, 'source', 0, assessmentId, 'Captured evidence']);
  const participantColumns = connection.all('PRAGMA table_info(finding_participants)').map(column => column.name);
  const participantsBefore = connection.all('SELECT * FROM finding_participants ORDER BY id');
  const inputColumns = connection.all('PRAGMA table_info(evaluation_inputs)').map(column => column.name);
  const inputsBefore = connection.all('SELECT * FROM evaluation_inputs ORDER BY id');
  const resultsBefore = connection.all('SELECT * FROM assessment_results ORDER BY id');
  const evaluationsBefore = connection.all('SELECT * FROM evaluations ORDER BY id');
  const request = { databaseGuid: '12345678-1234-4234-8234-123456789abc', expectedSchemaVersion: 1 };
  assert.deepEqual(migrateWorkbenchApplication(connection, request), { databaseGuid: request.databaseGuid, priorSchemaVersion: 1, schemaVersion: workbenchSchemaVersion });
  assert.deepEqual(connection.all(`SELECT ${inputColumns.join(', ')} FROM evaluation_inputs ORDER BY id`), inputsBefore);
  assert.deepEqual(connection.all('SELECT * FROM assessment_results ORDER BY id'), resultsBefore);
  assert.deepEqual(connection.all('SELECT * FROM evaluations ORDER BY id'), evaluationsBefore);
  assert.deepEqual(connection.all(`SELECT ${participantColumns.join(', ')} FROM finding_participants ORDER BY id`), participantsBefore);
  connection.run('INSERT INTO finding_participants(finding_id, participant_role, ordinal, rule_version_id) VALUES (?, ?, ?, ?)', [findingId, 'baseline', 1, 1]);
  assert.throws(() => connection.run('INSERT INTO finding_participants(finding_id, participant_role, ordinal, rule_version_id) VALUES (?, ?, ?, ?)',
    [findingId, 'baseline', 2, 999999]), /FOREIGN KEY/);
  assert.throws(() => connection.run('INSERT INTO finding_participants(finding_id, participant_role, ordinal, rule_version_id, assessment_result_id) VALUES (?, ?, ?, ?, ?)',
    [findingId, 'baseline', 2, 1, assessmentId]), /CHECK/);
  assert.equal(validateWorkbenchApplicationSchema(connection).valid, true);
  assert.ok(connection.all('PRAGMA foreign_key_list(evaluation_inputs)').some(row => row.from === 'assessment_result_id' && row.table === 'assessment_results'));
  assert.deepEqual(connection.all('SELECT version FROM application_migrations ORDER BY version').map(row => row.version), [1, workbenchSchemaVersion]);
  const target = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId, sourceVersionIds });
  connection.run('INSERT INTO evaluation_inputs(evaluation_id, role_code, assessment_result_id) VALUES (?, ?, ?)',
    [target.evaluationId, 'assessment-result', resultsBefore[0].id]);
  assert.throws(() => connection.run('INSERT INTO evaluation_inputs(evaluation_id, role_code, assessment_result_id) VALUES (?, ?, ?)',
    [target.evaluationId, 'assessment-result', 999999]), /FOREIGN KEY/);
  assert.throws(() => connection.run('INSERT INTO evaluation_inputs(evaluation_id, role_code, assessment_result_id, source_version_id) VALUES (?, ?, ?, ?)',
    [target.evaluationId, 'assessment-result', resultsBefore[1].id, sourceVersionIds[0]]), /CHECK/);
});

test('application upgrade rolls back failures and rejects identity or schema drift', context => {
  const connection = applicationFixture(context, undefined, 1);
  const request = { databaseGuid: '12345678-1234-4234-8234-123456789abc', expectedSchemaVersion: 1 };
  const before = connection.all('SELECT * FROM sqlite_schema ORDER BY name');
  assert.throws(() => migrateWorkbenchApplication(connection, { ...request, databaseGuid: 'other-database' }), /mismatched database/);
  const failing = { ...connection, exec(sql) {
    if (sql.includes('INSERT INTO evaluation_inputs')) throw new Error('Synthetic input migration failure');
    return connection.exec(sql);
  } };
  Object.defineProperty(failing, 'isTransaction', { get: () => connection.isTransaction });
  assert.throws(() => migrateWorkbenchApplication(failing, request), /Synthetic input migration failure/);
  assert.deepEqual(connection.all('SELECT * FROM sqlite_schema ORDER BY name'), before);
  assert.equal(connection.isTransaction, false);
  connection.exec('DROP INDEX evaluation_reuse');
  assert.throws(() => migrateWorkbenchApplication(connection, request), /altered source schema/);
});

test('application migration rolls back all domains on a component failure and refuses enclosing transactions', context => {
  const connection = openWorkbenchSqlite({ mode: 'memory' });
  context.after(() => connection.close());
  const failing = { ...connection, exec(sql) {
    if (sql.includes('CREATE TABLE protected_snapshots')) throw new Error('Synthetic migration failure');
    return connection.exec(sql);
  } };
  Object.defineProperty(failing, 'isTransaction', { get: () => connection.isTransaction });
  assert.throws(() => migrateNewWorkbenchApplication(failing), /Synthetic migration failure/);
  assert.deepEqual(connection.all("SELECT name FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%'"), []);
  assert.equal(connection.isTransaction, false);
  connection.exec('BEGIN IMMEDIATE');
  assert.throws(() => migrateNewWorkbenchApplication(connection), /own writable transaction/);
  connection.exec('ROLLBACK');
  migrateNewWorkbenchApplication(connection);
  assert.equal(validateWorkbenchApplicationSchema(connection).valid, true);
});

test('application inspection detects missing guards, missing indexes, unsupported versions and independent FK violations', context => {
  const connection = applicationFixture(context);
  connection.exec('DROP INDEX evaluation_reuse; DROP TRIGGER application_application_migrations_UPDATE');
  connection.exec('UPDATE application_migrations SET version = 999');
  connection.exec("CREATE TABLE foreign_probe (owner_id INTEGER REFERENCES actors(id) DEFERRABLE INITIALLY DEFERRED) STRICT; BEGIN; INSERT INTO foreign_probe VALUES (999)");
  const inspected = validateWorkbenchApplicationSchema(connection);
  assert.equal(inspected.valid, false);
  assert.deepEqual(inspected.problems, ['schema-shape-mismatch', 'unsupported-schema-version', 'foreign-key-violations']);
  assert.equal(connection.isTransaction, true);
  connection.exec('ROLLBACK');
  assert.deepEqual(validateWorkbenchApplicationSchema(connection).problems, ['schema-shape-mismatch', 'unsupported-schema-version']);
});

test('proposal baseline cycles commit only with matching owners and remain immutable', context => {
  const connection = applicationFixture(context);
  connection.exec(`
    BEGIN IMMEDIATE;
    INSERT INTO changes VALUES (1, 1);
    INSERT INTO proposal_versions VALUES (1, 1, 1, NULL, NULL, 1);
    INSERT INTO change_revisions VALUES (1, 1, 1, 1, NULL, 1, 1, 1, '', 2, '2026-11-05T00:00:00.000Z');
    COMMIT;
  `);
  assert.throws(() => connection.exec('UPDATE proposal_versions SET baseline_revision_id = 999 WHERE id = 1'), /immutable/);
  assert.throws(() => connection.exec("INSERT INTO change_revisions VALUES (2, 1, 1, 2, 1, 3, NULL, 1, '', 2, '2026-11-05T00:00:00.000Z')"), /Protected/);
  assert.throws(() => connection.exec("INSERT INTO change_revisions VALUES (2, 1, 1, 2, 1, 1, 2, 1, '', 2, '2026-11-05T00:00:00.000Z')"), { errcode: 787 });
  connection.exec(`
    BEGIN IMMEDIATE;
    INSERT INTO changes VALUES (2, 2);
    INSERT INTO proposal_versions VALUES (2, 2, 1, NULL, NULL, 1);
    INSERT INTO change_revisions VALUES (2, 2, 2, 1, NULL, NULL, NULL, 1, '', 2, '2026-11-05T00:00:00.000Z');
  `);
  assert.throws(() => connection.exec('COMMIT'), { errcode: 787 });
  connection.exec('ROLLBACK');
  assert.equal(connection.get('SELECT count(*) AS count FROM changes').count, 1);
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
});

test('application scoring and membership guards reject cross-policy values and false bulk provenance', context => {
  const connection = applicationFixture(context);
  connection.exec(`
    INSERT INTO scoring_policies VALUES (1, 'synthetic', 1, 0), (2, 'other', 1, 0);
    INSERT INTO scoring_factors VALUES (1, 1, 'severity', 'Severity', 'Synthetic factor', 0, 5, 1, 'value');
    INSERT INTO scorecards VALUES (1, 1, 'Synthetic rationale'), (2, 2, 'Other policy');
    INSERT INTO scorecard_values VALUES (1, 1, 5);
    INSERT INTO priority_bands VALUES (1, 1, 'normal', 'Normal', 0, 5);
    INSERT INTO plans VALUES (1, 'Synthetic Plan', NULL), (2, 'Other Plan', NULL);
    INSERT INTO changes VALUES (1, NULL);
    INSERT INTO bulk_add_operations VALUES (1, 1, 2, '2026-11-05T00:00:00.000Z', 'Synthetic selection');
  `);
  assert.throws(() => connection.exec('INSERT INTO scorecard_values VALUES (2, 1, 5)'), /policy or factor bounds/);
  assert.throws(() => connection.exec('UPDATE scorecard_values SET value = 6'), /policy or factor bounds/);
  assert.throws(() => connection.exec("INSERT INTO priority_bands VALUES (2, 1, 'overlap', 'Overlap', 5, NULL)"), /overlap/);
  assert.throws(() => connection.exec("INSERT INTO plan_memberships VALUES (1, 1, 1, 1, 1, 2, '2026-11-05T00:00:00.000Z', NULL, NULL)"), /addition method/);
  assert.throws(() => connection.exec("INSERT INTO plan_memberships VALUES (1, 2, 1, 2, 1, 2, '2026-11-05T00:00:00.000Z', NULL, NULL)"), { errcode: 787 });
  connection.exec("INSERT INTO plan_memberships VALUES (1, 1, 1, 1, NULL, 2, '2026-11-05T00:00:00.000Z', NULL, NULL)");
  assert.throws(() => connection.exec("INSERT INTO plan_memberships VALUES (2, 1, 1, 2, 1, 2, '2026-11-05T00:00:00.000Z', NULL, NULL)"), /UNIQUE/);
});

test('workspace capacity reader follows the selected policy and rejects mismatched bindings or invalid selection', context => {
  const connection = applicationFixture(context);
  const binding = { databaseGuid: '12345678-1234-4234-8234-123456789abc', repositoryId: 1, branchRef: 'refs/heads/synthetic' };
  assert.deepEqual(readSelectedCapacityPolicy(connection, binding), {
    policyId: 1000, code: 'synthetic-selected-policy', revision: 1, estimatorCode: 'character-quarter-estimate-v1', estimatorVersion: '1',
    charactersPerToken: 4, safetyMarginPercent: 25, runtimeRequestTokenLimit: 110000, guidanceTokenBudget: 25000,
  });
  connection.exec("INSERT INTO capacity_policies VALUES (1001, 'synthetic-selected-policy', 2, 'character-quarter-estimate-v1', '1', 4, 25, 110000, 25000)");
  assert.equal(readSelectedCapacityPolicy(connection, binding).policyId, 1000);
  connection.exec('UPDATE team_profiles SET capacity_policy_id = 1001 WHERE id = 1');
  assert.equal(readSelectedCapacityPolicy(connection, binding).policyId, 1001);
  assert.throws(() => connection.exec('UPDATE team_profiles SET capacity_policy_id = NULL WHERE id = 1'), /NOT NULL/);
  assert.throws(() => connection.exec('UPDATE team_profiles SET capacity_policy_id = 9999 WHERE id = 1'), { errcode: 787 });
  assert.throws(() => readSelectedCapacityPolicy(connection, { ...binding, databaseGuid: '12345678-1234-4234-8234-123456789abd' }), /identity does not match/);
  assert.throws(() => readSelectedCapacityPolicy(connection, { ...binding, repositoryId: 2 }), /bound repository/);
  assert.throws(() => readSelectedCapacityPolicy(connection, { ...binding, repositoryId: 0 }), /positive safe integer/);
  assert.throws(() => readSelectedCapacityPolicy(connection, { ...binding, policyId: 1000 }), /Bound workspace request/);
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
});

test('capacity policy selection requires the bound branch but does not invalidate on unrelated commit observations', context => {
  const connection = applicationFixture(context);
  const binding = { databaseGuid: '12345678-1234-4234-8234-123456789abc', repositoryId: 1, branchRef: 'refs/heads/synthetic' };
  const original = readSelectedCapacityPolicy(connection, binding);
  assert.throws(() => readSelectedCapacityPolicy(connection, { ...binding, branchRef: 'refs/heads/another-branch' }), /bound branch/);
  for (const branchRef of ['', ' ', null, 1, 'refs/heads/synthetic\0']) {
    assert.throws(() => readSelectedCapacityPolicy(connection, { ...binding, branchRef }), /nonempty branch reference/);
  }
  assert.throws(() => readSelectedCapacityPolicy(connection, { databaseGuid: binding.databaseGuid, repositoryId: binding.repositoryId }), /Bound workspace request/);
  connection.exec("INSERT INTO repository_contexts VALUES (2, 1, 'refs/heads/synthetic', '2222222222222222222222222222222222222222', '2026-11-05T01:00:00.000Z')");
  assert.deepEqual(readSelectedCapacityPolicy(connection, binding), original);
  assert.equal(connection.get('SELECT origin_context_id FROM workspace_identity').origin_context_id, 1);
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
});

test('capacity configuration resolves category and file bindings without storing usage or guessing rule prefixes', context => {
  const connection = applicationFixture(context);
  const binding = { databaseGuid: '12345678-1234-4234-8234-123456789abc', repositoryId: 1, branchRef: 'refs/heads/synthetic' };
  assert.throws(() => readSelectedCapacityConfiguration(connection, binding), /no configured category allowances/);
  connection.exec(`
    INSERT INTO capacity_buckets VALUES (1, 1000, 'application', 'Implementation', 8000, 'surface-sum');
    INSERT INTO capacity_bucket_surfaces VALUES (1, 1);
    INSERT INTO capacity_buckets VALUES (2, 1000, 'repository', 'Repository guidance', 2000, 'surface-sum');
    INSERT INTO capacity_bucket_files VALUES (2, '.github/copilot-instructions.md');
    INSERT INTO capacity_buckets VALUES (3, 1000, 'skill', 'Review skill', 3000, 'surface-sum');
    INSERT INTO capacity_bucket_files VALUES (3, '.github/skills/code-review/SKILL.md');
  `);
  const configured = readSelectedCapacityConfiguration(connection, binding);
  assert.equal(configured.policy.policyId, 1000);
  assert.deepEqual(configured.buckets.map(bucket => ({ code: bucket.code, categoryCode: bucket.categoryCode, relativePath: bucket.relativePath })), [
    { code: 'application', categoryCode: 'implementation', relativePath: '.github/instructions/synthetic.instructions.md' },
    { code: 'repository', categoryCode: null, relativePath: '.github/copilot-instructions.md' },
    { code: 'skill', categoryCode: null, relativePath: '.github/skills/code-review/SKILL.md' },
  ]);
  assert.equal(connection.isTransaction, false);
  assert.equal(connection.get('SELECT count(*) AS count FROM guidance_surfaces').count, 1);
  assert.throws(() => connection.exec("INSERT INTO capacity_bucket_files VALUES (999, '.github/unknown.md')"), { errcode: 787 });
  connection.exec('BEGIN');
  assert.equal(readSelectedCapacityConfiguration(connection, binding).buckets.length, 3);
  assert.equal(connection.isTransaction, true);
  connection.exec('ROLLBACK');
});

test('capacity configuration rejects missing, overlapping or unsafe mappings and preserves its caller transaction', context => {
  const connection = applicationFixture(context);
  const binding = { databaseGuid: '12345678-1234-4234-8234-123456789abc', repositoryId: 1, branchRef: 'refs/heads/synthetic' };
  connection.exec("INSERT INTO capacity_buckets VALUES (1, 1000, 'application', 'Implementation', 8000, 'surface-sum')");
  assert.throws(() => readSelectedCapacityConfiguration(connection, binding), /exactly one category/);
  assert.equal(connection.isTransaction, false);
  connection.exec("INSERT INTO capacity_bucket_files VALUES (1, '.github/copilot-instructions.md')");
  assert.throws(() => readSelectedCapacityConfiguration(connection, binding), /every registered guidance category/);
  connection.exec('DELETE FROM capacity_bucket_files; INSERT INTO capacity_bucket_surfaces VALUES (1, 1)');
  connection.exec("INSERT INTO capacity_bucket_files VALUES (1, '.github/copilot-instructions.md')");
  assert.throws(() => readSelectedCapacityConfiguration(connection, binding), /exactly one category/);
  connection.exec('DELETE FROM capacity_bucket_files');
  connection.exec("INSERT INTO capacity_buckets VALUES (2, 1000, 'other', 'Other', 2000, 'surface-sum'); INSERT INTO capacity_bucket_surfaces VALUES (2, 1)");
  assert.throws(() => readSelectedCapacityConfiguration(connection, binding), /more than once/);
  connection.exec('DELETE FROM capacity_bucket_surfaces WHERE bucket_id = 2');
  for (const path of ['/absolute.md', '../outside.md', 'folder//file.md', 'folder/./file.md', 'C:/outside.md', 'folder\\file.md']) {
    connection.run('INSERT INTO capacity_bucket_files VALUES (2, ?)', [path]);
    assert.throws(() => readSelectedCapacityConfiguration(connection, binding), /Hosted-root-relative/);
    connection.exec('DELETE FROM capacity_bucket_files WHERE bucket_id = 2');
  }
  connection.exec("INSERT INTO capacity_bucket_files VALUES (2, '.GITHUB/INSTRUCTIONS/SYNTHETIC.INSTRUCTIONS.MD')");
  assert.throws(() => readSelectedCapacityConfiguration(connection, binding), /more than once/);
  connection.exec('BEGIN');
  assert.throws(() => readSelectedCapacityConfiguration(connection, binding), /more than once/);
  assert.equal(connection.isTransaction, true);
  connection.exec('ROLLBACK');
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
});

test('capacity policy reserves one guidance budget inside the runtime limit and divides it into category allowances', context => {
  const connection = applicationFixture(context);
  const { tokenPolicy } = JSON.parse(readFileSync(new URL('../../config/adoption.json', import.meta.url), 'utf8'));
  connection.run(`INSERT INTO capacity_policies(id, code, revision, estimator_code, estimator_version, characters_per_token,
    safety_margin_percent, runtime_request_token_limit, guidance_token_budget) VALUES (1, 'synthetic-hosted', 1, ?, '1', 4, ?, ?, 25000)`,
  [tokenPolicy.estimator, tokenPolicy.safetyMarginPercent, tokenPolicy.maximumGuidanceTokens]);
  for (const area of tokenPolicy.areas) connection.run(`INSERT INTO capacity_buckets(policy_id, code, label, guarded_limit, accounting_mode)
    VALUES (1, ?, ?, ?, 'surface-sum')`, [area.name, area.name, area.budgetTokens]);
  const policy = connection.get('SELECT * FROM capacity_policies WHERE id = 1');
  assert.equal(policy.runtime_request_token_limit, 110000);
  assert.equal(policy.guidance_token_budget, 25000);
  assert.equal(policy.characters_per_token, 4);
  assert.equal(policy.safety_margin_percent, 25);
  assert.equal(connection.get('SELECT sum(guarded_limit) AS total FROM capacity_buckets WHERE policy_id = 1').total, policy.guidance_token_budget);
  assert.deepEqual(connection.all('SELECT code, guarded_limit FROM capacity_buckets ORDER BY id').map(row => ({ ...row })), [
    { code: 'repository', guarded_limit: 2000 }, { code: 'go', guarded_limit: 8000 }, { code: 'test', guarded_limit: 4000 },
    { code: 'documentation', guarded_limit: 8000 }, { code: 'skill', guarded_limit: 3000 },
  ]);
  const columns = connection.all("SELECT name FROM pragma_table_info('capacity_policies')").map(column => column.name);
  assert.ok(columns.every(name => !/usage|remaining|delta|count/.test(name)));
  assert.throws(() => connection.exec("INSERT INTO capacity_buckets(policy_id, code, label, guarded_limit, accounting_mode) VALUES (1, 'extra', 'Extra budget', 1, 'surface-sum')"), /Category allowances/);
  assert.throws(() => connection.exec("UPDATE capacity_buckets SET guarded_limit = 9000 WHERE code = 'go'"), /Category allowances/);
  assert.throws(() => connection.exec('UPDATE capacity_policies SET guidance_token_budget = 24999 WHERE id = 1'), /category allowances/);
  assert.throws(() => connection.exec('UPDATE capacity_policies SET guidance_token_budget = 110001 WHERE id = 1'), /CHECK/);
  assert.throws(() => connection.exec('UPDATE capacity_policies SET runtime_request_token_limit = 24000 WHERE id = 1'), /CHECK/);
  assert.throws(() => connection.exec("INSERT INTO capacity_buckets(policy_id, code, label, guarded_limit, accounting_mode) VALUES (999, 'unknown', 'Unknown policy', 1, 'surface-sum')"), { errcode: 787 });
  connection.exec("INSERT INTO capacity_policies VALUES (2, 'another-policy', 1, 'character-quarter-estimate-v1', '1', 4, 25, 110000, 25000)");
  connection.exec("INSERT INTO capacity_buckets(policy_id, code, label, guarded_limit, accounting_mode) VALUES (2, 'allocated', 'Allocated', 25000, 'surface-sum')");
  assert.throws(() => connection.exec("UPDATE capacity_buckets SET policy_id = 2 WHERE policy_id = 1 AND code = 'skill'"), /Category allowances/);
  const overBudgetText = 'Synthetic over-budget wording. '.repeat(20000);
  connection.run('INSERT INTO wording_versions VALUES (2, ?, ?, ?)', [overBudgetText, createHash('sha256').update(overBudgetText).digest('hex'), '2026-11-05T00:00:00.000Z']);
  assert.ok(Math.ceil(Math.ceil(overBudgetText.length / policy.characters_per_token) * (1 + policy.safety_margin_percent / 100)) > policy.runtime_request_token_limit);
  assert.equal(connection.get('SELECT text FROM wording_versions WHERE id = 2').text, overBudgetText);
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
});

test('native evaluations require model, prompt and actual request time without snapshot-import exceptions', context => {
  const connection = applicationFixture(context);
  const hash = 'a'.repeat(64);
  assert.throws(() => connection.exec("INSERT INTO llm_models(provider_code, model_code) VALUES ('synthetic', NULL)"), /NOT NULL/);
  const assignments = configureProfileLlms(connection, 1, { models: [{ key: 'main', providerCode: 'synthetic', modelCode: 'fixture-model' }],
    assignments: [{ taskCode: 'assessment', modelKey: 'main', adapterCode: 'synthetic', reasoningEffort: 'low' }] });
  assert.throws(() => connection.run(`INSERT INTO evaluator_profiles(code, revision, task_code, llm_assignment_id,
    prompt_sha256, behavior_sha256, result_contract_sha256) VALUES ('invalid-llm', 1, 'assessment', NULL, NULL, ?, ?)`, [hash, hash]), /NOT NULL/);
  const profileId = registerEvaluatorProfile(connection, { code: 'native-llm', taskCode: 'assessment', llmAssignmentId: assignments[0].assignmentId,
    promptSha256: hash, behaviorSha256: hash, resultContractSha256: hash });
  assert.throws(() => connection.run(`INSERT INTO evaluations(evaluator_profile_id, input_fingerprint, requested_at, completed_at, outcome)
    VALUES (?, ?, NULL, '2026-11-01T00:00:00.000Z', 'complete')`, [profileId, hash]), /NOT NULL/);
  connection.run(`INSERT INTO evaluations(evaluator_profile_id, input_fingerprint, requested_at, completed_at, outcome)
    VALUES (?, ?, '2026-11-05T00:00:00.000Z', NULL, 'running')`, [profileId, hash]);
  assert.throws(() => connection.exec("UPDATE evaluations SET outcome = 'complete' WHERE id = 1"), /CHECK/);
  assert.equal(connection.get("SELECT requested_at FROM evaluations WHERE id = 1").requested_at, '2026-11-05T00:00:00.000Z');
});

test('master profiles map arbitrary LLM counts to explicit tasks without global two-slot routing', context => {
  const connection = applicationFixture(context);
  const binding = { databaseGuid: '12345678-1234-4234-8234-123456789abc', repositoryId: 1, branchRef: 'refs/heads/synthetic' };
  connection.exec(`INSERT INTO capacity_buckets VALUES (1, 1000, 'implementation', 'Implementation', 8000, 'surface-sum');
    INSERT INTO capacity_bucket_surfaces VALUES (1, 1);`);
  for (const count of [1, 2, 10]) {
    const models = Array.from({ length: count }, (_, index) => ({ key: `model-${index}`, providerCode: 'synthetic', modelCode: `fixture-model-${index}` }));
    const assignments = models.map(model => ({ taskCode: `task-${model.key}`, modelKey: model.key, adapterCode: 'synthetic', reasoningEffort: 'low' }));
    configureProfileLlms(connection, 1, { models, assignments });
    const current = readWorkspaceLlmAssignments(connection, binding);
    assert.equal(current.length, count);
    assert.equal(new Set(current.map(assignment => assignment.modelId)).size, count);
    assert.equal(connection.isTransaction, false);
    assert.throws(() => configureProfileLlms(connection, 1, { models, assignments: [...assignments, assignments[0]] }), /exactly one/);
    assert.deepEqual(readWorkspaceLlmAssignments(connection, binding), current);
  }
  const before = readWorkspaceLlmAssignments(connection, binding);
  connection.exec("INSERT INTO team_profiles VALUES (2, 'other', 'Other master profile', 1000)");
  const other = configureProfileLlms(connection, 2, { models: [{ key: 'other', providerCode: 'synthetic', modelCode: 'other-model' }],
    assignments: [{ taskCode: before[0].taskCode, modelKey: 'other', adapterCode: 'synthetic', reasoningEffort: 'high' }] });
  assert.throws(() => connection.run('UPDATE profile_llm_heads SET assignment_id = ? WHERE team_profile_id = 1 AND task_code = ?', [other[0].assignmentId, before[0].taskCode]), /FOREIGN KEY/);
  assert.deepEqual(readWorkspaceLlmAssignments(connection, binding), before);
  assert.throws(() => connection.run("UPDATE llm_models SET model_code = 'changed' WHERE id = ?", [before[0].modelId]), /immutable/);
  assert.throws(() => connection.run("UPDATE profile_llm_assignments SET reasoning_effort = 'high' WHERE id = ?", [before[0].assignmentId]), /immutable/);
});

test('native evaluator identity is committed before inference and changes explicitly with prompt configuration', context => {
  const connection = applicationFixture(context);
  const assignments = configureProfileLlms(connection, 1, { models: [{ key: 'main', providerCode: 'synthetic', modelCode: 'fixture-model' }],
    assignments: [{ taskCode: 'assessment', modelKey: 'main', adapterCode: 'synthetic', reasoningEffort: 'low' }] });
  const profile = { code: 'native-assessment-v4', taskCode: 'assessment', llmAssignmentId: assignments[0].assignmentId,
    promptSha256: 'a'.repeat(64), behaviorSha256: 'b'.repeat(64), resultContractSha256: 'c'.repeat(64) };
  const profileId = registerEvaluatorProfile(connection, profile);
  assert.equal(connection.isTransaction, false);
  assert.equal(registerEvaluatorProfile(connection, profile), profileId);
  const revised = registerEvaluatorProfile(connection, { ...profile, promptSha256: 'd'.repeat(64) });
  assert.notEqual(revised, profileId);
  assert.equal(connection.get('SELECT revision FROM evaluator_profiles WHERE id = ?', [revised]).revision, 2);
  assert.throws(() => registerEvaluatorProfile(connection, { ...profile, llmAssignmentId: null }), /positive safe integer/);
  assert.equal(connection.get('SELECT count(*) AS count FROM evaluator_profiles').count, 2);
});

function nativeAssessmentFixture(context, { sourceCount = 1, fileBacked = false, assessmentCardinality = 'exactly-one',
  content = 'Validate the captured source.', schemaVersion = workbenchSchemaVersion, taskCodes = ['assessment'] } = {}) {
  const directory = fileBacked ? mkdtempSync(join(tmpdir(), 'workbench-concurrent-assessment-')) : null;
  const databasePath = directory ? join(directory, 'candidate.sqlite') : undefined;
  const connection = applicationFixture(context, databasePath, schemaVersion);
  if (directory) context.after(() => rmSync(directory, { recursive: true, force: true }));
  const binding = { databaseGuid: '12345678-1234-4234-8234-123456789abc', repositoryId: 1, branchRef: 'refs/heads/synthetic' };
  connection.exec(`
    INSERT INTO capacity_buckets VALUES (1, 1000, 'implementation', 'Implementation', 8000, 'surface-sum');
    INSERT INTO capacity_bucket_surfaces VALUES (1, 1);
    INSERT INTO guidance_surface_content VALUES (1, 'Implementation behavior', 'Implementation', '', '');
    INSERT INTO scoring_policies VALUES (1, 'synthetic-selection', 1, 0);
    INSERT INTO scoring_factors VALUES (1, 1, 'severity', 'Severity', 'Severity', 0, 5, 1, 'value');
  `);
  const protectedBytes = Buffer.from('');
  const protectedSnapshot = ingestProtectedCapture(connection, { repositoryContextId: 1, parserContractSha256: 'b'.repeat(64),
    requiredFiles: ['fixtures/protected.rules.md'], files: [{ relativePath: 'fixtures/protected.rules.md', contentBytes: protectedBytes,
      contentSha256: createHash('sha256').update(protectedBytes).digest('hex') }], blocks: [] });
  connection.run('UPDATE workspace_identity SET current_protected_snapshot_id = ?', [protectedSnapshot.snapshotId]);
  const definitionVersionId = registerSourceDefinition(connection, { lane: { code: 'test', label: 'Test', displayOrder: 0 }, code: 'synthetic-source',
    label: 'Synthetic source', parserId: 'maintainer-proposals-v4', parserContractSha256: 'a'.repeat(64), definitionSha256: 'b'.repeat(64),
    repositoryId: 1, rootKind: 'repository', location: 'fixtures', configuredRef: null, contentFormat: 'utf8', files: ['**/*.rules.md'], exclude: [],
    assessmentBatchSize: 2, assessmentCardinality });
  const collection = ingestSourceCollection(connection, { definitionVersionId, expectedCollectionId: null, repositoryContextId: 1, collectorVersion: 1,
    revision: { kind: 'repository-worktree', resolvedCommit: '1'.repeat(40), worktreeDirty: false, worktreeSha256: 'c'.repeat(64) }, complete: true,
    records: Array.from({ length: sourceCount }, (_, index) => {
      const sourceContent = index === 0 ? content : `${content} Source ${index + 1}.`;
      return { sourceId: `SOURCE-${String(index + 1).padStart(3, '0')}`, title: 'Captured source', content: sourceContent,
        contentSha256: createHash('sha256').update(sourceContent).digest('hex'), location: `fixtures/source-${index + 1}.rules.md`,
        presence: 'present', sourceLifecycle: 'active' };
    }) });
  const sourceVersionIds = collection.records.map(record => record.sourceVersionId);
  const assignments = configureProfileLlms(connection, 1, { models: [{ key: 'main', providerCode: 'synthetic', modelCode: 'fixture-model' }],
    assignments: taskCodes.map(taskCode => ({ taskCode, modelKey: 'main', adapterCode: 'synthetic', reasoningEffort: 'low' })) });
  const run = beginAnalysisRun(connection, { binding, actorId: 1, scoringPolicyId: 1, force: false, llmAssignmentIds: assignments.map(assignment => assignment.assignmentId) });
  const profileId = registerEvaluatorProfile(connection, { code: 'assessment-v4', taskCode: 'assessment', llmAssignmentId: assignments[0].assignmentId,
    promptSha256: 'a'.repeat(64), behaviorSha256: 'b'.repeat(64), resultContractSha256: 'c'.repeat(64) });
  return { connection, databasePath, binding, definitionVersionId, collection, content, assignments, run, profileId,
    sourceVersionIds, sourceVersionId: sourceVersionIds[0] };
}

const assessmentEvaluatorInput = Object.freeze({ prompt: 'Synthetic assessment instructions.', schema: '{"type":"object"}' });

function nativeAssessmentResult(recorded) {
  return { schemaVersion: 4, stage: 'assessment', sources: JSON.parse(recorded.serializedInput).sources.map(source => ({
    sourceVersionId: source.sourceVersionId,
    assessments: [{ localResultKey: 'meaning-1', title: source.title, sourceMeaning: source.content, impactDescription: 'Prevents invalid inputs',
      hostedApplicable: true, applicabilityRationale: 'Reviewable from changed code', selectionFactors: { severity: 3 }, selectionRationale: 'Direct evidence',
      confidence: { level: 'high', rationale: 'Explicit source', uncertainties: ['Synthetic uncertainty'] }, categories: ['implementation'],
      existingCoverage: { score: 0, rationale: 'No accepted coverage' } }],
  })) };
}

test('three concurrent evaluator calls commit out of order without mixing request or source ownership', async context => {
  const { connection, databasePath, binding, run, profileId, sourceVersionIds } = nativeAssessmentFixture(context, { sourceCount: 6, fileBacked: true });
  const observer = openWorkbenchSqlite({ mode: 'read-only', databasePath });
  const releases = Array.from({ length: 3 }, () => Promise.withResolvers());
  const completed = [];
  let activeEvaluators = 0;
  let maximumActiveEvaluators = 0;
  const recordedRequests = [];
  const workers = releases.map(async (release, index) => {
    const recorded = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId,
      sourceVersionIds: sourceVersionIds.slice(index * 2, index * 2 + 2) });
    recordedRequests.push(recorded);
    assert.equal(connection.isTransaction, false);
    assert.equal(observer.get('SELECT outcome FROM evaluations WHERE id = ?', [recorded.evaluationId]).outcome, 'running');
    activeEvaluators += 1;
    maximumActiveEvaluators = Math.max(maximumActiveEvaluators, activeEvaluators);
    await release.promise;
    activeEvaluators -= 1;
    const result = nativeAssessmentResult(recorded);
    const committed = commitAssessmentResults(connection, { binding, runId: run.runId, evaluationId: recorded.evaluationId,
      inputFingerprint: recorded.inputFingerprint, result });
    assert.equal(committed.assessmentCount, 2);
    assert.equal(connection.isTransaction, false);
    assert.equal(observer.get('SELECT count(*) AS count FROM assessment_results WHERE evaluation_id = ?', [recorded.evaluationId]).count, 2);
    completed.push(index + 1);
  });
  try {
    assert.equal(activeEvaluators, 3);
    assert.equal(maximumActiveEvaluators, 3);
    assert.equal(observer.get('SELECT count(*) AS count FROM evaluations WHERE outcome = ?', ['running']).count, 3);
    for (const index of [2, 0, 1]) {
      releases[index].resolve();
      await workers[index];
    }
    assert.deepEqual(completed, [3, 1, 2]);
    assert.equal(observer.get('SELECT count(*) AS count FROM assessment_results').count, 6);
    for (const [index, recorded] of recordedRequests.entries()) {
      const ownedSources = observer.all('SELECT source_version_id FROM assessment_results WHERE evaluation_id = ? ORDER BY source_version_id', [recorded.evaluationId]);
      assert.deepEqual(ownedSources.map(row => row.source_version_id), sourceVersionIds.slice(index * 2, index * 2 + 2));
      assert.equal(observer.get('SELECT run_id FROM run_evaluations WHERE evaluation_id = ?', [recorded.evaluationId]).run_id, run.runId);
    }
    assert.deepEqual(observer.all('PRAGMA foreign_key_check'), []);
    assert.equal(observer.get('PRAGMA quick_check').quick_check, 'ok');
    assert.equal(observer.get('SELECT count(*) AS count FROM workspace_analysis_head').count, 0);
  } finally {
    releases.forEach(release => release.resolve());
    await Promise.allSettled(workers);
    observer.close();
  }
});

test('native reconciliation requests pin completed assessment evidence before inference', context => {
  const { connection, binding, run, profileId, assignments, sourceVersionIds } = nativeAssessmentFixture(context,
    { sourceCount: 2, taskCodes: ['assessment', 'reconciliation'] });
  const reconciliationProfileId = registerEvaluatorProfile(connection, { code: 'native-reconciliation', taskCode: 'reconciliation',
    llmAssignmentId: assignments[1].assignmentId, promptSha256: 'd'.repeat(64), behaviorSha256: 'e'.repeat(64), resultContractSha256: 'f'.repeat(64) });
  const request = { binding, runId: run.runId, profileId: reconciliationProfileId, sourceVersionIds, assessmentResultIds: [1, 2], reconciliationPhase: 'routing' };
  assert.throws(() => prepareEvaluationInput(connection, request), /one pinned source-assessment identity/);
  const sourceRequest = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId, sourceVersionIds });
  assert.throws(() => prepareEvaluationInput(connection, request), /complete committed source assessment coverage/);
  commitAssessmentResults(connection, { binding, runId: run.runId, evaluationId: sourceRequest.evaluationId,
    inputFingerprint: sourceRequest.inputFingerprint, result: nativeAssessmentResult(sourceRequest) });
  const resultIds = connection.all('SELECT id FROM assessment_results ORDER BY id').map(row => row.id);
  const recorded = recordEvaluationRequest(connection, { ...request, assessmentResultIds: resultIds });
  const input = JSON.parse(recorded.serializedInput);
  assert.equal(input.stage, 'reconciliation');
  assert.equal(input.phase, 'routing');
  assert.deepEqual(input.assessments.map(result => result.assessmentResultId), resultIds);
  assert.deepEqual(input.assessments[0].selectionFactors, { severity: 3 });
  assert.equal(input.assessments[0].confidence.level, 'high');
  assert.deepEqual(connection.all("SELECT assessment_result_id AS id FROM evaluation_inputs WHERE evaluation_id = ? AND role_code = 'assessment-result' ORDER BY id",
    [recorded.evaluationId]).map(row => row.id), resultIds);
  assert.equal(connection.isTransaction, false);
  assert.throws(() => prepareEvaluationInput(connection, { ...request, assessmentResultIds: [999999] }), /pinned run and source inputs/);
  assert.throws(() => prepareEvaluationInput(connection, { ...request, sourceVersionIds: sourceVersionIds.slice(0, 1), assessmentResultIds: resultIds }), /pinned run and source inputs/);
});

test('native reconciliation components preserve typed membership and reject foreign evaluation inputs', context => {
  const { connection, binding, run, profileId, assignments, sourceVersionIds } = nativeAssessmentFixture(context,
    { sourceCount: 2, taskCodes: ['assessment', 'reconciliation'] });
  const sourceRequest = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId, sourceVersionIds });
  commitAssessmentResults(connection, { binding, runId: run.runId, evaluationId: sourceRequest.evaluationId,
    inputFingerprint: sourceRequest.inputFingerprint, result: nativeAssessmentResult(sourceRequest) });
  const resultIds = connection.all('SELECT id FROM assessment_results ORDER BY id').map(row => row.id);
  const reconciliationProfileId = registerEvaluatorProfile(connection, { code: 'native-reconciliation', taskCode: 'reconciliation',
    llmAssignmentId: assignments[1].assignmentId, promptSha256: 'd'.repeat(64), behaviorSha256: 'e'.repeat(64), resultContractSha256: 'f'.repeat(64) });
  const recorded = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId: reconciliationProfileId,
    sourceVersionIds: sourceVersionIds.slice(0, 1), assessmentResultIds: resultIds.slice(0, 1), reconciliationPhase: 'routing' });
  const componentId = Number(connection.run('INSERT INTO reconciliation_components(evaluation_id, phase_code, ordinal, semantic_summary) VALUES (?, ?, ?, ?)',
    [recorded.evaluationId, 'routing', 0, 'Synthetic input validation component']).lastInsertRowid);
  connection.run('INSERT INTO reconciliation_component_members VALUES (?, ?)', [componentId, resultIds[0]]);
  assert.deepEqual(connection.all('SELECT * FROM reconciliation_component_members').map(row => [row.component_id, row.assessment_result_id]), [[componentId, resultIds[0]]]);
  assert.throws(() => connection.run('INSERT INTO reconciliation_component_members VALUES (?, ?)', [componentId, resultIds[1]]), /exact evaluation inputs/);
  assert.throws(() => connection.run('INSERT INTO reconciliation_component_members VALUES (?, ?)', [componentId, resultIds[0]]), /UNIQUE/);
  assert.throws(() => connection.run('UPDATE reconciliation_components SET semantic_summary = ? WHERE id = ?', ['Changed', componentId]), /immutable/);
  assert.throws(() => connection.run('DELETE FROM reconciliation_component_members WHERE component_id = ?', [componentId]), /immutable/);
  assert.throws(() => connection.run('INSERT INTO reconciliation_components(evaluation_id, phase_code, ordinal, semantic_summary) VALUES (?, ?, ?, ?)',
    [sourceRequest.evaluationId, 'routing', 1, 'Invalid ownership']), /active reconciliation evaluation/);
  assert.ok(connection.all('PRAGMA foreign_key_list(evaluation_inputs)').some(row => row.from === 'reconciliation_component_id' && row.table === 'reconciliation_components'));
  assert.equal(validateWorkbenchApplicationSchema(connection).valid, true);
});

test('native reconciliation component commits require exact complete coverage and retain atomic results', context => {
  const { connection, binding, run, profileId, assignments, sourceVersionIds } = nativeAssessmentFixture(context,
    { sourceCount: 2, taskCodes: ['assessment', 'reconciliation', 'adjudication'] });
  connection.exec("INSERT INTO action_definitions VALUES (2, 'add', 'Add'); INSERT INTO guidance_sections VALUES (1, 0, 'Validation'); INSERT INTO source_provenance_codes VALUES ('synthetic', 'Synthetic evidence')");
  const sourceRequest = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId, sourceVersionIds });
  commitAssessmentResults(connection, { binding, runId: run.runId, evaluationId: sourceRequest.evaluationId,
    inputFingerprint: sourceRequest.inputFingerprint, result: nativeAssessmentResult(sourceRequest) });
  const resultIds = connection.all('SELECT id FROM assessment_results ORDER BY id').map(row => row.id);
  const reconciliationProfileId = registerEvaluatorProfile(connection, { code: 'native-reconciliation', taskCode: 'reconciliation',
    llmAssignmentId: assignments[1].assignmentId, promptSha256: 'd'.repeat(64), behaviorSha256: 'e'.repeat(64), resultContractSha256: 'f'.repeat(64) });
  const recorded = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId: reconciliationProfileId,
    sourceVersionIds, assessmentResultIds: resultIds, reconciliationPhase: 'routing' });
  const result = { schemaVersion: 4, stage: 'reconciliation', phase: 'routing',
    components: [{ assessmentResultIds: resultIds, semanticSummary: 'Validate captured input before use.' }] };
  const request = { binding, runId: run.runId, evaluationId: recorded.evaluationId, inputFingerprint: recorded.inputFingerprint, result };
  assert.throws(() => commitReconciliationComponents(connection, { ...request, result: { ...result, phase: 'consolidation' } }), /changed phase/);
  assert.throws(() => commitReconciliationComponents(connection, { ...request, result: { ...result,
    components: [{ ...result.components[0], assessmentResultIds: resultIds.slice(0, 1) }] } }), /every supplied assessment/);
  assert.throws(() => commitReconciliationComponents(connection, { ...request, result: { ...result,
    components: [{ ...result.components[0], assessmentResultIds: [resultIds[0], resultIds[0]] }] } }), /foreign or repeated/);
  assert.equal(connection.get('SELECT count(*) AS count FROM reconciliation_components').count, 0);
  let memberWrites = 0;
  const failing = { ...connection, run(sql, parameters) {
    if (sql.startsWith('INSERT INTO reconciliation_component_members') && ++memberWrites === 2) throw new Error('Synthetic component write failure');
    return connection.run(sql, parameters);
  } };
  Object.defineProperty(failing, 'isTransaction', { get: () => connection.isTransaction });
  assert.throws(() => commitReconciliationComponents(failing, request), /Synthetic component write failure/);
  assert.equal(connection.get('SELECT count(*) AS count FROM reconciliation_components').count, 0);
  assert.equal(connection.get('SELECT outcome FROM evaluations WHERE id = ?', [recorded.evaluationId]).outcome, 'running');
  const committed = commitReconciliationComponents(connection, request);
  assert.equal(committed.outcome, 'complete');
  assert.equal(committed.componentIds.length, 1);
  assert.equal(connection.get('SELECT count(*) AS count FROM reconciliation_component_members').count, 2);
  assert.equal(connection.isTransaction, false);
  assert.throws(() => commitReconciliationComponents(connection, request), /running request identity/);
  assert.throws(() => connection.run('INSERT INTO reconciliation_component_members VALUES (?, ?)', [committed.componentIds[0], resultIds[0]]), /exact evaluation inputs/);
  const downstreamRequest = { binding, runId: run.runId, profileId: reconciliationProfileId, sourceVersionIds,
    assessmentResultIds: resultIds, reconciliationPhase: 'consolidation', componentIds: committed.componentIds };
  const downstream = recordEvaluationRequest(connection, downstreamRequest);
  const downstreamInput = JSON.parse(downstream.serializedInput);
  assert.deepEqual(downstreamInput.components[0].assessmentResultIds, resultIds);
  assert.equal(downstreamInput.components[0].evaluationId, recorded.evaluationId);
  assert.equal(Object.hasOwn(downstreamInput.sources[0], 'content'), false);
  assert.equal(Object.hasOwn(downstreamInput.assessments[0], 'sourceMeaning'), false);
  assert.deepEqual(connection.all("SELECT reconciliation_component_id AS id FROM evaluation_inputs WHERE evaluation_id = ? AND role_code = 'component' ORDER BY id",
    [downstream.evaluationId]).map(row => row.id), committed.componentIds);
  assert.throws(() => prepareEvaluationInput(connection, { ...downstreamRequest, componentIds: [999999] }), /pinned completed reconciliation phase/);
  assert.throws(() => prepareEvaluationInput(connection, { ...downstreamRequest, assessmentResultIds: resultIds.slice(0, 1) }), /foreign, or overlapping/);
  assert.throws(() => prepareEvaluationInput(connection, { ...downstreamRequest, reconciliationPhase: 'synthesis' }), /pinned completed reconciliation phase/);
  assert.throws(() => commitReconciliationComponents(connection, { ...request, evaluationId: downstream.evaluationId,
    inputFingerprint: downstream.inputFingerprint, result: { ...result, phase: 'consolidation',
      components: resultIds.map(id => ({ assessmentResultIds: [id], semanticSummary: 'Improperly split component' })) } }), /cannot split/);
  const consolidated = commitReconciliationComponents(connection, { ...request, evaluationId: downstream.evaluationId,
    inputFingerprint: downstream.inputFingerprint, result: { ...result, phase: 'consolidation' } });
  const synthesisInput = prepareEvaluationInput(connection, { ...downstreamRequest, reconciliationPhase: 'synthesis', componentIds: consolidated.componentIds });
  assert.equal(JSON.parse(synthesisInput.serializedInput).components[0].phase, 'consolidation');
  assert.equal(JSON.parse(synthesisInput.serializedInput).sources[0].content, 'Validate the captured source.');
  const synthesis = recordEvaluationRequest(connection, { ...downstreamRequest, reconciliationPhase: 'synthesis', componentIds: consolidated.componentIds });
  const synthesisResult = { schemaVersion: 4, stage: 'reconciliation', phase: 'synthesis', groups: [{
    title: 'Captured input validation', semanticSummary: 'Validate inputs before use', synthesisRationale: 'Both inputs express validation',
    wording: 'Validate captured inputs before use.', selectionFactors: { severity: 4 }, selectionRationale: 'Prevents invalid processing', reviewState: 'recommended', needsReview: false,
    members: resultIds.map(assessmentResultId => ({ assessmentResultId, role: 'primary', coverageRationale: 'Preserves the validation requirement' })),
    operations: [{ role: 'primary', action: 'add', targetRuleVersionId: null, surfaceCode: 'implementation', sectionHeading: 'Validation',
      rationale: 'No existing managed coverage', relationship: null, provenanceCodes: ['synthetic'], evidenceCodes: [], applicabilityCodes: [] }],
  }], dispositions: resultIds.map(assessmentResultId => ({ assessmentResultId, code: 'grouped', rationale: 'Included in final validation wording' })) };
  const synthesisRequest = { binding, runId: run.runId, evaluationId: synthesis.evaluationId, inputFingerprint: synthesis.inputFingerprint, result: synthesisResult };
  assert.throws(() => commitSynthesisResults(connection, { ...synthesisRequest, result: { ...synthesisResult, dispositions: synthesisResult.dispositions.slice(0, 1) } }), /every supplied assessment disposition/);
  assert.equal(connection.get('SELECT count(*) AS count FROM group_versions').count, 0);
  const splitResult = { ...synthesisResult, groups: resultIds.map((id, index) => ({ ...synthesisResult.groups[0],
    title: `Captured validation ${index + 1}`, members: [synthesisResult.groups[0].members[index]],
    wording: index === 0 ? 'Validate captured inputs before use.' : 'Check captured inputs before processing.' })) };
  const final = commitSynthesisResults(connection, { ...synthesisRequest, result: splitResult });
  assert.equal(final.groupVersionIds.length, 2);
  assert.equal(connection.get('SELECT count(*) AS count FROM group_members').count, 2);
  assert.equal(connection.get('SELECT count(*) AS count FROM recommended_changes').count, 2);
  assert.equal(connection.get('SELECT count(*) AS count FROM changes').count, 0);
  assert.equal(connection.get('SELECT count(*) AS count FROM workspace_analysis_head').count, 0);
  assert.equal(connection.isTransaction, false);
  assert.throws(() => commitSynthesisResults(connection, synthesisRequest), /running request identity/);
  const adjudicationProfileId = registerEvaluatorProfile(connection, { code: 'native-adjudication', taskCode: 'adjudication',
    llmAssignmentId: assignments[2].assignmentId, promptSha256: '1'.repeat(64), behaviorSha256: '2'.repeat(64), resultContractSha256: '3'.repeat(64) });
  const adjudicationRequest = { binding, runId: run.runId, profileId: adjudicationProfileId, groupVersionIds: final.groupVersionIds };
  const adjudication = recordAdjudicationRequest(connection, adjudicationRequest);
  const adjudicationInput = JSON.parse(adjudication.serializedInput);
  assert.equal(adjudicationInput.comparisonPairs.length, 1);
  assert.equal(adjudicationInput.groups.length, 2);
  assert.throws(() => prepareAdjudicationInput(connection, { ...adjudicationRequest, groupVersionIds: [999999] }), /completed pinned synthesis/);
  const comparison = { ...adjudicationInput.comparisonPairs[0], relationship: 'equivalent', title: 'Overlapping validation rules', rationale: 'Both require input validation',
    needsReview: true, leftQuote: 'Validate captured inputs', rightQuote: 'Check captured inputs' };
  const adjudicated = { schemaVersion: 4, stage: 'adjudication', phase: 'relationships', comparisons: [comparison] };
  const adjudicationCommand = { binding, runId: run.runId, evaluationId: adjudication.evaluationId, inputFingerprint: adjudication.inputFingerprint, result: adjudicated };
  const completionRequest = { binding, runId: run.runId, sourceProfileId: profileId, reconciliationProfileId,
    adjudicationProfileId, expectedHeadRunId: null };
  assert.throws(() => completeNativeAnalysis(connection, completionRequest), /unfinished or mixed/);
  assert.throws(() => commitAdjudicationResults(connection, { ...adjudicationCommand, result: { ...adjudicated, comparisons: [] } }), /every requested comparison/);
  assert.throws(() => commitAdjudicationResults(connection, { ...adjudicationCommand, result: { ...adjudicated,
    comparisons: [{ ...comparison, leftQuote: 'Fabricated quote' }] } }), /exact supplied wording/);
  assert.equal(connection.get('SELECT count(*) AS count FROM findings').count, 0);
  const reviewed = commitAdjudicationResults(connection, adjudicationCommand);
  assert.equal(reviewed.comparisonCount, 1);
  assert.equal(reviewed.issueCount, 1);
  assert.equal(connection.get('SELECT count(*) AS count FROM finding_participants').count, 2);
  assert.equal(connection.get('SELECT count(*) AS count FROM issue_resolutions').count, 0);
  assert.equal(connection.get('SELECT count(*) AS count FROM workspace_analysis_head').count, 0);
  assert.equal(connection.isTransaction, false);
  assert.throws(() => commitAdjudicationResults(connection, adjudicationCommand), /running identity/);
  assert.throws(() => completeNativeAnalysis(connection, { ...completionRequest, expectedHeadRunId: 999 }), /changed current analysis head/);
  const completed = completeNativeAnalysis(connection, completionRequest);
  assert.equal(completed.outcome, 'complete');
  assert.equal(completed.groupCount, 2);
  assert.equal(completed.comparisonCount, 1);
  assert.equal(completed.readyForUi, false);
  assert.equal(connection.get('SELECT run_id FROM workspace_analysis_head WHERE workspace_id = 1').run_id, run.runId);
  assert.equal(connection.get('SELECT outcome FROM analysis_runs WHERE id = ?', [run.runId]).outcome, 'complete');
  assert.equal(connection.get('SELECT count(*) AS count FROM issue_resolutions').count, 0);
  assert.equal(connection.isTransaction, false);
});

test('native downstream planning measures complete routing envelopes before dispatch', context => {
  const { connection, binding, run, profileId, assignments, sourceVersionIds } = nativeAssessmentFixture(context,
    { sourceCount: 3, content: 'x'.repeat(150000), taskCodes: ['assessment', 'reconciliation'] });
  for (const id of sourceVersionIds) {
    const sourceRequest = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId, sourceVersionIds: [id] });
    commitAssessmentResults(connection, { binding, runId: run.runId, evaluationId: sourceRequest.evaluationId,
      inputFingerprint: sourceRequest.inputFingerprint, result: nativeAssessmentResult(sourceRequest) });
  }
  const reconciliationProfileId = registerEvaluatorProfile(connection, { code: 'native-reconciliation', taskCode: 'reconciliation',
    llmAssignmentId: assignments[1].assignmentId, promptSha256: 'd'.repeat(64), behaviorSha256: 'e'.repeat(64), resultContractSha256: 'f'.repeat(64) });
  const request = { binding, runId: run.runId, sourceProfileId: profileId, reconciliationProfileId };
  const input = { prompt: 'Synthetic reconciliation instructions.', schema: '{"type":"object"}' };
  const plan = planNativeReconciliation(connection, request, 'routing', input);
  assert.equal(plan.batchCount, 3);
  assert.ok(plan.jobs.every(job => job.payloadBytes <= 393216));
  assert.equal(plan.pendingPayloadBytes, plan.jobs.reduce((sum, job) => sum + job.payloadBytes, 0));
  assert.equal(connection.get('SELECT count(*) AS count FROM evaluations').count, 3);
  assert.throws(() => planNativeReconciliation(connection, request, 'routing', { ...input, prompt: 'p'.repeat(393216) }), /payload budget/);
  const componentIds = plan.jobs.flatMap(job => {
    const recorded = recordEvaluationRequest(connection, job.request);
    return commitReconciliationComponents(connection, { binding, runId: run.runId, evaluationId: recorded.evaluationId,
      inputFingerprint: recorded.inputFingerprint, result: { schemaVersion: 4, stage: 'reconciliation', phase: 'routing',
        components: [{ assessmentResultIds: job.request.assessmentResultIds, semanticSummary: 's'.repeat(1200) }] } }).componentIds;
  });
  const consolidatedPlan = planNativeReconciliation(connection, request, 'consolidation', input);
  assert.equal(consolidatedPlan.batchCount, 1);
  assert.deepEqual(consolidatedPlan.jobs[0].request.componentIds, componentIds);
  const recordedCount = connection.get('SELECT count(*) AS count FROM evaluations').count;
  const padding = 393216 - consolidatedPlan.pendingPayloadBytes + 1;
  assert.throws(() => planNativeReconciliation(connection, request, 'consolidation', { ...input, prompt: input.prompt + 'p'.repeat(padding) }), /global consolidation envelope/);
  const recorded = recordEvaluationRequest(connection, consolidatedPlan.jobs[0].request);
  commitReconciliationComponents(connection, { binding, runId: run.runId, evaluationId: recorded.evaluationId, inputFingerprint: recorded.inputFingerprint,
    result: { schemaVersion: 4, stage: 'reconciliation', phase: 'consolidation', components: [{
      assessmentResultIds: consolidatedPlan.jobs[0].request.assessmentResultIds, semanticSummary: 'One indivisible synthesis scope' }] } });
  assert.throws(() => planNativeReconciliation(connection, request, 'synthesis', input), /complete synthesis evidence/);
  assert.equal(connection.get('SELECT count(*) AS count FROM evaluations').count, recordedCount + 1);
});

test('native downstream execution resumes committed phases and advances only complete typed results', async context => {
  const { connection, binding, run, profileId, assignments, sourceVersionIds } = nativeAssessmentFixture(context,
    { sourceCount: 4, taskCodes: ['assessment', 'reconciliation', 'adjudication'] });
  connection.exec("INSERT INTO action_definitions VALUES (2, 'add', 'Add'); INSERT INTO guidance_sections VALUES (1, 0, 'Validation'); INSERT INTO source_provenance_codes VALUES ('synthetic', 'Synthetic evidence')");
  const sourceRequest = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId, sourceVersionIds });
  commitAssessmentResults(connection, { binding, runId: run.runId, evaluationId: sourceRequest.evaluationId,
    inputFingerprint: sourceRequest.inputFingerprint, result: nativeAssessmentResult(sourceRequest) });
  const inputs = { reconciliation: { prompt: 'Synthetic reconciliation instructions.', schema: '{"type":"object"}' },
    adjudication: { prompt: 'Synthetic adjudication instructions.', schema: '{"type":"object"}' } };
  const profiles = {};
  for (const [task, assignment] of [['reconciliation', assignments[1]], ['adjudication', assignments[2]]]) {
    profiles[task] = registerEvaluatorProfile(connection, { code: `native-${task}`, taskCode: task, llmAssignmentId: assignment.assignmentId,
      promptSha256: createHash('sha256').update(inputs[task].prompt).digest('hex'), behaviorSha256: 'e'.repeat(64),
      resultContractSha256: createHash('sha256').update(inputs[task].schema).digest('hex') });
  }
  const request = { binding, runId: run.runId, sourceProfileId: profileId, reconciliationProfileId: profiles.reconciliation,
    adjudicationProfileId: profiles.adjudication, expectedHeadRunId: null };
  const calls = [];
  const events = [];
  let failFirstSynthesis = true;
  const evaluate = async (recorded, { phase }) => {
    assert.equal(connection.isTransaction, false);
    calls.push(phase);
    const input = JSON.parse(recorded.serializedInput);
    if (phase === 'routing' || phase === 'consolidation') return { schemaVersion: 4, stage: 'reconciliation', phase,
      components: input.assessments.map(member => ({ assessmentResultIds: [member.assessmentResultId], semanticSummary: `Synthetic requirement ${member.assessmentResultId}` })) };
    if (phase === 'synthesis') {
      if (failFirstSynthesis) { failFirstSynthesis = false; throw new Error('Synthetic synthesis interruption'); }
      return { schemaVersion: 4, stage: 'reconciliation', phase, groups: input.assessments.map(member => ({
        title: `Synthetic requirement ${member.assessmentResultId}`, semanticSummary: 'Preserve the captured requirement', synthesisRationale: 'Source-grounded synthetic result',
        wording: `Review captured requirement ${member.assessmentResultId}.`, selectionFactors: { severity: 3 }, selectionRationale: 'Synthetic rationale',
        reviewState: 'recommended', needsReview: false, members: [{ assessmentResultId: member.assessmentResultId, role: 'primary', coverageRationale: 'Preserves the captured requirement' }],
        operations: [{ role: 'primary', action: 'add', targetRuleVersionId: null, surfaceCode: 'implementation', sectionHeading: 'Validation',
          rationale: 'No accepted baseline', relationship: null, provenanceCodes: ['synthetic'], evidenceCodes: [], applicabilityCodes: [] }],
      })), dispositions: input.assessments.map(member => ({ assessmentResultId: member.assessmentResultId, code: 'grouped', rationale: 'Preserved in final wording' })) };
    }
    return { schemaVersion: 4, stage: 'adjudication', phase: 'relationships', comparisons: input.comparisonPairs.map(pair => ({ ...pair,
      relationship: 'independent', title: 'Synthetic independent comparison', rationale: 'Distinct synthetic comparison subjects', needsReview: false, leftQuote: null, rightQuote: null })) };
  };
  await assert.rejects(executeNativeDownstream(connection, request, inputs, evaluate, event => events.push(event)), /in-flight jobs settled/);
  assert.equal(connection.get('SELECT count(*) AS count FROM workspace_analysis_head').count, 0);
  assert.equal(connection.get('SELECT count(*) AS count FROM group_versions').count, 2);
  const partialGroupIds = connection.all('SELECT id FROM group_versions ORDER BY id').map(row => row.id);
  const comparisonInput = prepareAdjudicationInput(connection, { binding, runId: run.runId, profileId: request.adjudicationProfileId, groupVersionIds: partialGroupIds });
  inputs.adjudication.prompt += 'p'.repeat(393216 - measureAssessmentInputBytes(comparisonInput.serializedInput, inputs.adjudication) + 1);
  request.adjudicationProfileId = registerEvaluatorProfile(connection, { code: 'native-bounded-adjudication', taskCode: 'adjudication',
    llmAssignmentId: assignments[2].assignmentId, promptSha256: createHash('sha256').update(inputs.adjudication.prompt).digest('hex'),
    behaviorSha256: 'e'.repeat(64), resultContractSha256: createHash('sha256').update(inputs.adjudication.schema).digest('hex') });
  const inferenceCount = calls.length;
  await assert.rejects(executeNativeDownstream(connection, { ...request, expectedHeadRunId: 999 }, inputs, evaluate), /changed analysis head before inference/);
  assert.equal(calls.length, inferenceCount);
  const resumed = await executeNativeDownstream(connection, request, inputs, evaluate, event => events.push(event));
  assert.equal(resumed.groupCount, 4);
  assert.equal(resumed.comparisonCount, 6);
  assert.equal(resumed.readyForUi, false);
  assert.equal(calls.filter(phase => phase === 'adjudication').length, 6);
  assert.equal(calls.filter(phase => phase === 'routing').length, 1);
  assert.equal(calls.filter(phase => phase === 'consolidation').length, 1);
  assert.equal(calls.filter(phase => phase === 'synthesis').length, 5);
  assert.equal(events.filter(event => event.state === 'plan' && event.phase === 'synthesis').at(-1).recoveredBatchCount, 2);
  assert.equal(connection.get('SELECT count(*) AS count FROM changes').count, 0);
  assert.equal(connection.get('SELECT outcome FROM analysis_runs WHERE id = ?', [run.runId]).outcome, 'complete');
});

test('native downstream database bridge refuses revision-one execution without an explicit upgrade', context => {
  const { connection, databasePath } = nativeAssessmentFixture(context, { fileBacked: true, schemaVersion: 1 });
  assert.throws(() => execFileSync(process.execPath,
    [databaseBridgePath, 'continue-analysis', databasePath],
    { encoding: 'utf8', input: '{}', timeout: 10000, stdio: ['pipe', 'pipe', 'pipe'] }), /explicit reviewed revision-two database upgrade/);
  assert.equal(validateWorkbenchApplicationSchema(connection, { schemaVersion: 1 }).valid, true);
  assert.equal(connection.get('SELECT count(*) AS count FROM evaluations').count, 0);
});

test('native downstream database bridge commits actual typed component inputs across processes', context => {
  const { connection, databasePath, binding, run, profileId, assignments, sourceVersionIds } = nativeAssessmentFixture(context,
    { sourceCount: 1, fileBacked: true, taskCodes: ['assessment', 'reconciliation'] });
  const sourceRequest = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId, sourceVersionIds });
  commitAssessmentResults(connection, { binding, runId: run.runId, evaluationId: sourceRequest.evaluationId,
    inputFingerprint: sourceRequest.inputFingerprint, result: nativeAssessmentResult(sourceRequest) });
  const resultIds = connection.all('SELECT id FROM assessment_results ORDER BY id').map(row => row.id);
  const reconciliationProfileId = registerEvaluatorProfile(connection, { code: 'native-reconciliation', taskCode: 'reconciliation',
    llmAssignmentId: assignments[1].assignmentId, promptSha256: 'd'.repeat(64), behaviorSha256: 'e'.repeat(64), resultContractSha256: 'f'.repeat(64) });
  const bridge = (operation, request) => JSON.parse(execFileSync(process.execPath,
    [databaseBridgePath, operation, databasePath],
    { encoding: 'utf8', input: JSON.stringify(request), timeout: 10000 }));
  const recorded = bridge('evaluation-request', { binding, runId: run.runId, profileId: reconciliationProfileId,
    sourceVersionIds, assessmentResultIds: resultIds, reconciliationPhase: 'routing' });
  const completed = bridge('reconciliation-components', { binding, runId: run.runId, evaluationId: recorded.evaluationId,
    inputFingerprint: recorded.inputFingerprint, result: { schemaVersion: 4, stage: 'reconciliation', phase: 'routing',
      components: [{ assessmentResultIds: resultIds, semanticSummary: 'Validate captured input' }] } });
  assert.equal(completed.outcome, 'complete');
  assert.equal(connection.get('SELECT count(*) AS count FROM reconciliation_component_members').count, 1);
  assert.equal(connection.get('SELECT outcome FROM evaluations WHERE id = ?', [recorded.evaluationId]).outcome, 'complete');
  assert.equal(connection.get('SELECT count(*) AS count FROM workspace_analysis_head').count, 0);
});

test('database-native payload measurement includes the complete UTF-8 prompt schema and quoted input', () => {
  const evaluatorInput = { prompt: 'Synthetic instructions\r\nPreserve \u00e9 and \u{1f600}.', schema: '{"type":"object"}\r\n' };
  const input = JSON.stringify({ stage: 'assessment', content: '\u00e9\u{1f600}' });
  const expected = evaluatorInput.prompt + '\n\n## Output Contract\n' + evaluatorInput.schema + '\n\n## Untrusted Quoted Input\n' + input;
  assert.equal(measureAssessmentInputBytes(input, evaluatorInput), Buffer.byteLength(expected, 'utf8'));
  assert.ok(measureAssessmentInputBytes(input, evaluatorInput) > Buffer.byteLength(input, 'utf8'));
  assert.throws(() => measureAssessmentInputBytes(input), /complete evaluator input/);
  assert.throws(() => measureAssessmentInputBytes(input, { prompt: evaluatorInput.prompt }), /complete evaluator input/);
});

test('database-native planning splits full evaluator payloads before estimating the complete workload', async context => {
  const { connection, binding, run, profileId, sourceVersionIds } = nativeAssessmentFixture(context, { sourceCount: 3, content: 'x'.repeat(200000) });
  const events = [];
  const requests = [];
  const input = { prompt: 'Synthetic instructions with repeated context.\n'.repeat(1000), schema: '{"type":"object"}' };
  const completed = await executeAssessmentBatches(connection, { binding, runId: run.runId, profileId }, input, async recorded => {
    requests.push(recorded);
    assert.ok(measureAssessmentInputBytes(recorded.serializedInput, input) <= 393216);
    return nativeAssessmentResult(recorded);
  }, event => events.push(event));
  assert.equal(events[0].batchCount, 3);
  assert.equal(events[0].workerCount, 3);
  assert.deepEqual(requests.map(request => JSON.parse(request.serializedInput).sources.map(source => source.sourceVersionId)), sourceVersionIds.map(id => [id]));
  const sizes = requests.map(request => Buffer.byteLength(input.prompt + '\n\n## Output Contract\n' + input.schema + '\n\n## Untrusted Quoted Input\n' + request.serializedInput, 'utf8'));
  assert.equal(events[0].pendingPayloadBytes, sizes.reduce((sum, size) => sum + size, 0));
  assert.equal(events[0].estimatedMilliseconds, Math.ceil(sizes.reduce((sum, size) => sum + size, 0) / (200 * 3) * 1000));
  assert.equal(completed.completedSources, 3);
});

test('database-native planning accepts the exact payload limit and rejects an oversized source before inference', async context => {
  const { connection, binding, run, profileId, sourceVersionIds } = nativeAssessmentFixture(context);
  const request = { binding, runId: run.runId, profileId };
  const prepared = prepareEvaluationInput(connection, { ...request, sourceVersionIds });
  const base = { prompt: '', schema: '{"type":"object"}' };
  const prompt = 'p'.repeat(393216 - measureAssessmentInputBytes(prepared.serializedInput, base));
  assert.equal(measureAssessmentInputBytes(prepared.serializedInput, { ...base, prompt }), 393216);
  const events = [];
  await assert.rejects(executeAssessmentBatches(connection, request, { ...base, prompt: prompt + 'x' }, () => {
    throw new Error('Oversized payload must be rejected before inference');
  }, event => events.push(event)), /exceeds evaluator payload budget/);
  assert.equal(events.length, 0);
  assert.equal(connection.get('SELECT count(*) AS count FROM evaluations').count, 0);
  const completed = await executeAssessmentBatches(connection, request, { ...base, prompt }, async recorded => nativeAssessmentResult(recorded),
    event => events.push(event));
  assert.equal(events[0].pendingPayloadBytes, 393216);
  assert.equal(events[0].workerCount, 1);
  assert.equal(events[0].estimatedMilliseconds, Math.ceil(393216 / 200 * 1000));
  assert.equal(completed.completedSources, 1);
});

test('database-native planning refuses missing evaluator context instead of estimating request bytes alone', async context => {
  const { connection, binding, run, profileId } = nativeAssessmentFixture(context);
  await assert.rejects(executeAssessmentBatches(connection, { binding, runId: run.runId, profileId }, undefined, () => {
    throw new Error('Incomplete evaluator context must not trigger inference');
  }), /complete evaluator input/);
  assert.equal(connection.get('SELECT count(*) AS count FROM evaluations').count, 0);
});

test('database-native executor runs three batches concurrently and reports only committed progress', async context => {
  const { connection, binding, run, profileId } = nativeAssessmentFixture(context, { sourceCount: 8 });
  const gates = Array.from({ length: 4 }, () => Promise.withResolvers());
  const events = [];
  const calls = [];
  const completed = [];
  let active = 0;
  let maximumActive = 0;
  const execution = executeAssessmentBatches(connection, { binding, runId: run.runId, profileId }, assessmentEvaluatorInput, async recorded => {
    const index = calls.length;
    calls.push(recorded);
    active += 1;
    maximumActive = Math.max(maximumActive, active);
    assert.equal(connection.isTransaction, false);
    await gates[index].promise;
    active -= 1;
    return nativeAssessmentResult(recorded);
  }, event => {
    events.push(event);
    if (event.state === 'passed') {
      completed.push(event.batchNumber);
      assert.equal(connection.get('SELECT count(*) AS count FROM assessment_results').count, event.assessmentCount);
      assert.equal(connection.get('SELECT outcome FROM evaluations WHERE id = ?', [event.evaluationId]).outcome, 'complete');
    }
  });
  try {
    assert.equal(calls.length, 3);
    gates[2].resolve();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(calls.length, 4);
    for (const index of [0, 3, 1]) {
      gates[index].resolve();
      await new Promise(resolve => setImmediate(resolve));
    }
    const result = await execution;
    assert.equal(maximumActive, 3);
    assert.deepEqual(completed, [3, 1, 4, 2]);
    assert.equal(events[0].state, 'plan');
    assert.equal(events[0].workerCount, 3);
    assert.equal(events[0].batchCount, 4);
    assert.equal(events[0].pendingPayloadBytes, calls.reduce((total, call) => total + measureAssessmentInputBytes(call.serializedInput, assessmentEvaluatorInput), 0));
    assert.deepEqual(events.filter(event => event.state === 'passed').map(event => event.sourceCount), [2, 4, 6, 8]);
    assert.equal(events.at(-1).state, 'complete');
    assert.equal(result.completedSources, 8);
    assert.equal(result.readyForUi, false);
  } finally {
    gates.forEach(gate => gate.resolve());
    await execution;
  }
});

for (const scenario of [
  { name: 'three workers and out-of-order completion', sourceCount: 8, maxWorkers: 3, workerCount: 3,
    completions: [[2, 1000], [0, 2000], [3, 3000], [1, 4000]] },
  { name: 'a single worker', sourceCount: 8, maxWorkers: 1, workerCount: 1,
    completions: [[0, 1000], [1, 3000], [2, 6000], [3, 10000]] },
  { name: 'one pending batch', sourceCount: 2, maxWorkers: 3, workerCount: 1,
    completions: [[0, 1000]] },
  { name: 'a zero-duration first sample', sourceCount: 4, maxWorkers: 3, workerCount: 2,
    completions: [[0, 0], [1, 1000]] },
]) {
  test(`database-native ETA uses accumulated worker time with ${scenario.name}`, async context => {
    const { connection, binding, run, profileId } = nativeAssessmentFixture(context, { sourceCount: scenario.sourceCount });
    let now = 0;
    context.mock.method(performance, 'now', () => now);
    const gates = scenario.completions.map(() => Promise.withResolvers());
    const calls = [];
    const startedAt = [];
    const events = [];
    let completedBytes = 0;
    let completedWorkerTime = 0;
    const execution = executeAssessmentBatches(connection, { binding, runId: run.runId, profileId }, assessmentEvaluatorInput, async recorded => {
      const index = calls.length;
      calls.push(recorded);
      startedAt.push(now);
      assert.equal(connection.isTransaction, false);
      await gates[index].promise;
      return nativeAssessmentResult(recorded);
    }, event => {
      events.push(event);
      if (event.state !== 'passed') return;
      const index = event.batchNumber - 1;
      const elapsed = now - startedAt[index];
      completedBytes += measureAssessmentInputBytes(calls[index].serializedInput, assessmentEvaluatorInput);
      completedWorkerTime += elapsed;
      const remainingBytes = events[0].pendingPayloadBytes - completedBytes;
      const expected = remainingBytes <= 0 ? 0 : completedWorkerTime <= 0 ?
        Math.ceil(remainingBytes / (200 * scenario.maxWorkers) * 1000) :
        Math.ceil(remainingBytes / ((completedBytes / completedWorkerTime) * scenario.maxWorkers));
      assert.equal(event.batchElapsedMilliseconds, elapsed);
      assert.equal(event.totalElapsedMilliseconds, now);
      assert.equal(event.remainingMilliseconds, expected);
      assert.equal(event.sourceCount, connection.get('SELECT count(*) AS count FROM assessment_results').count);
    }, scenario.maxWorkers);
    try {
      assert.equal(events[0].workerCount, scenario.workerCount);
      assert.equal(events[0].estimatedMilliseconds, Math.ceil(events[0].pendingPayloadBytes / (200 * scenario.workerCount) * 1000));
      assert.equal(calls.length, scenario.workerCount);
      for (const [index, completedAt] of scenario.completions) {
        now = completedAt;
        gates[index].resolve();
        await new Promise(resolve => setImmediate(resolve));
      }
      const result = await execution;
      const passed = events.filter(event => event.state === 'passed');
      assert.deepEqual(passed.map(event => event.batchNumber), scenario.completions.map(([index]) => index + 1));
      assert.equal(passed.at(-1).remainingMilliseconds, 0);
      assert.equal(result.completedSources, scenario.sourceCount);
      assert.equal(result.readyForUi, false);
    } finally {
      gates.forEach(gate => gate.resolve());
      await execution;
    }
  });
}

test('database-native executor stops dispatch after failure and drains in-flight commits before recovery', async context => {
  const { connection, binding, run, profileId, sourceVersionIds } = nativeAssessmentFixture(context, { sourceCount: 8 });
  let now = 0;
  context.mock.method(performance, 'now', () => now);
  const gates = Array.from({ length: 3 }, () => Promise.withResolvers());
  const calls = [];
  const events = [];
  let settled = false;
  const execution = executeAssessmentBatches(connection, { binding, runId: run.runId, profileId }, assessmentEvaluatorInput, async recorded => {
    const index = calls.length;
    calls.push(recorded);
    await gates[index].promise;
    const result = nativeAssessmentResult(recorded);
    if (index === 1) result.sources[1].assessments[0].categories = ['x'.repeat(129)];
    return result;
  }, event => events.push(event));
  const outcome = execution.then(value => { settled = true; return { value }; }, error => { settled = true; return { error }; });
  try {
    assert.equal(calls.length, 3);
    now = 1000;
    gates[1].resolve();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(settled, false);
    assert.equal(calls.length, 3);
    assert.equal(connection.get('SELECT count(*) AS count FROM assessment_results').count, 0);
    assert.equal(connection.get('SELECT outcome FROM evaluations WHERE id = ?', [calls[1].evaluationId]).outcome, 'failed');
    assert.equal(events.find(event => event.state === 'failed').remainingMilliseconds, events[0].estimatedMilliseconds);
    for (const index of [2, 0]) {
      now += 1000;
      gates[index].resolve();
      await new Promise(resolve => setImmediate(resolve));
    }
    assert.match((await outcome).error.message, /in-flight work settled/);
    assert.equal(calls.length, 3);
    assert.equal(events.some(event => event.state === 'complete'), false);
    assert.deepEqual(events.filter(event => event.state === 'passed').map(event => event.sourceCount), [2, 4]);
    let committedBytes = 0;
    let successfulWorkerTime = 0;
    for (const [index, event] of events.filter(event => event.state === 'passed').entries()) {
      const expectedElapsed = (index + 2) * 1000;
      assert.equal(event.batchElapsedMilliseconds, expectedElapsed);
      committedBytes += measureAssessmentInputBytes(calls[event.batchNumber - 1].serializedInput, assessmentEvaluatorInput);
      successfulWorkerTime += expectedElapsed;
      const remainingBytes = events[0].pendingPayloadBytes - committedBytes;
      const expected = Math.ceil(remainingBytes / ((committedBytes / successfulWorkerTime) * 3));
      assert.equal(event.remainingMilliseconds, expected);
    }
    const plan = readAssessmentRecoveryPlan(connection, { binding, runId: run.runId, profileId });
    assert.deepEqual(plan.remainingSourceVersionIds, [...sourceVersionIds.slice(2, 4), ...sourceVersionIds.slice(6)]);
    const retried = [];
    const recovered = await executeAssessmentBatches(connection, { binding, runId: run.runId, profileId }, assessmentEvaluatorInput, async recorded => {
      retried.push(...JSON.parse(recorded.serializedInput).sources.map(source => source.sourceVersionId));
      return nativeAssessmentResult(recorded);
    });
    assert.deepEqual(retried, plan.remainingSourceVersionIds);
    assert.equal(recovered.recoveredSourceCount, 4);
    assert.equal(recovered.evaluatedSourceCount, 4);
    assert.equal(recovered.completedSources, 8);
    assert.equal(connection.get('SELECT count(*) AS count FROM evaluations').count, 5);
    assert.equal(connection.get('SELECT count(*) AS count FROM workspace_analysis_head').count, 0);
    assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
  } finally {
    gates.forEach(gate => gate.resolve());
    await outcome;
  }
});

test('one invalid concurrent batch rolls back every result child while other batches commit', async context => {
  const { connection, databasePath, binding, run, profileId, sourceVersionIds } = nativeAssessmentFixture(context, { sourceCount: 6, fileBacked: true });
  const observer = openWorkbenchSqlite({ mode: 'read-only', databasePath });
  const releases = Array.from({ length: 3 }, () => Promise.withResolvers());
  const requests = releases.map((_, index) => recordEvaluationRequest(connection, { binding, runId: run.runId, profileId,
    sourceVersionIds: sourceVersionIds.slice(index * 2, index * 2 + 2) }));
  const workers = requests.map(async (recorded, index) => {
    assert.equal(connection.isTransaction, false);
    await releases[index].promise;
    const result = nativeAssessmentResult(recorded);
    if (index === 1) result.sources[1].assessments[0].categories = ['x'.repeat(129)];
    return commitAssessmentResults(connection, { binding, runId: run.runId, evaluationId: recorded.evaluationId,
      inputFingerprint: recorded.inputFingerprint, result });
  });
  const settled = Promise.allSettled(workers);
  try {
    releases[1].resolve();
    await assert.rejects(workers[1], /Proposed category exceeds its supported length/);
    assert.equal(connection.isTransaction, false);
    for (const table of ['assessment_results', 'scorecards', 'scorecard_values', 'assessment_uncertainties', 'assessment_category_proposals', 'assessment_surfaces']) {
      assert.equal(observer.get(`SELECT count(*) AS count FROM ${table}`).count, 0, `${table} must roll back with the rejected batch`);
    }
    assert.equal(observer.get('SELECT outcome FROM evaluations WHERE id = ?', [requests[1].evaluationId]).outcome, 'running');
    failEvaluation(connection, { binding, runId: run.runId, evaluationId: requests[1].evaluationId, failureCode: 'invalid-result' });
    for (const index of [2, 0]) {
      releases[index].resolve();
      assert.equal((await workers[index]).assessmentCount, 2);
    }
    const outcomes = await settled;
    assert.deepEqual(outcomes.map(outcome => outcome.status), ['fulfilled', 'rejected', 'fulfilled']);
    for (const table of ['assessment_results', 'scorecards', 'scorecard_values', 'assessment_uncertainties', 'assessment_category_proposals', 'assessment_surfaces']) {
      assert.equal(observer.get(`SELECT count(*) AS count FROM ${table}`).count, 4, `${table} must contain only the successful batches`);
    }
    assert.equal(observer.get('SELECT count(*) AS count FROM assessment_results WHERE evaluation_id = ?', [requests[1].evaluationId]).count, 0);
    assert.equal(observer.get('SELECT outcome FROM evaluations WHERE id = ?', [requests[1].evaluationId]).outcome, 'failed');
    const pending = readAssessmentRecoveryPlan(connection, { binding, runId: run.runId, profileId });
    assert.deepEqual(pending.remainingSourceVersionIds, sourceVersionIds.slice(2, 4));
    assert.deepEqual(pending.completedEvaluationIds, [requests[0].evaluationId, requests[2].evaluationId]);
    assert.equal(pending.completedSourceCount, 4);
    assert.equal(pending.completedAssessmentCount, 4);
    const previousRows = observer.all('SELECT * FROM assessment_results ORDER BY id');
    let retryCount = 0;
    const recovered = await continueAssessmentRun(connection, { binding, runId: run.runId, profileId }, assessmentEvaluatorInput, async recorded => {
      retryCount += 1;
      assert.equal(connection.isTransaction, false);
      assert.notEqual(recorded.evaluationId, requests[1].evaluationId);
      assert.equal(observer.get('SELECT outcome FROM evaluations WHERE id = ?', [recorded.evaluationId]).outcome, 'running');
      assert.deepEqual(JSON.parse(recorded.serializedInput).sources.map(source => source.sourceVersionId), sourceVersionIds.slice(2, 4));
      return nativeAssessmentResult(recorded);
    });
    assert.equal(retryCount, 1);
    assert.equal(recovered.completedSources, 6);
    assert.equal(recovered.completedAssessments, 6);
    assert.equal(recovered.readyForUi, false);
    assert.deepEqual(observer.all('SELECT * FROM assessment_results ORDER BY id').slice(0, previousRows.length), previousRows);
    assert.equal(observer.get('SELECT count(*) AS count FROM evaluations').count, 4);
    assert.equal(observer.get('SELECT failure_code FROM evaluations WHERE id = ?', [requests[1].evaluationId]).failure_code, 'invalid-result');
    for (const table of ['assessment_results', 'scorecards', 'scorecard_values', 'assessment_uncertainties', 'assessment_category_proposals', 'assessment_surfaces']) {
      assert.equal(observer.get(`SELECT count(*) AS count FROM ${table}`).count, 6);
    }
    await continueAssessmentRun(connection, { binding, runId: run.runId, profileId }, assessmentEvaluatorInput, () => { throw new Error('Already committed batches must not run again'); });
    assert.equal(observer.get('SELECT count(*) AS count FROM evaluations').count, 4);
    assert.deepEqual(observer.all('PRAGMA foreign_key_check'), []);
    assert.equal(observer.get('PRAGMA quick_check').quick_check, 'ok');
    assert.equal(observer.get('SELECT count(*) AS count FROM workspace_analysis_head').count, 0);
  } finally {
    releases.forEach(release => release.resolve());
    await settled;
    observer.close();
  }
});

test('assessment commits reject cross-run, cross-request, missing sources and duplicate delivery', context => {
  const { connection, binding, run, profileId, assignments, sourceVersionIds } = nativeAssessmentFixture(context, { sourceCount: 4 });
  const first = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId, sourceVersionIds: sourceVersionIds.slice(0, 2) });
  const second = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId, sourceVersionIds: sourceVersionIds.slice(2) });
  const otherRun = beginAnalysisRun(connection, { binding, actorId: 1, scoringPolicyId: 1, force: false,
    llmAssignmentIds: assignments.map(assignment => assignment.assignmentId) });
  const result = nativeAssessmentResult(first);
  const command = { binding, runId: run.runId, evaluationId: first.evaluationId, inputFingerprint: first.inputFingerprint, result };
  assert.throws(() => commitAssessmentResults(connection, { ...command, runId: otherRun.runId }), /running request identity/);
  assert.throws(() => commitAssessmentResults(connection, { ...command, inputFingerprint: second.inputFingerprint }), /running request identity/);
  assert.throws(() => commitAssessmentResults(connection, { ...command, result: nativeAssessmentResult(second) }), /exactly the captured request sources/);
  assert.throws(() => commitAssessmentResults(connection, { ...command, result: { ...result, sources: result.sources.slice(0, 1) } }), /exactly the captured request sources/);
  assert.throws(() => commitAssessmentResults(connection, { ...command, result: { ...result, sources: [result.sources[0], result.sources[0]] } }), /exactly the captured request sources/);
  assert.throws(() => recordEvaluationRequest(connection, { binding, runId: run.runId, profileId, sourceVersionIds: [999999] }), /pinned run capture/);
  assert.equal(connection.get('SELECT count(*) AS count FROM assessment_results').count, 0);
  assert.equal(connection.get('SELECT count(*) AS count FROM scorecards').count, 0);
  assert.equal(connection.get('SELECT count(*) AS count FROM evaluations').count, 2);
  assert.equal(commitAssessmentResults(connection, command).assessmentCount, 2);
  assert.throws(() => commitAssessmentResults(connection, command), /running request identity/);
  assert.equal(connection.get('SELECT count(*) AS count FROM assessment_results').count, 2);
  assert.equal(connection.get('SELECT outcome FROM evaluations WHERE id = ?', [second.evaluationId]).outcome, 'running');
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
});

test('assessment recovery keeps source families distinct when external source names overlap', async context => {
  const { connection, binding, assignments, profileId, sourceVersionIds } = nativeAssessmentFixture(context, { sourceCount: 3 });
  const otherDefinition = registerSourceDefinition(connection, { lane: { code: 'other', label: 'Other source family', displayOrder: 1 },
    code: 'other-synthetic-source', label: 'Other source', parserId: 'maintainer-proposals-v4', parserContractSha256: 'a'.repeat(64),
    definitionSha256: 'e'.repeat(64), repositoryId: 1, rootKind: 'repository', location: 'other-fixtures', configuredRef: null,
    contentFormat: 'utf8', files: ['**/*.rules.md'], exclude: [], assessmentBatchSize: 2, assessmentCardinality: 'exactly-one' });
  const otherCollection = ingestSourceCollection(connection, { definitionVersionId: otherDefinition, expectedCollectionId: null,
    repositoryContextId: 1, collectorVersion: 1,
    revision: { kind: 'repository-worktree', resolvedCommit: '1'.repeat(40), worktreeDirty: false, worktreeSha256: 'e'.repeat(64) }, complete: true,
    records: Array.from({ length: 3 }, (_, index) => {
      const content = `Other family source ${index + 1}.`;
      return { sourceId: `SOURCE-${String(index + 1).padStart(3, '0')}`, title: 'Other captured source', content,
        contentSha256: createHash('sha256').update(content).digest('hex'), location: `other-fixtures/source-${index + 1}.rules.md`,
        presence: 'present', sourceLifecycle: 'active' };
    }) });
  const run = beginAnalysisRun(connection, { binding, actorId: 1, scoringPolicyId: 1, force: false,
    llmAssignmentIds: assignments.map(assignment => assignment.assignmentId) });
  const batches = [];
  const completed = await continueAssessmentRun(connection, { binding, runId: run.runId, profileId }, assessmentEvaluatorInput, async recorded => {
    assert.equal(connection.isTransaction, false);
    const sources = JSON.parse(recorded.serializedInput).sources;
    assert.equal(new Set(sources.map(source => source.sourceDefinitionId)).size, 1);
    assert.ok(sources.length <= 2);
    batches.push({ family: sources[0].sourceDefinitionId, sources: sources.map(source => source.sourceVersionId) });
    return nativeAssessmentResult(recorded);
  });
  assert.deepEqual(batches, [
    { family: 'synthetic-source', sources: sourceVersionIds.slice(0, 2) },
    { family: 'synthetic-source', sources: sourceVersionIds.slice(2) },
    { family: 'other-synthetic-source', sources: otherCollection.records.slice(0, 2).map(record => record.sourceVersionId) },
    { family: 'other-synthetic-source', sources: otherCollection.records.slice(2).map(record => record.sourceVersionId) },
  ]);
  assert.equal(completed.completedSources, 6);
  assert.equal(completed.completedAssessments, 6);
  assert.equal(connection.get('SELECT count(DISTINCT source_version_id) AS count FROM assessment_results').count, 6);
  assert.deepEqual(readAssessmentRecoveryPlan(connection, { binding, runId: run.runId, profileId }).remainingSourceVersionIds, []);
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
  assert.equal(connection.get('SELECT count(*) AS count FROM workspace_analysis_head').count, 0);
});

test('valid zero-result source evaluations remain complete and are not rediscovered for retry', async context => {
  const { connection, binding, run, profileId, sourceVersionIds } = nativeAssessmentFixture(context, { sourceCount: 2, assessmentCardinality: 'zero-to-many' });
  const recorded = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId, sourceVersionIds });
  const result = nativeAssessmentResult(recorded);
  result.sources.forEach(source => { source.assessments = []; });
  assert.equal(commitAssessmentResults(connection, { binding, runId: run.runId, evaluationId: recorded.evaluationId,
    inputFingerprint: recorded.inputFingerprint, result }).assessmentCount, 0);
  const plan = readAssessmentRecoveryPlan(connection, { binding, runId: run.runId, profileId });
  assert.equal(plan.completedSourceCount, 2);
  assert.equal(plan.completedAssessmentCount, 0);
  assert.deepEqual(plan.completedEvaluationIds, [recorded.evaluationId]);
  assert.deepEqual(plan.remainingSourceVersionIds, []);
  const completed = await continueAssessmentRun(connection, { binding, runId: run.runId, profileId }, assessmentEvaluatorInput, () => {
    throw new Error('A valid zero-result evaluation must not trigger inference again');
  });
  assert.equal(completed.completedSources, 2);
  assert.equal(completed.completedAssessments, 0);
  assert.equal(completed.assessmentComplete, true);
  assert.equal(connection.get('SELECT count(*) AS count FROM evaluations').count, 1);
  assert.equal(connection.get('SELECT count(*) AS count FROM assessment_results').count, 0);
});

for (const outcome of ['cancelled', 'failed', 'complete']) {
  test(`${outcome} analysis runs reject late evaluator results without persisting result rows`, async context => {
    const { connection, binding, run, profileId, sourceVersionIds } = nativeAssessmentFixture(context);
    const recorded = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId, sourceVersionIds });
    connection.run('UPDATE analysis_runs SET outcome = ?, completed_at = ? WHERE id = ?', [outcome, new Date().toISOString(), run.runId]);
    assert.throws(() => commitAssessmentResults(connection, { binding, runId: run.runId, evaluationId: recorded.evaluationId,
      inputFingerprint: recorded.inputFingerprint, result: nativeAssessmentResult(recorded) }), /running request identity/);
    for (const table of ['assessment_results', 'scorecards', 'scorecard_values', 'assessment_uncertainties', 'assessment_category_proposals', 'assessment_surfaces']) {
      assert.equal(connection.get(`SELECT count(*) AS count FROM ${table}`).count, 0);
    }
    assert.equal(connection.get('SELECT outcome FROM analysis_runs WHERE id = ?', [run.runId]).outcome, outcome);
    assert.equal(connection.get('SELECT outcome FROM evaluations WHERE id = ?', [recorded.evaluationId]).outcome, 'running');
    assert.equal(connection.get('SELECT count(*) AS count FROM run_evaluations WHERE run_id = ?', [run.runId]).count, 1);
    await assert.rejects(continueAssessmentRun(connection, { binding, runId: run.runId, profileId }, assessmentEvaluatorInput, () => {
      throw new Error('A terminal run must not trigger inference');
    }), /running run and its pinned evaluator profile/);
    assert.equal(connection.get('SELECT count(*) AS count FROM evaluations').count, 1);
    assert.equal(connection.get('SELECT count(*) AS count FROM workspace_analysis_head').count, 0);
    assert.equal(connection.isTransaction, false);
    assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
  });
}

test('native requests pin source identity and atomic result commits hold no transaction during inference', async context => {
  const { connection, binding, definitionVersionId, collection, content, assignments, run, profileId, sourceVersionId } = nativeAssessmentFixture(context);
  const recorded = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId, sourceVersionIds: [sourceVersionId] });
  const pendingPlan = readAssessmentRecoveryPlan(connection, { binding, runId: run.runId, profileId });
  assert.deepEqual(pendingPlan.unfinishedEvaluationIds, [recorded.evaluationId]);
  assert.deepEqual(pendingPlan.remainingSourceVersionIds, [sourceVersionId]);
  assert.equal(pendingPlan.completedSourceCount, 0);
  const changedAssignments = configureProfileLlms(connection, 1, { models: [{ key: 'next', providerCode: 'synthetic', modelCode: 'changed-model' }],
    assignments: [{ taskCode: 'assessment', modelKey: 'next', adapterCode: 'synthetic', reasoningEffort: 'high' }] });
  assert.notEqual(changedAssignments[0].assignmentId, assignments[0].assignmentId);
  assert.equal(connection.get('SELECT assignment_id FROM analysis_run_llm_assignments WHERE run_id = ?', [run.runId]).assignment_id, assignments[0].assignmentId);
  const futureProfileId = registerEvaluatorProfile(connection, { code: 'future-assessment-v4', taskCode: 'assessment', llmAssignmentId: changedAssignments[0].assignmentId,
    promptSha256: 'a'.repeat(64), behaviorSha256: 'b'.repeat(64), resultContractSha256: 'c'.repeat(64) });
  assert.throws(() => recordEvaluationRequest(connection, { binding, runId: run.runId, profileId: futureProfileId, sourceVersionIds: [sourceVersionId] }), /pinned master-profile run/);
  assert.throws(() => beginAnalysisRun(connection, { binding, actorId: 1, scoringPolicyId: 1, force: false,
    llmAssignmentIds: assignments.map(assignment => assignment.assignmentId) }), /changed after availability/);
  assert.throws(() => connection.run('UPDATE evaluator_profiles SET llm_assignment_id = ? WHERE id = ?', [changedAssignments[0].assignmentId, profileId]), /immutable/);
  assert.equal(connection.isTransaction, false);
  assert.equal(connection.get('SELECT outcome FROM evaluations WHERE id = ?', [recorded.evaluationId]).outcome, 'running');
  assert.equal(JSON.parse(recorded.serializedInput).sources[0].content, content);
  assert.equal(connection.get('SELECT count(*) AS count FROM evaluation_inputs WHERE evaluation_id = ?', [recorded.evaluationId]).count, 5);
  const assessment = { localResultKey: 'meaning-1', title: 'Validate source', sourceMeaning: content, impactDescription: 'Prevents invalid inputs',
    hostedApplicable: true, applicabilityRationale: 'Reviewable from changed code', selectionFactors: { severity: 3 }, selectionRationale: 'Direct evidence',
    confidence: { level: 'high', rationale: 'Explicit source', uncertainties: [] }, categories: ['implementation'], existingCoverage: { score: 0, rationale: 'No accepted coverage' } };
  const result = { schemaVersion: 4, stage: 'assessment', sources: [{ sourceVersionId, assessments: [assessment] }] };
  assert.throws(() => commitAssessmentResults(connection, { binding, runId: run.runId, evaluationId: recorded.evaluationId, inputFingerprint: recorded.inputFingerprint,
    result: { ...result, sources: [{ sourceVersionId, assessments: [{ ...assessment, selectionFactors: { severity: 99 } }] }] } }), /policy or factor bounds/);
  assert.equal(connection.get('SELECT count(*) AS count FROM assessment_results').count, 0);
  assert.equal(connection.get('SELECT count(*) AS count FROM scorecards').count, 0);
  assert.equal(connection.isTransaction, false);
  const completed = commitAssessmentResults(connection, { binding, runId: run.runId, evaluationId: recorded.evaluationId, inputFingerprint: recorded.inputFingerprint, result });
  assert.equal(completed.assessmentCount, 1);
  assert.equal(connection.get('SELECT outcome FROM evaluations WHERE id = ?', [recorded.evaluationId]).outcome, 'complete');
  const completedPlan = readAssessmentRecoveryPlan(connection, { binding, runId: run.runId, profileId });
  assert.deepEqual(completedPlan.completedEvaluationIds, [recorded.evaluationId]);
  assert.deepEqual(completedPlan.remainingSourceVersionIds, []);
  assert.equal(completedPlan.completedSourceCount, 1);
  assert.equal(completedPlan.completedAssessmentCount, 1);
  assert.equal(connection.isTransaction, false);
  connection.run('UPDATE guidance_surface_content SET description = ? WHERE surface_id = ?', ['Changed category meaning', 1]);
  assert.throws(() => readAssessmentRecoveryPlan(connection, { binding, runId: run.runId, profileId }), /changed evaluation inputs/);
  connection.run('UPDATE guidance_surface_content SET description = ? WHERE surface_id = ?', ['Implementation behavior', 1]);
  assert.throws(() => commitAssessmentResults(connection, { binding, runId: run.runId, evaluationId: recorded.evaluationId, inputFingerprint: recorded.inputFingerprint, result }), /running request identity/);
  const failed = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId, sourceVersionIds: [sourceVersionId] });
  failEvaluation(connection, { binding, runId: run.runId, evaluationId: failed.evaluationId, failureCode: 'evaluator-failed' });
  assert.equal(connection.get('SELECT failure_code FROM evaluations WHERE id = ?', [failed.evaluationId]).failure_code, 'evaluator-failed');
  const unknown = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId, sourceVersionIds: [sourceVersionId] });
  commitAssessmentResults(connection, { binding, runId: run.runId, evaluationId: unknown.evaluationId, inputFingerprint: unknown.inputFingerprint,
    result: { ...result, sources: [{ sourceVersionId, assessments: [{ ...assessment, categories: ['unmapped-category'] }] }] } });
  const retained = connection.get('SELECT id, hosted_applicable FROM assessment_results WHERE evaluation_id = ?', [unknown.evaluationId]);
  assert.equal(retained.hosted_applicable, 1);
  assert.equal(connection.get('SELECT proposed_code FROM assessment_category_proposals WHERE assessment_id = ?', [retained.id]).proposed_code, 'unmapped-category');
  assert.equal(connection.get('SELECT count(*) AS count FROM assessment_surfaces WHERE assessment_id = ?', [retained.id]).count, 0);
  assert.throws(() => readAssessmentRecoveryPlan(connection, { binding, runId: run.runId, profileId }), /duplicate completed source coverage/);
  assert.throws(() => readAssessmentRecoveryPlan(connection, { binding, runId: run.runId, profileId: futureProfileId }), /pinned evaluator profile/);
  assert.equal(connection.get('SELECT count(*) AS count FROM workspace_analysis_head').count, 0);
  const recoveryRun = beginAnalysisRun(connection, { binding, actorId: 1, scoringPolicyId: 1, force: false,
    llmAssignmentIds: changedAssignments.map(assignment => assignment.assignmentId) });
  const interrupted = recordEvaluationRequest(connection, { binding, runId: recoveryRun.runId, profileId: futureProfileId, sourceVersionIds: [sourceVersionId] });
  let inferenceCalls = 0;
  const recovered = await continueAssessmentRun(connection, { binding, runId: recoveryRun.runId, profileId: futureProfileId }, assessmentEvaluatorInput, async recordedRequest => {
    inferenceCalls += 1;
    assert.equal(connection.isTransaction, false);
    assert.notEqual(recordedRequest.evaluationId, interrupted.evaluationId);
    assert.equal(connection.get('SELECT outcome FROM evaluations WHERE id = ?', [recordedRequest.evaluationId]).outcome, 'running');
    return result;
  });
  assert.equal(recovered.completedSources, 1);
  assert.equal(recovered.readyForUi, false);
  assert.equal(connection.get('SELECT failure_code FROM evaluations WHERE id = ?', [interrupted.evaluationId]).failure_code, 'interrupted-before-result');
  await continueAssessmentRun(connection, { binding, runId: recoveryRun.runId, profileId: futureProfileId }, assessmentEvaluatorInput, () => { throw new Error('Completed source must not be evaluated again'); });
  assert.equal(inferenceCalls, 1);
  assert.equal(connection.get('SELECT count(*) AS count FROM workspace_analysis_head').count, 0);
  const changedContent = 'Validate changed captured source behavior.';
  ingestSourceCollection(connection, { definitionVersionId, expectedCollectionId: collection.collectionId, repositoryContextId: 1, collectorVersion: 1,
    revision: { kind: 'repository-worktree', resolvedCommit: '1'.repeat(40), worktreeDirty: true, worktreeSha256: 'd'.repeat(64) }, complete: true,
    records: [{ sourceId: 'SOURCE-001', title: 'Captured source', content: changedContent, contentSha256: createHash('sha256').update(changedContent).digest('hex'),
      location: 'fixtures/source.rules.md', presence: 'present', sourceLifecycle: 'active' }] });
  assert.throws(() => readAssessmentRecoveryPlan(connection, { binding, runId: recoveryRun.runId, profileId: futureProfileId }), /changed source collections/);
  assert.equal(connection.get('SELECT outcome FROM evaluations WHERE id = ?', [recorded.evaluationId]).outcome, 'complete');
});

test('assessment execution guard rejects overlapping owners without deleting another lock', async context => {
  const directory = mkdtempSync(join(tmpdir(), 'workbench-assessment-lock-'));
  context.after(() => rmSync(directory, { recursive: true, force: true }));
  const databasePath = join(directory, 'candidate.sqlite');
  await withAssessmentExecutionLock(databasePath, async () => {
    assert.equal(existsSync(databasePath + '.assessment.lock'), true);
    await assert.rejects(withAssessmentExecutionLock(databasePath, () => {}), /already running or starting for this database/);
    assert.equal(existsSync(databasePath + '.assessment.lock'), true);
  });
  assert.equal(existsSync(databasePath + '.assessment.lock'), false);
});

test('assessment execution guard permits only one simultaneous command and refuses the second', async context => {
  const { connection, databasePath, binding, run, profileId, sourceVersionIds } = nativeAssessmentFixture(context, { fileBacked: true });
  const recoveryModule = new URL('../../modules/workbench/WorkbenchAssessmentRecovery.mjs', import.meta.url).href;
  const sqliteModule = new URL('../../modules/workbench/WorkbenchSqlite.mjs', import.meta.url).href;
  const evaluationModule = new URL('../../modules/workbench/WorkbenchEvaluations.mjs', import.meta.url).href;
  const script = `import { once } from 'node:events';
    import { withAssessmentExecutionLock } from ${JSON.stringify(recoveryModule)};
    import { openWorkbenchSqlite } from ${JSON.stringify(sqliteModule)};
    import { recordEvaluationRequest } from ${JSON.stringify(evaluationModule)};
    process.send({ state: 'ready' });
    const [message] = await once(process, 'message');
    try {
      await withAssessmentExecutionLock(message.databasePath, async () => {
        const connection = openWorkbenchSqlite({ mode: 'read-write', databasePath: message.databasePath });
        try {
          recordEvaluationRequest(connection, message.request);
          process.send({ state: 'entered' });
          await once(process, 'message');
        } finally { connection.close(); }
      });
      process.exitCode = 0;
    } catch (error) {
      process.send({ state: 'refused', code: error.code, message: error.message });
      process.exitCode = 1;
    }
    process.disconnect();`;
  const children = Array.from({ length: 2 }, () => spawn(process.execPath, ['--input-type=module', '-e', script], { stdio: ['pipe', 'pipe', 'pipe', 'ipc'] }));
  const exits = children.map(child => once(child, 'exit'));
  try {
    await Promise.all(children.map(child => once(child, 'message')));
    const results = children.map(child => once(child, 'message'));
    const request = { binding, runId: run.runId, profileId, sourceVersionIds };
    children.forEach(child => child.send({ databasePath, request }));
    const dispositions = (await Promise.all(results)).map(([result]) => result);
    assert.equal(dispositions.filter(result => result.state === 'entered').length, 1);
    assert.equal(dispositions.filter(result => result.state === 'refused').length, 1);
    const winner = dispositions.findIndex(result => result.state === 'entered');
    const loser = 1 - winner;
    assert.equal(dispositions[loser].code, 'workbench-execution-already-running');
    assert.match(dispositions[loser].message, /already running or starting for this database/);
    assert.equal((await exits[loser])[0], 1);
    const record = JSON.parse(readFileSync(databasePath + '.assessment.lock', 'utf8'));
    assert.equal(record.pid, children[winner].pid);
    assert.equal(connection.get('SELECT count(*) AS count FROM evaluations').count, 1);
    children[winner].send({ release: true });
    assert.equal((await exits[winner])[0], 0);
    assert.equal(existsSync(databasePath + '.assessment.lock'), false);
    assert.equal(connection.get('SELECT count(*) AS count FROM workspace_analysis_head').count, 0);
  } finally {
    for (const child of children) if (child.exitCode === null && child.signalCode === null) child.kill();
    await Promise.all(exits);
  }
});

test('assessment execution guard bridge returns a typed busy refusal without raw errors or writes', async context => {
  const { connection, databasePath, binding, run, assignments } = nativeAssessmentFixture(context,
    { fileBacked: true, taskCodes: ['assessment', 'reconciliation', 'adjudication'] });
  await withAssessmentExecutionLock(databasePath, async () => {
    const owner = readFileSync(databasePath + '.assessment.lock', 'utf8');
    const request = { databaseGuid: binding.databaseGuid, runId: run.runId, evaluatorCommand: 'synthetic-cli', cliVersion: 'fixture',
      llmAssignmentIds: assignments.map(assignment => assignment.assignmentId), maxParallelBatches: 3 };
    assert.throws(() => execFileSync(process.execPath, [databaseBridgePath, 'continue-analysis', databasePath],
      { encoding: 'utf8', input: JSON.stringify(request), timeout: 15000, stdio: ['pipe', 'pipe', 'pipe'] }), error => {
      assert.equal(error.status, 1);
      assert.equal(error.stderr, '');
      assert.deepEqual(JSON.parse(error.stdout), { kind: 'execution-refused', code: 'workbench-execution-already-running' });
      return true;
    });
    assert.equal(readFileSync(databasePath + '.assessment.lock', 'utf8'), owner);
    assert.equal(connection.get('SELECT count(*) AS count FROM evaluations').count, 0);
  });
});

test('assessment execution guard cancels owned children and blocks late database writes', async context => {
  const { connection, databasePath } = nativeAssessmentFixture(context, { fileBacked: true });
  let child;
  await assert.rejects(withAssessmentExecutionLock(databasePath, async control => {
    const guarded = withExecutionCancellation(connection, control);
    child = spawn(process.execPath, ['--input-type=module', '-e', "process.on('message', () => {}); process.send({ ready: true });"],
      { stdio: ['pipe', 'pipe', 'pipe', 'ipc'] });
    try {
      await once(child, 'message');
      const closed = once(child, 'exit');
      process.emit('SIGTERM');
      await closed;
      assert.equal(control.cancelled, true);
      assert.throws(() => guarded.run("UPDATE analysis_runs SET outcome = 'failed' WHERE id = 1"), /Execution cancelled/);
      assert.equal(connection.get('SELECT outcome FROM analysis_runs WHERE id = 1').outcome, 'running');
    } finally { if (child.exitCode === null && child.signalCode === null) child.kill(); }
  }), /Execution cancelled/);
  assert.equal(existsSync(databasePath + '.assessment.lock'), false);
  assert.equal(connection.get('SELECT count(*) AS count FROM workspace_analysis_head').count, 0);
});

test('catalog construction retains typed references and rejects writes after finalization', context => {
  const connection = applicationFixture(context);
  const content = Buffer.from('---\ndescription: Synthetic empty protected file\nsurface: implementation\n---\n');
  const digest = createHash('sha256').update(content).digest('hex');
  const snapshot = ingestProtectedCapture(connection, { repositoryContextId: 1, parserContractSha256: digest,
    requiredFiles: ['rules/implementation.rules.md'], files: [{ relativePath: 'rules/implementation.rules.md', contentBytes: content, contentSha256: digest }], blocks: [] });
  for (const revision of [1, 2]) connection.run(`INSERT INTO catalog_versions VALUES (?, NULL, ?, ?, 1, '2026-11-05', 1, ?, 'synthetic',
    'mandatory', 'model-based', 0, ?, '2026-11-05T00:00:00.000Z', NULL)`, [revision, snapshot.snapshotId, revision, '1'.repeat(40), digest]);
  connection.exec("INSERT INTO catalog_members VALUES (1, 1, 1); INSERT INTO catalog_evidence VALUES (2, 'synthetic', 0, 'architecture', 'Synthetic reference', 'Synthetic evidence')");
  connection.exec(`
    INSERT INTO source_lanes VALUES (1, 'synthetic', 'Synthetic source', 0);
    INSERT INTO source_definitions VALUES (1, 1, 'synthetic-source', 'Synthetic source');
    INSERT INTO source_rules VALUES (1, 1, 'SOURCE-001');
    INSERT INTO catalog_surface_content VALUES (1, 1, 'Captured category description', 'Captured title', 'Captured introduction', 'Captured closing');
    INSERT INTO catalog_surface_sections VALUES (1, 1, 0, 'Schema And State');
    INSERT INTO catalog_canonical_bindings VALUES (1, 1, 1, NULL);
  `);
  assert.throws(() => connection.exec("INSERT INTO catalog_surface_sections VALUES (2, 1, 0, 'Missing parent')"), { errcode: 787 });
  assert.throws(() => connection.exec('INSERT INTO catalog_canonical_bindings VALUES (1, 2, 1, NULL)'), { errcode: 787 });
  assert.throws(() => connection.exec("INSERT INTO catalog_member_evidence VALUES (1, 1, 0, 'synthetic')"), { errcode: 787 });
  assert.throws(() => connection.exec('INSERT INTO workspace_publication VALUES (1, 1)'), /finalized/);
  connection.exec("UPDATE catalog_versions SET finalized_at = '2026-11-05T00:00:00.000Z' WHERE id = 1; INSERT INTO workspace_publication VALUES (1, 1)");
  assert.throws(() => connection.exec('DELETE FROM catalog_members WHERE catalog_id = 1'), /immutable/);
  assert.throws(() => connection.exec('INSERT INTO catalog_members VALUES (1, 2, 2)'), /immutable/);
  assert.throws(() => connection.exec('UPDATE catalog_versions SET revision = 3 WHERE id = 1'), /immutable/);
  assert.throws(() => connection.exec("UPDATE catalog_surface_content SET title = 'Changed' WHERE catalog_id = 1"), /immutable/);
  assert.throws(() => connection.exec("INSERT INTO catalog_surface_sections VALUES (1, 1, 1, 'Changed')"), /immutable/);
  assert.throws(() => connection.exec('DELETE FROM catalog_canonical_bindings WHERE catalog_id = 1'), /immutable/);
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
});
