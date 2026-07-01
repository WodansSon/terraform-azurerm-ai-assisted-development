# Sanitized Fixture: Resource Implementation CustomizeDiff IsKnown Guard This fixture is synthetic and is intentionally validating a local toolkit implementation-guidance rule. ## Scenario A maintainer or contributor is adding `CustomizeDiff` validation under `internal/services/example/`. The code reads nested raw config from `GetRawConfig()` and walks into a `conditions` block using `LengthInt()` and `AsValueSlice()` directly. The contributor asks for implementation guidance on whether this is a safe pattern. The modeled failure mode is that generic `GetRawConfig()` guidance stops at configured-versus-unknown values and does not require `IsKnown()` before raw `cty.Value` shape inspection, or it broadens the fix into generic `IsKnown()` advice instead of keeping it specific to diff-time raw traversal. ## Simplified Code Shape ```go
rawConfig := diff.GetRawConfig()
conditions := rawConfig.GetAttr("conditions") if conditions.IsNull() || conditions.LengthInt() == 0 { return nil
} condition := conditions.AsValueSlice()[0].AsValueMap()
matchValues := condition["match_values"]
if matchValues.LengthInt() == 0 { return nil
}
``` ## Expected Guidance A correct `resource-implementation` response should: - anchor on `IMPL-SCHEMA-013` as the authoritative rule
- require `IsKnown()` before `LengthInt()`, `AsValueSlice()`, `AsValueMap()`, `Index()`, or similar raw `cty.Value` shape-inspection methods in `CustomizeDiff`
- say unknown values should defer validation and return `nil` instead of being treated as empty or allowed to panic
- keep any `AsValueMap()` discussion narrow to top-level field-presence detection when the top-level raw config value is already known and non-null
- include `Skill used: resource-implementation` in the final response marker ## Expected Must-Catch Outcomes - `isknown-before-shape-inspection`
- `defer-unknown-validation`
- `presence-detection-note-stays-narrow` ## Expected Must-Not-Flag Outcomes - `generic-isknown-everywhere`
- `unknown-equals-empty`
