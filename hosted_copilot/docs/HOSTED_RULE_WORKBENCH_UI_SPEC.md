# Hosted Rule Workbench UI Specification

## Scope And Ownership

This is the approved visual specification for Candidate Sources Details and Assessment Results Details. Both views consume the same section, assessment, information-panel, and editor styles. Other Workbench flows retain their documented behavior in the [implementation guide](HOSTED_COPILOT_CODE_REVIEW_IMPLEMENTATION.md).

- Shared detail markup belongs in [app.js](../workbench/app.js); equivalent evidence must use the same renderers rather than parallel view-specific implementations.
- Shared appearance belongs in [styles.css](../workbench/styles.css). Use existing theme tokens and semantic classes, not rule IDs, inline styles, browser-prototype selectors, or JavaScript-generated styling.
- Assessment freshness and approval authority are independent from evidence visibility. This specification does not change evaluator contracts, selected actions, plan membership, or promotion requirements.
- This document is maintainer-only Hosted guidance, not a deployed review instruction or a distribution artifact.

## Shared Detail Structure

Keep the fixed identity header and the existing owned detail scroller. Inside that scroller, render these common sections in order:

1. Source Rules.
2. Related Hosted Coverage in read-only Assessment Results only.
3. Assessment Details.
4. AI Assistance in Candidate Details only.
5. Current Hosted Rule and Proposed Hosted Rule comparison.
6. The view-specific maintainer controls.

Assessment Results additionally retains its Applicability Decision section between Assessment Details and the wording comparison, followed by its existing Maintainer Override workflow. It remains a read-only audit: do not add Rule Actions, proposed-wording editing, decision rationale, or promotion-plan controls.

### Section Boundaries

- Use the shared section block with `15px` top and bottom padding and the shared structural border color. Omit the final section's bottom border.
- Put each boundary at the actual section edge. Do not nest a divider inside another padded section or add margins that double the intended `15px` spacing.
- Source Rules and Assessment Results' Related Hosted Coverage are real sections, not section blocks hidden inside layout wrappers that suppress their borders.
- Section headings use the existing uppercase, semibold heading treatment. Field labels use the shared semibold treatment and trailing colons.

### Evidence Disclosures

- Source Rules and Assessment Results' Related Hosted Coverage start independently collapsed. Candidate Details omits the inferred coverage list; its absence does not alter stored assessment evidence or establish different relationships.
- Only their `24px` chevron buttons toggle disclosure. Titles remain static, and keyboard operation, accessible names, and ordinary-rerender disclosure preservation remain intact.
- Count pills are `18px` tall, with white `12px` semibold text on the shared blue background. Align them to the title baseline with an `8px` gap.
- Source IDs use the shared blue semibold rule-reference style. Retain provenance and meaning-preservation evidence, but omit a mapping badge that merely repeats the same source ID.
- Coverage entries show actual related Hosted IDs and their individual relationship explanations. Do not substitute the factor-scoring rationale.
- Retain source-proposal rationale when present in Assessment Results.
- Begin expanded Source Rules with shared information guidance explaining that these original source requirements are evidence, not additional Hosted rules selected for the Promotion Plan. Preserve every source entry.

## AI Assistance

- Candidate Details owns one rule-scoped conversation, immediately after Assessment Details. Assessment Results and protected-rule details remain read-only audit surfaces without a chat composer.
- Use the `AI Assistance:` heading, one read-only selectable response panel, and the accepted composer. Start the response window at `320px` and keep the composer fixed at `160px`, with internal shared scrolling.
- Make the response window's full-width lower edge draggable, using the Preview resizer's blue hover/focus treatment and accessible horizontal-separator semantics. Support pointer capture, cancellation, and keyboard resizing: Arrow Up/Down changes height by `16px`, Home selects the `160px` minimum, and End selects the viewport-height maximum. Clamp height and accessible values together when the viewport shrinks. Preserve the chosen height across rerenders and rule switches in browser memory only, and release drag state before replacing its DOM.
- Place the shared, non-dismissible information panel directly beneath the heading, before the response window. Use the semibold label `Advice only:` followed by `Conversation clears when switching rules or reloading; clearing conversation history does not change the draft.` Do not duplicate this guidance in a footer.
- Keep both outer windows transparent, with their existing borders. Retain the lighter user-message backgrounds.
- Keep user messages right-aligned in lighter-gray containers that shrink to fit short text and grow to at most `90%` of the transcript width, without a character-count width cap. Keep AI replies full-width and left-aligned without bubbles. Display reply text safely, never as model-supplied HTML. Completion time is application-measured, not generated by AI. Leave `16px` below completion time and above and below the Context note.
- Show one fixed identity chip at the left of the response toolbar: the locally hosted `16px` Copilot Codicon, muted `Copilot ·` prefix, and white italic current Hosted rule ID. Match the composer's dashed gray context-chip border, rounded corners, and padding. Do not repeat the identity on each reply or scroll it with the transcript.
- Keep Clear Conversation in the response panel's fixed top-right toolbar. Disable it when empty or working. Clear both visible turns and future model context without clearing unsent input, rule wording, rationale, actions, or Plan membership.
- Keep the composer's current rule chip, globe, and disabled additional-context control. Show the server-configured normal model and effort, not a selector. Use the OpenAI glyph from the locally hosted, attributed MIT-licensed Lobe Icons sprite without a runtime network dependency.
- Preserve the accepted `12px` model metadata, white italic rule label, muted placeholder, blue ready-to-send arrow, and gray outlined ring-and-square cancellation control. Only non-whitespace input enables Send.
- Enter sends; Shift+Enter inserts a newline. While working, keep the composer read-only, reuse the real waiting-panel border component and reduced-motion behavior, and leave Cancel operable.
- Load waiting messages from the local [assistance phrase catalog](../workbench/assistance-waiting-phrases.json). Require a non-empty array of unique, trimmed, single-line strings; missing or invalid catalogs fail visibly rather than falling back silently. Choose one phrase randomly when each assistance request starts, render it with the shared relationship-check shimmer, and keep it unchanged until that request finishes, including across rerenders. Do not rotate phrases on a timer, send them to the AI, persist them in drafts, or substitute them for actual completion, cancellation, or failure results.
- Cancel aborts the HTTP request and owned CLI process tree, rejects late replies, keeps unsent text, and displays exactly `Operation canceled.` in the conversation. Surface genuine failures there with a concrete reason.
- Keep conversation state only in Workbench memory, never in IndexedDB, portable drafts, or assessment caches. Switching selected rules or reloading resets it. Send all completed exchanges on follow-up; failed and canceled requests remain visible operation history rather than fabricated model replies.
- Follow new output only when the transcript was already at the bottom. Preserve the reader's scroll position otherwise.
- Ground every request in server-owned original sources, the selected wording at send time, and the complete active and protected Hosted catalog snapshot. State that scope explicitly; retired rules, other unsaved drafts, and projected Plan changes are not checked by this conversation.
- Treat replies as advisory. Do not change assessment freshness, scores, validation receipts, protected-rule authority, or promotion readiness because chat completed.
- Present suggested complete wording behind an explicit native review disclosure, with a shared down/up chevron in a right-aligned `24px` visual area. Immediately beneath the expanded summary, show the shared information panel with `Only fills the editor. Review and Save through the existing validation flow.` before the wording box; do not repeat it as a floating footer. Right-align `Use wording in editor` with a `16px` top margin. It fills only the existing editor after checking candidate, wording, and authority freshness, without saving, changing decisions, staging retirements, or modifying the Plan. The existing Save and validation flow remains authoritative.
- Reject input that exceeds the complete prompt's `393216`-byte engineering budget; do not truncate catalog rules or conversation history. Ask for a cleared conversation, and report when the base context still cannot fit. This is an application input bound, not a claimed model context-window size.
- Each request is a fresh, non-streaming local CLI invocation with no tools and no resumed CLI session. Workbench temporary transport files and redirected logs are removed on completion, cancellation, or shutdown. The CLI provider's own session retention remains independent of Workbench memory and Clear Conversation; do not claim that clearing the UI deletes provider-managed records.

### Shared Information Banners

- Ordinary informational notices use one shared renderer with an information icon by default and an optional caller-supplied icon.
- Use the existing information background RGB color with `0.31` alpha through its shared theme token. Keep text, icons, borders, and the panel itself fully opaque; do not apply element opacity.
- Icon overrides retain the shared `20px` icon size and information-panel colors, spacing, border, and typography. Do not create an alternate banner style for a lock icon.
- Section guidance uses the shared `section-guidance` spacing class, with `12px` before the following content.
- Keep informational guidance non-dismissible and its decorative icons hidden from assistive technology. Changing an icon must not change severity, accessibility semantics, or control behavior.
- Preserve the separately owned behavior and rich layout of confirmation dialogs and dismissible error alerts; an icon override is not a reason to redesign those surfaces.
- Actionable wording concerns use the shared warning variant with existing amber theme tokens and the local AI-issue icon. Do not recolor ordinary assessment, scoring, or help guidance merely because a separate warning exists.

## Assessment Details

Use one shared assessment renderer in both detail views, including incremental refreshes in Candidate Details.

Render the section contents in this order:

1. The `Assessment Details:` heading and its existing scoring-legend action.
2. A non-dismissible assessment-context information panel.
3. The three metric cards.
4. The Rule Value and Review Risk factor groups.

### Assessment Context

- Use the existing information-panel component, local information icon, and semantic theme tokens. Do not use a loose explanatory paragraph or add a dismiss button.
- Always begin the explanation with the bold label `Assessment:`. Keep freshness in the body rather than changing this label.
- Place `12px` between the heading and information panel, `12px` between the panel and metric strip, and `16px` between the strip and factor groups.
- When current evidence is unavailable, retain the validated original priority score, seven factors, rationale, applicability, and related coverage. Never fabricate replacement values or present the original assessment as current.
- Use this original-evidence message, substituting the recommendation from the original assessment:

> **Assessment:** Edited wording has not yet been reassessed. Priority and factor scores describe the original proposal, whose recommendation was {recommendation}; they do not validate the edited wording. Token Cost and Token Headroom reflect the current draft.

- When a complete current reassessment succeeds, replace historical context with current AI-assessment guidance. Do not leave the original-evidence warning or an obsolete recommendation in place.
- In both states, distinguish AI priority and factor judgments from deterministic draft token calculations. The original-evidence display fallback must never authorize approval or supply current candidate-row scoring.
- Preserve the existing scoring legend, keyboard dismissal, read-only factor evidence, and semantic positive and risk colors.

### Metric Cards

Use these stable labels in every freshness state:

| Label | Value |
| --- | --- |
| `Priority Score:` | The displayed assessment's priority score |
| `Token Cost:` | The current staged action's signed token delta |
| `Token Headroom:` | The projected remaining capacity after the current staged action |

- Do not add `Original` or `Draft` to metric labels. Explain freshness in the context panel.
- Keep all three cards in one equal-width row at supported laptop and desktop widths, with a `12px` gap.
- Keep each label and value inline and baseline-aligned, with a `12px` gap.
- Labels are white and semibold, with trailing colons and the existing uppercase metric treatment. Retain the existing value colors.
- Use the shared structural border token, `4px` corner radius, and `10px 12px` padding on each card.
- Token calculations follow the existing staged-action and complete-plan projection rules, including zero-cost non-mutating actions and replacement of an existing plan item's contribution. Renaming or regrouping metrics must not change those calculations.

## Hosted Wording Comparison

- Keep Current Hosted Rule and Proposed Hosted Rule adjacent, with the existing `12px` comparison spacing and no divider between them.
- Current Hosted Rule displays the shared blue semibold ID and catalog lifecycle status only. AI recommendations belong to Proposed Hosted Rule, not the existing rule.
- Show the advisory recommendation beside Proposed Hosted Rule only when saved-wording validation is not blocking. Defer uses the same amber foreground as warning status pills. Retain the underlying assessment and the maintainer's independent selected action.
- Put one non-dismissible rationale information panel immediately below the Proposed Hosted Rule heading and above its wording surface.
- When wording review does not replace this panel, always use the label `Assessment rationale:` with the exact current assessment rationale when available. When current evidence is unavailable, retain the original rationale and identify its freshness in the assessment context panel rather than changing this label.
- Candidate Details retains the proposed editor, explicit Save, relationship progress, failure, and resolution controls.
- Assessment Results displays the same saved proposed wording as read-only evidence.

### Wording Review And Attention Navigation

- A completed, current evaluation with non-accepted meaning or ownership guidance remains blocked even when it contains zero relationship pairs. Show `Wording needs review`, never a green current/resolved state or a generic instruction to reconcile again.
- Scope fit and wording acceptability are independent. A current `within-scope` result whose explicit `wordingStatus` is `needs-review` displays the same warning, contributes a Validation Issue, and blocks Plan readiness and approval even with zero relationship issues. Display its exact `wordingRationale`; if scope also needs review, retain both explanations inside the single warning. Do not infer acceptance from an advisory action or search explanatory prose for rejection phrases.
- Preserve saved wording and the maintainer's selected action. A meaning-neutral addition is still changed text, not an unchanged/no-op result. A corrected proposal requires explicit Save and a current acceptable result. Older saved results without an explicit wording decision require revalidation without preventing the draft from loading.
- Replace the assessment-rationale panel with one non-dismissible `Wording needs review` warning immediately above the proposed wording. Use the exact saved evaluation guidance and existing AI-issue icon in amber. Do not duplicate this warning beneath the editor or turn the assessment rationale into a second warning.
- Apply the same presentation in Candidate Details and read-only Assessment Results. Preserve assessment evidence, scope disposition, saved wording, decision, and approval gates; suppressing the advisory badge does not discard the AI result.
- Remove obsolete wording guidance immediately when the editor changes, restore it when the exact checked wording is restored, and preserve the current result through navigation and session reload without launching another check.
- Derive status labels and corrective destinations from the shared validation attention owner. Missing/stale checks target Check/Recheck; failures target Retry; active checks target progress; current wording concerns target the warning; and unresolved relationships target their resolution region.
- Promotion Plan preserves required-action, resource-type, and rationale precedence. Its readiness action targets that actual missing input, while the Validation Issues status bar targets the validation concern rather than an unrelated missing decision rationale. Both entry points use the same focus owner for the same concern.
- Use `Review wording` for the plan action. Show validation attention on unselected candidates and their collapsed ancestors without implying plan membership or selecting them.

### Maintainer-Directed Consolidation

- Keep the maintainer's edited rule as the intended bound target. Existing coverage may justify consolidation, not automatic routing away from that target. Similar categories alone do not justify retiring a rule.
- Reuse the existing Rule Issue suggested-wording preview and Apply Recommended Actions control. Present complete corrected wording and justified retirements together; do not rewrite text, retire rules, or change Plan membership merely because evaluation completed.
- Explicit acceptance checks the complete projected change for every affected candidate and publishes it only after atomic persistence succeeds. Any remaining scope, wording, relationship, authority, cancellation, or persistence problem leaves the original draft intact; concurrent maintainer edits must survive.
- Preserve accepted retirement intent through reload and portable draft import. Imported decisions require fresh validation and do not inherit approval authority.

### Relationship Check Progress

- Keep the panel background transparent so it matches the page; do not add a fill or background gradient.
- Preserve the shared heading, spinner, and animated one-screen-pixel border. Anchor the right and bottom chase masks to their actual painted edges, including fractional layout and browser zoom.
- Append `[Elapsed: HH:MM:SS]` immediately after `This can take a few minutes.` in the left-aligned text. Use tabular numerals and a non-announcing timer; rerendering or returning to Details must not restart it.
- Keep Cancel right-aligned and use the shared blue primary-button colors and brighter blue hover highlight. Its height is `28px`, with `14px` horizontal padding.
- At supported widths down to `768px`, allow the text and timer to wrap on the left without clipping or horizontal overflow.
- Cancel aborts the request and stops the owned native evaluator process tree. Preserve the saved wording, prior evidence, and plan; do not publish cancelled results, manufacture an evaluator failure, or bypass required validation. Stop the timer and allow rechecking.
- Keep Undo enabled with its existing icon during validation. Its accessible name and tooltip say `Cancel validation and undo this candidate`. Single-candidate, scoped Plan, and bulk-operation Undo cancel affected checks through the same cancellation owner before their normal reset; unlike Cancel alone, Undo discards the candidate's saved decision and validation metadata. Late completion must not restore discarded state, remove a newer check, or overwrite its progress. Preserve unrelated candidates' checks, warnings, and decorations; clear warnings only when their underlying problem no longer applies.
- Promotion Plan shows a compact amber `Checking` readiness action with the existing magnifying-glass search icon. Preserve full relationship-check context in its accessible name and tooltip, constrain readiness actions to their column, and retain the adjacent Undo control. Clicking `Checking` focuses the running progress panel without starting another check.
- The loopback server continues serving static assets, runtime configuration, and authenticated shutdown while evaluation runs. Serialize evaluations independently from HTTP serving, retain request authorization and result validation, and stop owned workers and descendants on disconnect or server shutdown. Do not mask blocked asset requests with icon replacement or relaxed caching or content-security rules.

## Maintainer Override

- Assessment Results follows the same title, guidance, then controls pattern as Candidate Details.
- Place one non-dismissible shared information banner immediately beneath `Maintainer Override:` and before the override summary, saved record, or editing controls.
- Pass the existing local lock icon to the shared banner renderer. Do not repeat the notice beneath the controls or retain a separate read-only-boundary style.
- Before an override is saved, preserve this wording:

> The AI assessment is read-only. A maintainer override records a separate correction without erasing the original result.

- For saved and editing overrides, preserve this wording:

> The AI assessment is read-only. This provisional maintainer correction does not erase the original result.

- Preserve override eligibility, rationale editing and cancellation, save and removal behavior, maintainer attribution, and the original AI assessment.

## Rule Actions

Rule Actions belongs only to Candidate Details.

- Render one heading: `Rule Actions: {hostedRuleId}`. The ID uses the existing blue semibold rule-reference style and comes from the candidate's effective generated identity.
- Do not render a second `RULE:` title bar.
- Put a non-dismissible information panel directly beneath the heading, with `12px` before the controls.
- Preserve status-dependent guidance: normally, `Choose one action. Hosted catalog status determines which actions are available.` When identical wording makes Update unavailable, retain that specific explanation.
- The controls sit directly in the section. A layout-only wrapper may arrange them, but must not add an outer subcontext background, border, rail, or padding.
- Keep individual control-group surfaces, status-constrained action choices, selected values, disabled states, retirement options, and plan semantics unchanged.
- Beneath `Rule Applies to Resource Type(s):`, show a non-dismissible information panel stating `Resource types apply only to implementation rules.`
- Resource types remain editable only for implementation rules with Add or Update selected. The guidance does not broaden that eligibility.

### Decision Rationale

- Keep the label, existing icon-only Save control, accessible name, tooltip, and plan-return behavior.
- Use the same shared editor-surface class as Proposed Hosted Rule for background, border color and width, corner radius, padding, and text styling.
- Generic form-textarea styling must not override a shared evidence editor. Fix that CSS ownership relationship rather than copying properties into a rationale-only rule.
- Preserve the saved and staged text, disabled behavior, placeholder, `500`-character limit, live count, fixed `84px` height, disabled resizing, and vertical overflow behavior.
- Styling must not enable a disabled field, save a decision, change an action, or invoke evaluation.

## Regression Coverage

- [The saved-assessment journey](../regression/workbench/playwright/journeys/saved-rule-assessment.journey.cjs) enforces the shared layout, exact labels, spacing, borders, typography, editor parity, and read-only Assessment Results boundary, including the lock-icon banner before and after an override is saved, edited, or removed.
- `WB-UX-DETAILS-001` owns the shared visual contract. `WB-UX-DETAILS-002` and `WB-UX-DETAILS-003` retain current-result projection and original-evidence freshness coverage.
- Exercise current and original-evidence states in both views, including unsaved, inflight, failed, stale, and restored evaluation contexts.
- Retain focused action, generated-identity, persistence, and relationship journeys when selectors or owning controls change.
- During UX implementation, use the focused owning checks. Complete Hosted validation remains a separate maintainer-authorized final step.
