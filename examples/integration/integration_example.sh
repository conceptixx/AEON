#!/bin/bash
################################################################################
# AEON Integration Example
# File: integration_example.sh
# Version: 0.1.0
#
# Purpose: Demonstrate how aeon-go.sh uses parallel.sh and 
#          install_dependencies.sh together
#
# This shows the complete workflow for installing dependencies on all devices
################################################################################

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

AEON_DIR="/opt/aeon"
DATA_DIR="$AEON_DIR/data"
LIB_DIR="$AEON_DIR/lib"
REMOTE_DIR="$AEON_DIR/remote"

# ============================================================================
# INTEGRATION WORKFLOW
# ============================================================================

main() {
    echo "═══════════════════════════════════════════════════════════"
    echo "  AEON Dependency Installation (Parallel)"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    
    # ========================================================================
    # STEP 1: Initialize Parallel Execution
    # ========================================================================
    
    echo "Step 1: Initializing parallel execution..."
    
    source "$LIB_DIR/parallel.sh"
    parallel_init || {
        echo "ERROR: Failed to initialize parallel execution"
        exit 1
    }
    
    echo ""
    
    # ========================================================================
    # STEP 2: Load Discovered Devices
    # ========================================================================
    
    echo "Step 2: Loading discovered devices..."
    
    # Read password from secure storage
    CLUSTER_PASSWORD=$(cat "$AEON_DIR/secrets/.cluster_password")
    
    # Load devices from discovery phase
    # Format: ip:user:password
    devices=()
    
    # Parse discovered_devices.json and build array
    # This is a simplified example - real implementation would use jq properly
    
    # Example devices (would be dynamically loaded in real implementation)
    devices=(
        "192.168.1.100:pi:$CLUSTER_PASSWORD"
        "192.168.1.101:pi:$CLUSTER_PASSWORD"
        "192.168.1.102:pi:$CLUSTER_PASSWORD"
        "192.168.1.103:aeon-llm:$CLUSTER_PASSWORD"
    )
    
    echo "  Loaded ${#devices[@]} device(s)"
    echo ""
    
    # ========================================================================
    # STEP 3: Transfer Installation Script to All Devices
    # ========================================================================
    
    echo "Step 3: Transferring installation script to all devices..."
    echo ""
    
    parallel_file_transfer devices[@] \
        "$REMOTE_DIR/install_dependencies.sh" \
        "/tmp/install_dependencies.sh"
    
    echo ""
    
    # ========================================================================
    # STEP 4: Execute Installation on All Devices (PARALLEL!)
    # ========================================================================
    
    echo "Step 4: Installing dependencies on all devices..."
    echo ""
    
    parallel_exec devices[@] \
        "bash /tmp/install_dependencies.sh" \
        "Installing AEON dependencies"
    
    echo ""
    
    # ========================================================================
    # STEP 5: Collect and Analyze Results
    # ========================================================================
    
    echo "Step 5: Analyzing installation results..."
    echo ""
    
    results=$(parallel_collect_results)
    
    # Extract key metrics
    total=$(echo "$results" | jq -r '.total_devices')
    successful=$(echo "$results" | jq -r '.successful')
    failed=$(echo "$results" | jq -r '.failed')
    success_rate=$(echo "$results" | jq -r '.success_rate')
    
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  Installation Results"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "  Total devices: $total"
    echo "  Successful: $successful"
    echo "  Failed: $failed"
    echo "  Success rate: ${success_rate}%"
    echo ""
    
    # ========================================================================
    # STEP 6: Check for Devices Requiring Reboot
    # ========================================================================
    
    echo "Step 6: Checking for reboot requirements..."
    echo ""
    
    # Find devices that need reboot
    devices_needing_reboot=$(echo "$results" | jq -r '.devices[] | select(.output | contains("REBOOT_REQUIRED")) | .ip')
    
    if [[ -n "$devices_needing_reboot" ]]; then
        echo "⚠️  The following devices require reboot:"
        echo "$devices_needing_reboot" | while read ip; do
            echo "  • $ip"
        done
        echo ""
        echo "Next step: Synchronized reboot will be initiated"
        echo ""
    else
        echo "✅ No devices require reboot"
        echo ""
    fi
    
    # ========================================================================
    # STEP 7: Validate Success Rate
    # ========================================================================
    
    echo "Step 7: Validating success rate..."
    echo ""
    
    # Check if success rate meets minimum requirement (95%)
    if (( $(echo "$success_rate >= 95" | bc -l) )); then
        echo "✅ SUCCESS: Installation successful (${success_rate}%)"
        echo ""
        echo "All devices are ready for AEON cluster participation!"
        echo ""
        
        # Save successful result
        echo "$results" > "$DATA_DIR/installation_results.json"
        
        # Cleanup
        parallel_cleanup
        
        exit 0
    else
        echo "❌ FAILURE: Success rate below 95% (${success_rate}%)"
        echo ""
        echo "Review failed devices:"
        echo ""
        
        # Show failed devices
        echo "$results" | jq -r '.devices[] | select(.status == "failed") | "  • \(.ip): \(.error)"'
        
        echo ""
        echo "Options:"
        echo "  1. Review logs: /opt/aeon/logs/parallel_*/"
        echo "  2. Retry failed devices"
        echo "  3. Continue anyway (not recommended)"
        echo ""
        
        # Cleanup
        parallel_cleanup
        
        exit 1
    fi
}

# ============================================================================
# EXAMPLE: Retry Failed Devices
# ============================================================================

retry_failed_devices() {
    echo "═══════════════════════════════════════════════════════════"
    echo "  Retrying Failed Devices"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    
    # Reinitialize
    source "$LIB_DIR/parallel.sh"
    parallel_init
    
    # Get previous results
    local previous_results=$(cat "$DATA_DIR/installation_results.json" 2>/dev/null || echo "{}")
    
    # Extract failed device IPs
    local failed_ips=$(echo "$previous_results" | jq -r '.devices[] | select(.status == "failed") | .ip')
    
    if [[ -z "$failed_ips" ]]; then
        echo "No failed devices to retry"
        return 0
    fi
    
    # Reconstruct device array for failed devices only
    local CLUSTER_PASSWORD=$(cat "$AEON_DIR/secrets/.cluster_password")
    local failed_devices=()
    
    # This would need to lookup user from discovered_devices.json
    # Simplified example:
    for ip in $failed_ips; do
        # Determine user based on IP or previous data
        local user="pi"  # Would be dynamically determined
        failed_devices+=("${ip}:${user}:${CLUSTER_PASSWORD}")
    done
    
    echo "Retrying installation on ${#failed_devices[@]} device(s)..."
    echo ""
    
    # Retry installation
    parallel_exec failed_devices[@] \
        "bash /tmp/install_dependencies.sh" \
        "Retrying installation on failed devices"
    
    # Collect results
    local retry_results=$(parallel_collect_results)
    
    # Show results
    echo ""
    echo "Retry Results:"
    echo "$retry_results" | jq '.'
    
    parallel_cleanup
}

# ============================================================================
# EXAMPLE: Staged Installation (Managers First, Then Workers)
# ============================================================================

staged_installation() {
    echo "═══════════════════════════════════════════════════════════"
    echo "  Staged Installation (Managers → Workers)"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    
    source "$LIB_DIR/parallel.sh"
    parallel_init
    
    # Load role assignments
    local role_assignments=$(cat "$DATA_DIR/role_assignments.json")
    
    # Extract managers
    local manager_ips=$(echo "$role_assignments" | jq -r '.assignments[] | select(.role == "manager") | .device.ip')
    
    # Extract workers
    local worker_ips=$(echo "$role_assignments" | jq -r '.assignments[] | select(.role == "worker") | .device.ip')
    
    local CLUSTER_PASSWORD=$(cat "$AEON_DIR/secrets/.cluster_password")
    
    # Build manager devices array
    local managers=()
    for ip in $manager_ips; do
        managers+=("${ip}:pi:${CLUSTER_PASSWORD}")
    done
    
    # Build worker devices array
    local workers=()
    for ip in $worker_ips; do
        # Would determine correct user (pi, aeon-llm, aeon-host)
        local user="pi"
        workers+=("${ip}:${user}:${CLUSTER_PASSWORD}")
    done
    
    # ========================================================================
    # Stage 1: Install on Managers
    # ========================================================================
    
    echo "Stage 1: Installing on ${#managers[@]} manager(s)..."
    echo ""
    
    parallel_file_transfer managers[@] \
        "$REMOTE_DIR/install_dependencies.sh" \
        "/tmp/install_dependencies.sh"
    
    parallel_exec managers[@] \
        "bash /tmp/install_dependencies.sh --role manager" \
        "Installing dependencies on managers"
    
    local manager_results=$(parallel_collect_results)
    local manager_success=$(echo "$manager_results" | jq -r '.success_rate')
    
    echo ""
    echo "Manager installation: ${manager_success}% success"
    echo ""
    
    # Only proceed if managers are successful
    if (( $(echo "$manager_success >= 95" | bc -l) )); then
        echo "✅ Managers ready, proceeding to workers..."
        echo ""
    else
        echo "❌ Manager installation failed, aborting"
        parallel_cleanup
        exit 1
    fi
    
    # ========================================================================
    # Stage 2: Install on Workers
    # ========================================================================
    
    echo "Stage 2: Installing on ${#workers[@]} worker(s)..."
    echo ""
    
    parallel_file_transfer workers[@] \
        "$REMOTE_DIR/install_dependencies.sh" \
        "/tmp/install_dependencies.sh"
    
    parallel_exec workers[@] \
        "bash /tmp/install_dependencies.sh --role worker" \
        "Installing dependencies on workers"
    
    local worker_results=$(parallel_collect_results)
    local worker_success=$(echo "$worker_results" | jq -r '.success_rate')
    
    echo ""
    echo "Worker installation: ${worker_success}% success"
    echo ""
    
    # ========================================================================
    # Overall Results
    # ========================================================================
    
    echo "═══════════════════════════════════════════════════════════"
    echo "  Staged Installation Complete"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "  Managers: ${manager_success}%"
    echo "  Workers: ${worker_success}%"
    echo ""
    
    parallel_cleanup
}

# ============================================================================
# EXECUTE
# ============================================================================

# Check if running in real environment
if [[ -d "$AEON_DIR" ]] && [[ -f "$LIB_DIR/parallel.sh" ]]; then
    echo "Running in AEON environment"
    main "$@"
else
    echo "This is an example integration script."
    echo "It demonstrates how aeon-go.sh uses parallel.sh and install_dependencies.sh"
    echo ""
    echo "To actually run this, ensure:"
    echo "  1. /opt/aeon/ directory exists"
    echo "  2. parallel.sh is in /opt/aeon/lib/"
    echo "  3. install_dependencies.sh is in /opt/aeon/remote/"
    echo "  4. Discovery phase has completed"
    echo ""
    exit 0
fi
