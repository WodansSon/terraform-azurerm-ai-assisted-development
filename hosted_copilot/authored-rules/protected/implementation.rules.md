---
description: "Maintainer-authored protected implementation review rules for Hosted Copilot."
surface: implementation
---

# Protected Implementation Review Rules

Add rules using this format:

<!--
### IMPL-RULE-001: Concise protected rule title

- Rule: Write one concise, enforceable review rule.
- Provenance: confirmed-maintainer-convention
- Rationale: Explain why the rule must remain immutable.
-->

### IMPL-WF-000: Classify AzureRM implementation resource types

- Rule: Classify implementation code as legacy, typed, or framework before applying resource-type-specific rules or suggesting changes. Legacy implementations use untyped Plugin SDK patterns with function-built `*pluginsdk.Resource` values and `*pluginsdk.ResourceData` callbacks. Typed implementations use receiver-based `internal/sdk` resource or data-source contracts. Framework implementations use Terraform Plugin Framework interfaces and request/response types, including list resources, ephemeral resources, and provider-defined functions. Use typed patterns for current ordinary resource and data source work, and framework patterns for framework-native or specialized surfaces. Preserve the existing resource type unless the change explicitly migrates it.
- Provenance: confirmed-maintainer-convention
- Rationale: Required first-party instruction infrastructure.
