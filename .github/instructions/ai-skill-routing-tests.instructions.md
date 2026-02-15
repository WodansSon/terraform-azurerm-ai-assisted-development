---
applyTo: "internal/**/*_test.go"
description: Route acceptance test work to the appropriate Agent Skill(s) and require a stable verification marker in assistant responses.
---

# AI skill routing (acceptance tests)

When editing or generating acceptance tests under `internal/**/*_test.go`, you must consult and follow the skill definition in:

- `.github/skills/azurerm-acceptance-testing/SKILL.md`

This is required even if the user does not explicitly ask to “use the skill”. Treat the skill as the authoritative checklist for acceptance test patterns (`BuildTestData`, `ExistsInAzure`, `ImportStep`, `RequiresImportErrorStep`) and safe test execution guidance.

## Verification marker (assistant response only)

Because use of this skill is mandatory for `internal/**/*_test.go`, the assistant's final response must include this line:

Skill used: azurerm-acceptance-testing

Rules:
- Do not write this marker into repository files.
- Do not emit the marker in intermediate/progress updates; only in the final response.
