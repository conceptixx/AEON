#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script info
SCRIPT_NAME="$(basename "$0")"
TMP_SCRIPT="/tmp/${SCRIPT_NAME}"

# Default repo URL (modify as needed)
DEFAULT_REPO="github.com/user/repo/branch/file.json"
REPO_FILE=""

# Flags
QUIET=false
FORCE=false
VERBOSE=false

# ============================================================================
# PHASE 1: Self-installation if piped from curl/wget
# ============================================================================
if [[ -p /dev/stdin ]] || [[ ! -t 0 ]]; then
    if [[ "${0}" == "bash" ]] || [[ "${0}" == "/bin/bash" ]] || [[ "${0##*/}" == "-bash" ]]; then
        echo -e "${GREEN}Detected pipe execution. Creating local copy at ${TMP_SCRIPT}${NC}"
        # Read the entire script from stdin and write to temp location
        cat > "${TMP_SCRIPT}" << 'EOF'
# Placeholder - will be replaced with actual script content
EOF
        
        # Replace the placeholder with the actual script content
        # In a real scenario, the entire script would be piped
        # For this example, we'll copy the current script
        if [[ -f "$0" ]]; then
            cp "$0" "${TMP_SCRIPT}"
        fi
        
        chmod +x "${TMP_SCRIPT}"
        echo -e "${GREEN}Running local copy...${NC}"
        exec "${TMP_SCRIPT}" "$@"
        exit 0
    fi
fi

# ============================================================================
# PHASE 2: Dependency checking and installation
# ============================================================================
install_dependency() {
    local dep="$1"
    echo -e "${YELLOW}Installing ${dep}...${NC}"
    
    # Map command names to package names for different package managers
    local pkg_name="$dep"
    
    # Handle sha256sum which might be part of coreutils
    if [[ "$dep" == "sha256sum" ]]; then
        if command -v apt-get &> /dev/null; then
            pkg_name="coreutils"
        elif command -v yum &> /dev/null; then
            pkg_name="coreutils"
        elif command -v dnf &> /dev/null; then
            pkg_name="coreutils"
        elif command -v brew &> /dev/null; then
            pkg_name="coreutils"
        elif command -v pacman &> /dev/null; then
            pkg_name="coreutils"
        elif command -v apk &> /dev/null; then
            pkg_name="coreutils"
        fi
    fi
    
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y "$pkg_name"
    elif command -v yum &> /dev/null; then
        sudo yum install -y "$pkg_name"
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y "$pkg_name"
    elif command -v brew &> /dev/null; then
        brew install "$pkg_name"
    elif command -v pacman &> /dev/null; then
        sudo pacman -Sy --noconfirm "$pkg_name"
    elif command -v apk &> /dev/null; then
        sudo apk add "$pkg_name"
    else
        echo -e "${RED}Could not determine package manager. Please install ${dep} manually.${NC}"
        exit 1
    fi
}

check_and_install_deps() {
    local deps=("curl" "wget" "jq" "sha256sum")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            if [[ "$QUIET" == false ]]; then
                echo -e "${YELLOW}${dep} not found. Attempting to install...${NC}"
            fi
            install_dependency "$dep"
        fi
    done
    
    # Verify all dependencies are now available
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo -e "${RED}Failed to install ${dep}. Please install it manually.${NC}"
            exit 1
        fi
    done
}

# ============================================================================
# PHASE 3: Argument parsing
# ============================================================================
parse_arguments() {
    local file_provided=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            *)
                # First non-flag argument is considered the file
                if [[ "$file_provided" == false ]] && [[ "$1" != -* ]]; then
                    REPO_FILE="$1"
                    file_provided=true
                    shift
                else
                    echo -e "${RED}Unknown argument: $1${NC}"
                    show_help
                    exit 1
                fi
                ;;
        esac
    done
    
    # If no file provided, use default
    if [[ -z "$REPO_FILE" ]]; then
        REPO_FILE="$DEFAULT_REPO"
    fi
}

show_help() {
    cat << EOF
Usage: $0 [OPTIONS] [FILE_OR_URL]

Options:
    -h, --help      Show this help message
    -q, --quiet     Suppress non-essential output
    -f, --force     Force execution even with warnings
    -v, --verbose   Show detailed output

Arguments:
    FILE_OR_URL     Local file path or URL to JSON manifest
                    If not provided, uses default: $DEFAULT_REPO

Examples:
    $0 manifest.json
    $0 https://example.com/manifest.json
    $0 --quiet --force
EOF
}

# ============================================================================
# PHASE 4: JSON loading and validation
# ============================================================================
load_json() {
    local source="$1"
    local json_content
    
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${GREEN}Loading from: ${source}${NC}"
    fi
    
    # Check if source is a URL
    if [[ "$source" =~ ^(http|https|ftp):// ]] || [[ "$source" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/ ]]; then
        # Add https:// if not present for github.com style URLs
        if [[ "$source" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/ ]] && ! [[ "$source" =~ ^(http|https|ftp):// ]]; then
            source="https://${source}"
        fi
        
        # At this point, curl or wget should be installed from check_and_install_deps
        if command -v curl &> /dev/null; then
            json_content=$(curl -s -f "$source")
            local curl_exit=$?
            if [[ $curl_exit -ne 0 ]]; then
                echo -e "${RED}Failed to download from URL using curl. Exit code: $curl_exit${NC}"
                exit 1
            fi
        elif command -v wget &> /dev/null; then
            json_content=$(wget -q -O - "$source")
            local wget_exit=$?
            if [[ $wget_exit -ne 0 ]]; then
                echo -e "${RED}Failed to download from URL using wget. Exit code: $wget_exit${NC}"
                exit 1
            fi
        else
            # This should never happen after check_and_install_deps
            echo -e "${RED}INTERNAL ERROR: Neither curl nor wget available after dependency check${NC}"
            exit 1
        fi
    else
        # Local file
        if [[ ! -f "$source" ]]; then
            echo -e "${RED}File not found: ${source}${NC}"
            exit 1
        fi
        json_content=$(cat "$source")
    fi
    
    # Check if we got content
    if [[ -z "$json_content" ]]; then
        echo -e "${RED}No content loaded from ${source}${NC}"
        exit 1
    fi
    
    echo "$json_content"
}

validate_json_structure() {
    local json_content="$1"
    
    # Basic JSON validation
    if ! echo "$json_content" | jq . > /dev/null 2>&1; then
        echo -e "${RED}Invalid JSON format${NC}"
        exit 1
    fi
    
    # Check for required top-level elements
    local top_level_count
    top_level_count=$(echo "$json_content" | jq 'keys | length')
    
    if [[ "$top_level_count" -ne 3 ]]; then
        echo -e "${RED}JSON must have exactly 3 top-level elements${NC}"
        exit 1
    fi
    
    # Check for required keys
    for key in "app" "vars" "data"; do
        if ! echo "$json_content" | jq -e ".${key}" > /dev/null 2>&1; then
            echo -e "${RED}Missing required top-level element: ${key}${NC}"
            exit 1
        fi
    done
    
    # Check for no extra top-level elements
    local allowed_keys='["app","vars","data"]'
    local actual_keys
    actual_keys=$(echo "$json_content" | jq -c 'keys | sort')
    
    if [[ "$actual_keys" != "$allowed_keys" ]]; then
        echo -e "${RED}Only 'app', 'vars', and 'data' top-level elements are allowed${NC}"
        exit 1
    fi
    
    # Validate app section structure (no nested elements)
    local app_keys
    app_keys=$(echo "$json_content" | jq '.app | keys[]')
    
    while IFS= read -r key; do
        local value_type
        value_type=$(echo "$json_content" | jq -r ".app[$key] | type")
        
        if [[ "$value_type" == "object" ]] || [[ "$value_type" == "array" ]]; then
            echo -e "${RED}App section cannot contain nested elements or arrays${NC}"
            exit 1
        fi
    done <<< "$app_keys"
    
    # Validate vars section structure
    local var_keys
    var_keys=$(echo "$json_content" | jq '.vars | keys[]')
    
    while IFS= read -r key; do
        local value_type
        value_type=$(echo "$json_content" | jq -r ".vars[$key] | type")
        
        if [[ "$value_type" == "object" ]]; then
            echo -e "${RED}Vars section cannot contain nested objects${NC}"
            exit 1
        fi
    done <<< "$var_keys"
}

# ============================================================================
# PHASE 5: Variable declaration
# ============================================================================
declare_variables() {
    local json_content="$1"
    
    # Get all variable names
    local var_names
    var_names=$(echo "$json_content" | jq -r '.vars | keys[]')
    
    while IFS= read -r var_name; do
        # Sanitize variable name (replace spaces and special characters with underscore)
        local safe_name
        safe_name=$(echo "$var_name" | tr ' ' '_' | tr '-' '_' | tr -cd '[:alnum:]_')
        
        local value_type
        value_type=$(echo "$json_content" | jq -r ".vars[\"$var_name\"] | type")
        
        case "$value_type" in
            "string")
                local value
                value=$(echo "$json_content" | jq -r ".vars[\"$var_name\"]")
                declare -g "$safe_name=$value"
                [[ "$VERBOSE" == true ]] && echo "Declared variable: $safe_name='$value'"
                ;;
            "number")
                local value
                value=$(echo "$json_content" | jq -r ".vars[\"$var_name\"]")
                declare -g "$safe_name=$value"
                [[ "$VERBOSE" == true ]] && echo "Declared variable: $safe_name=$value"
                ;;
            "array")
                # Read array into variable
                local array_value
                array_value=$(echo "$json_content" | jq -r ".vars[\"$var_name\"][] | @sh" | tr '\n' ' ')
                declare -ga "$safe_name"
                eval "$safe_name=($array_value)"
                [[ "$VERBOSE" == true ]] && echo "Declared array: $safe_name=${array_value}"
                ;;
            "boolean")
                local value
                value=$(echo "$json_content" | jq -r ".vars[\"$var_name\"]")
                declare -g "$safe_name=$value"
                [[ "$VERBOSE" == true ]] && echo "Declared variable: $safe_name=$value"
                ;;
            *)
                echo -e "${YELLOW}Warning: Skipping variable $var_name with unsupported type $value_type${NC}"
                ;;
        esac
    done <<< "$var_names"
}

# ============================================================================
# PHASE 6: Command execution from data section
# ============================================================================
execute_commands() {
    local json_content="$1"
    local section_path="$2"
    
    # Get all elements in the data/module section
    local elements
    elements=$(echo "$json_content" | jq -r "${section_path} | keys[]")
    
    while IFS= read -r element_key; do
        local element_type
        element_type=$(echo "$json_content" | jq -r "${section_path}.\"${element_key}\".type")
        
        if [[ "$element_type" == "null" ]]; then
            # This might be a module, check if it's an object
            local is_module
            is_module=$(echo "$json_content" | jq -r "${section_path}.\"${element_key}\" | type")
            
            if [[ "$is_module" == "object" ]]; then
                # Recursively process module
                [[ "$VERBOSE" == true ]] && echo "Processing module: $element_key"
                execute_commands "$json_content" "${section_path}.\"${element_key}\""
            fi
            continue
        fi
        
        # Execute based on type
        case "$element_type" in
            "run")
                local command
                command=$(echo "$json_content" | jq -r "${section_path}.\"${element_key}\".command")
                [[ "$QUIET" == false ]] && echo -e "${GREEN}Executing: ${command}${NC}"
                eval "$command"
                ;;
                
            "mkdir")
                local path
                path=$(echo "$json_content" | jq -r "${section_path}.\"${element_key}\".path")
                [[ "$QUIET" == false ]] && echo -e "${GREEN}Creating directory: ${path}${NC}"
                mkdir -p "$path"
                ;;
                
            "copy")
                local source
                source=$(echo "$json_content" | jq -r "${section_path}.\"${element_key}\".source")
                local destination
                destination=$(echo "$json_content" | jq -r "${section_path}.\"${element_key}\".destination")
                [[ "$QUIET" == false ]] && echo -e "${GREEN}Copying: ${source} -> ${destination}${NC}"
                cp -r "$source" "$destination"
                ;;
                
            "link")
                local target
                target=$(echo "$json_content" | jq -r "${section_path}.\"${element_key}\".target")
                local link_name
                link_name=$(echo "$json_content" | jq -r "${section_path}.\"${element_key}\".link_name")
                [[ "$QUIET" == false ]] && echo -e "${GREEN}Creating link: ${link_name} -> ${target}${NC}"
                ln -sf "$target" "$link_name"
                ;;
                
            "function")
                local func_name
                func_name=$(echo "$json_content" | jq -r "${section_path}.\"${element_key}\".name")
                local func_body
                func_body=$(echo "$json_content" | jq -r "${section_path}.\"${element_key}\".body")
                
                # Define the function
                eval "${func_name}() { ${func_body}; }"
                
                # Execute if auto_run is true
                local auto_run
                auto_run=$(echo "$json_content" | jq -r "${section_path}.\"${element_key}\".auto_run // false")
                
                if [[ "$auto_run" == "true" ]]; then
                    [[ "$QUIET" == false ]] && echo -e "${GREEN}Executing function: ${func_name}${NC}"
                    eval "$func_name"
                else
                    [[ "$VERBOSE" == true ]] && echo "Defined function: $func_name"
                fi
                ;;
                
            *)
                echo -e "${YELLOW}Warning: Unknown type '${element_type}' for element '${element_key}'${NC}"
                ;;
        esac
        
    done <<< "$elements"
}

# ============================================================================
# PHASE 7: Display app information
# ============================================================================
display_app_info() {
    local json_content="$1"
    
    if [[ "$QUIET" == true ]]; then
        return
    fi
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Application Manifest${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    # Display app information
    local app_name
    app_name=$(echo "$json_content" | jq -r '.app.name // "Unnamed"')
    local version
    version=$(echo "$json_content" | jq -r '.app.version // "Unknown"')
    local description
    description=$(echo "$json_content" | jq -r '.app.description // ""')
    
    echo -e "${YELLOW}Name:${NC} $app_name"
    echo -e "${YELLOW}Version:${NC} $version"
    
    if [[ -n "$description" ]]; then
        echo -e "${YELLOW}Description:${NC} $description"
    fi
    
    echo -e "${GREEN}========================================${NC}"
}

# ============================================================================
# MAIN EXECUTION FLOW
# ============================================================================
main() {
    # Parse arguments
    parse_arguments "$@"
    
    # Check and install dependencies
    check_and_install_deps
    
    # Load JSON
    [[ "$QUIET" == false ]] && echo -e "${GREEN}Loading manifest...${NC}"
    local json_content
    json_content=$(load_json "$REPO_FILE")
    
    # Validate JSON structure
    [[ "$QUIET" == false ]] && echo -e "${GREEN}Validating manifest structure...${NC}"
    validate_json_structure "$json_content"
    
    # Display app info
    display_app_info "$json_content"
    
    # Declare variables
    [[ "$QUIET" == false ]] && echo -e "${GREEN}Setting up environment variables...${NC}"
    declare_variables "$json_content"
    
    # Execute commands from data section
    [[ "$QUIET" == false ]] && echo -e "${GREEN}Executing manifest commands...${NC}"
    execute_commands "$json_content" ".data"
    
    [[ "$QUIET" == false ]] && echo -e "${GREEN}Done!${NC}"
}

# Run main function
main "$@"