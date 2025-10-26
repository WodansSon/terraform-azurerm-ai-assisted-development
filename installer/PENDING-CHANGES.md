# Pending Changes for v1.0.0 Release

**Status**: Work in Progress - PowerShell Script Updates
**Target**: Update both PowerShell and Bash scripts before finalizing changelog

---

## PowerShell Script Improvements (Completed)

### 1. Early Validation Error Refactoring
**Files Modified**: `install-copilot-setup.ps1`

- ✅ Created `Show-EarlyValidationError` function with switch statement pattern
- ✅ Consolidated 5 error types into single reusable function:
  - `BootstrapConflict` - Cannot use -Branch/-LocalPath with -Bootstrap
  - `MutuallyExclusive` - Cannot use both -Branch and -LocalPath
  - `ContributorRequired` - -Branch/-LocalPath require -Contributor flag
  - `EmptyLocalPath` - -LocalPath parameter cannot be empty
  - `LocalPathNotFound` - -LocalPath directory does not exist
- ✅ Reduced parameter validation code from ~100 lines to ~40 lines
- ✅ Type-safe with `[ValidateSet()]` parameter
- ✅ Consistent error formatting across all validation scenarios
- ✅ Matches `Show-ValidationError` pattern in UI module

**Why**: DRY principle - eliminates code duplication, easier to maintain, consistent error messages. Makes validation logic crystal clear and easy to extend.

**Bash Implementation TODO**:
- Create equivalent `show_early_validation_error()` function in bash
- Use case statement pattern (same as PowerShell switch)
- Support same error types with consistent messages
- Keep inline error display for pre-module-load validation

---

### 2. Contributor Mode Enhancements
**Files Modified**: `install-copilot-setup.ps1`

- ✅ Added `-Contributor` flag for testing AI file changes
- ✅ Added validation: `-Branch` and `-LocalPath` require `-Contributor` flag
- ✅ Added validation: Cannot use `-Branch` or `-LocalPath` with `-Bootstrap`
- ✅ Reordered validation priority: Bootstrap conflicts checked first (fail fast)
- ✅ Added SAFETY CHECK 3: Block contributor mode on source branches (main/master)
  - Prevents accidental AI infrastructure changes on protected branches
  - Shows clear error message with guidance

**Why**: Contributor safety - prevents testing AI file changes directly on source branches. Bootstrap validation first ensures foundational operation conflicts are caught immediately.

---

### 2. Code Organization - Region Structure
**Files Modified**: `install-copilot-setup.ps1`

- ✅ Added top-level region: `#region Parameter Parsing and Validation`
  - ✅ Sub-region: `#region Variable Initialization` - Script-level variables
  - ✅ Sub-region: `#region Early Helper Functions` - Functions before module loading
  - ✅ Sub-region: `#region Argument Parsing` - Manual parameter parsing loop
  - ✅ Sub-region: `#region Parameter Validation` - Validation checks

**Why**: Better code organization, collapsible sections in VS Code, easier navigation

---

### 3. Version Control Centralization
**Files Modified**:
- `install-copilot-setup.ps1`
- `modules/powershell/UI.psm1`

**Main Script (`install-copilot-setup.ps1`)**:
- ✅ Created `#region Script Configuration` section at top
- ✅ Added `$script:InstallerVersion = "1.0.0"` as single version source
- ✅ Updated `Show-EarlyErrorHeader` to use `$script:InstallerVersion`
- ✅ Updated fallback `InstallerConfig` to use `$script:InstallerVersion`

**UI Module (`UI.psm1`)**:
- ✅ Created `#region Module Configuration` section
- ✅ Added `$script:DefaultVersion = "1.0.0"` for fallback
- ✅ Updated `Write-Header` default parameter to use `$script:DefaultVersion`

**Why**: Single point of version management - change once, updates everywhere

---

### 4. Bootstrap Branch Detection Fix
**Files Modified**:
- `install-copilot-setup.ps1`
- `modules/powershell/UI.psm1`

**Problem**: `-Bootstrap` failed with error "Branch '' does not exist"
- `-Bootstrap` was passing empty `$Branch` parameter to `Get-ManifestConfig`
- Empty string overrode the default "main" branch

**Solution**:
- ✅ Added Step 3: Determine effective branch logic
- ✅ Bootstrap mode: Always detects and uses current git branch
- ✅ Contributor mode: Uses user-provided `-Branch` parameter
- ✅ Default mode: Uses "main" as fallback
- ✅ Added `Show-BootstrapGitError` UI function for consistent error display
- ✅ Bootstrap git detection failure is now a hard error (not silent fallback)

**Why**: Bootstrap should always use current local branch, no overrides. Git detection failure means we can't proceed safely.

---

### 5. Installation Source Clarity Improvements
**Files Modified**: `modules/powershell/FileOperations.psm1`

**Problem**: Installation messages didn't clearly indicate where AI files were coming from
- "Using local files from:" was vague (using vs installing)
- GitHub downloads didn't show which branch was being used
- Auto-detected local repo didn't show branch information

**Solution**:
- ✅ Updated local path message: `Installing from local path: C:\path\to\source`
- ✅ Updated GitHub download: `Downloading files from GitHub (branch: test/contributor_mode)...`
- ✅ Updated auto-detected repo: `Installing from local toolkit repository (branch: foo)...`
- ✅ Branch info only shown when not "main" (reduces noise for normal usage)
- ✅ Branch info **always** shown in contributor mode (even if "main") for clarity

**Why**: Clear, action-oriented messages that show both the action (Installing/Downloading) and the source (path/branch). In contributor mode, always showing the branch makes it crystal clear which source is being tested.

---

### 6. LocalPath File Resolution Fix
**Files Modified**: `modules/powershell/FileOperations.psm1`

**Problem**: `-LocalPath` was looking for files in wrong locations
- Code was stripping `.github/` prefix from file paths
- Expected files at repo root instead of `.github/` subdirectory
- All file copies failed with "Local file not found" warnings

**Solution**:
- ✅ Removed incorrect path stripping logic
- ✅ Now looks for files at their actual locations in the AI dev repo structure
- ✅ File paths match GitHub structure: `.github/copilot-instructions.md`, `.github/instructions/...`, etc.

**Why**: The AI dev repo has the same directory structure locally as on GitHub. Files should be accessed at their actual paths without modification.

---

### 7. LocalPath Parameter Validation (PRIORITY 4)
**Files Modified**:
- `install-copilot-setup.ps1`
- `modules/powershell/FileOperations.psm1`

**Problems**:
1. Empty `-LocalPath ""` parameter was accepted and failed deep in FileOperations with inconsistent error
2. Non-existent `-LocalPath "C:\does\not\exist"` showed inconsistent error format deep in module
3. Validation errors didn't follow the standard early error format used by other PRIORITY checks

**Solution**:
- ✅ Expanded PRIORITY 4 validation to check both empty strings and path existence
- ✅ Empty path check: Detects explicitly provided `-LocalPath` parameter using argument list inspection
- ✅ Path existence check: Validates directory exists before proceeding
- ✅ Consistent error format: Both validations use standard error header and formatting
- ✅ Removed redundant validations from FileOperations.psm1
- ✅ FileOperations now assumes valid path if it reaches the module

**Why**: Fail fast architecture with consistent user experience - all parameter validation errors should be caught early in the main script with clean, user-friendly error messages matching the established format. Business logic validation stays in modules. This provides better separation of concerns and cleaner error output.

---

### 8. Fixed "Copied" Action Not Counted as Success
**Files Modified**: `modules/powershell/FileOperations.psm1`

**Problem**: Local file copy operations were being counted as "Failed" even when they succeeded
- `Copy-LocalAIFile` function sets `$result.Action = "Copied"`
- Success counter only recognized "Downloaded" and "Overwritten" actions
- All `-LocalPath` installations showed "Successful: 0, Failed: 17" despite working correctly

**Solution**:
- ✅ Added "Copied" to the success actions list in the switch statement
- ✅ Local copy operations now correctly counted as successful

**Why**: Pre-existing bug revealed during contributor mode testing. The `-LocalPath` feature (contributor testing) was always broken for success counting, but the bug wasn't discovered until comprehensive testing of the empty path validation.

---

### 9. Output Spacing Consistency Fix
**Files Modified**: `modules/powershell/UI.psm1`

**Problem**: Output spacing between sections was inconsistent
- `Show-OperationSummary` didn't end with blank line
- `Show-CleanupReminder` started with blank line
- Result: Double blank line between summary and cleanup reminder

**Solution**:
- ✅ Added trailing `Write-Host ""` to `Show-OperationSummary` function
- ✅ Removed leading `Write-Host ""` from `Show-CleanupReminder` function
- ✅ Restored consistent output paradigm across all UI functions

**Why**: Maintains clean output methodology where every function ends with `Write-Host ""` and no function starts with it (unless internal spacing). This ensures consistent single blank lines between sections and eliminates spacing issues when functions are chained together.

---

## Bash Script Updates (Pending)

### Already Implemented in Bash
- ✅ `-contributor` flag
- ✅ Validation: `-branch` and `-local-path` require `-contributor`
- ✅ Validation: Cannot use `-branch` or `-local-path` with `-bootstrap`
- ✅ SAFETY CHECK 1: Block AI dev repo targeting
- ✅ SAFETY CHECK 2: Block source branch operations

### Need to Add to Bash
- ❌ SAFETY CHECK 3: Block contributor mode on source branch
- ❌ Version control via single variable (currently hardcoded in multiple places)
- ❌ Better section organization with clear comment blocks
- ❌ Bootstrap branch detection fix (check if same issue exists)

---

## Changelog Entry (Draft for v1.0.0)

```markdown
## 1.0.0 (Unreleased)

FEATURES:

* **New `-Contributor` Mode**: Added contributor testing features for AI infrastructure development
  - `-Contributor -Branch <name>`: Test published branch changes
  - `-Contributor -LocalPath <path>`: Test uncommitted local changes

IMPROVEMENTS:

* **Code Organization**: Added region-based structure for better maintainability
* **Version Management**: Centralized version control - single update point for all version displays
* **Bootstrap Reliability**: Fixed `-Bootstrap` to correctly detect and use current git branch

BUG FIXES:

* Fixed `-Bootstrap` failing with "Branch '' does not exist" error
* Added safety checks to prevent contributor mode on source branches

NOTES:

* Contributors testing AI file changes must use `-Contributor` flag for safety
```

---

## Testing Checklist

### PowerShell Testing
- [ ] Test `-Bootstrap` on main branch
- [ ] Test `-Bootstrap` on feature branch
- [ ] Test `-Contributor -Branch <name>` from user profile
- [ ] Test `-Contributor -LocalPath <path>` from user profile
- [ ] Test contributor mode rejection on main branch
- [ ] Test version display in all headers
- [ ] Test all validation error messages

### Bash Testing (After Updates)
- [ ] Test `-bootstrap` on main branch
- [ ] Test `-bootstrap` on feature branch
- [ ] Test `-contributor -branch <name>` from user profile
- [ ] Test `-contributor -local-path <path>` from user profile
- [ ] Test contributor mode rejection on main branch
- [ ] Test version display in all headers
- [ ] Test all validation error messages

---

## Next Steps

1. **Finish PowerShell Testing**: Verify all improvements work correctly
2. **Update Bash Script**: Apply all PowerShell improvements to bash version
3. **Cross-Platform Testing**: Verify both scripts work identically
4. **Finalize Changelog**: Clean up and format final changelog entry
5. **Update Documentation**: Update README if needed for new contributor features
