# Sanitized Fixture: PR Description Schema And Output Contract

This fixture is synthetic and sanitized.

## Valid Payload

The modeled `pr-description` payload uses `schemaVersion=1.2` and includes stable initial and final repository fingerprints, separate `existingPullRequest` discovery, trust, local relation, confirmed references, and structured conflict data plus all required base metadata, changed files, classified surfaces, title decision, complete body, checklist decisions, changelog decision, evidence gaps, and issue-search state.

The `existingPullRequest` object does not select the comparison base unless its trust level is `active-branch-identity`. Exact final-head prior evidence remains separate from current base resolution.

The prompt validates it and renders exactly these headings in order:

- `Suggested PR Title`
- `Why This Title`
- `Draft PR Body`
- `Evidence Notes`
- `Potential Related Issues`

The response ends with `Preflight complete: yes` and `Skill used: pr-description`.

## Invalid Payloads

The invalid runs cover:

- Missing `checklistDecisions`.
- `FEATURES` paired with a `[BUG]` line.
- `recommended` with no entries.
- `not-recommended` or `breaking-input-required` with entries.
- Non-contract fallback text.
- Active branch identity without `baseCommit`.
- An `existing-pr` base without `pullRequestNumber` or with a refresh status other than `not-applicable`.
- Missing or malformed repository-state fingerprints.

Schema validation fails before rendering. The response contains only the prompt-owned schema-invalid hard-stop sentence.
