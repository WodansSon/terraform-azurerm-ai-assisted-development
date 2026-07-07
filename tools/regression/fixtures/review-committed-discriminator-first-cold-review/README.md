# review-committed-discriminator-first-cold-review

Synthetic fixture for the generic committed review workflow.

This fixture models a workflow change where:

- a brand-new discriminator-specific managed resource must start its cold review with ownership-boundary and lifecycle-symmetry checks
- the resource accepts a generic identifier that can resolve to foreign discriminator variants
- the read path can hydrate a foreign variant into state
- the update path later rejects that foreign variant while delete still removes it
- the SDK exposes a dedicated PATCH or update path, but the resource update logic uses a create-style PUT helper instead
- the read path repopulates omitted optional metadata from the API into state
- the changed reference-doc example uses metadata field names whose casing does not match implementation-backed example evidence

The benchmark is satisfied when the review surfaces five separate findings from one cold review pass:

- Issue: the resource can adopt or delete foreign discriminator variants
- Issue: import or read or update or delete behavior is not ownership-symmetric for foreign variants
- Observation: update uses a PUT or create-style path instead of the available PATCH or update path
- Issue: omitted optional metadata is repopulated from the API into state
- Issue: the changed reference-doc example contains an evidence-backed docs example correctness bug under the docs contract

The benchmark fails if the review leads with secondary polish concerns, collapses distinct issue classes into one summary, drops the PUT-versus-PATCH observation because stronger issues already exist, or silently skips the changed docs example bug because larger Go findings are present.

The benchmark also fails if the assistant-emitted committed review body leaks editor-local or absolute-disk file references such as `vscode-file://`, `workbench.html`, `AppData`, or `workspaceStorage` instead of repo-scoped or PR-scoped paths.
