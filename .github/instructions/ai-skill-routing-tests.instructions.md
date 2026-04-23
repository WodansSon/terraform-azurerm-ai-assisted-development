---
applyTo: "internal/**/*_test.go"
description: Route acceptance test work to the appropriate Agent Skill(s) and require a stable verification marker in assistant responses.
---

# AI skill routing (acceptance tests)

When editing or generating acceptance tests under `internal/**/*_test.go`, you must consult and follow the skill definition in:

- `.github/skills/acceptance-testing/SKILL.md`

You must also consult and follow the shared testing contract:

- `.github/instructions/testing-compliance-contract.instructions.md`

This is required even if the user does not explicitly ask to “use the skill”. Treat the testing contract as the authoritative compliance layer, and treat the skill as the workflow layer that applies that contract plus companion testing guidance.

## Verification marker (assistant response only)

Because use of this skill is mandatory for `internal/**/*_test.go`, the assistant's final response must include this line:

Skill used: acceptance-testing

Rules:
- Do not write this marker into repository files.
- Do not emit the marker in intermediate/progress updates; only in the final response.
