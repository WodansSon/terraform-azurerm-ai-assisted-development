import { requireSourceObject, requireSourceText } from './WorkbenchSourceRecords.mjs';
import { readSelectedCapacityConfiguration } from './WorkbenchWorkspace.mjs';

function scopedTransaction(connection, operation) {
  connection.exec('SAVEPOINT workbench_llm_configuration');
  try {
    const result = operation();
    connection.exec('RELEASE workbench_llm_configuration');
    return result;
  } catch (error) {
    connection.exec('ROLLBACK TO workbench_llm_configuration; RELEASE workbench_llm_configuration');
    throw error;
  }
}

export function configureProfileLlms(connection, teamProfileId, configuration) {
  requireSourceObject(configuration, ['models', 'assignments'], ['models', 'assignments'], 'Master-profile LLM configuration');
  if (!Number.isSafeInteger(teamProfileId) || teamProfileId < 1 || !connection.get('SELECT id FROM team_profiles WHERE id = ?', [teamProfileId])) {
    throw new Error('LLM configuration requires an existing master profile');
  }
  if (!Array.isArray(configuration.models) || configuration.models.length === 0 || !Array.isArray(configuration.assignments) || configuration.assignments.length === 0) {
    throw new Error('Master profile requires a nonempty model and task assignment set');
  }
  const modelsByKey = new Map();
  for (const model of configuration.models) {
    requireSourceObject(model, ['key', 'providerCode', 'modelCode'], ['key', 'providerCode', 'modelCode'], 'LLM model identity');
    for (const field of ['key', 'providerCode', 'modelCode']) requireSourceText(model[field], field);
    if (modelsByKey.has(model.key)) throw new Error('LLM model keys must be unique within the configuration');
    modelsByKey.set(model.key, model);
  }
  const tasks = new Set();
  for (const assignment of configuration.assignments) {
    requireSourceObject(assignment, ['taskCode', 'modelKey', 'adapterCode', 'reasoningEffort'], ['taskCode', 'modelKey', 'adapterCode', 'reasoningEffort'], 'LLM task assignment');
    for (const field of ['taskCode', 'modelKey', 'adapterCode', 'reasoningEffort']) requireSourceText(assignment[field], field);
    if (!/^[a-z][a-z0-9-]*$/.test(assignment.taskCode) || tasks.has(assignment.taskCode)) throw new Error('Each configured task must have exactly one explicit LLM assignment');
    if (!modelsByKey.has(assignment.modelKey)) throw new Error('LLM task references an undeclared model');
    if (!['low', 'medium', 'high', 'xhigh'].includes(assignment.reasoningEffort)) throw new Error('LLM assignment has an unsupported reasoning effort');
    tasks.add(assignment.taskCode);
  }
  return scopedTransaction(connection, () => {
    const modelIds = new Map();
    for (const [key, model] of modelsByKey) {
      connection.run('INSERT INTO llm_models(provider_code, model_code) VALUES (?, ?) ON CONFLICT(provider_code, model_code) DO NOTHING', [model.providerCode, model.modelCode]);
      modelIds.set(key, connection.get('SELECT id FROM llm_models WHERE provider_code = ? AND model_code = ?', [model.providerCode, model.modelCode]).id);
    }
    const assignments = [];
    for (const assignment of configuration.assignments) {
      const modelId = modelIds.get(assignment.modelKey);
      const current = connection.get(`SELECT assignment.* FROM profile_llm_heads head JOIN profile_llm_assignments assignment ON assignment.id = head.assignment_id
        WHERE head.team_profile_id = ? AND head.task_code = ?`, [teamProfileId, assignment.taskCode]);
      let assignmentId = current?.id;
      if (!current || current.model_id !== modelId || current.adapter_code !== assignment.adapterCode || current.reasoning_effort !== assignment.reasoningEffort) {
        const revision = connection.get('SELECT coalesce(max(revision), 0) + 1 AS revision FROM profile_llm_assignments WHERE team_profile_id = ? AND task_code = ?', [teamProfileId, assignment.taskCode]).revision;
        assignmentId = Number(connection.run(`INSERT INTO profile_llm_assignments(team_profile_id, task_code, revision, model_id, adapter_code, reasoning_effort)
          VALUES (?, ?, ?, ?, ?, ?)`, [teamProfileId, assignment.taskCode, revision, modelId, assignment.adapterCode, assignment.reasoningEffort]).lastInsertRowid);
        connection.run(`INSERT INTO profile_llm_heads VALUES (?, ?, ?) ON CONFLICT(team_profile_id, task_code) DO UPDATE SET assignment_id = excluded.assignment_id`,
          [teamProfileId, assignment.taskCode, assignmentId]);
      }
      assignments.push({ taskCode: assignment.taskCode, assignmentId });
    }
    for (const head of connection.all('SELECT task_code FROM profile_llm_heads WHERE team_profile_id = ?', [teamProfileId])) {
      if (!tasks.has(head.task_code)) connection.run('DELETE FROM profile_llm_heads WHERE team_profile_id = ? AND task_code = ?', [teamProfileId, head.task_code]);
    }
    return assignments;
  });
}

export function readWorkspaceLlmAssignments(connection, binding) {
  readSelectedCapacityConfiguration(connection, binding);
  const assignments = connection.all(`SELECT assignment.id AS assignmentId, assignment.team_profile_id AS teamProfileId,
    assignment.task_code AS taskCode, assignment.revision, model.id AS modelId, model.provider_code AS providerCode,
    model.model_code AS model, assignment.adapter_code AS adapterCode, assignment.reasoning_effort AS reasoningEffort
    FROM workspace_identity workspace JOIN profile_llm_heads head ON head.team_profile_id = workspace.team_profile_id
    JOIN profile_llm_assignments assignment ON assignment.id = head.assignment_id JOIN llm_models model ON model.id = assignment.model_id
    WHERE workspace.id = 1 ORDER BY assignment.task_code`).map(row => ({ ...row }));
  if (assignments.length === 0) throw new Error('Selected master profile has no current LLM task assignments');
  return assignments;
}
