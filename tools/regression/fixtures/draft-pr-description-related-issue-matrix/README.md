# Sanitized Fixture: PR Description Related Issue Matrix

This fixture is synthetic and sanitized. It models independent issue-handling and search-budget runs for `azurerm_example_widget`.

## Authoritative Existing Pull Request Reference

An active branch identity and an exact final-head prior identity each contain `Fixes #12345`. Advisory issue search returns no match. The body preserves the confirmed reference rather than replacing it with `No related issue confirmed.`.

## Stale Closing Reference

An active pull request contains `Fixes #12345`, but current local evidence changes behavior so the issue is no longer demonstrably resolved. The body removes the closing claim, `existingPullRequest.evidenceConflicts` records the contradiction, and Evidence Notes requests contributor confirmation.

## Commit Association Only

Local `HEAD` appears as an intermediate commit in a merged pull request that later accumulated a broader scope. Its issue references remain advisory and outside the copy-ready body.

## Confirmed Reference

The user explicitly supplies an issue reference. The body preserves that reference under Related Issues.

`existingPullRequest.confirmedReferences` contains only references extracted from an identity-trusted pull request before conflict resolution. `relatedIssues.confirmedReferences` contains the final references approved for the generated body after combining every authoritative source and resolving conflicts.

## Plausible Advisory Candidate

Search returns an open issue containing the exact Terraform surface and the changed `retention_days` property. It appears in the advisory table with a reason, but the body does not claim that the change closes it.

## No Match

Search succeeds and every result fails the exact-identifier filter. The output says `No potential related issues found.`.

## Search Unavailable

The search tool is unavailable. Title and body drafting continue, and the output says `Potential related issue search unavailable.`.

## Search Budget

The changed scope has five Terraform surfaces, nine changed schema properties, and three changed error fragments. Duplicate search uses only the primary surface and one independently user-facing secondary surface. Advisory issue search uses at most four high-signal queries. Each search group runs concurrently. Because the change is an ordinary new feature rather than an error-behavior fix, no error-fragment extraction or search runs.
