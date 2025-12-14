#!/bin/bash
################################################################################
# AEON Common Utilities
# File: lib/common.sh
# Version: 0.1.0
#
# Purpose: Shared utilities used by all AEON modules
#
# Usage:
#   source /opt/aeon/lib/common.sh
#
# Provides:
#   - Color definitions
#   - Logging functions
#   - Display functions
#   - Utility functions
#   - Common constants
#
# Dependencies: None (this is the base module)
################################################################################

# Prevent double-sourcing
[[ -n "${AEON_COMMON_LOADED:-}" ]] && return 0
readonly AEON_COMMON_LOADED=1

# ============================================================================
# CONSTANTS
# ============================================================================

# Version
readonly AEON_VERSION="0.1.0"

# Directories (allow override via environment)
: "${AEON_DIR:=/opt/aeon}"
readonly AEON_DIR

readonly LIB_DIR="$AEON_DIR/lib"
readonly REMOTE_DIR="$AEON_DIR/remote"
readonly CONFIG_DIR="$AEON_DIR/config"
readonly DATA_DIR="$AEON_DIR/data"
readonly SECRETS_DIR="$AEON_DIR/secrets"
readonly LOG_DIR="$AEON_DIR/logs"
readonly REPORT_DIR="$AEON_DIR/reports"

# Log file
readonly AEON_LOG_FILE="${AEON_LOG_DIR:-$LOG_DIR}/aeon.log"

# ANSI Color Codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly WHITE='\033[0;37m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly UNDERLINE='\033[4m'
readonly NC='\033[0m'  # No Color / Reset

# Box Drawing Characters (UTF-8)
readonly BOX_H='═'      # Horizontal line
readonly BOX_V='║'      # Vertical line
readonly BOX_TL='╔'     # Top-left corner
readonly BOX_TR='╗'     # Top-right corner
readonly BOX_BL='╚'     # Bottom-left corner
readonly BOX_BR='╝'     # Bottom-right corner
readonly BOX_VL='╠'     # Vertical line with right connection
readonly BOX_VR='╣'     # Vertical line with left connection
readonly BOX_HT='╦'     # Horizontal line with down connection
readonly BOX_HB='╩'     # Horizontal line with up connection
readonly BOX_CROSS='╬'  # Cross

# Single-line box characters (fallback)
readonly SBOX_H='─'
readonly SBOX_V='│'
readonly SBOX_TL='┌'
readonly SBOX_TR='┐'
readonly SBOX_BL='└'
readonly SBOX_BR='┘'

# Emoji/Icons (optional, can be disabled)
readonly ICON_SUCCESS='✅'
readonly ICON_ERROR='❌'
readonly ICON_WARNING='⚠️ '
readonly ICON_INFO='ℹ️ '
readonly ICON_STEP='▶'
readonly ICON_BULLET='•'
readonly ICON_MANAGER='🔷'
readonly ICON_WORKER='🔶'
readonly ICON_LEADER='⭐'

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log() {
    # Unified logging function with color coding and file output
    #
    # Arguments:
    #   $1 - Log level: ERROR, WARN, INFO, SUCCESS, STEP, DEBUG
    #   $@ - Message to log
    #
    # Returns:
    #   None
    #
    # Side Effects:
    #   - Prints to stdout (INFO, SUCCESS, STEP, DEBUG) or stderr (ERROR, WARN)
    #   - Appends to log file if AEON_LOG_FILE is writable
    #
    # Example:
    #   log INFO "Starting installation"
    #   log ERROR "Connection failed"
    
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log to file (always, if possible)
    if [[ -w "$(dirname "$AEON_LOG_FILE" 2>/dev/null)" ]] 2>/dev/null; then
        echo "[$timestamp] [$level] $message" >> "$AEON_LOG_FILE" 2>/dev/null || true
    fi
    
    # Log to console with color coding
    case "$level" in
        ERROR)
            echo -e "${RED}${ICON_ERROR} $message${NC}" >&2
            ;;
        WARN|WARNING)
            echo -e "${YELLOW}${ICON_WARNING}$message${NC}"
            ;;
        INFO)
            echo -e "${CYAN}${ICON_INFO}$message${NC}"
            ;;
        SUCCESS)
            echo -e "${GREEN}${ICON_SUCCESS} $message${NC}"
            ;;
        STEP)
            echo -e "${BOLD}${BLUE}${ICON_STEP} $message${NC}"
            ;;
        DEBUG)
            if [[ "${AEON_DEBUG:-0}" == "1" ]]; then
                echo -e "${DIM}[DEBUG] $message${NC}"
            fi
            ;;
        *)
            echo "$message"
            ;;
    esac
}

log_debug() {
    # Log debug message (only if AEON_DEBUG=1)
    #
    # Arguments:
    #   $@ - Message to log
    #
    # Example:
    #   log_debug "Variable value: $var"
    
    log DEBUG "$@"
}

log_to_file() {
    # Log to file only, no console output
    #
    # Arguments:
    #   $1 - Log level
    #   $@ - Message
    #
    # Example:
    #   log_to_file INFO "Background process started"
    
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ -w "$(dirname "$AEON_LOG_FILE" 2>/dev/null)" ]] 2>/dev/null; then
        echo "[$timestamp] [$level] $message" >> "$AEON_LOG_FILE" 2>/dev/null || true
    fi
}

# ============================================================================
# DISPLAY FUNCTIONS
# ============================================================================

print_header() {
    # Print a formatted section header
    #
    # Arguments:
    #   $1 - Header text
    #
    # Example:
    #   print_header "Phase 1: Pre-flight Checks"
    
    local text="$1"
    local width=60
    
    echo ""
    echo -e "${BOLD}${CYAN}${BOX_TL}$(printf '%*s' $width '' | tr ' ' "$BOX_H")${BOX_TR}${NC}"
    echo -e "${BOLD}${CYAN}${BOX_V}  $text$(printf '%*s' $((width - ${#text} - 2)) '')${BOX_V}${NC}"
    echo -e "${BOLD}${CYAN}${BOX_BL}$(printf '%*s' $width '' | tr ' ' "$BOX_H")${BOX_BR}${NC}"
    echo ""
}

print_banner() {
    # Print AEON ASCII art banner
    #
    # Arguments:
    #   None
    #
    # Example:
    #   print_banner
    
    clear
    cat << 'EOF'

     █████╗ ███████╗ ██████╗ ███╗   ██╗
    ██╔══██╗██╔════╝██╔═══██╗████╗  ██║
    ███████║█████╗  ██║   ██║██╔██╗ ██║
    ██╔══██║██╔══╝  ██║   ██║██║╚██╗██║
    ██║  ██║███████╗╚██████╔╝██║ ╚████║
    ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝

    Autonomous Evolving Orchestration Network
    Distributed AI Infrastructure Platform

EOF
    
    echo -e "${BOLD}${CYAN}${BOX_TL}$(printf '%*s' 60 '' | tr ' ' "$BOX_H")${BOX_TR}${NC}"
    echo -e "${BOLD}${CYAN}${BOX_V}  Version: $AEON_VERSION$(printf '%*s' $((60 - 12 - ${#AEON_VERSION})) '')${BOX_V}${NC}"
    echo -e "${BOLD}${CYAN}${BOX_V}  Installation Directory: $AEON_DIR$(printf '%*s' $((60 - 27 - ${#AEON_DIR})) '')${BOX_V}${NC}"
    echo -e "${BOLD}${CYAN}${BOX_BL}$(printf '%*s' 60 '' | tr ' ' "$BOX_H")${BOX_BR}${NC}"
    echo ""
}

print_line() {
    # Print a horizontal line
    #
    # Arguments:
    #   $1 - Character to use (default: ═)
    #   $2 - Width (default: 60)
    #
    # Example:
    #   print_line
    #   print_line "─" 80
    
    local char="${1:-$BOX_H}"
    local width="${2:-60}"
    
    printf '%*s\n' "$width" '' | tr ' ' "$char"
}

print_box() {
    # Print text in a box
    #
    # Arguments:
    #   $@ - Lines of text
    #
    # Example:
    #   print_box "Line 1" "Line 2" "Line 3"
    
    local lines=("$@")
    local max_length=0
    
    # Find longest line
    for line in "${lines[@]}"; do
        if [[ ${#line} -gt $max_length ]]; then
            max_length=${#line}
        fi
    done
    
    local width=$((max_length + 4))
    
    # Top border
    echo -e "${BOX_TL}$(printf '%*s' $((width - 2)) '' | tr ' ' "$BOX_H")${BOX_TR}"
    
    # Content
    for line in "${lines[@]}"; do
        local padding=$((width - ${#line} - 4))
        echo -e "${BOX_V} $line$(printf '%*s' $padding '')  ${BOX_V}"
    done
    
    # Bottom border
    echo -e "${BOX_BL}$(printf '%*s' $((width - 2)) '' | tr ' ' "$BOX_H")${BOX_BR}"
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

command_exists() {
    # Check if a command exists in PATH
    #
    # Arguments:
    #   $1 - Command name
    #
    # Returns:
    #   0 if command exists
    #   1 if command does not exist
    #
    # Example:
    #   if command_exists docker; then
    #       echo "Docker is installed"
    #   fi
    
    command -v "$1" &>/dev/null
}

ensure_directory() {
    # Create directory if it doesn't exist
    #
    # Arguments:
    #   $1 - Directory path
    #   $2 - Permissions (optional, default: 755)
    #
    # Returns:
    #   0 on success
    #   1 on failure
    #
    # Example:
    #   ensure_directory "/opt/aeon/data"
    #   ensure_directory "/opt/aeon/secrets" 700
    
    local dir="$1"
    local perms="${2:-755}"
    
    if [[ ! -d "$dir" ]]; then
        if mkdir -p "$dir" 2>/dev/null; then
            chmod "$perms" "$dir" 2>/dev/null || true
            log_debug "Created directory: $dir (permissions: $perms)"
            return 0
        else
            log ERROR "Failed to create directory: $dir"
            return 1
        fi
    fi
    
    return 0
}

get_timestamp() {
    # Get current timestamp in ISO 8601 format
    #
    # Arguments:
    #   $1 - Format (optional): iso, unix, readable
    #
    # Returns:
    #   Formatted timestamp string
    #
    # Example:
    #   timestamp=$(get_timestamp)
    #   timestamp=$(get_timestamp unix)
    
    local format="${1:-iso}"
    
    case "$format" in
        iso)
            date -u '+%Y-%m-%dT%H:%M:%SZ'
            ;;
        unix)
            date '+%s'
            ;;
        readable)
            date '+%Y-%m-%d %H:%M:%S'
            ;;
        *)
            date -u '+%Y-%m-%dT%H:%M:%SZ'
            ;;
    esac
}

get_script_dir() {
    # Get the directory where the calling script is located
    #
    # Arguments:
    #   None
    #
    # Returns:
    #   Absolute path to script directory
    #
    # Example:
    #   SCRIPT_DIR=$(get_script_dir)
    
    local source="${BASH_SOURCE[1]}"
    while [[ -h "$source" ]]; do
        local dir="$(cd -P "$(dirname "$source")" && pwd)"
        source="$(readlink "$source")"
        [[ $source != /* ]] && source="$dir/$source"
    done
    cd -P "$(dirname "$source")" && pwd
}

join_array() {
    # Join array elements with a delimiter
    #
    # Arguments:
    #   $1 - Delimiter
    #   $@ - Array elements
    #
    # Returns:
    #   Joined string
    #
    # Example:
    #   result=$(join_array ", " "apple" "banana" "cherry")
    #   # result = "apple, banana, cherry"
    
    local delimiter="$1"
    shift
    local first="$1"
    shift
    printf "%s" "$first" "${@/#/$delimiter}"
}

trim() {
    # Trim leading and trailing whitespace
    #
    # Arguments:
    #   $1 - String to trim
    #
    # Returns:
    #   Trimmed string
    #
    # Example:
    #   result=$(trim "  hello world  ")
    
    local var="$*"
    # Remove leading whitespace
    var="${var#"${var%%[![:space:]]*}"}"
    # Remove trailing whitespace
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
}

to_lower() {
    # Convert string to lowercase
    #
    # Arguments:
    #   $1 - String
    #
    # Returns:
    #   Lowercase string
    #
    # Example:
    #   result=$(to_lower "HELLO")
    
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

to_upper() {
    # Convert string to uppercase
    #
    # Arguments:
    #   $1 - String
    #
    # Returns:
    #   Uppercase string
    #
    # Example:
    #   result=$(to_upper "hello")
    
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

contains() {
    # Check if string contains substring
    #
    # Arguments:
    #   $1 - Haystack (string to search in)
    #   $2 - Needle (string to search for)
    #
    # Returns:
    #   0 if found
    #   1 if not found
    #
    # Example:
    #   if contains "hello world" "world"; then
    #       echo "Found!"
    #   fi
    
    [[ "$1" == *"$2"* ]]
}

is_root() {
    # Check if running as root
    #
    # Arguments:
    #   None
    #
    # Returns:
    #   0 if root (UID 0)
    #   1 if not root
    #
    # Example:
    #   if is_root; then
    #       echo "Running as root"
    #   fi
    
    [[ $EUID -eq 0 ]]
}

confirm() {
    # Ask for user confirmation
    #
    # Arguments:
    #   $1 - Prompt message
    #   $2 - Default (optional): y/n
    #
    # Returns:
    #   0 if yes
    #   1 if no
    #
    # Example:
    #   if confirm "Proceed?"; then
    #       echo "Proceeding..."
    #   fi
    
    local prompt="$1"
    local default="${2:-n}"
    local yn
    
    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n] "
    else
        prompt="$prompt [y/N] "
    fi
    
    read -p "$prompt" -n 1 -r yn
    echo ""
    
    case "$yn" in
        [Yy])
            return 0
            ;;
        [Nn])
            return 1
            ;;
        "")
            [[ "$default" == "y" ]] && return 0 || return 1
            ;;
        *)
            return 1
            ;;
    esac
}

retry() {
    # Retry a command with exponential backoff
    #
    # Arguments:
    #   $1 - Max attempts
    #   $2 - Command to execute
    #   $@ - Command arguments
    #
    # Returns:
    #   0 if command succeeds within max attempts
    #   1 if all attempts fail
    #
    # Example:
    #   retry 3 ping -c 1 192.168.1.1
    
    local max_attempts="$1"
    shift
    local attempt=1
    local delay=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if "$@"; then
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            log_debug "Attempt $attempt failed, retrying in ${delay}s..."
            sleep "$delay"
            delay=$((delay * 2))  # Exponential backoff
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_debug "All $max_attempts attempts failed"
    return 1
}

# ============================================================================
# FILE UTILITIES
# ============================================================================

file_exists() {
    # Check if file exists and is readable
    #
    # Arguments:
    #   $1 - File path
    #
    # Returns:
    #   0 if file exists and is readable
    #   1 otherwise
    
    [[ -f "$1" ]] && [[ -r "$1" ]]
}

dir_exists() {
    # Check if directory exists
    #
    # Arguments:
    #   $1 - Directory path
    #
    # Returns:
    #   0 if directory exists
    #   1 otherwise
    
    [[ -d "$1" ]]
}

is_writable() {
    # Check if path is writable
    #
    # Arguments:
    #   $1 - Path to check
    #
    # Returns:
    #   0 if writable
    #   1 otherwise
    
    [[ -w "$1" ]]
}

get_file_size() {
    # Get file size in bytes
    #
    # Arguments:
    #   $1 - File path
    #
    # Returns:
    #   File size in bytes
    
    if [[ -f "$1" ]]; then
        stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# ============================================================================
# JSON UTILITIES
# ============================================================================

json_get() {
    # Extract value from JSON using jq
    #
    # Arguments:
    #   $1 - JSON file path
    #   $2 - jq query
    #
    # Returns:
    #   Extracted value
    #
    # Example:
    #   value=$(json_get "data.json" ".devices[0].ip")
    
    local file="$1"
    local query="$2"
    
    if ! command_exists jq; then
        log ERROR "jq is required for JSON operations"
        return 1
    fi
    
    if [[ ! -f "$file" ]]; then
        log ERROR "JSON file not found: $file"
        return 1
    fi
    
    jq -r "$query" "$file" 2>/dev/null
}

json_validate() {
    # Validate JSON file
    #
    # Arguments:
    #   $1 - JSON file path
    #
    # Returns:
    #   0 if valid JSON
    #   1 if invalid
    
    local file="$1"
    
    if ! command_exists jq; then
        log ERROR "jq is required for JSON validation"
        return 1
    fi
    
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    
    jq empty "$file" &>/dev/null
}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Create log directory if it doesn't exist
ensure_directory "$LOG_DIR" 755 2>/dev/null || true

# Log that common utilities have been loaded
log_debug "AEON common utilities loaded (version $AEON_VERSION)"

# Export functions (optional, for use in subshells)
export -f log log_debug log_to_file 2>/dev/null || true
export -f print_header print_banner print_line print_box 2>/dev/null || true
export -f command_exists ensure_directory get_timestamp 2>/dev/null || true
export -f trim to_lower to_upper contains is_root confirm retry 2>/dev/null || true
export -f file_exists dir_exists is_writable get_file_size 2>/dev/null || true
export -f json_get json_validate 2>/dev/null || true

# Return success
return 0
