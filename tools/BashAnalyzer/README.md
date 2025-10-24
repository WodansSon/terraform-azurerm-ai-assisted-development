# BashAnalyzer

This folder contains ShellCheck configuration files for validating bash scripts in the Terraform AzureRM AI-Assisted Development project.

## Files

- **`.shellcheckrc`**: ShellCheck configuration file with rule exclusions for installer scripts

## Purpose

The `.shellcheckrc` file defines which ShellCheck rules should be excluded during CI/CD validation:

- **SC2034**: Allows intentionally unused variables (used for configuration and exports)
- **SC2155**: Allows combined declaration and assignment (common bash pattern)
- **SC1090**: Allows non-constant source paths (required for dynamic module loading)
- **SC2005**: Allows echo in command substitution (used for clarity)
- **SC2001**: Allows sed usage instead of parameter expansion (clearer for complex patterns)
- **SC2059**: Allows variables in printf format strings (intentional for dynamic formatting)
- **SC2120**: Allows functions with optional arguments (default parameter pattern)
- **SC2119**: Allows function calls without explicit argument passing (default parameter pattern)
- **SC2046**: Allows unquoted command substitution (intentional word splitting)
- **SC2154**: Allows variables assigned in calling scope (scope inheritance pattern)
- **SC2178**: Allows nameref pattern for array references (bash 4.3+ feature)
- **SC2295**: Allows pattern matching in parameter expansion (intentional behavior)
- **SC2207**: Allows array assignment from command output (compatibility with older bash)
- **SC2086**: Allows intentional word splitting for `set` command (required pattern)
- **SC2329**: Allows unused functions (may be invoked indirectly or reserved for future use)
- **SC2317**: Allows unreachable commands (functions invoked indirectly or reserved for future use)

## Usage

### Local Testing
```bash
# Run ShellCheck with the configuration (if ShellCheck version supports --rcfile)
shellcheck --rcfile=./BashAnalyzer/.shellcheckrc ./installer/install-copilot-setup.sh

# Or use --exclude for older ShellCheck versions
shellcheck --exclude=SC2034,SC2155,SC1090,SC2005,SC2001,SC2059,SC2120,SC2119,SC2046,SC2154,SC2178,SC2295,SC2207,SC2086,SC2329,SC2317 ./installer/install-copilot-setup.sh
```

### CI/CD Integration
The GitHub Actions workflows use the `--exclude` parameter for compatibility:
```yaml
- name: ShellCheck
  run: |
    shellcheck --exclude=SC2034,SC2155,SC1090,SC2005,SC2001,SC2059,SC2120,SC2119,SC2046,SC2154,SC2178,SC2295,SC2207,SC2086,SC2329,SC2317 ./installer/**/*.sh
```

**Note**: The `--rcfile` option requires ShellCheck v0.7.0+. CI/CD environments may have older versions, so we use `--exclude` for maximum compatibility.

## Rationale

These exclusions are intentional design choices:

1. **SC2034 (Unused variables)**: Configuration variables and exports are used by sourced modules
2. **SC2155 (Combined declare/assign)**: Standard pattern for local variables in bash functions
3. **SC1090 (Non-constant source)**: Dynamic module loading pattern is required for our architecture
4. **SC2005 (Useless echo)**: Improves code readability in command substitution contexts
5. **SC2001 (Prefer parameter expansion)**: `sed` is clearer for complex regex patterns in our use cases
6. **SC2059 (Variables in printf format)**: Intentional for dynamic formatting in UI output functions
7. **SC2120 (Function references arguments)**: Functions designed to accept optional parameters
8. **SC2119 (Optional parameter patterns)**: Functions intentionally work with or without arguments
9. **SC2046 (Quote word splitting)**: Intentional word splitting in command substitution patterns
10. **SC2154 (Variable referenced but not assigned)**: Variables assigned in calling scope or via nameref
11. **SC2178 (Variable as array vs string)**: Nameref pattern for array references (bash 4.3+)
12. **SC2295 (Expansions need separate quoting)**: Pattern matching intentional in parameter expansion
13. **SC2207 (Prefer mapfile)**: Compatibility with older bash versions that lack mapfile
14. **SC2086 (Double quote to prevent globbing)**: Intentional word splitting for `set` command
15. **SC2329 (Function never invoked)**: Functions may be invoked indirectly or reserved for future use
16. **SC2317 (Command appears unreachable)**: Functions invoked indirectly or reserved for future use

## Maintenance

When adding new exclusions:
1. Document the rationale in this README
2. Ensure the exclusion is intentional, not masking a real issue
3. Update CI/CD workflows to use the configuration file
