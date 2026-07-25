# Sanitized Fixture: PR Description Surface And Title Matrix

This fixture is synthetic and sanitized. It models separate invocations of `draft-pr-description` in an AzureRM-shaped checkout.

## New Resource With Required List Resource

The change adds `azurerm_example_widget`, its Resource Identity support, required List Resource, tests, registration, and both documentation pages.

Compact implementation evidence proves these material user-facing behaviors:

- Managed reads reject an API object whose discriminator no longer matches the Resource type, preventing cross-type ownership.
- The computed `authentication_type` attribute identifies returned objects, including List Resource results.
- The List Resource enumerates objects across all projects in one parent account or within one selected project.
- Managed reads preserve configured metadata keys to prevent API-added metadata from causing drift, while imports and list results return complete API metadata when no prior configuration exists.

The description represents all four behaviors once in concise prose. It does not substitute client construction, registration, helper names, generated identity code, or vendored SDK details for them. It does not evaluate correctness, report missing tests, or recommend implementation changes.

Expected title: `New Resource: `azurerm_example_widget``.

The changelog contains separate New Resource and New List Resource feature lines.

## New Resource, Data Source, And List Resource

The change adds a Resource and Data Source sharing `azurerm_example_widget`, plus the required List Resource. The same coherent service-package change exports `retention_days` from the existing `azurerm_example_widget_policy` Data Source, updates the existing `azurerm_example_widget_policy` Resource so removing cache configuration and origin override settings actively clears both API-retained value families, and improves `match_values` validation in the existing `azurerm_example_widget_rule` Resource. Registration, Resource Identity, and supporting polling changes only support those user-facing surfaces.

The description states compactly that removing cache configuration and origin override settings clears both families' previous service-side values and prevents residual state. It does not substitute serialization flags, null payload fields, custom client names, or poller mechanics for that observable behavior, and it does not omit cache clearing merely because only origin override removal requires an additional settling poller.

The active clear behavior is owned by a changed custom payload marshaller under `azuresdkhacks/`. Its compact comment and clear-path logic show that absent cache configuration and origin override values are both sent as explicit removals because omission would preserve prior service-side values. The evidence plan reads that narrow behavior-owning block even though the marshaller remains subordinate for title and changelog purposes.

An existing consumer Resource changes lifecycle polling, but its schema and referenced-object ID path already accept the new object type without changed enabling logic. The draft may describe the proven lifecycle correction, but it does not claim that the consumer newly supports the new object type.

Expected title: `New (Data Source|Resource) - `azurerm_example_widget``.

The changelog contains these exact feature lines:

- `[FEATURE] * **New Resource**: `azurerm_example_widget``
- `[FEATURE] * **New Data Source**: `azurerm_example_widget``
- `[FEATURE] * **New List Resource**: `azurerm_example_widget``

The changelog also contains these exact title-subordinate enhancement lines:

- `[ENHANCEMENT] * Data Source: `azurerm_example_widget_policy` - export the `retention_days` attribute`
- `[ENHANCEMENT] * `azurerm_example_widget_policy` - clear removed cache configuration and origin override settings`
- `[ENHANCEMENT] * `azurerm_example_widget_rule` - improve validation for the `match_values` property`

The Resource and Data Source lines remain separate even though both use the Terraform name `azurerm_example_widget_policy`. Neither line describes behavior owned by the other surface.

The supporting registration, Resource Identity, custom payload marshaller, and polling changes do not receive independent changelog lines.

## Distinct Lifecycle Outcomes

One existing sibling, `azurerm_example_widget_a`, changes its create path to retry a transient in-progress conflict before waiting for terminal provisioning. A separate sibling, `azurerm_example_widget_b`, changes create, update, and delete paths to wait for their own readiness or terminal states, but it does not add Resource A's retry behavior.

The evidence inventory records these as separate owner, lifecycle-path, behavior-kind, and observable-outcome claims. Shared helper use or one connected change intent does not merge those claims.

The description may place both Resources in one paragraph, but it attributes retry behavior only to Resource A creation and waiting behavior only to the applicable Resource B paths. It does not say that both Resources retry and wait, that Resource B retries, or that Resource A update and delete paths changed.

Expected Resource A changelog wording names creation specifically: `[BUG] * `azurerm_example_widget_a` - retry transient in-progress creates and wait for terminal provisioning`.

Expected Resource B changelog wording contains no retry claim: `[BUG] * `azurerm_example_widget_b` - wait for create, update, and delete operations to reach readiness or terminal states`.

Existing Resource and Data Source changelog owner tokens remain plain Markdown text. Only Terraform names use code formatting; owner tokens are not bolded, italicized, or linked.

## Importer-Only Ownership Guard

An existing `azurerm_example_widget_legacy` Resource changes only its importer. The importer reads the remote discriminator and rejects objects owned by `azurerm_example_widget`; ordinary create, read, update, and delete paths are unchanged.

The description says that the legacy Resource prevents importing or adopting those objects. It does not claim that every lifecycle operation rejects them or that the Resource generally prevents their management.

Expected changelog line: `[ENHANCEMENT] * `azurerm_example_widget_legacy` - prevent importing objects owned by `azurerm_example_widget``.

## Standalone List Resource

The managed Resource already exists on the base. The change adds only List Resource support, query tests, and list documentation.

Expected title: `New List Resource: `azurerm_example_widget``.

## Existing Resource Change

One run adds support for `retention_days`. A second run corrects how that property is populated. A combined behavior change is classified as a bug fix before an enhancement.

Expected title wording names `azurerm_example_widget` and the property explicitly.

A separate run changes the existing Resource so create no longer returns success before Azure reaches a terminal provisioning state. Compact implementation and test evidence ties the polling change to the previously premature success behavior.

Expected changelog line: `[BUG] * `azurerm_example_widget` - wait for creation to reach a terminal provisioning state before returning`.

This run checks `Bug Fix`, not `Enhancement`. A poller refactor without evidence of corrected user-facing behavior remains a subordinate implementation change and receives no changelog line.

## Documentation And Contributor Guidance

One run changes only `website/docs/r/example_widget.html.markdown`. Another changes only `contributing/topics/example-guidance.md`.

Expected title prefixes are `Docs:` and `Contributing:` respectively, with no changelog recommendation.
