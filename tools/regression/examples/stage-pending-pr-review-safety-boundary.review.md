## Challenge Adjudication

- Immutable audit baseline: `3` findings preserved
- Test-coverage dispute:
  - Disposition: `accepted`
  - Result: original test finding `withdrawn`
  - Rationale: targeted inspection confirms `TestAccExampleWidget_versionModes` exercises current provider 5.x and vNext 6.0 behavior
- Human-proposed delete-path concern:
  - Disposition: `accepted`
  - Origin: `human`
  - Result: blocking delete-path finding `added`
  - Rationale: targeted inspection confirms the changed delete path sends legacy cleanup data without the matching version guard
- Adjudication state: `settled`

The original audit remains unchanged. The settled staging state contains the retained cross-path issue, the withdrawn test issue, the retained documentation question, and the added human delete-path issue.

## Pending Review Preview

- Pull request: `example/provider#42`
- Head commit: `0123456789abcdef0123456789abcdef01234567`
- Comment count: `3`
- File coverage:
  - `internal/services/example/example_widget_helpers.go`
  - `internal/services/example/example_widget_resource.go`
  - `website/docs/r/example_widget.html.markdown`
- Top-level review body: empty
- Submission event: omitted

The first finding is one indivisible schema-to-expand invariant. Its thread is anchored in `internal/services/example/example_widget_helpers.go` and covers that file plus `internal/services/example/example_widget_resource.go`.

## Inline Comments

### `internal/services/example/example_widget_helpers.go:88` (`RIGHT`)

**Problem:** The schema limits `legacy_mode` to current provider 5.x (`!features.SixPointOh()`), but this expansion path still reads it for vNext 6.0 (`features.SixPointOh()`). This one invariant spans `internal/services/example/example_widget_resource.go` and `internal/services/example/example_widget_helpers.go`.

**Effect:** A vNext 6.0 configuration can reach behavior for an argument that its schema no longer exposes, leaving the version branches asymmetric.

**Suggested change:** Guard the legacy expansion with `!features.SixPointOh()` and keep the vNext 6.0 payload path independent of `legacy_mode`.

**Reference:** [guide-breaking-changes.md (Breaking Schema Changes and Deprecations)](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/contributing/topics/guide-breaking-changes.md)

### `internal/services/example/example_widget_resource.go:144` (`RIGHT`)

**Problem:** The delete path sends current provider 5.x (`!features.SixPointOh()`) legacy cleanup data when running in vNext 6.0 (`features.SixPointOh()`), even though that argument is removed from the vNext surface.

**Effect:** Destroying the resource under vNext 6.0 can send an obsolete field and fail to remove the remote object cleanly.

**Suggested change:** Guard the legacy delete cleanup with `!features.SixPointOh()` and omit that field from the vNext 6.0 delete request.

**Reference:** [guide-breaking-changes.md (Breaking Schema Changes and Deprecations)](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/contributing/topics/guide-breaking-changes.md)

### `website/docs/r/example_widget.html.markdown:70` (`RIGHT`)

**Question (non-blocking):** Is `Enabled` a Terraform provider default for `mode`, or is it only the value returned by the API when configuration omits the argument?

**Why it matters:** Documenting an API-returned value as a provider default can lead users to rely on behavior Terraform does not actually configure.

**Suggested change if confirmed:** Keep `Defaults to \`Enabled\`.` only if the schema sets that default; otherwise describe the observed behavior without calling it a Terraform default.

**Reference:** [reference-documentation-standards.md (Arguments > Descriptions)](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/contributing/topics/reference-documentation-standards.md)

## REQUEST_CHANGES Summary

```markdown
Please address the blocking inline findings before this change is merged:

- Keep `legacy_mode` handling limited to current provider 5.x (`!features.SixPointOh()`) so the vNext 6.0 (`features.SixPointOh()`) payload path matches its schema.
- Gate delete-time legacy cleanup to current provider 5.x so vNext 6.0 does not send an obsolete field.
```

The pending review will use an empty top-level body and will not be submitted.

Stage this exact pending review now?

---

After the user replies with a new explicit approval, the unchanged plan is revalidated and staged.

## Verified Pending Review

- URL: [https://github.com/example/provider/pull/42#pullrequestreview-1001](https://github.com/example/provider/pull/42#pullrequestreview-1001)
- State: `PENDING`
- Top-level body: empty
- Submitted at: `null`
- Commit: `0123456789abcdef0123456789abcdef01234567`
- Comment count: `3`
- File coverage:
  - `internal/services/example/example_widget_helpers.go`
  - `internal/services/example/example_widget_resource.go`
  - `website/docs/r/example_widget.html.markdown`

Nothing was submitted. Submitting this pending review requires a new explicit user instruction.

## REQUEST_CHANGES Summary

```markdown
Please address the blocking inline findings before this change is merged:

- Keep `legacy_mode` handling limited to current provider 5.x (`!features.SixPointOh()`) so the vNext 6.0 (`features.SixPointOh()`) payload path matches its schema.
- Gate delete-time legacy cleanup to current provider 5.x so vNext 6.0 does not send an obsolete field.
```

Skill used: review-staging
