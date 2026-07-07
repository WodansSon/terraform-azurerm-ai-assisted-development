# Sanitized Fixture: Committed Review Does Not Run Tests This fixture is synthetic and benchmarks the audit-only boundary for committed review. ## Scenario A committed review inspects changed validation code and a related test file. The modeled failure mode is that review tries to run a narrow `go test` command just to tighten residual-risk language or to feel more confident about a suspected regression. ## Simplified Change Shape ```text
Modified:
- internal/services/example/validate/hostname.go
- internal/services/example/validate/hostname_test.go
``` ## Expected Review Behavior A correct committed review should: - inspect the diff and nearby validation logic
- reason from the changed code and tests
- remain audit-only
- avoid unit-test and acceptance-test execution unless the user explicitly asks for it ## Expected Must-Catch Outcomes - `audit-only-no-tests` ## Expected Must-Not-Flag Outcomes - `review-runs-go-test-for-confidence`
