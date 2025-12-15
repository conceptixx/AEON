#!/bin/bash
################################################################################
# AEON Dependency Management System
# File: lib/dependencies.sh
# Version: 0.1.0
#
# Purpose: Centralized dependency loading and management
#
# Usage:
#   source /opt/aeon/lib/dependencies.sh
#   load_dependencies "reboot.sh"
#
# Features:
#   - Centralized dependency declarations
#   - Automatic loading in correct order
#   - Prevents double-loading
#   - Handles absolute paths
#   - Graceful error handling
################################################################################

set -euo pipefail

# ============================================================================
# PREVENT DOUBLE-LOADING
# ============================================================================

[[ -n "${AEON_DEPENDENCIES_LOADED:-}" ]] && return 0
readonly AEON_DEPENDENCIES_LOADED=1

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
LIB_DIR="${LIB_DIR:-/opt/aeon/lib}"

# ============================================================================
# DEPENDENCY MANIFEST
# ============================================================================
#
# This is the SINGLE SOURCE OF TRUTH for all module dependencies
# Format: ["module"]="dep1 dep2 dep3"
#
# NOTE: Dependencies are loaded in the order listed
#

declare -A MODULE_DEPENDENCIES=(
    # Core modules (no dependencies except common.sh)
    ["common.sh"]=""
    ["progress.sh"]="common.sh"
    
    # main installer
    ["aeon_go.sh"]="common.sh progress.sh preflight.sh discovery.sh hardware.sh validation.sh parallel.sh user.sh reboot.sh swarm.sh report.sh"
    
    # Phase modules (orchestrated by aeon-go.sh)
    ["preflight.sh"]="common.sh progress.sh"
    ["discovery.sh"]="common.sh progress.sh"
    ["hardware.sh"]="common.sh progress.sh parallel.sh"
    ["validation.sh"]="common.sh progress.sh"
    ["parallel.sh"]="common.sh"
    ["user.sh"]="common.sh progress.sh parallel.sh"
    ["reboot.sh"]="common.sh progress.sh parallel.sh"
    ["swarm.sh"]="common.sh progress.sh parallel.sh"
    ["report.sh"]="common.sh progress.sh"
)

declare -A MODULES_LOADED=(
    # Core modules (no dependencies except common.sh)
    ["common.sh"]=""
    ["progress.sh"]=""
    
    # main installer
    ["aeon_go.sh"]=""
    
    # Phase modules (orchestrated by aeon-go.sh)
    ["preflight.sh"]=""
    ["discovery.sh"]=""
    ["hardware.sh"]=""
    ["validation.sh"]=""
    ["parallel.sh"]=""
    ["user.sh"]=""
    ["reboot.sh"]=""
    ["swarm.sh"]=""
    ["report.sh"]=""
)
# ============================================================================
# MODULE LOADING FUNCTIONS
# ============================================================================

#
# get_module_name $file_path
# Extracts module name from file path
#
get_module_name() {
    local file_path="$1"
    basename "$file_path"
}

#
# get_load_guard_name $module_name
# Generates the load guard variable name for a module
#
# Example: common.sh → AEON_COMMON_LOADED
#
get_load_guard_name() {
    local module_name="$1"
    local base_name="${module_name%.sh}"  # Remove .sh extension
    local upper_name=$(echo "$base_name" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
    echo "AEON_${upper_name}_LOADED"
}

#
# is_module_loaded $module_name
# Check if a module is already loaded
#
is_module_loaded() {
    local module_name="$1"
    local guard_name=$(get_load_guard_name "$module_name")
    
    [[ -n "${!guard_name:-}" ]]
}

#
# find_module $module_name
# Find the full path to a module file
#
find_module() {
    local module_name="$1"
    
    # Try relative to current script directory
    if [[ -f "$SCRIPT_DIR/$module_name" ]]; then
        echo "$SCRIPT_DIR/$module_name"
        return 0
    fi
    
    # Try in LIB_DIR
    if [[ -f "$LIB_DIR/$module_name" ]]; then
        echo "$LIB_DIR/$module_name"
        return 0
    fi
    
    # Not found
    return 1
}

#
# load_single_module $module_name
# Load a single module file (without dependencies)
#
load_single_module() {
    local module_name="$1"
    
    # Skip if already loaded
    if is_module_loaded "$module_name"; then
        return 0
    fi
    
    # Find module file
    local module_path=$(find_module "$module_name")
    
    if [[ -z "$module_path" ]]; then
        # Before common.sh is loaded, we can't use log()
        if is_module_loaded "common.sh"; then
            log ERROR "Cannot find module: $module_name"
        else
            echo "ERROR: Cannot find module: $module_name" >&2
        fi
        return 1
    fi
    echo "$module_name"
    # Source the module
    source "$module_path" || {
        if is_module_loaded "common.sh"; then
            log ERROR "Failed to source: $module_name"
        else
            echo "ERROR: Failed to source: $module_name" >&2
        fi
        return 1
    }
    
    # Log success (only if common.sh is loaded)
    if is_module_loaded "common.sh"; then
        log_debug "Loaded module: $module_name"
    fi
    
    return 0
}

#
# load_module_with_dependencies $module_name
# Load a module and all its dependencies recursively
#
load_module_with_dependencies() {
    local module_name="$1"
    
    # Skip if already loaded
    if is_module_loaded "$module_name"; then
        return 0
    fi
    
    # Get dependencies for this module
    local deps="${MODULE_DEPENDENCIES[$module_name]:-}"
    
    # Load dependencies first (in order)
    if [[ -n "$deps" ]]; then
        for dep in $deps; do
            load_module_with_dependencies "$dep" || return 1
        done
    fi
    
    # Load the module itself
    load_single_module "$module_name" || return 1

    return 0
}

#
# load_dependencies $requesting_module
# Main entry point - loads all dependencies for a module
#
load_dependencies() {
    local requesting_module="$1"
    
    # Normalize module name (remove path, ensure .sh extension)
    requesting_module=$(get_module_name "$requesting_module")
    [[ "$requesting_module" == *.sh ]] || requesting_module="${requesting_module}.sh"
    
    # Check if module is registered in manifest
    if [[ -z "${MODULE_DEPENDENCIES[$requesting_module]+isset}" ]]; then
        echo "WARNING: Module '$requesting_module' not registered in dependency manifest" >&2
        echo "         Add it to MODULE_DEPENDENCIES in dependencies.sh" >&2
        # Continue anyway, will try to load with no deps
    fi
    
    # Load all dependencies
    load_module_with_dependencies "$requesting_module" || {
        echo "FATAL: Failed to load dependencies for $requesting_module" >&2
        exit 1
    }

    return 0
}

#
# initialize_logging
# Initialize AEON logging system (called after common.sh is loaded)
#
initialize_logging() {
    # Only initialize once
    [[ -n "${AEON_LOGGING_INITIALIZED:-}" ]] && return 0
    readonly AEON_LOGGING_INITIALIZED=1
    
    # Ensure log directory exists
    LOG_FILE="${LOG_FILE:-/opt/aeon/logs/install.log}"
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    
    # Create log header
    {
        echo "═════════════════════════════════════════════════════════"
        echo "AEON Installation Log - $(date)"
        echo "═════════════════════════════════════════════════════════"
        echo ""
    } > "$LOG_FILE" 2>/dev/null || true
    
    return 0
}

#
# load_default_dependencies
# Load common dependencies needed by most modules
#
load_default_dependencies() {
    # Load common.sh first (required for logging)
    load_single_module "common.sh" || {
        echo "FATAL: Cannot load common.sh" >&2
        exit 1
    }
    
    # Initialize logging
    initialize_logging
    
    # Log that dependency system is ready
    log_debug "AEON dependency system initialized"
    
    return 0
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

#
# list_dependencies $module_name
# List all dependencies for a module (for debugging)
#
list_dependencies() {
    local module_name="$1"
    
    # Normalize name
    module_name=$(get_module_name "$module_name")
    [[ "$module_name" == *.sh ]] || module_name="${module_name}.sh"
    
    echo "Dependencies for $module_name:"
    
    local deps="${MODULE_DEPENDENCIES[$module_name]:-}"
    if [[ -z "$deps" ]]; then
        echo "  (none)"
    else
        for dep in $deps; do
            echo "  • $dep"
        done
    fi
}

#
# show_dependency_tree
# Show all registered modules and their dependencies
#
show_dependency_tree() {
    echo "AEON Dependency Tree:"
    echo ""
    
    for module in "${!MODULE_DEPENDENCIES[@]}"; do
        echo "📦 $module"
        local deps="${MODULE_DEPENDENCIES[$module]:-}"
        if [[ -z "$deps" ]]; then
            echo "   └─ (no dependencies)"
        else
            for dep in $deps; do
                echo "   ├─ $dep"
            done
        fi
        echo ""
    done
}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Dependency system is now loaded
# Modules can call: load_dependencies "modulename.sh"

return 0
