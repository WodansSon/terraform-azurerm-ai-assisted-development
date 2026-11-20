# Hosted Workbench UI Assessment

## Purpose And Authority

This is the ongoing interaction record for understanding the legacy Workbench before designing its SQL-backed replacement. It records actual browser exercises, not a complete parity claim, a database schema, or implementation approval.

The [process agreement](WORKBENCH_PROCESS_AGREEMENT.md) owns agreed product direction. The [UI specification](HOSTED_RULE_WORKBENCH_UI_SPEC.md) describes the existing experience. Differences between those sources need deliberate alignment rather than silent changes to runtime safeguards.

The shared invariant is that original assessments, eligibility corrections, edited wording, action decisions, Plan membership, relationship checks, conversations, and published rules are distinct facts. They can coexist and must not be collapsed into one status.

## Evidence And Safe Continuation

- Exercise the real UI. Source inspection can explain an observed result but does not establish that an interaction works.
- Use an isolated draft and preserve the maintainer's original draft. Make synthetic changes reversible through the UI.
- Keep motion enabled during automation and visual checks. Do not pause animations or enable reduced-motion emulation for stability.
- Verify completed saves rather than assuming an immediate post-click snapshot is final.
- Restore synthetic wording, decisions, and overrides, then verify across reload. An empty Plan alone is insufficient cleanup evidence because decisions can persist outside it.
- Do not put browser identifiers, private machine paths, credentials, local database identifiers, or run-specific recovery locations in this document.
- Do not infer publication behavior from Preview. Catalog Export, draft downloads/imports, clipboard writes, protected-source edits, and shared-server shutdown have not been executed in this walkthrough.

### Reading The Record

- **Observed:** A result exercised in the legacy browser UI.
- **Backend implication:** A distinction or operation the replacement design needs to account for, not a prescribed table or automatic approval of legacy behavior.
- **Open:** An unexercised branch or unresolved product decision.
- **Legacy quirk:** An observed behavior that must not become a replacement requirement without agreement.

## Candidates, Decisions, And Bulk Ownership

### Isolated Automated Validation

- **Observed:** The relationship-review journey passed 38 assertions using synthetic findings and failures. It checks dirty-wording decision locks, explicit wording and decision saves, relationship readiness, recovery controls, and cancellation. This is deterministic UI coverage, not proof of live AI semantics or backend process termination.
- **Observed:** The portable-review-state journey passed 65 assertions in a disposable browser context. It exercised exact local draft download/import, rejection of incompatible drafts without changing saved state, reload, snapshot-bound mocked relationship checks, and an approval-artifact download. The retirement fixtures distinguish retiring another rule through an ancillary selection from retiring the candidate's own rule through its primary action. Resolved Rule Issues remain visible as history.
- **Coverage limit:** The approval-artifact download did not update the authoritative catalog, reconcile SQL, deploy guidance, or transfer work between repositories. The maintainer's actual draft, clipboard, and shared server were not used.
- **Observed:** The manual-rule-editing journey passed 55 assertions. It exercised content-sized multiline wording, preservation of original assessment evidence, controlled save failure and retry, separate decision Save, explicit mocked relationship checking, projected-issue and rationale gates, Restore, and resolution-dialog persistence, cancellation, focus, and stale-write checks. Clipboard operations used a stub, not the system clipboard.
- **Prior automated failure:** After the bulk/manual ownership journey completed an explicit clean relationship check, Plan readiness was `Ready`, but the rendered candidate row retained its Needs input decoration. The journey deliberately failed on that mismatch instead of forcing a render or weakening readiness checks. The approved runtime correction has since been exercised manually, including candidate labels, icons, and parent readiness; the owning automated rerun is pending.
- **Coverage limit:** The later bulk/manual ownership transitions were not reached after that failure. These focused journeys do not complete the broader acceptance inventory below or approve SQL integration.

### Current Plan Relationship Validation

- **Observed:** Saved relationship-check findings appeared in Rule Issues. A fresh conflict result superseded an older duplicate classification for the same pair without hiding the conflict. Current wording remained visible when older retained findings also referenced that participant.
- **Observed:** Removing one counterpart from a grouped conflict left the remaining conflict active. Removing the last conflicting counterpart resolved the issue for the current Plan. Reselecting unchanged counterparts restored the conflict from saved evidence.
- **Observed:** Removing the conflicting subject left the two non-conflicting selected rules and their parent folders green. Reselecting it restored the applicable warnings. Candidate labels, status icons, parent labels, parent icons, issue counts, and Preview readiness followed the current Plan.
- **Observed:** Seven selection-only transitions issued zero checker requests and preserved the saved relationship reviews exactly. These transitions changed applicability, not the saved check evidence.
- **Observed:** After checking only the common subject, removing it left two remaining participants without pair evidence. The contradiction remained Needs Review. An explicit check of a remaining participant revealed their conflict instead of assuming that removing the common subject made them compatible.
- **Observed:** Visibly removing the conflicting clause made the previous check stale while retaining its findings. A declared failed check displayed an error and preserved that evidence. Retrying with the saved corrected wording resolved the remaining pair conflict while retaining findings against an unselected proposal.
- **Observed:** Editing an unselected rule did not select it into Plan. Saving its previously checked wording again left the saved check stale; reselecting it required revalidation rather than resurrecting the old valid status.
- **Observed:** Reload preserved saved decisions and relationship evidence exactly, including the unresolved conflict and the resolved older duplicate.
- **Validation handling:** An interrupted helper sequence edited the previously open Details subject rather than the intended rule. Its synthetic wording was visibly restored and explicitly rechecked. That interrupted sequence is not counted as a pass; the unselected-edit scenario was exercised separately against the explicitly opened subject.
- **Coverage limit:** These are isolated manual UI exercises using declared synthetic findings, complete production comparison evidence, and an explicit failure response. They do not prove live AI semantics, approval or Export behavior, SQL integration, or the latest automated journeys. No additional automated cases were authored in this phase.

### Selection And Action Are Separate

- **Observed:** Checking a candidate selected it into Plan as Manual with No Change and Needs action. It did not accept the recommended Add.
- **Observed:** Choosing Add, supplying a decision rationale, and saving produced a catalog mutation projection and a required relationship check.
- **Observed:** Merely opening a row selected its Details context without changing its Plan checkbox. Narrow layouts also expose separate Candidates and Details tabs.
- **Backend implication:** Preserve membership, chosen action, action rationale, recommendation, and currently displayed item separately.

### Search-Scoped Bulk Acceptance

- **Observed:** Bulk Actions reported the current result scope and separate counts for recommended Adds, Updates, and all actionable recommendations.
- **Observed:** Searching narrowed the bulk scope; expanding a group alone did not. A rule-ID search could match related evidence and return more than one candidate.
- **Observed:** Accepting scoped Updates preserved separately entered Manual work and attributed the accepted items as Bulk with generated rationales.
- **Observed:** Recommended Adds and All Actionable were exercised on separate one-candidate Add scopes. Already accepted or later manually deferred items were not eligible for duplicate bulk acceptance.
- **Observed:** All Actionable accepted a mixed batch containing one Add and two Updates. All three appeared as Bulk with generated rationales and independent relationship-readiness states. Reopening the same search showed zero actionable recommendations.
- **Observed:** Saving a wording-only edit on a Bulk Add preserved its Bulk attribution, chosen action, and generated decision rationale. Undo Last Bulk Selection then removed the decision and restored the original wording, No Change, and an empty rationale.
- **Backend implication:** Bulk ownership is not just the current action value. Preserve which operation owns which work and respect later manual decisions.

### Undo And Decisions Outside Plan

- **Observed:** Plan offered All, Manual, Bulk, and Override undo scopes, plus per-item Undo.
- **Observed:** Scoped Bulk undo removed its Bulk items while preserving a Manual Add. Scoped Manual undo removed the synthetic issue-resolution decisions.
- **Observed:** Candidate-menu Undo Last Bulk Selection removed its batch independently.
- **Observed:** A second one-item bulk batch coexisted with the earlier mixed batch. Undo Last Bulk Selection removed only the newer item; Plan preserved the earlier Add and two Updates with their Bulk attribution and readiness states. A second undo removed the earlier batch even while the search targeted a different candidate.
- **Observed:** A Bulk-added candidate was manually changed to Defer. Saving removed it from Plan but retained the Defer decision and its exact rationale across reload.
- **Observed:** That manual Defer was no longer owned by the earlier bulk operation. Undoing a later independent bulk batch preserved it.
- **Observed:** Selecting No Change immediately cleared that decision's rationale, disabled the rationale editor, and updated the saved state without another Save click. Reload confirmed No Change and an empty rationale.
- **Observed:** Direct Undo All removed a selected Bulk Add and a selected Manual No Change item together. An independently saved Defer outside Plan retained its exact rationale, and the pre-existing unselected override was preserved. Reload confirmed those distinctions with Plan empty.
- **Observed:** Direct Undo All also removed a selected Override item and its applied eligibility correction. Reload restored the original Exclude assessment without a contested marker and preserved the pre-existing unrelated override.
- **Backend implication:** Persisted work can exist outside Plan. Bulk undo, clearing a decision, and removing membership are not interchangeable operations.

## Wording And Original Assessment Evidence

### Editing, Saving, And Resetting

- **Observed:** Unsaved wording enabled Save and Reset. Saving wording alone did not automatically select a Plan mutation.
- **Observed:** Saved wording was marked Maintainer edited, while assessment rationale and scoring were explicitly identified as evidence for the original baseline.
- **Observed:** Selecting an action changed detail-level estimates before saving the decision changed Plan projections.
- **Observed:** Confirmed Reset restored the original synthesized proposal, not necessarily the active catalog wording. It preserved the independently saved action, rationale, and membership.
- **Observed:** Saving wording on a previously No Change candidate left it outside Plan with Action Required and no selected action. Confirmed Reset restored original wording without selecting an action; choosing No Change then returned it to No Change immediately, without another Save click.
- **Observed:** Per-item Plan Undo cleared the synthetic decision and active selection and restored No Change with no rationale.
- **Backend implication:** Original assessment evidence, original proposal wording, saved maintainer wording, unsaved editor text, and saved decisions need distinct ownership. Reset wording must not implicitly undo unrelated decisions.

### Unsaved Buffers And Save Boundaries

- **Observed:** Unsaved wording, an Update choice, and its pending rationale survived switching between Candidates and Details for the same rule. They also survived a round trip through Plan without changing rules. Both Save controls remained enabled, while Plan remained empty.
- **Legacy quirk:** Selecting another candidate and returning discarded all three pending fields without a discard confirmation. The other candidate retained its own original wording, No Change, and empty rationale. This buffer-loss behavior is not an agreed replacement requirement.
- **Observed:** Reload without saving restored the original wording, No Change, and empty rationale rather than the pending edits.
- **Observed:** Clicking the wording Save icon with an unsaved Update choice and rationale persisted the wording alone. Plan remained empty, and no relationship check started. Reload preserved the edited wording with no selected action and an empty rationale.
- **Legacy quirk:** That wording save also cleared the pending action choice and rationale from the current editor. Preserving separate save boundaries does not imply agreement to discard unrelated unsaved fields.
- **Observed:** In the opposite exercise, clicking Save decision with unsaved wording, Update, and a rationale saved all three and selected the item into Plan as Manual. The wording became Maintainer edited, both Save controls became disabled, and relationship revalidation remained required. Reload confirmed the exact edited wording, Update, and rationale persisted.
- **Backend implication:** The legacy save scopes are asymmetric: wording Save persisted wording alone, while the exercised decision Save also committed pending wording. Separate facts do not necessarily mean separate user operations, but the replacement needs an explicit, agreed write scope rather than inheriting that coupling implicitly.
- **Observed:** Per-item Plan Undo removed that synthetic decision and wording edit. Reload confirmed original wording, No Change, an empty rationale, disabled wording Save and Reset, an empty Plan, baseline issue count and capacity, and preservation of the pre-existing unrelated override.
- **Backend implication:** Editing buffers, saved wording, saved action/rationale, and Plan membership are distinct. Each Save control needs an explicit write scope; preserving UI buffers does not itself require automatic SQL writes.
- **Open:** Replacement behavior for retaining or warning about unsaved fields across rule changes, reload, and saving another field, including whether decision Save should also commit pending wording. Only the Update decision was exercised with unsaved wording; other actions are not proven by this result.

### Blank Wording

- **Legacy quirk:** Saving blank wording reported success, disabled Save, and produced no new validation error in the exercised path.
- **Observed:** Valid wording was immediately restored through confirmed Reset.
- **Open:** Export was not attempted. Neither the final treatment of blank wording nor a replacement policy has been established.

## Assessment Contest And Eligibility

### Independent Correction And Action Rationales

- **Observed:** Contest Assessment opened a provisional Eligible for Candidate Sources correction with its own required override rationale.
- **Observed:** Applying it moved an originally excluded rule into the Overrides candidate branch and selected it into Plan as Override, No Change, Needs action.
- **Observed:** Choosing Add required a separate decision rationale. Saving that action changed the Plan attribution to Manual and introduced a relationship-check requirement.
- **Observed:** The original assessment remained Exclude and read-only, with a Contested marker. Details could simultaneously show Excluded, Contested, and Maintainer Included.
- **Observed:** Override rationale, maintainer attribution, and save time were separate from original AI evidence. Editing the override rationale persisted across reload.
- **Backend implication:** Correcting applicability does not replace the original assessment or approve a catalog action. Candidate eligibility and Plan ownership can change independently.

### Cancel, Remove, And Scoped Undo

- **Observed:** Cancel Override closed the unsaved editor without changing eligibility or Plan. Reopening retained its unsaved rationale; Cancel did not mean erasing the buffer.
- **Observed:** Remove Override removed the associated Plan decision and cleared the active selection while preserving the original excluded assessment.
- **Observed:** Scoped Undo Override Items removed both the newly selected Plan item and its eligibility correction. The pre-existing unrelated override was preserved.
- **Observed:** Reload confirmed the exercised assessment had its original exclusion and no applied override.
- **Open:** Stale-source behavior and changes to assessment evidence while corrections exist.

## Rule Issues And Resolution Controls

### Navigation And Protected Evidence

- **Observed:** Previous/Next Issues scrolled the category-tab strip without switching the selected issue. Selecting a category explicitly changed the issue and its assistance context.
- **Observed:** Dismissing an issue message hid its banner without resolving the issue or changing Plan.
- **Observed:** Protected participants were read-only and identified as immutable. Issue assistance could discuss them as evidence without making them editable.
- **Observed:** Some contradictions showed Consolidated Wording Unresolved rather than offering a selected replacement.
- **Backend implication:** Category-strip position, selected issue, dismissed presentation, protected authority, and issue resolution are different states.

### Individual Resolve Dialog

- **Observed:** A Resolve header icon opened a separate action/rationale editor. Its initial Update choice did not imply an existing Plan decision.
- **Observed:** Reset Changes restored the initial action and rationale in the exercised dialog without modifying Plan.
- **Observed:** Saving a Retire resolution created a Manual Plan decision, marked the protected issue Resolved, and changed Preview from Blocked to Draft.
- **Observed:** The resolved message explicitly distinguished the projected relationship resolution from catalog validation. The retirement still required relationship checking.
- **Observed:** Reopening after grouped recommendations exposed Updated versus Original wording. Update was disabled for the changed-since-adjudication updated wording and became available after choosing Original. Cancel discarded those pending wording/action changes.
- **Observed:** A proposed participant's Resolve dialog started with Exclude selected and Save disabled until a rationale was entered. Changing to Defer and entering a rationale enabled Save without changing Plan. Tab from Save wrapped to Reset Changes; Escape closed the dialog and returned focus to its Resolve button. Reopening discarded the unsaved action and rationale and restored the initial Exclude choice.
- **Backend implication:** Resolve has its own editing buffer and save boundary. An issue addressed by the projected Plan is not automatically ready for approval or publication.
- **Open:** Other resolution shapes, editable consolidation, and reset behavior for additional field combinations.

### Grouped Recommendations

- **Observed:** Apply Recommended Actions immediately created two Manual decisions without confirmation, preserved the protected owner, and supplied a shared recommendation rationale.
- **Legacy quirk:** Applying it after a manually saved resolution replaced that manual rationale. This overwrite has not been accepted as replacement behavior.
- **Observed:** Two selected decisions produced only one catalog mutation because the other decision was Exclude.
- **Backend implication:** Distinguish selected decisions from mutations and preserve meaningful operation attribution. Do not infer a desired overwrite policy from this observation.

### Multi-Rule Resolution Without One Consolidated Rule

- **Observed:** A three-participant overlap recommended updating one existing owner, keeping another existing owner unchanged, and deferring the composite proposal. Its Consolidated Wording Unresolved explanation explicitly retained separate owners rather than selecting one replacement text. The issue explanation and participant text were read-only in the exercised issue view; the individual Resolve dialogs offered action and rationale controls, not a consolidated-wording editor.
- **Observed:** Apply Recommended Actions created two Manual Plan items: Update with a required relationship check, and Defer marked Ready with zero draft token cost. The unchanged owner did not become a third Plan item. The issue became Resolved while its split-wording explanation remained visible.
- **Observed:** After reload, undoing the Update left the Defer selected in Plan with the shared recommendation rationale. The issue displayed Resolved alongside Apply 1 Remaining Action. Undoing the remaining Defer returned the issue to Overlap and restored Apply Recommended Actions.
- **Backend implication:** Issue participants, per-rule recommendations, applied decisions, catalog mutations, and projected issue resolution are distinct. A resolved relationship does not require one consolidated rule or mean that every recommended improvement is applied. These observations do not establish which replacement resolution criteria should be used.
- **Observed:** Cleanup through the two per-item Undo controls was verified after reload: the affected dialogs showed their original proposal text and empty rationales, Plan was empty, issue count and headroom matched baseline, and the unrelated override remained present.
- **Open:** Editing and accepting genuinely consolidated wording, other grouped resolution shapes, and the replacement's issue-resolution criteria. No relationship AI check or publication was performed in this exercise.
- **Coverage limit:** This exercise applied existing recommendations, not fresh AI reevaluation. It does not prove that saving consolidated wording preserves other active rules, detects remaining overlaps, creates or updates Rule Issues, or supplies new AI resolution suggestions. Those are replacement requirements governed by the [process agreement](WORKBENCH_PROCESS_AGREEMENT.md#reconciliation-and-adjudication), not verified legacy behavior.

### Manually Combined Wording And Fresh Relationship Checking

- **Observed:** A reversible manual edit combined an existing layout obligation with a candidate's proposed summary-wording guidance. Wording Save persisted the combined text without selecting a Plan item. A separately saved Update and rationale then created one Manual Plan item; no retirement was selected and no Export was performed.
- **Observed:** A fresh live relationship check returned Relationships Need Review. It identified a partial overlap with the existing layout rule, quoted the matching requirement from both rules, and explained that the broader combined rule was not equivalent to the layout-only rule.
- **Observed:** The result did not rewrite the saved wording or add another Plan action. Plan retained the single Update with Relationships Need Review. The displayed priority and factors remained explicitly attributed to the original assessment, not a fresh score for the combined wording.
- **Coverage limit:** This exercised manual wording acceptance and live overlap detection, not an editable consolidated-wording control in the issue view, automatic Rule Issues creation, new resolution suggestions, revised semantic scoring, or publication. The inline finding and unchanged issue count do not establish the replacement's end-to-end reevaluation flow; the source-confirmed Rule Issues integration gap below remains relevant.
- **Observed:** Per-item Undo removed the temporary Update and combined wording. Reload verified original proposal wording, No Change, an empty rationale, disabled wording Save and Reset, an empty Plan, baseline issues/headroom, and preservation of the unrelated override.

## Relationship Checks Are Separate AI Operations

- **Observed:** Saving edited wording and an Update decision produced Relationship Check Required.
- **Observed:** Clicking the pill launched a live operation with Checking Relationships, elapsed time, and inline and toolbar Cancel controls. Its displayed scope was saved wording against the proposed catalog.
- **Observed:** Navigating to Preview preserved the operation. Approval still showed a pending relationship requirement.
- **Observed:** Completion returned Relationships Need Review with an overlap explanation and both quoted rules. It did not rewrite wording, approve the change, or satisfy the unresolved relationship gate.
- **Observed:** A subsequent unsaved wording edit immediately changed the pill to Revalidation Required and hid the old result details. Saving preserved that invalidated state in Plan.
- **Observed:** Canceling a new relationship check through its inline control removed both Cancel controls and the progress display. The browser request was aborted, the item returned to Relationship Check Required, and its saved Bulk Update and rationale remained intact. This did not prove termination of the backend AI process.
- **Observed:** A one-shot, page-local malformed response produced Relationship Check Failed with failure code `invalid-response`, recovery `retry`, and an enabled Retry relationship check control. The saved Update, rationale, original wording, and Plan membership remained intact. This was a deliberate negative-response exercise, not a genuine backend failure or a manufactured clean result; the interception was removed afterward.
- **Observed:** Reloading without changing comparison inputs preserved that failure and its Retry control. Dismissing its banner left the failure pill and saved decision intact; reload displayed the banner again.
- **Observed:** Clearing another candidate's saved Defer outside Plan changed the earlier failure to Revalidation Required. This was comparison-input invalidation, not evidence that reload had lost the failure.
- **Observed:** During a real retry, saving wording on another mapped candidate outside Plan changed the checked item to Revalidation Required while the request remained pending. Completion did not make the review current. The newer wording and the checked item's Update, rationale, original wording, and Plan membership were preserved. After restoring the comparison inputs, the failure explanation reported that the rule or catalog had changed and requested a new check.
- **Observed:** Editing the checked rule during a live request aborted the browser request and removed the active-check control. The unsaved edit remained in the editor with Save enabled and Revalidation Required; the saved Update, rationale, and Plan membership were preserved. Restoring the original wording disabled Save and exposed a failed attempt with code `snapshot-changed` and recovery `refresh-snapshot`. This does not establish backend process termination.
- **Legacy quirk:** That failure's recovery text suggested saving current wording or reloading before a new check. With the original wording restored, reload preserved the non-retryable failure without a Retry control. Clicking its failed-status pill displayed the failure rather than starting a fresh check. Recovery for unchanged saved inputs remains unresolved; this behavior is not an agreed replacement requirement.
- **Backend implication:** Advisory chat, relationship adjudication, issue resolution, wording saves, and approval are distinct operations. Results need to stay associated with the work they actually evaluated.
- **Backend implication:** Failure outcome, retry eligibility, comparison validity, and banner dismissal are separate facts. Comparison validity can depend on saved work outside Plan and outside the currently visible candidate; retaining a result does not authorize applying it to changed work.
- **Backend implication:** Invalidating an attempt must not consume unsaved editor text or change saved work. A retained failed-attempt outcome and eligibility to launch a fresh check are separate concerns; resolve the observed recovery gap before copying legacy failure gating into the replacement.
- **Source-confirmed gap:** The legacy checker saves results per candidate and renders findings in that candidate's relationship panel. Its completion path does not add those findings to the Rule Issues collection. See [the legacy app](../workbench/app.js). Inline relationship findings are not proof of the agreed reevaluation-to-Rule-Issues flow.
- **Open:** Applying an overlap resolution, backend termination after cancellation or reload, other failure classes, backend restart, fresh-check recovery after a non-retryable failure, and invalidation caused by an authoritative catalog change.

### Reload During A Relationship Check

- **Observed:** A saved Update and synthetic rationale provided the baseline. Reloading while Checking Relationships was visible preserved the Update, exact rationale, original proposal wording, and one Plan item. After draft loading, the item showed Revalidation Required with no visible active-check controls.
- **Observed:** Explicitly starting a fresh check succeeded without changing the saved inputs. It returned Relationships Checked rather than findings or a failure. Another reload preserved that result and rationale, and Plan showed the item as Ready.
- **Backend implication:** Saved maintainer work, an in-flight browser operation, a completed relationship result, and item readiness are distinct. A fresh check can recover this exercised interruption without resaving or rewriting the rule; its no-findings result is not proof of semantic correctness, catalog publication, or overall Export readiness.
- **Coverage limit:** This was a browser reload, not a backend restart or verified termination of the original AI process. It does not prove that the interrupted attempt was durably audited or that the separately observed non-retryable-failure recovery gap is resolved.
- **Observed:** Per-item Undo removed the temporary decision. Reload verified original proposal wording, No Change, an empty rationale, disabled wording Save and Reset, an empty Plan, baseline issues/headroom, and preservation of the unrelated override. No Export or runtime source change was performed.

## Chat Contexts And Lifetime

### Exercised Legacy Behavior

- **Observed:** Candidate advice used the selected wording, including an unsaved edit in a follow-up, and distinguished it from the original assessment.
- **Observed:** Suggestions appeared separately with Copy; they were not automatically adopted, saved, selected, or approved.
- **Observed:** New Chat required destructive-clear confirmation, cleared the captured conversation, and preserved unsent composer input.
- **Observed:** Canceling an advisory request showed Operation canceled and restored its request text to the composer. Independent backend process termination was not audited.
- **Observed:** Issue assistance used the issue, all affected rules, recorded evidence, and catalog snapshot while explicitly excluding drafts and Plan changes.
- **Observed:** Switching issues during a live request displayed a separate conversation. Returning restored the original pending thread; completion remained with the originating issue.
- **Observed:** Issue advice could distinguish conflicting candidate-level and issue-level recommendations without automatically reconciling them or changing Plan.
- **Observed:** Reload started fresh chats. This was intentional legacy v1 scope, not a defect.

### Concurrent Requests And Context-Owned Input

- **Observed:** Candidate and Rule Issue advisory requests were visibly pending at the same time. Starting the second request did not require the first to finish. The pending context's composer was read-only.
- **Observed:** Canceling the Candidate request retained its earlier completed response and restored the canceled request text to its own composer. The Issue request remained pending, then completed in its originating Issue conversation. This establishes independent browser-side cancellation, not termination of the canceled backend process.
- **Observed:** Candidate and Rule Issue composers retained different unsent text when switching between views. An overridden rule also retained different unsent questions in its Candidate and Assessment views even though both views referred to the same rule identity.
- **Observed:** Closing and reopening AI assistance preserved the Candidate's unsent composer input. Dragging its resize separator changed panel width; dragging it back restored the original width without changing Plan.
- **Backend implication:** One global active-item or request-status field cannot represent these interactions. Conversation ownership includes view context, and pending operations and their terminal outcomes belong to the originating conversation rather than the currently visible panel. Simultaneous browser requests do not prove parallel backend process execution.
- **Open:** Scroll-following behavior, other layout resizers, and persistence of panel preferences across reload.

### Failure And Retry

- **Observed:** Aborting one page-local advisory request displayed a failure and enabled Try again. The exact submitted question returned to the composer, while a separately saved Defer, rationale, and original wording remained intact. The interception was removed afterward.
- **Observed:** Changing unsaved wording disabled Try again; restoring the submitted wording reenabled it. Retry sent the original question even when a different unsent question was in the composer.
- **Observed:** A real retry succeeded on the existing user turn without duplicating it. Its reply replaced the visible failure, preserved the different unsent composer input, and left the saved Defer and rationale unchanged.
- **Backend implication:** A visible conversation turn and an operation attempt are not interchangeable. Successful retry can replace a visible error without removing the need for the independent operational audit agreed in the [process agreement](WORKBENCH_PROCESS_AGREEMENT.md#useful-operational-auditing). Retry must distinguish captured request input from newer unsent input.
- **Open:** Other failure classes and interrupted-request recovery in the replacement runtime. The exercise does not establish backend process termination or SQL audit persistence.

### Agreed SQL-Backed V1 Difference

The [limited chat-continuity agreement](WORKBENCH_PROCESS_AGREEMENT.md#limited-chat-continuity-in-v1) deliberately changes reload behavior. It owns the agreed persistence scope, conversation identities, v2 accommodation, and the decision to keep prompts on disk. Do not reproduce prompt routing or prompt contents in SQL.

- **Backend implication:** Persist the correct conversation and unsent input without mixing Candidate, Assessment, and Rule Issue contexts or redirecting in-flight outcomes.
- **Open:** Conversation lifetime when Export clears associated working data.

## Preview, Readiness, And Status

### Preview And Review Changes

- **Observed:** A populated Plan rendered virtual proposal wording, per-item payloads, and resulting catalog changes, with protected evidence shown separately.
- **Observed:** Filtering Preview narrowed its file navigation tree without hiding the other diff cards.
- **Observed:** Marking a file Viewed automatically collapsed its card. Re-expanding retained Viewed; reload cleared Viewed markers and the Preview filter while preserving saved decisions.
- **Observed:** Review Changes distinguished selected Plan actions, catalog mutations, rationale completeness, mutation targets, projected catalog issues, relationship requirements, and saved wording.
- **Observed:** No blocking projected issue did not imply approval readiness: a pending relationship check kept Approve & Export disabled.
- **Observed:** With three pending relationship checks, Review Changes offered a correction link that opened the first affected candidate's Details, focused its relationship pill, and showed its matching assistance context. Navigation did not start a check automatically.
- **Observed:** The projected-catalog-issue correction link opened the blocking protected issue, focused its issue entry, and displayed the matching Issue assistance context without starting AI or changing Plan.
- **Observed:** Expand Up revealed hidden catalog-diff context. Collapse all lines restored the folded view, and Expand all lines revealed the context again without changing Plan membership. Clicking the collapsed catalog file's tree entry left its diff card collapsed.
- **Observed:** Escape closed the Review Changes popover and returned focus to Review Changes. This popover was separate from the modal Resolve editor.
- **Backend implication:** Readiness is an explanation of several independent conditions, not one generic validation bit. Viewed and collapsed are presentation states, not approval evidence.
- **Open:** Other diff shapes and successful approval. Export has not been executed.

### Status Bar Navigation

- **Observed:** Eligible opened candidate browsing and cleared search. Excluded opened Assessment Results with a separate search.
- **Observed:** Mapped and Not mapped applied their corresponding candidate filters. Headroom navigated to Plan capacity.
- **Observed:** A nonzero warning focused a required relationship correction rather than opening a generic Problems panel.
- **Observed:** With three relationship warnings, three consecutive status-warning clicks targeted the first pending candidate rather than cycling through candidates. They focused the relationship pill without automatically starting an AI operation.
- **Observed:** Plan membership, issue counts, projected capacity, validation, and save status updated as work changed.
- **Observed:** An empty Plan could show No Problems while Preview remained Blocked by an existing catalog issue.
- **Backend implication:** Effective eligibility, original assessment categories, projected catalog issues, Plan validation, and Export readiness must remain distinguishable.
- **Open:** Nonzero-error navigation, additional tooltips, and layout resizing.

## Persistence And Publication Boundaries

- **Observed:** Reload restored saved wording, decisions, eligibility overrides, and their independently exercised effects. It did not restore every navigation or editing detail.
- **Source-confirmed:** The legacy working draft uses IndexedDB, with the active session identifier in localStorage. The initialization and persistence paths are in [the legacy app](../workbench/app.js). This explains draft restoration; it does not prescribe replacement storage.
- **Observed:** Draft options exposed Export Draft and JSON Import Draft. Neither was executed.
- **Open:** Startup navigation readiness needs a controlled check. During one reload, opening Plan before the draft-loaded notification produced a capacity-related JavaScript error and an empty workspace at that instant. Later navigation and cleanup succeeded; repeatability and any effect beyond presentation have not been established.
- **Observed:** After the failure/retry and cross-candidate invalidation exercises, per-item Undo, confirmed wording Reset, and No Change restored all exercised candidates to original wording, empty rationales, and No Change. Reload confirmed those states, an empty Plan, baseline issue count and capacity, and preservation of the pre-existing unrelated override.
- **Backend implication:** Working-data restoration, portable draft transfer, and published catalog loading are different operations.
- **Agreed direction:** SQL owns working data; the authoritative catalog remains JSON. The process agreement owns actual Export, reconciliation, cleanup, and audit requirements.
- **Agreed direction:** The [v1 transfer boundary](WORKBENCH_PROCESS_AGREEMENT.md#v1-cross-repository-transfer-boundary) excludes cross-repository transfers, not local draft Import/Export or local catalog updates. Cross-repository transfer is not a remaining v1 walkthrough requirement.
- **Open:** Local draft Import/Export, other failed-save paths, source incompatibility, and local publication/recovery behavior require safe test conditions. Review local-control labels and help text against the agreed transfer boundary before proposing UI changes; no such UI alignment has been implemented or verified.

### Failed Saves And Durable Versus In-Memory Work

- **Observed:** A saved Defer and rationale provided the baseline for two controlled failure exercises. Each used a one-shot, page-local abort of the matching IndexedDB write transaction; the temporary interception was removed afterward. These were deliberately induced browser-storage failures, not actual SQL or backend failures.
- **Observed:** Failed wording Save displayed Save failed and an error toast saying the wording was not saved. The exact unsaved wording remained in the editor with Save enabled. The saved Defer, rationale, and empty Plan were preserved. Reload restored original wording and the saved Defer/rationale, confirming that the failed wording had not persisted.
- **Observed:** Reentering that wording after reload and saving normally succeeded, preserved Defer and its rationale, and disabled wording Save. Confirmed Reset then restored the original wording.
- **Observed:** Failed decision Save displayed Save failed and an error toast. The live UI retained the attempted Update and rationale, one Plan item, and changed issue/count projections, with Save enabled. Reload restored the previously saved Defer/rationale, original wording, and empty Plan, confirming that the attempted decision had not changed the saved baseline.
- **Agreed interpretation:** Both exercises preserved the saved baseline as expected. Retaining attempted edits or their working projections after failure is not itself a workflow defect and does not require automatic rollback of the UI. The [failed-save agreement](WORKBENCH_PROCESS_AGREEMENT.md#failed-saves-and-the-saved-baseline) owns the distinction between pending work, confirmed persistence, and publication; these exercises did not test publication of unsaved changes.
- **Observed:** Final cleanup removed the temporary Defer through No Change. Reload verified original wording, No Change, an empty rationale, disabled wording Save and Reset, an empty Plan, baseline issues/headroom, preservation of the unrelated override, and removal of the fault hook.
- **Open:** Direct decision-save retry, other save paths, unknown commit outcomes, and SQL-specific failure/audit behavior. These exercises do not prove replacement transaction safety or durable operational auditing.

## Next Assessment Work

- Exercise other diff shapes without approving or exporting.
- Exercise the remaining relationship failure and invalidation branches without manufacturing a clean result; distinguish browser cancellation from backend termination.
- Exercise other chat failures, interruption/recovery, scroll-following controls, remaining layout resizers, and other modal dismissal paths.
- Exercise remaining resolution variants and distinguish unsaved-buffer cancellation from durable state changes.
- Resolve product decisions separately from observations, especially legacy overwrites and chat retention after Export.
- Leave file transfer, clipboard mutation, protected-source edits, Export, and shared-server shutdown unexecuted unless explicitly approved for a safe exercise.

## Keeping This Record Current

- Update the relevant interaction section after each meaningful exercise, not only after implementation starts.
- Record the action, observable outcome, backend distinction, and remaining branch together.
- Keep agreed product changes in the process agreement and link to them rather than duplicating their normative meaning here.
- Never label a visible control, source-code path, or passing automated test as completed interaction coverage without exercising the relevant behavior.
- Keep the inventory explicitly partial until the remaining workflows and their data permutations have been addressed.
