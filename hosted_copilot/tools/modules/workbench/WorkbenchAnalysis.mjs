import { execFile, execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { requireSourceObject, requireSourceText, sourceTextHash } from './WorkbenchSourceRecords.mjs';
import { beginAnalysisRun, registerEvaluatorProfile, readAssessmentRecoveryPlan } from './WorkbenchEvaluations.mjs';
import { readWorkspaceLlmAssignments } from './WorkbenchLlmAssignments.mjs';
import { executeAssessmentBatches } from './WorkbenchAssessmentExecution.mjs';
import { executeNativeDownstream } from './WorkbenchDownstreamExecution.mjs';
import { readSelectedCapacityConfiguration } from './WorkbenchWorkspace.mjs';

const executeFile = promisify(execFile);
const hostedRoot = fileURLToPath(new URL('../../../', import.meta.url));
const repositoryRoot = resolve(hostedRoot, '..');
const runnerPath = resolve(hostedRoot, 'tools/internal/workbench/Invoke-NativeEvaluation.ps1');

export function invokeNativeProcess(argumentsList, serializedInput) {
  const execution = executeFile('pwsh', argumentsList, { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024, timeout: 620000 });
  execution.child.stdin.end(serializedInput);
  return execution;
}

export function readNativeLlmRuntime(connection, databaseGuid) {
  const branchRef = execFileSync('git', ['-C', repositoryRoot, 'symbolic-ref', '--quiet', 'HEAD'], { encoding: 'utf8' }).trim();
  const workspace = connection.get(`SELECT workspace.database_guid, origin.repository_id, repository.canonical_name
    FROM workspace_identity workspace JOIN repository_contexts origin ON origin.id = workspace.origin_context_id
    JOIN repositories repository ON repository.id = origin.repository_id WHERE workspace.id = 1`);
  if (!workspace || workspace.database_guid !== databaseGuid || workspace.canonical_name !== `local:${sourceTextHash(repositoryRoot)}`) {
    throw new Error('Analysis database does not match the explicitly selected local workspace');
  }
  const binding = { databaseGuid, repositoryId: workspace.repository_id, branchRef };
  return { binding, assignments: readWorkspaceLlmAssignments(connection, binding) };
}

export function readNativeAssessmentBehaviorHash(cliVersion) {
  return sourceTextHash(JSON.stringify([
    readFileSync(fileURLToPath(import.meta.url), 'utf8'),
    readFileSync(fileURLToPath(new URL('./WorkbenchAssessmentExecution.mjs', import.meta.url)), 'utf8'),
    readFileSync(fileURLToPath(new URL('./WorkbenchEvaluations.mjs', import.meta.url)), 'utf8'),
    readFileSync(runnerPath, 'utf8'), cliVersion,
  ]));
}

export async function runNativeDownstream(connection, request, report = () => {}) {
  const fields = ['databaseGuid', 'runId', 'evaluatorCommand', 'cliVersion', 'llmAssignmentIds', 'maxParallelBatches'];
  requireSourceObject(request, fields, fields, 'Native downstream request');
  for (const field of ['evaluatorCommand', 'cliVersion']) requireSourceText(request[field], field);
  const { binding, assignments } = readNativeLlmRuntime(connection, request.databaseGuid);
  const capacity = readSelectedCapacityConfiguration(connection, binding);
  const context = connection.get(`SELECT context.*, run.outcome FROM analysis_run_contexts context JOIN analysis_runs run ON run.id = context.run_id
    WHERE context.run_id = ?`, [request.runId]);
  const workspace = connection.get('SELECT team_profile_id, current_protected_snapshot_id FROM workspace_identity WHERE id = 1');
  const catalogId = connection.get('SELECT current_catalog_id FROM workspace_publication WHERE workspace_id = 1')?.current_catalog_id ?? null;
  const pinned = connection.all('SELECT task_code, assignment_id FROM analysis_run_llm_assignments WHERE run_id = ?', [request.runId]);
  if (!context || context.outcome !== 'running' || context.team_profile_id !== workspace.team_profile_id ||
    context.protected_snapshot_id !== workspace.current_protected_snapshot_id || context.capacity_policy_id !== capacity.policy.policyId || context.base_catalog_id !== catalogId ||
    !Array.isArray(request.llmAssignmentIds) || request.llmAssignmentIds.length !== assignments.length || new Set(request.llmAssignmentIds).size !== assignments.length ||
    pinned.length !== assignments.length || assignments.some(assignment => !request.llmAssignmentIds.includes(assignment.assignmentId) ||
      !pinned.some(row => row.task_code === assignment.taskCode && row.assignment_id === assignment.assignmentId))) {
    throw new Error('Native downstream continuation refuses changed workspace context or unvalidated model assignments');
  }
  const sourceProfiles = connection.all(`SELECT DISTINCT profile.id FROM evaluator_profiles profile JOIN evaluations evaluation ON evaluation.evaluator_profile_id = profile.id
    JOIN run_evaluations used ON used.evaluation_id = evaluation.id WHERE used.run_id = ? AND profile.task_code = 'assessment'`, [request.runId]);
  if (sourceProfiles.length !== 1) throw new Error('Native downstream continuation requires one recorded source-assessment profile');
  const recovery = readAssessmentRecoveryPlan(connection, { binding, runId: request.runId, profileId: sourceProfiles[0].id });
  if (recovery.remainingSourceVersionIds.length || recovery.unfinishedEvaluationIds.length) {
    throw new Error('Native downstream continuation requires complete committed source assessments; resume source assessment separately');
  }
  const registry = JSON.parse(readFileSync(resolve(hostedRoot, 'contracts/workbench/native-evaluation-stages-v4.json'), 'utf8'));
  const behaviorFiles = ['WorkbenchAnalysis.mjs', 'WorkbenchAssessmentExecution.mjs', 'WorkbenchDownstreamExecution.mjs', 'WorkbenchReconciliationResults.mjs', 'WorkbenchAdjudication.mjs',
    'WorkbenchAnalysisCompletion.mjs', 'WorkbenchEvaluations.mjs', 'WorkbenchWorkspace.mjs', 'WorkbenchLlmAssignments.mjs', 'WorkbenchSourceRecords.mjs'];
  const behaviorHash = sourceTextHash(JSON.stringify([behaviorFiles.map(file => readFileSync(resolve(hostedRoot, 'tools/modules/workbench', file), 'utf8')),
    readFileSync(runnerPath, 'utf8'), readFileSync(resolve(hostedRoot, 'tools/modules/shared/HostedCli.psm1'), 'utf8'), request.cliVersion]));
  const evaluatorInputs = {};
  const profiles = {};
  const models = {};
  for (const task of ['reconciliation', 'adjudication']) {
    const stages = registry.stages.filter(stage => stage.code === task);
    const selected = assignments.filter(assignment => assignment.taskCode === task);
    if (registry.schemaVersion !== 4 || stages.length !== 1 || selected.length !== 1 ||
      selected[0].providerCode !== 'github-copilot' || selected[0].adapterCode !== 'copilot-cli') {
      throw new Error('Native downstream task requires one registered stage and supported model assignment');
    }
    const input = { prompt: readFileSync(resolve(hostedRoot, stages[0].prompt), 'utf8'), schema: readFileSync(resolve(hostedRoot, stages[0].resultSchema), 'utf8') };
    const prior = connection.all(`SELECT DISTINCT profile.* FROM evaluator_profiles profile JOIN evaluations evaluation ON evaluation.evaluator_profile_id = profile.id
      JOIN run_evaluations used ON used.evaluation_id = evaluation.id WHERE used.run_id = ? AND profile.task_code = ?`, [request.runId, task]);
    if (prior.length > 1 || prior.some(profile => profile.llm_assignment_id !== selected[0].assignmentId || profile.prompt_sha256 !== sourceTextHash(input.prompt) ||
      profile.result_contract_sha256 !== sourceTextHash(input.schema) || profile.behavior_sha256 !== behaviorHash)) {
      throw new Error('Native downstream recovery refuses changed prompt, result contract, or evaluator behavior');
    }
    evaluatorInputs[task] = input;
    models[task] = selected[0];
    profiles[task] = prior[0]?.id ?? registerEvaluatorProfile(connection, { code: `native-${task}-v4`, taskCode: task, llmAssignmentId: selected[0].assignmentId,
      promptSha256: sourceTextHash(input.prompt), behaviorSha256: behaviorHash, resultContractSha256: sourceTextHash(input.schema) });
  }
  const expectedHeadRunId = connection.get('SELECT run_id FROM workspace_analysis_head WHERE workspace_id = 1')?.run_id ?? null;
  return executeNativeDownstream(connection, { binding, runId: request.runId, sourceProfileId: sourceProfiles[0].id,
    reconciliationProfileId: profiles.reconciliation, adjudicationProfileId: profiles.adjudication, expectedHeadRunId }, evaluatorInputs, async (recorded, { phase }) => {
    const task = phase === 'adjudication' ? 'adjudication' : 'reconciliation';
    const { stdout } = await invokeNativeProcess(['-NoProfile', '-NonInteractive', '-File', runnerPath, '-Stage', task,
      '-Model', models[task].model, '-ReasoningEffort', models[task].reasoningEffort, '-ExpectedPromptSha256', sourceTextHash(evaluatorInputs[task].prompt),
      '-ExpectedSchemaSha256', sourceTextHash(evaluatorInputs[task].schema), '-EvaluatorCommand', request.evaluatorCommand], recorded.serializedInput);
    return JSON.parse(stdout);
  }, report, request.maxParallelBatches);
}

export async function runNativeAssessments(connection, request, report = () => {}) {
  const fields = ['databaseGuid', 'evaluatorCommand', 'cliVersion', 'force', 'llmAssignmentIds', 'maxParallelBatches'];
  requireSourceObject(request, fields, fields, 'Native analysis request');
  for (const field of ['evaluatorCommand', 'cliVersion']) requireSourceText(request[field], field);
  const { binding, assignments } = readNativeLlmRuntime(connection, request.databaseGuid);
  const selected = assignments.filter(assignment => assignment.taskCode === 'assessment');
  if (selected.length !== 1 || selected[0].adapterCode !== 'copilot-cli' || selected[0].providerCode !== 'github-copilot') {
    throw new Error('Native assessment requires one explicitly assigned supported model');
  }
  const llm = selected[0];
  const scoring = connection.all("SELECT id FROM scoring_policies WHERE code = 'terraform-selection' AND revision = 1");
  const actors = connection.all("SELECT id FROM actors WHERE actor_kind = 'system'");
  if (scoring.length !== 1 || actors.length !== 1) throw new Error('Current workspace does not select the required native scoring/system context');
  const registryPath = resolve(hostedRoot, 'contracts/workbench/native-evaluation-stages-v4.json');
  const registry = JSON.parse(readFileSync(registryPath, 'utf8'));
  const stages = registry.stages.filter(stage => stage.code === 'assessment');
  if (stages.length !== 1) throw new Error('Native assessment stage is not uniquely registered');
  const prompt = readFileSync(resolve(hostedRoot, stages[0].prompt), 'utf8');
  const schema = readFileSync(resolve(hostedRoot, stages[0].resultSchema), 'utf8');
  const profileId = registerEvaluatorProfile(connection, {
    code: 'native-assessment-v4', taskCode: 'assessment', llmAssignmentId: llm.assignmentId, promptSha256: sourceTextHash(prompt),
    behaviorSha256: readNativeAssessmentBehaviorHash(request.cliVersion),
    resultContractSha256: sourceTextHash(schema),
  });
  const run = beginAnalysisRun(connection, { binding, actorId: actors[0].id, scoringPolicyId: scoring[0].id, force: request.force, llmAssignmentIds: request.llmAssignmentIds });
  try {
    return await executeAssessmentBatches(connection, { binding, runId: run.runId, profileId }, { prompt, schema }, async recorded => {
      const { stdout } = await invokeNativeProcess(['-NoProfile', '-NonInteractive', '-File', runnerPath,
        '-Stage', 'assessment', '-Model', llm.model, '-ReasoningEffort', llm.reasoningEffort,
        '-ExpectedPromptSha256', sourceTextHash(prompt), '-ExpectedSchemaSha256', sourceTextHash(schema), '-EvaluatorCommand', request.evaluatorCommand],
      recorded.serializedInput);
      return JSON.parse(stdout);
    }, report, request.maxParallelBatches);
  } catch (error) {
    connection.run("UPDATE analysis_runs SET outcome = 'failed', completed_at = ? WHERE id = ? AND outcome = 'running'", [new Date().toISOString(), run.runId]);
    throw new Error(`Native assessment run ${run.runId} failed; committed requests/results were retained and the current analysis head was not changed`, { cause: error });
  }
}
