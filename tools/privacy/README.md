# Shared PII Checker

This repository-maintenance checker serves both the Interactive and Hosted
Toolkits. It is not a shipped runtime asset, an installer dependency, or an
automatic hook. It makes no Git changes, fetches, profile writes, or repairs.

## Usage

Run from the source checkout in native PowerShell:

```powershell
pwsh -NoProfile -File ./tools/Test-Pii.ps1 -Scope Worktree
pwsh -NoProfile -File ./tools/Test-Pii.ps1 -Scope Staged
pwsh -NoProfile -File ./tools/Test-Pii.ps1 -Scope Outgoing -BaseRef <verified-remote-commit>
```

- `Worktree` checks tracked and non-ignored untracked files across the whole
  repository. Known deleted tracked files are excluded. Linked worktree paths
  refuse inspection instead of reading files outside the repository.
- `Staged` reads actual Git index blobs, not working copies. A clean disk copy
  cannot hide sensitive staged content. An unresolved index blocks inspection.
- `Outgoing` requires an explicit baseline and checks file snapshots and messages
  in every commit reachable from `HeadRef` but not the baseline. Defaults to
  `HeadRef=HEAD`; a zero object ID explicitly represents a new remote branch.
  An unknown baseline blocks inspection. Repeated blob contents are inspected
  once, while findings retain each affected commit and path.
- Verify the intended remote baseline independently, or obtain it from a trusted
  pre-push input. A local tracking ref is not proof of the actual current remote.
  This checker does not fetch missing objects or assert remote freshness.
- `RepositoryRoot` selects an existing Git checkout, defaulting to this repository.
  `OutputFormat=Json` is available for automation; interactive use defaults to
  human-readable shared validation output.

## Detection And Output

- Detect personal home-directory paths, known local account/device identifiers,
  private measured-workspace artifact names, non-example email addresses, private
  key markers, GitHub credential forms, and cloud access-key identifiers.
- Use explicit synthetic placeholders such as `C:/Users/<user>/workspace`,
  environment-variable examples, or reserved `example`/`invalid`/`test` email
  domains in public documentation. Complete home-directory segments equal to
  `example` or `...` are also accepted as synthetic or redacted examples.
  Other literal account labels and placeholder prefixes remain findings, and
  known local identifiers are checked independently without this exemption.
- Report only rule codes, redacted repository-relative paths, line numbers, and
  immutable commit identities. Never emit matching text, personal values, raw
  Git diagnostics, or the caller's repository path. Line zero denotes a finding
  in a filename; `[commit-message]` denotes commit-message content.
- Inspect every selected file, including ASCII embedded in binary files and
  BOM-marked UTF-16 text. Do not silently exempt tests, generated files, or
  already-tracked paths that happen to match an ignore rule.
- Ignored and untracked private notes are excluded from worktree scope. If such
  a file is force-staged or committed, it is inspected like any other Git content.
- Recognize the current execution environment's local identifiers without
  persisting them. This is not a universal identity directory or proof that all
  semantic PII is absent. Git author/committer metadata is outside this check;
  explicitly configure suitable public author metadata before committing.

## Blocking Semantics

- Exit `0` means the selected scope completed without findings for these rules.
  It is not a guarantee that no possible PII or unknown secret exists.
- Exit `1` means findings require review/remediation. Published attribution or
  apparently synthetic paths are not automatically deleted or exempted.
- Exit `2` means inspection could not complete. Missing Git, invalid references,
  unreadable files, unsupported tree entries/submodules, or diagnostics must
  block an enforcing caller rather than become a passing empty report.
- A hook or external gate must treat every nonzero exit as blocking and prevent
  unauthorized changes to or bypasses of the scanner. No such hook is installed
  by this command; CI alone cannot prevent first disclosure at push.

## Verification

```powershell
pwsh -NoProfile -File ./tools/Test-PiiChecker.ps1
```

The suite uses disposable synthetic Git repositories and never modifies the
source checkout's index, branches, commits, profile configuration, or remote.
