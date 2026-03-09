---
description: "Code Review Prompt for Terraform AzureRM Provider Local Changes"
---

# 🚫 **RECURSION PREVENTION - READ FIRST**

**⚠️ CRITICAL:** Do not review this prompt file itself (recursion prevention).

### 🔄 **RECURSION PREVENTION**
*(Skipped: recursion prevention - cannot review code review prompt itself)*

### 🟢 **STRENGTHS**
[List positive aspects and well-implemented features]

### 🟡 **OBSERVATIONS**
[List areas for consideration or minor improvements]

### 🔴 **ISSUES** (if any)
[List ONLY actual problems that need to be fixed - bugs, errors, violations, missing requirements, typos, misspellings, improper pointer handling, incorrect SDK usage, using deprecated utilities, etc. Do NOT include observations about what was done correctly or opinions about changes that are already implemented properly]

**Before executing any review commands:**

**IF changes include the file `.github/prompts/code-review-local-changes.prompt.md`:**
- **SKIP** reviewing this specific file in the detailed review
- **LOG** in the review output: "- **File Skipped**: `.github/prompts/code-review-local-changes.prompt.md` - Cannot review code review prompt itself to prevent infinite loops"
- **CONTINUE** reviewing all other changed files normally

**This prevents self-review loops while allowing the review process to complete.**

---

# 🚀 **EXECUTE IMMEDIATELY** - Code Review Task

**PRIMARY TASK**: Perform code review of local changes for Terraform AzureRM provider

## ⚡ **START HERE - MANDATORY EXECUTION STEPS**

**1. GET THE DIFF - Run git commands to find changes:**

**Use the `run_in_terminal` tool with these exact patterns:**

```
# STEP 1: Check git status for overall state (including untracked files)
run_in_terminal:
  command: "git status --porcelain"
  explanation: "Check git status for overall state including untracked files"
  isBackground: false

# STEP 2: Get file summary for tracked files (to count changed files)
run_in_terminal:
  command: "git --no-pager diff --stat --no-prefix"
  explanation: "Get file summary for tracked files to count changed files"
  isBackground: false

# STEP 3: Get detailed changes for tracked files
run_in_terminal:
  command: "git --no-pager diff --no-prefix --unified=3"
  explanation: "Get detailed changes for tracked files"
  isBackground: false

# STEP 4: Check staged changes ONLY if no unstaged changes found in STEP 3
run_in_terminal:
  command: "git --no-pager diff --stat --no-prefix --staged"
  explanation: "Check staged file summary ONLY if no unstaged changes found"
  isBackground: false

run_in_terminal:
  command: "git --no-pager diff --no-prefix --unified=3 --staged"
  explanation: "Get detailed staged changes ONLY if no unstaged changes found"
  isBackground: false

# STEP 5: Get current branch name
run_in_terminal:
  command: "git branch --show-current"
  explanation: "Get current branch name"
  isBackground: false

# STEP 6: Handle untracked files (new files not in git yet)
# If git status shows untracked files, examine them individually using read_file tool
```

**⚠️ IMPORTANT**:
- If git status shows NO changes (tracked, staged, or untracked), abandon review and display: **"☠️ **Argh! There be no changes here!** ☠️"**
- If ONLY untracked files exist, review them as new file additions
- Untracked files are often the most critical changes to review (new features, scripts, etc.)
- **TOOL USAGE**: Always use the `run_in_terminal` tool with all three required parameters: `command`, `explanation`, and `isBackground`
- **EFFICIENCY RULE**: Never repeat the same git command - trust your initial results and move forward decisively

**📋 FOR LARGE MULTI-FILE CHANGES**: If the combined diff is too large or complex, examine each file individually using:
```powershell
git --no-pager diff --no-prefix filename1
git --no-pager diff --no-prefix filename2
# etc. for each file shown in git stat
```

**2. RECURSION PREVENTION CHECK** - Applied automatically (see top of file)

**🎯 EXECUTION EFFICIENCY RULE**:
- **NEVER repeat git commands** - Each command should only be run ONCE during the review
- **Trust initial results** - Don't second-guess or re-verify git output
- **Efficient sequence**: status → stat → diff → branch → examine untracked files (if any)
- **Avoid redundancy**: If you already have the diff, don't run it again
- **Move forward decisively** with the information gathered from the first execution of each command

**🚨 CRITICAL ACCURACY REQUIREMENT**:
The git stat output MUST be parsed correctly to count new/modified/deleted files accurately. Misclassifying deleted files as modified files is a critical error that undermines review credibility.

##  📝 **REVIEW OUTPUT FORMAT**

**Use this EXACT format for the review output:**

**3. ANALYZE THE FILE CHANGES** - Parse git status and diff output to get accurate file counts
- Parse `git status --porcelain` for complete change overview:
  - `??` prefix = Untracked files (NEW files not in git)
  - `M ` prefix = Modified files (tracked and changed)
  - `A ` prefix = Added files (staged new files)
  - `D ` prefix = Deleted files (staged deletions)
  - `MM` prefix = Modified file with both staged and unstaged changes
- Parse `git --no-pager diff --stat` for tracked file changes:
  - **CRITICAL**: Files showing only `------------------` (all minus signs) are DELETED files
  - **CRITICAL**: Files showing only `++++++++++++++++++` (all plus signs) are NEW tracked files
  - **CRITICAL**: Files showing both `+` and `-` are MODIFIED files
- **EXAMPLE git status**: `?? file.go` = UNTRACKED file (1 new untracked file)
- **EXAMPLE git stat**: `file.md | 505 -----------------` = DELETED file (1 deleted file)
- **EXAMPLE git stat**: `file.go | 25 +++++++++++++++++++++++++` = NEW tracked file (1 new file)
- **EXAMPLE git stat**: `file.go | 10 +++++++---` = MODIFIED file (1 modified file)
- Use this accurate classification in the CHANGE SUMMARY section

**4. REVIEW THE CHANGES** - Apply expertise as principal Terraform provider engineer

**🚨 CRITICAL: Review ALL files shown in git stat output - do not miss any files!**

**5. PROVIDE STRUCTURED FEEDBACK** - Use the review format below

---

## 🎯 **CORE REVIEW MISSION**

As a principal Terraform provider engineer with expertise in Go development, Azure APIs, and HashiCorp Plugin SDK, deliver actionable code review feedback.

**Critical Issues**:
- Security vulnerabilities in Azure authentication and API calls
- Resource lifecycle bugs (create, read, update, delete operations)
- State management and drift detection issues
- Azure API error handling and retry logic
- Resource import functionality correctness
- Terraform Plugin SDK usage violations
- Implementation approach consistency (Typed vs Untyped Resource Implementation)
- CustomizeDiff import pattern correctness (conditional import requirements)
- Resource schema validation and type safety

**Code Quality**:
- Go language conventions and idiomatic patterns
- Terraform resource implementation best practices
- Azure SDK for Go usage patterns
- Plugin SDK schema definitions and validation
- Schema standards: flag `TypeString` fields that are effectively boolean toggles (e.g. allowed values `Enabled`/`Disabled`, `Enable`/`Disable`, or `On`/`Off`) and prefer a boolean `*_enabled` instead
  - Tri-state nuance: if the API includes a third value like `None` (e.g. `Enabled`/`Disabled`/`None` or `On`/`Off`/`None`), confirm whether `None` is equivalent to omitted/default (still prefer optional `*_enabled`) vs a distinct user-settable state (string enum may be justified but must be explicitly justified)
  - Scope note: treat this as a standard for new fields; for already-shipped schemas, prefer deprecation/migration patterns over breaking renames
- Schema standards: flag `TypeString` fields whose `ValidateFunc` is only `validation.StringIsNotEmpty`/"string not empty" as an **Issue** unless there is explicit justification why stronger validation is not feasible
  - This is a last-resort validator and should not be used when an enum, regex, length bound, or other deterministic validation is possible
  - Legitimate exceptions exist (for example: Azure accepts unconstrained user strings, or the service has undocumented rules), but the PR should state the reason
- CustomizeDiff function validation logic and patterns
- Implementation approach appropriateness (Typed for new, Untyped maintenance only)
- Error handling and context propagation
- Resource timeout configurations
- Acceptance test coverage and quality
- **Tests use ONLY ExistsInAzure() check with ImportStep() - NO redundant field validation**
- **CRITICAL: Code comments policy enforcement - Comments only for Azure API quirks, complex business logic, or SDK workarounds that cannot be expressed through code structure**

**Documentation & Content Quality** *(Local Changes Focus)*:
- Spelling and grammar in all visible text
- Command examples accuracy and syntax
- Naming consistency across files
- Professional language standards
- Markdown formatting correctness
- Documentation template compliance

**Azure-Specific Concerns**:
- Azure API version compatibility
- Resource naming and tagging conventions
- Location/region handling
- Azure resource dependency management
- Subscription and resource group scoping
- Azure service-specific implementation patterns
- Resource ID parsing and validation

**Terraform Provider Patterns**:
- CRUD operation implementation correctness
- Schema design and nested resource handling
- ForceNew vs in-place update decisions
- CustomizeDiff function usage
- State refresh and conflict resolution
- Resource import state handling
- Documentation and example completeness

---

## 🔍 **VERIFICATION PROTOCOLS FOR LOCAL CHANGES**

**🚨 CRITICAL: VERIFY BEFORE FLAGGING POLICY 🚨**

**MANDATORY VERIFICATION REQUIREMENT**: NEVER flag formatting/encoding issues without verification. Console display artifacts are common and flagging them as critical issues wastes developer time and undermines review credibility.

**⚠️ Console Display Awareness**: Git diff output may wrap long lines. Use `read_file` to verify actual content before flagging display issues.

**Before flagging ANY formatting/encoding issues:**
1. **STOP** - Do not immediately flag suspicious formatting
2. **VERIFY FIRST** - Use read_file to check actual content
3. **ASSESS** - Console wrapping vs genuine issue
4. **RESPOND** - Only flag if genuinely broken after verification

**Zero Tolerance for False Positives**: False positive encoding/formatting flags are review failures that erode trust.

**Additional scope for local changes:**
- Spelling and grammar in visible text content
- Command syntax accuracy and consistency
- Professional standards in user-facing content
- Context quality in surrounding diff lines

---

##  **REVIEW OUTPUT FORMAT**

```markdown
# 📋 **Code Review**: ${change_description}

## 🔄 **CHANGE SUMMARY**
- **Files Changed**: [number] files ([tracked_additions] new tracked, [untracked_files] untracked, [modifications] modified, [deletions] deleted)
- **Line Changes**: [insertions] insertions, [deletions] deletions (tracked files only)
- **Branch**: [current_branch_from_git_command]
- **Type**: [local changes/staged changes/untracked files]
- **Scope**: [Brief description of overall scope]

## 📁 **FILES CHANGED**

**Modified Files:**
- `path/to/modified/file1.go` (+X/-Y lines)
- `path/to/modified/file2.md` (+X/-Y lines)

**Added Files (Tracked):**
- `path/to/new/tracked/file.go` (+X lines)

**Untracked Files (New):**
- `path/to/untracked/file1.ps1` (new file, untracked)
- `path/to/untracked/file2.md` (new file, untracked)

**Deleted Files:**
- `path/to/removed/file.go` (-X lines)

## 🎯 **PRIMARY CHANGES ANALYSIS**

[Overview of the code changes, including the purpose of the implementation, any relevant context about the Azure service or infrastructure changes, and the files involved.]

## 📋 **DETAILED TECHNICAL REVIEW**

### 🔄 **RECURSION PREVENTION**
- **File Skipped**: `.github/prompts/code-review-local-changes.prompt.md` - Cannot review code review prompt itself to prevent infinite loops

### 🔍 **STANDARDS CHECK**
- **PowerShell**: Approved verbs (`Get-`, `Set-`, `New-`, `Test-`), PascalCase
- **Go**: HashiCorp patterns, error handling, naming conventions
- **Terraform**: Resource patterns, schema validation, documentation

### 🟢 **STRENGTHS**
[List positive aspects and well-implemented features]

### 🟡 **OBSERVATIONS**
[List areas for consideration or minor improvements]

### 🔴 **ISSUES** (if any)
[List ONLY actual problems that need to be fixed - bugs, errors, violations, missing requirements, typos, misspellings, improper pointer handling, incorrect SDK usage, using deprecated utilities, etc. Do NOT include observations about what was done correctly or opinions about changes that are already implemented properly]

## ✅ **RECOMMENDATIONS**

### 🎯 **IMMEDIATE**
[Critical actions needed before commit]

### 🔄 **FUTURE CONSIDERATIONS**
[Improvements for future iterations]

## 🏆 **OVERALL ASSESSMENT**
[Final assessment with confidence level]

---

## Individual Comment Format:

## ${🔧/❓/⛏️/♻️/🤔/🚀/ℹ️/📌} ${Review Type}: ${Summary}
* **Priority**: ${🔥/🔴/🟡/🔵/⭐/✅}
* **File**: ${relative/path/to/file}
* **Details**: Clear explanation
* **Azure Context** (if applicable): Service behavior reference
* **Terraform Impact** (if applicable): Configuration/state effects
* **Suggested Change** (if applicable): Code snippet
```

**Priority System:** 🔥 Critical → 🔴 High → 🟡 Medium → 🔵 Low → ⭐ Notable → ✅ Good

**Review Type Emojis:**
* 🔧 Change request - Issues requiring fixes before commit
* ❓ Question - Clarification needed about approach
* ⛏️ Nitpick - Minor style/consistency improvements
* ♻️ Refactor - Structural improvements to consider
* 🤔 Thought - Design concerns for discussion
* 🚀 Positive - Well-implemented features worth noting
* ℹ️ Note - Technical context or information
* 📌 Future - Considerations for later development

---

## 🔍 **GIT DIFF OUTPUT INTERPRETATION**

**In the provided git diff output:**
- **Lines starting with `+`**: Added lines (new code)
- **Lines starting with `-`**: Removed lines (deleted code)
- **Lines starting with ` `** (space): Unchanged lines (context)
- **Lines starting with `@@`**: Hunk headers showing line numbers and context
- **Git stat symbols**:
  - `------------------` (all dashes): File was deleted
  - `++++++++++++++++++` (all pluses): File was added
  - Mixed `+` and `-`: File was modified

**Example git stat interpretation:**
```
file1.go                    |  10 +++++++---
file2.go                    |  25 -------------------------  # DELETED FILE
file3.go                    |  15 +++++++++++++++  # NEW FILE
```

---

# 📚 **LOCAL DEVELOPMENT FOCUS** *(Additional Context)*

**Local changes review emphasizes:**
- **Iterative feedback** for work-in-progress code
- **Development guidance** before commit readiness
- **Verification protocols** to prevent false positives from console display issues
- **Comprehensive scope** including spelling/grammar in visible content
- **Next steps clarity** for continued development

**Key Differences from Committed Changes Review:**
- More detailed verification for display artifacts
- Development-focused output format vs executive summary
- Emphasis on "before commit" actions vs "before merge" decisions
- Broader content quality scope for documentation and examples

---

# 📚 **APPENDIX: EDGE CASE HANDLING** *(Secondary Guidelines)*

## Console Line Wrapping Detection *(If Needed)*

**🚨 CRITICAL: CONSOLE LINE WRAPPING DETECTION POLICY 🚨**

**CONSOLE LINE WRAPPING WARNING**: When reviewing `git` diff output in terminal/console, be aware that long lines may wrap and appear malformed. Always verify actual file content for syntax validation, especially for `JSON`, `YAML`, or structured data files. Console wrapping can make valid syntax appear broken.

**VERIFICATION PROTOCOL FOR SUSPECTED ISSUES**:

🔍 **MANDATORY VERIFICATION STEPS:**
1. **STOP** - If text appears broken/fragmented, this is likely console wrapping
2. **VERIFY** - Use `Get-Content filename` (PowerShell) or `cat filename` (bash) to check actual file content
3. **VALIDATE** - For JSON/structured files: `Get-Content file.json | ConvertFrom-Json` (PowerShell) or `jq "." file.json` (bash)

### 🚨 **Console Wrapping Red Flags:**
- ❌ Text breaks mid-sentence or mid-word without logical reason
- ❌ Missing closing quotes/brackets that don't make sense contextually
- ❌ Fragmented lines that appear to continue elsewhere in the diff
- ❌ Content looks syntactically invalid but conceptually correct
- ❌ Long lines in git diff output that suddenly break

### ✅ **GOLDEN RULE**: If actual file content is valid → acknowledge console wrapping → do NOT flag as corruption

**🚫 COMMON REVIEW FAILURE**:
Flagging console display artifacts as "Critical: Encoding Issue" when actual file content is clean. This exact scenario wastes developer time and erodes review credibility.

**✅ CORRECT APPROACH**:
1. See suspicious formatting in git diff → Use read_file immediately
2. If content is clean → Use ℹ️ with ✅ priority and verification emoji
3. Never flag as 🔥 Critical without confirming actual file corruption

## Verification Protocol *(Edge Cases Only)*

**When to verify:**
- Text breaks mid-word without logical reason
- Missing quotes/brackets that don't make contextual sense
- Emojis appear as `??`
- JSON/YAML looks syntactically broken

**Verification format:**
```markdown
## ℹ️ **Console Display Verification**
* **Priority**: ✅
* **Details**: [What appeared wrong in git diff]
* **Verification**: Used read_file to check actual content
* **Result**: *(Verified: console wrapping - actual content clean)*
* **Assessment**: No action needed - normal console display artifact
```

**🚫 NEVER DO**: Flag encoding/formatting as 🔥 Critical without verification
**✅ ALWAYS DO**: Verify first, then provide appropriate assessment with ✅ emoji if clean

## Review Scope Expansion

**Beyond diff changes, also check:**
- Spelling and grammar in visible text
- Command examples accuracy
- Naming consistency
- Professional language standards

## Comprehensive Quality Guidelines

- **Code Comments Policy**: Comments only for Azure API quirks, complex business logic, or SDK workarounds that cannot be expressed through code structure
- **Comment Quality**: All comments must have clear justification and add genuine value beyond code structure
- **Refactoring Preference**: Consider if code restructuring could eliminate need for comments
- **Documentation Standards**: Ensure all user-facing documentation follows provider conventions and standards
