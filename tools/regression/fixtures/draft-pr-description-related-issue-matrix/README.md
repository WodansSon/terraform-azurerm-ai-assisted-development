# Sanitized Fixture: Confirmed Related Issues Only

This fixture models three independent drafting runs for one example Resource.

## Explicit Developer Reference

The developer supplies `Fixes #12345` for the current invocation. The body preserves it.

## Commit Reference

A current-branch commit subject contains `Fixes #12345`. The body preserves it.

## No Confirmed Reference

No explicit input or current-branch commit contains an issue. The body writes `No related issue confirmed.`

No scenario searches GitHub, renders potential candidates, or checks the developer-owned issue-review acknowledgement.
