# Workbench Database Snapshot Sharing: Deferred V2 Design

## Status and Authority

Design recorded on 2026-11-02. Snapshot sharing is deferred to v2 and is not implemented. This document records the intended behavior, implementation constraints, and acceptance criteria; it does not authorize implementation, migration, deletion of the preserved Workbench, or deployment.

The v1 SQL design includes a small persistent database/workspace identity record. That prerequisite is a schema requirement, not evidence that a database or identity table has already been created. V1 does not include snapshot sharing, JSON draft transfer, cross-database record merging, or a GUID-based import/export protocol.

This document owns the deferred snapshot-sharing design. The [SQLite-v1 design](WORKBENCH_SQLITE_V1_DESIGN.md) owns the proposed current database definitions and open v1 decisions; the identity fields below describe the prerequisite, not a separate competing schema. The [architectural reset checkpoint](WORKBENCH_ARCHITECTURAL_RESET_CHECKPOINT.md) owns the implementation pause and historical validation limitations. The [Hosted architecture](../../docs/HOSTED_COPILOT_CODE_REVIEW_ARCHITECTURE.md) continues to define product isolation and manifest-owned deployment. This feature does not introduce a Hosted release bundle or a new distribution system.

Requirements marked as decisions below reflect the agreed product direction. Candidate table names, command names, and technical approaches describe a design to implement later, not existing APIs. Open questions must be resolved explicitly rather than filled with compatibility fallbacks.

## Product Decision

Share a complete, consistent SQLite workspace snapshot when another maintainer needs to inspect the same rules, evidence, assessments, groups, decisions, Plan, and history.

Open the received snapshot as a separate, initially read-only local workspace. Leave the recipient's current database untouched. A later explicit replacement capability may replace the whole database after creating and verifying a recoverable backup; it must not merge individual records.

The snapshot retains the relationships that already exist inside one database. It is not a request to match records between independently created databases, remap their primary keys, or reinterpret assessment results.

The destination is another local Workbench instance, not a database hosted by a remote Git branch. Generated instruction files can be deployed to a fork separately through the normal, explicitly authorized deployment boundary.

## Independent Workspace Evolution

Repositories adopting this tooling define their own guidance sources, source adapters, locally authored proposals, and policy profiles. Do not assume a fixed set of source lanes or require a particular upstream project, documentation provider, or repository-local rule format. The examples below describe differences in captured data, not special treatment for named sources.

Two maintainers can start with equivalent data and then evolve their workspaces independently. One may collect additional external guidance, revise repository-local instructions, or accept locally authored proposals that the other's snapshot does not contain. The same divergence can occur between separate clones, branches, independent databases, or copies retaining the same database GUID.

A snapshot is a captured workspace, not a synchronization request or proof that its source state is newer than the recipient's. Structural compatibility and valid foreign keys do not establish equal source coverage, equivalent decisions, or current assessments for another workspace.

| Difference | Required Interpretation |
| --- | --- |
| Recipient collected a guidance source absent from the snapshot | The snapshot has a different captured source set; leave recipient records untouched and do not silently add them to inspection |
| Recipient revised locally maintained guidance | Inspect the snapshot's captured content as historical evidence, not the recipient's current file contents |
| Recipient created or accepted proposals absent from the snapshot | Preserve that work in the recipient's database; opening the snapshot neither removes nor imports decisions |
| Matching source identity has different captured content | Preserve each workspace's exact source versions and assessment bindings; identity alone does not establish reusable meaning |
| Source definitions, adapters, or policy profiles differ | Do not assume like-for-like comparison or interpret an uncollected source as deleted |
| A local checkout or external source changed after capture | Snapshot inspection makes no claim that live source state was refreshed or evaluated |

Read-only inspection must use the received snapshot's own captured evidence and relationships. Do not join the recipient's newer source inventory, local proposals, current catalog, or assessment results into the donor's groups to fill perceived gaps. Local authentication and the inspection capability remain recipient-owned, but they do not change the snapshot's domain evidence.

Different source sets or recorded decisions are not, by themselves, corruption or schema incompatibility. Explain which workspace and capture the displayed facts describe. If a source comparison is later implemented, compare explicit source definitions and captured versions without merging records; unavailable or incomparable evidence must remain unknown rather than be reported as removal or equivalence.

Opening or closing inspection must preserve both independent histories. Optional whole-database replacement deliberately selects the donor's complete captured state; it does not retain recipient-only guidance or decisions inside that replacement. State that consequence explicitly before confirmation, retain the verified recipient backup, and make restoration discoverable. Do not imply that receiving a snapshot combines the best or latest state from both workspaces.

Any later collection or reassessment in an explicitly authorized writable workspace follows the normal source-drift lifecycle: complete collection, versioned evidence, compatible evaluation reuse, reviewable changed meaning, and separate maintainer acceptance. Database identity, matching branch names, or a previously accepted donor decision cannot substitute for those checks. This is not permission to add source synchronization to the read-only milestone.

## Why the Old Feature Is Not the Implementation Template

The preserved Workbench's Draft options menu offers Export Draft and Import Draft. That feature transfers JSON decisions between a generated display and a browser-owned draft. Its data includes saved actions, wording, applicability overrides, Plan membership, addition provenance, bulk operations, and original proposal baselines. It depends on matching current source evidence and candidate identities.

The approval JSON also carries complete rule objects and metadata such as selection factors, scoring rationale, canonical candidate references, and source relationships. Its apply consumer uses that material to rebuild the JSON catalog. Those fields served as transport and persistence while the workflow relied on multiple JSON representations.

Under the SQL design, normalized records and immutable versions already preserve those facts. The server builds read models, prompt context, previews, and approved changes by querying them. Rebuilding the same JSON transfer contract would reintroduce synchronization work without providing the intended whole-workspace inspection experience.

Preserve these useful semantics, not the old transport:

- Keep AI recommendations distinct from maintainer decisions, even when the UI displays one effective action pill.
- Preserve source identities, independently assessed meanings, semantic group versions, member coverage, and original suggested wording.
- Keep saved wording, Plan membership, and published catalog lifecycle independent.
- Preserve exact input bindings and historical assessment and relationship results.
- Keep protected rules immutable and maintainers in control of approval and deployment.
- Keep audit attribution, manual/bulk addition provenance, and original proposal baselines.

During SQL-v1 implementation, remove feature-only JSON draft controls, event bindings, parsers, serializers, schemas, tests, and claims after confirming their ownership. Retain anything also required for normal persistence, source intake, backup/recovery, API validation, or deployment. Do not retain empty endpoints, disabled import/export buttons, or TODO-only runtime stubs for v2. This document is the continuation record; preservation does not depend on retaining intermediate Git history after a squash merge.

The current browser-only hiding of the Draft options menu does not constitute that source removal. Reloading the preserved application can restore the menu until its source and consumers are deliberately replaced.

## Scope Boundaries

### V1 Includes

- Local SQLite authoritative workspace state and normal recovery/backup requirements.
- Persistent database/workspace identity with separately recorded repository/branch context.
- Server-owned Save, Preview, review, approval, and apply commands with short database transactions.
- Immutable evidence and decision history, exact review applicability, and ordinary operational audit.
- Generation and explicit deployment of manifest-owned instruction files.

### V2 Adds

- Deliberate creation of a consistent whole-workspace sharing snapshot.
- Compatibility and integrity inspection before opening a received snapshot.
- A separate read-only inspection workspace without changing the recipient's active database.
- A local maintainer database-inspection website with table/data browsing and relationship visualization, under the read-only boundary below.
- Explicit restore or replacement only if its recovery requirements are implemented and accepted.

### V2 Backlog: Maintainer Database Inspector

Recorded on 2026-11-06. Provide an SSMS-style **inspection** experience inside the local Hosted maintainer tooling so maintainers can verify stored facts themselves rather than rely on assistant summaries or an external database extension. This is a deferred feature, not a V1 prerequisite or authorization to implement a new website now. A focused read-only inspector is feasible; a general-purpose SSMS replacement, database administration platform, or writable schema/data designer is not this backlog item.

- Show the selected database path, GUID, schema version, recorded repository/branch, capture context, and read-only mode. Clearly distinguish a current workspace view from a received snapshot or historical capture; do not silently switch or merge them.
- Provide a table/view explorer and bounded data grid with pagination, filtering, sorting, null/type display, and record details. Inspect actual SQLite tables and stored rows, not generated explanatory examples or a second editable JSON representation.
- Show schema definitions, columns, PK/FK constraints, indexes, and trigger definitions as inert text. Support FK navigation in both directions and ER diagrams derived from recorded database constraints; identify any inferred relationships separately rather than presenting them as enforced FKs.
- Let maintainers trace sources through evaluations, assessments, groups, decisions, findings, and audit history. Preserve original evaluator/input identity and make incomplete, failed, stale, and complete states distinguishable without promoting an unfinished run to current.
- Reuse the shared SQLite connection/inspection owner and an explicitly bound, authenticated loopback server boundary. The browser does not open filesystem paths, execute SQL itself, or choose arbitrary files; an inspection request must stay bound to the selected database and authorized local session.
- Keep queries read-only at the database/API boundary with existing authorizer, attachment/extension restrictions, and bounded time/row/response limits. Prefer typed browsing operations. Any later SQL console needs a reviewed read-only execution design, not a check that a string begins with `SELECT`.
- Do not add edits, DDL, Save, repair, migration, source refresh, AI evaluation, approval/publication, or deployment to inspection. Render stored text as untrusted data and never execute scripts, paths, or policy instructions found in it. Sensitive data remains subject to the existing non-disclosure rules; inspection is not permission to persist credentials or expose them through a new UI.
- Prove useful browsing and FK/ER navigation on the real normalized schema, read-only refusal through direct API calls, bounded cancellation/resource handling, database/WAL preservation, and preservation of the active Workbench session before acceptance. Use a consistent snapshot or the tested live read-only mechanism; do not inspect an unverified main-file copy from a WAL database.

This document owns the inspector backlog together with snapshot inspection. V1 continues to implement persistence and the existing Workbench experience; it does not gain a database-browser stub, dependency, or UI redesign for this future feature.

### Out of Scope

- Row-level merging between independent databases or teams.
- Primary-key remapping, duplicate resolution, source-identity matching, or reconciliation of two decision histories.
- Cloud databases, shared multi-tenant services, synchronization, remote database execution, or background uploads.
- A configurable transfer workflow engine, distributed locks, signed evidence infrastructure, or mandatory archive packaging.
- Automatic assessment, AI calls, source collection, approval, instruction regeneration, Git operations, or deployment merely because a snapshot is opened.
- Restoring the JSON draft or portable approval envelope as an alternate workspace authority.

## V1 Identity Requirement

### Separate Identity From Location

A database identity is not a Git branch identity. Git branch names are mutable locators, and branch names are not globally unique across repositories or forks. A commit identifies source content at a point in history; it is not the permanent identity of a workspace either.

Use the existing repository/workspace records if the final v1 model already owns these concepts. Otherwise, a small `workspace_identity` singleton is a candidate home for the persistent identifier. Do not create a second repository registry or introduce a generic identity subsystem solely for this feature.

| Logical Field | Requirement |
| --- | --- |
| `id` | Internal integer primary key; the workspace database has one identity record |
| `database_guid` | Non-null unique GUID created when the logical database is first initialized |
| `created_at` | Server-generated UTC creation time |
| `origin_repository_id` | Reference to the repository recorded at initialization, if repository records already exist |
| `origin_branch_ref` | Original branch context when available, not a primary key or permanent branch identity |
| `created_by_actor_id` | Reference to the creating actor when known; no credential storage |

Use the normal database schema-version mechanism as the compatibility authority. Do not create an independently maintained schema version in the identity row. If the application owns an SQLite application identifier, use it consistently rather than treating an arbitrary SQLite file as a Workbench database.

The GUID identifies the logical workspace and its backup lineage. It is useful in v1 audit, backup descriptions, and diagnostics even while sharing is absent. It is not authentication, permission, proof of integrity, or a declaration that all records match another file with the same GUID.

### Repository and Branch Context

Record origin separately from current operating context:

- Preserve the original repository and branch information as historical provenance.
- Record the current local repository association through the ordinary workspace/repository configuration owner.
- Keep the selected deployment fork, branch, checkout path, and authenticated actor in recipient-owned operating context.
- Record branch changes or workspace reassociation explicitly when the workflow supports them. Do not silently change a published catalog, accepted evidence, or target merely because the Git checkout changed branches.
- Do not infer identity or permissions from a remote URL, branch name, database filename, local folder name, or displayed rule ID.

This does not require multiple branch-scoped databases, one database shared across branches, or an active-workspace switcher in v1. The final v1 workspace lifecycle must choose that relationship explicitly. Whichever relationship is chosen, database GUID and branch locator must remain distinct.

### Identity Lifecycle

| Event | Database GUID | Required Treatment |
| --- | --- | --- |
| Initialize an independent database | New GUID | Record origin and creation attribution |
| Restart, Save, or reassess | Unchanged | Continue the same logical workspace |
| Rename or switch a branch while continuing the same workspace | Unchanged | Update operating context through its owner; preserve origin/history |
| Back up or produce a sharing snapshot | Preserved | The file represents that database lineage |
| Restore an earlier backup | Preserved | Its contents can be older despite matching identity |
| Open a snapshot read-only | Preserved | Do not rewrite the received file to manufacture a local identity |
| Create a deliberately independent writable workspace from a copy | New GUID | Only through an explicit future operation that records its origin |

A received snapshot can legitimately have a GUID different from the recipient's active database: separate inspection is not import into that database. Conversely, equal GUIDs cannot prove interchangeable content because backups and later copies can diverge.

No v1 database is created or modified by documenting this requirement. Do not add a one-off migration to the frozen JSON application just to generate a GUID.

## Ownership and Trust

| Concern | Owner |
| --- | --- |
| Recorded domain facts, versions, memberships, and history | Workspace database |
| Consistent backup, compatibility checks, read-only enforcement, and restore coordination | Server/database layer |
| Authenticated identity, current scoped permissions, target checkout, and deployment credentials | Recipient's local runtime and explicit configuration |
| File choice, inspection navigation, progress, confirmation, and display | UI |
| Published protected content and deployable file set | Repository-owned protected sources and Hosted manifest |

The browser never executes SQL or decides that a received file is safe to mutate. Every mutation entry point must enforce inspection mode server-side, even if an old browser tab still has enabled controls.

Do not treat arbitrary database contents as application instructions. Store source, catalog, assessment, recommendation, and conversation material as data. Opening a database must not execute a stored script, dynamically load an extension, run a trigger through a write operation, or choose executable code from a stored path. Apply the SQLite driver's supported defensive controls and schema allowlisting for files received from another machine; the exact driver APIs remain an implementation choice.

Do not serialize credentials, authentication tokens, authorization headers, private keys, provider session state, shutdown/operation capabilities, or equivalent secrets into the workspace database or sharing artifact. Keep machine-scoped credentials outside the database from v1 onward. Received permission snapshots and old authenticated actors are historical evidence, not the recipient's current authorization.

## Snapshot Contents

The default design is one consistent database snapshot, not one JSON document per table and not a generated intake/display bundle.

Preserve the complete persisted domain graph:

- Database identity, schema compatibility information, and source/policy profile configuration.
- Source definitions, collection snapshots, source versions, and evidence provenance.
- Assessments, factor values, confidence, rationale, and exact evaluator/input references.
- Semantic groups, versioned memberships, member coverage, and group correspondence evidence.
- Original generated wording, saved edits, decisions, and original baselines.
- Published catalog snapshots, protected references, Plan memberships, and manual/bulk addition provenance.
- Relationship-check inputs, findings, issues, recorded resolutions, and approval/apply history.
- Operational audit events with their original attribution.

Do not silently regenerate, rescore, renumber, normalize away, or reinterpret historical records during export or inspection. A stored result remains evidence for its recorded context, not a fresh result for the recipient's environment.

A whole database backup includes all durable tables; it cannot safely promise to exclude a transcript or other record that v1 deliberately persists. Before sharing, disclose the included data categories. If conversations remain browser-only, they are not in the snapshot; do not imply that they were captured. A sanitized partial export is a separate, unapproved design and must not be implemented by deleting arbitrary related rows from the sharing copy.

Keep the v2 sharing contract independent of donor-local files. The final SQL model must explicitly identify which domain evidence is stored in the database and which dependencies remain external. If required captured evidence is missing, block creation of a snapshot advertised as self-contained, or clearly classify it as a limited backup rather than silently fetching from the donor's paths. Application code, prompt templates, renderer assets, and credentials are not made executable or transferable merely by recording their versions.

Prefer the single SQLite snapshot. Add a small non-secret descriptive sidecar only if a concrete UX or compatibility requirement cannot be satisfied by inspecting the database. Do not design a versioned Hosted release archive or a mandatory multi-file package.

## Source Snapshot Creation

### Capture Boundary

1. Require an explicit sharing command; normal Save and approval do not create an external artifact.
2. Resolve the current database through the server, not a caller-supplied arbitrary file path.
3. Check current local permissions and the database's schema/application identity.
4. Choose a destination that cannot overwrite the active database, its WAL/SHM companions, or the only recovery copy.
5. Capture a consistent database state using the SQLite backup API or another explicitly supported, tested snapshot mechanism in the chosen driver.
6. Validate the produced snapshot before announcing completion.
7. Record the successful local sharing event without altering historical decisions in the snapshot.

Use SQLite's supported snapshot facilities to coordinate committed data. Do not hold an application transaction open while waiting for user interaction or inference. Do not claim that every successful backup includes commits made after its consistent capture point.

### WAL and Open Writers

Do not copy an active main database file and assume it contains all committed writes. WAL-mode commits can reside in a separate file. Copying the main database and WAL/SHM files independently also does not establish a consistent capture.

Use one of these deliberately selected approaches:

- Use the driver's SQLite backup API with its documented concurrency behavior and bounded cancellation/busy handling.
- Use another supported snapshot operation only after proving consistent committed content and reliable cleanup under concurrent writes.
- For an offline recovery backup, stop writers, close every connection, and follow the database layer's tested clean-close procedure before copying.

Do not make an unverified WAL checkpoint-and-file-copy sequence the fallback when the proper backup operation fails. A failed or cancelled capture leaves the source usable, does not overwrite a prior valid backup, and does not report a partial destination as shareable.

### Output Validation

Inspect the completed artifact using the chosen supported read-only mode:

- Confirm the Workbench application identity, supported schema, and expected database GUID.
- Run appropriate SQLite integrity and foreign-key checks; verify that foreign-key enforcement is enabled for normal writable connections.
- Validate required tables, constraints, and the domain references required to present the workspace.
- Confirm that required protected references and immutable-version bindings are present.
- Confirm that the snapshot does not need donor WAL/SHM files or machine-specific files to read its recorded domain evidence.
- Compute any comparison checksum over the completed immutable artifact, not an actively changing source file.

A checksum identifies captured bytes; it does not authenticate the donor or establish the semantic correctness of assessments.

## Recipient Inspection

### Opening Sequence

1. Receive a snapshot outside the active database's protected location.
2. Validate its type, size/resource limits, application identity, schema compatibility, and integrity before presenting it as usable.
3. Open it separately in read-only inspection mode through the server/database layer.
4. Bind the view and its requests to that inspection workspace, not the recipient's current writable workspace.
5. Show the donor workspace identity, recorded repository/branch origin, capture information when available, and inspection mode.
6. Leave the recipient's database, selected deployment target, browser draft, and active jobs untouched.

The safe SQLite URI flags and connection settings depend on the driver. Do not set `immutable` on a file that other processes can still change, or use it to hide a dependency on an uncaptured WAL. Resolve the supported approach during implementation and test it on Windows.

### Inspection Behavior

Inspection should support reading the captured catalog, source meanings, groups, assessments, findings, Plan, history, and previews from the same captured context. It does not imply that the recipient currently has the donor's source revision, policy, prompt implementation, or live authorization.

Server-side inspection mode rejects:

- Save, Reset, staging, Undo, resolution, approval, catalog apply, and other database mutations.
- Force/rebuild, collection, reassessment, relationship checks, and AI requests that would create new workspace results.
- Deploy, commit, push, source regeneration, or target modification.
- Background source refresh, automatic CODEOWNERS refresh writes, automatic schema migration, and silent cache repair in the received database.

The UI may disable or omit unavailable commands, but direct API requests must remain blocked. Pure local display operations such as filtering, navigation, text selection, and copying do not become database mutations.

Preserve existing unsaved editor buffers and conversations before changing the displayed workspace. Do not hide unsaved work by replacing a global browser context or reload a chat-bearing page without an explicit user decision. Read-only inspection does not require copying browser state into the received database.

### Returning to Local Work

Closing inspection returns to the original local workspace without a restore operation. Its selected records, saved decisions, Plan membership, and history must be unchanged. Background operations must remain associated with the workspace that started them; a late response from one workspace must never attach to another.

## Compatibility and Origin

| Condition | Required Behavior |
| --- | --- |
| Different database GUID | Allow separate inspection when compatible; do not merge into the current database |
| Matching GUID with different contents | Treat as another captured state, not proof of freshness or equality |
| Matching schema/application and complete evidence | Continue read-only validation and inspection |
| Unsupported newer schema | Refuse with an actionable compatibility message; do not guess fields |
| Older schema requiring migration | Do not mutate the received artifact; use a separate explicit compatibility design or refuse |
| Unknown application or unexpected schema objects | Refuse rather than opening as a normal Workbench workspace |
| Missing required evidence or broken foreign keys | Refuse complete inspection; do not reconstruct silently with AI |
| Different repository, branch, or team profile | Identify the difference; never silently rebind to the recipient's deployment target |
| Different captured guidance sources or local decisions | Allow compatible separate inspection; do not merge, drop recipient work, or claim source freshness |

Repository/branch context is provenance, not an import permission. Avoid arbitrary checks requiring identical donor and recipient GUIDs: that would reject the intended inspection of another maintainer's database while still failing to distinguish divergent copies of one database.

Store and display original actor identities accurately. Never rewrite donor audit records to name the recipient as the author. Resolve the recipient's identity and effective permissions independently for any later approved local action.

## Optional Whole-Database Replacement and Restore

Replacement is not required merely to inspect a snapshot. Implement it only after the read-only workflow and recovery criteria pass and maintainers explicitly approve that capability.

### Preconditions

- Obtain explicit confirmation identifying the current workspace being replaced and the candidate snapshot.
- Validate the candidate completely before changing the active database.
- Require a completed, verified backup of the current database and a clear restoration location.
- Handle unsaved UI buffers and running jobs explicitly; do not discard them as an incidental effect of replacement.
- Quiesce owned workers and writes, then close all database connections before switching files.
- Reject a replacement that would overwrite its own only backup or operate on unsupported links/paths.

### Replacement Boundary

Use the normal local database layer and a tested filesystem replacement procedure. Preserve the candidate database's internal IDs and history as one graph; do not import rows into the recipient's existing tables. Never rewrite foreign keys solely to match the old recipient database.

Treat the database, its WAL/SHM lifecycle, and the active workspace pointer as one coordinated application operation. A SQLite transaction cannot atomically replace operating-system files or update a Git branch. Do not leave an old WAL beside a different main database or delete unrelated files by a filename prefix.

Stage and validate the candidate outside the active path. At the final handoff, recheck operation ownership and closed connections, replace through the supported filesystem mechanism, open the selected database, validate it, and only then report success. Record a recipient-local operation outcome without rewriting the donor's historical audit events.

No replacement command may imply approval or deployment. Clear transient job handles and operation capabilities. Previously stored review results, approvals, and permission snapshots remain historical records until the normal local rules establish their applicability to a new operation.

### Recovery

Retain the verified pre-replacement backup until the user deliberately removes it. Report the exact backup location without exposing sensitive paths to unrelated AI prompts or shared artifacts.

If the handoff fails, do not claim a new active workspace or continue operating against an uncertain database. Return to the verified original when the replacement procedure can do so safely; otherwise stop with a precise recovery instruction and preserve both files. Do not add a general transaction journal or distributed recovery system without a demonstrated local requirement.

Restoration follows the same close/validate/replace/reopen discipline. Restoring a backup is whole-database recovery, not import, and is not guaranteed to include work created after that backup. Present that consequence before confirmation.

## Audit and Local State

Use ordinary operational audit: actor, server UTC time, action, workspace identity, relevant capture/content reference, outcome, and a safe failure code. Do not add cryptographic signing, hash-chain audit infrastructure, or tamper-proof claims for this local feature.

Record source-side snapshot creation only after a validated artifact exists. The snapshot represents its capture point and need not contain the later source-side success event. Record failed/cancelled attempts according to normal local audit policy without recording credentials or raw sensitive diagnostics.

A read-only received database cannot record local inspection events without violating its contract. Keep such events, if required, in the recipient's existing operational/audit owner, not in a second writable mirror of the donor's domain data. Do not add a new audit storage system solely for inspection.

Keep local authentication and deployment settings separate from donor domain records. A copied CODEOWNERS snapshot is not a permission grant, and a copied target branch is not an instruction to deploy there. If a replacement is later opened for writable local work, explicitly establish local runtime bindings and rerun required current authorization checks.

## Server and UI Contract

Use a small server command surface rather than browser database access. Candidate operations are Create Snapshot, Inspect Snapshot, Close Inspection, and, only if approved later, Replace Workspace and Restore Backup. These are responsibilities, not committed route or function names.

Every request must identify the intended workspace and operation. Use current authorization, validated file locations, bounded work, and existing safe error handling. A request identifier coordinates progress/cancellation; it does not authorize work on another database.

Do not expose an Import Draft or Export Draft affordance before the database workflow exists. When v2 is implemented, use controls whose names explain whole-workspace capture or inspection rather than suggesting individual rule merging. Preserve existing layout, accessibility, normal animation behavior, and unrelated commands.

Return explicit outcomes such as capture complete, inspection ready, incompatible schema, integrity failure, busy/cancelled, backup failed, or replacement recovery required. Do not render raw SQL, SQLite diagnostics containing sensitive paths, CLI transcripts, or exception messages as user instructions. Provide a safe diagnostic reference when the normal runtime supports one.

## Failure Matrix

| Failure | Expected Outcome |
| --- | --- |
| Destination full or unwritable | Source remains usable; no successful snapshot or partial-file handoff |
| Busy source beyond the supported deadline | Bounded failure/cancellation, no unbounded retry loop |
| Capture cancelled | Partial destination cleaned or explicitly unusable; prior valid backups retained |
| Corrupt/truncated candidate | Rejected before inspection or replacement |
| Missing donor dependency | No silent source fetch, AI regeneration, or misleading complete snapshot |
| Same GUID but older/divergent data | Presented as a separate capture, never automatically merged or approved |
| Donor permissions exceed recipient permissions | No inherited capability or target access |
| Stale browser issues a write during inspection | Server rejects it; received database remains unchanged |
| Workspace changed while an operation completes | Result stays bound to its originating workspace; no cross-attachment |
| Pre-replacement backup fails | Replacement does not begin |
| Open database handle blocks replacement on Windows | Safe refusal/recovery; no destructive retry variations |
| Replacement or reopen fails | Preserve recovery files and report verified active state accurately |

## Implementation Sequence

### V1 Preparation

1. Finalize the minimal database identity record and repository/workspace ownership in the v1 relational design.
2. Initialize the GUID once, enforce its uniqueness/singleton requirement, and preserve it across normal backup/restore.
3. Keep credentials, capabilities, and machine-local runtime state out of durable domain data.
4. Ensure required evidence has a declared persistent owner and normal database backup/recovery works.
5. Remove only the obsolete JSON transfer feature and its exclusive consumers during the approved SQL cutover; keep real input/API/AI/publication validation.
6. Leave snapshot-sharing controls, routes, and placeholders absent from v1.

### V2 Read-Only Milestone

1. Choose a supported SQLite snapshot mechanism and document its capture/concurrency behavior.
2. Build the candidate snapshot validator using the application's schema and driver controls.
3. Produce a complete snapshot from representative domain data without AI regeneration.
4. Implement separate server-enforced read-only workspace inspection and safe return to the original workspace.
5. Add truthful provenance/mode display, progress/cancellation, safe failures, and explicit local audit integration.
6. Validate on Windows, including WAL mode, concurrent writers, and stale browser requests.

### Optional Replacement Milestone

1. Obtain explicit scope approval; do not make replacement a prerequisite for inspection.
2. Implement and verify pre-replacement backup, worker quiescence, connection closure, file handoff, reopen, and restore.
3. Prove failure behavior before exposing the destructive confirmation UI.
4. Re-establish local runtime/permission bindings before allowing writable work.

## Acceptance Criteria

These are future tests, not checks executed by writing this document. Use complete synthetic records matching the final relational schema. Do not simplify the happy path to bypass required evidence, protected rules, or approval inputs.

| Area | Required Evidence |
| --- | --- |
| Identity | Independent initialization produces a new GUID; restart/Save/backup/restore preserve the existing one |
| Branch context | Branch rename/reassociation cannot silently rename database identity or alter accepted catalog/target |
| Copy lineage | Equal GUIDs with different contents remain distinguishable; different GUIDs permit separate compatible inspection |
| Snapshot fidelity | Source versions, assessed meanings, group membership/coverage, original and saved wording, decisions, and audit attribution survive exactly |
| Independent source sets | Recipient-only external guidance and repository-local rules remain untouched; inspection uses the donor's captured source set without a union or background fetch |
| Independent decisions | Recipient-only proposed or accepted rules survive inspection/return; replacement warns they are absent from the selected snapshot and retains a recoverable backup |
| Source comparability | Changed content and adapter/profile differences cannot be mistaken for identical evidence, source deletion, or reusable assessment merely because identifiers match |
| Version history | Accepted evidence stays pinned; latest discovery, pending drift, and forced-evaluation history are not rewritten |
| Empty successful results | Completed assessments/checks with no meanings/findings remain distinct from failed or unprocessed inputs |
| Plan semantics | Manual/bulk provenance, membership, saved actions, original recommendations, and Undo behavior remain distinct |
| Review freshness | Old assessments/checks are not relabeled current for changed wording, policy, or recipient context |
| Conflict history | A resolved A/B finding and a later A/C finding retain their exact participant versions and outcomes |
| Protected content | No inspection or replacement operation modifies or manufactures approval for protected authored rules |
| WAL/concurrency | Snapshot contains a consistent committed state under active writes without independently copying WAL/SHM files |
| Capture failure | Cancellation, busy timeout, disk failure, and interrupted output cannot destroy source or previous valid backup |
| Inspection isolation | Source snapshot bytes and recipient database/domain state remain unchanged throughout inspection |
| Server enforcement | Direct writes, AI jobs, collection, approval, and deployment are rejected in inspection mode |
| Compatibility | Unsupported versions, unexpected schema, broken references, and incomplete dependencies fail explicitly |
| Runtime separation | Donor identities, permission snapshots, executable paths, and targets cannot grant local authority |
| Replacement safety | Backup failure prevents replacement; closed-handle handoff and recovery work on Windows |
| Conversation/UI preservation | Inspection switching does not discard unsaved buffers/chats or attach late answers to another context |
| Privacy | Synthetic-only fixtures; no secrets or authentication material in snapshot, diagnostics, test output, or chat |
| Product boundary | Snapshot workflow does not invoke Interactive tooling or create a versioned Hosted release package |

Use the owning database/backup tests first. Run focused server/UI coverage when its surfaces change. Browser automation must use `reducedMotion: 'no-preference'`, verify the reduce query is false, and retain animation behavior. Never suppress motion to stabilize tests.

Measure capture/validation/opening latency and failure behavior with representative data when implementation is authorized. Do not claim performance gains or production reliability from schema design, a checksum, or one successful capture. Full Hosted validation remains a final, separately approved gate rather than a development loop.

## Decisions Still Required Before V2 Implementation

- Choose the final v1 identity table name and whether its repository association is represented in an existing workspace table.
- Define the workspace-to-local-checkout relationship and behavior on branch changes; no implicit per-branch clone or directory creation.
- Choose the SQLite library, supported backup API, read-only/defensive connection settings, and schema compatibility policy.
- Inventory required external evidence dependencies and determine whether any must move into the database for self-contained inspection.
- Confirm whether conversations are durable at all and disclose their inclusion if they are; do not add transcript storage merely for sharing.
- Define snapshot destination, naming, retention, and resource limits using normal local configuration, not hardcoded donor paths.
- Decide whether replacement is needed after separate inspection is usable, and select the Windows-tested file/connection handoff procedure.
- Decide whether any explicit independent writable-copy operation is wanted; until then, remain read-only rather than silently changing the database GUID.

Until those decisions and future acceptance criteria are met, keep v1 limited to its local persistence, domain workflow, backup/recovery, approval, and generated-file deployment responsibilities.
