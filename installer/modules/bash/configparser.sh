#!/usr/bin/env bash
# ConfigParser Module for Terraform AzureRM Provider AI Setup (Bash)
# STREAMLINED VERSION - Contains only functions actually used by main script

# Function to parse manifest section (used by get_manifest_files)
parse_manifest_section() {
    local manifest_file="$1"
    local section_name="$2"

    if [[ ! -f "${manifest_file}" ]]; then
        write_error_message "Manifest file not found: ${manifest_file}"
        return 1
    fi

    local in_section=false

    while IFS= read -r line; do
        # Remove leading/trailing whitespace
        line=$(echo "${line}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Skip empty lines and comments
        if [[ -z "${line}" ]] || echo "${line}" | grep -q '^#'; then
            continue
        fi

        # Check for section headers [SECTION_NAME]
        if echo "${line}" | grep -q '^\[[^]]*\]$'; then
            local current_section="$(echo "${line}" | sed 's/^\[\([^]]*\)\]$/\1/')"
            if [[ "${current_section}" == "${section_name}" ]]; then
                in_section=true
            else
                in_section=false
            fi
            continue
        fi

        # Output files from the requested section
        if [[ "${in_section}" == "true" && -n "${line}" ]]; then
            echo "${line}"
        fi
    done < "${manifest_file}"
}

# Function to get files from manifest by section (used by fileoperations module)
get_manifest_files() {
    local section_name="$1"
    local manifest_file="${2:-${HOME}/.terraform-azurerm-ai-installer/file-manifest.config}"

    # Require manifest file - no fallback
    if [[ ! -f "${manifest_file}" ]]; then
        write_error_message "Manifest file not found: ${manifest_file}"
        echo "Please run with -bootstrap first to set up the installer."
        return 1
    fi

    # Parse from manifest
    parse_manifest_section "${manifest_file}" "${section_name}"
}

# Export functions used by the installer and fileoperations modules
export -f parse_manifest_section get_manifest_files
