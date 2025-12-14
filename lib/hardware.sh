#!/bin/bash
################################################################################
# AEON Hardware Detection Orchestration
# File: lib/hardware.sh
# Version: 0.1.0
#
# Purpose: Orchestrate hardware profile collection from all devices
#
# Usage:
#   source /opt/aeon/lib/hardware.sh
#   run_hardware_detection \
#       "$DATA_DIR/discovered_devices.json" \
#       "$DATA_DIR/hw_profiles.json" || exit 1
#
# Provides:
#   - Device list loading
#   - Parallel hardware detection
#   - Result aggregation
#   - Profile validation
#
# Dependencies:
#   - lib/common.sh
#   - lib/parallel.sh
#   - remote/hardware.remote.sh
################################################################################

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || {
    echo "ERROR: Failed to source common.sh" >&2
    exit 1
}

source "$SCRIPT_DIR/parallel.sh" || {
    log ERROR "Failed to source parallel.sh"
    exit 1
}

# Prevent double-sourcing
[[ -n "${AEON_HARDWARE_LOADED:-}" ]] && return 0
readonly AEON_HARDWARE_LOADED=1

# ============================================================================
# CONFIGURATION
# ============================================================================

# Remote script name
readonly HARDWARE_SCRIPT="hardware.remote.sh"
readonly HARDWARE_SCRIPT_PATH="$REMOTE_DIR/$HARDWARE_SCRIPT"
readonly REMOTE_SCRIPT_PATH="/tmp/aeon_detect_hardware.sh"

# Required fields in hardware profile
readonly REQUIRED_HW_FIELDS=(
    "ip"
    "hostname"
    "device_type"
    "model"
    "ram_gb"
    "storage_type"
    "storage_size_gb"
    "cpu_cores"
)

# ============================================================================
# DEVICE LOADING
# ============================================================================

load_discovered_devices() {
    # Load devices from discovered_devices.json
    #
    # Arguments:
    #   $1 - Path to discovered_devices.json
    #
    # Returns:
    #   0 on success
    #   1 on failure
    #
    # Sets global:
    #   DISCOVERED_DEVICES_FILE
    
    local devices_file="$1"
    
    log_debug "Loading discovered devices from: $devices_file"
    
    # Validate file exists
    if [[ ! -f "$devices_file" ]]; then
        log ERROR "Discovered devices file not found: $devices_file"
        return 1
    fi
    
    # Validate JSON
    if ! json_validate "$devices_file"; then
        log ERROR "Invalid JSON in discovered devices file"
        return 1
    fi
    
    # Check has devices
    local device_count=$(jq -r '.devices | length' "$devices_file" 2>/dev/null)
    if [[ -z "$device_count" ]] || [[ "$device_count" == "0" ]]; then
        log ERROR "No devices found in discovered devices file"
        return 1
    fi
    
    DISCOVERED_DEVICES_FILE="$devices_file"
    log_debug "Loaded $device_count device(s)"
    
    return 0
}

build_device_array() {
    # Build array for parallel execution
    #
    # Arguments:
    #   $1 - Name of array variable (by reference)
    #
    # Returns:
    #   0 on success
    #   1 on failure
    #
    # Example:
    #   declare -a devices
    #   build_device_array devices
    
    local -n devices_ref=$1
    
    log_debug "Building device array..."
    
    # Clear array
    devices_ref=()
    
    # Read each device and build array
    while read -r device_json; do
        local ip=$(echo "$device_json" | jq -r '.ip')
        local user=$(echo "$device_json" | jq -r '.ssh_user')
        local password=$(echo "$device_json" | jq -r '.ssh_password')
        
        if [[ -z "$ip" ]] || [[ "$ip" == "null" ]]; then
            log_debug "Skipping device with no IP"
            continue
        fi
        
        devices_ref+=("${ip}:${user}:${password}")
    done < <(jq -c '.devices[]' "$DISCOVERED_DEVICES_FILE" 2>/dev/null)
    
    log_debug "Built array with ${#devices_ref[@]} device(s)"
    
    if [[ ${#devices_ref[@]} -eq 0 ]]; then
        log ERROR "No valid devices found"
        return 1
    fi
    
    return 0
}

# ============================================================================
# HARDWARE COLLECTION
# ============================================================================

transfer_detection_script() {
    # Transfer hardware detection script to all devices
    #
    # Arguments:
    #   $1 - Device array name (by reference)
    #
    # Returns:
    #   0 on success
    #   1 on failure
    
    local -n devices_ref=$1
    
    log INFO "Transferring hardware detection script to ${#devices_ref[@]} device(s)..."
    
    # Verify local script exists
    if [[ ! -f "$HARDWARE_SCRIPT_PATH" ]]; then
        log ERROR "Hardware detection script not found: $HARDWARE_SCRIPT_PATH"
        return 1
    fi
    
    # Transfer using parallel module
    parallel_file_transfer devices_ref \
        "$HARDWARE_SCRIPT_PATH" \
        "$REMOTE_SCRIPT_PATH"
    
    local result=$?
    
    if [[ $result -eq 0 ]]; then
        log SUCCESS "Detection script transferred"
    else
        log ERROR "Failed to transfer detection script to some devices"
    fi
    
    return $result
}

execute_hardware_detection() {
    # Execute hardware detection on all devices in parallel
    #
    # Arguments:
    #   $1 - Device array name (by reference)
    #
    # Returns:
    #   0 on success
    #   1 on failure
    
    local -n devices_ref=$1
    
    log INFO "Executing hardware detection on ${#devices_ref[@]} device(s)..."
    echo ""
    
    # Execute in parallel
    parallel_exec devices_ref \
        "bash $REMOTE_SCRIPT_PATH" \
        "Collecting hardware profiles"
    
    local result=$?
    
    echo ""
    
    if [[ $result -eq 0 ]]; then
        log SUCCESS "Hardware detection complete"
    else
        log WARN "Hardware detection had some failures"
    fi
    
    return 0  # Continue even with some failures
}

collect_hardware_result() {
    # Collect hardware profile from a single device
    #
    # Arguments:
    #   $1 - IP address
    #   $2 - SSH user
    #   $3 - SSH password
    #
    # Returns:
    #   JSON hardware profile (stdout)
    #   Empty string on failure
    
    local ip="$1"
    local user="$2"
    local password="$3"
    
    log_debug "Collecting hardware profile from $ip..."
    
    # Execute remote script and capture JSON output
    local hw_json=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        "${user}@${ip}" \
        "bash $REMOTE_SCRIPT_PATH" 2>/dev/null)
    
    if [[ -z "$hw_json" ]]; then
        log_debug "No hardware data from $ip"
        return 1
    fi
    
    # Validate it's valid JSON
    if ! echo "$hw_json" | jq empty 2>/dev/null; then
        log_debug "Invalid JSON from $ip"
        return 1
    fi
    
    echo "$hw_json"
    return 0
}

collect_hardware_results() {
    # SSH to each device and collect JSON hardware profiles
    #
    # Arguments:
    #   $1 - Device array name (by reference)
    #
    # Returns:
    #   JSON array of hardware profiles (stdout)
    
    local -n devices_ref=$1
    
    log STEP "Aggregating hardware profiles..."
    
    local hw_profiles='{"devices":['
    local first=true
    local collected=0
    local failed=0
    
    for device_info in "${devices_ref[@]}"; do
        local ip=$(echo "$device_info" | cut -d: -f1)
        local user=$(echo "$device_info" | cut -d: -f2)
        local password=$(echo "$device_info" | cut -d: -f3)
        
        local hw_json=$(collect_hardware_result "$ip" "$user" "$password")
        
        if [[ -n "$hw_json" ]]; then
            [[ "$first" == "false" ]] && hw_profiles+=","
            first=false
            hw_profiles+="$hw_json"
            ((collected++))
        else
            log_debug "Failed to collect from $ip"
            ((failed++))
        fi
    done
    
    hw_profiles+=']}'
    
    log INFO "Collected hardware profiles: $collected successful, $failed failed"
    
    echo "$hw_profiles"
    return 0
}

# ============================================================================
# RESULT PROCESSING
# ============================================================================

validate_hardware_profile() {
    # Validate a single hardware profile has required fields
    #
    # Arguments:
    #   $1 - JSON hardware profile
    #
    # Returns:
    #   0 if valid
    #   1 if invalid
    
    local profile="$1"
    
    # Check each required field
    for field in "${REQUIRED_HW_FIELDS[@]}"; do
        local value=$(echo "$profile" | jq -r ".$field" 2>/dev/null)
        
        if [[ -z "$value" ]] || [[ "$value" == "null" ]]; then
            log_debug "Missing required field: $field"
            return 1
        fi
    done
    
    return 0
}

aggregate_profiles() {
    # Combine all profiles into hw_profiles.json
    #
    # Arguments:
    #   $1 - JSON string with all profiles
    #   $2 - Output file path
    #
    # Returns:
    #   0 on success
    #   1 on failure
    
    local profiles_json="$1"
    local output_file="$2"
    
    log STEP "Saving hardware profiles to: $output_file"
    
    # Validate it's valid JSON
    if ! echo "$profiles_json" | jq empty 2>/dev/null; then
        log ERROR "Invalid JSON in aggregated profiles"
        return 1
    fi
    
    # Pretty-print and save
    echo "$profiles_json" | jq '.' > "$output_file" 2>/dev/null
    
    if [[ $? -ne 0 ]]; then
        log ERROR "Failed to write hardware profiles file"
        return 1
    fi
    
    # Validate saved file
    if ! json_validate "$output_file"; then
        log ERROR "Saved file is not valid JSON"
        return 1
    fi
    
    log SUCCESS "Hardware profiles saved"
    return 0
}

display_hardware_summary() {
    # Display summary of collected hardware
    #
    # Arguments:
    #   $1 - hw_profiles.json file path
    #
    # Returns:
    #   0 always
    
    local hw_file="$1"
    
    if [[ ! -f "$hw_file" ]]; then
        return 1
    fi
    
    log INFO "Hardware summary:"
    
    # Count by device type
    local pi_count=$(jq '[.devices[] | select(.device_type == "raspberry_pi")] | length' "$hw_file" 2>/dev/null)
    local llm_count=$(jq '[.devices[] | select(.device_type == "llm_computer")] | length' "$hw_file" 2>/dev/null)
    local host_count=$(jq '[.devices[] | select(.device_type == "host_computer")] | length' "$hw_file" 2>/dev/null)
    
    log INFO "  • Raspberry Pis: $pi_count"
    log INFO "  • LLM Computers: $llm_count"
    log INFO "  • Host Computers: $host_count"
    
    # Total RAM
    local total_ram=$(jq '[.devices[].ram_gb] | add' "$hw_file" 2>/dev/null)
    log INFO "  • Total RAM: ${total_ram}GB"
    
    # Total storage
    local total_storage=$(jq '[.devices[].storage_size_gb] | add' "$hw_file" 2>/dev/null)
    log INFO "  • Total Storage: ${total_storage}GB"
    
    return 0
}

# ============================================================================
# ORCHESTRATION
# ============================================================================

run_hardware_detection() {
    # Main function - complete hardware detection flow
    #
    # Arguments:
    #   $1 - Input file (discovered_devices.json)
    #   $2 - Output file (hw_profiles.json)
    #
    # Returns:
    #   0 on success
    #   1 on failure
    #
    # Example:
    #   run_hardware_detection \
    #       "$DATA_DIR/discovered_devices.json" \
    #       "$DATA_DIR/hw_profiles.json" || exit 1
    
    local input_file="$1"
    local output_file="$2"
    
    print_header "Hardware Detection"
    
    # Validate arguments
    if [[ -z "$input_file" ]] || [[ -z "$output_file" ]]; then
        log ERROR "Usage: run_hardware_detection <input_file> <output_file>"
        return 1
    fi
    
    # Initialize parallel module
    parallel_init || {
        log ERROR "Failed to initialize parallel execution"
        return 1
    }
    
    # Load discovered devices
    load_discovered_devices "$input_file" || return 1
    
    # Build device array
    declare -a devices
    build_device_array devices || return 1
    
    log STEP "Collecting hardware profiles from ${#devices[@]} device(s)..."
    echo ""
    
    # Transfer detection script
    transfer_detection_script devices || return 1
    
    echo ""
    
    # Execute detection
    execute_hardware_detection devices || true
    
    # Collect results
    local hw_profiles=$(collect_hardware_results devices)
    
    # Aggregate and save
    aggregate_profiles "$hw_profiles" "$output_file" || return 1
    
    echo ""
    
    # Display summary
    display_hardware_summary "$output_file"
    
    echo ""
    log SUCCESS "Hardware detection complete"
    echo ""
    
    return 0
}

# ============================================================================
# INITIALIZATION
# ============================================================================

log_debug "AEON hardware detection module loaded"

# Export functions
export -f load_discovered_devices build_device_array 2>/dev/null || true
export -f transfer_detection_script execute_hardware_detection 2>/dev/null || true
export -f collect_hardware_result collect_hardware_results 2>/dev/null || true
export -f validate_hardware_profile aggregate_profiles 2>/dev/null || true
export -f display_hardware_summary 2>/dev/null || true
export -f run_hardware_detection 2>/dev/null || true

return 0
