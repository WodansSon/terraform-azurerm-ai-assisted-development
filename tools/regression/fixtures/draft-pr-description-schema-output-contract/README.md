# Sanitized Fixture: PR Description Schema And Output Contract

This fixture is synthetic and sanitized.

## Valid Payload

The modeled `pr-description` payload includes all required base metadata, changed files, classified surfaces, title decision, complete body, checklist decisions, changelog decision, evidence gaps, and issue-search state.

The prompt validates it and renders exactly these headings in order:

- `Suggested PR Title`
- `Why This Title`
- `Draft PR Body`
- `Evidence Notes`
- `Potential Related Issues`

The response ends with `Preflight complete: yes` and `Skill used: pr-description`.

## Invalid Payload

The second run omits `checklistDecisions`. Schema validation fails before rendering. The response contains only the prompt-owned schema-invalid hard-stop sentence.
