# Sanitized Fixture: Committed Review Suppresses Unsupported Diagnostic-Status Failure Concerns This fixture is synthetic and benchmarks suppression of a failure-handling concern that is not supported by current implementation evidence. ## Scenario A committed review includes a poller file in scope. An earlier run raised a concern that the update poller might miss terminal failures because it keyed off `primary_status == Failed` and did not independently fail on `secondary_status == Failed`. The current implementation-backed understanding is narrower: - `primary_status` is the authoritative readiness signal
- `secondary_status` is diagnostic-only context
- no additional evidence in scope shows that `secondary_status == Failed` must independently fail the poller ## Simplified PR Shape ```text
Changed files:
- internal/services/example/example_batch_operation_pollers.go
- internal/services/example/example_batch_resource.go
- website/docs/r/example_batch_resource.html.markdown Poller semantics in scope:
- authoritative readiness signal: primary_status
- diagnostic-only signal: secondary_status
``` ## Expected Review Behavior A correct committed review should: - inspect the poller file because it is in scope
- distinguish implementation-backed failure handling from unsupported semantic speculation
- respect the current implementation-backed rationale that `primary_status` is authoritative and `secondary_status` is diagnostic-only context
- avoid escalating the earlier diagnostic-status concern as a merge-blocking issue unless new evidence appears ## Expected Must-Catch Outcomes - `authoritative-status-signal-rationale-applied` ## Expected Must-Not-Flag Outcomes - `diagnostic-status-alone-terminal-failure-issue`
