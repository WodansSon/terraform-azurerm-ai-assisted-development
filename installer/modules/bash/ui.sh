#!/usr/bin/env bash
# UI Module for Terraform AzureRM Provider AI Setup (Bash)
# STREAMLINED VERSION - Contains only functions actually used by main script and dependencies

# ============================================================================
# Module Configuration
# ============================================================================
_ui_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_installer_root="$(cd "${_ui_dir}/../.." && pwd)"
if [[ -f "${_installer_root}/VERSION" ]]; then
    INSTALLER_VERSION="$(tr -d '\r\n' < "${_installer_root}/VERSION")"
else
    INSTALLER_VERSION="dev"
fi
DEFAULT_VERSION="${INSTALLER_VERSION}"
unset _ui_dir
unset _installer_root

# Color definitions with cross-platform compatibility
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    # Terminal supports colors
    export RED='\033[0;31m'
    export GREEN='\033[0;32m'
    export YELLOW='\033[1;33m'
    export BLUE='\033[0;34m'
    export CYAN='\033[0;36m'
    export GRAY='\033[0;37m'
    export WHITE='\033[1;37m'
    export BOLD='\033[1m'
    export NC='\033[0m' # No Color
else
    # No color support (pipes, non-interactive, etc.)
    export RED=''
    export GREEN=''
    export YELLOW=''
    export BLUE=''
    export CYAN=''
    export GRAY=''
    export WHITE=''
    export BOLD=''
    export NC=''
fi

# Global workspace root variable for UI consistency
WORKSPACE_ROOT=""

# Color helper functions for consistent output
write_cyan() {
    local message="$1"
    echo -e "${CYAN}${message}${NC}"
}

write_dark_cyan() {
    local message="$1"
    echo -e "\033[36m${message}${NC}"
}

write_green() {
    local message="$1"
    echo -e "${GREEN}${message}${NC}"
}

write_yellow() {
    local message="$1"
    echo -e "${YELLOW}${message}${NC}"
}

write_white() {
    local message="$1"
    echo -e "${WHITE}${message}${NC}"
}

write_red() {
    local message="$1"
    echo -e "${RED}${message}${NC}"
}

# ============================================================================
# Early Validation Error Display (Centralized)
# ============================================================================
# Matches PowerShell Show-EarlyValidationError function
# Purpose: Provide clear, actionable error messages for parameter validation failures
# Called BEFORE showing main header to fail fast on invalid parameters
show_early_validation_error() {
    local error_type="$1"
    local script_name="${2:-$0}"

    # Always show error header first in cyan
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN} Terraform AzureRM Provider - AI Infrastructure Installer${NC}"
    echo -e "${CYAN} Version: ${VERSION:-${INSTALLER_VERSION}}${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""

    case "${error_type}" in
        "BootstrapNoArgs")
            echo -e "${RED} Error:${NC}${CYAN} -bootstrap does not accept any other parameters${NC}"
            echo ""
            echo -e "${CYAN} Run bootstrap from a local git clone (no other flags):${NC}"
            echo -e "   ${WHITE}${script_name} -bootstrap${NC}"
            ;;

        "BootstrapRequiresGitRepo")
            local path="$3"
            echo -e "${RED} Error:${NC}${CYAN} -bootstrap must be run from a git clone (directory containing .git)${NC}"
            echo ""
            if [[ -n "${path}" ]]; then
                echo -e "${CYAN} Checked path: ${WHITE}${path}${NC}"
                echo ""
            fi
            echo -e "${CYAN} -bootstrap is for contributors working on this repo. It is not supported from a release bundle or user-profile copy.${NC}"
            ;;

        "EmptyLocalPath")
            echo -e "${RED} Error:${NC}${CYAN} -local-path parameter cannot be empty${NC}"
            echo ""
            echo -e "${CYAN} Please provide a valid local directory path:${NC}"
            echo -e "   ${WHITE}-local-path \"/path/to/terraform-azurerm-ai-assisted-development\"${NC}"
            ;;

        "EmptyRepoDirectory")
            echo -e "${RED} Error:${NC}${CYAN} -repo-directory parameter cannot be empty${NC}"
            echo ""
            echo -e "${CYAN} Please provide the path to your terraform-provider-azurerm working copy:${NC}"
            echo -e "   ${WHITE}-repo-directory \"/path/to/terraform-provider-azurerm\"${NC}"
            ;;

        "LocalPathNotFound")
            local path="$3"
            echo -e "${RED} Error:${NC}${CYAN} -local-path directory does not exist${NC}"
            echo ""
            echo -e "${CYAN} Specified path: ${WHITE}${path}${NC}"
            echo ""
            echo -e "${CYAN} Please verify the directory path exists:${NC}"
            echo -e "   ${WHITE}-local-path \"/path/to/terraform-azurerm-ai-assisted-development\"${NC}"
            ;;

        "RepoDirectoryNotFound")
            local path="$3"
            echo -e "${RED} Error:${NC}${CYAN} -repo-directory path does not exist${NC}"
            echo ""
            echo -e "${CYAN} Specified path: ${WHITE}${path}${NC}"
            echo ""
            echo -e "${CYAN} Please provide the path to your terraform-provider-azurerm working copy:${NC}"
            echo -e "   ${WHITE}-repo-directory \"/path/to/terraform-provider-azurerm\"${NC}"
            echo ""
            echo -e "${CYAN} Tip: on WSL, Windows paths are typically under ${WHITE}/mnt/<drive>/${NC}"
            ;;

        *)
            echo -e "${RED} Error:${NC}${CYAN} Unknown validation error type: ${error_type}${NC}"
            ;;
    esac

    echo ""
    echo -e "${CYAN} For more help, run:${NC}"
    echo -e "   ${WHITE}${script_name} -help${NC}"
    echo ""
}

# Helper functions for common label patterns
write_label() {
    local label="$1"
    local value="$2"
    echo -e "${CYAN}${label}: ${NC}${value}"
}

write_colored_label() {
    local label="$1"
    local value="$2"
    local value_color="$3"
    echo -e "${CYAN}${label}: ${value_color}${value}${NC}"
}

write_section_header() {
    local header="$1"
    echo -e "${CYAN}${header}:${NC}"
}

write_file_operation_status() {
    local operation="$1"
    local filename="$2"
    local status="$3"

    case "${status}" in
        "OK"|"SUCCESS")
            echo -e "   ${CYAN}${operation}: ${NC}${filename} ${GREEN}[OK]${NC}"
            ;;
        "FAILED"|"ERROR")
            echo -e "   ${CYAN}${operation}: ${NC}${filename} ${RED}[FAILED]${NC}"
            ;;
        "SKIPPED"|"EXISTS")
            echo -e "   ${CYAN}${operation}: ${NC}${filename} ${YELLOW}[SKIPPED]${NC}"
            ;;
        *)
            echo -e "   ${CYAN}${operation}: ${NC}${filename} [${status}]"
            ;;
    esac
}

# Function to show operation summary (generic function for all operations - matches PowerShell Show-OperationSummary)
show_operation_summary() {
    local operation_name="$1"
    local success="$2"
    shift 2

    # Parse arguments for details (bash 3.2 compatible)
    # NOTE: NEXT STEPS are rendered by write_next_steps_block at call sites.
    local details_keys=""
    local details_values=""
    local longest_key=""

    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "--next-steps" ]]; then
            break
        fi

        if echo "$1" | grep -q '^[^:]\+:[[:space:]]*.\+$'; then
            local key="$(echo "$1" | sed 's/^\([^:]\+\):[[:space:]]*.\+$/\1/')"  # Preserve spaces in key names
            local value="$(echo "$1" | sed 's/^[^:]\+:[[:space:]]*\(.\+\)$/\1/')"

            if [[ -n "$details_keys" ]]; then
                details_keys="${details_keys}|${key}"
                details_values="${details_values}|${value}"
            else
                details_keys="${key}"
                details_values="${value}"
            fi

            if [[ ${#key} -gt ${#longest_key} ]]; then
                longest_key="$key"
            fi
        fi

        shift
    done

    # Show operation completion with consistent formatting
    local status_text
    if [[ "$success" == "true" ]]; then
        status_text="completed successfully"
        color="${GREEN}"
    else
        status_text="failed"
        color="${RED}"
    fi

    local completion_message=" ${operation_name} ${status_text}"

    echo ""
    echo -e "${color}${completion_message}${NC}"

    # Display details if any exist
    if [[ -n "$details_keys" ]]; then
        # Summary section (self-spacing block header)
        write_block_header "$(echo "${operation_name}" | tr '[:lower:]' '[:upper:]') SUMMARY:"
        echo ""
        write_section_header "DETAILS"

        # Split the keys and values for processing
        local IFS='|'
        set -- $details_keys
        local keys=("$@")
        set -- $details_values
        local values=("$@")

        # Reset IFS
        IFS=' '

        # Display each detail with consistent alignment
        local i=0
        while [[ $i -lt ${#keys[@]} ]]; do
            local key="${keys[$i]}"
            local value="${values[$i]}"

            # Calculate required spacing for alignment
            local label_length=${#key}
            local longest_length=${#longest_key}
            local required_width=$((longest_length - label_length))

            if [[ ${required_width} -lt 0 ]]; then
                required_width=0
            fi

            # Write key with consistent formatting and proper spacing
            printf "  ${CYAN} %s%*s :${NC} " "${key}" ${required_width} ""

            # Determine value color based on content
            if echo "$value" | grep -q '^[0-9]\+$' || echo "$value" | grep -q '^[0-9]\+\(\.[0-9]\+\)\?[[:space:]]*\(KB\|MB\|GB\|TB\|B\)$'; then
                # Numbers and file sizes in green
                write_green "${value}"
            else
                # Text values in yellow
                write_yellow "${value}"
            fi

            i=$((i + 1))
        done
    fi

    # No trailing blank line; callers control spacing by using self-spacing blocks.
}

# Helper function to print colored separator line
print_separator() {
    local length="${1:-60}"
    local color="${2:-${CYAN}}"
    local character="${3:-=}"

    printf "${color}"
    for ((i=1; i<=length; i++)); do
        printf "${character}"
    done
    printf "${NC}\n"
}

# Function to display a self-spacing block header (separator/title/separator)
# Starts with a leading blank line to avoid "sticking" to previous output.
write_block_header() {
    local title="$1"
    local length="${2:-60}"

    echo ""
    print_separator "${length}" "${CYAN}" "="
    write_cyan " ${title}"
    print_separator "${length}" "${CYAN}" "="
}

# Function to display a standardized NEXT STEPS block
# - Always starts with a leading blank line
# - No blank line between header and first step
# - Ensures each step starts with two spaces unless already indented
write_next_steps_block() {
    if [[ $# -le 0 ]]; then
        return 0
    fi

    echo ""
    write_cyan "NEXT STEPS:"

    local has_numbered=false
    local step

    for step in "$@"; do
        [[ -z "${step}" ]] && continue
        if echo "${step}" | grep -Eq '^[[:space:]]*[0-9]+[\.|\)]\s'; then
            has_numbered=true
            break
        fi
    done

    local printed_first_numbered=false
    for step in "$@"; do
        [[ -z "${step}" ]] && continue

        if [[ "${has_numbered}" == "true" ]] && echo "${step}" | grep -Eq '^[[:space:]]*[0-9]+[\.|\)]\s'; then
            if [[ "${printed_first_numbered}" == "true" ]]; then
                echo ""
            fi
            printed_first_numbered=true
        fi

        if echo "${step}" | grep -q '^[[:space:]]'; then
            write_plain "${step}"
        else
            write_plain "  ${step}"
        fi
    done
}

# Function to display a standardized issues list block
# - Always starts with a leading blank line
# - No blank line between header and first item
# - Items printed as "  - <item>" in red
write_issues_block() {
    if [[ $# -le 0 ]]; then
        return 0
    fi

    echo ""
    write_yellow " Issues Found:"

    local issue
    for issue in "$@"; do
        [[ -z "${issue}" ]] && continue
        write_red "  - ${issue}"
    done
}

# Function to display main application header
write_header() {
    local title="${1:-Terraform AzureRM Provider - AI Infrastructure Installer}"
    local version="${2:-$DEFAULT_VERSION}"

    echo ""
    print_separator
    write_cyan " ${title}"
    write_cyan " Version: ${version}"
    print_separator
    echo ""
}

# Function to format aligned labels with proper spacing
format_aligned_label() {
    local label="$1"
    local longest_label="$2"

    # Calculate required spacing for alignment (PowerShell style)
    local label_length=${#label}
    local longest_length=${#longest_label}
    local required_width=$((longest_length - label_length))

    if [[ ${required_width} -lt 0 ]]; then
        required_width=0
    fi

    # Return with leading space and trailing spaces to match PowerShell format
    printf " %s%*s " "${label}" ${required_width} ""
}

# Function to display branch detection with type-based formatting
show_branch_detection() {
    local branch_name="${1:-Unknown}"
    local workspace_root="${2:-}"

    # Set global for consistency across UI functions
    WORKSPACE_ROOT="${workspace_root}"

    # Determine branch label based on type
    local branch_label
    case "${branch_name}" in
        "main"|"master")
            branch_label="SOURCE BRANCH DETECTED"
            ;;
        "unknown"|"Unknown")
            branch_label="BRANCH DETECTED"
            ;;
        *)
            branch_label="FEATURE BRANCH DETECTED"
            ;;
    esac

    # Use the longest possible label for alignment
    local longest_label="FEATURE BRANCH DETECTED"

    # Calculate spacing for branch label
    local branch_label_length=${#branch_label}
    local longest_length=${#longest_label}
    local branch_required_width=$((longest_length - branch_label_length))
    if [[ ${branch_required_width} -lt 0 ]]; then
        branch_required_width=0
    fi

    # Display branch information with consistent alignment
    printf "${CYAN} %s%*s : ${NC}${YELLOW}%s${NC}\n" "${branch_label}" ${branch_required_width} "" "${branch_name}"

    # Dynamic workspace label with proper alignment and colors
    if [[ -n "${workspace_root}" ]]; then
        local workspace_label="WORKSPACE"
        local workspace_label_length=${#workspace_label}
        local workspace_required_width=$((longest_length - workspace_label_length))
        if [[ ${workspace_required_width} -lt 0 ]]; then
            workspace_required_width=0
        fi

        printf "${CYAN} %s%*s : ${NC}${GREEN}%s${NC}\n" "${workspace_label}" ${workspace_required_width} "" "${workspace_root}"
    fi

    echo ""
    print_separator
}

# Function to display section headers
write_section() {
    local section_title="$1"
    write_cyan " ${section_title}"
    print_separator
    echo ""
}

# Function to display error messages
write_error_message() {
    local message="$1"
    echo -e "${RED} ${message}${NC}" >&2
}

# Function to display warning messages
write_warning_message() {
    local message="$1"
    echo -e "${YELLOW}${message}${NC}"
}

# Function to display success messages
write_success_message() {
    local message="$1"
    echo -e "${GREEN}${message}${NC}"
}

# Function to get user profile directory

# Function to get user profile directory
get_user_profile() {
    # Return the full expanded path (not using ~ shorthand) to match PowerShell behavio
    local expanded_home
    expanded_home="${HOME:-/home/$(whoami)}"
    echo "${expanded_home}/.terraform-azurerm-ai-installer"
}

# Function to write operation status with consistent formatting
write_operation_status() {
    local message="$1"
    local status="${2:-Info}"

    case "$status" in
        "Success")
            echo -e "${GREEN} [SUCCESS] ${message}${NC}"
            ;;
        "Warning")
            echo -e "${YELLOW} [WARNING] ${message}${NC}"
            ;;
        "Error")
            echo -e "${RED} [ERROR] ${message}${NC}" >&2
            ;;
        "Info"|*)
            echo -e "${BLUE} [INFO] ${message}${NC}"
            ;;
    esac
}

# Function to format aligned label spacing (for consistent alignment)
format_aligned_label_spacing() {
    local label="$1"
    local reference_label="$2"

    # Calculate spacing needed to align labels
    local label_len=${#label}
    local ref_len=${#reference_label}
    local spaces_needed=$((ref_len - label_len))

    if [[ $spaces_needed -gt 0 ]]; then
        printf "%*s" $spaces_needed ""
    fi
}

# Function to show percentage completion
show_completion() {
    local current="$1"
    local total="$2"
    local description="$3"

    local percentage=$(( (current * 100) / total ))

    printf "${BLUE}[%3d%%]${NC} %s\n" "${percentage}" "${description}"
}

# Function to calculate maximum filename length for dynamic spacing (matches PowerShell)
calculate_max_filename_length() {
    local max_length=0

    for filename in "$@"; do
        local length=${#filename}
        if [[ $length -gt $max_length ]]; then
            max_length=$length
        fi
    done

    echo $max_length
}

# Function to display file operation status
# Function to display file operations (enhanced to match PowerShell output with dynamic padding)
show_file_operation() {
    local operation="$1"
    local filename="$2"
    local status="$3"
    local max_length="$4"  # Required parameter - no default to ensure dynamic calculation

    # Align filename to match PowerShell format using dynamic length
    local formatted_filename
    formatted_filename=$(printf "%-${max_length}s" "${filename}")

    case "${status}" in
        "OK"|"SUCCESS")
            write_file_operation_status "${operation}" "${formatted_filename}" "OK"
            ;;
        "FAILED"|"ERROR")
            write_file_operation_status "${operation}" "${formatted_filename}" "FAILED"
            ;;
        "SKIPPED"|"EXISTS")
            write_file_operation_status "${operation}" "${formatted_filename}" "SKIPPED"
            ;;
        *)
            echo -e "   ${CYAN}${operation}: ${NC}${formatted_filename} [${status}]"
            ;;
    esac
}

# Function to display error block with solutions
show_error_block() {
    local issue="$1"
    local solutions_str="$2"
    local example_usage="${3:-}"
    local additional_info="${4:-}"

    echo ""
    write_red "ISSUE:"
    write_plain "  ${issue}"
    echo ""

    if [[ -n "${solutions_str}" ]]; then
        write_yellow "SOLUTIONS:"
        # Split solutions by semicolon and display each
        IFS=';' read -ra solutions_array <<< "${solutions_str}"
        for solution in "${solutions_array[@]}"; do
            solution="${solution# }"  # Remove leading space
            write_plain "  - ${solution}"
        done
        echo ""
    fi

    if [[ -n "${example_usage}" ]]; then
        write_green "EXAMPLE:"
        write_plain "  ${example_usage}"
        echo ""
    fi

    if [[ -n "${additional_info}" ]]; then
        write_cyan "ADDITIONAL INFO:"
        write_plain "  ${additional_info}"
        echo ""
    fi
}

# Function to show repository information
show_repository_info() {
    local directory="$1"

    write_plain "Repository Directory: ${directory}"

    # Try to get git branch if available
    if command -v git >/dev/null 2>&1 && [[ -d "${directory}/.git" ]]; then
        local branch
        branch=$(cd "${directory}" && git branch --show-current 2>/dev/null || echo "unknown")
        write_plain "Current Branch: ${branch}"
    fi
}

# Function to display completion summary (enhanced to match PowerShell quality)
show_completion_summary() {
    local operation="$1"
    local files_processed="$2"
    local files_succeeded="$3"
    local files_failed="${4:-0}"
    local total_size="${5:-}"
    local install_location="${6:-}"
    local branch_name="${7:-}"
    local branch_type="${8:-feature}"

    echo ""
    write_green "INSTALLATION COMPLETE"
    print_separator 40 "${GREEN}" "="
    echo ""

    # Show branch information if provided
    if [[ -n "${branch_name}" ]]; then
        show_branch_detection "${branch_name}" "${branch_type}"
        echo ""
    fi

    # Show summary statistics
    write_cyan "SUMMARY:"
    write_label "  Files copied" "${files_succeeded}"
    if [[ "${files_failed}" -gt 0 ]]; then
        write_colored_label "  Files failed" "${files_failed}" "${RED}"
    fi
    if [[ -n "${total_size}" ]]; then
        write_label "  Total size" "${total_size}"
    fi
    if [[ -n "${install_location}" ]]; then
        write_label "  Location" "${install_location}"
    fi
    echo ""
}

# Function to show key-value pairs
show_key_value() {
    local key="$1"
    local value="$2"
    write_label "${key}" "${value}"
}

# Function to show next steps (matches PowerShell formatting)
show_next_steps() {
    local steps=("$@")

    if [[ ${#steps[@]} -gt 0 ]]; then
        local formatted_steps=()
        for i in "${!steps[@]}"; do
            local step_num=$((i + 1))
            formatted_steps+=("${step_num}. ${steps[i]}")
        done

        write_next_steps_block "${formatted_steps[@]}"
    fi
}

# Function to show divider
show_divider() {
    local char="${1:--}"
    local length="${2:-60}"

    printf "%${length}s\n" | tr ' ' "${char}"
}

# Function to display dynamic help based on branch type and context
show_usage() {
    local branch_type="${1:-feature}"
    local workspace_valid="${2:-true}"
    local workspace_issue="${3:-}"
    local attempted_command="${4:-}"

    # Detect if running from user profile directory
    local from_user_profile="false"
    local user_profile_path
    user_profile_path="$(get_user_profile)"
    if [[ "$(pwd)" == "${user_profile_path}" ]] || [[ "$(pwd)" == "${user_profile_path}/"* ]]; then
        from_user_profile="true"
    fi

    echo ""
    write_cyan "DESCRIPTION:"
    write_plain "  Interactive installer for AI-assisted development infrastructure that enhances"
    write_plain "  GitHub Copilot with Terraform-specific knowledge, patterns, and best practices."
    echo ""

    write_cyan "OFFICIAL INSTALLATION:"
    write_plain "  This installer is distributed as a release bundle."
    write_plain "  Download and extract the latest bundle into your user profile installer directory:"
    write_cyan "    https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/latest"
    echo ""
    write_plain "  Installer operations are offline-only and use the bundled payload (aii/)."
    write_plain "  No network downloads occur during install, verify, or clean."
    write_plain "  Install and verify validate the bundled payload checksum (aii.checksum)."
    echo ""
    write_plain "  Target installs require a terraform-provider-azurerm clone with an origin remote."
    write_plain "  The AI development repo is a source-only workspace and is not a valid target."
    echo ""
    write_yellow "  Note: -bootstrap must be run from a git clone (repo root contains .git)."
    echo ""

    # Dynamic options and examples based on branch type
    case "${branch_type}" in
        "source")
            show_source_branch_help "${attempted_command}"
            ;;
        "feature")
            show_feature_branch_help "${attempted_command}"
            ;;
        *)
            show_unknown_branch_help "${workspace_valid}" "${workspace_issue}" "${from_user_profile}" "${attempted_command}"
            ;;
    esac

    write_cyan "For more information, visit: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development"
    echo ""
}

# Function to show source branch specific help
show_source_branch_help() {
    local attempted_command="${1:-}"

    write_cyan "USAGE:"
    write_plain "  ./install-copilot-setup.sh [OPTIONS]"
    echo ""
    write_cyan "AVAILABLE OPTIONS:"
    write_plain "  -bootstrap        Copy installer to user profile (~/.terraform-azurerm-ai-installer/)"
    write_plain "                    Must be run from a git clone (.git present)"
    write_plain "  -verify           Check current workspace status and validate setup"
    write_plain "  -help             Show this help information"
    echo ""
    write_cyan "EXAMPLES:"
    write_plain "  Bootstrap installer (run from a git clone):"
    write_plain "    ./install-copilot-setup.sh -bootstrap"
    echo ""
    write_plain "  Verify setup:"
    write_plain "    ./install-copilot-setup.sh -verify"
    echo ""

    # Show command-specific help if a command was attempted
    if [[ -n "${attempted_command}" ]]; then
        echo ""
        write_yellow "NOTE: You tried to run '${attempted_command}' but this is a source branch."
        write_plain "      Use -bootstrap first to copy the installer to your user profile,"
        write_plain "      then switch to a feature branch for installation operations."
    fi

    write_cyan "BOOTSTRAP WORKFLOW:"
    write_plain "  1. Run -bootstrap from a git clone to copy installer to user profile"
    write_plain "  2. In your terraform-provider-azurerm working copy, switch to a feature branch:"
    write_plain "     git checkout -b feature/your-branch-name"
    write_plain "  3. Navigate to user profile: cd ~/.terraform-azurerm-ai-installer/"
    write_plain "  4. Run installer: ./install-copilot-setup.sh -repo-directory \"/path/to/terraform-provider-azurerm\""
    echo ""
}

# Function to show feature branch specific help
show_feature_branch_help() {
    local attempted_command="${1:-}"

    write_cyan "USAGE:"
    write_plain "  ./install-copilot-setup.sh [OPTIONS]"
    echo ""

    write_cyan "AVAILABLE OPTIONS:"
    write_plain "  -repo-directory   Path to your terraform-provider-azurerm working copy"
    write_plain "  -local-path       Local directory to copy AI files from (source override; instead of bundled payload)"
    write_plain "  -verify           Check current workspace status and validate setup"
    write_plain "  -clean            Remove AI infrastructure from workspace"
    write_plain "  -help             Show this help information"
    echo ""

    write_cyan "EXAMPLES:"
    write_cyan "  Install AI infrastructure (default - from bundled payload):"
    write_plain "    cd ~/.terraform-azurerm-ai-installer/"
    write_plain "    ./install-copilot-setup.sh -repo-directory \"/path/to/terraform-provider-azurerm\""
    echo ""
    write_cyan "  Install from local files (contributor override):"
    write_plain "    ./install-copilot-setup.sh -local-path \"/path/to/terraform-azurerm-ai-assisted-development\" -repo-directory \"/path/to/terraform-provider-azurerm\""
    echo ""
    write_cyan "  Clean removal:"
    write_plain "    cd ~/.terraform-azurerm-ai-installer/"
    write_plain "    ./install-copilot-setup.sh -repo-directory \"/path/to/terraform-provider-azurerm\" -clean"
    echo ""

    # Show command-specific help if a command was attempted.
    # Suppress this note when the user explicitly requested help/verify.
    if [[ -n "${attempted_command}" ]] && [[ "${attempted_command}" != "-help" ]] && [[ "${attempted_command}" != "-verify" ]]; then
        echo ""
        write_yellow "NOTE: You tried to run '${attempted_command}'."
        case "${attempted_command}" in
            "-repo-directory"*)
                write_plain "      This is correct! You're trying to install AI infrastructure."
                write_plain "      Make sure you're running from ~/.terraform-azurerm-ai-installer/ directory."
                ;;
            "-bootstrap")
                write_plain "      Bootstrap is for source branches only. Use -repo-directory instead."
                ;;
            *)
                write_plain "      For feature branches, use -repo-directory to specify your workspace."
                ;;
        esac
    fi

    write_cyan "WORKFLOW:"
    write_plain "  1. Navigate to user profile installer directory: cd ~/.terraform-azurerm-ai-installer/"
    write_plain "  2. Run installer with -repo-directory pointing to your terraform-provider-azurerm working copy"
    write_plain "  3. Start developing with enhanced GitHub Copilot AI features"
    write_plain "  4. Use -clean to remove AI infrastructure when done"
    echo ""
    write_cyan "LOCAL SOURCE WORKFLOW:"
    write_plain "  Use -local-path to copy AI files from a local directory instead of the bundled payload."
    echo ""
}

# Function to show generic help when branch type cannot be determined
show_unknown_branch_help() {
    local workspace_valid="${1:-true}"
    local workspace_issue="${2:-}"
    local from_user_profile="${3:-false}"
    local attempted_command="${4:-}"

    # Show workspace issue if detected
    if [[ "${workspace_valid}" != "true" && -n "${workspace_issue}" ]]; then
        write_cyan "WORKSPACE ISSUE DETECTED:"
        write_yellow "  ${workspace_issue}"
        echo ""
        write_cyan "SOLUTION:"

        # Use dynamic command or default to -help
        local command_example="${attempted_command:-"-help"}"

        if [[ "${from_user_profile}" == "true" ]]; then
            # User is running from ~/.terraform-azurerm-ai-installer, they need -repo-directory
            write_plain "  Use the -repo-directory parameter to specify your repository path:"
            write_plain "  ./install-copilot-setup.sh -repo-directory \"/path/to/terraform-provider-azurerm\" ${command_example}"
        else
            # User is running from somewhere else, they need to navigate to a repo or use -repo-directory
            write_plain "  Navigate to a terraform-provider-azurerm repository, or use the -repo-directory parameter:"
            write_plain "  ./install-copilot-setup.sh -repo-directory \"/path/to/terraform-provider-azurerm\" ${command_example}"
        fi

        echo ""
        print_separator
        echo ""
    fi

    write_cyan "USAGE:"
    write_plain "  ./install-copilot-setup.sh [OPTIONS]"
    echo ""

    write_cyan "ALL OPTIONS:"
    write_plain "  -bootstrap        Copy installer to user profile (~/.terraform-azurerm-ai-installer/)"
    write_plain "  -repo-directory   Path to your terraform-provider-azurerm working copy"
    write_plain "  -local-path       Local directory to copy AI files from (source override; instead of bundled payload)"
    write_plain "  -verify           Check current workspace status and validate setup"
    write_plain "  -clean            Remove AI infrastructure from workspace"
    write_plain "  -help             Show this help information"
    echo ""

    write_cyan "EXAMPLES:"
    write_dark_cyan "  Source Branch Operations:"
    write_plain "    ./install-copilot-setup.sh -bootstrap"
    write_plain "    ./install-copilot-setup.sh -verify"
    echo ""
    write_dark_cyan "  Feature Branch Operations:"
    write_plain "    cd ~/.terraform-azurerm-ai-installer"
    write_plain "    ./install-copilot-setup.sh -repo-directory \"/path/to/terraform-provider-azurerm\""
    write_plain "    ./install-copilot-setup.sh -repo-directory \"/path/to/terraform-provider-azurerm\" -clean"
    echo ""
    write_dark_cyan "  Local Source Operations (Contributor Override):"
    write_plain "    ./install-copilot-setup.sh -local-path \"/path/to/ai-repo\" -repo-directory \"/path/to/terraform-provider-azurerm\""
    echo ""

    write_cyan "BRANCH DETECTION:"
    write_plain "  The installer automatically detects your branch type and shows appropriate options."
    echo ""
}

# Function to display source branch welcome and guidance
show_source_branch_welcome() {
    local branch_name="${1:-}"

    if [[ -z "${branch_name}" ]]; then
        echo ""
        return 0
    fi

    echo ""
    write_green "WELCOME TO AI-ASSISTED TERRAFORM AZURERM DEVELOPMENT"
    echo ""
}

# Function to write plain text (no prefix)
write_plain() {
    local message="$1"
    echo -e "${message}"
}

# Function to show bootstrap location error
show_bootstrap_location_error() {
    local current_location="$1"
    local expected_location="$2"

    echo ""
    print_separator
    echo ""
    write_error_message "Bootstrap must be run from the source repository, not user profile"
    echo ""
    write_plain "Current location: ${current_location}"
    write_plain "Expected location: ${expected_location}"
    echo ""
    write_yellow "SOLUTION:"
    write_cyan "Navigate to a git clone of terraform-azurerm-ai-assisted-development and run:"
    write_plain "  cd /path/to/terraform-azurerm-ai-assisted-development/installer"
    write_plain "  ./install-copilot-setup.sh -bootstrap"
    echo ""
}

# Function to show bootstrap directory validation error
show_bootstrap_directory_validation_error() {
    local current_location="$1"

    echo ""
    write_error_message "Bootstrap must be run from a git clone of terraform-azurerm-ai-assisted-development"
    echo ""
    write_plain "Current location: ${current_location}"
    write_cyan "Expected structure:"
    write_plain "  From repo root: installer/install-copilot-setup.sh"
    write_plain "  From installer: install-copilot-setup.sh, modules/"
    echo ""
}

show_repository_directory_required_error() {
    local current_location="$1"

    echo ""
    write_error_message "Repository directory required when running from outside terraform-provider-azurerm repository"
    echo ""
    write_plain "You are running the installer from: ${current_location}"
    write_plain "This is not a terraform-provider-azurerm repository directory."
    echo ""
    write_cyan "Required: Specify target repository with -repo-directory"
    write_plain "  ./install-copilot-setup.sh -repo-directory /path/to/terraform-provider-azurerm"
    echo ""
    write_cyan "Alternative: Bootstrap installer to user profile"
    write_plain "  ./install-copilot-setup.sh -bootstrap"
    echo ""
}

# Function to display branch validation failed message (matches PowerShell UX)
show_branch_validation_failed() {
    local branch_name="$1"
    local script_name="${2:-./install-copilot-setup.sh}"

    echo ""
    write_red " Error: Installer configuration validation failed"
    echo ""
    write_cyan " Source: Bundled payload (aii/)"
    echo ""
    write_cyan " The installer could not load the required local files (manifest/payload)."
    echo ""
    write_cyan " Notes:"
    write_cyan " - Default installs use the bundled payload in the installer directory."
    write_cyan " - Use -local-path to source files from a local working tree (contributor/dev override)."
    echo ""
    write_cyan " Suggested actions:"
    write_plain " - Re-extract the latest release bundle into your user profile and try again"
    write_plain " - Or use local source install:"
    write_plain "   ./install-copilot-setup.sh -local-path \"/path/to/terraform-azurerm-ai-assisted-development\" -repo-directory \"/path/to/terraform-provider-azurerm\""
    echo ""
    write_cyan " For more help, run:"
    write_plain "   ${script_name} -help"
    echo ""
}

# Function to display safety violation message for source branch operations
show_safety_violation() {
    local branch_name="${1:-main}"
    local operation="${2:-operation}"
    local from_user_profile="${3:-false}"
    local workspace_root="${4:-$PWD}"

    write_red " SAFETY VIOLATION: Cannot ${operation} on source branch"
    print_separator 60 "${CYAN}" "="
    echo ""

    if [[ "${from_user_profile}" == "true" ]]; then
        write_yellow " The -repo-directory points to the source branch '${branch_name}'."
    else
        write_yellow " You are currently in the source branch '${branch_name}'."
    fi

    write_yellow " Operations other than -verify, -help, and -bootstrap are not allowed on the source branch."
    echo ""
    write_cyan "SOLUTION:"
    write_cyan "  Switch to a feature branch in your target repository:"
    write_plain "    cd \"<path-to-your-terraform-provider-azurerm>\""
    write_plain "    git checkout -b feature/your-branch-name"
    echo ""
    write_cyan "  Then run the installer again and target your terraform-provider-azurerm repo directory:"
    write_plain "    \$HOME/.terraform-azurerm-ai-installer/install-copilot-setup.sh -repo-directory \"<path-to-your-terraform-provider-azurerm>\""
    echo ""
}

# Function to display workspace validation error message
show_workspace_validation_error() {
    local reason="${1:-Unknown validation error}"
    local from_user_profile="${2:-false}"

    echo ""
    write_error_message "WORKSPACE VALIDATION FAILED: ${reason}"
    echo ""

    # Context-aware error message based on how the script was invoked
    if [[ "${from_user_profile}" == "true" ]]; then
        write_yellow " Running from your user profile directory (\$HOME/.terraform-azurerm-ai-installer)"
        write_yellow " Please ensure -repo-directory points to a valid terraform-provider-azurerm working copy:"
        write_yellow "   \$HOME/.terraform-azurerm-ai-installer/install-copilot-setup.sh -repo-directory \"<path-to-terraform-provider-azurerm>\""
    else
        write_yellow " Bootstrap must be run from a git clone of terraform-azurerm-ai-assisted-development (repo root contains .git)."
        write_yellow " After bootstrap, run from your user profile directory and target your provider repo:"
        write_yellow "   \$HOME/.terraform-azurerm-ai-installer/install-copilot-setup.sh -repo-directory \"<path-to-terraform-provider-azurerm>\""
    fi
    echo ""
    print_separator
}



# Export all UI functions for use in other scripts
export -f write_cyan write_green write_yellow write_white write_red
export -f write_plain write_label write_colored_label write_section_header write_section
export -f write_block_header
export -f write_next_steps_block
export -f write_issues_block
export -f write_header write_operation_status
export -f write_error_message write_warning_message write_success_message
export -f write_file_operation_status show_completion_summary show_safety_violation
export -f show_usage show_source_branch_welcome show_workspace_validation_error
export -f show_branch_validation_failed
export -f show_operation_summary
export -f print_separator get_user_profile format_aligned_label_spacing calculate_max_filename_length
