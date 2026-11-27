import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync, spawn } from 'node:child_process';
import { once } from 'node:events';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { Worker } from 'node:worker_threads';
import { openWorkbenchSqlite } from '../../modules/workbench/WorkbenchSqlite.mjs';
import { migrateNewWorkbenchApplication, validateWorkbenchApplicationSchema, workbenchSchemaVersion } from '../../modules/workbench/WorkbenchApplicationSchema.mjs';
import { ingestProtectedCapture } from '../../modules/workbench/WorkbenchProtectedSnapshots.mjs';
import { readSelectedCapacityPolicy, readSelectedCapacityConfiguration, readNativeWorkspaceView, readNativeWorkspaceReadiness } from '../../modules/workbench/WorkbenchWorkspace.mjs';
import { beginAnalysisRun, registerEvaluatorProfile, recordEvaluationRequest, commitAssessmentResults, commitReconciliationComponents, failEvaluation, readAssessmentRecoveryPlan, prepareEvaluationInput, withEvaluationPlanningSnapshot } from '../../modules/workbench/WorkbenchEvaluations.mjs';
import { registerSourceDefinition, ingestSourceCollection } from '../../modules/workbench/WorkbenchSourceIngestion.mjs';
import { configureProfileLlms, readWorkspaceLlmAssignments } from '../../modules/workbench/WorkbenchLlmAssignments.mjs';
import { continueAssessmentRun, withAssessmentExecutionLock, withExecutionCancellation } from '../../modules/workbench/WorkbenchAssessmentRecovery.mjs';
import { executeAssessmentBatches, measureAssessmentInputBytes } from '../../modules/workbench/WorkbenchAssessmentExecution.mjs';
import { planNativeReconciliation, planNativeAdjudication, executeNativeDownstream } from '../../modules/workbench/WorkbenchDownstreamExecution.mjs';
import { commitSynthesisResults } from '../../modules/workbench/WorkbenchReconciliationResults.mjs';
import { readPinnedGroupEvidence } from '../../modules/workbench/WorkbenchGroupContinuity.mjs';
import { prepareAdjudicationInput, recordAdjudicationRequest, commitAdjudicationResults, readAdjudicationResult } from '../../modules/workbench/WorkbenchAdjudication.mjs';
import { connectedRelationshipComponents, readAdjudicationComponents, validateAdjudicationResult } from '../../modules/workbench/WorkbenchRelationshipComponents.mjs';
import { completeNativeAnalysis } from '../../modules/workbench/WorkbenchAnalysisCompletion.mjs';
import { initializeNativeWorkspace } from '../../modules/workbench/WorkbenchNativeWorkspace.mjs';
import { parseInitialRulesJson } from '../../modules/workbench/WorkbenchInitialCatalog.mjs';
import { readNativeLlmRuntime } from '../../modules/workbench/WorkbenchAnalysis.mjs';
import { describeEvaluationFailure } from '../../modules/workbench/WorkbenchEvaluationFailures.mjs';
import { readPublishedGuidance, readRequiredGuidance } from '../../modules/workbench/WorkbenchPublishedGuidance.mjs';
import { createWorkbenchAudit, recordWorkbenchAudit } from '../../modules/workbench/WorkbenchAudit.mjs';
import './staged-catalog.test.mjs';

const databaseBridgePath = fileURLToPath(new URL('../../modules/workbench/WorkbenchDatabase.mjs', import.meta.url));

function newGroupContinuity() {
  return { kind: 'new', priorGroupVersionIds: [], retainedGroupVersionId: null, confidence: 'high',
    rationale: 'No established prior group evidence is supplied.', memberMatches: [] };
}

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

function applicationFixture(context, databasePath) {
  const connection = openWorkbenchSqlite(databasePath ? { mode: 'create', databasePath } : { mode: 'memory' });
  context.after(() => connection.close());
  migrateNewWorkbenchApplication(connection);
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

test('application initialization composes the actual component schemas and validates without mutating them', context => {
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

test('application initialization rolls back all domains on a component failure and refuses enclosing transactions', context => {
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

function nativeCatalogRequest() {
  const hash = value => createHash('sha256').update(value).digest('hex');
  const profile = JSON.parse(readFileSync(new URL('../../config/workbench-terraform-profile.json', import.meta.url), 'utf8'));
  const rules = profile.categories.flatMap((category, categoryIndex) => [1, 2].map(ordinal => ({
    id: `${['IMPL', 'TEST', 'DOCS'][categoryIndex]}-SYN-${String(ordinal).padStart(3, '0')}`,
    origin: 'hosted-baseline-migration', status: 'active', text: `Published ${category.code} criterion ${ordinal}.`,
    provenance: ['local-safeguard'], sourceIds: ['synthetic-source'], evidenceIds: ['synthetic-evidence'],
    ...(category.code === 'implementation' ? { implementationModels: ['legacy', 'typed', 'framework'] } : {}),
    ...(category.code === 'documentation' && ordinal === 2 ? { documentationGap: true } : {}),
  })));
  const definition = { id: 'synthetic-source', displayName: 'Synthetic source', parser: 'maintainer-proposals-v4',
    root: { kind: 'repository', path: 'fixtures' }, assessmentBatchSize: 2, files: ['*.rules.md'], exclude: [] };
  const definitionJson = JSON.stringify(definition);
  const records = rules.map((rule, index) => ({ sourceId: rule.id, title: `Synthetic criterion ${index + 1}`,
    content: rule.text, contentSha256: hash(rule.text), location: `fixtures/source-${index + 1}.rules.md`,
    presence: 'present', sourceLifecycle: 'active', provenance: 'local-safeguard', evidence: ['Synthetic evidence'],
    surface: profile.categories[Math.floor(index / 2)].code, ruleText: rule.text, rationale: 'Synthetic rationale' }));
  const inventory = { $schema: 'source-inventory.schema.json', schemaVersion: 1, sourceDefinitionId: definition.id,
    sourceDefinitionSha256: hash(definitionJson), inventoryConfigurationSha256: hash('synthetic configuration'), collectorVersion: 1,
    parserId: definition.parser, parserContractSha256: hash('synthetic parser'), collectedAt: '2026-11-09T00:00:00.000Z',
    collection: { complete: true, sourceRevision: { kind: 'repository-worktree', resolvedCommit: '1'.repeat(40),
      worktreeDirty: false, worktreeSha256: hash(JSON.stringify(records)) }, inventorySha256: hash(JSON.stringify(records)) }, records };
  const catalog = { $schema: 'instruction-catalog.schema.json', schemaVersion: 1, lastSemanticReview: '2026-11-09',
    upstreamSnapshot: { repository: 'hashicorp/terraform-provider-azurerm', baselineCommit: '2'.repeat(40), currentRef: 'main' },
    ruleDefaults: { requirementLevel: 'mandatory', enforcementMethod: 'model-based', documentationGap: false },
    sources: [{ id: 'synthetic-source', title: 'Synthetic source', rawUrl: 'https://example.com/raw', referenceUrl: 'https://example.com/source', baselineSha256: hash('synthetic baseline') }],
    evidence: [{ id: 'synthetic-evidence', type: 'architecture', description: 'Synthetic evidence', reference: 'fixtures/evidence.md' }],
    surfaces: profile.categories.map((category, index) => ({ id: category.code, outputPath: category.outputPath,
      description: category.description, applyTo: category.patterns[0], title: `Published ${category.label}`,
      introduction: 'Published introduction', closing: 'Published closing',
      sections: [{ heading: category.sections[0], ruleIds: rules.slice(index * 2, index * 2 + 2).map(rule => rule.id) }] })),
    canonicalCandidateMappings: Object.fromEntries(rules.map((rule, index) => [rule.id, { sourceDefinitionId: definition.id, sourceId: rule.id,
      ...(index === 0 ? { assessmentId: 'LEGACY-ASSESSMENT-SYN-001' } : {}) }])), rules };
  const files = profile.categories.map(category => {
    const contentBytes = Buffer.from(`Protected ${category.code} input`);
    return { relativePath: `fixtures/protected-${category.code}.rules.md`, contentBytes, contentSha256: hash(contentBytes) };
  });
  return { repository: { canonicalName: 'synthetic/workspace', branchRef: 'refs/heads/synthetic', commitOid: '1'.repeat(40) },
    profile, catalogJson: JSON.stringify(catalog), captures: [{ definition, definitionJson, inventoryJson: JSON.stringify(inventory),
      parserContract: { assessmentCardinality: 'exactly-one' }, lane: { code: 'synthetic', label: 'Synthetic source', displayOrder: 0 } }],
    protectedCapture: { parserContractSha256: hash('synthetic protection parser'), requiredFiles: files.map(file => file.relativePath), files,
      blocks: [{ id: 'PROTECTED-SYN-001', title: 'Synthetic protection', surfaceCode: 'implementation', relativePath: files[0].relativePath,
        content: 'Protected implementation input', contentSha256: files[0].contentSha256, text: 'Preserve protected wording.',
        provenance: 'local-safeguard', protectionReason: 'Synthetic protection boundary' }] } };
}

async function completeNativeCatalogFixture(connection, binding, audit = null, report = () => {}) {
  const assignments = readWorkspaceLlmAssignments(connection, binding);
  const run = beginAnalysisRun(connection, { binding, actorId: 1, scoringPolicyId: 1, force: false,
    llmAssignmentIds: assignments.map(assignment => assignment.assignmentId) });
  const inputs = Object.fromEntries(['assessment', 'reconciliation', 'adjudication'].map(task =>
    [task, { prompt: `Synthetic ${task} instructions.`, schema: '{"type":"object"}' }]));
  const profiles = Object.fromEntries(Object.keys(inputs).map(task => [task, registerEvaluatorProfile(connection, {
    code: `launch-fixture-${task}`, taskCode: task, llmAssignmentId: assignments.find(assignment => assignment.taskCode === task).assignmentId,
    promptSha256: createHash('sha256').update(inputs[task].prompt).digest('hex'), behaviorSha256: 'b'.repeat(64),
    resultContractSha256: createHash('sha256').update(inputs[task].schema).digest('hex'),
  })]));
  const sourceVersionIds = connection.all(`SELECT member.source_version_id AS id FROM source_collection_heads head
    JOIN source_collection_members member ON member.collection_id = head.collection_id WHERE member.presence = 'present' ORDER BY member.ordinal`).map(row => row.id);
  const factors = Object.fromEntries(connection.all('SELECT code FROM scoring_factors ORDER BY id').map(factor => [factor.code, 3]));
  const recorded = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId: profiles.assessment, sourceVersionIds });
  commitAssessmentResults(connection, { binding, runId: run.runId, evaluationId: recorded.evaluationId, inputFingerprint: recorded.inputFingerprint,
    result: { schemaVersion: 4, stage: 'assessment', sources: JSON.parse(recorded.serializedInput).sources.map(source => ({
      sourceVersionId: source.sourceVersionId, assessments: [{ localResultKey: 'meaning-1', title: source.title, sourceMeaning: source.content,
        impactDescription: 'Prevents invalid synthetic inputs', hostedApplicable: true, applicabilityRationale: 'Visible in changed code',
        selectionFactors: factors, selectionRationale: 'Synthetic evidence', confidence: { level: 'high', rationale: 'Explicit source', uncertainties: [] },
        categories: ['implementation'], existingCoverage: { score: 0, rationale: 'Synthetic independent requirement' } }],
    })) } });
  const placement = connection.get(`SELECT surface.code, section.heading FROM guidance_surfaces surface
    JOIN guidance_sections section ON section.surface_id = surface.id WHERE surface.code = 'implementation' ORDER BY section.ordinal LIMIT 1`);
  await executeNativeDownstream(connection, { binding, runId: run.runId, sourceProfileId: profiles.assessment,
    reconciliationProfileId: profiles.reconciliation, adjudicationProfileId: profiles.adjudication, expectedHeadRunId: null }, inputs,
  async (request, { phase }) => {
    const input = JSON.parse(request.serializedInput);
    if (phase === 'routing' || phase === 'consolidation') return { schemaVersion: 4, stage: 'reconciliation', phase,
      components: [...input.assessments.map(member => ({ assessmentResultIds: [member.assessmentResultId], ruleVersionIds: [], semanticSummary: 'Synthetic independent requirement' })),
        ...input.ruleVersionIds.map(id => ({ assessmentResultIds: [], ruleVersionIds: [id], semanticSummary: 'Preserve independent baseline rule' }))] };
    if (phase === 'synthesis') return { schemaVersion: 4, stage: 'reconciliation', phase,
      groups: input.assessments.map(member => ({ title: 'Synthetic launch requirement', semanticSummary: 'Preserve captured requirement',
        continuity: newGroupContinuity(), relatedCoverage: [],
        synthesisRationale: 'Source-grounded synthetic result', wording: `Review synthetic requirement ${member.assessmentResultId}.`,
        selectionFactors: factors, selectionRationale: 'Synthetic evidence', reviewState: 'recommended', needsReview: false,
        members: [{ assessmentResultId: member.assessmentResultId, role: 'primary', coverageRationale: 'Preserves captured requirement' }],
        operations: [{ role: 'primary', action: 'add', targetRuleVersionId: null, surfaceCode: placement.code, sectionHeading: placement.heading,
          rationale: 'Synthetic independent requirement', relationship: null, provenanceCodes: ['local-safeguard'], evidenceCodes: [], applicabilityCodes: [] }],
      })), dispositions: input.assessments.map(member => ({ assessmentResultId: member.assessmentResultId, code: 'grouped', rationale: 'Preserved in final wording' })) };
    return independentAdjudication(input);
  }, report, 3, audit);
  assert.equal(readNativeWorkspaceReadiness(connection, { binding }).ready, true);
  return run;
}

test('required repository guidance validates manual files without requiring a catalog', async context => {
  const root = mkdtempSync(join(tmpdir(), 'workbench-required-guidance-'));
  context.after(() => rmSync(root, { recursive: true, force: true }));
  mkdirSync(join(root, 'guidance'));
  const relativePaths = ['guidance/implementation.instructions.md', 'guidance/testing.instructions.md',
    'guidance/documentation.instructions.md', 'guidance/repository.md', 'guidance/SKILL.md'];
  const content = '# Synthetic guidance\n\nReview the supplied evidence.\n';
  const capacity = { policy: { charactersPerToken: 4, safetyMarginPercent: 25 },
    buckets: relativePaths.map((relativePath, index) => ({ bucketId: index + 1, relativePath })) };
  for (const relativePath of relativePaths) writeFileSync(join(root, relativePath), content);
  const valid = await readRequiredGuidance(capacity, { root });
  assert.equal(valid.available, true);
  assert.equal(valid.source, 'repository-guidance-files');
  assert.deepEqual(valid.failures, []);
  assert.equal(valid.files.length, relativePaths.length);
  assert.equal(Object.hasOwn(valid, 'catalogSha256'), false);
  assert.equal(existsSync(join(root, 'copilot-rule-catalog')), false);
  const unpublished = await readPublishedGuidance(capacity, { root });
  assert.equal(unpublished.available, true);
  assert.equal(unpublished.catalogState, 'unpublished');
  assert.equal(unpublished.catalogSha256, null);
  assert.equal(unpublished.catalogRuleCount, null);
  mkdirSync(join(root, 'copilot-rule-catalog'));
  const catalogPath = join(root, 'copilot-rule-catalog/instruction-catalog.json');
  writeFileSync(catalogPath, 'Legacy artifacts are not catalog authority.');
  assert.deepEqual(await readPublishedGuidance(capacity, { root }), unpublished);
  const catalogBytes = JSON.stringify({ schemaVersion: 4, rules: [{ id: 'SYN-RULE-001' }] });
  const catalog = { contentSha256: createHash('sha256').update(catalogBytes).digest('hex'), rules: [{ id: 'SYN-RULE-001' }] };
  writeFileSync(catalogPath, catalogBytes);
  mkdirSync(join(root, 'copilot-rule-catalog/staged'));
  writeFileSync(join(root, 'copilot-rule-catalog/staged/instruction-catalog.json'), catalogBytes);
  assert.equal((await readPublishedGuidance(capacity, { root, catalog })).reason, 'published-catalog-missing');
  assert.deepEqual(await readPublishedGuidance(capacity, { root }), unpublished);
  mkdirSync(join(root, 'copilot-rule-catalog/published'));
  const publishedCatalogPath = join(root, 'copilot-rule-catalog/published/instruction-catalog.json');
  writeFileSync(publishedCatalogPath, catalogBytes);
  const published = await readPublishedGuidance(capacity, { root, catalog });
  assert.equal(published.available, true);
  assert.equal(published.catalogState, 'published');
  assert.equal(published.catalogSha256, catalog.contentSha256);
  assert.equal(published.catalogRuleCount, 1);
  writeFileSync(publishedCatalogPath, 'Changed after publication.');
  assert.equal((await readPublishedGuidance(capacity, { root, catalog })).reason, 'published-catalog-mismatch');
  rmSync(publishedCatalogPath);
  assert.equal((await readPublishedGuidance(capacity, { root, catalog })).reason, 'published-catalog-missing');
  assert.equal((await readPublishedGuidance(capacity, { root })).available, true);
  for (const file of valid.files) {
    assert.equal(file.contentSha256, createHash('sha256').update(content).digest('hex'));
    assert.equal(file.currentGuardedTokens, Math.ceil(Math.ceil(content.length / 4) * 1.25));
    assert.equal(Object.hasOwn(file, 'path'), false);
  }
  for (const relativePath of relativePaths) {
    rmSync(join(root, relativePath));
    const missing = await readRequiredGuidance(capacity, { root });
    assert.equal(missing.available, false);
    assert.deepEqual(missing.failures, [{ relativePath, reason: 'missing' }]);
    writeFileSync(join(root, relativePath), content);
  }
  const relativePath = relativePaths[0];
  for (const [invalid, reason] of [[Buffer.from([0xc3, 0x28]), 'invalid-utf8'], [' \n', 'invalid-content'], ['invalid\0content', 'invalid-content']]) {
    writeFileSync(join(root, relativePath), invalid);
    const result = await readRequiredGuidance(capacity, { root });
    assert.equal(result.available, false);
    assert.deepEqual(result.failures, [{ relativePath, reason }]);
  }
  rmSync(join(root, relativePath));
  mkdirSync(join(root, relativePath));
  const unreadable = await readRequiredGuidance(capacity, { root });
  assert.deepEqual(unreadable.failures, [{ relativePath, reason: 'unreadable' }]);
});

test('native launch readiness blocks HTTP startup for incomplete SQL without mutation', async context => {
  const { startWorkbenchNewServer, WorkbenchNewLaunchError } = await import('../../modules/workbench/WorkbenchNewServer.mjs');
  const directory = mkdtempSync(join(tmpdir(), 'workbench-new-refusal-'));
  const databasePath = join(directory, 'workspace.sqlite');
  context.after(() => rmSync(directory, { recursive: true, force: true }));
  const writer = openWorkbenchSqlite({ mode: 'create', databasePath });
  let initialized;
  try { migrateNewWorkbenchApplication(writer); initialized = initializeNativeWorkspace(writer, nativeCatalogRequest()); }
  finally { writer.close(); }
  const reader = openWorkbenchSqlite({ mode: 'read-only', databasePath });
  const before = createHash('sha256').update(readFileSync(databasePath)).digest('hex');
  try {
    const binding = { databaseGuid: initialized.databaseGuid, repositoryId: initialized.repositoryId, branchRef: initialized.branchRef };
    await assert.rejects(startWorkbenchNewServer({ connection: reader, binding, port: 0 }), error =>
      error instanceof WorkbenchNewLaunchError && error.checks.some(check => check.name === 'completed-analysis' && check.status === 'failed'));
    assert.equal(createHash('sha256').update(readFileSync(databasePath)).digest('hex'), before);
  } finally { reader.close(); }
});

test('Workbench New HTTP reads use an isolated launch token and never accept URL database selection', async context => {
  const { startWorkbenchNewServer } = await import('../../modules/workbench/WorkbenchNewServer.mjs');
  const directory = mkdtempSync(join(tmpdir(), 'workbench-new-http-'));
  const databasePath = join(directory, 'workspace.sqlite');
  let reader;
  let instance;
  context.after(async () => {
    if (instance) await instance.close();
    reader?.close();
    rmSync(directory, { recursive: true, force: true });
  });
  const writer = openWorkbenchSqlite({ mode: 'create', databasePath });
  let initialized;
  try {
    migrateNewWorkbenchApplication(writer);
    initialized = initializeNativeWorkspace(writer, nativeCatalogRequest());
    await completeNativeCatalogFixture(writer, { databaseGuid: initialized.databaseGuid, repositoryId: initialized.repositoryId, branchRef: initialized.branchRef });
  } finally { writer.close(); }
  reader = openWorkbenchSqlite({ mode: 'read-only', databasePath });
  let sqlCalls = 0;
  const observed = { ...reader,
    all(...parameters) { sqlCalls++; return reader.all(...parameters); },
    get(...parameters) { sqlCalls++; return reader.get(...parameters); },
  };
  Object.defineProperty(observed, 'isTransaction', { get: () => reader.isTransaction });
  const binding = { databaseGuid: initialized.databaseGuid, repositoryId: initialized.repositoryId, branchRef: initialized.branchRef };
  const targetRepository = { status: 'validated', repository: 'synthetic/provider-fork', branch: 'main', commit: 'a'.repeat(40),
    upstreamRepository: 'synthetic/provider', upstreamBranch: 'main', aheadBy: 2, behindBy: 3, reason: null };
  instance = await startWorkbenchNewServer({ connection: observed, binding, port: 0, targetRepository });
  const before = createHash('sha256').update(readFileSync(databasePath)).digest('hex');
  const configResponse = await fetch(instance.url + 'runtime-config');
  assert.equal(configResponse.status, 200);
  const config = await configResponse.json();
  assert.ok(typeof config.operationToken === 'string' && config.operationToken.length === 64);
  assert.equal(config.capabilities.save, false);
  assert.deepEqual(config.targetRepository, targetRepository);
  const markup = await (await fetch(instance.url)).text();
  assert.equal((markup.match(/rel="stylesheet"/g) ?? []).length, 1);
  assert.match(markup, /href="styles\.css"/);
  assert.equal((await fetch(instance.url + 'styles.css')).status, 200);
  assert.equal((await fetch(instance.url + 'native.css')).status, 404);
  for (const request of [
    { path: 'api/workspace', headers: {}, status: 403 },
    { path: 'api/workspace', headers: { 'X-Workbench-Operation-Token': 'synthetic-previous-launch' }, status: 403 },
    { path: 'api/workspace?token=synthetic-token-in-url', headers: {}, status: 403 },
    { path: 'api/workspace?databasePath=synthetic.sqlite', status: 400 },
    { path: 'api/workspace', method: 'POST', status: 405 },
    { path: 'api/workspace', headers: { Origin: 'https://example.com' }, status: 403 },
  ]) {
    const callsBefore = sqlCalls;
    const response = await fetch(instance.url + request.path, {
      method: request.method ?? 'GET', headers: request.headers ?? { 'X-Workbench-Operation-Token': config.operationToken },
    });
    assert.equal(response.status, request.status);
    await response.arrayBuffer();
    assert.equal(sqlCalls, callsBefore);
  }
  const callsBeforeRead = sqlCalls;
  const response = await fetch(instance.url + 'api/workspace', { headers: { 'X-Workbench-Operation-Token': config.operationToken } });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  const view = await response.json();
  assert.equal(view.analysis.status, 'complete');
  assert.equal(view.sources.length, 6);
  assert.ok(view.sources.every(source => Object.hasOwn(source, 'originRef') && source.originRef === null));
  assert.equal(view.publishedCatalog.rules.length, 6);
  assert.ok(sqlCalls > callsBeforeRead);
  assert.equal(createHash('sha256').update(readFileSync(databasePath)).digest('hex'), before);
  assert.equal(reader.isTransaction, false);
});

test('Workbench New HTTP Save authenticates before mutation and persists versioned SQL changes', async context => {
  const { startWorkbenchNewServer } = await import('../../modules/workbench/WorkbenchNewServer.mjs');
  const { saveSourceChange, updatePlanMembership } = await import('../../modules/workbench/WorkbenchChanges.mjs');
  const directory = mkdtempSync(join(tmpdir(), 'workbench-new-save-'));
  const databasePath = join(directory, 'workspace.sqlite');
  const writer = openWorkbenchSqlite({ mode: 'create', databasePath });
  let reader;
  let instance;
  context.after(async () => { if (instance) await instance.close(); reader?.close(); rmSync(directory, { recursive: true, force: true }); });
  let initialized;
  try {
    migrateNewWorkbenchApplication(writer);
    initialized = initializeNativeWorkspace(writer, nativeCatalogRequest());
    await completeNativeCatalogFixture(writer, { databaseGuid: initialized.databaseGuid, repositoryId: initialized.repositoryId, branchRef: initialized.branchRef });
  }
  finally { writer.close(); }
  reader = openWorkbenchSqlite({ mode: 'read-only', databasePath });
  const binding = { databaseGuid: initialized.databaseGuid, repositoryId: initialized.repositoryId, branchRef: initialized.branchRef };
  let writes = 0;
  instance = await startWorkbenchNewServer({ connection: reader, binding, port: 0, saveChanges: input => {
    writes++;
    const writable = openWorkbenchSqlite({ mode: 'read-write', databasePath });
    try { saveSourceChange(writable, binding, input); return readNativeWorkspaceView(writable, { binding }); }
    finally { writable.close(); }
  }, changePlan: input => {
    writes++;
    const writable = openWorkbenchSqlite({ mode: 'read-write', databasePath });
    try { updatePlanMembership(writable, binding, input); return readNativeWorkspaceView(writable, { binding }); }
    finally { writable.close(); }
  } });
  const config = await (await fetch(instance.url + 'runtime-config')).json();
  assert.equal(config.capabilities.save, true);
  assert.equal(config.capabilities.plan, true);
  const source = readNativeWorkspaceView(reader, { binding }).sources[0];
  const input = { sourceVersionId: source.sourceVersionId, expectedRevisionId: null, wording: 'Saved over authenticated HTTP: ' + '\u00e9'.repeat(70000), rationale: 'Synthetic operator rationale.' };
  const headers = { 'Content-Type': 'application/json', 'X-Workbench-Operation-Token': config.operationToken };
  for (const attempt of [
    { headers: { 'Content-Type': 'application/json' }, status: 403 },
    { path: 'api/plan', headers: { 'Content-Type': 'application/json' }, status: 403 },
    { headers: { ...headers, Origin: 'https://example.com' }, status: 403 },
    { path: 'api/changes?databasePath=other.sqlite', headers, status: 400 },
    { headers: { ...headers, 'Content-Type': 'text/plain' }, status: 400 },
  ]) {
    const response = await fetch(instance.url + (attempt.path ?? 'api/changes'), { method: 'POST', headers: attempt.headers, body: JSON.stringify(input) });
    assert.equal(response.status, attempt.status);
    await response.arrayBuffer();
    assert.equal(writes, 0);
  }
  const saved = await fetch(instance.url + 'api/changes', { method: 'POST', headers, body: JSON.stringify(input) });
  assert.equal(saved.status, 200);
  const view = await saved.json();
  assert.equal(view.changes[0].wording, input.wording);
  const stale = await fetch(instance.url + 'api/changes', { method: 'POST', headers, body: JSON.stringify(input) });
  assert.equal(stale.status, 409);
  await stale.arrayBuffer();
  assert.equal(readNativeWorkspaceView(reader, { binding }).changes.length, 1);
  const [surface] = view.publishedCatalog.surfaces;
  const planInput = { changeId: view.changes[0].changeId, expectedRevisionId: view.changes[0].revisionId,
    expectedPlanVersionId: null, operation: 'add', action: 'add', targetRuleVersionId: null, surface: surface.code, sectionHeading: surface.sections[0] };
  const planned = await fetch(instance.url + 'api/plan', { method: 'POST', headers, body: JSON.stringify(planInput) });
  assert.equal(planned.status, 200);
  const plannedView = await planned.json();
  assert.equal(plannedView.plans[0].items.length, 1);
  assert.equal(plannedView.plans[0].items[0].wording, input.wording);
  assert.deepEqual(reader.all('PRAGMA foreign_key_check'), []);
});

test('Exit audit links the USER request and SYSTEM completion without claiming an implicit save', () => {
  const connection = openWorkbenchSqlite({ mode: 'memory' });
  try {
    migrateNewWorkbenchApplication(connection);
    const initialized = initializeNativeWorkspace(connection, nativeCatalogRequest());
    const binding = { databaseGuid: initialized.databaseGuid, repositoryId: initialized.repositoryId, branchRef: initialized.branchRef };
    const facts = { binding, correlationGuid: '00000000-0000-4000-8000-000000000044', requestedPort: 0, listenerPort: 43143, elapsedMs: 0 };
    const { binding: bound, correlationGuid, ...exitFacts } = facts;
    recordWorkbenchAudit(connection, { binding: bound, correlationGuid, rootActionCode: 'exit-workbench', actionCode: 'exit-workbench',
      rootRequest: true, outcome: 'started', facts: { ...exitFacts, stateSaveOutcome: 'unknown' } });
    recordWorkbenchAudit(connection, { binding: bound, correlationGuid, rootActionCode: 'exit-workbench', actionCode: 'exit-workbench',
      outcome: 'succeeded', facts: { ...exitFacts, elapsedMs: 12, stateSaveOutcome: 'unknown' } });
    const events = connection.all(`SELECT event.outcome, event.correlation_id AS correlationId, event.state_save_outcome AS stateSaveOutcome,
      event.requested_port AS requestedPort, event.listener_port AS listenerPort, event.elapsed_ms AS elapsedMs,
      actor.actor_kind AS actorKind, actor.provider_code AS providerCode, actor.provider_actor_id AS providerActorId,
      category.code AS category, action.code AS action, correlation.correlation_guid AS correlationGuid
      FROM audit_events event JOIN actors actor ON actor.id = event.actor_id
      JOIN audit_categories category ON category.id = event.category_id
      JOIN audit_actions action ON action.id = event.action_id
      JOIN audit_correlations correlation ON correlation.id = event.correlation_id
      ORDER BY event.id`);
    assert.deepEqual(events.map(event => event.outcome), ['started', 'succeeded']);
    assert.deepEqual(events.map(event => event.actorKind), ['person', 'system']);
    assert.equal(events[0].providerCode, 'local-workbench');
    assert.equal(events[0].providerActorId, 'operator');
    assert.equal(events[1].providerActorId, null);
    assert.ok(Number.isSafeInteger(events[0].correlationId));
    assert.equal(events[0].correlationId, events[1].correlationId);
    assert.ok(events.every(event => event.correlationGuid === facts.correlationGuid && event.category === 'workbench' &&
      event.action === 'exit-workbench' && event.stateSaveOutcome === 'unknown' && event.requestedPort === 0 && event.listenerPort === 43143));
    assert.equal(events[1].elapsedMs, 12);
    assert.throws(() => connection.exec('DELETE FROM audit_correlations'), /append-only/);
    assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
  } finally { connection.close(); }
});

test('Exit audit rolls back missing events and preserves uncertain commit acknowledgement', () => {
  const connection = openWorkbenchSqlite({ mode: 'memory' });
  try {
    migrateNewWorkbenchApplication(connection);
    const initialized = initializeNativeWorkspace(connection, nativeCatalogRequest());
    const facts = { binding: { databaseGuid: initialized.databaseGuid, repositoryId: initialized.repositoryId, branchRef: initialized.branchRef },
      correlationGuid: '00000000-0000-4000-8000-000000000044', rootActionCode: 'exit-workbench', actionCode: 'exit-workbench',
      rootRequest: true, facts: { requestedPort: 0, listenerPort: 43143, elapsedMs: 0 }, outcome: 'started' };
    connection.exec(`CREATE TRIGGER reject_exit_audit BEFORE INSERT ON audit_events WHEN NEW.action_code = 'exit-workbench'
      BEGIN SELECT RAISE(ABORT, 'Synthetic audit write failure'); END`);
    assert.throws(() => recordWorkbenchAudit(connection, facts), error => error.auditPersistence === 'not-recorded');
    assert.equal(connection.get('SELECT count(*) AS count FROM audit_correlations').count, 0);
    assert.equal(connection.isTransaction, false);
    connection.exec('DROP TRIGGER reject_exit_audit');
    const uncertain = { ...connection, exec(sql) {
      connection.exec(sql);
      if (sql === 'COMMIT') throw new Error('Synthetic lost commit acknowledgement');
    } };
    Object.defineProperty(uncertain, 'isTransaction', { get: () => connection.isTransaction });
    assert.throws(() => recordWorkbenchAudit(uncertain, facts), error => error.auditPersistence === 'uncertain');
    assert.equal(connection.get("SELECT count(*) AS count FROM audit_events WHERE action_code = 'exit-workbench'").count, 1);
    assert.equal(connection.isTransaction, false);
  } finally { connection.close(); }
});

test('Workbench New Exit closes the real listener independently of audit persistence', async context => {
  const { startWorkbenchNewServer } = await import('../../modules/workbench/WorkbenchNewServer.mjs');
  for (const scenario of ['recorded', 'terminal-failure', 'request-failure']) await context.test(scenario, async context => {
    const directory = mkdtempSync(join(tmpdir(), 'workbench-new-exit-'));
    const databasePath = join(directory, 'workspace.sqlite');
    let reader;
    let instance;
    context.after(async () => { if (instance) await instance.close(); reader?.close(); rmSync(directory, { recursive: true, force: true }); });
    const writer = openWorkbenchSqlite({ mode: 'create', databasePath });
    let initialized;
    try {
      migrateNewWorkbenchApplication(writer);
      initialized = initializeNativeWorkspace(writer, nativeCatalogRequest());
      await completeNativeCatalogFixture(writer, { databaseGuid: initialized.databaseGuid, repositoryId: initialized.repositoryId, branchRef: initialized.branchRef });
    } finally { writer.close(); }
    reader = openWorkbenchSqlite({ mode: 'read-only', databasePath });
    const binding = { databaseGuid: initialized.databaseGuid, repositoryId: initialized.repositoryId, branchRef: initialized.branchRef };
    instance = await startWorkbenchNewServer({ connection: reader, binding, port: 0, databasePath });
    if (scenario !== 'recorded') {
      const failure = openWorkbenchSqlite({ mode: 'read-write', databasePath });
      try {
        failure.exec(`CREATE TRIGGER reject_exit_audit BEFORE INSERT ON audit_events
          WHEN NEW.action_code = 'exit-workbench' ${scenario === 'terminal-failure' ? "AND NEW.outcome = 'succeeded'" : ''}
          BEGIN SELECT RAISE(ABORT, 'Synthetic audit write failure'); END`);
      } finally { failure.close(); }
    }
    const config = await (await fetch(instance.url + 'runtime-config')).json();
    const headers = { 'X-Workbench-Operation-Token': config.operationToken };
    for (const attempt of [
      { method: 'POST', headers: {}, status: 403 },
      { method: 'GET', headers, status: 405 },
      { method: 'POST', headers: { ...headers, Origin: 'https://example.com' }, status: 403 },
    ]) {
      const response = await fetch(instance.url + 'shutdown', attempt);
      assert.equal(response.status, attempt.status);
      await response.arrayBuffer();
      assert.equal(reader.get('SELECT count(*) AS count FROM audit_correlations').count, 0);
      assert.equal(instance.server.listening, true);
    }
    const response = await fetch(instance.url + 'shutdown', { method: 'POST', headers });
    assert.equal(response.status, 200);
    const result = await response.json();
    assert.equal(result.status, 'closed');
    assert.equal(result.listenerStopped, true);
    assert.equal(result.stateSaveOutcome, 'unknown');
    assert.equal(result.audit.persistence, scenario === 'recorded' ? 'recorded' : 'not-recorded');
    assert.match(result.audit.correlationGuid, /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
    assert.equal(instance.server.listening, false);
    await assert.rejects(fetch(instance.url, { signal: AbortSignal.timeout(1000) }));
    const events = reader.all(`SELECT event.outcome, correlation.correlation_guid AS correlationGuid
      FROM audit_events event JOIN audit_correlations correlation ON correlation.id = event.correlation_id ORDER BY event.id`);
    assert.deepEqual(events.map(event => event.outcome), scenario === 'recorded' ? ['started', 'succeeded'] : scenario === 'terminal-failure' ? ['started'] : []);
    assert.ok(events.every(event => event.correlationGuid === result.audit.correlationGuid));
    assert.equal(readNativeWorkspaceView(reader, { binding }).analysis.status, 'complete');
    assert.equal(reader.isTransaction, false);
  });
});

function nativeAuditFixture(context, request = nativeCatalogRequest()) {
  const directory = mkdtempSync(join(tmpdir(), 'workbench-operational-audit-'));
  const databasePath = join(directory, 'workspace.sqlite');
  const connection = openWorkbenchSqlite({ mode: 'create', databasePath });
  context.after(() => { connection.close(); rmSync(directory, { recursive: true, force: true }); });
  migrateNewWorkbenchApplication(connection);
  const initialized = initializeNativeWorkspace(connection, request);
  const binding = { databaseGuid: initialized.databaseGuid, repositoryId: initialized.repositoryId, branchRef: initialized.branchRef };
  return { connection, databasePath, binding };
}

test('shared operational audit carries one correlation and distinct owning categories across processes', async context => {
  const { connection, databasePath, binding } = nativeAuditFixture(context);
  const audit = createWorkbenchAudit({ databasePath, binding, actionCode: 'assess' });
  audit.start();
  const run = await completeNativeCatalogFixture(connection, binding);
  audit.transition('reconcile', { runId: run.runId, itemCount: 6 });
  const script = `
    import { readFileSync } from 'node:fs';
    const { createWorkbenchAudit } = await import(process.argv[1]);
    const selected = JSON.parse(readFileSync(0, 'utf8'));
    const audit = createWorkbenchAudit(selected);
    audit.transition('adjudicate', { runId: selected.runId, itemCount: 6 });
    audit.finish('succeeded', { runId: selected.runId, itemCount: 0 });
    console.log(JSON.stringify({ context: audit.snapshot(), warning: audit.takeWarning() }));`;
  const output = execFileSync(process.execPath, ['--input-type=module', '-e', script,
    new URL('../../modules/workbench/WorkbenchAudit.mjs', import.meta.url).href], {
    encoding: 'utf8', input: JSON.stringify({ databasePath, binding, actionCode: 'assess', context: audit.snapshot(), runId: run.runId }),
    timeout: 15000, stdio: ['pipe', 'pipe', 'pipe'],
  });
  const recorded = JSON.parse(output);
  assert.equal(recorded.context.persistence, 'recorded');
  assert.equal(recorded.warning, null);
  const events = connection.all(`SELECT event.action_code AS action, event.outcome, category.code AS category, actor.actor_kind AS actor,
    correlation.correlation_guid AS guid, root.code AS rootAction FROM audit_events event
    JOIN audit_categories category ON category.id = event.category_id JOIN actors actor ON actor.id = event.actor_id
    JOIN audit_correlations correlation ON correlation.id = event.correlation_id JOIN audit_actions root ON root.id = correlation.action_id ORDER BY event.id`);
  assert.deepEqual(events.map(event => [event.action, event.outcome, event.category]), [
    ['assess', 'started', 'assessment'], ['assess', 'succeeded', 'assessment'],
    ['reconcile', 'started', 'reconciliation'], ['reconcile', 'succeeded', 'reconciliation'],
    ['adjudicate', 'started', 'adjudication'], ['adjudicate', 'succeeded', 'adjudication'],
  ]);
  assert.deepEqual(events.map(event => event.actor), ['person', 'system', 'system', 'system', 'system', 'system']);
  assert.ok(events.every(event => event.guid === audit.result().correlationGuid && event.rootAction === 'assess'));
  assert.equal(connection.get('SELECT count(*) AS count FROM audit_targets WHERE analysis_run_id = ?', [run.runId]).count, 5);
  assert.throws(() => connection.run("UPDATE audit_categories SET code = 'renamed' WHERE code = 'assessment'"), /append-only/);
  const resume = createWorkbenchAudit({ databasePath, binding, actionCode: 'assess' });
  resume.start('assess', { runId: run.runId });
  resume.finish('reused', { runId: run.runId, itemCount: 6 });
  assert.notEqual(resume.result().correlationGuid, audit.result().correlationGuid);
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
});

test('shared operational audit failure cannot roll back confirmed native analysis or erase earlier degradation', async context => {
  for (const failedOutcome of ['started', 'succeeded']) await context.test(failedOutcome, async context => {
    const { connection, databasePath, binding } = nativeAuditFixture(context);
    connection.exec(`CREATE TRIGGER reject_operational_audit BEFORE INSERT ON audit_events WHEN NEW.correlation_id IS NOT NULL AND NEW.outcome = '${failedOutcome}'
      BEGIN SELECT RAISE(ABORT, 'Synthetic audit failure'); END`);
    const audit = createWorkbenchAudit({ databasePath, binding, actionCode: 'assess' });
    audit.start();
    const result = await audit.run(async () => {
      assert.equal(connection.isTransaction, false);
      const run = await completeNativeCatalogFixture(connection, binding);
      audit.finish('succeeded', { runId: run.runId, itemCount: 6 });
      return run;
    });
    assert.equal(readNativeWorkspaceView(connection, { binding }).analysis.runId, result.runId);
    assert.equal(readNativeWorkspaceView(connection, { binding }).analysis.status, 'complete');
    assert.equal(audit.result().persistence, 'not-recorded');
    const warning = audit.takeWarning();
    assert.equal(warning.correlationGuid, audit.result().correlationGuid);
    assert.equal(warning.persistence, 'not-recorded');
    assert.equal(audit.takeWarning(), null);
    connection.exec('DROP TRIGGER reject_operational_audit');
    const continued = createWorkbenchAudit({ databasePath, binding, actionCode: 'assess', context: audit.snapshot() });
    continued.start('reconcile', { runId: result.runId });
    continued.finish('reused', { runId: result.runId });
    assert.equal(continued.result().persistence, 'not-recorded');
    assert.equal(continued.takeWarning(), null);
    assert.equal(connection.isTransaction, false);
    assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
  });
});

test('shared operational audit preserves primary failures and atomically rolls back rejected typed targets', async context => {
  const { connection, databasePath, binding } = nativeAuditFixture(context);
  const run = await completeNativeCatalogFixture(connection, binding);
  const audit = createWorkbenchAudit({ databasePath, binding, actionCode: 'reconcile' });
  audit.start();
  connection.exec(`CREATE TRIGGER reject_operational_target BEFORE INSERT ON audit_targets WHEN NEW.analysis_run_id IS NOT NULL
    BEGIN SELECT RAISE(ABORT, 'Synthetic target failure'); END`);
  audit.finish('succeeded', { runId: run.runId });
  assert.equal(audit.result().persistence, 'not-recorded');
  assert.deepEqual(connection.all('SELECT outcome FROM audit_events WHERE correlation_id IS NOT NULL').map(row => row.outcome), ['started']);
  assert.equal(connection.get('SELECT count(*) AS count FROM audit_targets WHERE analysis_run_id IS NOT NULL').count, 0);
  connection.exec(`CREATE TRIGGER reject_operational_failure BEFORE INSERT ON audit_events WHEN NEW.outcome = 'failed'
    BEGIN SELECT RAISE(ABORT, 'Synthetic secondary failure'); END`);
  const failed = createWorkbenchAudit({ databasePath, binding, actionCode: 'assess' });
  failed.start();
  const primary = new Error('Synthetic domain failure');
  await assert.rejects(failed.run(async () => { throw primary; }), error => error === primary);
  assert.equal(failed.result().persistence, 'not-recorded');
  assert.equal(failed.takeWarning().kind, 'audit-warning');
  assert.equal(connection.isTransaction, false);
});

test('shared operational audit retains uncertain transport state after acknowledged later writes', context => {
  const { connection, databasePath, binding } = nativeAuditFixture(context);
  const audit = createWorkbenchAudit({ databasePath, binding, actionCode: 'assess' });
  audit.start();
  const uncertain = createWorkbenchAudit({ databasePath, binding, actionCode: 'assess',
    context: { ...audit.snapshot(), persistence: 'uncertain' } });
  uncertain.finish('succeeded');
  assert.equal(uncertain.result().persistence, 'uncertain');
  assert.equal(uncertain.takeWarning().persistence, 'uncertain');
  assert.equal(uncertain.takeWarning(), null);
  assert.equal(connection.get("SELECT count(*) AS count FROM audit_events WHERE outcome = 'succeeded'").count, 1);
});

test('native downstream operational audit follows major stages rather than batches or progress ticks', async context => {
  const { connection, databasePath, binding } = nativeAuditFixture(context);
  const audit = createWorkbenchAudit({ databasePath, binding, actionCode: 'reconcile' });
  audit.start();
  const progress = [];
  const run = await audit.run(() => completeNativeCatalogFixture(connection, binding, audit, event => progress.push(event)));
  audit.finish('succeeded', { runId: run.runId });
  assert.equal(audit.result().persistence, 'recorded');
  assert.deepEqual(connection.all(`SELECT action_code AS action, outcome FROM audit_events WHERE correlation_id IS NOT NULL ORDER BY id`).map(row =>
    [row.action, row.outcome]), [['reconcile', 'started'], ['reconcile', 'succeeded'], ['adjudicate', 'started'], ['adjudicate', 'succeeded']]);
  assert.equal(connection.get('SELECT count(*) AS count FROM audit_correlations').count, 1);
  assert.ok(progress.length > 4);
  assert.ok(progress.some(event => event.state === 'running') && progress.some(event => event.state === 'passed'));
  assert.equal(readNativeWorkspaceView(connection, { binding }).analysis.status, 'complete');
});

test('native audit PowerShell adapter preserves the exit status and separates one safe warning from JSON output', async context => {
  const request = nativeCatalogRequest();
  const repositoryRoot = resolve(fileURLToPath(new URL('../../../../', import.meta.url)));
  request.repository.canonicalName = 'local:' + createHash('sha256').update(repositoryRoot).digest('hex');
  request.repository.branchRef = execFileSync('git', ['-C', repositoryRoot, 'symbolic-ref', '--quiet', 'HEAD'], { encoding: 'utf8' }).trim();
  const { connection, databasePath, binding } = nativeAuditFixture(context, request);
  const run = await completeNativeCatalogFixture(connection, binding);
  const script = `
    $ErrorActionPreference = 'Stop'
    $WarningPreference = 'Stop'
    $selected = [Console]::In.ReadToEnd() | ConvertFrom-Json
    Import-Module $selected.modulePath -Force
    $global:LASTEXITCODE = 17
    $records = @(& {
      $audit = New-WorkbenchAudit -DatabasePath $selected.databasePath -DatabaseGuid $selected.databaseGuid -ActionCode $selected.actionCode -Facts @{ runId = [int]$selected.runId }
      Invoke-WorkbenchAuditTransition -Audit $audit -Transition finish -Outcome reused -Facts @{ runId = [int]$selected.runId }
      [pscustomobject]@{ persistence = $audit.Context.persistence; correlationGuid = $audit.CorrelationGuid; domainExitCode = $global:LASTEXITCODE }
    } 3>&1)
    $result = @($records | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })[0]
    $result | Add-Member -NotePropertyName warningCount -NotePropertyValue @($records | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count
    $result | ConvertTo-Json -Compress`;
  for (const scenario of ['recorded', 'missing-store', 'unreadable-reply']) {
    const selectedPath = scenario === 'missing-store' ? join(databasePath, '..', 'missing.sqlite') : databasePath;
    const result = JSON.parse(execFileSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', script], {
      encoding: 'utf8', input: JSON.stringify({ databasePath: selectedPath, databaseGuid: binding.databaseGuid, runId: run.runId,
        actionCode: scenario === 'unreadable-reply' ? 'synthetic-unregistered-action' : 'assess',
        modulePath: fileURLToPath(new URL('../../modules/workbench/Workbench.Audit.psm1', import.meta.url)) }),
      timeout: 30000, stdio: ['pipe', 'pipe', 'pipe'],
    }));
    assert.equal(result.persistence, scenario === 'recorded' ? 'recorded' : scenario === 'missing-store' ? 'not-recorded' : 'uncertain');
    assert.equal(result.warningCount, scenario === 'recorded' ? 0 : 1);
    assert.equal(result.domainExitCode, 17);
    assert.match(result.correlationGuid, /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/);
    if (scenario === 'missing-store') assert.equal(existsSync(selectedPath), false);
    if (scenario === 'unreadable-reply') assert.equal(connection.get('SELECT count(*) AS count FROM audit_correlations WHERE correlation_guid = ?', [result.correlationGuid]).count, 0);
  }
});

test('native workspace read command reconstructs initialized facts without writing or inferring analysis', context => {
  const directory = mkdtempSync(join(tmpdir(), 'workbench-read-view-'));
  context.after(() => rmSync(directory, { recursive: true, force: true }));
  const databasePath = join(directory, 'workspace.sqlite');
  const connection = openWorkbenchSqlite({ mode: 'create', databasePath });
  const request = nativeCatalogRequest();
  let initialized;
  try {
    migrateNewWorkbenchApplication(connection);
    initialized = initializeNativeWorkspace(connection, request);
  } finally { connection.close(); }
  const binding = { databaseGuid: initialized.databaseGuid, repositoryId: initialized.repositoryId, branchRef: initialized.branchRef };
  const fingerprint = () => createHash('sha256').update(readFileSync(databasePath)).digest('hex');
  const before = fingerprint();
  const read = selectedBinding => {
    try {
      return JSON.parse(execFileSync(process.execPath, [databaseBridgePath, 'read-workspace', databasePath],
        { input: JSON.stringify({ binding: selectedBinding }), encoding: 'utf8', timeout: 10000, stdio: ['pipe', 'pipe', 'pipe'] }));
    } catch (error) {
      if (String(error.stderr).includes('Bound workspace identity does not match the database')) throw new Error('Workspace identity does not match the database');
      throw new Error('Native read command failed; command arguments and private diagnostic details omitted');
    }
  };
  const view = read(binding);
  assert.equal(view.analysis.status, 'not-started');
  assert.equal(view.analysis.runId, null);
  assert.equal(view.publishedCatalog.catalogId, initialized.catalogId);
  const catalog = JSON.parse(request.catalogJson);
  assert.deepEqual(view.publishedCatalog.rules.map(rule => rule.displayedId), catalog.rules.map(rule => rule.id));
  assert.deepEqual(view.publishedCatalog.rules.map(rule => rule.wording), catalog.rules.map(rule => rule.text));
  assert.deepEqual(view.publishedCatalog.rules.map(rule => rule.provenances), catalog.rules.map(rule => rule.provenance));
  assert.deepEqual(view.publishedCatalog.rules.map(rule => rule.sourceCodes), catalog.rules.map(rule => rule.sourceIds));
  assert.deepEqual(view.publishedCatalog.rules.map(rule => rule.evidenceCodes), catalog.rules.map(rule => rule.evidenceIds));
  assert.deepEqual(view.publishedCatalog.rules.map(rule => rule.canonicalSource.sourceId), catalog.rules.map(rule => rule.id));
  assert.deepEqual(view.publishedCatalog.surfaces.map(surface => surface.sections), catalog.surfaces.map(surface => surface.sections.map(section => section.heading)));
  assert.deepEqual(view.publishedCatalog.evidence.map(evidence => evidence.code), catalog.evidence.map(evidence => evidence.id));
  assert.equal(view.publishedCatalog.protectedRules.length, 1);
  assert.equal(view.sourceLanes.length, 1);
  assert.equal(view.sources.length, 6);
  assert.ok(view.sources.every(source => source.presence === 'present' && source.provenances.includes('local-safeguard')));
  const expectedSources = new Map(catalog.rules.map(rule => [rule.id, rule.text]));
  for (const source of view.sources) assert.equal(source.content, expectedSources.get(source.sourceId));
  assert.deepEqual(view.assessments, []);
  assert.deepEqual(view.groups, []);
  assert.deepEqual(view.findings, []);
  assert.deepEqual(read(binding), view);
  assert.equal(fingerprint(), before);
  assert.throws(() => read({ ...binding, databaseGuid: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' }), /identity does not match/);
  assert.equal(fingerprint(), before);
});

test('native launch readiness accepts complete inputs and rejects stale or missing authorities', async context => {
  const connection = openWorkbenchSqlite({ mode: 'memory' });
  context.after(() => connection.close());
  migrateNewWorkbenchApplication(connection);
  const initialized = initializeNativeWorkspace(connection, nativeCatalogRequest());
  const binding = { databaseGuid: initialized.databaseGuid, repositoryId: initialized.repositoryId, branchRef: initialized.branchRef };
  await completeNativeCatalogFixture(connection, binding);
  const before = connection.get('SELECT total_changes() AS count').count;
  assert.equal(readNativeWorkspaceReadiness(connection, { binding }).ready, true);
  assert.equal(connection.get('SELECT total_changes() AS count').count, before);
  for (const [mutation, checkName] of [
    ['DELETE FROM workspace_publication', 'catalog-baseline'],
    ['DELETE FROM source_collection_heads', 'source-collections'],
    [() => {
      const snapshot = ingestProtectedCapture(connection, { ...nativeCatalogRequest().protectedCapture,
        repositoryContextId: 1, parserContractSha256: 'd'.repeat(64) });
      connection.run('UPDATE workspace_identity SET current_protected_snapshot_id = ? WHERE id = 1', [snapshot.snapshotId]);
    }, 'current-protection'],
    ['DELETE FROM workspace_analysis_head', 'completed-analysis'],
    [() => {
      const configuration = nativeCatalogRequest().profile.llmConfiguration;
      configuration.models[0].modelCode += '-synthetic-revision';
      configureProfileLlms(connection, 1, configuration);
    }, 'current-model-assignments'],
  ]) {
    connection.exec('BEGIN');
    try {
      if (typeof mutation === 'string') connection.exec(mutation);
      else mutation();
      const readiness = readNativeWorkspaceReadiness(connection, { binding });
      assert.equal(readiness.ready, false);
      assert.equal(readiness.checks.find(check => check.name === checkName).status, 'failed');
    } finally { connection.exec('ROLLBACK'); }
  }
  assert.equal(readNativeWorkspaceReadiness(connection, { binding }).ready, true);
});

test('native launch readiness refuses initialized but unanalysed workspaces without mutation', context => {
  const connection = openWorkbenchSqlite({ mode: 'memory' });
  context.after(() => connection.close());
  migrateNewWorkbenchApplication(connection);
  const initialized = initializeNativeWorkspace(connection, nativeCatalogRequest());
  const binding = { databaseGuid: initialized.databaseGuid, repositoryId: initialized.repositoryId, branchRef: initialized.branchRef };
  const before = connection.get('SELECT total_changes() AS count').count;
  const readiness = readNativeWorkspaceReadiness(connection, { binding });
  assert.equal(readiness.ready, false);
  assert.equal(readiness.checks.find(check => check.name === 'catalog-baseline').status, 'passed');
  assert.equal(readiness.checks.find(check => check.name === 'source-collections').status, 'passed');
  assert.equal(readiness.checks.find(check => check.name === 'completed-analysis').status, 'failed');
  assert.equal(readiness.checks.find(check => check.name === 'assessment-readback').status, 'failed');
  assert.equal(connection.get('SELECT total_changes() AS count').count, before);
  assert.equal(connection.isTransaction, false);
});

test('native workspace view exposes current protection without publication or analysis', context => {
  const connection = openWorkbenchSqlite({ mode: 'memory' });
  context.after(() => connection.close());
  migrateNewWorkbenchApplication(connection);
  const request = nativeCatalogRequest();
  const initialized = initializeNativeWorkspace(connection, request);
  const binding = { databaseGuid: initialized.databaseGuid, repositoryId: initialized.repositoryId, branchRef: initialized.branchRef };
  connection.run('DELETE FROM workspace_publication WHERE workspace_id = 1');
  const before = connection.get('SELECT total_changes() AS count').count;
  const view = readNativeWorkspaceView(connection, { binding });
  assert.equal(view.publishedCatalog, null);
  assert.equal(view.analysis.status, 'not-started');
  assert.equal(view.currentProtectedSnapshot.rules.length, 1);
  const [rule] = view.currentProtectedSnapshot.rules;
  const [expected] = request.protectedCapture.blocks;
  assert.deepEqual({ id: rule.displayedId, title: rule.title, surface: rule.surface, wording: rule.wording,
    provenance: rule.provenance, protectionReason: rule.protectionReason, sourcePath: rule.sourcePath }, {
    id: expected.id, title: expected.title, surface: expected.surfaceCode, wording: expected.text,
    provenance: expected.provenance, protectionReason: expected.protectionReason, sourcePath: expected.relativePath,
  });
  assert.equal(connection.get('SELECT total_changes() AS count').count, before);
  assert.equal(connection.isTransaction, false);
});

test('native staged bootstrap is the analysis baseline without becoming a publication', async context => {
  const { buildInitialStagedCatalog } = await import('../../modules/workbench/WorkbenchPublishedGuidance.mjs');
  const { inspectWorkbenchNewLaunch } = await import('../../modules/workbench/WorkbenchNewServer.mjs');
  const request = nativeCatalogRequest();
  const catalog = await buildInitialStagedCatalog({ profile: request.profile });
  request.catalogJson = JSON.stringify(catalog);
  const protectedRule = catalog.rules.find(rule => rule.kind === 'protected');
  const protectedBytes = Buffer.from(protectedRule.text);
  const protectedHash = createHash('sha256').update(protectedBytes).digest('hex');
  request.protectedCapture.files[0] = { ...request.protectedCapture.files[0], contentBytes: protectedBytes, contentSha256: protectedHash };
  request.protectedCapture.blocks[0] = { ...request.protectedCapture.blocks[0], id: protectedRule.id,
    text: protectedRule.text, content: protectedRule.text, contentSha256: protectedHash };
  const connection = openWorkbenchSqlite({ mode: 'memory' });
  context.after(() => connection.close());
  migrateNewWorkbenchApplication(connection);
  const initialized = initializeNativeWorkspace(connection, request);
  const binding = { databaseGuid: initialized.databaseGuid, repositoryId: initialized.repositoryId, branchRef: initialized.branchRef };
  let view = readNativeWorkspaceView(connection, { binding });
  assert.equal(view.publishedCatalog, null);
  assert.equal(view.stagedCatalog.catalogId, initialized.catalogId);
  assert.equal(view.stagedCatalog.rules.length, catalog.rules.filter(rule => rule.kind === 'managed').length);
  assert.deepEqual(view.stagedCatalog.guidanceFiles, catalog.files);
  assert.equal(view.stagedCatalog.upstreamRepository, null);
  assert.equal(view.stagedCatalog.lastSemanticReview, null);
  assert.throws(() => connection.run(`INSERT INTO catalog_versions(protected_snapshot_id, revision, input_schema_version,
    default_requirement_level, default_enforcement_method, default_documentation_gap, content_fingerprint, created_at)
    VALUES (?, 2, 1, 'mandatory', 'model-based', 0, ?, ?)`, [initialized.protectedSnapshotId, 'a'.repeat(64), new Date().toISOString()]), /CHECK constraint/);
  assert.equal(connection.get('SELECT count(*) AS count FROM workspace_publication').count, 0);
  assert.equal(connection.get('SELECT count(*) AS count FROM catalog_canonical_bindings').count, 0);
  assert.equal(connection.get('SELECT count(*) AS count FROM approvals').count, 0);
  assert.equal(readNativeWorkspaceReadiness(connection, { binding }).ready, false);
  await completeNativeCatalogFixture(connection, binding);
  view = readNativeWorkspaceView(connection, { binding });
  assert.equal(view.analysis.catalogId, initialized.catalogId);
  assert.equal(view.analysis.catalogMatchesCurrent, true);
  const readiness = await inspectWorkbenchNewLaunch(connection, binding);
  assert.equal(readiness.ready, true, JSON.stringify(readiness.checks.filter(check => check.status !== 'passed')));
  const { saveSourceChange, updatePlanMembership } = await import('../../modules/workbench/WorkbenchChanges.mjs');
  const source = view.sources[0];
  const saved = saveSourceChange(connection, binding, { sourceVersionId: source.sourceVersionId, expectedRevisionId: null,
    wording: 'Synthetic staged-baseline Plan proposal.', rationale: 'Synthetic first-run Plan verification.' });
  const [surface] = view.workingCatalog.surfaces;
  const plan = updatePlanMembership(connection, binding, { changeId: saved.changeId, expectedRevisionId: saved.revisionId,
    expectedPlanVersionId: null, operation: 'add', action: 'add', targetRuleVersionId: null, surface: surface.code, sectionHeading: surface.sections[0] });
  assert.equal(connection.get('SELECT base_catalog_id FROM plan_versions WHERE id = ?', [plan.versionId]).base_catalog_id, initialized.catalogId);
  assert.equal(connection.get('SELECT count(*) AS count FROM workspace_publication').count, 0);
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
});

test('native staged bootstrap rejects tampered guidance and mismatched protection without partial ingestion', async () => {
  const { buildInitialStagedCatalog } = await import('../../modules/workbench/WorkbenchPublishedGuidance.mjs');
  const original = nativeCatalogRequest();
  const catalog = await buildInitialStagedCatalog({ profile: original.profile });
  for (const [alter, expected] of [
    [copy => { copy.rules[1].text = 'Uncaptured synthetic replacement.'; }, /index does not match/],
    [copy => { copy.files[0].content += '\nUncaptured synthetic content.\n'; }, /hash is invalid/],
    [() => {}, /protection must match/],
  ]) {
    const connection = openWorkbenchSqlite({ mode: 'memory' });
    try {
      migrateNewWorkbenchApplication(connection);
      const copy = structuredClone(catalog);
      alter(copy);
      assert.throws(() => initializeNativeWorkspace(connection, { ...original, catalogJson: JSON.stringify(copy) }), expected);
      for (const table of ['workspace_identity', 'catalog_versions', 'workspace_staging', 'workspace_publication', 'source_collections']) {
        assert.equal(connection.get(`SELECT count(*) AS count FROM ${table}`).count, 0);
      }
      assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
      assert.equal(connection.isTransaction, false);
    } finally { connection.close(); }
  }
});

test('native initial JSON persists exact baseline metadata and supports analysis and Plan without publication', async context => {
  const request = nativeCatalogRequest();
  delete request.catalogJson;
  const content = readFileSync(new URL('../../../copilot-rule-catalog/initial-rules.json', import.meta.url), 'utf8');
  request.initialRulesCapture = { format: 'initial-rules-json', relativePath: 'copilot-rule-catalog/initial-rules.json',
    contentSha256: createHash('sha256').update(content).digest('hex'), content };
  const expected = parseInitialRulesJson(request.initialRulesCapture, request.profile);
  const connection = openWorkbenchSqlite({ mode: 'memory' });
  context.after(() => connection.close());
  migrateNewWorkbenchApplication(connection);
  const initialized = initializeNativeWorkspace(connection, request);
  const binding = { databaseGuid: initialized.databaseGuid, repositoryId: initialized.repositoryId, branchRef: initialized.branchRef };
  let view = readNativeWorkspaceView(connection, { binding });
  assert.equal(initialized.baselineSource, 'initial-rules-json');
  assert.equal(view.publishedCatalog, null);
  assert.equal(view.workingCatalog.captureKind, 'initial-rules');
  assert.deepEqual(view.workingCatalog.rules.map(rule => [rule.displayedId, rule.wording, rule.applicabilities]),
    expected.rules.map(rule => [rule.id, rule.text, rule.implementationModels]));
  assert.deepEqual(view.workingCatalog.guidanceFiles, [{ relativePath: request.initialRulesCapture.relativePath, role: 'baseline',
    contentSha256: request.initialRulesCapture.contentSha256, content }]);
  for (const surface of expected.surfaces) {
    const actual = view.workingCatalog.surfaces.find(item => item.code === surface.code);
    assert.deepEqual([actual.description, actual.introduction, actual.closing, actual.sections],
      [surface.description, surface.introduction, surface.closing, surface.sections]);
  }
  assert.equal(connection.get('SELECT count(*) AS count FROM catalog_canonical_bindings').count, 0);
  assert.equal(connection.get('SELECT count(*) AS count FROM approvals').count, 0);
  assert.deepEqual(connection.all('SELECT source_line AS line, source_pointer AS pointer FROM catalog_rule_guidance WHERE catalog_id = ? ORDER BY rule_id', [initialized.catalogId])
    .map(location => [location.line, location.pointer]), expected.rules.map(rule => [null, rule.sourcePointer]));
  assert.equal(connection.get("SELECT count(*) AS count FROM audit_events WHERE action_code = 'initial-catalog-import'").count, 1);
  assert.throws(() => connection.run("UPDATE catalog_surface_content SET closing_text = 'Replacement' WHERE catalog_id = ?", [initialized.catalogId]), /immutable/);
  await completeNativeCatalogFixture(connection, binding);
  const { inspectWorkbenchNewLaunch } = await import('../../modules/workbench/WorkbenchNewServer.mjs');
  assert.equal((await inspectWorkbenchNewLaunch(connection, binding)).ready, true);
  view = readNativeWorkspaceView(connection, { binding });
  const { saveSourceChange, updatePlanMembership } = await import('../../modules/workbench/WorkbenchChanges.mjs');
  const saved = saveSourceChange(connection, binding, { sourceVersionId: view.sources[0].sourceVersionId, expectedRevisionId: null,
    wording: 'Synthetic JSON baseline proposal.', rationale: 'Synthetic Plan verification.' });
  const [surface] = view.workingCatalog.surfaces;
  const plan = updatePlanMembership(connection, binding, { changeId: saved.changeId, expectedRevisionId: saved.revisionId,
    expectedPlanVersionId: null, operation: 'add', action: 'add', targetRuleVersionId: null, surface: surface.code, sectionHeading: surface.sections[0] });
  assert.equal(connection.get('SELECT base_catalog_id FROM plan_versions WHERE id = ?', [plan.versionId]).base_catalog_id, initialized.catalogId);
  assert.equal(connection.get('SELECT count(*) AS count FROM workspace_publication').count, 0);
  assert.throws(() => initializeNativeWorkspace(connection, request), /new uninitialized workspace/);
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
});

test('initial JSON database creation verifies reopening and refuses existing destinations', context => {
  const directory = mkdtempSync(join(tmpdir(), 'workbench-initial-json-'));
  context.after(() => rmSync(directory, { recursive: true, force: true }));
  const request = nativeCatalogRequest();
  delete request.catalogJson;
  const content = readFileSync(new URL('../../../copilot-rule-catalog/initial-rules.json', import.meta.url), 'utf8');
  request.initialRulesCapture = { format: 'initial-rules-json', relativePath: 'copilot-rule-catalog/initial-rules.json',
    contentSha256: createHash('sha256').update(content).digest('hex'), content };
  request.protectedCapture.files = request.protectedCapture.files.map(file => ({ ...file, contentBytes: [...file.contentBytes] }));
  const databasePath = join(directory, 'initial.sqlite');
  const create = () => execFileSync(process.execPath, [databaseBridgePath, 'create', databasePath], { encoding: 'utf8', input: JSON.stringify(request), stdio: 'pipe' });
  const created = JSON.parse(create());
  assert.equal(created.baselineSource, 'initial-rules-json');
  const before = readFileSync(databasePath);
  assert.throws(create, error => /already exists|existing|EEXIST/.test(error.stderr));
  assert.deepEqual(readFileSync(databasePath), before);
  const connection = openWorkbenchSqlite({ mode: 'read-only', databasePath });
  try {
    const view = readNativeWorkspaceView(connection, { binding: { databaseGuid: created.databaseGuid, repositoryId: created.repositoryId, branchRef: created.branchRef } });
    assert.equal(view.workingCatalog.contentSha256, request.initialRulesCapture.contentSha256);
    assert.equal(view.workingCatalog.captureKind, 'initial-rules');
    assert.equal(view.publishedCatalog, null);
    assert.deepEqual(validateWorkbenchApplicationSchema(connection), { valid: true, schemaVersion: workbenchSchemaVersion, problems: [] });
  } finally { connection.close(); }
  const invalid = structuredClone(request);
  invalid.initialRulesCapture.content += '\nUnowned synthetic text.\n';
  const invalidPath = join(directory, 'invalid.sqlite');
  assert.throws(() => execFileSync(process.execPath, [databaseBridgePath, 'create', invalidPath], { encoding: 'utf8', input: JSON.stringify(invalid), stdio: 'pipe' }),
    error => /capture is invalid/.test(error.stderr));
  assert.equal(existsSync(invalidPath), false);
  assert.deepEqual(readFileSync(databasePath), before);
});

test('native source wording Save persists immutable revisions and rejects stale or protected writes', async context => {
  const { saveSourceChange } = await import('../../modules/workbench/WorkbenchChanges.mjs');
  const connection = openWorkbenchSqlite({ mode: 'memory' });
  context.after(() => connection.close());
  migrateNewWorkbenchApplication(connection);
  const request = nativeCatalogRequest();
  const initialized = initializeNativeWorkspace(connection, request);
  const binding = { databaseGuid: initialized.databaseGuid, repositoryId: initialized.repositoryId, branchRef: initialized.branchRef };
  const before = readNativeWorkspaceView(connection, { binding });
  const source = before.sources[0];
  const input = { sourceVersionId: source.sourceVersionId, expectedRevisionId: null, wording: 'Proposed synthetic wording.', rationale: 'Synthetic maintainer decision.' };
  const saved = saveSourceChange(connection, binding, input);
  const view = readNativeWorkspaceView(connection, { binding });
  assert.equal(view.changes.length, 1);
  assert.equal(view.changes[0].wording, input.wording);
  assert.equal(view.changes[0].revisionId, saved.revisionId);
  assert.deepEqual(view.sources, before.sources);
  assert.deepEqual(view.currentProtectedSnapshot, before.currentProtectedSnapshot);
  assert.deepEqual(view.publishedCatalog, before.publishedCatalog);
  assert.equal(connection.get('SELECT COUNT(*) AS count FROM change_revisions').count, 2);
  assert.equal(connection.get('SELECT wording.text FROM proposal_versions proposal JOIN change_revisions baseline ON baseline.id = proposal.baseline_revision_id JOIN wording_versions wording ON wording.id = baseline.wording_version_id').text, source.ruleText || source.content);
  const changes = connection.get('SELECT total_changes() AS count').count;
  assert.throws(() => saveSourceChange(connection, binding, input), /saved-revision-conflict/);
  assert.equal(connection.get('SELECT total_changes() AS count').count, changes);
  assert.throws(() => saveSourceChange(connection, binding, { ...input, sourceVersionId: 999999 }), /source-is-not-current-or-is-protected/);
  assert.throws(() => saveSourceChange(connection, binding, { ...input, expectedRevisionId: saved.revisionId, rationale: '' }), /invalid-source-change/);
  const revised = saveSourceChange(connection, binding, { ...input, expectedRevisionId: saved.revisionId, wording: 'Revised synthetic wording.' });
  assert.notEqual(revised.revisionId, saved.revisionId);
  assert.equal(readNativeWorkspaceView(connection, { binding }).changes[0].wording, 'Revised synthetic wording.');
  assert.equal(connection.get('SELECT COUNT(*) AS count FROM audit_events WHERE action_code = ?', ['save-source-change']).count, 2);
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
});

test('native Plan membership snapshots exact saved revisions and requires current publication and placement', async context => {
  const { saveSourceChange, updatePlanMembership } = await import('../../modules/workbench/WorkbenchChanges.mjs');
  const connection = openWorkbenchSqlite({ mode: 'memory' });
  context.after(() => connection.close());
  migrateNewWorkbenchApplication(connection);
  const request = nativeCatalogRequest();
  const initialized = initializeNativeWorkspace(connection, request);
  const binding = { databaseGuid: initialized.databaseGuid, repositoryId: initialized.repositoryId, branchRef: initialized.branchRef };
  let view = readNativeWorkspaceView(connection, { binding });
  const saved = saveSourceChange(connection, binding, { sourceVersionId: view.sources[0].sourceVersionId, expectedRevisionId: null,
    wording: 'An exact synthetic Plan wording.', rationale: 'Synthetic Plan rationale.' });
  const [surface] = view.publishedCatalog.surfaces;
  const command = { changeId: saved.changeId, expectedRevisionId: saved.revisionId, expectedPlanVersionId: null,
    operation: 'add', action: 'add', targetRuleVersionId: null, surface: surface.code, sectionHeading: surface.sections[0] };
  assert.throws(() => updatePlanMembership(connection, binding, { ...command, sectionHeading: 'Unregistered section' }), /current-catalog-placement-required/);
  assert.equal(connection.get('SELECT COUNT(*) AS count FROM plans').count, 0);
  const added = updatePlanMembership(connection, binding, command);
  view = readNativeWorkspaceView(connection, { binding });
  assert.equal(view.plans[0].items.length, 1);
  assert.equal(view.plans[0].items[0].action, 'add');
  assert.equal(view.plans[0].items[0].needsReview, false);
  const exactRevision = view.plans[0].items[0].revisionId;
  assert.throws(() => updatePlanMembership(connection, binding, command), /plan-revision-conflict/);
  const edited = saveSourceChange(connection, binding, { sourceVersionId: view.sources[0].sourceVersionId,
    expectedRevisionId: view.changes[0].revisionId, wording: 'A later wording not silently added to the Plan.', rationale: 'Explicit rereview required.' });
  view = readNativeWorkspaceView(connection, { binding });
  assert.equal(view.changes[0].action, 'add');
  assert.equal(view.plans[0].items[0].revisionId, exactRevision);
  assert.equal(view.plans[0].items[0].needsReview, true);
  const refreshed = updatePlanMembership(connection, binding, { ...command, expectedRevisionId: edited.revisionId, expectedPlanVersionId: added.versionId });
  view = readNativeWorkspaceView(connection, { binding });
  assert.equal(view.plans[0].items[0].needsReview, false);
  assert.equal(connection.get('SELECT change_revision_id AS id FROM plan_items WHERE plan_version_id = ?', [added.versionId]).id, exactRevision);
  assert.equal(connection.get('SELECT COUNT(*) AS count FROM change_placements WHERE change_revision_id = ?', [edited.revisionId]).count, 1);
  const removed = updatePlanMembership(connection, binding, { changeId: saved.changeId, expectedRevisionId: view.changes[0].revisionId,
    expectedPlanVersionId: refreshed.versionId, operation: 'remove' });
  assert.deepEqual(readNativeWorkspaceView(connection, { binding }).plans[0].items, []);
  connection.run('DELETE FROM workspace_publication WHERE workspace_id = 1');
  assert.throws(() => updatePlanMembership(connection, binding, { ...command, expectedPlanVersionId: removed.versionId }), /catalog-baseline-required/);
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
});

test('native workspace view preserves publication and missing-last-known sources during incomplete analysis', context => {
  const connection = openWorkbenchSqlite({ mode: 'memory' });
  context.after(() => connection.close());
  migrateNewWorkbenchApplication(connection);
  const request = nativeCatalogRequest();
  const initialized = initializeNativeWorkspace(connection, request);
  const binding = { databaseGuid: initialized.databaseGuid, repositoryId: initialized.repositoryId, branchRef: initialized.branchRef };
  const assignments = readWorkspaceLlmAssignments(connection, binding);
  const scoringPolicyId = connection.get('SELECT id FROM scoring_policies').id;
  beginAnalysisRun(connection, { binding, actorId: 1, scoringPolicyId, force: false, llmAssignmentIds: assignments.map(assignment => assignment.assignmentId) });
  const definitionVersionId = connection.get('SELECT id FROM source_definition_versions').id;
  const repositoryContextId = connection.get('SELECT origin_context_id AS id FROM workspace_identity').id;
  const previous = connection.get('SELECT collection_id AS id FROM source_collection_heads').id;
  ingestSourceCollection(connection, { definitionVersionId, expectedCollectionId: previous, repositoryContextId, collectorVersion: 1,
    revision: { kind: 'repository-worktree', resolvedCommit: '1'.repeat(40), worktreeDirty: false, worktreeSha256: 'd'.repeat(64) }, complete: true, records: [] });
  const before = connection.get('SELECT total_changes() AS count').count;
  const view = readNativeWorkspaceView(connection, { binding });
  assert.equal(view.analysis.status, 'incomplete');
  assert.equal(view.analysis.runId, null);
  assert.equal(view.sources.length, 6);
  assert.ok(view.sources.every(source => source.presence === 'missing-last-known' && source.removedAt && source.content));
  assert.equal(view.publishedCatalog.catalogId, initialized.catalogId);
  assert.ok(view.publishedCatalog.rules.every(rule => rule.lifecycle === 'active'));
  assert.deepEqual(view.assessments, []);
  assert.deepEqual(view.groups, []);
  assert.deepEqual(view.findings, []);
  assert.equal(connection.get('SELECT total_changes() AS count').count, before);
  connection.exec('BEGIN');
  assert.equal(readNativeWorkspaceView(connection, { binding }).analysis.status, 'incomplete');
  assert.equal(connection.isTransaction, true);
  connection.exec('ROLLBACK');
  assert.throws(() => readNativeWorkspaceView(connection, { binding: { ...binding, branchRef: 'refs/heads/another' } }), /bound branch/);
  assert.equal(connection.isTransaction, false);
  assert.throws(() => readNativeWorkspaceView(connection, { binding, runId: 999 }), /missing or unsupported fields/);
});

test('local-only workspace schema has no CODEOWNERS permission dependencies', context => {
  const connection = openWorkbenchSqlite({ mode: 'memory' });
  context.after(() => connection.close());
  const initialization = { ...connection, exec(sql) {
    if (/codeowner|permission_snapshot/i.test(sql)) throw new Error('Fresh local-only initialization must not execute CODEOWNERS or permission-snapshot SQL');
    return connection.exec(sql);
  } };
  Object.defineProperty(initialization, 'isTransaction', { get: () => connection.isTransaction });
  migrateNewWorkbenchApplication(initialization);
  const definitions = connection.all("SELECT name, sql FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%'");
  assert.deepEqual(definitions.filter(row => /codeowner|permission_snapshot/i.test(row.name + ' ' + row.sql)).map(row => row.name), []);
  for (const table of ['approvals', 'catalog_applications', 'deployments', 'audit_events']) {
    assert.ok(connection.all(`PRAGMA foreign_key_list(${table})`).some(reference => reference.table === 'actors'));
  }
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
});

test('native catalog initialization faithfully persists published rules and provenance', context => {
  const connection = openWorkbenchSqlite({ mode: 'memory' });
  context.after(() => connection.close());
  migrateNewWorkbenchApplication(connection);
  const request = nativeCatalogRequest();
  const catalog = JSON.parse(request.catalogJson);
  const result = initializeNativeWorkspace(connection, request);
  assert.equal(result.readyForAnalysis, true);
  assert.equal(result.readyForUi, false);
  assert.equal(connection.get('SELECT current_catalog_id AS id FROM workspace_publication WHERE workspace_id = 1').id, result.catalogId);
  const storedRules = connection.all(`SELECT rule.id AS internalId, version.id AS versionId, rule.displayed_id AS id,
    version.origin_code AS origin, version.lifecycle AS status, wording.text, version.documentation_gap AS documentationGap
    FROM catalog_members member JOIN rules rule ON rule.id = member.rule_id JOIN rule_versions version ON version.id = member.rule_version_id
    JOIN wording_versions wording ON wording.id = version.wording_version_id WHERE member.catalog_id = ? ORDER BY rule.id`, [result.catalogId]);
  assert.equal(storedRules.length, catalog.rules.length);
  for (const [index, rule] of storedRules.entries()) {
    const original = catalog.rules[index];
    assert.deepEqual([rule.id, rule.origin, rule.status, rule.text, rule.documentationGap],
      [original.id, original.origin, original.status, original.text, original.documentationGap === undefined ? null : Number(original.documentationGap)]);
    assert.deepEqual(connection.all('SELECT code FROM rule_provenances WHERE rule_version_id = ? ORDER BY ordinal', [rule.versionId]).map(row => row.code), original.provenance);
    assert.deepEqual(connection.all('SELECT source_code FROM catalog_member_sources WHERE catalog_id = ? AND rule_id = ? ORDER BY ordinal', [result.catalogId, rule.internalId]).map(row => row.source_code), original.sourceIds);
    assert.deepEqual(connection.all('SELECT evidence_code FROM catalog_member_evidence WHERE catalog_id = ? AND rule_id = ? ORDER BY ordinal', [result.catalogId, rule.internalId]).map(row => row.evidence_code), original.evidenceIds);
    assert.deepEqual(connection.all(`SELECT applicability.code FROM rule_applicabilities member JOIN applicability_definitions applicability ON applicability.id = member.applicability_id
      WHERE member.rule_version_id = ? ORDER BY applicability.id`, [rule.versionId]).map(row => row.code), original.implementationModels ?? []);
  }
  assert.equal(connection.get('SELECT count(*) AS count FROM catalog_canonical_bindings').count, catalog.rules.length);
  assert.equal(connection.get('SELECT count(*) AS count FROM rule_placements').count, catalog.rules.length);
  assert.deepEqual(connection.all(`SELECT rule.displayed_id AS id, surface.code AS surface, placement.section_heading AS heading, placement.display_order AS ordinal
    FROM rule_placements placement JOIN rule_versions version ON version.id = placement.rule_version_id JOIN rules rule ON rule.id = version.rule_id
    JOIN guidance_surfaces surface ON surface.id = placement.surface_id ORDER BY rule.id`).map(row => ({ ...row })),
  catalog.surfaces.flatMap(surface => surface.sections.flatMap(section => section.ruleIds.map((id, ordinal) => ({ id, surface: surface.id, heading: section.heading, ordinal })))));
  assert.deepEqual(connection.all(`SELECT rule.displayed_id AS id, definition.code AS sourceDefinitionId, source.external_key AS sourceId,
    binding.assessment_local_key AS assessmentId
    FROM catalog_canonical_bindings binding JOIN rules rule ON rule.id = binding.rule_id JOIN source_rules source ON source.id = binding.source_rule_id
    JOIN source_definitions definition ON definition.id = source.definition_id ORDER BY rule.id`).map(row => ({ ...row })),
  catalog.rules.map(rule => ({ id: rule.id, ...catalog.canonicalCandidateMappings[rule.id], assessmentId: catalog.canonicalCandidateMappings[rule.id].assessmentId ?? null })));
  const binding = { databaseGuid: result.databaseGuid, repositoryId: result.repositoryId, branchRef: result.branchRef };
  assert.deepEqual(readNativeWorkspaceView(connection, { binding }).publishedCatalog.rules.map(rule => rule.canonicalSource.localResultKey),
    catalog.rules.map(rule => catalog.canonicalCandidateMappings[rule.id].assessmentId ?? null));
  assert.equal(connection.get('SELECT count(*) AS count FROM assessment_results').count, 0);
  assert.equal(connection.get('SELECT count(*) AS count FROM evaluations').count, 0);
  const metadata = connection.get('SELECT * FROM catalog_versions WHERE id = ?', [result.catalogId]);
  assert.equal(metadata.last_semantic_review, catalog.lastSemanticReview);
  assert.equal(metadata.upstream_baseline_commit, catalog.upstreamSnapshot.baselineCommit);
  assert.equal(metadata.upstream_current_ref, catalog.upstreamSnapshot.currentRef);
  assert.equal(metadata.content_fingerprint, createHash('sha256').update(request.catalogJson).digest('hex'));
  assert.equal(metadata.default_requirement_level, catalog.ruleDefaults.requirementLevel);
  assert.equal(metadata.default_enforcement_method, catalog.ruleDefaults.enforcementMethod);
  assert.equal(metadata.default_documentation_gap, Number(catalog.ruleDefaults.documentationGap));
  assert.ok(metadata.finalized_at);
  assert.deepEqual(connection.all('SELECT * FROM catalog_surface_content ORDER BY surface_id').map(row => [row.description, row.title, row.introduction, row.closing_text]),
    catalog.surfaces.map(surface => [surface.description, surface.title, surface.introduction, surface.closing]));
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
  assert.equal(validateWorkbenchApplicationSchema(connection).valid, true);
  assert.throws(() => initializeNativeWorkspace(connection, request), /new uninitialized workspace/);
});

test('native catalog initialization rolls back invalid or unsupported published input', context => {
  const cases = [
    { name: 'unsupported scoring', mutate: catalog => { catalog.rules[0].selectionFactors = { scoringStatus: 'not-applicable' }; }, pattern: /missing or unsupported fields/ },
    { name: 'unsupported override', mutate: catalog => { catalog.rules[0].foundationalOverride = { rationale: 'Synthetic override', affectedHostedRuleIds: [], affectedSurfaces: ['implementation'] }; }, pattern: /missing or unsupported fields/ },
    { name: 'unknown evidence', mutate: catalog => { catalog.rules[0].evidenceIds = ['absent-evidence']; }, pattern: /FOREIGN KEY/ },
    { name: 'unknown source', mutate: catalog => { catalog.rules[0].sourceIds = ['absent-source']; }, pattern: /FOREIGN KEY/ },
    { name: 'duplicate rule', mutate: catalog => { catalog.rules.push({ ...catalog.rules[0] }); }, pattern: /repeated identities/ },
    { name: 'missing canonical provenance', mutate: catalog => { delete catalog.canonicalCandidateMappings[catalog.rules[0].id]; }, pattern: /missing or unsupported fields/ },
    { name: 'null canonical assessment reference', mutate: catalog => { catalog.canonicalCandidateMappings[catalog.rules[0].id].assessmentId = null; }, pattern: /supported assessment identifier/ },
    { name: 'invalid canonical assessment reference', mutate: catalog => { catalog.canonicalCandidateMappings[catalog.rules[0].id].assessmentId = 'invalid_reference'; }, pattern: /supported assessment identifier/ },
    { name: 'unknown canonical provenance field', mutate: catalog => { catalog.canonicalCandidateMappings[catalog.rules[0].id].unsupported = true; }, pattern: /missing or unsupported fields/ },
    { name: 'unresolved canonical provenance', mutate: catalog => { catalog.canonicalCandidateMappings[catalog.rules[0].id].sourceId = 'IMPL-ABSENT-001'; }, pattern: /does not resolve/ },
    { name: 'wrong profile surface', mutate: catalog => { catalog.surfaces[0].applyTo = 'unsupported/**'; }, pattern: /does not match the selected profile/ },
  ];
  for (const scenario of cases) {
    const connection = openWorkbenchSqlite({ mode: 'memory' });
    try {
      migrateNewWorkbenchApplication(connection);
      const request = nativeCatalogRequest();
      const catalog = JSON.parse(request.catalogJson);
      scenario.mutate(catalog);
      request.catalogJson = JSON.stringify(catalog);
      assert.throws(() => initializeNativeWorkspace(connection, request), scenario.pattern, scenario.name);
      assert.equal(connection.isTransaction, false, scenario.name);
      for (const table of ['workspace_identity', 'repositories', 'source_collections', 'protected_snapshots', 'catalog_versions', 'rules', 'evaluations']) {
        assert.equal(connection.get(`SELECT count(*) AS count FROM ${table}`).count, 0, `${scenario.name}: ${table}`);
      }
    } finally { connection.close(); }
  }
});

test('native catalog initialization preserves retired last placement without rendering it active', context => {
  const connection = openWorkbenchSqlite({ mode: 'memory' });
  context.after(() => connection.close());
  migrateNewWorkbenchApplication(connection);
  const request = nativeCatalogRequest();
  const catalog = JSON.parse(request.catalogJson);
  const retired = catalog.rules[0];
  retired.status = 'retired';
  retired.retirementReason = 'Synthetic approved retirement';
  retired.lastPlacement = { surfaceId: catalog.surfaces[0].id, sectionHeading: catalog.surfaces[0].sections[0].heading };
  catalog.surfaces[0].sections[0].ruleIds.shift();
  request.catalogJson = JSON.stringify(catalog);
  const result = initializeNativeWorkspace(connection, request);
  const stored = connection.get(`SELECT version.lifecycle, version.retirement_reason, surface.code, placement.section_heading
    FROM rules rule JOIN rule_versions version ON version.rule_id = rule.id JOIN rule_placements placement ON placement.rule_version_id = version.id
    JOIN guidance_surfaces surface ON surface.id = placement.surface_id WHERE rule.displayed_id = ?`, [retired.id]);
  assert.deepEqual({ ...stored }, { lifecycle: 'retired', retirement_reason: retired.retirementReason,
    code: retired.lastPlacement.surfaceId, section_heading: retired.lastPlacement.sectionHeading });
  assert.equal(connection.get(`SELECT count(*) AS count FROM catalog_members member JOIN rule_versions version ON version.id = member.rule_version_id
    WHERE member.catalog_id = ? AND version.lifecycle = 'active'`, [result.catalogId]).count, catalog.rules.length - 1);
});

test('native catalog context does not publish saved maintainer wording or change original evidence', context => {
  const connection = openWorkbenchSqlite({ mode: 'memory' });
  context.after(() => connection.close());
  migrateNewWorkbenchApplication(connection);
  const request = nativeCatalogRequest();
  const initialized = initializeNativeWorkspace(connection, request);
  const managed = connection.get(`SELECT rule.id AS ruleId, version.id AS versionId, wording.id AS wordingId, wording.text
    FROM rules rule JOIN rule_versions version ON version.rule_id = rule.id JOIN wording_versions wording ON wording.id = version.wording_version_id
    WHERE rule.rule_kind = 'managed' ORDER BY rule.id LIMIT 1`);
  const edited = 'Maintainer-corrected wording awaiting publication.';
  const editedId = Number(connection.run('INSERT INTO wording_versions(text, content_sha256, created_at) VALUES (?, ?, ?)',
    [edited, createHash('sha256').update(edited).digest('hex'), '2026-11-09T00:00:00.000Z']).lastInsertRowid);
  const actionId = connection.get("SELECT id FROM action_definitions WHERE code = 'update'").id;
  const sourceId = connection.get('SELECT id FROM source_versions ORDER BY id LIMIT 1').id;
  connection.exec('BEGIN');
  connection.run('INSERT INTO changes(id, current_revision_id) VALUES (1, 2)');
  connection.run('INSERT INTO proposal_versions(id, change_id, revision, origin_source_version_id, baseline_revision_id) VALUES (1, 1, 1, ?, 1)', [sourceId]);
  for (const [revision, wordingId] of [[1, managed.wordingId], [2, editedId]]) {
    connection.run(`INSERT INTO change_revisions(id, change_id, proposal_version_id, revision, selected_action_id, target_rule_id,
      baseline_rule_version_id, wording_version_id, rationale, recorded_by_actor_id, recorded_at) VALUES (?, 1, 1, ?, ?, ?, ?, ?, ?, 1, ?)`,
    [revision, revision, actionId, managed.ruleId, managed.versionId, wordingId, 'Synthetic maintainer correction', '2026-11-09T00:00:00.000Z']);
  }
  connection.exec('COMMIT');
  const binding = { databaseGuid: initialized.databaseGuid, repositoryId: initialized.repositoryId, branchRef: initialized.branchRef };
  const assignments = readWorkspaceLlmAssignments(connection, binding);
  const run = beginAnalysisRun(connection, { binding, actorId: 1, scoringPolicyId: 1, force: false, llmAssignmentIds: assignments.map(assignment => assignment.assignmentId) });
  const profileId = registerEvaluatorProfile(connection, { code: 'synthetic-assessment', taskCode: 'assessment',
    llmAssignmentId: assignments.find(assignment => assignment.taskCode === 'assessment').assignmentId,
    promptSha256: 'a'.repeat(64), behaviorSha256: 'b'.repeat(64), resultContractSha256: 'c'.repeat(64) });
  const input = JSON.parse(prepareEvaluationInput(connection, { binding, runId: run.runId, profileId, sourceVersionIds: [sourceId] }).serializedInput);
  assert.equal(input.catalogRules.find(rule => rule.ruleVersionId === managed.versionId).text, managed.text);
  assert.equal(input.catalogRules.some(rule => rule.text === edited), false);
  assert.equal(connection.get('SELECT current_catalog_id AS id FROM workspace_publication WHERE workspace_id = 1').id, initialized.catalogId);
  assert.equal(connection.get(`SELECT wording.text FROM changes saved JOIN change_revisions revision ON revision.id = saved.current_revision_id
    JOIN wording_versions wording ON wording.id = revision.wording_version_id WHERE saved.id = 1`).text, edited);
  assert.equal(connection.get(`SELECT wording.text FROM proposal_versions proposal JOIN change_revisions baseline ON baseline.id = proposal.baseline_revision_id
    JOIN wording_versions wording ON wording.id = baseline.wording_version_id WHERE proposal.id = 1`).text, managed.text);
});

test('native catalog analysis refuses a missing published baseline before model execution', context => {
  const { connection, binding } = nativeAssessmentFixture(context);
  const root = resolve(fileURLToPath(new URL('../../../../', import.meta.url)));
  connection.run('UPDATE repositories SET canonical_name = ? WHERE id = 1', [`local:${createHash('sha256').update(root).digest('hex')}`]);
  assert.throws(() => readNativeLlmRuntime(connection, binding.databaseGuid), /requires a finalized current published catalog/);
});

function nativeAssessmentFixture(context, { sourceCount = 1, fileBacked = false, assessmentCardinality = 'exactly-one',
  content = 'Validate the captured source.', taskCodes = ['assessment'], protectedTexts = [], withCatalog = false, canonicalBindings = [] } = {}) {
  const directory = fileBacked ? mkdtempSync(join(tmpdir(), 'workbench-concurrent-assessment-')) : null;
  const databasePath = directory ? join(directory, 'candidate.sqlite') : undefined;
  const connection = applicationFixture(context, databasePath);
  if (directory) context.after(() => rmSync(directory, { recursive: true, force: true }));
  const binding = { databaseGuid: '12345678-1234-4234-8234-123456789abc', repositoryId: 1, branchRef: 'refs/heads/synthetic' };
  connection.exec(`
    INSERT INTO capacity_buckets VALUES (1, 1000, 'implementation', 'Implementation', 8000, 'surface-sum');
    INSERT INTO capacity_bucket_surfaces VALUES (1, 1);
    INSERT INTO guidance_surface_content VALUES (1, 'Implementation behavior', 'Implementation', '', '');
    INSERT INTO scoring_policies VALUES (1, 'synthetic-selection', 1, 0);
    INSERT INTO scoring_factors VALUES (1, 1, 'severity', 'Severity', 'Severity', 0, 5, 1, 'value');
  `);
  const protectedBytes = Buffer.from(protectedTexts.join('\n'));
  const protectedSnapshot = ingestProtectedCapture(connection, { repositoryContextId: 1, parserContractSha256: 'b'.repeat(64),
    requiredFiles: ['fixtures/protected.rules.md'], files: [{ relativePath: 'fixtures/protected.rules.md', contentBytes: protectedBytes,
      contentSha256: createHash('sha256').update(protectedBytes).digest('hex') }],
    blocks: protectedTexts.map((text, index) => ({ id: `PROTECTED-SYN-${String(index + 1).padStart(3, '0')}`,
      title: 'Protected validation', surfaceCode: 'implementation', relativePath: 'fixtures/protected.rules.md', content: text,
      contentSha256: createHash('sha256').update(text).digest('hex'), text, provenance: 'local-safeguard',
      protectionReason: 'Synthetic immutable validation boundary' })) });
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
  if (withCatalog) {
    connection.run(`INSERT INTO catalog_versions VALUES (1, NULL, ?, 'managed-catalog', 1, 1, '2026-11-09', 1, ?, 'synthetic',
      'mandatory', 'model-based', 0, ?, '2026-11-09T00:00:00.000Z', NULL)`, [protectedSnapshot.snapshotId, '1'.repeat(40), 'a'.repeat(64)]);
    connection.exec('INSERT INTO catalog_members VALUES (1, 1, 1), (1, 2, 2)');
    for (const owner of canonicalBindings) {
      const source = connection.get('SELECT source_rule_id FROM source_versions WHERE id = ?', [sourceVersionIds[owner.sourceIndex]]);
      connection.run('INSERT INTO catalog_canonical_bindings VALUES (1, ?, ?, ?)', [owner.ruleId, source.source_rule_id, owner.assessmentKey]);
    }
    connection.exec(`UPDATE catalog_versions SET finalized_at = '2026-11-09T00:00:00.000Z' WHERE id = 1;
      INSERT INTO workspace_publication VALUES (1, 1)`);
  }
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

function synthesizedGroup(input, memberIds = input.assessments.map(member => member.assessmentResultId)) {
  return { title: 'Captured validation', semanticSummary: 'Validate captured input', synthesisRationale: 'Preserve the complete supplied scope',
    wording: 'Validate captured input before use.', selectionFactors: { severity: 3 }, selectionRationale: 'Direct synthetic evidence',
    reviewState: 'recommended', needsReview: false, continuity: newGroupContinuity(), relatedCoverage: [],
    members: memberIds.map(assessmentResultId => ({ assessmentResultId, role: 'primary', coverageRationale: 'Preserves captured validation' })),
    operations: [{ role: 'primary', action: 'add', targetRuleVersionId: null, surfaceCode: 'implementation', sectionHeading: 'Validation',
      rationale: 'Proposed synthetic outcome', relationship: null, provenanceCodes: ['synthetic'], evidenceCodes: [], applicabilityCodes: [] }],
  };
}

function mixedSemanticFixture(context, { sourceCount = 3, allExcluded = false, zeroAssessments = false, canonicalBindings = [] } = {}) {
  const fixture = nativeAssessmentFixture(context, { sourceCount, fileBacked: true, withCatalog: true, canonicalBindings,
    protectedTexts: ['Validate protected evidence before use.'], assessmentCardinality: zeroAssessments ? 'zero-to-many' : 'exactly-one',
    taskCodes: ['assessment', 'reconciliation', 'adjudication'] });
  const { connection, binding, run, profileId, assignments, sourceVersionIds } = fixture;
  connection.exec(`INSERT INTO action_definitions VALUES (2, 'add', 'Add'), (3, 'defer', 'Defer');
    INSERT INTO guidance_sections VALUES (1, 0, 'Validation'); INSERT INTO source_provenance_codes VALUES ('synthetic', 'Synthetic evidence')`);
  const recorded = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId, sourceVersionIds });
  const result = nativeAssessmentResult(recorded);
  for (const [index, source] of result.sources.entries()) {
    if (zeroAssessments) source.assessments = [];
    else source.assessments[0].hostedApplicable = !allExcluded && index < 2;
  }
  commitAssessmentResults(connection, { binding, runId: run.runId, evaluationId: recorded.evaluationId, inputFingerprint: recorded.inputFingerprint, result });
  const inputs = Object.fromEntries(['reconciliation', 'adjudication'].map(task => [task, {
    prompt: `Synthetic mixed ${task} instructions.`, schema: '{"type":"object"}',
  }]));
  const profiles = Object.fromEntries(Object.keys(inputs).map(task => [task, registerEvaluatorProfile(connection, {
    code: `mixed-${task}`, taskCode: task, llmAssignmentId: assignments.find(assignment => assignment.taskCode === task).assignmentId,
    promptSha256: createHash('sha256').update(inputs[task].prompt).digest('hex'), behaviorSha256: 'e'.repeat(64),
    resultContractSha256: createHash('sha256').update(inputs[task].schema).digest('hex'),
  })]));
  return { ...fixture, inputs, profiles, request: { binding, runId: run.runId, sourceProfileId: profileId,
    reconciliationProfileId: profiles.reconciliation, adjudicationProfileId: profiles.adjudication, expectedHeadRunId: null } };
}

test('native mixed semantic routing preserves typed rule coverage exclusions and selective recovery through completion', async context => {
  const { connection, databasePath, request, inputs } = mixedSemanticFixture(context);
  const protectedId = connection.get(`SELECT member.rule_version_id AS id FROM protected_members member
    JOIN analysis_run_contexts context ON context.protected_snapshot_id = member.snapshot_id WHERE context.run_id = ?`, [request.runId]).id;
  const calls = [];
  let interrupted = false;
  const evaluate = async (recorded, { phase }) => {
    calls.push(phase);
    const input = JSON.parse(recorded.serializedInput);
    if (phase === 'routing') {
      assert.equal(input.assessments.length, 2);
      assert.ok(input.assessments.every(assessment => assessment.hostedApplicable));
      assert.deepEqual(input.ruleVersionIds, [1, 2, protectedId]);
      return { schemaVersion: 4, stage: 'reconciliation', phase, components: [
        { assessmentResultIds: input.assessments.map(member => member.assessmentResultId), ruleVersionIds: [1, protectedId], semanticSummary: 'Related source and baseline evidence' },
        { assessmentResultIds: [], ruleVersionIds: [2], semanticSummary: 'Independent managed baseline' },
      ] };
    }
    if (phase === 'consolidation') return { schemaVersion: 4, stage: 'reconciliation', phase,
      components: input.components.map(({ assessmentResultIds, ruleVersionIds, semanticSummary }) => ({ assessmentResultIds, ruleVersionIds, semanticSummary })) };
    if (phase === 'adjudication') return materialAdjudication(input);
    if (input.assessments.every(assessment => !assessment.hostedApplicable)) {
      assert.deepEqual(input.components, []);
      return { schemaVersion: 4, stage: 'reconciliation', phase, groups: [],
        dispositions: input.assessments.map(member => ({ assessmentResultId: member.assessmentResultId, code: 'excluded', rationale: 'Not Hosted applicable' })) };
    }
    assert.deepEqual(input.ruleVersionIds, [1, protectedId]);
    assert.equal(input.components.length, 1);
    if (!interrupted) { interrupted = true; throw new Error('Synthetic mixed synthesis interruption'); }
    return { schemaVersion: 4, stage: 'reconciliation', phase,
      groups: input.assessments.map(member => ({ ...synthesizedGroup(input, [member.assessmentResultId]),
        relatedCoverage: [provisionalCoverage(input, member.assessmentResultId, { kind: 'rule', id: protectedId })] })),
      dispositions: input.assessments.map(member => ({ assessmentResultId: member.assessmentResultId, code: 'grouped', rationale: 'Preserved in complete guidance' })) };
  };
  await assert.rejects(executeNativeDownstream(connection, request, inputs, evaluate), /in-flight jobs settled/);
  assert.equal(connection.get('SELECT count(*) AS count FROM workspace_analysis_head').count, 0);
  assert.equal(connection.get('SELECT count(*) AS count FROM consolidated_component_rules').count, 3);
  assert.equal(connection.get('SELECT count(*) AS count FROM group_versions').count, 0);
  const completed = await executeNativeDownstream(connection, request, inputs, evaluate);
  assert.equal(completed.assessmentCount, 3);
  assert.equal(completed.groupCount, 2);
  assert.equal(completed.comparisonCount, 2);
  assert.equal(calls.filter(phase => phase === 'routing').length, 1);
  assert.equal(calls.filter(phase => phase === 'consolidation').length, 1);
  assert.equal(calls.filter(phase => phase === 'synthesis').length, 3);
  assert.equal(connection.get('SELECT count(*) AS count FROM adjudicated_issues').count, 1);
  assert.equal(connection.get("SELECT count(*) AS count FROM reconciliation_dispositions WHERE disposition_code = 'excluded'").count, 1);
  assert.equal(connection.get('SELECT count(*) AS count FROM approvals').count, 0);
  const baselineOnly = connection.get(`SELECT component.id FROM consolidated_components component
    WHERE NOT EXISTS(SELECT 1 FROM consolidated_component_members member WHERE member.component_id = component.id)`);
  assert.throws(() => connection.run('INSERT INTO consolidated_component_rules VALUES (?, ?)', [baselineOnly.id, protectedId]), /exact unused completed shard evidence/);
  const reader = openWorkbenchSqlite({ mode: 'read-only', databasePath });
  try {
    assert.equal(reader.get('SELECT run_id FROM workspace_analysis_head').run_id, request.runId);
    assert.equal(reader.get('SELECT count(*) AS count FROM consolidated_component_rules').count, 3);
    assert.deepEqual(reader.all('PRAGMA foreign_key_check'), []);
  } finally { reader.close(); }
});

for (const options of [{ zeroAssessments: true }, { allExcluded: true }]) {
  test(`native baseline-only components retain exact coverage without invented source proposals: ${Object.keys(options)[0]}`, async context => {
    const { connection, request, inputs } = mixedSemanticFixture(context, { ...options, sourceCount: 1 });
    const calls = [];
    const completed = await executeNativeDownstream(connection, request, inputs, async (recorded, { phase }) => {
      calls.push(phase);
      const input = JSON.parse(recorded.serializedInput);
      if (phase === 'routing') {
        assert.deepEqual(input.assessments, []);
        assert.deepEqual(input.sources, []);
        return { schemaVersion: 4, stage: 'reconciliation', phase,
          components: input.ruleVersionIds.map(id => ({ assessmentResultIds: [], ruleVersionIds: [id], semanticSummary: 'Retain independent baseline evidence' })) };
      }
      if (phase === 'consolidation') return { schemaVersion: 4, stage: 'reconciliation', phase,
        components: input.components.map(({ assessmentResultIds, ruleVersionIds, semanticSummary }) => ({ assessmentResultIds, ruleVersionIds, semanticSummary })) };
      assert.equal(phase, 'synthesis');
      assert.ok(input.assessments.length > 0 && input.assessments.every(assessment => !assessment.hostedApplicable));
      return { schemaVersion: 4, stage: 'reconciliation', phase, groups: [],
        dispositions: input.assessments.map(member => ({ assessmentResultId: member.assessmentResultId, code: 'excluded', rationale: 'Not Hosted applicable' })) };
    });
    assert.equal(completed.groupCount, 0);
    assert.equal(completed.comparisonCount, 0);
    assert.equal(calls.includes('adjudication'), false);
    assert.equal(calls.includes('synthesis'), Boolean(options.allExcluded));
    assert.equal(connection.get('SELECT count(*) AS count FROM consolidated_component_rules').count, 3);
    assert.equal(connection.get('SELECT count(*) AS count FROM recommended_changes').count, 0);
  });
}

test('native mixed components reject incomplete rule coverage and roll back typed writes atomically', context => {
  const { connection, binding, request, inputs } = mixedSemanticFixture(context, { sourceCount: 2 });
  const job = planNativeReconciliation(connection, request, 'routing', inputs.reconciliation).jobs[0];
  const recorded = recordEvaluationRequest(connection, job.request);
  const component = { assessmentResultIds: job.request.assessmentResultIds, ruleVersionIds: job.request.ruleVersionIds, semanticSummary: 'Complete mixed scope' };
  const command = { binding, runId: request.runId, evaluationId: recorded.evaluationId, inputFingerprint: recorded.inputFingerprint,
    result: { schemaVersion: 4, stage: 'reconciliation', phase: 'routing', components: [component] } };
  assert.throws(() => commitReconciliationComponents(connection, { ...command, result: { ...command.result,
    components: [{ ...component, ruleVersionIds: component.ruleVersionIds.slice(1) }] } }), /every supplied assessment and rule/);
  assert.throws(() => commitReconciliationComponents(connection, { ...command, result: { ...command.result,
    components: [{ ...component, ruleVersionIds: [1, 1] }] } }), /foreign or repeated rule/);
  connection.exec(`INSERT INTO rules VALUES (99, 'UNPINNED-001', 'managed', NULL);
    INSERT INTO rule_versions VALUES (99, 99, 1, 1, 'active', NULL, 'synthetic', NULL)`);
  assert.throws(() => prepareEvaluationInput(connection, { ...job.request, ruleVersionIds: [99] }), /pinned catalog or protected/);
  let ruleWrites = 0;
  const failing = { ...connection, run(sql, parameters) {
    if (sql.startsWith('INSERT INTO reconciliation_component_rules') && ++ruleWrites === 2) throw new Error('Synthetic typed rule write failure');
    return connection.run(sql, parameters);
  } };
  Object.defineProperty(failing, 'isTransaction', { get: () => connection.isTransaction });
  assert.throws(() => commitReconciliationComponents(failing, command), /Synthetic typed rule write failure/);
  assert.equal(connection.get('SELECT count(*) AS count FROM reconciliation_components').count, 0);
  assert.equal(connection.get('SELECT count(*) AS count FROM reconciliation_component_members').count, 0);
  assert.equal(connection.get('SELECT outcome FROM evaluations WHERE id = ?', [recorded.evaluationId]).outcome, 'running');
  const committed = commitReconciliationComponents(connection, command);
  assert.throws(() => connection.run('INSERT INTO reconciliation_component_rules VALUES (?, ?)', [committed.componentIds[0], 99]), /exact evaluation inputs/);
  assert.throws(() => connection.run('DELETE FROM reconciliation_component_rules'), /immutable/);
});

test('native canonical ownership stays separate from supporting rule context and prevents cross-owner groups', context => {
  const { connection, binding, request, inputs } = mixedSemanticFixture(context, { sourceCount: 2,
    canonicalBindings: [{ ruleId: 1, sourceIndex: 0, assessmentKey: 'meaning-1' }, { ruleId: 2, sourceIndex: 1, assessmentKey: 'meaning-1' }] });
  for (const phase of ['routing', 'consolidation']) {
    const job = planNativeReconciliation(connection, request, phase, inputs.reconciliation).jobs[0];
    const recorded = recordEvaluationRequest(connection, job.request);
    commitReconciliationComponents(connection, { binding, runId: request.runId, evaluationId: recorded.evaluationId, inputFingerprint: recorded.inputFingerprint,
      result: { schemaVersion: 4, stage: 'reconciliation', phase, components: [{ assessmentResultIds: job.request.assessmentResultIds,
        ruleVersionIds: job.request.ruleVersionIds, semanticSummary: 'Consider complete related evidence without merging ownership' }] } });
  }
  const job = planNativeReconciliation(connection, request, 'synthesis', inputs.reconciliation).jobs[0];
  const recorded = recordEvaluationRequest(connection, job.request);
  const input = JSON.parse(recorded.serializedInput);
  assert.equal(input.canonicalBindings.length, 2);
  assert.deepEqual(input.priorGroups, []);
  const command = { binding, runId: request.runId, evaluationId: recorded.evaluationId, inputFingerprint: recorded.inputFingerprint,
    result: { schemaVersion: 4, stage: 'reconciliation', phase: 'synthesis', groups: [synthesizedGroup(input)],
      dispositions: input.assessments.map(member => ({ assessmentResultId: member.assessmentResultId, code: 'grouped', rationale: 'Preserve source meaning' })) } };
  const wordingCount = connection.get('SELECT count(*) AS count FROM wording_versions').count;
  assert.throws(() => commitSynthesisResults(connection, command), /different canonical rules/);
  assert.equal(connection.get('SELECT count(*) AS count FROM group_versions').count, 0);
  assert.equal(connection.get('SELECT count(*) AS count FROM wording_versions').count, wordingCount);
  const committed = commitSynthesisResults(connection, { ...command, result: { ...command.result,
    groups: input.assessments.map(member => synthesizedGroup(input, [member.assessmentResultId])) } });
  assert.equal(committed.groupVersionIds.length, 2);
  assert.equal(connection.get('SELECT count(*) AS count FROM accepted_group_evidence').count, 0);
});

test('native completion refuses omitted baseline rules even after every source meaning has a final disposition', context => {
  const { connection, binding, request, inputs } = mixedSemanticFixture(context, { sourceCount: 1 });
  let componentIds;
  for (const phase of ['routing', 'consolidation', 'synthesis']) {
    const planned = planNativeReconciliation(connection, request, phase, inputs.reconciliation).jobs[0].request;
    const scoped = { ...planned, ruleVersionIds: [1], ...(componentIds ? { componentIds } : {}) };
    const recorded = recordEvaluationRequest(connection, scoped);
    const command = { binding, runId: request.runId, evaluationId: recorded.evaluationId, inputFingerprint: recorded.inputFingerprint };
    if (phase === 'synthesis') {
      const input = JSON.parse(recorded.serializedInput);
      commitSynthesisResults(connection, { ...command, result: { schemaVersion: 4, stage: 'reconciliation', phase,
        groups: [synthesizedGroup(input)], dispositions: input.assessments.map(member =>
          ({ assessmentResultId: member.assessmentResultId, code: 'grouped', rationale: 'Preserved source meaning' })) } });
    } else componentIds = commitReconciliationComponents(connection, { ...command,
      result: { schemaVersion: 4, stage: 'reconciliation', phase, components: [{
        assessmentResultIds: scoped.assessmentResultIds, ruleVersionIds: scoped.ruleVersionIds, semanticSummary: 'Deliberately incomplete baseline scope',
      }] } }).componentIds;
  }
  assert.equal(connection.get('SELECT count(*) AS count FROM reconciliation_dispositions').count, 1);
  assert.throws(() => completeNativeAnalysis(connection, request), /complete typed canonical consolidation membership/);
  assert.equal(connection.get('SELECT count(*) AS count FROM workspace_analysis_head').count, 0);
  assert.equal(connection.get('SELECT outcome FROM analysis_runs WHERE id = ?', [request.runId]).outcome, 'running');
});

function provisionalCoverage(input, assessmentResultId, target) {
  const meaning = id => {
    const assessment = input.assessments.find(member => member.assessmentResultId === id);
    return assessment.sourceMeaning ?? input.sources.find(source => source.sourceVersionId === assessment.sourceMeaningSourceVersionId).content;
  };
  const targetText = target.kind === 'assessment' ? meaning(target.id) :
    [...input.catalogRules, ...input.protectedRules].find(rule => rule.ruleVersionId === target.id).text;
  return { target, relationship: 'partial-overlap', rationale: 'Recorded common enforceable validation requirement',
    evidence: [{ assessmentResultId, sourceQuote: meaning(assessmentResultId).slice(0, 2000), targetQuote: targetText.slice(0, 2000) }] };
}

function independentAdjudication(input) {
  return { schemaVersion: 4, stage: 'adjudication', phase: 'components', issues: [],
    relationshipDecisions: input.components.flatMap(component => component.relationships).map(relationship => ({
      relationshipId: relationship.relationshipId, disposition: 'independent', relationship: 'independent',
      title: 'Independent recorded obligations', rationale: 'The complete endpoint wordings can coexist', leftQuote: null, rightQuote: null,
    })) };
}

function materialAdjudication(input, independentIds = []) {
  const relationships = input.components.flatMap(component => component.relationships);
  const text = subject => subject.kind === 'group' ? input.groups.find(group => group.groupVersionId === subject.id).wording :
    input.rules.find(rule => rule.ruleVersionId === subject.id).text;
  return { schemaVersion: 4, stage: 'adjudication', phase: 'components',
    relationshipDecisions: relationships.map(relationship => ({ relationshipId: relationship.relationshipId,
      disposition: independentIds.includes(relationship.relationshipId) ? 'independent' : 'issue',
      relationship: independentIds.includes(relationship.relationshipId) ? 'independent' : 'partial-overlap',
      title: 'Recorded validation overlap', rationale: 'The complete wordings require one maintainer decision',
      leftQuote: text(relationship.left).slice(0, 2000), rightQuote: text(relationship.right).slice(0, 2000) })),
    issues: connectedRelationshipComponents(relationships.filter(relationship => !independentIds.includes(relationship.relationshipId))).map(component => {
      const protectedMembers = component.subjects.filter(subject => subject.kind === 'rule' && input.rules.find(rule => rule.ruleVersionId === subject.id).kind === 'protected');
      const anchor = protectedMembers[0] ?? component.subjects[0];
      return { anchor, classification: protectedMembers.length > 1 ? 'protected-integrity' : protectedMembers.length ? 'protected-coverage' : 'overlap',
        title: 'One coherent validation decision', blocking: protectedMembers.length > 1, assessmentSummary: 'Consider complete member obligations together',
        members: component.subjects.map(subject => ({ subject, disposition: subject.kind === 'group' ? 'defer' : 'keep' })),
        relationshipIds: component.relationships.map(relationship => relationship.relationshipId),
        wording: protectedMembers.length === 1 ? { status: 'canonical', source: anchor, text: text(anchor), rationale: 'Protected wording is immutable' } :
          { status: 'unresolved', source: null, text: null, rationale: 'Maintainer must select faithful complete wording' },
        recommendedMaintainerAction: { summary: 'Defer proposed mutations pending review',
          operations: component.subjects.filter(subject => subject.kind === 'group').map(subject => ({
            subject, action: 'defer', proposedText: text(subject), retireRuleVersionIds: [],
          })) },
      };
    }) };
}

function relationshipSynthesisFixture(context, { sourceCount = 4, protectedTexts = [], separateScopes = false, withCatalog = false } = {}) {
  const fixture = nativeAssessmentFixture(context, { sourceCount, protectedTexts, withCatalog, taskCodes: ['assessment', 'reconciliation', 'adjudication'] });
  const { connection, binding, run, profileId, sourceVersionIds, assignments } = fixture;
  connection.exec(`INSERT INTO action_definitions VALUES (2, 'add', 'Add'), (3, 'defer', 'Defer');
    INSERT INTO guidance_sections VALUES (1, 0, 'Validation'); INSERT INTO source_provenance_codes VALUES ('synthetic', 'Synthetic evidence')`);
  const source = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId, sourceVersionIds });
  commitAssessmentResults(connection, { binding, runId: run.runId, evaluationId: source.evaluationId,
    inputFingerprint: source.inputFingerprint, result: nativeAssessmentResult(source) });
  const profiles = Object.fromEntries(['reconciliation', 'adjudication'].map((task, index) => [task, registerEvaluatorProfile(connection, {
    code: `relationship-${task}`, taskCode: task, llmAssignmentId: assignments[index + 1].assignmentId,
    promptSha256: 'a'.repeat(64), behaviorSha256: 'b'.repeat(64), resultContractSha256: 'c'.repeat(64),
  })]));
  const assessmentResultIds = connection.all('SELECT id FROM assessment_results ORDER BY id').map(row => row.id);
  const ruleVersionIds = connection.all(`SELECT member.rule_version_id AS id FROM catalog_members member
    JOIN analysis_run_contexts context ON context.base_catalog_id = member.catalog_id WHERE context.run_id = ?
    UNION SELECT rule_version_id AS id FROM protected_members WHERE snapshot_id = ? ORDER BY id`, [run.runId, run.protectedSnapshotId]).map(row => row.id);
  let componentIds;
  for (const phase of ['routing', 'consolidation']) {
    const recorded = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId: profiles.reconciliation,
      sourceVersionIds, assessmentResultIds, ruleVersionIds, reconciliationPhase: phase, ...(componentIds ? { componentIds } : {}) });
    componentIds = commitReconciliationComponents(connection, { binding, runId: run.runId, evaluationId: recorded.evaluationId,
      inputFingerprint: recorded.inputFingerprint, result: { schemaVersion: 4, stage: 'reconciliation', phase,
        components: (separateScopes ? assessmentResultIds.map(id => [id]) : [assessmentResultIds])
          .map((ids, index) => ({ assessmentResultIds: ids, ruleVersionIds: index === 0 ? ruleVersionIds : [], semanticSummary: 'Complete enforceable validation scope' })) } }).componentIds;
  }
  const commands = (separateScopes ? componentIds.map(id => [id]) : [componentIds]).map(ids => {
    const memberIds = separateScopes ? [assessmentResultIds[componentIds.indexOf(ids[0])]] : assessmentResultIds;
    const recorded = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId: profiles.reconciliation,
      sourceVersionIds: sourceVersionIds.filter((_, index) => memberIds.includes(assessmentResultIds[index])),
      assessmentResultIds: memberIds, ruleVersionIds: !separateScopes || ids[0] === componentIds[0] ? ruleVersionIds : [], reconciliationPhase: 'synthesis', componentIds: ids });
    const input = JSON.parse(recorded.serializedInput);
    const result = { schemaVersion: 4, stage: 'reconciliation', phase: 'synthesis',
      groups: memberIds.map(id => ({ ...synthesizedGroup(input, [id]), wording: `Validate captured input ${id} before use.` })),
      dispositions: memberIds.map(assessmentResultId => ({ assessmentResultId, code: 'grouped', rationale: 'Preserved as proposed guidance' })) };
    return { binding, runId: run.runId, evaluationId: recorded.evaluationId, inputFingerprint: recorded.inputFingerprint, result, input };
  });
  const command = ({ input, ...request }) => request;
  return { ...fixture, profiles, commands, command, input: commands[0].input, result: commands[0].result,
    completionRequest: { binding, runId: run.runId, sourceProfileId: profileId, reconciliationProfileId: profiles.reconciliation,
      adjudicationProfileId: profiles.adjudication, expectedHeadRunId: null },
    adjudicationRequest: () => ({ binding, runId: run.runId, profileId: profiles.adjudication,
      componentIds: readAdjudicationComponents(connection, run.runId).map(component => component.componentId) }) };
}

test('native reconciliation records sparse member-backed relationships independently of mutation targets', context => {
  const fixture = relationshipSynthesisFixture(context);
  const { connection, input, result, commands, command } = fixture;
  const ids = input.assessments.map(member => member.assessmentResultId);
  result.groups[0].relatedCoverage = [provisionalCoverage(input, ids[0], { kind: 'assessment', id: ids[1] }),
    provisionalCoverage(input, ids[0], { kind: 'assessment', id: ids[2] })];
  const valid = structuredClone(result.groups[0].relatedCoverage);
  for (const invalid of [
    undefined, [valid[0], valid[0]], [{ ...valid[0], target: { kind: 'assessment', id: ids[0] } }],
    [{ ...valid[0], target: { kind: 'assessment', id: 999999 } }],
    [{ ...valid[0], evidence: [{ ...valid[0].evidence[0], assessmentResultId: ids[3] }] }],
    [{ ...valid[0], evidence: [{ ...valid[0].evidence[0], sourceQuote: 'Fabricated source evidence' }] }],
    [{ ...valid[0], evidence: [{ ...valid[0].evidence[0], targetQuote: 'Fabricated target evidence' }] }],
  ]) {
    result.groups[0].relatedCoverage = invalid;
    assert.throws(() => commitSynthesisResults(connection, command(commands[0])), /related coverage|Related coverage/);
    assert.equal(connection.get('SELECT count(*) AS count FROM group_relationships').count, 0);
    assert.equal(connection.get('SELECT count(*) AS count FROM group_versions').count, 0);
  }
  result.groups[0].relatedCoverage = valid;
  const failing = { ...connection, run(sql, parameters) {
    if (sql.startsWith('INSERT INTO group_relationships') && parameters[1] === ids[2]) throw new Error('Synthetic relationship write failure');
    return connection.run(sql, parameters);
  } };
  Object.defineProperty(failing, 'isTransaction', { get: () => connection.isTransaction });
  assert.throws(() => commitSynthesisResults(failing, command(commands[0])), /relationship write failure/);
  assert.equal(connection.get('SELECT count(*) AS count FROM group_versions').count, 0);
  const committed = commitSynthesisResults(connection, command(commands[0]));
  const plan = planNativeAdjudication(connection, fixture.completionRequest, { prompt: 'Synthetic adjudication', schema: '{}' });
  assert.equal(plan.comparisonCount, 2);
  assert.equal(plan.componentCount, 1);
  const prepared = prepareAdjudicationInput(connection, plan.jobs[0].request).input;
  assert.equal(prepared.groups.length, 3);
  assert.ok(prepared.groups.every(group => group.members.every(member => member.sourceMeaning)));
  assert.equal(prepared.groups.some(group => group.groupVersionId === committed.groupVersionIds[3]), false);
  assert.equal(connection.get('SELECT count(*) AS count FROM group_catalog_anchors').count, 0);
  assert.equal(connection.get('SELECT count(*) AS count FROM assessment_catalog_links').count, 0);
  assert.ok(prepared.components[0].relationships.every(relationship => relationship.evidence.origin === 'reconciliation'));
  assert.throws(() => connection.exec("UPDATE group_relationships SET rationale = 'Changed'"), /immutable/);
  assert.throws(() => completeNativeAnalysis(connection, fixture.completionRequest), /every recorded relationship component/);
});

test('native synthesis aggregates complete member evidence under one relationship and adjudicates it once', context => {
  const fixture = relationshipSynthesisFixture(context, { sourceCount: 3, protectedTexts: ['Preserve complete validation evidence.'] });
  const { connection, input, result, commands, command } = fixture;
  const ids = input.assessments.map(member => member.assessmentResultId);
  const supporting = result.groups.splice(1, 1)[0].members[0];
  result.groups[0].members.push({ ...supporting, role: 'supporting' });
  const target = { kind: 'rule', id: input.protectedRules[0].ruleVersionId };
  const relation = provisionalCoverage(input, ids[0], target);
  relation.evidence.push(provisionalCoverage(input, ids[1], target).evidence[0]);
  result.groups[0].relatedCoverage = [relation];
  for (const evidence of [[], [relation.evidence[0], relation.evidence[0]],
    [relation.evidence[0], { ...relation.evidence[1], assessmentResultId: ids[2] }],
    [relation.evidence[0], { ...relation.evidence[1], sourceQuote: 'Invented supporting meaning' }],
    [relation.evidence[0], { ...relation.evidence[1], targetQuote: 'Invented target meaning' }]]) {
    result.groups[0].relatedCoverage = [{ ...relation, evidence }];
    assert.throws(() => commitSynthesisResults(connection, command(commands[0])), /Related coverage/);
    assert.equal(connection.get('SELECT count(*) AS count FROM group_relationships').count, 0);
    assert.equal(connection.get('SELECT count(*) AS count FROM group_relationship_evidence').count, 0);
    assert.equal(connection.get('SELECT count(*) AS count FROM group_versions').count, 0);
  }
  result.groups[0].relatedCoverage = [relation];
  for (const mode of ['write-failure', 'foreign-member', 'source-quote', 'target-quote', 'missing-evidence']) {
    const failing = { ...connection, run(sql, parameters) {
      if (sql.startsWith('INSERT INTO group_relationship_evidence')) {
        if (mode === 'missing-evidence') return { changes: 0, lastInsertRowid: 0 };
        if (parameters[1] === 1) {
          if (mode === 'write-failure') throw new Error('Synthetic supporting evidence write failure');
          parameters = [...parameters];
          parameters[mode === 'foreign-member' ? 2 : mode === 'source-quote' ? 3 : 4] =
            mode === 'foreign-member' ? ids[2] : 'Synthetic ungrounded quote';
        }
      }
      return connection.run(sql, parameters);
    } };
    Object.defineProperty(failing, 'isTransaction', { get: () => connection.isTransaction });
    assert.throws(() => commitSynthesisResults(failing, command(commands[0])), /supporting evidence write failure|exact running member and target quotes|evidence for every relationship/);
    assert.equal(connection.get('SELECT count(*) AS count FROM group_versions').count, 0);
    assert.equal(connection.get('SELECT count(*) AS count FROM group_relationships').count, 0);
    assert.equal(connection.get('SELECT count(*) AS count FROM group_relationship_evidence').count, 0);
  }
  commitSynthesisResults(connection, command(commands[0]));
  assert.equal(connection.get('SELECT count(*) AS count FROM group_relationships').count, 1);
  assert.equal(connection.get('SELECT count(*) AS count FROM group_relationship_evidence').count, 2);
  assert.throws(() => connection.exec("UPDATE group_relationship_evidence SET source_quote = 'Changed'"), /immutable/);
  assert.throws(() => connection.exec('DELETE FROM group_relationship_evidence'), /immutable/);
  const recorded = recordAdjudicationRequest(connection, fixture.adjudicationRequest());
  const prepared = JSON.parse(recorded.serializedInput);
  assert.equal(prepared.components.length, 1);
  assert.equal(prepared.components[0].relationships.length, 1);
  assert.deepEqual(prepared.components[0].relationships[0].evidence.members, relation.evidence);
  const adjudicated = independentAdjudication(prepared);
  assert.equal(adjudicated.relationshipDecisions.length, 1);
  commitAdjudicationResults(connection, { binding: fixture.binding, runId: fixture.run.runId,
    evaluationId: recorded.evaluationId, inputFingerprint: recorded.inputFingerprint, result: adjudicated });
  assert.equal(completeNativeAnalysis(connection, fixture.completionRequest).comparisonCount, 1);
});

test('native synthesis persists safe validation reason and exact location without rejected content', context => {
  const fixture = relationshipSynthesisFixture(context, { sourceCount: 2 });
  const { connection, input, result, commands, command } = fixture;
  const marker = 'SYNTHETIC_UNTRUSTED_EVIDENCE_MARKER';
  const relation = provisionalCoverage(input, input.assessments[0].assessmentResultId,
    { kind: 'assessment', id: input.assessments[1].assessmentResultId });
  relation.evidence[0].sourceQuote = marker;
  result.groups[0].relatedCoverage = [relation];
  let failure;
  assert.throws(() => commitSynthesisResults(connection, command(commands[0])), error => {
    failure = describeEvaluationFailure(error, 'commit');
    return true;
  });
  assert.equal(failure.failureCode, 'evaluator-result-contract-invalid');
  assert.equal(failure.failureStage, 'commit');
  assert.equal(failure.failureReason, 'Related coverage quotes must occur in exact supplied meanings or rule text');
  assert.equal(failure.failurePath, '/groups/0/relatedCoverage/0/evidence/0/sourceQuote');
  const recorded = commands[0];
  failEvaluation(connection, { binding: fixture.binding, runId: fixture.run.runId, evaluationId: recorded.evaluationId, ...failure });
  const persisted = connection.get('SELECT failure_code, failure_stage, failure_reason, failure_path FROM evaluations WHERE id = ?', [recorded.evaluationId]);
  assert.deepEqual({ ...persisted }, { failure_code: failure.failureCode, failure_stage: failure.failureStage,
    failure_reason: failure.failureReason, failure_path: failure.failurePath });
  assert.equal(JSON.stringify(persisted).includes(marker), false);
  assert.equal(connection.get('SELECT count(*) AS count FROM group_relationships').count, 0);
});

test('native evaluator failures redact arbitrary errors and reject forged diagnostic metadata', async context => {
  const { connection, binding, run, profileId, sourceVersionIds } = nativeAssessmentFixture(context, { sourceCount: 2 });
  const marker = 'SYNTHETIC_PRIVATE_DIAGNOSTIC_MARKER';
  const events = [];
  const hostile = Object.assign(new Error(marker), { stdout: marker, stderr: marker,
    failureReason: marker, failurePath: '/groups/0', code: marker });
  await assert.rejects(executeAssessmentBatches(connection, { binding, runId: run.runId, profileId },
    assessmentEvaluatorInput, async () => { throw hostile; }, event => events.push(event)), error => {
    assert.equal(error.message.includes(marker), false);
    return true;
  });
  const failed = events.find(event => event.state === 'failed');
  assert.equal(failed.failureStage, 'evaluate');
  assert.ok(failed.failureReason.length > 0);
  assert.equal(JSON.stringify(events).includes(marker), false);
  const persisted = connection.get("SELECT failure_code, failure_stage, failure_reason, failure_path FROM evaluations WHERE outcome = 'failed'");
  assert.equal(persisted.failure_stage, 'evaluate');
  assert.equal(persisted.failure_reason, failed.failureReason);
  assert.equal(JSON.stringify(persisted).includes(marker), false);
  for (const stage of ['request', 'evaluate', 'commit']) {
    const details = describeEvaluationFailure(hostile, stage);
    assert.equal(details.failureStage, stage);
    assert.equal(JSON.stringify(details).includes(marker), false);
  }
  const recorded = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId, sourceVersionIds });
  assert.throws(() => failEvaluation(connection, { binding, runId: run.runId, evaluationId: recorded.evaluationId,
    failureCode: 'evaluator-result-contract-invalid', failureStage: 'commit', failureReason: marker, failurePath: '/groups/0' }));
  assert.equal(connection.get('SELECT outcome FROM evaluations WHERE id = ?', [recorded.evaluationId]).outcome, 'running');
});

test('native adjudication persists one shared-anchor decision atomically with complete advisory operations', context => {
  const fixture = relationshipSynthesisFixture(context);
  const { connection, input, result, command, commands } = fixture;
  const ids = input.assessments.map(member => member.assessmentResultId);
  result.groups[0].relatedCoverage = ids.slice(1).map(id => provisionalCoverage(input, ids[0], { kind: 'assessment', id }));
  commitSynthesisResults(connection, command(commands[0]));
  const recorded = recordAdjudicationRequest(connection, fixture.adjudicationRequest());
  const prepared = JSON.parse(recorded.serializedInput);
  const adjudicated = materialAdjudication(prepared);
  const issue = adjudicated.issues[0];
  issue.members[0].disposition = 'promote';
  issue.recommendedMaintainerAction.operations[0].action = 'add';
  issue.recommendedMaintainerAction.operations[0].proposedText = 'Validate all captured inputs before use.';
  issue.wording = { status: 'selected', source: issue.members[0].subject,
    text: 'Validate all captured inputs before use.', rationale: 'Complete common validation obligation' };
  const commit = result => commitAdjudicationResults(connection, { binding: fixture.binding, runId: fixture.run.runId,
    evaluationId: recorded.evaluationId, inputFingerprint: recorded.inputFingerprint, result });
  for (const invalid of [
    { ...adjudicated, relationshipDecisions: adjudicated.relationshipDecisions.slice(1) },
    { ...adjudicated, relationshipDecisions: [...adjudicated.relationshipDecisions, adjudicated.relationshipDecisions[0]] },
    { ...adjudicated, issues: [] },
    { ...adjudicated, issues: [{ ...issue, relationshipIds: issue.relationshipIds.slice(0, 1) }] },
    { ...adjudicated, issues: [{ ...issue, members: issue.members.slice(1) }] },
    { ...adjudicated, issues: [{ ...issue, recommendedMaintainerAction: { ...issue.recommendedMaintainerAction, operations: [] } }] },
    { ...adjudicated, issues: [{ ...issue, wording: { ...issue.wording, text: 'An unbound replacement' } }] },
  ]) {
    assert.throws(() => commit(invalid), /relationship|component|membership|group member|wording/);
    assert.equal(connection.get('SELECT count(*) AS count FROM findings').count, 0);
  }
  const failing = { ...connection, run(sql, parameters) {
    if (sql.startsWith('INSERT INTO adjudicated_issue_operations') && parameters[1] === 1) throw new Error('Synthetic grouped operation failure');
    return connection.run(sql, parameters);
  } };
  Object.defineProperty(failing, 'isTransaction', { get: () => connection.isTransaction });
  assert.throws(() => commitAdjudicationResults(failing, { binding: fixture.binding, runId: fixture.run.runId,
    evaluationId: recorded.evaluationId, inputFingerprint: recorded.inputFingerprint, result: adjudicated }), /grouped operation failure/);
  assert.equal(connection.get('SELECT count(*) AS count FROM issues').count, 0);
  assert.equal(connection.get('SELECT count(*) AS count FROM findings').count, 0);
  assert.equal(connection.get('SELECT outcome FROM evaluations WHERE id = ?', [recorded.evaluationId]).outcome, 'running');
  const committed = commit(adjudicated);
  assert.equal(committed.issueCount, 1);
  assert.equal(committed.comparisonCount, 3);
  assert.deepEqual(readAdjudicationResult(connection, recorded.evaluationId), adjudicated);
  assert.equal(connection.get('SELECT count(DISTINCT issue_id) AS count FROM issue_findings').count, 1);
  assert.equal(connection.get('SELECT count(*) AS count FROM adjudicated_issue_members').count, 4);
  assert.throws(() => connection.exec("UPDATE adjudicated_issue_members SET disposition = 'keep'"), /immutable/);
  const completed = completeNativeAnalysis(connection, fixture.completionRequest);
  assert.equal(completed.comparisonCount, 3);
  assert.equal(completed.groupCount, 4);
  for (const table of ['changes', 'approvals', 'issue_resolutions', 'workspace_publication']) {
    assert.equal(connection.get(`SELECT count(*) AS count FROM ${table}`).count, 0);
  }
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
});

test('native adjudication splits only on independent bridges and accepts wholly independent outcomes', context => {
  const fixture = relationshipSynthesisFixture(context, { sourceCount: 5 });
  const { connection, input, result, command, commands } = fixture;
  for (let index = 0; index < result.groups.length - 1; index++) result.groups[index].relatedCoverage = [
    provisionalCoverage(input, input.assessments[index].assessmentResultId, { kind: 'assessment', id: input.assessments[index + 1].assessmentResultId }),
  ];
  commitSynthesisResults(connection, command(commands[0]));
  const recorded = recordAdjudicationRequest(connection, fixture.adjudicationRequest());
  const prepared = JSON.parse(recorded.serializedInput);
  validateAdjudicationResult(prepared, independentAdjudication(prepared));
  const bridge = prepared.components[0].relationships[1].relationshipId;
  const adjudicated = materialAdjudication(prepared, [bridge]);
  assert.equal(adjudicated.issues.length, 2);
  commitAdjudicationResults(connection, { binding: fixture.binding, runId: fixture.run.runId,
    evaluationId: recorded.evaluationId, inputFingerprint: recorded.inputFingerprint, result: adjudicated });
  assert.equal(connection.get('SELECT count(*) AS count FROM issue_findings').count, 3);
  assert.equal(completeNativeAnalysis(connection, fixture.completionRequest).comparisonCount, 4);
});

test('native adjudication joins protected anchors across synthesis requests without making them mutation targets', context => {
  const fixture = relationshipSynthesisFixture(context, { sourceCount: 2, separateScopes: true, protectedTexts: ['Validate the captured source.'] });
  const { connection, commands, command } = fixture;
  for (const [index, entry] of commands.entries()) {
    const assessmentId = entry.input.assessments[0].assessmentResultId;
    entry.result.groups[0].relatedCoverage = [provisionalCoverage(entry.input, assessmentId,
      { kind: 'rule', id: entry.input.protectedRules[0].ruleVersionId })];
    commitSynthesisResults(connection, command(entry));
    if (index === 0) {
      assert.throws(() => planNativeAdjudication(connection, fixture.completionRequest, { prompt: 'Synthetic adjudication', schema: '{}' }), /final reconciliation/);
      assert.throws(() => recordAdjudicationRequest(connection, fixture.adjudicationRequest()), /final reconciliation/);
    }
  }
  const plan = planNativeAdjudication(connection, fixture.completionRequest, { prompt: 'Synthetic adjudication', schema: '{}' });
  assert.equal(plan.componentCount, 1);
  assert.equal(plan.comparisonCount, 2);
  const recorded = recordAdjudicationRequest(connection, plan.jobs[0].request);
  const prepared = JSON.parse(recorded.serializedInput);
  assert.equal(prepared.groups.length, 2);
  assert.equal(prepared.rules.length, 1);
  assert.ok(prepared.groups.every(group => group.operations[0].targetRuleVersionId === null));
  const adjudicated = materialAdjudication(prepared);
  const invalid = structuredClone(adjudicated);
  invalid.issues[0].wording.text = 'Changed protected text.';
  assert.throws(() => validateAdjudicationResult(prepared, invalid), /exact and canonical/);
  const forged = structuredClone(adjudicated);
  forged.issues[0].recommendedMaintainerAction.operations[0].subject = forged.issues[0].anchor;
  assert.throws(() => validateAdjudicationResult(prepared, forged), /supplied group ownership/);
  commitAdjudicationResults(connection, { binding: fixture.binding, runId: fixture.run.runId,
    evaluationId: recorded.evaluationId, inputFingerprint: recorded.inputFingerprint, result: adjudicated });
  assert.deepEqual(readAdjudicationResult(connection, recorded.evaluationId), adjudicated);
  assert.equal(completeNativeAnalysis(connection, fixture.completionRequest).comparisonCount, 2);
});

test('native adjudication preserves multi-protected integrity as blocking unresolved evidence', context => {
  const fixture = relationshipSynthesisFixture(context, { sourceCount: 1,
    protectedTexts: ['Validate the captured source.', 'Always validate the captured source.'] });
  const { connection, input, result, commands, command } = fixture;
  result.groups[0].relatedCoverage = input.protectedRules.map(rule => provisionalCoverage(input, input.assessments[0].assessmentResultId,
    { kind: 'rule', id: rule.ruleVersionId }));
  commitSynthesisResults(connection, command(commands[0]));
  const recorded = recordAdjudicationRequest(connection, fixture.adjudicationRequest());
  const prepared = JSON.parse(recorded.serializedInput);
  const adjudicated = materialAdjudication(prepared);
  assert.equal(adjudicated.issues[0].classification, 'protected-integrity');
  assert.equal(adjudicated.issues[0].blocking, true);
  const invalid = structuredClone(adjudicated);
  invalid.issues[0].blocking = false;
  assert.throws(() => validateAdjudicationResult(prepared, invalid), /protected membership/);
  commitAdjudicationResults(connection, { binding: fixture.binding, runId: fixture.run.runId,
    evaluationId: recorded.evaluationId, inputFingerprint: recorded.inputFingerprint, result: adjudicated });
  assert.equal(readAdjudicationResult(connection, recorded.evaluationId).issues[0].wording.status, 'unresolved');
  assert.equal(completeNativeAnalysis(connection, fixture.completionRequest).comparisonCount, 2);
});

test('native reconciliation with no material relationships completes without adjudication inference', context => {
  const fixture = relationshipSynthesisFixture(context, { sourceCount: 3 });
  commitSynthesisResults(fixture.connection, fixture.command(fixture.commands[0]));
  const plan = planNativeAdjudication(fixture.connection, fixture.completionRequest, { prompt: 'Synthetic adjudication', schema: '{}' });
  assert.equal(plan.batchCount, 0);
  assert.equal(plan.comparisonCount, 0);
  assert.equal(completeNativeAnalysis(fixture.connection, fixture.completionRequest).comparisonCount, 0);
});

test('native grouped operations preserve managed targets, complete target context, and explicit ancillary retirements', context => {
  const fixture = relationshipSynthesisFixture(context, { sourceCount: 1, withCatalog: true });
  const { connection, input, result, commands, command } = fixture;
  const [target, related] = input.catalogRules;
  result.groups[0].operations[0] = { ...result.groups[0].operations[0], action: 'update', targetRuleVersionId: target.ruleVersionId,
    relationship: { code: 'assessment-extends-hosted', rationale: 'Preserves and clarifies the existing target' } };
  result.groups[0].relatedCoverage = [provisionalCoverage(input, input.assessments[0].assessmentResultId, { kind: 'rule', id: related.ruleVersionId })];
  commitSynthesisResults(connection, command(commands[0]));
  const recorded = recordAdjudicationRequest(connection, fixture.adjudicationRequest());
  const prepared = JSON.parse(recorded.serializedInput);
  assert.equal(prepared.rules.some(rule => rule.ruleVersionId === target.ruleVersionId), false);
  assert.equal(prepared.groups[0].operations[0].targetRule.text, target.text);
  const adjudicated = materialAdjudication(prepared);
  const issue = adjudicated.issues[0];
  issue.members.find(member => member.subject.kind === 'group').disposition = 'replace';
  issue.members.find(member => member.subject.kind === 'rule').disposition = 'retire';
  const operation = issue.recommendedMaintainerAction.operations[0];
  operation.action = 'update';
  operation.proposedText = 'Preserve synthetic wording and validate every captured input before use.';
  operation.retireRuleVersionIds = [related.ruleVersionId];
  issue.wording = { status: 'selected', source: operation.subject, text: operation.proposedText, rationale: 'Preserves both complete obligations' };
  for (const change of [
    copy => { copy.issues[0].recommendedMaintainerAction.operations[0].action = 'add'; },
    copy => { copy.issues[0].recommendedMaintainerAction.operations[0].retireRuleVersionIds = [target.ruleVersionId]; },
    copy => { copy.issues[0].recommendedMaintainerAction.operations[0].retireRuleVersionIds = [999999]; },
    copy => { copy.issues[0].recommendedMaintainerAction.operations[0].subject = { kind: 'group', id: 999999 }; },
  ]) {
    const invalid = structuredClone(adjudicated);
    change(invalid);
    assert.throws(() => validateAdjudicationResult(prepared, invalid), /lifecycle|retirement|ownership/);
  }
  const retiredInput = structuredClone(prepared);
  retiredInput.groups[0].operations[0].targetLifecycle = 'retired';
  retiredInput.groups[0].operations[0].targetRule.lifecycle = 'retired';
  assert.throws(() => validateAdjudicationResult(retiredInput, adjudicated), /pinned target lifecycle/);
  const restored = structuredClone(adjudicated);
  restored.issues[0].members.find(member => member.subject.kind === 'group').disposition = 'promote';
  restored.issues[0].recommendedMaintainerAction.operations[0].action = 'restore';
  validateAdjudicationResult(retiredInput, restored);
  for (const table of ['adjudicated_issue_members', 'adjudicated_issue_operations', 'adjudicated_operation_retirements']) {
    const stopped = { ...connection, run(sql, parameters) {
      if (sql.startsWith(`INSERT INTO ${table}`)) connection.run('UPDATE analysis_runs SET outcome = ?, completed_at = ? WHERE id = ?',
        ['failed', '2026-11-14T00:00:00.000Z', fixture.run.runId]);
      return connection.run(sql, parameters);
    } };
    Object.defineProperty(stopped, 'isTransaction', { get: () => connection.isTransaction });
    assert.throws(() => commitAdjudicationResults(stopped, { binding: fixture.binding, runId: fixture.run.runId,
      evaluationId: recorded.evaluationId, inputFingerprint: recorded.inputFingerprint, result: adjudicated }), /exact running component inputs/);
    assert.equal(connection.get('SELECT count(*) AS count FROM findings').count, 0);
    assert.equal(connection.get('SELECT outcome FROM analysis_runs WHERE id = ?', [fixture.run.runId]).outcome, 'running');
  }
  commitAdjudicationResults(connection, { binding: fixture.binding, runId: fixture.run.runId,
    evaluationId: recorded.evaluationId, inputFingerprint: recorded.inputFingerprint, result: adjudicated });
  assert.deepEqual(readAdjudicationResult(connection, recorded.evaluationId), adjudicated);
  assert.equal(connection.get('SELECT count(*) AS count FROM adjudicated_operation_retirements').count, 1);
  assert.equal(connection.get('SELECT lifecycle FROM rule_versions WHERE id = ?', [related.ruleVersionId]).lifecycle, 'active');
  assert.equal(completeNativeAnalysis(connection, fixture.completionRequest).comparisonCount, 1);
});

test('native adjudication rejects changed evidence and mismatched typed scope before persisting decisions', context => {
  const fixture = relationshipSynthesisFixture(context, { sourceCount: 2 });
  const { connection, input, result, commands, command } = fixture;
  result.groups[0].relatedCoverage = [provisionalCoverage(input, input.assessments[0].assessmentResultId,
    { kind: 'assessment', id: input.assessments[1].assessmentResultId })];
  commitSynthesisResults(connection, command(commands[0]));
  const recorded = recordAdjudicationRequest(connection, fixture.adjudicationRequest());
  const request = { binding: fixture.binding, runId: fixture.run.runId, evaluationId: recorded.evaluationId,
    inputFingerprint: recorded.inputFingerprint, result: materialAdjudication(JSON.parse(recorded.serializedInput)) };
  for (const mode of ['scope', 'evidence', 'member-evidence']) {
    const changed = { ...connection, all(sql, parameters) {
      const rows = connection.all(sql, parameters);
      if (mode === 'scope' && sql.startsWith('SELECT * FROM evaluation_inputs')) return rows.map(row =>
        row.role_code === 'relationship' ? { ...row, group_relationship_id: 999999 } : row);
      if (mode === 'evidence' && sql.startsWith('SELECT relation.* FROM group_relationships')) return rows.map(row => ({ ...row, rationale: 'Changed evidence' }));
      if (mode === 'member-evidence' && sql.startsWith('SELECT evidence.* FROM group_relationship_evidence')) {
        return rows.map(row => ({ ...row, source_quote: 'Changed member evidence' }));
      }
      return rows;
    } };
    Object.defineProperty(changed, 'isTransaction', { get: () => connection.isTransaction });
    assert.throws(() => commitAdjudicationResults(changed, request), /exact typed component inputs|changed input scope or evidence/);
    assert.equal(connection.get('SELECT count(*) AS count FROM findings').count, 0);
    assert.equal(connection.get('SELECT outcome FROM evaluations WHERE id = ?', [recorded.evaluationId]).outcome, 'running');
  }
  commitAdjudicationResults(connection, request);
  const duplicate = recordAdjudicationRequest(connection, fixture.adjudicationRequest());
  commitAdjudicationResults(connection, { ...request, evaluationId: duplicate.evaluationId, inputFingerprint: duplicate.inputFingerprint });
  assert.throws(() => completeNativeAnalysis(connection, fixture.completionRequest), /repeated component coverage/);
  assert.equal(connection.get('SELECT count(*) AS count FROM workspace_analysis_head').count, 0);
});

async function groupContinuityFixture(context, { sourceCount = 2, partition, changedContent } = {}) {
  const fixture = nativeAssessmentFixture(context, { sourceCount, taskCodes: ['assessment', 'reconciliation', 'adjudication'] });
  const { connection, binding, run, profileId, assignments } = fixture;
  connection.exec(`INSERT INTO action_definitions VALUES (2, 'add', 'Add'), (3, 'defer', 'Defer'), (4, 'no-change', 'No Change'), (5, 'retire', 'Retire');
    INSERT INTO guidance_sections VALUES (1, 0, 'Validation'); INSERT INTO source_provenance_codes VALUES ('synthetic', 'Synthetic evidence')`);
  const inputs = { reconciliation: { prompt: 'Synthetic reconciliation instructions.', schema: '{"type":"object"}' },
    adjudication: { prompt: 'Synthetic adjudication instructions.', schema: '{"type":"object"}' } };
  const profiles = Object.fromEntries(['reconciliation', 'adjudication'].map(task => [task, registerEvaluatorProfile(connection, {
    code: `continuity-${task}`, taskCode: task, llmAssignmentId: assignments.find(assignment => assignment.taskCode === task).assignmentId,
    promptSha256: createHash('sha256').update(inputs[task].prompt).digest('hex'), behaviorSha256: 'b'.repeat(64),
    resultContractSha256: createHash('sha256').update(inputs[task].schema).digest('hex'),
  })]));
  const assess = currentRun => {
    const sourceVersionIds = connection.all(`SELECT member.source_version_id AS id FROM source_collection_heads head
      JOIN source_collection_members member ON member.collection_id = head.collection_id WHERE member.presence = 'present' ORDER BY member.ordinal`).map(row => row.id);
    const recorded = recordEvaluationRequest(connection, { binding, runId: currentRun.runId, profileId, sourceVersionIds });
    commitAssessmentResults(connection, { binding, runId: currentRun.runId, evaluationId: recorded.evaluationId,
      inputFingerprint: recorded.inputFingerprint, result: nativeAssessmentResult(recorded) });
    return { sourceVersionIds, assessmentResultIds: connection.all('SELECT id FROM assessment_results WHERE evaluation_id = ? ORDER BY id',
      [recorded.evaluationId]).map(row => row.id) };
  };
  assess(run);
  await executeNativeDownstream(connection, { binding, runId: run.runId, sourceProfileId: profileId,
    reconciliationProfileId: profiles.reconciliation, adjudicationProfileId: profiles.adjudication, expectedHeadRunId: null }, inputs,
  async (recorded, { phase }) => {
    const input = JSON.parse(recorded.serializedInput);
    if (phase === 'routing' || phase === 'consolidation') return { schemaVersion: 4, stage: 'reconciliation', phase,
      components: [{ assessmentResultIds: input.assessments.map(member => member.assessmentResultId), ruleVersionIds: input.ruleVersionIds, semanticSummary: 'Complete validation scope' }] };
    if (phase === 'synthesis') return { schemaVersion: 4, stage: 'reconciliation', phase,
      groups: (partition ?? [input.assessments.map((_, index) => index)]).map(indices =>
        synthesizedGroup(input, indices.map(index => input.assessments[index].assessmentResultId))),
      dispositions: input.assessments.map(member => ({ assessmentResultId: member.assessmentResultId, code: 'grouped', rationale: 'Preserved' })) };
    return independentAdjudication(input);
  });
  const priorVersions = connection.all('SELECT id FROM group_versions ORDER BY id').map(row => row.id);
  const snapshotId = connection.get('SELECT current_protected_snapshot_id AS id FROM workspace_identity WHERE id = 1').id;
  connection.run(`INSERT INTO catalog_versions VALUES (1, NULL, ?, 'managed-catalog', 1, 1, '2026-11-09', 1, ?, 'synthetic',
    'mandatory', 'model-based', 0, ?, '2026-11-09T00:00:00.000Z', NULL)`, [snapshotId, '1'.repeat(40), 'a'.repeat(64)]);
  for (const [index, versionId] of priorVersions.entries()) {
    connection.run('INSERT INTO catalog_members VALUES (1, ?, ?)', [index + 1, index + 1]);
    connection.run('INSERT INTO accepted_group_evidence VALUES (1, ?, ?)', [index + 1, versionId]);
  }
  connection.exec("UPDATE catalog_versions SET finalized_at = '2026-11-09T00:00:00.000Z' WHERE id = 1");
  assert.throws(() => readPinnedGroupEvidence(connection, 1), /approved or verified published/);
  connection.exec('INSERT INTO workspace_publication VALUES (1, 1)');
  if (changedContent !== undefined) {
    const previous = connection.all(`SELECT rule.external_key AS sourceId, observation.title, observation.captured_location AS location,
      version.captured_text AS content FROM source_collection_members member JOIN source_versions version ON version.id = member.source_version_id
      JOIN source_rules rule ON rule.id = member.source_rule_id JOIN source_observations observation ON observation.id = member.observation_id
      WHERE member.collection_id = ? ORDER BY member.ordinal`, [fixture.collection.collectionId]);
    ingestSourceCollection(connection, { definitionVersionId: fixture.definitionVersionId, expectedCollectionId: fixture.collection.collectionId,
      repositoryContextId: 1, collectorVersion: 1, complete: true,
      revision: { kind: 'repository-worktree', resolvedCommit: '1'.repeat(40), worktreeDirty: true, worktreeSha256: 'd'.repeat(64) },
      records: previous.map((record, index) => {
        const content = index === 0 ? changedContent : record.content;
        return { ...record, content, contentSha256: createHash('sha256').update(content).digest('hex'), presence: 'present', sourceLifecycle: 'active' };
      }) });
  }
  const currentRun = beginAnalysisRun(connection, { binding, actorId: 1, scoringPolicyId: 1, force: false,
    llmAssignmentIds: assignments.map(assignment => assignment.assignmentId) });
  const captured = assess(currentRun);
  const request = { binding, runId: currentRun.runId, profileId: profiles.reconciliation, ...captured,
    ruleVersionIds: connection.all('SELECT rule_version_id AS id FROM catalog_members WHERE catalog_id = 1 ORDER BY rule_version_id').map(row => row.id) };
  const route = recordEvaluationRequest(connection, { ...request, reconciliationPhase: 'routing' });
  const routed = commitReconciliationComponents(connection, { binding, runId: currentRun.runId, evaluationId: route.evaluationId, inputFingerprint: route.inputFingerprint,
    result: { schemaVersion: 4, stage: 'reconciliation', phase: 'routing',
      components: [{ assessmentResultIds: captured.assessmentResultIds, ruleVersionIds: request.ruleVersionIds, semanticSummary: 'Complete current validation scope' }] } });
  const consolidation = recordEvaluationRequest(connection, { ...request, reconciliationPhase: 'consolidation', componentIds: routed.componentIds });
  const consolidated = commitReconciliationComponents(connection, { binding, runId: currentRun.runId, evaluationId: consolidation.evaluationId, inputFingerprint: consolidation.inputFingerprint,
    result: { schemaVersion: 4, stage: 'reconciliation', phase: 'consolidation',
      components: [{ assessmentResultIds: captured.assessmentResultIds, ruleVersionIds: request.ruleVersionIds, semanticSummary: 'Complete current validation scope' }] } });
  const synthesis = recordEvaluationRequest(connection, { ...request, reconciliationPhase: 'synthesis', componentIds: consolidated.componentIds });
  const input = JSON.parse(synthesis.serializedInput);
  const result = { schemaVersion: 4, stage: 'reconciliation', phase: 'synthesis', groups: [synthesizedGroup(input)],
    dispositions: captured.assessmentResultIds.map(assessmentResultId => ({ assessmentResultId, code: 'grouped', rationale: 'Preserved in current wording' })) };
  return { ...fixture, currentRun, input, priorVersions, result, synthesisRequest: { binding, runId: currentRun.runId,
    evaluationId: synthesis.evaluationId, inputFingerprint: synthesis.inputFingerprint, result } };
}

function matchedGroupContinuity(input, kind, priors = input.priorGroups, currentIds = input.assessments.map(member => member.assessmentResultId)) {
  return { kind, priorGroupVersionIds: priors.map(prior => prior.groupVersionId), retainedGroupVersionId: priors[0].groupVersionId,
    confidence: 'high', rationale: 'Explicit continuity between recorded validation meanings',
    memberMatches: input.assessments.filter(member => currentIds.includes(member.assessmentResultId)).map(member => {
      const source = input.sources.find(source => source.sourceVersionId === member.sourceVersionId);
      const prior = priors.flatMap(group => group.members).find(prior => prior.sourceId === source.sourceId);
      return { assessmentResultId: member.assessmentResultId, priorAssessmentResultId: prior.assessmentResultId,
        currentQuote: member.sourceMeaning ?? source.content, priorQuote: prior.sourceMeaning, rationale: 'Compare complete captured source meanings' };
    }) };
}

test('native group continuity preserves established identity across changed source evidence without accepting proposals', async context => {
  const fixture = await groupContinuityFixture(context, { changedContent: 'Validate captured input and reject unsafe values.' });
  const { connection, input, result, synthesisRequest, priorVersions } = fixture;
  const prior = input.priorGroups[0];
  assert.notEqual(input.assessments[0].sourceVersionId, prior.members[0].sourceVersionId);
  assert.equal(input.priorGroups.length, 1);
  assert.equal(prior.members[0].sourceContent, 'Validate the captured source.');
  assert.deepEqual(connection.all("SELECT group_version_id AS id FROM evaluation_inputs WHERE evaluation_id = ? AND role_code = 'prior-group'",
    [synthesisRequest.evaluationId]).map(row => row.id), priorVersions);
  result.groups[0].continuity = matchedGroupContinuity(input, 'material-change');
  const committed = commitSynthesisResults(connection, synthesisRequest);
  const version = connection.get('SELECT group_id, revision FROM group_versions WHERE id = ?', [committed.groupVersionIds[0]]);
  assert.equal(version.group_id, prior.groupId);
  assert.equal(version.revision, prior.revision + 1);
  assert.equal(connection.get('SELECT count(*) AS count FROM semantic_groups').count, 1);
  assert.equal(connection.get('SELECT group_version_id FROM accepted_group_evidence WHERE catalog_id = 1').group_version_id, prior.groupVersionId);
  assert.equal(connection.get('SELECT run_id FROM workspace_analysis_head').run_id, fixture.run.runId);
  assert.equal(connection.get('SELECT count(*) AS count FROM group_correspondence_members').count, 2);
  assert.throws(() => connection.exec("UPDATE group_correspondence_members SET rationale = 'Changed'"), /immutable/);
  assert.throws(() => connection.run('INSERT INTO group_members VALUES (?, ?, ?, ?)',
    [prior.groupVersionId, input.assessments[0].assessmentResultId, 'supporting', 'Late alteration']), /running synthesis inputs/);
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
});

test('native group continuity rejects missing, foreign, ambiguous and incomplete correspondence atomically', async context => {
  const { connection, input, result, synthesisRequest } = await groupContinuityFixture(context);
  const group = result.groups[0];
  const valid = matchedGroupContinuity(input, 'equivalent');
  for (const invalid of [
    undefined,
    { ...valid, priorGroupVersionIds: [999999] },
    { ...valid, confidence: 'medium' },
    { ...valid, memberMatches: valid.memberMatches.slice(0, 1) },
    { ...valid, memberMatches: [{ ...valid.memberMatches[0], currentQuote: 'Unseen meaning' }, valid.memberMatches[1]] },
  ]) {
    group.continuity = invalid;
    assert.throws(() => commitSynthesisResults(connection, synthesisRequest), /Group continuity|group continuity|member coverage/);
    assert.equal(connection.get('SELECT count(*) AS count FROM group_versions').count, 1);
    assert.equal(connection.get('SELECT count(*) AS count FROM group_correspondences').count, 0);
    assert.equal(connection.get('SELECT outcome FROM evaluations WHERE id = ?', [synthesisRequest.evaluationId]).outcome, 'running');
  }
  group.continuity = valid;
  result.groups.push(structuredClone(group));
  assert.throws(() => commitSynthesisResults(connection, synthesisRequest), /competing revisions/);
  result.groups.pop();
  const failing = { ...connection, run(sql, parameters) {
    if (sql.startsWith('INSERT INTO group_correspondence_members')) throw new Error('Synthetic member-lineage write failure');
    return connection.run(sql, parameters);
  } };
  Object.defineProperty(failing, 'isTransaction', { get: () => connection.isTransaction });
  assert.throws(() => commitSynthesisResults(failing, synthesisRequest), /member-lineage write failure/);
  assert.equal(connection.get('SELECT count(*) AS count FROM group_versions').count, 1);
  assert.equal(connection.get('SELECT count(*) AS count FROM group_correspondences').count, 0);
  const tampered = { ...connection, run(sql, parameters) {
    if (sql.startsWith('INSERT INTO group_correspondence_members')) {
      parameters = [...parameters];
      parameters[3] = 'Unseen meaning';
    }
    return connection.run(sql, parameters);
  } };
  Object.defineProperty(tampered, 'isTransaction', { get: () => connection.isTransaction });
  assert.throws(() => commitSynthesisResults(tampered, synthesisRequest), /exact predecessor and successor membership/);
  assert.equal(connection.get('SELECT count(*) AS count FROM group_versions').count, 1);
  commitSynthesisResults(connection, synthesisRequest);
  assert.equal(connection.get('SELECT count(*) AS count FROM semantic_groups').count, 1);
});

test('native group continuity retains one merge survivor and all predecessor evidence', async context => {
  const { connection, input, result, synthesisRequest } = await groupContinuityFixture(context, { partition: [[0], [1]] });
  result.groups[0].continuity = matchedGroupContinuity(input, 'merge');
  const committed = commitSynthesisResults(connection, synthesisRequest);
  assert.equal(connection.get('SELECT group_id FROM group_versions WHERE id = ?', [committed.groupVersionIds[0]]).group_id, input.priorGroups[0].groupId);
  assert.equal(connection.get('SELECT count(*) AS count FROM semantic_groups').count, 2);
  assert.deepEqual(connection.all('SELECT prior_group_version_id AS id, correspondence_kind AS kind FROM group_correspondences ORDER BY id').map(row => ({ ...row })),
    input.priorGroups.map(prior => ({ id: prior.groupVersionId, kind: 'merge' })));
  assert.equal(connection.get('SELECT count(*) AS count FROM group_correspondence_members').count, 2);
  assert.equal(connection.get('SELECT count(*) AS count FROM accepted_group_evidence WHERE catalog_id = 1').count, 2);
});

test('native group continuity requires a complete split with exactly one retained identity', async context => {
  const { connection, input, result, synthesisRequest } = await groupContinuityFixture(context);
  result.groups = input.assessments.map((member, index) => {
    const group = synthesizedGroup(input, [member.assessmentResultId]);
    group.continuity = matchedGroupContinuity(input, 'split', input.priorGroups, [member.assessmentResultId]);
    if (index === 1) group.continuity.retainedGroupVersionId = null;
    return group;
  });
  const successor = result.groups.pop();
  assert.throws(() => commitSynthesisResults(connection, synthesisRequest), /split requires/);
  result.groups.push(successor);
  const committed = commitSynthesisResults(connection, synthesisRequest);
  const ids = committed.groupVersionIds.map(id => connection.get('SELECT group_id FROM group_versions WHERE id = ?', [id]).group_id);
  assert.equal(ids[0], input.priorGroups[0].groupId);
  assert.notEqual(ids[0], ids[1]);
  assert.equal(connection.get('SELECT count(*) AS count FROM group_correspondences WHERE correspondence_kind = ?', ['split']).count, 2);
  assert.equal(connection.get('SELECT count(*) AS count FROM group_correspondence_members').count, 2);
});

test('native group continuity keeps ambiguous proposals identity-free and outside accepted group evidence', async context => {
  const { connection, input, result, synthesisRequest } = await groupContinuityFixture(context);
  const group = result.groups[0];
  group.continuity = { ...matchedGroupContinuity(input, 'unresolved'), retainedGroupVersionId: null, confidence: 'low' };
  group.reviewState = 'deferred';
  group.needsReview = true;
  group.operations[0].action = 'defer';
  result.dispositions.forEach(disposition => { disposition.code = 'deferred'; });
  const committed = commitSynthesisResults(connection, synthesisRequest);
  assert.equal(connection.get('SELECT group_id FROM group_versions WHERE id = ?', [committed.groupVersionIds[0]]).group_id, null);
  assert.equal(connection.get('SELECT count(*) AS count FROM semantic_groups').count, 1);
  assert.equal(connection.get('SELECT correspondence_kind FROM group_correspondences').correspondence_kind, 'unresolved');
  const snapshotId = connection.get('SELECT current_protected_snapshot_id AS id FROM workspace_identity WHERE id = 1').id;
  connection.run(`INSERT INTO catalog_versions VALUES (2, 1, ?, 'managed-catalog', 2, 1, '2026-11-09', 1, ?, 'synthetic',
    'mandatory', 'model-based', 0, ?, '2026-11-09T00:00:00.000Z', NULL)`, [snapshotId, '1'.repeat(40), 'b'.repeat(64)]);
  connection.exec('INSERT INTO catalog_members VALUES (2, 1, 1)');
  assert.throws(() => connection.run('INSERT INTO accepted_group_evidence VALUES (2, 1, ?)', [committed.groupVersionIds[0]]), /completed established group/);
  assert.equal(readPinnedGroupEvidence(connection, 1)[0].groupVersionId, input.priorGroups[0].groupVersionId);
});

test('native synthesis preserves a twenty-meaning component above the independent-component packing limit', async context => {
  const { connection, run, input } = await groupContinuityFixture(context, { sourceCount: 20 });
  const evaluations = connection.all(`SELECT evaluation.id FROM evaluations evaluation JOIN run_evaluations used ON used.evaluation_id = evaluation.id
    WHERE used.run_id = ? AND EXISTS(SELECT 1 FROM group_versions WHERE synthesis_evaluation_id = evaluation.id)`, [run.runId]);
  assert.equal(evaluations.length, 1);
  assert.equal(connection.get('SELECT count(*) AS count FROM group_members').count, 20);
  assert.equal(input.assessments.length, 20);
  assert.equal(input.components.length, 1);
  assert.equal(input.components[0].assessmentResultIds.length, 20);
  assert.equal(input.components[0].semanticSummary, 'Complete current validation scope');
  assert.equal(input.priorGroups[0].members.length, 20);
});

test('native assessment context uses pinned published wording scoring and evidence', context => {
  const fixture = nativeAssessmentFixture(context);
  const { connection, binding, assignments, profileId, sourceVersionIds } = fixture;
  const snapshotId = connection.get('SELECT current_protected_snapshot_id AS id FROM workspace_identity WHERE id = 1').id;
  connection.run(`INSERT INTO catalog_versions VALUES (1, NULL, ?, 'managed-catalog', 1, 1, '2026-11-09', 1, ?, 'synthetic',
    'mandatory', 'model-based', 0, ?, '2026-11-09T00:00:00.000Z', NULL)`, [snapshotId, '1'.repeat(40), 'a'.repeat(64)]);
  connection.exec(`INSERT INTO catalog_members VALUES (1, 1, 1);
    INSERT INTO catalog_evidence VALUES (1, 'synthetic-evidence', 0, 'architecture', 'Current published evidence', 'fixtures/evidence.md');
    UPDATE catalog_versions SET finalized_at = '2026-11-09T00:00:00.000Z' WHERE id = 1;
    INSERT INTO workspace_publication VALUES (1, 1)`);
  const run = beginAnalysisRun(connection, { binding, actorId: 1, scoringPolicyId: 1, force: false,
    llmAssignmentIds: assignments.map(assignment => assignment.assignmentId) });
  const prepared = prepareEvaluationInput(connection, { binding, runId: run.runId, profileId, sourceVersionIds });
  const input = JSON.parse(prepared.serializedInput);
  assert.equal(input.baseCatalogId, 1);
  assert.deepEqual(input.catalogRules, [{ ruleVersionId: 1, id: 'SYNTHETIC-001', kind: 'managed', lifecycle: 'active', text: 'Synthetic wording' }]);
  assert.deepEqual(input.scoringFactors.map(factor => [factor.code, factor.minimumValue, factor.maximumValue, factor.weight, factor.contributionKind]),
    [['severity', 0, 5, 1, 'value']]);
  assert.deepEqual(input.catalogEvidence, [{ code: 'synthetic-evidence', kind: 'architecture', description: 'Current published evidence', reference: 'fixtures/evidence.md' }]);
  assert.equal(input.catalogRules.some(rule => rule.id === 'SYNTHETIC-002'), false);
});

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
  const request = { binding, runId: run.runId, profileId: reconciliationProfileId, sourceVersionIds, assessmentResultIds: [1, 2], ruleVersionIds: [], reconciliationPhase: 'routing' };
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
    sourceVersionIds: sourceVersionIds.slice(0, 1), assessmentResultIds: resultIds.slice(0, 1), ruleVersionIds: [], reconciliationPhase: 'routing' });
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
    sourceVersionIds, assessmentResultIds: resultIds, ruleVersionIds: [], reconciliationPhase: 'routing' });
  const result = { schemaVersion: 4, stage: 'reconciliation', phase: 'routing',
    components: [{ assessmentResultIds: resultIds, ruleVersionIds: [], semanticSummary: 'Validate captured input before use.' }] };
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
    assessmentResultIds: resultIds, ruleVersionIds: [], reconciliationPhase: 'consolidation', componentIds: committed.componentIds };
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
      components: resultIds.map(id => ({ assessmentResultIds: [id], ruleVersionIds: [], semanticSummary: 'Improperly split component' })) } }), /cannot split/);
  const consolidated = commitReconciliationComponents(connection, { ...request, evaluationId: downstream.evaluationId,
    inputFingerprint: downstream.inputFingerprint, result: { ...result, phase: 'consolidation' } });
  const synthesisInput = prepareEvaluationInput(connection, { ...downstreamRequest, reconciliationPhase: 'synthesis', componentIds: consolidated.componentIds });
  assert.equal(JSON.parse(synthesisInput.serializedInput).components[0].phase, 'consolidation');
  assert.equal(JSON.parse(synthesisInput.serializedInput).sources[0].content, 'Validate the captured source.');
  const synthesis = recordEvaluationRequest(connection, { ...downstreamRequest, reconciliationPhase: 'synthesis', componentIds: consolidated.componentIds });
  const synthesisResult = { schemaVersion: 4, stage: 'reconciliation', phase: 'synthesis', groups: [{
    title: 'Captured input validation', semanticSummary: 'Validate inputs before use', synthesisRationale: 'Both inputs express validation',
    continuity: newGroupContinuity(), relatedCoverage: [],
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
    relatedCoverage: index === 0 ? [provisionalCoverage(JSON.parse(synthesis.serializedInput), id, { kind: 'assessment', id: resultIds[1] })] : [],
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
  const adjudicationRequest = { binding, runId: run.runId, profileId: adjudicationProfileId,
    componentIds: readAdjudicationComponents(connection, run.runId).map(component => component.componentId) };
  const adjudication = recordAdjudicationRequest(connection, adjudicationRequest);
  const adjudicationInput = JSON.parse(adjudication.serializedInput);
  assert.equal(adjudicationInput.components[0].relationships.length, 1);
  assert.equal(adjudicationInput.groups.length, 2);
  assert.throws(() => prepareAdjudicationInput(connection, { ...adjudicationRequest, componentIds: [999999] }), /recorded relationship components/);
  const adjudicated = materialAdjudication(adjudicationInput);
  const adjudicationCommand = { binding, runId: run.runId, evaluationId: adjudication.evaluationId, inputFingerprint: adjudication.inputFingerprint, result: adjudicated };
  const completionRequest = { binding, runId: run.runId, sourceProfileId: profileId, reconciliationProfileId,
    adjudicationProfileId, expectedHeadRunId: null };
  assert.throws(() => completeNativeAnalysis(connection, completionRequest), /unfinished or mixed/);
  assert.throws(() => commitAdjudicationResults(connection, { ...adjudicationCommand, result: { ...adjudicated, relationshipDecisions: [] } }), /every recorded relationship/);
  assert.throws(() => commitAdjudicationResults(connection, { ...adjudicationCommand, result: { ...adjudicated,
    relationshipDecisions: [{ ...adjudicated.relationshipDecisions[0], leftQuote: 'Fabricated quote' }] } }), /exact supplied wording/);
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

test('native consolidation shard planning preserves all within-block and cross-block comparisons', async () => {
  const { planConsolidationShards, readWorkbenchBudgets, mergeConsolidationShards } = await import('../../modules/workbench/WorkbenchSharding.mjs');
  const components = Array.from({ length: 6 }, (_, index) => ({ componentId: index + 1,
    semanticSummary: `Synthetic requirement ${index + 1}: ${'meaning '.repeat(8)}`, assessmentResultIds: [index + 1], ruleVersionIds: [] }));
  const stagePayloadBudgetBytes = Buffer.byteLength(JSON.stringify({ components: components.slice(0, 2) }));
  const budgets = { stagePayloadBudgetBytes, evaluatorPayloadBudgetBytes: stagePayloadBudgetBytes + 100 };
  const measure = members => {
    const inputBytes = Buffer.byteLength(JSON.stringify({ components: members }));
    return { inputBytes, payloadBytes: inputBytes + 100 };
  };
  const shards = planConsolidationShards(components, budgets, measure);
  assert.ok(shards.length > 1);
  assert.ok(shards.every(shard => shard.inputBytes <= budgets.stagePayloadBudgetBytes));
  assert.ok(shards.every(shard => shard.payloadBytes <= budgets.evaluatorPayloadBudgetBytes));
  for (const left of components) for (const right of components) {
    assert.ok(shards.some(shard => shard.componentIds.includes(left.componentId) && shard.componentIds.includes(right.componentId)));
  }
  assert.deepEqual(planConsolidationShards([...components].reverse(), budgets, measure), shards);
  assert.throws(() => readWorkbenchBudgets({ ...budgets, evaluatorPayloadBudgetBytes: 1 }), /positive byte budgets/);
  assert.throws(() => planConsolidationShards(components, budgets,
    () => ({ inputBytes: 1, payloadBytes: budgets.evaluatorPayloadBudgetBytes + 1 })), /evaluator budget/);
  const results = shards.map(shard => ({ componentIds: shard.componentIds, components: [{ assessmentResultIds: shard.componentIds, ruleVersionIds: [] }] }));
  const merged = mergeConsolidationShards(components, shards, results);
  assert.equal(merged.length, 1);
  assert.deepEqual(merged[0].assessmentResultIds, [1, 2, 3, 4, 5, 6]);
  assert.throws(() => mergeConsolidationShards(components, shards, results.slice(1)), /every planned shard/);
  assert.throws(() => mergeConsolidationShards(components, shards.slice(0, 1), results.slice(0, 1)), /cross-block comparison coverage/);
  assert.throws(() => mergeConsolidationShards(components, shards, results.map((result, index) => index ? result : { ...result, components: [] })), /exact complete shard membership/);
  assert.equal(components.length, 6);
});

test('native consolidation joins assessment components transitively through rule-only shards without mixing identity namespaces', async () => {
  const { mergeConsolidationShards } = await import('../../modules/workbench/WorkbenchSharding.mjs');
  const components = [
    { componentId: 1, semanticSummary: 'First source', assessmentResultIds: [1], ruleVersionIds: [] },
    { componentId: 2, semanticSummary: 'Connecting baseline', assessmentResultIds: [], ruleVersionIds: [1] },
    { componentId: 3, semanticSummary: 'Second source', assessmentResultIds: [2], ruleVersionIds: [] },
  ];
  const shards = [[1], [1, 2], [1, 3], [2], [2, 3], [3]].map(componentIds => ({ componentIds }));
  const results = shards.map(shard => ({ componentIds: shard.componentIds,
    components: shard.componentIds.includes(2)
      ? [{ assessmentResultIds: shard.componentIds.filter(id => id !== 2).flatMap(id => components[id - 1].assessmentResultIds),
        ruleVersionIds: [1] }]
      : shard.componentIds.map(id => ({ assessmentResultIds: components[id - 1].assessmentResultIds, ruleVersionIds: [] })) }));
  const merged = mergeConsolidationShards(components, shards, results);
  assert.deepEqual(merged.map(({ componentIds, assessmentResultIds, ruleVersionIds }) => ({ componentIds, assessmentResultIds, ruleVersionIds })),
    [{ componentIds: [1, 2, 3], assessmentResultIds: [1, 2], ruleVersionIds: [1] }]);
  const invalid = structuredClone(results);
  invalid[1].components[0].ruleVersionIds = [];
  assert.throws(() => mergeConsolidationShards(components, shards, invalid), /exact complete shard membership/);
});

test('native adjudication packs only independent complete components and refuses oversized whole decisions', async () => {
  const { planAdjudicationShards } = await import('../../modules/workbench/WorkbenchSharding.mjs');
  const relationships = Array.from({ length: 90 }, (_, index) => ({
    relationshipId: index + 1, left: { kind: 'group', id: index + 1 }, right: { kind: 'rule', id: 101 },
  }));
  relationships.push({ relationshipId: 91, left: { kind: 'group', id: 92 }, right: { kind: 'rule', id: 102 } });
  const components = connectedRelationshipComponents(relationships);
  const budgets = { stagePayloadBudgetBytes: 1200, evaluatorPayloadBudgetBytes: 1400 };
  const measure = scope => ({ inputBytes: scope.componentIds.length === 1 ? 1000 : 1300, payloadBytes: scope.componentIds.length === 1 ? 1300 : 1500 });
  const shards = planAdjudicationShards(components, budgets, measure);
  assert.deepEqual(shards.map(shard => shard.componentIds), [[1], [91]]);
  assert.equal(components[0].relationships.length, 90);
  assert.deepEqual(planAdjudicationShards(components.toReversed(), budgets, measure), shards);
  assert.deepEqual(planAdjudicationShards([], budgets, measure), []);
  assert.throws(() => planAdjudicationShards([components[0], components[0]], budgets, measure), /unique positive/);
  assert.throws(() => planAdjudicationShards(components, budgets, () => ({ inputBytes: 1201, payloadBytes: 1401 })), /evaluator budget/);
});

test('native planning snapshots isolate reads and expire on success or failure', context => {
  const connection = openWorkbenchSqlite({ mode: 'memory' });
  context.after(() => connection.close());
  createConstraintFixture(connection);
  let retained;
  withEvaluationPlanningSnapshot(connection, snapshot => {
    retained = snapshot;
    const row = snapshot.get('SELECT * FROM evidence WHERE id = ?', [1]);
    row.score = 99;
    assert.equal(snapshot.get('SELECT * FROM evidence WHERE id = ?', [1]).score, 50);
    const rows = snapshot.all('SELECT * FROM evidence');
    rows.length = 0;
    assert.equal(snapshot.all('SELECT * FROM evidence').length, 1);
    assert.equal(snapshot.get('SELECT typeof(?) AS type', [1]).type, 'real');
    assert.equal(snapshot.get('SELECT typeof(?) AS type', ['1']).type, 'text');
    assert.throws(() => snapshot.get('DELETE FROM evidence RETURNING *'), /only read queries/);
  });
  assert.equal(connection.isTransaction, false);
  assert.throws(() => retained.get('SELECT * FROM evidence'), /snapshot is closed/);
  assert.throws(() => withEvaluationPlanningSnapshot(connection, snapshot => {
    retained = snapshot;
    throw new Error('Synthetic planning failure');
  }), /Synthetic planning failure/);
  assert.equal(connection.isTransaction, false);
  assert.throws(() => retained.all('SELECT * FROM evidence'), /snapshot is closed/);
  assert.throws(() => withEvaluationPlanningSnapshot(connection, async () => {}), /synchronous operation/);
  assert.throws(() => withEvaluationPlanningSnapshot(connection, () => {
    connection.run('UPDATE evidence SET score = 51 WHERE id = 1');
  }), /changed inside/);
  assert.equal(connection.get('SELECT score FROM evidence WHERE id = 1').score, 50);
  connection.exec('BEGIN');
  withEvaluationPlanningSnapshot(connection, () => {});
  assert.equal(connection.isTransaction, true);
  connection.exec('ROLLBACK');
});

test('native downstream planning bounds SQL reads and preserves fresh request fingerprints', context => {
  const sourceCount = 48;
  const { connection, binding, run, profileId, assignments, sourceVersionIds } = nativeAssessmentFixture(context,
    { sourceCount, taskCodes: ['assessment', 'reconciliation'] });
  for (let offset = 0; offset < sourceCount; offset += 4) {
    const recorded = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId,
      sourceVersionIds: sourceVersionIds.slice(offset, offset + 4) });
    commitAssessmentResults(connection, { binding, runId: run.runId, evaluationId: recorded.evaluationId,
      inputFingerprint: recorded.inputFingerprint, result: nativeAssessmentResult(recorded) });
  }
  const reconciliationProfileId = registerEvaluatorProfile(connection, { code: 'native-reconciliation', taskCode: 'reconciliation',
    llmAssignmentId: assignments[1].assignmentId, promptSha256: 'd'.repeat(64), behaviorSha256: 'e'.repeat(64), resultContractSha256: 'f'.repeat(64) });
  let queries = 0;
  let recoveryChecks = 0;
  const measured = {
    ...connection,
    get isTransaction() { return connection.isTransaction; },
    get(sql, parameters) {
      queries += 1;
      if (sql.includes('SELECT run.outcome, profile.task_code FROM analysis_runs run')) recoveryChecks += 1;
      return connection.get(sql, parameters);
    },
    all(sql, parameters) { queries += 1; return connection.all(sql, parameters); },
  };
  const request = { binding, runId: run.runId, sourceProfileId: profileId, reconciliationProfileId,
    budgets: { stagePayloadBudgetBytes: 12000, evaluatorPayloadBudgetBytes: 16000 } };
  const evaluatorInput = { prompt: 'Synthetic reconciliation instructions.', schema: '{"type":"object"}' };
  const plan = planNativeReconciliation(measured, request, 'routing', evaluatorInput);
  assert.ok(plan.jobs.length > 1);
  assert.ok(queries <= sourceCount * 12 + 150, `Expected bounded SQL reads, got ${queries}`);
  assert.equal(recoveryChecks, 1);
  assert.equal(connection.isTransaction, false);
  for (const job of plan.jobs) {
    const prepared = prepareEvaluationInput(connection, job.request);
    assert.equal(job.inputFingerprint, createHash('sha256').update(prepared.serializedInput).digest('hex'));
    assert.equal(job.inputBytes, Buffer.byteLength(prepared.serializedInput));
    assert.equal(job.payloadBytes, measureAssessmentInputBytes(prepared.serializedInput, evaluatorInput));
    assert.ok(job.inputBytes <= request.budgets.stagePayloadBudgetBytes);
    assert.ok(job.payloadBytes <= request.budgets.evaluatorPayloadBudgetBytes);
  }
  const original = connection.get('SELECT * FROM evaluations WHERE id = 1');
  connection.run("UPDATE evaluations SET outcome = 'failed', failure_code = 'synthetic-failure' WHERE id = 1");
  assert.throws(() => planNativeReconciliation(connection, request, 'routing', evaluatorInput), /complete committed/);
  assert.equal(connection.isTransaction, false);
  assert.throws(() => recordEvaluationRequest(connection, plan.jobs[0].request), /complete committed/);
  assert.equal(connection.get('SELECT count(*) AS count FROM evaluations').count, sourceCount / 4);
  connection.run('UPDATE evaluations SET outcome = ?, failure_code = NULL WHERE id = ?', [original.outcome, original.id]);
  connection.run("UPDATE evaluations SET input_fingerprint = ? WHERE id = 1", ['f'.repeat(64)]);
  assert.throws(() => planNativeReconciliation(connection, request, 'routing', evaluatorInput), /changed evaluation inputs/);
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
  for (const job of plan.jobs) {
    const projected = JSON.parse(prepareEvaluationInput(connection, job.request).serializedInput);
    assert.ok(projected.sources.every(source => !Object.hasOwn(source, 'content') && source.contentSha256));
    assert.ok(projected.assessments.every(assessment => assessment.sourceMeaning.length >= 150000));
  }
  assert.throws(() => planNativeReconciliation(connection, request, 'routing', { ...input, prompt: 'p'.repeat(393216) }),
    { code: 'workbench-evaluator-input-budget-exceeded', phase: 'routing' });
  const componentIds = plan.jobs.flatMap(job => {
    const recorded = recordEvaluationRequest(connection, job.request);
    return commitReconciliationComponents(connection, { binding, runId: run.runId, evaluationId: recorded.evaluationId,
      inputFingerprint: recorded.inputFingerprint, result: { schemaVersion: 4, stage: 'reconciliation', phase: 'routing',
        components: [{ assessmentResultIds: job.request.assessmentResultIds, ruleVersionIds: job.request.ruleVersionIds, semanticSummary: 's'.repeat(1200) }] } }).componentIds;
  });
  const consolidatedPlan = planNativeReconciliation(connection, request, 'consolidation', input);
  assert.equal(consolidatedPlan.batchCount, 1);
  assert.deepEqual(consolidatedPlan.jobs[0].request.componentIds, componentIds);
  const recordedCount = connection.get('SELECT count(*) AS count FROM evaluations').count;
  const padding = 393216 - consolidatedPlan.pendingPayloadBytes + 1;
  const boundedInput = { ...input, prompt: input.prompt + 'p'.repeat(padding) };
  const shardedPlan = planNativeReconciliation(connection, request, 'consolidation', boundedInput);
  assert.ok(shardedPlan.batchCount > 1);
  const coveredPairs = new Set();
  for (const job of shardedPlan.jobs) {
    const prepared = prepareEvaluationInput(connection, job.request);
    assert.ok(Buffer.byteLength(prepared.serializedInput, 'utf8') <= 262144);
    assert.ok(measureAssessmentInputBytes(prepared.serializedInput, boundedInput) <= 393216);
    for (const left of job.request.componentIds) for (const right of job.request.componentIds) {
      coveredPairs.add([left, right].sort((first, second) => first - second).join(':'));
    }
  }
  for (const left of componentIds) for (const right of componentIds) assert.ok(coveredPairs.has([left, right].sort((first, second) => first - second).join(':')));
  assert.equal(connection.get('SELECT count(*) AS count FROM evaluations').count, recordedCount);
  const recorded = recordEvaluationRequest(connection, consolidatedPlan.jobs[0].request);
  commitReconciliationComponents(connection, { binding, runId: run.runId, evaluationId: recorded.evaluationId, inputFingerprint: recorded.inputFingerprint,
    result: { schemaVersion: 4, stage: 'reconciliation', phase: 'consolidation', components: [{
      assessmentResultIds: consolidatedPlan.jobs[0].request.assessmentResultIds, ruleVersionIds: consolidatedPlan.jobs[0].request.ruleVersionIds, semanticSummary: 'One logical synthesis group spanning several requests' }] } });
  assert.throws(() => planNativeReconciliation(connection, request, 'synthesis', input),
    { code: 'workbench-evaluator-input-budget-exceeded', phase: 'synthesis' });
  assert.equal(connection.get('SELECT count(*) AS count FROM evaluations').count, recordedCount + 1);
});

test('native downstream execution resumes committed phases and advances only complete typed results', async context => {
  const { connection, binding, run, profileId, assignments, sourceVersionIds } = nativeAssessmentFixture(context,
    { sourceCount: 20, taskCodes: ['assessment', 'reconciliation', 'adjudication'] });
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
  let failAdjudication = true;
  const evaluate = async (recorded, { phase }) => {
    assert.equal(connection.isTransaction, false);
    calls.push(phase);
    const input = JSON.parse(recorded.serializedInput);
    if (phase === 'routing' || phase === 'consolidation') return { schemaVersion: 4, stage: 'reconciliation', phase,
      components: input.assessments.map(member => ({ assessmentResultIds: [member.assessmentResultId], ruleVersionIds: [], semanticSummary: `Synthetic requirement ${member.assessmentResultId}` })) };
    if (phase === 'synthesis') {
      if (failFirstSynthesis) { failFirstSynthesis = false; throw new Error('Synthetic synthesis interruption'); }
      return { schemaVersion: 4, stage: 'reconciliation', phase, groups: input.assessments.map((member, index) => ({
        title: `Synthetic requirement ${member.assessmentResultId}`, semanticSummary: 'Preserve the captured requirement', synthesisRationale: 'Source-grounded synthetic result',
        continuity: newGroupContinuity(),
        relatedCoverage: index % 2 === 0 ? [provisionalCoverage(input, member.assessmentResultId,
          { kind: 'assessment', id: input.assessments[index + 1].assessmentResultId })] : [],
        wording: `Review captured requirement ${member.assessmentResultId}.`, selectionFactors: { severity: 3 }, selectionRationale: 'Synthetic rationale',
        reviewState: 'recommended', needsReview: false, members: [{ assessmentResultId: member.assessmentResultId, role: 'primary', coverageRationale: 'Preserves the captured requirement' }],
        operations: [{ role: 'primary', action: 'add', targetRuleVersionId: null, surfaceCode: 'implementation', sectionHeading: 'Validation',
          rationale: 'No accepted baseline', relationship: null, provenanceCodes: ['synthetic'], evidenceCodes: [], applicabilityCodes: [] }],
      })), dispositions: input.assessments.map(member => ({ assessmentResultId: member.assessmentResultId, code: 'grouped', rationale: 'Preserved in final wording' })) };
    }
    if (failAdjudication) throw Object.assign(new Error('Synthetic adjudicator failure'), { stderr: 'Native evaluator response failed its result contract; content omitted' });
    return independentAdjudication(input);
  };
  await assert.rejects(executeNativeDownstream(connection, request, inputs, evaluate, event => events.push(event)), /in-flight jobs settled/);
  assert.equal(connection.get('SELECT count(*) AS count FROM workspace_analysis_head').count, 0);
  assert.equal(connection.get('SELECT count(*) AS count FROM group_versions').count, 4);
  const callsBeforeAdjudicationOnly = calls.length;
  await assert.rejects(executeNativeDownstream(connection, { ...request, adjudicationOnly: true }, inputs, evaluate), /requires fully committed reconciliation/);
  assert.equal(calls.length, callsBeforeAdjudicationOnly);
  const comparisonInput = prepareAdjudicationInput(connection, { binding, runId: run.runId, profileId: request.adjudicationProfileId,
    componentIds: readAdjudicationComponents(connection, run.runId).map(component => component.componentId) });
  inputs.adjudication.prompt += 'p'.repeat(393216 - measureAssessmentInputBytes(comparisonInput.serializedInput, inputs.adjudication) + 1);
  request.adjudicationProfileId = registerEvaluatorProfile(connection, { code: 'native-bounded-adjudication', taskCode: 'adjudication',
    llmAssignmentId: assignments[2].assignmentId, promptSha256: createHash('sha256').update(inputs.adjudication.prompt).digest('hex'),
    behaviorSha256: 'e'.repeat(64), resultContractSha256: createHash('sha256').update(inputs.adjudication.schema).digest('hex') });
  const inferenceCount = calls.length;
  await assert.rejects(executeNativeDownstream(connection, { ...request, expectedHeadRunId: 999 }, inputs, evaluate), /changed analysis head before inference/);
  assert.equal(calls.length, inferenceCount);
  await assert.rejects(executeNativeDownstream(connection, request, inputs, evaluate, event => events.push(event)), /in-flight jobs settled/);
  failAdjudication = false;
  assert.ok(events.some(event => event.phase === 'adjudication' && event.state === 'failed' && event.failureCode === 'evaluator-result-contract-invalid'));
  assert.ok(events.some(event => event.phase === 'adjudication' && event.state === 'failed' &&
    event.failureStage === 'evaluate' && event.failureReason.length > 0));
  assert.ok(events.some(event => event.phase === 'adjudication' && event.state === 'plan' && event.comparisonCount === 10 && event.componentCount === 10));
  request.adjudicationProfileId = registerEvaluatorProfile(connection, { code: 'native-repaired-adjudication', taskCode: 'adjudication',
    llmAssignmentId: assignments[2].assignmentId, promptSha256: createHash('sha256').update(inputs.adjudication.prompt).digest('hex'),
    behaviorSha256: 'd'.repeat(64), resultContractSha256: createHash('sha256').update(inputs.adjudication.schema).digest('hex') });
  const resumed = await executeNativeDownstream(connection, { ...request, adjudicationOnly: true }, inputs, evaluate, event => events.push(event));
  assert.equal(resumed.groupCount, 20);
  assert.equal(resumed.comparisonCount, 10);
  assert.equal(resumed.readyForUi, false);
  assert.ok(calls.filter(phase => phase === 'adjudication').length > 1);
  assert.equal(calls.filter(phase => phase === 'routing').length, 1);
  assert.equal(calls.filter(phase => phase === 'consolidation').length, 1);
  assert.equal(calls.filter(phase => phase === 'synthesis').length, 3);
  assert.equal(events.filter(event => event.state === 'plan' && event.phase === 'synthesis').at(-1).recoveredBatchCount, 2);
  assert.equal(events.filter(event => event.state === 'plan' && event.phase === 'synthesis').at(-1).batchCount, 0);
  assert.equal(connection.get('SELECT count(*) AS count FROM changes').count, 0);
  assert.equal(connection.get('SELECT outcome FROM analysis_runs WHERE id = ?', [run.runId]).outcome, 'complete');
});

for (const scale of [
  { name: 'large source evidence', sourceRepeats: 450, summaryRepeats: 1, stageBytes: 30000, envelopeBytes: 40000 },
  { name: 'aggregate summary larger than one request', sourceRepeats: 45, summaryRepeats: 22, stageBytes: 6000, envelopeBytes: 10000 },
]) test(`native synthesis refuses an oversized whole component without partial inference: ${scale.name}`, async context => {
  const { connection, databasePath, binding, run, profileId, assignments, sourceVersionIds } = nativeAssessmentFixture(context,
    { sourceCount: 6, fileBacked: true, content: 'Captured enforceable synthetic requirement. '.repeat(scale.sourceRepeats), taskCodes: ['assessment', 'reconciliation', 'adjudication'] });
  connection.exec("INSERT INTO action_definitions VALUES (2, 'add', 'Add'); INSERT INTO guidance_sections VALUES (1, 0, 'Validation'); INSERT INTO source_provenance_codes VALUES ('synthetic', 'Synthetic evidence')");
  for (const sourceVersionId of sourceVersionIds) {
    const recorded = recordEvaluationRequest(connection, { binding, runId: run.runId, profileId, sourceVersionIds: [sourceVersionId] });
    commitAssessmentResults(connection, { binding, runId: run.runId, evaluationId: recorded.evaluationId,
      inputFingerprint: recorded.inputFingerprint, result: nativeAssessmentResult(recorded) });
  }
  const inputs = { reconciliation: { prompt: 'Synthetic reconciliation instructions.', schema: '{"type":"object"}' },
    adjudication: { prompt: 'Synthetic comparison instructions.', schema: '{"type":"object"}' } };
  const profiles = {};
  for (const [task, assignment] of [['reconciliation', assignments[1]], ['adjudication', assignments[2]]]) {
    profiles[task] = registerEvaluatorProfile(connection, { code: `native-sharded-${task}`, taskCode: task, llmAssignmentId: assignment.assignmentId,
      promptSha256: createHash('sha256').update(inputs[task].prompt).digest('hex'), behaviorSha256: 'e'.repeat(64),
      resultContractSha256: createHash('sha256').update(inputs[task].schema).digest('hex') });
  }
  const budgets = { stagePayloadBudgetBytes: scale.stageBytes, evaluatorPayloadBudgetBytes: scale.envelopeBytes };
  const request = { binding, runId: run.runId, sourceProfileId: profileId, reconciliationProfileId: profiles.reconciliation,
    adjudicationProfileId: profiles.adjudication, expectedHeadRunId: null, budgets };
  const calls = [];
  const evaluate = async (recorded, { phase, evaluatorInput }) => {
    const input = JSON.parse(recorded.serializedInput);
    assert.ok(Buffer.byteLength(recorded.serializedInput, 'utf8') <= budgets.stagePayloadBudgetBytes);
    assert.ok(measureAssessmentInputBytes(recorded.serializedInput, evaluatorInput) <= budgets.evaluatorPayloadBudgetBytes);
    calls.push(phase);
    if (phase === 'routing' || phase === 'consolidation') return { schemaVersion: 4, stage: 'reconciliation', phase,
      components: [{ assessmentResultIds: input.assessments.map(member => member.assessmentResultId), ruleVersionIds: input.ruleVersionIds,
        semanticSummary: 'Related independently enforceable requirements. '.repeat(scale.summaryRepeats) }] };
    throw new Error('Oversized component must not dispatch synthesis or adjudication');
  };
  await assert.rejects(executeNativeDownstream(connection, request, inputs, evaluate),
    { code: 'workbench-evaluator-input-budget-exceeded', phase: 'synthesis' });
  assert.equal(calls.includes('synthesis'), false);
  assert.equal(calls.includes('adjudication'), false);
  assert.equal(connection.get('SELECT count(*) AS count FROM group_versions').count, 0);
  assert.equal(connection.get('SELECT count(*) AS count FROM workspace_analysis_head').count, 0);
  assert.equal(connection.get('SELECT count(*) AS count FROM consolidated_components').count, 1);
  const component = connection.get('SELECT id, semantic_summary FROM consolidated_components');
  const allMembers = connection.all('SELECT assessment_result_id AS id FROM consolidated_component_members WHERE component_id = ? ORDER BY id',
    [component.id]).map(row => row.id);
  assert.equal(allMembers.length, 6);
  const whole = prepareEvaluationInput(connection, { binding, runId: run.runId, profileId: profiles.reconciliation, sourceVersionIds,
    assessmentResultIds: allMembers, ruleVersionIds: [], consolidatedComponentIds: [component.id], reconciliationPhase: 'synthesis' });
  assert.ok(Buffer.byteLength(whole.serializedInput, 'utf8') > budgets.stagePayloadBudgetBytes ||
    measureAssessmentInputBytes(whole.serializedInput, inputs.reconciliation) > budgets.evaluatorPayloadBudgetBytes);
  assert.equal(JSON.parse(whole.serializedInput).components[0].semanticSummary, component.semantic_summary);
  assert.throws(() => prepareEvaluationInput(connection, { binding, runId: run.runId, profileId: profiles.reconciliation,
    sourceVersionIds: sourceVersionIds.slice(0, 1), assessmentResultIds: allMembers.slice(0, 1), ruleVersionIds: [],
    consolidatedComponentIds: [component.id], reconciliationPhase: 'synthesis' }), /complete canonical component/);
  const inferenceCalls = calls.length;
  const view = connection.all(`SELECT member.assessment_result_id, source.captured_text FROM consolidated_component_members member
    JOIN assessment_results assessment ON assessment.id = member.assessment_result_id JOIN source_versions source ON source.id = assessment.source_version_id
    WHERE member.component_id = ? ORDER BY member.assessment_result_id`, [component.id]);
  assert.equal(view.length, 6);
  assert.ok(view.every(row => row.captured_text.length > 40 * scale.sourceRepeats));
  const databaseBytes = () => ['', '-wal'].filter(suffix => existsSync(databasePath + suffix))
    .map(suffix => ({ suffix, sha256: createHash('sha256').update(readFileSync(databasePath + suffix)).digest('hex') }));
  const beforeRead = databaseBytes();
  const reader = openWorkbenchSqlite({ mode: 'read-only', databasePath });
  try {
    const workspace = readNativeWorkspaceView(reader, { binding });
    assert.equal(workspace.analysis.runs.find(row => row.runId === run.runId).outcome, 'running');
    assert.ok(workspace.sources.every(source => source.presence === 'present'));
    assert.equal(workspace.groups.length, 0);
    assert.equal(workspace.findings.length, 0);
    assert.deepEqual(readNativeWorkspaceView(reader, { binding }), workspace);
    assert.equal(reader.isTransaction, false);
  } finally { reader.close(); }
  assert.deepEqual(databaseBytes(), beforeRead);
  assert.equal(calls.length, inferenceCalls);
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
    sourceVersionIds, assessmentResultIds: resultIds, ruleVersionIds: [], reconciliationPhase: 'routing' });
  const completed = bridge('reconciliation-components', { binding, runId: run.runId, evaluationId: recorded.evaluationId,
    inputFingerprint: recorded.inputFingerprint, result: { schemaVersion: 4, stage: 'reconciliation', phase: 'routing',
      components: [{ assessmentResultIds: resultIds, ruleVersionIds: [], semanticSummary: 'Validate captured input' }] } });
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
    assert.equal(events.find(event => event.state === 'failed').failureStage, 'commit');
    assert.ok(connection.get('SELECT failure_reason FROM evaluations WHERE id = ?', [calls[1].evaluationId]).failure_reason);
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

test('assessment execution guard bridge audits its typed busy refusal without raw errors or domain writes', async context => {
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
      const packets = error.stdout.trim().split('\n').map(line => JSON.parse(line));
      assert.equal(packets[0].kind, 'audit-context');
      assert.equal(packets[0].context.persistence, 'recorded');
      assert.equal(packets[0].context.activeActionCode, null);
      assert.deepEqual(packets[1], { kind: 'execution-refused', code: 'workbench-execution-already-running' });
      assert.equal(packets.length, 2);
      return true;
    });
    assert.equal(readFileSync(databasePath + '.assessment.lock', 'utf8'), owner);
    assert.equal(connection.get('SELECT count(*) AS count FROM evaluations').count, 0);
    assert.deepEqual(connection.all('SELECT outcome FROM audit_events WHERE correlation_id IS NOT NULL ORDER BY id').map(row => row.outcome), ['started', 'refused']);
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
  for (const revision of [1, 2]) connection.run(`INSERT INTO catalog_versions VALUES (?, NULL, ?, 'managed-catalog', ?, 1, '2026-11-05', 1, ?, 'synthetic',
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
