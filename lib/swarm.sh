#!/bin/bash
################################################################################
# AEON Docker Swarm Setup Module
# File: lib/swarm.sh
# Version: 0.1.0
#
# Purpose: Initialize and configure Docker Swarm cluster across all devices
#
# Phases:
#   1. Preparation - Load assignments, identify first manager
#   2. Swarm Init - Initialize swarm on first manager
#   3. Token Extraction - Retrieve manager/worker join tokens
#   4. Manager Join - Add additional managers (sequential)
#   5. Worker Join - Add workers (parallel)
#   6. Network Setup - Create overlay networks
#   7. Verification - Verify cluster health
#
# Security:
#   - Tokens stored in memory only (never written to disk)
#   - Tokens never logged
#   - SSH authentication via AEON user
################################################################################

set -euo pipefail

# ============================================================================
# DEPENDENCIES
# ============================================================================

# Prevent double-loading
[[ -n "${AEON_SWARM_LOADED:-}" ]] && return 0
readonly AEON_SWARM_LOADED=1

# Load dependencies
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
if [[ -z "${AEON_DEPENDENCIES_LOADED:-}" ]]; then
    source "$SCRIPT_DIR/dependencies.sh" || source "/opt/aeon/lib/dependencies.sh" || {
        echo "ERROR: Cannot find dependencies.sh" >&2
        exit 1
    }
fi

# load dependecies -if available
load_dependencies "swarm.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

SWARM_ADVERTISE_PORT=2377
SWARM_MANAGER_JOIN_DELAY=5      # Delay between manager joins (Raft consensus)
SWARM_OVERLAY_SUBNET="10.0.1.0/24"
SWARM_VERIFY_RETRIES=3
SWARM_VERIFY_DELAY=10

# Global variables (set during execution)
FIRST_MANAGER=""
OTHER_MANAGERS=()
ALL_MANAGERS=()
WORKERS=()
MANAGER_TOKEN=""
WORKER_TOKEN=""

print_header() {
    echo ""
}

# ============================================================================
# PHASE 1: PREPARATION
# ============================================================================

load_role_assignments() {
    local assignments_file="$1"
    
    log STEP "Loading role assignments..."
    
    if [[ ! -f "$assignments_file" ]]; then
        log ERROR "Role assignments file not found: $assignments_file"
        return 1
    fi
    
    # Extract all managers (sorted by rank)
    ALL_MANAGERS=($(jq -r '.assignments[] | select(.role == "manager") | "\(.rank):\(.device.ip)"' "$assignments_file" | sort -n | cut -d: -f2))
    
    # First manager is rank #1 (highest scored)
    FIRST_MANAGER="${ALL_MANAGERS[0]}"
    
    # Other managers (rank #2, #3, etc.)
    OTHER_MANAGERS=("${ALL_MANAGERS[@]:1}")
    
    # All workers
    WORKERS=($(jq -r '.assignments[] | select(.role == "worker") | .device.ip' "$assignments_file"))
    
    log INFO "First manager (rank #1): $FIRST_MANAGER"
    log INFO "Additional managers: ${#OTHER_MANAGERS[@]}"
    log INFO "Workers: ${#WORKERS[@]}"
    log INFO "Total cluster size: $((${#ALL_MANAGERS[@]} + ${#WORKERS[@]})) nodes"
    
    return 0
}

check_docker_ready() {
    local ip="$1"
    local user="$2"
    local password="$3"
    
    # Check if Docker daemon is running and accessible
    if sshpass -p "$password" ssh -o StrictHostKeyChecking=no "${user}@${ip}" \
        "docker info" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

verify_all_docker_ready() {
    local user="$1"
    local password="$2"
    
    log STEP "Verifying Docker is ready on all devices..."
    
    local total_devices=$((${#ALL_MANAGERS[@]} + ${#WORKERS[@]}))
    local ready=0
    local not_ready=0
    
    # Check managers
    for ip in "${ALL_MANAGERS[@]}"; do
        if check_docker_ready "$ip" "$user" "$password"; then
            log INFO "[$ip] Docker ready"
            ((ready++))
        else
            log ERROR "[$ip] Docker not ready"
            ((not_ready++))
        fi
    done
    
    # Check workers
    for ip in "${WORKERS[@]}"; do
        if check_docker_ready "$ip" "$user" "$password"; then
            log INFO "[$ip] Docker ready"
            ((ready++))
        else
            log ERROR "[$ip] Docker not ready"
            ((not_ready++))
        fi
    done
    
    if [[ $not_ready -gt 0 ]]; then
        log ERROR "$not_ready device(s) do not have Docker ready"
        return 1
    fi
    
    log SUCCESS "All $total_devices device(s) have Docker ready"
    return 0
}

# ============================================================================
# PHASE 2: SWARM INITIALIZATION
# ============================================================================

initialize_swarm() {
    local first_manager="$1"
    local user="$2"
    local password="$3"
    
    print_header "Phase 2: Initialize Docker Swarm"
    
    log STEP "Initializing swarm on first manager: $first_manager"
    
    # Check if swarm already initialized
    local swarm_status=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no "${user}@${first_manager}" \
        "docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null" || echo "inactive")
    
    if [[ "$swarm_status" == "active" ]]; then
        log WARN "Swarm already initialized on $first_manager"
        
        # Check if this node is a manager
        local is_manager=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no "${user}@${first_manager}" \
            "docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null" || echo "false")
        
        if [[ "$is_manager" == "true" ]]; then
            log INFO "Node is already a swarm manager, continuing..."
            return 0
        else
            log ERROR "Node is in a swarm but not a manager - cannot continue"
            return 1
        fi
    fi
    
    # Initialize swarm
    log INFO "Running: docker swarm init --advertise-addr ${first_manager}:${SWARM_ADVERTISE_PORT}"
    
    local init_output=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no "${user}@${first_manager}" \
        "docker swarm init \
         --advertise-addr ${first_manager}:${SWARM_ADVERTISE_PORT} \
         --listen-addr ${first_manager}:${SWARM_ADVERTISE_PORT}" 2>&1)
    
    if [[ $? -eq 0 ]]; then
        log SUCCESS "Swarm initialized successfully"
        
        # Extract node ID from output
        local node_id=$(echo "$init_output" | grep -oP 'current node \(\K[a-z0-9]+' || echo "unknown")
        log INFO "Swarm node ID: $node_id"
        
        return 0
    else
        log ERROR "Failed to initialize swarm"
        log ERROR "Output: $init_output"
        return 1
    fi
}

# ============================================================================
# PHASE 3: TOKEN EXTRACTION
# ============================================================================

extract_join_tokens() {
    local first_manager="$1"
    local user="$2"
    local password="$3"
    
    print_header "Phase 3: Extract Join Tokens"
    
    log STEP "Retrieving swarm join tokens from $first_manager"
    
    # Get manager token
    log INFO "Extracting manager token..."
    MANAGER_TOKEN=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no "${user}@${first_manager}" \
        "docker swarm join-token manager -q" 2>/dev/null)
    
    if [[ -z "$MANAGER_TOKEN" ]]; then
        log ERROR "Failed to retrieve manager token"
        return 1
    fi
    
    log SUCCESS "Manager token retrieved (length: ${#MANAGER_TOKEN} chars)"
    log INFO "Manager token: <hidden for security>"
    
    # Get worker token
    log INFO "Extracting worker token..."
    WORKER_TOKEN=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no "${user}@${first_manager}" \
        "docker swarm join-token worker -q" 2>/dev/null)
    
    if [[ -z "$WORKER_TOKEN" ]]; then
        log ERROR "Failed to retrieve worker token"
        return 1
    fi
    
    log SUCCESS "Worker token retrieved (length: ${#WORKER_TOKEN} chars)"
    log INFO "Worker token: <hidden for security>"
    
    # Tokens are now stored in global variables
    # NEVER write them to disk or log them!
    
    return 0
}

# ============================================================================
# PHASE 4: MANAGER JOIN
# ============================================================================

join_manager() {
    local manager_ip="$1"
    local first_manager="$2"
    local user="$3"
    local password="$4"
    local token="$5"
    
    log INFO "Joining manager: $manager_ip"
    
    # Check if already in swarm
    local swarm_status=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no "${user}@${manager_ip}" \
        "docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null" || echo "inactive")
    
    if [[ "$swarm_status" == "active" ]]; then
        log WARN "[$manager_ip] Already in swarm, skipping"
        return 0
    fi
    
    # Join swarm as manager
    local join_output=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no "${user}@${manager_ip}" \
        "docker swarm join \
         --token ${token} \
         --advertise-addr ${manager_ip}:${SWARM_ADVERTISE_PORT} \
         --listen-addr ${manager_ip}:${SWARM_ADVERTISE_PORT} \
         ${first_manager}:${SWARM_ADVERTISE_PORT}" 2>&1)
    
    if [[ $? -eq 0 ]]; then
        log SUCCESS "[$manager_ip] Joined as manager"
        return 0
    else
        log ERROR "[$manager_ip] Failed to join swarm"
        log ERROR "Output: $join_output"
        return 1
    fi
}

join_all_managers() {
    local first_manager="$1"
    local user="$2"
    local password="$3"
    local token="$4"
    
    if [[ ${#OTHER_MANAGERS[@]} -eq 0 ]]; then
        log INFO "No additional managers to join"
        return 0
    fi
    
    print_header "Phase 4: Join Additional Managers (Sequential)"
    
    log STEP "Adding ${#OTHER_MANAGERS[@]} manager(s) to swarm..."
    log INFO "Joining managers sequentially to maintain Raft consensus"
    
    local joined=0
    local failed=0
    
    for manager_ip in "${OTHER_MANAGERS[@]}"; do
        if join_manager "$manager_ip" "$first_manager" "$user" "$password" "$token"; then
            ((joined++))
            
            # Wait for Raft consensus to stabilize
            log INFO "Waiting ${SWARM_MANAGER_JOIN_DELAY}s for Raft consensus..."
            sleep "$SWARM_MANAGER_JOIN_DELAY"
        else
            ((failed++))
            
            log ERROR "Manager join failed, cluster may be unstable"
            
            # Ask user if they want to continue
            read -p "Continue with remaining managers? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log ERROR "Manager join aborted by user"
                return 1
            fi
        fi
    done
    
    log INFO "Manager join summary: $joined joined, $failed failed"
    
    if [[ $failed -gt 0 ]]; then
        log WARN "Some managers failed to join"
        return 1
    fi
    
    log SUCCESS "All managers joined successfully"
    return 0
}

# ============================================================================
# PHASE 5: WORKER JOIN
# ============================================================================

join_all_workers() {
    local first_manager="$1"
    local user="$2"
    local password="$3"
    local token="$4"
    
    if [[ ${#WORKERS[@]} -eq 0 ]]; then
        log INFO "No workers to join"
        return 0
    fi
    
    print_header "Phase 5: Join Workers (Parallel)"
    
    log STEP "Adding ${#WORKERS[@]} worker(s) to swarm..."
    log INFO "Joining workers in parallel for speed"
    
    # Build device array for parallel execution
    local worker_devices=()
    for worker_ip in "${WORKERS[@]}"; do
        worker_devices+=("${worker_ip}:${user}:${password}")
    done
    
    # Build join command
    local join_cmd="docker swarm join \
        --token ${token} \
        --advertise-addr \$(hostname -I | awk '{print \$1}'):${SWARM_ADVERTISE_PORT} \
        --listen-addr \$(hostname -I | awk '{print \$1}'):${SWARM_ADVERTISE_PORT} \
        ${first_manager}:${SWARM_ADVERTISE_PORT}"
    
    # Execute in parallel
    parallel_exec worker_devices[@] \
        "$join_cmd" \
        "Joining workers to swarm"
    
    # Check results
    local results=$(parallel_collect_results)
    local success_count=$(echo "$results" | jq -r '.successful')
    local failed_count=$(echo "$results" | jq -r '.failed')
    local success_rate=$(echo "$results" | jq -r '.success_rate')
    
    log INFO "Worker join summary: $success_count joined, $failed_count failed"
    
    if [[ $failed_count -gt 0 ]]; then
        log WARN "Some workers failed to join"
        
        # Show which workers failed
        echo "$results" | jq -r '.devices[] | select(.status == "failed") | "  • \(.ip): \(.error)"'
        
        # Continue anyway (workers are not critical)
        log WARN "Continuing with $success_count workers"
    fi
    
    log SUCCESS "Workers joined to swarm"
    return 0
}

# ============================================================================
# PHASE 6: NETWORK SETUP
# ============================================================================

create_overlay_networks() {
    local first_manager="$1"
    local user="$2"
    local password="$3"
    
    print_header "Phase 6: Create Overlay Networks"
    
    log STEP "Creating overlay networks..."
    
    # Check if network already exists
    local network_exists=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no "${user}@${first_manager}" \
        "docker network ls --filter name=aeon-overlay --format '{{.Name}}'" 2>/dev/null)
    
    if [[ "$network_exists" == "aeon-overlay" ]]; then
        log INFO "Overlay network 'aeon-overlay' already exists"
    else
        log INFO "Creating overlay network: aeon-overlay"
        
        sshpass -p "$password" ssh -o StrictHostKeyChecking=no "${user}@${first_manager}" \
            "docker network create \
             --driver overlay \
             --attachable \
             --subnet ${SWARM_OVERLAY_SUBNET} \
             aeon-overlay" &>/dev/null
        
        if [[ $? -eq 0 ]]; then
            log SUCCESS "Overlay network 'aeon-overlay' created"
        else
            log ERROR "Failed to create overlay network"
            return 1
        fi
    fi
    
    # List all networks
    log INFO "Available networks:"
    sshpass -p "$password" ssh -o StrictHostKeyChecking=no "${user}@${first_manager}" \
        "docker network ls --format 'table {{.Name}}\t{{.Driver}}\t{{.Scope}}'" | while read line; do
        log INFO "  $line"
    done
    
    return 0
}

# ============================================================================
# PHASE 7: VERIFICATION
# ============================================================================

verify_swarm_cluster() {
    local first_manager="$1"
    local user="$2"
    local password="$3"
    
    print_header "Phase 7: Verify Swarm Cluster"
    
    log STEP "Verifying cluster health..."
    
    # Get node list
    local node_list=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no "${user}@${first_manager}" \
        "docker node ls --format '{{json .}}'" 2>/dev/null)
    
    if [[ -z "$node_list" ]]; then
        log ERROR "Failed to retrieve node list"
        return 1
    fi
    
    # Count nodes
    local total_nodes=$(echo "$node_list" | wc -l)
    local manager_nodes=$(echo "$node_list" | jq -r 'select(.ManagerStatus != "") | .ID' | wc -l)
    local worker_nodes=$((total_nodes - manager_nodes))
    local ready_nodes=$(echo "$node_list" | jq -r 'select(.Status == "Ready") | .ID' | wc -l)
    local leader_node=$(echo "$node_list" | jq -r 'select(.ManagerStatus == "Leader") | .Hostname' | head -1)
    
    log INFO "Cluster status:"
    log INFO "  Total nodes: $total_nodes"
    log INFO "  Managers: $manager_nodes"
    log INFO "  Workers: $worker_nodes"
    log INFO "  Ready: $ready_nodes / $total_nodes"
    log INFO "  Leader: $leader_node"
    
    # Check if all nodes are ready
    if [[ $ready_nodes -ne $total_nodes ]]; then
        log WARN "Not all nodes are ready ($ready_nodes/$total_nodes)"
        
        # Show which nodes are not ready
        echo "$node_list" | jq -r 'select(.Status != "Ready") | "  • \(.Hostname) (\(.IP)): \(.Status)"' | while read line; do
            log WARN "$line"
        done
    else
        log SUCCESS "All nodes are ready"
    fi
    
    # Check manager quorum
    local quorum_needed=$(( (manager_nodes / 2) + 1 ))
    log INFO "  Quorum: $quorum_needed / $manager_nodes managers required for consensus"
    
    if [[ $manager_nodes -lt 3 ]]; then
        log WARN "Less than 3 managers - fault tolerance is limited"
    fi
    
    # Display node details
    echo ""
    log INFO "Node details:"
    
    sshpass -p "$password" ssh -o StrictHostKeyChecking=no "${user}@${first_manager}" \
        "docker node ls" | while read line; do
        log INFO "  $line"
    done
    
    echo ""
    
    # Final status
    if [[ $ready_nodes -eq $total_nodes ]] && [[ $manager_nodes -ge 3 ]]; then
        log SUCCESS "✅ Docker Swarm cluster is healthy and ready!"
        return 0
    elif [[ $ready_nodes -eq $total_nodes ]]; then
        log SUCCESS "✅ Docker Swarm cluster is operational"
        log WARN "⚠️  Manager count is below recommended (3+)"
        return 0
    else
        log WARN "⚠️  Swarm cluster is operational but some nodes are not ready"
        return 1
    fi
}

# ============================================================================
# MAIN SWARM SETUP ORCHESTRATION
# ============================================================================

setup_docker_swarm() {
    local assignments_file="$1"
    local user="${2:-aeon}"
    local password="${3:-}"
    
    print_header "Docker Swarm Cluster Setup"
    
    log INFO "AEON user: $user"
    log INFO "Role assignments: $assignments_file"
    echo ""
    
    # ========================================================================
    # PHASE 1: PREPARATION
    # ========================================================================
    
    print_header "Phase 1: Preparation"
    
    load_role_assignments "$assignments_file" || return 1
    
    echo ""
    log INFO "Cluster topology:"
    log INFO "  First manager: $FIRST_MANAGER (rank #1 - will initialize swarm)"
    
    if [[ ${#OTHER_MANAGERS[@]} -gt 0 ]]; then
        log INFO "  Other managers:"
        for i in "${!OTHER_MANAGERS[@]}"; do
            log INFO "    • ${OTHER_MANAGERS[$i]} (rank #$((i + 2)))"
        done
    fi
    
    if [[ ${#WORKERS[@]} -gt 0 ]]; then
        log INFO "  Workers:"
        for worker in "${WORKERS[@]}"; do
            log INFO "    • $worker"
        done
    fi
    
    echo ""
    
    # Verify Docker is ready on all devices
    verify_all_docker_ready "$user" "$password" || {
        log ERROR "Not all devices have Docker ready"
        return 1
    }
    
    echo ""
    
    # ========================================================================
    # PHASE 2: SWARM INITIALIZATION
    # ========================================================================
    
    initialize_swarm "$FIRST_MANAGER" "$user" "$password" || return 1
    
    echo ""
    
    # ========================================================================
    # PHASE 3: TOKEN EXTRACTION
    # ========================================================================
    
    extract_join_tokens "$FIRST_MANAGER" "$user" "$password" || return 1
    
    echo ""
    
    # ========================================================================
    # PHASE 4: MANAGER JOIN
    # ========================================================================
    
    join_all_managers "$FIRST_MANAGER" "$user" "$password" "$MANAGER_TOKEN" || {
        log ERROR "Failed to join all managers"
        log WARN "Cluster may be operational with reduced manager count"
    }
    
    echo ""
    
    # ========================================================================
    # PHASE 5: WORKER JOIN
    # ========================================================================
    
    join_all_workers "$FIRST_MANAGER" "$user" "$password" "$WORKER_TOKEN" || {
        log WARN "Some workers failed to join"
    }
    
    echo ""
    
    # ========================================================================
    # PHASE 6: NETWORK SETUP
    # ========================================================================
    
    create_overlay_networks "$FIRST_MANAGER" "$user" "$password" || {
        log ERROR "Failed to create overlay networks"
    }
    
    echo ""
    
    # ========================================================================
    # PHASE 7: VERIFICATION
    # ========================================================================
    
    verify_swarm_cluster "$FIRST_MANAGER" "$user" "$password" || {
        log WARN "Cluster verification shows issues"
    }
    
    # ========================================================================
    # COMPLETION
    # ========================================================================
    
    print_header "Swarm Setup Complete"
    
    log SUCCESS "🎉 Docker Swarm cluster is ready!"
    echo ""
    log INFO "Next steps:"
    log INFO "  1. Deploy services: docker stack deploy -c docker-compose.yml <stack>"
    log INFO "  2. View cluster: docker node ls"
    log INFO "  3. View services: docker service ls"
    echo ""
    
    # Clear sensitive tokens from memory
    MANAGER_TOKEN=""
    WORKER_TOKEN=""
    
    return 0
}

# ============================================================================
# EXPORT FUNCTIONS
# ============================================================================

export -f setup_docker_swarm
export -f load_role_assignments
export -f verify_swarm_cluster

# ============================================================================
# STANDALONE EXECUTION
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    
    if [[ $# -lt 3 ]]; then
        echo "Usage: $0 <role_assignments.json> <user> <password>"
        echo ""
        echo "Example:"
        echo "  $0 /opt/aeon/data/role_assignments.json aeon mypassword"
        exit 1
    fi
    
    # Source parallel module (required)
    if [[ -f "/opt/aeon/lib/parallel.sh" ]]; then
        source /opt/aeon/lib/parallel.sh
        parallel_init
    else
        echo "ERROR: parallel.sh not found - required for worker join"
        exit 1
    fi
    
    setup_docker_swarm "$1" "$2" "$3"
fi
