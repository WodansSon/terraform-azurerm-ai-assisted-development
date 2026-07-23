# Sanitized Fixture: PR Description Related Issue Matrix

This fixture is synthetic and sanitized. It models four independent issue-handling runs for `azurerm_example_widget`.

## Confirmed Reference

The user explicitly supplies an issue reference. The body preserves that reference under Related Issues.

## Plausible Advisory Candidate

Search returns an open issue containing the exact Terraform surface and the changed `retention_days` property. It appears in the advisory table with a reason, but the body does not claim that the change closes it.

## No Match

Search succeeds and every result fails the exact-identifier filter. The output says `No potential related issues found.`.

## Search Unavailable

The search tool is unavailable. Title and body drafting continue, and the output says `Potential related issue search unavailable.`.
