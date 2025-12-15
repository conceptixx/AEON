#!/bin/bash
################################################################################
# AEON Progress Bar Module
# File: lib/progress.sh
# Version: 0.1.0
#
# Purpose: Professional installation progress tracking with dynamic terminal
#          sizing and clean, centered output.
#
# Features:
#   - Dynamic terminal sizing (adapts to 80x24 or larger)
#   - Centered AEON logo
#   - Live progress bars with smooth updates
#   - Silent background operations (all logs to file)
#   - Professional status indicators
################################################################################

set -euo pipefail

# ============================================================================
# DEPENDENCIES
# ============================================================================

# Prevent double-loading
[[ -n "${AEON_PROGRESS_LOADED:-}" ]] && return 0
readonly AEON_PROGRESS_LOADED=1

# Load dependencies
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
if [[ -z "${AEON_DEPENDENCIES_LOADED:-}" ]]; then
    source "$SCRIPT_DIR/dependencies.sh" || source "/opt/aeon/lib/dependencies.sh" || {
        echo "ERROR: Cannot find dependencies.sh" >&2
        exit 1
    }
fi

# load dependecies -if available
load_dependencies "progress.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

PROGRESS_FILE="/tmp/aeon_progress_${$}.tmp"
LOG_FILE="${LOG_FILE:-/opt/aeon/logs/install.log}"

# Phase configuration
TOTAL_PHASES=10
CURRENT_PHASE=0

# Phase weights (must sum to 100)
declare -a PHASE_WEIGHTS=(10 15 10 5 10 20 10 5 10 5)

# Phase names
declare -a PHASE_NAMES=(
    "Pre-flight Checks"
    "Network Discovery"
    "Hardware Detection"
    "Role Assignment"
    "Validation"
    "Dependencies Installation"
    "User Creation"
    "System Reboot"
    "Swarm Setup"
    "Report Generation"
)

# Phase status tracking
declare -a PHASE_STATUS=()
declare -a PHASE_DETAILS=()

# Terminal state
TERM_WIDTH=80
TERM_HEIGHT=24
LOGO_START_LINE=0
PROGRESS_START_LINE=0

# ============================================================================
# TERMINAL MANAGEMENT
# ============================================================================

#
# get_terminal_size
# Detects current terminal dimensions
#
get_terminal_size() {
    if command -v tput &>/dev/null; then
        TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)
        TERM_HEIGHT=$(tput lines 2>/dev/null || echo 24)
    else
        # Fallback to stty if tput not available
        local size=$(stty size 2>/dev/null || echo "24 80")
        TERM_HEIGHT=$(echo "$size" | awk '{print $1}')
        TERM_WIDTH=$(echo "$size" | awk '{print $2}')
    fi
    
    # Minimum terminal size
    [[ $TERM_WIDTH -lt 80 ]] && TERM_WIDTH=80
    [[ $TERM_HEIGHT -lt 24 ]] && TERM_HEIGHT=24
}

#
# center_text $text
# Centers text based on terminal width
#
center_text() {
    local text="$1"
    local text_length=${#text}
    local padding=$(( (TERM_WIDTH - text_length) / 2 ))
    
    printf "%${padding}s%s\n" "" "$text"
}

#
# draw_line $char
# Draws a horizontal line across terminal width
#
draw_line() {
    local char="${1:-═}"
    printf "%${TERM_WIDTH}s\n" | tr ' ' "$char"
}

# ============================================================================
# LOGO DISPLAY
# ============================================================================

#
# show_centered_logo
# Displays AEON logo centered on screen
#
show_centered_logo() {
    local logo_lines=(
        "   █████╗  ███████╗  ██████╗  ███╗   ██╗ "
        "  ██╔══██╗ ██╔════╝ ██╔═══██╗ ████╗  ██║ "
        "  ███████║ █████╗   ██║   ██║ ██╔██╗ ██║ "
        "  ██╔══██║ ██╔══╝   ██║   ██║ ██║╚██╗██║ "
        "  ██║  ██║ ███████╗ ╚██████╔╝ ██║ ╚████║ "
        "  ╚═╝  ╚═╝ ╚══════╝  ╚═════╝  ╚═╝  ╚═══╝ "
        ""
        "Autonomous Evolving Orchestration Network"
    )
    
    for line in "${logo_lines[@]}"; do
        center_text "$line"
    done
    
    echo ""
}

# ============================================================================
# PROGRESS BAR DRAWING
# ============================================================================

#
# draw_progress_bar $percent $width
# Draws a progress bar with given percentage and width
#
draw_progress_bar() {
    local percent=$1
    local width=${2:-40}
    
    # Calculate filled and empty portions
    local filled=$((percent * width / 100))
    local empty=$((width - filled))
    
    # Ensure non-negative values
    [[ $filled -lt 0 ]] && filled=0
    [[ $empty -lt 0 ]] && empty=0
    
    # Draw bar
    printf "["
    [[ $filled -gt 0 ]] && printf "%${filled}s" | tr ' ' '█'
    [[ $empty -gt 0 ]] && printf "%${empty}s" | tr ' ' '░'
    printf "] %3d%%" "$percent"
}

#
# calculate_bar_width
# Calculates optimal progress bar width based on terminal size
#
calculate_bar_width() {
    local available_width=$((TERM_WIDTH - 50))  # Reserve 50 chars for labels
    local min_width=30
    local max_width=50
    
    if [[ $available_width -lt $min_width ]]; then
        echo "$min_width"
    elif [[ $available_width -gt $max_width ]]; then
        echo "$max_width"
    else
        echo "$available_width"
    fi
}

# ============================================================================
# PROGRESS CALCULATION
# ============================================================================

#
# calculate_total_progress
# Calculates overall installation progress (0-100)
#
calculate_total_progress() {
    local total=0
    
    # Sum completed phases
    for i in $(seq 0 $((CURRENT_PHASE - 1))); do
        total=$((total + ${PHASE_WEIGHTS[$i]}))
    done
    
    # Add current phase weighted progress
    if [[ $CURRENT_PHASE -lt $TOTAL_PHASES ]]; then
        if [[ -f "$PROGRESS_FILE" ]]; then
            local phase_progress=$(cat "$PROGRESS_FILE" 2>/dev/null || echo "0")
            local weighted=$((${PHASE_WEIGHTS[$CURRENT_PHASE]} * phase_progress / 100))
            total=$((total + weighted))
        fi
    fi
    
    echo "$total"
}

# ============================================================================
# DISPLAY FUNCTIONS
# ============================================================================

#
# init_progress
# Initializes progress tracking and displays initial screen
#
init_progress() {
    # Detect terminal size
    get_terminal_size
    
    # Initialize phase status
    for i in $(seq 0 $((TOTAL_PHASES - 1))); do
        PHASE_STATUS[$i]="pending"
        PHASE_DETAILS[$i]=""
    done
    
    # Create progress file
    echo "0" > "$PROGRESS_FILE"
    
    # Setup terminal
    clear
    tput civis 2>/dev/null || true  # Hide cursor
    
    # Calculate layout
    LOGO_START_LINE=2
    PROGRESS_START_LINE=13
    
    # Draw initial screen
    show_centered_logo
    draw_line "═"
    center_text "Installation Progress"
    draw_line "═"
    echo ""
    
    # Show initial progress
    refresh_progress_display
}

#
# refresh_progress_display
# Redraws the entire progress display
#
refresh_progress_display() {
    local bar_width=$(calculate_bar_width)
    
    # Move cursor to progress area
    tput cup $PROGRESS_START_LINE 0 2>/dev/null || true
    
    # Clear from cursor to end of screen
    tput ed 2>/dev/null || true
    
    # Total progress bar
    local total_percent=$(calculate_total_progress)
    local total_line="Total: $(draw_progress_bar $total_percent $bar_width)"
    center_text "$total_line"
    echo ""
    
    # Individual phases
    for i in $(seq 0 $((TOTAL_PHASES - 1))); do
        local phase_num=$((i + 1))
        local phase_name="${PHASE_NAMES[$i]}"
        local status="${PHASE_STATUS[$i]}"
        local detail="${PHASE_DETAILS[$i]}"
        
        local line=""
        
        case "$status" in
            pending)
                line=$(printf "Phase %2d: %-32s [░░░░░░░░░░░░░░░░░░░░]   0%%" \
                    "$phase_num" "$phase_name")
                ;;
            running)
                if [[ -f "$PROGRESS_FILE" ]]; then
                    local percent=$(cat "$PROGRESS_FILE" 2>/dev/null || echo "0")
                    line=$(printf "Phase %2d: %-32s " "$phase_num" "$phase_name")
                    line+=$(draw_progress_bar "$percent" 20)
                else
                    line=$(printf "Phase %2d: %-32s [░░░░░░░░░░░░░░░░░░░░]   0%%" \
                        "$phase_num" "$phase_name")
                fi
                ;;
            completed)
                if [[ -n "$detail" ]]; then
                    line=$(printf "Phase %2d: %-32s ✓ Completed (%s)" \
                        "$phase_num" "$phase_name" "$detail")
                else
                    line=$(printf "Phase %2d: %-32s ✓ Completed" \
                        "$phase_num" "$phase_name")
                fi
                ;;
            completed_warnings)
                if [[ -n "$detail" ]]; then
                    line=$(printf "Phase %2d: %-32s ⚠ Completed with warnings (%s)" \
                        "$phase_num" "$phase_name" "$detail")
                else
                    line=$(printf "Phase %2d: %-32s ⚠ Completed with warnings" \
                        "$phase_num" "$phase_name")
                fi
                ;;
            skipped)
                if [[ -n "$detail" ]]; then
                    line=$(printf "Phase %2d: %-32s ⊙ Skipped (%s)" \
                        "$phase_num" "$phase_name" "$detail")
                else
                    line=$(printf "Phase %2d: %-32s ⊙ Skipped" \
                        "$phase_num" "$phase_name")
                fi
                ;;
            failed)
                if [[ -n "$detail" ]]; then
                    line=$(printf "Phase %2d: %-32s ✗ Failed (%s)" \
                        "$phase_num" "$phase_name" "$detail")
                else
                    line=$(printf "Phase %2d: %-32s ✗ Failed" \
                        "$phase_num" "$phase_name")
                fi
                ;;
        esac
        
        # Center or left-align based on terminal width
        if [[ $TERM_WIDTH -ge 100 ]]; then
            center_text "$line"
        else
            echo "$line"
        fi
    done
    
    echo ""
}

# ============================================================================
# PHASE CONTROL
# ============================================================================

#
# start_phase $phase_number
# Starts a new installation phase
#
start_phase() {
    local phase_number=$1
    
    CURRENT_PHASE=$((phase_number - 1))
    PHASE_STATUS[$CURRENT_PHASE]="running"
    echo "0" > "$PROGRESS_FILE"
    
    # Log to file
    log_to_file "═══════════════════════════════════════════════════════════"
    log_to_file "Phase $phase_number: ${PHASE_NAMES[$CURRENT_PHASE]}"
    log_to_file "═══════════════════════════════════════════════════════════"
    
    refresh_progress_display
}

#
# update_phase_progress $percent
# Updates current phase progress (0-100)
#
update_phase_progress() {
    local percent=$1
    
    # Clamp to 0-100
    [[ $percent -lt 0 ]] && percent=0
    [[ $percent -gt 100 ]] && percent=100
    
    echo "$percent" > "$PROGRESS_FILE"
    refresh_progress_display
}

#
# complete_phase $status $detail
# Completes current phase with status
#
complete_phase() {
    local status="${1:-completed}"
    local detail="${2:-}"
    
    PHASE_STATUS[$CURRENT_PHASE]="$status"
    PHASE_DETAILS[$CURRENT_PHASE]="$detail"
    echo "100" > "$PROGRESS_FILE"
    
    log_to_file "Phase completed: $status"
    if [[ -n "$detail" ]]; then
        log_to_file "Details: $detail"
    fi
    log_to_file ""
    
    refresh_progress_display
    
    # Move to next phase
    CURRENT_PHASE=$((CURRENT_PHASE + 1))
}

# ============================================================================
# COMPLETION
# ============================================================================

#
# show_completion_summary
# Shows final installation summary
#
show_completion_summary() {
    # Move cursor below progress bars
    local summary_line=$((PROGRESS_START_LINE + TOTAL_PHASES + 5))
    tput cup $summary_line 0 2>/dev/null || true
    
    draw_line "═"
    center_text "Installation Complete"
    draw_line "═"
    echo ""
    
    # Count results
    local completed=0
    local warnings=0
    local failed=0
    local skipped=0
    
    for status in "${PHASE_STATUS[@]}"; do
        case "$status" in
            completed) ((completed++)) ;;
            completed_warnings) ((warnings++)) ;;
            failed) ((failed++)) ;;
            skipped) ((skipped++)) ;;
        esac
    done
    
    # Show summary
    center_text "Summary:"
    center_text "  ✓ $completed phases completed successfully"
    [[ $warnings -gt 0 ]] && center_text "  ⚠ $warnings phases completed with warnings"
    [[ $skipped -gt 0 ]] && center_text "  ⊙ $skipped phases skipped"
    [[ $failed -gt 0 ]] && center_text "  ✗ $failed phases failed"
    echo ""
    
    center_text "Installation log: $LOG_FILE"
    echo ""
    
    # Show cursor again
    tput cnorm 2>/dev/null || true
}

# ============================================================================
# CLEANUP
# ============================================================================

#
# cleanup_progress
# Cleans up temporary files and restores terminal
#
cleanup_progress() {
    rm -f "$PROGRESS_FILE"
    tput cnorm 2>/dev/null || true  # Show cursor
}

# ============================================================================
# LOGGING HELPERS
# ============================================================================

#
# log_to_file $message
# Logs message to installation log file
#
log_to_file() {
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$LOG_FILE"
}

#
# silent_exec $command
# Executes command silently, logging output to file
#
silent_exec() {
    local description="$1"
    shift
    
    log_to_file "Executing: $description"
    log_to_file "Command: $*"
    
    if "$@" >> "$LOG_FILE" 2>&1; then
        log_to_file "Success: $description"
        return 0
    else
        local exit_code=$?
        log_to_file "Failed: $description (exit code: $exit_code)"
        return $exit_code
    fi
}

# ============================================================================
# EXPORT FUNCTIONS
# ============================================================================

export -f init_progress
export -f start_phase
export -f update_phase_progress
export -f complete_phase
export -f show_completion_summary
export -f cleanup_progress
export -f log_to_file
export -f silent_exec
export -f refresh_progress_display

# ============================================================================
# SIGNAL HANDLERS
# ============================================================================

# Cleanup on exit
trap cleanup_progress EXIT INT TERM
