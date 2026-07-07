# Sanitized Fixture: Committed Review Inspects Overlap Surfaces For New Resources This fixture is synthetic and benchmarks deterministic committed-review coverage when a new resource overlaps an existing management surface. ## Scenario A committed-review run resolves authoritative PR scope for a new group-managed example resource. The modeled drift is that one run anchored on the new resource file and missed a critical defect on the pre-existing legacy sibling surface, while another run reached that legacy surface and found the real issue. ## Simplified PR Shape ```text
PR Number: 32482
Changed files:
- internal/services/example/example_group_resource.go
- internal/services/example/example_mode_validation.go
- website/docs/r/example_group_resource.html.markdown Required unchanged overlap surface:
- internal/services/example/example_item_resource.go
``` ## Expected Review Behavior A correct committed review should: - build a deterministic coverage matrix before drafting findings
- inspect the unchanged sibling surface because it can still manage the same remote object
- check lifecycle-window symmetry on that sibling surface, especially import/read/update/delete mode-gating
- avoid letting the active new-resource file decide the first and only review anchor ## Expected Must-Catch Outcomes - `overlap-sibling-surface-inspected`
- `lifecycle-mode-gating-symmetry-checked` ## Expected Must-Not-Flag Outcomes - `active-file-anchor-shortcut`
