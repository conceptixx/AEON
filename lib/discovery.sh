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
# CONFIGURATION
# ============================================================================

DISCOVERY_TIMEOUT=300              # Max time for discovery (5 min)
PING_TIMEOUT=1                     # Ping timeout per host
SSH_TIMEOUT=5                      # SSH connection timeout
SSH_RETRIES=2                      # SSH retry attempts
PARALLEL_SCAN_JOBS=50              # Parallel ping jobs

# Common SSH users to try
DEFAULT_SSH_USERS=("pi" "ubuntu" "aeon" "aeon-llm" "aeon-host")

# Global arrays
DISCOVERED_IPS=()
ACCESSIBLE_DEVICES=()

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
# NETWORK SCANNING
# ============================================================================

#
# check_scan_tools
# 
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
# scan_network_nmap
# 
#
scan_network_nmap() {
    local network_range="$1"
    
    log INFO "Scanning network with nmap: $network_range"
    
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
# scan_network_ping $network_reange
#
#
scan_network_ping() {
    local network_range="$1"
    
    log INFO "Scanning network with ping sweep: $network_range"
    
    # Extract network prefix (e.g., 192.168.1 from 192.168.1.0/24)
    local network_prefix=$(echo "$network_range" | cut -d'/' -f1 | rev | cut -d'.' -f2- | rev)
    
    # Get CIDR (e.g., 24 from 192.168.1.0/24)
    local cidr=$(echo "$network_range" | cut -d'/' -f2)
    
    # For /24, scan .1 to .254
    if [[ "$cidr" == "24" ]]; then
        log INFO "Ping sweep ${network_prefix}.1-254 (this may take a while)..."
        
        local alive_hosts=()
        local self_ip=$(hostname -I | awk '{print $1}')
        
        # Parallel ping sweep
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
        log ERROR "Only /24 networks supported for ping sweep"
        return 1
    fi
}

#
# discover_network_devices $network_reange
#
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
    
    # Store in global array
    DISCOVERED_IPS=($(echo "$discovered" | sort -V))
    
    local count=${#DISCOVERED_IPS[@]}
    
    if [[ $count -eq 0 ]]; then
        log ERROR "No devices found on network $network_range"
        return 1
    fi
    
    log SUCCESS "Found $count device(s) on network"
    
    # Display discovered IPs
    for ip in "${DISCOVERED_IPS[@]}"; do
        log INFO "  • $ip"
    done
    
    return 0
}

# ============================================================================
# SSH CONNECTIVITY TESTING
# ============================================================================

#
# test_ssh_connection $ip $user $password
#
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
# find_ssh_credentials $ip $user $password
#
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
    
    # Try common user/password combinations
    local common_passwords=("raspberry" "ubuntu" "aeon" "pi")
    
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
#
#
test_ssh_accessibility() {
    local user="${1:-}"
    local password="${2:-}"
    
    print_header "SSH Connectivity Testing"
    
    log STEP "Testing SSH access to ${#DISCOVERED_IPS[@]} device(s)..."
    
    if [[ -z "$user" ]] || [[ -z "$password" ]]; then
        log WARN "No credentials provided, will try common defaults"
    fi
    
    local accessible_count=0
    local tested_count=0
    
    for ip in "${DISCOVERED_IPS[@]}"; do
        ((tested_count++))
        
        printf "\r  Testing [$tested_count/${#DISCOVERED_IPS[@]}] $ip..."
        
        local credentials=""
        credentials=$(find_ssh_credentials "$ip" "$user" "$password")
        
        if [[ $? -eq 0 ]]; then
            echo ""  # New line for log
            log SUCCESS "[$ip] SSH accessible (${credentials%%:*})"
            ACCESSIBLE_DEVICES+=("${ip}:${credentials}")
            ((accessible_count++))
        else
            echo ""  # New line for log
            log WARN "[$ip] SSH not accessible"
        fi
    done
    
    echo ""  # New line after progress
    
    if [[ $accessible_count -eq 0 ]]; then
        log ERROR "No devices accessible via SSH"
        log INFO "Please ensure:"
        log INFO "  • SSH is enabled on devices"
        log INFO "  • Correct username/password provided"
        log INFO "  • Firewall allows SSH (port 22)"
        return 1
    fi
    
    log SUCCESS "$accessible_count device(s) accessible via SSH"
    
    return 0
}

# ============================================================================
# DEVICE TYPE DETECTION
# ============================================================================

#
# detect_device_type $ip $user $password
#
#
detect_device_type() {
    local ip="$1"
    local user="$2"
    local password="$3"
    
    # Check /proc/cpuinfo for Raspberry Pi
    local is_raspberry_pi=$(sshpass -p "$password" ssh \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout="$SSH_TIMEOUT" \
        "${user}@${ip}" \
        "grep -qi 'Raspberry' /proc/cpuinfo && echo 'yes' || echo 'no'" 2>/dev/null)
    
    if [[ "$is_raspberry_pi" == "yes" ]]; then
        echo "raspberry_pi"
        return 0
    fi
    
    # Check hostname for conventions
    local hostname=$(sshpass -p "$password" ssh \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout="$SSH_TIMEOUT" \
        "${user}@${ip}" "hostname" 2>/dev/null)
    
    # LLM computer naming convention
    if [[ "$hostname" =~ ^aeon-llm ]]; then
        echo "llm_computer"
        return 0
    fi
    
    # Host computer naming convention  
    if [[ "$hostname" =~ ^aeon-host ]]; then
        echo "host_computer"
        return 0
    fi
    
    # Default to host computer
    echo "host_computer"
    return 0
}

#
# classify_devices
# 
#
classify_devices() {
    print_header "Device Classification"
    
    log STEP "Classifying ${#ACCESSIBLE_DEVICES[@]} device(s)..."
    
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
                log INFO "[$ip] Raspberry Pi"
                ((pi_count++))
                ;;
            llm_computer)
                log INFO "[$ip] LLM Computer"
                ((llm_count++))
                ;;
            host_computer)
                log INFO "[$ip] Host Computer"
                ((host_count++))
                ;;
        esac
    done
    
    echo ""
    log SUCCESS "Classification complete:"
    log INFO "  • Raspberry Pis: $pi_count"
    log INFO "  • LLM Computers: $llm_count"
    log INFO "  • Host Computers: $host_count"
    echo ""
    
    # Check minimum requirements
    if [[ $pi_count -lt 3 ]]; then
        log ERROR "Minimum 3 Raspberry Pis required (found $pi_count)"
        log INFO "AEON requires at least 3 Raspberry Pis for manager quorum"
        return 1
    fi
    
    log SUCCESS "Minimum requirements met ($pi_count Raspberry Pis)"
    
    return 0
}

# ============================================================================
# SAVE DISCOVERED DEVICES
# ============================================================================

#
# save_discovered_devices $output_file
# 
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
    
    # Create complete JSON
    cat > "$output_file" <<EOF
{
  "discovery_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "network_range": "${NETWORK_RANGE:-unknown}",
  "total_discovered": ${#DISCOVERED_IPS[@]},
  "total_accessible": ${#ACCESSIBLE_DEVICES[@]},
  "devices": $devices_json
}
EOF
    
    log SUCCESS "Discovered devices saved to $output_file"
    
    return 0
}

# ============================================================================
# INTERACTIVE DISCOVERY
# ============================================================================

#
# interactive_discovery $output_file
#
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
    
    local pi_count=$(cat "$output_file" | jq -r '.devices[] | select(.device_type == "raspberry_pi") | .ip' | wc -l)
    local llm_count=$(cat "$output_file" | jq -r '.devices[] | select(.device_type == "llm_computer") | .ip' | wc -l)
    local host_count=$(cat "$output_file" | jq -r '.devices[] | select(.device_type == "host_computer") | .ip' | wc -l)
    local total_count=$(cat "$output_file" | jq -r '.devices | length')
    
    log SUCCESS "Discovery Summary:"
    log INFO "  • Total devices found: $total_count"
    log INFO "  • Raspberry Pis: $pi_count"
    log INFO "  • LLM Computers: $llm_count"
    log INFO "  • Host Computers: $host_count"
    log INFO "  • Results: $output_file"
    echo ""
    
    if [[ $pi_count -ge 3 ]]; then
        log SUCCESS "✅ Ready to proceed with cluster setup"
    else
        log ERROR "❌ Need at least 3 Raspberry Pis (found $pi_count)"
        return 1
    fi
    
    return 0
}

# ============================================================================
# NON-INTERACTIVE DISCOVERY
# ============================================================================

#
# automated_discovery $network_range $ssh_user $ssh_password $output_file
#
#
automated_discovery() {
    local network_range="$1"
    local ssh_user="$2"
    local ssh_password="$3"
    local output_file="$4"
    
    NETWORK_RANGE="$network_range"
    
    # Run discovery steps
    discover_network_devices "$network_range" || return 1
    test_ssh_accessibility "$ssh_user" "$ssh_password" || return 1
    classify_devices || return 1
    save_discovered_devices "$output_file" || return 1
    
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

#
# 02-discovery.sh interactive/--interactive $output_file
# 02-discovery.sh automated/--automated $network_range $ssh_user $ssh_password $output_file
# 02-discovery.sh
# standalone execution
#
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
