# Sanitized Fixture: Committed Review Keeps PR-Scoped File References

This fixture is synthetic and benchmarks committed-review rendering when authoritative PR scope is already known.

## Scenario

A committed-review run resolves authoritative PR scope for a Front Door batch ruleset pull request. The historical failure mode is not scope resolution itself; it is the final review body leaking editor-session file links such as `vscode-file://...workbench.html` instead of preserving repo-scoped or PR-scoped references.

## Simplified PR Shape

```text
PR Number: 32482
In-scope files:
- internal/services/cdn/cdn_frontdoor_batch_rule_set_resource.go
- internal/services/cdn/cdn_frontdoor_batch_rule_set_resource_list.go
- website/docs/r/cdn_frontdoor_batch_rule_set.html.markdown

Forbidden rendered link shapes:
- vscode-file://...
- .../workbench.html
- .../AppData/...
- .../workspaceStorage/...
```

## Expected Review Behavior

A correct committed review should:

- keep file references repo-scoped or PR-scoped in the rendered review body
- preserve normal committed-review section layout and findings behavior
- never emit editor-local placeholder links in file lists, standards-check bullets, strengths, observations, issues, or recommendations

## Expected Must-Catch Outcomes

- `repo-scoped-file-references-preserved`
- `editor-local-link-leak-blocked`

## Expected Must-Not-Flag Outcomes

- `vscode-file-uri-output`
- `spill-path-output`
