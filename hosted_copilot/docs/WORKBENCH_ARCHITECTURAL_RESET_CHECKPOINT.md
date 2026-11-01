# Workbench Architectural Reset Checkpoint

## Status

This 2026-11-01 checkpoint preserves an unfinished Hosted Workbench experiment as reference for a holistic redesign. It is not release-ready, adoption-ready, or evidence that the current architecture should be continued. Implementation and test-fixing are paused by maintainer direction.

Do not delete, revert, migrate, publish, or resume this implementation merely because it is preserved in Git. Preserve the current source and useful UI decisions while designing the replacement independently.

## Working Direction

- Use local embedded SQLite for authoritative workspace state. SQLite is free and does not require a separately hosted database server. CSV is an optional import/export format, not a replacement transactional database.
- Design the relational model, constraints, transaction boundaries, concurrency handling, and workflow commands together. Do not translate each existing JSON structure into a table one-for-one.
- Put decisions, Plan mutations, original baselines, relationship review freshness, readiness, authorization, and audit rules in one server-owned domain implementation. Database constraints enforce structural integrity; they do not decide semantic compatibility between rule texts.
- Keep the UI thin: display server-derived state and own local input, selection, focus, filtering, clipboard behavior, and display semantics. Do not reconstruct authoritative workflow state independently in each view.
- Retire duplicated internal JSON state contracts. Retain minimal typed validation at genuine source-import, API, AI-response, and publication-export boundaries; replacing internal storage does not authorize weakening those boundaries.
- Preserve repository-managed published rules as controlled inputs and outputs. Define the distinction between published authority and mutable workspace state explicitly.
- Use configurable source and policy adapters so the solution can support other teams. Establish adaptability with one complete workflow under two different team profiles before committing to a full rewrite.

## Source-Backed Reference Work

- The working tree retains bounded relationship-review lifecycle, production-launcher wiring, failure classification, cancellation, and fixture-backed regression changes made before the architectural pause.
- Workbench source includes immutable source/catalog-bound original baselines, optional baseline records in existing version-7 sessions and version-4 portable drafts, original Reset behavior, guarded resolution saving and Plan membership, derived retained issue rows and pending counts, and read-only cross-view issue history.
- Shared success and wording presentation uses the dark green surface with neutral body text, semantic green status glyphs, `git-pull-request-done` for resolved status, `edit` before Suggested Consolidated Wording, a trailing colon, and a right-aligned light-mint Copy command. Copy never clears or reads the clipboard on empty/error outcomes.
- Source includes shared Title Case tooltip display and an in-place cost/headroom refresh that avoids remounting original assessment evidence during typing. These are reference implementations, not proof of architectural suitability.
- The attributed Codicon source, runtime inventory, generated sprite, and preview include the pinned resolved-status glyph.

## Browser-Only Reference Work

- The live source-checkpoint tab contains a cloned temporary UI draft. Preview Add/Retire choices were not written into the real saved draft. Its persistence interception and restore wrappers are browser-only machinery, not source code or production design.
- Promotion Plan's attention filter still replaces its table header and rows in source. A browser-only preview renders desired output off-screen and reconciles keyed rows and stable nodes. The live toggle retained the header, rows, and SVGs without table-node replacement. Do not copy its temporary element-redirection wrapper into production; decide a proper shared view-update boundary in the redesign.
- A resolved-advice clarification was requested for browser preview: Original Assessment and Original Recommended Maintainer Action labels, with Apply hidden for resolved issues. Its last tool response was not recorded, so its live application must be inspected rather than assumed. It is not in source.
- Browser conversations, pending requests, inputs, scroll state, CSSOM changes, temporary function wrappers, and local generated display data are not preserved by this Git commit. Do not reload or stop the live Workbench without explicit maintainer direction and consideration of that ephemeral state.

## Known Validation State

- The focused relationship-review journey passed 36 assertions during this work. It was not rerun after all subsequent edits; no final whole-checkpoint validation is claimed.
- Manual-rule-editing first failed its typing-stability assertion. The source refresh was repaired, and the live source preserved evidence and the saved recommendation pill during typing.
- The subsequent manual-rule-editing run failed with `Saving altered rebuild evidence or presented the edited wording as freshly assessed`. The assertion combines preserved assessment/issue evidence and a specific rationale-label expectation. The cause was not fully adjudicated; do not dismiss it as a harmless stale assertion or claim it was fixed.
- The failure occurs before the newly added resolution assertions finish. Those changes remain unverified by the complete owning journey, despite prior isolated live UI interactions.
- Testing was explicitly stopped. No complete Hosted validator, publication gate, or final all-pass result was obtained. No further feature fixes, test chasing, or cleanup refactors belong in this preservation checkpoint.

## Next Work

Agree on the replacement's domain model, relationships, server commands, authoritative state, external adapters, and ownership boundaries before implementation or migration. Use this checkpoint as evidence and requirements input, not as the architectural template.
