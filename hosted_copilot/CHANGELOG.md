# Hosted Toolkit Changelog

All notable changes to the Hosted Toolkit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/). The Hosted Toolkit is deployed directly from this source repository, so its history remains unversioned unless its distribution model changes.

## [Unreleased]

### Added

- Introduced the source-deployed Hosted review experiment with compact path-specific guidance for documentation, Go implementation, and acceptance tests, plus controlled paired-review workflows for comparing Hosted and control results.
- Added a normalized Hosted rule catalog and read-only intake workflow that evaluates upstream contributor guidance, Interactive rules, and Maintainer Proposals with reusable semantic assessments, guidance-capacity reporting, portable drafts, and auditable promotion contracts.
- Added the Hosted Rule Workbench as a laptop-and-desktop Hosted-rules IDE with searchable candidate and assessment views, persistent decisions, promotion-plan review, guarded capacity projections, source-backed diffs, hash-bound approval export, and repository-read-only loopback serving.
- Expanded the pinned, locally hosted Codicon inventory with folder-state, directory-link, and workspace-trust symbols for current and future Workbench surfaces.

### Changed

- Made the normalized catalog authoritative for generated path-specific guidance, applicability, provenance, and active-rule rendering, with direct source deployment and exact installed-file tracking.
- Made every assessment produce a complete, collision-free Hosted rule proposal independently from Add, Update, Defer, Exclude, or No Change, with smart field-level repair for prior baselines and clear existing-versus-resulting identity throughout Workbench review and export.
- Standardized Hosted validation and test reporting with the Interactive Toolkit execution-state presentation and adopted a guarded four-characters-per-token capacity estimate with 25% safety headroom.
- Added CODEOWNER-only current-results Bulk Actions that accept evaluated Add and Update recommendations as complete decisions with deterministic rationale, actor and source-hash provenance, operation-scoped Undo, and preservation of existing or subsequently reviewed manual decisions.
- Centralized current Workbench browser behavior under schema-backed Playwright journeys, added headed viewport and fixed-window 100%-through-200% browser-zoom playback with owned-server cleanup and aggregate failure reporting, covered bulk-to-manual tree ownership and color transitions, and retained Puppeteer temporarily as a second consumer of the same viewport suite.
- Reworked Promotion Preview into a continuous authenticated GitHub-style file review with independently disclosed Proposed, Payload, and Raw artifact trees, persistent file navigation, sticky split-diff headers, muted file and filled folder icons, CODEOWNERS headers, uniform spacing, independent Viewed and collapse controls, a Review changes approval popover, and one contextual full-file raw payload diff.

### Fixed

- Hardened release boundaries by rejecting linked-path installer escapes, blocking loopback DNS rebinding, constraining review cleanup to tool-owned branch namespaces, scanning deployable files for recognizable credentials and private keys, integrity-locking Node validation dependencies, and auditing the lockfile before installation with explicit staged remediation for high or critical findings.
- Kept required CI deterministic by moving live Hosted upstream-source drift detection to the explicit maintainer audit while continuing to validate the committed source catalog and pinned baseline.
- Made Workbench icon preview generation portable across Windows and Linux by replacing Edge-only process launch with locked headless Puppeteer and exercising both icon families in temporary CI staging.
- Improved Workbench usability across supported viewports with shared model-driven Candidate Sources and Assessment Results trees, fully collapsed initial hierarchies, compact 40px rule rows, complete sticky parent rows, bounded prewarmed renderers for stable child-boundary handoffs, grid-aligned full-speed wheel scrolling, sort-stable scrolling, jump-free folder expansion, generated Hosted identities and proposals throughout Assessment Results, compact icon-only override actions, semantically matched scoring meters and values, stable row and scrollbar alignment, accessible controls, hierarchical readiness cues, non-destructive candidate search, consistent clamped tooltips and tree truncation, unobtrusive VS Code-style scrollbars, reliable Bulk Actions, clearer status feedback, and consistent Candidate, Details, Assessment, Plan, and Preview workflows.
- Made interactive startup report semantic-assessment progress before staging and server readiness, recover from invalid disposable assessment caches through the committed baseline, and preserve machine-readable automation output.
- Corrected experiment and validation reliability for supported GitHub review effort levels, cross-platform pull-request file capture, complete contributor-source drift coverage, and deterministic Mermaid rendering dependencies.
