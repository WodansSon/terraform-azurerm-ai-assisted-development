# Hosted Workbench Process Agreement

## Status And Purpose

This document records the maintainer-agreed direction for simplifying the Hosted Workbench. It describes the intended experience and ownership, not a claim that the current implementation already provides them.

Recording this agreement alone does not authorize implementation, module deletion, database migration, or changes to existing safeguards. The maintainer subsequently approved the isolated New-prefixed copy and prototype implementation described below; SQL integration and legacy archival require separate approval. This is maintainer documentation, not deployed guidance or another machine-enforced workflow contract.

The [UI assessment](WORKBENCH_UI_ASSESSMENT.md) records exercised interactions, their backend implications, observed legacy quirks, and remaining coverage. Keep observed behavior separate from the agreed direction in this document.

## Start With The Maintainer Experience

- Preserve useful legacy behavior: Candidates, Assessments, Rule Issues, understandable evidence and mappings, editable wording, and explicit maintainer decisions.
- Make the UI's needs paramount. Do not start by inventing tables, schemas, contracts, or processing phases.
- Preserve the relationships between source passages, independently enforceable meanings, and synthesized recommendations. One source is not necessarily one proposed rule, and one proposed rule can have several supporting sources.
- Keep original AI assessments distinguishable from maintainer edits and decisions. Saving exact wording is separate from semantic checking; AI advice does not save, approve, or select changes.
- Preserve scope, conditions, exceptions, applicability, and supporting passages during analysis. Compare the whole working set, including proposals and saved edits hidden by filters or not selected for export.
- Evaluate the selected output separately. An unrelated, unselected alternative must not automatically block otherwise valid output.
- Prove useful behavior with representative maintainer actions. Passing schema, integrity, or source-shape checks alone does not demonstrate UI or semantic parity.

## Ownership

| Owner | Responsibility |
| --- | --- |
| UI | Interactive workflow logic, presentation, filtering, navigation, editing buffers, selections, comparisons, projected results, and readiness explanations |
| AI | Advisory semantic analysis of meaning, scope, coverage, overlap, and contradiction, with evidence and uncertainty |
| Thin backend | Data access, local AI execution, safe catalog writes, transactional SQL operations, and necessary boundary validation |
| SQL | Tool-owned configuration, current sources and analysis, proposals, edits, decisions, issues, and operational auditing |
| Catalog JSON | The single authoritative list of current maintainer-approved rules and the settings needed to generate their instruction files |
| Instruction generator | Deterministic rendering of the catalog into instruction files without another AI rewrite |

The backend still enforces stale-write protection, protected-rule restrictions, and valid mutations. It must not become a second workflow engine duplicating the UI. Instructions own rule wording; skills own review procedure.

SQL must not own a competing published catalog. Any SQL references or derived data needed for working comparisons must remain subordinate to the authoritative JSON.

## Reconciliation And Adjudication

Preserve semantic issue detection, supporting evidence, and maintainer control while removing rigid JSON workflow machinery. Moving storage into SQL must not recreate that machinery as relational structures or leave the same schema-driven AI response requirements in the checker prompts and result handling.

- Detect duplicates, equivalence, partial overlaps, and genuine contradictions using the rules' meaning, scope, conditions, exceptions, and supporting evidence, not merely similar wording.
- Apply the whole-working-set comparison requirements above, including existing catalog rules and saved edits. Reevaluate affected relationships when wording or decisions change.
- Create or update flat, evidence-backed Rule Issues from reevaluation findings, including remaining or newly introduced overlaps, identifying the affected rules, relevant passages, relationship explanation, and AI resolution suggestions. Keep ambiguity and unresolved disagreement visible for maintainer judgment.
- Keep responsibilities distinct: AI determines semantic meaning; SQL stores current relationships, evidence, issues, and decisions; the UI presents them for review.
- Do not let detecting an issue or suggesting a resolution automatically accept wording, select a change, or approve publication.
- Saving consolidated wording does not retire other rules. Existing rules remain active unless the maintainer explicitly chooses their retirement; AI may recommend retirement, refining wording, or retaining separately scoped rules, but must not apply those suggestions automatically.
- Align relationship-checking prompts and result handling with this review model. Preserve necessary boundary validation, protected-rule restrictions, and stale-write protection without treating legacy JSON contracts or failure gates as replacement requirements.

### UI-Led Reevaluation With SQL Support

The UI initiates reevaluation using current review context and saved data retrieved through the backend. The backend executes the AI request with the appropriate on-disk prompt; the UI presents the findings and refreshed calculations. SQL supports durable working data, not a database-driven review procedure.

- Compare revised wording against existing catalog rules and relevant proposed updates across the complete working set, including work hidden by filters or outside Plan.
- Identify newly introduced issues, earlier issues no longer supported by the revised wording, and remaining issues whose scope or explanation may have changed.
- Reevaluate semantic scoring factors and priority using the established assessment rubric. Recalculate token estimates, projected changes, and capacity headroom through deterministic calculations, not AI guesses.
- Keep the assessment of the revised proposal distinguishable from the original assessment. Do not imply that original scores evaluated wording that did not exist when they were produced.
- Identify issues resolved in the proposed working set as projected resolutions, not proof that the published catalog has been fixed. Reevaluation does not automatically accept wording, select changes, or approve publication.
- Account for saved current reevaluation findings, associated wording and evidence, relationships, issue dispositions, scoring, and maintainer decisions when designing the flatter SQL tables. Distinguish derived calculations from AI assessments without requiring storage of every intermediate calculation, editing state, or historical snapshot.

### Current Plan Relationships

- Derive Rule Issue status from current wording, saved decisions, and the Plan projection. An untouched proposal remains available for an explicit decision rather than appearing resolved merely because it is not selected. Explicitly declining a conflicting proposal or retiring its published participant resolves the applicable conflict; restoring unchanged conflicting participants restores the issue from retained evidence without another check.
- Keep existing catalog rules in the output projection unless the maintainer selects their retirement or replacement. Unselecting a proposal does not remove its published baseline.
- Keep a grouped issue open while any of its conflicting relationships remain. Removing one participant does not resolve other conflicts in the group.
- Accepting a complete applicable recommendation marks its issue Resolved unless known current conflicts or a genuine remaining validation need prevent that outcome. Findings about A/B and A/C do not establish a B/C conflict or invent a new comparison requirement. Keep actual unchanged conflicts and current checker findings open; issue resolution does not establish publication readiness.
- Preserve saved checks across selection changes. A successful wording edit invalidates only that subject's check while retaining its last relationship evidence for review; restoring earlier wording does not make an invalidated check current again.
- Present saved checker findings and explanations in Rule Issues. Details presents check status and a right-aligned Rule Issues navigation button instead of repeating the explanation. A failed check preserves prior evidence and reports the failure; it must not make an issue appear resolved.

## Failed Saves And The Saved Baseline

- A confirmed failed wording or decision save leaves the previously saved baseline unchanged. Preserve saved wording, decisions, and rationale; report the failed save explicitly.
- Keep attempted edits available for correction or retry. The UI may retain their working Plan and calculated projections without automatically reverting them to the saved baseline. That difference is expected working-state behavior, not itself a persistence defect.
- Distinguish unsaved edits and projections from successfully saved work. A failed save must not be presented as successful or allow its unsaved changes to be published as though they were saved.
- Reload restoring the saved baseline is consistent with a failed save. Whether unsaved buffers also survive reload is a separate retention decision, not evidence that the failed save should have changed the baseline. Unknown commit outcomes remain uncertain and must not be described as confirmed failures or successful saves without evidence.

## Save Presentation And Editing-Flow Scope

- Use the disk-shaped `save` icon and concise, action-specific labels for genuine Save actions throughout the replacement. This global visual convention includes future override editors, but does not authorize changing the legacy comparison baseline.
- Keep the accepted Candidate Details editing-flow prototype scoped to that experience. Evaluate other editors individually before adopting broader Undo, Restore, dependent-control, or keyboard-shortcut policy; shared Save artwork does not authorize a blanket behavioral rollout.

### Isolated New Workbench And Preserved Legacy Reference

- Copy the complete current Workbench and its required supporting implementation into [NewWorkbench](../NewWorkbench/), [NewTools](../NewTools/), [NewContracts](../NewContracts/), [NewRegression](../NewRegression/), [NewDocs](../NewDocs/), and [NewCopilotRuleCatalog source definitions](../NewCopilotRuleCatalog/source-definitions/). Rebind runtime dependencies to those owners; neither experience executes the other's backend.
- Preserve the existing legacy source, launcher, browser origin, and saved work unchanged as a usable comparison reference. This is a temporary side-by-side transition, not two permanent products.
- Implement the accepted browser prototype in the new source, including complete-decision comparison, separate dialog reset and original-baseline restoration, retained-owner defaults, and read-only resolved outcomes. Preserve Candidates, Assessments, Rule Issues, Plan, Preview, AI Assistance, evidence, and unrelated operations.
- Give the new launcher an independent default port, staged site, caches, intake namespace, IndexedDB database, and active-session preference. See the [launch and validation guide](../NewTools/README.md). Do not copy saved decisions, runtime credentials, or browser storage.
- Read the existing authoritative catalog and protected-rule sources without creating a competing published catalog. An explicitly selected display source may seed only validated display and Rule Issues artifacts, not mutable runtime state.
- Keep the browser prototype available until its source implementation and validation are complete; do not reload or remove the reference during implementation.
- Keep the rejected retained SQL runtime out of the new execution path. Define and integrate the approved simpler SQL persistence later; this step does not initialize, migrate, or connect SQL.
- Archive legacy source and its supporting files only after the new experience and backend are complete and the maintainer explicitly approves cutover.

### Accepted Candidate Details Interactions

- Distinguish the original proposal, the last saved draft, and pending edits. Wording Save and decision Save remain separate operations using the existing persistence flow; neither invokes AI.
- Lock Rule Actions, rationale, and decision Save while wording is dirty. Change the existing guidance to "Save or undo the wording changes before changing Rule Actions." Restore normal guidance when clean; do not add a competing warning.
- Also lock those decision controls when an active Rule Issue affects this rule in the current Plan. For grouped issues, evaluate this rule's remaining applicable pairs, not membership in the original group alone. Keep wording editing and candidate unselection available; unrelated rules and resolved or historical issues do not lock decisions.
- Preserve saved actions and rationale while issue-locked. When the issue no longer applies, restore normal action, metadata, and No Change editability without changing saved decisions or starting a check.
- Use the shared `.section-disabled` CSS state to preserve enabled geometry, typography, and hierarchy with fixed disabled colors. Shared header CSS retains semibold rule-reference emphasis in darker neutral gray; disabled radios retain the same filled-circle shape without per-option offsets or dynamic color scaling.
- Use Undo Current Changes to return to the last saved wording and action and clear pending rationale input. Preserve the saved rationale separately.
- Confirm Restore before returning this candidate's wording and Rule Actions to the original baseline. Save that candidate's baseline through the existing guarded draft transaction, clear its rationale and Plan membership, and remove only its bulk-operation membership. Preserve unrelated candidates, decisions, overrides, and work. A failed save retains the saved draft and pending text.
- Keep the original Codicons `discard` artwork for Undo and use the custom `restore` sprite symbol for Restore. Do not modify upstream `debug-restart`.
- Keep Ctrl+Z native. In the focused wording editor only, Ctrl+U performs Undo and Ctrl+R opens Restore confirmation. Escape cancels Restore and returns focus to the wording editor.
- Intercept Ctrl+S only in the focused wording or rationale editor when its associated Save is available; otherwise preserve browser behavior.
- Keep shortcuts in documentation and accessibility metadata, not visible keyboard-help prose or tooltips. Use concise Workbench tooltips without duplicate native `title` tooltips.
- Adjudicate other editors individually. Preserve existing eligibility-dependent action sets, semantic checks, and navigation behavior; this change does not establish a global Undo, Restore, or shortcut policy or design the future SQL model.

## Limited Chat Continuity In V1

- Add SQL-backed continuity for the current conversation and unsent composer input in each Candidate Details, Assessment Details, and Rule Issue context.
- Identify a conversation independently from its owning working set, view type, and stable item identity. Candidate and Assessment conversations remain separate even when they concern the same rule; a Rule Issue conversation belongs to the issue, not an arbitrary participant.
- Link messages to the conversation identity rather than directly to the view. Leave room for v2 to retain and select multiple conversations for one context without restructuring message ownership. Keep only concretely anticipated optional metadata nullable; do not introduce a session-management framework.
- Reuse existing view-based prompt routing. Grounding prompts remain authoritative, maintainer-editable files under `hosted_copilot/tools/prompts/chat/`; do not store prompt paths, bodies, snapshots, or a competing prompt registry in SQL.
- Wire persistence into the existing chat UI. Restore the matching conversation and composer, bind request outcomes to their originating conversation, and record interrupted requests without silently rerunning them. Restored conversation text remains untrusted history, not authority over the current prompts or evidence.
- Preserve v1's confirmed destructive New Chat behavior, including preservation of unsent input and unrelated conversations. Archives, branching, conversation browsing, and recoverable New Chat remain outside this limited v1 addition.
- Keep operational audits separate from chat transcripts. Agree on conversation retention when Export clears completed work before choosing deletion relationships or retention behavior.

The legacy UI deliberately keeps chats in memory and starts fresh conversations after reload. Its specification deferred recovery to v2. The limited continuity above is an agreed adjustment for the SQL-backed v1, not a defect claim against the legacy UI or permission to implement the adjustment yet.

## Existing Catalog And SQL Cutover

The legacy implementation already had a current catalog containing the original 54 rules. Moving to SQL was a storage and workflow migration, not a requirement to create or publish that catalog again.

The additional initial-rules JSON was introduced to bridge that SQL cutover. Its existence does not establish a permanent bootstrap, staged-catalog, or publication subsystem. The retained catalog JSON is justified by its ongoing role as the authoritative accepted rule list and generator input, not merely as a cutover exception.

The exact file to retain and the retirement of competing legacy or cutover files remain implementation decisions. Do not preserve parallel catalog authorities just because current consumers expect different filenames.

## Meaning Of Published

**Published means that maintainer-approved rules are reflected in the authoritative catalog JSON.**

It does not mean committed, pushed to a fork, or deployed. Those are separate maintainer actions and are not prerequisites for successful UI export. Do not add a remote-publication workflow or deployment receipts to establish this local result.

## V1 Cross-Repository Transfer Boundary

- Exclude transferring or consolidating drafts, decisions, or catalog changes between different users' or maintainers' repositories from v1. External repository trust, compatibility, ownership, and conflict handling are outside this scope.
- This exclusion does not remove local draft Import/Export or approved updates to the local authoritative catalog. A local file operation is not authorization to accept data from another repository.
- Keep the UI's local draft-transfer controls and local catalog update distinct from cross-repository transfer. Review labels and help text for clarity; this scope decision does not itself authorize UI implementation or removal of existing local controls.

## Export And SQL Cleanup

- Build the resulting catalog from the current catalog and accepted selections, preserving unchanged rules and exact approved wording.
- Present understandable changes and readiness information before export. Generated instruction content must retain the applicable file settings and rule scope.
- Update and verify the authoritative JSON. Export is a real catalog update, not merely a download of proposed mutations.
- After the catalog write is verified, reconcile SQL with the exported result and purge the corresponding completed working rows in one SQL transaction.
- Preserve unrelated drafts, newer edits, unfinished work, and unresolved issues affecting remaining work. Purging related work does not mean emptying every related table.
- Preserve useful audit records independently of the working rows being cleared. Do not retain permanent draft, snapshot, or lineage chains merely to explain completed work.

A file write and a SQL transaction are not atomic together. Complete export requires both the verified catalog update and successful SQL reconciliation.

- If the catalog update fails, do not clear pending SQL work.
- If the catalog update succeeds but SQL cleanup fails, report partial completion explicitly and preserve pending work. Do not claim that the entire export failed without changing the catalog.
- Recovery must recognize work already written to the catalog rather than blindly apply it again. The recovery mechanism remains to be designed; this agreement does not prescribe another history or synchronization subsystem.
- Report uncertain outcomes as unknown rather than inventing success, rollback, or preservation claims.

## Useful Operational Auditing

Recoverable failures still require durable SQL auditing even when the UI can retry or recover. Recording an attempt is separate from accepting its result: a failed request must preserve saved work, and a stale response must not overwrite newer work. Neither safeguard requires retaining every intermediate editing state, progress update, or discarded response body.

Use **Export** as the audit action/category, with an outcome such as **Succeeded**, **Failed**, or **Partially completed**. Stage-specific details belong in that operation's explanation, not a new category for every failure variation.

The audit comment must be a safe, self-contained diagnostic summary that a maintainer can copy into a support conversation without supplying the original database or terminal history. It should identify:

- When the action occurred and which meaningful rule IDs or items were involved.
- Which steps completed, including the catalog write and SQL cleanup.
- The specific safe failure reason, when known.
- What changed, what was preserved, and what remains uncertain.
- The evidence-backed next action, or an explicit statement that further diagnosis is needed.

For example, the following is an illustrative failure summary, not an actual runtime event:

> **Export - Partially completed**  
> Rules: EXAMPLE-001, EXAMPLE-002  
> Catalog: Updated and verified  
> SQL cleanup: Failed; transaction rolled back  
> Cause: Database write lock could not be acquired  
> Preserved: All pending work  
> Recovery: Reconcile cleanup with the updated catalog; do not reapply the exported changes

Audit comments must remain understandable after related working rows are purged. Never include secrets, raw authentication material, or unnecessary personal or machine-specific information.

If the audit cannot be saved, report that failure through the existing toast control, not a new UI element. Distinguish the operation's actual outcome from the audit-write failure: for example, "Decision saved, but its audit entry could not be recorded." Do not claim the audit was recorded or imply that a successful operation failed or was rolled back merely because logging failed.

## Machinery Not To Recreate

- Do not maintain competing JSON and SQL catalogs or add staged and published JSON copies as runtime authorities.
- Do not recreate tool-owned JSON caches, receipts, workflow contracts, or configuration files as a parallel persistence system. Ordinary request/response serialization and unrelated external-tool manifests are not the target.
- Do not hide the same document structures in SQL JSON columns.
- Do not default to immutable revision graphs, tombstones, historical snapshots, hashes, generic registries, elaborate response schemas, or more orchestration stages.
- Keep validation at meaningful boundaries, including untrusted AI responses, without rebuilding a sprawling contract framework.
- Do not treat legacy implementation details or SQL-cutover scaffolding as requirements without a concrete UI or operational need.

## Open Decisions And Required Alignment

- Identify the exact canonical catalog file and how existing catalog consumers transition without competing authorities.
- Determine the smallest SQL representation needed for current work and catalog references, and how export invalidates or refreshes affected analysis without discarding unrelated work.
- Define safe behavior for interrupted export, concurrent edits, and retries across the catalog write and SQL cleanup.
- Complete the UI capability inventory and behavioral checks before choosing which modules to retain, simplify, or retire.

Existing guidance needs deliberate alignment with this agreement:

- [Maintainer guardrails](../../AGENTS.md) currently place the accepted catalog in SQL, describe updating it together with cleanup in one database transaction, and express a narrower frontend responsibility split.
- [Hosted tools documentation](../tools/README.md) describes publication and completed-analysis startup requirements that need reassessment against the intended UI experience.
- [Catalog documentation](../copilot-rule-catalog/README.md) describes staged and fork-publication roles inherited from the earlier design.
- [The UI specification](HOSTED_RULE_WORKBENCH_UI_SPEC.md) and [implementation guide](HOSTED_COPILOT_CODE_REVIEW_IMPLEMENTATION.md) remain evidence of existing behavior, not automatic requirements to retain every historical gate or mechanism.

These are identified alignment items, not permission to edit those files or silently bypass current runtime checks.
