# CLI Plugin Adapter Plan

This document defines the side-by-side design for adding an Agency Playground plugin and CLI-friendly adapter to this repository without forking the existing VS Code and GitHub Copilot workflow model.

## Goals

- Keep the existing VS Code and installer workflow intact.
- Add a plugin and CLI-friendly frontend that can be developed in the same repository.
- Preserve a single shared source of truth for contracts, workflow guidance, and domain rules.
- Convert the current prompt-driven review workflows into agents that are portable outside VS Code.
- Keep repo-only maintainer tooling separate from runtime plugin payloads.

## Non-Goals

- Replacing the current installer-based VS Code workflow.
- Duplicating rule content into a second independent plugin knowledge base.
- Shipping repo-maintainer workflows such as changelog maintenance as part of the runtime plugin by default.
- Making the plugin the new source of truth for provider standards.

## Design Principles

1. Contracts remain authoritative.
The hard rules continue to live under `.github/instructions/`.

2. Skills remain shared workflow guidance.
The core domain workflows continue to live under `.github/skills/`.

3. Frontends are adapters.
VS Code prompts and the Playground plugin are two different delivery surfaces over the same core guidance.

4. Review workflows should become agents.
The existing prompt-driven review procedures are the least portable part of the current design. They should be re-expressed as plugin agents with explicit inputs.

5. Repo-only maintenance stays repo-only.
Maintainer workflows such as toolkit alignment and changelog maintenance should remain in this repository and should not be pulled into the runtime plugin unless there is an explicit maintainer mode requirement.

## Shared Source Of Truth

These areas stay authoritative and shared by both frontends:

- `.github/instructions/`
- `.github/skills/`
- `tools/regression/`
- `tools/validate-ai-toolkit.ps1`

These files define the provider-specific rules, workflow expectations, and regression baselines. Changes here should flow into both the VS Code and plugin frontends.

## Frontend Split

### VS Code Frontend

The current VS Code and Copilot-specific surface remains in place:

- `.github/copilot-instructions.md`
- `.github/prompts/`
- `installer/`
- `.vscode/`

This remains the installer-driven workflow for GitHub Copilot and slash-command usage in target repositories.

### Playground Plugin Frontend

Add a new plugin-focused adapter in this repository that mirrors the packaging shape expected by the Agency Playground while still depending on the shared core guidance.

Recommended location:

```text
plugins/terraform-azurerm-ai-toolkit/
```

That directory should eventually contain the plugin-specific metadata, agents, export scaffolding, and any thin wrappers needed for Playground packaging.

## Proposed Repository Layout

The intended side-by-side structure is:

```text
.github/
├── instructions/                  # Shared contracts and guidance (authoritative)
├── prompts/                       # VS Code / Copilot prompt adapters
├── skills/                        # Shared domain workflows (authoritative)
└── copilot-instructions.md        # VS Code root instructions

installer/                         # VS Code / Copilot installer frontend

plugins/
└── terraform-azurerm-ai-toolkit/
    ├── .claude-plugin/
    │   └── plugin.json            # Playground plugin manifest
    ├── agency.json                # Playground engine/category targeting
    ├── README.md                  # Plugin-specific usage notes
    ├── agents/
    │   ├── review-local.agent.md
    │   ├── review-committed.agent.md
    │   └── review-docs.agent.md
    ├── skills/                    # Thin plugin wrappers only if required by platform
    └── export/                    # Generated or synchronized payload if needed

tools/
└── playground-plugin/
  ├── validate-plugin.ps1        # Future plugin validation helper
  ├── export-plugin.ps1          # Future marketplace/export packaging helper
  └── test-staged-plugin.ps1     # Future one-command staged-plugin smoke test helper
```

## Responsibility Matrix

### Shared core

- Rule contracts
- Companion guidance
- Domain skills
- Regression fixtures
- Validation rules

### VS Code adapter

- Prompt files
- Installer payload
- Copilot instruction entrypoints
- VS Code-specific workflow assumptions such as active editor or slash command invocation

### Playground plugin adapter

- Plugin manifest and metadata
- Agent definitions
- Optional plugin-facing skill wrappers
- Explicit input handling for repo path, file path, PR number, and diff scope

### Repo-only maintenance

- Changelog maintenance
- AI toolkit maintenance
- Release tooling
- Branch and repository maintenance workflows

## Prompt To Agent Migration Map

The current prompt workflows should migrate into plugin agents as follows:

| Current prompt | Plugin target | Reason |
| --- | --- | --- |
| `.github/prompts/code-review-local-changes.prompt.md` | `agents/review-local.agent.md` | Review is orchestration-heavy and should accept explicit repo and diff inputs |
| `.github/prompts/code-review-committed-changes.prompt.md` | `agents/review-committed.agent.md` | PR and commit-range review is better expressed as an agent workflow than a prompt |
| `.github/prompts/code-review-docs.prompt.md` | `agents/review-docs.agent.md` | Docs review already behaves like a deterministic audit workflow and maps naturally to an agent |

The domain authoring and implementation workflows should remain skills first:

- `.github/skills/resource-implementation/SKILL.md`
- `.github/skills/acceptance-testing/SKILL.md`
- `.github/skills/docs-writer/SKILL.md`
- `.github/skills/custom-poller-migration/SKILL.md`

## Guidance-Only First Phase

The first Playground iteration should be guidance-only.

Include:

- shared contracts and guidance
- implementation, testing, docs, and custom poller skills
- agent wrappers for the three review workflows

Do not include initially:

- installer logic
- repo-only maintainer skills
- release-management workflows
- local bootstrap assumptions

This keeps the first plugin focused on reusable standards and review behavior rather than repository bootstrapping.

## Synchronization Strategy

To keep the plugin inheriting updates from the VS Code install workflow without drift:

1. Shared contracts and skills must not be duplicated manually.
2. Plugin agents should reference the same underlying rule files and workflow guidance.
3. If the Playground packaging format requires copied files inside the plugin directory, those copies should be generated by sync or export tooling rather than hand-maintained.
4. Changes to provider standards should land in shared contracts first.
5. Changes to invocation behavior should land only in the relevant frontend adapter.

The sync rule is:

- rules change once in shared core
- frontend behavior changes in adapters
- plugin packaging is generated or synchronized from the shared source

## Native CLI Instruction Loading

GitHub Copilot CLI now supports repository-wide and path-specific custom instructions natively, including `.github/copilot-instructions.md`, `.github/instructions/**/*.instructions.md`, and `AGENTS.md`.

That makes a plugin-side instruction-catalog and parity-resolver layer unnecessary for the normal same-repo CLI workflow.

The intended model is:

- run Copilot CLI from the target repo when practical
- let Copilot CLI load the target repo's repository-wide and path-specific instruction files natively
- keep the plugin focused on workflow entrypoints and any gaps that still are not covered natively, such as deterministic PR-scope preparation when needed

Cross-repo review still needs explicit care around `repo_path` and PR context, but not a separate instruction-matching engine.

## Suggested Plugin Metadata

The Playground repository expects plugin metadata shaped roughly like this:

```json
{
  "name": "terraform-azurerm-ai-toolkit",
  "description": "Provider-specific review, implementation, testing, and documentation guidance for terraform-provider-azurerm contributors.",
  "version": "0.1.0",
  "author": {
    "name": "<maintainer names>",
    "email": "<maintainer emails>"
  },
  "keywords": ["terraform", "azurerm", "copilot", "review", "docs", "testing"]
}
```

Likely `agency.json` starting point:

```json
{
  "engines": ["claude", "copilot"],
  "category": "developer-tools"
}
```

## Regression Strategy

The existing regression harness should become the alignment mechanism between the VS Code and plugin frontends.

Future direction:

- keep one adjudicated case corpus under `tools/regression/`
- allow a case to record which frontend was evaluated
- compare outputs from prompt-based and agent-based frontends against the same benchmark expectations

This is the control point that prevents the side-by-side model from drifting into two unrelated products.

## Recommended Delivery Phases

### Phase 1

- add the planning and adapter layout
- define plugin metadata
- create agent placeholders for review workflows
- keep all rule content shared

### Phase 2

- translate review prompt execution rules into agent workflows
- define explicit CLI-style inputs for repo path, file path, PR number, and diff range
- add plugin validation helpers

### Phase 3

- add sync or export tooling to build the plugin payload from shared source files
- extend regression coverage to compare frontends

### Phase 4

- decide whether any plugin-specific MCP integrations are needed
- decide whether any maintainer-only workflows deserve an optional non-runtime adapter mode

## Initial Concrete Tasks

1. Create `plugins/terraform-azurerm-ai-toolkit/` as the future plugin root.
2. Add `.claude-plugin/plugin.json` and `agency.json` under that plugin root.
3. Add three agent definitions for local review, committed review, and docs review.
4. Decide whether plugin skills should wrap shared skills directly or be generated during export.
5. Add a small sync or validation helper under `tools/playground-plugin/`.
6. Extend regression planning so plugin-agent output can be benchmarked against the existing adjudicated corpus.

## Decision Summary

The repository should evolve into one shared governance core with two adapters:

- VS Code and Copilot prompt and installer adapter
- Playground plugin and CLI agent adapter

The shared contracts and skills remain authoritative. The review prompts become agents. The plugin should be developed side by side in this repository, but it should inherit standards and workflow updates from the shared core rather than maintaining its own duplicate rule set.
