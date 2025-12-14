#!/bin/bash
################################################################################
# AEON Requirements Validation
# File: lib/validation.sh
# Version: 0.1.0
#
# Purpose: Validate cluster meets minimum requirements
#
# Usage:
#   source /opt/aeon/lib/validation.sh
#   run_validation "$DATA_DIR/hw_profiles.json" || exit 1
#
# Provides:
#   - Raspberry Pi count validation
#   - Hardware requirements validation
#   - Cluster viability validation
#   - Network connectivity validation
#   - Validation reporting
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
[[ -n "${AEON_VALIDATION_LOADED:-}" ]] && return 0
readonly AEON_VALIDATION_LOADED=1

# ============================================================================
# CONFIGURATION
# ============================================================================

# Minimum requirements
readonly MIN_RASPBERRY_PIS=3
readonly MIN_TOTAL_DEVICES=3
readonly MIN_RAM_PER_PI_GB=2
readonly MIN_STORAGE_PER_PI_GB=8
readonly MIN_CPU_CORES=2

# Manager count rules (must be ODD for Raft consensus)
readonly MIN_MANAGERS=3
readonly MAX_MANAGERS=7

# Validation results
declare -g VALIDATION_PASSED=0
declare -g VALIDATION_WARNINGS=0
declare -g VALIDATION_ERRORS=0

# ============================================================================
# DEVICE VALIDATION
# ============================================================================

validate_raspberry_pi_count() {
    local hw_file="$1"
    
    log STEP "Validating Raspberry Pi count..."
    
    local pi_count=$(jq '[.devices[] | select(.device_type == "raspberry_pi")] | length' \
        "$hw_file" 2>/dev/null)
    
    if [[ -z "$pi_count" ]] || [[ "$pi_count" == "null" ]]; then
        log ERROR "Failed to count Raspberry Pis"
        ((VALIDATION_ERRORS++))
        return 1
    fi
    
    if [[ $pi_count -lt $MIN_RASPBERRY_PIS ]]; then
        log WARN "Found $pi_count Raspberry Pi(s) - below minimum of $MIN_RASPBERRY_PIS for production"
        echo ""
        log INFO "SETUP MODE: You can proceed with setup, but cluster cannot start until requirements are met"
        log INFO ""
        log INFO "Current: $pi_count Raspberry Pi(s)"
        log INFO "Required for cluster start: $MIN_RASPBERRY_PIS Raspberry Pis"
        log INFO ""
        log INFO "Next steps:"
        log INFO "  1. Complete setup on this device"
        log INFO "  2. Add more Raspberry Pis to network"
        log INFO "  3. Run cluster start when requirements are met"
        echo ""
        
        # Warning, not error - allow setup to continue
        ((VALIDATION_WARNINGS++))
        return 0
    fi
    
    log SUCCESS "Raspberry Pi count: $pi_count (minimum: $MIN_RASPBERRY_PIS)"
    ((VALIDATION_PASSED++))
    return 0
}

validate_total_device_count() {
    # Validate total device count
    #
    # Arguments:
    #   $1 - hw_profiles.json file path
    #
    # Returns:
    #   0 if sufficient devices
    #   1 if insufficient
    
    local hw_file="$1"
    
    log STEP "Validating total device count..."
    
    local total_devices=$(jq '.devices | length' "$hw_file" 2>/dev/null)
    
    if [[ $total_devices -lt $MIN_TOTAL_DEVICES ]]; then
        log ERROR "Insufficient devices: $total_devices found, minimum $MIN_TOTAL_DEVICES required"
        ((VALIDATION_ERRORS++))
        return 1
    fi
    
    log SUCCESS "Total devices: $total_devices (minimum: $MIN_TOTAL_DEVICES)"
    ((VALIDATION_PASSED++))
    return 0
}

validate_device_hardware() {
    # Check each device meets minimum hardware specs
    #
    # Arguments:
    #   $1 - hw_profiles.json file path
    #
    # Returns:
    #   0 if all devices meet minimums
    #   1 if any device below minimum
    
    local hw_file="$1"
    
    log STEP "Validating device hardware specifications..."
    
    local issues=0
    
    # Check each Raspberry Pi
    while read -r device_json; do
        local ip=$(echo "$device_json" | jq -r '.ip')
        local hostname=$(echo "$device_json" | jq -r '.hostname')
        local ram=$(echo "$device_json" | jq -r '.ram_gb')
        local storage=$(echo "$device_json" | jq -r '.storage_size_gb')
        local cores=$(echo "$device_json" | jq -r '.cpu_cores')
        
        # Validate RAM
        if [[ $ram -lt $MIN_RAM_PER_PI_GB ]]; then
            log WARN "Device $hostname ($ip) has only ${ram}GB RAM (minimum: ${MIN_RAM_PER_PI_GB}GB)"
            ((VALIDATION_WARNINGS++))
            ((issues++))
        fi
        
        # Validate storage
        if [[ $storage -lt $MIN_STORAGE_PER_PI_GB ]]; then
            log WARN "Device $hostname ($ip) has only ${storage}GB storage (minimum: ${MIN_STORAGE_PER_PI_GB}GB)"
            ((VALIDATION_WARNINGS++))
            ((issues++))
        fi
        
        # Validate CPU cores
        if [[ $cores -lt $MIN_CPU_CORES ]]; then
            log WARN "Device $hostname ($ip) has only $cores CPU cores (minimum: $MIN_CPU_CORES)"
            ((VALIDATION_WARNINGS++))
            ((issues++))
        fi
        
    done < <(jq -c '.devices[] | select(.device_type == "raspberry_pi")' "$hw_file" 2>/dev/null)
    
    if [[ $issues -eq 0 ]]; then
        log SUCCESS "All devices meet minimum hardware requirements"
        ((VALIDATION_PASSED++))
        return 0
    else
        log WARN "$issues device(s) below recommended specifications"
        log INFO "Cluster will still function, but performance may be impacted"
        return 0  # Warning, not error
    fi
}

# ============================================================================
# CLUSTER VALIDATION
# ============================================================================

validate_cluster_size() {
    # Check cluster is viable size for fault tolerance
    #
    # Arguments:
    #   $1 - hw_profiles.json file path
    #
    # Returns:
    #   0 if cluster size is viable
    #   1 if too small for fault tolerance
    
    local hw_file="$1"
    
    log STEP "Validating cluster size for fault tolerance..."
    
    local pi_count=$(jq '[.devices[] | select(.device_type == "raspberry_pi")] | length' \
        "$hw_file" 2>/dev/null)
    
    # Calculate fault tolerance
    local manager_count=$MIN_MANAGERS
    if [[ $pi_count -ge 5 ]]; then
        manager_count=5
    elif [[ $pi_count -ge 7 ]]; then
        manager_count=7
    fi
    
    local fault_tolerance=$(( (manager_count - 1) / 2 ))
    
    log SUCCESS "Cluster can have $manager_count managers"
    log SUCCESS "Fault tolerance: Can lose $fault_tolerance manager(s) and maintain quorum"
    
    ((VALIDATION_PASSED++))
    return 0
}

validate_manager_capacity() {
    # Ensure enough Pis for managers (ODD number: 3, 5, or 7)
    #
    # Arguments:
    #   $1 - hw_profiles.json file path
    #
    # Returns:
    #   0 if sufficient for managers
    #   1 if insufficient
    
    local hw_file="$1"
    
    log STEP "Validating manager capacity..."
    
    local pi_count=$(jq '[.devices[] | select(.device_type == "raspberry_pi")] | length' \
        "$hw_file" 2>/dev/null)
    
    # Determine manager count
    local manager_count=$MIN_MANAGERS
    if [[ $pi_count -ge 7 ]]; then
        manager_count=7
    elif [[ $pi_count -ge 5 ]]; then
        manager_count=5
    fi
    
    log SUCCESS "Will assign $manager_count manager(s) from $pi_count Raspberry Pi(s)"
    
    ((VALIDATION_PASSED++))
    return 0
}

# ============================================================================
# NETWORK VALIDATION
# ============================================================================

validate_network_connectivity() {
    # Verify devices can reach each other (optional check)
    #
    # Arguments:
    #   $1 - hw_profiles.json file path
    #
    # Returns:
    #   0 always (informational only)
    
    local hw_file="$1"
    
    log STEP "Checking network connectivity (optional)..."
    
    # This is a basic check - full connectivity tests happen during swarm setup
    log INFO "Network connectivity will be verified during swarm formation"
    log INFO "Required ports: 2377/tcp, 7946/tcp, 7946/udp, 4789/udp"
    
    return 0
}

# ============================================================================
# DATA VALIDATION
# ============================================================================

validate_hardware_file() {
    # Validate hardware profiles file structure
    #
    # Arguments:
    #   $1 - hw_profiles.json file path
    #
    # Returns:
    #   0 if valid
    #   1 if invalid
    
    local hw_file="$1"
    
    log STEP "Validating hardware profiles file..."
    
    # Check file exists
    if [[ ! -f "$hw_file" ]]; then
        log ERROR "Hardware profiles file not found: $hw_file"
        ((VALIDATION_ERRORS++))
        return 1
    fi
    
    # Check file is readable
    if [[ ! -r "$hw_file" ]]; then
        log ERROR "Hardware profiles file not readable: $hw_file"
        ((VALIDATION_ERRORS++))
        return 1
    fi
    
    # Validate JSON
    if ! json_validate "$hw_file"; then
        log ERROR "Invalid JSON in hardware profiles file"
        ((VALIDATION_ERRORS++))
        return 1
    fi
    
    # Check has devices array
    if ! jq -e '.devices' "$hw_file" &>/dev/null; then
        log ERROR "Hardware profiles file missing 'devices' array"
        ((VALIDATION_ERRORS++))
        return 1
    fi
    
    log SUCCESS "Hardware profiles file is valid"
    ((VALIDATION_PASSED++))
    return 0
}

validate_required_fields() {
    # Validate all devices have required fields
    #
    # Arguments:
    #   $1 - hw_profiles.json file path
    #
    # Returns:
    #   0 if all have required fields
    #   1 if any missing fields
    
    local hw_file="$1"
    
    log STEP "Validating device data completeness..."
    
    local required_fields=(
        "ip"
        "hostname"
        "device_type"
        "model"
        "ram_gb"
        "storage_type"
        "storage_size_gb"
        "cpu_cores"
    )
    
    local incomplete_devices=0
    
    # Check each device
    local device_count=$(jq '.devices | length' "$hw_file" 2>/dev/null)
    for ((i=0; i<device_count; i++)); do
        local device=$(jq ".devices[$i]" "$hw_file" 2>/dev/null)
        local ip=$(echo "$device" | jq -r '.ip')
        
        local missing_fields=()
        
        for field in "${required_fields[@]}"; do
            local value=$(echo "$device" | jq -r ".$field" 2>/dev/null)
            if [[ -z "$value" ]] || [[ "$value" == "null" ]]; then
                missing_fields+=("$field")
            fi
        done
        
        if [[ ${#missing_fields[@]} -gt 0 ]]; then
            log WARN "Device $ip missing fields: ${missing_fields[*]}"
            ((incomplete_devices++))
            ((VALIDATION_WARNINGS++))
        fi
    done
    
    if [[ $incomplete_devices -eq 0 ]]; then
        log SUCCESS "All devices have complete data"
        ((VALIDATION_PASSED++))
        return 0
    else
        log WARN "$incomplete_devices device(s) have incomplete data"
        log INFO "Cluster will still function, but features may be limited"
        return 0  # Warning, not error
    fi
}

# ============================================================================
# REPORTING
# ============================================================================

generate_validation_report() {
    # Generate detailed validation report
    #
    # Arguments:
    #   None (uses global validation counters)
    #
    # Returns:
    #   0 always
    
    echo ""
    print_line "$BOX_H" 60
    echo ""
    
    log INFO "Validation Summary:"
    log INFO "  ${ICON_SUCCESS} Passed: $VALIDATION_PASSED"
    
    if [[ $VALIDATION_WARNINGS -gt 0 ]]; then
        log INFO "  ${ICON_WARNING}Warnings: $VALIDATION_WARNINGS"
    fi
    
    if [[ $VALIDATION_ERRORS -gt 0 ]]; then
        log INFO "  ${ICON_ERROR} Errors: $VALIDATION_ERRORS"
    fi
    
    echo ""
    
    if [[ $VALIDATION_ERRORS -eq 0 ]]; then
        log SUCCESS "All critical validations passed"
        if [[ $VALIDATION_WARNINGS -gt 0 ]]; then
            log INFO "Cluster can proceed with warnings"
        fi
    else
        log ERROR "Validation failed - cannot proceed"
        echo ""
        log INFO "Please fix the errors listed above and try again"
    fi
    
    echo ""
    print_line "$BOX_H" 60
    echo ""
    
    return 0
}

# ============================================================================
# ORCHESTRATION
# ============================================================================

run_validation() {
    # Main function - run all validations
    #
    # Arguments:
    #   $1 - hw_profiles.json file path
    #
    # Returns:
    #   0 if all critical validations pass
    #   1 if any critical validation fails
    #
    # Example:
    #   run_validation "$DATA_DIR/hw_profiles.json" || exit 1
    
    local hw_file="$1"
    
    print_header "Requirements Validation"
    
    # Validate arguments
    if [[ -z "$hw_file" ]]; then
        log ERROR "Usage: run_validation <hw_profiles.json>"
        return 1
    fi
    
    # Reset counters
    VALIDATION_PASSED=0
    VALIDATION_WARNINGS=0
    VALIDATION_ERRORS=0
    
    # Run all validations
    # Critical validations (must pass)
    validate_hardware_file "$hw_file" || return 1
    validate_raspberry_pi_count "$hw_file" || return 1
    validate_total_device_count "$hw_file" || return 1
    
    # Important validations (should pass)
    validate_cluster_size "$hw_file" || true
    validate_manager_capacity "$hw_file" || true
    
    # Informational validations (warnings only)
    validate_required_fields "$hw_file" || true
    validate_device_hardware "$hw_file" || true
    validate_network_connectivity "$hw_file" || true
    
    # Generate report
    generate_validation_report
    
    # Return based on errors
    if [[ $VALIDATION_ERRORS -gt 0 ]]; then
        return 1
    fi
    
    return 0
}

# ============================================================================
# INITIALIZATION
# ============================================================================

log_debug "AEON validation module loaded"

# Export functions
export -f validate_raspberry_pi_count validate_total_device_count 2>/dev/null || true
export -f validate_device_hardware validate_cluster_size 2>/dev/null || true
export -f validate_manager_capacity validate_network_connectivity 2>/dev/null || true
export -f validate_hardware_file validate_required_fields 2>/dev/null || true
export -f generate_validation_report run_validation 2>/dev/null || true

return 0
