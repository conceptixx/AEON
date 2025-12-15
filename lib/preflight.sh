#!/bin/bash
################################################################################
# AEON Pre-flight Checks
# File: lib/preflight.sh
# Version: 0.1.0
#
# Purpose: Verify system meets requirements before installation
#
# Usage:
#   source /opt/aeon/lib/preflight.sh
#   run_preflight_checks || exit 1
#
# Provides:
#   - Root privilege verification
#   - Internet connectivity check
#   - Disk space validation
#   - Required tools installation
#   - Directory structure creation
#
# Dependencies:
#   - lib/common.sh
#   - lib/progress.sh
################################################################################

set -euo pipefail

# ============================================================================
# DEPENDENCIES
# ============================================================================

# Prevent double-loading
[[ -n "${AEON_PREFLIGHT_LOADED:-}" ]] && return 0
readonly AEON_PREFLIGHT_LOADED=1

# Load dependencies
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
if [[ -z "${AEON_DEPENDENCIES_LOADED:-}" ]]; then
    source "$SCRIPT_DIR/dependencies.sh" || source "/opt/aeon/lib/dependencies.sh" || {
        echo "ERROR: Cannot find dependencies.sh" >&2
        exit 1
    }
fi

# load dependecies -if available
load_dependencies "preflight.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

# Minimum requirements
readonly MIN_DISK_SPACE_GB=1
readonly REQUIRED_BASH_VERSION=4

# Required tools (will be installed if missing)
readonly REQUIRED_TOOLS=(
    "curl"
    "wget"
    "jq"
    "git"
    "sshpass"
    "python3"
    "nmap"
    "bc"
    "docker"
)

# Optional tools (warn if missing, but don't fail)
readonly OPTIONAL_TOOLS=(
)

# ============================================================================
# ROOT CHECK
# ============================================================================

check_root() {
    # Verify script is running as root
    #
    # Arguments:
    #   None
    #
    # Returns:
    #   0 if root
    #   Exits with 1 if not root
    #
    # Example:
    #   check_root || exit 1
    
    log_to_file "Checking root privileges..."
    
    if ! is_root; then
        log_to_file "ERROR: This script must be run as root"
        
        # Show error on screen
        tput cup $((TERM_HEIGHT - 5)) 0 2>/dev/null || true
        echo ""
        echo -e "${RED}ERROR: This script must be run as root${NC}"
        echo ""
        echo -e "${YELLOW}Please run with sudo:${NC}"
        echo -e "  ${CYAN}sudo bash $0${NC}"
        echo ""
        
        complete_phase "failed" "Not running as root"
        exit 1
    fi
    
    log_to_file "✓ Running as root"
    return 0
}

# ============================================================================
# BASH VERSION CHECK
# ============================================================================

check_bash_version() {
    # Verify bash version is sufficient
    #
    # Arguments:
    #   None
    #
    # Returns:
    #   0 if version >= 4.0
    #   1 if version < 4.0
    
    log_to_file "Checking bash version..."
    
    local major_version="${BASH_VERSINFO[0]}"
    
    if [[ $major_version -lt $REQUIRED_BASH_VERSION ]]; then
        log_to_file "ERROR: Bash version $REQUIRED_BASH_VERSION or higher required"
        log_to_file "Current version: $BASH_VERSION"
        return 1
    fi
    
    log_to_file "✓ Bash version: $BASH_VERSION"
    return 0
}

# ============================================================================
# NETWORK CHECKS
# ============================================================================

check_internet() {
    # Verify internet connectivity
    #
    # Arguments:
    #   None
    #
    # Returns:
    #   0 if internet available
    #   1 if no internet
    #
    # Example:
    #   check_internet || exit 1
    
    log_to_file "Checking internet connectivity..."
    
    # Try multiple DNS servers
    local dns_servers=(
        "8.8.8.8"          # Google DNS
        "1.1.1.1"          # Cloudflare DNS
        "9.9.9.9"          # Quad9 DNS
    )
    
    for dns in "${dns_servers[@]}"; do
        if ping -c 1 -W 3 "$dns" &>/dev/null; then
            log_to_file "✓ Internet connection available (tested: $dns)"
            return 0
        fi
    done
    
    log_to_file "ERROR: No internet connection detected"
    log_to_file "Internet is required for package installation, Docker, and repository downloads"
    
    return 1
}

check_dns_resolution() {
    # Verify DNS resolution works
    #
    # Arguments:
    #   None
    #
    # Returns:
    #   0 if DNS works
    #   1 if DNS fails
    
    log_to_file "Checking DNS resolution..."
    
    if host github.com &>/dev/null || nslookup github.com &>/dev/null; then
        log_to_file "✓ DNS resolution working"
        return 0
    else
        log_to_file "⚠ DNS resolution may be impaired"
        return 1
    fi
}

# ============================================================================
# STORAGE CHECKS
# ============================================================================

check_disk_space() {
    # Verify sufficient disk space available
    #
    # Arguments:
    #   None
    #
    # Returns:
    #   0 if sufficient space
    #   1 if insufficient space
    #
    # Example:
    #   check_disk_space || exit 1
    
    log_to_file "Checking disk space..."
    
    # Get available space in KB
    local available_kb=$(df / | tail -1 | awk '{print $4}')
    local available_gb=$((available_kb / 1024 / 1024))
    local required_kb=$((MIN_DISK_SPACE_GB * 1024 * 1024))
    
    if [[ $available_kb -lt $required_kb ]]; then
        log_to_file "ERROR: Insufficient disk space"
        log_to_file "  Available: ${available_gb}GB"
        log_to_file "  Required: ${MIN_DISK_SPACE_GB}GB"
        return 1
    fi
    
    log_to_file "✓ Sufficient disk space: ${available_gb}GB available"
    return 0
}

check_disk_write() {
    # Verify write permissions to installation directory
    #
    # Arguments:
    #   None
    #
    # Returns:
    #   0 if writable
    #   1 if not writable
    
    log_to_file "Checking write permissions..."
    
    local test_dir="${AEON_DIR}/test_$$"
    
    if mkdir -p "$test_dir" 2>/dev/null; then
        rmdir "$test_dir" 2>/dev/null
        log_to_file "✓ Write permissions verified"
        return 0
    else
        log_to_file "ERROR: Cannot write to $AEON_DIR"
        return 1
    fi
}

# ============================================================================
# TOOL MANAGEMENT
# ============================================================================

check_tool() {
    # Check if a single tool is available
    #
    # Arguments:
    #   $1 - Tool name
    #
    # Returns:
    #   0 if available
    #   1 if not available
    
    local tool="$1"
    command_exists "$tool"
}

get_package_manager() {
    # Detect available package manager
    #
    # Arguments:
    #   None
    #
    # Returns:
    #   Package manager name (apt-get, yum, dnf, brew, etc.)
    #   Empty string if none found
    
    if command_exists apt-get; then
        echo "apt-get"
    elif command_exists yum; then
        echo "yum"
    elif command_exists dnf; then
        echo "dnf"
    elif command_exists brew; then
        echo "brew"
    elif command_exists pacman; then
        echo "pacman"
    else
        echo ""
    fi
}

install_tool() {
    # Install a single tool using available package manager (SILENT)
    #
    # Arguments:
    #   $1 - Tool name
    #
    # Returns:
    #   0 on success
    #   1 on failure
    
    local tool="$1"
    local pkg_mgr=$(get_package_manager)
    
    if [[ -z "$pkg_mgr" ]]; then
        log_to_file "ERROR: No supported package manager found"
        return 1
    fi
    
    log_to_file "Installing $tool..."
    
    case "$pkg_mgr" in
        apt-get)
            apt-get update -qq &>/dev/null || true
            apt-get install -y -qq "$tool" &>/dev/null
            ;;
        yum)
            yum install -y -q "$tool" &>/dev/null
            ;;
        dnf)
            dnf install -y -q "$tool" &>/dev/null
            ;;
        brew)
            brew install "$tool" &>/dev/null
            ;;
        pacman)
            pacman -S --noconfirm "$tool" &>/dev/null
            ;;
    esac
    
    if check_tool "$tool"; then
        log_to_file "✓ $tool installed successfully"
        return 0
    else
        log_to_file "ERROR: Failed to install $tool"
        return 1
    fi
}

check_required_tools() {
    # Check and install all required tools (SILENT)
    #
    # Arguments:
    #   None
    #
    # Returns:
    #   0 if all tools available (after installation)
    #   1 if any required tool cannot be installed
    #
    # Example:
    #   check_required_tools || exit 1
    
    log_to_file "Checking required tools..."
    
    local missing_tools=()
    local failed_tools=()
    
    # Check which tools are missing
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! check_tool "$tool"; then
            missing_tools+=("$tool")
        fi
    done
    
    # If all tools present, we're done
    if [[ ${#missing_tools[@]} -eq 0 ]]; then
        log_to_file "✓ All required tools available"
        return 0
    fi
    
    # Install missing tools
    log_to_file "Missing tools: ${missing_tools[*]}"
    log_to_file "Installing missing tools..."
    
    for tool in "${missing_tools[@]}"; do
        if ! install_tool "$tool"; then
            failed_tools+=("$tool")
        fi
    done
    
    # Check if any installations failed
    if [[ ${#failed_tools[@]} -gt 0 ]]; then
        log_to_file "ERROR: Failed to install: ${failed_tools[*]}"
        log_to_file "Please install these tools manually"
        return 1
    fi
    
    log_to_file "✓ All required tools installed"
    return 0
}

check_optional_tools() {
    # Check optional tools (warn if missing, don't fail)
    #
    # Arguments:
    #   None
    #
    # Returns:
    #   Always 0
    
    log_to_file "Checking optional tools..."
    
    local missing_optional=()
    
    for tool in "${OPTIONAL_TOOLS[@]}"; do
        if ! check_tool "$tool"; then
            missing_optional+=("$tool")
        fi
    done
    
    if [[ ${#missing_optional[@]} -gt 0 ]]; then
        log_to_file "⚠ Optional tools not available: ${missing_optional[*]}"
        log_to_file "These are not required but recommended"
    else
        log_to_file "✓ All optional tools available"
    fi
    
    return 0
}

# ============================================================================
# DIRECTORY SETUP
# ============================================================================

create_directories() {
    # Create AEON directory structure
    #
    # Arguments:
    #   None
    #
    # Returns:
    #   0 on success
    #   1 on failure
    #
    # Example:
    #   create_directories || exit 1
    
    log_to_file "Creating AEON directory structure..."
    
    local directories=(
        "$AEON_DIR"
        "$LIB_DIR"
        "$REMOTE_DIR"
        "$CONFIG_DIR"
        "$DATA_DIR"
        "$LOG_DIR"
        "$REPORT_DIR"
        "$SECRETS_DIR"
    )
    
    local failed=0
    
    for dir in "${directories[@]}"; do
        local perms=755
        
        # Secrets directory gets restricted permissions
        if [[ "$dir" == "$SECRETS_DIR" ]]; then
            perms=700
        fi
        
        if ! ensure_directory "$dir" "$perms"; then
            log_to_file "ERROR: Failed to create: $dir"
            failed=1
        else
            log_to_file "✓ Created: $dir"
        fi
    done
    
    if [[ $failed -eq 1 ]]; then
        return 1
    fi
    
    log_to_file "✓ Directory structure created"
    return 0
}

verify_directories() {
    # Verify all directories exist and are writable
    #
    # Arguments:
    #   None
    #
    # Returns:
    #   0 if all verified
    #   1 if any issues
    
    log_to_file "Verifying directory structure..."
    
    local directories=(
        "$AEON_DIR"
        "$LIB_DIR"
        "$REMOTE_DIR"
        "$CONFIG_DIR"
        "$DATA_DIR"
        "$LOG_DIR"
        "$REPORT_DIR"
        "$SECRETS_DIR"
    )
    
    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_to_file "ERROR: Directory missing: $dir"
            return 1
        fi
        
        if [[ ! -w "$dir" ]]; then
            log_to_file "ERROR: Directory not writable: $dir"
            return 1
        fi
    done
    
    log_to_file "✓ All directories verified"
    return 0
}

# ============================================================================
# SYSTEM CHECKS
# ============================================================================

check_os_compatibility() {
    # Check if OS is supported
    #
    # Arguments:
    #   None
    #
    # Returns:
    #   0 if supported
    #   1 if not supported (with warning)
    
    log_to_file "Checking OS compatibility..."
    
    local os_type=$(uname -s)
    local os_release=""
    
    case "$os_type" in
        Linux)
            if [[ -f /etc/os-release ]]; then
                os_release=$(grep "^PRETTY_NAME=" /etc/os-release | cut -d'"' -f2)
                log_to_file "✓ Detected: $os_release"
                return 0
            else
                log_to_file "⚠ Unknown Linux distribution"
                return 0  # Continue anyway
            fi
            ;;
        Darwin)
            os_release=$(sw_vers -productVersion 2>/dev/null || echo "Unknown")
            log_to_file "✓ Detected: macOS $os_release"
            log_to_file "⚠ macOS support is experimental"
            return 0
            ;;
        *)
            log_to_file "⚠ Unsupported OS: $os_type"
            log_to_file "AEON is designed for Linux, continuing anyway"
            return 0  # Continue anyway
            ;;
    esac
}

check_system_resources() {
    # Check system has adequate resources
    #
    # Arguments:
    #   None
    #
    # Returns:
    #   0 always (informational only)
    
    log_to_file "Checking system resources..."
    
    # Get CPU cores
    local cpu_cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "unknown")
    
    # Get total RAM in GB
    local ram_gb="unknown"
    if [[ -f /proc/meminfo ]]; then
        local ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        ram_gb=$((ram_kb / 1024 / 1024))
    fi
    
    log_to_file "System resources: CPU cores: $cpu_cores, RAM: ${ram_gb}GB"
    
    return 0
}

# ============================================================================
# ORCHESTRATION
# ============================================================================

run_preflight_checks() {
    # Main preflight check orchestration with progress tracking
    #
    # Arguments:
    #   None
    #
    # Returns:
    #   0 if all checks pass
    #   1 if any critical check fails
    
    start_phase 1
    
    local has_warnings=false
    
    # All output goes to log file
    {
        log_to_file "═══════════════════════════════════════════════════════════"
        log_to_file "Starting Pre-flight Checks"
        log_to_file "═══════════════════════════════════════════════════════════"
        
        # Critical checks (0-10%)
        log_to_file ""
        log_to_file "--- Critical Checks ---"
        if ! check_root; then
            complete_phase "failed" "Root check failed"
            return 1
        fi
        update_phase_progress 10
        
        # Bash version (10-15%)
        if ! check_bash_version; then
            complete_phase "failed" "Bash version too old"
            return 1
        fi
        update_phase_progress 15
        
        # Internet connectivity (15-30%)
        if ! check_internet; then
            complete_phase "failed" "No internet connection"
            return 1
        fi
        update_phase_progress 30
        
        # Disk space (30-40%)
        if ! check_disk_space; then
            complete_phase "failed" "Insufficient disk space"
            return 1
        fi
        update_phase_progress 40
        
        # Write permissions (40-45%)
        if ! check_disk_write; then
            complete_phase "failed" "No write permissions"
            return 1
        fi
        update_phase_progress 45
        
        # Required tools (45-70%)
        if ! check_required_tools; then
            complete_phase "failed" "Missing required tools"
            return 1
        fi
        update_phase_progress 70
        
        # Directory creation (70-85%)
        if ! create_directories; then
            complete_phase "failed" "Directory creation failed"
            return 1
        fi
        update_phase_progress 85
        
        # Directory verification (85-90%)
        if ! verify_directories; then
            complete_phase "failed" "Directory verification failed"
            return 1
        fi
        update_phase_progress 90
        
        # Informational checks (90-100%)
        log_to_file ""
        log_to_file "--- Informational Checks ---"
        
        if ! check_dns_resolution; then
            has_warnings=true
        fi
        update_phase_progress 93
        
        check_optional_tools || true
        update_phase_progress 96
        
        check_os_compatibility || true
        update_phase_progress 98
        
        check_system_resources || true
        update_phase_progress 100
        
        log_to_file ""
        log_to_file "═══════════════════════════════════════════════════════════"
        log_to_file "Pre-flight Checks Complete"
        log_to_file "═══════════════════════════════════════════════════════════"
        
    } 2>&1  # Redirect all output to log
    
    if [[ "$has_warnings" == true ]]; then
        complete_phase "completed_warnings" "See log for details"
    else
        complete_phase "completed"
    fi
    
    return 0
}

# ============================================================================
# INITIALIZATION
# ============================================================================

log_debug "AEON pre-flight module loaded"

# Export functions
export -f check_root check_bash_version 2>/dev/null || true
export -f check_internet check_dns_resolution 2>/dev/null || true
export -f check_disk_space check_disk_write 2>/dev/null || true
export -f check_tool install_tool check_required_tools 2>/dev/null || true
export -f create_directories verify_directories 2>/dev/null || true
export -f run_preflight_checks 2>/dev/null || true

return 0
