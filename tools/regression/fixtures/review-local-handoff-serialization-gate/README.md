# review-local-handoff-serialization-gate

Synthetic fixture for the generic local review workflow.

This fixture models a workflow change where:

- the shared review contract should be the authoritative source for the immediate-emission rule
- the shared review contract should require every evidence-backed concern discovered during a mandatory issue-class check to become a structured handoff record immediately before routed roles begin
- the coverage matrix schema should carry emitted handoff record IDs and issue-class-to-record-ID bindings
- the review-coordinator skill should own a post-review linkage-validation phase over those bindings while consuming the contract-owned rule rather than restating it independently
- the local review prompt should invoke that router-owned linkage-validation phase and the contract-owned immediate-emission rule rather than carrying duplicate policy text

The benchmark is satisfied when the review flags any design that lets mandatory issue-class checks complete without immediate machine-checkable linkage to emitted handoff records.
