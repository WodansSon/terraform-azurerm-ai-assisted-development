# Hosted Contract Library

This is the authoritative location for Hosted behavior descriptors and JSON validation schemas. Task prompts remain in [the prompt library](../tools/prompts/README.md). Rule catalogs, source definitions, inventories, assessment results, and browser drafts are configuration or data, not contract definitions.

## Families

| Folder | Owns |
| --- | --- |
| [adoption](adoption/) | Repository adoption descriptor and configurable token-policy schema |
| [assessment](assessment/) | Source-assessment behavior, draft, and baseline contracts |
| [catalog](catalog/) | Rule catalog, protected guidance, and guidance-capacity schemas |
| [parsers](parsers/) | Versioned parser descriptors and their shared contract schema |
| [reconciliation](reconciliation/) | Synthesis, routing, consolidation, adjudication, saved evaluation, cache, and run contracts |
| [review](review/) | Paired-review result schema |
| [sources](sources/) | Source-definition, source-definition-set, and inventory schemas |
| [workbench](workbench/) | Display, draft, approval, Rule Issues, Remote Rules exchange, chat result, and regression behavior schemas |

## Loading And Authority

- Resolve contract paths explicitly from this tree using the owning repository or Hosted root. Do not infer a schema location from a caller-supplied data file's directory or fall back to an old catalog or prompt location.
- Keep each JSON behavior descriptor next to the schema that validates it. Maintain existing behavior identity and ordinal `behaviorFiles` ordering, with repository-relative dependencies pointing to their actual source locations.
- Include required contracts and schemas in retained run snapshots. A retained evaluator must use its frozen repository tree rather than the live checkout.
- Preserve existing schema constraints, logical `$schema` values, `$id` identifiers, and payload names during location-only changes. These identifiers are not a request to look beside the input data file. Validation supplies the explicit schema path.
- Evaluator working directories may contain frozen copies with existing flat filenames. Those are bounded run inputs, not another authoritative source library.
- Treat existing artifacts as bound to their original authority. Do not rewrite saved results or cached hashes to make them appear current after a move; normal validation and reconstruction determine reuse.
- Use [Test-WorkbenchContracts.ps1](../tools/tests/Test-WorkbenchContracts.ps1) for the central layout and behavior-dependency boundary checks, followed by the owning focused tests for changed consumers.

## Configuration And Adoption

The [adoption descriptor](../tools/config/adoption.json) owns references to the required source-definition set, instruction catalog, and protected rules, together with the guidance token policy. Its references are relative to the Hosted root. The referenced files still own lane definitions and rule content; the descriptor does not introduce a second lane registry. This library exposes behavior and validation dependencies without making arbitrary files executable.

Capacity reports bind the resolved policy hash, include every configured area and combination exactly once, and account for every deployed catalog surface. Validation checks membership, paths, budgets, arithmetic, safety margin, unique-file totals, and the overall ceiling. Retained reconciliation snapshots include the descriptor, schema, and loader; they do not fall back to a live policy. Existing reports without this authority must be reconstructed, not relabeled as current.

See [repository adoption and token policy](../tools/README.md#repository-adoption-and-token-policy) for the read-only preflight, exit codes, and remaining runtime integration boundaries.

The centralized layout does not remove the remaining AzureRM-specific schema constraints or runtime assumptions. Repository adoption and adapter generalization are separate changes.
