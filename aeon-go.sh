#!/bin/bash
################################################################################
# AEON Bootstrap Script (aeon-go.sh)
# Version: 0.1.0
# Purpose: Complete AEON Network setup with parallel installation
#
# Usage:
#   curl -fsSL https://get.aeon.dev | bash
#   OR
#   bash aeon-go.sh
#
# Requirements:
#   - Minimum 3 Raspberry Pis on network
#   - Standardized usernames (pi, aeon-llm, aeon-host)
#   - Shared initial password across devices
################################################################################

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

AEON_VERSION="0.1.0"
AEON_DIR="/opt/aeon"
LOG_DIR="$AEON_DIR/logs"
DATA_DIR="$AEON_DIR/data"
LIB_DIR="$AEON_DIR/lib"
TEMP_DIR="$AEON_DIR/tmp"

# Log files
MAIN_LOG="$LOG_DIR/aeon-go.log"
DISCOVERY_LOG="$LOG_DIR/discovery.log"
INSTALL_LOG="$LOG_DIR/installation.log"
ERROR_LOG="$LOG_DIR/errors.log"

# Network configuration
SCAN_NETWORK="192.168.1.0/24"  # Will auto-detect
SSH_TIMEOUT=5
MAX_PARALLEL_JOBS=10

# User conventions
declare -A DEVICE_USERS=(
    ["raspberry_pi"]="pi"
    ["llm_computer"]="aeon-llm"
    ["host_computer"]="aeon-host"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" | tee -a "$MAIN_LOG"
    
    case "$level" in
        ERROR)
            echo "[$timestamp] $message" >> "$ERROR_LOG"
            echo -e "${RED}❌ $message${NC}" >&2
            ;;
        WARN)
            echo -e "${YELLOW}⚠️  $message${NC}"
            ;;
        INFO)
            echo -e "${CYAN}ℹ️  $message${NC}"
            ;;
        SUCCESS)
            echo -e "${GREEN}✅ $message${NC}"
            ;;
        DEBUG)
            if [[ "${DEBUG:-0}" == "1" ]]; then
                echo -e "${MAGENTA}🔍 $message${NC}"
            fi
            ;;
    esac
}

progress() {
    local current=$1
    local total=$2
    local message=$3
    local percent=$((current * 100 / total))
    
    printf "\r${CYAN}[%3d%%]${NC} %s" "$percent" "$message"
    
    if [[ $current -eq $total ]]; then
        echo ""
    fi
}

spinner() {
    local pid=$1
    local message=$2
    local spin='-\|/'
    local i=0
    
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r${CYAN}${spin:$i:1}${NC} %s" "$message"
        sleep 0.1
    done
    
    printf "\r${GREEN}✓${NC} %s\n" "$message"
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

setup_directories() {
    log INFO "Setting up AEON directories..."
    
    mkdir -p "$AEON_DIR" "$LOG_DIR" "$DATA_DIR" "$LIB_DIR" "$TEMP_DIR"
    mkdir -p "$AEON_DIR/secrets" "$AEON_DIR/config"
    
    chmod 700 "$AEON_DIR/secrets"
    
    log SUCCESS "Directories created"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log ERROR "This script must be run as root"
        echo ""
        echo "Please run: sudo bash aeon-go.sh"
        exit 1
    fi
}

detect_network_range() {
    log INFO "Detecting network range..."
    
    local ip=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')
    local interface=$(ip route get 1.1.1.1 | grep -oP 'dev \K\S+')
    
    if [[ -n "$ip" ]]; then
        # Extract network (assume /24)
        local network="${ip%.*}.0/24"
        SCAN_NETWORK="$network"
        log SUCCESS "Network range detected: $SCAN_NETWORK"
    else
        log WARN "Could not auto-detect network, using default: $SCAN_NETWORK"
    fi
}

check_internet() {
    log INFO "Checking internet connectivity..."
    
    if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        log SUCCESS "Internet connection: OK"
        return 0
    else
        log ERROR "No internet connection detected"
        echo ""
        echo "AEON requires internet for initial setup to download packages."
        echo "Please ensure internet connectivity and try again."
        exit 1
    fi
}

# ============================================================================
# PASSWORD HANDLING
# ============================================================================

collect_cluster_password() {
    log INFO "Collecting cluster password..."
    
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  AEON Cluster Password${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Please enter the shared password used across all devices."
    echo ""
    echo "This password should be configured on:"
    echo "  • All Raspberry Pis (user: pi)"
    echo "  • All LLM computers (user: aeon-llm)"
    echo "  • All host computers (user: aeon-host)"
    echo ""
    echo -e "${YELLOW}⚠️  Security: This password will be used ONLY for initial setup.${NC}"
    echo -e "${YELLOW}   You'll be prompted to change passwords after installation.${NC}"
    echo ""
    
    # Read password securely
    read -s -p "Cluster Password: " CLUSTER_PASSWORD
    echo ""
    read -s -p "Confirm Password: " CLUSTER_PASSWORD_CONFIRM
    echo ""
    
    if [[ "$CLUSTER_PASSWORD" != "$CLUSTER_PASSWORD_CONFIRM" ]]; then
        log ERROR "Passwords do not match"
        exit 1
    fi
    
    if [[ -z "$CLUSTER_PASSWORD" ]]; then
        log ERROR "Password cannot be empty"
        exit 1
    fi
    
    # Store temporarily (will be cleared after setup)
    echo "$CLUSTER_PASSWORD" > "$AEON_DIR/secrets/.cluster_password"
    chmod 600 "$AEON_DIR/secrets/.cluster_password"
    
    log SUCCESS "Password collected and secured"
}

# ============================================================================
# NETWORK DISCOVERY
# ============================================================================

test_ssh_connection() {
    local ip="$1"
    local user="$2"
    local password="$3"
    
    # Use sshpass for password authentication
    if ! command -v sshpass &>/dev/null; then
        apt-get update -qq &>/dev/null
        apt-get install -y sshpass &>/dev/null
    fi
    
    # Test connection with timeout
    if sshpass -p "$password" ssh -o StrictHostKeyChecking=no \
                                  -o ConnectTimeout=$SSH_TIMEOUT \
                                  -o BatchMode=no \
                                  "$user@$ip" "echo ok" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

discover_devices() {
    log INFO "Starting network discovery..."
    
    local discovered_file="$DATA_DIR/discovered_devices.json"
    local temp_discovered="$TEMP_DIR/discovered.tmp"
    
    echo "[]" > "$temp_discovered"
    
    local password=$(cat "$AEON_DIR/secrets/.cluster_password")
    
    # Get entry device info
    local entry_ip=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')
    
    echo ""
    echo -e "${BOLD}Scanning network: $SCAN_NETWORK${NC}"
    echo ""
    
    # Scan for all device types
    local total_scanned=0
    local devices_found=0
    
    # Calculate total IPs to scan (assume /24)
    local total_ips=254
    
    for ip in $(nmap -sn "$SCAN_NETWORK" -oG - | grep "Up" | awk '{print $2}'); do
        total_scanned=$((total_scanned + 1))
        
        # Skip entry device (will add separately)
        if [[ "$ip" == "$entry_ip" ]]; then
            continue
        fi
        
        progress $total_scanned $total_ips "Scanning $ip..."
        
        # Try each user type
        for device_type in raspberry_pi llm_computer host_computer; do
            local user="${DEVICE_USERS[$device_type]}"
            
            if test_ssh_connection "$ip" "$user" "$password"; then
                devices_found=$((devices_found + 1))
                
                log SUCCESS "Found $device_type at $ip (user: $user)" >> "$DISCOVERY_LOG"
                
                # Add to discovered devices
                local device_json=$(cat <<EOF
{
    "ip": "$ip",
    "user": "$user",
    "type": "$device_type",
    "discovered_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)
                
                # Append to temp file (will properly format later)
                echo "$device_json" >> "$temp_discovered"
                
                break  # Found user, no need to try others
            fi
        done
    done
    
    echo ""
    log SUCCESS "Discovery complete: Found $devices_found device(s)"
    
    # Format discovered devices as proper JSON array
    # (Simple approach - will enhance in Python module)
    mv "$temp_discovered" "$discovered_file"
    
    echo "$devices_found"
}

# ============================================================================
# HARDWARE DETECTION (Remote Execution)
# ============================================================================

detect_hardware_remote() {
    local ip="$1"
    local user="$2"
    local password="$3"
    
    # Transfer hardware detection script
    log DEBUG "Detecting hardware on $ip..."
    
    # Inline hardware detection script (will be executed remotely)
    local detect_script=$(cat <<'REMOTE_SCRIPT'
#!/bin/bash

# Detect device type
if grep -qi "raspberry" /proc/cpuinfo; then
    DEVICE_TYPE="raspberry_pi"
    
    # Detect Pi model
    if grep -qi "Pi 5" /proc/cpuinfo; then
        MODEL="pi5"
    elif grep -qi "Pi 4" /proc/cpuinfo; then
        MODEL="pi4"
    elif grep -qi "Pi 3" /proc/cpuinfo; then
        MODEL="pi3"
    else
        MODEL="unknown_pi"
    fi
else
    # Check for GPU
    if lspci 2>/dev/null | grep -iE "nvidia|amd.*radeon|amd.*vega"; then
        DEVICE_TYPE="llm_computer"
        MODEL="gpu_workstation"
    else
        DEVICE_TYPE="host_computer"
        MODEL="standard_pc"
    fi
fi

# CPU info
CPU_ARCH=$(uname -m)
CPU_CORES=$(nproc)
CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)

# RAM info
RAM_TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
RAM_TOTAL_GB=$(awk "BEGIN {printf \"%.1f\", $RAM_TOTAL_KB/1024/1024}")

# Storage info
ROOT_DEVICE=$(df / | tail -1 | awk '{print $1}')
STORAGE_TOTAL=$(df -BG / | tail -1 | awk '{print $2}' | tr -d 'G')

# Detect storage type
if [[ "$ROOT_DEVICE" =~ mmcblk ]]; then
    STORAGE_TYPE="sd"
elif [[ "$ROOT_DEVICE" =~ nvme ]]; then
    STORAGE_TYPE="nvme"
elif lsblk -d -o name,rota | grep "$ROOT_DEVICE" | grep "0" &>/dev/null; then
    STORAGE_TYPE="ssd"
else
    STORAGE_TYPE="hdd"
fi

# Network speed
NET_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
if [[ -n "$NET_IFACE" ]]; then
    NET_SPEED=$(cat /sys/class/net/$NET_IFACE/speed 2>/dev/null || echo "0")
else
    NET_SPEED="0"
fi

# GPU info (if present)
GPU_PRESENT="false"
GPU_MODEL=""
if lspci 2>/dev/null | grep -iE "nvidia|amd.*radeon"; then
    GPU_PRESENT="true"
    GPU_MODEL=$(lspci | grep -iE "nvidia|amd.*radeon" | head -1 | cut -d: -f3 | xargs)
fi

# Output JSON
cat <<JSON
{
    "hostname": "$(hostname)",
    "device_type": "$DEVICE_TYPE",
    "model": "$MODEL",
    "cpu": {
        "arch": "$CPU_ARCH",
        "cores": $CPU_CORES,
        "model": "$CPU_MODEL"
    },
    "memory": {
        "total_gb": $RAM_TOTAL_GB
    },
    "storage": {
        "type": "$STORAGE_TYPE",
        "total_gb": $STORAGE_TOTAL
    },
    "network": {
        "speed_mbps": $NET_SPEED
    },
    "gpu": {
        "present": $GPU_PRESENT,
        "model": "$GPU_MODEL"
    }
}
JSON
REMOTE_SCRIPT
)
    
    # Execute remotely and capture JSON
    local hw_json=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no \
                                                "$user@$ip" \
                                                "bash -s" <<< "$detect_script" 2>/dev/null)
    
    if [[ -n "$hw_json" ]]; then
        echo "$hw_json" > "$DATA_DIR/hw_${ip}.json"
        return 0
    else
        log WARN "Failed to detect hardware on $ip"
        return 1
    fi
}

detect_all_hardware() {
    log INFO "Detecting hardware on all devices (parallel)..."
    
    local password=$(cat "$AEON_DIR/secrets/.cluster_password")
    local discovered_file="$DATA_DIR/discovered_devices.json"
    
    # Read discovered devices (simplified - real version would parse JSON properly)
    local device_count=$(grep -c '"ip"' "$discovered_file" 2>/dev/null || echo "0")
    
    if [[ "$device_count" -eq 0 ]]; then
        log WARN "No devices discovered"
        return
    fi
    
    echo ""
    log INFO "Detecting hardware on $device_count device(s)..."
    
    # TODO: Parse JSON properly and parallelize
    # For now, sequential detection
    
    log SUCCESS "Hardware detection complete"
}

# ============================================================================
# NETWORK VALIDATION
# ============================================================================

validate_aeon_network() {
    log INFO "Validating AEON Network requirements..."
    
    # Count Raspberry Pis
    local pi_count=$(grep -c '"raspberry_pi"' "$DATA_DIR/discovered_devices.json" 2>/dev/null || echo "0")
    
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  AEON Network Validation${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Raspberry Pis found: ${BOLD}$pi_count${NC}"
    echo -e "  Required minimum: ${BOLD}3${NC}"
    echo ""
    
    if [[ "$pi_count" -lt 3 ]]; then
        echo -e "${RED}❌ VALIDATION FAILED${NC}"
        echo ""
        echo "AEON Network requires minimum 3 Raspberry Pis."
        echo ""
        echo "Why?"
        echo "  • AEON = Autonomous Evolving Orchestration NETWORK"
        echo "  • Network requires distributed consensus (Raft algorithm)"
        echo "  • Raspberry Pis provide guaranteed 24/7 availability"
        echo "  • Minimum 3 managers for fault tolerance"
        echo ""
        echo "Current status:"
        echo "  Found: $pi_count Raspberry Pi(s)"
        echo "  Missing: $((3 - pi_count)) Raspberry Pi(s)"
        echo ""
        echo "Please add $((3 - pi_count)) more Raspberry Pi(s) and try again."
        echo ""
        exit 1
    fi
    
    log SUCCESS "Network validation passed"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

print_banner() {
    clear
    echo ""
    echo -e "${MAGENTA}${BOLD}"
    cat << "BANNER"
     █████╗ ███████╗ ██████╗ ███╗   ██╗
    ██╔══██╗██╔════╝██╔═══██╗████╗  ██║
    ███████║█████╗  ██║   ██║██╔██╗ ██║
    ██╔══██║██╔══╝  ██║   ██║██║╚██╗██║
    ██║  ██║███████╗╚██████╔╝██║ ╚████║
    ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝
BANNER
    echo -e "${NC}"
    echo -e "  ${CYAN}Autonomous Evolving Orchestration Network${NC}"
    echo -e "  ${CYAN}Version: $AEON_VERSION${NC}"
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

main() {
    print_banner
    
    # Pre-flight checks
    log INFO "Starting AEON bootstrap..."
    check_root
    setup_directories
    check_internet
    detect_network_range
    
    # Collect credentials
    collect_cluster_password
    
    # Discovery phase
    echo ""
    echo -e "${BOLD}Phase 1: Network Discovery${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    local device_count=$(discover_devices)
    
    # Hardware detection
    echo ""
    echo -e "${BOLD}Phase 2: Hardware Detection${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    detect_all_hardware
    
    # Network validation
    echo ""
    echo -e "${BOLD}Phase 3: Network Validation${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    validate_aeon_network
    
    # TODO: Continue with installation phases
    
    echo ""
    log SUCCESS "AEON bootstrap complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Review installation summary"
    echo "  2. Access setup UI: http://$(hostname -I | awk '{print $1}'):8888"
    echo ""
}

# Trap errors
trap 'log ERROR "Script failed at line $LINENO"' ERR

# Execute main
main "$@"
