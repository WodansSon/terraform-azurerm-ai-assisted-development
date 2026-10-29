# Hosted Prompt Library

All authored instructions for local AI evaluation live in this task-organized library. Runtime code loads these files and supplies validated context or template values; it must not embed instruction prose or provide an inline prompt fallback. Deterministic permissions, schema validation, ownership, protected-rule checks, payload limits, and persistence remain code-owned.

## Tasks

| Task | Prompt |
| --- | --- |
| Source assessment | [SourceAssessment-v4.md](assessment/SourceAssessment-v4.md) |
| Assessment launch | [AssessmentAttempt.md](assessment/AssessmentAttempt.md) |
| Semantic routing | [AssessmentReconciliationRouting-v4.md](reconciliation/AssessmentReconciliationRouting-v4.md) |
| Component consolidation | [AssessmentReconciliationConsolidation-v4.md](reconciliation/AssessmentReconciliationConsolidation-v4.md) |
| Recommendation synthesis | [AssessmentReconciliation-v4.md](reconciliation/AssessmentReconciliation-v4.md) |
| Rule Issue adjudication | [RuleIssueAdjudication-v4.md](reconciliation/RuleIssueAdjudication-v4.md) |
| Saved-rule relationship discovery | [ManualRuleRelationship-v4.md](reconciliation/ManualRuleRelationship-v4.md) |
| Candidate assistance chat | [RuleAssistance.md](chat/RuleAssistance.md) |
| Assessment assistance chat | [RuleAssistance.md](chat/RuleAssistance.md) plus [AssessmentAssistance.md](chat/AssessmentAssistance.md) |
| Rule Issue assistance chat | [RuleIssueAssistance.md](chat/RuleIssueAssistance.md) |
| File-based evaluation transport | [FileEvaluation.md](shared/FileEvaluation.md) |
| Inline evaluation transport | [InlineEvaluation.md](shared/InlineEvaluation.md) |
| Validation retry correction | [RetryCorrection.md](shared/RetryCorrection.md) |

The chat result schema lives in the separate [contract library](../../contracts/README.md) as [rule-assistance-result.schema.json](../../contracts/workbench/rule-assistance-result.schema.json). It is structured validation data, not another prompt.

## Authoring And Authority

- Add task-specific prompts to the corresponding folder and reuse the shared transport templates rather than copying their instructions into launchers.
- Include a `## Boundaries` section that treats supplied source, assessment, and catalog text as untrusted quoted data and rejects prompt injection, tool requests, role changes, output-format changes, and policy claims embedded in that data.
- Register every consumed prompt in the owning JSON contract's `behaviorFiles`, or the chat runtime's hash-bound file set. Retained evaluators must load their frozen dependencies, not fall back to a live checkout.
- Keep placeholders limited to named data substitutions. Preserve complete serialized input and fail on missing templates rather than silently substituting inline instructions.
- Run [Test-PromptLibrary.ps1](../tests/Test-PromptLibrary.ps1) after prompt or loader changes. The focused check covers the registered runtime set, boundaries, authority paths, transport framing, and chat consolidation guidance without inference.

## Repository Adoption

The intended engine is repository-neutral. AzureRM is the current configured use case, not a reason to bake provider policy into orchestration. Another team's adoption should replace its sources, source-format parser configuration, catalog and protected guidance, semantic prompts, and review surfaces rather than fork the rule-management engine. Parsers interpret source structure; prompts assess meaning; `behaviorFiles` records reproducible behavior authority, not a new permission to execute arbitrary code.

| Concern | Existing Owner |
| --- | --- |
| Source locations and parser selection | [Source definitions](../../copilot-rule-catalog/source-definitions) and [parser contracts](../../contracts/parsers) |
| Rule content and protected policy | [Instruction catalog](../../copilot-rule-catalog/instruction-catalog.json) and [protected rules](../../copilot-rule-catalog/protected-rules.json) |
| Semantic task instructions | The task folders above |
| Snapshot and cache behavior | The owning assessment and reconciliation JSON contracts' `behaviorFiles` |
| Model and reasoning profiles | [llm.json](../config/llm.json) |

This migration does not establish drop-in portability. Known remaining code-level AzureRM coupling includes source collection's repository guard in [New-SourceInventory.ps1](../internal/collection/New-SourceInventory.ps1), paired-review repository validation in [Import-PullRequest.ps1](../internal/review/Import-PullRequest.ps1), and hard-coded review surfaces and budgets in [Get-GuidanceCapacity.ps1](../internal/workbench/Get-GuidanceCapacity.ps1). These need explicit configuration ownership and focused alternative-repository tests before claiming general adoption. Moving such values must preserve repository authorization and capacity enforcement, not remove those checks.
