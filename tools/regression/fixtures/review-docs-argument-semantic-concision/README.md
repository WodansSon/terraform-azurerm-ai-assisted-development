# Sanitized Fixture: Argument Semantic Concision

This fixture is synthetic and sanitized for regression benchmarking.

## Scenario

A resource argument bullet contains four required standard sentences:

- a field definition
- canonical possible values
- a schema-backed default
- the standard ForceNew sentence

The bullet also contains one supplemental selection caveat that is useful but not part of the field's core schema semantics.

## Simplified Docs Shape

```markdown
* `sku_name` - (Optional) The SKU used for this gateway. Possible values are `Standard` and `Premium`. Defaults to `Standard`. Changing this forces a new resource to be created. Choose the SKU only after confirming the expected regional capacity with the service team.
```

## Expected Review Behavior

A correct docs review should:

- treat the four required standard sentences as compliant regardless of sentence count
- preserve the definition, `Possible values are`, `Defaults to`, and ForceNew sentences in the bullet
- flag only the supplemental regional-capacity sentence under `DOCS-ARG-011`
- require that supplemental sentence to move into an adjacent `-> **Note:**`
- identify the specific excessive content rather than citing sentence count as the defect

## Expected Must-Catch Outcomes

- `supplemental-caveat-needs-note`

## Expected Must-Not-Flag Outcomes

- `four-required-sentences-exceed-cap`
- `move-required-semantics-to-note`
