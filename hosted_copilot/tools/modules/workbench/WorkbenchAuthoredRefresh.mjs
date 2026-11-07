import { requireSourceObject, requireSourceText, normalizeCapturedSourceFiles } from './WorkbenchSourceRecords.mjs';
import { ingestSourceCollection, readSourceCollection } from './WorkbenchSourceIngestion.mjs';
import { ingestProtectedCapture, readProtectedSnapshot } from './WorkbenchProtectedSnapshots.mjs';
import { readCurrentProtectedSnapshot, advanceCurrentProtectedSnapshot } from './WorkbenchWorkspace.mjs';

const auditTargets = {
  change_revision_id: 'change_revisions', resolution_id: 'issue_resolutions', plan_version_id: 'plan_versions',
  approval_id: 'approvals', catalog_application_id: 'catalog_applications', deployment_id: 'deployments',
  backup_id: 'database_backups', codeowner_refresh_id: 'codeowner_refreshes', evaluation_id: 'evaluations',
  source_collection_id: 'source_collections', protected_snapshot_id: 'protected_snapshots', source_rule_id: 'source_rules', rule_version_id: 'rule_versions',
};

function transaction(connection, operation) {
  connection.exec('SAVEPOINT workbench_authored_refresh');
  try {
    const result = operation();
    connection.exec('RELEASE workbench_authored_refresh');
    return result;
  } catch (error) {
    try { connection.exec('ROLLBACK TO workbench_authored_refresh; RELEASE workbench_authored_refresh'); }
    catch (rollbackError) { throw Object.assign(new AggregateError([error, rollbackError], 'Authored refresh and rollback failed'), { rollbackFailed: true }); }
    throw error;
  }
}

export function createAuthoredAuditSchema(connection) {
  for (const [table, columns] of Object.entries({
    actors: ['id', 'actor_kind', 'provider_code', 'provider_actor_id', 'display_name'],
    guidance_surfaces: ['id', 'code', 'label'], codeowner_snapshots: ['id', 'repository_context_id', 'source_relative_path', 'captured_text', 'content_sha256', 'parser_version', 'captured_at'],
    repository_contexts: ['id', 'repository_id', 'branch_ref', 'commit_oid', 'observed_at'],
    ...Object.fromEntries(Object.values(auditTargets).map(table => [table, ['id']])),
  })) {
    const existing = new Set(connection.all('SELECT name FROM pragma_table_info(?)', [table]).map(column => column.name));
    if (columns.some(column => !existing.has(column))) throw new Error('Audit schema requires its actual actor, scope and typed-target dependencies');
  }
  transaction(connection, () => {
    connection.exec(`
      CREATE UNIQUE INDEX actors_one_system ON actors(actor_kind) WHERE actor_kind = 'system';
      CREATE TABLE audit_events (
        id INTEGER PRIMARY KEY, actor_id INTEGER NOT NULL REFERENCES actors(id), initiated_by_actor_id INTEGER REFERENCES actors(id),
        permission_snapshot_id INTEGER REFERENCES codeowner_snapshots(id), repository_context_id INTEGER REFERENCES repository_contexts(id),
        startup_attempt_guid TEXT, severity TEXT NOT NULL CHECK(severity IN ('info', 'warning', 'error')),
        authored_collection_code TEXT CHECK(authored_collection_code IN ('proposals', 'protected')),
        authored_surface_id INTEGER REFERENCES guidance_surfaces(id), authored_relative_path TEXT,
        action_code TEXT NOT NULL, outcome TEXT NOT NULL, occurred_at TEXT NOT NULL, safe_summary TEXT NOT NULL,
        CHECK(authored_collection_code IS NULL OR (startup_attempt_guid IS NOT NULL AND authored_relative_path IS NOT NULL)),
        CHECK(authored_surface_id IS NULL OR authored_collection_code IS NOT NULL),
        CHECK(authored_relative_path IS NULL OR authored_collection_code IS NOT NULL),
        CHECK(startup_attempt_guid IS NULL OR authored_collection_code IS NOT NULL)
      ) STRICT;
      CREATE INDEX audit_startup_attempt ON audit_events(startup_attempt_guid, id);
      CREATE TABLE audit_targets (
        id INTEGER PRIMARY KEY, event_id INTEGER NOT NULL REFERENCES audit_events(id), target_role TEXT NOT NULL CHECK(target_role IN ('subject', 'before', 'after')),
        ${Object.entries(auditTargets).map(([field, table]) => `${field} INTEGER REFERENCES ${table}(id)`).join(', ')},
        CHECK(${Object.keys(auditTargets).map(field => `(${field} IS NOT NULL)`).join(' + ')} = 1)
      ) STRICT;
    `);
    for (const table of ['audit_events', 'audit_targets']) for (const operation of ['UPDATE', 'DELETE']) {
      connection.exec(`CREATE TRIGGER ${table}_${operation} BEFORE ${operation} ON ${table} BEGIN SELECT RAISE(ABORT, 'Audit history is append-only'); END`);
    }
  });
}

function scope(connection, request) {
  const { databaseGuid, repositoryId, repositoryContextId, startupAttemptGuid, profile } = request;
  if (typeof startupAttemptGuid !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(startupAttemptGuid)) throw new Error('A canonical startup attempt GUID is required');
  readCurrentProtectedSnapshot(connection, { databaseGuid, repositoryId });
  const context = connection.get('SELECT repository_id FROM repository_contexts WHERE id = ?', [repositoryContextId]);
  if (!context || context.repository_id !== repositoryId) throw new Error('Startup context does not match the bound repository');
  requireSourceObject(profile, ['proposalsRoot', 'protectedRoot'], ['proposalsRoot', 'protectedRoot'], 'Authored profile');
  for (const root of [profile.proposalsRoot, profile.protectedRoot]) {
    requireSourceText(root, 'Authored collection root');
    if (!/^[A-Za-z0-9._/-]+$/.test(root) || root.startsWith('/') || root.split('/').some(part => !part || part === '.' || part === '..')) throw new Error('Authored roots must be scoped repository-relative paths');
  }
  if (profile.proposalsRoot === profile.protectedRoot || profile.proposalsRoot.startsWith(`${profile.protectedRoot}/`) || profile.protectedRoot.startsWith(`${profile.proposalsRoot}/`)) throw new Error('Authored collection roots must not overlap');
  const surfaces = connection.all('SELECT id, code FROM guidance_surfaces ORDER BY code').map(surface => ({ ...surface }));
  if (surfaces.length === 0 || surfaces.some(surface => !/^[a-z][a-z0-9-]*$/.test(surface.code))) throw new Error('Registered authored surfaces are required');
  const actor = connection.get("SELECT id FROM actors WHERE actor_kind = 'system'");
  if (!actor) throw new Error('A server-controlled SYSTEM actor is required');
  return { databaseGuid, repositoryId, repositoryContextId, startupAttemptGuid, profile, surfaces, actorId: actor.id };
}

function fileScope(context, collection, surfaceCode = null) {
  const root = context.profile[collection === 'proposals' ? 'proposalsRoot' : 'protectedRoot'];
  const surface = surfaceCode === null ? null : context.surfaces.find(item => item.code === surfaceCode);
  if (surfaceCode !== null && !surface) throw new Error('Authored surface is not registered');
  return { surfaceId: surface?.id ?? null, path: surface ? `${root}/${surface.code}.rules.md` : root };
}

function event(connection, context, collection, surfaceCode, action, outcome, severity, summary, targets = []) {
  const selected = fileScope(context, collection, surfaceCode);
  const eventId = Number(connection.run(`INSERT INTO audit_events(actor_id, repository_context_id, startup_attempt_guid, severity,
    authored_collection_code, authored_surface_id, authored_relative_path, action_code, outcome, occurred_at, safe_summary)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`, [context.actorId, context.repositoryContextId, context.startupAttemptGuid, severity,
    collection, selected.surfaceId, selected.path, action, outcome, new Date().toISOString(), summary]).lastInsertRowid);
  for (const [role, field, targetId] of targets) {
    if (!['subject', 'before', 'after'].includes(role) || !Object.hasOwn(auditTargets, field) || !Number.isSafeInteger(targetId) || targetId < 1) throw new Error('Invalid typed authored audit target');
    connection.run(`INSERT INTO audit_targets(event_id, target_role, ${field}) VALUES (?, ?, ?)`, [eventId, role, targetId]);
  }
}

export function readAuthoredStartupAudit(connection, request) {
  const context = scope(connection, request);
  return connection.all('SELECT * FROM audit_events WHERE startup_attempt_guid = ? AND repository_context_id = ? ORDER BY id', [context.startupAttemptGuid, context.repositoryContextId]).map(row => ({
    ...row, targets: connection.all('SELECT * FROM audit_targets WHERE event_id = ? ORDER BY id', [row.id]).map(target => ({ ...target })),
  }));
}

function failure(connection, context, failures) {
  transaction(connection, () => {
    for (const item of failures) event(connection, context, item.collection, item.surfaceCode ?? null, 'input-check', item.code, 'error', 'Authored inputs were not refreshed; correct the input and restart');
  });
}

export function recordAuthoredStartupFailure(connection, request) {
  const fields = ['databaseGuid', 'repositoryId', 'repositoryContextId', 'startupAttemptGuid', 'profile', 'failures'];
  requireSourceObject(request, [...fields, 'validatedChecks'], fields, 'Authored startup failure');
  if (connection.isTransaction) throw new Error('Failure audit must own its separate transaction');
  const context = scope(connection, request);
  if (!Array.isArray(request.failures) || request.failures.length === 0) throw new Error('Actual input failures are required');
  for (const item of request.failures) {
    requireSourceObject(item, ['collection', 'surfaceCode', 'code'], ['collection', 'code'], 'Authored failure');
    if (!['proposals', 'protected'].includes(item.collection) || !['missing-directory', 'missing-file', 'read-failed', 'parse-failed', 'invalid-input', 'capture-changed'].includes(item.code)) throw new Error('Unsupported authored failure scope or code');
    if ((item.code === 'missing-directory' && item.surfaceCode !== undefined) || (item.code === 'missing-file' && item.surfaceCode === undefined)) throw new Error('Missing file failures require a surface; missing directories must not invent one');
    fileScope(context, item.collection, item.surfaceCode ?? null);
  }
  const checks = request.validatedChecks ?? [];
  if (!Array.isArray(checks)) throw new Error('Validated input checks must be an array');
  const scopes = new Set(request.failures.map(item => `${item.collection}:${item.surfaceCode ?? ''}`));
  for (const check of checks) {
    requireSourceObject(check, ['collection', 'surfaceCode'], ['collection', 'surfaceCode'], 'Validated input check');
    if (!['proposals', 'protected'].includes(check.collection)) throw new Error('Unsupported validated collection');
    fileScope(context, check.collection, check.surfaceCode);
    const key = `${check.collection}:${check.surfaceCode}`;
    if (scopes.has(key) || scopes.has(`${check.collection}:`)) throw new Error('A failed or duplicate scope cannot claim successful validation');
    scopes.add(key);
  }
  transaction(connection, () => {
    for (const check of checks) event(connection, context, check.collection, check.surfaceCode, 'input-check', 'valid', 'info', 'Required file validated; the complete authored refresh did not commit');
    for (const item of request.failures) event(connection, context, item.collection, item.surfaceCode ?? null, 'input-check', item.code, 'error', 'Authored inputs were not refreshed; correct the input and restart');
  });
  return readAuthoredStartupAudit(connection, request);
}

export function refreshAuthoredInputs(connection, request) {
  const fields = ['databaseGuid', 'repositoryId', 'repositoryContextId', 'startupAttemptGuid', 'profile', 'proposals', 'protectedCapture', 'expectedProtectedSnapshotId'];
  requireSourceObject(request, fields, fields, 'Authored refresh');
  if (connection.isTransaction) throw new Error('Authored refresh must own its outer transaction');
  const context = scope(connection, request);
  if (connection.get('SELECT id FROM audit_events WHERE startup_attempt_guid = ?', [context.startupAttemptGuid])) throw new Error('Startup attempt has already been recorded; use a new attempt');
  let activeCollection = 'proposals';
  try {
    return transaction(connection, () => {
      const current = readCurrentProtectedSnapshot(connection, contextBinding(context));
      if ((current?.snapshotId ?? null) !== request.expectedProtectedSnapshotId) throw new Error('Protected input changed; refresh the expected head');
      const priorProtected = current ? readProtectedSnapshot(connection, current.snapshotId) : null;
      const definition = connection.get(`SELECT definition.code, version.repository_id, version.root_kind FROM source_definition_versions version
        JOIN source_definitions definition ON definition.id = version.definition_id WHERE version.id = ?`, [request.proposals.definitionVersionId]);
      if (!definition || definition.repository_id !== context.repositoryId || definition.root_kind !== 'repository') throw new Error('Proposal definition does not match the bound repository');
      const priorProposals = readSourceCollection(connection, definition.code);
      const proposalFiles = normalizeCapturedSourceFiles(request.proposals.files);
      activeCollection = 'protected';
      const protectedFiles = normalizeCapturedSourceFiles(request.protectedCapture.files);
      for (const [collection, files] of [['proposals', proposalFiles], ['protected', protectedFiles]]) {
        activeCollection = collection;
        const required = context.surfaces.map(surface => fileScope(context, collection, surface.code).path);
        if (required.some(path => !files.some(file => file.relativePath === path)) || files.some(file => !required.includes(file.relativePath))) throw new Error('A complete registered authored file set is required');
      }
      if (request.protectedCapture.repositoryContextId !== context.repositoryContextId || request.proposals.repositoryContextId !== context.repositoryContextId) throw new Error('Authored captures require the exact startup repository context');
      const proposalPaths = new Set(proposalFiles.map(file => file.relativePath));
      if (request.proposals.records.some(record => record.presence !== 'present' || !proposalPaths.has(record.location))) throw new Error('Proposal records must belong to the complete current capture');
      activeCollection = 'proposals';
      const proposals = ingestSourceCollection(connection, { ...request.proposals, files: proposalFiles });
      activeCollection = 'protected';
      const protectedSnapshot = ingestProtectedCapture(connection, { ...request.protectedCapture, files: protectedFiles,
        requiredFiles: context.surfaces.map(surface => fileScope(context, 'protected', surface.code).path) });
      advanceCurrentProtectedSnapshot(connection, { ...contextBinding(context), snapshotId: protectedSnapshot.snapshotId, expectedSnapshotId: request.expectedProtectedSnapshotId });
      for (const [collection, files, beforeId, afterId, target] of [
        ['proposals', proposalFiles, priorProposals?.collectionId, proposals.collectionId, 'source_collection_id'],
        ['protected', protectedFiles, priorProtected?.snapshotId, protectedSnapshot.snapshotId, 'protected_snapshot_id'],
      ]) {
        activeCollection = collection;
        const priorFiles = collection === 'proposals'
          ? (beforeId ? connection.all('SELECT relative_path AS relativePath, content_sha256 AS contentSha256 FROM source_collection_files WHERE collection_id = ?', [beforeId]) : [])
          : priorProtected?.files ?? [];
        for (const surface of context.surfaces) {
          const path = fileScope(context, collection, surface.code).path;
          const file = files.find(item => item.relativePath === path);
          const outcome = priorFiles.find(item => item.relativePath === path)?.contentSha256 === file.contentSha256 ? 'unchanged' : 'changed';
          event(connection, context, collection, surface.code, 'input-check', outcome, 'info', 'Required authored file validated', [['subject', target, afterId]]);
        }
        const before = collection === 'proposals' ? priorProposals?.records.filter(record => record.presence === 'present') ?? [] : priorProtected?.blocks ?? [];
        const after = collection === 'proposals' ? proposals.records.filter(record => record.presence === 'present') : protectedSnapshot.blocks;
        for (const removed of before) {
          const key = collection === 'proposals' ? 'sourceId' : 'id';
          if (after.some(record => record[key] === removed[key])) continue;
          const path = collection === 'proposals' ? removed.location : removed.relativePath;
          const surface = context.surfaces.find(item => fileScope(context, collection, item.code).path === path);
          if (!surface) throw new Error('Removed authored identity has an incompatible historical path');
          event(connection, context, collection, surface.code, 'rule-removed', 'removed', 'warning', 'Previously observed authored rule is absent from valid current inputs', [
            ['subject', collection === 'proposals' ? 'source_rule_id' : 'rule_version_id', collection === 'proposals' ? removed.sourceRuleId : removed.ruleVersionId],
            ['before', target, beforeId], ['after', target, afterId],
          ]);
        }
        event(connection, context, collection, null, 'refresh', 'complete', 'info', 'Authored collection and audit committed together', [
          ...(beforeId ? [['before', target, beforeId]] : []), ['after', target, afterId],
        ]);
      }
      return { collectionId: proposals.collectionId, protectedSnapshotId: protectedSnapshot.snapshotId, startupAttemptGuid: context.startupAttemptGuid };
    });
  } catch (error) {
    if (error.rollbackFailed || connection.isTransaction) throw Object.assign(error, { auditPersistence: 'uncertain' });
    let auditPersistence = 'not-recorded';
    try { failure(connection, context, [{ collection: activeCollection, code: 'refresh-failed' }]); auditPersistence = 'recorded'; }
    catch (auditError) { throw Object.assign(new AggregateError([error, auditError], 'Authored refresh failed and failure audit could not be committed'), { auditPersistence: auditError.rollbackFailed ? 'uncertain' : 'not-recorded' }); }
    throw Object.assign(error, { auditPersistence });
  }
}

function contextBinding(context) {
  return { databaseGuid: context.databaseGuid, repositoryId: context.repositoryId };
}
