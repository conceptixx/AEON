#!/bin/bash
################################################################################
# AEON Bootstrap Installer
# File: bootstrap.sh
# Version: 0.1.0
#
# Purpose: One-command installation of AEON
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/conceptixx/AEON/main/bootstrap.sh | sudo bash
#   
# Or manually:
#   wget https://raw.githubusercontent.com/conceptixx/AEON/main/bootstrap.sh
#   sudo bash bootstrap.sh
################################################################################

set -euo pipefail

# Configuration
AEON_REPO="https://github.com/conceptixx/AEON.git"
AEON_RAW="https://raw.githubusercontent.com/conceptixx/AEON/main"
INSTALL_DIR="/opt/aeon"

LIB_MODULES=(
    "common.sh"
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
    cat << 'EOF'

     █████╗ ███████╗ ██████╗ ███╗   ██╗
    ██╔══██╗██╔════╝██╔═══██╗████╗  ██║
    ███████║█████╗  ██║   ██║██╔██╗ ██║
    ██╔══██║██╔══╝  ██║   ██║██║╚██╗██║
    ██║  ██║███████╗╚██████╔╝██║ ╚████║
    ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝

    Bootstrap Installer
    
EOF
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
    if [[ $EUID -ne 0 ]]; then
        log ERROR "This script must be run as root"
        echo ""
        echo -e "${YELLOW}Please run:${NC}"
        echo -e "  ${CYAN}curl -fsSL https://raw.githubusercontent.com/conceptixx/AEON/main/bootstrap.sh | sudo bash${NC}"
        echo ""
        exit 1
    fi
    log SUCCESS "check_root"
}

#
# check_prerequisites
# Checks if AEON is already installed and handles reinstallation
#
check_prerequisites() {
    log STEP "Checking prerequisites..."
    
    # Check if already installed
    if [[ -d "$INSTALL_DIR" ]]; then
        log WARN "AEON is already installed at $INSTALL_DIR"
        read -p "Reinstall? [y/N] " -n 60 -r
        echo ""
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log INFO "Installation cancelled"
            exit 0
        fi
        
        log WARN "Removing existing installation..."
        rm -rf "$INSTALL_DIR"
    fi
    
    log SUCCESS "Prerequisites checked"
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
    
    log SUCCESS "Repository cloned"
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
    
    log SUCCESS "Components downloaded"
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
    echo ""
    echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}  [SUCCESS] AEON Bootstrap Complete!${NC}"
    echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${BOLD}Installation Details:${NC}"
    echo -e "  • Location: ${CYAN}$INSTALL_DIR${NC}"
    echo -e "  • Main Script: ${CYAN}$INSTALL_DIR/aeon-go.sh${NC}"
    echo ""
    
    echo -e "${BOLD}Next Steps:${NC}"
    echo ""
    echo -e "  ${BOLD}1. Start AEON Installation:${NC}"
    echo -e "     ${CYAN}cd $INSTALL_DIR${NC}"
    echo -e "     ${CYAN}sudo bash aeon-go.sh${NC}"
    echo ""
    echo -e "  ${BOLD}2. Or run directly:${NC}"
    echo -e "     ${CYAN}sudo bash $INSTALL_DIR/aeon-go.sh${NC}"
    echo ""
    
    echo -e "${BOLD}Requirements:${NC}"
    echo -e "  • Minimum 3 Raspberry Pis on local network"
    echo -e "  • SSH enabled on all devices"
    echo -e "  • Network connectivity between devices"
    echo ""
    
    echo -e "${BOLD}Documentation:${NC}"
    echo -e "  • GitHub: ${CYAN}https://github.com/conceptixx/AEON${NC}"
    echo -e "  • Local Docs: ${CYAN}$INSTALL_DIR/docs/${NC}"
    echo ""
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
