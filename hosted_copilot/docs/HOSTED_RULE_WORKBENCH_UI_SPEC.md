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
4. Current Hosted Rule and Proposed Hosted Rule comparison.
5. The view-specific maintainer controls.

Assessment Results additionally retains its Applicability Decision section between Assessment Details and the wording comparison, followed by its existing Maintainer Override workflow. It remains a read-only audit: do not add Rule Actions, proposed-wording editing, decision rationale, or promotion-plan controls.

### Section Boundaries

- Use the shared section block with `15px` top and bottom padding and the shared structural border color. Omit the final section's bottom border.
- Put each boundary at the actual section edge. Do not nest a divider inside another padded section or add margins that double the intended `15px` spacing.
- Source Rules and Assessment Results' Related Hosted Coverage are real sections, not section blocks hidden inside layout wrappers that suppress their borders.
- Section headings use the existing uppercase, semibold heading treatment. Field labels use the shared semibold treatment and trailing colons.

### Evidence Disclosures

- Source Rules and Assessment Results' Related Hosted Coverage start independently collapsed. Candidate Details omits the inferred coverage list; its absence does not alter stored assessment evidence or establish different relationships.
- Related Hosted Coverage is absent when no related Hosted rules are recorded; render no heading, zero-count pill, empty body, or section spacing. Otherwise show the individual Hosted-rule comparisons and their relationship rationales, not the general selection or coverage-summary rationale. Keep the assessment rationale once beneath Proposed Hosted Rule; do not change the underlying evidence to remove a presentation duplicate.
- Only their `24px` chevron buttons toggle disclosure. Titles remain static, and keyboard operation, accessible names, and ordinary-rerender disclosure preservation remain intact.
- Count pills are `18px` tall, with white `12px` semibold text on the shared blue background. Align them to the title baseline with an `8px` gap.
- Source IDs use the shared blue semibold rule-reference style. Retain provenance and meaning-preservation evidence, but omit a mapping badge that merely repeats the same source ID.
- Coverage entries show actual related Hosted IDs and their individual relationship explanations. Do not substitute the factor-scoring rationale.
- Retain source-proposal rationale when present in Assessment Results.
- Begin expanded Source Rules with shared information guidance explaining that these original source requirements are evidence, not additional Hosted rules selected for the Promotion Plan. Preserve every source entry.

### Shared Scroll Controls

- Use one `.scroll-edge-button` appearance for Back to Top and Scroll to Latest: a `28px` circular surface, thin themed border, and native `16px` chevron. Disabled controls retain the circular surface, muted foreground and border, and default arrow cursor without hover decoration or tooltips.
- Keep Back to Top in the fixed Details header and apply no vertical transform to its upward chevron. Keep Scroll to Latest floating at the response area's bottom-right, with its downward chevron's existing `1px` optical offset. Shared appearance must not impose shared positioning.
- Derive each control's availability from its own scroller. Back to Top disables at the top; Scroll to Latest hides at the bottom. Neither may scroll the fixed outer shell or shift its header or status bar.

## AI Assistance

- The Workbench owns one shared sidebar outside all view panels, with independent in-memory chat state for each workspace view and rule. Show it only in Candidate Details or Assessment Details with a valid matching selection. Hide it on startup, lists, Rule Issues, Plan, Preview, and protected-rule or empty selections. Navigation selects the originating view/rule context rather than transferring its conversation, composer input, pending request, or reading position to another chat. Protected-rule selection clears the displayed editable target without erasing other chats.
- Use the `AI Assistance:` heading with one read-only selectable response area and the accepted composer. Start hidden on the list, with an expanded preference for the first eligible Details view and a `420px` width. Keep the preference independent of context-driven visibility. Let the response use the remaining viewport height, keep the composer fixed at `160px`, and retain independent shared scrolling. At supported widths of `1100px` or less, use a right-side drawer rather than compressing the main workspace. Mobile-device rejection remains unchanged.
- Place one permanent show/hide command immediately left of Close Workbench in the title bar. Keep this preference toggle enabled across views. Declare support through each Details panel's `data-sidebar-enabled="true"` metadata; absent metadata means unsupported. Derive actual visibility from support, a valid matching selection, and the global preference. The pressed state and icon describe the preference, while `aria-expanded` describes actual visibility. Use the local `layout-sidebar-right` and `layout-sidebar-right-off` Codicons with the shared custom tooltip and accessible labels `Hide AI assistance` and `Show AI assistance`. Do not move or duplicate the command between view toolbars.
- Keep one X in the sidebar header. It clears the same global visibility preference and returns focus to the titlebar toggle, without cancelling requests or clearing conversations. Hide the whole sidebar and reclaim its workspace column, not a collapsed rail. Preserve width, each chat's input and transcript, and its reading position. The drawer spans exactly from the fixed `35px` header to the status bar at supported narrow widths, including `768px`.
- Keep `AI Assistance:` and adjacent New Chat plus and close X controls in the sidebar header. Use the pinned native `add` Codicon for New Chat. Share the titlebar's existing `34px` icon-button sizing and one authoritative `1px` gap rule; do not introduce separate sidebar button dimensions or spacing. Remove the duplicate heading spinner and Stop control. Derive the real waiting-panel border and composer Send/Cancel state from the displayed chat's own pending request. A completed chat must not inherit another chat's running appearance. Reduced motion disables the shared animation without changing pending state.
- Resize the sidebar through its full-height left edge, using accessible vertical-separator semantics and pointer capture. Arrow Left increases width by `16px`; Arrow Right decreases it. Home selects `320px`; End selects the smaller of `680px` and the viewport width minus `400px`, with a `320px` floor. Clamp width and accessible values together when the viewport shrinks. Keep a `5px` transparent grab area, but highlight only the existing `1px` left divider on hover or keyboard focus. Pointer cancellation, hiding, and lost capture finish the drag. Preserve width in browser memory without resizing the composer.
- Place the shared, non-dismissible information panel above the response area. Use exactly `This response is AI-generated. Please review it for accuracy and relevance before use.` without an extra label or footer. Preserve the unavailable-service explanation when no runtime assistance profile exists.
- Give the sidebar only a left divider, with no top, right, or bottom border. Keep the response area transparent and borderless; retain the composer border and lighter user-message backgrounds.
- Keep user messages right-aligned in lighter-gray containers that shrink to fit short text and grow to at most `90%` of the transcript width, without a character-count width cap. Keep AI replies full-width and left-aligned without bubbles. Display reply text safely, never as model-supplied HTML. Completion time is application-measured, not generated by AI. Place the grounding note directly after completion time and before the reply. Leave `16px` below completion time and above and below the grounding note.
- Render chat grounding notes through one helper that accepts literal message text and an optional Codicon name, defaulting to `tools`. Use exactly `Assessment, sources, and catalog snapshot; excludes other drafts and Plan changes.` without a `Context:` prefix or visible rule count. Place the decorative `14px` local sprite icon before the text with an `8px` gap. Use the darker muted `#737373` foreground for both icon and text, and align wrapped lines beneath the text rather than the icon. Escape message text and reuse the existing icon-name validation. Icon overrides such as `terminal-compact` and `edit-compact` change only the glyph, never the layout, chat state, or rule authority.
- Show one fixed identity chip at the left of the response toolbar: the locally hosted `16px` Copilot Codicon, muted `Copilot ·` prefix, and white italic current Hosted rule ID. Match the composer's dashed gray context-chip border, rounded corners, and padding. Do not repeat the identity on each reply or scroll it with the transcript.
- Remove the transcript toolbar's Clear Conversation icon. For v1, the header's New Chat plus performs the same destructive reset only after confirmation; it does not archive sessions or offer undo. Disable it when the displayed chat is empty or running. Preserve unsent input, rule wording, rationale, actions, Plan membership, and every other chat.
- Reuse one shared confirmation dialog and the existing warning-modal, primary Cancel, and destructive-action styles. The caller supplies the title and description: `Start a New AI Candidate Chat?` or `Start a New AI Assessment Chat?`, and `This will permanently clear the {view} AI chat history from this Workbench. Future AI requests in this chat will not include that history.` Follow with `This action cannot be undone.` Use the pinned warning icon in the title and the pinned trash icon on the red Clear Chat action, not a plus icon in either location. Focus Cancel by default. Clearing conversation history does not remove the selected rule or catalog context from future requests.
- Opening the dialog does not clear anything. Cancel, X, Escape, and backdrop dismissal preserve state. Confirmation clears only the captured originating chat when it remains the registered, idle chat object; never retarget the command to a later selection. Ignore closed-dialog clicks, do not repaint another displayed chat, and restore appropriate focus after closing.
- Keep the composer's current rule chip, globe, and disabled additional-context control. Show the server-configured normal model and effort, not a selector. Use the OpenAI glyph from the locally hosted, attributed MIT-licensed Lobe Icons sprite without a runtime network dependency.
- Preserve the accepted `12px` model metadata, white italic rule label, muted placeholder, blue ready-to-send arrow, and gray native `16px` Codicon stop-circle cancellation control. Reuse the local sprite instead of inline stop drawings or downscaled larger artwork. Only non-whitespace input enables Send.
- Enter and Send immediately clear submitted input once the turn enters the transcript, without waiting for a reply. Retain the exact submitted text only in request-owned memory so failure or cancellation can restore it if the composer is still empty; never overwrite newer input or clear it when an older request settles. Retry clears restored text only when it matches that failed question and preserves unrelated unsent drafts. Shift+Enter inserts a newline without sending. While working, keep the composer read-only, reuse the real waiting-panel border component and reduced-motion behavior, and leave Cancel operable.
- Load waiting messages from the local [assistance phrase catalog](../workbench/assistance-waiting-phrases.json). Require a non-empty array of unique, trimmed, single-line strings; missing or invalid catalogs fail visibly rather than falling back silently. Choose one phrase randomly when each assistance request starts, render it with the shared relationship-check shimmer, and keep it unchanged until that request finishes, including across rerenders. Do not rotate phrases on a timer, send them to the AI, persist them in drafts, or substitute them for actual completion, cancellation, or failure results.
- Cancel aborts the HTTP request and owned CLI process tree, rejects late replies, keeps unsent text, and displays exactly `Operation canceled.` in the conversation. Surface genuine failures there with a concrete reason.
- Render every chat failure directly beneath its user message through the single `.assist-chat-error` component, including generic fallbacks and repeated failed retries. Use the compact VS Code-inspired inline structure: `8px 12px` padding, a red `16px` error icon beside the safe message, transparent background, and a thin themed border. Remove the former titled card, close X, Dismiss action, and their styles. Do not route fallbacks through a legacy variant, rule-validation banner, modal, or toast.
- Use `The AI chat request could not be completed.` for unknown failures without replacing trusted specific failure reasons. Show a diagnostic reference only when one was recorded, as secondary text with `Diagnostic Reference:` semibold at `600` and its identifier regular at `400`. Keep a lightweight `Try again` action right-aligned beneath the message. Reuse theme colors, shared buttons, and the native error icon; do not expose raw CLI output or credentials.
- Preserve structured failure information at the worker/API boundary, following [Copilot's error-details pattern](https://github.com/microsoft/vscode-copilot-chat/blob/main/src/platform/chat/common/commonTypes.ts). A single converter preserves explicitly trusted validation messages and supplies a safe fallback for unexpected exceptions. Return `code`, `message`, and an optional `diagnosticId`; the browser validates and renders these fields without parsing terminal transcripts or inferring causes from prose. Unknown failures remain unknown.
- Record the public failure message and allowlisted phase, exit code, byte counts, and event counts under the diagnostic reference. Never retain raw prompts, conversations, CLI replies, stderr, stack dumps, or credentials in these records. Failure to record diagnostics must not manufacture a reference or prevent the safe failure response.
- Preserve the failed turn, unsent input, rule wording, decisions, and Plan; do not mark a reply accepted. Retry is explicit, limited to the latest failed turn and its unchanged wording snapshot, and reuses that turn instead of duplicating the user message. Preserve independently edited composer input. Disable Retry during a request or after the wording changes, and never retry automatically. A failed Retry renders the same compact error component again without changing its styling or reviving retired controls.
- Keep conversation state only in Workbench memory, never in IndexedDB, portable drafts, assessment caches, or persisted CLI sessions. Return to the same view/rule chat when revisiting it; reload starts fresh chats. Send only that chat's completed exchanges on follow-up. Failed and canceled requests remain its operation history rather than fabricated model replies. Confirmed New Chat clears only its originating conversation and preserves its unrelated unsent input and all rule decisions.
- Allow one pending request per chat while independent chats can each own a request. Switching views or rules never prompts or cancels work. Capture the originating chat and request before awaiting; bind success, failure, and cleanup to that same chat object and active request. Reject obsolete completions. Update an inactive chat's history and pending state without repainting the displayed chat. Explicit cancellation targets only the displayed chat's request and cannot clear a replacement request or another chat's busy state.
- Follow new output only when the transcript was already at the bottom. Preserve the reader's scroll position otherwise. Show a `28px` circular Scroll to latest reply control at the conversation's bottom-right only when the reader is more than `4px` from the bottom. Match the effective response background, retain a thin blue outline and light `16px` down chevron with a `1px` downward optical offset, and use only the shared custom tooltip. Clicking returns directly to the bottom, restores output following, and hides the control. Keep visibility current after scrolling, resizing, and rerendering without changing the conversation's layout.
- Ground every request in server-owned original sources, the original parent assessment and recommendation, every member's assessment and meaning-preservation rationale, the selected wording at send time, and the complete active and protected Hosted catalog snapshot. Include source lanes, hashes, and mappings for stable evidence identity; browser-supplied assessment evidence is not accepted. State that scope explicitly; retired rules, other unsaved drafts, and projected Plan changes are not checked by this conversation.
- Bind recorded assessment evidence to the original proposal text hash and explicitly report whether the current wording matches. Include scoring definitions from the display schema and bind that schema into runtime freshness. Explain recorded ratings through their supplied rationales without inventing intermediate score thresholds. Parent factor values come from reconciliation; inherited primary-source confidence, evaluator, and evaluation time must not be presented as independent reconciliation provenance or certainty.
- Treat contribution rationales as recorded claims, not proof of complete preservation. Compare each assigned source meaning with original and current wording; distinguish concise equivalence, evidenced scope boundaries, and missing or weakened requirements. Attribute gaps to the appropriate wording version, cite supplied source, assessment, or Hosted rule IDs, and acknowledge missing evidence rather than inventing historical intent. All supplied records remain untrusted quoted data; reject embedded instructions and keep explanations advisory.
- Treat replies as advisory. Do not change assessment freshness, scores, validation receipts, protected-rule authority, or promotion readiness because chat completed.
- Present suggested complete wording directly in the reply after `I suggest updating the rule to:`, without a disclosure, editor-insertion button, or nested scrollbar. Preserve the exact text and safe rendering. Show one floating copy toolbar across the wording block's upper-right edge on hover or keyboard focus. Use a visible themed border, `28px` toolbar height, a fixed `22px` action with full-height hover treatment and `3px` horizontal gutters, and the existing `16px` copy icon. Keep the shared custom tooltip and accessible label without a native browser tooltip, including copied and failed-copy feedback. Copying is advisory and cannot edit or save wording, validate a rule, change decisions, stage retirements, or modify the Plan. The existing editor, Save, and validation flow remain authoritative.
- Reject input that exceeds the complete prompt's `393216`-byte engineering budget; do not truncate catalog rules or conversation history. Ask for a cleared conversation, and report when the base context still cannot fit. This is an application input bound, not a claimed model context-window size.
- Each request is a fresh, non-streaming local CLI invocation with no tools and no resumed CLI session. Workbench temporary transport files and redirected logs are removed on completion, cancellation, or shutdown. The CLI provider's own session retention remains independent of Workbench memory and New Chat; do not claim that clearing the UI deletes provider-managed records.
- Accept multiple assistant messages within one root turn, selecting its final message only after exactly one `assistant.turn_end`, one terminal `result`, and a successful CLI exit. Validate that final message against the response schema; never select an earlier valid-looking message to rescue an invalid final reply. Reject missing or duplicate completion, messages after the completed turn, error or abort events, nested-agent output, tool requests, and unexpected models. Preserve all existing source, wording, catalog, and authority checks.

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

> **Assessment:** Priority and factor scores describe the original rebuild proposal, whose recommendation was {recommendation}; they do not validate the maintainer-edited wording. Token Cost and Token Headroom reflect the current draft.

- Saved edits retain original rebuild scores rather than requesting a new AI assessment. Identify edited wording as maintainer-edited without implying AI certification.
- Distinguish original AI priority and factor judgments from deterministic draft token calculations. Approval consumes the existing deterministic readiness checks, not saved-edit AI certification.
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
- Show the rebuild recommendation beside unchanged saved Proposed Hosted Rule wording, or `Maintainer edited` only after different wording is successfully saved. Unsaved typing does not change the pill, assessment, or rationale. Defer uses the same amber foreground as warning status pills. Retain the underlying assessment and the maintainer's independent selected action.
- Put one non-dismissible rationale information panel immediately below the Proposed Hosted Rule heading and above its wording surface.
- Keep the Proposed Hosted Rule title left-aligned and its recommendation pill right-aligned in read-only Assessment Details. Preserve the editable header's status and action alignment through the shared auto-margin layout.
- Use `Assessment rationale:` for unchanged proposals and `Original assessment rationale:` for edited wording, preserving the exact rebuild rationale.
- Candidate Details retains the proposed editor and explicit Save/Reset controls. Saving performs no relationship discovery, scope review, adjudication, or reassessment.
- Derive Save availability from editor text differing from the latest successfully saved wording. Typing updates dirty controls and retry validity in place, without rebuilding assessment evidence, Rule Issues, Plan, or Preview. Persist a staged wording change before committing its saved state; failures preserve the previous saved text, pill, and unsaved buffer. Reject intervening draft or editor changes rather than overwriting them.
- Render recommendation and validation pills together in one right-aligned `.proposed-rule-statuses` group with an `8px` internal gap and wrapping at narrow widths, before a compact Save/Reset action group. Keep both icon buttons at their existing hit-area size with no extra internal gap; preserve the `10px` separation from the pills. The renderer owns this structure so view changes need no observer or repair pass. Reset uses the pinned Codicons `debug-restart` symbol and tooltip `Reset rule to original`.
- Shared disabled styling covers native `disabled`, `aria-disabled="true"`, and `.disabled` controls: icon buttons fade consistently, retain a default arrow cursor and their accessible names, and receive no hover decoration or tooltip. The shared tooltip owner and display functions reject disabled controls and ancestors, including a control disabled while its tooltip is pending. Do not add Save-, Reset-, or rationale-specific disabled rules.
- Assessment Results displays the same saved proposed wording as read-only evidence.

### Shared Tooltips And Protected References

- Use the shared tooltip controller for authored explanations and truncated text. Show after the existing `500ms` delay. Center hover tooltips horizontally on the captured pointer entry X and keyboard tooltips on the control. Keep vertical spacing fixed above or below the invoking control, independent of pointer Y. Use the shared CSS gap and viewport inset for flipping and clamping. Movement during the opening delay does not replace the entry X; once visible, movement within the same trigger does not dismiss, reposition, or restart the tooltip.
- Treat the trigger and visible tooltip as one hover region. The visible tooltip accepts pointer hover without taking keyboard focus. Use a cancellable `150ms` close grace to cross the gap between them, and dismiss only after leaving both regions and removing focus from the trigger.
- Escape dismisses the tooltip without moving pointer or keyboard focus. Keep it suppressed during further movement inside the same trigger; a fresh hover entry or keyboard-focus cycle can show it again. Preserve existing click, resize, and disabled-control safeguards.
- Keep the shared opaque dark surface, `--muted` border, and compact shadow. Do not add an oversized fade or protected-rule-specific tooltip presentation.
- Protected Rule Issue references show `Protected` and `Immutable`, never an optional `Keep` action. Derive the protected-reference class from protected catalog identity or status. Render their text with `--disabled-foreground`, a default arrow cursor, and text selection intact; do not mark the whole reference as a disabled control. Neither pill nor the rule body has a protection-explanation tooltip or extra tab stop.
- All classifications in the Protected issue category display one shared information panel immediately below the warning. It explains editing the protected source file directly in the repository, then relaunching with `-Rebuild` to refresh the snapshot and analysis, including the potentially significant assessment and Rule Issue processing time. Ordinary relationship issues do not display this notice. Dismissing the warning leaves the information panel visible at the existing pane inset without an extra leading gap. Displaying the notice never edits a rule, runs a rebuild, or changes approval readiness.

### Shared Rendering Geometry

| CSS Metric | Default | Shared Consumers |
| --- | --- | --- |
| `--detail-pane-inset` | `12px` | Detail pane top padding and adjacent warning/information-panel spacing |
| `--section-gap` | `16px` | Equivalent Rule Issue section headings and section separation |
| `--section-label-gap` | `10px` | Section heading-to-content separation |
| `--panel-padding` | `14px` | Rule comparison, assessment, canonical wording, and recommendation content |
| `--tooltip-gap` | `6px` | Tooltip clearance above or below the invoking control |
| `--tooltip-viewport-inset` | `8px` | Tooltip clamping, initial placement, and maximum width |
| `--tree-row-height` | `40px` | Candidate and Assessment row styling and hierarchy model defaults |
| `--line-height-body` | `--line-height-default` | Body text in rule and information panels |

- CSS owns these values. Runtime positioning and hierarchy adapters consume the CSS metrics rather than repeat numeric defaults. Explicit per-node heights remain available for variable-height rows.
- The shared heading rule owns the leading section gap. A comparison followed by a section heading does not add a competing trailing margin. Preserve comparisons without a following heading.
- Preserve intentional optical alignment for Back to Top and Scroll to Latest icons, native glyph dimensions, pixel-aligned borders, and measured virtualization geometry. These are not generic spacing inconsistencies.

### Original Proposal Restoration

- Enable Reset whenever either the editor wording or saved wording differs from the original proposal in the loaded assessment bundle. Saving an edit disables Save but leaves Reset available. Manually typing the original wording does not conceal a still-saved edit from Reset.
- Confirm explicit Reset before replacing the selected rule's saved wording with that original baseline. Persist the reset atomically, then restore the editor and pill and disable Save and Reset. Retain the selected Details view, independent rationale, Plan membership, applicability override, and retirement intent; invalidate an unavailable lifecycle action rather than silently choosing another action. A failed reset preserves the previous saved rule and unsaved buffer.
- Returning manually to the original wording requires explicit Save. Preserve independent rationale and retirement selections; restoring wording does not choose or approve a lifecycle action.
- Missing or stale baseline evidence remains invalid. Reset does not manufacture a successful assessment or bypass promotion safeguards.

### Shared Modal Dialogs

- Use `.modal-dialog`, `.modal-dialog-heading`, `.modal-dialog-title`, `.modal-dialog-content`, and `.modal-dialog-actions` for shared native-dialog structure. Keep scoring-specific data attributes and handlers independent from common presentation. Shared body text uses `--ink`; confirmation and warning headers use `.modal-dialog-warning` with the existing amber title, icon, and close-X treatment across icon families.
- Reuse existing button classes rather than add local palettes or hover overrides. The Reset confirmation uses blue `.button.primary` Cancel and green `.button.review` Reset to Original, including their existing lighter hover borders. Other confirmations retain their action-appropriate variants.
- Reset title: `Reset Rule to Original?`. Body: `Restore the original proposed wording for {ruleId}?` followed by `This will replace the saved wording for this proposal.` Render the rule ID using the shared blue `.rule-reference` class. Do not add prototype notices or narrate the unchanged Details location.
- The close X and Cancel share dismissal without mutation; Escape and backdrop dismissal have the same outcome. Only explicit confirmation invokes Reset. Preserve keyboard focus and responsive bounds.

### V1 Editing And Promotion

- Preserve exact maintainer wording on Save, reload, and portable draft import without any saved-edit AI request. Discard retired relationship-check metadata when loading local sessions, not the associated wording or decisions.
- Keep original rebuild assessment scores and published Rule Issues as evidence. Edits do not add, replace, hide, resolve, or certify that relationship snapshot.
- Keep AI Assistance independently available for copy-only advice. Assistance does not save, select, approve, or change draft validation.
- Require valid explicit lifecycle actions, rationales, implementation resource types, and saved wording. Invalidated lifecycle choices become missing actions rather than discarding edited wording or selecting a replacement action automatically.
- Promotion preview displays `Rule wording` as saved or unsaved. Remove relationship-check statuses, progress, retry, resolution, and assessment-certification requirements from the interactive workflow.
- Preserve the published Rule Issues approval gate, mutation-target uniqueness, protected-rule boundaries, and authenticated maintainer authority.
- Apply published Rule Issue recommendations only through an explicit maintainer command. Persist the complete recommendation atomically, protect concurrent draft changes, and leave the original draft intact on persistence failure. Do not evaluate the projected selection again.
- Keep Details scrollbar behavior and implementation-only Legacy, Typed, and Framework applicability controls unchanged. Preserve explicit retirement intent through reload and portable draft import.

### Review Changes

- Balance the title and close icon vertically within the menu header, with equal top and bottom spacing. Keep the existing side padding and inset header divider.
- Place Approve & Export in a `.preview-approval-actions` footer that owns its top divider and spacing independently of the requirement rows. Do not special-case the final row or change the button's own border; adding, removing, or reordering checks must preserve that section boundary.
- Show the server-validated GitHub login read-only, without an `@` prefix. Remove the editable Approver Name control. A typed or imported legacy display name never satisfies approval identity or replaces verified export attribution.
- Require a CODEOWNERS-validated identity for approval. Refresh server context before export, and use that verified login for both identity and display name. Keep a missing or unauthorized identity blocked with no manual fallback; approval metadata is not a new repository-write authority.
- Render passed checks with the existing green check, correctable pending checks with the amber warning, and hard failures with the red outlined circle-X and red value. Successful rows are noninteractive. Pending rows are native keyboard-operable correction buttons, not explanatory tooltips.
- Give hard-error rows the shared custom tooltip on hover and keyboard focus, plus an accessible description. Identity errors retain the logged-in username when available and explain failed CODEOWNERS authorization in the tooltip.
- Missing or invalid original rebuild evidence for selected Plan items is a hard failure: show `Not available`, block approval, and instruct the user to close Workbench, relaunch with `-Rebuild`, and reload. Do not offer an in-app repair link or run a rebuild automatically. An empty Plan alone is not missing evidence; its separate Plan requirement remains pending.
- A correction command closes Review Changes, opens the appropriate tab, reveals the first affected item in the destination's stable order, scrolls only its owned pane, and focuses the correction control. Missing Plan actions lead to Candidate Sources; no decisions are selected, changed, saved, or approved automatically.
- Resolve affected Plan items in the existing Plan sort order. Rule Issues uses the current category first, then the existing category order, and clears only the obstructing issue search. Clear an obstructing source query when opening a specific candidate control.
- Preserve unsaved wording. Its own warning returns to the same buffer and caret; unrelated correction navigation must require Save or Reset rather than discard it. Keep the menu open through ordinary Preview rendering, and close it only through dismissal or leaving Preview.
- Treat Review Changes as a click-opened non-modal popover. Dismiss on an outside click or user-driven outside scrolling, including wheel, touch, keyboard scrolling, and scrollbar interaction, while allowing the underlying click or scroll to continue normally. Keep it open for inside interactions, pointer-leave, ordinary rerenders, and programmatic scrolling. Retain Escape, the close icon, and the Review Changes toggle as explicit dismissal controls.

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
