#!/bin/bash
################################################################################
# AEON Parallel Execution Module
# File: lib/parallel.sh
# Version: 0.1.0
#
# Purpose: Execute commands on multiple remote devices simultaneously with
#          progress tracking, error handling, and result aggregation.
#
# Usage:
#   source /opt/aeon/lib/parallel.sh
#   parallel_init
#   parallel_exec devices[@] "command" "description"
#   results=$(parallel_collect_results)
#   parallel_cleanup
#
# Dependencies: sshpass, ssh, scp, bc, jq (optional)
################################################################################

# ============================================================================
# GLOBAL VARIABLES
# ============================================================================

PARALLEL_JOB_DIR=""
PARALLEL_MAX_JOBS=${PARALLEL_MAX_JOBS:-10}
PARALLEL_SSH_TIMEOUT=${PARALLEL_SSH_TIMEOUT:-30}
PARALLEL_RETRY_COUNT=${PARALLEL_RETRY_COUNT:-3}
PARALLEL_RETRY_DELAY=${PARALLEL_RETRY_DELAY:-5}

# Colors for output
PARALLEL_RED='\033[0;31m'
PARALLEL_GREEN='\033[0;32m'
PARALLEL_YELLOW='\033[1;33m'
PARALLEL_BLUE='\033[0;34m'
PARALLEL_CYAN='\033[0;36m'
PARALLEL_BOLD='\033[1m'
PARALLEL_NC='\033[0m'

# Job tracking
declare -A PARALLEL_JOBS        # PID -> IP mapping
declare -A PARALLEL_JOB_STATUS  # IP -> status mapping
declare -A PARALLEL_JOB_START   # IP -> start time
declare -A PARALLEL_JOB_END     # IP -> end time

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

parallel_log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ -n "${PARALLEL_JOB_DIR}" ]] && [[ -d "${PARALLEL_JOB_DIR}" ]]; then
        echo "[$timestamp] [$level] $message" >> "${PARALLEL_JOB_DIR}/parallel.log"
    fi
    
    case "$level" in
        ERROR)
            echo -e "${PARALLEL_RED}❌ $message${PARALLEL_NC}" >&2
            ;;
        WARN)
            echo -e "${PARALLEL_YELLOW}⚠️  $message${PARALLEL_NC}"
            ;;
        INFO)
            echo -e "${PARALLEL_CYAN}ℹ️  $message${PARALLEL_NC}"
            ;;
        SUCCESS)
            echo -e "${PARALLEL_GREEN}✅ $message${PARALLEL_NC}"
            ;;
        DEBUG)
            if [[ "${DEBUG:-0}" == "1" ]]; then
                echo -e "${PARALLEL_BLUE}🔍 $message${PARALLEL_NC}"
            fi
            ;;
    esac
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

parallel_check_dependencies() {
    local missing=()
    
    for cmd in sshpass ssh scp bc; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        parallel_log ERROR "Missing dependencies: ${missing[*]}"
        parallel_log INFO "Installing missing dependencies..."
        
        if command -v apt-get &>/dev/null; then
            apt-get update -qq
            for pkg in "${missing[@]}"; do
                apt-get install -y -qq "$pkg" 2>/dev/null || {
                    parallel_log ERROR "Failed to install $pkg"
                    return 1
                }
            done
        else
            parallel_log ERROR "Cannot auto-install dependencies (unsupported package manager)"
            return 1
        fi
        
        parallel_log SUCCESS "Dependencies installed"
    fi
    
    return 0
}

parallel_create_progress_bar() {
    local current=$1
    local total=$2
    local width=${3:-40}
    
    local percent=$((current * 100 / total))
    local filled=$((width * current / total))
    local empty=$((width - filled))
    
    printf "["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %3d%%" "$percent"
}

parallel_format_duration() {
    local seconds=$1
    
    if [[ $seconds -lt 60 ]]; then
        printf "%ds" "$seconds"
    elif [[ $seconds -lt 3600 ]]; then
        printf "%dm %ds" $((seconds / 60)) $((seconds % 60))
    else
        printf "%dh %dm %ds" $((seconds / 3600)) $(((seconds % 3600) / 60)) $((seconds % 60))
    fi
}

# ============================================================================
# CORE FUNCTIONS
# ============================================================================

parallel_init() {
    parallel_log INFO "Initializing parallel execution environment..."
    
    # Check dependencies
    parallel_check_dependencies || return 1
    
    # Create temporary directory
    PARALLEL_JOB_DIR=$(mktemp -d /tmp/aeon_parallel_XXXXXX)
    
    mkdir -p "${PARALLEL_JOB_DIR}/jobs"
    mkdir -p "${PARALLEL_JOB_DIR}/results"
    mkdir -p "${PARALLEL_JOB_DIR}/errors"
    mkdir -p "${PARALLEL_JOB_DIR}/progress"
    
    parallel_log SUCCESS "Parallel execution initialized: ${PARALLEL_JOB_DIR}"
    
    # Set cleanup trap
    trap parallel_cleanup EXIT INT TERM
    
    return 0
}

parallel_ssh_exec() {
    local ip="$1"
    local user="$2"
    local password="$3"
    local command="$4"
    local timeout="${5:-$PARALLEL_SSH_TIMEOUT}"
    
    local output_file="${PARALLEL_JOB_DIR}/results/${ip}.out"
    local error_file="${PARALLEL_JOB_DIR}/errors/${ip}.err"
    local status_file="${PARALLEL_JOB_DIR}/progress/${ip}.status"
    
    # Record start time
    echo "$(date +%s)" > "${PARALLEL_JOB_DIR}/jobs/${ip}.start"
    echo "running" > "$status_file"
    
    # Execute with timeout and retry logic
    local attempt=1
    local success=false
    
    while [[ $attempt -le $PARALLEL_RETRY_COUNT ]] && [[ "$success" == "false" ]]; do
        parallel_log DEBUG "[$ip] Attempt $attempt/$PARALLEL_RETRY_COUNT"
        
        # Execute SSH command
        if timeout "$timeout" sshpass -p "$password" ssh \
            -o StrictHostKeyChecking=no \
            -o ConnectTimeout=10 \
            -o ServerAliveInterval=5 \
            -o ServerAliveCountMax=3 \
            -o BatchMode=no \
            "${user}@${ip}" \
            "$command" > "$output_file" 2> "$error_file"; then
            
            success=true
            echo "success" > "$status_file"
            echo "0" > "${PARALLEL_JOB_DIR}/jobs/${ip}.exit"
            parallel_log DEBUG "[$ip] Command succeeded"
        else
            local exit_code=$?
            echo "$exit_code" > "${PARALLEL_JOB_DIR}/jobs/${ip}.exit"
            
            if [[ $attempt -lt $PARALLEL_RETRY_COUNT ]]; then
                parallel_log WARN "[$ip] Attempt $attempt failed (exit: $exit_code), retrying in ${PARALLEL_RETRY_DELAY}s..."
                sleep "$PARALLEL_RETRY_DELAY"
                ((attempt++))
            else
                echo "failed" > "$status_file"
                parallel_log ERROR "[$ip] All attempts failed (exit: $exit_code)"
            fi
        fi
    done
    
    # Record end time
    echo "$(date +%s)" > "${PARALLEL_JOB_DIR}/jobs/${ip}.end"
    
    return 0
}

parallel_exec() {
    local devices_ref="$1[@]"
    local devices=("${!devices_ref}")
    local command="$2"
    local description="${3:-Executing command}"
    
    if [[ ${#devices[@]} -eq 0 ]]; then
        parallel_log ERROR "No devices provided"
        return 1
    fi
    
    parallel_log INFO "Starting parallel execution on ${#devices[@]} device(s)"
    parallel_log INFO "Command: $command"
    
    echo ""
    echo -e "${PARALLEL_BOLD}${description}${PARALLEL_NC}"
    echo ""
    
    # Clear previous job tracking
    PARALLEL_JOBS=()
    PARALLEL_JOB_STATUS=()
    PARALLEL_JOB_START=()
    PARALLEL_JOB_END=()
    
    # Start jobs
    local active_jobs=0
    local device_index=0
    local total_devices=${#devices[@]}
    
    for device in "${devices[@]}"; do
        # Parse device string: ip:user:password
        IFS=':' read -r ip user password <<< "$device"
        
        # Wait if max jobs reached
        while [[ $active_jobs -ge $PARALLEL_MAX_JOBS ]]; do
            sleep 0.5
            active_jobs=$(jobs -r | wc -l)
        done
        
        # Start background job
        parallel_ssh_exec "$ip" "$user" "$password" "$command" &
        local pid=$!
        
        PARALLEL_JOBS[$pid]="$ip"
        PARALLEL_JOB_STATUS[$ip]="running"
        PARALLEL_JOB_START[$ip]=$(date +%s)
        
        parallel_log DEBUG "Started job for $ip (PID: $pid)"
        
        ((active_jobs++))
        ((device_index++))
    done
    
    # Monitor progress
    parallel_monitor_jobs "${devices[@]}"
    
    # Wait for all jobs to complete
    wait
    
    echo ""
    parallel_log SUCCESS "All parallel executions complete"
    
    return 0
}

parallel_monitor_jobs() {
    local devices=("$@")
    local total_devices=${#devices[@]}
    
    # Get terminal width for dynamic progress bar
    local term_width=$(tput cols 2>/dev/null || echo 80)
    local bar_width=$((term_width - 60))
    [[ $bar_width -lt 20 ]] && bar_width=20
    
    local completed=0
    local start_time=$(date +%s)
    
    while [[ $completed -lt $total_devices ]]; do
        # Clear screen area (move cursor up)
        for i in $(seq 1 $((total_devices + 3))); do
            echo -ne "\033[1A\033[2K"
        done
        
        completed=0
        
        # Display progress for each device
        for device in "${devices[@]}"; do
            IFS=':' read -r ip user password <<< "$device"
            
            local status_file="${PARALLEL_JOB_DIR}/progress/${ip}.status"
            local status="pending"
            
            if [[ -f "$status_file" ]]; then
                status=$(cat "$status_file")
            fi
            
            # Determine progress
            local progress_percent=0
            local status_icon="⏳"
            local status_text="Waiting..."
            local status_color="${PARALLEL_CYAN}"
            
            case "$status" in
                running)
                    progress_percent=50
                    status_icon="⚙️"
                    status_text="Running..."
                    status_color="${PARALLEL_BLUE}"
                    ;;
                success)
                    progress_percent=100
                    status_icon="✓"
                    status_text="Complete"
                    status_color="${PARALLEL_GREEN}"
                    ((completed++))
                    ;;
                failed)
                    progress_percent=100
                    status_icon="✗"
                    status_text="Failed"
                    status_color="${PARALLEL_RED}"
                    ((completed++))
                    ;;
            esac
            
            # Calculate duration
            local duration_text=""
            if [[ -f "${PARALLEL_JOB_DIR}/jobs/${ip}.start" ]]; then
                local job_start=$(cat "${PARALLEL_JOB_DIR}/jobs/${ip}.start")
                local current_time=$(date +%s)
                
                if [[ -f "${PARALLEL_JOB_DIR}/jobs/${ip}.end" ]]; then
                    local job_end=$(cat "${PARALLEL_JOB_DIR}/jobs/${ip}.end")
                    local duration=$((job_end - job_start))
                else
                    local duration=$((current_time - job_start))
                fi
                
                duration_text=" ($(parallel_format_duration $duration))"
            fi
            
            # Create progress bar
            local bar=$(parallel_create_progress_bar $progress_percent 100 $bar_width)
            
            # Display line
            printf "${status_color}%-15s${PARALLEL_NC} %s ${status_color}%s${PARALLEL_NC}%s\n" \
                "$ip" "$bar" "$status_text" "$duration_text"
        done
        
        # Overall progress
        echo ""
        local overall_percent=$((completed * 100 / total_devices))
        local overall_bar=$(parallel_create_progress_bar $completed $total_devices $bar_width)
        
        local elapsed=$(($(date +%s) - start_time))
        local elapsed_text=$(parallel_format_duration $elapsed)
        
        # Estimate time remaining
        local eta_text="calculating..."
        if [[ $completed -gt 0 ]]; then
            local avg_time_per_device=$((elapsed / completed))
            local remaining=$((total_devices - completed))
            local eta=$((avg_time_per_device * remaining))
            eta_text=$(parallel_format_duration $eta)
        fi
        
        printf "${PARALLEL_BOLD}Overall:${PARALLEL_NC} %s ${PARALLEL_BOLD}[%d/%d]${PARALLEL_NC} | Elapsed: %s | ETA: %s\n" \
            "$overall_bar" "$completed" "$total_devices" "$elapsed_text" "$eta_text"
        
        echo ""
        
        # Sleep before next update (unless all complete)
        if [[ $completed -lt $total_devices ]]; then
            sleep 0.5
        fi
    done
}

parallel_file_transfer() {
    local devices_ref="$1[@]"
    local devices=("${!devices_ref}")
    local local_file="$2"
    local remote_path="$3"
    
    if [[ ! -f "$local_file" ]]; then
        parallel_log ERROR "Local file not found: $local_file"
        return 1
    fi
    
    parallel_log INFO "Transferring file to ${#devices[@]} device(s)"
    parallel_log INFO "Source: $local_file"
    parallel_log INFO "Destination: $remote_path"
    
    echo ""
    echo -e "${PARALLEL_BOLD}Transferring files...${PARALLEL_NC}"
    echo ""
    
    # Transfer to each device in parallel
    for device in "${devices[@]}"; do
        IFS=':' read -r ip user password <<< "$device"
        
        (
            local status_file="${PARALLEL_JOB_DIR}/progress/${ip}.status"
            echo "running" > "$status_file"
            
            if sshpass -p "$password" scp \
                -o StrictHostKeyChecking=no \
                -o ConnectTimeout=10 \
                "$local_file" \
                "${user}@${ip}:${remote_path}" &>/dev/null; then
                
                echo "success" > "$status_file"
                parallel_log DEBUG "[$ip] File transferred successfully"
            else
                echo "failed" > "$status_file"
                parallel_log ERROR "[$ip] File transfer failed"
            fi
        ) &
    done
    
    # Monitor transfers
    parallel_monitor_jobs "${devices[@]}"
    
    wait
    
    parallel_log SUCCESS "File transfer complete"
    return 0
}

parallel_wait_online() {
    local devices_ref="$1[@]"
    local devices=("${!devices_ref}")
    local timeout="${2:-300}"
    
    parallel_log INFO "Waiting for ${#devices[@]} device(s) to come online (timeout: ${timeout}s)"
    
    echo ""
    echo -e "${PARALLEL_BOLD}Waiting for devices to come back online...${PARALLEL_NC}"
    echo ""
    
    local start_time=$(date +%s)
    local all_online=false
    
    declare -A device_online
    declare -A device_online_time
    
    # Initialize tracking
    for device in "${devices[@]}"; do
        IFS=':' read -r ip user password <<< "$device"
        device_online[$ip]="false"
    done
    
    while [[ "$all_online" == "false" ]]; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        # Check timeout
        if [[ $elapsed -ge $timeout ]]; then
            parallel_log ERROR "Timeout waiting for devices to come online"
            
            # List devices still offline
            for ip in "${!device_online[@]}"; do
                if [[ "${device_online[$ip]}" == "false" ]]; then
                    parallel_log ERROR "  ✗ $ip - Still offline"
                fi
            done
            
            return 1
        fi
        
        # Clear screen
        for device in "${devices[@]}"; do
            echo -ne "\033[1A\033[2K"
        done
        echo -ne "\033[1A\033[2K"
        echo -ne "\033[1A\033[2K"
        echo -ne "\033[1A\033[2K"
        
        # Check each device
        local online_count=0
        for device in "${devices[@]}"; do
            IFS=':' read -r ip user password <<< "$device"
            
            if [[ "${device_online[$ip]}" == "true" ]]; then
                ((online_count++))
                local online_duration=$((current_time - device_online_time[$ip]))
                printf "${PARALLEL_GREEN}✓ %-15s - Online (%s)${PARALLEL_NC}\n" \
                    "$ip" "$(parallel_format_duration $online_duration)"
            else
                # Test SSH connection
                if timeout 5 sshpass -p "$password" ssh \
                    -o StrictHostKeyChecking=no \
                    -o ConnectTimeout=5 \
                    -o BatchMode=no \
                    "${user}@${ip}" \
                    "echo ok" &>/dev/null; then
                    
                    device_online[$ip]="true"
                    device_online_time[$ip]=$current_time
                    ((online_count++))
                    
                    parallel_log SUCCESS "$ip is back online"
                    printf "${PARALLEL_GREEN}✓ %-15s - Online (just now)${PARALLEL_NC}\n" "$ip"
                else
                    printf "${PARALLEL_CYAN}⏳ %-15s - Waiting... (%s)${PARALLEL_NC}\n" \
                        "$ip" "$(parallel_format_duration $elapsed)"
                fi
            fi
        done
        
        # Overall progress
        echo ""
        local remaining=$((timeout - elapsed))
        printf "${PARALLEL_BOLD}[%d/%d] devices online${PARALLEL_NC} | Elapsed: %s | Timeout in: %s\n" \
            "$online_count" "${#devices[@]}" \
            "$(parallel_format_duration $elapsed)" \
            "$(parallel_format_duration $remaining)"
        echo ""
        
        # Check if all online
        if [[ $online_count -eq ${#devices[@]} ]]; then
            all_online=true
            parallel_log SUCCESS "All devices are online!"
        else
            sleep 2
        fi
    done
    
    return 0
}

parallel_collect_results() {
    local output_file="${PARALLEL_JOB_DIR}/results_summary.json"
    
    parallel_log INFO "Collecting results from all devices..."
    
    # Initialize JSON
    echo "{" > "$output_file"
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"," >> "$output_file"
    echo "  \"total_devices\": 0," >> "$output_file"
    echo "  \"successful\": 0," >> "$output_file"
    echo "  \"failed\": 0," >> "$output_file"
    echo "  \"success_rate\": 0.0," >> "$output_file"
    echo "  \"devices\": [" >> "$output_file"
    
    local total=0
    local successful=0
    local failed=0
    local first=true
    
    # Collect results from each device
    for status_file in "${PARALLEL_JOB_DIR}/progress/"*.status; do
        [[ ! -f "$status_file" ]] && continue
        
        local ip=$(basename "$status_file" .status)
        local status=$(cat "$status_file")
        
        # Get timing info
        local start_time=0
        local end_time=0
        local duration=0
        
        if [[ -f "${PARALLEL_JOB_DIR}/jobs/${ip}.start" ]]; then
            start_time=$(cat "${PARALLEL_JOB_DIR}/jobs/${ip}.start")
        fi
        
        if [[ -f "${PARALLEL_JOB_DIR}/jobs/${ip}.end" ]]; then
            end_time=$(cat "${PARALLEL_JOB_DIR}/jobs/${ip}.end")
            duration=$((end_time - start_time))
        fi
        
        # Get output and error
        local output=""
        local error=""
        local exit_code=0
        
        if [[ -f "${PARALLEL_JOB_DIR}/results/${ip}.out" ]]; then
            output=$(cat "${PARALLEL_JOB_DIR}/results/${ip}.out" | sed 's/"/\\"/g' | tr '\n' ' ')
        fi
        
        if [[ -f "${PARALLEL_JOB_DIR}/errors/${ip}.err" ]]; then
            error=$(cat "${PARALLEL_JOB_DIR}/errors/${ip}.err" | sed 's/"/\\"/g' | tr '\n' ' ')
        fi
        
        if [[ -f "${PARALLEL_JOB_DIR}/jobs/${ip}.exit" ]]; then
            exit_code=$(cat "${PARALLEL_JOB_DIR}/jobs/${ip}.exit")
        fi
        
        # Count stats
        ((total++))
        if [[ "$status" == "success" ]]; then
            ((successful++))
        else
            ((failed++))
        fi
        
        # Add comma between entries
        [[ "$first" == "false" ]] && echo "," >> "$output_file"
        first=false
        
        # Write device entry
        cat >> "$output_file" << JSON
    {
      "ip": "$ip",
      "status": "$status",
      "duration_seconds": $duration,
      "exit_code": $exit_code,
      "output": "$output",
      "error": "$error"
    }
JSON
    done
    
    # Close devices array
    echo "  ]" >> "$output_file"
    echo "}" >> "$output_file"
    
    # Calculate success rate
    local success_rate=0
    if [[ $total -gt 0 ]]; then
        success_rate=$(echo "scale=2; $successful * 100 / $total" | bc)
    fi
    
    # Update summary stats
    sed -i "s/\"total_devices\": 0/\"total_devices\": $total/" "$output_file"
    sed -i "s/\"successful\": 0/\"successful\": $successful/" "$output_file"
    sed -i "s/\"failed\": 0/\"failed\": $failed/" "$output_file"
    sed -i "s/\"success_rate\": 0.0/\"success_rate\": $success_rate/" "$output_file"
    
    # Output summary
    echo ""
    echo -e "${PARALLEL_BOLD}═══════════════════════════════════════════════${PARALLEL_NC}"
    echo -e "${PARALLEL_BOLD}Results Summary${PARALLEL_NC}"
    echo -e "${PARALLEL_BOLD}═══════════════════════════════════════════════${PARALLEL_NC}"
    echo ""
    echo -e "  Total devices: ${PARALLEL_BOLD}$total${PARALLEL_NC}"
    echo -e "  Successful: ${PARALLEL_GREEN}${PARALLEL_BOLD}$successful${PARALLEL_NC}"
    echo -e "  Failed: ${PARALLEL_RED}${PARALLEL_BOLD}$failed${PARALLEL_NC}"
    echo -e "  Success rate: ${PARALLEL_BOLD}${success_rate}%${PARALLEL_NC}"
    echo ""
    
    # Return JSON
    cat "$output_file"
}

parallel_cleanup() {
    if [[ -n "$PARALLEL_JOB_DIR" ]] && [[ -d "$PARALLEL_JOB_DIR" ]]; then
        parallel_log INFO "Cleaning up parallel execution environment..."
        
        # Kill any remaining jobs
        for pid in "${!PARALLEL_JOBS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                parallel_log WARN "Killing lingering job: $pid (${PARALLEL_JOBS[$pid]})"
                kill -9 "$pid" 2>/dev/null || true
            fi
        done
        
        # Archive logs if successful
        if [[ -f "${PARALLEL_JOB_DIR}/results_summary.json" ]]; then
            local archive_dir="/opt/aeon/logs/parallel_$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$archive_dir"
            cp -r "${PARALLEL_JOB_DIR}"/* "$archive_dir/"
            parallel_log INFO "Logs archived to: $archive_dir"
        fi
        
        # Remove temp directory
        rm -rf "$PARALLEL_JOB_DIR"
        
        parallel_log SUCCESS "Cleanup complete"
    fi
}

# ============================================================================
# EXPORT FUNCTIONS
# ============================================================================

export -f parallel_init
export -f parallel_exec
export -f parallel_file_transfer
export -f parallel_wait_online
export -f parallel_collect_results
export -f parallel_cleanup
export -f parallel_log

# ============================================================================
# MODULE LOADED
# ============================================================================

parallel_log DEBUG "Parallel execution module loaded (version 0.1.0)"
