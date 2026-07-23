# Sanitized Fixture: PR Description Base And Evidence Matrix

This fixture is synthetic and sanitized. It models separate invocations of `draft-pr-description`.

## Existing Pull Request Base Plus Local Changes

Authoritative metadata provides a base commit. The branch also has an unstaged edit and a non-ignored untracked test file. The merge-base-to-working-tree scope includes both local changes as well as branch commits.

The prompt loads the template and contributor guidance from the selected base commit. It uses the merge base only to collect the candidate change-set.

## Missing Base Authority

The merge-base revision lacks `.github/pull_request_template.md` in one run and `contributing/topics/guide-resource-identity.md` in another. Each run stops and names the missing path exactly.

## Unrelated Service Packages

The branch changes primary managed Resources in two distinct synthetic service packages. The fixture paths use the corpus-approved example namespace, while the supplied classification evidence keeps the package identities distinct. Neither change is a companion of the other. Drafting stops before title selection.

## Validation Evidence

- One run observes a named current-run unit test complete successfully.
- One run observes an acceptance command exit successfully after all tests skip because required Azure environment variables are absent.
- One run has no validation output.
- One run has an older existing pull request claim that does not cover the current diff.

Only the first run checks applicable local validation. The remaining runs keep the checklist conservative and add concise evidence gaps.
