# Sanitized Fixture: Existing Pull Request Feedback Deduplication

This fixture is synthetic and sanitized.

## Scenario

A completed committed review freezes four visible findings for synthetic pull request `example/provider#42` at head commit `0123456789abcdef0123456789abcdef01234567`.

Before staging begins, the pull request already contains:

- an open inline suggestion-only thread that gives the exact replacement for the first frozen finding
- a resolved inline thread that raises the same underlying concern and correction as the second frozen finding using different wording
- a submitted review body that already raises the third frozen finding without an inline anchor
- no existing feedback equivalent to the fourth frozen finding

The complete review-thread connection, submitted reviews, and top-level discussion are available with all pages and replies. The existing feedback was written by reviewers other than the authenticated staging user.

## Frozen Findings

### Exact suggestion-only duplicate

The audit flags a fixed error string using `fmt.Errorf` and proposes `errors.New` at `internal/services/example/example_widget_resource.go:80`.

An existing open review thread at `https://github.com/example/provider/pull/42#discussion_r100` already contains the exact `errors.New` suggestion at that location.

### Materially equivalent resolved duplicate

The audit flags a default description that presents API-returned behavior as a Terraform-configured default at `website/docs/r/example_widget.html.markdown:70`.

A resolved review thread at `https://github.com/example/provider/pull/42#discussion_r101` asks the contributor to distinguish provider configuration from API-returned behavior. Its wording differs, but the concern and correction path are materially equivalent.

### Review-body duplicate

The audit flags missing focused update coverage for `network_mode` at `internal/services/example/example_widget_resource_test.go:45`.

A submitted review body at `https://github.com/example/provider/pull/42#pullrequestreview-200` already requests focused update coverage for that same behavior.

### New finding

The audit identifies that the delete path still sends `LegacyMode` in vNext 6.0 at `internal/services/example/example_widget_resource.go:144`.

No existing review thread, review body, or top-level discussion comment raises that concern. The exact guard is proven and directly applicable.

## Expected Staging Behavior

- Retrieve all inline review threads with replies and state, all submitted review bodies, and all top-level discussion comments before preview.
- Preserve all four frozen audit findings unchanged.
- Mark the first three staging findings `suppressed` with their matched URLs, authors, feedback kinds, states, and equivalence rationales.
- Treat the suggestion-only thread as substantive existing feedback.
- Suppress the resolved thread despite its different wording and resolution state.
- Suppress the equivalent submitted review body even though it has no inline anchor.
- Keep the delete-path finding because no existing feedback covers it.
- Preview exactly one inline comment and derive the Request Changes Summary only from that unsuppressed finding.
- Re-run the complete existing-feedback check after approval and before mutation.
- Create and verify one unsubmitted pending review only when the second check remains clear.
