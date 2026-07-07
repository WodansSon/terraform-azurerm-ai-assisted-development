# Sanitized Fixture: Committed Review Prefers Direct HTTPS PR-Files Retrieval First This fixture is synthetic and benchmarks the explicit-PR direct-API-first rule for committed review. ## Scenario A committed-review run is invoked with an explicit PR number. The preferred direct shell-native HTTPS GitHub PR-files request for that exact PR number is available. The modeled failure mode is that review starts with active or viewed PR metadata tools, hits summary-only output or a forbidden spill-file transport, and then detours into local `gh api` fallback or fail-closed behavior even though the direct HTTPS PR-files request should have been tried first. ## Simplified PR Shape ```text
Invocation:
- /code-review-committed-changes PR 4828 User request:
- Explicit PR number only
``` ## Expected Review Behavior A correct committed review should: - try the preferred direct shell-native HTTPS GitHub PR-files request first
- avoid starting explicit-PR scope resolution with summary-only PR metadata tools
- avoid detouring into automatic `gh api` fallback or spill-file-driven fail-closed behavior while the direct PR-files path remains available ## Expected Must-Catch Outcomes - `direct-pr-files-api-first-choice` ## Expected Must-Not-Flag Outcomes - `metadata-tools-before-direct-pr-files-api`
- `automatic-gh-cli-fallback-without-user-request`
