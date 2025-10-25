# Implementation Summary: Branch and Local Path Parameters

## Overview
Added `-Branch` and `-LocalPath` parameters to both PowerShell and Bash installers to allow contributors to test AI file changes from different sources.

## Use Cases

### Standard User (Default Behavior - No Changes)
```powershell
# From source branch
.\install-copilot-setup.ps1 -Bootstrap

# From user profile to feature branch
cd ~/.terraform-azurerm-ai-installer/
.\install-copilot-setup.ps1 -RepositoryDirectory "C:\path\to\feature-branch"
```

### Contributor Testing Published Branch Changes
```powershell
# Test AI files from a specific GitHub branch
cd ~/.terraform-azurerm-ai-installer/
.\install-copilot-setup.ps1 -RepositoryDirectory "C:\path\to\repo" -Branch "feature/new-ai-files"
```

### Contributor Testing Uncommitted Changes
```powershell
# Test AI files from local directory (uncommitted changes)
cd ~/.terraform-azurerm-ai-installer/
.\install-copilot-setup.ps1 -RepositoryDirectory "C:\path\to\repo" -LocalPath "C:\path\to\ai-installer-repo"
```

## Parameter Validation

### Mutually Exclusive Parameters
- `-Branch` and `-LocalPath` cannot be used together
- Clear error message explains the difference between the two options

### Bootstrap Restriction
- `-Branch` and `-LocalPath` cannot be used with `-Bootstrap`
- `-Bootstrap` always uses the current local branch
- These parameters are only for updating from user profile

## Implementation Details

### PowerShell Changes

#### File: `install-copilot-setup.ps1`
- Added `-Branch` parameter (String, optional)
- Added `-LocalPath` parameter (String, optional)
- Added validation to ensure mutual exclusivity
- Added validation to prevent use with `-Bootstrap`
- Updated help documentation with contributor examples

#### File: `modules/powershell/FileOperations.psm1`
- Updated `Invoke-InstallInfrastructure` function signature to accept `Branch` and `LocalSourcePath`
- Updated `Install-AllAIFile` function signature to accept `Branch` and `LocalSourcePath`
- Added logic to determine source (GitHub branch vs local path)
- Updated file download/copy logic to use appropriate source

#### File: `modules/powershell/UI.psm1`
- Updated `Show-FeatureBranchHelp` with contributor workflow examples
- Added documentation for `-Branch` and `-LocalPath` parameters
- Added "CONTRIBUTOR WORKFLOW" section explaining testing scenarios

### Bash Changes

#### File: `install-copilot-setup.sh`
- Added `-branch` parameter parsing
- Added `-local-path` parameter parsing
- Added validation for mutually exclusive parameters
- Added validation to prevent use with `-bootstrap`
- Updated function call to pass parameters

#### File: `modules/bash/fileoperations.sh`
- Updated `install_infrastructure()` function signature
- Added logic to configure `SOURCE_REPOSITORY` and `BRANCH` based on parameters
- Updated `download_file()` to support `file://` protocol for local copying
- Added local file copy logic alongside GitHub download logic

#### File: `modules/bash/ui.sh`
- Updated `show_feature_branch_help()` with contributor examples
- Added documentation for `-branch` and `-local-path` parameters
- Added "CONTRIBUTOR WORKFLOW" section

## Testing Scenarios

### Scenario 1: Default Behavior (Main Branch)
```powershell
cd ~/.terraform-azurerm-ai-installer/
.\install-copilot-setup.ps1 -RepositoryDirectory "C:\terraform-provider-azurerm"
```
**Expected**: Downloads AI files from main branch on GitHub

### Scenario 2: Test Specific GitHub Branch
```powershell
cd ~/.terraform-azurerm-ai-installer/
.\install-copilot-setup.ps1 -RepositoryDirectory "C:\terraform-provider-azurerm" -Branch "feature/updated-docs"
```
**Expected**: Downloads AI files from `feature/updated-docs` branch on GitHub

### Scenario 3: Test Local Uncommitted Changes
```powershell
cd ~/.terraform-azurerm-ai-installer/
.\install-copilot-setup.ps1 -RepositoryDirectory "C:\terraform-provider-azurerm" -LocalPath "C:\ai-installer-dev"
```
**Expected**: Copies AI files from `C:\ai-installer-dev` local directory

### Scenario 4: Error - Both Parameters
```powershell
.\install-copilot-setup.ps1 -RepositoryDirectory "C:\repo" -Branch "main" -LocalPath "C:\local"
```
**Expected**: Clear error message explaining mutual exclusivity

### Scenario 5: Error - With Bootstrap
```powershell
.\install-copilot-setup.ps1 -Bootstrap -Branch "main"
```
**Expected**: Error explaining bootstrap uses current local branch

## Benefits

1. **Contributor Workflow**: Contributors can now easily test AI file changes before publishing
2. **Testing Flexibility**: Test both published branches and uncommitted local changes
3. **No Breaking Changes**: Standard users see no difference in behavior
4. **Clear Documentation**: Help text clearly explains contributor features
5. **Proper Validation**: Parameters are validated to prevent misuse

## Files Modified

### PowerShell
- `installer/install-copilot-setup.ps1`
- `installer/modules/powershell/FileOperations.psm1`
- `installer/modules/powershell/UI.psm1`

### Bash
- `installer/install-copilot-setup.sh`
- `installer/modules/bash/fileoperations.sh`
- `installer/modules/bash/ui.sh`

## Backward Compatibility

✅ **Fully Backward Compatible**
- All existing command patterns continue to work unchanged
- Default behavior when parameters are omitted remains the same
- No breaking changes to standard user workflow
