#!/bin/bash
################################################################################
# AEON Main Orchestrator
# File: aeon-go.sh
# Version: 0.1.0
#
# Purpose: Complete end-to-end AEON cluster setup orchestration
#
# Phases:
#   1. Pre-flight checks
#   2. Network discovery
#   3. Hardware detection
#   4. Requirements validation
#   5. Role assignment
#   6. Dependency installation
#   7. AEON user setup
#   8. Synchronized reboot (if needed)
#   9. Docker Swarm setup
#   10. Report generation
#
# Usage: sudo bash aeon-go.sh
################################################################################

set -euo pipefail

# ============================================================================
# DEPENDENCIES
# ============================================================================

# Prevent double-loading
[[ -n "${AEON_AEON_GO_LOADED:-}" ]] && return 0
readonly AEON_AEON_GO_LOADED=1

# Load dependencies
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
if [[ -z "${AEON_DEPENDENCIES_LOADED:-}" ]]; then
    source "$SCRIPT_DIR/dependencies.sh" || source "/opt/aeon/lib/dependencies.sh" || {
        echo "ERROR: Cannot find dependencies.sh" >&2
        exit 1
    }
fi

# load dependecies -if available
load_dependencies "aeon_go.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================
AEON_VERSION="0.1.0"
AEON_DIR="/opt/aeon"
DATA_DIR="$AEON_DIR/data"
LOG_DIR="$AEON_DIR/logs"
SECRETS_DIR="$AEON_DIR/secrets"
REPORT_DIR="$AEON_DIR/reports"

# Default network range
DEFAULT_NETWORK_RANGE="192.168.1.0/24"

# ============================================================================
# MODULE LOADING
# ============================================================================
# Set library directory
LIB_DIR="$AEON_DIR/lib"
REMOTE_DIR="$AEON_DIR/remote"

# ============================================================================
# PHASE 1: PRE-FLIGHT CHECKS
# ============================================================================

#
# check_root
# Verify script runs as root
#
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log ERROR "This script must be run as root"
        echo ""
        echo -e "${YELLOW}Please run:${NC} sudo bash $0"
        exit 1
    fi
}

#
# check_internet
# Verify internet connectivity
#
check_internet() {
    log STEP "Checking internet connectivity..."
    
    if ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
        log SUCCESS "Internet connection available"
        return 0
    else
        log ERROR "No internet connection"
        return 1
    fi
}

#
# check_disk_space
# Ensure sufficient disk space
#
check_disk_space() {
    log STEP "Checking disk space..."
    
    local available=$(df / | tail -1 | awk '{print $4}')
    local required=$((1024 * 1024))  # 1GB
    
    if [[ $available -gt $required ]]; then
        log SUCCESS "Sufficient disk space"
        return 0
    else
        log ERROR "Insufficient disk space"
        return 1
    fi
}

#
# check_required_tools
# Install missing required tools
#
check_required_tools() {
    log STEP "Checking required tools..."
    
    local missing_tools=()
    
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log WARN "Installing missing tools: ${missing_tools[*]}"
        apt-get update -qq
        apt-get install -y -qq "${missing_tools[@]}"
        log SUCCESS "Tools installed"
    else
        log SUCCESS "All required tools available"
    fi
    
    return 0
}

#
# create_directories
# Create AEON directory structure
#
create_directories() {
    log STEP "Creating AEON directories..."
    
    mkdir -p "$AEON_DIR"/{lib,remote,config,data,secrets,logs,reports}
    chmod 755 "$AEON_DIR"
    chmod 700 "$SECRETS_DIR"
    
    log SUCCESS "Directories created"
    return 0
}

#
# run_preflight_checks
# Orchestrate all pre-flight checks
#
run_preflight_checks() {
    print_header "Phase 1: Pre-flight Checks"
    
    check_root || exit 1
    check_internet || exit 1
    check_disk_space || exit 1
    check_required_tools || exit 1
    create_directories || exit 1
    
    echo ""
    log SUCCESS "Pre-flight checks passed"
    echo ""
    
    return 0
}

# ============================================================================
# NETWORK AUTO-DETECTION
# ============================================================================

get_network_range() {
    local ip=""
    
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    
    if [[ -z "$ip" ]]; then
        ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
    fi
    
    if [[ -z "$ip" ]]; then
        >&2 log ERROR "Could not detect IP address"  # ← To stderr!
        return 1
    fi
    
    >&2 log DEBUG "Detected IP: $ip"  # ← To stderr!
    
    local network_prefix=$(echo "$ip" | cut -d. -f1-3)
    local network_range="${network_prefix}.0/24"
    
    >&2 log INFO "Auto-detected network range: $network_range"  # ← To stderr!
    
    echo "$network_range"  # ← ONLY this to stdout
    return 0
}

run_discovery_phase() {
    print_header "Phase 2: Network Discovery"
    
    # Auto-detect network
    local NETWORK_RANGE=$(get_network_range)
    
    if [[ -z "$NETWORK_RANGE" ]]; then
        log WARN "Failed to auto-detect network, using default"
        NETWORK_RANGE="$DEFAULT_NETWORK_RANGE"
    fi
    
    log SUCCESS "Using network range: $NETWORK_RANGE"
    
    # Use predefined credentials
    local DEFAULT_USER="pi"
    local DEFAULT_PASSWORD="raspberry"
    
    log INFO "SSH Discovery Configuration:"
    log INFO "  - Default user: pi"
    log INFO "  - Default password: raspberry"
    log INFO "  - Will also try: ubuntu/ubuntu, aeon-llm/raspberry, aeon-host/raspberry"
    log WARN "IMPORTANT: Change all default passwords after cluster setup!"
    
    echo ""
    
    # Run automated_discovery
    automated_discovery "$NETWORK_RANGE" "$DEFAULT_USER" "$DEFAULT_PASSWORD" "$DATA_DIR/discovered_devices.json"
    
    if [[ $? -ne 0 ]]; then
        log ERROR "Network discovery failed"
        return 1
    fi
    
    log SUCCESS "Phase 2: Network Discovery complete"
    return 0
}
# ============================================================================
# PHASE 3: HARDWARE DETECTION
# ============================================================================

#
# run_hardware_detection
# Collect hardware specs from all devices
#
run_hardware_detection() {
    print_header "Phase 3: Hardware Detection"
    
    # parallel.sh already sourced at top
    parallel_init
    
    log STEP "Collecting hardware profiles..."
    echo ""
    
    # Build device array
    local devices=()
    while read -r device_json; do
        local ip=$(echo "$device_json" | jq -r '.ip')
        local user=$(echo "$device_json" | jq -r '.ssh_user')
        local password=$(echo "$device_json" | jq -r '.ssh_password')
        
        devices+=("${ip}:${user}:${password}")
    done < <(jq -c '.devices[]' "$DATA_DIR/discovered_devices.json")
    
    # Transfer detection script
    parallel_file_transfer devices[@] \
        "$AEON_DIR/remote/detect_hardware.sh" \
        "/tmp/detect_hardware.sh"
    
    echo ""
    
    # Execute detection
    parallel_exec devices[@] \
        "bash /tmp/detect_hardware.sh" \
        "Collecting hardware profiles"
    
    echo ""
    
    # Aggregate results
    log STEP "Aggregating hardware profiles..."
    
    local hw_profiles='{"devices":['
    local first=true
    
    for device_info in "${devices[@]}"; do
        local ip=$(echo "$device_info" | cut -d: -f1)
        local user=$(echo "$device_info" | cut -d: -f2)
        local password=$(echo "$device_info" | cut -d: -f3)
        
        local hw_json=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no "${user}@${ip}" \
            "bash /tmp/detect_hardware.sh" 2>/dev/null)
        
        if [[ -n "$hw_json" ]]; then
            [[ "$first" == "false" ]] && hw_profiles+=","
            first=false
            hw_profiles+="$hw_json"
        fi
    done
    
    hw_profiles+=']}'
    
    echo "$hw_profiles" | jq '.' > "$DATA_DIR/hw_profiles.json"
    
    log SUCCESS "Hardware profiles collected"
    echo ""
    
    return 0
}

# ============================================================================
# PHASE 4: REQUIREMENTS VALIDATION
# ============================================================================

#
# run_validation
# Ensure minimum cluster requirements met
#
run_validation() {
    print_header "Phase 4: Requirements Validation"
    
    log STEP "Validating cluster requirements..."
    
    local pi_count=$(jq '[.devices[] | select(.device_type == "raspberry_pi")] | length' "$DATA_DIR/hw_profiles.json")
    
    if [[ $pi_count -lt 3 ]]; then
        log ERROR "Insufficient Raspberry Pis: $pi_count found, minimum 3 required"
        return 1
    fi
    
    log SUCCESS "Requirements met: $pi_count Raspberry Pis"
    echo ""
    
    return 0
}

# ============================================================================
# PHASE 5: ROLE ASSIGNMENT
# ============================================================================

#
# run_role_assignment
# Score devices and assign manager/worker roles
#
run_role_assignment() {
    print_header "Phase 5: Role Assignment"
    
    log STEP "Assigning roles..."
    echo ""
    
    python3 "$AEON_DIR/lib/scoring.py" \
        "$DATA_DIR/hw_profiles.json" \
        "$DATA_DIR/role_assignments.json"
    
    if [[ $? -ne 0 ]]; then
        log ERROR "Role assignment failed"
        return 1
    fi
    
    log SUCCESS "Roles assigned"
    echo ""
    
    return 0
}

# ============================================================================
# PHASE 6: DEPENDENCY INSTALLATION
# ============================================================================

#
# run_installation
# Install Docker and dependencies on all devices
#
run_installation() {
    print_header "Phase 6: Dependency Installation"
    
    log STEP "Installing Docker and dependencies..."
    echo ""
    
    local devices=()
    while read -r assignment; do
        local ip=$(echo "$assignment" | jq -r '.device.ip')
        local user=$(echo "$assignment" | jq -r '.device.ssh_user // "pi"')
        local password=$(echo "$assignment" | jq -r '.device.ssh_password // "raspberry"')
        
        devices+=("${ip}:${user}:${password}")
    done < <(jq -c '.assignments[]' "$DATA_DIR/role_assignments.json")
    
    parallel_file_transfer devices[@] \
        "$AEON_DIR/remote/install_dependencies.sh" \
        "/tmp/install_dependencies.sh"
    
    echo ""
    
    parallel_exec devices[@] \
        "sudo bash /tmp/install_dependencies.sh" \
        "Installing dependencies"
    
    echo ""
    
    local results=$(parallel_collect_results)
    echo "$results" > "$DATA_DIR/installation_results.json"
    
    log SUCCESS "Installation complete"
    echo ""
    
    return 0
}

# ============================================================================
# PHASE 7: AEON USER SETUP
# ============================================================================

#
# run_user_setup
# Create AEON automation user on all devices
#
run_user_setup() {
    print_header "Phase 7: AEON User Setup"
    
    # user.sh already sourced at top
    
    log STEP "Setting up AEON automation user..."
    echo ""
    
    generate_aeon_password
    save_aeon_credentials "$SECRETS_DIR/.aeon.env"
    cp "$SECRETS_DIR/.aeon.env" "$AEON_DIR/.aeon.env"
    
    log SUCCESS "AEON credentials generated"
    echo ""
    
    local devices=()
    while read -r assignment; do
        local ip=$(echo "$assignment" | jq -r '.device.ip')
        local user=$(echo "$assignment" | jq -r '.device.ssh_user // "pi"')
        local password=$(echo "$assignment" | jq -r '.device.ssh_password // "raspberry"')
        
        devices+=("${ip}:${user}:${password}")
    done < <(jq -c '.assignments[]' "$DATA_DIR/role_assignments.json")
    
    setup_aeon_user_on_devices devices[@]
    
    log SUCCESS "AEON user configured"
    echo ""
    
    return 0
}

# ============================================================================
# PHASE 8: SYNCHRONIZED REBOOT
# ============================================================================

#
# run_reboot_phase
# Reboot devices if needed while maintaining cluster quorum
#
run_reboot_phase() {
    print_header "Phase 8: Synchronized Reboot"
    
    # reboot.sh already sourced at top
    
    if ! check_devices_need_reboot "$DATA_DIR/installation_results.json"; then
        log INFO "No reboot required"
        echo ""
        return 0
    fi
    
    read -p "Proceed with reboot? [y/N] " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log WARN "Reboot skipped"
        echo ""
        return 0
    fi
    
    echo ""
    
    source "$AEON_DIR/.aeon.env"
    local entry_ip=$(hostname -I | awk '{print $1}')
    
    synchronized_reboot \
        "$DATA_DIR/role_assignments.json" \
        "$entry_ip" \
        "$AEON_USER" \
        "$AEON_PASSWORD"
    
    log SUCCESS "Reboot complete"
    echo ""
    
    return 0
}

# ============================================================================
# PHASE 9: DOCKER SWARM SETUP
# ============================================================================

#
# run_swarm_setup
# Initialize and form Docker Swarm cluster
#
run_swarm_setup() {
    print_header "Phase 9: Docker Swarm Setup"
    
    # swarm.sh already sourced at top
    source "$AEON_DIR/.aeon.env"
    
    log STEP "Initializing swarm..."
    echo ""
    
    setup_docker_swarm \
        "$DATA_DIR/role_assignments.json" \
        "$AEON_USER" \
        "$AEON_PASSWORD"
    
    log SUCCESS "Swarm operational"
    echo ""
    
    return 0
}

# ============================================================================
# PHASE 10: REPORT GENERATION
# ============================================================================

#
# run_report_generation
# Generate beautiful installation reports
#
run_report_generation() {
    print_header "Phase 10: Installation Report"
    
    # report.sh already sourced at top
    
    export AEON_LOG_DIR="$LOG_DIR"
    
    generate_installation_report "$DATA_DIR" "all"
    
    return 0
}

# ============================================================================
# COMPLETION
# ============================================================================

#
# print_completion
# Display final success message and quick start guide
#
print_completion() {
    echo ""
    echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}  🎉 AEON CLUSTER INSTALLATION COMPLETE! 🎉${NC}"
    echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════${NC}"
    echo ""
    
    local first_manager=$(jq -r '.assignments[] | select(.role == "manager" and .rank == 1) | .device.ip' \
        "$DATA_DIR/role_assignments.json" 2>/dev/null | head -1)
    
    echo -e "${BOLD}Quick Start:${NC}"
    echo ""
    echo -e "  ${CYAN}ssh aeon@${first_manager}${NC}"
    echo -e "  ${CYAN}docker node ls${NC}"
    echo ""
    
    echo -e "${BOLD}Resources:${NC}"
    echo -e "  • Reports: ${CYAN}$REPORT_DIR/${NC}"
    echo -e "  • Logs: ${CYAN}$LOG_DIR/aeon-go.log${NC}"
    echo ""
}

# At the end of main() function, before final success message:

show_security_warning() {
    echo ""
    print_header "🔒 IMPORTANT SECURITY NOTICE"
    echo ""
    
    log WARN "DEFAULT PASSWORDS IN USE!"
    echo ""
    log INFO "All devices are currently using default password: 'raspberry'"
    log INFO ""
    log INFO "You MUST change passwords on all devices:"
    log INFO "  1. SSH to each device"
    log INFO "  2. Run: passwd"
    log INFO "  3. Set a strong password"
    log INFO ""
    log INFO "Devices to update:"
    
    # List all discovered devices
    if [[ -f "$DATA_DIR/discovered_devices.json" ]]; then
        jq -r '.devices[] | "  - \(.ip) (\(.hostname)) - user: \(.ssh_user)"' \
            "$DATA_DIR/discovered_devices.json"
    fi
    
    echo ""
    log WARN "Cluster security depends on changing these passwords!"
    echo ""
}

# ============================================================================
# ERROR HANDLING
# ============================================================================

#
# handle_error
# Trap and handle script errors
#
handle_error() {
    local exit_code=$?
    local line_number=$1
    
    echo ""
    log ERROR "Installation failed at line $line_number"
    log INFO "Check logs: $LOG_DIR/aeon-go.log"
    echo ""
    
    exit $exit_code
}

trap 'handle_error $LINENO' ERR

# ============================================================================
# MAIN EXECUTION
# ============================================================================

#
# main
# Main orchestration - calls all phases in order
#
main() {
    # initialize aeon setup
    aeon_init
    # Initialize progress bar
    init_progress
    
    # Run phases
    local start_time=$(date +%s)
    run_preflight_checks || exit 1
    run_discovery_phase || exit 1
    run_hardware_detection || exit 1
    run_validation || exit 1
    run_role_assignment || exit 1
    run_installation || exit 1
    run_user_setup || exit 1
    run_reboot_phase || true
    run_swarm_setup || exit 1
    run_report_generation || true
    show_security_warning || true
    print_completion
  
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log SUCCESS "Total time: $((duration / 60))m $((duration % 60))s"
    echo ""
}

#
# automatic execution
# entrypoint main
#
main "$@"
