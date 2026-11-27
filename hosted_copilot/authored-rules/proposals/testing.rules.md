---
description: "Maintainer-authored testing review rule proposals for Hosted Copilot."
surface: testing
---

# Maintainer Testing Rule Proposals

Add rules using this format:

<!--
### TEST-MAINT-001: Concise rule title

- Rule: Write one concise, enforceable review rule.
- Provenance: confirmed-maintainer-convention
- Rationale: Explain why the rule is authoritative and useful to Hosted review.
-->

### TEST-PATTERN-007: Inline one-use helper arguments in fmt.Sprintf-based config builders

- Rule: In `fmt.Sprintf`-based acceptance-test configuration helpers, pass one-use helper calls such as `r.template(data)` directly as arguments instead of assigning them to a local variable first. Introduce a local only when the value is reused or transformed.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.
