import { requireSourceObject, requireSourceHash, requireSourceText, sourceTextHash } from './WorkbenchSourceRecords.mjs';
import { readSelectedCapacityConfiguration } from './WorkbenchWorkspace.mjs';
import { readWorkspaceLlmAssignments } from './WorkbenchLlmAssignments.mjs';

function transaction(connection, operation) {
  if (connection.isTransaction) throw new Error('Evaluation commands require their own short transaction');
  connection.exec('BEGIN IMMEDIATE');
  try {
    const result = operation();
    connection.exec('COMMIT');
    return result;
  } catch (error) {
    if (connection.isTransaction) connection.exec('ROLLBACK');
    throw error;
  }
}

function identity(value, label) {
  if (!Number.isSafeInteger(value) || value < 1) throw new Error(`${label} must be a positive safe integer`);
}

export { transaction as withEvaluationTransaction };

export function beginAnalysisRun(connection, request) {
  const fields = ['binding', 'actorId', 'scoringPolicyId', 'force', 'llmAssignmentIds'];
  requireSourceObject(request, fields, fields, 'Analysis run');
  const capacity = readSelectedCapacityConfiguration(connection, request.binding);
  identity(request.actorId, 'Analysis actor');
  identity(request.scoringPolicyId, 'Scoring policy');
  if (typeof request.force !== 'boolean') throw new Error('Analysis force must be explicit');
  return transaction(connection, () => {
    const workspace = connection.get('SELECT current_protected_snapshot_id, team_profile_id FROM workspace_identity WHERE id = 1');
    if (workspace.current_protected_snapshot_id === null) throw new Error('Analysis requires a validated current protected capture');
    const llms = readWorkspaceLlmAssignments(connection, request.binding);
    if (!Array.isArray(request.llmAssignmentIds) || request.llmAssignmentIds.length !== llms.length ||
      new Set(request.llmAssignmentIds).size !== llms.length || llms.some(assignment => !request.llmAssignmentIds.includes(assignment.assignmentId))) {
      throw new Error('Master-profile LLM assignments changed after availability validation');
    }
    const collections = connection.all(`SELECT head.collection_id FROM source_collection_heads head
      JOIN source_collections collection ON collection.id = head.collection_id WHERE collection.outcome = 'complete' ORDER BY head.definition_id`);
    if (collections.length === 0 || collections.length !== connection.get('SELECT count(*) AS count FROM source_definitions').count) {
      throw new Error('Analysis requires complete captured sources for every registered definition');
    }
    const runId = Number(connection.run(`INSERT INTO analysis_runs(requested_by_actor_id, requested_at, force_requested, outcome)
      VALUES (?, ?, ?, 'running')`, [request.actorId, new Date().toISOString(), Number(request.force)]).lastInsertRowid);
    const catalog = connection.get('SELECT current_catalog_id FROM workspace_publication WHERE workspace_id = 1');
    connection.run('INSERT INTO analysis_run_contexts VALUES (?, 1, ?, ?, ?, ?, ?)',
      [runId, workspace.current_protected_snapshot_id, catalog?.current_catalog_id ?? null, request.scoringPolicyId, capacity.policy.policyId, workspace.team_profile_id]);
    for (const assignment of llms) connection.run('INSERT INTO analysis_run_llm_assignments VALUES (?, ?, ?, ?)',
      [runId, workspace.team_profile_id, assignment.taskCode, assignment.assignmentId]);
    for (const collection of collections) connection.run('INSERT INTO run_collections VALUES (?, ?)', [runId, collection.collection_id]);
    return { runId, protectedSnapshotId: workspace.current_protected_snapshot_id, collectionIds: collections.map(collection => collection.collection_id) };
  });
}

export function registerEvaluatorProfile(connection, profile) {
  const fields = ['code', 'taskCode', 'llmAssignmentId', 'promptSha256', 'behaviorSha256', 'resultContractSha256'];
  requireSourceObject(profile, fields, fields, 'Evaluator profile');
  for (const field of ['code', 'taskCode']) requireSourceText(profile[field], field);
  identity(profile.llmAssignmentId, 'LLM assignment');
  for (const field of ['promptSha256', 'behaviorSha256', 'resultContractSha256']) requireSourceHash(profile[field], field);
  return transaction(connection, () => {
    const existing = connection.get(`SELECT id FROM evaluator_profiles WHERE code = ? AND task_code = ? AND llm_assignment_id = ?
      AND prompt_sha256 = ? AND behavior_sha256 = ? AND result_contract_sha256 = ?`, fields.map(field => profile[field]));
    if (existing) return existing.id;
    const revision = connection.get('SELECT coalesce(max(revision), 0) + 1 AS revision FROM evaluator_profiles WHERE code = ?', [profile.code]).revision;
    return Number(connection.run(`INSERT INTO evaluator_profiles(code, revision, task_code, llm_assignment_id,
      prompt_sha256, behavior_sha256, result_contract_sha256) VALUES (?, ?, ?, ?, ?, ?, ?)`,
    [profile.code, revision, ...fields.slice(1).map(field => profile[field])]).lastInsertRowid);
  });
}

export function prepareEvaluationInput(connection, request) {
  const fields = ['binding', 'runId', 'profileId', 'sourceVersionIds'];
  requireSourceObject(request, [...fields, 'assessmentResultIds', 'reconciliationPhase', 'componentIds'], fields, 'Evaluation request');
  readSelectedCapacityConfiguration(connection, request.binding);
  for (const field of ['runId', 'profileId']) identity(request[field], field);
  if (!Array.isArray(request.sourceVersionIds) || request.sourceVersionIds.length === 0 || new Set(request.sourceVersionIds).size !== request.sourceVersionIds.length) {
    throw new Error('Evaluation requires a unique nonempty captured source set');
  }
  request.sourceVersionIds.forEach(value => identity(value, 'Source version'));
    const context = connection.get(`SELECT context.*, run.outcome FROM analysis_run_contexts context
      JOIN analysis_runs run ON run.id = context.run_id WHERE context.run_id = ?`, [request.runId]);
    if (!context || context.outcome !== 'running') throw new Error('Evaluation requires an active analysis run context');
    const profile = connection.get('SELECT * FROM evaluator_profiles WHERE id = ?', [request.profileId]);
    if (!profile) throw new Error('Evaluator profile is not registered');
    if (!connection.get('SELECT assignment_id FROM analysis_run_llm_assignments WHERE run_id = ? AND task_code = ? AND assignment_id = ?',
      [request.runId, profile.task_code, profile.llm_assignment_id])) throw new Error('Evaluator LLM assignment does not belong to the pinned master-profile run');
    const sources = request.sourceVersionIds.map(versionId => {
      const source = connection.get(`SELECT version.id AS sourceVersionId, member.observation_id AS observationId,
        definition.code AS sourceDefinitionId, rule.external_key AS sourceId, version.content_sha256 AS contentSha256,
        version.captured_text AS content, observation.title, observation.source_lifecycle AS lifecycle,
        observation.metadata_sha256 AS metadataSha256, observation.captured_location AS location,
        configuration.assessment_cardinality AS assessmentCardinality
        FROM run_collections captured JOIN source_collection_members member ON member.collection_id = captured.collection_id
        JOIN source_versions version ON version.id = member.source_version_id
        JOIN source_rules rule ON rule.id = member.source_rule_id JOIN source_definitions definition ON definition.id = member.definition_id
        JOIN source_collections collection ON collection.id = captured.collection_id
        JOIN source_definition_versions configuration ON configuration.id = collection.definition_version_id
        JOIN source_observations observation ON observation.id = member.observation_id
        WHERE captured.run_id = ? AND version.id = ? AND member.presence = 'present'`, [request.runId, versionId]);
      if (!source) throw new Error('Evaluation source does not belong to the pinned run capture');
      return { ...source };
    });
    const categories = connection.all(`SELECT surface.code, content.description FROM guidance_surfaces surface
      JOIN guidance_surface_content content ON content.surface_id = surface.id ORDER BY surface.id`).map(row => ({ ...row }));
    const protectedRules = connection.all(`SELECT rule.displayed_id AS id, wording.text, detail.title, surface.code AS category
      FROM protected_members member JOIN rule_versions version ON version.id = member.rule_version_id
      JOIN rules rule ON rule.id = version.rule_id JOIN wording_versions wording ON wording.id = version.wording_version_id
      JOIN protected_rule_details detail ON detail.rule_version_id = version.id JOIN guidance_surfaces surface ON surface.id = detail.surface_id
      WHERE member.snapshot_id = ? ORDER BY rule.displayed_id`, [context.protected_snapshot_id]).map(row => ({ ...row }));
    const input = { stage: profile.task_code, sources, categories, protectedRules, protectedSnapshotId: context.protected_snapshot_id,
      baseCatalogId: context.base_catalog_id, scoringPolicyId: context.scoring_policy_id, capacityPolicyId: context.capacity_policy_id };
    if (profile.task_code === 'reconciliation') {
      if (!['routing', 'consolidation', 'synthesis'].includes(request.reconciliationPhase) || !Array.isArray(request.assessmentResultIds) ||
        request.assessmentResultIds.length === 0 || new Set(request.assessmentResultIds).size !== request.assessmentResultIds.length) {
        throw new Error('Reconciliation requires its phase and unique completed assessment inputs');
      }
      const sourceProfiles = connection.all(`SELECT DISTINCT evaluation.evaluator_profile_id AS id FROM run_evaluations used
        JOIN evaluations evaluation ON evaluation.id = used.evaluation_id JOIN evaluator_profiles source_profile ON source_profile.id = evaluation.evaluator_profile_id
        WHERE used.run_id = ? AND source_profile.task_code = 'assessment'`, [request.runId]);
      if (sourceProfiles.length !== 1) throw new Error('Reconciliation requires one pinned source-assessment identity');
      const recovery = readAssessmentRecoveryPlan(connection, { binding: request.binding, runId: request.runId, profileId: sourceProfiles[0].id });
      if (recovery.remainingSourceVersionIds.length !== 0 || recovery.unfinishedEvaluationIds.length !== 0) {
        throw new Error('Reconciliation requires complete committed source assessment coverage');
      }
      input.phase = request.reconciliationPhase;
      input.actions = connection.all('SELECT code, label FROM action_definitions ORDER BY id').map(row => ({ ...row }));
      input.provenanceCodes = connection.all('SELECT code, label FROM source_provenance_codes ORDER BY code').map(row => ({ ...row }));
      input.applicabilities = connection.all('SELECT code, label, renderer_code AS rendererCode FROM applicability_definitions ORDER BY id').map(row => ({ ...row }));
      input.scoringFactors = connection.all(`SELECT code, label, description, minimum_value AS minimumValue, maximum_value AS maximumValue,
        weight, contribution_kind AS contributionKind FROM scoring_factors WHERE policy_id = ? ORDER BY id`, [context.scoring_policy_id]).map(row => ({ ...row }));
      input.categories = categories.map(category => ({ ...category,
        sections: connection.all(`SELECT section.heading FROM guidance_sections section JOIN guidance_surfaces surface ON surface.id = section.surface_id
          WHERE surface.code = ? ORDER BY section.ordinal`, [category.code]).map(row => row.heading) }));
      input.catalogRules = context.base_catalog_id === null ? [] : connection.all(`SELECT version.id AS ruleVersionId, rule.displayed_id AS id,
        rule.rule_kind AS kind, version.lifecycle, wording.text FROM catalog_members member JOIN rule_versions version ON version.id = member.rule_version_id
        JOIN rules rule ON rule.id = version.rule_id JOIN wording_versions wording ON wording.id = version.wording_version_id
        WHERE member.catalog_id = ? ORDER BY rule.id`, [context.base_catalog_id]).map(row => ({ ...row }));
      input.protectedRules = connection.all(`SELECT version.id AS ruleVersionId, rule.displayed_id AS id, wording.text, detail.title, surface.code AS category
        FROM protected_members member JOIN rule_versions version ON version.id = member.rule_version_id
        JOIN rules rule ON rule.id = version.rule_id JOIN wording_versions wording ON wording.id = version.wording_version_id
        JOIN protected_rule_details detail ON detail.rule_version_id = version.id JOIN guidance_surfaces surface ON surface.id = detail.surface_id
        WHERE member.snapshot_id = ? ORDER BY rule.id`, [context.protected_snapshot_id]).map(row => ({ ...row }));
      input.sources = sources.map(source => ({ ...source,
        provenanceCodes: connection.all('SELECT code FROM source_observation_provenance WHERE observation_id = ? ORDER BY ordinal', [source.observationId]).map(row => row.code),
        evidence: connection.all('SELECT evidence_text FROM source_observation_evidence WHERE observation_id = ? ORDER BY ordinal', [source.observationId]).map(row => row.evidence_text) }));
      input.assessments = request.assessmentResultIds.map(assessmentId => {
        identity(assessmentId, 'Assessment result');
        const result = connection.get(`SELECT result.* FROM assessment_results result JOIN evaluations evaluation ON evaluation.id = result.evaluation_id
          JOIN run_evaluations used ON used.evaluation_id = evaluation.id
          WHERE result.id = ? AND used.run_id = ? AND evaluation.evaluator_profile_id = ? AND evaluation.outcome = 'complete'`,
        [assessmentId, request.runId, sourceProfiles[0].id]);
        if (!result || !request.sourceVersionIds.includes(result.source_version_id)) {
          throw new Error('Reconciliation assessment does not belong to its pinned run and source inputs');
        }
        const factors = connection.all(`SELECT factor.code, value.value FROM scorecard_values value JOIN scoring_factors factor ON factor.id = value.factor_id
          WHERE value.scorecard_id = ? ORDER BY factor.id`, [result.scorecard_id]);
        return { assessmentResultId: result.id, evaluationId: result.evaluation_id, sourceVersionId: result.source_version_id,
          localResultKey: result.local_result_key, title: result.title, sourceMeaning: result.source_meaning, impactDescription: result.impact_description,
          hostedApplicable: Boolean(result.hosted_applicable), applicabilityRationale: result.applicability_rationale,
          confidence: { level: result.confidence_level, rationale: result.confidence_rationale,
            uncertainties: connection.all('SELECT description FROM assessment_uncertainties WHERE assessment_id = ? ORDER BY ordinal', [result.id]).map(row => row.description) },
          selectionFactors: Object.fromEntries(factors.map(factor => [factor.code, factor.value])),
          categories: connection.all('SELECT proposed_code FROM assessment_category_proposals WHERE assessment_id = ? ORDER BY ordinal', [result.id]).map(row => row.proposed_code),
          existingCoverage: { score: result.existing_coverage_score, rationale: result.existing_coverage_rationale } };
      });
      if (request.reconciliationPhase === 'routing') {
        if (request.componentIds !== undefined) throw new Error('Routing requires source assessments, not intermediate components');
      } else {
        if (!Array.isArray(request.componentIds) || request.componentIds.length === 0 || new Set(request.componentIds).size !== request.componentIds.length) {
          throw new Error('Later reconciliation phases require unique completed component inputs');
        }
        const members = new Set();
        const verifiedEvaluations = new Set();
        input.components = request.componentIds.map(componentId => {
          identity(componentId, 'Reconciliation component');
          const component = connection.get(`SELECT component.*, evaluation.input_fingerprint, evaluation.evaluator_profile_id FROM reconciliation_components component
            JOIN evaluations evaluation ON evaluation.id = component.evaluation_id JOIN run_evaluations used ON used.evaluation_id = evaluation.id
            WHERE component.id = ? AND used.run_id = ? AND evaluation.outcome = 'complete'`, [componentId, request.runId]);
          if (!component || component.evaluator_profile_id !== request.profileId ||
            (request.reconciliationPhase === 'synthesis' && component.phase_code !== 'consolidation')) {
            throw new Error('Component input must belong to the pinned completed reconciliation phase');
          }
          if (!verifiedEvaluations.has(component.evaluation_id)) {
            const recordedInputs = connection.all('SELECT * FROM evaluation_inputs WHERE evaluation_id = ? ORDER BY id', [component.evaluation_id]);
            const parentRequest = { binding: request.binding, runId: request.runId, profileId: request.profileId,
              sourceVersionIds: recordedInputs.filter(row => row.role_code === 'source').map(row => row.source_version_id),
              assessmentResultIds: recordedInputs.filter(row => row.role_code === 'assessment-result').map(row => row.assessment_result_id),
              reconciliationPhase: component.phase_code };
            if (component.phase_code !== 'routing') parentRequest.componentIds = recordedInputs.filter(row => row.role_code === 'component').map(row => row.reconciliation_component_id);
            if (sourceTextHash(prepareEvaluationInput(connection, parentRequest).serializedInput) !== component.input_fingerprint) {
              throw new Error('Component input refuses changed parent evaluation evidence');
            }
            verifiedEvaluations.add(component.evaluation_id);
          }
          const assessmentResultIds = connection.all('SELECT assessment_result_id AS id FROM reconciliation_component_members WHERE component_id = ? ORDER BY assessment_result_id',
            [componentId]).map(row => row.id);
          if (assessmentResultIds.length === 0 || assessmentResultIds.some(id => !request.assessmentResultIds.includes(id) || members.has(id))) {
            throw new Error('Component input contains empty, foreign, or overlapping assessment coverage');
          }
          assessmentResultIds.forEach(id => members.add(id));
          return { componentId, evaluationId: component.evaluation_id, phase: component.phase_code, semanticSummary: component.semantic_summary, assessmentResultIds };
        });
        if (members.size !== request.assessmentResultIds.length) throw new Error('Component inputs must cover the exact supplied assessment set');
      }
      if (request.reconciliationPhase === 'consolidation') {
        input.sources = input.sources.map(source => ({ sourceVersionId: source.sourceVersionId, observationId: source.observationId,
          sourceDefinitionId: source.sourceDefinitionId, sourceId: source.sourceId, contentSha256: source.contentSha256,
          metadataSha256: source.metadataSha256, provenanceCodes: source.provenanceCodes }));
        input.assessments = input.assessments.map(assessment => ({ assessmentResultId: assessment.assessmentResultId,
          evaluationId: assessment.evaluationId, sourceVersionId: assessment.sourceVersionId, localResultKey: assessment.localResultKey }));
      }
    } else if (request.assessmentResultIds !== undefined || request.reconciliationPhase !== undefined || request.componentIds !== undefined) {
      throw new Error('Assessment-result inputs require a reconciliation evaluator');
    }
    const serializedInput = JSON.stringify(input);
    return { context, sources, serializedInput };
}

export function recordEvaluationRequest(connection, request) {
  return transaction(connection, () => {
    const { context, sources, serializedInput } = prepareEvaluationInput(connection, request);
    const evaluationId = Number(connection.run(`INSERT INTO evaluations(evaluator_profile_id, input_fingerprint, requested_at, outcome)
      VALUES (?, ?, ?, 'running')`, [request.profileId, sourceTextHash(serializedInput), new Date().toISOString()]).lastInsertRowid);
    connection.run("INSERT INTO run_evaluations VALUES (?, ?, 'executed')", [request.runId, evaluationId]);
    for (const source of sources) {
      connection.run("INSERT INTO evaluation_inputs(evaluation_id, role_code, source_version_id) VALUES (?, 'source', ?)", [evaluationId, source.sourceVersionId]);
      connection.run("INSERT INTO evaluation_inputs(evaluation_id, role_code, source_observation_id) VALUES (?, 'source-metadata', ?)", [evaluationId, source.observationId]);
    }
    for (const assessmentId of request.assessmentResultIds ?? []) {
      connection.run("INSERT INTO evaluation_inputs(evaluation_id, role_code, assessment_result_id) VALUES (?, 'assessment-result', ?)", [evaluationId, assessmentId]);
    }
    for (const componentId of request.componentIds ?? []) {
      connection.run("INSERT INTO evaluation_inputs(evaluation_id, role_code, reconciliation_component_id) VALUES (?, 'component', ?)", [evaluationId, componentId]);
    }
    connection.run("INSERT INTO evaluation_inputs(evaluation_id, role_code, protected_snapshot_id) VALUES (?, 'protected', ?)", [evaluationId, context.protected_snapshot_id]);
    connection.run("INSERT INTO evaluation_inputs(evaluation_id, role_code, scoring_policy_id) VALUES (?, 'scoring', ?)", [evaluationId, context.scoring_policy_id]);
    connection.run("INSERT INTO evaluation_inputs(evaluation_id, role_code, capacity_policy_id) VALUES (?, 'capacity', ?)", [evaluationId, context.capacity_policy_id]);
    if (context.base_catalog_id !== null) connection.run("INSERT INTO evaluation_inputs(evaluation_id, role_code, catalog_version_id) VALUES (?, 'catalog', ?)", [evaluationId, context.base_catalog_id]);
    return { evaluationId, runId: request.runId, profileId: request.profileId, inputFingerprint: sourceTextHash(serializedInput), serializedInput };
  });
}

export function failEvaluation(connection, request) {
  requireSourceObject(request, ['binding', 'runId', 'evaluationId', 'failureCode'], ['binding', 'runId', 'evaluationId', 'failureCode'], 'Evaluation failure');
  readSelectedCapacityConfiguration(connection, request.binding);
  requireSourceText(request.failureCode, 'Failure code');
  if (!/^[a-z][a-z0-9-]{0,63}$/.test(request.failureCode)) throw new Error('Failure code must be bounded non-content metadata');
  return transaction(connection, () => {
    if (!connection.get('SELECT evaluation_id FROM run_evaluations WHERE run_id = ? AND evaluation_id = ?', [request.runId, request.evaluationId])) {
      throw new Error('Evaluation failure does not belong to the requested run');
    }
    const changed = connection.run(`UPDATE evaluations SET outcome = 'failed', failure_code = ?, completed_at = ? WHERE id = ? AND outcome = 'running'`,
      [request.failureCode, new Date().toISOString(), request.evaluationId]);
    if (changed.changes !== 1) throw new Error('Only a running evaluation can fail');
    return { evaluationId: request.evaluationId, outcome: 'failed' };
  });
}

export function readAssessmentRecoveryPlan(connection, request) {
  const fields = ['binding', 'runId', 'profileId'];
  requireSourceObject(request, fields, fields, 'Assessment recovery plan');
  readSelectedCapacityConfiguration(connection, request.binding);
  for (const field of ['runId', 'profileId']) identity(request[field], field);
  const context = connection.get(`SELECT run.outcome, profile.task_code FROM analysis_runs run
    JOIN analysis_run_llm_assignments assigned ON assigned.run_id = run.id
    JOIN evaluator_profiles profile ON profile.llm_assignment_id = assigned.assignment_id AND profile.task_code = assigned.task_code
    WHERE run.id = ? AND profile.id = ?`, [request.runId, request.profileId]);
  if (!context || context.outcome !== 'running' || context.task_code !== 'assessment') {
    throw new Error('Assessment recovery requires the running run and its pinned evaluator profile');
  }
  const captured = connection.all('SELECT collection_id FROM run_collections WHERE run_id = ?', [request.runId]);
  const currentHeads = connection.all('SELECT collection_id FROM source_collection_heads');
  if (captured.length !== currentHeads.length || captured.some(row => !currentHeads.some(head => head.collection_id === row.collection_id))) {
    throw new Error('Assessment recovery refuses changed source collections');
  }
  const sources = connection.all(`SELECT member.source_version_id AS sourceVersionId FROM run_collections captured
    JOIN source_collection_members member ON member.collection_id = captured.collection_id
    WHERE captured.run_id = ? AND member.presence = 'present' ORDER BY captured.collection_id, member.ordinal`, [request.runId]);
  const expected = new Set(sources.map(source => source.sourceVersionId));
  const completed = new Set();
  const completedEvaluationIds = [];
  const unfinishedEvaluationIds = [];
  let completedAssessmentCount = 0;
  const evaluations = connection.all(`SELECT evaluation.id, evaluation.outcome, evaluation.evaluator_profile_id FROM run_evaluations used
    JOIN evaluations evaluation ON evaluation.id = used.evaluation_id JOIN evaluator_profiles profile ON profile.id = evaluation.evaluator_profile_id
    WHERE used.run_id = ? AND profile.task_code = 'assessment' ORDER BY evaluation.id`, [request.runId]);
  for (const evaluation of evaluations) {
    if (evaluation.evaluator_profile_id !== request.profileId) throw new Error('Assessment recovery refuses mixed evaluator identities');
    if (evaluation.outcome === 'running') unfinishedEvaluationIds.push(evaluation.id);
    if (evaluation.outcome !== 'complete') continue;
    const inputs = connection.all("SELECT source_version_id FROM evaluation_inputs WHERE evaluation_id = ? AND role_code = 'source' ORDER BY id", [evaluation.id]);
    if (inputs.length === 0) throw new Error('Completed assessment requires recorded source inputs');
    const prepared = prepareEvaluationInput(connection, { binding: request.binding, runId: request.runId, profileId: request.profileId,
      sourceVersionIds: inputs.map(input => input.source_version_id) });
    const recorded = connection.get('SELECT input_fingerprint FROM evaluations WHERE id = ?', [evaluation.id]);
    if (sourceTextHash(prepared.serializedInput) !== recorded.input_fingerprint) throw new Error('Assessment recovery refuses changed evaluation inputs');
    for (const input of inputs) {
      if (!expected.has(input.source_version_id) || completed.has(input.source_version_id)) {
        throw new Error('Assessment recovery refuses missing, foreign, or duplicate completed source coverage');
      }
      completed.add(input.source_version_id);
    }
    completedEvaluationIds.push(evaluation.id);
    completedAssessmentCount += connection.get('SELECT count(*) AS count FROM assessment_results WHERE evaluation_id = ?', [evaluation.id]).count;
  }
  return { runId: request.runId, profileId: request.profileId, completedEvaluationIds, unfinishedEvaluationIds,
    completedSourceCount: completed.size, completedAssessmentCount,
    remainingSourceVersionIds: sources.filter(source => !completed.has(source.sourceVersionId)).map(source => source.sourceVersionId) };
}

export function commitReconciliationComponents(connection, request) {
  const fields = ['binding', 'runId', 'evaluationId', 'inputFingerprint', 'result'];
  requireSourceObject(request, fields, fields, 'Reconciliation component result command');
  readSelectedCapacityConfiguration(connection, request.binding);
  requireSourceHash(request.inputFingerprint, 'Expected input fingerprint');
  const resultFields = ['schemaVersion', 'stage', 'phase', 'components'];
  requireSourceObject(request.result, resultFields, resultFields, 'Reconciliation component result');
  if (request.result.schemaVersion !== 4 || request.result.stage !== 'reconciliation' ||
    !['routing', 'consolidation'].includes(request.result.phase) || !Array.isArray(request.result.components)) {
    throw new Error('Unsupported reconciliation component result contract');
  }
  return transaction(connection, () => {
    const evaluation = connection.get(`SELECT evaluation.*, profile.task_code, run.outcome AS run_outcome FROM evaluations evaluation
      JOIN run_evaluations used ON used.evaluation_id = evaluation.id JOIN evaluator_profiles profile ON profile.id = evaluation.evaluator_profile_id
      JOIN analysis_runs run ON run.id = used.run_id WHERE evaluation.id = ? AND used.run_id = ?`, [request.evaluationId, request.runId]);
    if (!evaluation || evaluation.outcome !== 'running' || evaluation.run_outcome !== 'running' ||
      evaluation.task_code !== 'reconciliation' || evaluation.input_fingerprint !== request.inputFingerprint) {
      throw new Error('Reconciliation result does not match its running request identity');
    }
    const inputs = connection.all("SELECT assessment_result_id AS id FROM evaluation_inputs WHERE evaluation_id = ? AND role_code = 'assessment-result' ORDER BY id", [request.evaluationId]);
    const sourceInputs = connection.all("SELECT source_version_id AS id FROM evaluation_inputs WHERE evaluation_id = ? AND role_code = 'source' ORDER BY id", [request.evaluationId]);
    const componentInputs = connection.all("SELECT reconciliation_component_id AS id FROM evaluation_inputs WHERE evaluation_id = ? AND role_code = 'component' ORDER BY id", [request.evaluationId]);
    if (request.result.phase === 'consolidation' && componentInputs.length === 0) throw new Error('Reconciliation result refuses changed phase or missing component inputs');
    const preparedRequest = { binding: request.binding, runId: request.runId, profileId: evaluation.evaluator_profile_id,
      sourceVersionIds: sourceInputs.map(row => row.id), assessmentResultIds: inputs.map(row => row.id), reconciliationPhase: request.result.phase };
    if (request.result.phase !== 'routing') preparedRequest.componentIds = componentInputs.map(row => row.id);
    const prepared = prepareEvaluationInput(connection, preparedRequest);
    if (sourceTextHash(prepared.serializedInput) !== evaluation.input_fingerprint) {
      throw new Error('Reconciliation result refuses changed phase or evaluation inputs');
    }
    const expected = new Set(inputs.map(row => row.id));
    const received = new Set();
    for (const component of request.result.components) {
      requireSourceObject(component, ['assessmentResultIds', 'semanticSummary'], ['assessmentResultIds', 'semanticSummary'], 'Reconciliation component');
      requireSourceText(component.semanticSummary, 'Component semantic summary');
      if (component.semanticSummary.length > 1200 || !Array.isArray(component.assessmentResultIds) || component.assessmentResultIds.length === 0) {
        throw new Error('Component requires a bounded summary and nonempty member set');
      }
      for (const memberId of component.assessmentResultIds) {
        identity(memberId, 'Component assessment result');
        if (!expected.has(memberId) || received.has(memberId)) throw new Error('Component coverage contains foreign or repeated assessment inputs');
        received.add(memberId);
      }
    }
    if (received.size !== expected.size) throw new Error('Component result must account for every supplied assessment exactly once');
    if (request.result.phase === 'consolidation') {
      const parentComponents = JSON.parse(prepared.serializedInput).components;
      for (const parent of parentComponents) {
        const containing = request.result.components.find(component => component.assessmentResultIds.includes(parent.assessmentResultIds[0]));
        if (!containing || parent.assessmentResultIds.some(id => !containing.assessmentResultIds.includes(id))) {
          throw new Error('Consolidation cannot split a committed input component');
        }
      }
    }
    const componentIds = request.result.components.map((component, ordinal) => {
      const componentId = Number(connection.run(`INSERT INTO reconciliation_components(evaluation_id, phase_code, ordinal, semantic_summary)
        VALUES (?, ?, ?, ?)`, [request.evaluationId, request.result.phase, ordinal, component.semanticSummary]).lastInsertRowid);
      for (const memberId of component.assessmentResultIds) {
        connection.run('INSERT INTO reconciliation_component_members VALUES (?, ?)', [componentId, memberId]);
      }
      return componentId;
    });
    connection.run("UPDATE evaluations SET outcome = 'complete', completed_at = ? WHERE id = ?", [new Date().toISOString(), request.evaluationId]);
    return { evaluationId: request.evaluationId, outcome: 'complete', phase: request.result.phase, componentIds };
  });
}

export function commitAssessmentResults(connection, request) {
  const fields = ['binding', 'runId', 'evaluationId', 'inputFingerprint', 'result'];
  requireSourceObject(request, fields, fields, 'Assessment result command');
  readSelectedCapacityConfiguration(connection, request.binding);
  requireSourceHash(request.inputFingerprint, 'Expected input fingerprint');
  requireSourceObject(request.result, ['schemaVersion', 'stage', 'sources'], ['schemaVersion', 'stage', 'sources'], 'Assessment result');
  if (request.result.schemaVersion !== 4 || request.result.stage !== 'assessment' || !Array.isArray(request.result.sources)) throw new Error('Unsupported assessment result contract');
  return transaction(connection, () => {
    const evaluation = connection.get(`SELECT evaluation.*, profile.task_code, context.scoring_policy_id, run.outcome AS run_outcome FROM evaluations evaluation
      JOIN run_evaluations used ON used.evaluation_id = evaluation.id JOIN evaluator_profiles profile ON profile.id = evaluation.evaluator_profile_id
      JOIN analysis_run_contexts context ON context.run_id = used.run_id
      JOIN analysis_runs run ON run.id = used.run_id
      WHERE evaluation.id = ? AND used.run_id = ?`, [request.evaluationId, request.runId]);
    if (!evaluation || evaluation.outcome !== 'running' || evaluation.run_outcome !== 'running' ||
      evaluation.task_code !== 'assessment' || evaluation.input_fingerprint !== request.inputFingerprint) {
      throw new Error('Assessment result does not match its running request identity');
    }
    const expected = connection.all(`SELECT input.source_version_id, configuration.assessment_cardinality FROM evaluation_inputs input
      JOIN run_collections captured ON captured.run_id = ? JOIN source_collection_members member
        ON member.collection_id = captured.collection_id AND member.source_version_id = input.source_version_id
      JOIN source_collections collection ON collection.id = captured.collection_id
      JOIN source_definition_versions configuration ON configuration.id = collection.definition_version_id
      WHERE input.evaluation_id = ? AND input.role_code = 'source'`, [request.runId, request.evaluationId]);
    const received = new Set(request.result.sources.map(source => source.sourceVersionId));
    if (received.size !== request.result.sources.length || received.size !== expected.length || expected.some(source => !received.has(source.source_version_id))) {
      throw new Error('Assessment result must account for exactly the captured request sources');
    }
    const factors = connection.all('SELECT id, code FROM scoring_factors WHERE policy_id = ? ORDER BY id', [evaluation.scoring_policy_id]);
    const categoryIds = new Map(connection.all('SELECT id, code FROM guidance_surfaces').map(row => [row.code, row.id]));
    let assessmentCount = 0;
    for (const source of request.result.sources) {
      requireSourceObject(source, ['sourceVersionId', 'assessments'], ['sourceVersionId', 'assessments'], 'Source assessment results');
      if (!Array.isArray(source.assessments)) throw new Error('Source assessments must be an array');
      const cardinality = expected.find(value => value.source_version_id === source.sourceVersionId).assessment_cardinality;
      if ((cardinality === 'exactly-one' && source.assessments.length !== 1) || source.assessments.length > 50) throw new Error('Source result violates its registered assessment cardinality');
      for (const assessment of source.assessments) {
        const fields = ['localResultKey', 'title', 'sourceMeaning', 'impactDescription', 'hostedApplicable', 'applicabilityRationale',
          'selectionFactors', 'selectionRationale', 'confidence', 'categories', 'existingCoverage'];
        requireSourceObject(assessment, fields, fields, 'Native assessment');
        for (const field of ['localResultKey', 'title', 'sourceMeaning', 'impactDescription', 'applicabilityRationale', 'selectionRationale']) requireSourceText(assessment[field], field);
        if (typeof assessment.hostedApplicable !== 'boolean' || !Array.isArray(assessment.categories)) throw new Error('Assessment applicability and categories are required');
        requireSourceObject(assessment.selectionFactors, factors.map(factor => factor.code), factors.map(factor => factor.code), 'Selection factors');
        requireSourceObject(assessment.confidence, ['level', 'rationale', 'uncertainties'], ['level', 'rationale', 'uncertainties'], 'Assessment confidence');
        requireSourceText(assessment.confidence.rationale, 'Confidence rationale');
        if (!Array.isArray(assessment.confidence.uncertainties)) throw new Error('Assessment uncertainties must be an array');
        requireSourceObject(assessment.existingCoverage, ['score', 'rationale'], ['score', 'rationale'], 'Existing coverage');
        requireSourceText(assessment.existingCoverage.rationale, 'Coverage rationale');
        const scorecardId = Number(connection.run('INSERT INTO scorecards(policy_id, selection_rationale) VALUES (?, ?)',
          [evaluation.scoring_policy_id, assessment.selectionRationale]).lastInsertRowid);
        for (const factor of factors) connection.run('INSERT INTO scorecard_values VALUES (?, ?, ?)', [scorecardId, factor.id, assessment.selectionFactors[factor.code]]);
        const assessmentId = Number(connection.run(`INSERT INTO assessment_results(evaluation_id, source_version_id, local_result_key,
          title, source_meaning, impact_description, hosted_applicable, applicability_rationale, confidence_level, confidence_rationale,
          existing_coverage_score, existing_coverage_rationale, scorecard_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [request.evaluationId, source.sourceVersionId, assessment.localResultKey, assessment.title, assessment.sourceMeaning, assessment.impactDescription,
          Number(assessment.hostedApplicable), assessment.applicabilityRationale, assessment.confidence.level, assessment.confidence.rationale,
          assessment.existingCoverage.score, assessment.existingCoverage.rationale, scorecardId]).lastInsertRowid);
        assessment.confidence.uncertainties.forEach((text, ordinal) => {
          requireSourceText(text, 'Uncertainty');
          connection.run('INSERT INTO assessment_uncertainties VALUES (?, ?, ?)', [assessmentId, ordinal, text]);
        });
        for (const [ordinal, category] of assessment.categories.entries()) {
          requireSourceText(category, 'Proposed category');
          if (category.length > 128) throw new Error('Proposed category exceeds its supported length');
          connection.run('INSERT INTO assessment_category_proposals VALUES (?, ?, ?)', [assessmentId, ordinal, category]);
          if (categoryIds.has(category)) connection.run('INSERT INTO assessment_surfaces VALUES (?, ?)', [assessmentId, categoryIds.get(category)]);
        }
        assessmentCount += 1;
      }
    }
    connection.run("UPDATE evaluations SET outcome = 'complete', completed_at = ? WHERE id = ?", [new Date().toISOString(), request.evaluationId]);
    return { evaluationId: request.evaluationId, outcome: 'complete', assessmentCount };
  });
}
