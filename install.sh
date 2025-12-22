#!/usr/bin/env bash
################################################################################
# AEON Bootstrap Installer
################################################################################
# Description:
#   This is the minimal bootstrap script that detects the target OS and
#   delegates the actual installation to the appropriate platform-specific
#   installer (install.bash.sh for Unix-like systems, install.pwrshl.ps1 for
#   Windows PowerShell).
#
# Purpose:
#   - Detect operating system (Linux/macOS/Windows)
#   - Ensure download tools (curl/wget) are available
#   - Download and execute the appropriate platform-specific installer
#   - Handle Windows by delegating to WSL (Windows Subsystem for Linux)
#
# Usage:
#   ./install.sh [OPTIONS]
#
# Options:
#   -c, --cli-enable, --enable-cli     Enable CLI mode
#   -w, --web-enable, --enable-web     Enable Web mode
#   -n, --noninteractive               Run in silent/non-interactive mode
#
# Exit Codes:
#   0  - Success
#   1  - Runtime error (missing tools, network failure, etc.)
#   2  - Invalid arguments
#
# Requirements:
#   - Bash 3.2 or higher
#   - Internet connectivity
#   - curl or wget (will attempt auto-install if missing)
#   - sudo privileges (for system modifications)
#
# Author: AEON Project
# Version: 1.0.0
################################################################################

# Enable strict error handling:
# - Exit on any command failure (set -e)
set -e

################################################################################
# CONFIGURATION CONSTANTS
################################################################################

# Base URL for downloading installer scripts from GitHub repository
AEON_RAW_BASE_URL="https://raw.githubusercontent.com/conceptixx/AEON/main"

# Working directory where AEON will be installed
# Linux/WSL: /opt/aeon
# macOS: /usr/local/aeon
AEON_WORKING_DIR="/opt/aeon"

# Temporary directory for downloaded installer scripts
# Will be set based on AEON_WORKING_DIR
AEON_TARGET_DIR=""

# Name of the bash installer script for Unix-like systems
AEON_BASH_FILE="install.bash.sh"

# Name of the PowerShell installer script for Windows
# (Currently not used in this version, reserved for future Windows support)
AEON_PWSH_FILE="install.pwrshl.ps1"

# Flag to track if non-interactive mode is enabled
# 0 = interactive (default), 1 = non-interactive/silent
AEON_FLAG_N=0

# Array to store normalized/validated command-line flags
NORMALIZED_FLAGS=()

################################################################################
# FLAG NORMALIZATION FUNCTION
################################################################################
# Purpose:
#   Converts various flag formats to a standardized internal representation.
#   This allows users to use different variations of the same flag
#   (e.g., -c, --cli-enable, --enable-cli all map to --enable-cli).
#
# Arguments:
#   $1 - The flag to normalize
#
# Returns:
#   Echoes the normalized flag string, or empty string if invalid
#
# Side Effects:
#   Sets AEON_FLAG_N=1 if noninteractive flag is detected
################################################################################
normalize_flag() {
    local flag="$1"
    local lower_flag
    
    # Convert flag to lowercase for case-insensitive comparison
    # Using printf instead of echo for better portability and to avoid
    # potential issues with strings that begin with '-' or contain backslashes
    lower_flag=$(printf '%s' "$flag" | tr '[:upper:]' '[:lower:]')
    
    # Map various flag formats to standardized versions
    case "$lower_flag" in
        # CLI mode flags - all map to --enable-cli
        -c|--cli-enable|--enable-cli)
            echo "--enable-cli"
            ;;
        # Web mode flags - all map to --enable-web
        -w|--web-enable|--enable-web)
            echo "--enable-web"
            ;;
        # Non-interactive mode flags - all map to --noninteractive
        # Also sets the global AEON_FLAG_N variable for immediate effect
        -n|--noninteractive)
            AEON_FLAG_N=1
            echo "--noninteractive"
            ;;
        # Invalid flag - return empty string
        *)
            echo ""
            ;;
    esac
}

################################################################################
# FLAG VALIDATION AND PARSING
################################################################################
# Process all command-line arguments through the normalize_flag function
for arg in "$@"; do
    normalized=$(normalize_flag "$arg")
    
    # If normalization returned empty string, flag is invalid
    if [ -z "$normalized" ]; then
        echo "ERROR: Unknown flag: $arg" >&2
        echo "Usage: $0 [-c|--cli-enable] [-w|--web-enable] [-n|--noninteractive]" >&2
        exit 2
    fi
    
    # Add validated flag to array for later passing to installer
    NORMALIZED_FLAGS+=("$normalized")
done

# Enforce maximum of 3 flags (one of each type)
if [ ${#NORMALIZED_FLAGS[@]} -gt 3 ]; then
    echo "ERROR: Maximum 3 flags allowed" >&2
    exit 2
fi

################################################################################
# OPERATING SYSTEM DETECTION
################################################################################
# Purpose:
#   Detect the operating system to determine installation strategy.
#   Uses the OSTYPE environment variable which is set by bash.
#
# Possible values:
#   - linux-gnu*  → Linux
#   - darwin*     → macOS
#   - msys*/mingw*/cygwin* → Windows (Git Bash, MinGW, Cygwin)
#
# Sets:
#   OS_TYPE - "linux", "macos", or "windows"
#   AEON_WORKING_DIR - Adjusted for macOS if needed
################################################################################
OS_TYPE=""
case "$OSTYPE" in
    linux-gnu*)
        OS_TYPE="linux"
        ;;
    darwin*)
        OS_TYPE="macos"
        # macOS uses different standard directory structure
        AEON_WORKING_DIR="/usr/local/aeon"
        ;;
    msys*|mingw*|cygwin*)
        # Windows environments (Git Bash, MSYS2, Cygwin)
        OS_TYPE="windows"
        ;;
    *)
        # Default to linux for unknown systems
        OS_TYPE="linux"
        ;;
esac

# Set target directory for temporary installer files
AEON_TARGET_DIR="${AEON_WORKING_DIR}/tmp"

# Conditional logging based on interactive mode
# (( AEON_FLAG_N )) evaluates to true if AEON_FLAG_N is non-zero
# || prevents exit due to 'set -e' when condition is false
(( AEON_FLAG_N )) || echo "[INFO] Detected OS: $OS_TYPE"

################################################################################
# WINDOWS/WSL HANDLING
################################################################################
# Purpose:
#   Windows systems require special handling. This script delegates to WSL
#   (Windows Subsystem for Linux) for the actual installation, as AEON
#   requires a Unix-like environment.
#
# Process:
#   1. Check if WSL is installed
#   2. If not, attempt automatic installation via PowerShell
#   3. Check if Ubuntu-22.04 distribution is installed
#   4. If not, install Ubuntu-22.04
#   5. Execute the bootstrap process inside WSL
################################################################################
if [ "$OS_TYPE" = "windows" ]; then
    (( AEON_FLAG_N )) || echo "[INFO] Windows environment detected. Delegating to WSL..."
    
    # Check if WSL command is available
    if ! command -v wsl.exe >/dev/null 2>&1; then
        echo "[WARN] WSL not found. Attempting installation..."
        
        # Try to install WSL via PowerShell (requires admin privileges)
        if command -v powershell.exe >/dev/null 2>&1; then
            # Start-Process with -Verb RunAs requests admin elevation
            # wsl --install -d Ubuntu-22.04 installs WSL with Ubuntu 22.04
            powershell.exe -Command "Start-Process powershell -Verb RunAs -ArgumentList '-Command wsl --install -d Ubuntu-22.04'" 2>/dev/null || {
                # If auto-install fails, provide manual instructions
                echo "[ERROR] Could not auto-install WSL. Manual steps required:" >&2
                echo "1. Open PowerShell as Administrator" >&2
                echo "2. Run: wsl --install -d Ubuntu-22.04" >&2
                echo "3. Restart computer if prompted" >&2
                echo "4. Run this script again" >&2
                exit 1
            }
            (( AEON_FLAG_N )) || echo "[INFO] WSL installation initiated. Restart and re-run this script."
            exit 0
        else
            echo "[ERROR] PowerShell not found. Install WSL manually:" >&2
            echo "Open PowerShell as Admin and run: wsl --install -d Ubuntu-22.04" >&2
            exit 1
        fi
    fi
    
    # Verify Ubuntu-22.04 distribution is available in WSL
    if ! wsl.exe -d Ubuntu-22.04 -- bash -c "exit 0" 2>/dev/null; then
        echo "[WARN] Ubuntu-22.04 not available. Attempting installation..."
        
        if command -v powershell.exe >/dev/null 2>&1; then
            powershell.exe -Command "Start-Process powershell -Verb RunAs -ArgumentList '-Command wsl --install -d Ubuntu-22.04'" 2>/dev/null || {
                echo "[ERROR] Failed to install Ubuntu-22.04. Manual steps:" >&2
                echo "Open PowerShell as Admin: wsl --install -d Ubuntu-22.04" >&2
                exit 1
            }
            (( AEON_FLAG_N )) || echo "[INFO] Ubuntu-22.04 installation initiated. Restart and re-run."
            exit 0
        fi
    fi
    
    (( AEON_FLAG_N )) || echo "[INFO] Executing bootstrap in WSL Ubuntu-22.04..."
    
    # Build the command string to execute inside WSL
    # This command will:
    # 1. Check for curl/wget
    # 2. Install curl if needed
    # 3. Download install.bash.sh
    # 4. Execute install.bash.sh with passed flags
    WSL_CMD="set -e; "
    WSL_CMD="${WSL_CMD}echo '[WSL] Checking for downloader...'; "
    WSL_CMD="${WSL_CMD}if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then "
    WSL_CMD="${WSL_CMD}echo '[WSL] Installing curl...'; "
    WSL_CMD="${WSL_CMD}sudo apt-get update -qq && sudo apt-get install -y curl; "
    WSL_CMD="${WSL_CMD}fi; "
    WSL_CMD="${WSL_CMD}if command -v curl >/dev/null 2>&1; then "
    WSL_CMD="${WSL_CMD}DOWNLOADER='curl -fsSL'; "
    WSL_CMD="${WSL_CMD}else "
    WSL_CMD="${WSL_CMD}DOWNLOADER='wget -qO-'; "
    WSL_CMD="${WSL_CMD}fi; "
    WSL_CMD="${WSL_CMD}echo '[WSL] Creating directory ${AEON_TARGET_DIR}'; "
    WSL_CMD="${WSL_CMD}sudo mkdir -p '${AEON_TARGET_DIR}'; "
    WSL_CMD="${WSL_CMD}echo '[WSL] Downloading ${AEON_BASH_FILE}...'; "
    WSL_CMD="${WSL_CMD}\$DOWNLOADER '${AEON_RAW_BASE_URL}/${AEON_BASH_FILE}' | sudo tee '${AEON_TARGET_DIR}/${AEON_BASH_FILE}' >/dev/null; "
    WSL_CMD="${WSL_CMD}sudo chmod +x '${AEON_TARGET_DIR}/${AEON_BASH_FILE}'; "
    WSL_CMD="${WSL_CMD}echo '[WSL] Executing ${AEON_BASH_FILE}...'; "
    WSL_CMD="${WSL_CMD}sudo '${AEON_TARGET_DIR}/${AEON_BASH_FILE}'"
    
    # Append all normalized flags to the command
    for flag in "${NORMALIZED_FLAGS[@]}"; do
        WSL_CMD="${WSL_CMD} '$flag'"
    done
    
    # Execute the command in WSL and exit with its exit code
    # -d specifies the distribution (Ubuntu-22.04)
    # -lc executes a login command (loads full environment)
    wsl.exe -d Ubuntu-22.04 -- bash -lc "$WSL_CMD"
    exit $?
fi

################################################################################
# DOWNLOAD TOOL VERIFICATION AND INSTALLATION
################################################################################
# Purpose:
#   Ensure either curl or wget is available for downloading the installer.
#   Attempts automatic installation if neither is found.
#
# Priority:
#   1. curl (preferred)
#   2. wget (fallback)
#
# Sets:
#   DOWNLOADER - Command to use for downloads ("curl -fsSL" or "wget -qO-")
################################################################################
(( AEON_FLAG_N )) || echo "[INFO] Ensuring downloader availability..."

DOWNLOADER=""

# Check for curl first (preferred)
if command -v curl >/dev/null 2>&1; then
    # -f: Fail silently on server errors
    # -s: Silent mode (no progress bar)
    # -S: Show errors even in silent mode
    # -L: Follow redirects
    DOWNLOADER="curl -fsSL"
    (( AEON_FLAG_N )) || echo "[INFO] Using curl"

# Check for wget as fallback
elif command -v wget >/dev/null 2>&1; then
    # -q: Quiet mode (no output)
    # -O-: Output to stdout
    DOWNLOADER="wget -qO-"
    (( AEON_FLAG_N )) || echo "[INFO] Using wget"

# Neither found - attempt installation
else
    echo "[WARN] Neither curl nor wget found. Attempting installation..."
    
    # Linux package manager detection and installation
    if [ "$OS_TYPE" = "linux" ]; then
        # Try apt-get (Debian/Ubuntu)
        if command -v apt-get >/dev/null 2>&1; then
            (( AEON_FLAG_N )) || echo "[INFO] Installing curl via apt-get..."
            # -qq: Very quiet (minimal output)
            # -y: Automatic yes to prompts
            sudo apt-get update -qq && sudo apt-get install -y curl
            DOWNLOADER="curl -fsSL"
        
        # Try yum (RHEL/CentOS 7 and earlier)
        elif command -v yum >/dev/null 2>&1; then
            (( AEON_FLAG_N )) || echo "[INFO] Installing curl via yum..."
            sudo yum install -y curl
            DOWNLOADER="curl -fsSL"
        
        # Try dnf (Fedora/RHEL 8+)
        elif command -v dnf >/dev/null 2>&1; then
            (( AEON_FLAG_N )) || echo "[INFO] Installing curl via dnf..."
            sudo dnf install -y curl
            DOWNLOADER="curl -fsSL"
        
        else
            echo "[ERROR] Could not install curl/wget. Please install manually." >&2
            exit 1
        fi
    
    # macOS with Homebrew
    elif [ "$OS_TYPE" = "macos" ]; then
        if command -v brew >/dev/null 2>&1; then
            (( AEON_FLAG_N )) || echo "[INFO] Installing curl via Homebrew..."
            brew install curl
            DOWNLOADER="curl -fsSL"
        else
            echo "[ERROR] Neither curl nor wget found, and Homebrew is not available." >&2
            echo "Please install Homebrew (https://brew.sh) or manually install curl/wget." >&2
            exit 1
        fi
    fi
fi

################################################################################
# TEMPORARY FILE HANDLING
################################################################################
# Purpose:
#   Create a temporary file for downloading the installer script.
#   Register cleanup trap to ensure temp file is deleted on exit.
#
# Cleanup Strategy:
#   The trap command ensures the temp file is removed even if the script
#   exits due to error, interrupt (Ctrl+C), or normal completion.
################################################################################

# Create temporary file (mktemp ensures unique filename)
TEMP_FILE=$(mktemp)

# Register cleanup function to run on script exit
# EXIT trap catches: normal exit, errors (due to set -e), and signals
trap "rm -f '$TEMP_FILE'" EXIT

################################################################################
# DOWNLOAD INSTALLER SCRIPT
################################################################################
# Purpose:
#   Download install.bash.sh from GitHub repository
################################################################################
(( AEON_FLAG_N )) || echo "[INFO] Downloading ${AEON_BASH_FILE}..."

# Download to temporary file
# $DOWNLOADER is set above to either "curl -fsSL" or "wget -qO-"
$DOWNLOADER "${AEON_RAW_BASE_URL}/${AEON_BASH_FILE}" > "$TEMP_FILE"

################################################################################
# PREPARE TARGET DIRECTORY
################################################################################
# Purpose:
#   Create the target directory structure with appropriate permissions
################################################################################
(( AEON_FLAG_N )) || echo "[INFO] Creating target directory: ${AEON_TARGET_DIR}"

# Create directory with sudo (may require root for /opt or /usr/local)
# -p: Create parent directories as needed, no error if existing
sudo mkdir -p "$AEON_TARGET_DIR"

################################################################################
# INSTALL DOWNLOADED SCRIPT
################################################################################
# Purpose:
#   Copy downloaded installer to target location and make executable
################################################################################
(( AEON_FLAG_N )) || echo "[INFO] Copying to ${AEON_TARGET_DIR}/${AEON_BASH_FILE}"

# Copy temp file to target location
sudo cp "$TEMP_FILE" "${AEON_TARGET_DIR}/${AEON_BASH_FILE}"

(( AEON_FLAG_N )) || echo "[INFO] Setting executable permissions..."

# Make the installer script executable
# chmod +x adds execute permission for all users
sudo chmod +x "${AEON_TARGET_DIR}/${AEON_BASH_FILE}"

################################################################################
# EXECUTE INSTALLER
################################################################################
# Purpose:
#   Run the downloaded installer script with appropriate privileges
#
# Privilege Handling:
#   - If already root (id -u = 0): Execute directly
#   - Otherwise: Use sudo to execute with root privileges
#
# Flag Forwarding:
#   All normalized flags are passed to the installer script
################################################################################
(( AEON_FLAG_N )) || echo "[INFO] Executing ${AEON_BASH_FILE}..."

if [ "$(id -u)" -eq 0 ]; then
    # Already running as root
    "${AEON_TARGET_DIR}/${AEON_BASH_FILE}" "${NORMALIZED_FLAGS[@]}"
else
    # Need sudo for root privileges
    sudo "${AEON_TARGET_DIR}/${AEON_BASH_FILE}" "${NORMALIZED_FLAGS[@]}"
fi

################################################################################
# COMPLETION
################################################################################
echo "[INFO] Bootstrap completed successfully."
exit 0
