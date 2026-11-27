import { randomUUID } from 'node:crypto';
import { openWorkbenchSqlite } from './WorkbenchSqlite.mjs';
import { readSelectedCapacityPolicy } from './WorkbenchWorkspace.mjs';
import { requireSourceObject } from './WorkbenchSourceRecords.mjs';
import { workbenchSchemaVersion } from './WorkbenchApplicationSchema.mjs';

const guidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const outcomes = ['started', 'succeeded', 'failed', 'refused', 'cancelled', 'reused'];
const persistenceStates = ['recorded', 'not-recorded', 'uncertain'];
const actions = {
  'start-workbench': ['Start Workbench', 'workbench'],
  'exit-workbench': ['Exit Workbench', 'workbench'],
  assess: ['Assess', 'assessment'],
  reconcile: ['Reconcile', 'reconciliation'],
  adjudicate: ['Adjudicate', 'adjudication'],
};
const categories = { workbench: 'Workbench', assessment: 'Assessment', reconciliation: 'Reconciliation', adjudication: 'Adjudication' };
const factColumns = { requestedPort: 'requested_port', listenerPort: 'listener_port', elapsedMs: 'elapsed_ms',
  stateSaveOutcome: 'state_save_outcome', itemCount: 'item_count', failureCount: 'failure_count' };

export function registerWorkbenchAuditDefinitions(connection) {
  for (const [code, label] of Object.entries(categories)) connection.run('INSERT INTO audit_categories(code, label) VALUES (?, ?)', [code, label]);
  for (const [code, [label]] of Object.entries(actions)) connection.run('INSERT INTO audit_actions(code, label) VALUES (?, ?)', [code, label]);
}

function validateFacts(facts) {
  requireSourceObject(facts, [...Object.keys(factColumns), 'runId'], [], 'Operational audit facts');
  for (const field of ['requestedPort', 'listenerPort', 'elapsedMs', 'itemCount', 'failureCount', 'runId']) {
    if (facts[field] !== undefined && (!Number.isSafeInteger(facts[field]) ||
        facts[field] < (['listenerPort', 'runId'].includes(field) ? 1 : 0))) throw new Error('Invalid numeric operational audit fact');
  }
  if ((facts.requestedPort ?? 0) > 65535 || (facts.listenerPort ?? 1) > 65535 ||
      (facts.stateSaveOutcome !== undefined && !['saved', 'nothing-pending', 'failed', 'unknown'].includes(facts.stateSaveOutcome))) {
    throw new Error('Invalid operational audit outcome facts');
  }
}

// Commit only audit-owned rows; a lost commit acknowledgement must not be reported as a confirmed rollback.
export function recordWorkbenchAudit(connection, { binding, correlationGuid, rootActionCode, actionCode, outcome, rootRequest = false, facts = {} }) {
  if (connection.readOnly || connection.isTransaction) throw new Error('Operational audit requires its own writable transaction');
  if (!guidPattern.test(correlationGuid) || !Object.hasOwn(actions, rootActionCode) || !Object.hasOwn(actions, actionCode) ||
      !outcomes.includes(outcome) || typeof rootRequest !== 'boolean' ||
      (rootRequest && (outcome !== 'started' || rootActionCode !== actionCode))) throw new Error('Invalid operational audit event');
  validateFacts(facts);
  if (connection.get('SELECT max(version) AS version FROM application_migrations')?.version !== workbenchSchemaVersion) {
    throw new Error('Operational audit requires the current application schema');
  }
  readSelectedCapacityPolicy(connection, binding);
  const context = connection.get('SELECT origin_context_id AS id FROM workspace_identity WHERE id = 1');
  const rootAction = connection.get('SELECT id FROM audit_actions WHERE code = ?', [rootActionCode]);
  const action = connection.get('SELECT id FROM audit_actions WHERE code = ?', [actionCode]);
  const category = connection.get('SELECT id FROM audit_categories WHERE code = ?', [actions[actionCode][1]]);
  if (!context?.id || !rootAction || !action || !category) throw new Error('Operational audit requires registered workspace scope, action and category');
  if (facts.runId !== undefined && !connection.get('SELECT run_id FROM analysis_run_contexts WHERE run_id = ? AND workspace_id = 1', [facts.runId])) {
    throw new Error('Operational audit run does not belong to the selected workspace');
  }
  const occurredAt = new Date().toISOString();
  connection.exec('BEGIN IMMEDIATE');
  let committing = false;
  try {
    let actor = connection.get(rootRequest
      ? "SELECT id FROM actors WHERE actor_kind = 'person' AND provider_code = 'local-workbench' AND provider_actor_id = 'operator'"
      : "SELECT id FROM actors WHERE actor_kind = 'system'");
    if (!actor) actor = { id: Number(connection.run(rootRequest
      ? "INSERT INTO actors(actor_kind, provider_code, provider_actor_id, display_name) VALUES ('person', 'local-workbench', 'operator', 'USER')"
      : "INSERT INTO actors(actor_kind, display_name) VALUES ('system', 'SYSTEM')").lastInsertRowid) };
    let correlation;
    if (rootRequest) {
      correlation = { id: Number(connection.run(`INSERT INTO audit_correlations(correlation_guid, action_id, initiated_by_actor_id, repository_context_id, started_at)
        VALUES (?, ?, ?, ?, ?)`, [correlationGuid, rootAction.id, actor.id, context.id, occurredAt]).lastInsertRowid) };
    } else {
      correlation = connection.get('SELECT id FROM audit_correlations WHERE correlation_guid = ? AND action_id = ? AND repository_context_id = ?',
        [correlationGuid, rootAction.id, context.id]);
      if (!correlation) throw new Error('Operational audit correlation was not recorded');
    }
    const summary = actionCode === 'exit-workbench' && outcome === 'succeeded'
      ? 'Workbench listener stopped; Exit did not perform a state save'
      : `${rootRequest ? 'User requested' : actions[actionCode][0]} ${rootRequest ? actions[actionCode][0] : outcome}`;
    const severity = outcome === 'failed' ? 'error' : ['refused', 'cancelled'].includes(outcome) ? 'warning' : 'info';
    const fields = Object.keys(factColumns).filter(field => facts[field] !== undefined);
    const result = connection.run(`INSERT INTO audit_events(actor_id, repository_context_id, severity, action_code, outcome, occurred_at, safe_summary,
      correlation_id, action_id, category_id${fields.map(field => `, ${factColumns[field]}`).join('')})
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?${fields.map(() => ', ?').join('')})`,
    [actor.id, context.id, severity, actionCode, outcome, occurredAt, summary, correlation.id, action.id, category.id, ...fields.map(field => facts[field])]);
    if (facts.runId !== undefined) connection.run("INSERT INTO audit_targets(event_id, target_role, analysis_run_id) VALUES (?, 'subject', ?)",
      [Number(result.lastInsertRowid), facts.runId]);
    committing = true;
    connection.exec('COMMIT');
  } catch (error) {
    const auditPersistence = committing && !connection.isTransaction ? 'uncertain' : 'not-recorded';
    if (connection.isTransaction) {
      try { connection.exec('ROLLBACK'); }
      catch (rollbackError) {
        throw Object.assign(new AggregateError([error, rollbackError], 'Audit rollback could not be confirmed'), { auditPersistence: 'uncertain' });
      }
    }
    throw Object.assign(error, { auditPersistence });
  }
}

// Transient state crosses command boundaries; it is not another persisted workflow or retry queue.
export function createWorkbenchAudit({ databasePath, binding, actionCode, correlationGuid = randomUUID(), context = null }) {
  if (!Object.hasOwn(actions, actionCode)) throw new Error('Operational audit action is not registered');
  const state = context === null ? { correlationGuid, rootActionCode: actionCode, persistence: 'recorded',
    warningIssued: false, activeActionCode: null, activeStartedAt: null, rootStarted: false } : { ...context };
  const fields = ['correlationGuid', 'rootActionCode', 'persistence', 'warningIssued', 'activeActionCode', 'activeStartedAt', 'rootStarted'];
  requireSourceObject(state, fields, fields, 'Operational audit context');
  if (!guidPattern.test(state.correlationGuid) || state.rootActionCode !== actionCode || !persistenceStates.includes(state.persistence) ||
      typeof state.warningIssued !== 'boolean' || typeof state.rootStarted !== 'boolean' ||
      (state.activeActionCode !== null && !Object.hasOwn(actions, state.activeActionCode)) ||
      (state.activeActionCode === null ? state.activeStartedAt !== null : !Number.isSafeInteger(state.activeStartedAt))) {
    throw new Error('Invalid operational audit context');
  }
  const degrade = persistence => {
    if (state.persistence !== 'uncertain' && persistence !== 'recorded') state.persistence = persistence;
  };
  const append = (selectedAction, outcome, rootRequest, facts) => {
    let writer;
    try {
      writer = openWorkbenchSqlite({ mode: 'read-write', databasePath, busyTimeoutMilliseconds: 100 });
      recordWorkbenchAudit(writer, { binding, correlationGuid: state.correlationGuid, rootActionCode: state.rootActionCode,
        actionCode: selectedAction, outcome, rootRequest, facts });
    } catch (error) {
      degrade(error.auditPersistence === 'uncertain' ? 'uncertain' : 'not-recorded');
    } finally {
      if (writer) {
        try { writer.close(); }
        catch { degrade('uncertain'); }
      }
    }
  };
  const start = (selectedAction = actionCode, facts = {}) => {
    if (state.activeActionCode !== null) throw new Error('Complete the active major audit operation before starting another');
    state.activeActionCode = selectedAction;
    state.activeStartedAt = Date.now();
    const rootRequest = !state.rootStarted;
    state.rootStarted = true;
    append(selectedAction, 'started', rootRequest, facts);
  };
  const finish = (outcome, facts = {}) => {
    if (state.activeActionCode === null || !outcomes.includes(outcome) || outcome === 'started') throw new Error('An active major audit operation and terminal outcome are required');
    append(state.activeActionCode, outcome, false, { elapsedMs: Math.max(0, Date.now() - state.activeStartedAt), ...facts });
    state.activeActionCode = null;
    state.activeStartedAt = null;
  };
  return Object.freeze({
    start,
    finish,
    transition(selectedAction, facts = {}) { finish('succeeded', facts); start(selectedAction, facts.runId === undefined ? {} : { runId: facts.runId }); },
    snapshot() { return { ...state }; },
    result() { return { persistence: state.persistence, correlationGuid: state.correlationGuid }; },
    takeWarning() {
      if (state.persistence === 'recorded' || state.warningIssued) return null;
      state.warningIssued = true;
      return { kind: 'audit-warning', code: 'workbench-event-log-incomplete', persistence: state.persistence, correlationGuid: state.correlationGuid };
    },
    async run(operation) {
      try { return await operation(); }
      catch (error) {
        if (state.activeActionCode !== null) finish(error.code === 'workbench-execution-already-running' ? 'refused'
          : error.code === 'workbench-execution-cancelled' ? 'cancelled' : 'failed');
        throw error;
      }
    },
  });
}
