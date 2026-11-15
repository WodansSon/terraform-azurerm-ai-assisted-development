import { randomUUID } from 'node:crypto';
import { requireSourceObject, requireSourceText, sourceTextHash } from './WorkbenchSourceRecords.mjs';
import { ingestSourceInventory } from './WorkbenchSourceIngestion.mjs';
import { ingestProtectedCapture } from './WorkbenchProtectedSnapshots.mjs';
import { readSelectedCapacityConfiguration } from './WorkbenchWorkspace.mjs';
import { configureProfileLlms } from './WorkbenchLlmAssignments.mjs';
import { parseInitialRulesJson } from './WorkbenchInitialCatalog.mjs';

function insert(connection, sql, parameters) {
  return Number(connection.run(sql, parameters).lastInsertRowid);
}

// Re-extract the staged rule index from exact guidance captures instead of trusting an independently supplied projection.
function readStagedBootstrap(serialized, profile) {
  const catalog = JSON.parse(serialized);
  const fields = ['$schema', 'schemaVersion', 'kind', 'state', 'approval', 'profileCode', 'source', 'files', 'rules'];
  requireSourceObject(catalog, fields, fields, 'Staged bootstrap catalog');
  if (catalog.$schema !== '../../contracts/catalog/instruction-catalog-bootstrap.schema.json' || catalog.schemaVersion !== 1 ||
      catalog.kind !== 'hosted-guidance-bootstrap' || catalog.state !== 'staged' || catalog.approval !== 'not-recorded' ||
      catalog.profileCode !== profile.code || catalog.source !== 'repository-guidance-files') throw new Error('Unsupported staged bootstrap catalog');
  const expectedFiles = [...profile.categories.map(category => ({ relativePath: category.outputPath, role: 'instructions', surface: category.code, patterns: category.patterns })),
    ...profile.fixedGuidanceFiles.map(file => ({ relativePath: file.path, role: file.code === 'repository' ? 'repository' : 'skill' }))];
  if (!Array.isArray(catalog.files) || catalog.files.length !== expectedFiles.length || new Set(catalog.files.map(file => file.relativePath)).size !== expectedFiles.length ||
      !Array.isArray(catalog.rules) || !catalog.rules.length) throw new Error('Staged bootstrap requires complete unique guidance and rules');
  const extracted = [];
  for (const expected of expectedFiles) {
    const file = catalog.files.find(item => item.relativePath === expected.relativePath);
    const allowed = [...Object.keys(expected), 'contentSha256', 'content'];
    requireSourceObject(file, allowed, allowed, 'Staged guidance capture');
    for (const [key, value] of Object.entries(expected)) if (JSON.stringify(file[key]) !== JSON.stringify(value)) throw new Error('Staged guidance does not match the selected profile');
    requireSourceText(file.content, 'Staged guidance content');
    if (file.content.includes('\0') || sourceTextHash(file.content) !== file.contentSha256) throw new Error(`Staged guidance hash is invalid: ${file.relativePath}`);
    if (file.role !== 'instructions') continue;
    let section;
    for (const [index, line] of file.content.split(/\r?\n/).entries()) {
      if (line.startsWith('## ')) section = line.slice(3).trim();
      const match = /^- `\[([A-Z]+-[A-Z0-9]+-[0-9]+[A-Z]?)\]` (.+)$/.exec(line);
      if (!match) continue;
      if (!section) throw new Error('Staged rule requires a section');
      const models = /^\[(legacy|typed|framework)(?:, (?:legacy|typed|framework))*\] /.exec(match[2]);
      extracted.push({ id: match[1], surface: file.surface, kind: section === 'Protected Rules' ? 'protected' : 'managed',
        section, sourcePath: file.relativePath, sourceLine: index + 1, text: match[2],
        ...(models ? { implementationModels: models[0].slice(1, -2).split(', ') } : {}) });
    }
  }
  if (JSON.stringify(extracted) !== JSON.stringify(catalog.rules) || new Set(extracted.map(rule => rule.id)).size !== extracted.length) {
    throw new Error('Staged rule index does not match its exact guidance captures');
  }
  return catalog;
}

// Seed an unpublished manual-guidance baseline, checking protected rules against their independent authored capture.
function seedStagedBootstrap(connection, catalog, serialized, protectedSnapshotId, now) {
  const catalogId = insert(connection, `INSERT INTO catalog_versions(protected_snapshot_id, capture_kind, revision, input_schema_version,
    default_requirement_level, default_enforcement_method, default_documentation_gap, content_fingerprint, created_at)
    VALUES (?, 'manual-guidance', 1, ?, 'mandatory', 'model-based', 0, ?, ?)`, [protectedSnapshotId, catalog.schemaVersion, sourceTextHash(serialized), now]);
  for (const file of catalog.files) {
    const surfaceId = file.role === 'instructions' ? connection.get('SELECT id FROM guidance_surfaces WHERE code = ?', [file.surface]).id : null;
    connection.run('INSERT INTO catalog_guidance_files VALUES (?, ?, ?, ?, ?, ?)', [catalogId, file.relativePath, file.role, surfaceId, file.contentSha256, file.content]);
    if (surfaceId !== null) {
      const title = /^# (.+)$/m.exec(file.content)?.[1];
      const description = /^description: "(.+)"\r?$/m.exec(file.content)?.[1];
      const introduction = file.content.split(/^## /m)[0].split(/^# .+\r?$/m)[1]?.trim();
      if (!title || !description || !introduction) throw new Error('Staged instructions require their exact title, description and introduction');
      connection.run('INSERT INTO catalog_surface_content VALUES (?, ?, ?, ?, ?, ?)', [catalogId, surfaceId, description, title, introduction, '']);
      const headings = [...new Set(catalog.rules.filter(rule => rule.surface === file.surface && rule.kind === 'managed').map(rule => rule.section))];
      for (const [ordinal, heading] of headings.entries()) {
        if (!connection.get('SELECT heading FROM guidance_sections WHERE surface_id = ? AND heading = ?', [surfaceId, heading])) throw new Error('Staged rule section is not configured');
        connection.run('INSERT INTO catalog_surface_sections VALUES (?, ?, ?, ?)', [catalogId, surfaceId, ordinal, heading]);
      }
    }
  }
  for (const [ordinal, rule] of catalog.rules.entries()) {
    const surfaceId = connection.get('SELECT id FROM guidance_surfaces WHERE code = ?', [rule.surface]).id;
    if (rule.kind === 'protected') {
      const protectedRule = connection.get(`SELECT wording.text FROM protected_members member JOIN rules rule ON rule.id = member.rule_id
        JOIN rule_versions version ON version.id = member.rule_version_id JOIN wording_versions wording ON wording.id = version.wording_version_id
        JOIN protected_rule_details detail ON detail.rule_version_id = version.id WHERE member.snapshot_id = ? AND rule.displayed_id = ? AND detail.surface_id = ?`,
      [protectedSnapshotId, rule.id, surfaceId]);
      if (protectedRule?.text !== rule.text) throw new Error('Staged protection must match the independently captured authored rule');
      continue;
    }
    if (connection.get('SELECT id FROM rules WHERE displayed_id = ?', [rule.id])) throw new Error('Staged managed identity conflicts with captured protection');
    const ruleId = insert(connection, "INSERT INTO rules(displayed_id, rule_kind) VALUES (?, 'managed')", [rule.id]);
    const models = /^\[(?:legacy|typed|framework)(?:, (?:legacy|typed|framework))*\] /.exec(rule.text);
    const text = models ? rule.text.slice(models[0].length) : rule.text;
    const wordingId = insert(connection, 'INSERT INTO wording_versions(text, content_sha256, created_at) VALUES (?, ?, ?)', [text, sourceTextHash(text), now]);
    const versionId = insert(connection, `INSERT INTO rule_versions(rule_id, revision, wording_version_id, lifecycle, origin_code)
      VALUES (?, 1, ?, 'active', 'hosted-manual-bootstrap')`, [ruleId, wordingId]);
    connection.run('INSERT INTO catalog_members VALUES (?, ?, ?)', [catalogId, ruleId, versionId]);
    connection.run('INSERT INTO catalog_rule_guidance(catalog_id, rule_id, relative_path, source_line) VALUES (?, ?, ?, ?)', [catalogId, ruleId, rule.sourcePath, rule.sourceLine]);
    connection.run('INSERT INTO rule_provenances VALUES (?, 0, ?)', [versionId, 'unclassified']);
    connection.run('INSERT INTO rule_placements VALUES (?, ?, ?, ?)', [versionId, surfaceId, rule.section, ordinal]);
    for (const code of rule.implementationModels ?? []) {
      const applicability = connection.get("SELECT id FROM applicability_definitions WHERE code = ? AND renderer_code = 'implementation-model'", [code]);
      connection.run('INSERT INTO rule_applicabilities VALUES (?, ?)', [versionId, applicability.id]);
    }
  }
  connection.run('UPDATE catalog_versions SET finalized_at = ? WHERE id = ?', [now, catalogId]);
  connection.run('INSERT INTO workspace_staging VALUES (1, ?)', [catalogId]);
  return catalogId;
}

// Validate the supported published-catalog shape, lifecycle state, references, and canonical source mappings.
function readCurrentCatalog(serialized) {
  requireSourceText(serialized, 'Current catalog capture');
  const catalog = JSON.parse(serialized);
  const fields = ['$schema', 'schemaVersion', 'lastSemanticReview', 'upstreamSnapshot', 'ruleDefaults', 'sources', 'evidence', 'surfaces', 'canonicalCandidateMappings', 'rules'];
  requireSourceObject(catalog, fields, fields, 'Current catalog');
  if (catalog.$schema !== 'instruction-catalog.schema.json' || catalog.schemaVersion !== 1) throw new Error('Current catalog format is not supported');
  requireSourceText(catalog.lastSemanticReview, 'Catalog semantic review');
  requireSourceObject(catalog.upstreamSnapshot, ['repository', 'baselineCommit', 'currentRef'], ['repository', 'baselineCommit', 'currentRef'], 'Catalog upstream');
  for (const field of ['repository', 'baselineCommit', 'currentRef']) requireSourceText(catalog.upstreamSnapshot[field], `Catalog upstream ${field}`);
  requireSourceObject(catalog.ruleDefaults, ['requirementLevel', 'enforcementMethod', 'documentationGap'], ['requirementLevel', 'enforcementMethod', 'documentationGap'], 'Catalog defaults');
  if (catalog.ruleDefaults.requirementLevel !== 'mandatory' || catalog.ruleDefaults.enforcementMethod !== 'model-based' || catalog.ruleDefaults.documentationGap !== false) {
    throw new Error('Current catalog defaults are not supported');
  }
  for (const field of ['sources', 'evidence', 'surfaces', 'rules']) {
    if (!Array.isArray(catalog[field]) || (field !== 'sources' && !catalog[field].length)) throw new Error('Current catalog requires complete definitions and rules');
    if (new Set(catalog[field].map(row => row.id)).size !== catalog[field].length) throw new Error('Current catalog contains repeated identities');
  }
  requireSourceObject(catalog.canonicalCandidateMappings, catalog.rules.map(rule => rule.id), catalog.rules.map(rule => rule.id), 'Catalog canonical provenance');
  for (const rule of catalog.rules) {
    const required = ['id', 'origin', 'status', 'text', 'provenance', 'sourceIds', 'evidenceIds'];
    requireSourceObject(rule, [...required, 'implementationModels', 'documentationGap', 'retirementReason', 'lastPlacement'], required, 'Current catalog rule');
    for (const field of ['id', 'origin', 'status', 'text']) requireSourceText(rule[field], `Catalog rule ${field}`);
    if (!['active', 'retired'].includes(rule.status) || !['hosted-baseline-migration', 'hosted-catalog-addition'].includes(rule.origin)) throw new Error('Unsupported catalog rule lifecycle or origin');
    if (rule.documentationGap !== undefined && typeof rule.documentationGap !== 'boolean') throw new Error('Catalog documentation gap must be explicit boolean data');
    for (const field of ['provenance', 'sourceIds', 'evidenceIds', ...(rule.implementationModels === undefined ? [] : ['implementationModels'])]) {
      if (!Array.isArray(rule[field]) || new Set(rule[field]).size !== rule[field].length || (field !== 'sourceIds' && !rule[field].length)) throw new Error('Catalog rule references must be unique complete lists');
      rule[field].forEach(value => requireSourceText(value, 'Catalog rule reference'));
    }
    if (rule.status === 'retired') {
      requireSourceText(rule.retirementReason, 'Catalog retirement reason');
      requireSourceObject(rule.lastPlacement, ['surfaceId', 'sectionHeading'], ['surfaceId', 'sectionHeading'], 'Retired catalog placement');
    } else if (rule.retirementReason !== undefined || rule.lastPlacement !== undefined) throw new Error('Active catalog rules cannot carry retirement state');
    const mapping = catalog.canonicalCandidateMappings[rule.id];
    requireSourceObject(mapping, ['sourceDefinitionId', 'sourceId', 'assessmentId'], ['sourceDefinitionId', 'sourceId'], 'Canonical source provenance');
    for (const field of ['sourceDefinitionId', 'sourceId']) requireSourceText(mapping[field], 'Canonical source provenance');
    if (Object.hasOwn(mapping, 'assessmentId') && (typeof mapping.assessmentId !== 'string' || !/^[A-Za-z][A-Za-z0-9-]*$/.test(mapping.assessmentId))) {
      throw new Error('Canonical assessment provenance must use a supported assessment identifier');
    }
  }
  return catalog;
}

// Reconstruct the existing publication and its source provenance without fabricating new maintainer approval.
function seedCurrentCatalog(connection, catalog, serialized, protectedSnapshotId, now) {
  connection.run("INSERT INTO repositories(provider_code, canonical_name) VALUES ('github', ?) ON CONFLICT(provider_code, canonical_name) DO NOTHING", [catalog.upstreamSnapshot.repository]);
  const upstreamId = connection.get("SELECT id FROM repositories WHERE provider_code = 'github' AND canonical_name = ?", [catalog.upstreamSnapshot.repository]).id;
  const catalogId = insert(connection, `INSERT INTO catalog_versions(parent_catalog_id, protected_snapshot_id, revision, input_schema_version, last_semantic_review,
    upstream_repository_id, upstream_baseline_commit, upstream_current_ref, default_requirement_level, default_enforcement_method, default_documentation_gap,
    content_fingerprint, created_at) VALUES (NULL, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  [protectedSnapshotId, catalog.schemaVersion, catalog.lastSemanticReview, upstreamId, catalog.upstreamSnapshot.baselineCommit, catalog.upstreamSnapshot.currentRef,
    catalog.ruleDefaults.requirementLevel, catalog.ruleDefaults.enforcementMethod, Number(catalog.ruleDefaults.documentationGap), sourceTextHash(serialized), now]);
  for (const [ordinal, source] of catalog.sources.entries()) {
    const fields = ['id', 'title', 'rawUrl', 'referenceUrl', 'baselineSha256'];
    requireSourceObject(source, fields, fields, 'Catalog source');
    fields.forEach(field => requireSourceText(source[field], 'Catalog source field'));
    connection.run('INSERT INTO catalog_sources VALUES (?, ?, ?, ?, ?, ?, ?)', [catalogId, source.id, ordinal, source.title, source.rawUrl, source.referenceUrl, source.baselineSha256]);
  }
  for (const [ordinal, evidence] of catalog.evidence.entries()) {
    const fields = ['id', 'type', 'description', 'reference'];
    requireSourceObject(evidence, fields, fields, 'Catalog evidence');
    fields.forEach(field => requireSourceText(evidence[field], 'Catalog evidence field'));
    connection.run('INSERT INTO catalog_evidence VALUES (?, ?, ?, ?, ?, ?)', [catalogId, evidence.id, ordinal, evidence.type, evidence.description, evidence.reference]);
  }
  const surfaces = new Map();
  const placements = new Map(catalog.rules.map(rule => [rule.id, []]));
  for (const surface of catalog.surfaces) {
    const fields = ['id', 'outputPath', 'description', 'applyTo', 'title', 'introduction', 'sections', 'closing'];
    requireSourceObject(surface, fields, fields, 'Catalog surface');
    for (const field of fields.filter(field => field !== 'sections')) requireSourceText(surface[field], 'Catalog surface field');
    const selected = connection.get('SELECT id, output_relative_path FROM guidance_surfaces WHERE code = ?', [surface.id]);
    const patterns = selected ? connection.all('SELECT pattern FROM surface_patterns WHERE surface_id = ?', [selected.id]) : [];
    if (!selected || selected.output_relative_path !== surface.outputPath || patterns.length !== 1 || patterns[0].pattern !== surface.applyTo ||
      !Array.isArray(surface.sections) || !surface.sections.length || new Set(surface.sections.map(section => section.heading)).size !== surface.sections.length) {
      throw new Error('Current catalog surface does not match the selected profile');
    }
    surfaces.set(surface.id, selected.id);
    connection.run('INSERT INTO catalog_surface_content VALUES (?, ?, ?, ?, ?, ?)', [catalogId, selected.id, surface.description, surface.title, surface.introduction, surface.closing]);
    for (const [ordinal, section] of surface.sections.entries()) {
      requireSourceObject(section, ['heading', 'ruleIds'], ['heading', 'ruleIds'], 'Catalog section');
      requireSourceText(section.heading, 'Catalog section heading');
      if (!Array.isArray(section.ruleIds) || !section.ruleIds.length || !connection.get('SELECT heading FROM guidance_sections WHERE surface_id = ? AND heading = ?', [selected.id, section.heading])) {
        throw new Error('Catalog section must belong to its selected surface');
      }
      connection.run('INSERT INTO catalog_surface_sections VALUES (?, ?, ?, ?)', [catalogId, selected.id, ordinal, section.heading]);
      for (const [displayOrder, ruleId] of section.ruleIds.entries()) {
        const rulePlacements = placements.get(ruleId);
        if (!rulePlacements || rulePlacements.some(placement => placement[0] === selected.id && placement[1] === section.heading)) throw new Error('Catalog section references a foreign or repeated rule');
        rulePlacements.push([selected.id, section.heading, displayOrder]);
      }
    }
  }
  if (surfaces.size !== connection.get('SELECT count(*) AS count FROM guidance_surfaces').count) throw new Error('Catalog capture must cover every configured surface');
  for (const rule of catalog.rules) {
    if (connection.get('SELECT id FROM rules WHERE displayed_id = ?', [rule.id])) throw new Error('Catalog managed identity conflicts with captured protection');
    const ruleId = insert(connection, "INSERT INTO rules(displayed_id, rule_kind) VALUES (?, 'managed')", [rule.id]);
    const wordingId = insert(connection, 'INSERT INTO wording_versions(text, content_sha256, created_at) VALUES (?, ?, ?)', [rule.text, sourceTextHash(rule.text), now]);
    const versionId = insert(connection, `INSERT INTO rule_versions(rule_id, revision, wording_version_id, lifecycle, retirement_reason, origin_code, documentation_gap)
      VALUES (?, 1, ?, ?, ?, ?, ?)`, [ruleId, wordingId, rule.status, rule.retirementReason ?? null, rule.origin, rule.documentationGap === undefined ? null : Number(rule.documentationGap)]);
    connection.run('INSERT INTO catalog_members VALUES (?, ?, ?)', [catalogId, ruleId, versionId]);
    for (const [ordinal, code] of rule.provenance.entries()) {
      if (!connection.get('SELECT code FROM source_provenance_codes WHERE code = ?', [code])) throw new Error('Catalog provenance is not configured');
      connection.run('INSERT INTO rule_provenances VALUES (?, ?, ?)', [versionId, ordinal, code]);
    }
    for (const [ordinal, sourceId] of rule.sourceIds.entries()) connection.run('INSERT INTO catalog_member_sources VALUES (?, ?, ?, ?)', [catalogId, ruleId, ordinal, sourceId]);
    for (const [ordinal, evidenceId] of rule.evidenceIds.entries()) connection.run('INSERT INTO catalog_member_evidence VALUES (?, ?, ?, ?)', [catalogId, ruleId, ordinal, evidenceId]);
    for (const code of rule.implementationModels ?? []) {
      const applicability = connection.get("SELECT id FROM applicability_definitions WHERE code = ? AND renderer_code = 'implementation-model'", [code]);
      if (!applicability) throw new Error('Catalog implementation model is not configured');
      connection.run('INSERT INTO rule_applicabilities VALUES (?, ?)', [versionId, applicability.id]);
    }
    const selectedPlacements = placements.get(rule.id);
    if (rule.status === 'retired') {
      const surfaceId = surfaces.get(rule.lastPlacement.surfaceId);
      if (selectedPlacements.length || !surfaceId || !connection.get('SELECT heading FROM catalog_surface_sections WHERE catalog_id = ? AND surface_id = ? AND heading = ?', [catalogId, surfaceId, rule.lastPlacement.sectionHeading])) {
        throw new Error('Retired catalog rule must retain only its valid last placement');
      }
      selectedPlacements.push([surfaceId, rule.lastPlacement.sectionHeading, 0]);
    } else if (!selectedPlacements.length) throw new Error('Active catalog rule lacks published placement');
    for (const placement of selectedPlacements) connection.run('INSERT INTO rule_placements VALUES (?, ?, ?, ?)', [versionId, ...placement]);
    const mapping = catalog.canonicalCandidateMappings[rule.id];
    const source = connection.get(`SELECT rule.id FROM source_rules rule JOIN source_definitions definition ON definition.id = rule.definition_id
      WHERE definition.code = ? AND rule.external_key = ?`, [mapping.sourceDefinitionId, mapping.sourceId]);
    if (!source) throw new Error('Catalog canonical provenance does not resolve in the selected captured source definitions');
    connection.run('INSERT INTO catalog_canonical_bindings VALUES (?, ?, ?, ?)', [catalogId, ruleId, source.id, mapping.assessmentId ?? null]);
  }
  connection.run('UPDATE catalog_versions SET finalized_at = ? WHERE id = ?', [now, catalogId]);
  connection.run('INSERT INTO workspace_publication VALUES (1, ?)', [catalogId]);
  return catalogId;
}

// Preserve initial JSON wording and instruction metadata as a staged baseline with exact per-rule source pointers.
function seedInitialRules(connection, catalog, protectedSnapshotId, now) {
  const catalogId = insert(connection, `INSERT INTO catalog_versions(protected_snapshot_id, capture_kind, revision, input_schema_version,
    default_requirement_level, default_enforcement_method, default_documentation_gap, content_fingerprint, created_at)
    VALUES (?, 'initial-rules', 1, 1, 'mandatory', 'model-based', 0, ?, ?)`, [protectedSnapshotId, catalog.source.contentSha256, now]);
  connection.run('INSERT INTO catalog_guidance_files VALUES (?, ?, ?, NULL, ?, ?)',
    [catalogId, catalog.source.relativePath, 'baseline', catalog.source.contentSha256, catalog.source.content]);
  for (const surface of catalog.surfaces) {
    const surfaceId = connection.get('SELECT id FROM guidance_surfaces WHERE code = ?', [surface.code]).id;
    connection.run('INSERT INTO catalog_surface_content VALUES (?, ?, ?, ?, ?, ?)',
      [catalogId, surfaceId, surface.description, surface.title, surface.introduction, surface.closing]);
    connection.run('INSERT INTO catalog_surface_sections VALUES (?, ?, 0, ?)', [catalogId, surfaceId, 'Rules']);
  }
  for (const [ordinal, rule] of catalog.rules.entries()) {
    if (connection.get('SELECT id FROM rules WHERE displayed_id = ?', [rule.id])) throw new Error('Initial managed identity conflicts with captured protection');
    const ruleId = insert(connection, "INSERT INTO rules(displayed_id, rule_kind) VALUES (?, 'managed')", [rule.id]);
    const wordingId = insert(connection, 'INSERT INTO wording_versions(text, content_sha256, created_at) VALUES (?, ?, ?)', [rule.text, sourceTextHash(rule.text), now]);
    const versionId = insert(connection, `INSERT INTO rule_versions(rule_id, revision, wording_version_id, lifecycle, origin_code)
      VALUES (?, 1, ?, 'active', 'hosted-initial-json')`, [ruleId, wordingId]);
    const surfaceId = connection.get('SELECT id FROM guidance_surfaces WHERE code = ?', [rule.surface]).id;
    connection.run('INSERT INTO catalog_members VALUES (?, ?, ?)', [catalogId, ruleId, versionId]);
    connection.run('INSERT INTO catalog_rule_guidance(catalog_id, rule_id, relative_path, source_pointer) VALUES (?, ?, ?, ?)',
      [catalogId, ruleId, catalog.source.relativePath, rule.sourcePointer]);
    connection.run('INSERT INTO rule_provenances VALUES (?, 0, ?)', [versionId, 'unclassified']);
    connection.run('INSERT INTO rule_placements VALUES (?, ?, ?, ?)', [versionId, surfaceId, rule.section, ordinal]);
    for (const code of rule.implementationModels) {
      const applicability = connection.get("SELECT id FROM applicability_definitions WHERE code = ? AND renderer_code = 'implementation-model'", [code]);
      connection.run('INSERT INTO rule_applicabilities VALUES (?, ?)', [versionId, applicability.id]);
    }
  }
  connection.run('UPDATE catalog_versions SET finalized_at = ? WHERE id = ?', [now, catalogId]);
  connection.run('INSERT INTO workspace_staging VALUES (1, ?)', [catalogId]);
  return catalogId;
}

// Atomically bind a fresh database to its repository, profile, source captures, protection, and selected initial baseline.
export function initializeNativeWorkspace(connection, request) {
  const fields = ['repository', 'profile', 'captures', 'protectedCapture'];
  requireSourceObject(request, [...fields, 'catalogJson', 'initialRulesCapture'], fields, 'Native workspace creation');
  if (Object.hasOwn(request, 'catalogJson') === Object.hasOwn(request, 'initialRulesCapture')) throw new Error('Select exactly one initial catalog input');
  const { repository } = request;
  let { profile } = request;
  requireSourceObject(repository, ['canonicalName', 'branchRef', 'commitOid'], ['canonicalName', 'branchRef', 'commitOid'], 'Repository binding');
  for (const field of ['canonicalName', 'branchRef', 'commitOid']) requireSourceText(repository[field], field);
  requireSourceObject(profile, ['schemaVersion', 'code', 'label', 'runtimeRequestTokenLimit', 'guidanceTokenBudget', 'charactersPerToken',
    'safetyMarginPercent', 'categories', 'fixedGuidanceFiles', 'scoringFactors', 'provenanceCodes', 'llmConfiguration'], ['schemaVersion', 'code', 'label', 'runtimeRequestTokenLimit',
    'guidanceTokenBudget', 'charactersPerToken', 'safetyMarginPercent', 'categories', 'fixedGuidanceFiles', 'scoringFactors', 'provenanceCodes', 'llmConfiguration'], 'Current Terraform profile');
  if (profile.schemaVersion !== 1 || profile.categories.length !== 3) throw new Error('Unsupported current Terraform profile');
  const initial = Object.hasOwn(request, 'initialRulesCapture') ? parseInitialRulesJson(request.initialRulesCapture, profile) : null;
  const bootstrap = initial === null && JSON.parse(request.catalogJson).kind === 'hosted-guidance-bootstrap';
  const catalog = initial ?? (bootstrap ? readStagedBootstrap(request.catalogJson, profile) : readCurrentCatalog(request.catalogJson));
  if (initial !== null) profile = { ...profile, categories: profile.categories.map(category => {
    const surface = initial.surfaces.find(item => item.code === category.code);
    return { ...category, description: surface.description, patterns: surface.patterns, sections: surface.sections };
  }) };
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
    phase = 'current managed catalog';
    const catalogId = initial !== null ? seedInitialRules(connection, initial, snapshot.snapshotId, now)
      : (bootstrap ? seedStagedBootstrap : seedCurrentCatalog)(connection, catalog, request.catalogJson, snapshot.snapshotId, now);
    connection.run(`INSERT INTO audit_events(actor_id, repository_context_id, severity, action_code, outcome, occurred_at, safe_summary)
      VALUES (?, ?, 'info', 'initial-catalog-import', 'complete', ?, ?)`, [actorId, contextId, now, initial !== null
      ? 'Initial JSON baseline imported without approval or publication'
      : bootstrap ? 'Manual guidance baseline captured without approval or publication' : 'Existing published catalog imported without new approval or deployment']);
    if (connection.all('PRAGMA foreign_key_check').length !== 0) throw new Error('Fresh workspace references are invalid');
    connection.exec('COMMIT');
    return { databaseGuid, repositoryId, branchRef: repository.branchRef, protectedSnapshotId: snapshot.snapshotId,
      catalogId, collections, baselineSource: initial !== null ? 'initial-rules-json' : bootstrap ? 'manual-guidance' : 'published-catalog', readyForAnalysis: true, readyForUi: false };
  } catch (error) {
    if (connection.isTransaction) connection.exec('ROLLBACK');
    throw new Error(`Native creation failed during ${phase}: ${error.message}`, { cause: error });
  }
}
