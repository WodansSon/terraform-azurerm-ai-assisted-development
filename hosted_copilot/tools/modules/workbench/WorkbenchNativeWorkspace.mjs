import { randomUUID } from 'node:crypto';
import { requireSourceObject, requireSourceText, sourceTextHash } from './WorkbenchSourceRecords.mjs';
import { ingestSourceInventory } from './WorkbenchSourceIngestion.mjs';
import { ingestProtectedCapture } from './WorkbenchProtectedSnapshots.mjs';
import { readSelectedCapacityConfiguration } from './WorkbenchWorkspace.mjs';
import { configureProfileLlms } from './WorkbenchLlmAssignments.mjs';

function insert(connection, sql, parameters) {
  return Number(connection.run(sql, parameters).lastInsertRowid);
}

export function initializeNativeWorkspace(connection, request) {
  const fields = ['repository', 'profile', 'captures', 'protectedCapture'];
  requireSourceObject(request, fields, fields, 'Native workspace creation');
  const { repository, profile } = request;
  requireSourceObject(repository, ['canonicalName', 'branchRef', 'commitOid'], ['canonicalName', 'branchRef', 'commitOid'], 'Repository binding');
  for (const field of ['canonicalName', 'branchRef', 'commitOid']) requireSourceText(repository[field], field);
  requireSourceObject(profile, ['schemaVersion', 'code', 'label', 'runtimeRequestTokenLimit', 'guidanceTokenBudget', 'charactersPerToken',
    'safetyMarginPercent', 'categories', 'fixedGuidanceFiles', 'scoringFactors', 'provenanceCodes', 'llmConfiguration'], ['schemaVersion', 'code', 'label', 'runtimeRequestTokenLimit',
    'guidanceTokenBudget', 'charactersPerToken', 'safetyMarginPercent', 'categories', 'fixedGuidanceFiles', 'scoringFactors', 'provenanceCodes', 'llmConfiguration'], 'Current Terraform profile');
  if (profile.schemaVersion !== 1 || profile.categories.length !== 3) throw new Error('Unsupported current Terraform profile');
  if (!Array.isArray(request.captures) || request.captures.length === 0) throw new Error('Fresh complete source captures are required');
  if (connection.isTransaction || connection.get('SELECT count(*) AS count FROM workspace_identity').count !== 0) {
    throw new Error('Native creation requires a new uninitialized workspace and its own transaction');
  }
  const now = new Date().toISOString();
  const databaseGuid = randomUUID();
  let phase = 'workspace and profile';
  connection.exec('BEGIN IMMEDIATE');
  try {
    const capacityId = insert(connection, `INSERT INTO capacity_policies(code, revision, estimator_code, estimator_version, characters_per_token,
      safety_margin_percent, runtime_request_token_limit, guidance_token_budget) VALUES (?, 1, 'character-quarter-estimate-v1', '1', ?, ?, ?, ?)`,
    [profile.code, profile.charactersPerToken, profile.safetyMarginPercent, profile.runtimeRequestTokenLimit, profile.guidanceTokenBudget]);
    const teamId = insert(connection, 'INSERT INTO team_profiles(code, label, capacity_policy_id) VALUES (?, ?, ?)', [profile.code, profile.label, capacityId]);
    configureProfileLlms(connection, teamId, profile.llmConfiguration);
    const repositoryId = insert(connection, "INSERT INTO repositories(provider_code, canonical_name) VALUES ('local-git', ?)", [repository.canonicalName]);
    const contextId = insert(connection, 'INSERT INTO repository_contexts(repository_id, branch_ref, commit_oid, observed_at) VALUES (?, ?, ?, ?)',
      [repositoryId, repository.branchRef, repository.commitOid, now]);
    const actorId = insert(connection, "INSERT INTO actors(actor_kind, provider_code, provider_actor_id, display_name) VALUES ('system', NULL, NULL, 'SYSTEM')", []);
    connection.run(`INSERT INTO workspace_identity(id, database_guid, team_profile_id, origin_context_id, created_by_actor_id, created_at)
      VALUES (1, ?, ?, ?, ?, ?)`, [databaseGuid, teamId, contextId, actorId, now]);
    for (const code of ['add', 'update', 'retire', 'restore', 'no-change', 'exclude', 'defer']) connection.run('INSERT INTO action_definitions(code, label) VALUES (?, ?)', [code, code]);
    connection.run("INSERT INTO plan_add_methods(code, label) VALUES ('manual', 'Manual'), ('bulk', 'Bulk')");
    for (const category of profile.categories) {
      const surfaceId = insert(connection, `INSERT INTO guidance_surfaces(code, revision, label, output_relative_path, renderer_code)
        VALUES (?, 1, ?, ?, 'hosted-markdown-v1')`, [category.code, category.label, category.outputPath]);
      connection.run('INSERT INTO guidance_surface_content VALUES (?, ?, ?, ?, ?)', [surfaceId, category.description, category.label, '', '']);
      for (const pattern of category.patterns) connection.run('INSERT INTO surface_patterns VALUES (?, ?)', [surfaceId, pattern]);
      connection.run("INSERT INTO applicability_definitions(code, label, renderer_code) VALUES (?, ?, 'source-category')", [category.code, category.label]);
      const bucketId = insert(connection, "INSERT INTO capacity_buckets(policy_id, code, label, guarded_limit, accounting_mode) VALUES (?, ?, ?, ?, 'surface-sum')",
        [capacityId, category.code, category.label, category.budgetTokens]);
      connection.run('INSERT INTO capacity_bucket_surfaces VALUES (?, ?)', [bucketId, surfaceId]);
      for (const [ordinal, heading] of category.sections.entries()) connection.run('INSERT INTO guidance_sections VALUES (?, ?, ?)', [surfaceId, ordinal, heading]);
    }
    for (const file of profile.fixedGuidanceFiles) {
      const bucketId = insert(connection, "INSERT INTO capacity_buckets(policy_id, code, label, guarded_limit, accounting_mode) VALUES (?, ?, ?, ?, 'surface-sum')",
        [capacityId, file.code, file.code, file.budgetTokens]);
      connection.run('INSERT INTO capacity_bucket_files VALUES (?, ?)', [bucketId, file.path]);
    }
    for (const code of ['legacy', 'typed', 'framework']) connection.run("INSERT INTO applicability_definitions(code, label, renderer_code) VALUES (?, ?, 'implementation-model')", [code, code]);
    for (const provenance of profile.provenanceCodes) connection.run('INSERT INTO source_provenance_codes VALUES (?, ?)', [provenance.code, provenance.label]);
    const scoringId = insert(connection, "INSERT INTO scoring_policies(code, revision, minimum_total) VALUES ('terraform-selection', 1, 0)", []);
    for (const factor of profile.scoringFactors) connection.run(`INSERT INTO scoring_factors(policy_id, code, label, description, minimum_value, maximum_value,
      weight, contribution_kind) VALUES (?, ?, ?, ?, 0, 5, ?, ?)`, [scoringId, factor.code, factor.label, factor.description, factor.weight, factor.kind]);
    readSelectedCapacityConfiguration(connection, { databaseGuid, repositoryId, branchRef: repository.branchRef });
    const collections = [];
    for (const capture of request.captures) {
      phase = `source capture ${capture.definition.id}`;
      requireSourceObject(capture, ['definition', 'definitionJson', 'inventoryJson', 'parserContract', 'lane'],
        ['definition', 'definitionJson', 'inventoryJson', 'parserContract', 'lane'], 'Fresh parser capture');
      const { definition, parserContract } = capture;
      const inventory = JSON.parse(capture.inventoryJson);
      let sourceRepositoryId = repositoryId;
      if (definition.root.kind === 'github') {
        connection.run("INSERT INTO repositories(provider_code, canonical_name) VALUES ('github', ?) ON CONFLICT(provider_code, canonical_name) DO NOTHING", [definition.root.repository]);
        sourceRepositoryId = connection.get("SELECT id FROM repositories WHERE provider_code = 'github' AND canonical_name = ?", [definition.root.repository]).id;
      }
      const collection = ingestSourceInventory(connection, {
        profile: { code: definition.id, label: definition.displayName, lane: capture.lane, parserId: definition.parser,
          parserContractSha256: inventory.parserContractSha256, definitionSha256: sourceTextHash(capture.definitionJson), repositoryId: sourceRepositoryId,
          rootKind: definition.root.kind, location: definition.root.path, configuredRef: definition.root.ref ?? null,
          contentFormat: 'utf8-source-records', assessmentBatchSize: definition.assessmentBatchSize,
          assessmentCardinality: parserContract.assessmentCardinality, files: definition.files, exclude: definition.exclude },
        inventoryJson: capture.inventoryJson, captureSha256: sourceTextHash(capture.inventoryJson),
        inventoryConfigurationSha256: inventory.inventoryConfigurationSha256, expectedRevision: inventory.collection.sourceRevision,
        expectedCollectionId: null, repositoryContextId: sourceRepositoryId === repositoryId ? contextId : null,
      });
      collections.push({ definitionId: definition.id, collectionId: collection.collectionId, count: collection.records.length });
    }
    phase = 'protected capture';
    const snapshot = ingestProtectedCapture(connection, { ...request.protectedCapture, repositoryContextId: contextId });
    phase = 'current protected reference';
    connection.run('UPDATE workspace_identity SET current_protected_snapshot_id = ? WHERE id = 1', [snapshot.snapshotId]);
    if (connection.all('PRAGMA foreign_key_check').length !== 0) throw new Error('Fresh workspace references are invalid');
    connection.exec('COMMIT');
    return { databaseGuid, repositoryId, branchRef: repository.branchRef, protectedSnapshotId: snapshot.snapshotId,
      collections, readyForAnalysis: true, readyForUi: false };
  } catch (error) {
    if (connection.isTransaction) connection.exec('ROLLBACK');
    throw new Error(`Native creation failed during ${phase}: ${error.message}`, { cause: error });
  }
}
