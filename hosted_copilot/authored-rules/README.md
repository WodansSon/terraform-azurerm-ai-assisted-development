# Authored Rules

This directory is the human authoring surface for repository-owned Hosted review rules.

## Proposals

Add candidate rules under `proposals/`. The assessment and promotion workflow evaluates these rules before they can enter the lifecycle-managed instruction catalog.

## Protected Rules

Add immutable runtime rules under `protected/`. These rules compile directly into generated Hosted instructions and appear as read-only protected rules in the Workbench.

Both channels use the same rule format:

```markdown
### IMPL-RULE-001: Concise rule title

- Rule: Write one concise, enforceable review rule.
- Provenance: confirmed-maintainer-convention
- Rationale: Explain why the rule exists.
```

The file frontmatter declares the target surface. The source directory determines whether a rule is a proposal or protected. Do not edit `copilot-rule-catalog/protected-rules.json` directly; regenerate it with `tools/commands/catalog/Generate-ProtectedRules.ps1 -Write`.
