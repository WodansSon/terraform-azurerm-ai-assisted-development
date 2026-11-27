const trustedResults = new WeakMap();
const trustedDetails = new Set();
const stages = new Set(['request', 'evaluate', 'commit']);
const unknownReasons = {
  request: 'Evaluation request failed; the original reason is unavailable in safe diagnostics',
  evaluate: 'Evaluator invocation failed; the original reason is unavailable in safe diagnostics',
  commit: 'Evaluation result commit failed; the original reason is unavailable in safe diagnostics',
};
const contractReason = 'Evaluator response failed its result contract; raw response content omitted';
const storageReason = 'Evaluation result violated a database constraint; database content omitted';
const cliReasons = new Map([
  ['cli-exit', 'Evaluator CLI exited unsuccessfully; response content omitted'],
  ['cli-options', 'Evaluator CLI rejected its options; response content omitted'],
  ['prompt-mode', 'Evaluator CLI rejected non-interactive input; response content omitted'],
  ['authentication', 'Evaluator CLI authentication failed; response content omitted'],
  ['permissions', 'Evaluator CLI permissions failed; response content omitted'],
  ['model-settings', 'Evaluator CLI rejected model settings; response content omitted'],
  ['working-directory', 'Evaluator CLI rejected its working directory; local paths omitted'],
]);

function registerDetails(failureReason, failurePath) {
  trustedDetails.add(JSON.stringify([failureReason, failurePath]));
}
for (const reason of [...Object.values(unknownReasons), contractReason, storageReason, ...cliReasons.values()]) registerDetails(reason, null);

// Only server-owned literal validation text and schema locations belong at this boundary.
export function evaluationResultError(message, path = null) {
  if (typeof message !== 'string' || message.length === 0 || message.length > 512 || /[^\x20-\x7e]/.test(message) ||
      (path !== null && (typeof path !== 'string' || path.length > 256 ||
        !/^\/(?:groups|components|dispositions|assessments|relationshipDecisions|issues)(?:\/(?:[a-z][A-Za-z]*|0|[1-9][0-9]*))*$/.test(path)))) {
    throw new Error('Evaluation diagnostic requires bounded server-owned text and a schema location');
  }
  const error = new Error(message);
  trustedResults.set(error, { failureReason: message, failurePath: path });
  registerDetails(message, path);
  return error;
}

export function validateEvaluationFailureDetails({ failureStage = null, failureReason = null, failurePath = null }) {
  if ((failureStage !== null && !stages.has(failureStage)) ||
      (failureReason !== null && (failureStage === null || typeof failureReason !== 'string' || failureReason.length > 512)) ||
      (failurePath !== null && (failureReason === null || typeof failurePath !== 'string' || failurePath.length > 256)) ||
      (failureReason !== null && !trustedDetails.has(JSON.stringify([failureReason, failurePath])))) {
    throw new Error('Evaluation failure diagnostics must be registered safe metadata');
  }
  return { failureStage, failureReason, failurePath };
}

export function describeEvaluationFailure(error, stage) {
  if (!stages.has(stage)) throw new Error('Evaluation failure stage is unsupported');
  const trusted = error !== null && typeof error === 'object' ? trustedResults.get(error) : null;
  if (trusted) return { failureCode: 'evaluator-result-contract-invalid', failureStage: stage, ...trusted };
  const result = { failureCode: 'evaluator-or-result-failed', failureStage: stage, failureReason: unknownReasons[stage], failurePath: null };
  if (stage === 'commit' && error?.code === 'ERR_SQLITE_ERROR' && Number.isSafeInteger(error.errcode) && error.errcode > 0 && (error.errcode & 255) === 19) {
    return { ...result, failureCode: 'evaluation-result-storage-constraint', failureReason: storageReason };
  }
  if (stage !== 'evaluate') return result;
  const stderr = typeof error?.stderr === 'string' && error.stderr.length <= 16384
    ? error.stderr.replace(/\x1b\[[0-9;]*m/g, '') : '';
  const messages = [typeof error?.message === 'string' ? error.message : '', ...stderr.split(/\r?\n/).map(line => line.trim().replace(/^(?:\|\s*|Exception:\s*)/, ''))];
  if (messages.includes('Native evaluator response failed its result contract; content omitted') ||
      messages.includes('Native evaluator response failed its result contract')) {
    return { ...result, failureCode: 'evaluator-result-contract-invalid', failureReason: contractReason };
  }
  for (const line of stderr.split(/\r?\n/)) {
    if (line.length > 512 || !line.trim().startsWith('{')) continue;
    let diagnostic;
    try { diagnostic = JSON.parse(line); } catch { continue; }
    if (diagnostic?.kind === 'native-cli-exit' && cliReasons.has(diagnostic.category) &&
        Number.isSafeInteger(diagnostic.exitCode) && diagnostic.exitCode !== 0 &&
        Number.isSafeInteger(diagnostic.stdoutBytes) && diagnostic.stdoutBytes >= 0 &&
        Number.isSafeInteger(diagnostic.stderrBytes) && diagnostic.stderrBytes >= 0 &&
        Object.keys(diagnostic).sort().join(',') === 'category,exitCode,kind,stderrBytes,stdoutBytes') {
      return { ...result, failureCode: `evaluator-${diagnostic.category}-failed`, failureReason: cliReasons.get(diagnostic.category) };
    }
  }
  return result;
}
