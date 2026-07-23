# Sanitized Fixture: PR Description Surface And Title Matrix

This fixture is synthetic and sanitized. It models separate invocations of `draft-pr-description` in an AzureRM-shaped checkout.

## New Resource With Required List Resource

The change adds `azurerm_example_widget`, its Resource Identity support, required List Resource, tests, registration, and both documentation pages.

Expected title: `New Resource: `azurerm_example_widget``.

The changelog contains separate New Resource and New List Resource feature lines.

## New Resource, Data Source, And List Resource

The change adds a Resource and Data Source sharing `azurerm_example_widget`, plus the required List Resource.

Expected title: `New (Data Source|Resource) - `azurerm_example_widget``.

## Standalone List Resource

The managed Resource already exists on the base. The change adds only List Resource support, query tests, and list documentation.

Expected title: `New List Resource: `azurerm_example_widget``.

## Existing Resource Change

One run adds support for `retention_days`. A second run corrects how that property is populated. A combined behavior change is classified as a bug fix before an enhancement.

Expected title wording names `azurerm_example_widget` and the property explicitly.

## Documentation And Contributor Guidance

One run changes only `website/docs/r/example_widget.html.markdown`. Another changes only `contributing/topics/example-guidance.md`.

Expected title prefixes are `Docs:` and `Contributing:` respectively, with no changelog recommendation.
