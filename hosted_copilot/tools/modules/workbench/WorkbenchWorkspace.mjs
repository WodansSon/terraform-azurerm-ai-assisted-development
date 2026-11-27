import { requireSourceObject } from './WorkbenchSourceRecords.mjs';
import { readProtectedSnapshot } from './WorkbenchProtectedSnapshots.mjs';
import { readWorkspaceLlmAssignments } from './WorkbenchLlmAssignments.mjs';

const guidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

function positiveIdentity(value, label) {
  if (!Number.isSafeInteger(value) || value < 1) throw new Error(`${label} must be a positive safe integer`);
}

// Require a canonical database/repository binding and only the additional fields declared by the selected operation.
function validateBinding(request, extraFields = []) {
  const fields = ['databaseGuid', 'repositoryId', ...extraFields];
  requireSourceObject(request, fields, fields, 'Bound workspace request');
  if (typeof request.databaseGuid !== 'string' || !guidPattern.test(request.databaseGuid)) throw new Error('Workspace identity requires a canonical database GUID');
  positiveIdentity(request.repositoryId, 'Bound repository identity');
}

// Keep workspace lineage immutable while allowing a repository-scoped protected snapshot head to advance.
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

// Resolve capacity only after matching the selected database, repository, and branch to the workspace origin.
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

// Read one consistent policy snapshot and reject missing, overlapping, unsafe, or overallocated guidance mappings.
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

// Prefer finalized publication over staging; an invalid selected publication must not silently fall back.
export function readWorkingCatalogId(connection) {
  const selected = connection.get(`SELECT current_catalog_id AS id FROM workspace_publication WHERE workspace_id = 1`)
    ?? connection.get('SELECT current_catalog_id AS id FROM workspace_staging WHERE workspace_id = 1');
  if (selected && !connection.get('SELECT id FROM catalog_versions WHERE id = ? AND finalized_at IS NOT NULL', [selected.id])) {
    throw new Error('Working catalog must identify a finalized published or staged baseline');
  }
  return selected?.id ?? null;
}

// Project one consistent SQL snapshot for the UI, keeping current inputs, historical analysis, proposals, and publication distinct.
export function readNativeWorkspaceView(connection, request) {
  requireSourceObject(request, ['binding'], ['binding'], 'Native workspace view');
  const ownsTransaction = !connection.isTransaction;
  if (ownsTransaction) connection.exec('BEGIN');
  try {
    const capacity = readSelectedCapacityConfiguration(connection, request.binding);
    const values = (sql, parameters, field = 'code') => connection.all(sql, parameters).map(row => row[field]);
    const scorecard = scorecardId => ({ ...connection.get(`SELECT policy_id AS policyId, selection_rationale AS rationale
      FROM scorecards WHERE id = ?`, [scorecardId]),
    factors: connection.all(`SELECT factor.code, value.value, factor.label, factor.description, factor.weight,
      factor.contribution_kind AS contributionKind, factor.minimum_value AS minimumValue, factor.maximum_value AS maximumValue
      FROM scorecard_values value JOIN scoring_factors factor ON factor.id = value.factor_id
      WHERE value.scorecard_id = ? ORDER BY factor.id`, [scorecardId]).map(row => ({ ...row })) });
    const currentCollections = connection.all(`SELECT definition_id AS definitionId, collection_id AS collectionId
      FROM source_collection_heads ORDER BY definition_id`).map(row => ({ ...row }));
    const runs = connection.all(`SELECT id AS runId, outcome, requested_at AS requestedAt, completed_at AS completedAt
      FROM analysis_runs ORDER BY id`).map(row => ({ ...row }));
    const head = connection.get(`SELECT run.id AS runId, run.outcome, context.base_catalog_id AS catalogId,
      context.protected_snapshot_id AS protectedSnapshotId, context.capacity_policy_id AS capacityPolicyId
      FROM workspace_analysis_head head JOIN analysis_runs run ON run.id = head.run_id
      JOIN analysis_run_contexts context ON context.run_id = run.id WHERE head.workspace_id = 1 AND context.workspace_id = 1`);
    if (connection.get('SELECT run_id FROM workspace_analysis_head WHERE workspace_id = 1') && head?.outcome !== 'complete') {
      throw new Error('Current analysis head must reference a completed workspace analysis');
    }
    const runId = head?.runId ?? null;
    const selectedCollections = head ? connection.all(`SELECT collection.definition_id AS definitionId, used.collection_id AS collectionId
      FROM run_collections used JOIN source_collections collection ON collection.id = used.collection_id
      WHERE used.run_id = ? ORDER BY collection.definition_id`, [runId]).map(row => ({ ...row })) : currentCollections;
    const readCatalog = catalogId => {
      const publication = connection.get(`SELECT catalog.id AS catalogId, catalog.revision, catalog.parent_catalog_id AS parentCatalogId,
      catalog.protected_snapshot_id AS protectedSnapshotId, catalog.content_fingerprint AS contentSha256, catalog.capture_kind AS captureKind,
      catalog.last_semantic_review AS lastSemanticReview, catalog.finalized_at AS finalizedAt,
      catalog.default_requirement_level AS requirementLevel, catalog.default_enforcement_method AS enforcementMethod,
      catalog.default_documentation_gap AS documentationGap, repository.canonical_name AS upstreamRepository,
      catalog.upstream_baseline_commit AS upstreamBaselineCommit, catalog.upstream_current_ref AS upstreamCurrentRef
      FROM catalog_versions catalog LEFT JOIN repositories repository ON repository.id = catalog.upstream_repository_id WHERE catalog.id = ?`, [catalogId]);
      if (!publication || publication.finalizedAt === null) throw new Error('Referenced catalog must be finalized before readback');
      return {
      ...publication, documentationGap: Boolean(publication.documentationGap),
      guidanceFiles: connection.all(`SELECT file.relative_path AS relativePath, file.role_code AS role, surface.code AS surface,
        file.content_sha256 AS contentSha256, file.content FROM catalog_guidance_files file LEFT JOIN guidance_surfaces surface ON surface.id = file.surface_id
        WHERE file.catalog_id = ? ORDER BY CASE file.role_code WHEN 'instructions' THEN 0 WHEN 'repository' THEN 1 ELSE 2 END, surface.id`, [catalogId]).map(file => {
        const { surface, ...capture } = file;
        return surface === null ? capture : { ...capture, surface,
          patterns: values('SELECT pattern AS code FROM surface_patterns WHERE surface_id = (SELECT id FROM guidance_surfaces WHERE code = ?) ORDER BY pattern', [surface]) };
      }),
      sources: connection.all('SELECT code, title, raw_url AS rawUrl, reference_url AS referenceUrl, baseline_sha256 AS baselineSha256 FROM catalog_sources WHERE catalog_id = ? ORDER BY ordinal', [publication.catalogId]).map(row => ({ ...row })),
      evidence: connection.all('SELECT code, evidence_kind AS kind, description, reference FROM catalog_evidence WHERE catalog_id = ? ORDER BY ordinal', [publication.catalogId]).map(row => ({ ...row })),
      surfaces: connection.all(`SELECT surface.id AS surfaceId, surface.code, surface.output_relative_path AS outputPath,
        content.description, content.title, content.introduction, content.closing_text AS closing
        FROM catalog_surface_content content JOIN guidance_surfaces surface ON surface.id = content.surface_id
        WHERE content.catalog_id = ? ORDER BY surface.id`, [publication.catalogId]).map(surface => ({ ...surface,
        sections: connection.all('SELECT heading FROM catalog_surface_sections WHERE catalog_id = ? AND surface_id = ? ORDER BY ordinal', [publication.catalogId, surface.surfaceId]).map(row => row.heading) })),
      rules: connection.all(`SELECT rule.id AS ruleId, rule.displayed_id AS displayedId, version.id AS ruleVersionId,
        version.revision, version.lifecycle, version.origin_code AS origin, version.documentation_gap AS documentationGap,
        version.retirement_reason AS retirementReason, wording.id AS wordingVersionId, wording.text AS wording
        FROM catalog_members member JOIN rules rule ON rule.id = member.rule_id JOIN rule_versions version ON version.id = member.rule_version_id
        JOIN wording_versions wording ON wording.id = version.wording_version_id WHERE member.catalog_id = ? ORDER BY rule.id`, [publication.catalogId]).map(rule => ({ ...rule,
        documentationGap: rule.documentationGap === null ? null : Boolean(rule.documentationGap),
        provenances: values('SELECT code FROM rule_provenances WHERE rule_version_id = ? ORDER BY ordinal', [rule.ruleVersionId]),
        sourceCodes: values('SELECT source_code AS code FROM catalog_member_sources WHERE catalog_id = ? AND rule_id = ? ORDER BY ordinal', [publication.catalogId, rule.ruleId]),
        evidenceCodes: values('SELECT evidence_code AS code FROM catalog_member_evidence WHERE catalog_id = ? AND rule_id = ? ORDER BY ordinal', [publication.catalogId, rule.ruleId]),
        applicabilities: values(`SELECT definition.code FROM rule_applicabilities member JOIN applicability_definitions definition ON definition.id = member.applicability_id
          WHERE member.rule_version_id = ? ORDER BY definition.id`, [rule.ruleVersionId]),
        placements: connection.all(`SELECT surface.code AS surface, placement.section_heading AS sectionHeading, placement.display_order AS ordinal
          FROM rule_placements placement JOIN guidance_surfaces surface ON surface.id = placement.surface_id
          WHERE placement.rule_version_id = ? ORDER BY surface.id, placement.display_order`, [rule.ruleVersionId]).map(row => ({ ...row })),
        canonicalSource: connection.get(`SELECT source.id AS sourceRuleId, definition.code AS sourceDefinitionId, source.external_key AS sourceId, binding.assessment_local_key AS localResultKey
          FROM catalog_canonical_bindings binding JOIN source_rules source ON source.id = binding.source_rule_id
          JOIN source_definitions definition ON definition.id = source.definition_id WHERE binding.catalog_id = ? AND binding.rule_id = ?`, [publication.catalogId, rule.ruleId]) ?? null,
      })),
      protectedRules: connection.all(`SELECT version.id AS ruleVersionId, rule.displayed_id AS displayedId, wording.text AS wording,
        detail.title, detail.protection_reason AS protectionReason, surface.code AS surface
        FROM protected_members member JOIN rule_versions version ON version.id = member.rule_version_id JOIN rules rule ON rule.id = version.rule_id
        JOIN wording_versions wording ON wording.id = version.wording_version_id JOIN protected_rule_details detail ON detail.rule_version_id = version.id
        JOIN guidance_surfaces surface ON surface.id = detail.surface_id WHERE member.snapshot_id = ? ORDER BY rule.id`, [publication.protectedSnapshotId]).map(row => ({ ...row })),
      };
    };
    const publishedId = connection.get('SELECT current_catalog_id AS id FROM workspace_publication WHERE workspace_id = 1')?.id ?? null;
    const publishedCatalog = publishedId === null ? null : readCatalog(publishedId);
    const stagedId = connection.get('SELECT current_catalog_id AS id FROM workspace_staging WHERE workspace_id = 1')?.id ?? null;
    const stagedCatalog = stagedId === null ? null : readCatalog(stagedId);
    const workingId = readWorkingCatalogId(connection);
    const analysisCatalog = head && head.catalogId !== null && head.catalogId !== publishedId ? readCatalog(head.catalogId) : null;
    const protectedSnapshot = readCurrentProtectedSnapshot(connection, {
      databaseGuid: request.binding.databaseGuid, repositoryId: request.binding.repositoryId });
    const currentProtectedSnapshot = protectedSnapshot === null ? null : {
      ...protectedSnapshot,
      rules: readProtectedSnapshot(connection, protectedSnapshot.snapshotId).blocks.map(block => ({
        displayedId: block.id, ruleVersionId: block.ruleVersionId, title: block.title, surface: block.surfaceCode,
        wording: block.text, provenance: block.provenance, protectionReason: block.protectionReason,
        sourcePath: block.relativePath, contentSha256: block.contentSha256,
      })),
    };
    const sources = selectedCollections.flatMap(collection => connection.all(`SELECT member.source_rule_id AS sourceRuleId,
      member.source_version_id AS sourceVersionId, member.observation_id AS observationId, member.collection_id AS collectionId,
      definition.id AS definitionId, definition.code AS sourceDefinitionId, definition.lane_id AS laneId, rule.external_key AS sourceId,
      member.presence, member.removed_at AS removedAt, version.captured_text AS content, version.content_sha256 AS contentSha256,
      observation.title, observation.captured_location AS location, observation.source_lifecycle AS lifecycle,
      observation.metadata_sha256 AS metadataSha256, observation.rule_text AS ruleText, observation.rationale,
      observation.lifecycle_reason AS lifecycleReason, observation.deprecated_on AS deprecatedOn, observation.retired_on AS retiredOn,
      observation.contract_path AS contractPath, observation.origin_repository AS originRepository, collection.configured_ref AS originRef,
      observation.origin_commit AS originCommit, observation.origin_reference_url AS originReferenceUrl
      FROM source_collection_members member JOIN source_rules rule ON rule.id = member.source_rule_id
      JOIN source_collections collection ON collection.id = member.collection_id
      JOIN source_definitions definition ON definition.id = member.definition_id JOIN source_versions version ON version.id = member.source_version_id
      JOIN source_observations observation ON observation.id = member.observation_id WHERE member.collection_id = ? ORDER BY member.ordinal`, [collection.collectionId]).map(source => ({ ...source,
      provenances: values('SELECT code FROM source_observation_provenance WHERE observation_id = ? ORDER BY ordinal', [source.observationId]),
      evidence: values('SELECT evidence_text AS text FROM source_observation_evidence WHERE observation_id = ? ORDER BY ordinal', [source.observationId], 'text'),
      references: values('SELECT external_key AS code FROM source_observation_references WHERE observation_id = ? ORDER BY ordinal', [source.observationId]),
      applicabilities: values(`SELECT definition.code FROM source_observation_applicabilities member
        JOIN applicability_definitions definition ON definition.id = member.applicability_id WHERE member.observation_id = ? ORDER BY member.ordinal`, [source.observationId]),
      replacements: values(`SELECT source.external_key AS code FROM source_observation_replacements member
        JOIN source_rules source ON source.id = member.replacement_rule_id WHERE member.observation_id = ? ORDER BY member.ordinal`, [source.observationId]),
    })));
    const readAssessments = assessmentRunId => connection.all(`SELECT result.id AS assessmentResultId, result.evaluation_id AS evaluationId,
      result.source_version_id AS sourceVersionId, result.local_result_key AS localResultKey, result.title, result.source_meaning AS sourceMeaning,
      result.impact_description AS impactDescription, result.hosted_applicable AS hostedApplicable, result.applicability_rationale AS applicabilityRationale,
      result.confidence_level AS confidenceLevel, result.confidence_rationale AS confidenceRationale, result.existing_coverage_score AS existingCoverageScore,
      result.existing_coverage_rationale AS existingCoverageRationale, result.scorecard_id AS scorecardId
      FROM assessment_results result JOIN evaluations evaluation ON evaluation.id = result.evaluation_id JOIN run_evaluations used ON used.evaluation_id = evaluation.id
      WHERE used.run_id = ? AND evaluation.outcome = 'complete' ORDER BY result.id`, [assessmentRunId]).map(result => ({ ...result,
      hostedApplicable: Boolean(result.hostedApplicable), scorecard: scorecard(result.scorecardId),
      uncertainties: values('SELECT description FROM assessment_uncertainties WHERE assessment_id = ? ORDER BY ordinal', [result.assessmentResultId], 'description'),
      categories: values('SELECT proposed_code AS code FROM assessment_category_proposals WHERE assessment_id = ? ORDER BY ordinal', [result.assessmentResultId]),
    }));
    const assessments = readAssessments(runId);
    const assessmentRun = runs.at(-1) ?? null;
    const currentSourceVersions = new Set(sources.map(source => source.sourceVersionId));
    const assessmentResults = (assessmentRun?.runId === runId ? assessments : readAssessments(assessmentRun?.runId ?? null))
      .filter(result => currentSourceVersions.has(result.sourceVersionId));
    const groups = connection.all(`SELECT grouped.id AS groupVersionId, grouped.group_id AS groupId, grouped.revision,
      grouped.synthesis_evaluation_id AS evaluationId, grouped.title, grouped.semantic_summary AS semanticSummary,
      grouped.synthesis_rationale AS synthesisRationale, grouped.review_state AS reviewState, grouped.needs_review AS needsReview,
      grouped.scorecard_id AS scorecardId, wording.id AS wordingVersionId, wording.text AS suggestedWording
      FROM group_versions grouped JOIN evaluations evaluation ON evaluation.id = grouped.synthesis_evaluation_id
      JOIN run_evaluations used ON used.evaluation_id = evaluation.id JOIN wording_versions wording ON wording.id = grouped.suggested_wording_id
      WHERE used.run_id = ? AND evaluation.outcome = 'complete' ORDER BY grouped.id`, [runId]).map(group => ({ ...group,
      needsReview: Boolean(group.needsReview), scorecard: scorecard(group.scorecardId),
      members: connection.all('SELECT assessment_result_id AS assessmentResultId, member_role AS role, meaning_coverage_rationale AS coverageRationale FROM group_members WHERE group_version_id = ? ORDER BY assessment_result_id', [group.groupVersionId]).map(row => ({ ...row })),
      operations: connection.all(`SELECT operation.id AS operationId, operation.operation_role AS role, action.code AS action,
        operation.target_rule_version_id AS targetRuleVersionId, wording.text AS suggestedWording, surface.code AS surface,
        operation.section_heading AS sectionHeading, operation.rationale FROM recommended_changes operation JOIN action_definitions action ON action.id = operation.action_id
        LEFT JOIN wording_versions wording ON wording.id = operation.wording_version_id LEFT JOIN guidance_surfaces surface ON surface.id = operation.surface_id
        WHERE operation.group_version_id = ? ORDER BY operation.ordinal`, [group.groupVersionId]).map(operation => ({ ...operation,
        provenances: values('SELECT code FROM recommended_change_provenances WHERE recommended_change_id = ? ORDER BY ordinal', [operation.operationId]),
        evidenceCodes: values('SELECT evidence_code AS code FROM recommended_change_evidence WHERE recommended_change_id = ? ORDER BY ordinal', [operation.operationId]),
        applicabilities: values(`SELECT definition.code FROM recommended_change_applicabilities member JOIN applicability_definitions definition ON definition.id = member.applicability_id
          WHERE member.recommended_change_id = ? ORDER BY definition.id`, [operation.operationId]),
      })),
      catalogAnchors: connection.all('SELECT rule_version_id AS ruleVersionId, relationship_code AS relationship, rationale FROM group_catalog_anchors WHERE group_version_id = ? ORDER BY rule_version_id', [group.groupVersionId]).map(row => ({ ...row })),
    }));
    const findings = connection.all(`SELECT finding.id AS findingId, finding.evaluation_id AS evaluationId, finding.finding_kind AS kind, finding.title, finding.rationale
      FROM findings finding JOIN evaluations evaluation ON evaluation.id = finding.evaluation_id JOIN run_evaluations used ON used.evaluation_id = evaluation.id
      WHERE used.run_id = ? AND evaluation.outcome = 'complete' ORDER BY finding.id`, [runId]).map(finding => ({ ...finding,
      participants: connection.all(`SELECT participant_role AS role, assessment_result_id AS assessmentResultId, group_version_id AS groupVersionId,
        rule_version_id AS ruleVersionId, review_subject_id AS reviewSubjectId, evidence_quote AS evidenceQuote
        FROM finding_participants WHERE finding_id = ? ORDER BY ordinal`, [finding.findingId]).map(row => ({ ...row })),
      issues: connection.all(`SELECT issue.id AS issueId, issue.display_key AS displayKey, issue.title, link.correspondence_rationale AS correspondenceRationale
        FROM issue_findings link JOIN issues issue ON issue.id = link.issue_id WHERE link.finding_id = ? ORDER BY issue.id`, [finding.findingId]).map(row => ({ ...row })),
    }));
    const result = {
      guidanceCapacity: capacity,
      analysis: { status: head ? 'complete' : runs.length ? 'incomplete' : 'not-started', runId, runs,
        catalogId: head?.catalogId ?? null, protectedSnapshotId: head?.protectedSnapshotId ?? null,
        sourcesMatchCurrent: head ? JSON.stringify(selectedCollections) === JSON.stringify(currentCollections) : null,
        catalogMatchesCurrent: head ? head.catalogId === workingId : null,
        protectionMatchesCurrent: head ? head.protectedSnapshotId === (protectedSnapshot?.snapshotId ?? null) : null,
        capacityMatchesCurrent: head ? head.capacityPolicyId === capacity.policy.policyId : null },
      sourceCollections: selectedCollections, currentSourceCollections: currentCollections,
      sourceLanes: connection.all('SELECT id AS laneId, code, label, display_order AS displayOrder FROM source_lanes ORDER BY display_order, id').map(row => ({ ...row })),
      publishedCatalog, stagedCatalog, workingCatalog: publishedCatalog ?? stagedCatalog, analysisCatalog, currentProtectedSnapshot, sources, assessments, groups, findings,
      assessmentResults,
      llmAssignments: readWorkspaceLlmAssignments(connection, request.binding).map(assignment => ({
        taskCode: assignment.taskCode, model: assignment.model, providerCode: assignment.providerCode,
        adapterCode: assignment.adapterCode, reasoningEffort: assignment.reasoningEffort,
      })),
      assessmentContext: { runId: assessmentRun?.runId ?? null, outcome: assessmentRun?.outcome ?? 'not-started',
        adopted: assessmentRun !== null && assessmentRun.runId === runId },
      phaseEvaluations: connection.all(`SELECT evaluation.id AS evaluationId, profile.task_code AS taskCode, evaluation.outcome
        FROM run_evaluations used JOIN evaluations evaluation ON evaluation.id = used.evaluation_id
        JOIN evaluator_profiles profile ON profile.id = evaluation.evaluator_profile_id
        WHERE used.run_id = ? ORDER BY evaluation.id`, [assessmentRun?.runId ?? null]).map(evaluation => ({ ...evaluation })),
      relationshipReviews: connection.all(`SELECT review.id AS reviewId, review.base_catalog_id AS catalogId,
        review.protected_snapshot_id AS protectedSnapshotId, review.plan_version_id AS planVersionId,
        review.scope_code AS scopeCode, evaluation.outcome, evaluation.completed_at AS completedAt
        FROM relationship_reviews review JOIN evaluations evaluation ON evaluation.id = review.evaluation_id ORDER BY review.id`).map(review => ({ ...review,
        subjects: connection.all(`SELECT subject.change_revision_id AS revisionId, subject.subject_role AS role,
          proposal.origin_source_version_id AS sourceVersionId, source.source_rule_id AS sourceRuleId, wording.text AS wording
          FROM review_subjects subject JOIN wording_versions wording ON wording.id = subject.wording_version_id
          LEFT JOIN change_revisions revision ON revision.id = subject.change_revision_id
          LEFT JOIN proposal_versions proposal ON proposal.id = revision.proposal_version_id
          LEFT JOIN source_versions source ON source.id = proposal.origin_source_version_id
          WHERE subject.review_id = ? ORDER BY subject.id`, [review.reviewId]).map(subject => ({ ...subject })),
        findings: connection.all('SELECT id AS findingId, title, rationale FROM findings WHERE review_id = ? ORDER BY id', [review.reviewId]).map(finding => ({ ...finding })),
      })),
      guidanceSurfaces: connection.all('SELECT id AS surfaceId, code, label FROM guidance_surfaces ORDER BY id').map(surface => ({ ...surface })),
      changes: connection.all(`SELECT change.id AS changeId, revision.id AS revisionId, revision.revision, action.code AS action,
        revision.baseline_rule_version_id AS targetRuleVersionId,
        proposal.origin_source_version_id AS sourceVersionId, wording.text AS wording, revision.rationale, revision.recorded_at AS savedAt
        FROM changes change JOIN change_revisions revision ON revision.id = change.current_revision_id
        JOIN proposal_versions proposal ON proposal.id = revision.proposal_version_id
        JOIN wording_versions wording ON wording.id = revision.wording_version_id LEFT JOIN action_definitions action ON action.id = revision.selected_action_id ORDER BY change.id`).map(row => ({ ...row,
        placements: connection.all(`SELECT surface.code AS surface, placement.section_heading AS sectionHeading FROM change_placements placement
          JOIN guidance_surfaces surface ON surface.id = placement.surface_id WHERE placement.change_revision_id = ? ORDER BY surface.id`, [row.revisionId]).map(placement => ({ ...placement })),
      })),
      plans: connection.all(`SELECT plan.id AS planId, plan.label, plan.current_version_id AS versionId, version.base_catalog_id AS catalogId
        FROM plans plan LEFT JOIN plan_versions version ON version.id = plan.current_version_id ORDER BY plan.id`).map(plan => ({ ...plan,
        items: connection.all(`SELECT member.id AS membershipId, member.change_id AS changeId, revision.id AS revisionId,
          source.external_key AS sourceId, definition.code AS sourceDefinitionId, action.code AS action, wording.text AS wording,
          change.current_revision_id <> revision.id AS needsReview
          FROM plan_items item JOIN plan_memberships member ON member.id = item.membership_id JOIN change_revisions revision ON revision.id = item.change_revision_id
          JOIN changes change ON change.id = member.change_id JOIN proposal_versions proposal ON proposal.id = revision.proposal_version_id
          JOIN source_versions version ON version.id = proposal.origin_source_version_id JOIN source_rules source ON source.id = version.source_rule_id
          JOIN source_definitions definition ON definition.id = source.definition_id LEFT JOIN action_definitions action ON action.id = revision.selected_action_id
          JOIN wording_versions wording ON wording.id = revision.wording_version_id WHERE item.plan_version_id = ? ORDER BY member.id`, [plan.versionId]).map(item => ({ ...item, needsReview: Boolean(item.needsReview) })),
      })),
      dispositions: connection.all('SELECT assessment_result_id AS assessmentResultId, disposition_code AS code, rationale FROM reconciliation_dispositions WHERE run_id = ? ORDER BY assessment_result_id', [runId]).map(row => ({ ...row })),
    };
    if (ownsTransaction) connection.exec('COMMIT');
    return result;
  } catch (error) {
    if (ownsTransaction && connection.isTransaction) {
      try { connection.exec('ROLLBACK'); }
      catch (rollbackError) { throw new AggregateError([error, rollbackError], 'Workspace readback and rollback failed'); }
    }
    throw error;
  }
}

// Require complete analysis whose source, catalog, protection, capacity, and model authorities match current workspace state.
export function readNativeWorkspaceReadiness(connection, request) {
  const ownsTransaction = !connection.isTransaction;
  if (ownsTransaction) connection.exec('BEGIN');
  try {
    const view = readNativeWorkspaceView(connection, request);
    const definitions = connection.all('SELECT id FROM source_definitions ORDER BY id');
    const collections = new Set(view.currentSourceCollections.map(collection => collection.definitionId));
    const assignments = readWorkspaceLlmAssignments(connection, request.binding);
    const pinnedAssignments = connection.all('SELECT task_code AS taskCode, assignment_id AS assignmentId FROM analysis_run_llm_assignments WHERE run_id = ?', [view.analysis.runId]);
    const requirements = [
      ['catalog-baseline', view.publishedCatalog !== null || view.stagedCatalog !== null, 'A finalized published catalog or initial staged baseline is required'],
      ['source-collections', definitions.length > 0 && definitions.every(definition => collections.has(definition.id)), 'Every configured source definition requires a current collection'],
      ['protected-snapshot', view.currentProtectedSnapshot !== null, 'A current protected snapshot is required'],
      ['completed-analysis', view.analysis.status === 'complete', 'Native assessment and downstream analysis must be complete'],
      ['assessment-readback', view.assessmentContext.adopted && view.assessmentContext.outcome === 'complete', 'Assessment results must belong to the completed analysis head'],
      ['current-sources', view.analysis.sourcesMatchCurrent === true, 'Analysis must use the current source collections'],
      ['current-catalog', view.analysis.catalogMatchesCurrent === true, 'Analysis must use the selected working catalog'],
      ['current-protection', view.analysis.protectionMatchesCurrent === true, 'Analysis must use the current protected snapshot'],
      ['current-capacity', view.analysis.capacityMatchesCurrent === true, 'Analysis must use the current capacity policy'],
      ['current-model-assignments', pinnedAssignments.length === assignments.length && assignments.every(assignment =>
        pinnedAssignments.some(pinned => pinned.taskCode === assignment.taskCode && pinned.assignmentId === assignment.assignmentId)), 'Analysis must use the current database task/model assignments'],
    ];
    const checks = requirements.map(([name, passed, detail]) => ({ name, status: passed ? 'passed' : 'failed', detail }));
    const result = { ready: checks.every(check => check.status === 'passed'), checks, llmAssignments: view.llmAssignments };
    if (ownsTransaction) connection.exec('COMMIT');
    return result;
  } catch (error) {
    if (ownsTransaction && connection.isTransaction) connection.exec('ROLLBACK');
    throw error;
  }
}

// Resolve the current protection reference only within the explicitly bound database and repository.
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

// Compare-and-swap the protection head so a stale refresh cannot overwrite a newer repository-scoped capture.
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
