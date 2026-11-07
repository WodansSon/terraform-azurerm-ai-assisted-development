import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { openWorkbenchSqlite } from '../../modules/workbench/WorkbenchSqlite.mjs';
import { normalizeSourceRecord, normalizeSourceRecords, normalizeLegacySourceRecords, sourceTextHash } from '../../modules/workbench/WorkbenchSourceRecords.mjs';
import { createSourceIngestionSchema, registerSourceDefinition, ingestSourceCollection, ingestSourceInventory, readSourceCollection } from '../../modules/workbench/WorkbenchSourceIngestion.mjs';
import { createWorkspaceIdentitySchema, readCurrentProtectedSnapshot, advanceCurrentProtectedSnapshot } from '../../modules/workbench/WorkbenchWorkspace.mjs';
import { createProtectedSnapshotSchema, ingestProtectedCapture, readProtectedSnapshot, protectedCaptureFromParser } from '../../modules/workbench/WorkbenchProtectedSnapshots.mjs';
import { createAuthoredAuditSchema, refreshAuthoredInputs, readAuthoredStartupAudit, recordAuthoredStartupFailure } from '../../modules/workbench/WorkbenchAuthoredRefresh.mjs';

function authoredFixture(context) {
  const connection = protectedFixture(context);
  connection.exec(`
    CREATE TABLE team_profiles (id INTEGER PRIMARY KEY, code TEXT NOT NULL UNIQUE, label TEXT NOT NULL) STRICT;
    CREATE TABLE actors (id INTEGER PRIMARY KEY, actor_kind TEXT NOT NULL CHECK(actor_kind IN ('person', 'system')), provider_code TEXT, provider_actor_id TEXT, display_name TEXT NOT NULL, UNIQUE(provider_code, provider_actor_id)) STRICT;
    CREATE TABLE codeowner_snapshots (id INTEGER PRIMARY KEY, repository_context_id INTEGER NOT NULL REFERENCES repository_contexts(id), source_relative_path TEXT NOT NULL, captured_text TEXT NOT NULL, content_sha256 TEXT NOT NULL, parser_version TEXT NOT NULL, captured_at TEXT NOT NULL) STRICT;
    CREATE TABLE change_revisions (id INTEGER PRIMARY KEY, change_id INTEGER NOT NULL, proposal_version_id INTEGER NOT NULL, revision INTEGER NOT NULL, selected_action_id INTEGER, target_rule_id INTEGER, baseline_rule_version_id INTEGER, wording_version_id INTEGER NOT NULL, rationale TEXT NOT NULL, recorded_by_actor_id INTEGER NOT NULL, recorded_at TEXT NOT NULL, UNIQUE(change_id, revision), UNIQUE(change_id, id), UNIQUE(change_id, proposal_version_id, id)) STRICT;
    CREATE TABLE issue_resolutions (id INTEGER PRIMARY KEY, decision_code TEXT NOT NULL, rationale TEXT NOT NULL, recorded_by_actor_id INTEGER NOT NULL, recorded_at TEXT NOT NULL) STRICT;
    CREATE TABLE plan_versions (id INTEGER PRIMARY KEY, plan_id INTEGER NOT NULL, revision INTEGER NOT NULL, base_catalog_id INTEGER NOT NULL, recorded_by_actor_id INTEGER NOT NULL, recorded_at TEXT NOT NULL, UNIQUE(plan_id, revision), UNIQUE(plan_id, id), UNIQUE(id, base_catalog_id)) STRICT;
    CREATE TABLE approvals (id INTEGER PRIMARY KEY, plan_version_id INTEGER NOT NULL, catalog_id INTEGER NOT NULL, artifact_id INTEGER NOT NULL, approved_by_actor_id INTEGER NOT NULL, permission_snapshot_id INTEGER NOT NULL, approved_at TEXT NOT NULL, UNIQUE(id, catalog_id)) STRICT;
    CREATE TABLE catalog_applications (id INTEGER PRIMARY KEY, operation_key TEXT NOT NULL UNIQUE, approval_id INTEGER NOT NULL, base_catalog_id INTEGER NOT NULL, resulting_catalog_id INTEGER NOT NULL, requested_by_actor_id INTEGER NOT NULL, permission_snapshot_id INTEGER NOT NULL, created_at TEXT NOT NULL, started_at TEXT, completed_at TEXT, outcome TEXT NOT NULL CHECK(outcome IN ('pending', 'running', 'complete', 'failed'))) STRICT;
    CREATE TABLE deployments (id INTEGER PRIMARY KEY, application_id INTEGER NOT NULL, target_context_id INTEGER NOT NULL, deployed_by_actor_id INTEGER NOT NULL, permission_snapshot_id INTEGER NOT NULL, started_at TEXT NOT NULL, completed_at TEXT, outcome TEXT NOT NULL CHECK(outcome IN ('running', 'complete', 'failed'))) STRICT;
    CREATE TABLE database_backups (id INTEGER PRIMARY KEY, database_guid TEXT NOT NULL, requested_by_actor_id INTEGER NOT NULL, requested_at TEXT NOT NULL, completed_at TEXT, local_path TEXT NOT NULL, content_sha256 TEXT, outcome TEXT NOT NULL CHECK(outcome IN ('running', 'complete', 'failed', 'cancelled')), verification_outcome TEXT) STRICT;
    CREATE TABLE codeowner_refreshes (id INTEGER PRIMARY KEY, repository_context_id INTEGER NOT NULL, successful_snapshot_id INTEGER, initiated_by_actor_id INTEGER, attempted_at TEXT NOT NULL, observed_sha256 TEXT, outcome TEXT NOT NULL CHECK(outcome IN ('changed', 'unchanged', 'failed')), failure_code TEXT) STRICT;
    CREATE TABLE evaluations (id INTEGER PRIMARY KEY, evaluator_profile_id INTEGER NOT NULL, input_fingerprint TEXT NOT NULL, requested_at TEXT NOT NULL, completed_at TEXT, outcome TEXT NOT NULL CHECK(outcome IN ('running', 'complete', 'failed', 'cancelled')), failure_code TEXT) STRICT;
    INSERT INTO team_profiles VALUES (1, 'synthetic-profile', 'Synthetic profile');
    INSERT INTO actors VALUES (1, 'system', NULL, NULL, 'Synthetic server');
  `);
  createWorkspaceIdentitySchema(connection);
  createAuthoredAuditSchema(connection);
  const binding = { databaseGuid: '12345678-1234-4234-8234-123456789abc', repositoryId: 1 };
  connection.run('INSERT INTO workspace_identity(id, database_guid, team_profile_id, origin_context_id, created_by_actor_id, created_at) VALUES (1, ?, 1, 1, 1, ?)', [binding.databaseGuid, '2026-11-05T00:00:00.000Z']);
  const definitionVersionId = registerSourceDefinition(connection, profile());
  const content = '### IMPL-PROPOSAL-001: Synthetic proposal\n\n- Rule: Synthetic proposed wording\n- Provenance: local-safeguard\n- Rationale: Synthetic rationale\n- Status: active';
  const files = ['implementation', 'testing', 'documentation'].map(surface => {
    const text = `---\ndescription: Synthetic proposal file\nsurface: ${surface}\n---\n\n${surface === 'implementation' ? content : ''}\n`;
    return { relativePath: `rules/proposals/${surface}.rules.md`, contentBytes: Buffer.from(text), contentSha256: sourceTextHash(text) };
  });
  const proposals = request(definitionVersionId, proposalRecords({ sourceId: 'IMPL-PROPOSAL-001', title: 'Synthetic proposal', location: files[0].relativePath, content, contentSha256: sourceTextHash(content) }), null, {
    repositoryContextId: 1, files, revision: { kind: 'repository-worktree', resolvedCommit: '1'.repeat(40), worktreeDirty: true, worktreeSha256: sourceTextHash('Synthetic authored worktree') },
  });
  let attempt = 0;
  const next = (overrides = {}) => ({
    ...binding, repositoryContextId: 1, startupAttemptGuid: `12345678-1234-4234-8234-${String(++attempt).padStart(12, '0')}`,
    profile: { proposalsRoot: 'rules/proposals', protectedRoot: 'rules/protected' }, proposals,
    protectedCapture: protectedCapture(), expectedProtectedSnapshotId: null, ...overrides,
  });
  return { connection, binding, next };
}

test('authored refresh commits both captures, current references and complete typed startup audit atomically', context => {
  const { connection, binding, next } = authoredFixture(context);
  const first = next();
  const saved = refreshAuthoredInputs(connection, first);
  assert.equal(connection.isTransaction, false);
  assert.equal(readSourceCollection(connection, 'team-one').collectionId, saved.collectionId);
  assert.equal(readCurrentProtectedSnapshot(connection, binding).snapshotId, saved.protectedSnapshotId);
  const audit = readAuthoredStartupAudit(connection, first);
  assert.equal(audit.length, 8);
  assert.equal(audit.filter(event => event.action_code === 'input-check').length, 6);
  assert.equal(audit.filter(event => event.outcome === 'complete').length, 2);
  assert.ok(audit.every(event => event.actor_id === 1 && event.severity === 'info' && event.targets.length > 0));
  const second = next({ proposals: { ...first.proposals, expectedCollectionId: saved.collectionId }, expectedProtectedSnapshotId: saved.protectedSnapshotId });
  const unchanged = refreshAuthoredInputs(connection, second);
  assert.equal(unchanged.protectedSnapshotId, saved.protectedSnapshotId);
  assert.equal(readAuthoredStartupAudit(connection, second).filter(event => event.outcome === 'unchanged').length, 6);
  assert.equal(connection.get('SELECT count(*) AS count FROM protected_snapshots').count, 1);
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
});

test('authored refresh rolls back both heads and new facts when audit fails, then separately records failure', context => {
  const { connection, binding, next } = authoredFixture(context);
  connection.exec("CREATE TRIGGER reject_success_audit BEFORE INSERT ON audit_events WHEN NEW.severity = 'info' BEGIN SELECT RAISE(ABORT, 'Synthetic audit storage failure'); END");
  const attempt = next();
  assert.throws(() => refreshAuthoredInputs(connection, attempt), error => error.message.includes('Synthetic audit storage failure') && error.auditPersistence === 'recorded');
  assert.equal(readSourceCollection(connection, 'team-one'), null);
  assert.equal(readCurrentProtectedSnapshot(connection, binding), null);
  for (const table of ['source_collections', 'source_collection_files', 'protected_snapshots', 'protected_files', 'rules', 'rule_versions', 'wording_versions']) assert.equal(connection.get(`SELECT count(*) AS count FROM ${table}`).count, 0, table);
  const audit = readAuthoredStartupAudit(connection, attempt);
  assert.equal(audit.length, 1);
  assert.equal(audit[0].severity, 'error');
  assert.equal(audit[0].targets.length, 0);
  assert.equal(connection.isTransaction, false);
  connection.exec('DROP TRIGGER reject_success_audit');
  assert.ok(refreshAuthoredInputs(connection, next()).collectionId > 0);
});

test('authored refresh records removal transitions once and preserves historical source and protected versions', context => {
  const { connection, next } = authoredFixture(context);
  const first = next();
  const saved = refreshAuthoredInputs(connection, first);
  const emptyFiles = files => files.map(file => {
    const surface = file.relativePath.split('/').at(-1).split('.')[0];
    const text = `---\ndescription: Synthetic empty file\nsurface: ${surface}\n---\n`;
    return { ...file, contentBytes: Buffer.from(text), contentSha256: sourceTextHash(text) };
  });
  const removedRequest = next({
    proposals: { ...first.proposals, expectedCollectionId: saved.collectionId, records: [], files: emptyFiles(first.proposals.files) },
    protectedCapture: { ...first.protectedCapture, blocks: [], files: emptyFiles(first.protectedCapture.files) }, expectedProtectedSnapshotId: saved.protectedSnapshotId,
  });
  const removed = refreshAuthoredInputs(connection, removedRequest);
  const warnings = readAuthoredStartupAudit(connection, removedRequest).filter(event => event.severity === 'warning');
  assert.equal(warnings.length, 2);
  assert.ok(warnings.every(event => event.targets.length === 3));
  assert.deepEqual(warnings.map(event => event.targets.map(target => target.target_role)), [['subject', 'before', 'after'], ['subject', 'before', 'after']]);
  assert.equal(readSourceCollection(connection, 'team-one').records[0].presence, 'missing-last-known');
  assert.equal(readProtectedSnapshot(connection, removed.protectedSnapshotId).blocks.length, 0);
  assert.equal(readProtectedSnapshot(connection, saved.protectedSnapshotId).blocks.length, 1);
  const againRequest = next({ ...removedRequest, startupAttemptGuid: next().startupAttemptGuid, proposals: { ...removedRequest.proposals, expectedCollectionId: removed.collectionId }, expectedProtectedSnapshotId: removed.protectedSnapshotId });
  refreshAuthoredInputs(connection, againRequest);
  assert.equal(readAuthoredStartupAudit(connection, againRequest).filter(event => event.severity === 'warning').length, 0);
  assert.equal(connection.get('SELECT count(*) AS count FROM rule_versions').count, 1);
});

test('authored startup failures retain exact missing-path scope and audit targets reject fabricated or multiple subjects', context => {
  const { connection, next } = authoredFixture(context);
  const attempt = next();
  const { proposals, protectedCapture: capture, expectedProtectedSnapshotId, ...failureRequest } = attempt;
  const audit = recordAuthoredStartupFailure(connection, { ...failureRequest, failures: [
    { collection: 'proposals', code: 'missing-directory' }, { collection: 'protected', surfaceCode: 'testing', code: 'missing-file' },
  ] });
  assert.equal(audit.length, 2);
  assert.equal(audit[0].authored_relative_path, 'rules/proposals');
  assert.equal(audit[0].authored_surface_id, null);
  assert.equal(audit[1].authored_relative_path, 'rules/protected/testing.rules.md');
  assert.ok(audit.every(event => event.targets.length === 0));
  assert.throws(() => connection.run("INSERT INTO audit_targets(event_id, target_role) VALUES (?, 'subject')", [audit[0].id]), /CHECK/);
  assert.throws(() => connection.run("INSERT INTO audit_targets(event_id, target_role, source_collection_id) VALUES (?, 'subject', 999)", [audit[0].id]), { errcode: 787 });
  assert.throws(() => connection.run("INSERT INTO audit_targets(event_id, target_role, source_collection_id, rule_version_id) VALUES (?, 'subject', 999, 999)", [audit[0].id]), /CHECK/);
  assert.throws(() => connection.run('DELETE FROM audit_events WHERE id = ?', [audit[0].id]), /append-only/);
  const mixed = { ...failureRequest, startupAttemptGuid: next().startupAttemptGuid,
    validatedChecks: [{ collection: 'proposals', surfaceCode: 'implementation' }],
    failures: [{ collection: 'protected', code: 'read-failed' }],
  };
  const mixedAudit = recordAuthoredStartupFailure(connection, mixed);
  assert.equal(mixedAudit.length, 2);
  assert.equal(mixedAudit[0].outcome, 'valid');
  assert.equal(mixedAudit[1].authored_surface_id, null);
  assert.ok(mixedAudit.every(event => event.targets.length === 0));
  assert.equal(readSourceCollection(connection, 'team-one'), null);
  assert.throws(() => recordAuthoredStartupFailure(connection, { ...mixed, validatedChecks: [{ collection: 'protected', surfaceCode: 'testing' }] }), /failed or duplicate scope/);
});

test('authored refresh preserves an existing workspace through protected, reference and audit-target failures', context => {
  for (const stage of ['protected', 'reference', 'audit-target', 'all-audit']) {
    const { connection, binding, next } = authoredFixture(context);
    const first = next();
    const saved = refreshAuthoredInputs(connection, first);
    const facts = () => Object.fromEntries(connection.all("SELECT name FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'audit_%' ORDER BY name").map(({ name }) => [name, connection.get(`SELECT count(*) AS count FROM ${name}`).count]));
    const before = facts();
    const attempt = next({ proposals: { ...first.proposals, expectedCollectionId: saved.collectionId }, expectedProtectedSnapshotId: saved.protectedSnapshotId });
    const definitions = {
      protected: "BEFORE INSERT ON protected_members BEGIN SELECT RAISE(ABORT, 'Synthetic protected failure'); END",
      reference: "BEFORE UPDATE OF current_protected_snapshot_id ON workspace_identity BEGIN SELECT RAISE(ABORT, 'Synthetic reference failure'); END",
      'audit-target': "BEFORE INSERT ON audit_targets BEGIN SELECT RAISE(ABORT, 'Synthetic audit target failure'); END",
      'all-audit': "BEFORE INSERT ON audit_events BEGIN SELECT RAISE(ABORT, 'Synthetic all audit failure'); END",
    };
    if (stage === 'protected') {
      const capture = attempt.protectedCapture;
      const original = capture.blocks[0];
      const content = original.content.replace('Preserve synthetic wording.', 'Preserve changed synthetic wording.');
      attempt.protectedCapture = { ...capture, blocks: [{ ...original, content, contentSha256: sourceTextHash(content), text: 'Preserve changed synthetic wording.' }], files: capture.files.map(file => {
        if (file.relativePath !== original.relativePath) return file;
        const text = file.contentBytes.toString('utf8').replace(original.content, content);
        return { ...file, contentBytes: Buffer.from(text), contentSha256: sourceTextHash(text) };
      }) };
    }
    connection.exec(`CREATE TRIGGER reject_refresh_stage ${definitions[stage]}`);
    assert.throws(() => refreshAuthoredInputs(connection, attempt), error => error.auditPersistence === (stage === 'all-audit' ? 'not-recorded' : 'recorded'), stage);
    assert.deepEqual(facts(), before, stage);
    assert.equal(readSourceCollection(connection, 'team-one').collectionId, saved.collectionId, stage);
    assert.equal(readCurrentProtectedSnapshot(connection, binding).snapshotId, saved.protectedSnapshotId, stage);
    assert.equal(readProtectedSnapshot(connection, saved.protectedSnapshotId).blocks[0].text, 'Preserve synthetic wording.', stage);
    assert.equal(readAuthoredStartupAudit(connection, attempt).length, stage === 'all-audit' ? 0 : 1, stage);
    assert.equal(connection.isTransaction, false, stage);
    assert.deepEqual(connection.all('PRAGMA foreign_key_check'), [], stage);
  }
});

test('authored refresh rejects incomplete captures, stale scopes and enclosing transactions without partial heads', context => {
  const { connection, binding, next } = authoredFixture(context);
  const first = next();
  const saved = refreshAuthoredInputs(connection, first);
  const complete = () => next({ proposals: { ...first.proposals, expectedCollectionId: saved.collectionId }, expectedProtectedSnapshotId: saved.protectedSnapshotId });
  for (const malformed of [
    { ...complete(), protectedCapture: { ...first.protectedCapture, files: first.protectedCapture.files.slice(1) } },
    { ...complete(), proposals: { ...complete().proposals, files: first.proposals.files.slice(1) } },
    { ...complete(), expectedProtectedSnapshotId: null },
    { ...complete(), proposals: { ...complete().proposals, expectedCollectionId: null } },
    { ...complete(), protectedCapture: { ...first.protectedCapture, files: first.protectedCapture.files.map((file, index) => index ? file : { ...file, contentBytes: Buffer.from('Tampered file bytes') }) } },
  ]) {
    assert.throws(() => refreshAuthoredInputs(connection, malformed));
    assert.equal(readSourceCollection(connection, 'team-one').collectionId, saved.collectionId);
    assert.equal(readCurrentProtectedSnapshot(connection, binding).snapshotId, saved.protectedSnapshotId);
    assert.equal(readAuthoredStartupAudit(connection, malformed).filter(event => event.severity === 'info').length, 0);
  }
  assert.throws(() => refreshAuthoredInputs(connection, { ...complete(), repositoryId: 2 }), /bound repository/);
  connection.exec('BEGIN IMMEDIATE');
  assert.throws(() => refreshAuthoredInputs(connection, complete()), /own its outer transaction/);
  const { proposals, protectedCapture: capture, expectedProtectedSnapshotId, ...failureRequest } = complete();
  assert.throws(() => recordAuthoredStartupFailure(connection, { ...failureRequest, failures: [{ collection: 'protected', code: 'missing-directory' }] }), /separate transaction/);
  connection.exec('ROLLBACK');
  assert.equal(connection.get('SELECT count(*) AS count FROM protected_snapshots').count, 1);
});

test('authored refresh does not claim committed failure audit after a rollback failure', context => {
  const { connection, binding, next } = authoredFixture(context);
  const first = next();
  const saved = refreshAuthoredInputs(connection, first);
  const attempt = next({ proposals: { ...first.proposals, expectedCollectionId: saved.collectionId }, expectedProtectedSnapshotId: saved.protectedSnapshotId });
  connection.exec("CREATE TRIGGER reject_success_audit BEFORE INSERT ON audit_events WHEN NEW.severity = 'info' BEGIN SELECT RAISE(ABORT, 'Synthetic success audit failure'); END");
  const failingConnection = { ...connection, exec(sql) {
    if (sql.startsWith('ROLLBACK TO workbench_authored_refresh')) throw new Error('Synthetic rollback I/O failure');
    return connection.exec(sql);
  } };
  Object.defineProperty(failingConnection, 'isTransaction', { get: () => connection.isTransaction });
  try {
    assert.throws(() => refreshAuthoredInputs(failingConnection, attempt), error => error.auditPersistence === 'uncertain');
    assert.equal(connection.isTransaction, true);
    assert.equal(readAuthoredStartupAudit(connection, attempt).length, 0);
  } finally { connection.exec('ROLLBACK'); }
  assert.equal(readSourceCollection(connection, 'team-one').collectionId, saved.collectionId);
  assert.equal(readCurrentProtectedSnapshot(connection, binding).snapshotId, saved.protectedSnapshotId);
});

function protectedFixture(context) {
  const connection = fixture(context);
  connection.exec(`
    CREATE TABLE guidance_surfaces (id INTEGER PRIMARY KEY, code TEXT NOT NULL UNIQUE, label TEXT NOT NULL) STRICT;
    CREATE TABLE rules (id INTEGER PRIMARY KEY, displayed_id TEXT NOT NULL UNIQUE, rule_kind TEXT NOT NULL CHECK(rule_kind IN ('managed', 'protected')), naming_scheme_id INTEGER) STRICT;
    CREATE TABLE wording_versions (id INTEGER PRIMARY KEY, text TEXT NOT NULL, content_sha256 TEXT NOT NULL, created_at TEXT NOT NULL) STRICT;
    CREATE TABLE rule_versions (
      id INTEGER PRIMARY KEY, rule_id INTEGER NOT NULL REFERENCES rules(id), revision INTEGER NOT NULL CHECK(revision > 0),
      wording_version_id INTEGER NOT NULL REFERENCES wording_versions(id), lifecycle TEXT NOT NULL CHECK(lifecycle IN ('active', 'retired')),
      retirement_reason TEXT, origin_code TEXT, documentation_gap INTEGER CHECK(documentation_gap IN (0, 1)), UNIQUE(rule_id, revision), UNIQUE(rule_id, id)
    ) STRICT;
    CREATE TABLE rule_provenances (rule_version_id INTEGER NOT NULL REFERENCES rule_versions(id), ordinal INTEGER NOT NULL CHECK(ordinal >= 0), code TEXT NOT NULL, PRIMARY KEY(rule_version_id, ordinal), UNIQUE(rule_version_id, code)) STRICT;
    INSERT INTO guidance_surfaces VALUES (1, 'implementation', 'Implementation'), (2, 'testing', 'Testing'), (3, 'documentation', 'Documentation');
    INSERT INTO repository_contexts VALUES (1, 1, 'refs/heads/synthetic', '1111111111111111111111111111111111111111', '2026-11-05T00:00:00.000Z');
  `);
  createProtectedSnapshotSchema(connection);
  return connection;
}

function protectedCapture() {
  const content = '### IMPL-CAPTURE-001: Synthetic protection\n\n- Rule: Preserve synthetic wording.\n- Provenance: local-safeguard\n- Rationale: Synthetic protection rationale.';
  const files = ['implementation', 'testing', 'documentation'].map(surface => {
    const text = `---\ndescription: Synthetic capture\nsurface: ${surface}\n---\n\n${surface === 'implementation' ? content : ''}\n`;
    return { relativePath: `rules/protected/${surface}.rules.md`, contentBytes: Buffer.from(text), contentSha256: sourceTextHash(text) };
  });
  return {
    repositoryContextId: 1, parserContractSha256: sourceTextHash('Synthetic protected parser contract'), requiredFiles: files.map(file => file.relativePath), files,
    blocks: [{ id: 'IMPL-CAPTURE-001', title: 'Synthetic protection', surfaceCode: 'implementation', relativePath: files[0].relativePath,
      content, contentSha256: sourceTextHash(content), text: 'Preserve synthetic wording.', provenance: 'local-safeguard', protectionReason: 'Synthetic protection rationale.' }],
  };
}

test('protected persistence round-trips exact bytes and metadata, reuses versions and keeps empty snapshots', context => {
  const connection = protectedFixture(context);
  const capture = protectedCapture();
  const saved = ingestProtectedCapture(connection, capture);
  assert.equal(saved.files.length, 3);
  for (const file of capture.files) assert.deepEqual(saved.files.find(item => item.relativePath === file.relativePath), file);
  assert.deepEqual(saved.blocks, [{ ...capture.blocks[0], ruleVersionId: 1 }]);
  assert.deepEqual(readProtectedSnapshot(connection, saved.snapshotId), saved);
  assert.equal(ingestProtectedCapture(connection, capture).snapshotId, saved.snapshotId);
  const empty = { ...capture, blocks: [], files: capture.files.map(file => {
    const text = `---\ndescription: Synthetic empty capture\nsurface: ${file.relativePath.split('/').at(-1).split('.')[0]}\n---\n`;
    return { ...file, contentBytes: Buffer.from(text), contentSha256: sourceTextHash(text) };
  }) };
  const removed = ingestProtectedCapture(connection, empty);
  assert.equal(removed.blocks.length, 0);
  assert.equal(removed.files.length, 3);
  assert.equal(readProtectedSnapshot(connection, saved.snapshotId).blocks.length, 1);
  assert.equal(connection.get('SELECT count(*) AS count FROM rule_versions').count, 1);
  assert.throws(() => connection.run('UPDATE protected_files SET content = ? WHERE snapshot_id = ?', [Buffer.from('changed'), saved.snapshotId]), /immutable/);
  assert.throws(() => connection.run('UPDATE wording_versions SET text = ?', ['Changed captured wording']), /immutable/);
  assert.throws(() => connection.run('UPDATE rule_versions SET lifecycle = ?', ['retired']), /immutable/);
  assert.throws(() => connection.run('UPDATE rule_provenances SET code = ?', ['inferred-maintainer-convention']), /immutable/);
  assert.throws(() => connection.run('UPDATE rules SET displayed_id = ?', ['IMPL-CHANGED-001']), /immutable/);
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
});

test('real PowerShell protected capture transport feeds the SQLite owner without losing metadata or creating another store', context => {
  const connection = protectedFixture(context);
  const capture = protectedCapture();
  const root = mkdtempSync(join(tmpdir(), 'workbench-protected-persistence-'));
  context.after(() => rmSync(root, { recursive: true, force: true }));
  for (const file of capture.files) {
    mkdirSync(dirname(join(root, file.relativePath)), { recursive: true });
    writeFileSync(join(root, file.relativePath), file.contentBytes);
  }
  const modulePath = fileURLToPath(new URL('../../modules/source-parsers/ProtectedRules.psm1', import.meta.url));
  const parsed = JSON.parse(execFileSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', `
    $ErrorActionPreference = 'Stop'
    $request = [Console]::In.ReadToEnd() | ConvertFrom-Json -AsHashtable
    Import-Module $request.modulePath -Force
    Get-ProtectedRulesCapture -SourceRoot (Join-Path $request.root 'rules/protected') -RepositoryRoot $request.root | ConvertTo-Json -Depth 20 -Compress
  `], { input: JSON.stringify({ root, modulePath }), encoding: 'utf8' }));
  const { files, blocks, ...authority } = capture;
  const transported = protectedCaptureFromParser(parsed, authority);
  assert.deepEqual(transported, { ...capture, files: [...files].sort((left, right) => left.relativePath < right.relativePath ? -1 : 1) });
  const saved = ingestProtectedCapture(connection, transported);
  assert.deepEqual(saved.blocks, [{ ...blocks[0], ruleVersionId: 1 }]);
  parsed.Catalog.rules[0].text = 'Changed projected wording';
  assert.throws(() => protectedCaptureFromParser(parsed, authority), /differ/);
});

function fixture(context) {
  const connection = openWorkbenchSqlite({ mode: 'memory' });
  context.after(() => connection.close());
  connection.exec(`
    CREATE TABLE repositories (
      id INTEGER PRIMARY KEY, provider_code TEXT NOT NULL, provider_repository_id TEXT, canonical_name TEXT NOT NULL,
      UNIQUE(provider_code, canonical_name)
    ) STRICT;
    CREATE TABLE repository_contexts (
      id INTEGER PRIMARY KEY, repository_id INTEGER NOT NULL REFERENCES repositories(id), branch_ref TEXT NOT NULL,
      commit_oid TEXT NOT NULL, observed_at TEXT NOT NULL
    ) STRICT;
    CREATE TABLE applicability_definitions (id INTEGER PRIMARY KEY, code TEXT NOT NULL UNIQUE, label TEXT NOT NULL, renderer_code TEXT NOT NULL) STRICT;
    INSERT INTO repositories VALUES (1, 'fixture', NULL, 'synthetic/team-one'), (2, 'fixture', NULL, 'synthetic/team-two');
    INSERT INTO applicability_definitions VALUES (1, 'implementation', 'Implementation', 'fixture-renderer'), (2, 'custom-language', 'Custom language', 'fixture-renderer');
  `);
  createSourceIngestionSchema(connection);
  for (const code of ['local-safeguard', 'confirmed-maintainer-convention', 'inferred-maintainer-convention', 'published-upstream-standard', 'unclassified']) {
    connection.run('INSERT INTO source_provenance_codes VALUES (?, ?)', [code, 'Synthetic provenance label']);
  }
  return connection;
}

function profile(code = 'team-one', parserId = 'maintainer-proposals-v4') {
  return {
    lane: { code: 'synthetic-lane', label: 'Synthetic lane', displayOrder: 3 }, code, label: 'Synthetic source definition', parserId,
    parserContractSha256: sourceTextHash(parserId), definitionSha256: sourceTextHash('Synthetic definition'), repositoryId: 1,
    rootKind: 'repository', location: '.', configuredRef: null, contentFormat: 'markdown',
    files: parserId === 'interactive-toolkit-v4' ? ['rule-catalog.json', 'rule-catalog.schema.json'] : ['**/*.rules.md'],
    exclude: ['excluded/**'], assessmentBatchSize: 10, assessmentCardinality: 'exactly-one',
  };
}

function proposal(overrides = {}) {
  return {
    sourceId: 'TEAM-CHECK-001', presence: 'present', sourceLifecycle: 'active', location: 'rules/example.rules.md',
    content: 'Synthetic captured source', contentSha256: sourceTextHash('Synthetic captured source'), title: 'Synthetic source',
    surface: 'implementation', ruleText: 'Synthetic proposed wording', provenance: 'local-safeguard',
    rationale: 'Synthetic rationale', evidence: ['Synthetic evidence', 'Synthetic evidence'], ...overrides,
  };
}

function interactive(overrides = {}) {
  const { surface, ruleText, rationale, ...common } = proposal();
  return {
    ...common, location: '.github/instructions/example-compliance-contract.instructions.md',
    contractPath: '.github/instructions/example-compliance-contract.instructions.md', evidence: ['Synthetic evidence'],
    sourceIds: ['synthetic-document'], replacementIds: ['TEAM-CHECK-002'], deprecatedOn: '2026-10-01',
    sourceLifecycle: 'deprecated', lifecycleReason: 'Synthetic lifecycle observation', ...overrides,
  };
}

function contributor(commit = 'a'.repeat(40), overrides = {}) {
  const repository = 'hashicorp/terraform-provider-azurerm';
  const location = 'contributing/topics/synthetic/naming.md';
  const content = '# Synthetic naming\n\nSynthetic contributor guidance.\n';
  return {
    sourceId: 'synthetic-naming', presence: 'present', sourceLifecycle: 'active', location,
    content, contentSha256: sourceTextHash(content), title: 'Synthetic naming', repository, resolvedCommit: commit,
    referenceUrl: `https://github.com/${repository}/blob/${commit}/${location}`, ...overrides,
  };
}

function contributorVersion(connection) {
  connection.run('INSERT INTO repositories VALUES (?, ?, ?, ?)', [3, 'github', null, contributor().repository]);
  return registerSourceDefinition(connection, {
    ...profile('contributor', 'contributor-guidance-v4'), repositoryId: 3, rootKind: 'github',
    location: 'contributing', configuredRef: 'main', files: ['README.md', 'topics/**/*.md'], exclude: [], assessmentCardinality: 'zero-to-many',
  });
}

function contributorRequest(definitionVersionId, commit = 'a'.repeat(40), expectedCollectionId = null, overrides = {}) {
  return request(definitionVersionId, normalizeLegacySourceRecords('contributor-guidance-v4', [contributor(commit)]), expectedCollectionId, {
    revision: { kind: 'github-commit', resolvedCommit: commit, configuredRef: 'main', overrideUsed: false }, ...overrides,
  });
}

function request(definitionVersionId, records, expectedCollectionId = null, overrides = {}) {
  return {
    definitionVersionId, expectedCollectionId, repositoryContextId: null, collectorVersion: 1, complete: true, records,
    revision: { kind: 'repository-worktree', resolvedCommit: null, worktreeDirty: true, worktreeSha256: sourceTextHash('Synthetic worktree') },
    ...overrides,
  };
}

function proposalRecords(overrides = {}) {
  return normalizeLegacySourceRecords('maintainer-proposals-v4', [proposal(overrides)]);
}

function counts(connection) {
  return Object.fromEntries(connection.all("SELECT name FROM sqlite_schema WHERE type = 'table' AND name LIKE 'source_%' ORDER BY name").map(({ name }) => [name, connection.get(`SELECT count(*) AS count FROM ${name}`).count]));
}

function inventoryHandoff(selectedProfile = profile(), records = [proposal()], overrides = {}) {
  const revision = request(1, []).revision;
  const configurationHash = sourceTextHash('Synthetic collector configuration');
  const inventory = {
    $schema: 'source-inventory.schema.json', schemaVersion: 1, sourceDefinitionId: selectedProfile.code,
    sourceDefinitionSha256: selectedProfile.definitionSha256, inventoryConfigurationSha256: configurationHash,
    collectorVersion: 1, parserId: selectedProfile.parserId, parserContractSha256: selectedProfile.parserContractSha256,
    collectedAt: '2026-11-03T00:00:00Z',
    collection: { complete: true, sourceRevision: revision, inventorySha256: sourceTextHash(JSON.stringify(records)) },
    records, ...overrides,
  };
  const inventoryJson = JSON.stringify(inventory);
  return {
    profile: selectedProfile, inventoryJson, captureSha256: sourceTextHash(inventoryJson),
    inventoryConfigurationSha256: configurationHash, expectedRevision: inventory.collection.sourceRevision,
    expectedCollectionId: null, repositoryContextId: null,
  };
}

test('protected capture preserves exact file bytes and parses the captured block without reopening source files', context => {
  const root = mkdtempSync(join(tmpdir(), 'workbench-protected-capture-'));
  context.after(() => rmSync(root, { recursive: true, force: true }));
  const sourceRoot = join(root, 'hosted_copilot', 'authored-rules', 'protected');
  mkdirSync(sourceRoot, { recursive: true });
  const block = '### IMPL-CAPTURE-001: Synthetic protected rule\n\n- Rule: Preserve synthetic captured wording.\n- Provenance: local-safeguard\n- Rationale: Synthetic protection rationale.';
  const contents = {};
  for (const surface of ['implementation', 'testing', 'documentation']) {
    const content = `---\ndescription: Synthetic protected capture\nsurface: ${surface}\n---\n\n# Protected Rules\n\n${surface === 'implementation' ? `${block}\n` : ''}`.replaceAll('\n', '\r\n');
    contents[surface] = content;
    writeFileSync(join(sourceRoot, `${surface}.rules.md`), content);
  }
  const modulePath = fileURLToPath(new URL('../../modules/source-parsers/ProtectedRules.psm1', import.meta.url));
  const result = JSON.parse(execFileSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', `
    $ErrorActionPreference = 'Stop'
    $request = [Console]::In.ReadToEnd() | ConvertFrom-Json -AsHashtable
    Import-Module $request.modulePath -Force
    $capture = Get-ProtectedRulesCapture -SourceRoot $request.sourceRoot -RepositoryRoot $request.root
    $capturedBytes = @{}
    foreach ($file in $capture.Files) { $capturedBytes[(Join-Path $request.root $file.relativePath)] = $file.contentBytes }
    [IO.File]::WriteAllText((Join-Path $request.sourceRoot 'implementation.rules.md'), 'Changed after capture', [Text.UTF8Encoding]::new($false))
    Import-Module (Join-Path (Split-Path -Parent $request.modulePath) 'AuthoredRules.psm1') -Force
    $reparsed = @(Get-AuthoredRuleBlocks -SourceBytes $capturedBytes -RepositoryRoot $request.root -ChannelName Protected -AllowedFields Rule,Provenance,Rationale)
    [ordered]@{
      files = @($capture.Files | ForEach-Object { [ordered]@{ relativePath = $_.relativePath; contentBase64 = [Convert]::ToBase64String($_.contentBytes); contentSha256 = $_.contentSha256 } })
      blocks = @($capture.Blocks | ForEach-Object { [ordered]@{ id = $_.id; normalizedContent = $_.normalizedContent; contentSha256 = $_.contentSha256 } })
      rules = @($capture.Catalog.rules)
      reparsed = @($reparsed | ForEach-Object { [ordered]@{ id = $_.id; normalizedContent = $_.normalizedContent; contentSha256 = $_.contentSha256 } })
    } | ConvertTo-Json -Depth 20 -Compress
  `], { input: JSON.stringify({ root, sourceRoot, modulePath }), encoding: 'utf8' }));
  assert.equal(result.files.length, 3);
  for (const file of result.files) {
    const surface = file.relativePath.split('/').at(-1).replace('.rules.md', '');
    assert.equal(file.relativePath, `hosted_copilot/authored-rules/protected/${surface}.rules.md`);
    assert.equal(Buffer.from(file.contentBase64, 'base64').toString('utf8'), contents[surface]);
    assert.equal(file.contentSha256, sourceTextHash(contents[surface]));
  }
  assert.deepEqual(result.blocks, [{ id: 'IMPL-CAPTURE-001', normalizedContent: block, contentSha256: sourceTextHash(block) }]);
  assert.deepEqual(result.reparsed, result.blocks);
  assert.equal(result.rules[0].contentSha256, result.blocks[0].contentSha256);
  assert.equal(result.rules[0].protectionReason, 'Synthetic protection rationale.');
  assert.equal(result.rules[0].text, 'Preserve synthetic captured wording.');
  assert.equal(result.rules[0].impact, 100);
});

test('protected capture accepts complete empty inputs and rejects missing, malformed, duplicate and locked files', context => {
  const root = mkdtempSync(join(tmpdir(), 'workbench-protected-capture-errors-'));
  context.after(() => rmSync(root, { recursive: true, force: true }));
  const sourceRoot = join(root, 'hosted_copilot', 'authored-rules', 'protected');
  mkdirSync(sourceRoot, { recursive: true });
  const modulePath = fileURLToPath(new URL('../../modules/source-parsers/ProtectedRules.psm1', import.meta.url));
  const result = JSON.parse(execFileSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', `
    $ErrorActionPreference = 'Stop'
    $request = [Console]::In.ReadToEnd() | ConvertFrom-Json -AsHashtable
    Import-Module $request.modulePath -Force
    function Reset-Fixture {
      Get-ChildItem -LiteralPath $request.sourceRoot -File -Force | Remove-Item -Force
      foreach ($surface in @('implementation', 'testing', 'documentation')) {
        [IO.File]::WriteAllText((Join-Path $request.sourceRoot "$surface.rules.md"), "---\ndescription: Synthetic capture fixture\nsurface: $surface\n---\n", [Text.UTF8Encoding]::new($false))
      }
    }
    Reset-Fixture
    $empty = Get-ProtectedRulesCapture -SourceRoot $request.sourceRoot -RepositoryRoot $request.root
    $projection = Get-ProtectedRulesCatalog -SourceRoot $request.sourceRoot -RepositoryRoot $request.root
    $block = "\n### IMPL-CAPTURE-001: Synthetic rule\n\n- Rule: Preserve synthetic wording.\n- Provenance: local-safeguard\n- Rationale: Synthetic rationale.\n"
    $implementationPath = Join-Path $request.sourceRoot 'implementation.rules.md'
    $cases = [Collections.Generic.List[object]]::new()
    foreach ($case in @('missing-implementation', 'missing-testing', 'missing-documentation', 'invalid-utf8', 'utf8-bom', 'invalid-frontmatter', 'blank-file', 'missing-field', 'unsupported-field', 'unsupported-provenance', 'duplicate-id', 'locked-file', 'outside-repository', 'missing-directory', 'changed-file-set', 'removed-before-enumeration')) {
      Reset-Fixture
      $stream = $null
      $repositoryRoot = $request.root
      $selectedRoot = $request.sourceRoot
      switch ($case) {
        'missing-implementation' { Remove-Item -LiteralPath $implementationPath }
        'missing-testing' { Remove-Item -LiteralPath (Join-Path $request.sourceRoot 'testing.rules.md') }
        'missing-documentation' { Remove-Item -LiteralPath (Join-Path $request.sourceRoot 'documentation.rules.md') }
        'invalid-utf8' { [IO.File]::WriteAllBytes($implementationPath, [byte[]]@(255, 254, 255)) }
        'utf8-bom' { [IO.File]::WriteAllText($implementationPath, [IO.File]::ReadAllText($implementationPath), [Text.UTF8Encoding]::new($true)) }
        'invalid-frontmatter' { [IO.File]::WriteAllText($implementationPath, 'Synthetic malformed source') }
        'blank-file' { [IO.File]::WriteAllBytes($implementationPath, [byte[]]::new(0)) }
        'missing-field' { [IO.File]::AppendAllText($implementationPath, $block.Replace('- Rationale: Synthetic rationale.', '')) }
        'unsupported-field' { [IO.File]::AppendAllText($implementationPath, $block + '- Unexpected: Synthetic value.') }
        'unsupported-provenance' { [IO.File]::AppendAllText($implementationPath, $block.Replace('local-safeguard', 'unsupported-provenance')) }
        'duplicate-id' { [IO.File]::AppendAllText($implementationPath, $block + $block) }
        'locked-file' { $stream = [IO.File]::Open($implementationPath, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None) }
        'outside-repository' { $repositoryRoot = Join-Path $request.root 'unrelated-repository' }
        'missing-directory' { $selectedRoot = Join-Path $request.root 'missing-protected' }
        { $_ -in @('changed-file-set', 'removed-before-enumeration') } {
          & (Get-Module ProtectedRules) {
            param($mutation)
            $script:captureMutation = $mutation
            $script:captureEnumeration = 0
            function script:Get-ChildItem {
              [CmdletBinding()]
              param([string]$LiteralPath, [string]$Filter, [switch]$File, [switch]$Force)
              $script:captureEnumeration++
              if ($script:captureMutation -eq 'changed-file-set' -and $script:captureEnumeration -eq 2) {
                [IO.File]::WriteAllText((Join-Path $LiteralPath 'late.rules.md'), "---\ndescription: Synthetic late file\nsurface: implementation\n---\n", [Text.UTF8Encoding]::new($false))
              }
              if ($script:captureMutation -eq 'removed-before-enumeration' -and $script:captureEnumeration -eq 1) {
                Remove-Item -LiteralPath (Join-Path $LiteralPath 'testing.rules.md')
              }
              Microsoft.PowerShell.Management\\Get-ChildItem @PSBoundParameters
            }
          } $case
        }
      }
      $rejected = $false
      $failure = $null
      try { $null = Get-ProtectedRulesCapture -SourceRoot $selectedRoot -RepositoryRoot $repositoryRoot }
      catch { $rejected = $true; $failure = $_.Exception.Message }
      finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ($case -in @('changed-file-set', 'removed-before-enumeration')) { & (Get-Module ProtectedRules) { Remove-Item Function:\\Get-ChildItem } }
      }
      if ($case -eq 'changed-file-set' -and $failure -cne 'Protected rule file set changed during capture') { throw 'The changed file set was not rejected by the capture consistency check' }
      if ($case -eq 'removed-before-enumeration' -and $failure -notlike '*missing surface file: testing*') { throw 'A required file disappeared without a scoped capture failure' }
      $cases.Add([ordered]@{ name = $case; rejected = $rejected })
      Reset-Fixture
      $recovered = Get-ProtectedRulesCapture -SourceRoot $request.sourceRoot -RepositoryRoot $request.root
      if ($recovered.Files.Count -ne 3 -or $recovered.Catalog.rules.Count -ne 0) { throw 'Capture did not recover after a rejected input' }
    }
    [ordered]@{ emptyFiles = $empty.Files.Count; emptyBlocks = @($empty.Blocks).Count; emptyRules = @($empty.Catalog.rules).Count; projectionRules = @($projection.rules).Count; cases = $cases.ToArray() } | ConvertTo-Json -Depth 10 -Compress
  `], { input: JSON.stringify({ root, sourceRoot, modulePath }), encoding: 'utf8' }));
  assert.equal(result.emptyFiles, 3);
  assert.equal(result.emptyBlocks, 0);
  assert.equal(result.emptyRules, 0);
  assert.equal(result.projectionRules, 0);
  for (const candidate of result.cases) assert.equal(candidate.rejected, true, candidate.name);
});

function workspaceFixture(context) {
  const connection = fixture(context);
  connection.exec(`
    CREATE TABLE team_profiles (id INTEGER PRIMARY KEY, code TEXT NOT NULL UNIQUE, label TEXT NOT NULL) STRICT;
    CREATE TABLE actors (
      id INTEGER PRIMARY KEY, actor_kind TEXT NOT NULL CHECK(actor_kind IN ('person', 'system')), provider_code TEXT,
      provider_actor_id TEXT, display_name TEXT NOT NULL, UNIQUE(provider_code, provider_actor_id)
    ) STRICT;
    CREATE TABLE protected_snapshots (
      id INTEGER PRIMARY KEY, repository_context_id INTEGER NOT NULL REFERENCES repository_contexts(id),
      captured_at TEXT NOT NULL, content_sha256 TEXT NOT NULL CHECK(length(content_sha256) = 64 AND content_sha256 NOT GLOB '*[^0-9a-f]*')
    ) STRICT;
    CREATE TABLE protected_files (
      id INTEGER PRIMARY KEY, snapshot_id INTEGER NOT NULL REFERENCES protected_snapshots(id), relative_path TEXT NOT NULL,
      content BLOB NOT NULL, content_sha256 TEXT NOT NULL CHECK(length(content_sha256) = 64 AND content_sha256 NOT GLOB '*[^0-9a-f]*'),
      UNIQUE(snapshot_id, relative_path)
    ) STRICT;
    INSERT INTO team_profiles VALUES (1, 'synthetic-profile', 'Synthetic profile');
    INSERT INTO actors VALUES (1, 'system', NULL, NULL, 'Synthetic system');
  `);
  for (const repositoryId of [1, 2]) connection.run('INSERT INTO repository_contexts VALUES (?, ?, ?, ?, ?)', [repositoryId, repositoryId, 'refs/heads/synthetic', String(repositoryId).repeat(40), '2026-11-04T00:00:00.000Z']);
  for (const [snapshotId, repositoryId] of [[1, 1], [2, 1], [3, 2]]) {
    connection.run('INSERT INTO protected_snapshots VALUES (?, ?, ?, ?)', [snapshotId, repositoryId, '2026-11-04T00:00:00.000Z', sourceTextHash(`Synthetic snapshot ${snapshotId}`)]);
    for (const surface of ['implementation', 'testing', 'documentation']) {
      const content = `---\ndescription: Synthetic empty protected rules\nsurface: ${surface}\n---\n`;
      connection.run('INSERT INTO protected_files(snapshot_id, relative_path, content, content_sha256) VALUES (?, ?, ?, ?)', [snapshotId, `rules/protected/${surface}.rules.md`, Buffer.from(content), sourceTextHash(content)]);
    }
  }
  createWorkspaceIdentitySchema(connection);
  const binding = { databaseGuid: '12345678-1234-4234-8234-123456789abc', repositoryId: 1 };
  connection.run('INSERT INTO workspace_identity(id, database_guid, team_profile_id, origin_context_id, created_by_actor_id, created_at) VALUES (?, ?, ?, ?, ?, ?)', [1, binding.databaseGuid, 1, 1, 1, '2026-11-04T00:00:00.000Z']);
  return { connection, binding };
}

test('workspace identity schema requires complete dependencies and enforces its protected snapshot reference', context => {
  const missing = openWorkbenchSqlite({ mode: 'memory' });
  try {
    assert.throws(() => createWorkspaceIdentitySchema(missing), /complete.*dependencies/);
    assert.equal(missing.get("SELECT count(*) AS count FROM sqlite_schema WHERE name = 'workspace_identity'").count, 0);
  } finally { missing.close(); }
  const { connection, binding } = workspaceFixture(context);
  assert.equal(connection.get("SELECT strict FROM pragma_table_list WHERE name = 'workspace_identity'").strict, 1);
  assert.equal(readCurrentProtectedSnapshot(connection, binding), null);
  assert.throws(() => connection.run('UPDATE workspace_identity SET current_protected_snapshot_id = ?', [999]), { errcode: 787 });
  assert.throws(() => connection.run('UPDATE workspace_identity SET database_guid = ?', ['87654321-4321-4321-8321-cba987654321']), /lineage/);
  assert.throws(() => connection.exec('DELETE FROM workspace_identity'), /retained/);
  assert.equal(readCurrentProtectedSnapshot(connection, binding), null);
});

test('current protected input follows the workspace reference rather than the newest snapshot', context => {
  const { connection, binding } = workspaceFixture(context);
  assert.deepEqual(advanceCurrentProtectedSnapshot(connection, { ...binding, snapshotId: 1, expectedSnapshotId: null }), { snapshotId: 1 });
  assert.deepEqual(readCurrentProtectedSnapshot(connection, binding), {
    snapshotId: 1, repositoryContextId: 1, capturedAt: '2026-11-04T00:00:00.000Z', contentSha256: sourceTextHash('Synthetic snapshot 1'),
  });
  assert.equal(connection.get('SELECT max(id) AS id FROM protected_snapshots').id, 3);
  assert.equal(connection.get('SELECT count(*) AS count FROM protected_files WHERE snapshot_id = ?', [1]).count, 3);
  assert.throws(() => connection.exec('UPDATE workspace_identity SET current_protected_snapshot_id = NULL'), /cannot be cleared/);
  assert.throws(() => connection.run('DELETE FROM protected_snapshots WHERE id = ?', [1]), { errcode: 787 });
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
});

test('protected reference updates reject stale heads and wrong workspace or repository scope', context => {
  const { connection, binding } = workspaceFixture(context);
  assert.throws(() => readCurrentProtectedSnapshot(connection, { ...binding, repositoryId: 2 }), /bound repository/);
  assert.throws(() => advanceCurrentProtectedSnapshot(connection, { ...binding, repositoryId: 2, snapshotId: 3, expectedSnapshotId: null }), /bound repository/);
  advanceCurrentProtectedSnapshot(connection, { ...binding, snapshotId: 1, expectedSnapshotId: null });
  const update = { ...binding, snapshotId: 2, expectedSnapshotId: 1 };
  assert.throws(() => advanceCurrentProtectedSnapshot(connection, { ...update, expectedSnapshotId: null }), /changed/);
  assert.throws(() => advanceCurrentProtectedSnapshot(connection, { ...update, databaseGuid: '87654321-4321-4321-8321-cba987654321' }), /changed/);
  assert.throws(() => readCurrentProtectedSnapshot(connection, { ...binding, databaseGuid: '87654321-4321-4321-8321-cba987654321' }), /does not match/);
  assert.throws(() => advanceCurrentProtectedSnapshot(connection, { ...update, snapshotId: 999 }), /bound repository/);
  assert.throws(() => advanceCurrentProtectedSnapshot(connection, { ...update, snapshotId: 3 }), /bound repository/);
  assert.throws(() => advanceCurrentProtectedSnapshot(connection, { ...update, repositoryId: 2, snapshotId: 3 }), /bound repository/);
  assert.throws(() => connection.run('UPDATE workspace_identity SET current_protected_snapshot_id = ?', [3]), /repository scope/);
  assert.throws(() => readCurrentProtectedSnapshot(connection, { ...binding, repositoryId: 2 }), /bound repository/);
  assert.equal(readCurrentProtectedSnapshot(connection, binding).snapshotId, 1);
  assert.deepEqual(advanceCurrentProtectedSnapshot(connection, update), { snapshotId: 2 });
  assert.equal(readCurrentProtectedSnapshot(connection, binding).snapshotId, 2);
  assert.equal(connection.get('SELECT count(*) AS count FROM protected_snapshots').count, 3);
  assert.equal(connection.get('SELECT count(*) AS count FROM protected_files').count, 9);
});

test('protected reference commands reject malformed bindings without changing current input', context => {
  const { connection, binding } = workspaceFixture(context);
  for (const request of [{ ...binding, databaseGuid: 'not-a-guid' }, { ...binding, repositoryId: 0 }, { ...binding, extra: true }]) {
    assert.throws(() => readCurrentProtectedSnapshot(connection, request));
  }
  for (const snapshotId of [0, -1, 1.5, '1', null]) assert.throws(() => advanceCurrentProtectedSnapshot(connection, { ...binding, snapshotId, expectedSnapshotId: null }));
  for (const expectedSnapshotId of [undefined, 0, '1']) assert.throws(() => advanceCurrentProtectedSnapshot(connection, { ...binding, snapshotId: 1, expectedSnapshotId }));
  assert.equal(readCurrentProtectedSnapshot(connection, binding), null);
});

test('source collection and current protected reference participate in the same caller transaction', context => {
  const { connection, binding } = workspaceFixture(context);
  const definitionVersionId = registerSourceDefinition(connection, profile());
  const before = counts(connection);
  connection.exec('BEGIN IMMEDIATE');
  ingestSourceCollection(connection, request(definitionVersionId, proposalRecords()));
  advanceCurrentProtectedSnapshot(connection, { ...binding, snapshotId: 1, expectedSnapshotId: null });
  assert.equal(readCurrentProtectedSnapshot(connection, binding).snapshotId, 1);
  assert.throws(() => connection.run('UPDATE workspace_identity SET current_protected_snapshot_id = ?', [999]), { errcode: 787 });
  connection.exec('ROLLBACK');
  assert.equal(readCurrentProtectedSnapshot(connection, binding), null);
  assert.equal(readSourceCollection(connection, profile().code), null);
  assert.deepEqual(counts(connection), before);
  connection.exec('BEGIN IMMEDIATE');
  const ingested = ingestSourceCollection(connection, request(definitionVersionId, proposalRecords()));
  advanceCurrentProtectedSnapshot(connection, { ...binding, snapshotId: 1, expectedSnapshotId: null });
  connection.exec('COMMIT');
  assert.equal(readCurrentProtectedSnapshot(connection, binding).snapshotId, 1);
  assert.equal(readSourceCollection(connection, profile().code).collectionId, ingested.collectionId);
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
});

test('collector handoff preserves source data through the existing writer and rejects changed capture bytes', context => {
  const connection = fixture(context);
  const handoff = inventoryHandoff();
  ingestSourceInventory(connection, handoff);
  const current = readSourceCollection(connection, handoff.profile.code);
  assert.equal(current.records[0].ruleText, proposal().ruleText);
  assert.deepEqual(current.records[0].evidence, proposal().evidence);
  const before = counts(connection);
  assert.throws(() => ingestSourceInventory(connection, { ...handoff, inventoryJson: handoff.inventoryJson.replace('Synthetic rationale', 'Altered rationale'), expectedCollectionId: current.collectionId }), /capture hash/);
  assert.deepEqual(counts(connection), before);
  assert.equal(readSourceCollection(connection, handoff.profile.code).collectionId, current.collectionId);
});

test('collector handoff accepts actual PowerShell serialization for all existing parser families', context => {
  const connection = fixture(context);
  connection.run('INSERT INTO repositories VALUES (?, ?, ?, ?)', [3, 'github', null, contributor().repository]);
  const remoteProfile = {
    ...profile('contributor', 'contributor-guidance-v4'), repositoryId: 3, rootKind: 'github',
    location: 'contributing', configuredRef: 'main', files: ['README.md', 'topics/**/*.md'], exclude: [], assessmentCardinality: 'zero-to-many',
  };
  const remoteRevision = contributorRequest(1).revision;
  for (const [selectedProfile, records, revision] of [
    [profile('proposals-v4'), [proposal()]],
    [profile('interactive', 'interactive-toolkit-v4'), [interactive()]],
    [remoteProfile, [contributor()], remoteRevision],
  ]) {
    const overrides = revision ? { collection: { complete: true, sourceRevision: revision, inventorySha256: sourceTextHash('Synthetic remote inventory') } } : {};
    const handoff = inventoryHandoff(selectedProfile, records, overrides);
    const transported = JSON.parse(execFileSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', `
      $ErrorActionPreference = 'Stop'
      $request = [Console]::In.ReadToEnd() | ConvertFrom-Json -AsHashtable -Depth 100 -DateKind String
      Import-Module -Name $request.helperPath
      $handoff = $request.handoff
      $inventory = $handoff.inventoryJson | ConvertFrom-Json -AsHashtable -Depth 100 -DateKind String
      $inventory.collection.inventorySha256 = Get-Sha256 -Content ($inventory.records | ConvertTo-Json -Depth 20 -Compress)
      $handoff.inventoryJson = ($inventory | ConvertTo-Json -Depth 30) + [Environment]::NewLine
      if (-not (Test-Json -Json $handoff.inventoryJson -SchemaFile $request.schemaPath)) { throw 'Synthetic collector envelope failed its existing schema' }
      $handoff.captureSha256 = Get-Sha256 -Content $handoff.inventoryJson
      $handoff | ConvertTo-Json -Depth 40 -Compress
    `], {
      input: JSON.stringify({
        handoff,
        helperPath: fileURLToPath(new URL('../../modules/shared/HostedToolkit.Helpers.psm1', import.meta.url)),
        schemaPath: fileURLToPath(new URL('../../../contracts/sources/source-inventory.schema.json', import.meta.url)),
      }),
      encoding: 'utf8', timeout: 15000,
    }));
    const result = ingestSourceInventory(connection, transported);
    assert.deepEqual(result.records.map(({ sourceRuleId, sourceVersionId, observationId, ...record }) => record), normalizeLegacySourceRecords(selectedProfile.parserId, records));
    assert.equal(result.definitionVersionId, readSourceCollection(connection, selectedProfile.code).definitionVersionId);
  }
  assert.equal(connection.get('SELECT count(*) AS count FROM source_collection_heads').count, 3);
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
});

test('collector handoff rejects stale identities and revisions without advancing the saved head', context => {
  const connection = fixture(context);
  const handoff = inventoryHandoff();
  const current = ingestSourceInventory(connection, handoff);
  const inventory = JSON.parse(handoff.inventoryJson);
  const before = counts(connection);
  for (const overrides of [
    { sourceDefinitionId: 'other-definition' },
    { sourceDefinitionSha256: sourceTextHash('Changed definition') },
    { parserId: 'interactive-toolkit-v4' },
    { parserContractSha256: sourceTextHash('Changed parser') },
    { inventoryConfigurationSha256: sourceTextHash('Changed configuration') },
    { collection: { ...inventory.collection, sourceRevision: { ...inventory.collection.sourceRevision, worktreeSha256: sourceTextHash('Changed capture revision') } } },
    { collection: { ...inventory.collection, complete: false } },
    { schemaVersion: 2 },
  ]) {
    const candidate = inventoryHandoff(handoff.profile, [proposal()], overrides);
    assert.throws(() => ingestSourceInventory(connection, { ...candidate, expectedRevision: handoff.expectedRevision, expectedCollectionId: current.collectionId }), /does not match|complete|version/);
    assert.deepEqual(counts(connection), before);
    assert.equal(readSourceCollection(connection, handoff.profile.code).collectionId, current.collectionId);
  }
  assert.throws(() => ingestSourceInventory(connection, handoff), /refresh the expected head/);
  assert.deepEqual(counts(connection), before);
});

test('collector handoff rolls back registration with a failed write and preserves complete empty captures', context => {
  const connection = fixture(context);
  const before = counts(connection);
  const invalid = inventoryHandoff(profile('failed-capture'), [proposal({ surface: 'documentation' })]);
  assert.throws(() => ingestSourceInventory(connection, invalid), /applicability is not registered/);
  assert.deepEqual(counts(connection), before);
  assert.equal(readSourceCollection(connection, invalid.profile.code), null);
  const handoff = inventoryHandoff();
  const first = ingestSourceInventory(connection, handoff);
  const empty = ingestSourceInventory(connection, { ...inventoryHandoff(handoff.profile, []), expectedCollectionId: first.collectionId });
  assert.equal(empty.records.length, 1);
  assert.equal(empty.records[0].presence, 'missing-last-known');
  assert.equal(empty.records[0].sourceVersionId, first.records[0].sourceVersionId);
  assert.equal(readSourceCollection(connection, handoff.profile.code).collectionId, empty.collectionId);
});

test('PowerShell handoff builder derives installed profile identity and rejects stale or tampered evidence', context => {
  const connection = fixture(context);
  const root = mkdtempSync(join(tmpdir(), 'hosted-source-handoff-'));
  context.after(() => rmSync(root, { recursive: true, force: true }));
  for (const schema of ['sources/source-definition.schema.json', 'sources/source-inventory.schema.json', 'parsers/parser-contract.schema.json']) {
    const target = join(root, 'hosted_copilot/contracts', schema);
    mkdirSync(dirname(target), { recursive: true });
    copyFileSync(fileURLToPath(new URL(`../../../contracts/${schema}`, import.meta.url)), target);
  }
  const definitionPath = join(root, 'hosted_copilot/copilot-rule-catalog/source-definitions/fixture-proposals.json');
  mkdirSync(dirname(definitionPath), { recursive: true });
  writeFileSync(definitionPath, JSON.stringify({
    $schema: 'source-definition.schema.json', schemaVersion: 1, id: 'fixture-proposals', displayName: 'Synthetic installed profile',
    root: { kind: 'repository', path: 'rules' }, files: ['**/*.rules.md'], exclude: [], parser: 'maintainer-proposals-v4', assessmentBatchSize: 10,
  }));
  const behaviorPath = join(root, 'hosted_copilot/fixtures/parser.mjs');
  mkdirSync(dirname(behaviorPath), { recursive: true });
  writeFileSync(behaviorPath, 'export const syntheticParserRevision = 1;\n');
  writeFileSync(join(root, 'hosted_copilot/contracts/parsers/maintainer-proposals-v4.json'), JSON.stringify({
    $schema: 'parser-contract.schema.json', schemaVersion: 1, parserId: 'maintainer-proposals-v4',
    assessmentCardinality: 'exactly-one', behaviorFiles: ['hosted_copilot/fixtures/parser.mjs'],
  }));
  const result = JSON.parse(execFileSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', `
    $ErrorActionPreference = 'Stop'
    $request = [Console]::In.ReadToEnd() | ConvertFrom-Json -Depth 100 -DateKind String
    Import-Module -Name $request.modulePath
    $evidence = Get-CurrentSourceDefinitionEvidence -RepositoryRoot $request.root -SourceDefinitionId 'fixture-proposals'
    $inventory = $request.inventoryJson | ConvertFrom-Json -DateKind String
    $inventory.sourceDefinitionId = $evidence.SourceDefinitionId
    $inventory.sourceDefinitionSha256 = $evidence.SourceDefinitionSha256
    $inventory.parserContractSha256 = $evidence.ParserContractSha256
    $inventory.inventoryConfigurationSha256 = $evidence.InventoryConfigurationSha256
    $collectorAst = [Management.Automation.Language.Parser]::ParseFile($request.collectorPath, [ref]$null, [ref]$null)
    $producerCalls = @($collectorAst.FindAll({ param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$inventorySha256' }, $true))
    if ($producerCalls.Count -ne 3) { throw 'Expected all three collector record-hash assignments' }
    $verifiedHashes = [Collections.Generic.List[string]]::new()
    foreach ($hashCase in $request.hashCases) {
      $sortedRecords = @($hashCase)
      $expectedHash = Get-SourceEvidenceRecordsSha256 -Records $sortedRecords
      foreach ($producerCall in $producerCalls) {
        $actualHash = & ([scriptblock]::Create($producerCall.Extent.Text + [Environment]::NewLine + '$inventorySha256'))
        if ($actualHash -cne $expectedHash) { throw 'Collector record hash does not match shared evidence validation' }
      }
      $verifiedHashes.Add($expectedHash)
    }
    $sortedRecords = @($inventory.records)
    $inventory.collection.inventorySha256 = & ([scriptblock]::Create($producerCalls[0].Extent.Text + [Environment]::NewLine + '$inventorySha256'))
    $inventoryJson = ($inventory | ConvertTo-Json -Depth 30) + [Environment]::NewLine
    $arguments = @{
      RepositoryRoot = $request.root; SourceDefinitionId = 'fixture-proposals'; InventoryJson = $inventoryJson
      Lane = $request.lane; RepositoryId = 1; ContentFormat = 'markdown'; ExpectedRevision = $inventory.collection.sourceRevision
    }
    $handoff = New-SourceInventoryHandoff @arguments
    $emptyInventory = $inventoryJson | ConvertFrom-Json -DateKind String
    $emptyInventory.records = @()
    $sortedRecords = @()
    $emptyInventory.collection.inventorySha256 = & ([scriptblock]::Create($producerCalls[0].Extent.Text + [Environment]::NewLine + '$inventorySha256'))
    $arguments.InventoryJson = ($emptyInventory | ConvertTo-Json -Depth 30) + [Environment]::NewLine
    $emptyHandoff = New-SourceInventoryHandoff @arguments
    $arguments.InventoryJson = $inventoryJson
    $arguments.SourceDefinitionId = '../escape'
    $invalidSelectionRejected = $false
    try { $null = New-SourceInventoryHandoff @arguments }
    catch { $invalidSelectionRejected = $_.Exception.Message -like '*pattern*' }
    $arguments.SourceDefinitionId = 'fixture-proposals'
    $inventory.records[0].content = 'Tampered synthetic content'
    $arguments.InventoryJson = $inventory | ConvertTo-Json -Depth 30
    $tamperingRejected = $false
    try { $null = New-SourceInventoryHandoff @arguments }
    catch { $tamperingRejected = $_.Exception.Message -like '*record hash does not match*' }
    $arguments.InventoryJson = $inventoryJson
    [IO.File]::WriteAllText($request.behaviorPath, 'export const syntheticParserRevision = 2;')
    $behaviorRejected = $false
    try { $null = New-SourceInventoryHandoff @arguments }
    catch { $behaviorRejected = $_.Exception.Message -like '*parser contract hash is stale*' }
    @{ handoff = $handoff; emptyHandoff = $emptyHandoff; verifiedHashes = $verifiedHashes.ToArray(); invalidSelectionRejected = $invalidSelectionRejected; tamperingRejected = $tamperingRejected; behaviorRejected = $behaviorRejected } | ConvertTo-Json -Depth 40 -Compress
  `], {
    input: JSON.stringify({
      root, behaviorPath, lane: profile().lane, inventoryJson: inventoryHandoff().inventoryJson,
      hashCases: [[], [proposal()], [proposal({ sourceId: 'TEAM-CHECK-002' }), proposal()], [proposal(), proposal({ sourceId: 'TEAM-CHECK-002' })], [proposal({ presence: 'removed', removedAt: '2026-11-03T01:02:03.1234567Z' })]],
      collectorPath: fileURLToPath(new URL('../../internal/collection/New-SourceInventory.ps1', import.meta.url)),
      modulePath: fileURLToPath(new URL('../../modules/shared/SourceEvidenceValidation.psm1', import.meta.url)),
    }),
    encoding: 'utf8', timeout: 15000,
  }));
  assert.equal(result.invalidSelectionRejected, true);
  assert.equal(result.tamperingRejected, true);
  assert.equal(result.behaviorRejected, true);
  assert.equal(result.handoff.profile.label, 'Synthetic installed profile');
  assert.equal(result.handoff.captureSha256, sourceTextHash(result.handoff.inventoryJson));
  assert.equal(result.handoff.expectedCollectionId, null);
  assert.equal(result.handoff.repositoryContextId, null);
  assert.equal(result.verifiedHashes.length, 5);
  assert.equal(result.verifiedHashes[0], sourceTextHash('[]'));
  assert.equal(result.verifiedHashes[2], result.verifiedHashes[3]);
  const stored = ingestSourceInventory(connection, result.handoff);
  assert.equal(stored.records[0].content, proposal().content);
  assert.equal(stored.records[0].rationale, proposal().rationale);
  assert.equal(readSourceCollection(connection, 'fixture-proposals').collectionId, stored.collectionId);
  const missing = ingestSourceInventory(connection, { ...result.emptyHandoff, expectedCollectionId: stored.collectionId });
  assert.equal(missing.records[0].presence, 'missing-last-known');
  assert.equal(missing.records[0].sourceVersionId, stored.records[0].sourceVersionId);
  assert.equal(missing.records[0].content, proposal().content);
  assert.equal(readSourceCollection(connection, 'fixture-proposals').collectionId, missing.collectionId);
});

test('one closed executable record contract rejects malformed data without discarding fields', () => {
  const record = proposalRecords()[0];
  assert.equal(record.ruleText, proposal().ruleText);
  assert.equal(record.evidence.length, 2);
  assert.throws(() => normalizeSourceRecord({ ...record, content: 'Changed content' }), /hash does not match/);
  assert.throws(() => normalizeSourceRecord({ ...record, metadataBlob: {} }), /unsupported fields/);
  assert.throws(() => normalizeSourceRecord({ ...record, evidence: null }), /array/);
  assert.throws(() => normalizeSourceRecord({ ...record, title: '\uD800' }), /nonempty text/);
  assert.throws(() => normalizeSourceRecord({ ...record, sourceId: 'contains\0nul' }), /nonempty text/);
  assert.throws(() => normalizeSourceRecords([record, record]), /Duplicate source keys/);
  assert.throws(() => normalizeSourceRecord({ ...record, deprecatedOn: '2026-02-30' }), /calendar date/);
  assert.throws(() => normalizeSourceRecord({ ...record, presence: 'missing-last-known', removedAt: '2026-02-30T00:00:00Z' }), /UTC removedAt/);
  assert.throws(() => normalizeSourceRecord({ ...record, replacementIds: [record.sourceId] }), /replace itself/);
  const accessor = { ...record };
  Object.defineProperty(accessor, 'title', { enumerable: true, get() { throw new Error('Untrusted accessor must not execute'); } });
  assert.throws(() => normalizeSourceRecord(accessor), /unsupported fields/);
});

test('legacy adapters retain their declared format checks and all supported optional data', () => {
  const record = normalizeLegacySourceRecords('interactive-toolkit-v4', [interactive()])[0];
  assert.equal(record.contractPath, interactive().contractPath);
  assert.deepEqual(record.sourceIds, ['synthetic-document']);
  assert.deepEqual(record.replacementIds, ['TEAM-CHECK-002']);
  assert.equal(record.deprecatedOn, '2026-10-01');
  assert.equal(normalizeLegacySourceRecords('maintainer-proposals-v4', [proposal()])[0].rationale, proposal().rationale);
  assert.throws(() => normalizeLegacySourceRecords('unknown-v1', []), /Unsupported legacy/);
  assert.throws(() => normalizeLegacySourceRecords('interactive-toolkit-v4', [interactive({ evidence: ['same', 'same'] })]), /unique/);
  assert.throws(() => normalizeLegacySourceRecords('interactive-toolkit-v4', [interactive({ contractPath: '../untrusted' })]), /locator/);
  assert.throws(() => normalizeLegacySourceRecords('maintainer-proposals-v4', [proposal({ ruleText: null })]), /nonempty text/);
  assert.throws(() => normalizeLegacySourceRecords('maintainer-proposals-v4', [proposal({ surface: 'unregistered' })]), /surface/);
  assert.throws(() => normalizeLegacySourceRecords('maintainer-proposals-v4', [proposal({ provenance: 'invented' })]), /provenance/);
  assert.throws(() => normalizeLegacySourceRecords('interactive-toolkit-v4', [interactive({ deprecatedOn: null })]), /nonempty text/);
});

test('schema requires real dependency shapes and uses actual STRICT/FK guards', context => {
  const empty = openWorkbenchSqlite({ mode: 'memory' });
  try { assert.throws(() => createSourceIngestionSchema(empty), /complete repository/); } finally { empty.close(); }
  const connection = fixture(context);
  for (const table of connection.all("SELECT name, strict FROM pragma_table_list WHERE name LIKE 'source_%'")) assert.equal(table.strict, 1, table.name);
  assert.throws(() => connection.run('INSERT INTO source_definitions VALUES (?, ?, ?, ?)', [1, 999, 'orphan', 'Orphan']), { errcode: 787 });
  assert.throws(() => connection.run('INSERT INTO source_lanes VALUES (?, ?, ?, ?)', [1, 'wrong-type', 'Wrong type', 'not-an-integer']), { errcode: 3091 });
  const before = counts(connection);
  assert.throws(() => createSourceIngestionSchema(connection), /already exists/);
  assert.deepEqual(counts(connection), before);
});

test('source definition registration pins behavior, normalization, selectors and cardinality', context => {
  const connection = fixture(context);
  const first = registerSourceDefinition(connection, profile());
  assert.equal(registerSourceDefinition(connection, profile()), first);
  assert.equal(connection.get('SELECT display_order FROM source_lanes').display_order, 3);
  assert.throws(() => registerSourceDefinition(connection, { ...profile(), lane: { ...profile().lane, displayOrder: 4 } }), /explicit profile update/);
  const changed = registerSourceDefinition(connection, { ...profile(), parserContractSha256: sourceTextHash('Changed parser behavior') });
  assert.notEqual(changed, first);
  assert.equal(connection.get('SELECT normalized_contract_version FROM source_definition_versions WHERE id = ?', [changed]).normalized_contract_version, 2);
  assert.deepEqual(connection.all('SELECT kind, pattern FROM source_definition_patterns WHERE definition_version_id = ? ORDER BY kind', [first]).map(row => ({ ...row })), [{ kind: 'exclude', pattern: 'excluded/**' }, { kind: 'include', pattern: '**/*.rules.md' }]);
  assert.throws(() => registerSourceDefinition(connection, { ...profile('unsafe'), files: ['../escape'] }), /relative paths/);
  assert.throws(() => registerSourceDefinition(connection, { ...profile('wrong-repository'), repositoryId: 999 }), { errcode: 787 });
  assert.equal(connection.get('SELECT count(*) AS count FROM source_definitions WHERE code = ?', ['wrong-repository']).count, 0);
});

test('two existing parser output formats use one writer and preserve definition-scoped identity', context => {
  const connection = fixture(context);
  const proposalVersion = registerSourceDefinition(connection, profile('proposals'));
  const interactiveVersion = registerSourceDefinition(connection, profile('interactive', 'interactive-toolkit-v4'));
  const first = ingestSourceCollection(connection, request(proposalVersion, proposalRecords()));
  const second = ingestSourceCollection(connection, request(interactiveVersion, normalizeLegacySourceRecords('interactive-toolkit-v4', [interactive()])));
  assert.equal(first.records[0].sourceId, second.records[0].sourceId);
  assert.notEqual(first.records[0].sourceRuleId, second.records[0].sourceRuleId);
  assert.equal(first.records[0].ruleText, proposal().ruleText);
  assert.deepEqual(first.records[0].applicabilityCodes, ['implementation']);
  assert.deepEqual(second.records[0].sourceIds, ['synthetic-document']);
  assert.deepEqual(second.records[0].replacementIds, ['TEAM-CHECK-002']);
  assert.equal(second.records[0].sourceLifecycle, 'deprecated');
  assert.equal(connection.get('SELECT count(*) AS count FROM source_versions').count, 2);
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
});

test('contributor adapter preserves coherent document origins and the README identity', () => {
  const original = contributor();
  const record = normalizeLegacySourceRecords('contributor-guidance-v4', [original])[0];
  assert.equal(record.originRepository, original.repository);
  assert.equal(record.originCommit, original.resolvedCommit);
  assert.equal(record.originReferenceUrl, original.referenceUrl);
  assert.deepEqual(record.provenanceCodes, ['published-upstream-standard']);
  const location = 'contributing/README.md';
  const readme = contributor(original.resolvedCommit, { sourceId: 'contributing-readme', location, referenceUrl: `https://github.com/${original.repository}/blob/${original.resolvedCommit}/${location}` });
  assert.equal(normalizeLegacySourceRecords('contributor-guidance-v4', [readme])[0].sourceId, 'contributing-readme');
  assert.throws(() => normalizeLegacySourceRecords('contributor-guidance-v4', [contributor(original.resolvedCommit, { referenceUrl: original.referenceUrl.replace(original.resolvedCommit, 'b'.repeat(40)) })]), /does not match/);
  assert.throws(() => normalizeLegacySourceRecords('contributor-guidance-v4', [contributor(original.resolvedCommit, { sourceId: 'wrong-document' })]), /does not match/);
  assert.throws(() => normalizeLegacySourceRecords('contributor-guidance-v4', [contributor(original.resolvedCommit, { repository: 'unsupported/repository' })]), /repository/);
  assert.throws(() => normalizeLegacySourceRecords('contributor-guidance-v4', [contributor(original.resolvedCommit, { location: 'contributing/../outside.md' })]), /locator/);
  assert.throws(() => normalizeLegacySourceRecords('contributor-guidance-v4', [contributor(original.resolvedCommit, { sourceLifecycle: 'retired' })]), /lifecycle/);
  assert.throws(() => normalizeLegacySourceRecords('contributor-guidance-v4', [contributor(original.resolvedCommit, { removedAt: null })]), /must not declare/);
  assert.throws(() => normalizeSourceRecord({ ...record, originRepository: null }), /nonempty text/);
  assert.throws(() => normalizeSourceRecord({ ...record, originReferenceUrl: 'http://example.invalid/source' }), /HTTPS/);
  assert.throws(() => normalizeSourceRecord({ ...record, originReferenceUrl: 'https://example.invalid/source?synthetic=value' }), /query or fragment/);
});

test('all current parser families share one writer with typed contributor origin storage', context => {
  const connection = fixture(context);
  const proposals = registerSourceDefinition(connection, profile('proposals'));
  const toolkit = registerSourceDefinition(connection, profile('interactive', 'interactive-toolkit-v4'));
  const documents = contributorVersion(connection);
  ingestSourceCollection(connection, request(proposals, proposalRecords()));
  ingestSourceCollection(connection, request(toolkit, normalizeLegacySourceRecords('interactive-toolkit-v4', [interactive()])));
  const result = ingestSourceCollection(connection, contributorRequest(documents));
  assert.equal(result.records[0].originReferenceUrl, contributor().referenceUrl);
  const stored = connection.get('SELECT origin_repository, origin_commit, origin_reference_url FROM source_observations WHERE id = ?', [result.records[0].observationId]);
  assert.deepEqual({ ...stored }, { origin_repository: contributor().repository, origin_commit: contributor().resolvedCommit, origin_reference_url: contributor().referenceUrl });
  assert.equal(connection.get('SELECT count(*) AS count FROM source_versions').count, 3);
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
});

test('contributor commit-only changes and disappearance preserve exact historical citations', context => {
  const connection = fixture(context);
  const version = contributorVersion(connection);
  const first = ingestSourceCollection(connection, contributorRequest(version));
  const second = ingestSourceCollection(connection, contributorRequest(version, 'b'.repeat(40), first.collectionId));
  assert.equal(second.records[0].sourceVersionId, first.records[0].sourceVersionId);
  assert.notEqual(second.records[0].observationId, first.records[0].observationId);
  assert.equal(readSourceCollection(connection, 'contributor', first.collectionId).records[0].originCommit, 'a'.repeat(40));
  const missing = ingestSourceCollection(connection, contributorRequest(version, 'c'.repeat(40), second.collectionId, { records: [] }));
  assert.equal(missing.records[0].presence, 'missing-last-known');
  assert.equal(missing.records[0].originCommit, 'b'.repeat(40));
  assert.equal(missing.records[0].originReferenceUrl, contributor('b'.repeat(40)).referenceUrl);
  const reappeared = ingestSourceCollection(connection, contributorRequest(version, 'd'.repeat(40), missing.collectionId));
  assert.equal(reappeared.records[0].presence, 'present');
  assert.equal(reappeared.records[0].originCommit, 'd'.repeat(40));
  assert.equal(reappeared.records[0].sourceVersionId, first.records[0].sourceVersionId);
});

test('present contributor origins must match both selected repository and captured commit', context => {
  const connection = fixture(context);
  const version = contributorVersion(connection);
  const initial = ingestSourceCollection(connection, contributorRequest(version));
  const before = counts(connection);
  const differentRevision = contributorRequest(version, 'b'.repeat(40), initial.collectionId, { records: normalizeLegacySourceRecords('contributor-guidance-v4', [contributor()]) });
  assert.throws(() => ingestSourceCollection(connection, differentRevision), /collection authority/);
  const differentRepository = { ...normalizeLegacySourceRecords('contributor-guidance-v4', [contributor()])[0], originRepository: 'synthetic/team-two' };
  assert.throws(() => ingestSourceCollection(connection, contributorRequest(version, 'a'.repeat(40), initial.collectionId, { records: [differentRepository] })), /collection authority/);
  assert.deepEqual(counts(connection), before);
  assert.equal(readSourceCollection(connection, 'contributor').collectionId, initial.collectionId);
});

test('SQL origin constraints reject partial tuples and invalid complete-collection authority', context => {
  const connection = fixture(context);
  const version = contributorVersion(connection);
  const initial = ingestSourceCollection(connection, contributorRequest(version));
  assert.throws(() => connection.run('INSERT INTO source_observations(source_rule_id, source_version_id, definition_id, metadata_sha256, title, captured_location, source_lifecycle, origin_repository) SELECT source_rule_id, source_version_id, definition_id, ?, title, captured_location, source_lifecycle, origin_repository FROM source_observations WHERE id = ?', [sourceTextHash('Partial origin tuple'), initial.records[0].observationId]), { errcode: 275 });
  const candidate = Number(connection.run("INSERT INTO source_collections(definition_id, definition_version_id, collector_version, source_revision_kind, resolved_commit, configured_ref, override_used, started_at, outcome) SELECT definition_id, definition_version_id, collector_version, source_revision_kind, ?, configured_ref, override_used, started_at, 'running' FROM source_collections WHERE id = ?", ['b'.repeat(40), initial.collectionId]).lastInsertRowid);
  connection.run('INSERT INTO source_collection_members SELECT ?, source_rule_id, source_version_id, observation_id, definition_id, ordinal, presence, removed_at FROM source_collection_members WHERE collection_id = ?', [candidate, initial.collectionId]);
  assert.throws(() => connection.run("UPDATE source_collections SET inventory_sha256 = ?, completed_at = ?, outcome = 'complete' WHERE id = ?", [initial.inventorySha256, '2026-11-03T00:00:00Z', candidate]), /collection authority/);
  const definitionId = connection.get('SELECT definition_id FROM source_collections WHERE id = ?', [candidate]).definition_id;
  assert.throws(() => connection.run('UPDATE source_collection_heads SET collection_id = ? WHERE definition_id = ?', [candidate, definitionId]), /complete collection/);
  assert.equal(readSourceCollection(connection, 'contributor').collectionId, initial.collectionId);
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
});

test('metadata-only changes create immutable observations without duplicating text versions', context => {
  const connection = fixture(context);
  const version = registerSourceDefinition(connection, profile());
  const first = ingestSourceCollection(connection, request(version, proposalRecords()));
  const second = ingestSourceCollection(connection, request(version, proposalRecords({ title: 'Updated title', sourceLifecycle: 'retired', evidence: ['Different evidence'] }), first.collectionId));
  assert.equal(second.records[0].sourceVersionId, first.records[0].sourceVersionId);
  assert.notEqual(second.records[0].observationId, first.records[0].observationId);
  assert.equal(readSourceCollection(connection, 'team-one', first.collectionId).records[0].sourceLifecycle, 'active');
  const third = ingestSourceCollection(connection, request(version, proposalRecords({ content: 'Changed source text', contentSha256: sourceTextHash('Changed source text') }), second.collectionId));
  assert.notEqual(third.records[0].sourceVersionId, first.records[0].sourceVersionId);
  assert.equal(connection.get('SELECT count(*) AS count FROM source_versions').count, 2);
});

test('unchanged captures reuse immutable facts but record independent collection observations', context => {
  const connection = fixture(context);
  const version = registerSourceDefinition(connection, profile());
  const first = ingestSourceCollection(connection, request(version, proposalRecords()));
  const second = ingestSourceCollection(connection, request(version, proposalRecords(), first.collectionId));
  assert.notEqual(second.collectionId, first.collectionId);
  assert.equal(second.inventorySha256, first.inventorySha256);
  assert.equal(second.records[0].sourceVersionId, first.records[0].sourceVersionId);
  assert.equal(second.records[0].observationId, first.records[0].observationId);
  const changedParser = registerSourceDefinition(connection, { ...profile(), parserContractSha256: sourceTextHash('Changed implementation') });
  const third = ingestSourceCollection(connection, request(changedParser, proposalRecords(), second.collectionId));
  assert.notEqual(third.inventorySha256, first.inventorySha256);
  assert.equal(third.records[0].sourceVersionId, first.records[0].sourceVersionId);
});

test('empty captures, disappearance and reappearance retain last-known content and removal time', context => {
  const connection = fixture(context);
  const version = registerSourceDefinition(connection, profile());
  const empty = ingestSourceCollection(connection, request(version, []));
  assert.deepEqual(empty.records, []);
  const present = ingestSourceCollection(connection, request(version, proposalRecords(), empty.collectionId));
  const missing = ingestSourceCollection(connection, request(version, [], present.collectionId));
  assert.equal(missing.records[0].presence, 'missing-last-known');
  assert.equal(missing.records[0].sourceLifecycle, 'active');
  const stillMissing = ingestSourceCollection(connection, request(version, [], missing.collectionId));
  assert.equal(stillMissing.records[0].removedAt, missing.records[0].removedAt);
  const restored = ingestSourceCollection(connection, request(version, proposalRecords(), stillMissing.collectionId));
  assert.equal(restored.records[0].presence, 'present');
  assert.equal(restored.records[0].removedAt, null);
  assert.equal(restored.records[0].sourceVersionId, present.records[0].sourceVersionId);
  assert.equal(restored.records[0].observationId, present.records[0].observationId);
});

test('missing markers cannot fabricate or replace last-known evidence', context => {
  const connection = fixture(context);
  const version = registerSourceDefinition(connection, profile());
  const removed = { ...proposalRecords()[0], presence: 'missing-last-known', removedAt: '2026-11-03T00:00:00Z' };
  assert.throws(() => ingestSourceCollection(connection, request(version, [removed])), /previously captured/);
  const present = ingestSourceCollection(connection, request(version, proposalRecords()));
  assert.throws(() => ingestSourceCollection(connection, request(version, [{ ...removed, title: 'Invented missing title' }], present.collectionId)), /previously captured/);
  const missing = ingestSourceCollection(connection, request(version, [], present.collectionId));
  assert.throws(() => ingestSourceCollection(connection, request(version, [{ ...removed, removedAt: '2026-11-04T00:00:00Z' }], missing.collectionId)), /first removal/);
});

test('mid-write failures roll back every new source fact and preserve the last complete head', context => {
  const connection = fixture(context);
  const version = registerSourceDefinition(connection, profile());
  const initial = ingestSourceCollection(connection, request(version, proposalRecords()));
  const before = counts(connection);
  const valid = { ...proposalRecords()[0], sourceId: 'A-FIRST-001', replacementIds: ['A-NEXT-002'] };
  const invalid = { ...proposalRecords()[0], sourceId: 'Z-FAIL-001', provenanceCodes: ['unregistered-code'] };
  assert.throws(() => ingestSourceCollection(connection, request(version, [valid, invalid], initial.collectionId)), { errcode: 787 });
  assert.deepEqual(counts(connection), before);
  assert.equal(readSourceCollection(connection, 'team-one').collectionId, initial.collectionId);
  assert.throws(() => ingestSourceCollection(connection, request(version, [{ ...valid, applicabilityCodes: ['unregistered-code'] }], initial.collectionId)), /not registered/);
  assert.deepEqual(counts(connection), before);
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
});

test('incomplete requests and stale expected heads cannot advance observed state', context => {
  const connection = fixture(context);
  const version = registerSourceDefinition(connection, profile());
  const initial = ingestSourceCollection(connection, request(version, proposalRecords()));
  const before = counts(connection);
  assert.throws(() => ingestSourceCollection(connection, request(version, [], initial.collectionId, { complete: false })), /Only complete/);
  assert.throws(() => ingestSourceCollection(connection, request(version, [])), /refresh the expected head/);
  assert.deepEqual(counts(connection), before);
  assert.equal(readSourceCollection(connection, 'team-one').collectionId, initial.collectionId);
});

test('repository identity and commit context are checked by both owner and SQL guard', context => {
  const connection = fixture(context);
  const version = registerSourceDefinition(connection, profile());
  connection.run('INSERT INTO repository_contexts VALUES (?, ?, ?, ?, ?)', [1, 2, 'refs/heads/synthetic', 'a'.repeat(40), '2026-11-03T00:00:00Z']);
  const invalid = request(version, proposalRecords(), null, { repositoryContextId: 1, revision: { kind: 'repository-worktree', resolvedCommit: 'a'.repeat(40), worktreeDirty: false, worktreeSha256: sourceTextHash('Synthetic worktree') } });
  assert.throws(() => ingestSourceCollection(connection, invalid), /repository context/);
  const definition = connection.get('SELECT definition_id FROM source_definition_versions WHERE id = ?', [version]).definition_id;
  assert.throws(() => connection.run("INSERT INTO source_collections(definition_id, definition_version_id, repository_context_id, collector_version, source_revision_kind, resolved_commit, worktree_dirty, worktree_sha256, started_at, outcome) VALUES (?, ?, ?, 1, 'repository-worktree', ?, 0, ?, ?, 'running')", [definition, version, 1, 'a'.repeat(40), sourceTextHash('Synthetic worktree'), '2026-11-03T00:00:00Z']), /repository context mismatch/);
  assert.equal(connection.get('SELECT count(*) AS count FROM source_collections').count, 0);
});

test('remote revision and opaque identifiers use the same writer without source-specific SQL', context => {
  const connection = fixture(context);
  const version = registerSourceDefinition(connection, { ...profile('remote', 'custom-team-v1'), rootKind: 'github', configuredRef: 'main', assessmentCardinality: 'zero-to-many' });
  const record = { ...proposalRecords()[0], sourceId: "opaque'); DROP TABLE source_rules; --", applicabilityCodes: ['custom-language'] };
  const revision = { kind: 'github-commit', resolvedCommit: 'b'.repeat(40), configuredRef: 'main', overrideUsed: false };
  const result = ingestSourceCollection(connection, request(version, [record], null, { revision }));
  assert.equal(result.records[0].sourceId, record.sourceId);
  assert.deepEqual(result.records[0].applicabilityCodes, ['custom-language']);
  assert.throws(() => ingestSourceCollection(connection, request(version, [record], result.collectionId, { revision: { ...revision, configuredRef: 'different' } })), /configured ref/);
  assert.equal(connection.get('SELECT count(*) AS count FROM source_rules').count, 1);
});

test('finalized configuration, content, metadata and collection snapshots reject direct mutation', context => {
  const connection = fixture(context);
  const version = registerSourceDefinition(connection, profile());
  const result = ingestSourceCollection(connection, request(version, proposalRecords()));
  const record = result.records[0];
  const definitionId = connection.get('SELECT definition_id FROM source_rules WHERE id = ?', [record.sourceRuleId]).definition_id;
  assert.throws(() => connection.run('INSERT INTO source_versions(source_rule_id, definition_id, captured_text, content_sha256) VALUES (?, ?, ?, ?)', [record.sourceRuleId, definitionId, 'Invalid digest', 'z'.repeat(64)]), { errcode: 275 });
  for (const [sql, parameters] of [
    ['UPDATE source_definition_versions SET label = ? WHERE id = ?', ['changed', version]],
    ['DELETE FROM source_definition_patterns WHERE definition_version_id = ?', [version]],
    ['UPDATE source_versions SET captured_text = ? WHERE id = ?', ['changed', record.sourceVersionId]],
    ['DELETE FROM source_observation_evidence WHERE observation_id = ?', [record.observationId]],
    ['UPDATE source_observations SET title = ? WHERE id = ?', ['changed', record.observationId]],
    ['DELETE FROM source_collection_members WHERE collection_id = ?', [result.collectionId]],
    ['DELETE FROM source_collections WHERE id = ?', [result.collectionId]],
  ]) assert.throws(() => connection.run(sql, parameters), /immutable/);
  const openObservation = Number(connection.run('INSERT INTO source_observations(source_rule_id, source_version_id, definition_id, metadata_sha256, title, captured_location, source_lifecycle) SELECT source_rule_id, source_version_id, definition_id, ?, title, captured_location, source_lifecycle FROM source_observations WHERE id = ?', [sourceTextHash('Unfinished observation'), record.observationId]).lastInsertRowid);
  connection.run('INSERT INTO source_observation_evidence VALUES (?, ?, ?)', [openObservation, 99, 'Unfinished evidence']);
  assert.throws(() => connection.run('UPDATE source_observation_evidence SET observation_id = ? WHERE observation_id = ?', [record.observationId, openObservation]), /immutable/);
  assert.equal(readSourceCollection(connection, 'team-one').records[0].evidence.length, 2);
});

test('composite guards reject cross-definition replacements even for an unfinished observation', context => {
  const connection = fixture(context);
  const firstVersion = registerSourceDefinition(connection, profile('one'));
  const secondVersion = registerSourceDefinition(connection, profile('two'));
  const first = ingestSourceCollection(connection, request(firstVersion, proposalRecords()));
  const second = ingestSourceCollection(connection, request(secondVersion, proposalRecords()));
  const record = first.records[0];
  const observation = connection.run('INSERT INTO source_observations(source_rule_id, source_version_id, definition_id, metadata_sha256, title, captured_location, source_lifecycle) SELECT source_rule_id, source_version_id, definition_id, ?, title, captured_location, source_lifecycle FROM source_observations WHERE id = ?', [sourceTextHash('Cross-scope probe'), record.observationId]);
  const definition = connection.get('SELECT definition_id FROM source_rules WHERE id = ?', [record.sourceRuleId]).definition_id;
  assert.throws(() => connection.run('INSERT INTO source_observation_replacements VALUES (?, ?, ?, ?)', [Number(observation.lastInsertRowid), definition, 0, second.records[0].sourceRuleId]), { errcode: 787 });
  assert.deepEqual(connection.all('PRAGMA foreign_key_check'), []);
});
