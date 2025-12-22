#!/usr/bin/env bash

set -e

AEON_RAW_BASE_URL="https://raw.githubusercontent.com/conceptixx/AEON/main"
#-AEON_TARGET_DIR=""
#+AEON_WORKING_DIR="/opt/aeon"
#+AEON_TARGET_DIR=""
AEON_WORKING_DIR="/opt/aeon"
AEON_TARGET_DIR=""
AEON_BASH_FILE="install.bash.sh"
AEON_PWSH_FILE="install.pwrshl.ps1"
AEON_FLAG_N=0

NORMALIZED_FLAGS=()

normalize_flag() {
    local flag="$1"
    local lower_flag
# - lower_flag=$(echo "$flag" | tr '[:upper:]' '[:lower:]')
# + lower_flag=$(printf '%s' "$flag" | tr '[:upper:]' '[:lower:]')
    lower_flag=$(printf '%s' "$flag" | tr '[:upper:]' '[:lower:]')
    
    case "$lower_flag" in
        -c|--cli-enable|--enable-cli)
            echo "--enable-cli"
            ;;
        -w|--web-enable|--enable-web)
            echo "--enable-web"
            ;;
        -n|--noninteractive)
            AEON_FLAG_N=1
            echo "--noninteractive"
            ;;
        *)
            echo ""
            ;;
    esac
}

for arg in "$@"; do
    normalized=$(normalize_flag "$arg")
    if [ -z "$normalized" ]; then
        echo "ERROR: Unknown flag: $arg" >&2
        echo "Usage: $0 [-c|--cli-enable] [-w|--web-enable] [-n|--noninteractive]" >&2
        exit 2
    fi
    NORMALIZED_FLAGS+=("$normalized")
done

if [ ${#NORMALIZED_FLAGS[@]} -gt 3 ]; then
    echo "ERROR: Maximum 3 flags allowed" >&2
    exit 2
fi

OS_TYPE=""
case "$OSTYPE" in
    linux-gnu*)
        OS_TYPE="linux"
        ;;
    darwin*)
        OS_TYPE="macos"
        #+AEON_WORKING_DIR="/usr/local/aeon"
        AEON_WORKING_DIR="/usr/local/aeon"
        ;;
    msys*|mingw*|cygwin*)
        OS_TYPE="windows"
        ;;
    *)
        OS_TYPE="linux"
        ;;
esac
#+AEON_TARGET_DIR="${AEON_WORKING_DIR}/tmp"
AEON_TARGET_DIR="${AEON_WORKING_DIR}/tmp"

(( AEON_FLAG_N )) || echo "[INFO] Detected OS: $OS_TYPE"

if [ "$OS_TYPE" = "windows" ]; then
    (( AEON_FLAG_N )) || echo "[INFO] Windows environment detected. Delegating to WSL..."
    
    if ! command -v wsl.exe >/dev/null 2>&1; then
        echo "[WARN] WSL not found. Attempting installation..."
        
        if command -v powershell.exe >/dev/null 2>&1; then
            powershell.exe -Command "Start-Process powershell -Verb RunAs -ArgumentList '-Command wsl --install -d Ubuntu-22.04'" 2>/dev/null || {
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
    
    for flag in "${NORMALIZED_FLAGS[@]}"; do
        WSL_CMD="${WSL_CMD} '$flag'"
    done
    
    wsl.exe -d Ubuntu-22.04 -- bash -lc "$WSL_CMD"
    exit $?
fi

(( AEON_FLAG_N )) || echo "[INFO] Ensuring downloader availability..."

DOWNLOADER=""
if command -v curl >/dev/null 2>&1; then
    DOWNLOADER="curl -fsSL"
    (( AEON_FLAG_N )) || echo "[INFO] Using curl"
elif command -v wget >/dev/null 2>&1; then
    DOWNLOADER="wget -qO-"
    (( AEON_FLAG_N )) || echo "[INFO] Using wget"
else
    echo "[WARN] Neither curl nor wget found. Attempting installation..."
    
    if [ "$OS_TYPE" = "linux" ]; then
        if command -v apt-get >/dev/null 2>&1; then
            (( AEON_FLAG_N )) || echo "[INFO] Installing curl via apt-get..."
            sudo apt-get update -qq && sudo apt-get install -y curl
            DOWNLOADER="curl -fsSL"
        elif command -v yum >/dev/null 2>&1; then
            (( AEON_FLAG_N )) || echo "[INFO] Installing curl via yum..."
            sudo yum install -y curl
            DOWNLOADER="curl -fsSL"
        elif command -v dnf >/dev/null 2>&1; then
            (( AEON_FLAG_N )) || echo "[INFO] Installing curl via dnf..."
            sudo dnf install -y curl
            DOWNLOADER="curl -fsSL"
        else
            echo "[ERROR] Could not install curl/wget. Please install manually." >&2
            exit 1
        fi
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

TEMP_FILE=$(mktemp)
trap "rm -f '$TEMP_FILE'" EXIT

(( AEON_FLAG_N )) || echo "[INFO] Downloading ${AEON_BASH_FILE}..."
$DOWNLOADER "${AEON_RAW_BASE_URL}/${AEON_BASH_FILE}" > "$TEMP_FILE"

(( AEON_FLAG_N )) || echo "[INFO] Creating target directory: ${AEON_TARGET_DIR}"
sudo mkdir -p "$AEON_TARGET_DIR"

(( AEON_FLAG_N )) || echo "[INFO] Copying to ${AEON_TARGET_DIR}/${AEON_BASH_FILE}"
sudo cp "$TEMP_FILE" "${AEON_TARGET_DIR}/${AEON_BASH_FILE}"

(( AEON_FLAG_N )) || echo "[INFO] Setting executable permissions..."
sudo chmod +x "${AEON_TARGET_DIR}/${AEON_BASH_FILE}"

(( AEON_FLAG_N )) || echo "[INFO] Executing ${AEON_BASH_FILE}..."
if [ "$(id -u)" -eq 0 ]; then
    "${AEON_TARGET_DIR}/${AEON_BASH_FILE}" "${NORMALIZED_FLAGS[@]}"
else
    sudo "${AEON_TARGET_DIR}/${AEON_BASH_FILE}" "${NORMALIZED_FLAGS[@]}"
fi

echo "[INFO] Bootstrap completed successfully."
exit 0