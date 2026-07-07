# Sanitized Fixture: Committed Review PR-Authoritative Scope This fixture is synthetic and sanitized for regression benchmarking. ## Scenario A committed review runs with explicit pull request context and a bounded PR diff. The authoritative PR scope contains one provider Go file modeled as `internal/services/example/example_resource.go`. The local branch also contains a separate docs-only commit modeled as `docs/TROUBLESHOOTING.md`, but that commit is not part of the active pull request. The benchmarked behavior is whether the committed review keeps the review body scoped to the PR diff instead of leaking the broader branch diff into files changed, findings, or review framing. ## Simplified PR Shape ```text
PR Number: 4821
PR Changed Files:
- internal/services/example/example_resource.go Branch-only commits outside the PR:
- docs/TROUBLESHOOTING.md
``` ## Expected Review Behavior A correct committed review should: - Treat the explicit PR changed-file set as the authoritative committed-review scope
- Keep `docs/TROUBLESHOOTING.md` and any other branch-only commits out of the files-changed section and out of findings
- Describe the committed review as PR-scoped rather than as a generic branch diff against `origin/main...HEAD`
- Continue to run `azurerm-linter` with PR scope for the in-scope provider Go file ## Expected Must-Catch Outcomes - `pr-scope-authoritative`
- `scope-reporting-consistency` ## Expected Must-Not-Flag Outcomes - `branch-only-doc-finding`
- `branch-wide-diff-framing`
