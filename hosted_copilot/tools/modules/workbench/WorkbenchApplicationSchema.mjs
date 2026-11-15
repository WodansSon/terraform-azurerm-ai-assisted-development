import { createHash } from 'node:crypto';
import { openWorkbenchSqlite } from './WorkbenchSqlite.mjs';
import { createSourceIngestionSchema } from './WorkbenchSourceIngestion.mjs';
import { createProtectedSnapshotSchema } from './WorkbenchProtectedSnapshots.mjs';
import { createWorkspaceIdentitySchema } from './WorkbenchWorkspace.mjs';
import { createAuthoredAuditSchema } from './WorkbenchAuthoredRefresh.mjs';

export const workbenchSchemaVersion = 13;

// Give each finding participant exactly one typed subject reference and a stable display order.
function findingParticipantsDdl() {
  return `CREATE TABLE finding_participants (
    id INTEGER PRIMARY KEY, finding_id INTEGER NOT NULL REFERENCES findings(id), participant_role TEXT NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal >= 0),
    review_subject_id INTEGER REFERENCES review_subjects(id), assessment_result_id INTEGER REFERENCES assessment_results(id), group_version_id INTEGER REFERENCES group_versions(id),
    evidence_quote TEXT, rule_version_id INTEGER REFERENCES rule_versions(id), CHECK((review_subject_id IS NOT NULL) + (assessment_result_id IS NOT NULL) + (group_version_id IS NOT NULL) + (rule_version_id IS NOT NULL) = 1), UNIQUE(finding_id, ordinal)
  ) STRICT`;
}

// Define the core relational model; dependent ingestion, workspace, and audit schemas are composed separately.
const applicationDdl = () => `
  CREATE TABLE application_migrations (
    version INTEGER PRIMARY KEY CHECK(version > 0), applied_at TEXT NOT NULL
  ) STRICT;
  CREATE TABLE team_profiles (
    id INTEGER PRIMARY KEY, code TEXT NOT NULL UNIQUE, label TEXT NOT NULL,
    capacity_policy_id INTEGER NOT NULL REFERENCES capacity_policies(id)
  ) STRICT;
  CREATE TABLE repositories (
    id INTEGER PRIMARY KEY, provider_code TEXT NOT NULL, provider_repository_id TEXT, canonical_name TEXT NOT NULL,
    UNIQUE(provider_code, canonical_name)
  ) STRICT;
  CREATE TABLE repository_contexts (
    id INTEGER PRIMARY KEY, repository_id INTEGER NOT NULL REFERENCES repositories(id), branch_ref TEXT NOT NULL,
    commit_oid TEXT NOT NULL CHECK(length(commit_oid) = 40 AND commit_oid NOT GLOB '*[^0-9a-f]*'), observed_at TEXT NOT NULL
  ) STRICT;
  CREATE TABLE actors (
    id INTEGER PRIMARY KEY, actor_kind TEXT NOT NULL CHECK(actor_kind IN ('person', 'system')),
    provider_code TEXT, provider_actor_id TEXT, display_name TEXT NOT NULL,
    CHECK((actor_kind = 'system' AND provider_code IS NULL AND provider_actor_id IS NULL)
      OR (actor_kind = 'person' AND provider_code IS NOT NULL AND provider_actor_id IS NOT NULL)),
    UNIQUE(provider_code, provider_actor_id)
  ) STRICT;
  CREATE TABLE action_definitions (
    id INTEGER PRIMARY KEY, code TEXT NOT NULL UNIQUE CHECK(code IN ('add', 'update', 'retire', 'restore', 'no-change', 'exclude', 'defer')), label TEXT NOT NULL
  ) STRICT;
  CREATE TABLE workflow_status_definitions (
    id INTEGER PRIMARY KEY, dimension TEXT NOT NULL, code TEXT NOT NULL, label TEXT NOT NULL, description TEXT NOT NULL, UNIQUE(dimension, code)
  ) STRICT;
  CREATE TABLE rule_id_schemes (
    id INTEGER PRIMARY KEY, scheme_code TEXT NOT NULL, revision INTEGER NOT NULL CHECK(revision > 0), prefix TEXT NOT NULL,
    separator TEXT NOT NULL, numeric_width INTEGER NOT NULL CHECK(numeric_width > 0), UNIQUE(scheme_code, revision)
  ) STRICT;
  CREATE TABLE rule_id_counters (
    scheme_id INTEGER PRIMARY KEY REFERENCES rule_id_schemes(id), next_value INTEGER NOT NULL CHECK(next_value > 0)
  ) STRICT;
  CREATE TABLE guidance_surfaces (
    id INTEGER PRIMARY KEY, code TEXT NOT NULL UNIQUE, revision INTEGER NOT NULL CHECK(revision > 0), label TEXT NOT NULL,
    output_relative_path TEXT NOT NULL UNIQUE, renderer_code TEXT NOT NULL
  ) STRICT;
  CREATE TABLE surface_patterns (
    surface_id INTEGER NOT NULL REFERENCES guidance_surfaces(id), pattern TEXT NOT NULL, PRIMARY KEY(surface_id, pattern)
  ) STRICT;
  CREATE TABLE guidance_surface_content (
    surface_id INTEGER PRIMARY KEY REFERENCES guidance_surfaces(id), description TEXT NOT NULL, title TEXT NOT NULL,
    introduction TEXT NOT NULL, closing_text TEXT NOT NULL
  ) STRICT;
  CREATE TABLE guidance_sections (
    surface_id INTEGER NOT NULL REFERENCES guidance_surfaces(id), ordinal INTEGER NOT NULL CHECK(ordinal >= 0), heading TEXT NOT NULL,
    PRIMARY KEY(surface_id, ordinal), UNIQUE(surface_id, heading)
  ) STRICT;
  CREATE TABLE applicability_definitions (
    id INTEGER PRIMARY KEY, code TEXT NOT NULL UNIQUE, label TEXT NOT NULL, renderer_code TEXT NOT NULL
  ) STRICT;
  CREATE TABLE evaluator_profiles (
    id INTEGER PRIMARY KEY, code TEXT NOT NULL, revision INTEGER NOT NULL CHECK(revision > 0), task_code TEXT NOT NULL,
    llm_assignment_id INTEGER NOT NULL, prompt_sha256 TEXT NOT NULL,
    behavior_sha256 TEXT NOT NULL, result_contract_sha256 TEXT NOT NULL, UNIQUE(code, revision),
    FOREIGN KEY(llm_assignment_id, task_code) REFERENCES profile_llm_assignments(id, task_code)
  ) STRICT;
  CREATE TABLE llm_models (
    id INTEGER PRIMARY KEY, provider_code TEXT NOT NULL, model_code TEXT NOT NULL,
    UNIQUE(provider_code, model_code)
  ) STRICT;
  CREATE TABLE profile_llm_assignments (
    id INTEGER PRIMARY KEY, team_profile_id INTEGER NOT NULL REFERENCES team_profiles(id), task_code TEXT NOT NULL,
    revision INTEGER NOT NULL CHECK(revision > 0), model_id INTEGER NOT NULL REFERENCES llm_models(id),
    adapter_code TEXT NOT NULL, reasoning_effort TEXT NOT NULL CHECK(reasoning_effort IN ('low', 'medium', 'high', 'xhigh')),
    UNIQUE(team_profile_id, task_code, revision), UNIQUE(id, task_code), UNIQUE(id, team_profile_id, task_code)
  ) STRICT;
  CREATE TABLE profile_llm_heads (
    team_profile_id INTEGER NOT NULL REFERENCES team_profiles(id), task_code TEXT NOT NULL, assignment_id INTEGER NOT NULL,
    PRIMARY KEY(team_profile_id, task_code),
    FOREIGN KEY(assignment_id, team_profile_id, task_code) REFERENCES profile_llm_assignments(id, team_profile_id, task_code)
  ) STRICT;
  CREATE TABLE analysis_runs (
    id INTEGER PRIMARY KEY, requested_by_actor_id INTEGER NOT NULL REFERENCES actors(id), requested_at TEXT NOT NULL,
    force_requested INTEGER NOT NULL CHECK(force_requested IN (0, 1)), outcome TEXT NOT NULL CHECK(outcome IN ('running', 'complete', 'failed', 'cancelled')),
    completed_at TEXT,
    CHECK((outcome = 'running') = (completed_at IS NULL))
  ) STRICT;
  CREATE TABLE evaluations (
    id INTEGER PRIMARY KEY, evaluator_profile_id INTEGER NOT NULL REFERENCES evaluator_profiles(id), input_fingerprint TEXT NOT NULL,
    requested_at TEXT NOT NULL, completed_at TEXT, outcome TEXT NOT NULL CHECK(outcome IN ('running', 'complete', 'failed', 'cancelled')), failure_code TEXT,
    failure_stage TEXT CHECK(failure_stage IN ('request', 'evaluate', 'commit')),
    failure_reason TEXT CHECK(length(failure_reason) BETWEEN 1 AND 512),
    failure_path TEXT CHECK(length(failure_path) BETWEEN 1 AND 256),
    CHECK((outcome = 'running') = (completed_at IS NULL)), CHECK(outcome <> 'complete' OR failure_code IS NULL)
  ) STRICT;
  CREATE TABLE analysis_run_contexts (
    run_id INTEGER PRIMARY KEY REFERENCES analysis_runs(id), workspace_id INTEGER NOT NULL REFERENCES workspace_identity(id),
    protected_snapshot_id INTEGER NOT NULL REFERENCES protected_snapshots(id), base_catalog_id INTEGER REFERENCES catalog_versions(id),
    scoring_policy_id INTEGER NOT NULL REFERENCES scoring_policies(id), capacity_policy_id INTEGER NOT NULL REFERENCES capacity_policies(id),
    team_profile_id INTEGER NOT NULL REFERENCES team_profiles(id), UNIQUE(run_id, team_profile_id)
  ) STRICT;
  CREATE TABLE analysis_run_llm_assignments (
    run_id INTEGER NOT NULL, team_profile_id INTEGER NOT NULL, task_code TEXT NOT NULL, assignment_id INTEGER NOT NULL,
    PRIMARY KEY(run_id, task_code),
    FOREIGN KEY(run_id, team_profile_id) REFERENCES analysis_run_contexts(run_id, team_profile_id),
    FOREIGN KEY(assignment_id, team_profile_id, task_code) REFERENCES profile_llm_assignments(id, team_profile_id, task_code)
  ) STRICT;
  CREATE INDEX evaluation_reuse ON evaluations(evaluator_profile_id, outcome, input_fingerprint);
  CREATE TABLE run_evaluations (
    run_id INTEGER NOT NULL REFERENCES analysis_runs(id), evaluation_id INTEGER NOT NULL REFERENCES evaluations(id),
    use_kind TEXT NOT NULL CHECK(use_kind IN ('executed', 'reused')), PRIMARY KEY(run_id, evaluation_id)
  ) STRICT;
  CREATE TABLE scoring_policies (
    id INTEGER PRIMARY KEY, code TEXT NOT NULL, revision INTEGER NOT NULL CHECK(revision > 0), minimum_total INTEGER NOT NULL, UNIQUE(code, revision)
  ) STRICT;
  CREATE TABLE scoring_factors (
    id INTEGER PRIMARY KEY, policy_id INTEGER NOT NULL REFERENCES scoring_policies(id), code TEXT NOT NULL, label TEXT NOT NULL, description TEXT NOT NULL,
    minimum_value INTEGER NOT NULL, maximum_value INTEGER NOT NULL, weight INTEGER NOT NULL CHECK(weight >= 0),
    contribution_kind TEXT NOT NULL CHECK(contribution_kind IN ('value', 'risk')), CHECK(minimum_value <= maximum_value), UNIQUE(policy_id, code), UNIQUE(id, policy_id)
  ) STRICT;
  CREATE TABLE priority_bands (
    id INTEGER PRIMARY KEY, policy_id INTEGER NOT NULL REFERENCES scoring_policies(id), code TEXT NOT NULL, label TEXT NOT NULL,
    minimum_score INTEGER NOT NULL, maximum_score INTEGER, CHECK(maximum_score IS NULL OR maximum_score >= minimum_score), UNIQUE(policy_id, code)
  ) STRICT;
  CREATE TABLE scorecards (id INTEGER PRIMARY KEY, policy_id INTEGER NOT NULL REFERENCES scoring_policies(id), selection_rationale TEXT NOT NULL) STRICT;
  CREATE TABLE scorecard_values (
    scorecard_id INTEGER NOT NULL REFERENCES scorecards(id), factor_id INTEGER NOT NULL REFERENCES scoring_factors(id), value INTEGER NOT NULL,
    PRIMARY KEY(scorecard_id, factor_id)
  ) STRICT;
  CREATE TABLE wording_versions (id INTEGER PRIMARY KEY, text TEXT NOT NULL, content_sha256 TEXT NOT NULL, created_at TEXT NOT NULL) STRICT;
  CREATE TABLE rules (
    id INTEGER PRIMARY KEY, displayed_id TEXT NOT NULL UNIQUE, rule_kind TEXT NOT NULL CHECK(rule_kind IN ('managed', 'protected')),
    naming_scheme_id INTEGER REFERENCES rule_id_schemes(id)
  ) STRICT;
  CREATE TABLE rule_versions (
    id INTEGER PRIMARY KEY, rule_id INTEGER NOT NULL REFERENCES rules(id), revision INTEGER NOT NULL CHECK(revision > 0),
    wording_version_id INTEGER NOT NULL REFERENCES wording_versions(id), lifecycle TEXT NOT NULL CHECK(lifecycle IN ('active', 'retired')),
    retirement_reason TEXT, origin_code TEXT, documentation_gap INTEGER CHECK(documentation_gap IN (0, 1)),
    CHECK(lifecycle <> 'active' OR retirement_reason IS NULL), UNIQUE(rule_id, revision), UNIQUE(rule_id, id)
  ) STRICT;
  CREATE TABLE rule_provenances (
    rule_version_id INTEGER NOT NULL REFERENCES rule_versions(id), ordinal INTEGER NOT NULL CHECK(ordinal >= 0), code TEXT NOT NULL,
    PRIMARY KEY(rule_version_id, ordinal), UNIQUE(rule_version_id, code)
  ) STRICT;
  CREATE TABLE rule_placements (
    rule_version_id INTEGER NOT NULL REFERENCES rule_versions(id), surface_id INTEGER NOT NULL REFERENCES guidance_surfaces(id),
    section_heading TEXT NOT NULL, display_order INTEGER NOT NULL CHECK(display_order >= 0), PRIMARY KEY(rule_version_id, surface_id, section_heading)
  ) STRICT;
  CREATE TABLE rule_applicabilities (
    rule_version_id INTEGER NOT NULL REFERENCES rule_versions(id), applicability_id INTEGER NOT NULL REFERENCES applicability_definitions(id),
    PRIMARY KEY(rule_version_id, applicability_id)
  ) STRICT;
  CREATE TABLE catalog_versions (
    id INTEGER PRIMARY KEY, parent_catalog_id INTEGER REFERENCES catalog_versions(id), protected_snapshot_id INTEGER NOT NULL REFERENCES protected_snapshots(id),
    capture_kind TEXT NOT NULL DEFAULT 'managed-catalog' CHECK(capture_kind IN ('managed-catalog', 'manual-guidance', 'initial-rules')),
    revision INTEGER NOT NULL UNIQUE CHECK(revision > 0), input_schema_version INTEGER NOT NULL CHECK(input_schema_version > 0), last_semantic_review TEXT,
    upstream_repository_id INTEGER REFERENCES repositories(id), upstream_baseline_commit TEXT, upstream_current_ref TEXT,
    default_requirement_level TEXT NOT NULL, default_enforcement_method TEXT NOT NULL, default_documentation_gap INTEGER NOT NULL CHECK(default_documentation_gap IN (0, 1)),
    content_fingerprint TEXT NOT NULL, created_at TEXT NOT NULL, finalized_at TEXT, UNIQUE(id, parent_catalog_id), CHECK(parent_catalog_id IS NULL OR parent_catalog_id <> id),
    CHECK((capture_kind IN ('manual-guidance', 'initial-rules') AND last_semantic_review IS NULL AND upstream_repository_id IS NULL AND upstream_baseline_commit IS NULL AND upstream_current_ref IS NULL)
      OR (capture_kind = 'managed-catalog' AND last_semantic_review IS NOT NULL AND upstream_repository_id IS NOT NULL AND upstream_baseline_commit IS NOT NULL AND upstream_current_ref IS NOT NULL))
  ) STRICT;
  CREATE TABLE catalog_members (
    catalog_id INTEGER NOT NULL REFERENCES catalog_versions(id), rule_id INTEGER NOT NULL REFERENCES rules(id), rule_version_id INTEGER NOT NULL,
    PRIMARY KEY(catalog_id, rule_id), FOREIGN KEY(rule_id, rule_version_id) REFERENCES rule_versions(rule_id, id)
  ) STRICT;
  CREATE TABLE catalog_surface_content (
    catalog_id INTEGER NOT NULL REFERENCES catalog_versions(id), surface_id INTEGER NOT NULL REFERENCES guidance_surfaces(id),
    description TEXT NOT NULL, title TEXT NOT NULL, introduction TEXT NOT NULL, closing_text TEXT NOT NULL,
    PRIMARY KEY(catalog_id, surface_id)
  ) STRICT;
  CREATE TABLE catalog_surface_sections (
    catalog_id INTEGER NOT NULL, surface_id INTEGER NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal >= 0), heading TEXT NOT NULL,
    PRIMARY KEY(catalog_id, surface_id, ordinal), UNIQUE(catalog_id, surface_id, heading),
    FOREIGN KEY(catalog_id, surface_id) REFERENCES catalog_surface_content(catalog_id, surface_id)
  ) STRICT;
  CREATE TABLE catalog_canonical_bindings (
    catalog_id INTEGER NOT NULL, rule_id INTEGER NOT NULL, source_rule_id INTEGER NOT NULL REFERENCES source_rules(id), assessment_local_key TEXT,
    PRIMARY KEY(catalog_id, rule_id), FOREIGN KEY(catalog_id, rule_id) REFERENCES catalog_members(catalog_id, rule_id)
  ) STRICT;
  CREATE TABLE catalog_sources (
    catalog_id INTEGER NOT NULL REFERENCES catalog_versions(id), code TEXT NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal >= 0), title TEXT NOT NULL,
    raw_url TEXT NOT NULL, reference_url TEXT NOT NULL, baseline_sha256 TEXT NOT NULL, PRIMARY KEY(catalog_id, code), UNIQUE(catalog_id, ordinal)
  ) STRICT;
  CREATE TABLE catalog_evidence (
    catalog_id INTEGER NOT NULL REFERENCES catalog_versions(id), code TEXT NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal >= 0), evidence_kind TEXT NOT NULL,
    description TEXT NOT NULL, reference TEXT NOT NULL, PRIMARY KEY(catalog_id, code), UNIQUE(catalog_id, ordinal)
  ) STRICT;
  CREATE TABLE catalog_member_sources (
    catalog_id INTEGER NOT NULL, rule_id INTEGER NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal >= 0), source_code TEXT NOT NULL,
    PRIMARY KEY(catalog_id, rule_id, ordinal), UNIQUE(catalog_id, rule_id, source_code),
    FOREIGN KEY(catalog_id, rule_id) REFERENCES catalog_members(catalog_id, rule_id), FOREIGN KEY(catalog_id, source_code) REFERENCES catalog_sources(catalog_id, code)
  ) STRICT;
  CREATE TABLE catalog_member_evidence (
    catalog_id INTEGER NOT NULL, rule_id INTEGER NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal >= 0), evidence_code TEXT NOT NULL,
    PRIMARY KEY(catalog_id, rule_id, ordinal), UNIQUE(catalog_id, rule_id, evidence_code),
    FOREIGN KEY(catalog_id, rule_id) REFERENCES catalog_members(catalog_id, rule_id), FOREIGN KEY(catalog_id, evidence_code) REFERENCES catalog_evidence(catalog_id, code)
  ) STRICT;
  CREATE TABLE workspace_publication (
    workspace_id INTEGER PRIMARY KEY REFERENCES workspace_identity(id) CHECK(workspace_id = 1), current_catalog_id INTEGER NOT NULL REFERENCES catalog_versions(id)
  ) STRICT;
  CREATE TABLE workspace_staging (
    workspace_id INTEGER PRIMARY KEY REFERENCES workspace_identity(id) CHECK(workspace_id = 1), current_catalog_id INTEGER NOT NULL REFERENCES catalog_versions(id)
  ) STRICT;
  CREATE TABLE catalog_guidance_files (
    catalog_id INTEGER NOT NULL REFERENCES catalog_versions(id), relative_path TEXT NOT NULL, role_code TEXT NOT NULL CHECK(role_code IN ('instructions', 'repository', 'skill', 'baseline')),
    surface_id INTEGER REFERENCES guidance_surfaces(id), content_sha256 TEXT NOT NULL, content TEXT NOT NULL,
    PRIMARY KEY(catalog_id, relative_path), CHECK((role_code = 'instructions') = (surface_id IS NOT NULL))
  ) STRICT;
  CREATE TABLE catalog_rule_guidance (
    catalog_id INTEGER NOT NULL, rule_id INTEGER NOT NULL, relative_path TEXT NOT NULL, source_line INTEGER CHECK(source_line > 0),
    source_pointer TEXT CHECK(length(source_pointer) > 0 AND substr(source_pointer, 1, 1) = '/'),
    CHECK((source_line IS NOT NULL) + (source_pointer IS NOT NULL) = 1),
    PRIMARY KEY(catalog_id, rule_id), FOREIGN KEY(catalog_id, rule_id) REFERENCES catalog_members(catalog_id, rule_id),
    FOREIGN KEY(catalog_id, relative_path) REFERENCES catalog_guidance_files(catalog_id, relative_path)
  ) STRICT;
  CREATE TABLE workspace_analysis_head (
    workspace_id INTEGER PRIMARY KEY REFERENCES workspace_identity(id) CHECK(workspace_id = 1), run_id INTEGER NOT NULL REFERENCES analysis_runs(id)
  ) STRICT;
  CREATE TABLE assessment_results (
    id INTEGER PRIMARY KEY, evaluation_id INTEGER NOT NULL REFERENCES evaluations(id), source_version_id INTEGER NOT NULL REFERENCES source_versions(id),
    local_result_key TEXT NOT NULL, title TEXT NOT NULL, source_meaning TEXT NOT NULL, impact_description TEXT NOT NULL,
    hosted_applicable INTEGER NOT NULL CHECK(hosted_applicable IN (0, 1)), applicability_rationale TEXT NOT NULL,
    confidence_level TEXT NOT NULL CHECK(confidence_level IN ('low', 'medium', 'high')), confidence_rationale TEXT NOT NULL,
    existing_coverage_score INTEGER NOT NULL CHECK(existing_coverage_score BETWEEN 0 AND 5), existing_coverage_rationale TEXT NOT NULL,
    scorecard_id INTEGER NOT NULL REFERENCES scorecards(id), UNIQUE(evaluation_id, source_version_id, local_result_key)
  ) STRICT;
  CREATE TABLE assessment_uncertainties (
    assessment_id INTEGER NOT NULL REFERENCES assessment_results(id), ordinal INTEGER NOT NULL CHECK(ordinal >= 0), description TEXT NOT NULL, PRIMARY KEY(assessment_id, ordinal)
  ) STRICT;
  CREATE TABLE assessment_surfaces (
    assessment_id INTEGER NOT NULL REFERENCES assessment_results(id), surface_id INTEGER NOT NULL REFERENCES guidance_surfaces(id), PRIMARY KEY(assessment_id, surface_id)
  ) STRICT;
  CREATE TABLE assessment_category_proposals (
    assessment_id INTEGER NOT NULL REFERENCES assessment_results(id), ordinal INTEGER NOT NULL CHECK(ordinal >= 0), proposed_code TEXT NOT NULL,
    PRIMARY KEY(assessment_id, ordinal)
  ) STRICT;
  CREATE TABLE assessment_catalog_links (
    assessment_id INTEGER NOT NULL REFERENCES assessment_results(id), rule_version_id INTEGER NOT NULL REFERENCES rule_versions(id),
    relationship_code TEXT NOT NULL, rationale TEXT NOT NULL, suggested_wording_id INTEGER REFERENCES wording_versions(id), PRIMARY KEY(assessment_id, rule_version_id)
  ) STRICT;
  CREATE TABLE semantic_groups (id INTEGER PRIMARY KEY, created_at TEXT NOT NULL) STRICT;
  CREATE TABLE group_versions (
    id INTEGER PRIMARY KEY, group_id INTEGER REFERENCES semantic_groups(id), revision INTEGER NOT NULL CHECK(revision > 0),
    synthesis_evaluation_id INTEGER NOT NULL REFERENCES evaluations(id), suggested_wording_id INTEGER NOT NULL REFERENCES wording_versions(id),
    scorecard_id INTEGER NOT NULL REFERENCES scorecards(id), title TEXT NOT NULL, semantic_summary TEXT NOT NULL, synthesis_rationale TEXT NOT NULL,
    review_state TEXT NOT NULL CHECK(review_state IN ('recommended', 'excluded', 'deferred')), needs_review INTEGER NOT NULL CHECK(needs_review IN (0, 1)),
    continuity_kind TEXT NOT NULL CHECK(continuity_kind IN ('new', 'equivalent', 'material-change', 'split', 'merge', 'unresolved')),
    continuity_confidence TEXT NOT NULL CHECK(continuity_confidence IN ('high', 'medium', 'low')), continuity_rationale TEXT NOT NULL,
    CHECK((continuity_kind = 'unresolved') = (group_id IS NULL)),
    CHECK(group_id IS NOT NULL OR (review_state = 'deferred' AND needs_review = 1)),
    CHECK(continuity_kind IN ('new', 'unresolved') OR continuity_confidence = 'high'), UNIQUE(group_id, revision)
  ) STRICT;
  CREATE TABLE group_members (
    group_version_id INTEGER NOT NULL REFERENCES group_versions(id), assessment_result_id INTEGER NOT NULL REFERENCES assessment_results(id),
    member_role TEXT NOT NULL CHECK(member_role IN ('primary', 'supporting')), meaning_coverage_rationale TEXT NOT NULL, PRIMARY KEY(group_version_id, assessment_result_id)
  ) STRICT;
  CREATE TABLE group_catalog_anchors (
    group_version_id INTEGER NOT NULL REFERENCES group_versions(id), rule_version_id INTEGER NOT NULL REFERENCES rule_versions(id),
    relationship_code TEXT NOT NULL, rationale TEXT NOT NULL, suggested_wording_id INTEGER REFERENCES wording_versions(id), PRIMARY KEY(group_version_id, rule_version_id)
  ) STRICT;
  CREATE TABLE group_relationships (
    id INTEGER PRIMARY KEY, group_version_id INTEGER NOT NULL REFERENCES group_versions(id),
    target_assessment_id INTEGER REFERENCES assessment_results(id), target_rule_version_id INTEGER REFERENCES rule_versions(id),
    relationship_code TEXT NOT NULL CHECK(relationship_code IN ('equivalent', 'partial-overlap', 'left-extends-right', 'left-narrows-right', 'conflicts')),
    rationale TEXT NOT NULL,
    evidence_origin TEXT NOT NULL CHECK(evidence_origin = 'reconciliation'),
    CHECK((target_assessment_id IS NOT NULL) + (target_rule_version_id IS NOT NULL) = 1)
  ) STRICT;
  CREATE UNIQUE INDEX group_relationship_assessment ON group_relationships(group_version_id, target_assessment_id) WHERE target_assessment_id IS NOT NULL;
  CREATE UNIQUE INDEX group_relationship_rule ON group_relationships(group_version_id, target_rule_version_id) WHERE target_rule_version_id IS NOT NULL;
  CREATE TABLE group_relationship_evidence (
    relationship_id INTEGER NOT NULL REFERENCES group_relationships(id),
    ordinal INTEGER NOT NULL CHECK(ordinal >= 0),
    source_assessment_id INTEGER NOT NULL REFERENCES assessment_results(id),
    source_quote TEXT NOT NULL CHECK(length(trim(source_quote)) > 0 AND length(source_quote) <= 2000),
    target_quote TEXT NOT NULL CHECK(length(trim(target_quote)) > 0 AND length(target_quote) <= 2000),
    PRIMARY KEY(relationship_id, ordinal), UNIQUE(relationship_id, source_assessment_id)
  ) STRICT;
  CREATE TABLE group_correspondences (
    id INTEGER PRIMARY KEY, prior_group_version_id INTEGER NOT NULL REFERENCES group_versions(id), next_group_version_id INTEGER NOT NULL REFERENCES group_versions(id),
    correspondence_kind TEXT NOT NULL CHECK(correspondence_kind IN ('equivalent', 'split', 'merge', 'material-change', 'unresolved')), rationale TEXT NOT NULL,
    evaluation_id INTEGER REFERENCES evaluations(id), recorded_by_actor_id INTEGER REFERENCES actors(id), recorded_at TEXT NOT NULL,
    confidence_level TEXT CHECK(confidence_level IN ('high', 'medium', 'low')),
    CHECK(prior_group_version_id <> next_group_version_id), CHECK(evaluation_id IS NOT NULL OR recorded_by_actor_id IS NOT NULL),
    CHECK(evaluation_id IS NULL OR confidence_level IS NOT NULL)
  ) STRICT;
  CREATE TABLE group_correspondence_members (
    correspondence_id INTEGER NOT NULL REFERENCES group_correspondences(id),
    assessment_result_id INTEGER NOT NULL REFERENCES assessment_results(id),
    prior_assessment_result_id INTEGER NOT NULL REFERENCES assessment_results(id),
    current_evidence_quote TEXT NOT NULL, prior_evidence_quote TEXT NOT NULL, rationale TEXT NOT NULL,
    PRIMARY KEY(correspondence_id, assessment_result_id, prior_assessment_result_id)
  ) STRICT;
  CREATE TABLE recommended_changes (
    id INTEGER PRIMARY KEY, group_version_id INTEGER NOT NULL REFERENCES group_versions(id), ordinal INTEGER NOT NULL CHECK(ordinal >= 0),
    operation_role TEXT NOT NULL CHECK(operation_role IN ('primary', 'ancillary')), action_id INTEGER NOT NULL REFERENCES action_definitions(id),
    target_rule_version_id INTEGER REFERENCES rule_versions(id), wording_version_id INTEGER REFERENCES wording_versions(id),
    surface_id INTEGER REFERENCES guidance_surfaces(id), section_heading TEXT, rationale TEXT NOT NULL,
    proposed_rule_id INTEGER REFERENCES rules(id), implementation_models_defined INTEGER NOT NULL DEFAULT 0 CHECK(implementation_models_defined IN (0, 1)), UNIQUE(group_version_id, ordinal)
  ) STRICT;
  CREATE TABLE recommended_change_provenances (
    recommended_change_id INTEGER NOT NULL REFERENCES recommended_changes(id), ordinal INTEGER NOT NULL CHECK(ordinal >= 0), code TEXT NOT NULL,
    PRIMARY KEY(recommended_change_id, ordinal), UNIQUE(recommended_change_id, code)
  ) STRICT;
  CREATE TABLE recommended_change_evidence (
    recommended_change_id INTEGER NOT NULL REFERENCES recommended_changes(id), catalog_id INTEGER NOT NULL, evidence_code TEXT NOT NULL,
    ordinal INTEGER NOT NULL CHECK(ordinal >= 0), PRIMARY KEY(recommended_change_id, ordinal),
    FOREIGN KEY(catalog_id, evidence_code) REFERENCES catalog_evidence(catalog_id, code)
  ) STRICT;
  CREATE TABLE recommended_change_applicabilities (
    recommended_change_id INTEGER NOT NULL REFERENCES recommended_changes(id), applicability_id INTEGER NOT NULL REFERENCES applicability_definitions(id),
    PRIMARY KEY(recommended_change_id, applicability_id)
  ) STRICT;
  CREATE UNIQUE INDEX group_one_primary ON recommended_changes(group_version_id) WHERE operation_role = 'primary';
  CREATE TABLE reconciliation_dispositions (
    run_id INTEGER NOT NULL REFERENCES analysis_runs(id), assessment_result_id INTEGER NOT NULL REFERENCES assessment_results(id),
    disposition_code TEXT NOT NULL CHECK(disposition_code IN ('grouped', 'deferred', 'excluded')), rationale TEXT NOT NULL, PRIMARY KEY(run_id, assessment_result_id)
  ) STRICT;
  CREATE TABLE accepted_group_evidence (
    catalog_id INTEGER NOT NULL, rule_id INTEGER NOT NULL, group_version_id INTEGER NOT NULL REFERENCES group_versions(id),
    PRIMARY KEY(catalog_id, rule_id, group_version_id), FOREIGN KEY(catalog_id, rule_id) REFERENCES catalog_members(catalog_id, rule_id)
  ) STRICT;
  CREATE TABLE changes (
    id INTEGER PRIMARY KEY, current_revision_id INTEGER REFERENCES change_revisions(id) DEFERRABLE INITIALLY DEFERRED,
    FOREIGN KEY(id, current_revision_id) REFERENCES change_revisions(change_id, id) DEFERRABLE INITIALLY DEFERRED
  ) STRICT;
  CREATE TABLE proposal_versions (
    id INTEGER PRIMARY KEY, change_id INTEGER NOT NULL REFERENCES changes(id), revision INTEGER NOT NULL CHECK(revision > 0),
    origin_group_version_id INTEGER REFERENCES group_versions(id), origin_source_version_id INTEGER REFERENCES source_versions(id),
    baseline_revision_id INTEGER NOT NULL REFERENCES change_revisions(id) DEFERRABLE INITIALLY DEFERRED,
    UNIQUE(change_id, revision), UNIQUE(change_id, id),
    FOREIGN KEY(change_id, id, baseline_revision_id) REFERENCES change_revisions(change_id, proposal_version_id, id) DEFERRABLE INITIALLY DEFERRED
  ) STRICT;
  CREATE TABLE change_revisions (
    id INTEGER PRIMARY KEY, change_id INTEGER NOT NULL REFERENCES changes(id), proposal_version_id INTEGER NOT NULL,
    revision INTEGER NOT NULL CHECK(revision > 0), selected_action_id INTEGER REFERENCES action_definitions(id), target_rule_id INTEGER REFERENCES rules(id),
    baseline_rule_version_id INTEGER REFERENCES rule_versions(id), wording_version_id INTEGER NOT NULL REFERENCES wording_versions(id), rationale TEXT NOT NULL,
    recorded_by_actor_id INTEGER NOT NULL REFERENCES actors(id), recorded_at TEXT NOT NULL,
    UNIQUE(change_id, revision), UNIQUE(change_id, id), UNIQUE(change_id, proposal_version_id, id),
    FOREIGN KEY(change_id, proposal_version_id) REFERENCES proposal_versions(change_id, id) DEFERRABLE INITIALLY DEFERRED,
    FOREIGN KEY(target_rule_id, baseline_rule_version_id) REFERENCES rule_versions(rule_id, id),
    CHECK(baseline_rule_version_id IS NULL OR target_rule_id IS NOT NULL)
  ) STRICT;
  CREATE TABLE change_placements (
    change_revision_id INTEGER NOT NULL REFERENCES change_revisions(id), surface_id INTEGER NOT NULL REFERENCES guidance_surfaces(id),
    section_heading TEXT NOT NULL, display_order INTEGER NOT NULL CHECK(display_order >= 0), PRIMARY KEY(change_revision_id, surface_id, section_heading)
  ) STRICT;
  CREATE TABLE change_retirements (
    change_revision_id INTEGER NOT NULL REFERENCES change_revisions(id), retired_rule_version_id INTEGER NOT NULL REFERENCES rule_versions(id), PRIMARY KEY(change_revision_id, retired_rule_version_id)
  ) STRICT;
  CREATE TABLE change_applicabilities (
    change_revision_id INTEGER NOT NULL REFERENCES change_revisions(id), applicability_id INTEGER NOT NULL REFERENCES applicability_definitions(id), PRIMARY KEY(change_revision_id, applicability_id)
  ) STRICT;
  CREATE TABLE plans (
    id INTEGER PRIMARY KEY, label TEXT NOT NULL, current_version_id INTEGER REFERENCES plan_versions(id) DEFERRABLE INITIALLY DEFERRED,
    FOREIGN KEY(id, current_version_id) REFERENCES plan_versions(plan_id, id) DEFERRABLE INITIALLY DEFERRED
  ) STRICT;
  CREATE TABLE plan_add_methods (id INTEGER PRIMARY KEY, code TEXT NOT NULL UNIQUE CHECK(code IN ('manual', 'bulk')), label TEXT NOT NULL) STRICT;
  CREATE TABLE bulk_add_operations (
    id INTEGER PRIMARY KEY, plan_id INTEGER NOT NULL REFERENCES plans(id), initiated_by_actor_id INTEGER NOT NULL REFERENCES actors(id),
    initiated_at TEXT NOT NULL, selection_description TEXT NOT NULL, UNIQUE(id, plan_id)
  ) STRICT;
  CREATE TABLE plan_memberships (
    id INTEGER PRIMARY KEY, plan_id INTEGER NOT NULL REFERENCES plans(id), change_id INTEGER NOT NULL REFERENCES changes(id),
    add_method_id INTEGER NOT NULL REFERENCES plan_add_methods(id), bulk_operation_id INTEGER, added_by_actor_id INTEGER NOT NULL REFERENCES actors(id),
    added_at TEXT NOT NULL, removed_by_actor_id INTEGER REFERENCES actors(id), removed_at TEXT,
    CHECK((removed_at IS NULL) = (removed_by_actor_id IS NULL)), FOREIGN KEY(bulk_operation_id, plan_id) REFERENCES bulk_add_operations(id, plan_id)
  ) STRICT;
  CREATE UNIQUE INDEX plan_active_membership ON plan_memberships(plan_id, change_id) WHERE removed_at IS NULL;
  CREATE TABLE plan_versions (
    id INTEGER PRIMARY KEY, plan_id INTEGER NOT NULL REFERENCES plans(id), revision INTEGER NOT NULL CHECK(revision > 0),
    base_catalog_id INTEGER NOT NULL REFERENCES catalog_versions(id), recorded_by_actor_id INTEGER NOT NULL REFERENCES actors(id), recorded_at TEXT NOT NULL,
    UNIQUE(plan_id, revision), UNIQUE(plan_id, id), UNIQUE(id, base_catalog_id)
  ) STRICT;
  CREATE TABLE plan_items (
    plan_version_id INTEGER NOT NULL REFERENCES plan_versions(id), membership_id INTEGER NOT NULL REFERENCES plan_memberships(id),
    change_revision_id INTEGER NOT NULL REFERENCES change_revisions(id), PRIMARY KEY(plan_version_id, membership_id)
  ) STRICT;
  CREATE TABLE wording_assessments (
    id INTEGER PRIMARY KEY, evaluation_id INTEGER NOT NULL REFERENCES evaluations(id), wording_version_id INTEGER NOT NULL REFERENCES wording_versions(id),
    scorecard_id INTEGER NOT NULL REFERENCES scorecards(id), meaning_summary TEXT NOT NULL, impact_description TEXT NOT NULL,
    applicable INTEGER NOT NULL CHECK(applicable IN (0, 1)), applicability_rationale TEXT NOT NULL,
    confidence_level TEXT NOT NULL CHECK(confidence_level IN ('low', 'medium', 'high')), confidence_rationale TEXT NOT NULL,
    existing_coverage_score INTEGER NOT NULL CHECK(existing_coverage_score BETWEEN 0 AND 5), existing_coverage_rationale TEXT NOT NULL
  ) STRICT;
  CREATE TABLE wording_assessment_uncertainties (
    assessment_id INTEGER NOT NULL REFERENCES wording_assessments(id), ordinal INTEGER NOT NULL CHECK(ordinal >= 0), description TEXT NOT NULL, PRIMARY KEY(assessment_id, ordinal)
  ) STRICT;
  CREATE TABLE wording_assessment_surfaces (
    assessment_id INTEGER NOT NULL REFERENCES wording_assessments(id), surface_id INTEGER NOT NULL REFERENCES guidance_surfaces(id), PRIMARY KEY(assessment_id, surface_id)
  ) STRICT;
  CREATE TABLE relationship_reviews (
    id INTEGER PRIMARY KEY, evaluation_id INTEGER NOT NULL REFERENCES evaluations(id), base_catalog_id INTEGER NOT NULL REFERENCES catalog_versions(id),
    protected_snapshot_id INTEGER NOT NULL REFERENCES protected_snapshots(id), plan_version_id INTEGER REFERENCES plan_versions(id),
    scope_code TEXT NOT NULL CHECK(scope_code IN ('saved-changes', 'plan')), CHECK(scope_code <> 'plan' OR plan_version_id IS NOT NULL)
  ) STRICT;
  CREATE TABLE review_subjects (
    id INTEGER PRIMARY KEY, review_id INTEGER NOT NULL REFERENCES relationship_reviews(id), rule_version_id INTEGER REFERENCES rule_versions(id),
    change_revision_id INTEGER REFERENCES change_revisions(id), wording_version_id INTEGER NOT NULL REFERENCES wording_versions(id),
    subject_role TEXT NOT NULL CHECK(subject_role IN ('changed', 'active', 'protected')), CHECK((rule_version_id IS NOT NULL) + (change_revision_id IS NOT NULL) = 1)
  ) STRICT;
  CREATE UNIQUE INDEX review_rule_subject ON review_subjects(review_id, rule_version_id) WHERE rule_version_id IS NOT NULL;
  CREATE UNIQUE INDEX review_change_subject ON review_subjects(review_id, change_revision_id) WHERE change_revision_id IS NOT NULL;
  CREATE TABLE review_removals (
    review_id INTEGER NOT NULL REFERENCES relationship_reviews(id), removed_rule_version_id INTEGER NOT NULL REFERENCES rule_versions(id),
    change_revision_id INTEGER NOT NULL REFERENCES change_revisions(id), PRIMARY KEY(review_id, removed_rule_version_id)
  ) STRICT;
  CREATE TABLE findings (
    id INTEGER PRIMARY KEY, evaluation_id INTEGER NOT NULL REFERENCES evaluations(id), review_id INTEGER REFERENCES relationship_reviews(id),
    finding_kind TEXT NOT NULL, title TEXT NOT NULL, rationale TEXT NOT NULL
  ) STRICT;
  ${findingParticipantsDdl()};
  CREATE TABLE issues (id INTEGER PRIMARY KEY, display_key TEXT NOT NULL UNIQUE, title TEXT NOT NULL, created_at TEXT NOT NULL) STRICT;
  CREATE TABLE issue_findings (
    issue_id INTEGER NOT NULL REFERENCES issues(id), finding_id INTEGER NOT NULL REFERENCES findings(id), correspondence_rationale TEXT NOT NULL,
    matched_by_evaluation_id INTEGER REFERENCES evaluations(id), matched_by_actor_id INTEGER REFERENCES actors(id), PRIMARY KEY(issue_id, finding_id)
  ) STRICT;
  CREATE TABLE adjudication_relationship_decisions (
    evaluation_id INTEGER NOT NULL REFERENCES evaluations(id), relationship_id INTEGER NOT NULL REFERENCES group_relationships(id),
    finding_id INTEGER NOT NULL UNIQUE REFERENCES findings(id), disposition TEXT NOT NULL CHECK(disposition IN ('issue', 'independent')),
    PRIMARY KEY(evaluation_id, relationship_id)
  ) STRICT;
  CREATE TABLE adjudicated_issues (
    issue_id INTEGER PRIMARY KEY REFERENCES issues(id), evaluation_id INTEGER NOT NULL REFERENCES evaluations(id),
    anchor_group_version_id INTEGER REFERENCES group_versions(id), anchor_rule_version_id INTEGER REFERENCES rule_versions(id),
    classification TEXT NOT NULL CHECK(classification IN ('protected-integrity', 'protected-conflict', 'protected-coverage', 'contradiction', 'duplicate', 'overlap')),
    blocking INTEGER NOT NULL CHECK(blocking IN (0, 1)), assessment_summary TEXT NOT NULL,
    wording_status TEXT NOT NULL CHECK(wording_status IN ('canonical', 'selected', 'unresolved')),
    wording_group_version_id INTEGER REFERENCES group_versions(id), wording_rule_version_id INTEGER REFERENCES rule_versions(id),
    wording_version_id INTEGER REFERENCES wording_versions(id), wording_rationale TEXT NOT NULL, action_summary TEXT NOT NULL,
    CHECK((anchor_group_version_id IS NOT NULL) + (anchor_rule_version_id IS NOT NULL) = 1),
    CHECK((wording_status = 'unresolved' AND wording_version_id IS NULL AND wording_group_version_id IS NULL AND wording_rule_version_id IS NULL)
      OR (wording_status <> 'unresolved' AND wording_version_id IS NOT NULL
        AND (wording_group_version_id IS NOT NULL) + (wording_rule_version_id IS NOT NULL) = 1))
  ) STRICT;
  CREATE TABLE adjudicated_issue_members (
    issue_id INTEGER NOT NULL REFERENCES adjudicated_issues(issue_id), ordinal INTEGER NOT NULL CHECK(ordinal >= 0),
    group_version_id INTEGER REFERENCES group_versions(id), rule_version_id INTEGER REFERENCES rule_versions(id),
    disposition TEXT NOT NULL CHECK(disposition IN ('keep', 'promote', 'replace', 'retire', 'exclude', 'defer', 'review')),
    PRIMARY KEY(issue_id, ordinal), CHECK((group_version_id IS NOT NULL) + (rule_version_id IS NOT NULL) = 1)
  ) STRICT;
  CREATE TABLE adjudicated_issue_operations (
    id INTEGER PRIMARY KEY, issue_id INTEGER NOT NULL REFERENCES adjudicated_issues(issue_id), ordinal INTEGER NOT NULL CHECK(ordinal >= 0),
    group_version_id INTEGER NOT NULL REFERENCES group_versions(id), action_code TEXT NOT NULL,
    wording_version_id INTEGER NOT NULL REFERENCES wording_versions(id), UNIQUE(issue_id, ordinal), UNIQUE(issue_id, group_version_id)
  ) STRICT;
  CREATE TABLE adjudicated_operation_retirements (
    operation_id INTEGER NOT NULL REFERENCES adjudicated_issue_operations(id), rule_version_id INTEGER NOT NULL REFERENCES rule_versions(id),
    PRIMARY KEY(operation_id, rule_version_id)
  ) STRICT;
  CREATE TABLE issue_resolutions (
    id INTEGER PRIMARY KEY, decision_code TEXT NOT NULL, rationale TEXT NOT NULL, recorded_by_actor_id INTEGER NOT NULL REFERENCES actors(id), recorded_at TEXT NOT NULL
  ) STRICT;
  CREATE TABLE resolution_issues (
    resolution_id INTEGER NOT NULL REFERENCES issue_resolutions(id), issue_id INTEGER NOT NULL REFERENCES issues(id), PRIMARY KEY(resolution_id, issue_id)
  ) STRICT;
  CREATE TABLE resolution_findings (
    resolution_id INTEGER NOT NULL REFERENCES issue_resolutions(id), finding_id INTEGER NOT NULL REFERENCES findings(id), PRIMARY KEY(resolution_id, finding_id)
  ) STRICT;
  CREATE TABLE resolution_changes (
    resolution_id INTEGER NOT NULL REFERENCES issue_resolutions(id), change_revision_id INTEGER NOT NULL REFERENCES change_revisions(id), PRIMARY KEY(resolution_id, change_revision_id)
  ) STRICT;
  CREATE TABLE capacity_policies (
    id INTEGER PRIMARY KEY, code TEXT NOT NULL, revision INTEGER NOT NULL CHECK(revision > 0), estimator_code TEXT NOT NULL, estimator_version TEXT NOT NULL,
    characters_per_token REAL CHECK(characters_per_token > 0), safety_margin_percent REAL NOT NULL CHECK(safety_margin_percent >= 0),
    runtime_request_token_limit INTEGER NOT NULL CHECK(runtime_request_token_limit > 0),
    guidance_token_budget INTEGER NOT NULL CHECK(guidance_token_budget > 0 AND guidance_token_budget <= runtime_request_token_limit), UNIQUE(code, revision)
  ) STRICT;
  CREATE TABLE capacity_buckets (
    id INTEGER PRIMARY KEY, policy_id INTEGER NOT NULL REFERENCES capacity_policies(id), code TEXT NOT NULL, label TEXT NOT NULL,
    guarded_limit INTEGER NOT NULL CHECK(guarded_limit >= 0), accounting_mode TEXT NOT NULL CHECK(accounting_mode IN ('surface-sum', 'rendered-union')), UNIQUE(policy_id, code)
  ) STRICT;
  CREATE TABLE capacity_bucket_surfaces (
    bucket_id INTEGER NOT NULL REFERENCES capacity_buckets(id), surface_id INTEGER NOT NULL REFERENCES guidance_surfaces(id), PRIMARY KEY(bucket_id, surface_id)
  ) STRICT;
  CREATE TABLE capacity_bucket_files (
    bucket_id INTEGER PRIMARY KEY REFERENCES capacity_buckets(id), relative_path TEXT NOT NULL CHECK(length(relative_path) > 0)
  ) STRICT;
  CREATE TABLE database_backups (
    id INTEGER PRIMARY KEY, database_guid TEXT NOT NULL, requested_by_actor_id INTEGER NOT NULL REFERENCES actors(id), requested_at TEXT NOT NULL,
    completed_at TEXT, local_path TEXT NOT NULL, content_sha256 TEXT, outcome TEXT NOT NULL CHECK(outcome IN ('running', 'complete', 'failed', 'cancelled')), verification_outcome TEXT
  ) STRICT;
  CREATE TABLE rendered_artifacts (
    id INTEGER PRIMARY KEY, plan_version_id INTEGER NOT NULL REFERENCES plan_versions(id), base_catalog_id INTEGER NOT NULL,
    catalog_id INTEGER NOT NULL REFERENCES catalog_versions(id), protected_snapshot_id INTEGER NOT NULL REFERENCES protected_snapshots(id),
    capacity_policy_id INTEGER NOT NULL REFERENCES capacity_policies(id), renderer_sha256 TEXT NOT NULL, manifest_sha256 TEXT NOT NULL,
    content_fingerprint TEXT NOT NULL, created_at TEXT NOT NULL, UNIQUE(id, plan_version_id, catalog_id),
    FOREIGN KEY(plan_version_id, base_catalog_id) REFERENCES plan_versions(id, base_catalog_id),
    FOREIGN KEY(catalog_id, base_catalog_id) REFERENCES catalog_versions(id, parent_catalog_id)
  ) STRICT;
  CREATE TABLE artifact_files (
    id INTEGER PRIMARY KEY, artifact_id INTEGER NOT NULL REFERENCES rendered_artifacts(id), relative_path TEXT NOT NULL,
    content BLOB NOT NULL, content_sha256 TEXT NOT NULL, expected_before_sha256 TEXT, UNIQUE(artifact_id, relative_path)
  ) STRICT;
  CREATE TABLE approvals (
    id INTEGER PRIMARY KEY, plan_version_id INTEGER NOT NULL REFERENCES plan_versions(id), catalog_id INTEGER NOT NULL REFERENCES catalog_versions(id),
    artifact_id INTEGER NOT NULL, approved_by_actor_id INTEGER NOT NULL REFERENCES actors(id), approved_at TEXT NOT NULL, UNIQUE(id, catalog_id),
    FOREIGN KEY(artifact_id, plan_version_id, catalog_id) REFERENCES rendered_artifacts(id, plan_version_id, catalog_id)
  ) STRICT;
  CREATE TABLE approval_reviews (
    approval_id INTEGER NOT NULL REFERENCES approvals(id), review_id INTEGER NOT NULL REFERENCES relationship_reviews(id), PRIMARY KEY(approval_id, review_id)
  ) STRICT;
  CREATE TABLE catalog_applications (
    id INTEGER PRIMARY KEY, operation_key TEXT NOT NULL UNIQUE, approval_id INTEGER NOT NULL, base_catalog_id INTEGER NOT NULL, resulting_catalog_id INTEGER NOT NULL,
    requested_by_actor_id INTEGER NOT NULL REFERENCES actors(id), created_at TEXT NOT NULL,
    started_at TEXT, completed_at TEXT, outcome TEXT NOT NULL CHECK(outcome IN ('pending', 'running', 'complete', 'failed')),
    FOREIGN KEY(approval_id, resulting_catalog_id) REFERENCES approvals(id, catalog_id),
    FOREIGN KEY(resulting_catalog_id, base_catalog_id) REFERENCES catalog_versions(id, parent_catalog_id),
    CHECK((outcome IN ('pending', 'running')) = (completed_at IS NULL))
  ) STRICT;
  CREATE TABLE deployments (
    id INTEGER PRIMARY KEY, application_id INTEGER NOT NULL REFERENCES catalog_applications(id), target_context_id INTEGER NOT NULL REFERENCES repository_contexts(id),
    deployed_by_actor_id INTEGER NOT NULL REFERENCES actors(id), started_at TEXT NOT NULL, completed_at TEXT, outcome TEXT NOT NULL CHECK(outcome IN ('running', 'complete', 'failed'))
  ) STRICT;
  CREATE TABLE deployment_files (
    deployment_id INTEGER NOT NULL REFERENCES deployments(id), artifact_file_id INTEGER NOT NULL REFERENCES artifact_files(id), observed_before_sha256 TEXT, observed_after_sha256 TEXT,
    outcome TEXT NOT NULL CHECK(outcome IN ('pending', 'written', 'unchanged', 'failed')), PRIMARY KEY(deployment_id, artifact_file_id)
  ) STRICT;
`;

// Create schema domains in dependency order before installing cross-domain constraints and history guards.
function createApplicationObjects(connection) {
  connection.exec(applicationDdl());
  createSourceIngestionSchema(connection);
  createProtectedSnapshotSchema(connection);
  createWorkspaceIdentitySchema(connection);
  createAuthoredAuditSchema(connection);
  connection.exec(`
    CREATE TABLE run_collections (
      run_id INTEGER NOT NULL REFERENCES analysis_runs(id), collection_id INTEGER NOT NULL REFERENCES source_collections(id), PRIMARY KEY(run_id, collection_id)
    ) STRICT;
    CREATE TABLE source_version_comparisons (
      id INTEGER PRIMARY KEY, evaluation_id INTEGER NOT NULL REFERENCES evaluations(id), prior_version_id INTEGER NOT NULL REFERENCES source_versions(id),
      current_version_id INTEGER NOT NULL REFERENCES source_versions(id), classification TEXT NOT NULL, rationale TEXT NOT NULL, prior_evidence_quote TEXT, current_evidence_quote TEXT,
      CHECK(prior_version_id <> current_version_id)
    ) STRICT;
  `);
  createReconciliationComponents(connection);
  createConsolidationMerges(connection);
  createEvaluationInputs(connection, true, true);
  createReconciliationComponentGuards(connection);
  createApplicationGuards(connection);
}

// Preserve merged component membership together with the completed shard evaluations that justify it.
function createConsolidationMerges(connection) {
  connection.exec(`
    CREATE TABLE consolidation_merges (
      id INTEGER PRIMARY KEY, run_id INTEGER NOT NULL REFERENCES analysis_runs(id), evaluator_profile_id INTEGER NOT NULL REFERENCES evaluator_profiles(id),
      plan_sha256 TEXT NOT NULL CHECK(length(plan_sha256) = 64), created_at TEXT NOT NULL, UNIQUE(run_id, evaluator_profile_id, plan_sha256)
    ) STRICT;
    CREATE TABLE consolidation_merge_evaluations (
      merge_id INTEGER NOT NULL REFERENCES consolidation_merges(id), evaluation_id INTEGER NOT NULL REFERENCES evaluations(id),
      ordinal INTEGER NOT NULL CHECK(ordinal >= 0), PRIMARY KEY(merge_id, evaluation_id), UNIQUE(merge_id, ordinal)
    ) STRICT;
    CREATE TABLE consolidated_components (
      id INTEGER PRIMARY KEY, merge_id INTEGER NOT NULL REFERENCES consolidation_merges(id), ordinal INTEGER NOT NULL CHECK(ordinal >= 0),
      semantic_summary TEXT NOT NULL CHECK(length(semantic_summary) > 0), UNIQUE(merge_id, ordinal)
    ) STRICT;
    CREATE TABLE consolidated_component_members (
      component_id INTEGER NOT NULL REFERENCES consolidated_components(id), assessment_result_id INTEGER NOT NULL REFERENCES assessment_results(id),
      PRIMARY KEY(component_id, assessment_result_id)
    ) STRICT;
    CREATE TABLE consolidated_component_rules (
      component_id INTEGER NOT NULL REFERENCES consolidated_components(id), rule_version_id INTEGER NOT NULL REFERENCES rule_versions(id),
      PRIMARY KEY(component_id, rule_version_id)
    ) STRICT;
    CREATE TRIGGER consolidation_merge_scope_INSERT BEFORE INSERT ON consolidation_merges
      WHEN NOT EXISTS(SELECT 1 FROM analysis_runs run JOIN analysis_run_llm_assignments assigned ON assigned.run_id = run.id
        JOIN evaluator_profiles profile ON profile.llm_assignment_id = assigned.assignment_id AND profile.task_code = assigned.task_code
        WHERE run.id = NEW.run_id AND run.outcome = 'running' AND profile.id = NEW.evaluator_profile_id AND profile.task_code = 'reconciliation')
      BEGIN SELECT RAISE(ABORT, 'Consolidation merge requires an active run and its pinned evaluator'); END;
    CREATE TRIGGER consolidation_merge_evaluation_scope_INSERT BEFORE INSERT ON consolidation_merge_evaluations
      WHEN NOT EXISTS(SELECT 1 FROM consolidation_merges merge JOIN run_evaluations used ON used.run_id = merge.run_id
        JOIN evaluations evaluation ON evaluation.id = used.evaluation_id
        WHERE merge.id = NEW.merge_id AND evaluation.id = NEW.evaluation_id AND evaluation.outcome = 'complete'
          AND evaluation.evaluator_profile_id = merge.evaluator_profile_id
          AND EXISTS(SELECT 1 FROM reconciliation_components component WHERE component.evaluation_id = evaluation.id AND component.phase_code = 'consolidation'))
      BEGIN SELECT RAISE(ABORT, 'Consolidation merge lineage requires its completed shard evaluations'); END;
    CREATE TRIGGER consolidated_component_member_scope_INSERT BEFORE INSERT ON consolidated_component_members
      WHEN NOT EXISTS(SELECT 1 FROM consolidated_components component JOIN consolidation_merge_evaluations lineage ON lineage.merge_id = component.merge_id
        JOIN evaluation_inputs input ON input.evaluation_id = lineage.evaluation_id
        WHERE component.id = NEW.component_id AND input.role_code = 'assessment-result' AND input.assessment_result_id = NEW.assessment_result_id)
      BEGIN SELECT RAISE(ABORT, 'Consolidated member requires exact completed shard evidence'); END;
    CREATE TRIGGER consolidated_component_rule_scope_INSERT BEFORE INSERT ON consolidated_component_rules
      WHEN NOT EXISTS(SELECT 1 FROM consolidated_components component JOIN consolidation_merges merge ON merge.id = component.merge_id
        JOIN analysis_runs run ON run.id = merge.run_id JOIN consolidation_merge_evaluations lineage ON lineage.merge_id = component.merge_id
        JOIN evaluation_inputs input ON input.evaluation_id = lineage.evaluation_id
        WHERE component.id = NEW.component_id AND run.outcome = 'running'
          AND input.role_code = 'reconciliation-rule' AND input.rule_version_id = NEW.rule_version_id)
      OR EXISTS(SELECT 1 FROM evaluation_inputs WHERE consolidated_component_id = NEW.component_id)
      BEGIN SELECT RAISE(ABORT, 'Consolidated rule requires exact unused completed shard evidence'); END;
  `);
  for (const table of ['consolidation_merges', 'consolidation_merge_evaluations', 'consolidated_components', 'consolidated_component_members', 'consolidated_component_rules']) {
    for (const operation of ['UPDATE', 'DELETE']) connection.exec(`CREATE TRIGGER application_${table}_${operation} BEFORE ${operation} ON ${table}
      BEGIN SELECT RAISE(ABORT, 'Consolidation merge history is immutable'); END`);
  }
}

// Store routing and consolidation scopes with separate typed assessment and baseline-rule membership.
function createReconciliationComponents(connection) {
  connection.exec(`
    CREATE TABLE reconciliation_components (
      id INTEGER PRIMARY KEY, evaluation_id INTEGER NOT NULL REFERENCES evaluations(id),
      phase_code TEXT NOT NULL CHECK(phase_code IN ('routing', 'consolidation')),
      ordinal INTEGER NOT NULL CHECK(ordinal >= 0), semantic_summary TEXT NOT NULL CHECK(length(semantic_summary) > 0),
      UNIQUE(evaluation_id, ordinal)
    ) STRICT;
    CREATE TABLE reconciliation_component_members (
      component_id INTEGER NOT NULL REFERENCES reconciliation_components(id),
      assessment_result_id INTEGER NOT NULL REFERENCES assessment_results(id),
      PRIMARY KEY(component_id, assessment_result_id)
    ) STRICT;
    CREATE TABLE reconciliation_component_rules (
      component_id INTEGER NOT NULL REFERENCES reconciliation_components(id),
      rule_version_id INTEGER NOT NULL REFERENCES rule_versions(id),
      PRIMARY KEY(component_id, rule_version_id)
    ) STRICT;
  `);
}

// Restrict component writes to their running evaluation's supplied assessments, then make the history immutable.
function createReconciliationComponentGuards(connection) {
  connection.exec(`
    CREATE TRIGGER reconciliation_component_scope_INSERT BEFORE INSERT ON reconciliation_components
      WHEN NOT EXISTS(SELECT 1 FROM evaluations evaluation JOIN evaluator_profiles profile ON profile.id = evaluation.evaluator_profile_id
        WHERE evaluation.id = NEW.evaluation_id AND evaluation.outcome = 'running' AND profile.task_code = 'reconciliation')
      BEGIN SELECT RAISE(ABORT, 'Component requires an active reconciliation evaluation'); END;
    CREATE TRIGGER reconciliation_component_member_scope_INSERT BEFORE INSERT ON reconciliation_component_members
      WHEN NOT EXISTS(SELECT 1 FROM reconciliation_components component JOIN evaluations evaluation ON evaluation.id = component.evaluation_id
        JOIN evaluation_inputs input ON input.evaluation_id = evaluation.id
        WHERE component.id = NEW.component_id AND evaluation.outcome = 'running'
          AND input.role_code = 'assessment-result' AND input.assessment_result_id = NEW.assessment_result_id)
      BEGIN SELECT RAISE(ABORT, 'Component member must belong to its exact evaluation inputs'); END;
    CREATE TRIGGER reconciliation_component_rule_scope_INSERT BEFORE INSERT ON reconciliation_component_rules
      WHEN NOT EXISTS(SELECT 1 FROM reconciliation_components component JOIN evaluations evaluation ON evaluation.id = component.evaluation_id
        JOIN evaluation_inputs input ON input.evaluation_id = evaluation.id
        WHERE component.id = NEW.component_id AND evaluation.outcome = 'running'
          AND input.role_code = 'reconciliation-rule' AND input.rule_version_id = NEW.rule_version_id)
      BEGIN SELECT RAISE(ABORT, 'Component rule must belong to its exact evaluation inputs'); END;
  `);
  for (const table of ['reconciliation_components', 'reconciliation_component_members', 'reconciliation_component_rules']) {
    for (const operation of ['UPDATE', 'DELETE']) connection.exec(`CREATE TRIGGER application_${table}_${operation} BEFORE ${operation} ON ${table}
      BEGIN SELECT RAISE(ABORT, 'Reconciliation component history is immutable'); END`);
  }
}

// Record one typed evidence reference per input, enabling later reconstruction of the exact evaluator scope.
function createEvaluationInputs(connection, includeAssessmentResults = false, includeConsolidatedComponents = false) {
  const inputs = {
    source_version_id: 'source_versions', source_observation_id: 'source_observations', group_version_id: 'group_versions', wording_version_id: 'wording_versions',
    rule_version_id: 'rule_versions', catalog_version_id: 'catalog_versions', protected_snapshot_id: 'protected_snapshots', plan_version_id: 'plan_versions',
    scoring_policy_id: 'scoring_policies', capacity_policy_id: 'capacity_policies',
    group_relationship_id: 'group_relationships',
  };
  if (includeAssessmentResults) {
    inputs.assessment_result_id = 'assessment_results';
    inputs.reconciliation_component_id = 'reconciliation_components';
  }
  if (includeConsolidatedComponents) {
    inputs.consolidated_component_id = 'consolidated_components';
    inputs.evaluator_profile_id = 'evaluator_profiles';
  }
  connection.exec(`CREATE TABLE evaluation_inputs (
    id INTEGER PRIMARY KEY, evaluation_id INTEGER NOT NULL REFERENCES evaluations(id), role_code TEXT NOT NULL,
    ${Object.entries(inputs).map(([field, table]) => `${field} INTEGER REFERENCES ${table}(id)`).join(', ')},
    CHECK(${Object.keys(inputs).map(field => `(${field} IS NOT NULL)`).join(' + ')} = 1)
  ) STRICT`);
  for (const field of Object.keys(inputs)) connection.exec(`CREATE UNIQUE INDEX evaluation_input_${field} ON evaluation_inputs(evaluation_id, role_code, ${field}) WHERE ${field} IS NOT NULL`);
}

// Enforce cross-table policy, ownership, active-evaluation scope, and immutable history at the database boundary.
function createApplicationGuards(connection) {
  for (const operation of ['INSERT', 'UPDATE']) {
    connection.exec(`
      CREATE TRIGGER capacity_bucket_allocation_${operation} BEFORE ${operation} ON capacity_buckets
        WHEN NEW.guarded_limit + (SELECT coalesce(sum(guarded_limit), 0) FROM capacity_buckets WHERE policy_id = NEW.policy_id AND id <> NEW.id)
          > (SELECT guidance_token_budget FROM capacity_policies WHERE id = NEW.policy_id)
        BEGIN SELECT RAISE(ABORT, 'Category allowances must fit within the guidance reservation'); END;
      CREATE TRIGGER scorecard_value_scope_${operation} BEFORE ${operation} ON scorecard_values
        WHEN NOT EXISTS(SELECT 1 FROM scorecards card JOIN scoring_factors factor ON factor.policy_id = card.policy_id
          WHERE card.id = NEW.scorecard_id AND factor.id = NEW.factor_id AND NEW.value BETWEEN factor.minimum_value AND factor.maximum_value)
        BEGIN SELECT RAISE(ABORT, 'Score value violates policy or factor bounds'); END;
      CREATE TRIGGER priority_band_overlap_${operation} BEFORE ${operation} ON priority_bands
        WHEN EXISTS(SELECT 1 FROM priority_bands band WHERE band.policy_id = NEW.policy_id AND band.id <> NEW.id
          AND (band.maximum_score IS NULL OR NEW.minimum_score <= band.maximum_score)
          AND (NEW.maximum_score IS NULL OR band.minimum_score <= NEW.maximum_score))
        BEGIN SELECT RAISE(ABORT, 'Priority bands must not overlap'); END;
      CREATE TRIGGER plan_membership_method_${operation} BEFORE ${operation} ON plan_memberships
        WHEN NOT EXISTS(SELECT 1 FROM plan_add_methods method WHERE method.id = NEW.add_method_id
          AND ((method.code = 'manual' AND NEW.bulk_operation_id IS NULL) OR (method.code = 'bulk' AND NEW.bulk_operation_id IS NOT NULL)))
        BEGIN SELECT RAISE(ABORT, 'Plan membership requires its actual addition method'); END;
      CREATE TRIGGER plan_item_scope_${operation} BEFORE ${operation} ON plan_items
        WHEN NOT EXISTS(SELECT 1 FROM plan_memberships member JOIN plan_versions version ON version.plan_id = member.plan_id
          JOIN change_revisions revision ON revision.change_id = member.change_id
          WHERE member.id = NEW.membership_id AND version.id = NEW.plan_version_id AND revision.id = NEW.change_revision_id)
        BEGIN SELECT RAISE(ABORT, 'Plan item violates membership ownership'); END;
      CREATE TRIGGER change_managed_scope_${operation} BEFORE ${operation} ON change_revisions
        WHEN NEW.target_rule_id IS NOT NULL AND EXISTS(SELECT 1 FROM rules WHERE id = NEW.target_rule_id AND rule_kind <> 'managed')
        BEGIN SELECT RAISE(ABORT, 'Protected rules cannot be changed'); END;
      CREATE TRIGGER retirement_managed_scope_${operation} BEFORE ${operation} ON change_retirements
        WHEN EXISTS(SELECT 1 FROM rule_versions version JOIN rules rule ON rule.id = version.rule_id WHERE version.id = NEW.retired_rule_version_id AND rule.rule_kind <> 'managed')
        BEGIN SELECT RAISE(ABORT, 'Protected rules cannot be retired'); END;
      CREATE TRIGGER review_subject_wording_${operation} BEFORE ${operation} ON review_subjects
        WHEN NOT EXISTS(SELECT 1 FROM rule_versions WHERE id = NEW.rule_version_id AND wording_version_id = NEW.wording_version_id)
          AND NOT EXISTS(SELECT 1 FROM change_revisions WHERE id = NEW.change_revision_id AND wording_version_id = NEW.wording_version_id)
        BEGIN SELECT RAISE(ABORT, 'Review subject must pin exact wording'); END;
      CREATE TRIGGER published_catalog_finalized_${operation} BEFORE ${operation} ON workspace_publication
        WHEN NOT EXISTS(SELECT 1 FROM catalog_versions WHERE id = NEW.current_catalog_id AND finalized_at IS NOT NULL)
        BEGIN SELECT RAISE(ABORT, 'Published catalog must be finalized'); END;
      CREATE TRIGGER staged_catalog_finalized_${operation} BEFORE ${operation} ON workspace_staging
        WHEN NOT EXISTS(SELECT 1 FROM catalog_versions WHERE id = NEW.current_catalog_id AND finalized_at IS NOT NULL)
        BEGIN SELECT RAISE(ABORT, 'Staged catalog must be finalized'); END;
      CREATE TRIGGER artifact_catalog_finalized_${operation} BEFORE ${operation} ON rendered_artifacts
        WHEN NOT EXISTS(SELECT 1 FROM catalog_versions WHERE id = NEW.catalog_id AND finalized_at IS NOT NULL AND protected_snapshot_id = NEW.protected_snapshot_id)
        BEGIN SELECT RAISE(ABORT, 'Artifact requires finalized matching protection'); END;
      CREATE TRIGGER resolution_finding_scope_${operation} BEFORE ${operation} ON resolution_findings
        WHEN NOT EXISTS(SELECT 1 FROM resolution_issues resolution JOIN issue_findings finding ON finding.issue_id = resolution.issue_id
          WHERE resolution.resolution_id = NEW.resolution_id AND finding.finding_id = NEW.finding_id)
        BEGIN SELECT RAISE(ABORT, 'Resolution finding must belong to a linked issue'); END;
    `);
  }
  connection.exec(`
    CREATE TRIGGER group_version_scope_INSERT BEFORE INSERT ON group_versions
      WHEN NOT EXISTS(SELECT 1 FROM evaluations evaluation JOIN evaluator_profiles profile ON profile.id = evaluation.evaluator_profile_id
        JOIN run_evaluations used ON used.evaluation_id = evaluation.id JOIN analysis_runs run ON run.id = used.run_id
        WHERE evaluation.id = NEW.synthesis_evaluation_id AND evaluation.outcome = 'running' AND run.outcome = 'running' AND profile.task_code = 'reconciliation'
          AND EXISTS(SELECT 1 FROM evaluation_inputs input LEFT JOIN reconciliation_components component ON component.id = input.reconciliation_component_id
            WHERE input.evaluation_id = evaluation.id AND ((input.role_code = 'component' AND component.phase_code = 'consolidation')
              OR input.role_code = 'merged-component')))
      BEGIN SELECT RAISE(ABORT, 'Group version requires a running reconciliation evaluation'); END;
    CREATE TRIGGER group_member_scope_INSERT BEFORE INSERT ON group_members
      WHEN NOT EXISTS(SELECT 1 FROM group_versions version JOIN evaluations evaluation ON evaluation.id = version.synthesis_evaluation_id
        JOIN evaluation_inputs input ON input.evaluation_id = evaluation.id
        JOIN run_evaluations used ON used.evaluation_id = evaluation.id JOIN analysis_runs run ON run.id = used.run_id
        WHERE version.id = NEW.group_version_id AND evaluation.outcome = 'running' AND run.outcome = 'running'
          AND input.role_code = 'assessment-result' AND input.assessment_result_id = NEW.assessment_result_id)
      BEGIN SELECT RAISE(ABORT, 'Group member requires exact running synthesis inputs'); END;
    CREATE TRIGGER group_anchor_scope_INSERT BEFORE INSERT ON group_catalog_anchors
      WHEN NOT EXISTS(SELECT 1 FROM group_versions version JOIN evaluations evaluation ON evaluation.id = version.synthesis_evaluation_id
        JOIN run_evaluations used ON used.evaluation_id = evaluation.id
        JOIN analysis_run_contexts context ON context.run_id = used.run_id
        JOIN analysis_runs run ON run.id = used.run_id
        WHERE version.id = NEW.group_version_id AND evaluation.outcome = 'running' AND run.outcome = 'running'
          AND (EXISTS(SELECT 1 FROM catalog_members WHERE catalog_id = context.base_catalog_id AND rule_version_id = NEW.rule_version_id)
            OR EXISTS(SELECT 1 FROM protected_members WHERE snapshot_id = context.protected_snapshot_id AND rule_version_id = NEW.rule_version_id)))
      BEGIN SELECT RAISE(ABORT, 'Group anchor requires pinned running synthesis context'); END;
    CREATE TRIGGER group_relationship_scope_INSERT BEFORE INSERT ON group_relationships
      WHEN NOT EXISTS(SELECT 1 FROM group_versions version JOIN evaluations evaluation ON evaluation.id = version.synthesis_evaluation_id
        JOIN run_evaluations used ON used.evaluation_id = evaluation.id JOIN analysis_runs run ON run.id = used.run_id
        JOIN analysis_run_contexts context ON context.run_id = run.id
        WHERE version.id = NEW.group_version_id AND evaluation.outcome = 'running' AND run.outcome = 'running'
          AND ((NEW.target_assessment_id IS NOT NULL
            AND NOT EXISTS(SELECT 1 FROM group_members WHERE group_version_id = version.id AND assessment_result_id = NEW.target_assessment_id)
            AND EXISTS(SELECT 1 FROM evaluation_inputs input JOIN assessment_results target ON target.id = input.assessment_result_id
              WHERE input.evaluation_id = evaluation.id AND input.role_code = 'assessment-result'
                AND target.id = NEW.target_assessment_id))
            OR (NEW.target_rule_version_id IS NOT NULL
              AND (EXISTS(SELECT 1 FROM catalog_members WHERE catalog_id = context.base_catalog_id AND rule_version_id = NEW.target_rule_version_id)
                OR EXISTS(SELECT 1 FROM protected_members WHERE snapshot_id = context.protected_snapshot_id AND rule_version_id = NEW.target_rule_version_id)))))
      BEGIN SELECT RAISE(ABORT, 'Group relationship requires exact pinned synthesis evidence'); END;
    CREATE TRIGGER group_relationship_evidence_scope_INSERT BEFORE INSERT ON group_relationship_evidence
      WHEN NOT EXISTS(SELECT 1 FROM group_relationships relation
        JOIN group_versions version ON version.id = relation.group_version_id
        JOIN evaluations evaluation ON evaluation.id = version.synthesis_evaluation_id
        JOIN run_evaluations used ON used.evaluation_id = evaluation.id JOIN analysis_runs run ON run.id = used.run_id
        JOIN group_members member ON member.group_version_id = version.id AND member.assessment_result_id = NEW.source_assessment_id
        JOIN assessment_results source ON source.id = member.assessment_result_id
        WHERE relation.id = NEW.relationship_id AND evaluation.outcome = 'running' AND run.outcome = 'running'
          AND instr(source.source_meaning, NEW.source_quote) > 0
          AND ((relation.target_assessment_id IS NOT NULL AND EXISTS(SELECT 1 FROM assessment_results target
              WHERE target.id = relation.target_assessment_id AND instr(target.source_meaning, NEW.target_quote) > 0))
            OR (relation.target_rule_version_id IS NOT NULL AND EXISTS(SELECT 1 FROM rule_versions rule
              JOIN wording_versions wording ON wording.id = rule.wording_version_id
              WHERE rule.id = relation.target_rule_version_id AND instr(wording.text, NEW.target_quote) > 0))))
      BEGIN SELECT RAISE(ABORT, 'Group relationship evidence requires exact running member and target quotes'); END;
    CREATE TRIGGER group_relationship_evidence_complete_UPDATE BEFORE UPDATE OF outcome ON evaluations
      WHEN NEW.outcome = 'complete' AND EXISTS(SELECT 1 FROM group_relationships relation
        JOIN group_versions version ON version.id = relation.group_version_id
        WHERE version.synthesis_evaluation_id = NEW.id
          AND NOT EXISTS(SELECT 1 FROM group_relationship_evidence evidence WHERE evidence.relationship_id = relation.id))
      BEGIN SELECT RAISE(ABORT, 'Completed synthesis requires evidence for every relationship'); END;
    CREATE TRIGGER group_correspondence_scope_INSERT BEFORE INSERT ON group_correspondences
      WHEN NOT EXISTS(SELECT 1 FROM group_versions next JOIN evaluations evaluation ON evaluation.id = next.synthesis_evaluation_id
        JOIN evaluation_inputs input ON input.evaluation_id = evaluation.id
        JOIN run_evaluations used ON used.evaluation_id = evaluation.id JOIN analysis_runs run ON run.id = used.run_id
        JOIN analysis_run_contexts context ON context.run_id = run.id
        WHERE next.id = NEW.next_group_version_id AND evaluation.id = NEW.evaluation_id AND evaluation.outcome = 'running' AND run.outcome = 'running'
          AND input.role_code = 'prior-group' AND input.group_version_id = NEW.prior_group_version_id
          AND NEW.correspondence_kind = next.continuity_kind AND NEW.confidence_level = next.continuity_confidence
          AND EXISTS(SELECT 1 FROM accepted_group_evidence WHERE catalog_id = context.base_catalog_id AND group_version_id = NEW.prior_group_version_id)
          AND ((NEW.correspondence_kind = 'unresolved' AND next.group_id IS NULL)
            OR (NEW.correspondence_kind <> 'unresolved' AND next.group_id IS NOT NULL)))
      BEGIN SELECT RAISE(ABORT, 'Group correspondence requires pinned prior evidence and its running successor'); END;
    CREATE TRIGGER group_correspondence_member_scope_INSERT BEFORE INSERT ON group_correspondence_members
      WHEN NOT EXISTS(SELECT 1 FROM group_correspondences correspondence
        JOIN evaluations evaluation ON evaluation.id = correspondence.evaluation_id
        JOIN group_members current ON current.group_version_id = correspondence.next_group_version_id
        JOIN group_members prior ON prior.group_version_id = correspondence.prior_group_version_id
        JOIN assessment_results current_assessment ON current_assessment.id = current.assessment_result_id
        JOIN assessment_results prior_assessment ON prior_assessment.id = prior.assessment_result_id
        JOIN run_evaluations used ON used.evaluation_id = evaluation.id JOIN analysis_runs run ON run.id = used.run_id
        WHERE correspondence.id = NEW.correspondence_id AND evaluation.outcome = 'running' AND run.outcome = 'running'
          AND current.assessment_result_id = NEW.assessment_result_id AND prior.assessment_result_id = NEW.prior_assessment_result_id
          AND length(trim(NEW.current_evidence_quote)) > 0 AND length(trim(NEW.prior_evidence_quote)) > 0
          AND instr(current_assessment.source_meaning, NEW.current_evidence_quote) > 0
          AND instr(prior_assessment.source_meaning, NEW.prior_evidence_quote) > 0)
      BEGIN SELECT RAISE(ABORT, 'Group correspondence member requires exact predecessor and successor membership'); END;
    CREATE TRIGGER accepted_group_established_INSERT BEFORE INSERT ON accepted_group_evidence
      WHEN NOT EXISTS(SELECT 1 FROM group_versions version JOIN evaluations evaluation ON evaluation.id = version.synthesis_evaluation_id
        WHERE version.id = NEW.group_version_id AND version.group_id IS NOT NULL AND evaluation.outcome = 'complete')
      BEGIN SELECT RAISE(ABORT, 'Catalog group evidence requires a completed established group version'); END;
  `);
  for (const [table, scope] of [
    ['adjudication_relationship_decisions', `SELECT evaluation.id FROM evaluations evaluation
      JOIN evaluator_profiles profile ON profile.id = evaluation.evaluator_profile_id
      JOIN run_evaluations used ON used.evaluation_id = evaluation.id JOIN analysis_runs run ON run.id = used.run_id
      JOIN evaluation_inputs input ON input.evaluation_id = evaluation.id JOIN findings finding ON finding.evaluation_id = evaluation.id
      WHERE evaluation.id = NEW.evaluation_id AND profile.task_code = 'adjudication' AND evaluation.outcome = 'running' AND run.outcome = 'running'
        AND input.role_code = 'relationship' AND input.group_relationship_id = NEW.relationship_id AND finding.id = NEW.finding_id`],
    ['adjudicated_issues', `SELECT evaluation.id FROM evaluations evaluation JOIN evaluator_profiles profile ON profile.id = evaluation.evaluator_profile_id
      JOIN run_evaluations used ON used.evaluation_id = evaluation.id JOIN analysis_runs run ON run.id = used.run_id
      JOIN evaluation_inputs input ON input.evaluation_id = evaluation.id WHERE evaluation.id = NEW.evaluation_id
        AND profile.task_code = 'adjudication' AND evaluation.outcome = 'running' AND run.outcome = 'running'
        AND ((input.role_code = 'group' AND input.group_version_id = NEW.anchor_group_version_id)
          OR (input.role_code IN ('managed-rule', 'protected-rule') AND input.rule_version_id = NEW.anchor_rule_version_id))`],
    ['adjudicated_issue_members', `SELECT issue.issue_id FROM adjudicated_issues issue JOIN evaluations evaluation ON evaluation.id = issue.evaluation_id
      JOIN run_evaluations used ON used.evaluation_id = evaluation.id JOIN analysis_runs run ON run.id = used.run_id
      JOIN evaluation_inputs input ON input.evaluation_id = evaluation.id WHERE issue.issue_id = NEW.issue_id AND evaluation.outcome = 'running' AND run.outcome = 'running'
        AND ((input.role_code = 'group' AND input.group_version_id = NEW.group_version_id)
          OR (input.role_code IN ('managed-rule', 'protected-rule') AND input.rule_version_id = NEW.rule_version_id))`],
    ['adjudicated_issue_operations', `SELECT issue.issue_id FROM adjudicated_issues issue JOIN evaluations evaluation ON evaluation.id = issue.evaluation_id
      JOIN run_evaluations used ON used.evaluation_id = evaluation.id JOIN analysis_runs run ON run.id = used.run_id
      JOIN adjudicated_issue_members member ON member.issue_id = issue.issue_id
      WHERE issue.issue_id = NEW.issue_id AND evaluation.outcome = 'running' AND run.outcome = 'running' AND member.group_version_id = NEW.group_version_id`],
    ['adjudicated_operation_retirements', `SELECT operation.id FROM adjudicated_issue_operations operation
      JOIN adjudicated_issues issue ON issue.issue_id = operation.issue_id JOIN evaluations evaluation ON evaluation.id = issue.evaluation_id
      JOIN run_evaluations used ON used.evaluation_id = evaluation.id JOIN analysis_runs run ON run.id = used.run_id
      JOIN adjudicated_issue_members member ON member.issue_id = issue.issue_id
      WHERE operation.id = NEW.operation_id AND evaluation.outcome = 'running' AND run.outcome = 'running' AND member.rule_version_id = NEW.rule_version_id`],
  ]) {
    connection.exec(`CREATE TRIGGER ${table}_scope_INSERT BEFORE INSERT ON ${table} WHEN NOT EXISTS(${scope})
      BEGIN SELECT RAISE(ABORT, 'Adjudication output requires exact running component inputs'); END`);
  }
  for (const table of ['application_migrations', 'proposal_versions', 'change_revisions', 'change_placements', 'change_retirements', 'change_applicabilities',
    'plan_versions', 'plan_items', 'wording_versions', 'rule_versions', 'rule_provenances', 'rule_placements', 'rule_applicabilities', 'approvals', 'approval_reviews',
    'rendered_artifacts', 'artifact_files', 'group_versions', 'group_members', 'group_catalog_anchors', 'group_correspondences',
    'group_correspondence_members', 'group_relationships', 'group_relationship_evidence', 'adjudication_relationship_decisions', 'adjudicated_issues',
    'adjudicated_issue_members', 'adjudicated_issue_operations', 'adjudicated_operation_retirements',
    'issue_resolutions', 'resolution_issues', 'resolution_findings', 'resolution_changes',
    'llm_models', 'profile_llm_assignments', 'evaluator_profiles', 'analysis_run_contexts', 'analysis_run_llm_assignments']) {
    for (const operation of ['UPDATE', 'DELETE']) connection.exec(`CREATE TRIGGER application_${table}_${operation} BEFORE ${operation} ON ${table}
      BEGIN SELECT RAISE(ABORT, 'Application history is immutable'); END`);
  }
  for (const table of ['catalog_members', 'catalog_sources', 'catalog_evidence', 'catalog_member_sources', 'catalog_member_evidence', 'accepted_group_evidence',
    'catalog_surface_content', 'catalog_surface_sections', 'catalog_canonical_bindings', 'catalog_guidance_files', 'catalog_rule_guidance']) {
    for (const operation of ['INSERT', 'UPDATE', 'DELETE']) {
      const tests = (operation === 'INSERT' ? ['NEW'] : operation === 'DELETE' ? ['OLD'] : ['OLD', 'NEW'])
        .map(row => `EXISTS(SELECT 1 FROM catalog_versions WHERE id = ${row}.catalog_id AND finalized_at IS NOT NULL)`);
      connection.exec(`CREATE TRIGGER application_${table}_${operation} BEFORE ${operation} ON ${table} WHEN ${tests.join(' OR ')}
        BEGIN SELECT RAISE(ABORT, 'Finalized catalog is immutable'); END`);
    }
  }
  connection.exec(`
    CREATE TRIGGER capacity_policy_allocation_UPDATE BEFORE UPDATE OF guidance_token_budget ON capacity_policies
      WHEN NEW.guidance_token_budget < (SELECT coalesce(sum(guarded_limit), 0) FROM capacity_buckets WHERE policy_id = OLD.id)
      BEGIN SELECT RAISE(ABORT, 'Guidance reservation must contain its category allowances'); END;
    CREATE TRIGGER catalog_root_UPDATE BEFORE UPDATE ON catalog_versions WHEN OLD.finalized_at IS NOT NULL
      BEGIN SELECT RAISE(ABORT, 'Finalized catalog is immutable'); END;
    CREATE TRIGGER catalog_root_DELETE BEFORE DELETE ON catalog_versions WHEN OLD.finalized_at IS NOT NULL
      BEGIN SELECT RAISE(ABORT, 'Finalized catalog is immutable'); END;
  `);
}

// Initialize and verify an empty database atomically; populated databases require a separate supported migration.
export function migrateNewWorkbenchApplication(connection, { schemaVersion = workbenchSchemaVersion } = {}) {
  if (connection.readOnly || connection.isTransaction) throw new Error('Application initialization requires its own writable transaction');
  if (schemaVersion !== workbenchSchemaVersion) throw new Error('Application schema revision is not supported');
  if (connection.get("SELECT name FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%' LIMIT 1")) throw new Error('Application initialization requires an empty database; existing schemas need an explicit supported migration');
  connection.exec('BEGIN IMMEDIATE');
  try {
    createApplicationObjects(connection);
    connection.run('INSERT INTO application_migrations(version, applied_at) VALUES (?, ?)', [schemaVersion, new Date().toISOString()]);
    if (connection.all('PRAGMA foreign_key_check').length) throw new Error('Application migration failed referential verification');
    connection.exec('COMMIT');
  } catch (error) {
    if (connection.isTransaction) {
      try { connection.exec('ROLLBACK'); }
      catch (rollbackError) { throw new AggregateError([error, rollbackError], 'Application migration and rollback failed'); }
    }
    throw error;
  }
}

// Fingerprint stored DDL, including indexes and triggers, rather than trusting only a schema version number.
function schemaSignature(connection) {
  return createHash('sha256').update(JSON.stringify(connection.all("SELECT type, name, tbl_name, sql FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name"))).digest('hex');
}

const expectedSignatures = new Map();
// Build the authoritative schema in memory once per revision for non-mutating comparisons with existing databases.
function expectedSchemaSignature(schemaVersion) {
  if (!expectedSignatures.has(schemaVersion)) {
    const expected = openWorkbenchSqlite({ mode: 'memory' });
    try {
      migrateNewWorkbenchApplication(expected, { schemaVersion });
      expectedSignatures.set(schemaVersion, schemaSignature(expected));
    }
    finally { expected.close(); }
  }
  return expectedSignatures.get(schemaVersion);
}

// Inspect schema shape, migration history, enforcement settings, and integrity without repairing the selected database.
export function validateWorkbenchApplicationSchema(connection, { schemaVersion = workbenchSchemaVersion } = {}) {
  const problems = [];
  if (schemaVersion !== workbenchSchemaVersion) return { valid: false, schemaVersion, problems: ['unsupported-schema-version'] };
  if (schemaSignature(connection) !== expectedSchemaSignature(schemaVersion)) problems.push('schema-shape-mismatch');
  try {
    const versions = connection.all('SELECT version FROM application_migrations ORDER BY version');
    const revisions = versions.map(row => row.version);
    if (revisions.at(-1) !== schemaVersion || revisions.some((revision, index) => !Number.isInteger(revision) || revision < 1 ||
      revision > schemaVersion || (index > 0 && revision <= revisions[index - 1]))) {
      problems.push('unsupported-schema-version');
    }
  } catch { problems.push('missing-migration-history'); }
  if (connection.get('PRAGMA foreign_keys')?.foreign_keys !== 1) problems.push('foreign-keys-disabled');
  if (connection.all("SELECT name FROM pragma_table_list WHERE schema = 'main' AND name NOT LIKE 'sqlite_%' AND strict <> 1").length) problems.push('non-strict-tables');
  try { if (connection.all('PRAGMA foreign_key_check').length) problems.push('foreign-key-violations'); }
  catch { problems.push('invalid-foreign-key-schema'); }
  try { if (connection.all('PRAGMA integrity_check').some(row => row.integrity_check !== 'ok')) problems.push('storage-integrity-failure'); }
  catch { problems.push('storage-integrity-failure'); }
  return { valid: problems.length === 0, schemaVersion, problems };
}
