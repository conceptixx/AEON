#!/bin/bash
################################################################################
# AEON Network Discovery Module
# File: lib/discovery.sh
# Version: 0.1.0
#
# Purpose: Discover devices on the network that can join AEON cluster
#
# Discovery Methods:
#   1. Network scan (nmap or ping sweep)
#   2. ARP cache inspection
#   3. SSH connectivity testing
#   4. Device type detection
#
# Output: discovered_devices.json
################################################################################

set -euo pipefail

# ============================================================================
# DEPENDENCIES
# ============================================================================

# Auto-source common.sh if not already loaded
if [[ -z "${AEON_COMMON_LOADED:-}" ]]; then
    SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
    
    # Try to source from lib directory
    if [[ -f "$SCRIPT_DIR/common.sh" ]]; then
        source "$SCRIPT_DIR/common.sh"
    elif [[ -f "/opt/aeon/lib/common.sh" ]]; then
        source "/opt/aeon/lib/common.sh"
    else
        echo "ERROR: Cannot find common.sh" >&2
        return 1 2>/dev/null || exit 1
    fi
fi

# ============================================================================
# CONFIGURATION
# ============================================================================

DISCOVERY_TIMEOUT=300              # Max time for discovery (5 min)
PING_TIMEOUT=1                     # Ping timeout per host
SSH_TIMEOUT=5                      # SSH connection timeout
SSH_RETRIES=2                      # SSH retry attempts
PARALLEL_SCAN_JOBS=50              # Parallel ping jobs

# Common SSH users to try
DEFAULT_SSH_USERS=("pi" "ubuntu" "aeon-llm" "aeon-host" "aeon")

# Global arrays
DISCOVERED_IPS=()
ACCESSIBLE_DEVICES=()

# ============================================================================
# NETWORK SCANNING
# ============================================================================

#
# check_scan_tools
# Checks for network scanning tools and sets SCAN_METHOD
#
check_scan_tools() {
    log STEP "Checking for network scanning tools..."
    
    # Check for nmap (preferred)
    if command -v nmap &>/dev/null; then
        SCAN_METHOD="nmap"
        log SUCCESS "nmap found - will use for network scanning"
        return 0
    fi
    
    # Fallback to ping sweep
    SCAN_METHOD="ping"
    log WARN "nmap not found - will use ping sweep (slower)"
    log INFO "Install nmap for faster scanning: sudo apt install nmap"
    
    return 0
}

#
# scan_network_nmap $network_range
# Fast network scan using nmap
#
scan_network_nmap() {
    local network_range="$1"
    
    >&2 log INFO "Scanning network with nmap: $network_range"
    
    # Use nmap for fast host discovery
    local scan_result=$(nmap -sn -T4 "$network_range" -oG - 2>/dev/null | \
        grep "Status: Up" | \
        awk '{print $2}')
    
    # Exclude entry device (self)
    local self_ip=$(hostname -I | awk '{print $1}')
    scan_result=$(echo "$scan_result" | grep -v "^${self_ip}$" || true)
    
    echo "$scan_result"
}

#
# scan_network_ping $network_range
# Fallback ping sweep for network scanning
#
scan_network_ping() {
    local network_range="$1"
    
    # Send logs to stderr to avoid contaminating stdout
    >&2 log INFO "Scanning network with ping sweep: $network_range"
    
    # Extract network prefix (e.g., 192.168.1 from 192.168.1.0/24)
    local network_prefix=$(echo "$network_range" | cut -d'/' -f1 | rev | cut -d'.' -f2- | rev)
    
    # Get CIDR (e.g., 24 from 192.168.1.0/24)
    local cidr=$(echo "$network_range" | cut -d'/' -f2)
    
    # For /24, scan .1 to .254
    if [[ "$cidr" == "24" ]]; then
        >&2 log INFO "Ping sweep ${network_prefix}.1-254 (this may take a while)..."
        
        local self_ip=$(hostname -I | awk '{print $1}')
        
        # Parallel ping sweep - only IPs go to stdout
        for i in $(seq 1 254); do
            (
                local ip="${network_prefix}.${i}"
                if [[ "$ip" != "$self_ip" ]]; then
                    if ping -c 1 -W "$PING_TIMEOUT" "$ip" &>/dev/null; then
                        echo "$ip"
                    fi
                fi
            ) &
            
            # Limit parallel jobs
            if (( $(jobs -r | wc -l) >= PARALLEL_SCAN_JOBS )); then
                wait -n
            fi
        done
        
        wait
    else
        >&2 log ERROR "Only /24 networks supported for ping sweep"
        return 1
    fi
}

#
# discover_network_devices $network_range
# Main network discovery function
#
discover_network_devices() {
    local network_range="${1:-192.168.1.0/24}"
    
    print_header "Network Discovery"
    
    log INFO "Network range: $network_range"
    
    # Check available tools
    check_scan_tools
    
    # Scan network
    local discovered=""
    
    case "$SCAN_METHOD" in
        nmap)
            discovered=$(scan_network_nmap "$network_range")
            ;;
        ping)
            discovered=$(scan_network_ping "$network_range")
            ;;
    esac
    
    # Store in global array (excluding self - we'll add it later if accessible)
    DISCOVERED_IPS=($(echo "$discovered" | sort -V))
    
    local count=${#DISCOVERED_IPS[@]}
    
    log SUCCESS "Found $count device(s) on network (excluding this device)"
    
    # Display discovered IPs
    if [[ $count -gt 0 ]]; then
        for ip in "${DISCOVERED_IPS[@]}"; do
            log INFO "  • $ip"
        done
    fi
    
    return 0
}

# ============================================================================
# SSH CONNECTIVITY TESTING
# ============================================================================

#
# test_ssh_connection $ip $user $password
# Test SSH connection to a single device
#
test_ssh_connection() {
    local ip="$1"
    local user="$2"
    local password="$3"
    
    # Test SSH with timeout
    if sshpass -p "$password" ssh \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout="$SSH_TIMEOUT" \
        -o BatchMode=no \
        "${user}@${ip}" "exit 0" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

#
# find_ssh_credentials $ip $custom_user $custom_password
# Find working SSH credentials for a device
#
find_ssh_credentials() {
    local ip="$1"
    local custom_user="${2:-}"
    local custom_password="${3:-}"
    
    # If custom credentials provided, try those first
    if [[ -n "$custom_user" ]] && [[ -n "$custom_password" ]]; then
        log DEBUG "Testing custom credentials for $ip..."
        
        if test_ssh_connection "$ip" "$custom_user" "$custom_password"; then
            echo "${custom_user}:${custom_password}"
            return 0
        fi
    fi
    
    # All devices MUST use "raspberry" as password initially
    # User will be prompted to change after setup
    local common_passwords=("raspberry" "ubuntu" "pi" "aeon")
    
    for user in "${DEFAULT_SSH_USERS[@]}"; do
        for password in "${common_passwords[@]}"; do
            log DEBUG "Testing $user:$password for $ip..."
            
            if test_ssh_connection "$ip" "$user" "$password"; then
                echo "${user}:${password}"
                return 0
            fi
        done
    done
    
    return 1
}

#
# test_ssh_accessibility $user $password
# Test SSH access to all discovered devices (and current device)
#
test_ssh_accessibility() {
    local user="${1:-}"
    local password="${2:-}"
    
    print_header "SSH Connectivity Testing"
    
    # Get current device info
    local self_ip=$(hostname -I | awk '{print $1}')
    local self_hostname=$(hostname)
    
    log INFO "Current device: $self_hostname ($self_ip)"
    echo ""
    
    # First, try to add current device
    log STEP "Testing SSH access to current device..."
    
    local self_credentials=""
    self_credentials=$(find_ssh_credentials "$self_ip" "$user" "$password")
    
    if [[ $? -eq 0 ]]; then
        log SUCCESS "Current device is SSH accessible (${self_credentials%%:*})"
        ACCESSIBLE_DEVICES+=("${self_ip}:${self_credentials}")
    else
        log WARN "Cannot SSH to current device - this may cause issues"
        log INFO "Trying to continue anyway..."
    fi
    
    echo ""
    
    # Now test discovered devices
    if [[ ${#DISCOVERED_IPS[@]} -eq 0 ]]; then
        log INFO "No other devices found on network"
    else
        log STEP "Testing SSH access to ${#DISCOVERED_IPS[@]} discovered device(s)..."
        
        if [[ -z "$user" ]] || [[ -z "$password" ]]; then
            log INFO "Will try common default credentials"
        fi
        
        local tested_count=0
        local remote_accessible=0
        
        for ip in "${DISCOVERED_IPS[@]}"; do
            ((tested_count++))
            
            printf "\r  Testing [$tested_count/${#DISCOVERED_IPS[@]}] $ip..."
            
            local credentials=""
            credentials=$(find_ssh_credentials "$ip" "$user" "$password")
            
            if [[ $? -eq 0 ]]; then
                echo ""  # New line for log
                log SUCCESS "[$ip] SSH accessible (${credentials%%:*})"
                ACCESSIBLE_DEVICES+=("${ip}:${credentials}")
                ((remote_accessible++))
            else
                echo ""  # New line for log
                log WARN "[$ip] SSH not accessible"
            fi
        done
        
        echo ""  # New line after progress
    fi
    
    # Summary
    local total_accessible=${#ACCESSIBLE_DEVICES[@]}
    
    if [[ $total_accessible -eq 0 ]]; then
        log ERROR "No devices accessible via SSH (including this one)"
        echo ""
        log INFO "Please ensure:"
        log INFO "  • SSH is enabled: sudo systemctl enable ssh && sudo systemctl start ssh"
        log INFO "  • Password is set to 'raspberry': echo 'pi:raspberry' | sudo chpasswd"
        log INFO "  • Firewall allows SSH: sudo ufw allow 22/tcp"
        echo ""
        return 1
    fi
    
    # Determine setup mode
    local self_only=false
    if [[ $total_accessible -eq 1 ]]; then
        # Check if it's only self
        local first_device="${ACCESSIBLE_DEVICES[0]}"
        local first_ip=$(echo "$first_device" | cut -d: -f1)
        
        if [[ "$first_ip" == "$self_ip" ]]; then
            self_only=true
        fi
    fi
    
    if [[ "$self_only" == true ]]; then
        log WARN "Only current device is accessible via SSH"
        echo ""
        log INFO "═══════════════════════════════════════════════════════════"
        log INFO "  SINGLE-DEVICE SETUP MODE"
        log INFO "═══════════════════════════════════════════════════════════"
        echo ""
        log INFO "Setup will continue on this device only."
        log INFO ""
        log INFO "IMPORTANT:"
        log INFO "  • Cluster requires minimum 3 Raspberry Pis"
        log INFO "  • Current setup: 1 device"
        log INFO "  • Cluster services will NOT start automatically"
        log INFO ""
        log INFO "Next steps after setup:"
        log INFO "  1. Add more Raspberry Pis to your network"
        log INFO "  2. Ensure SSH is enabled with password 'raspberry'"
        log INFO "  3. Use AEON management interface to add devices"
        log INFO "  4. Start cluster when requirements are met"
        echo ""
        log INFO "═══════════════════════════════════════════════════════════"
        echo ""
    else
        log SUCCESS "SSH access confirmed for $total_accessible device(s)"
        
        # Count how many are self vs remote
        local remote_count=$((total_accessible - 1))
        if echo "${ACCESSIBLE_DEVICES[@]}" | grep -q "$self_ip"; then
            log INFO "  • Current device: 1"
            log INFO "  • Remote devices: $remote_count"
        else
            log INFO "  • Remote devices: $total_accessible"
        fi
    fi
    
    return 0
}

# ============================================================================
# DEVICE CLASSIFICATION
# ============================================================================

#
# detect_device_type $ip $user $password
# Detect what type of device this is
#
detect_device_type() {
    local ip="$1"
    local user="$2"
    local password="$3"
    
    # Check if Raspberry Pi
    local device_check=$(sshpass -p "$password" ssh \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout="$SSH_TIMEOUT" \
        "${user}@${ip}" "cat /proc/device-tree/model 2>/dev/null" 2>/dev/null || echo "unknown")
    
    if echo "$device_check" | grep -qi "raspberry"; then
        echo "raspberry_pi"
        return 0
    fi
    
    # Check hostname for LLM indicator
    local hostname=$(sshpass -p "$password" ssh \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout="$SSH_TIMEOUT" \
        "${user}@${ip}" "hostname" 2>/dev/null || echo "unknown")
    
    if echo "$hostname" | grep -qi "llm"; then
        echo "llm_computer"
        return 0
    fi
    
    # Default to host computer
    echo "host_computer"
    return 0
}

#
# classify_devices
# Classify all accessible devices
#
classify_devices() {
    print_header "Device Classification"
    
    log STEP "Classifying ${#ACCESSIBLE_DEVICES[@]} device(s)..."
    echo ""
    
    local pi_count=0
    local llm_count=0
    local host_count=0
    
    for device in "${ACCESSIBLE_DEVICES[@]}"; do
        local ip=$(echo "$device" | cut -d: -f1)
        local user=$(echo "$device" | cut -d: -f2)
        local password=$(echo "$device" | cut -d: -f3)
        
        local device_type=$(detect_device_type "$ip" "$user" "$password")
        
        case "$device_type" in
            raspberry_pi)
                log INFO "  [$ip] Raspberry Pi"
                ((pi_count++))
                ;;
            llm_computer)
                log INFO "  [$ip] LLM Computer"
                ((llm_count++))
                ;;
            host_computer)
                log INFO "  [$ip] Host Computer"
                ((host_count++))
                ;;
        esac
    done
    
    echo ""
    log SUCCESS "Device Classification:"
    log INFO "  • Raspberry Pis: $pi_count"
    log INFO "  • LLM Computers: $llm_count"
    log INFO "  • Host Computers: $host_count"
    echo ""
    
    # Validate minimum requirements (warning only, not error)
    if [[ $pi_count -lt 3 ]]; then
        log WARN "Found $pi_count Raspberry Pi(s) - below minimum of 3 for production cluster"
        echo ""
        log INFO "SETUP MODE: You can proceed with setup"
        log INFO ""
        log INFO "Current: $pi_count Raspberry Pi(s)"
        log INFO "Required for cluster start: 3 Raspberry Pis minimum"
        log INFO ""
        log INFO "Cluster services will be configured but not started."
        log INFO "Add more devices later via management interface."
        echo ""
    else
        log SUCCESS "Minimum requirements met ($pi_count Raspberry Pis)"
        echo ""
    fi
    
    return 0
}

# ============================================================================
# SAVE DISCOVERED DEVICES
# ============================================================================

#
# save_discovered_devices $output_file
# Generate and save discovered_devices.json
#
save_discovered_devices() {
    local output_file="$1"
    
    log STEP "Saving discovered devices to $output_file..."
    
    # Create JSON structure
    local devices_json="["
    local first=true
    
    for device in "${ACCESSIBLE_DEVICES[@]}"; do
        local ip=$(echo "$device" | cut -d: -f1)
        local user=$(echo "$device" | cut -d: -f2)
        local password=$(echo "$device" | cut -d: -f3)
        
        # Get device type
        local device_type=$(detect_device_type "$ip" "$user" "$password")
        
        # Get hostname
        local hostname=$(sshpass -p "$password" ssh \
            -o StrictHostKeyChecking=no \
            -o ConnectTimeout="$SSH_TIMEOUT" \
            "${user}@${ip}" "hostname" 2>/dev/null || echo "unknown")
        
        # Add to JSON
        if [[ "$first" == true ]]; then
            first=false
        else
            devices_json+=","
        fi
        
        devices_json+="
    {
      \"ip\": \"$ip\",
      \"hostname\": \"$hostname\",
      \"device_type\": \"$device_type\",
      \"ssh_user\": \"$user\",
      \"ssh_password\": \"$password\"
    }"
    done
    
    devices_json+="
  ]"
    
    # Determine setup mode
    local setup_mode="cluster"
    if [[ ${#ACCESSIBLE_DEVICES[@]} -eq 1 ]]; then
        local self_ip=$(hostname -I | awk '{print $1}')
        local first_device="${ACCESSIBLE_DEVICES[0]}"
        local first_ip=$(echo "$first_device" | cut -d: -f1)
        
        if [[ "$first_ip" == "$self_ip" ]]; then
            setup_mode="single-device"
        fi
    fi
    
    # Create complete JSON
    cat > "$output_file" <<EOF
{
  "discovery_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "network_range": "${NETWORK_RANGE:-unknown}",
  "setup_mode": "$setup_mode",
  "total_discovered": ${#DISCOVERED_IPS[@]},
  "total_accessible": ${#ACCESSIBLE_DEVICES[@]},
  "devices": $devices_json
}
EOF
    
    log SUCCESS "Discovered devices saved to $output_file"
    
    # Show mode
    if [[ "$setup_mode" == "single-device" ]]; then
        log INFO "Setup mode: SINGLE-DEVICE"
    else
        log INFO "Setup mode: CLUSTER (${#ACCESSIBLE_DEVICES[@]} devices)"
    fi
    
    return 0
}

# ============================================================================
# INTERACTIVE DISCOVERY
# ============================================================================

#
# interactive_discovery $output_file
# Interactive wizard for discovery
#
interactive_discovery() {
    local output_file="${1:-/opt/aeon/data/discovered_devices.json}"
    
    print_header "AEON Network Discovery"
    
    echo -e "${CYAN}This wizard will discover devices on your network.${NC}"
    echo ""
    
    # Ask for network range
    echo -e "${BOLD}Network Configuration${NC}"
    read -p "Enter network range (CIDR) [192.168.1.0/24]: " network_input
    NETWORK_RANGE="${network_input:-192.168.1.0/24}"
    echo ""
    
    # Ask for SSH credentials
    echo -e "${BOLD}SSH Credentials${NC}"
    echo -e "${CYAN}Enter default SSH credentials (will try common defaults if left blank)${NC}"
    read -p "Default SSH user [pi]: " ssh_user
    ssh_user="${ssh_user:-pi}"
    
    read -sp "Default SSH password: " ssh_password
    echo ""
    echo ""
    
    # Start discovery
    discover_network_devices "$NETWORK_RANGE" || return 1
    
    # Test SSH access
    test_ssh_accessibility "$ssh_user" "$ssh_password" || return 1
    
    # Classify devices
    classify_devices || return 1
    
    # Save results
    save_discovered_devices "$output_file" || return 1
    
    # Summary
    print_header "Discovery Complete"
    
    local pi_count=$(jq -r '[.devices[] | select(.device_type == "raspberry_pi")] | length' "$output_file" 2>/dev/null || echo "0")
    local llm_count=$(jq -r '[.devices[] | select(.device_type == "llm_computer")] | length' "$output_file" 2>/dev/null || echo "0")
    local host_count=$(jq -r '[.devices[] | select(.device_type == "host_computer")] | length' "$output_file" 2>/dev/null || echo "0")
    local total_count=$(jq -r '.devices | length' "$output_file" 2>/dev/null || echo "0")
    local setup_mode=$(jq -r '.setup_mode' "$output_file" 2>/dev/null || echo "unknown")
    
    log SUCCESS "Discovery Summary:"
    log INFO "  • Total devices: $total_count"
    log INFO "  • Raspberry Pis: $pi_count"
    log INFO "  • LLM Computers: $llm_count"
    log INFO "  • Host Computers: $host_count"
    log INFO "  • Setup mode: $setup_mode"
    log INFO "  • Results: $output_file"
    echo ""
    
    if [[ $pi_count -ge 1 ]]; then
        log SUCCESS "✅ Ready to proceed with setup"
    else
        log WARN "⚠️  No Raspberry Pis found"
    fi
    
    return 0
}

# ============================================================================
# NON-INTERACTIVE DISCOVERY
# ============================================================================

#
# automated_discovery $network_range $ssh_user $ssh_password $output_file
# Non-interactive discovery for automation
#
automated_discovery() {
    local network_range="$1"
    local ssh_user="$2"
    local ssh_password="$3"
    local output_file="$4"
    
    NETWORK_RANGE="$network_range"
    
    # Run discovery steps
    print_banner
    discover_network_devices "$network_range" || return 1
    sleep 10

    print_banner    
    test_ssh_accessibility "$ssh_user" "$ssh_password" || return 1
    sleep 10

    print_banner    
    classify_devices || return 1
    sleep 10

    print_banner    
    save_discovered_devices "$output_file" || return 1
    sleep 10
    
    return 0
}

# ============================================================================
# EXPORT FUNCTIONS
# ============================================================================

export -f interactive_discovery
export -f automated_discovery
export -f discover_network_devices
export -f test_ssh_accessibility
export -f classify_devices

# ============================================================================
# STANDALONE EXECUTION
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    
    case "${1:-interactive}" in
        interactive|--interactive|-i)
            interactive_discovery "${2:-/opt/aeon/data/discovered_devices.json}"
            ;;
        automated|--automated|-a)
            if [[ $# -lt 4 ]]; then
                echo "Usage: $0 automated <network_range> <ssh_user> <ssh_password> [output_file]"
                echo ""
                echo "Example:"
                echo "  $0 automated 192.168.1.0/24 pi raspberry /opt/aeon/data/discovered_devices.json"
                exit 1
            fi
            
            automated_discovery "$2" "$3" "$4" "${5:-/opt/aeon/data/discovered_devices.json}"
            ;;
        *)
            echo "Usage: $0 {interactive|automated} [options]"
            echo ""
            echo "Modes:"
            echo "  interactive           Interactive discovery wizard (default)"
            echo "  automated <args>      Non-interactive discovery"
            echo ""
            echo "Interactive mode:"
            echo "  $0 interactive [output_file]"
            echo ""
            echo "Automated mode:"
            echo "  $0 automated <network_range> <ssh_user> <ssh_password> [output_file]"
            echo ""
            echo "Example:"
            echo "  $0 interactive"
            echo "  $0 automated 192.168.1.0/24 pi raspberry"
            exit 1
            ;;
    esac
fi
