# Hosted Command Help Implementation

This document defines the planned shared help presentation for maintainer-facing Hosted Toolkit commands. Native PowerShell comment-based help and parameter metadata remain authoritative; the shared Hosted module owns only the curated terminal rendering and discovery experience.

The system is not implemented until native help exists on every registered entrypoint, the shared renderer and compatibility switches exist, and focused validation passes. This document does not make `-Help`, `-h`, or `-Detailed` available by itself.

## Purpose

Maintainers should be able to discover ordinary workflows without reading PowerShell source or relying on PowerShell's default formatted `Get-Help` presentation. Standard PowerShell tooling must still be able to discover complete command help and valid invocation shapes.

The shared system must:

- Preserve zero-argument behavior for commands designed to run with defaults.
- Present a small golden path before advanced options.
- Render every registered command through one consistent layout.
- Use native comment-based help as the command-specific prose and example authority.
- Use native parameter metadata and parameter sets for syntax, defaults, validation, mutual exclusion, and default invocation behavior.
- Derive renderer content from PowerShell help and command metadata instead of maintaining a parallel catalog.
- Exit before authentication, network access, source collection, process launch, or file writes when showing help or rejecting arguments.
- Preserve normal `Get-Help` behavior for scripts and standard PowerShell tooling.

## First-Party Foundation

The implementation follows these Microsoft PowerShell standards:

- [Comment-based help](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_comment_based_help) defines script and function help through `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`, `.NOTES`, and `.LINK` blocks. PowerShell generates command name, syntax, parameter attributes, common parameters, and remarks from the command itself.
- [Parameter sets](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_parameter_sets) define valid invocation shapes, mutually exclusive parameters, mandatory parameters per shape, and the default parameter set.
- [`Get-Help`](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/get-help) is the standard discovery surface for scripts, functions, and cmdlets. PowerShell handles `-?` for external scripts before script parameter binding, so it remains the native help path rather than a custom alias.
- [PowerShell help types](https://learn.microsoft.com/powershell/utility-modules/platyps/types-of-help) include comment-based help and external MAML help. External MAML and PlatyPS are unnecessary for the initial four source scripts because the Hosted Toolkit does not require localized or updatable help packages.

The Hosted renderer supplements these standards; it does not replace them.

## Scope

Only supported maintainer entrypoints receive the shared interface.

The initial allowlist is:

- `hosted_copilot/tools/Install-HostedRules.ps1`
- `hosted_copilot/tools/Invoke-HostedReview.ps1`
- `hosted_copilot/tools/Start-RuleWorkbench.ps1`
- `hosted_copilot/tools/Test-HostedRules.ps1`

Scripts beneath `commands/`, `internal/`, `tests/`, migration directories, and fixture directories are not registered merely because they are executable PowerShell files. Modules may consume shared presentation primitives but do not expose command help.

Adding or removing a registered command is an explicit maintainer-interface change. Filesystem discovery must not expand the allowlist automatically.

## Ownership

The implementation has one owner for each concern:

| Concern | Owner |
| --- | --- |
| Synopsis, description, parameter descriptions, examples, notes, and links | Comment-based help in each registered PowerShell entrypoint |
| Parameter names, aliases, types, defaults, validation attributes, parameter sets, and default parameter set | Each registered PowerShell entrypoint |
| Fixed layout, semantic styling, wrapping, introspection, and rendering | `hosted_copilot/tools/modules/shared/HostedCommandHelp.psm1` |
| Registration, native-help, side-effect, alias, parameter-set, and rendering tests | `hosted_copilot/tools/tests/Test-HostedCommandHelp.ps1` |
| Complete profile composition | `hosted_copilot/tools/Test-HostedRules.ps1` |

The module must not contain command-specific summaries, examples, parameter descriptions, parameter sets, defaults, or argument relationships. Registered scripts must not hand-author help layout.

## Entrypoint Contract

Every registered command contains complete comment-based help before its parameter block and declares `Help` with the `h` compatibility alias plus `Detailed`. Both switches own dedicated parameter sets:

```powershell
[CmdletBinding(DefaultParameterSetName = 'Default')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Help')]
    [Alias('h')]
    [switch]$Help,

    [Parameter(Mandatory, ParameterSetName = 'Detailed')]
    [switch]$Detailed
)
```

Operational parameters belong only to operational parameter sets. Combining help with operational parameters must fail during native parameter binding rather than silently ignoring requested work.

After parameter binding, the script imports the shared help module and dispatches help before operational initialization:

```powershell
if ($Help -or $Detailed) {
    Show-HostedCommandHelp -ScriptPath $PSCommandPath
    return
}
```

The help path may read the shared module and target script metadata. Exceptional command-owned argument validation may inspect bound parameters. Neither path may:

- Authenticate with GitHub or Azure.
- Invoke Git, GitHub CLI, Copilot CLI, npm, or another child process.
- Collect source inventories or inspect a target repository.
- Create directories, caches, temporary files, logs, or browser state.
- Start a server or browser.
- Mutate environment variables or persistent user configuration.

`-Help`, `-h`, and `-Detailed` must produce equivalent curated content and exit successfully. Native `-?` must resolve the same comment-based help and exit successfully without entering the script body, but its PowerShell-owned presentation is not required to match the curated renderer byte-for-byte. These paths do not change the standard `Get-Help <script-path>` surface.

Use native parameter sets for incompatible invocation shapes whenever possible. A relationship that cannot be expressed cleanly without parameter-set explosion may retain one explicit, tested validation check immediately after help dispatch and before operational side effects. Do not build a generic relationship language for those exceptional checks.

## Command Identity

The shared module resolves the calling script to a normalized repository-relative path for diagnostics and rendering.

Identity rules are:

- Resolve the path with filesystem APIs before comparison.
- Reject paths outside `hosted_copilot/tools/`.
- Convert separators to `/` for stable repository-relative presentation.
- Reject filename-only identity because different command directories may contain the same filename.

The caller passes `$PSCommandPath`; it does not pass a display identity or select authored content.

## Fixed Presentation Template

The module owns one terminal layout for every registered command. Native help may omit an optional supported section, but commands cannot reorder or restyle sections.

The fixed order is:

- Command header
- Summary
- Usage
- Command-owned semantic option groups
- Notes
- Related links

The module owns:

- Header separators and capitalization.
- Blank-line and indentation rules.
- Terminal-width detection and text wrapping.
- Semantic colors and emphasis: yellow section headings and value-placeholder content, magenta script arguments, cyan commands, paths, links, and default values, and neutral syntax delimiters and prose.
- Command, parameter, default, allowed-value, note, and link formatting.
- Semantic option-group layout while each command owns only group names and parameter membership.
- Empty-section suppression.
- Stable text output when color is unavailable or redirected.

Help text must remain readable as plain text. Redirected output must not contain terminal control sequences.

## Native Help Content

Each registered script owns one contiguous comment-based help block using standard PowerShell keywords.

- `.SYNOPSIS` supplies the rendered summary.
- `.DESCRIPTION` supplies extended context when needed.
- `.PARAMETER` supplies authored parameter meaning without repeating type, required state, aliases, defaults, or validation attributes.
- `.EXAMPLE` supplies common workflows and examples. Put ordinary maintainer workflows first and advanced or automation examples later.
- `.NOTES` supplies concise operational caveats.
- `.LINK` supplies related documentation.

The first `.EXAMPLE` for a command with a valid zero-argument operation must show that default operation. Commands requiring operational input must not advertise a parameter-free example.

Do not use `.EXTERNALHELP` or generated MAML in the initial implementation. Comment-based help is sufficient, source-reviewable, and natively supported for these scripts.

## Native Invocation Contract

Parameter sets are the authority for legal invocation shapes.

- Use `CmdletBinding(DefaultParameterSetName = '<name>')` to identify zero-argument behavior when a command supports it.
- Give each distinct operation a unique parameter or unique parameter combination.
- Place incompatible parameters in different sets.
- Keep parameters shared across modes in every applicable set.
- Use `Mandatory` within an operational set when that operation requires input.
- Reserve one dedicated set for `Help` so mandatory operational input never prevents help binding.
- Keep the total comfortably below PowerShell's 32-set limit.

Do not misuse parameter sets as display categories. Their only purpose is executable command syntax.

When a dependency such as one switch requiring another cannot be represented without awkward prompting or excessive sets, retain a small explicit command-owned check. The check must be immediately after help dispatch, must produce an actionable error, and must have focused positive and negative tests.

## Parameter Introspection

The module derives parameter facts from the registered script.

Use `Get-Help`, PowerShell command metadata, and the script abstract syntax tree to derive:

- Synopsis, description, parameter descriptions, examples, notes, and links.
- Parameter name and type.
- Aliases.
- Mandatory state.
- Parameter sets and the default parameter set.
- `ValidateSet`, `ValidateRange`, and `ValidatePattern` constraints.
- Static literal defaults.
- Whether a non-literal default is computed.

Do not execute a default-value expression to render help. A safe static literal may be displayed directly; another expression is displayed as `computed`.

The module must exclude PowerShell common parameters from command-specific options. Each registered script supplies an ordered map of semantic option-group names to parameter names; the module rejects unknown, duplicate, or missing command parameters. Group membership is presentation metadata only and must not duplicate descriptions, types, defaults, validation, conflicts, or runtime behavior. The shared help switch is shown in a fixed footer rather than repeated as an operational option.

## Rendering Behavior

The renderer must:

- Use the command filename as the visible identity and normalized path as the internal identity.
- Show ordinary `.EXAMPLE` workflows before the complete grouped option inventory.
- Mark the syntax associated with the native default parameter set as the zero-argument behavior when applicable.
- Render required parameters distinctly from optional parameters.
- Show aliases, allowed values, safe defaults, and valid parameter-set syntax without restating parameter facts.
- List every command-owned operational parameter exactly once with its native help description.
- Wrap prose without splitting parameter names or command tokens.
- Adapt to the current terminal width with a documented minimum width.
- Use semantic presentation helpers rather than command-specific colors.
- Produce deterministic plain text for identical command metadata and terminal width.
- Return text through the success stream and reserve diagnostics for failures.

The shared module may consume repository-wide validation presentation primitives for consistent separators and semantic status rendering. It must not depend on Interactive Toolkit runtime files or introduce a deployment dependency between products.

## Validation Contract

`Test-HostedCommandHelp.ps1` validates the complete registered set.

### Registration And Native Help

- Require exact agreement between the test-owned public-command allowlist and the supported root entrypoints.
- Reject internal, test, migration, fixture, and module paths.
- Require valid comment-based help with synopsis, parameter descriptions, and at least one example.
- Require every registered script to declare `Help` with alias `h` and a dedicated `Detailed` switch.
- Require `Get-Help <script-path> -Full` to resolve every command-owned parameter.
- Require every declared parameter set to be natively resolvable and to have a unique invocation shape.
- Require the declared default parameter set to match documented zero-argument behavior.

### Rendering

- Invoke each command with `-Help`, `-h`, `-Detailed`, and native `-?` in isolated temporary state.
- Require `-Help`, `-h`, and `-Detailed` to produce equivalent normalized output, and require native `-?` to expose the command's comment-based help.
- Require the fixed section order and one shared presentation shape.
- Require workflows, usage, options, and examples to identify the correct calling script.
- Require a command with a valid zero-argument operation to present that operation first.
- Require a command without a zero-argument operation to render required input clearly.
- Test narrow and wide terminal widths through renderer inputs rather than changing the maintainer terminal.
- Verify redirected output contains no ANSI or other terminal control sequences.

### Invocation Validation

- Invoke representative valid syntax from every parameter set and require native binding success.
- Invoke representative incompatible parameter combinations and require failure before operational work.
- Exercise each exceptional explicit dependency check in valid and invalid forms.
- Require rendered usage to match `Get-Command` parameter-set metadata.

### Side Effects

- Run help and invalid argument combinations with unavailable external authentication and require deterministic results.
- Snapshot relevant repository and temporary roots before invocation and require no writes afterward.
- Prove no child process, server, browser, network request, source collection, or semantic evaluation starts.
- Require help dispatch and exceptional argument validation before operational modules that perform environment validation or side effects.

### Drift

- Fail when a registered script adds, removes, or renames a parameter without corresponding native help coverage.
- Fail when comment-based help omits a command-owned parameter.
- Fail when an example references an unknown parameter.
- Fail when the default parameter set and first ordinary example disagree.
- Fail when an unregistered root-level maintainer command is added without an ownership decision.

`Test-HostedRules.ps1` composes this focused suite into complete Hosted validation. Focused development may invoke `Test-HostedCommandHelp.ps1` directly.

## Migration Sequence

Implement the system in this order:

- Add complete comment-based help and deliberate parameter sets to one entrypoint.
- Implement `HostedCommandHelp.psm1` with deterministic rendering over native PowerShell help and command metadata.
- Implement `Test-HostedCommandHelp.ps1` for registration, native help, parameter sets, rendering, aliases, side effects, and drift.
- Add side-effect-free help dispatch to the first command and validate the complete path.
- Migrate the remaining three commands without changing ordinary behavior.
- Replace duplicated conflict checks only where native parameter sets provide equivalent behavior and tests.
- Compose the focused test into `Test-HostedRules.ps1`.
- Update `hosted_copilot/tools/README.md` to present `-Help`, `-h`, and `-Detailed` as the curated discovery surface while preserving native `-?` and `Get-Help` behavior.
- Add the user-visible implementation to `hosted_copilot/CHANGELOG.md` only when the executable system lands.

The migration must not weaken mandatory operational parameters. In particular, the dedicated help parameter set must let `Install-HostedRules.ps1` and `Invoke-HostedReview.ps1` bind help without `RepoDirectory`, while every operational parameter set continues to require it.

## Non-Goals

The first implementation does not:

- Add help menus to internal, specialized catalog, migration, fixture, or test scripts.
- Replace ordinary zero-argument command behavior.
- Implement a general-purpose PowerShell documentation generator.
- Replace or bypass PowerShell's `Get-Help` system.
- Add a JSON or schema authority for help content, parameter facts, conflicts, dependencies, or default behavior.
- Allow per-command layouts, colors, widths, format strings, or arbitrary section ordering.
- Execute examples or workflow commands from the help menu.
- Provide interactive prompts, pagers, or terminal menus.
- Change Hosted runtime payload or target-repository deployment behavior.

## Completion Criteria

The shared command-help system is complete when:

- All four allowlisted commands support equivalent curated `-Help`, `-h`, and `-Detailed` menus plus native `-?` and `Get-Help` topics.
- Help exits successfully without operational side effects.
- Exceptional command-owned argument checks fail before operational side effects.
- Native parameter sets reject incompatible invocation shapes before operational side effects.
- All commands render through one module-owned template.
- Standard `Get-Help` remains complete and functional for every registered script.
- The custom renderer derives authored content and parameter facts from native PowerShell authorities.
- Zero-argument and existing operational behavior remain unchanged.
- Focused command-help tests and complete Hosted validation pass.
