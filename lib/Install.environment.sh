INSTALL_ENVIRONMENT_INITIALIZED="${INSTALL_ENVIRONMENT_INITIALIZED:-false}"
[[ "$init_file" == "true" ]] || init_function

install_environment_init() {
    [[ "${INSTALL_ENVIRONMENT_INITIALIZED:-false}" == "true" ]] && return 0
    INSTALL_ENVIRONMENT_INITIALIZED="true"
    
    # ============================================================================
    # CONFIGURATION
    # ============================================================================
    AEON_VERSION="0.1.0"
    AEON_DIR="/opt/aeon"
    DATA_DIR="$AEON_DIR/data"
    LOG_DIR="$AEON_DIR/logs"
    SECRETS_DIR="$AEON_DIR/secrets"
    REPORT_DIR="$AEON_DIR/reports"

    # Default network range
    DEFAULT_NETWORK_RANGE="192.168.1.0/24"

    # ============================================================================
    # MODULE LOADING
    # ============================================================================
    # Set library directory
    LIB_DIR="$AEON_DIR/lib"
    REMOTE_DIR="$AEON_DIR/remote"

# ANSI Color Codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly WHITE='\033[0;37m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly UNDERLINE='\033[4m'
readonly NC='\033[0m'  # No Color / Reset

# Box Drawing Characters (UTF-8)
readonly BOX_H='═'      # Horizontal line
readonly BOX_V='║'      # Vertical line
readonly BOX_TL='╔'     # Top-left corner
readonly BOX_TR='╗'     # Top-right corner
readonly BOX_BL='╚'     # Bottom-left corner
readonly BOX_BR='╝'     # Bottom-right corner
readonly BOX_VL='╠'     # Vertical line with right connection
readonly BOX_VR='╣'     # Vertical line with left connection
readonly BOX_HT='╦'     # Horizontal line with down connection
readonly BOX_HB='╩'     # Horizontal line with up connection
readonly BOX_CROSS='╬'  # Cross

# Single-line box characters (fallback)
readonly SBOX_H='─'
readonly SBOX_V='│'
readonly SBOX_TL='┌'
readonly SBOX_TR='┐'
readonly SBOX_BL='└'
readonly SBOX_BR='┘'

# Emoji/Icons (optional, can be disabled)
readonly ICON_SUCCESS='✅'
readonly ICON_ERROR='❌'
readonly ICON_WARNING='⚠️ '
readonly ICON_INFO='ℹ️ '
readonly ICON_STEP='▶'
readonly ICON_BULLET='•'
readonly ICON_MANAGER='🔷'
readonly ICON_WORKER='🔶'
readonly ICON_LEADER='⭐'
    
    SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
LIB_DIR="${LIB_DIR:-/opt/aeon/lib}"

DISCOVERY_TIMEOUT=300              # Max time for discovery (5 min)
PING_TIMEOUT=1                     # Ping timeout per host
SSH_TIMEOUT=5                      # SSH connection timeout
SSH_RETRIES=2                      # SSH retry attempts
PARALLEL_SCAN_JOBS=50              # Parallel ping jobs

# Common SSH users to try
DEFAULT_SSH_USERS=("pi" "ubuntu" "aeon-llm" "aeon-host" "aeon")

# Global arrays
DISCOVERED_IPS=()
ACCESSIBLE_DEVICES=()


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
readonly MODULE_DEPENDENCIES

}