#!/usr/bin/env bash
# ValidationEngine Module for Terraform AzureRM Provider AI Setup (Bash)
# Handles comprehensive validation, dependency checking, and system requirements
# STREAMLINED VERSION - Contains only functions actually used by main script and dependencies

# Private Functions

# Function to find workspace root by looking for go.mod file
find_workspace_root() {
    local start_path="$1"
    local current_path="${start_path}"
    local max_depth=10
    local depth=0

    # Bash 3.2 compatible while loop (macOS default bash)
    while [ ${depth} -lt ${max_depth} ] && [ -n "${current_path}" ]; do
        # Check for AI dev repo marker (installer directory)
        local installer_path="${current_path}/installer"
        if [[ -d "${installer_path}" ]]; then
            echo "${current_path}"
            return 0
        fi

        # Check for Terraform provider marker (go.mod)
        local go_mod_path="${current_path}/go.mod"
        if [[ -f "${go_mod_path}" ]]; then
            echo "${current_path}"
            return 0
        fi

        # Move to parent directory
        local parent_path=$(dirname "${current_path}")
        if [[ "${parent_path}" == "${current_path}" ]]; then
            # Reached root directory
            break
        fi
        current_path="${parent_path}"
        ((depth++))
    done

    return 1
}

# Function to test bash version (equivalent to PowerShell version test)
test_bash_version() {
    local bash_version="${BASH_VERSION}"
    local version_major=$(echo "${bash_version}" | cut -d. -f1)

    if [[ ${version_major} -ge 3 ]]; then
        echo "Valid=true"
        echo "Version=${bash_version}"
        echo "Reason=Bash version ${bash_version} meets requirements"
    else
        echo "Valid=false"
        echo "Version=${bash_version}"
        echo "Reason=Bash version ${bash_version} is too old. Minimum version 3.2 required"
    fi
}

# Function to test required commands
test_required_commands() {
    local required_commands=("git" "curl" "mkdir" "cp" "rm" "dirname" "realpath")
    local missing_commands=()
    local valid=true

    for cmd in "${required_commands[@]}"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            missing_commands+=("${cmd}")
            valid=false
        fi
    done

    echo "Valid=${valid}"
    if [[ ${valid} == "true" ]]; then
        echo "Reason=All required commands available"
    else
        echo "Reason=Missing commands: ${missing_commands[*]}"
        echo "MissingCommands=${missing_commands[*]}"
    fi
}

# Function to validate repository structure (pure validation logic)
validate_repository() {
    local repo_dir="$1"

    # Check if directory exists
    if [[ ! -d "${repo_dir}" ]]; then
        return 1
    fi

    # Check for terraform-provider-azurerm repository (comprehensive validation)
    local has_go_mod=false
    local has_azurerm_content=false
    local has_main_go=false
    local has_services_dir=false

    # Check for go.mod and its content
    if [[ -f "${repo_dir}/go.mod" ]]; then
        has_go_mod=true
        if grep -q "terraform-provider-azurerm" "${repo_dir}/go.mod" 2>/dev/null; then
            has_azurerm_content=true
        fi
    fi

    # Check for expected structure
    if [[ -f "${repo_dir}/main.go" ]]; then
        has_main_go=true
    fi

    if [[ -d "${repo_dir}/internal/services" ]]; then
        has_services_dir=true
    fi

    # Valid only if we have ALL expected characteristics
    if [[ "${has_go_mod}" == "true" && "${has_azurerm_content}" == "true" &&
          "${has_main_go}" == "true" && "${has_services_dir}" == "true" ]]; then
        return 0
    fi

    return 1
}

# Function to test system requirements (comprehensive version)
test_system_requirements() {
    local bash_result=$(test_bash_version)
    local commands_result=$(test_required_commands)
    local internet_result=""

    # Test internet connectivity
    if test_internet_connectivity; then
        internet_result="Connected=true"$'\n'"Reason=Internet connectivity verified"
    else
        internet_result="Connected=false"$'\n'"Reason=No internet connectivity detected. Check network connection and firewall settings."
    fi

    # Parse results
    local bash_valid=$(echo "${bash_result}" | grep "Valid=" | cut -d= -f2)
    local commands_valid=$(echo "${commands_result}" | grep "Valid=" | cut -d= -f2)
    local internet_connected=$(echo "${internet_result}" | grep "Connected=" | cut -d= -f2)

    # Overall validation
    if [[ "${bash_valid}" == "true" && "${commands_valid}" == "true" && "${internet_connected}" == "true" ]]; then
        echo "OverallValid=true"
    else
        echo "OverallValid=false"
    fi

    echo "Bash=${bash_result}"
    echo "Commands=${commands_result}"
    echo "Internet=${internet_result}"
}

# Function to test system requirements (original version for compatibility)
test_system_requirements_basic() {
    local missing_tools=()

    # Check for curl or wget
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        missing_tools+=("curl or wget")
    fi

    # Check for basic Unix tools
    local required_tools=("bash" "mkdir" "cp" "rm" "dirname" "realpath")
    for tool in "${required_tools[@]}"; do
        if ! command -v "${tool}" >/dev/null 2>&1; then
            missing_tools+=("${tool}")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        write_error_message "Missing required system tools: ${missing_tools[*]}"
        return 1
    fi

    return 0
}

# Function to test Git repository with branch safety checks
test_git_repository() {
    local repo_dir="$1"
    local allow_bootstrap_on_source="${2:-false}"

    # Initialize result variables
    local valid=false
    local is_git_repo=false
    local has_remote=false
    local current_branch="Unknown"
    local is_source_branch=false
    local reason=""

    if [[ ! -d "${repo_dir}/.git" ]]; then
        reason="Not a Git repository: ${repo_dir}"
            write_warning_message "${reason}"
    else
        is_git_repo=true

        # Check if git command is available
        if ! command -v git >/dev/null 2>&1; then
            reason="Git command not available"
            write_warning_message "${reason}"
        else
            # Get current branch
            current_branch=$(cd "${repo_dir}" && git branch --show-current 2>/dev/null || echo "Unknown")

            # Check for remote
            if cd "${repo_dir}" && git remote -v >/dev/null 2>&1; then
                has_remote=true
            fi

            # Check if on source branch (main, master, or exp/terraform_copilot)
            case "${current_branch}" in
                "main"|"master"|"exp/terraform_copilot")
                    is_source_branch=true
                    ;;
            esac

            # Validate based on branch safety rules
            if [[ "${is_source_branch}" == "true" ]] && [[ "${allow_bootstrap_on_source}" != "true" ]]; then
                valid=false
                reason="Cannot install on source branch '${current_branch}' without explicit permission. Use feature branch for safety."
            else
                valid=true
                reason="Git repository validation passed"
            fi
        fi
    fi

    # Output results in a structured format
    echo "Valid=${valid}"
    echo "IsGitRepo=${is_git_repo}"
    echo "HasRemote=${has_remote}"
    echo "CurrentBranch=${current_branch}"
    echo "IsSourceBranch=${is_source_branch}"
    echo "Reason=${reason}"

    [[ "${valid}" == "true" ]]
}

# Function to test workspace validity
test_workspace_valid() {
    local workspace_path="${1:-$(pwd)}"

    # Initialize result variables
    local valid=false
    local is_terraform_provider=false
    local is_azurerm_provider=false
    local is_ai_dev_repo=false
    local workspace_root=""
    local reason=""

    # Find workspace root
    workspace_root=$(find_workspace_root "${workspace_path}")

    if [[ -n "${workspace_root}" ]]; then
        # Check for installer directory (AI development repo)
        local installer_path="${workspace_root}/installer"
        local instructions_path="${workspace_root}/.github/instructions"

        if [[ -d "${installer_path}" && -d "${instructions_path}" ]]; then
            is_ai_dev_repo=true
            valid=true
            reason="Valid AI development repository workspace"

            # Output results and return early
            echo "Valid=${valid}"
            echo "IsTerraformProvider=${is_terraform_provider}"
            echo "IsAzureRMProvider=${is_azurerm_provider}"
            echo "IsAIDevRepo=${is_ai_dev_repo}"
            echo "WorkspaceRoot=${workspace_root}"
            echo "Reason=${reason}"
            return 0
        fi

        # Check if it's a Terraform provider
        if [[ -f "${workspace_root}/main.go" ]] && [[ -d "${workspace_root}/internal" ]]; then
            is_terraform_provider=true

            # Check if it's specifically the AzureRM provider
            if grep -q "terraform-provider-azurerm" "${workspace_root}/go.mod" 2>/dev/null; then
                is_azurerm_provider=true
                valid=true
                reason="Valid AzureRM provider workspace detected"
            else
                reason="Terraform provider detected but not AzureRM provider"
            fi
        else
            reason="Directory contains go.mod but is not a Terraform provider"
        fi
    else
        reason="No workspace root found (missing go.mod)"
    fi

    # Output results in structured format
    echo "Valid=${valid}"
    echo "IsTerraformProvider=${is_terraform_provider}"
    echo "IsAzureRMProvider=${is_azurerm_provider}"
    echo "IsAIDevRepo=${is_ai_dev_repo}"
    echo "WorkspaceRoot=${workspace_root}"
    echo "Reason=${reason}"

    [[ "${valid}" == "true" ]]
}

# Function to run comprehensive pre-installation validation
test_pre_installation() {
    local allow_bootstrap_on_source="${1:-false}"
    local workspace_path="${2:-$(pwd)}"

    # Initialize results
    local overall_valid=true
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Get workspace root for git operations
    local workspace_root=$(find_workspace_root "${workspace_path}")

    # Test Git repository (CRITICAL: check first for branch safety)
    local git_result=""
    if [[ -n "${workspace_root}" ]]; then
        git_result=$(test_git_repository "${workspace_root}" "${allow_bootstrap_on_source}")
    else
        git_result=$(test_git_repository "${workspace_path}" "${allow_bootstrap_on_source}")
    fi

    local git_valid=$(echo "${git_result}" | grep "Valid=" | cut -d= -f2)
    if [[ "${git_valid}" != "true" ]]; then
        overall_valid=false
    fi

    # Test workspace validity
    local workspace_result=$(test_workspace_valid "${workspace_path}")
    local workspace_valid=$(echo "${workspace_result}" | grep "Valid=" | cut -d= -f2)
    if [[ "${workspace_valid}" != "true" ]]; then
        overall_valid=false
    fi

    # Test system requirements
    local system_result=$(test_system_requirements)
    local system_valid=$(echo "${system_result}" | grep "OverallValid=" | cut -d= -f2)
    if [[ "${system_valid}" != "true" ]]; then
        overall_valid=false
    fi

    # Output comprehensive results
    echo "OverallValid=${overall_valid}"
    echo "Timestamp=${timestamp}"
    echo "Git=${git_result}"
    echo "Workspace=${workspace_result}"
    echo "SystemRequirements=${system_result}"

    [[ "${overall_valid}" == "true" ]]
}

# Public Functions

# Function to get workspace root (public wrapper for find_workspace_root)
get_workspace_root() {
    local start_path="${1:-$(pwd)}"
    find_workspace_root "${start_path}"
}

# Function to test internet connectivity
test_internet_connectivity() {
    local test_url="https://raw.githubusercontent.com"

    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL --connect-timeout 10 "${test_url}" >/dev/null 2>&1; then
            return 0
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q --timeout=10 --tries=1 "${test_url}" -O /dev/null 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

# Function to verify AI infrastructure installation
verify_installation() {
    local workspace_root="${1:-$(get_workspace_root)}"

    write_cyan " Workspace Verification"
    print_separator
    echo ""

    local all_good=true
    local manifest_file=""
    # Prefer the manifest shipped with the running installer to avoid using a stale user-profile manifest.
    local module_dir
    module_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local installer_dir
    installer_dir="$(cd "${module_dir}/../.." && pwd)"

    if [[ -f "${installer_dir}/file-manifest.config" ]]; then
        manifest_file="${installer_dir}/file-manifest.config"
    elif [[ -f "${HOME}/.terraform-azurerm-ai-installer/file-manifest.config" ]]; then
        manifest_file="${HOME}/.terraform-azurerm-ai-installer/file-manifest.config"
    else
        write_error_message "Manifest file not found"
        write_plain "Expected one of:"
        write_plain "  ${installer_dir}/file-manifest.config"
        write_plain "  ${HOME}/.terraform-azurerm-ai-installer/file-manifest.config"
        echo ""
        write_plain "TIP: If running from user profile, run bootstrap first:"
        write_plain "  ./install-copilot-setup.sh -bootstrap"
        return 1
    fi

    # Enforce that the local manifest matches the remote manifest.
    # This prevents misleading verification results when the local installer/manifest is stale.
    local branch_for_remote="main"
    if [[ -n "${SOURCE_BRANCH:-}" ]]; then
        branch_for_remote="${SOURCE_BRANCH}"
    fi

    # Contributor local-path workflows explicitly source files from a local working tree and may
    # legitimately diverge from the GitHub manifest. In that case, skip remote manifest validation.
    if [[ "${CONTRIBUTOR}" == "true" ]] && [[ -n "${LOCAL_SOURCE_PATH}" ]]; then
        :
    elif command -v curl >/dev/null 2>&1; then
        local remote_manifest_url="https://raw.githubusercontent.com/WodansSon/terraform-azurerm-ai-assisted-development/${branch_for_remote}/installer/file-manifest.config"

        local local_manifest_content
        local_manifest_content="$(tr -d '\r' < "${manifest_file}" 2>/dev/null || true)"

        local remote_manifest_raw
        local curl_exit

        # Some environments export `SHELLOPTS` with `errexit`, which would cause a failing curl inside
        # command substitution to terminate the script before we can print a warning.
        local errexit_was_set=false
        if [[ "$-" == *e* ]]; then
            errexit_was_set=true
            set +e
        fi

        remote_manifest_raw="$(curl -fsSL --connect-timeout 10 --max-time 20 "${remote_manifest_url}" 2>/dev/null)"
        curl_exit=$?

        if [[ "${errexit_was_set}" == "true" ]]; then
            set -e
        fi

        local remote_manifest_content
        remote_manifest_content="$(printf '%s' "${remote_manifest_raw}" | tr -d '\r')"

        if [[ ${curl_exit} -ne 0 ]] || [[ -z "${remote_manifest_content}" ]]; then
            write_yellow " NOTE: Could not validate remote manifest; continuing verification"
        elif [[ "${local_manifest_content}" != "${remote_manifest_content}" ]]; then
            show_manifest_mismatch_error "${manifest_file}" "${remote_manifest_url}" "$0"
            return 1
        fi
    else
        write_yellow " NOTE: curl not found; skipping remote manifest validation"
    fi

    write_cyan " Using manifest: ${manifest_file}"
    echo ""
    local files_checked=0
    local files_passed=0
    local files_failed=0
    local missing_items=()  # Array to track specific missing files/directories

    # Check main files
    local main_files
    main_files=$(get_manifest_files "MAIN_FILES" "${manifest_file}")
    if [[ $? -eq 0 && -n "${main_files}" ]]; then
        while IFS= read -r file; do
            [[ -z "${file}" ]] && continue
            local full_path="${workspace_root}/${file}"
            files_checked=$((files_checked + 1))
            if [[ -f "${full_path}" ]]; then
                write_green "  [FOUND  ] ${file}"
                files_passed=$((files_passed + 1))
            else
                write_red "  [MISSING] ${file}"
                files_failed=$((files_failed + 1))
                missing_items+=("${file}")
                all_good=false
            fi
        done <<< "${main_files}"
    fi

    # Check instruction files
    local instruction_files
    instruction_files=$(get_manifest_files "INSTRUCTION_FILES" "${manifest_file}")
    if [[ $? -eq 0 && -n "${instruction_files}" ]]; then
        # Check if instructions directory exists
        local instructions_dir="${workspace_root}/.github/instructions"
        files_checked=$((files_checked + 1))
        if [[ -d "${instructions_dir}" ]]; then
            write_green "  [FOUND  ] .github/instructions/"
            files_passed=$((files_passed + 1))

            while IFS= read -r file; do
                [[ -z "${file}" ]] && continue
                local full_path="${workspace_root}/${file}"
                local filename=$(basename "${file}")
                files_checked=$((files_checked + 1))
                if [[ -f "${full_path}" ]]; then
                    write_green "    [FOUND  ] ${filename}"
                    files_passed=$((files_passed + 1))
                else
                    write_red "    [MISSING] ${filename}"
                    files_failed=$((files_failed + 1))
                    missing_items+=("${file}")
                    all_good=false
                fi
            done <<< "${instruction_files}"
        else
            write_red "  [MISSING] .github/instructions/"
            files_failed=$((files_failed + 1))
            missing_items+=(".github/instructions")
            all_good=false
        fi
    fi

    # Check prompt files
    local prompt_files
    prompt_files=$(get_manifest_files "PROMPT_FILES" "${manifest_file}")
    if [[ $? -eq 0 && -n "${prompt_files}" ]]; then
        # Check if prompts directory exists
        local prompts_dir="${workspace_root}/.github/prompts"
        files_checked=$((files_checked + 1))
        if [[ -d "${prompts_dir}" ]]; then
            write_green "  [FOUND  ] .github/prompts/"
            files_passed=$((files_passed + 1))

            while IFS= read -r file; do
                [[ -z "${file}" ]] && continue
                local full_path="${workspace_root}/${file}"
                local filename=$(basename "${file}")
                files_checked=$((files_checked + 1))
                if [[ -f "${full_path}" ]]; then
                    write_green "    [FOUND  ] ${filename}"
                    files_passed=$((files_passed + 1))
                else
                    write_red "    [MISSING] ${filename}"
                    files_failed=$((files_failed + 1))
                    missing_items+=("${file}")
                    all_good=false
                fi
            done <<< "${prompt_files}"
        else
            write_red "  [MISSING] .github/prompts/"
            files_failed=$((files_failed + 1))
            missing_items+=(".github/prompts")
            all_good=false
        fi
    fi

    # Check skill files
    local skill_files
    skill_files=$(get_manifest_files "SKILL_FILES" "${manifest_file}" 2>/dev/null || true)
    if [[ -n "${skill_files}" ]]; then
        # Check if skills directory exists
        local skills_dir="${workspace_root}/.github/skills"
        files_checked=$((files_checked + 1))
        if [[ -d "${skills_dir}" ]]; then
            write_green "  [FOUND  ] .github/skills/"
            files_passed=$((files_passed + 1))

            while IFS= read -r file; do
                [[ -z "${file}" ]] && continue
                local full_path="${workspace_root}/${file}"
                local skill_name
                skill_name=$(basename "$(dirname "${file}")")
                files_checked=$((files_checked + 1))
                if [[ -f "${full_path}" ]]; then
                    write_green "    [FOUND  ] ${skill_name}/SKILL.md"
                    files_passed=$((files_passed + 1))
                else
                    write_red "    [MISSING] ${skill_name}/SKILL.md"
                    files_failed=$((files_failed + 1))
                    missing_items+=("${file}")
                    all_good=false
                fi
            done <<< "${skill_files}"
        else
            write_red "  [MISSING] .github/skills/"
            files_failed=$((files_failed + 1))
            missing_items+=(".github/skills")
            all_good=false
        fi
    fi

    # Check universal files
    local universal_files
    universal_files=$(get_manifest_files "UNIVERSAL_FILES" "${manifest_file}")
    if [[ $? -eq 0 && -n "${universal_files}" ]]; then
        while IFS= read -r file; do
            [[ -z "${file}" ]] && continue
            local full_path="${workspace_root}/${file}"
            local dir_path=$(dirname "${file}")
            local filename=$(basename "${file}")

            # Special handling for .vscode/settings.json
            if [[ "${file}" == ".vscode/settings.json" ]]; then
                files_checked=$((files_checked + 1))
                if [[ -f "${full_path}" ]]; then
                    write_green "  [FOUND  ] .vscode/settings.json"
                    files_passed=$((files_passed + 1))
                else
                    write_red "  [MISSING] .vscode/settings.json"
                    files_failed=$((files_failed + 1))
                    missing_items+=(".vscode/settings.json")
                    all_good=false
                fi
            else
                # Regular file processing
                # Count directory first (like PowerShell does)
                files_checked=$((files_checked + 1))
                if [[ -d "${workspace_root}/${dir_path}" ]]; then
                    write_green "  [FOUND  ] ${dir_path}/"
                    files_passed=$((files_passed + 1))
                else
                    write_red "  [MISSING] ${dir_path}/"
                    files_failed=$((files_failed + 1))
                    missing_items+=("${dir_path}")
                    all_good=false
                fi

                # Count file separately (like PowerShell does)
                files_checked=$((files_checked + 1))
                if [[ -f "${full_path}" ]]; then
                    write_green "    [FOUND  ] ${filename}"
                    files_passed=$((files_passed + 1))
                else
                    write_red "    [MISSING] ${filename}"
                    files_failed=$((files_failed + 1))
                    missing_items+=("${file}")
                    all_good=false
                fi
            fi
        done <<< "${universal_files}"
    fi

    if [[ "${all_good}" == "true" ]]; then
        # Show verification summary using dynamic show_operation_summary
        if declare -f show_operation_summary >/dev/null 2>&1; then
            # Get dynamic branch information
            local current_branch="unknown"
            local branch_type="feature"
            if command -v git >/dev/null 2>&1 && [[ -d "${workspace_root}/.git" ]]; then
                current_branch=$(cd "${workspace_root}" && git branch --show-current 2>/dev/null || echo "unknown")
                # Determine branch type
                local source_branches=("main" "master" "exp/terraform_copilot")
                for branch in "${source_branches[@]}"; do
                    if [[ "$current_branch" == "$branch" ]]; then
                        branch_type="source"
                        break
                    fi
                done
            fi
            local issues_found=0

            # Match PowerShell order: Branch Type, Target Branch, Files Verified, Issues Found, Location
            # Clean branch_type variable to remove any potential line breaks or whitespace
            branch_type=$(echo "${branch_type}" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            show_operation_summary "Verification" "true" "false" \
                "Branch Type: ${branch_type}" \
                "Target Branch: ${current_branch}" \
                "Files Verified: ${files_checked}" \
                "Issues Found: ${issues_found}" \
                "Location: ${workspace_root}"
        fi
    else
        echo ""
        write_red " Some AI infrastructure files are missing!"
        echo ""
        write_yellow " Issues Found:"
        echo ""

        # List specific missing files/directories
        for item in "${missing_items[@]}"; do
            write_red "  - ${item}"
        done
        echo ""
        write_cyan " TIP: To install missing files, run the installer from user profile"

        # Show verification summary using dynamic show_operation_summary
        if declare -f show_operation_summary >/dev/null 2>&1; then
            # Get dynamic branch information
            local current_branch="unknown"
            local branch_type="feature"
            if command -v git >/dev/null 2>&1 && [[ -d "${workspace_root}/.git" ]]; then
                current_branch=$(cd "${workspace_root}" && git branch --show-current 2>/dev/null || echo "unknown")
                # Determine branch type
                local source_branches=("main" "master" "exp/terraform_copilot")
                for branch in "${source_branches[@]}"; do
                    if [[ "$current_branch" == "$branch" ]]; then
                        branch_type="source"
                        break
                    fi
                done
            fi

            local issues_found=${#missing_items[@]}
            # Clean branch_type variable to remove any potential line breaks or whitespace
            branch_type=$(echo "${branch_type}" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            show_operation_summary "Verification" "false" "false" \
                "Branch Type: ${branch_type}" \
                "Target Branch: ${current_branch}" \
                "Files Verified: ${files_checked}" \
                "Issues Found: ${issues_found}" \
                "Location: ${workspace_root}" \
                --next-steps \
                "Run installation if components are missing" \
                "Use -clean option to remove installation if needed"
        else
            echo "Run the installer to restore missing files."
        fi
    fi
}

# Function to test if directory is AI dev repo or Terraform provider repo
test_is_azurerm_provider_repo() {
    local repo_dir="$1"
    local require_provider_repo="${2:-false}"

    # Initialize result variables
    local valid=false
    local is_ai_dev_repo=false
    local is_azurerm_provider=false
    local reason=""

    # Define markers
    local installer_dir="${repo_dir}/installer"
    local instructions_dir="${repo_dir}/.github/instructions"
    local go_mod="${repo_dir}/go.mod"
    local internal_services="${repo_dir}/internal/services"
    local provider_file="${repo_dir}/internal/provider/provider.go"

    # Check if this is the AI development repository
    if [[ -d "${installer_dir}" && -d "${instructions_dir}" ]]; then
        is_ai_dev_repo=true

        # If we require a provider repo, reject AI dev repo
        if [[ "${require_provider_repo}" == "true" ]]; then
            valid=false
            reason="Target directory is the AI development repository, not a Terraform provider repository. Use -repo-directory to point to your terraform-provider-azurerm working copy."
            echo "Valid=${valid}"
            echo "IsAIDevRepo=${is_ai_dev_repo}"
            echo "IsAzureRMProvider=${is_azurerm_provider}"
            echo "Reason=${reason}"
            return
        fi

        valid=true
        echo "Valid=${valid}"
        echo "IsAIDevRepo=${is_ai_dev_repo}"
        echo "IsAzureRMProvider=${is_azurerm_provider}"
        echo "Reason=${reason}"
        return
    fi

    # Check if this is the Terraform AzureRM provider repository
    # Check if go.mod exists
    if [[ ! -f "${go_mod}" ]]; then
        reason="Not a valid repository - missing installer/ and .github/instructions/ directories, or go.mod file"
        echo "Valid=${valid}"
        echo "IsAIDevRepo=${is_ai_dev_repo}"
        echo "IsAzureRMProvider=${is_azurerm_provider}"
        echo "Reason=${reason}"
        return
    fi

    # Read go.mod and check for azurerm provider module
    if grep -q "module github.com/hashicorp/terraform-provider-azurerm" "${go_mod}" 2>/dev/null; then
        is_azurerm_provider=true
    else
        reason="go.mod exists but does not declare terraform-provider-azurerm module"
        echo "Valid=${valid}"
        echo "IsAIDevRepo=${is_ai_dev_repo}"
        echo "IsAzureRMProvider=${is_azurerm_provider}"
        echo "Reason=${reason}"
        return
    fi

    # Check for internal/services directory
    if [[ ! -d "${internal_services}" ]]; then
        reason="Missing internal/services directory structure"
        echo "Valid=${valid}"
        echo "IsAIDevRepo=${is_ai_dev_repo}"
        echo "IsAzureRMProvider=${is_azurerm_provider}"
        echo "Reason=${reason}"
        return
    fi

    # Check for provider file
    if [[ ! -f "${provider_file}" ]]; then
        reason="Missing internal/provider/provider.go file"
        echo "Valid=${valid}"
        echo "IsAIDevRepo=${is_ai_dev_repo}"
        echo "IsAzureRMProvider=${is_azurerm_provider}"
        echo "Reason=${reason}"
        return
    fi

    # All checks passed
    valid=true
    reason="Validated as Terraform AzureRM provider repository"
    echo "Valid=${valid}"
    echo "IsAIDevRepo=${is_ai_dev_repo}"
    echo "IsAzureRMProvider=${is_azurerm_provider}"
    echo "Reason=${reason}"
}

# Export functions for use in other scripts
export -f test_system_requirements validate_repository test_is_azurerm_provider_repo
export -f test_git_repository test_workspace_valid test_internet_connectivity verify_installation
