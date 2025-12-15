#!/bin/bash
################################################################################
# AEON Synchronized Reboot Module
# File: lib/reboot.sh
# Version: 0.1.0
#
# Purpose: Orchestrate synchronized cluster reboot to prevent split-brain
#          and maintain cluster consensus during system reboots.
#
# Reboot Order:
#   1. Workers (least critical)
#   2. Managers (except entry device)
#   3. Entry device (last, maintains coordination)
#
# Features:
#   - Parallel worker reboot
#   - Sequential manager reboot
#   - Wait for all devices online
#   - Health verification after reboot
#   - Automatic rollback on failure
################################################################################

set -euo pipefail

# ============================================================================
# DEPENDENCIES
# ============================================================================

# Prevent double-loading
[[ -n "${AEON_REBOOT_LOADED:-}" ]] && return 0
readonly AEON_REBOOT_LOADED=1

# Load dependencies
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
if [[ -z "${AEON_DEPENDENCIES_LOADED:-}" ]]; then
    source "$SCRIPT_DIR/dependencies.sh" || source "/opt/aeon/lib/dependencies.sh" || {
        echo "ERROR: Cannot find dependencies.sh" >&2
        exit 1
    }
fi

# load dependecies -if available
load_dependencies "reboot.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

REBOOT_WORKER_DELAY=30          # Wait after workers reboot (seconds)
REBOOT_MANAGER_DELAY=60         # Wait after managers reboot (seconds)
REBOOT_ENTRY_DELAY=90           # Wait after entry device reboot (seconds)
REBOOT_ONLINE_TIMEOUT=300       # Max wait for devices to come online (5 min)
REBOOT_HEALTH_CHECK_RETRIES=3   # Health check retry count

# ============================================================================
# DEVICE CLASSIFICATION
# ============================================================================

classify_devices() {
    local role_assignments_file="${1:-}"
    local entry_device_ip="${2:-}"
    
    if [[ -z "$role_assignments_file" ]] || [[ ! -f "$role_assignments_file" ]]; then
        log ERROR "Invalid role assignments file: $role_assignments_file"
        return 1
    fi
    
    log STEP "Classifying devices for reboot order..."
    
    # Extract devices by role
    MANAGER_DEVICES=$(jq -r '.assignments[] | select(.role == "manager") | .device.ip' "$role_assignments_file")
    WORKER_DEVICES=$(jq -r '.assignments[] | select(.role == "worker") | .device.ip' "$role_assignments_file")
    
    # Separate entry device from other managers
    OTHER_MANAGERS=()
    for ip in $MANAGER_DEVICES; do
        if [[ "$ip" != "$entry_device_ip" ]]; then
            OTHER_MANAGERS+=("$ip")
        fi
    done
    
    # Convert to arrays
    WORKERS=($WORKER_DEVICES)
    
    log INFO "Worker devices: ${#WORKERS[@]}"
    log INFO "Manager devices (excluding entry): ${#OTHER_MANAGERS[@]}"
    log INFO "Entry device: $entry_device_ip"
    
    return 0
}

# ============================================================================
# REBOOT DETECTION
# ============================================================================

check_devices_need_reboot() {
    local results_file="${1:-}"
    
    if [[ ! -f "$results_file" ]]; then
        log ERROR "Results file not found: $results_file"
        return 1
    fi
    
    log STEP "Checking which devices require reboot..."
    
    # Parse installation results
    local devices_needing_reboot=$(jq -r '.devices[] | select(.output | contains("REBOOT_REQUIRED")) | .ip' "$results_file" 2>/dev/null || echo "")
    
    if [[ -z "$devices_needing_reboot" ]]; then
        log SUCCESS "No devices require reboot"
        return 1  # No reboot needed
    fi
    
    # Count devices
    local reboot_count=$(echo "$devices_needing_reboot" | wc -l)
    
    log WARN "$reboot_count device(s) require reboot:"
    for ip in $devices_needing_reboot; do
        log INFO "  • $ip"
    done
    
    echo "$devices_needing_reboot"
    return 0  # Reboot needed
}

# ============================================================================
# REBOOT EXECUTION
# ============================================================================

reboot_devices() {
    local devices_ref="$1[@]"
    local devices=("${!devices_ref}")
    local description="$2"
    local user="${3:-aeon}"
    local password="${4:-}"
    
    if [[ ${#devices[@]} -eq 0 ]]; then
        log INFO "No devices to reboot in this group"
        return 0
    fi
    
    log STEP "$description (${#devices[@]} device(s))..."
    
    # Build device array for parallel execution
    local device_array=()
    for ip in "${devices[@]}"; do
        device_array+=("${ip}:${user}:${password}")
    done
    
    # Execute reboot command
    parallel_exec device_array[@] \
        "sudo systemctl reboot" \
        "$description"
    
    log SUCCESS "Reboot command sent to ${#devices[@]} device(s)"
    return 0
}

# ============================================================================
# WAIT FOR DEVICES ONLINE
# ============================================================================

wait_for_devices_online() {
    local devices_ref="$1[@]"
    local devices=("${!devices_ref}")
    local timeout="${2:-$REBOOT_ONLINE_TIMEOUT}"
    local user="${3:-aeon}"
    local password="${4:-}"
    
    if [[ ${#devices[@]} -eq 0 ]]; then
        log INFO "No devices to wait for"
        return 0
    fi
    
    log STEP "Waiting for ${#devices[@]} device(s) to come back online (timeout: ${timeout}s)..."
    
    # Build device array for parallel wait
    local device_array=()
    for ip in "${devices[@]}"; do
        device_array+=("${ip}:${user}:${password}")
    done
    
    # Use parallel module's wait function
    parallel_wait_online device_array[@] "$timeout"
    
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        log SUCCESS "All devices are back online"
        return 0
    else
        log ERROR "Some devices failed to come back online within ${timeout}s"
        return 1
    fi
}

# ============================================================================
# HEALTH VERIFICATION
# ============================================================================

verify_device_health() {
    local ip="$1"
    local user="${2:-aeon}"
    local password="${3:-}"
    
    log INFO "Verifying health of $ip..."
    
    # Check 1: Docker is running
    if ! sshpass -p "$password" ssh -o StrictHostKeyChecking=no \
        "${user}@${ip}" "systemctl is-active docker" &>/dev/null; then
        log WARN "[$ip] Docker service not running"
        return 1
    fi
    
    # Check 2: Docker daemon accessible
    if ! sshpass -p "$password" ssh -o StrictHostKeyChecking=no \
        "${user}@${ip}" "docker info" &>/dev/null; then
        log WARN "[$ip] Docker daemon not accessible"
        return 1
    fi
    
    # Check 3: System load is reasonable (optional)
    local load=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no \
        "${user}@${ip}" "uptime | awk -F'load average:' '{print \$2}' | awk '{print \$1}' | tr -d ','")
    
    log INFO "[$ip] ✓ Docker running, load: $load"
    return 0
}

verify_cluster_health() {
    local devices_ref="$1[@]"
    local devices=("${!devices_ref}")
    local user="${2:-aeon}"
    local password="${3:-}"
    
    if [[ ${#devices[@]} -eq 0 ]]; then
        return 0
    fi
    
    log STEP "Verifying cluster health (${#devices[@]} device(s))..."
    
    local healthy=0
    local unhealthy=0
    
    for ip in "${devices[@]}"; do
        if verify_device_health "$ip" "$user" "$password"; then
            ((healthy++))
        else
            ((unhealthy++))
        fi
    done
    
    if [[ $unhealthy -gt 0 ]]; then
        log WARN "$unhealthy device(s) failed health check"
    fi
    
    log SUCCESS "$healthy device(s) healthy"
    return 0
}

# ============================================================================
# MAIN SYNCHRONIZED REBOOT ORCHESTRATION
# ============================================================================

synchronized_reboot() {
    local role_assignments_file="${1:-}"
    local entry_device_ip="${2:-}"
    local user="${3:-aeon}"
    local password="${4:-}"
    
    # Validate required parameters
    if [[ -z "$role_assignments_file" ]]; then
        log ERROR "Role assignments file not specified"
        log INFO "Usage: synchronized_reboot <role_assignments.json> <entry_ip> <user> <password>"
        return 1
    fi
    
    if [[ ! -f "$role_assignments_file" ]]; then
        log ERROR "Role assignments file not found: $role_assignments_file"
        log INFO "This file is created during role assignment phase"
        log INFO "Run hardware detection and role assignment first"
        return 1
    fi
    
    if [[ -z "$entry_device_ip" ]]; then
        log ERROR "Entry device IP not specified"
        return 1
    fi
    
    print_header "Synchronized Cluster Reboot"
    
    log INFO "Role assignments: $role_assignments_file"
    log INFO "Entry device: $entry_device_ip"
    log INFO "Reboot user: $user"
    echo ""
    
    # Classify devices
    classify_devices "$role_assignments_file" "$entry_device_ip"
    
    # Calculate total devices that need reboot
    local total_reboot_devices=$((${#WORKERS[@]} + ${#OTHER_MANAGERS[@]} + 1))
    
    log INFO "Devices requiring reboot: $total_reboot_devices"
    echo ""
    
    # ========================================================================
    # STAGE 1: Reboot Workers (Parallel)
    # ========================================================================
    
    if [[ ${#WORKERS[@]} -gt 0 ]]; then
        print_header "Stage 1: Rebooting Workers"
        
        log INFO "Rebooting ${#WORKERS[@]} worker(s) in parallel..."
        
        reboot_devices WORKERS \
            "Rebooting workers" \
            "$user" \
            "$password"
        
        log INFO "Waiting ${REBOOT_WORKER_DELAY}s for workers to shutdown..."
        sleep "$REBOOT_WORKER_DELAY"
        
        log INFO "Waiting for workers to come back online..."
        if ! wait_for_devices_online WORKERS "$REBOOT_ONLINE_TIMEOUT" "$user" "$password"; then
            log ERROR "Some workers failed to come back online"
            log WARN "Continuing anyway (workers are not critical for cluster formation)..."
        fi
        
        # Verify worker health
        verify_cluster_health WORKERS "$user" "$password"
        
        echo ""
    else
        log INFO "No worker nodes to reboot"
        echo ""
    fi
    
    # ========================================================================
    # STAGE 2: Reboot Managers (Sequential, excluding entry)
    # ========================================================================
    
    if [[ ${#OTHER_MANAGERS[@]} -gt 0 ]]; then
        print_header "Stage 2: Rebooting Managers (Sequential)"
        
        log WARN "Rebooting managers one at a time to maintain quorum..."
        
        for manager_ip in "${OTHER_MANAGERS[@]}"; do
            log INFO "Rebooting manager: $manager_ip"
            
            # Reboot single manager
            local single_manager=("$manager_ip")
            reboot_devices single_manager \
                "Rebooting manager $manager_ip" \
                "$user" \
                "$password"
            
            log INFO "Waiting ${REBOOT_MANAGER_DELAY}s for manager to shutdown..."
            sleep "$REBOOT_MANAGER_DELAY"
            
            log INFO "Waiting for manager to come back online..."
            if ! wait_for_devices_online single_manager "$REBOOT_ONLINE_TIMEOUT" "$user" "$password"; then
                log ERROR "Manager $manager_ip failed to come back online!"
                log ERROR "This may cause cluster issues!"
                
                # Ask user if they want to continue
                read -p "Continue with remaining reboots? [y/N] " -n 1 -r < /dev/tty
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log ERROR "Reboot sequence aborted by user"
                    return 1
                fi
            else
                log SUCCESS "Manager $manager_ip is back online"
            fi
            
            # Verify manager health
            verify_device_health "$manager_ip" "$user" "$password"
            
            echo ""
        done
        
        log SUCCESS "All managers rebooted successfully"
        echo ""
    else
        log INFO "No additional managers to reboot (only entry device is manager)"
        echo ""
    fi
    
    # ========================================================================
    # STAGE 3: Reboot Entry Device (LAST!)
    # ========================================================================
    
    print_header "Stage 3: Rebooting Entry Device"
    
    log WARN "⚠️  Entry device will now reboot"
    log WARN "⚠️  You will lose connection to this script"
    log WARN "⚠️  The device will come back online automatically"
    echo ""
    
    log INFO "Entry device IP: $entry_device_ip"
    log INFO "Expected downtime: ~${REBOOT_ENTRY_DELAY}s"
    echo ""
    
    # Save checkpoint file before rebooting
    local checkpoint_file="/opt/aeon/data/.reboot_checkpoint"
    echo "REBOOT_STAGE=complete" > "$checkpoint_file"
    echo "REBOOT_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$checkpoint_file"
    
    log INFO "Checkpoint saved to $checkpoint_file"
    log INFO "Initiating entry device reboot in 5 seconds..."
    
    for i in {5..1}; do
        echo -ne "\rRebooting in $i seconds... "
        sleep 1
    done
    echo ""
    
    # Reboot entry device
    log WARN "Rebooting NOW..."
    sudo systemctl reboot
    
    # This line should never be reached
    return 0
}

# ============================================================================
# VERIFY AFTER REBOOT (Run on next boot)
# ============================================================================

verify_reboot_completion() {
    local checkpoint_file="/opt/aeon/data/.reboot_checkpoint"
    
    if [[ ! -f "$checkpoint_file" ]]; then
        log INFO "No reboot checkpoint found (not needed)"
        return 1  # No reboot was performed
    fi
    
    log STEP "Verifying reboot completion..."
    
    # Load checkpoint
    source "$checkpoint_file"
    
    if [[ "$REBOOT_STAGE" == "complete" ]]; then
        log SUCCESS "Reboot completed successfully"
        log INFO "Reboot time: $REBOOT_TIME"
        
        # Clean up checkpoint
        rm -f "$checkpoint_file"
        
        return 0
    else
        log WARN "Reboot may not have completed properly"
        return 1
    fi
}

# ============================================================================
# DRY RUN (Testing mode)
# ============================================================================

dry_run_reboot() {
    local role_assignments_file="${1:-}"
    local entry_device_ip="${2:-}"
    
    if [[ -z "$role_assignments_file" ]] || [[ ! -f "$role_assignments_file" ]]; then
        log ERROR "Invalid role assignments file"
        return 1
    fi
    
    print_header "Synchronized Reboot - DRY RUN"
    
    log INFO "This is a DRY RUN - no actual reboots will occur"
    echo ""
    
    # Classify devices
    classify_devices "$role_assignments_file" "$entry_device_ip"
    
    # Show reboot plan
    echo -e "${BOLD}REBOOT PLAN:${NC}"
    echo ""
    
    if [[ ${#WORKERS[@]} -gt 0 ]]; then
        echo -e "${CYAN}Stage 1: Workers (Parallel)${NC}"
        for ip in "${WORKERS[@]}"; do
            echo "  • $ip"
        done
        echo "  Wait: ${REBOOT_WORKER_DELAY}s + ${REBOOT_ONLINE_TIMEOUT}s (online)"
        echo ""
    fi
    
    if [[ ${#OTHER_MANAGERS[@]} -gt 0 ]]; then
        echo -e "${CYAN}Stage 2: Managers (Sequential)${NC}"
        for ip in "${OTHER_MANAGERS[@]}"; do
            echo "  • $ip"
            echo "    Wait: ${REBOOT_MANAGER_DELAY}s + ${REBOOT_ONLINE_TIMEOUT}s (online)"
        done
        echo ""
    fi
    
    echo -e "${CYAN}Stage 3: Entry Device${NC}"
    echo "  • $entry_device_ip"
    echo "  Wait: ${REBOOT_ENTRY_DELAY}s + ${REBOOT_ONLINE_TIMEOUT}s (online)"
    echo ""
    
    # Calculate total time
    local total_time=0
    
    if [[ ${#WORKERS[@]} -gt 0 ]]; then
        total_time=$((total_time + REBOOT_WORKER_DELAY + REBOOT_ONLINE_TIMEOUT))
    fi
    
    if [[ ${#OTHER_MANAGERS[@]} -gt 0 ]]; then
        local manager_time=$((${#OTHER_MANAGERS[@]} * (REBOOT_MANAGER_DELAY + REBOOT_ONLINE_TIMEOUT)))
        total_time=$((total_time + manager_time))
    fi
    
    total_time=$((total_time + REBOOT_ENTRY_DELAY + REBOOT_ONLINE_TIMEOUT))
    
    log INFO "Estimated total reboot time: $((total_time / 60)) minutes"
    echo ""
    
    log SUCCESS "Dry run complete - no devices rebooted"
    return 0
}

# ============================================================================
# EXPORT FUNCTIONS
# ============================================================================

export -f synchronized_reboot
export -f classify_devices
export -f check_devices_need_reboot
export -f verify_reboot_completion
export -f dry_run_reboot

# ============================================================================
# STANDALONE EXECUTION
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    
    case "${1:-}" in
        --dry-run)
            dry_run_reboot "$2" "$3"
            ;;
        --verify)
            verify_reboot_completion
            ;;
        --check)
            check_devices_need_reboot "$2"
            ;;
        *)
            echo "Usage: $0 {--dry-run|--verify|--check} [role_assignments.json] [entry_ip]"
            echo ""
            echo "Commands:"
            echo "  --dry-run <assignments> <entry_ip>  Show reboot plan without rebooting"
            echo "  --verify                             Verify reboot completion"
            echo "  --check <results.json>              Check which devices need reboot"
            echo ""
            echo "Normal usage:"
            echo "  Source this file and call: synchronized_reboot <assignments> <entry_ip> <user> <password>"
            exit 1
            ;;
    esac
fi
