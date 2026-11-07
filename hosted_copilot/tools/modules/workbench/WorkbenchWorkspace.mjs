import { requireSourceObject } from './WorkbenchSourceRecords.mjs';

const guidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

function positiveIdentity(value, label) {
  if (!Number.isSafeInteger(value) || value < 1) throw new Error(`${label} must be a positive safe integer`);
}

function validateBinding(request, extraFields = []) {
  const fields = ['databaseGuid', 'repositoryId', ...extraFields];
  requireSourceObject(request, fields, fields, 'Bound workspace request');
  if (typeof request.databaseGuid !== 'string' || !guidPattern.test(request.databaseGuid)) throw new Error('Workspace identity requires a canonical database GUID');
  positiveIdentity(request.repositoryId, 'Bound repository identity');
}

export function createWorkspaceIdentitySchema(connection) {
  for (const [table, columns] of Object.entries({
    team_profiles: ['id', 'code', 'label'],
    repository_contexts: ['id', 'repository_id', 'branch_ref', 'commit_oid', 'observed_at'],
    actors: ['id', 'actor_kind', 'provider_code', 'provider_actor_id', 'display_name'],
    protected_snapshots: ['id', 'repository_context_id', 'captured_at', 'content_sha256'],
  })) {
    const existing = new Set(connection.all('SELECT name FROM pragma_table_info(?)', [table]).map(column => column.name));
    if (columns.some(column => !existing.has(column))) throw new Error('Workspace identity schema requires complete profile, context, actor and protected-snapshot dependencies');
  }
  connection.exec('SAVEPOINT workbench_workspace_schema');
  try {
    connection.exec(`
      CREATE TABLE workspace_identity (
        id INTEGER PRIMARY KEY CHECK(id = 1), database_guid TEXT NOT NULL UNIQUE,
        team_profile_id INTEGER NOT NULL REFERENCES team_profiles(id), origin_context_id INTEGER REFERENCES repository_contexts(id),
        created_by_actor_id INTEGER REFERENCES actors(id), created_at TEXT NOT NULL,
        current_protected_snapshot_id INTEGER REFERENCES protected_snapshots(id),
        CHECK(length(database_guid) = 36 AND substr(database_guid, 9, 1) = '-' AND substr(database_guid, 14, 1) = '-'
          AND substr(database_guid, 19, 1) = '-' AND substr(database_guid, 24, 1) = '-'
          AND length(replace(database_guid, '-', '')) = 32 AND replace(database_guid, '-', '') NOT GLOB '*[^0-9a-f]*')
      ) STRICT;
      CREATE TRIGGER workspace_identity_immutable BEFORE UPDATE OF id, database_guid, team_profile_id, origin_context_id, created_by_actor_id, created_at ON workspace_identity
        BEGIN SELECT RAISE(ABORT, 'Workspace lineage requires an explicit maintenance operation'); END;
      CREATE TRIGGER workspace_identity_retained BEFORE DELETE ON workspace_identity
        BEGIN SELECT RAISE(ABORT, 'Workspace identity must be retained'); END;
      CREATE TRIGGER workspace_protected_reference_retained BEFORE UPDATE OF current_protected_snapshot_id ON workspace_identity
        WHEN OLD.current_protected_snapshot_id IS NOT NULL AND NEW.current_protected_snapshot_id IS NULL
        BEGIN SELECT RAISE(ABORT, 'Current protected input cannot be cleared'); END;
    `);
    for (const operation of ['INSERT', 'UPDATE']) {
      connection.exec(`CREATE TRIGGER workspace_protected_scope_${operation} BEFORE ${operation} ON workspace_identity
        WHEN NEW.current_protected_snapshot_id IS NOT NULL
          AND EXISTS(SELECT 1 FROM protected_snapshots WHERE id = NEW.current_protected_snapshot_id)
          AND NOT EXISTS(SELECT 1 FROM protected_snapshots snapshot
            JOIN repository_contexts captured ON captured.id = snapshot.repository_context_id
            JOIN repository_contexts origin ON origin.id = NEW.origin_context_id
            WHERE snapshot.id = NEW.current_protected_snapshot_id AND captured.repository_id = origin.repository_id)
        BEGIN SELECT RAISE(ABORT, 'Protected snapshot violates workspace repository scope'); END`);
    }
    connection.exec('RELEASE workbench_workspace_schema');
  } catch (error) {
    try { connection.exec('ROLLBACK TO workbench_workspace_schema; RELEASE workbench_workspace_schema'); }
    catch (rollbackError) { throw new AggregateError([error, rollbackError], 'Workspace schema creation and rollback failed'); }
    throw error;
  }
}

export function readSelectedCapacityPolicy(connection, request) {
  validateBinding(request, ['branchRef']);
  if (typeof request.branchRef !== 'string' || !request.branchRef.trim() || request.branchRef.includes('\0')) {
    throw new Error('Bound workspace requires a nonempty branch reference');
  }
  const selected = connection.get(`SELECT origin.repository_id AS repositoryId, origin.branch_ref AS branchRef, policy.id AS policyId,
      policy.code, policy.revision, policy.estimator_code AS estimatorCode, policy.estimator_version AS estimatorVersion,
      policy.characters_per_token AS charactersPerToken, policy.safety_margin_percent AS safetyMarginPercent,
      policy.runtime_request_token_limit AS runtimeRequestTokenLimit, policy.guidance_token_budget AS guidanceTokenBudget
    FROM workspace_identity workspace
    LEFT JOIN repository_contexts origin ON origin.id = workspace.origin_context_id
    LEFT JOIN team_profiles profile ON profile.id = workspace.team_profile_id
    LEFT JOIN capacity_policies policy ON policy.id = profile.capacity_policy_id
    WHERE workspace.id = 1 AND workspace.database_guid = ?`, [request.databaseGuid]);
  if (!selected) throw new Error('Bound workspace identity does not match the database');
  if (selected.repositoryId !== request.repositoryId) throw new Error('Workspace does not match the bound repository');
  if (selected.branchRef !== request.branchRef) throw new Error('Workspace does not match the bound branch');
  if (selected.policyId === null) throw new Error('Workspace profile does not select a capacity policy');
  const { repositoryId, branchRef, ...policy } = selected;
  return policy;
}

export function readSelectedCapacityConfiguration(connection, request) {
  const ownsTransaction = !connection.isTransaction;
  if (ownsTransaction) connection.exec('BEGIN');
  try {
    const policy = readSelectedCapacityPolicy(connection, request);
    const configured = connection.all(`SELECT bucket.id AS bucketId, bucket.code, bucket.label, bucket.guarded_limit AS budgetTokens,
        bucket.accounting_mode AS accountingMode, surface.id AS categoryId, surface.code AS categoryCode,
        surface.output_relative_path AS categoryPath, file.relative_path AS filePath
      FROM capacity_buckets bucket
      LEFT JOIN capacity_bucket_surfaces mapping ON mapping.bucket_id = bucket.id
      LEFT JOIN guidance_surfaces surface ON surface.id = mapping.surface_id
      LEFT JOIN capacity_bucket_files file ON file.bucket_id = bucket.id
      WHERE bucket.policy_id = ? ORDER BY bucket.id`, [policy.policyId]);
    if (configured.length === 0) throw new Error('Selected capacity policy has no configured category allowances');
    const bucketIds = new Set();
    const paths = new Set();
    const categories = new Set();
    const buckets = configured.map(input => {
      if (bucketIds.has(input.bucketId)) throw new Error('Capacity bucket maps to more than one guidance input');
      bucketIds.add(input.bucketId);
      if ((input.categoryPath !== null) === (input.filePath !== null)) throw new Error('Capacity bucket must map to exactly one category or configured file');
      const relativePath = input.categoryPath ?? input.filePath;
      if (relativePath.includes('\\') || relativePath.includes(':') || relativePath.split('/').some(segment => ['', '.', '..'].includes(segment))) {
        throw new Error('Capacity input paths must remain Hosted-root-relative without empty or dot segments');
      }
      const pathKey = relativePath.toLowerCase();
      if (paths.has(pathKey)) throw new Error('Selected capacity policy counts a guidance file more than once');
      paths.add(pathKey);
      if (input.categoryId !== null) categories.add(input.categoryId);
      return { bucketId: input.bucketId, code: input.code, label: input.label, budgetTokens: input.budgetTokens,
        accountingMode: input.accountingMode, categoryId: input.categoryId, categoryCode: input.categoryCode, relativePath };
    });
    if (connection.all('SELECT id FROM guidance_surfaces').some(category => !categories.has(category.id))) {
      throw new Error('Selected capacity policy must account for every registered guidance category');
    }
    if (buckets.reduce((total, bucket) => total + bucket.budgetTokens, 0) > policy.guidanceTokenBudget) {
      throw new Error('Category allowances exceed the selected guidance reservation');
    }
    if (ownsTransaction) connection.exec('COMMIT');
    return { policy, buckets };
  } catch (error) {
    if (ownsTransaction && connection.isTransaction) {
      try { connection.exec('ROLLBACK'); }
      catch (rollbackError) { throw new AggregateError([error, rollbackError], 'Capacity configuration inspection and rollback failed'); }
    }
    throw error;
  }
}

export function readCurrentProtectedSnapshot(connection, request) {
  validateBinding(request);
  const workspace = connection.get(`SELECT workspace.current_protected_snapshot_id, origin.repository_id AS repositoryId
    FROM workspace_identity workspace LEFT JOIN repository_contexts origin ON origin.id = workspace.origin_context_id
    WHERE workspace.id = 1 AND workspace.database_guid = ?`, [request.databaseGuid]);
  if (!workspace) throw new Error('Bound workspace identity does not match the database');
  if (workspace.repositoryId !== request.repositoryId) throw new Error('Workspace does not match the bound repository');
  if (workspace.current_protected_snapshot_id === null) return null;
  const snapshot = connection.get(`SELECT snapshot.id AS snapshotId, snapshot.repository_context_id AS repositoryContextId,
      snapshot.captured_at AS capturedAt, snapshot.content_sha256 AS contentSha256
    FROM protected_snapshots snapshot JOIN repository_contexts context ON context.id = snapshot.repository_context_id
    WHERE snapshot.id = ? AND context.repository_id = ?`, [workspace.current_protected_snapshot_id, request.repositoryId]);
  if (!snapshot) throw new Error('Current protected input does not match the bound repository');
  return { ...snapshot };
}

export function advanceCurrentProtectedSnapshot(connection, request) {
  validateBinding(request, ['snapshotId', 'expectedSnapshotId']);
  positiveIdentity(request.snapshotId, 'Protected snapshot identity');
  if (request.expectedSnapshotId !== null) positiveIdentity(request.expectedSnapshotId, 'Expected protected snapshot identity');
  const workspace = connection.get(`SELECT origin.repository_id AS repositoryId
    FROM workspace_identity workspace LEFT JOIN repository_contexts origin ON origin.id = workspace.origin_context_id
    WHERE workspace.id = 1 AND workspace.database_guid = ?`, [request.databaseGuid]);
  if (workspace && workspace.repositoryId !== request.repositoryId) throw new Error('Workspace does not match the bound repository');
  const snapshot = connection.get(`SELECT snapshot.id FROM protected_snapshots snapshot
    JOIN repository_contexts context ON context.id = snapshot.repository_context_id
    WHERE snapshot.id = ? AND context.repository_id = ?`, [request.snapshotId, request.repositoryId]);
  if (!snapshot) throw new Error('Protected snapshot does not match the bound repository');
  const updated = connection.get(`UPDATE workspace_identity SET current_protected_snapshot_id = ?
    WHERE id = 1 AND database_guid = ? AND current_protected_snapshot_id IS ?
      AND EXISTS(SELECT 1 FROM protected_snapshots snapshot JOIN repository_contexts context ON context.id = snapshot.repository_context_id
        WHERE snapshot.id = ? AND context.repository_id = ?)
    RETURNING current_protected_snapshot_id AS snapshotId`, [request.snapshotId, request.databaseGuid, request.expectedSnapshotId, request.snapshotId, request.repositoryId]);
  if (!updated) throw new Error('Bound workspace identity or current protected snapshot changed; refresh the expected reference');
  return { snapshotId: updated.snapshotId };
}
