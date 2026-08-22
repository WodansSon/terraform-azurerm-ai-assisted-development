# Code Review: local validator placement precedence

## CHANGE SUMMARY

- **Files Changed**: 1 modified Go implementation file
- **Branch**: fixture/local-validator-placement
- **Scope**: reviews schema validation placement for two changed fields

## FILES CHANGED

- `internal/services/example/example_resource.go`

## PRIMARY CHANGES ANALYSIS

The local change adds readable nested helper composition for `path_match` and a separate anonymous custom parser for `routing_expression`. Under `IMPL-SCHEMA-005`, established helper composition remains inline even when nested; only the genuinely complex parser crosses the service-local validator boundary.

## AZURERM LINTER

- **Status**: No issues
- **Run Scope**: local Go diff
- **Issue Count**: 0

## STRENGTHS

- `path_match` expresses its complete constraint through established `validation.All(...)` and `validation.Any(...)` helpers without unnecessary indirection.

## OBSERVATIONS

- None.

## ISSUES

- `routing_expression` embeds custom parsing, normalization, duplicate tracking, and multiple error paths in an anonymous `ValidateFunc` closure. This genuinely complex logic should move to `validate/routing_expression.go` with focused unit tests, keeping the schema readable without creating a wrapper for `path_match`.

## OVERALL ASSESSMENT

The nested `path_match` composition is correctly placed inline. The complex `routing_expression` parser should be extracted and unit tested before merge.
