#!/usr/bin/env bash
################################################################################
# AEON Bootstrap Installer
# File: bootstrap.sh
# Version: 0.1.0
################################################################################

# ============================================================================
# SELF-EXTRACTION FOR PIPED EXECUTION
# ============================================================================
if [[ "${AEON_BOOTSTRAP_REEXEC:-}" != "true" ]]; then
    if [[ ! -t 0 ]]; then
        TEMP_SCRIPT="/tmp/aeon-bootstrap-$$.sh"
        
        # Read script content and save to temp
        cat > "$TEMP_SCRIPT"
        chmod +x "$TEMP_SCRIPT"
        
        # Re-execute from temp file
        AEON_BOOTSTRAP_REEXEC=true exec "$TEMP_SCRIPT" "$@"
        
        # Cleanup on failure
        rm -f "$TEMP_SCRIPT"
        exit 1
    fi
fi

# ============================================================================
# SELF-CLEANUP AFTER PIPED EXECUTION
# ============================================================================
#if [[ "${AEON_BOOTSTRAP_REEXEC:-}" == "true" ]]; then
#    trap 'rm -f "/tmp/aeon-bootstrap-$$.sh"' EXIT
#fi

# ============================================================================
# MAIN EXECUTION
# ============================================================================
set -euo pipefail

# Configuration
AEON_REPO="https://github.com/conceptixx/AEON.git"
AEON_RAW="https://raw.githubusercontent.com/conceptixx/AEON/main"
INSTALL_DIR="/opt/aeon"

LIB_MODULES=(
    "dependecies.sh"
    "common.sh"
    "progress.sh"
    "preflight.sh"
    "discovery.sh"
    "hardware.sh"
    "validation.sh"
    "parallel.sh"
    "user.sh"
    "reboot.sh"
    "swarm.sh"
    "report.sh"
    "scoring.py"
)

REMOTE_SCRIPTS=(
    "dependencies.remote.sh"
    "hardware.remote.sh"
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================================
# BANNER
# ============================================================================

#
# print banner
# Displays the AEON ASCII art logo and bootstrap title
#
print_banner() {
    clear
    local logo_lines=(
        "   █████╗  ███████╗  ██████╗  ███╗   ██╗ "
        "  ██╔══██╗ ██╔════╝ ██╔═══██╗ ████╗  ██║ "
        "  ███████║ █████╗   ██║   ██║ ██╔██╗ ██║ "
        "  ██╔══██║ ██╔══╝   ██║   ██║ ██║╚██╗██║ "
        "  ██║  ██║ ███████╗ ╚██████╔╝ ██║ ╚████║ "
        "  ╚═╝  ╚═╝ ╚══════╝  ╚═════╝  ╚═╝  ╚═══╝ "
        ""
        "Autonomous Evolving Orchestration Network"
    )
    
    for line in "${logo_lines[@]}"; do
        local text_length=${#line}
        local padding=$(( (80 - text_length) / 2 ))
        printf "%${padding}s%s\n" "" "$text"
    done
    
    echo ""
}

#
# log $level $message
# Logs messages with appropriate color coding and formatting
#
log() {
    local level="$1"
    shift
    local message="$*"
    
    case "$level" in
        ERROR)
            echo -e "${RED}[ERROR] $message${NC}" >&2
            ;;
        WARN)
            echo -e "${YELLOW}[WARNING]  $message${NC}"
            ;;
        INFO)
            echo -e "${CYAN}[INFO]  $message${NC}"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS] $message${NC}"
            ;;
        STEP)
            echo -e "${BOLD}${BLUE}[STEP] $message${NC}"
            ;;
    esac
}

# ============================================================================
# PRE-CHECKS
# ============================================================================

#
# check_root
# Verifies the script is running with root privileges
#
check_root() {
    log STEP "Checking sudo ..."
    if [[ $EUID -ne 0 ]]; then
        log ERROR "This script must be run as root"
        log INFO ""
        log INFO "Please run:"
        log INFO "  curl -fsSL https://raw.githubusercontent.com/conceptixx/AEON/main/bootstrap.sh | sudo bash"
        log INFO ""
        exit 1
    fi
    log SUCCESS "Check for root user successful"
}

#
# check_prerequisites
# Checks if AEON is already installed and handles reinstallation
#
check_prerequisites() {
    log STEP "Checking prerequisites ..."
    
    # Check if already installed
    if [[ -d "$INSTALL_DIR" ]]; then
        log WARN "AEON is already installed at $INSTALL_DIR"
        log INFO ""
        
        # Check if we can access terminal
        if [[ -t 1 ]] && [[ -c /dev/tty ]]; then
            # Interactive mode - read from TTY
            log INFO "Reinstall? [y/N]: "
            read -r response < /dev/tty
        else
            # Non-interactive - default to no
            log INFO "Reinstall? [y/N]: n (non-interactive mode)"
            response="n"
        fi
        
        log INFO ""
        
        # Normalize response
        response=$(echo "$response" | tr '[:upper:]' '[:lower:]' | xargs)
        
        if [[ "$response" != "y" ]] && [[ "$response" != "yes" ]]; then
            log INFO "Installation cancelled"
            log INFO ""
            log INFO "To force reinstall: sudo rm -rf $INSTALL_DIR && curl ... | sudo bash"
            log INFO ""
            exit 0
        fi
        
        log WARN "Removing existing installation..."
        rm -rf "$INSTALL_DIR"
    fi
    
    log SUCCESS "Check for prerequisites successful"
}

# ============================================================================
# INSTALLATION
# ============================================================================

#
# install_via_git
# Installs AEON by cloning the GitHub repository
#
install_via_git() {
    log STEP "Cloning AEON repository..."
    
    if ! command -v git &>/dev/null; then
        log WARN "Git not found, installing..."
        apt-get update -qq
        apt-get install -y -qq git
    fi
    
    git clone --quiet "$AEON_REPO" "$INSTALL_DIR"
    
    log SUCCESS "Repository cloned successful"
}

#
# install_via_download
# Installs AEON by downloading individual files directly
#
install_via_download() {
    log STEP "Downloading AEON components..."
    
    # Ensure curl/wget available
    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        apt-get update -qq
        apt-get install -y -qq curl wget
    fi
    
    # Create directory structure
    mkdir -p "$INSTALL_DIR"/{lib,remote,config,data,secrets,logs,reports,docs,examples}
    
    # Download main script
    curl -fsSL "$AEON_RAW/aeon-go.sh" -o "$INSTALL_DIR/aeon-go.sh"
    
    # Download lib modules
    for module in "${LIB_MODULES[@]}"; do
        curl -fsSL "$AEON_RAW/lib/$module" -o "$INSTALL_DIR/lib/$module"
    done
    
    # Download remote scripts
    for script in "${REMOTE_SCRIPTS[@]}"; do
        curl -fsSL "$AEON_RAW/remote/$script" -o "$INSTALL_DIR/remote/$script"
    done
    
    # Make executable
    chmod +x "$INSTALL_DIR"/*.sh
    chmod +x "$INSTALL_DIR"/lib/*.sh
    chmod +x "$INSTALL_DIR"/lib/*.py
    chmod +x "$INSTALL_DIR"/remote/*.sh
    
    log SUCCESS "Components downloaded successful"
}

#
# perform_installation
# Main installation orchestrator - tries git first, falls back to download
#
perform_installation() {
    log STEP "Installing AEON..."
    echo ""
    
    # Try git first, fallback to direct download
    if command -v git &>/dev/null; then
        install_via_git
    else
        log WARN "Git not available, using direct download"
        install_via_download
    fi
    
    # Set permissions
    chmod 755 "$INSTALL_DIR"
    
    log SUCCESS "AEON installed to $INSTALL_DIR"
}

# ============================================================================
# POST-INSTALLATION
# ============================================================================

#
# show_next_steps
# Displays completion message with next steps for the user
#
show_next_steps() {
    log INFO "Starting AEON installation..."
    local seconds="30"
    local i
    for ((i=seconds; i>0; i--)); do
        printf "\rPress any key to continue (auto in %2ds)\033[K" "$i"
        if read -r -n 1 -s -t 1; then
            break
        fi
    done
    # Auto-launch aeon-go.sh
    cd "$INSTALL_DIR"
    exec bash aeon_go.sh
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

#
# main
# Main execution function - orchestrates the bootstrap process
#
main() {
    print_banner
    
    check_root
    check_prerequisites
    perform_installation
    show_next_steps
}

#
# automatic execution
# entrypoint main
#
main "$@"
