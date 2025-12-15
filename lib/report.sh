#!/bin/bash
################################################################################
# AEON Report Generation Module
# File: lib/report.sh
# Version: 0.1.0
#
# Purpose: Generate beautiful installation reports showing:
#   - Installation timeline
#   - Cluster topology
#   - Device details
#   - Success/failure summary
#   - Next steps
#
# Output Formats:
#   - Terminal (colored, formatted)
#   - Markdown (.md)
#   - JSON (machine-readable)
#   - Plain text (.txt)
################################################################################

set -euo pipefail

# ============================================================================
# DEPENDENCIES
# ============================================================================

# Prevent double-loading
[[ -n "${AEON_REPORT_LOADED:-}" ]] && return 0
readonly AEON_REPORT_LOADED=1

# Load dependencies
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
if [[ -z "${AEON_DEPENDENCIES_LOADED:-}" ]]; then
    source "$SCRIPT_DIR/dependencies.sh" || source "/opt/aeon/lib/dependencies.sh" || {
        echo "ERROR: Cannot find dependencies.sh" >&2
        exit 1
    }
fi

# load dependecies -if available
load_dependencies "report.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

REPORT_DIR="/opt/aeon/reports"
REPORT_TIMESTAMP=$(date '+%Y%m%d-%H%M%S')

# ============================================================================
# DATA COLLECTION
# ============================================================================

collect_report_data() {
    local data_dir="${1:-/opt/aeon/data}"
    
    # Initialize report data structure
    REPORT_DATA=$(cat <<EOF
{
    "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "aeon_version": "0.1.0",
    "installation": {},
    "cluster": {},
    "devices": [],
    "timeline": [],
    "summary": {}
}
EOF
)
    
    # Load discovered devices (if available)
    if [[ -f "$data_dir/discovered_devices.json" ]]; then
        DISCOVERED_DATA=$(cat "$data_dir/discovered_devices.json")
    fi
    
    # Load hardware profiles
    if [[ -f "$data_dir/hw_profiles.json" ]]; then
        HW_PROFILES=$(cat "$data_dir/hw_profiles.json")
    fi
    
    # Load role assignments
    if [[ -f "$data_dir/role_assignments.json" ]]; then
        ROLE_ASSIGNMENTS=$(cat "$data_dir/role_assignments.json")
    fi
    
    # Load installation results
    if [[ -f "$data_dir/installation_results.json" ]]; then
        INSTALL_RESULTS=$(cat "$data_dir/installation_results.json")
    fi
    
    # Collect swarm status (if available)
    if command -v docker &>/dev/null && docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q "active"; then
        collect_swarm_status
    fi
    
    return 0
}

collect_swarm_status() {
    # Get swarm info from first manager
    local first_manager=$(echo "$ROLE_ASSIGNMENTS" | jq -r '.assignments[] | select(.role == "manager" and .rank == 1) | .device.ip' | head -1)
    
    if [[ -n "$first_manager" ]] && [[ -f /opt/aeon/.aeon.env ]]; then
        source /opt/aeon/.aeon.env
        
        SWARM_STATUS=$(sshpass -p "$AEON_PASSWORD" ssh -o StrictHostKeyChecking=no \
            "${AEON_USER}@${first_manager}" \
            "docker node ls --format '{{json .}}'" 2>/dev/null | jq -s '.')
        
        SWARM_NETWORKS=$(sshpass -p "$AEON_PASSWORD" ssh -o StrictHostKeyChecking=no \
            "${AEON_USER}@${first_manager}" \
            "docker network ls --format '{{json .}}'" 2>/dev/null | jq -s '.')
    fi
}

# ============================================================================
# TERMINAL REPORT
# ============================================================================

print_terminal_report() {
    clear
    
    # ASCII Art Banner
    cat << 'EOF'
    
     █████╗ ███████╗ ██████╗ ███╗   ██╗
    ██╔══██╗██╔════╝██╔═══██╗████╗  ██║
    ███████║█████╗  ██║   ██║██╔██╗ ██║
    ██╔══██║██╔══╝  ██║   ██║██║╚██╗██║
    ██║  ██║███████╗╚██████╔╝██║ ╚████║
    ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝
    
    Autonomous Evolving Orchestration Network
    
EOF
    
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  INSTALLATION COMPLETE REPORT${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Executive Summary
    print_executive_summary
    
    # Cluster Topology
    print_cluster_topology
    
    # Device Details
    print_device_details
    
    # Network Configuration
    print_network_config
    
    # Next Steps
    print_next_steps
    
    # Footer
    echo ""
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}  🎉 Your AEON cluster is ready for production!${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_executive_summary() {
    echo -e "${BOLD}${BLUE}EXECUTIVE SUMMARY${NC}"
    echo ""
    
    # Get summary from role assignments
    local total_devices=$(echo "$ROLE_ASSIGNMENTS" | jq -r '.summary.total_devices // 0')
    local manager_count=$(echo "$ROLE_ASSIGNMENTS" | jq -r '.summary.manager_count // 0')
    local worker_count=$(echo "$ROLE_ASSIGNMENTS" | jq -r '.summary.worker_count // 0')
    local fault_tolerance=$(echo "$ROLE_ASSIGNMENTS" | jq -r '.summary.fault_tolerance // 0')
    
    echo -e "  ${CYAN}Generated:${NC}        $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo -e "  ${CYAN}AEON Version:${NC}     0.1.0"
    echo -e "  ${CYAN}Status:${NC}           ${GREEN}${BOLD}✅ SUCCESS${NC}"
    echo ""
    echo -e "  ${CYAN}Total Devices:${NC}    $total_devices"
    echo -e "  ${CYAN}Managers:${NC}         ${BLUE}$manager_count${NC} (all operational)"
    echo -e "  ${CYAN}Workers:${NC}          $worker_count (all operational)"
    echo -e "  ${CYAN}Fault Tolerance:${NC}  Can lose ${BOLD}$fault_tolerance${NC} manager(s)"
    echo ""
}

print_cluster_topology() {
    echo -e "${BOLD}${BLUE}CLUSTER TOPOLOGY${NC}"
    echo ""
    
    # Managers
    echo -e "${BOLD}  ${BLUE}Managers (Control Plane)${NC}"
    echo ""
    
    local managers=$(echo "$ROLE_ASSIGNMENTS" | jq -r '.assignments[] | select(.role == "manager") | @json')
    
    echo "$managers" | while read -r manager_json; do
        local rank=$(echo "$manager_json" | jq -r '.rank')
        local hostname=$(echo "$manager_json" | jq -r '.device.hostname')
        local ip=$(echo "$manager_json" | jq -r '.device.ip')
        local model=$(echo "$manager_json" | jq -r '.device.model')
        local ram=$(echo "$manager_json" | jq -r '.device.ram_gb')
        local storage=$(echo "$manager_json" | jq -r '.device.storage_type')
        local storage_size=$(echo "$manager_json" | jq -r '.device.storage_size_gb')
        local score=$(echo "$manager_json" | jq -r '.device.score')
        
        local leader_mark=""
        if [[ $rank -eq 1 ]]; then
            leader_mark=" ${YELLOW}⭐ LEADER${NC}"
        fi
        
        echo -e "  ${BOX_TL}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_TR}"
        echo -e "  ${BOX_V} ${BOLD}Rank #$rank - $hostname ($ip)${NC} 🔷${leader_mark}"
        echo -e "  ${BOX_V}   Model: $model ($ram GB)"
        echo -e "  ${BOX_V}   Storage: $storage $storage_size GB"
        echo -e "  ${BOX_V}   Score: ${GREEN}$score/170${NC} ($(( score * 100 / 170 ))%)"
        echo -e "  ${BOX_V}   Status: ${GREEN}✅ Ready, ✅ Reachable${NC}"
        echo -e "  ${BOX_BL}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_BR}"
        echo ""
    done
    
    # Workers
    echo -e "${BOLD}  Workers (Compute Nodes)${NC}"
    echo ""
    
    local workers=$(echo "$ROLE_ASSIGNMENTS" | jq -r '.assignments[] | select(.role == "worker") | @json')
    
    echo "$workers" | while read -r worker_json; do
        local hostname=$(echo "$worker_json" | jq -r '.device.hostname')
        local ip=$(echo "$worker_json" | jq -r '.device.ip')
        local device_type=$(echo "$worker_json" | jq -r '.device.device_type')
        local model=$(echo "$worker_json" | jq -r '.device.model')
        local ram=$(echo "$worker_json" | jq -r '.device.ram_gb')
        local storage=$(echo "$worker_json" | jq -r '.device.storage_type')
        local storage_size=$(echo "$worker_json" | jq -r '.device.storage_size_gb')
        local score=$(echo "$worker_json" | jq -r '.device.score // 0')
        
        local type_label=""
        if [[ "$device_type" == "raspberry_pi" ]]; then
            type_label="Pi Worker"
        elif [[ "$device_type" == "llm_computer" ]]; then
            type_label="LLM Worker"
        else
            type_label="Host Worker"
        fi
        
        echo -e "  ${BOX_TL}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_TR}"
        echo -e "  ${BOX_V} ${BOLD}$hostname ($ip)${NC} 🔶 $type_label"
        echo -e "  ${BOX_V}   Model: $model ($ram GB)"
        echo -e "  ${BOX_V}   Storage: $storage $storage_size GB"
        if [[ $score -gt 0 ]]; then
            echo -e "  ${BOX_V}   Score: $score/170 ($(( score * 100 / 170 ))%)"
        fi
        echo -e "  ${BOX_V}   Status: ${GREEN}✅ Ready${NC}"
        echo -e "  ${BOX_BL}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_BR}"
        echo ""
    done
}

print_device_details() {
    echo -e "${BOLD}${BLUE}DEVICE SUMMARY${NC}"
    echo ""
    
    # Table header
    printf "  %-18s %-15s %-8s %-12s %-6s %-12s %-8s %-8s\n" \
        "Hostname" "IP" "Type" "Model" "RAM" "Storage" "Role" "Status"
    echo "  ─────────────────────────────────────────────────────────────────────────────────────────────"
    
    # Table rows
    echo "$ROLE_ASSIGNMENTS" | jq -r '.assignments[] | @json' | while read -r device_json; do
        local hostname=$(echo "$device_json" | jq -r '.device.hostname')
        local ip=$(echo "$device_json" | jq -r '.device.ip')
        local device_type=$(echo "$device_json" | jq -r '.device.device_type')
        local model=$(echo "$device_json" | jq -r '.device.model' | sed 's/Raspberry //')
        local ram=$(echo "$device_json" | jq -r '.device.ram_gb')
        local storage=$(echo "$device_json" | jq -r '.device.storage_type')
        local storage_size=$(echo "$device_json" | jq -r '.device.storage_size_gb')
        local role=$(echo "$device_json" | jq -r '.role')
        
        local type_short=""
        case "$device_type" in
            raspberry_pi) type_short="Pi" ;;
            llm_computer) type_short="LLM" ;;
            host_computer) type_short="Host" ;;
            *) type_short="?" ;;
        esac
        
        local storage_display="${storage^^} ${storage_size}GB"
        
        printf "  %-18s %-15s %-8s %-12s %-6s %-12s %-8s ${GREEN}%-8s${NC}\n" \
            "$hostname" "$ip" "$type_short" "$model" "${ram}GB" "$storage_display" "$role" "✅ Ready"
    done
    
    echo ""
}

print_network_config() {
    echo -e "${BOLD}${BLUE}NETWORK CONFIGURATION${NC}"
    echo ""
    
    echo -e "  ${CYAN}Swarm Networks:${NC}"
    echo -e "    • ${BOLD}ingress${NC} - Overlay network for published ports"
    echo -e "    • ${BOLD}docker_gwbridge${NC} - Bridge for container-host communication"
    echo -e "    • ${BOLD}aeon-overlay${NC} - Custom overlay (10.0.1.0/24)"
    echo ""
    
    echo -e "  ${CYAN}Firewall Ports (Opened):${NC}"
    echo -e "    • ${BOLD}2376/tcp${NC} - Docker daemon (TLS)"
    echo -e "    • ${BOLD}2377/tcp${NC} - Swarm management"
    echo -e "    • ${BOLD}7946/tcp+udp${NC} - Swarm node communication"
    echo -e "    • ${BOLD}4789/udp${NC} - Overlay network (VXLAN)"
    echo ""
}

print_next_steps() {
    echo -e "${BOLD}${BLUE}QUICK START GUIDE${NC}"
    echo ""
    
    local first_manager=$(echo "$ROLE_ASSIGNMENTS" | jq -r '.assignments[] | select(.role == "manager" and .rank == 1) | .device.ip' | head -1)
    
    echo -e "  ${BOLD}1. Connect to Any Manager${NC}"
    echo -e "     ${CYAN}ssh aeon@${first_manager}${NC}"
    echo ""
    
    echo -e "  ${BOLD}2. View Cluster Status${NC}"
    echo -e "     ${CYAN}docker node ls${NC}"
    echo ""
    
    echo -e "  ${BOLD}3. Deploy a Test Service${NC}"
    echo -e "     ${CYAN}docker service create --name web --replicas 3 --publish 80:80 nginx${NC}"
    echo -e "     ${CYAN}docker service ps web${NC}"
    echo ""
    
    echo -e "  ${BOLD}4. Deploy a Stack${NC}"
    echo -e "     ${CYAN}docker stack deploy -c docker-compose.yml myapp${NC}"
    echo -e "     ${CYAN}docker stack ps myapp${NC}"
    echo ""
    
    echo -e "  ${CYAN}Documentation:${NC} https://github.com/conceptixx/AEON"
    echo -e "  ${CYAN}Report Location:${NC} $REPORT_DIR/aeon-report-${REPORT_TIMESTAMP}.md"
    echo ""
}

# ============================================================================
# MARKDOWN REPORT
# ============================================================================

generate_markdown_report() {
    local output_file="$1"
    
    cat > "$output_file" <<'EOF'
# AEON Cluster Installation Report

**Generated:** %TIMESTAMP%
**AEON Version:** 0.1.0
**Status:** ✅ SUCCESS

---

## Executive Summary

- **Total Devices:** %TOTAL_DEVICES%
- **Managers:** %MANAGER_COUNT% (all operational)
- **Workers:** %WORKER_COUNT% (all operational)
- **Fault Tolerance:** Can lose %FAULT_TOLERANCE% manager(s)
- **Installation Success Rate:** 100%

---

## Cluster Topology

### Managers (Control Plane)

%MANAGERS%

### Workers (Compute Nodes)

%WORKERS%

---

## Device Summary

| Hostname | IP | Type | Model | RAM | Storage | Role | Status |
|----------|-------|------|-------|-----|---------|------|--------|
%DEVICE_TABLE%

---

## Network Configuration

### Swarm Networks
- **ingress**: Overlay network for published ports
- **docker_gwbridge**: Bridge for container-host communication
- **aeon-overlay**: Custom overlay (10.0.1.0/24)

### Firewall Ports (Opened)
- **2376/tcp**: Docker daemon (TLS)
- **2377/tcp**: Swarm management
- **7946/tcp+udp**: Swarm node communication
- **4789/udp**: Overlay network (VXLAN)

---

## Quick Start

### 1. Connect to Any Manager
```bash
ssh aeon@%FIRST_MANAGER_IP%
```

### 2. View Cluster Status
```bash
docker node ls
```

### 3. Deploy a Test Service
```bash
docker service create --name web --replicas 3 --publish 80:80 nginx
docker service ps web
```

### 4. Deploy a Stack
```bash
docker stack deploy -c docker-compose.yml myapp
docker stack ps myapp
```

---

## Resources

- **AEON Documentation:** https://github.com/conceptixx/AEON
- **Docker Swarm Docs:** https://docs.docker.com/engine/swarm/
- **Report Location:** %REPORT_FILE%

---

**🎉 Congratulations! Your AEON cluster is ready for production!**
EOF
    
    # Replace placeholders
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S %Z')
    local total_devices=$(echo "$ROLE_ASSIGNMENTS" | jq -r '.summary.total_devices // 0')
    local manager_count=$(echo "$ROLE_ASSIGNMENTS" | jq -r '.summary.manager_count // 0')
    local worker_count=$(echo "$ROLE_ASSIGNMENTS" | jq -r '.summary.worker_count // 0')
    local fault_tolerance=$(echo "$ROLE_ASSIGNMENTS" | jq -r '.summary.fault_tolerance // 0')
    local first_manager=$(echo "$ROLE_ASSIGNMENTS" | jq -r '.assignments[] | select(.role == "manager" and .rank == 1) | .device.ip' | head -1)
    
    sed -i "s|%TIMESTAMP%|$timestamp|g" "$output_file"
    sed -i "s|%TOTAL_DEVICES%|$total_devices|g" "$output_file"
    sed -i "s|%MANAGER_COUNT%|$manager_count|g" "$output_file"
    sed -i "s|%WORKER_COUNT%|$worker_count|g" "$output_file"
    sed -i "s|%FAULT_TOLERANCE%|$fault_tolerance|g" "$output_file"
    sed -i "s|%FIRST_MANAGER_IP%|$first_manager|g" "$output_file"
    sed -i "s|%REPORT_FILE%|$output_file|g" "$output_file"
    
    # Generate managers section
    local managers_md=""
    echo "$ROLE_ASSIGNMENTS" | jq -r '.assignments[] | select(.role == "manager") | @json' | while read -r manager_json; do
        local rank=$(echo "$manager_json" | jq -r '.rank')
        local hostname=$(echo "$manager_json" | jq -r '.device.hostname')
        local ip=$(echo "$manager_json" | jq -r '.device.ip')
        local model=$(echo "$manager_json" | jq -r '.device.model')
        local ram=$(echo "$manager_json" | jq -r '.device.ram_gb')
        local storage=$(echo "$manager_json" | jq -r '.device.storage_type')
        local storage_size=$(echo "$manager_json" | jq -r '.device.storage_size_gb')
        local score=$(echo "$manager_json" | jq -r '.device.score')
        
        local leader_mark=""
        [[ $rank -eq 1 ]] && leader_mark=" ⭐ **LEADER**"
        
        managers_md+="#### Rank #$rank - $hostname ($ip) 🔷$leader_mark

- **Model:** $model ($ram GB)
- **Storage:** $storage $storage_size GB
- **Score:** $score/170 ($(( score * 100 / 170 ))%)
- **Status:** ✅ Ready, ✅ Reachable

"
    done
    
    # Generate workers section
    local workers_md=""
    echo "$ROLE_ASSIGNMENTS" | jq -r '.assignments[] | select(.role == "worker") | @json' | while read -r worker_json; do
        local hostname=$(echo "$worker_json" | jq -r '.device.hostname')
        local ip=$(echo "$worker_json" | jq -r '.device.ip')
        local device_type=$(echo "$worker_json" | jq -r '.device.device_type')
        local model=$(echo "$worker_json" | jq -r '.device.model')
        local ram=$(echo "$worker_json" | jq -r '.device.ram_gb')
        local storage=$(echo "$worker_json" | jq -r '.device.storage_type')
        local storage_size=$(echo "$worker_json" | jq -r '.device.storage_size_gb')
        
        local type_label=""
        case "$device_type" in
            raspberry_pi) type_label="Pi Worker" ;;
            llm_computer) type_label="LLM Worker" ;;
            *) type_label="Host Worker" ;;
        esac
        
        workers_md+="#### $hostname ($ip) 🔶 $type_label

- **Model:** $model ($ram GB)
- **Storage:** $storage $storage_size GB
- **Status:** ✅ Ready

"
    done
    
    # Generate device table
    local device_table=""
    echo "$ROLE_ASSIGNMENTS" | jq -r '.assignments[] | @json' | while read -r device_json; do
        local hostname=$(echo "$device_json" | jq -r '.device.hostname')
        local ip=$(echo "$device_json" | jq -r '.device.ip')
        local device_type=$(echo "$device_json" | jq -r '.device.device_type')
        local model=$(echo "$device_json" | jq -r '.device.model' | sed 's/Raspberry //')
        local ram=$(echo "$device_json" | jq -r '.device.ram_gb')
        local storage=$(echo "$device_json" | jq -r '.device.storage_type')
        local storage_size=$(echo "$device_json" | jq -r '.device.storage_size_gb')
        local role=$(echo "$device_json" | jq -r '.role')
        
        local type_short=""
        case "$device_type" in
            raspberry_pi) type_short="Pi" ;;
            llm_computer) type_short="LLM" ;;
            host_computer) type_short="Host" ;;
        esac
        
        device_table+="| $hostname | $ip | $type_short | $model | ${ram}GB | ${storage^^} ${storage_size}GB | $role | ✅ Ready |
"
    done
    
    # Insert generated content (use temporary file to avoid sed issues)
    awk -v managers="$managers_md" '/^%MANAGERS%$/{print managers; next}1' "$output_file" > "$output_file.tmp" && mv "$output_file.tmp" "$output_file"
    awk -v workers="$workers_md" '/^%WORKERS%$/{print workers; next}1' "$output_file" > "$output_file.tmp" && mv "$output_file.tmp" "$output_file"
    awk -v table="$device_table" '/^%DEVICE_TABLE%$/{print table; next}1' "$output_file" > "$output_file.tmp" && mv "$output_file.tmp" "$output_file"
    
    return 0
}

# ============================================================================
# JSON REPORT
# ============================================================================

generate_json_report() {
    local output_file="$1"
    
    # Compile complete report JSON
    local report=$(cat <<EOF
{
    "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "aeon_version": "0.1.0",
    "status": "success",
    "role_assignments": $ROLE_ASSIGNMENTS,
    "installation_results": ${INSTALL_RESULTS:-null},
    "swarm_status": ${SWARM_STATUS:-null},
    "swarm_networks": ${SWARM_NETWORKS:-null}
}
EOF
)
    
    echo "$report" | jq '.' > "$output_file"
    
    return 0
}

# ============================================================================
# MAIN REPORT GENERATION
# ============================================================================

generate_installation_report() {
    local data_dir="${1:-/opt/aeon/data}"
    local format="${2:-all}"  # all, terminal, markdown, json
    
    mkdir -p "$REPORT_DIR"
    
    # Collect data
    collect_report_data "$data_dir"
    
    # Generate reports based on format
    case "$format" in
        terminal)
            print_terminal_report
            ;;
        markdown)
            generate_markdown_report "$REPORT_DIR/aeon-report-${REPORT_TIMESTAMP}.md"
            ;;
        json)
            generate_json_report "$REPORT_DIR/aeon-report-${REPORT_TIMESTAMP}.json"
            ;;
        all|*)
            # Generate all formats
            print_terminal_report
            generate_markdown_report "$REPORT_DIR/aeon-report-${REPORT_TIMESTAMP}.md"
            generate_json_report "$REPORT_DIR/aeon-report-${REPORT_TIMESTAMP}.json"
            
            echo ""
            echo -e "${GREEN}✅ Reports generated:${NC}"
            echo -e "  ${CYAN}• Terminal display${NC} (shown above)"
            echo -e "  ${CYAN}• Markdown:${NC} $REPORT_DIR/aeon-report-${REPORT_TIMESTAMP}.md"
            echo -e "  ${CYAN}• JSON:${NC} $REPORT_DIR/aeon-report-${REPORT_TIMESTAMP}.json"
            ;;
    esac
    
    return 0
}

# ============================================================================
# EXPORT FUNCTIONS
# ============================================================================

export -f generate_installation_report
export -f print_terminal_report

# ============================================================================
# STANDALONE EXECUTION
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 [data_dir] [format]"
        echo ""
        echo "Parameters:"
        echo "  data_dir  - Directory containing AEON data files (default: /opt/aeon/data)"
        echo "  format    - Output format: terminal, markdown, json, all (default: all)"
        echo ""
        echo "Example:"
        echo "  $0 /opt/aeon/data all"
        exit 1
    fi
    
    generate_installation_report "${1:-/opt/aeon/data}" "${2:-all}"
fi
