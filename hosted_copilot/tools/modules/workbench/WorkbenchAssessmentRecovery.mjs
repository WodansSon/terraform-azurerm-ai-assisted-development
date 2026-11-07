import { randomBytes } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { requireSourceObject, sourceTextHash } from './WorkbenchSourceRecords.mjs';
import { readSelectedCapacityConfiguration } from './WorkbenchWorkspace.mjs';
import { readNativeLlmRuntime, invokeNativeProcess, readNativeAssessmentBehaviorHash } from './WorkbenchAnalysis.mjs';
import { executeAssessmentBatches } from './WorkbenchAssessmentExecution.mjs';

const hostedRoot = fileURLToPath(new URL('../../../', import.meta.url));
const executionGuardPath = resolve(hostedRoot, 'tools/internal/workbench/Invoke-WorkbenchExecutionGuard.ps1');

function invokeExecutionGuard(action, owner) {
  let result;
  try {
    result = JSON.parse(execFileSync('pwsh', ['-NoProfile', '-NonInteractive', '-File', executionGuardPath, '-Action', action],
      { encoding: 'utf8', input: JSON.stringify(owner), timeout: 30000, stdio: ['pipe', 'pipe', 'pipe'] }));
  } catch {
    throw new Error('Assessment execution is locked, or process ownership could not be verified; no takeover was performed');
  }
  if (result.failureCode === 'execution-already-running') {
    const error = new Error('Workbench analysis is already running or starting for this database; wait for the active command to finish or cancel it');
    error.code = 'workbench-execution-already-running';
    throw error;
  }
  return result;
}

export async function withAssessmentExecutionLock(databasePath, operation) {
  const owner = { databasePath, pid: process.pid, nonce: randomBytes(16).toString('hex') };
  const claimed = invokeExecutionGuard('claim', owner);
  owner.processStartTicks = claimed.processStartTicks;
  let cancelled = false;
  let cancellationFailure;
  const control = {
    recoveredLock: claimed.recovered,
    get cancelled() { return cancelled; },
    throwIfCancelled() {
      if (cancelled) throw new Error('Execution cancelled; committed results were retained and unfinished requests require recovery');
    },
  };
  const cancel = () => {
    if (cancelled) return;
    cancelled = true;
    try { invokeExecutionGuard('cancel-children', owner); }
    catch (error) { cancellationFailure = error; }
  };
  const outputClosed = error => { if (error.code === 'EPIPE') cancel(); };
  process.on('SIGINT', cancel);
  process.on('SIGTERM', cancel);
  process.stdout.on('error', outputClosed);
  try {
    const result = await operation(control);
    if (cancellationFailure) throw cancellationFailure;
    control.throwIfCancelled();
    return result;
  } finally {
    process.removeListener('SIGINT', cancel);
    process.removeListener('SIGTERM', cancel);
    process.stdout.removeListener('error', outputClosed);
    invokeExecutionGuard('release', owner);
  }
}

export function withExecutionCancellation(connection, control) {
  return Object.freeze({ ...connection,
    get isTransaction() { return connection.isTransaction; },
    run(sql, parameters) { control.throwIfCancelled(); return connection.run(sql, parameters); },
    exec(sql) {
      if (sql.trim().toUpperCase() !== 'ROLLBACK') control.throwIfCancelled();
      return connection.exec(sql);
    },
  });
}

export async function continueAssessmentRun(connection, request, evaluatorInput, evaluate, report = () => {}, maxParallelBatches = 3) {
  return executeAssessmentBatches(connection, request, evaluatorInput, evaluate, report, maxParallelBatches);
}

export async function resumeNativeAssessments(connection, request, report = () => {}) {
  const fields = ['databaseGuid', 'runId', 'evaluatorCommand', 'cliVersion', 'llmAssignmentIds', 'maxParallelBatches'];
  requireSourceObject(request, fields, fields, 'Assessment resume request');
  const { binding, assignments } = readNativeLlmRuntime(connection, request.databaseGuid);
  const capacity = readSelectedCapacityConfiguration(connection, binding);
  const context = connection.get('SELECT * FROM analysis_run_contexts WHERE run_id = ?', [request.runId]);
  const current = connection.get('SELECT current_protected_snapshot_id, team_profile_id FROM workspace_identity WHERE id = 1');
  const catalog = connection.get('SELECT current_catalog_id FROM workspace_publication WHERE workspace_id = 1');
  if (!context || context.team_profile_id !== current.team_profile_id || context.protected_snapshot_id !== current.current_protected_snapshot_id ||
    context.capacity_policy_id !== capacity.policy.policyId || context.base_catalog_id !== (catalog?.current_catalog_id ?? null)) {
    throw new Error('Assessment resume refuses changed workspace context');
  }
  const pinned = connection.all('SELECT task_code, assignment_id FROM analysis_run_llm_assignments WHERE run_id = ?', [request.runId]);
  if (!Array.isArray(request.llmAssignmentIds) || new Set(request.llmAssignmentIds).size !== assignments.length ||
    request.llmAssignmentIds.length !== assignments.length || pinned.length !== assignments.length || assignments.some(assignment =>
      !request.llmAssignmentIds.includes(assignment.assignmentId) || !pinned.some(row => row.task_code === assignment.taskCode && row.assignment_id === assignment.assignmentId))) {
    throw new Error('Assessment resume refuses changed or unvalidated model assignments');
  }
  const profiles = connection.all(`SELECT DISTINCT profile.* FROM run_evaluations used JOIN evaluations evaluation ON evaluation.id = used.evaluation_id
    JOIN evaluator_profiles profile ON profile.id = evaluation.evaluator_profile_id WHERE used.run_id = ? AND profile.task_code = 'assessment'`, [request.runId]);
  const llm = assignments.find(assignment => assignment.taskCode === 'assessment');
  if (profiles.length !== 1 || llm?.providerCode !== 'github-copilot' || llm.adapterCode !== 'copilot-cli' || profiles[0].llm_assignment_id !== llm.assignmentId) {
    throw new Error('Assessment resume requires one pinned supported evaluator');
  }
  const registry = JSON.parse(readFileSync(resolve(hostedRoot, 'contracts/workbench/native-evaluation-stages-v4.json'), 'utf8'));
  const stages = registry.stages.filter(stage => stage.code === 'assessment');
  if (stages.length !== 1) throw new Error('Assessment resume requires one registered assessment stage');
  const runner = resolve(hostedRoot, 'tools/internal/workbench/Invoke-NativeEvaluation.ps1');
  const prompt = readFileSync(resolve(hostedRoot, stages[0].prompt), 'utf8');
  const schema = readFileSync(resolve(hostedRoot, stages[0].resultSchema), 'utf8');
  const promptHash = sourceTextHash(prompt);
  const schemaHash = sourceTextHash(schema);
  const behaviorHash = readNativeAssessmentBehaviorHash(request.cliVersion);
  if (profiles[0].prompt_sha256 !== promptHash || profiles[0].result_contract_sha256 !== schemaHash || profiles[0].behavior_sha256 !== behaviorHash) {
    throw new Error('Assessment resume refuses changed prompt, result contract, or evaluator behavior');
  }
  return continueAssessmentRun(connection, { binding, runId: request.runId, profileId: profiles[0].id }, { prompt, schema }, async recorded => {
    const { stdout } = await invokeNativeProcess(['-NoProfile', '-NonInteractive', '-File', runner, '-Stage', 'assessment',
      '-Model', llm.model, '-ReasoningEffort', llm.reasoningEffort, '-ExpectedPromptSha256', promptHash,
      '-ExpectedSchemaSha256', schemaHash, '-EvaluatorCommand', request.evaluatorCommand], recorded.serializedInput);
    return JSON.parse(stdout);
  }, report, request.maxParallelBatches);
}
