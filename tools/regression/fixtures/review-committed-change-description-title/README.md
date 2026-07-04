# Sanitized Fixture: Committed Review Change-Focused Title

This fixture is synthetic and sanitized. It exists to prove that the final committed-review heading uses a concise change-focused title when the review already established what the pull request changes.

## Scenario

The modeled committed change adds a new Cognitive Services project-connection resource family, including:

- a typed managed resource
- a framework list resource
- acceptance coverage
- registration and client wiring
- resource and list-resource docs

## Expected Title Behavior

- The final heading should summarize the change, for example `Add Cognitive Services project-connection resource family`.
- The heading must not collapse to only a bare PR identifier such as `PR 32628` when authoritative PR context and richer current-run summary evidence exist.
