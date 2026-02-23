#!/usr/bin/env bash
# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

# Main AI Infrastructure Installer for Terraform AzureRM Provider (macOS/Linux)
# Version: see VERSION file
# Description: Interactive installer for AI-powered development tools
# Requires bash 3.2+ (compatible with macOS default bash)

set -euo pipefail

# ============================================================================
# PARAMETER DEFINITIONS
# ============================================================================

# Installer version is centralized in the VERSION file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/VERSION" ]]; then
    VERSION="$(tr -d '\r\n' < "${SCRIPT_DIR}/VERSION")"
else
    VERSION="dev"
fi

# If VERSION is a placeholder (0.0.0) and we're running from a git clone, show a dev build version.
if [[ "${VERSION}" == "0.0.0" ]] && command -v git >/dev/null 2>&1; then
    repo_root="$(cd "${SCRIPT_DIR}/.." && pwd)"
    if [[ -e "${repo_root}/.git" ]]; then
        sha="$(git -C "${repo_root}" rev-parse --short HEAD 2>/dev/null | tr -d '\r\n')"
        if [[ -n "${sha}" ]]; then
            VERSION="dev-${sha}"
            if [[ -n "$(git -C "${repo_root}" status --porcelain 2>/dev/null)" ]]; then
                VERSION="${VERSION}-dirty"
            fi
        fi
    fi
fi

# Global variables
# Note: AI infrastructure files are sourced from a local payload (aii/) by default.

# Command line parameters with help text
BOOTSTRAP=false           # Copy installer to user profile for feature branch use
REPO_DIRECTORY=""         # Path to the repository directory for git operations (when running from user profile)
LOCAL_SOURCE_PATH=""      # Local directory to copy AI files from instead of bundled payload
VERIFY=false              # Check the current state of the workspace
CLEAN=false               # Remove AI infrastructure from the workspace
HELP=false                # Show detailed help information

# Export variables that need to be accessible to modules as global variables
# Note: Other variables are passed as function parameters, so they don't need to be exported

# ============================================================================
# COLOR DEFINITIONS - Required for early error display
# ============================================================================
# These must be defined BEFORE module loading for early validation errors

# ANSI color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color

# ============================================================================
# MODULE LOADING - This must succeed or the script cannot continue
# ============================================================================

# Get script directory with robust detection
get_script_directory() {
    local source="${BASH_SOURCE[0]}"
    while [[ -L "${source}" ]]; do
        local dir="$(cd -P "$(dirname "${source}")" && pwd)"
        source="$(readlink "${source}")"
        [[ ${source} != /* ]] && source="${dir}/${source}"
    done
    echo "$(cd -P "$(dirname "${source}")" && pwd)"
}

get_modules_path() {
    local script_directory="$1"

    # Simple logic: modules are always in the same relative location
    local modules_path="${script_directory}/modules/bash"

    echo "${modules_path}"
}

import_required_modules() {
    local modules_path="$1"

    # Define all required modules in dependency order
    local modules=(
        "configparser"
        "ui"
        "validationengine"
        "fileoperations"
    )

    # Load each module cleanly
    for module in "${modules[@]}"; do
        local module_path="${modules_path}/${module}.sh"

        if [[ ! -f "${module_path}" ]]; then
            echo ""
            echo "============================================================"
            echo "[ERROR] Required module '${module}' not found at: ${module_path}"
            echo ""
            echo "If running from user profile, ensure the release bundle is extracted into your installer directory:"
            echo "  ${HOME}/.terraform-azurerm-ai-installer"
            echo ""
            echo "Run bootstrap from a local git clone:"
            echo "  $0 -bootstrap"
            echo ""
            return 1
        fi

        if ! source "${module_path}"; then
            echo ""
            echo "============================================================"
            echo "[ERROR] Failed to import module '${module}': ${module_path}"
            echo ""
            return 1
        fi
    done

    # Verify critical functions are available
    local required_functions=(
        "write_header"
        "verify_installation"
    )

    for func in "${required_functions[@]}"; do
        if ! command -v "${func}" >/dev/null 2>&1; then
            echo ""
            echo "============================================================"
            echo "[ERROR] Required function '${func}' not available after module loading"
            echo ""
            return 1
        fi
    done

    return 0
}

# Get script directory and load modules
SCRIPT_DIR="$(get_script_directory)"
MODULES_PATH="$(get_modules_path "${SCRIPT_DIR}")"

# Import all required modules or exit with error
if ! import_required_modules "${MODULES_PATH}"; then
    exit 1
fi
# ============================================================================
# WORKSPACE DETECTION - Simple and reliable
# ============================================================================

get_workspace_root() {
    local repo_directory="$1"
    local script_directory="$2"

    # If repo_directory is provided, use it (validation happens later)
    if [[ -n "${repo_directory}" ]]; then
        echo "${repo_directory}"
        return
    fi

    # Otherwise, find workspace root from script location
    local current_path="${script_directory}"
    while [[ -n "${current_path}" && "${current_path}" != "$(dirname "${current_path}")" ]]; do
        # Check for AI dev repo marker (installer directory)
        if [[ -d "${current_path}/installer" ]]; then
            echo "${current_path}"
            return
        fi

        # Check for Terraform provider marker (go.mod)
        if [[ -f "${current_path}/go.mod" ]]; then
            echo "${current_path}"
            return
        fi
        current_path="$(dirname "${current_path}")"
    done

    # If no workspace found, return the directory where the script was called from
    # This allows help and other functions to work, with validation happening separately
    pwd
}

# ============================================================================
# MAIN EXECUTION - Clean and simple
# ============================================================================

main() {
    #
    # Main entry point for the installer - matches PowerShell structure
    #

    # STEP 1: Parse command line arguments first
    parse_arguments "$@"

    # STEP 1.1: -bootstrap must be a standalone operation (no additional flags)
    if [[ "${BOOTSTRAP}" == "true" ]] && { [[ -n "${REPO_DIRECTORY}" ]] || [[ -n "${LOCAL_SOURCE_PATH}" ]] || [[ "${VERIFY}" == "true" ]] || [[ "${CLEAN}" == "true" ]] || [[ "${HELP}" == "true" ]]; }; then
        show_early_validation_error "BootstrapNoArgs" "$0"
        exit 1
    fi

    # STEP 1.62: -bootstrap must be run from a git clone (directory containing .git)
    if [[ "${BOOTSTRAP}" == "true" ]]; then
        local bootstrap_repo_root
        bootstrap_repo_root="$(cd "${SCRIPT_DIR}/.." && pwd)"
        if [[ ! -e "${bootstrap_repo_root}/.git" ]]; then
            show_early_validation_error "BootstrapRequiresGitRepo" "$0" "${bootstrap_repo_root}"
            exit 1
        fi
    fi

    # STEP 1.65: Validate -local-path is not empty (NEW CHECK)
    # Check if LOCAL_SOURCE_PATH was set (even to empty string) and is empty after trimming
    if [[ -z "${LOCAL_SOURCE_PATH}" ]] && [[ "$*" == *"-local-path"* ]]; then
        show_early_validation_error "EmptyLocalPath" "$0"
        exit 1
    fi

    # STEP 1.67: Validate -local-path directory exists (NEW CHECK)
    if [[ -n "${LOCAL_SOURCE_PATH}" ]] && [[ ! -d "${LOCAL_SOURCE_PATH}" ]]; then
        show_early_validation_error "LocalPathNotFound" "$0" "${LOCAL_SOURCE_PATH}"
        exit 1
    fi

    # STEP 2: Show header immediately for consistent user experience
    write_header "Terraform AzureRM Provider - AI Infrastructure Installer" "${VERSION}"

    # STEP 3: Get workspace root and branch information for display and safety checks
    local workspace_root
    workspace_root="$(get_workspace_root "${REPO_DIRECTORY}" "${SCRIPT_DIR}")"

    local current_branch
    if [[ -n "${REPO_DIRECTORY}" ]]; then
        if [[ -d "${workspace_root}/.git" ]]; then
            current_branch=$(cd "${workspace_root}" && git branch --show-current 2>/dev/null || echo "unknown")
        else
            current_branch="unknown"
        fi
    else
        current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    fi

    # STEP 4: Show branch detection immediately after getting branch info
    show_branch_detection "${current_branch}" "${workspace_root}"

    # STEP 4.5: SAFETY CHECK 1 - Block operations targeting AI dev repo when using -repo-directory
    if [[ -n "${REPO_DIRECTORY}" ]] && [[ "${VERIFY}" != "true" ]] && [[ "${HELP}" != "true" ]] && [[ "${BOOTSTRAP}" != "true" ]]; then
        # Quick check: Is target directory the AI dev repo?
        local repo_check_result
        repo_check_result=$(test_is_azurerm_provider_repo "${workspace_root}" "true")

        local repo_valid=$(echo "${repo_check_result}" | grep "^Valid=" | cut -d= -f2)
        local is_ai_dev_repo=$(echo "${repo_check_result}" | grep "^IsAIDevRepo=" | cut -d= -f2)
        local repo_reason=$(echo "${repo_check_result}" | grep "^Reason=" | cut -d= -f2-)

        if [[ "${repo_valid}" != "true" ]] && [[ "${is_ai_dev_repo}" == "true" ]]; then
            echo ""
            echo -e "${CYAN}============================================================${NC}"
            echo -e "${RED} SAFETY VIOLATION: Cannot install into AI Development Repository${NC}"
            echo -e "${CYAN}============================================================${NC}"
            echo ""
            echo -e "${YELLOW} The -repo-directory points to the AI development repository:${NC}"
            echo -e "${CYAN} ${workspace_root}${NC}"
            echo ""
            echo -e "${YELLOW} This repository contains the source files. Use -repo-directory to point${NC}"
            echo -e "${YELLOW} to your terraform-provider-azurerm working copy instead.${NC}"
            echo ""
            echo -e "${GREEN}SOLUTION:${NC}"
            echo -e "${WHITE}  Clone or navigate to your terraform-provider-azurerm repository:${NC}"
            echo -e "${CYAN}    cd \"<path-to-your-terraform-provider-azurerm>\"${NC}"
            echo ""
            echo -e "${WHITE}  Then run the installer from your user profile:${NC}"
            echo -e "${CYAN}    cd \"${HOME}/.terraform-azurerm-ai-installer\"${NC}"
            echo -e "${CYAN}    ./install-copilot-setup.sh -repo-directory \"<path-to-your-terraform-provider-azurerm>\"${NC}"
            echo ""
            exit 1
        fi
    fi

    # STEP 5: SAFETY CHECK 2 - Early safety check - fail fast if on source branch with repo directory
    if [[ -n "${REPO_DIRECTORY}" ]]; then
        # Block operations on source branch immediately (except verify, help, bootstrap)
        # Source branches: main, master
        local source_branches=("main" "master")
        local is_source_branch=false
        for branch in "${source_branches[@]}"; do
            if [[ "${current_branch}" == "${branch}" ]]; then
                is_source_branch=true
                break
            fi
        done

        if [[ "${is_source_branch}" == "true" ]] && [[ "${VERIFY}" != "true" ]] && [[ "${HELP}" != "true" ]] && [[ "${BOOTSTRAP}" != "true" ]]; then
            # Safety violation - header and branch detection already shown above
            show_safety_violation "${current_branch}" "Install" "true"
            exit 1
        fi
    fi

    # STEP 6: Initialize workspace validation (workspace_root already set above)
    local workspace_valid workspace_reason
    local workspace_validation_result=$(test_workspace_valid "${workspace_root}")
    workspace_valid=$(echo "${workspace_validation_result}" | grep "Valid=" | cut -d= -f2)
    workspace_reason=$(echo "${workspace_validation_result}" | grep "Reason=" | cut -d= -f2)

    # Default to false if parsing failed
    if [[ -z "${workspace_valid}" ]]; then
        workspace_valid=false
        workspace_reason="Workspace validation failed"
    fi

    # STEP 7: Determine branch type - be explicit about what we know vs don't know
    local branch_type
    case "${current_branch}" in
        "main"|"master")
            branch_type="source"
            ;;
        "unknown"|"")
            branch_type="unknown"
            ;;
        *)
            # Any other valid branch name is a feature branch
            branch_type="feature"
            ;;
    esac

    # STEP 8: Detect what command was attempted (for better error messages)
    local attempted_command=""
    if [[ "${BOOTSTRAP}" == "true" ]]; then
        attempted_command="-bootstrap"
    elif [[ "${VERIFY}" == "true" ]]; then
        attempted_command="-verify"
    elif [[ "${CLEAN}" == "true" ]]; then
        attempted_command="-clean"
    elif [[ "${HELP}" == "true" ]]; then
        attempted_command="-help"
    elif [[ -n "${LOCAL_SOURCE_PATH}" ]]; then
        attempted_command="-local-path \"${LOCAL_SOURCE_PATH}\""
    elif [[ -n "${REPO_DIRECTORY}" && "${HELP}" != "true" && "${VERIFY}" != "true" && "${BOOTSTRAP}" != "true" && "${CLEAN}" != "true" ]]; then
        attempted_command="-repo-directory \"${REPO_DIRECTORY}\""
    fi

    # Export context for downstream modules and summaries
    export INSTALLER_DIR="${SCRIPT_DIR}"
    export INSTALLER_ATTEMPTED_COMMAND="${attempted_command}"
    export INSTALLER_COMMAND_LINE="$0 $*"

    # STEP 9: Simple parameter handling (like PowerShell)
    if [[ "${HELP}" == "true" ]]; then
        show_usage "${branch_type}" "${workspace_valid}" "${workspace_reason}" "${attempted_command}"
        exit 0
    fi

    # STEP 10: Check if any actual operation was requested
    local operation_requested=false
    if [[ "${VERIFY}" == "true" ]] || [[ "${BOOTSTRAP}" == "true" ]] || [[ "${CLEAN}" == "true" ]] || [[ -n "${REPO_DIRECTORY}" ]]; then
        operation_requested=true
    fi

    # STEP 11: For operations that require workspace, validate it
    if [[ "${operation_requested}" == "true" ]] && [[ "${workspace_valid}" != "true" ]]; then
        show_workspace_validation_error "${workspace_reason}" "$([[ -n "${REPO_DIRECTORY}" ]] && echo "true" || echo "false")"

        # Show help menu for guidance
        show_usage "${branch_type}" "false" "${workspace_reason}" "${attempted_command}"
        exit 1
    fi

    if [[ "${VERIFY}" == "true" ]] || ([[ -n "${REPO_DIRECTORY}" ]] && [[ "${HELP}" != "true" ]] && [[ "${BOOTSTRAP}" != "true" ]] && [[ "${CLEAN}" != "true" ]]); then
        if ! verify_installer_checksum "${SCRIPT_DIR}"; then
            exit 1
        fi
    fi

    # STEP 12: Execute single operation based on parameters (like PowerShell)
    if [[ "${VERIFY}" == "true" ]]; then
        verify_installation "${workspace_root}"
        exit 0
    fi

    if [[ "${BOOTSTRAP}" == "true" ]]; then
        # Show operation title (main header already displayed)
        write_section "Bootstrap - Copying Installer to User Profile"

        local bootstrap_script_dir="${SCRIPT_DIR}"
        local bootstrap_manifest_file="${SCRIPT_DIR}/file-manifest.config"

        # Execute the bootstrap operation with built-in validation
        if bootstrap_files_to_profile "$(pwd)" "$(get_user_profile)" "${bootstrap_manifest_file}" "${current_branch}" "${branch_type}" "${bootstrap_script_dir}"; then
            # Show detailed summary with next steps
            local user_profile
            user_profile=$(get_user_profile)
            local size_kb=$((BOOTSTRAP_STATS_TOTAL_SIZE / 1024))
            show_operation_summary "Bootstrap" "true" "false" \
                "Installer Files Copied:${BOOTSTRAP_STATS_FILES_COPIED}" \
                "Payload Files Copied (aii/):${BOOTSTRAP_STATS_PAYLOAD_FILES_COPIED:-0}" \
                "Total Size (installer + payload):${size_kb} KB" \
                "Location:${user_profile}" \
                --next-steps \
                " 1. In your terraform-provider-azurerm working copy, switch to a feature branch:" \
                "    git checkout -b feature/your-branch-name" \
                "" \
                " 2. Run the installer from your user profile:" \
                "    cd ~/.terraform-azurerm-ai-installer" \
                "    ./install-copilot-setup.sh -repo-directory \"<path-to-your-terraform-provider-azurerm>\""

            # Show welcome message after successful bootstrap
            show_source_branch_welcome "${current_branch}"
        else
            exit 1
        fi
        exit 0
    fi

    if [[ "${CLEAN}" == "true" ]]; then
        clean_infrastructure "${workspace_root}" "${current_branch}" "${branch_type}"
        exit 0
    fi

    # STEP 13: Installation path (when -repo-directory is provided and not other specific operations)
    if [[ -n "${REPO_DIRECTORY}" ]] && [[ "${HELP}" != "true" ]] && [[ "${VERIFY}" != "true" ]] && [[ "${BOOTSTRAP}" != "true" ]] && [[ "${CLEAN}" != "true" ]]; then
        # Proceed with installation
        install_infrastructure "${workspace_root}" "${current_branch}" "${branch_type}" "${LOCAL_SOURCE_PATH}"
        exit 0
    fi

    # STEP 14: Default - show help with workspace context (matches PowerShell behavior)
    show_usage "${branch_type}" "${workspace_valid}" "${workspace_reason}" "${attempted_command}"
    exit 0
}

# ============================================================================
# COMMAND LINE ARGUMENT PROCESSING
# ============================================================================

check_typos() {
    local param="$1"
    local suggestion=""

    # Handle bare dash edge case
    if [[ "${param}" == "-" ]] || [[ "${param}" == "--" ]]; then
        printf " \033[31mError:\033[0m\033[36m Failed to parse command-line argument:\033[0m\n"
        printf " \033[36mArgument provided but not defined:\033[0m \033[33m${param}\033[0m\n"
        echo ""
        printf " \033[36mFor more help on using this command, run:\033[0m\n"
        printf "   \033[37m$0 -help\033[0m\n"
        echo ""
        exit 1
    fi

    # Remove leading dashes and convert to lowercase
    local clean_param="${param#-}"
    clean_param="${clean_param#-}"
    local lower_param="$(echo "${clean_param}" | tr '[:upper:]' '[:lower:]')"

    # Direct prefix matching (higher priority)
    if echo "${lower_param}" | grep -q '^cl'; then
        suggestion="clean"
    elif echo "${lower_param}" | grep -q '^bo'; then
        suggestion="bootstrap"
    elif echo "${lower_param}" | grep -q '^ve'; then
        suggestion="verify"
    elif echo "${lower_param}" | grep -q '^he'; then
        suggestion="help"
    elif echo "${lower_param}" | grep -q '^re'; then
        suggestion="repo-directory"
    elif echo "${lower_param}" | grep -q '^lo'; then
        suggestion="local-path"
    # Fuzzy matching (lower priority)
    elif [[ "${lower_param}" == *cle* ]]; then
        suggestion="clean"
    elif [[ "${lower_param}" == *boo* ]]; then
        suggestion="bootstrap"
    elif [[ "${lower_param}" == *ver* ]]; then
        suggestion="verify"
    elif [[ "${lower_param}" == *hel* ]]; then
        suggestion="help"
    elif [[ "${lower_param}" == *repo* ]]; then
        suggestion="repo-directory"
    elif [[ "${lower_param}" == *local* ]]; then
        suggestion="local-path"
    elif [[ "${lower_param}" == *source* ]]; then
        suggestion="local-path"
    fi

    if [[ -n "${suggestion}" ]]; then
        printf " \033[31mError:\033[0m\033[36m Failed to parse command-line argument:\033[0m\n"
        printf " \033[36mArgument provided but not defined:\033[0m \033[33m${param}\033[0m\n"
        printf " \033[36mDid you mean:\033[0m \033[32m-${suggestion}\033[0m\033[36m?\033[0m\n"
        echo ""
        printf " \033[36mFor more help on using this command, run:\033[0m\n"
        printf "   \033[37m$0 -help\033[0m\n"
        echo ""
        exit 1
    fi
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -bootstrap)
                BOOTSTRAP=true
                shift
                ;;
            -repo-directory)
                if [[ $# -lt 2 ]] || [[ "${2:-}" == -* ]]; then
                    write_error_message " Option -repo-directory requires a directory path"
                    exit 1
                fi
                REPO_DIRECTORY="$2"
                shift 2
                ;;
            -local-path)
                if [[ $# -lt 2 ]] || [[ "${2:-}" == -* ]]; then
                    write_error_message " Option -local-path requires a directory path"
                    exit 1
                fi
                LOCAL_SOURCE_PATH="$2"
                shift 2
                ;;
            -verify)
                VERIFY=true
                shift
                ;;
            -clean)
                CLEAN=true
                shift
                ;;
            -help)
                HELP=true
                shift
                ;;
            *)
                # Check for typos before showing generic error
                if [[ "$1" == -* ]]; then
                    check_typos "$1"
                fi

                printf " \033[31mError:\033[0m\033[36m Failed to parse command-line argument:\033[0m\n"
                printf " \033[36mUnknown option:\033[0m \033[33m$1\033[0m\n"
                echo ""
                printf " \033[36mFor more help on using this command, run:\033[0m\n"
                printf "   \033[37m$0 -help\033[0m\n"
                echo ""
                exit 1
                ;;
        esac
    done
}

# ============================================================================
# SCRIPT EXECUTION
# ============================================================================

# Run main function with all arguments - single entry point like PowerShell
main "$@"
