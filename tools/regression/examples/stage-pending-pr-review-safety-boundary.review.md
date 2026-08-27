## Staging Session Opened

- Invocation: `/stage-pending-pr-review`
- Immutable audit baseline loaded: `3` findings
- Staging candidate ledger: initialized from the frozen baseline
- Informal pre-invocation discussion: not imported as an adjudicated disposition
- Bare invocation: complete preview rendered without another user request
- GitHub mutation: none; explicit approval still required
- Reviewer response: challenged the initial preview with the test-coverage dispute and proposed delete-path concern below

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

The numbered headings and placement fields below are chat-only preview metadata. Only each fenced Markdown body will be added to GitHub.

### Comment 1

**File:** `internal/services/example/example_widget_helpers.go`

**Line:** `88`

**Review Comment:**

```markdown
It looks like the schema limits `legacy_mode` to current provider 5.x (`!features.SixPointOh()`), but this expansion path still reads it for vNext 6.0 (`features.SixPointOh()`). A vNext configuration could therefore reach behavior for an argument that its schema no longer exposes. Could we keep the `legacy_mode` handling behind `!features.SixPointOh()` so the expansion path stays aligned with the schema? This applies across `internal/services/example/example_widget_resource.go` and `internal/services/example/example_widget_helpers.go`.

**Reference:** [guide-breaking-changes.md (Breaking Schema Changes and Deprecations)](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/contributing/topics/guide-breaking-changes.md)
```

### Comment 2

**File:** `internal/services/example/example_widget_resource.go`

**Line:** `144`

**Review Comment:**

````markdown
It looks like this delete path is still sending the current provider 5.x (`!features.SixPointOh()`) legacy cleanup field when vNext 6.0 (`features.SixPointOh()`) is enabled, even though that field is no longer part of the v6 schema. Could we keep this assignment behind the existing-version guard instead?

```suggestion
if !features.SixPointOh() {
	request.LegacyMode = pointer.To(legacyMode)
}
```

**Reference:** [guide-breaking-changes.md (Breaking Schema Changes and Deprecations)](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/contributing/topics/guide-breaking-changes.md)
````

### Comment 3

**File:** `website/docs/r/example_widget.html.markdown`

**Line:** `70`

**Review Comment:**

```markdown
Am I reading this correctly that `Enabled` is configured as the Terraform schema default for `mode`, rather than only being returned by the API when the argument is omitted? If this is API behavior instead, could we avoid describing it as a Terraform default so users do not assume Terraform explicitly configures it?

**Reference:** [reference-documentation-standards.md (Arguments > Descriptions)](https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/contributing/topics/reference-documentation-standards.md)
```

## Request Changes Summary

```markdown
Thanks for pushing those updates. I gave this another look and found two remaining blocking concerns:

- Could we keep `legacy_mode` handling limited to current provider 5.x (`!features.SixPointOh()`) so the vNext 6.0 (`features.SixPointOh()`) payload path matches its schema?
- Could we gate delete-time legacy cleanup to current provider 5.x so vNext 6.0 does not send an obsolete field?

I also left a non-blocking documentation question for clarification.
```

The pending review will use an empty top-level body and will not be submitted.

**Stage this exact pending review on `example/provider#42`: "Add Example Widget support"?**

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

Nothing was submitted. Inspect or edit the pending comments, then submit the review manually in GitHub when satisfied.

## Request Changes Summary

```markdown
Thanks for pushing those updates. I gave this another look and found two remaining blocking concerns:

- Could we keep `legacy_mode` handling limited to current provider 5.x (`!features.SixPointOh()`) so the vNext 6.0 (`features.SixPointOh()`) payload path matches its schema?
- Could we gate delete-time legacy cleanup to current provider 5.x so vNext 6.0 does not send an obsolete field?

I also left a non-blocking documentation question for clarification.
```

Skill used: review-staging
