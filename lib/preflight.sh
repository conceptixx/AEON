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
################################################################################

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || {
    echo "ERROR: Failed to source common.sh" >&2
    exit 1
}

# Prevent double-sourcing
[[ -n "${AEON_PREFLIGHT_LOADED:-}" ]] && return 0
readonly AEON_PREFLIGHT_LOADED=1

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
)

# Optional tools (warn if missing, but don't fail)
readonly OPTIONAL_TOOLS=(
    "nmap"
    "bc"
    "docker"
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
    
    log STEP "Checking root privileges..."
    
    if ! is_root; then
        log ERROR "This script must be run as root"
        echo ""
        echo -e "${YELLOW}Please run with sudo:${NC}"
        echo -e "  ${CYAN}sudo bash $0${NC}"
        echo ""
        exit 1
    fi
    
    log SUCCESS "Running as root"
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
    
    log STEP "Checking bash version..."
    
    local major_version="${BASH_VERSINFO[0]}"
    
    if [[ $major_version -lt $REQUIRED_BASH_VERSION ]]; then
        log ERROR "Bash version $REQUIRED_BASH_VERSION or higher required"
        log ERROR "Current version: $BASH_VERSION"
        return 1
    fi
    
    log SUCCESS "Bash version: $BASH_VERSION"
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
    
    log STEP "Checking internet connectivity..."
    
    # Try multiple DNS servers
    local dns_servers=(
        "8.8.8.8"          # Google DNS
        "1.1.1.1"          # Cloudflare DNS
        "9.9.9.9"          # Quad9 DNS
    )
    
    for dns in "${dns_servers[@]}"; do
        if ping -c 1 -W 3 "$dns" &>/dev/null; then
            log SUCCESS "Internet connection available"
            return 0
        fi
    done
    
    log ERROR "No internet connection detected"
    log INFO "Internet is required for:"
    log INFO "  • Package installation"
    log INFO "  • Docker installation"
    log INFO "  • Repository downloads"
    echo ""
    log INFO "Please check your network connection and try again"
    
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
    
    log STEP "Checking DNS resolution..."
    
    if host github.com &>/dev/null || nslookup github.com &>/dev/null; then
        log SUCCESS "DNS resolution working"
        return 0
    else
        log WARN "DNS resolution may be impaired"
        log INFO "This may cause issues downloading packages"
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
    
    log STEP "Checking disk space..."
    
    # Get available space in KB
    local available_kb=$(df / | tail -1 | awk '{print $4}')
    local available_gb=$((available_kb / 1024 / 1024))
    local required_kb=$((MIN_DISK_SPACE_GB * 1024 * 1024))
    
    if [[ $available_kb -lt $required_kb ]]; then
        log ERROR "Insufficient disk space"
        log ERROR "  Available: ${available_gb}GB"
        log ERROR "  Required: ${MIN_DISK_SPACE_GB}GB"
        echo ""
        log INFO "Please free up disk space and try again"
        log INFO "You can check disk usage with: df -h /"
        
        return 1
    fi
    
    log SUCCESS "Sufficient disk space: ${available_gb}GB available"
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
    
    log STEP "Checking write permissions..."
    
    local test_dir="${AEON_DIR}/test_$$"
    
    if mkdir -p "$test_dir" 2>/dev/null; then
        rmdir "$test_dir" 2>/dev/null
        log SUCCESS "Write permissions verified"
        return 0
    else
        log ERROR "Cannot write to $AEON_DIR"
        log INFO "Please check directory permissions"
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
    # Install a single tool using available package manager
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
        log ERROR "No supported package manager found"
        return 1
    fi
    
    log INFO "Installing $tool..."
    
    case "$pkg_mgr" in
        apt-get)
            apt-get update -qq 2>/dev/null || true
            apt-get install -y -qq "$tool" 2>/dev/null
            ;;
        yum)
            yum install -y -q "$tool" 2>/dev/null
            ;;
        dnf)
            dnf install -y -q "$tool" 2>/dev/null
            ;;
        brew)
            brew install "$tool" 2>/dev/null
            ;;
        pacman)
            pacman -S --noconfirm "$tool" 2>/dev/null
            ;;
    esac
    
    if check_tool "$tool"; then
        log SUCCESS "$tool installed successfully"
        return 0
    else
        log ERROR "Failed to install $tool"
        return 1
    fi
}

check_required_tools() {
    # Check and install all required tools
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
    
    log STEP "Checking required tools..."
    
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
        log SUCCESS "All required tools available"
        return 0
    fi
    
    # Install missing tools
    log WARN "Missing tools: ${missing_tools[*]}"
    log INFO "Installing missing tools..."
    echo ""
    
    for tool in "${missing_tools[@]}"; do
        if ! install_tool "$tool"; then
            failed_tools+=("$tool")
        fi
    done
    
    # Check if any installations failed
    if [[ ${#failed_tools[@]} -gt 0 ]]; then
        log ERROR "Failed to install: ${failed_tools[*]}"
        echo ""
        log INFO "Please install these tools manually:"
        for tool in "${failed_tools[@]}"; do
            log INFO "  • $tool"
        done
        return 1
    fi
    
    echo ""
    log SUCCESS "All required tools installed"
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
    
    log STEP "Checking optional tools..."
    
    local missing_optional=()
    
    for tool in "${OPTIONAL_TOOLS[@]}"; do
        if ! check_tool "$tool"; then
            missing_optional+=("$tool")
        fi
    done
    
    if [[ ${#missing_optional[@]} -gt 0 ]]; then
        log WARN "Optional tools not available: ${missing_optional[*]}"
        log INFO "These are not required but recommended"
    else
        log SUCCESS "All optional tools available"
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
    
    log STEP "Creating AEON directory structure..."
    
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
            log ERROR "Failed to create: $dir"
            failed=1
        fi
    done
    
    if [[ $failed -eq 1 ]]; then
        return 1
    fi
    
    log SUCCESS "Directory structure created"
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
    
    log STEP "Verifying directory structure..."
    
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
            log ERROR "Directory missing: $dir"
            return 1
        fi
        
        if [[ ! -w "$dir" ]]; then
            log ERROR "Directory not writable: $dir"
            return 1
        fi
    done
    
    log SUCCESS "All directories verified"
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
    
    log STEP "Checking OS compatibility..."
    
    local os_type=$(uname -s)
    local os_release=""
    
    case "$os_type" in
        Linux)
            if [[ -f /etc/os-release ]]; then
                os_release=$(grep "^PRETTY_NAME=" /etc/os-release | cut -d'"' -f2)
                log SUCCESS "Detected: $os_release"
                return 0
            else
                log WARN "Unknown Linux distribution"
                return 0  # Continue anyway
            fi
            ;;
        Darwin)
            os_release=$(sw_vers -productVersion 2>/dev/null || echo "Unknown")
            log SUCCESS "Detected: macOS $os_release"
            log WARN "macOS support is experimental"
            return 0
            ;;
        *)
            log WARN "Unsupported OS: $os_type"
            log INFO "AEON is designed for Linux"
            log INFO "Continuing anyway, but issues may occur"
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
    
    log STEP "Checking system resources..."
    
    # Get CPU cores
    local cpu_cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "unknown")
    
    # Get total RAM in GB
    local ram_gb="unknown"
    if [[ -f /proc/meminfo ]]; then
        local ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        ram_gb=$((ram_kb / 1024 / 1024))
    fi
    
    log INFO "System resources:"
    log INFO "  • CPU cores: $cpu_cores"
    log INFO "  • RAM: ${ram_gb}GB"
    
    return 0
}

# ============================================================================
# ORCHESTRATION
# ============================================================================

run_preflight_checks() {
    # Main function - run all pre-flight checks in order
    #
    # Arguments:
    #   None
    #
    # Returns:
    #   0 if all checks pass
    #   Exits with 1 if any critical check fails
    #
    # Example:
    #   run_preflight_checks || exit 1
    
    print_header "Pre-flight Checks"
    
    # Critical checks (exit on failure)
    check_root || exit 1
    check_bash_version || exit 1
    check_internet || exit 1
    check_disk_space || exit 1
    check_disk_write || exit 1
    check_required_tools || exit 1
    create_directories || exit 1
    verify_directories || exit 1
    
    # Informational checks (continue on failure)
    check_dns_resolution || true
    check_optional_tools || true
    check_os_compatibility || true
    check_system_resources || true
    
    echo ""
    log SUCCESS "All pre-flight checks passed"
    echo ""
    
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
