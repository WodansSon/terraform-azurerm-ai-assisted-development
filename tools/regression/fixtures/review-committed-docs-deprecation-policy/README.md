# Sanitized Fixture: Committed Review Docs Deprecation Policy

This fixture is derived from a real mixed committed-review docs-policy dispute, but the final artifact is sanitized and does not retain live PR identity.

## Scenario

A committed review runs with explicit PR context for a mixed change that touches one provider Go file, one live reference doc, and one versioned upgrade guide.

The implementation still accepts a legacy field on the non-5.0 path, but the live reference doc intentionally removes that field because it is legacy-only under the next-major deprecation model.

The upgrade guide carries the migration guidance instead.

## Simplified PR Shape

```text
PR Changed Files:
- internal/services/cdn/cdn_frontdoor_custom_domain_resource.go
- website/docs/r/cdn_frontdoor_custom_domain.html.markdown
- website/docs/guides/5.0-upgrade-guide.html.markdown

Legacy field still accepted on transitional path:
- minimum_tls_version
```

## Expected Review Behavior

A correct committed review should:

- Load and apply the docs contract and docs guidance for the `website/docs/**/*.html.markdown` files in scope
- Treat `DOCS-DEPR-001` and `DOCS-DEPR-002` as authoritative for next-major deprecations
- Accept removal of the legacy non-vNext field from the live reference doc
- Treat the upgrade guide as the correct place for migration guidance
- Cite the exact supporting docs rule IDs when explaining that behavior
- Avoid raising a docs-parity issue that tries to restore the legacy field to the live reference doc

## Expected Must-Catch Outcomes

- `docs-deprecation-policy-applied`
- `exact-docs-rule-citation`

## Expected Must-Not-Flag Outcomes

- `legacy-field-doc-parity-issue`
