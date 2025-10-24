# PowerShell Script Analyzer Configuration

This directory contains configuration files for PSScriptAnalyzer, the static code analysis tool for PowerShell scripts.

## Files

### `PSScriptAnalyzerSettings.psd1`
The main PSScriptAnalyzer configuration file used for CI/CD validation and code quality checks.

**Excluded Rules:**
- `PSAvoidGlobalVars` - Intentional use for script-wide state management
- `PSAvoidUsingWriteHost` - Acceptable for interactive installer scripts
- `PSUseShouldProcessForStateChangingFunctions` - Not applicable for our use case
- `PSReviewUnusedParameter` - Parameters kept for API compatibility/future use
- `PSAvoidUsingEmptyCatchBlock` - Intentional for error suppression in non-critical operations
- `PSUseDeclaredVarsMoreThanAssignments` - Variables kept for debugging/future use

### `.pssacodeanalyzersettings.psd1`
Alternative configuration with minimal exclusions, used by some editors for real-time analysis.

## Usage

### Manual Analysis
```powershell
# Analyze all PowerShell files in the installer directory
Invoke-ScriptAnalyzer -Path .\installer\ -Settings .\PSAnalyzer\PSScriptAnalyzerSettings.psd1 -Recurse

# Analyze a specific file
Invoke-ScriptAnalyzer -Path .\installer\install-copilot-setup.ps1 -Settings .\PSAnalyzer\PSScriptAnalyzerSettings.psd1
```

### CI/CD Integration
These settings are automatically used by GitHub Actions and other CI/CD pipelines to ensure code quality standards.

## Customization

To modify the rules:
1. Edit `PSScriptAnalyzerSettings.psd1`
2. Add or remove rules from the `ExcludeRules` array
3. Test your changes: `Invoke-ScriptAnalyzer -Path .\installer\ -Settings .\PSAnalyzer\PSScriptAnalyzerSettings.psd1 -Recurse`

## Documentation

For more information on PSScriptAnalyzer rules and configuration:
- [PSScriptAnalyzer Documentation](https://github.com/PowerShell/PSScriptAnalyzer)
- [Rule Documentation](https://github.com/PowerShell/PSScriptAnalyzer/tree/master/RuleDocumentation)
