#!/bin/bash
################################################################################
# AEON Dependency Installer
# File: remote/install_dependencies.sh
# Version: 0.1.0
#
# Purpose: Comprehensive dependency installation script executed on each
#          remote device to prepare for AEON cluster participation.
#
# Usage:
#   bash install_dependencies.sh [--manager-ip <ip>] [--role <manager|worker>]
#
# This script installs:
#   - System packages (curl, wget, jq, git, etc.)
#   - Docker Engine (24.0+)
#   - Docker Compose (2.20+)
#   - Python dependencies
#   - System configuration for Docker Swarm
#
# Exit codes:
#   0 - Success
#   1 - Critical failure
#   2 - Success but reboot required
################################################################################

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_VERSION="0.1.0"
INSTALL_LOG="/var/log/aeon_install.log"
TEMP_DIR="/tmp/aeon_install_$$"

# Minimum versions
MIN_DOCKER_VERSION="24.0"
MIN_COMPOSE_VERSION="2.20"

# Package lists
SYSTEM_PACKAGES=(
    "curl"
    "wget"
    "git"
    "jq"
    "net-tools"
    "nmap"
    "avahi-daemon"
    "python3"
    "python3-pip"
    "lsb-release"
    "ca-certificates"
    "gnupg"
    "software-properties-common"
    "apt-transport-https"
)

PYTHON_PACKAGES=(
    "requests"
    "pyyaml"
    "netifaces"
    "psutil"
    "rich"
    "docker"
)

# Flags
DOCKER_INSTALLED=false
DOCKER_JUST_INSTALLED=false
REBOOT_REQUIRED=false
MANAGER_IP=""
NODE_ROLE="worker"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Write to log file
    echo "[$timestamp] [$level] $message" >> "$INSTALL_LOG"
    
    # Write to stdout with color
    case "$level" in
        ERROR)
            echo -e "${RED}❌ ERROR: $message${NC}" >&2
            ;;
        WARN)
            echo -e "${YELLOW}⚠️  WARNING: $message${NC}"
            ;;
        INFO)
            echo -e "${CYAN}ℹ️  $message${NC}"
            ;;
        SUCCESS)
            echo -e "${GREEN}✅ $message${NC}"
            ;;
        STEP)
            echo -e "${BOLD}${BLUE}▶ $message${NC}"
            ;;
        DEBUG)
            if [[ "${DEBUG:-0}" == "1" ]]; then
                echo -e "${BLUE}🔍 $message${NC}"
            fi
            ;;
    esac
}

print_header() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_separator() {
    echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

version_ge() {
    # Compare versions: return 0 if $1 >= $2
    local ver1="$1"
    local ver2="$2"
    
    if [[ "$ver1" == "$ver2" ]]; then
        return 0
    fi
    
    local IFS=.
    local i ver1_arr=($ver1) ver2_arr=($ver2)
    
    for ((i=0; i<${#ver1_arr[@]} || i<${#ver2_arr[@]}; i++)); do
        local v1=${ver1_arr[i]:-0}
        local v2=${ver2_arr[i]:-0}
        
        if ((v1 > v2)); then
            return 0
        elif ((v1 < v2)); then
            return 1
        fi
    done
    
    return 0
}

check_internet() {
    log INFO "Checking internet connectivity..."
    
    if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        log SUCCESS "Internet connection: OK"
        return 0
    else
        log ERROR "No internet connection detected"
        return 1
    fi
}

check_disk_space() {
    log INFO "Checking available disk space..."
    
    local available=$(df / | tail -1 | awk '{print $4}')
    local required=5000000  # 5GB in KB
    
    if [[ $available -lt $required ]]; then
        log ERROR "Insufficient disk space"
        log ERROR "  Available: $((available / 1024))MB"
        log ERROR "  Required: $((required / 1024))MB"
        return 1
    fi
    
    log SUCCESS "Disk space: OK ($((available / 1024 / 1024))GB available)"
    return 0
}

# ============================================================================
# OS DETECTION
# ============================================================================

detect_os() {
    log STEP "Detecting operating system..."
    
    if [[ ! -f /etc/os-release ]]; then
        log ERROR "Cannot detect OS (missing /etc/os-release)"
        return 1
    fi
    
    source /etc/os-release
    
    OS_ID="$ID"
    OS_VERSION="$VERSION_ID"
    OS_CODENAME="${VERSION_CODENAME:-unknown}"
    OS_PRETTY="$PRETTY_NAME"
    
    log INFO "Operating System: $OS_PRETTY"
    log INFO "  ID: $OS_ID"
    log INFO "  Version: $OS_VERSION"
    log INFO "  Codename: $OS_CODENAME"
    
    # Detect architecture
    ARCH=$(uname -m)
    log INFO "  Architecture: $ARCH"
    
    # Detect package manager
    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt"
        PKG_UPDATE="apt-get update -qq"
        PKG_INSTALL="apt-get install -y -qq"
        log INFO "  Package Manager: APT"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
        PKG_UPDATE="dnf check-update -q"
        PKG_INSTALL="dnf install -y -q"
        log INFO "  Package Manager: DNF"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
        PKG_UPDATE="yum check-update -q"
        PKG_INSTALL="yum install -y -q"
        log INFO "  Package Manager: YUM"
    else
        log ERROR "Unsupported package manager"
        return 1
    fi
    
    # Detect device type
    if grep -qi "raspberry" /proc/cpuinfo; then
        DEVICE_TYPE="raspberry_pi"
        
        if grep -qi "Pi 5" /proc/cpuinfo; then
            DEVICE_MODEL="pi5"
        elif grep -qi "Pi 4" /proc/cpuinfo; then
            DEVICE_MODEL="pi4"
        elif grep -qi "Pi 3" /proc/cpuinfo; then
            DEVICE_MODEL="pi3"
        else
            DEVICE_MODEL="unknown_pi"
        fi
        
        log INFO "  Device Type: Raspberry Pi ($DEVICE_MODEL)"
    else
        DEVICE_TYPE="computer"
        DEVICE_MODEL="generic"
        log INFO "  Device Type: Standard Computer"
    fi
    
    log SUCCESS "OS detection complete"
    return 0
}

# ============================================================================
# EXISTING INSTALLATION CHECK
# ============================================================================

check_existing_installation() {
    log STEP "Checking for existing installations..."
    
    # Docker check
    if command -v docker &>/dev/null; then
        local docker_version=$(docker --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
        
        if [[ -n "$docker_version" ]]; then
            local docker_major_minor=$(echo "$docker_version" | cut -d. -f1,2)
            
            if version_ge "$docker_major_minor" "$MIN_DOCKER_VERSION"; then
                log SUCCESS "Docker $docker_version already installed"
                DOCKER_INSTALLED=true
            else
                log WARN "Docker $docker_version is outdated (need ≥$MIN_DOCKER_VERSION)"
                DOCKER_INSTALLED=false
            fi
        else
            DOCKER_INSTALLED=false
        fi
    else
        log INFO "Docker not installed"
        DOCKER_INSTALLED=false
    fi
    
    # Docker Compose check
    if docker compose version &>/dev/null; then
        local compose_version=$(docker compose version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
        
        if [[ -n "$compose_version" ]]; then
            log SUCCESS "Docker Compose $compose_version already installed"
        fi
    else
        log INFO "Docker Compose not installed"
    fi
    
    # Python check
    if command -v python3 &>/dev/null; then
        local python_version=$(python3 --version | grep -oP '\d+\.\d+\.\d+')
        log SUCCESS "Python3 $python_version already installed"
    else
        log INFO "Python3 not installed"
    fi
    
    return 0
}

# ============================================================================
# SYSTEM PACKAGES INSTALLATION
# ============================================================================

install_system_packages() {
    log STEP "Installing system packages..."
    
    # Update package lists
    log INFO "Updating package lists..."
    
    local update_attempts=0
    local update_max_attempts=3
    
    while [[ $update_attempts -lt $update_max_attempts ]]; do
        if eval "$PKG_UPDATE" &>/dev/null; then
            log SUCCESS "Package lists updated"
            break
        else
            ((update_attempts++))
            if [[ $update_attempts -lt $update_max_attempts ]]; then
                log WARN "Update failed (attempt $update_attempts/$update_max_attempts), retrying..."
                sleep 5
            else
                log ERROR "Failed to update package lists after $update_max_attempts attempts"
                return 1
            fi
        fi
    done
    
    # Install packages
    local installed=0
    local already_installed=0
    local failed=0
    
    for pkg in "${SYSTEM_PACKAGES[@]}"; do
        # Check if already installed
        if dpkg -l 2>/dev/null | grep -q "^ii  $pkg "; then
            log DEBUG "$pkg already installed"
            ((already_installed++))
            continue
        fi
        
        log INFO "Installing $pkg..."
        
        local install_attempts=0
        local install_max_attempts=3
        local success=false
        
        while [[ $install_attempts -lt $install_max_attempts ]]; do
            if eval "$PKG_INSTALL $pkg" &>/dev/null; then
                log SUCCESS "$pkg installed"
                ((installed++))
                success=true
                break
            else
                ((install_attempts++))
                if [[ $install_attempts -lt $install_max_attempts ]]; then
                    log WARN "$pkg installation failed (attempt $install_attempts/$install_max_attempts), retrying..."
                    sleep 3
                fi
            fi
        done
        
        if [[ "$success" == "false" ]]; then
            log ERROR "Failed to install $pkg after $install_max_attempts attempts"
            ((failed++))
        fi
    done
    
    print_separator
    log INFO "System packages summary:"
    log INFO "  Newly installed: $installed"
    log INFO "  Already installed: $already_installed"
    
    if [[ $failed -gt 0 ]]; then
        log WARN "  Failed: $failed"
    fi
    
    if [[ $failed -eq 0 ]]; then
        log SUCCESS "All system packages installed successfully"
        return 0
    else
        log ERROR "Some system packages failed to install"
        return 1
    fi
}

# ============================================================================
# DOCKER INSTALLATION
# ============================================================================

install_docker() {
    if [[ "$DOCKER_INSTALLED" == "true" ]]; then
        log INFO "Docker already installed, skipping"
        return 0
    fi
    
    log STEP "Installing Docker Engine..."
    
    # Download Docker installation script
    log INFO "Downloading Docker installation script..."
    
    if ! curl -fsSL https://get.docker.com -o "$TEMP_DIR/get-docker.sh"; then
        log ERROR "Failed to download Docker installation script"
        return 1
    fi
    
    log SUCCESS "Docker script downloaded"
    
    # Execute installation script
    log INFO "Running Docker installation (this may take several minutes)..."
    
    if sh "$TEMP_DIR/get-docker.sh" &>> "$INSTALL_LOG"; then
        log SUCCESS "Docker installed successfully"
        DOCKER_JUST_INSTALLED=true
    else
        log ERROR "Docker installation failed"
        log ERROR "Check log file: $INSTALL_LOG"
        return 1
    fi
    
    # Enable Docker service
    log INFO "Enabling Docker service..."
    
    systemctl enable docker &>/dev/null || log WARN "Failed to enable Docker service"
    systemctl start docker &>/dev/null || log WARN "Failed to start Docker service"
    
    # Add user to docker group
    local current_user="${SUDO_USER:-$USER}"
    
    if [[ "$current_user" != "root" ]]; then
        log INFO "Adding user '$current_user' to docker group..."
        usermod -aG docker "$current_user" || log WARN "Failed to add user to docker group"
    fi
    
    # Verify installation
    log INFO "Verifying Docker installation..."
    
    sleep 2  # Give Docker a moment to fully start
    
    if docker run --rm hello-world &>/dev/null; then
        local docker_version=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
        log SUCCESS "Docker $docker_version verified and working"
    else
        log WARN "Docker verification failed (may require reboot)"
    fi
    
    # Clean up
    rm -f "$TEMP_DIR/get-docker.sh"
    
    return 0
}

# ============================================================================
# DOCKER COMPOSE INSTALLATION
# ============================================================================

install_docker_compose() {
    log STEP "Installing Docker Compose..."
    
    # Check if already installed
    if docker compose version &>/dev/null; then
        local compose_version=$(docker compose version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
        local compose_major_minor=$(echo "$compose_version" | cut -d. -f1,2)
        
        if version_ge "$compose_major_minor" "$MIN_COMPOSE_VERSION"; then
            log SUCCESS "Docker Compose $compose_version already installed"
            return 0
        else
            log WARN "Docker Compose $compose_version is outdated (need ≥$MIN_COMPOSE_VERSION)"
        fi
    fi
    
    # Install Docker Compose plugin
    case "$PKG_MANAGER" in
        apt)
            log INFO "Installing docker-compose-plugin..."
            
            if eval "$PKG_INSTALL docker-compose-plugin" &>/dev/null; then
                log SUCCESS "Docker Compose plugin installed"
            else
                log WARN "Failed to install via apt, trying manual installation..."
                install_docker_compose_manual
            fi
            ;;
        *)
            log INFO "Installing Docker Compose manually..."
            install_docker_compose_manual
            ;;
    esac
    
    # Verify installation
    if docker compose version &>/dev/null; then
        local compose_version=$(docker compose version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
        log SUCCESS "Docker Compose $compose_version installed and verified"
        return 0
    else
        log ERROR "Docker Compose verification failed"
        return 1
    fi
}

install_docker_compose_manual() {
    local compose_version="2.24.0"
    
    log INFO "Downloading Docker Compose v$compose_version..."
    
    # Determine architecture
    local arch_suffix=""
    case "$ARCH" in
        x86_64)
            arch_suffix="x86_64"
            ;;
        aarch64)
            arch_suffix="aarch64"
            ;;
        armv7l)
            arch_suffix="armv7"
            ;;
        *)
            log ERROR "Unsupported architecture for manual Compose installation: $ARCH"
            return 1
            ;;
    esac
    
    local compose_url="https://github.com/docker/compose/releases/download/v${compose_version}/docker-compose-linux-${arch_suffix}"
    
    if curl -SL "$compose_url" -o /usr/local/bin/docker-compose; then
        chmod +x /usr/local/bin/docker-compose
        log SUCCESS "Docker Compose downloaded and installed to /usr/local/bin/docker-compose"
        return 0
    else
        log ERROR "Failed to download Docker Compose"
        return 1
    fi
}

# ============================================================================
# PYTHON DEPENDENCIES
# ============================================================================

install_python_packages() {
    log STEP "Installing Python packages..."
    
    # Ensure pip is available
    if ! command -v pip3 &>/dev/null; then
        log ERROR "pip3 not found (should have been installed with python3-pip)"
        return 1
    fi
    
    # Upgrade pip
    log INFO "Upgrading pip..."
    python3 -m pip install --upgrade pip --break-system-packages &>/dev/null || \
        log WARN "Failed to upgrade pip"
    
    # Install packages
    local installed=0
    local already_installed=0
    local failed=0
    
    for pkg in "${PYTHON_PACKAGES[@]}"; do
        # Check if already installed
        if python3 -c "import ${pkg//-/_}" &>/dev/null; then
            log DEBUG "Python package '$pkg' already installed"
            ((already_installed++))
            continue
        fi
        
        log INFO "Installing Python package: $pkg..."
        
        if python3 -m pip install "$pkg" --break-system-packages &>/dev/null; then
            log SUCCESS "$pkg installed"
            ((installed++))
        else
            log ERROR "Failed to install $pkg"
            ((failed++))
        fi
    done
    
    print_separator
    log INFO "Python packages summary:"
    log INFO "  Newly installed: $installed"
    log INFO "  Already installed: $already_installed"
    
    if [[ $failed -gt 0 ]]; then
        log WARN "  Failed: $failed"
    fi
    
    if [[ $failed -eq 0 ]]; then
        log SUCCESS "All Python packages installed successfully"
        return 0
    else
        log WARN "Some Python packages failed to install"
        return 0  # Non-critical
    fi
}

# ============================================================================
# SYSTEM CONFIGURATION
# ============================================================================

configure_system() {
    log STEP "Configuring system for AEON..."
    
    # Enable services
    log INFO "Enabling required services..."
    
    systemctl enable docker &>/dev/null || log WARN "Failed to enable docker"
    systemctl enable avahi-daemon &>/dev/null || log WARN "Failed to enable avahi-daemon"
    
    systemctl start avahi-daemon &>/dev/null || log WARN "Failed to start avahi-daemon"
    
    # Configure firewall if UFW is active
    if systemctl is-active --quiet ufw 2>/dev/null; then
        log INFO "Configuring UFW firewall for Docker Swarm..."
        
        ufw allow 2376/tcp comment 'Docker daemon' &>/dev/null
        ufw allow 2377/tcp comment 'Swarm management' &>/dev/null
        ufw allow 7946/tcp comment 'Swarm node communication' &>/dev/null
        ufw allow 7946/udp comment 'Swarm node communication' &>/dev/null
        ufw allow 4789/udp comment 'Overlay network' &>/dev/null
        
        ufw reload &>/dev/null
        
        log SUCCESS "Firewall configured"
    fi
    
    # Raspberry Pi specific optimizations
    if [[ "$DEVICE_TYPE" == "raspberry_pi" ]]; then
        log INFO "Applying Raspberry Pi optimizations..."
        
        # Enable cgroup memory (required for Docker)
        if [[ -f /boot/cmdline.txt ]]; then
            if ! grep -q "cgroup_enable=memory" /boot/cmdline.txt; then
                log INFO "Enabling cgroup memory in /boot/cmdline.txt..."
                sed -i '1 s/$/ cgroup_enable=memory cgroup_memory=1/' /boot/cmdline.txt
                REBOOT_REQUIRED=true
                log SUCCESS "Cgroup memory enabled (reboot required)"
            else
                log INFO "Cgroup memory already enabled"
            fi
        elif [[ -f /boot/firmware/cmdline.txt ]]; then
            # Ubuntu on Pi uses different path
            if ! grep -q "cgroup_enable=memory" /boot/firmware/cmdline.txt; then
                log INFO "Enabling cgroup memory in /boot/firmware/cmdline.txt..."
                sed -i '1 s/$/ cgroup_enable=memory cgroup_memory=1/' /boot/firmware/cmdline.txt
                REBOOT_REQUIRED=true
                log SUCCESS "Cgroup memory enabled (reboot required)"
            else
                log INFO "Cgroup memory already enabled"
            fi
        fi
        
        # Increase swap if needed (for small RAM Pis)
        local ram_gb=$(free -g | grep Mem | awk '{print $2}')
        
        if [[ $ram_gb -lt 4 ]]; then
            log INFO "Low RAM detected (${ram_gb}GB), checking swap..."
            
            local swap_size=$(free -m | grep Swap | awk '{print $2}')
            
            if [[ $swap_size -lt 2048 ]]; then
                log WARN "Swap size is low (${swap_size}MB), consider increasing"
                # Note: Not automatically changing swap as it can be risky
            fi
        fi
    fi
    
    log SUCCESS "System configuration complete"
    return 0
}

# ============================================================================
# REBOOT CHECK
# ============================================================================

check_reboot_required() {
    log STEP "Checking if reboot is required..."
    
    # Check for kernel updates
    if [[ -f /var/run/reboot-required ]]; then
        REBOOT_REQUIRED=true
        log WARN "Reboot required (kernel update)"
    fi
    
    # Check if Docker config changed
    if [[ "$DOCKER_JUST_INSTALLED" == "true" ]] && [[ "$DEVICE_TYPE" == "raspberry_pi" ]]; then
        if grep -q "cgroup_enable=memory" /boot/cmdline.txt 2>/dev/null || \
           grep -q "cgroup_enable=memory" /boot/firmware/cmdline.txt 2>/dev/null; then
            REBOOT_REQUIRED=true
            log WARN "Reboot required (Docker configuration)"
        fi
    fi
    
    if [[ "$REBOOT_REQUIRED" == "true" ]]; then
        log WARN "⚠️  REBOOT REQUIRED"
        echo "REBOOT_REQUIRED"
        return 2
    else
        log SUCCESS "No reboot required"
        echo "NO_REBOOT"
        return 0
    fi
}

# ============================================================================
# INSTALLATION VERIFICATION
# ============================================================================

verify_installation() {
    log STEP "Verifying installation..."
    
    local errors=0
    
    # Docker version check
    if command -v docker &>/dev/null; then
        local docker_version=$(docker --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
        local docker_major_minor=$(echo "$docker_version" | cut -d. -f1,2)
        
        if version_ge "$docker_major_minor" "$MIN_DOCKER_VERSION"; then
            log SUCCESS "✓ Docker version: $docker_version (≥$MIN_DOCKER_VERSION)"
        else
            log ERROR "✗ Docker version check failed: $docker_version < $MIN_DOCKER_VERSION"
            ((errors++))
        fi
    else
        log ERROR "✗ Docker not found"
        ((errors++))
    fi
    
    # Docker Compose check
    if docker compose version &>/dev/null; then
        local compose_version=$(docker compose version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
        log SUCCESS "✓ Docker Compose version: $compose_version"
    else
        log ERROR "✗ Docker Compose not found"
        ((errors++))
    fi
    
    # Docker service check
    if systemctl is-active --quiet docker; then
        log SUCCESS "✓ Docker service running"
    else
        log ERROR "✗ Docker service not running"
        ((errors++))
    fi
    
    # Docker network check
    if docker network ls &>/dev/null; then
        log SUCCESS "✓ Docker network accessible"
    else
        log ERROR "✗ Docker network check failed"
        ((errors++))
    fi
    
    # Python check
    if command -v python3 &>/dev/null; then
        local python_version=$(python3 --version | grep -oP '\d+\.\d+\.\d+')
        log SUCCESS "✓ Python3 version: $python_version"
    else
        log WARN "✗ Python3 not found"
    fi
    
    # System packages check
    local missing_packages=0
    for pkg in curl wget jq git; do
        if ! command -v "$pkg" &>/dev/null; then
            log WARN "✗ $pkg not found"
            ((missing_packages++))
        fi
    done
    
    if [[ $missing_packages -eq 0 ]]; then
        log SUCCESS "✓ All essential system packages present"
    fi
    
    print_separator
    
    if [[ $errors -eq 0 ]]; then
        log SUCCESS "✅ All verifications passed"
        return 0
    else
        log ERROR "❌ $errors verification(s) failed"
        return 1
    fi
}

# ============================================================================
# CLEANUP
# ============================================================================

cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

print_banner() {
    clear
    echo ""
    echo -e "${BOLD}${CYAN}"
    cat << 'BANNER'
     █████╗ ███████╗ ██████╗ ███╗   ██╗
    ██╔══██╗██╔════╝██╔═══██╗████╗  ██║
    ███████║█████╗  ██║   ██║██╔██╗ ██║
    ██╔══██║██╔══╝  ██║   ██║██║╚██╗██║
    ██║  ██║███████╗╚██████╔╝██║ ╚████║
    ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝
BANNER
    echo -e "${NC}"
    echo -e "  ${CYAN}Dependency Installation Script v$SCRIPT_VERSION${NC}"
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --manager-ip)
                MANAGER_IP="$2"
                shift 2
                ;;
            --role)
                NODE_ROLE="$2"
                shift 2
                ;;
            --debug)
                DEBUG=1
                shift
                ;;
            *)
                log WARN "Unknown argument: $1"
                shift
                ;;
        esac
    done
}

main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Create temp directory
    mkdir -p "$TEMP_DIR"
    
    # Set cleanup trap
    trap cleanup EXIT
    
    print_banner
    
    # Pre-flight checks
    print_header "Pre-flight Checks"
    check_internet || exit 1
    check_disk_space || exit 1
    
    # System detection
    print_header "System Detection"
    detect_os || exit 1
    check_existing_installation
    
    # Installation phases
    print_header "Phase 1: System Packages"
    install_system_packages || exit 1
    
    print_header "Phase 2: Docker Engine"
    install_docker || exit 1
    
    print_header "Phase 3: Docker Compose"
    install_docker_compose || exit 1
    
    print_header "Phase 4: Python Dependencies"
    install_python_packages || exit 0  # Non-critical
    
    print_header "Phase 5: System Configuration"
    configure_system || exit 1
    
    print_header "Phase 6: Reboot Check"
    reboot_status=$(check_reboot_required)
    
    print_header "Phase 7: Verification"
    verify_installation || exit 1
    
    # Final summary
    echo ""
    print_header "Installation Complete"
    
    log SUCCESS "All dependencies installed successfully!"
    echo ""
    
    if [[ "$REBOOT_REQUIRED" == "true" ]]; then
        log WARN "⚠️  REBOOT REQUIRED"
        log WARN "Some changes require a system reboot to take effect."
        echo ""
        exit 2
    else
        log SUCCESS "System ready for AEON cluster participation"
        echo ""
        exit 0
    fi
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    echo "Please run: sudo bash $0"
    exit 1
fi

# Execute main
main "$@"
