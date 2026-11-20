# Hosted Catalog Inputs and Outputs

This directory separates source-intake configuration from approved staged output and confirmed fork publication.

## Directory Roles

| Path | Role |
| --- | --- |
| `source-definitions/` | Active collection input: the selected source set and each source's root, file patterns, parser, and assessment batch size |
| `initial-rules.json` | Straightforward first-run AzureRM baseline input containing instruction-file settings, managed rule IDs, exact wording, and optional implementation-model applicability |
| `staged/instruction-catalog.json` | Initial Terraform catalog captured from current Hosted instructions and the review skill; later the destination for an approved export, never proof of publication |
| `published/instruction-catalog.json` | Intended record of the catalog successfully published to the fork by the separate future PowerShell publish command |

The [initial JSON baseline](initial-rules.json) supplies the current AzureRM first-run baseline import. Its `instructionFiles` array contains the three configured destinations. Each entry requires `fileName`, `applyTo`, and a non-empty `rules` array of `id` and `text` objects. `description`, `taskDescription`, and `rulesPostText` are optional strings; implementation rules may also declare `implementationModels`. The input requires no schema file, provenance, source mappings, scores, or historical workflow records. Missing optional text remains empty, and imported provenance remains unclassified rather than inferred from legacy catalogs.

The optional text supplies operational review guidance: `description` identifies the review surface, `taskDescription` frames the review task, and `rulesPostText` directs supporting evidence checks across implementation, tests, and documentation. These fields are independent of managed rule wording and do not serve as provenance records.

`Initialize-WorkbenchDatabase.ps1` selects `published/instruction-catalog.json` when present and valid. Only its absence selects `initial-rules.json`; invalid publication blocks creation rather than selecting a fallback. The shared importer preserves rule IDs, exact text, file metadata, model applicability, source bytes and hashes, and JSON-pointer rule locations. It creates the first database baseline without AI, approval, or a claim of fork publication, then verifies readback after reopening. Existing databases and their bindings are not reseeded or replaced. Protected rules retain their separate authored capture.

Manual-guidance staging remains available with `./hosted_copilot/tools/internal/workbench/New-InitialStagedCatalog.ps1`; it is not a prerequisite for JSON baseline initialization. It captures the five profile-owned guidance files, their exact content and SHA-256 hashes, and every identified rule with its source location and protected classification. The bootstrap schema records `approval: not-recorded`; creation does not fabricate approvals, AI results, source relationships, or publication. Existing staged files are never overwritten by this command.

The bootstrap format is distinct from the legacy managed catalogs: it preserves repository-wide instructions and the review skill without inventing numbered rules or historical upstream provenance for that material. The complete file content remains authoritative for this capture; the extracted rule list is an index into those files. A file's presence alone does not establish approval or successful publication. The Workbench's versioned database records remain the workflow authority.

The initial Terraform implementation requires the existing manual instruction files and review skill. Missing, unreadable, or invalid required guidance blocks startup with a file-specific diagnostic. No official published catalog is required before the first review and staged export. Generalized team onboarding and empty-repository setup remain deferred.

## Source Definitions

- `source-definition-set.json` selects the active source definitions.
- `contributor-guidance.json` selects upstream contributor documents.
- `interactive-toolkit.json` selects the configured Interactive Toolkit intake source; it is not deployed Hosted runtime guidance.
- `maintainer-proposals.json` selects the authored proposal files.

Source collection uses temporary capture transport and database-owned evidence rather than a maintained `source-inventories/` directory. Authored protected Markdown remains under `../authored-rules/protected/` and must not be deleted with a generated JSON projection.

## Transitional Legacy Files

| Path | Remaining Dependency |
| --- | --- |
| `instruction-catalog.json` | Schema-v1 legacy assessment, generation, and adoption consumers; not used by native initialization |
| `protected-rules.json` | Generated protected-rule projection still required by legacy assessment and generation consumers |

These are not the new workflow's official published output and must never be copied into `staged/` or `published/` to simulate approval or publication. Remove each artifact only with the replacement or retirement of its remaining consumers and preservation of required behavior. The root `instruction-catalog-v4.json` and its version-4 boundary schema remain preserved; the initial staged catalog is derived from the manual guidance, not copied from either root catalog.

## Implementation Status

Native manual-guidance diagnostics and publication-file checks are implemented. The publication reader checks only `published/instruction-catalog.json` when the database identifies an established publication; neither root legacy files nor staged output can satisfy that check.

Initial JSON baseline import, staged manual-guidance capture, and native ingestion are implemented. Schema revision 7 retains exact baseline input and either line-based manual-guidance locations or JSON-pointer rule locations. JSON bootstrap selects `workspace_staging` without inserting `workspace_publication` or approvals. Analysis and existing Plan commands pin the working catalog: an established publication takes precedence, otherwise the initial baseline is used. Mapping status remains publication-based. Launch requires complete analysis and unchanged required guidance.

Existing databases are not silently upgraded or replaced. First-catalog approval and approved staged export remain separate work described in the design checkpoint. The fork publisher is not implemented. Bootstrap staging and ingestion do not approve or publish a catalog.
