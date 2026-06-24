# New Resource Surface Resolution Workflow Notes

These notes capture a possible future workflow for new AzureRM resource implementation in this toolkit.

## Why This Exists

The current single-agent implementation guidance already tells the agent how to look for APIs and SDK surfaces. A future dedicated workflow would be different: it would separate discovery and surface resolution from the actual implementation pass.

This looks like the strongest candidate in the toolkit for a specialized multi-agent workflow.

## Core Design Direction

- Keep normal single-agent implementation as the default path.
- Add a separate discovery-oriented workflow for new resources when API availability or package ownership is unclear.
- Do not model discovery as `service -> single SDK package`.
- Model discovery as `user-facing surface -> candidate implementation surfaces/packages`.

## Stress-Test Example

`cdn_frontdoor` is the best known stress-test example.

Why it matters:

- user-facing Front Door resources do not always map cleanly to a single SDK package
- some resources resolve to CDN surfaces
- some resources resolve to Front Door WAF surfaces
- some resources depend on adjacent surfaces such as DNS validation, Private Link, or separate rules/rulesets API packages

This means the workflow must resolve the actual implementation surface instead of assuming naming alone is enough.

## Future Workflow Shape

Potential entrypoint:

```text
/new-resource --surface <surface> --resource <resource-name> [--api-version <version>] [--package-hint <hint>]
```

Important rule:

- package hints should be optional
- the workflow should discover the real package ownership when possible

## Proposed Discovery Steps

1. Accept the requested user-facing Azure surface.
2. Resolve candidate Pandora/SDK packages for that surface.
3. Search all candidate packages before declaring the API unavailable.
4. Check upstream evidence when generated SDK coverage is missing or unclear.
5. Compare neighboring provider implementations for established patterns.
6. Emit a structured resolution result before implementation starts.

## Structured Resolution Output

The workflow should report:

- requested surface
- requested resource name
- candidate packages searched
- resolved package or packages
- resolved API version or versions
- resource ID or import namespace expectations
- evidence source
- implementation viability

## Separation of Responsibilities

This should remain clearly separated from the existing single-agent implementation guidance.

- single-agent guidance: how to implement when the surface is already reasonably clear
- future discovery workflow: how to resolve unclear or cross-surface ownership before implementation

If this is added later, the trigger boundary needs to be explicit so the agent knows when to stay single-agent and when to escalate into the discovery workflow.

## Key Constraint

Only declare an API or resource unavailable after searching all candidate packages and, when needed, upstream evidence sources.
