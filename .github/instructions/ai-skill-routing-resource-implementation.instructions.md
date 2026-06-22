---
applyTo: "internal/**/*.go"
description: Route Go implementation work through the resource-implementation skill and its custom-poller companion when applicable.
---

# AI skill routing (resource implementation)

When editing or generating code under `internal/**/*.go`, you must consult and follow the skill definition in:

- `.github/skills/resource-implementation/SKILL.md`

When the task specifically involves migrating or replacing legacy polling logic such as `pluginsdk.Retry()`, `pluginsdk.StateChangeConf`, or `WaitForStateContext()`, you must also consult and follow:

- `.github/skills/custom-poller-migration/SKILL.md`

You must also consult and follow the shared implementation contract:

- `.github/instructions/implementation-compliance-contract.instructions.md`

This is required even if the user does not explicitly ask to "use the skill". Treat the implementation contract as the authoritative compliance layer, and treat the skill as the workflow layer that applies that contract plus companion implementation guidance.

## Verification marker (assistant response only)

Because use of this skill is mandatory for `internal/**/*.go`, the assistant's final response must include this line:

Skill used: resource-implementation

If `.github/skills/custom-poller-migration/SKILL.md` was also used for a polling-migration task, the assistant's final response must also include:

Skill used: custom-poller-migration

Rules:
- Do not write this marker into repository files.
- Do not emit the marker in intermediate/progress updates; only in the final response.
