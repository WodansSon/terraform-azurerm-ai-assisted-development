import { createHash } from 'node:crypto';
import { readCurrentProtectedSnapshot, readWorkingCatalogId } from './WorkbenchWorkspace.mjs';
import { requireSourceObject } from './WorkbenchSourceRecords.mjs';

export class WorkbenchChangeError extends Error {
  constructor(code, status = 400) { super(code); this.code = code; this.status = status; }
}

// Apply an optimistic-concurrency-checked membership change and snapshot exact saved revisions into a new Plan version.
export function updatePlanMembership(connection, binding, input) {
  requireSourceObject(input, ['changeId', 'expectedRevisionId', 'expectedPlanVersionId', 'operation', 'action', 'targetRuleVersionId', 'surface', 'sectionHeading'],
    ['changeId', 'expectedRevisionId', 'expectedPlanVersionId', 'operation'], 'Plan membership');
  if (connection.readOnly || connection.isTransaction || !Number.isSafeInteger(input.changeId) || !Number.isSafeInteger(input.expectedRevisionId) ||
      !['add', 'remove'].includes(input.operation) || input.expectedPlanVersionId !== null && !Number.isSafeInteger(input.expectedPlanVersionId)) throw new WorkbenchChangeError('invalid-plan-command');
  connection.exec('BEGIN IMMEDIATE');
  try {
    readCurrentProtectedSnapshot(connection, { databaseGuid: binding.databaseGuid, repositoryId: binding.repositoryId });
    const origin = connection.get(`SELECT context.id, context.branch_ref AS branchRef FROM workspace_identity workspace JOIN repository_contexts context ON context.id = workspace.origin_context_id WHERE workspace.id = 1`);
    if (origin.branchRef !== binding.branchRef) throw new WorkbenchChangeError('workspace-branch-mismatch', 409);
    const catalogId = readWorkingCatalogId(connection);
    if (catalogId === null) throw new WorkbenchChangeError('catalog-baseline-required', 409);
    const plans = connection.all("SELECT plan.id, plan.current_version_id AS versionId, version.base_catalog_id AS catalogId FROM plans plan LEFT JOIN plan_versions version ON version.id = plan.current_version_id WHERE plan.label = 'Promotion Plan'");
    if (plans.length > 1 || (plans[0]?.versionId ?? null) !== input.expectedPlanVersionId || plans[0]?.catalogId && plans[0].catalogId !== catalogId) throw new WorkbenchChangeError('plan-revision-conflict', 409);
    const change = connection.get(`SELECT revision.*, proposal.origin_source_version_id AS sourceVersionId FROM changes change
      JOIN change_revisions revision ON revision.id = change.current_revision_id JOIN proposal_versions proposal ON proposal.id = revision.proposal_version_id WHERE change.id = ?`, [input.changeId]);
    if (!change || change.id !== input.expectedRevisionId) throw new WorkbenchChangeError('saved-revision-conflict', 409);
    const currentSource = connection.get(`SELECT member.source_version_id FROM source_collection_heads head JOIN source_collection_members member ON member.collection_id = head.collection_id
      JOIN source_rules source ON source.id = member.source_rule_id WHERE member.source_version_id = ? AND member.presence = 'present'
      AND NOT EXISTS(SELECT 1 FROM protected_members protected JOIN rules rule ON rule.id = protected.rule_id WHERE rule.displayed_id = source.external_key)`, [change.sourceVersionId]);
    if (!currentSource) throw new WorkbenchChangeError('source-is-not-current-or-is-protected', 409);
    const actor = connection.get("SELECT id FROM actors WHERE provider_code = 'local-workbench' AND provider_actor_id = 'operator'");
    if (!actor) throw new WorkbenchChangeError('saved-local-change-required');
    const now = new Date().toISOString();
    const planId = plans[0]?.id ?? Number(connection.run("INSERT INTO plans(label) VALUES ('Promotion Plan')").lastInsertRowid);
    let revisionId = change.id;
    if (input.operation === 'add') {
      const action = connection.get('SELECT id FROM action_definitions WHERE code = ?', [input.action ?? '']);
      if (!action || !['add', 'update', 'retire', 'restore'].includes(input.action)) throw new WorkbenchChangeError('plan-action-required');
      let target = null;
      if (input.action !== 'add') {
        target = connection.get(`SELECT member.rule_id AS ruleId, version.id, version.lifecycle FROM catalog_members member JOIN rule_versions version ON version.id = member.rule_version_id
          JOIN rules rule ON rule.id = member.rule_id WHERE member.catalog_id = ? AND version.id = ? AND rule.rule_kind = 'managed'`, [catalogId, input.targetRuleVersionId ?? null]);
        if (!target) throw new WorkbenchChangeError('current-managed-target-required');
        if ((input.action === 'restore') !== (target.lifecycle === 'retired')) throw new WorkbenchChangeError('target-lifecycle-conflict', 409);
      } else if (input.targetRuleVersionId !== null && input.targetRuleVersionId !== undefined) throw new WorkbenchChangeError('add-cannot-target-existing-rule');
      let placement = null;
      if (input.action !== 'retire') {
        placement = connection.get(`SELECT content.surface_id AS surfaceId FROM catalog_surface_content content JOIN guidance_surfaces surface ON surface.id = content.surface_id
          JOIN catalog_surface_sections section ON section.catalog_id = content.catalog_id AND section.surface_id = content.surface_id
          WHERE content.catalog_id = ? AND surface.code = ? AND section.heading = ?`, [catalogId, input.surface ?? '', input.sectionHeading ?? '']);
        if (!placement) throw new WorkbenchChangeError('current-catalog-placement-required');
      }
      revisionId = Number(connection.run(`INSERT INTO change_revisions(change_id, proposal_version_id, revision, selected_action_id, target_rule_id,
        baseline_rule_version_id, wording_version_id, rationale, recorded_by_actor_id, recorded_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [change.change_id, change.proposal_version_id, change.revision + 1, action.id, target?.ruleId ?? null, target?.id ?? null,
        change.wording_version_id, change.rationale, actor.id, now]).lastInsertRowid);
      if (placement) connection.run('INSERT INTO change_placements VALUES (?, ?, ?, 0)', [revisionId, placement.surfaceId, input.sectionHeading]);
      connection.run('INSERT INTO change_applicabilities SELECT ?, applicability_id FROM change_applicabilities WHERE change_revision_id = ?', [revisionId, change.id]);
      connection.run('UPDATE changes SET current_revision_id = ? WHERE id = ?', [revisionId, input.changeId]);
      const member = connection.get('SELECT id FROM plan_memberships WHERE plan_id = ? AND change_id = ? AND removed_at IS NULL', [planId, input.changeId]);
      if (!member) connection.run(`INSERT INTO plan_memberships(plan_id, change_id, add_method_id, added_by_actor_id, added_at)
        SELECT ?, ?, id, ?, ? FROM plan_add_methods WHERE code = 'manual'`, [planId, input.changeId, actor.id, now]);
    } else {
      const member = connection.get('SELECT id FROM plan_memberships WHERE plan_id = ? AND change_id = ? AND removed_at IS NULL', [planId, input.changeId]);
      if (!member) throw new WorkbenchChangeError('active-plan-membership-required', 409);
      connection.run('UPDATE plan_memberships SET removed_by_actor_id = ?, removed_at = ? WHERE id = ?', [actor.id, now, member.id]);
    }
    const revision = connection.get('SELECT COALESCE(MAX(revision), 0) + 1 AS value FROM plan_versions WHERE plan_id = ?', [planId]).value;
    const versionId = Number(connection.run('INSERT INTO plan_versions(plan_id, revision, base_catalog_id, recorded_by_actor_id, recorded_at) VALUES (?, ?, ?, ?, ?)', [planId, revision, catalogId, actor.id, now]).lastInsertRowid);
    connection.run(`INSERT INTO plan_items(plan_version_id, membership_id, change_revision_id)
      SELECT ?, member.id, CASE WHEN member.change_id = ? THEN ? ELSE previous.change_revision_id END FROM plan_memberships member
      LEFT JOIN plan_items previous ON previous.plan_version_id = ? AND previous.membership_id = member.id
      WHERE member.plan_id = ? AND member.removed_at IS NULL`, [versionId, input.changeId, revisionId, plans[0]?.versionId ?? null, planId]);
    connection.run('UPDATE plans SET current_version_id = ? WHERE id = ?', [versionId, planId]);
    const auditId = Number(connection.run(`INSERT INTO audit_events(actor_id, repository_context_id, severity, action_code, outcome, occurred_at, safe_summary)
      VALUES (?, ?, 'info', 'plan-membership', 'complete', ?, 'Plan membership changed with an exact immutable revision snapshot')`, [actor.id, origin.id, now]).lastInsertRowid);
    connection.run("INSERT INTO audit_targets(event_id, target_role, plan_version_id) VALUES (?, 'after', ?)", [auditId, versionId]);
    connection.exec('COMMIT');
    return { planId, versionId };
  } catch (error) { if (connection.isTransaction) connection.exec('ROLLBACK'); throw error; }
}

// Append a maintainer edit while preserving its original source baseline, selected action, and dependent metadata.
export function saveSourceChange(connection, binding, input) {
  requireSourceObject(input, ['sourceVersionId', 'expectedRevisionId', 'wording', 'rationale'],
    ['sourceVersionId', 'expectedRevisionId', 'wording', 'rationale'], 'Saved source change');
  if (connection.readOnly || connection.isTransaction) throw new WorkbenchChangeError('invalid-write-connection');
  if (!Number.isSafeInteger(input.sourceVersionId) || input.sourceVersionId < 1 ||
      input.expectedRevisionId !== null && (!Number.isSafeInteger(input.expectedRevisionId) || input.expectedRevisionId < 1) ||
      typeof input.wording !== 'string' || !input.wording.trim() || input.wording.length > 200000 ||
      typeof input.rationale !== 'string' || !input.rationale.trim() || input.rationale.length > 500) throw new WorkbenchChangeError('invalid-source-change');
  connection.exec('BEGIN IMMEDIATE');
  try {
    readCurrentProtectedSnapshot(connection, { databaseGuid: binding.databaseGuid, repositoryId: binding.repositoryId });
    const origin = connection.get(`SELECT context.id, context.branch_ref AS branchRef FROM workspace_identity workspace
      JOIN repository_contexts context ON context.id = workspace.origin_context_id WHERE workspace.id = 1`);
    if (origin.branchRef !== binding.branchRef) throw new WorkbenchChangeError('workspace-branch-mismatch', 409);
    const source = connection.get(`SELECT member.source_rule_id AS sourceRuleId, observation.id AS observationId, observation.rule_text AS ruleText, version.captured_text AS content
      FROM source_collection_heads head JOIN source_collection_members member ON member.collection_id = head.collection_id
      JOIN source_versions version ON version.id = member.source_version_id JOIN source_rules source ON source.id = member.source_rule_id
      JOIN source_observations observation ON observation.id = member.observation_id
      WHERE member.source_version_id = ? AND member.presence = 'present'
      AND NOT EXISTS(SELECT 1 FROM protected_members protected JOIN rules rule ON rule.id = protected.rule_id WHERE rule.displayed_id = source.external_key)`, [input.sourceVersionId]);
    if (!source) throw new WorkbenchChangeError('source-is-not-current-or-is-protected', 409);
    const existing = connection.all(`SELECT change.id AS changeId, change.current_revision_id AS revisionId, proposal.id AS proposalId,
      revision.selected_action_id AS actionId, revision.target_rule_id AS targetRuleId, revision.baseline_rule_version_id AS baselineRuleVersionId
      FROM changes change JOIN change_revisions revision ON revision.id = change.current_revision_id
      JOIN proposal_versions proposal ON proposal.id = revision.proposal_version_id WHERE proposal.origin_source_version_id = ?`, [input.sourceVersionId]);
    if (existing.length > 1 || (existing[0]?.revisionId ?? null) !== input.expectedRevisionId) throw new WorkbenchChangeError('saved-revision-conflict', 409);
    const now = new Date().toISOString();
    let actor = connection.get("SELECT id FROM actors WHERE provider_code = 'local-workbench' AND provider_actor_id = 'operator'");
    if (!actor) actor = { id: Number(connection.run("INSERT INTO actors(actor_kind, provider_code, provider_actor_id, display_name) VALUES ('person', 'local-workbench', 'operator', 'Local operator')").lastInsertRowid) };
    const addWording = text => Number(connection.run('INSERT INTO wording_versions(text, content_sha256, created_at) VALUES (?, ?, ?)',
      [text, createHash('sha256').update(text).digest('hex'), now]).lastInsertRowid);
    let current = existing[0];
    if (!current) {
      const changeId = Number(connection.run('INSERT INTO changes(current_revision_id) VALUES (NULL)').lastInsertRowid);
      const baselineId = connection.get('SELECT COALESCE(MAX(id), 0) + 1 AS id FROM change_revisions').id;
      const proposalId = Number(connection.run(`INSERT INTO proposal_versions(change_id, revision, origin_source_version_id, baseline_revision_id)
        VALUES (?, 1, ?, ?)`, [changeId, input.sourceVersionId, baselineId]).lastInsertRowid);
      const wordingId = addWording(source.ruleText || source.content);
      connection.run(`INSERT INTO change_revisions(id, change_id, proposal_version_id, revision, wording_version_id, rationale, recorded_by_actor_id, recorded_at)
        VALUES (?, ?, ?, 1, ?, 'Captured source baseline', ?, ?)`, [baselineId, changeId, proposalId, wordingId, actor.id, now]);
      connection.run('INSERT INTO change_applicabilities SELECT ?, applicability_id FROM source_observation_applicabilities WHERE observation_id = ?', [baselineId, source.observationId]);
      current = { changeId, proposalId, revisionId: baselineId };
    }
    const wordingId = addWording(input.wording);
    const revision = connection.get('SELECT COALESCE(MAX(revision), 0) + 1 AS value FROM change_revisions WHERE change_id = ?', [current.changeId]).value;
    const revisionId = Number(connection.run(`INSERT INTO change_revisions(change_id, proposal_version_id, revision, wording_version_id,
      rationale, recorded_by_actor_id, recorded_at, selected_action_id, target_rule_id, baseline_rule_version_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`, [current.changeId, current.proposalId, revision, wordingId, input.rationale, actor.id, now,
      current.actionId ?? null, current.targetRuleId ?? null, current.baselineRuleVersionId ?? null]).lastInsertRowid);
    connection.run(`INSERT INTO change_placements SELECT ?, surface_id, section_heading, display_order FROM change_placements WHERE change_revision_id = ?`, [revisionId, current.revisionId]);
    connection.run(`INSERT INTO change_retirements SELECT ?, retired_rule_version_id FROM change_retirements WHERE change_revision_id = ?`, [revisionId, current.revisionId]);
    connection.run(`INSERT INTO change_applicabilities SELECT ?, applicability_id FROM change_applicabilities WHERE change_revision_id = ?`, [revisionId, current.revisionId]);
    connection.run('UPDATE changes SET current_revision_id = ? WHERE id = ?', [revisionId, current.changeId]);
    const auditId = Number(connection.run(`INSERT INTO audit_events(actor_id, repository_context_id, severity, action_code, outcome, occurred_at, safe_summary)
      VALUES (?, ?, 'info', 'save-source-change', 'complete', ?, 'Source proposal saved as an immutable SQL revision')`, [actor.id, origin.id, now]).lastInsertRowid);
    connection.run("INSERT INTO audit_targets(event_id, target_role, change_revision_id) VALUES (?, 'after', ?)", [auditId, revisionId]);
    connection.exec('COMMIT');
    return { changeId: current.changeId, revisionId };
  } catch (error) {
    if (connection.isTransaction) connection.exec('ROLLBACK');
    throw error;
  }
}
