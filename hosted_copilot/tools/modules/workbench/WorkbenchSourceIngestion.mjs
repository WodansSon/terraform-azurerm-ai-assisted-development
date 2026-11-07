import { isDeepStrictEqual } from 'node:util';
import {
  normalizedSourceContractVersion, normalizeLegacySourceRecords, normalizeSourceRecords, requireSourceHash,
  requireSourceObject, requireSourceText, sourceTextHash,
  normalizeCapturedSourceFiles,
} from './WorkbenchSourceRecords.mjs';

const profileFields = ['lane', 'code', 'label', 'parserId', 'parserContractSha256', 'definitionSha256', 'repositoryId', 'rootKind', 'location', 'configuredRef', 'contentFormat', 'files', 'exclude', 'assessmentBatchSize', 'assessmentCardinality'];
const observationFields = ['title', 'location', 'sourceLifecycle', 'contractPath', 'ruleText', 'rationale', 'deprecatedOn', 'retiredOn', 'lifecycleReason', 'originRepository', 'originCommit', 'originReferenceUrl'];
const scalarColumns = ['title', 'captured_location', 'source_lifecycle', 'contract_path', 'rule_text', 'rationale', 'deprecated_on', 'retired_on', 'lifecycle_reason', 'origin_repository', 'origin_commit', 'origin_reference_url'];
const detailTables = {
  provenanceCodes: ['source_observation_provenance', 'code'],
  evidence: ['source_observation_evidence', 'evidence_text'],
  sourceIds: ['source_observation_references', 'external_key'],
};

function transaction(connection, operation) {
  connection.exec('SAVEPOINT workbench_source_command');
  try {
    const result = operation();
    connection.exec('RELEASE workbench_source_command');
    return result;
  } catch (error) {
    try { connection.exec('ROLLBACK TO workbench_source_command; RELEASE workbench_source_command'); }
    catch (rollbackError) { throw new AggregateError([error, rollbackError], 'Source command and rollback failed'); }
    throw error;
  }
}

function positiveInteger(value, label) {
  if (!Number.isSafeInteger(value) || value < 1) throw new Error(`${label} must be a positive safe integer`);
}

function relativePath(value, pattern = false) {
  requireSourceText(value, 'Source path');
  if (!(pattern ? /^[A-Za-z0-9._*/-]+$/ : /^[A-Za-z0-9._/-]+$/).test(value) || value.startsWith('/') || value.split('/').includes('..')) {
    throw new Error('Source paths must be scoped relative paths');
  }
}

export function createSourceIngestionSchema(connection) {
  for (const [table, columns] of Object.entries({
    repositories: ['id', 'provider_code', 'provider_repository_id', 'canonical_name'],
    repository_contexts: ['id', 'repository_id', 'branch_ref', 'commit_oid', 'observed_at'],
    applicability_definitions: ['id', 'code', 'label', 'renderer_code'],
  })) {
    const existing = new Set(connection.all('SELECT name FROM pragma_table_info(?)', [table]).map(column => column.name));
    if (columns.some(column => !existing.has(column))) throw new Error('Source schema requires complete repository and applicability dependencies');
  }
  transaction(connection, () => {
    connection.exec(`
      CREATE TABLE source_lanes (id INTEGER PRIMARY KEY, code TEXT NOT NULL UNIQUE, label TEXT NOT NULL, display_order INTEGER NOT NULL CHECK(display_order >= 0)) STRICT;
      CREATE TABLE source_provenance_codes (code TEXT PRIMARY KEY NOT NULL, label TEXT NOT NULL) STRICT;
      CREATE TABLE source_definitions (
        id INTEGER PRIMARY KEY, lane_id INTEGER NOT NULL REFERENCES source_lanes(id), code TEXT NOT NULL UNIQUE, label TEXT NOT NULL
      ) STRICT;
      CREATE TABLE source_definition_versions (
        id INTEGER PRIMARY KEY, definition_id INTEGER NOT NULL REFERENCES source_definitions(id), revision INTEGER NOT NULL CHECK(revision > 0),
        label TEXT NOT NULL, adapter_code TEXT NOT NULL, parser_contract_sha256 TEXT NOT NULL CHECK(length(parser_contract_sha256) = 64 AND parser_contract_sha256 NOT GLOB '*[^0-9a-f]*'),
        normalized_contract_version INTEGER NOT NULL CHECK(normalized_contract_version = ${normalizedSourceContractVersion}), definition_sha256 TEXT NOT NULL CHECK(length(definition_sha256) = 64 AND definition_sha256 NOT GLOB '*[^0-9a-f]*'),
        configuration_sha256 TEXT NOT NULL CHECK(length(configuration_sha256) = 64 AND configuration_sha256 NOT GLOB '*[^0-9a-f]*'), repository_id INTEGER NOT NULL REFERENCES repositories(id),
        root_kind TEXT NOT NULL CHECK(root_kind IN ('repository', 'github')), location TEXT NOT NULL, configured_ref TEXT, content_format TEXT NOT NULL,
        assessment_batch_size INTEGER NOT NULL CHECK(assessment_batch_size BETWEEN 1 AND 50),
        assessment_cardinality TEXT NOT NULL CHECK(assessment_cardinality IN ('zero-to-many', 'exactly-one')),
        finalized INTEGER NOT NULL DEFAULT 0 CHECK(finalized IN (0, 1)),
        CHECK((root_kind = 'github' AND configured_ref IS NOT NULL) OR (root_kind = 'repository' AND configured_ref IS NULL)),
        UNIQUE(definition_id, revision), UNIQUE(definition_id, configuration_sha256), UNIQUE(id, definition_id)
      ) STRICT;
      CREATE TABLE source_definition_patterns (
        definition_version_id INTEGER NOT NULL REFERENCES source_definition_versions(id), kind TEXT NOT NULL CHECK(kind IN ('include', 'exclude')),
        ordinal INTEGER NOT NULL CHECK(ordinal >= 0), pattern TEXT NOT NULL, PRIMARY KEY(definition_version_id, kind, ordinal), UNIQUE(definition_version_id, kind, pattern)
      ) STRICT;
      CREATE TABLE source_rules (
        id INTEGER PRIMARY KEY, definition_id INTEGER NOT NULL REFERENCES source_definitions(id), external_key TEXT NOT NULL,
        UNIQUE(definition_id, external_key), UNIQUE(id, definition_id)
      ) STRICT;
      CREATE TABLE source_versions (
        id INTEGER PRIMARY KEY, source_rule_id INTEGER NOT NULL, definition_id INTEGER NOT NULL, captured_text TEXT NOT NULL,
        content_sha256 TEXT NOT NULL CHECK(length(content_sha256) = 64 AND content_sha256 NOT GLOB '*[^0-9a-f]*'), UNIQUE(source_rule_id, content_sha256), UNIQUE(id, source_rule_id, definition_id),
        FOREIGN KEY(source_rule_id, definition_id) REFERENCES source_rules(id, definition_id)
      ) STRICT;
      CREATE TABLE source_observations (
        id INTEGER PRIMARY KEY, source_rule_id INTEGER NOT NULL, source_version_id INTEGER NOT NULL, definition_id INTEGER NOT NULL,
        metadata_sha256 TEXT NOT NULL CHECK(length(metadata_sha256) = 64 AND metadata_sha256 NOT GLOB '*[^0-9a-f]*'), title TEXT NOT NULL, captured_location TEXT NOT NULL,
        source_lifecycle TEXT NOT NULL CHECK(source_lifecycle IN ('active', 'deprecated', 'retired')),
        contract_path TEXT, rule_text TEXT, rationale TEXT, deprecated_on TEXT, retired_on TEXT, lifecycle_reason TEXT,
        origin_repository TEXT, origin_commit TEXT CHECK(length(origin_commit) = 40 AND origin_commit NOT GLOB '*[^0-9a-f]*'),
        origin_reference_url TEXT CHECK(origin_reference_url IS NULL OR origin_reference_url LIKE 'https://%'),
        finalized INTEGER NOT NULL DEFAULT 0 CHECK(finalized IN (0, 1)),
        CHECK((origin_repository IS NULL AND origin_commit IS NULL AND origin_reference_url IS NULL)
          OR (origin_repository IS NOT NULL AND origin_commit IS NOT NULL AND origin_reference_url IS NOT NULL)),
        UNIQUE(source_version_id, metadata_sha256), UNIQUE(id, source_rule_id, source_version_id, definition_id), UNIQUE(id, definition_id),
        FOREIGN KEY(source_version_id, source_rule_id, definition_id) REFERENCES source_versions(id, source_rule_id, definition_id)
      ) STRICT;
      CREATE TABLE source_observation_provenance (
        observation_id INTEGER NOT NULL REFERENCES source_observations(id), ordinal INTEGER NOT NULL CHECK(ordinal >= 0),
        code TEXT NOT NULL REFERENCES source_provenance_codes(code), PRIMARY KEY(observation_id, ordinal), UNIQUE(observation_id, code)
      ) STRICT;
      CREATE TABLE source_observation_evidence (
        observation_id INTEGER NOT NULL REFERENCES source_observations(id), ordinal INTEGER NOT NULL CHECK(ordinal >= 0),
        evidence_text TEXT NOT NULL, PRIMARY KEY(observation_id, ordinal)
      ) STRICT;
      CREATE TABLE source_observation_references (
        observation_id INTEGER NOT NULL REFERENCES source_observations(id), ordinal INTEGER NOT NULL CHECK(ordinal >= 0),
        external_key TEXT NOT NULL, PRIMARY KEY(observation_id, ordinal), UNIQUE(observation_id, external_key)
      ) STRICT;
      CREATE TABLE source_observation_applicabilities (
        observation_id INTEGER NOT NULL REFERENCES source_observations(id), ordinal INTEGER NOT NULL CHECK(ordinal >= 0),
        applicability_id INTEGER NOT NULL REFERENCES applicability_definitions(id), PRIMARY KEY(observation_id, ordinal), UNIQUE(observation_id, applicability_id)
      ) STRICT;
      CREATE TABLE source_observation_replacements (
        observation_id INTEGER NOT NULL, definition_id INTEGER NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal >= 0), replacement_rule_id INTEGER NOT NULL,
        PRIMARY KEY(observation_id, ordinal), UNIQUE(observation_id, replacement_rule_id),
        FOREIGN KEY(observation_id, definition_id) REFERENCES source_observations(id, definition_id),
        FOREIGN KEY(replacement_rule_id, definition_id) REFERENCES source_rules(id, definition_id)
      ) STRICT;
      CREATE TABLE source_collections (
        id INTEGER PRIMARY KEY, definition_id INTEGER NOT NULL, definition_version_id INTEGER NOT NULL,
        repository_context_id INTEGER REFERENCES repository_contexts(id), collector_version INTEGER NOT NULL CHECK(collector_version > 0),
        source_revision_kind TEXT NOT NULL CHECK(source_revision_kind IN ('repository-worktree', 'github-commit')),
        resolved_commit TEXT CHECK(length(resolved_commit) = 40 AND resolved_commit NOT GLOB '*[^0-9a-f]*'), worktree_dirty INTEGER CHECK(worktree_dirty IN (0, 1)), worktree_sha256 TEXT CHECK(length(worktree_sha256) = 64 AND worktree_sha256 NOT GLOB '*[^0-9a-f]*'),
        configured_ref TEXT, override_used INTEGER CHECK(override_used IN (0, 1)), inventory_sha256 TEXT CHECK(length(inventory_sha256) = 64 AND inventory_sha256 NOT GLOB '*[^0-9a-f]*'),
        started_at TEXT NOT NULL, completed_at TEXT, outcome TEXT NOT NULL CHECK(outcome IN ('running', 'complete', 'failed', 'cancelled')),
        CHECK(outcome != 'complete' OR (completed_at IS NOT NULL AND inventory_sha256 IS NOT NULL)),
        CHECK((source_revision_kind = 'repository-worktree' AND worktree_dirty IS NOT NULL AND worktree_sha256 IS NOT NULL AND configured_ref IS NULL AND override_used IS NULL)
          OR (source_revision_kind = 'github-commit' AND resolved_commit IS NOT NULL AND configured_ref IS NOT NULL AND override_used IS NOT NULL AND worktree_dirty IS NULL AND worktree_sha256 IS NULL)),
        UNIQUE(id, definition_id), FOREIGN KEY(definition_version_id, definition_id) REFERENCES source_definition_versions(id, definition_id)
      ) STRICT;
      CREATE TABLE source_collection_members (
        collection_id INTEGER NOT NULL, source_rule_id INTEGER NOT NULL, source_version_id INTEGER NOT NULL, observation_id INTEGER NOT NULL, definition_id INTEGER NOT NULL,
        ordinal INTEGER NOT NULL CHECK(ordinal >= 0), presence TEXT NOT NULL CHECK(presence IN ('present', 'missing-last-known')), removed_at TEXT,
        PRIMARY KEY(collection_id, source_rule_id), UNIQUE(collection_id, ordinal),
        CHECK((presence = 'present' AND removed_at IS NULL) OR (presence = 'missing-last-known' AND removed_at IS NOT NULL)),
        FOREIGN KEY(collection_id, definition_id) REFERENCES source_collections(id, definition_id),
        FOREIGN KEY(observation_id, source_rule_id, source_version_id, definition_id) REFERENCES source_observations(id, source_rule_id, source_version_id, definition_id)
      ) STRICT;
      CREATE TABLE source_collection_heads (
        definition_id INTEGER PRIMARY KEY REFERENCES source_definitions(id), collection_id INTEGER NOT NULL,
        FOREIGN KEY(collection_id, definition_id) REFERENCES source_collections(id, definition_id)
      ) STRICT;
      CREATE TABLE source_collection_files (
        collection_id INTEGER NOT NULL REFERENCES source_collections(id), relative_path TEXT NOT NULL, content BLOB NOT NULL,
        content_sha256 TEXT NOT NULL CHECK(length(content_sha256) = 64 AND content_sha256 NOT GLOB '*[^0-9a-f]*'),
        PRIMARY KEY(collection_id, relative_path)
      ) STRICT;
      CREATE TRIGGER source_collection_ready BEFORE INSERT ON source_collections
        WHEN NOT EXISTS(SELECT 1 FROM source_definition_versions WHERE id = NEW.definition_version_id AND finalized = 1)
        BEGIN SELECT RAISE(ABORT, 'Source definition is not finalized'); END;
      CREATE TRIGGER source_member_ready BEFORE INSERT ON source_collection_members
        WHEN NOT EXISTS(SELECT 1 FROM source_collections WHERE id = NEW.collection_id AND outcome = 'running')
          OR NOT EXISTS(SELECT 1 FROM source_observations WHERE id = NEW.observation_id AND finalized = 1)
        BEGIN SELECT RAISE(ABORT, 'Source collection or observation is not writable'); END;
      CREATE TRIGGER source_origin_finalization BEFORE UPDATE OF outcome ON source_collections
        WHEN NEW.outcome = 'complete' AND EXISTS(
          SELECT 1 FROM source_collection_members member JOIN source_observations observation ON observation.id = member.observation_id
          JOIN source_definition_versions version ON version.id = NEW.definition_version_id JOIN repositories repository ON repository.id = version.repository_id
          WHERE member.collection_id = NEW.id AND member.presence = 'present' AND observation.origin_repository IS NOT NULL
            AND (observation.origin_repository != repository.canonical_name OR observation.origin_commit IS NOT NEW.resolved_commit))
        BEGIN SELECT RAISE(ABORT, 'Source origin does not match collection authority'); END;
    `);
      for (const operation of ['INSERT', 'UPDATE']) connection.exec(`CREATE TRIGGER source_context_${operation} BEFORE ${operation} ON source_collections WHEN NEW.repository_context_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM repository_contexts context JOIN source_definition_versions version ON version.id = NEW.definition_version_id WHERE context.id = NEW.repository_context_id AND context.repository_id = version.repository_id AND context.commit_oid = NEW.resolved_commit) BEGIN SELECT RAISE(ABORT, 'Source repository context mismatch'); END`);
    for (const table of ['source_versions', 'source_rules']) {
      for (const operation of ['UPDATE', 'DELETE']) connection.exec(`CREATE TRIGGER ${table}_${operation} BEFORE ${operation} ON ${table} BEGIN SELECT RAISE(ABORT, 'Captured source identity/content is immutable'); END`);
    }
    for (const [table, completed] of [['source_definition_versions', 'OLD.finalized = 1'], ['source_observations', 'OLD.finalized = 1'], ['source_collections', "OLD.outcome != 'running'"]]) {
      for (const operation of ['UPDATE', 'DELETE']) connection.exec(`CREATE TRIGGER ${table}_${operation} BEFORE ${operation} ON ${table} WHEN ${completed} BEGIN SELECT RAISE(ABORT, 'Finalized source facts are immutable'); END`);
    }
    for (const table of [...Object.values(detailTables).map(([name]) => name), 'source_observation_applicabilities', 'source_observation_replacements', 'source_definition_patterns', 'source_collection_members', 'source_collection_files']) {
      const collectionDetail = ['source_collection_members', 'source_collection_files'].includes(table);
      const owner = table === 'source_definition_patterns' ? 'source_definition_versions' : collectionDetail ? 'source_collections' : 'source_observations';
      const column = table === 'source_definition_patterns' ? 'definition_version_id' : collectionDetail ? 'collection_id' : 'observation_id';
      const condition = owner === 'source_collections' ? "outcome != 'running'" : 'finalized = 1';
      for (const operation of ['INSERT', 'UPDATE', 'DELETE']) {
        const row = operation === 'INSERT' ? 'NEW' : 'OLD';
        const destination = operation === 'UPDATE' ? ` OR EXISTS(SELECT 1 FROM ${owner} WHERE id = NEW.${column} AND ${condition})` : '';
        connection.exec(`CREATE TRIGGER ${table}_${operation} BEFORE ${operation} ON ${table} WHEN EXISTS(SELECT 1 FROM ${owner} WHERE id = ${row}.${column} AND ${condition})${destination} BEGIN SELECT RAISE(ABORT, 'Finalized source details are immutable'); END`);
      }
    }
    for (const operation of ['INSERT', 'UPDATE']) connection.exec(`CREATE TRIGGER source_head_${operation} BEFORE ${operation} ON source_collection_heads WHEN NOT EXISTS(SELECT 1 FROM source_collections WHERE id = NEW.collection_id AND outcome = 'complete') BEGIN SELECT RAISE(ABORT, 'Source head requires a complete collection'); END`);
  });
}

export function registerSourceDefinition(connection, profile) {
  requireSourceObject(profile, profileFields, profileFields, 'Source definition');
  requireSourceObject(profile.lane, ['code', 'label', 'displayOrder'], ['code', 'label', 'displayOrder'], 'Source lane');
  if (!Number.isSafeInteger(profile.lane.displayOrder) || profile.lane.displayOrder < 0) throw new Error('Source lane order must be a nonnegative safe integer');
  for (const field of ['code', 'label', 'parserId', 'contentFormat']) requireSourceText(profile[field], field);
  for (const field of ['code', 'label']) requireSourceText(profile.lane[field], 'Source lane');
  for (const field of ['parserContractSha256', 'definitionSha256']) requireSourceHash(profile[field], field);
  positiveInteger(profile.repositoryId, 'Repository identity');
  positiveInteger(profile.assessmentBatchSize, 'Assessment batch size');
  if (profile.assessmentBatchSize > 50 || !['exactly-one', 'zero-to-many'].includes(profile.assessmentCardinality)) throw new Error('Unsupported assessment configuration');
  if (!['repository', 'github'].includes(profile.rootKind)) throw new Error('Unsupported source root kind');
  if (profile.rootKind === 'github') requireSourceText(profile.configuredRef, 'configuredRef');
  else if (profile.configuredRef !== null) throw new Error('Repository roots must not declare configuredRef');
  relativePath(profile.location);
  for (const field of ['files', 'exclude']) {
    if (!Array.isArray(profile[field]) || new Set(profile[field]).size !== profile[field].length || (field === 'files' && profile[field].length === 0)) throw new Error('Invalid source include/exclude patterns');
    profile[field].forEach(pattern => relativePath(pattern, true));
  }
  const canonical = { ...Object.fromEntries(profileFields.map(field => [field, profile[field]])), lane: { code: profile.lane.code, label: profile.lane.label, displayOrder: profile.lane.displayOrder } };
  const fingerprint = sourceTextHash(JSON.stringify({ normalizedContractVersion: normalizedSourceContractVersion, profile: canonical }));
  return transaction(connection, () => {
    let lane = connection.get('SELECT id, label, display_order FROM source_lanes WHERE code = ?', [profile.lane.code]);
    if (!lane) { connection.run('INSERT INTO source_lanes(code, label, display_order) VALUES (?, ?, ?)', [profile.lane.code, profile.lane.label, profile.lane.displayOrder]); lane = connection.get('SELECT id, label, display_order FROM source_lanes WHERE code = ?', [profile.lane.code]); }
    if (lane.label !== profile.lane.label || lane.display_order !== profile.lane.displayOrder) throw new Error('Existing lane configuration requires an explicit profile update');
    connection.run('INSERT INTO source_definitions(lane_id, code, label) VALUES (?, ?, ?) ON CONFLICT(code) DO NOTHING', [lane.id, profile.code, profile.label]);
    const definition = connection.get('SELECT id, lane_id FROM source_definitions WHERE code = ?', [profile.code]);
    if (definition.lane_id !== lane.id) throw new Error('Existing source definition belongs to another lane');
    const existing = connection.get('SELECT id FROM source_definition_versions WHERE definition_id = ? AND configuration_sha256 = ? AND finalized = 1', [definition.id, fingerprint]);
    if (existing) return existing.id;
    const revision = connection.get('SELECT coalesce(max(revision), 0) + 1 AS revision FROM source_definition_versions WHERE definition_id = ?', [definition.id]).revision;
    const inserted = connection.run(`INSERT INTO source_definition_versions(definition_id, revision, label, adapter_code, parser_contract_sha256, normalized_contract_version, definition_sha256, configuration_sha256, repository_id, root_kind, location, configured_ref, content_format, assessment_batch_size, assessment_cardinality) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`, [definition.id, revision, profile.label, profile.parserId, profile.parserContractSha256, normalizedSourceContractVersion, profile.definitionSha256, fingerprint, profile.repositoryId, profile.rootKind, profile.location, profile.configuredRef, profile.contentFormat, profile.assessmentBatchSize, profile.assessmentCardinality]);
    const id = Number(inserted.lastInsertRowid);
    for (const [field, kind] of [['files', 'include'], ['exclude', 'exclude']]) profile[field].forEach((pattern, ordinal) => connection.run('INSERT INTO source_definition_patterns VALUES (?, ?, ?, ?)', [id, kind, ordinal, pattern]));
    connection.run('UPDATE source_definition_versions SET finalized = 1 WHERE id = ?', [id]);
    return id;
  });
}

export function ingestSourceInventory(connection, request) {
  const fields = ['profile', 'inventoryJson', 'captureSha256', 'inventoryConfigurationSha256', 'expectedRevision', 'expectedCollectionId', 'repositoryContextId'];
  requireSourceObject(request, fields, fields, 'Source inventory handoff');
  requireSourceText(request.inventoryJson, 'Captured inventory JSON');
  requireSourceHash(request.captureSha256, 'Capture hash');
  requireSourceHash(request.inventoryConfigurationSha256, 'Collector configuration hash');
  if (sourceTextHash(request.inventoryJson) !== request.captureSha256) throw new Error('Source capture hash does not match the supplied inventory');
  const inventory = JSON.parse(request.inventoryJson);
  const inventoryFields = ['$schema', 'schemaVersion', 'sourceDefinitionId', 'sourceDefinitionSha256', 'inventoryConfigurationSha256', 'collectorVersion', 'parserId', 'parserContractSha256', 'collectedAt', 'collection', 'records'];
  requireSourceObject(inventory, inventoryFields, inventoryFields, 'Collected source inventory');
  requireSourceObject(inventory.collection, ['complete', 'sourceRevision', 'inventorySha256'], ['complete', 'sourceRevision', 'inventorySha256'], 'Inventory collection');
  if (inventory.$schema !== 'source-inventory.schema.json' || inventory.schemaVersion !== 1 || inventory.collectorVersion !== 1) throw new Error('Unsupported collected source inventory version');
  requireSourceText(inventory.collectedAt, 'Inventory collection time');
  if (!Number.isFinite(Date.parse(inventory.collectedAt))) throw new Error('Invalid inventory collection time');
  requireSourceHash(inventory.collection.inventorySha256, 'Collector inventory hash');
  if (inventory.collection.complete !== true) throw new Error('Only complete source captures can be handed off');
  return transaction(connection, () => {
    const definitionVersionId = registerSourceDefinition(connection, request.profile);
    const profile = request.profile;
    if (inventory.sourceDefinitionId !== profile.code || inventory.sourceDefinitionSha256 !== profile.definitionSha256 ||
        inventory.parserId !== profile.parserId || inventory.parserContractSha256 !== profile.parserContractSha256 ||
        inventory.inventoryConfigurationSha256 !== request.inventoryConfigurationSha256) {
      throw new Error('Source capture does not match the selected definition, parser or configuration');
    }
    const definition = { root_kind: profile.rootKind, configured_ref: profile.configuredRef };
    const revision = normalizeRevision(inventory.collection.sourceRevision, definition);
    if (!isDeepStrictEqual(revision, normalizeRevision(request.expectedRevision, definition))) throw new Error('Source capture does not match the expected revision');
    return ingestSourceCollection(connection, {
      definitionVersionId, expectedCollectionId: request.expectedCollectionId, repositoryContextId: request.repositoryContextId,
      collectorVersion: inventory.collectorVersion, revision, complete: inventory.collection.complete,
      records: normalizeLegacySourceRecords(profile.parserId, inventory.records),
    });
  });
}

function normalizeRevision(revision, definition) {
  const worktree = definition.root_kind === 'repository';
  const fields = worktree ? ['kind', 'resolvedCommit', 'worktreeDirty', 'worktreeSha256'] : ['kind', 'resolvedCommit', 'configuredRef', 'overrideUsed'];
  requireSourceObject(revision, fields, fields, 'Source revision');
  if (revision.kind !== (worktree ? 'repository-worktree' : 'github-commit')) throw new Error('Source revision kind does not match registered root');
  if (!(worktree && revision.resolvedCommit === null) && (typeof revision.resolvedCommit !== 'string' || !/^[a-f0-9]{40}$/.test(revision.resolvedCommit))) throw new Error('Invalid resolved commit');
  if (worktree) {
    if (typeof revision.worktreeDirty !== 'boolean') throw new Error('Invalid worktree state');
    requireSourceHash(revision.worktreeSha256, 'Worktree hash');
  } else {
    if (typeof revision.overrideUsed !== 'boolean' || revision.configuredRef !== definition.configured_ref) throw new Error('Source revision does not match configured ref');
  }
  return Object.fromEntries(fields.map(field => [field, revision[field]]));
}

function metadata(record) {
  return { ...Object.fromEntries(observationFields.map(field => [field, record[field]])), ...Object.fromEntries([...Object.keys(detailTables), 'applicabilityCodes', 'replacementIds'].map(field => [field, record[field]])) };
}

export function readSourceCollection(connection, definitionCode, collectionId) {
  requireSourceText(definitionCode, 'Definition code');
  if (collectionId !== undefined) positiveInteger(collectionId, 'Collection identity');
  const collection = collectionId === undefined
    ? connection.get('SELECT collection.* FROM source_collection_heads head JOIN source_definitions definition ON definition.id = head.definition_id JOIN source_collections collection ON collection.id = head.collection_id WHERE definition.code = ?', [definitionCode])
    : connection.get('SELECT collection.* FROM source_collections collection JOIN source_definitions definition ON definition.id = collection.definition_id WHERE definition.code = ? AND collection.id = ? AND collection.outcome = ?', [definitionCode, collectionId, 'complete']);
  if (!collection) return null;
  if (connection.get('SELECT normalized_contract_version FROM source_definition_versions WHERE id = ?', [collection.definition_version_id])?.normalized_contract_version !== normalizedSourceContractVersion) throw new Error('Unsupported stored source normalization contract');
  const records = connection.all(`SELECT member.*, rule.external_key, version.captured_text, version.content_sha256, observation.* FROM source_collection_members member JOIN source_rules rule ON rule.id = member.source_rule_id JOIN source_versions version ON version.id = member.source_version_id JOIN source_observations observation ON observation.id = member.observation_id WHERE member.collection_id = ? ORDER BY member.ordinal`, [collection.id]).map(row => {
    const record = { sourceId: row.external_key, content: row.captured_text, contentSha256: row.content_sha256, presence: row.presence, removedAt: row.removed_at };
    observationFields.forEach((field, index) => { record[field] = row[scalarColumns[index]]; });
    for (const [field, [table, column]] of Object.entries(detailTables)) record[field] = connection.all(`SELECT ${column} AS value FROM ${table} WHERE observation_id = ? ORDER BY ordinal`, [row.observation_id]).map(detail => detail.value);
    record.applicabilityCodes = connection.all('SELECT definition.code FROM source_observation_applicabilities detail JOIN applicability_definitions definition ON definition.id = detail.applicability_id WHERE observation_id = ? ORDER BY ordinal', [row.observation_id]).map(detail => detail.code);
    record.replacementIds = connection.all('SELECT rule.external_key FROM source_observation_replacements detail JOIN source_rules rule ON rule.id = detail.replacement_rule_id WHERE observation_id = ? ORDER BY ordinal', [row.observation_id]).map(detail => detail.external_key);
    return { ...normalizeSourceRecords([record])[0], sourceRuleId: row.source_rule_id, sourceVersionId: row.source_version_id, observationId: row.observation_id };
  });
  return { collectionId: collection.id, definitionVersionId: collection.definition_version_id, inventorySha256: collection.inventory_sha256, records };
}

export function ingestSourceCollection(connection, request) {
  const fields = ['definitionVersionId', 'expectedCollectionId', 'repositoryContextId', 'collectorVersion', 'revision', 'complete', 'records'];
  requireSourceObject(request, [...fields, 'files'], fields, 'Source collection');
  positiveInteger(request.definitionVersionId, 'Definition version');
  positiveInteger(request.collectorVersion, 'Collector version');
  if (request.expectedCollectionId !== null) positiveInteger(request.expectedCollectionId, 'Expected collection');
  if (request.repositoryContextId !== null) positiveInteger(request.repositoryContextId, 'Repository context');
  if (request.complete !== true) throw new Error('Only complete source captures can be ingested');
  const incoming = normalizeSourceRecords(request.records);
  const capturedFiles = normalizeCapturedSourceFiles(request.files ?? []);
  return transaction(connection, () => {
    const definition = connection.get('SELECT version.*, definition.code FROM source_definition_versions version JOIN source_definitions definition ON definition.id = version.definition_id WHERE version.id = ? AND version.finalized = 1', [request.definitionVersionId]);
    if (!definition || definition.normalized_contract_version !== normalizedSourceContractVersion) throw new Error('Unsupported or missing source definition version');
    const revision = normalizeRevision(request.revision, definition);
    if (request.repositoryContextId !== null) {
      const context = connection.get('SELECT repository_id, commit_oid FROM repository_contexts WHERE id = ?', [request.repositoryContextId]);
      if (!context || context.repository_id !== definition.repository_id || context.commit_oid !== revision.resolvedCommit) throw new Error('Source revision does not match repository context');
    }
    const repository = connection.get('SELECT canonical_name FROM repositories WHERE id = ?', [definition.repository_id]);
    for (const record of incoming) if (record.presence === 'present' && record.originRepository !== null) {
      if (record.originRepository !== repository?.canonical_name || record.originCommit !== revision.resolvedCommit) throw new Error('Source origin does not match collection authority');
    }
    const prior = readSourceCollection(connection, definition.code);
    if ((prior?.collectionId ?? null) !== request.expectedCollectionId) throw new Error('Source collection changed; refresh the expected head');
    const now = new Date().toISOString();
    const priorRecords = new Map((prior?.records ?? []).map(record => [record.sourceId, record]));
    const records = [...incoming];
    for (const record of incoming) if (record.presence === 'missing-last-known') {
      const previous = priorRecords.get(record.sourceId);
      if (!previous || previous.contentSha256 !== record.contentSha256 || sourceTextHash(JSON.stringify(metadata(previous))) !== sourceTextHash(JSON.stringify(metadata(record)))) throw new Error('Missing sources must retain previously captured evidence');
      if (previous.presence === 'missing-last-known' && previous.removedAt !== record.removedAt) throw new Error('Missing sources must preserve their first removal observation');
    }
    const incomingKeys = new Set(incoming.map(record => record.sourceId));
    for (const previous of priorRecords.values()) if (!incomingKeys.has(previous.sourceId)) {
      const { sourceRuleId, sourceVersionId, observationId, ...record } = previous;
      records.push({ ...record, presence: 'missing-last-known', removedAt: record.removedAt ?? now });
    }
    records.sort((left, right) => left.sourceId < right.sourceId ? -1 : left.sourceId > right.sourceId ? 1 : 0);
    const inventoryHash = sourceTextHash(JSON.stringify({ definitionVersionId: definition.id, collectorVersion: request.collectorVersion, revision, records, files: capturedFiles.map(({ relativePath, contentSha256 }) => ({ relativePath, contentSha256 })) }));
    const collectionId = Number(connection.run(`INSERT INTO source_collections(definition_id, definition_version_id, repository_context_id, collector_version, source_revision_kind, resolved_commit, worktree_dirty, worktree_sha256, configured_ref, override_used, started_at, outcome) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'running')`, [definition.definition_id, definition.id, request.repositoryContextId, request.collectorVersion, revision.kind, revision.resolvedCommit, revision.worktreeDirty === undefined ? null : Number(revision.worktreeDirty), revision.worktreeSha256 ?? null, revision.configuredRef ?? null, revision.overrideUsed === undefined ? null : Number(revision.overrideUsed), now]).lastInsertRowid);
    const identity = key => {
      connection.run('INSERT INTO source_rules(definition_id, external_key) VALUES (?, ?) ON CONFLICT(definition_id, external_key) DO NOTHING', [definition.definition_id, key]);
      return connection.get('SELECT id FROM source_rules WHERE definition_id = ? AND external_key = ?', [definition.definition_id, key]).id;
    };
    records.forEach((record, ordinal) => {
      const ruleId = identity(record.sourceId);
      connection.run('INSERT INTO source_versions(source_rule_id, definition_id, captured_text, content_sha256) VALUES (?, ?, ?, ?) ON CONFLICT(source_rule_id, content_sha256) DO NOTHING', [ruleId, definition.definition_id, record.content, record.contentSha256]);
      const version = connection.get('SELECT id, captured_text FROM source_versions WHERE source_rule_id = ? AND content_sha256 = ?', [ruleId, record.contentSha256]);
      if (version.captured_text !== record.content) throw new Error('Source digest collision or inconsistent captured text');
      const metadataHash = sourceTextHash(JSON.stringify(metadata(record)));
      let observation = connection.get('SELECT id FROM source_observations WHERE source_version_id = ? AND metadata_sha256 = ? AND finalized = 1', [version.id, metadataHash]);
      if (!observation) {
        const observationId = Number(connection.run(`INSERT INTO source_observations(source_rule_id, source_version_id, definition_id, metadata_sha256, ${scalarColumns.join(', ')}) VALUES (?, ?, ?, ?, ${scalarColumns.map(() => '?').join(', ')})`, [ruleId, version.id, definition.definition_id, metadataHash, ...observationFields.map(field => record[field])]).lastInsertRowid);
        for (const [field, [table, column]] of Object.entries(detailTables)) record[field].forEach((value, position) => connection.run(`INSERT INTO ${table}(observation_id, ordinal, ${column}) VALUES (?, ?, ?)`, [observationId, position, value]));
        record.applicabilityCodes.forEach((code, position) => {
          const applicability = connection.get('SELECT id FROM applicability_definitions WHERE code = ?', [code]);
          if (!applicability) throw new Error('Source applicability is not registered by the selected profile');
          connection.run('INSERT INTO source_observation_applicabilities VALUES (?, ?, ?)', [observationId, position, applicability.id]);
        });
        record.replacementIds.forEach((key, position) => connection.run('INSERT INTO source_observation_replacements VALUES (?, ?, ?, ?)', [observationId, definition.definition_id, position, identity(key)]));
        connection.run('UPDATE source_observations SET finalized = 1 WHERE id = ?', [observationId]);
        observation = { id: observationId };
      }
      connection.run('INSERT INTO source_collection_members VALUES (?, ?, ?, ?, ?, ?, ?, ?)', [collectionId, ruleId, version.id, observation.id, definition.definition_id, ordinal, record.presence, record.removedAt]);
    });
    for (const file of capturedFiles) connection.run('INSERT INTO source_collection_files VALUES (?, ?, ?, ?)', [collectionId, file.relativePath, file.contentBytes, file.contentSha256]);
    connection.run("UPDATE source_collections SET inventory_sha256 = ?, completed_at = ?, outcome = 'complete' WHERE id = ?", [inventoryHash, new Date().toISOString(), collectionId]);
    connection.run('INSERT INTO source_collection_heads VALUES (?, ?) ON CONFLICT(definition_id) DO UPDATE SET collection_id = excluded.collection_id', [definition.definition_id, collectionId]);
    return readSourceCollection(connection, definition.code, collectionId);
  });
}
