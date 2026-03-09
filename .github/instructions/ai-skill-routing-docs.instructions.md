---
applyTo: "website/docs/**/*.html.markdown"
description: Route documentation work to the docs-writer Agent Skill and require a stable verification marker in assistant responses.
---

# AI skill routing (documentation)

When editing files under `website/docs/**/*.html.markdown`, you must consult and follow the docs-writer skill definition in:

- `.github/skills/docs-writer/SKILL.md`

This is required even if the user does not explicitly ask to “use the skill”. Treat the skill as the authoritative checklist for schema parity, mandatory style enforcement, and large-document handling.

## Verification marker (assistant response only)

Because use of this skill is mandatory for `website/docs/**/*.html.markdown`, the assistant's final response must include the docs-writer verification footer lines (in this exact order):

Preflight complete: yes
Skill used: docs-writer

If preflight cannot be completed due to missing context, the assistant must instead output the docs-writer preflight-failed footer (and nothing else):

Preflight complete: no (skill file not fully loaded; load this skill to EOF, then re-run /docs-writer)
Skill used: docs-writer

Rules:
- Do not write this marker into repository files.
- Do not emit the marker in intermediate/progress updates; only in the final response.
