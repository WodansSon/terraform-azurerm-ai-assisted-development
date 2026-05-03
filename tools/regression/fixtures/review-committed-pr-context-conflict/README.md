# Sanitized Fixture: Committed Review PR Context Conflict

This fixture is derived from a real committed-review scope-selection failure mode, but the final artifact is sanitized and does not retain live PR identity.

## Scenario

A committed review runs with both environment PR context and an explicit PR number supplied in the invocation text.

The environment context resolves to PR `30997`, but the invocation text says `PR 30998`.

There is no explicit user instruction that the supplied PR should override the active or viewed PR context.

## Expected Review Behavior

A correct committed review should:

- Detect that the two PR targets conflict
- Fail closed instead of silently choosing one PR target
- Stop before running the normal review flow or `azurerm-linter`
- Tell the user, in the prompt's pirate-style hard-stop voice, how to rerun with either the correct PR number or an explicit override

## Expected Must-Catch Outcomes

- `pr-context-conflict-hard-stop`

## Expected Must-Not-Flag Outcomes

- `silent-pr-selection`
