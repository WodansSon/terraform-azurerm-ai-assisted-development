# Test Plan for Branch and LocalPath Parameters

## Pre-Test Setup
1. Ensure clean state: Remove `~/.terraform-azurerm-ai-installer/` if exists
2. Have a test Terraform repository ready
3. Have this AI installer repository cloned locally

## Test Cases

### Test 1: Bootstrap (Existing Functionality - No Changes Expected)
**Objective**: Verify bootstrap still works normally

**PowerShell**:
```powershell
cd "C:\path\to\terraform-azurerm-ai-assisted-development\installer"
.\install-copilot-setup.ps1 -Bootstrap
```

**Bash**:
```bash
cd /path/to/terraform-azurerm-ai-assisted-development/installer
./install-copilot-setup.sh -bootstrap
```

**Expected**:
- ✅ Files copied to user profile (~/.terraform-azurerm-ai-installer/)
- ✅ No errors
- ✅ Bootstrap message displayed

---

### Test 2: Default Installation from User Profile (Existing - Should Use Main Branch)
**Objective**: Verify default behavior pulls from main branch

**PowerShell**:
```powershell
cd ~/.terraform-azurerm-ai-installer
.\install-copilot-setup.ps1 -RepositoryDirectory "C:\path\to\terraform-provider-azurerm"
```

**Bash**:
```bash
cd ~/.terraform-azurerm-ai-installer
./install-copilot-setup.sh -repository-directory "/path/to/terraform-provider-azurerm"
```

**Expected**:
- ✅ Downloads from GitHub main branch
- ✅ Files installed to repository .github/ directory
- ✅ Success message displayed

---

### Test 3: Specify GitHub Branch (New Functionality)
**Objective**: Verify -Branch parameter downloads from specified branch

**PowerShell**:
```powershell
cd ~/.terraform-azurerm-ai-installer
.\install-copilot-setup.ps1 -RepositoryDirectory "C:\path\to\terraform-provider-azurerm" -Branch "develop"
```

**Bash**:
```bash
cd ~/.terraform-azurerm-ai-installer
./install-copilot-setup.sh -repository-directory "/path/to/terraform-provider-azurerm" -branch "develop"
```

**Expected**:
- ✅ Message: "Using GitHub branch: develop"
- ✅ Downloads from specified branch
- ✅ Files installed successfully

**Verification**:
- Check URL in verbose output (if available)
- Verify file content matches branch content on GitHub

---

### Test 4: Use Local Source Path (New Functionality)
**Objective**: Verify -LocalPath parameter copies from local directory

**PowerShell**:
```powershell
cd ~/.terraform-azurerm-ai-installer
.\install-copilot-setup.ps1 -RepositoryDirectory "C:\path\to\terraform-provider-azurerm" -LocalPath "C:\path\to\terraform-azurerm-ai-assisted-development"
```

**Bash**:
```bash
cd ~/.terraform-azurerm-ai-installer
./install-copilot-setup.sh -repository-directory "/path/to/terraform-provider-azurerm" -local-path "/path/to/terraform-azurerm-ai-assisted-development"
```

**Expected**:
- ✅ Message: "Using local source: /path/to/..."
- ✅ Copies files from local directory
- ✅ Files installed successfully
- ✅ No network requests made

**Verification**:
- Make a unique change to a local file
- Verify that change appears in the installed file

---

### Test 5: Error - Both Branch and LocalPath (Validation Test)
**Objective**: Verify mutual exclusivity validation

**PowerShell**:
```powershell
cd ~/.terraform-azurerm-ai-installer
.\install-copilot-setup.ps1 -RepositoryDirectory "C:\repo" -Branch "main" -LocalPath "C:\local"
```

**Bash**:
```bash
cd ~/.terraform-azurerm-ai-installer
./install-copilot-setup.sh -repository-directory "/repo" -branch "main" -local-path "/local"
```

**Expected**:
- ❌ Error message: "Cannot specify both -branch and -local-path"
- ✅ Explanation of the difference
- ✅ Script exits with error code 1

---

### Test 6: Error - Branch with Bootstrap (Validation Test)
**Objective**: Verify bootstrap validation

**PowerShell**:
```powershell
cd "C:\path\to\terraform-azurerm-ai-assisted-development\installer"
.\install-copilot-setup.ps1 -Bootstrap -Branch "develop"
```

**Bash**:
```bash
cd /path/to/terraform-azurerm-ai-assisted-development/installer
./install-copilot-setup.sh -bootstrap -branch "develop"
```

**Expected**:
- ❌ Error message: "Cannot use -branch or -local-path with -bootstrap"
- ✅ Explanation that bootstrap uses current local branch
- ✅ Script exits with error code 1

---

### Test 7: Error - LocalPath with Bootstrap (Validation Test)
**Objective**: Verify bootstrap validation for LocalPath

**PowerShell**:
```powershell
cd "C:\path\to\terraform-azurerm-ai-assisted-development\installer"
.\install-copilot-setup.ps1 -Bootstrap -LocalPath "C:\some\path"
```

**Bash**:
```bash
cd /path/to/terraform-azurerm-ai-assisted-development/installer
./install-copilot-setup.sh -bootstrap -local-path "/some/path"
```

**Expected**:
- ❌ Error message: "Cannot use -branch or -local-path with -bootstrap"
- ✅ Script exits with error code 1

---

### Test 8: Help Documentation (Verification Test)
**Objective**: Verify help text includes new parameters

**PowerShell**:
```powershell
.\install-copilot-setup.ps1 -Help
```

**Bash**:
```bash
./install-copilot-setup.sh -help
```

**Expected**:
- ✅ -Branch parameter documented
- ✅ -LocalPath parameter documented (or -local-path for bash)
- ✅ Contributor workflow examples shown
- ✅ Clear explanation of when to use each parameter

---

### Test 9: Relative Path Handling (Edge Case)
**Objective**: Verify relative paths are handled correctly

**PowerShell**:
```powershell
cd ~/.terraform-azurerm-ai-installer
.\install-copilot-setup.ps1 -RepositoryDirectory "C:\repo" -LocalPath "..\ai-installer-repo"
```

**Bash**:
```bash
cd ~/.terraform-azurerm-ai-installer
./install-copilot-setup.sh -repository-directory "/repo" -local-path "../ai-installer-repo"
```

**Expected**:
- ✅ Relative path converted to absolute path
- ✅ Files copied successfully from resolved path

---

### Test 10: Non-existent Branch (Error Handling)
**Objective**: Verify graceful handling of invalid branch

**PowerShell**:
```powershell
cd ~/.terraform-azurerm-ai-installer
.\install-copilot-setup.ps1 -RepositoryDirectory "C:\repo" -Branch "non-existent-branch-12345"
```

**Bash**:
```bash
cd ~/.terraform-azurerm-ai-installer
./install-copilot-setup.sh -repository-directory "/repo" -branch "non-existent-branch-12345"
```

**Expected**:
- ❌ Download failures (404 errors)
- ✅ Error message indicating download failures
- ✅ Failed files count shown in summary

---

### Test 11: Non-existent Local Path (Error Handling)
**Objective**: Verify validation of local path existence

**PowerShell**:
```powershell
cd ~/.terraform-azurerm-ai-installer
.\install-copilot-setup.ps1 -RepositoryDirectory "C:\repo" -LocalPath "C:\does\not\exist"
```

**Bash**:
```bash
cd ~/.terraform-azurerm-ai-installer
./install-copilot-setup.sh -repository-directory "/repo" -local-path "/does/not/exist"
```

**Expected**:
- ❌ Copy failures
- ✅ Error message indicating source files not found
- ✅ Failed files count shown in summary

---

## Success Criteria

✅ **All validation tests pass**:
- Mutual exclusivity enforced
- Bootstrap restrictions enforced
- Clear error messages displayed

✅ **All functional tests pass**:
- Branch parameter downloads from correct branch
- LocalPath parameter copies from local directory
- Default behavior unchanged (uses main branch)

✅ **Help documentation complete**:
- New parameters documented
- Contributor workflows explained
- Clear examples provided

✅ **Edge cases handled**:
- Relative paths converted to absolute
- Non-existent sources fail gracefully
- Error messages are helpful

✅ **Backward compatibility maintained**:
- Existing commands work unchanged
- No breaking changes to standard workflow

## Test Environment Requirements

- PowerShell 5.1+ or PowerShell Core 7+
- Bash 3.2+ (for bash tests)
- Git repository for testing (terraform-provider-azurerm recommended)
- Network access to GitHub (for branch tests)
- Local clone of terraform-azurerm-ai-assisted-development (for local path tests)

## Notes for Tester

1. Clean state between tests: Remove ~/.terraform-azurerm-ai-installer/ between test runs
2. Verify file content changes when testing local path feature
3. Check console output for appropriate informational messages
4. Verify error messages are user-friendly and actionable
5. Test on both Windows (PowerShell) and Linux/macOS (Bash) if possible
