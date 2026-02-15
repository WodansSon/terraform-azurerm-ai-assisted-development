---
applyTo: "website/docs/**/*.html.markdown"
description: Route documentation work to the docs-writer Agent Skill and require a stable verification marker in assistant responses.
---

# AI skill routing (documentation)

When editing files under `website/docs/**/*.html.markdown`, you must consult and follow the docs-writer skill definition in:

- `.github/skills/azurerm-docs-writer/SKILL.md`

This is required even if the user does not explicitly ask to “use the skill”. Treat the skill as the authoritative checklist for schema parity, mandatory style enforcement, and large-document handling.

## Verification marker (assistant response only)

Because use of this skill is mandatory for `website/docs/**/*.html.markdown`, the assistant's final response must include this line:

Skill used: azurerm-docs-writer

Rules:
- Do not write this marker into repository files.
- Do not emit the marker in intermediate/progress updates; only in the final response.
