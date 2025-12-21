#!/usr/bin/env bash
# AEON Installation Script
# Supports: Linux (Ubuntu/Debian/Raspbian), macOS, WSL
# Bash 3.2+ compatible

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

AEON_VERSION="3.1.0"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/conceptixx/AEON/main"

# Orchestrator configuration
AEON_ORCH_MODE="auto"
AEON_ORCH_DOCKER_IMAGE="python:3.11-slim"
AEON_ORCH_DOCKER_PULL=1
AEON_ORCH_DOCKER_SOCKET=1

# Sudoers commands - broad install/ops permissions
SUDOERS_INSTALL_CMDS="/usr/bin/apt,/usr/bin/apt-get,/usr/bin/dpkg,/usr/bin/systemctl,/bin/systemctl,/usr/sbin/service,/sbin/service,/usr/bin/snap,/usr/local/bin/brew,/opt/homebrew/bin/brew,/usr/bin/python3,/usr/local/bin/python3,/usr/bin/pip3,/usr/local/bin/pip3,/usr/bin/docker,/usr/local/bin/docker,/usr/bin/docker-compose,/usr/local/bin/docker-compose,/bin/chown,/usr/bin/chown,/bin/chmod,/usr/bin/chmod,/bin/mkdir,/usr/bin/mkdir,/bin/rm,/usr/bin/rm,/bin/cp,/usr/bin/cp,/bin/mv,/usr/bin/mv,/usr/bin/curl,/usr/bin/wget,/usr/bin/git,/usr/local/bin/git"

# System user
AEON_USER="aeon-system"

# Flags
FLAG_CLI_ENABLE=0
FLAG_WEB_ENABLE=0
FLAG_NONINTERACTIVE=0

# Global state
OS_TYPE=""
AEON_ROOT=""
BREW_USER=""
BREW_PATH=""
LOG_FILE=""
SILENT_MODE=0
APT_UPDATED=0

# =============================================================================
# PRE-SCAN NONINTERACTIVE (GLOBAL SCOPE)
# =============================================================================

# Scan for noninteractive flag without any output
for arg in "$@"; do
    # Convert to lowercase using tr (Bash 3.2 compatible)
    arg_lower=$(printf '%s\n' "$arg" | tr '[:upper:]' '[:lower:]')
    case "$arg_lower" in
        -n|--noninteractive)
            # Set up logging immediately
            LOG_FILE="/tmp/aeon-install-$$.log"
            exec 1>"$LOG_FILE"
            exec 2>&1
            SILENT_MODE=1
            break
            ;;
    esac
done

# =============================================================================
# EARLY INIT SILENT MODE
# =============================================================================

early_init_silent() {
    local tmplog
    
    # Try AEON_ROOT logdir first if available
    if [ -n "$AEON_ROOT" ] && mkdir -p "$AEON_ROOT/logs" 2>/dev/null; then
        tmplog="$AEON_ROOT/logs/install-$$.log"
    else
        tmplog="/tmp/aeon-install-$$.log"
    fi
    
    # Redirect all output to log
    exec 1>"$tmplog"
    exec 2>&1
    
    LOG_FILE="$tmplog"
    SILENT_MODE=1
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

parse_args() {
    local count=0
    local arg_lower
    
    while [ $# -gt 0 ]; do
        # Convert to lowercase using tr
        arg_lower=$(printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]')
        
        case "$arg_lower" in
            -c|--cli-enable|--enable-cli)
                FLAG_CLI_ENABLE=1
                count=$((count + 1))
                shift
                ;;
            -w|--web-enable|--enable-web)
                FLAG_WEB_ENABLE=1
                count=$((count + 1))
                shift
                ;;
            -n|--noninteractive)
                FLAG_NONINTERACTIVE=1
                count=$((count + 1))
                if [ "$SILENT_MODE" -eq 0 ]; then
                    early_init_silent
                fi
                shift
                ;;
            *)
                printf "Error: Unknown flag '%s'\n" "$1" >&2
                printf "\nUsage: %s [OPTIONS]\n" "$0" >&2
                printf "Options:\n" >&2
                printf "  -c, --cli-enable       Enable CLI mode\n" >&2
                printf "  -w, --web-enable       Enable Web mode\n" >&2
                printf "  -n, --noninteractive   Non-interactive silent mode\n" >&2
                exit 2
                ;;
        esac
    done
    
    # Check max 3 flags
    if [ $count -gt 3 ]; then
        printf "Error: Maximum 3 flags allowed (c/w/n)\n" >&2
        exit 2
    fi
}

# =============================================================================
# LOGGING
# =============================================================================

log() {
    if [ "$SILENT_MODE" -eq 1 ]; then
        printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
    else
        printf "[AEON] %s\n" "$*"
    fi
}

log_error() {
    if [ "$SILENT_MODE" -eq 1 ]; then
        printf "[%s] ERROR: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
    else
        printf "[AEON ERROR] %s\n" "$*" >&2
    fi
}

# =============================================================================
# OS DETECTION
# =============================================================================

detect_os() {
    local uname_s
    uname_s="$(uname -s)"
    
    case "$uname_s" in
        Linux*)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                OS_TYPE="wsl"
                AEON_ROOT="/opt/aeon"
            else
                OS_TYPE="linux"
                AEON_ROOT="/opt/aeon"
            fi
            ;;
        Darwin*)
            OS_TYPE="macos"
            AEON_ROOT="/usr/local/aeon"
            ;;
        *)
            log_error "Unsupported OS: $uname_s"
            exit 1
            ;;
    esac
    
    log "Detected OS: $OS_TYPE"
    log "AEON_ROOT: $AEON_ROOT"
}

# =============================================================================
# MACOS BREW USER DETECTION
# =============================================================================

detect_brew_user() {
    if [ "$OS_TYPE" != "macos" ]; then
        return
    fi
    
    # Try SUDO_USER first
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        BREW_USER="$SUDO_USER"
        log "Using SUDO_USER for brew: $BREW_USER"
        return
    fi
    
    # Fallback: console user
    if command -v stat >/dev/null 2>&1; then
        local console_user
        console_user="$(stat -f%Su /dev/console 2>/dev/null || true)"
        if [ -n "$console_user" ] && [ "$console_user" != "root" ]; then
            BREW_USER="$console_user"
            log "Using console user for brew: $BREW_USER"
            return
        fi
    fi
    
    log_error "Cannot determine non-root user for Homebrew on macOS"
    exit 1
}

detect_brew_path() {
    if [ "$OS_TYPE" != "macos" ]; then
        return
    fi
    
    # Check if brew is in PATH as BREW_USER
    if sudo -u "$BREW_USER" -H command -v brew >/dev/null 2>&1; then
        BREW_PATH="$(sudo -u "$BREW_USER" -H command -v brew)"
        log "Found brew in PATH: $BREW_PATH"
        return
    fi
    
    # Check common locations
    for path in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$path" ]; then
            BREW_PATH="$path"
            log "Found brew at: $BREW_PATH"
            return
        fi
    done
    
    log_error "Homebrew not found. Please install Homebrew first:"
    log_error "Visit https://brew.sh or run:"
    log_error '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    exit 1
}

# =============================================================================
# PACKAGE INSTALLATION - IDEMPOTENT
# =============================================================================

install_always_tools() {
    log "Checking always-required tools..."
    
    case "$OS_TYPE" in
        linux|wsl)
            local missing_pkgs=""
            
            # Check each package
            for pkg in curl wget ca-certificates; do
                if ! dpkg -s "$pkg" >/dev/null 2>&1; then
                    missing_pkgs="$missing_pkgs $pkg"
                fi
            done
            
            if [ -n "$missing_pkgs" ]; then
                log "Installing missing packages:$missing_pkgs"
                if [ "$APT_UPDATED" -eq 0 ]; then
                    apt-get update -qq
                    APT_UPDATED=1
                fi
                apt-get install -y -qq $missing_pkgs
            else
                log "All always-tools already installed"
            fi
            ;;
            
        macos)
            # curl usually present
            if ! command -v curl >/dev/null 2>&1; then
                log_error "curl not found on macOS (unexpected)"
                exit 1
            fi
            
            # wget via brew if needed
            if ! command -v wget >/dev/null 2>&1; then
                log "Installing wget via Homebrew..."
                sudo -u "$BREW_USER" -H "$BREW_PATH" install wget
            else
                log "wget already installed"
            fi
            
            # ca-certificates only if brew available and package missing
            if sudo -u "$BREW_USER" -H "$BREW_PATH" list ca-certificates >/dev/null 2>&1; then
                log "ca-certificates already installed"
            else
                log "Installing ca-certificates via Homebrew..."
                sudo -u "$BREW_USER" -H "$BREW_PATH" install ca-certificates || log "ca-certificates install skipped/failed (may be optional)"
            fi
            ;;
    esac
}

install_python() {
    log "Checking Python installation..."
    
    case "$OS_TYPE" in
        linux|wsl)
            local missing_pkgs=""
            
            for pkg in python3 python3-pip python3-venv python-is-python3; do
                if ! dpkg -s "$pkg" >/dev/null 2>&1; then
                    missing_pkgs="$missing_pkgs $pkg"
                fi
            done
            
            if [ -n "$missing_pkgs" ]; then
                log "Installing missing Python packages:$missing_pkgs"
                if [ "$APT_UPDATED" -eq 0 ]; then
                    apt-get update -qq
                    APT_UPDATED=1
                fi
                apt-get install -y -qq $missing_pkgs
            else
                log "Python already installed"
            fi
            ;;
            
        macos)
            # Check if python3 works and venv module available
            if command -v python3 >/dev/null 2>&1 && python3 -m venv --help >/dev/null 2>&1; then
                log "Python3 with venv already installed"
            else
                log "Installing Python via Homebrew..."
                sudo -u "$BREW_USER" -H "$BREW_PATH" install python
            fi
            ;;
    esac
}

install_docker() {
    if [ "$OS_TYPE" = "macos" ]; then
        log "Docker installation on macOS requires Docker Desktop (manual install)"
        return
    fi
    
    log "Checking Docker installation..."
    
    # Check if docker exists
    if command -v docker >/dev/null 2>&1; then
        # Check if daemon is running
        if systemctl is-active docker >/dev/null 2>&1 || service docker status >/dev/null 2>&1; then
            log "Docker already installed and running"
            return
        fi
        
        # Docker exists but not running - try to start
        log "Docker installed but not running, starting..."
        systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true
        sleep 2
        
        if systemctl is-active docker >/dev/null 2>&1 || service docker status >/dev/null 2>&1; then
            log "Docker started successfully"
            return
        fi
    fi
    
    # Need to install Docker
    log "Installing Docker..."
    
    # Detect distro
    local distro_id
    if [ -f /etc/os-release ]; then
        distro_id="$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')"
        # Raspbian -> Debian
        if [ "$distro_id" = "raspbian" ]; then
            distro_id="debian"
        fi
    else
        log_error "Cannot determine Linux distribution"
        exit 1
    fi
    
    if [ "$distro_id" != "ubuntu" ] && [ "$distro_id" != "debian" ]; then
        log_error "Docker auto-install only supports Ubuntu/Debian/Raspbian, detected: $distro_id"
        exit 1
    fi
    
    # Install prerequisites
    if [ "$APT_UPDATED" -eq 0 ]; then
        apt-get update -qq
        APT_UPDATED=1
    fi
    apt-get install -y -qq ca-certificates curl gnupg lsb-release
    
    # Add Docker GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$distro_id/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    printf "deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/%s %s stable\n" \
        "$(dpkg --print-architecture)" \
        "$distro_id" \
        "$(lsb_release -cs)" > /etc/apt/sources.list.d/docker.list
    
    # Install Docker packages
    apt-get update -qq
    APT_UPDATED=1
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Enable and start
    systemctl enable docker
    systemctl start docker
    
    log "Docker installed and started"
}

# =============================================================================
# USER & PERMISSIONS
# =============================================================================

create_system_user() {
    log "Checking system user: $AEON_USER"
    
    if id "$AEON_USER" >/dev/null 2>&1; then
        log "User $AEON_USER already exists"
        return
    fi
    
    log "Creating system user: $AEON_USER"
    
    case "$OS_TYPE" in
        linux|wsl)
            useradd -r -s /usr/sbin/nologin -d "$AEON_ROOT" -c "AEON System User" "$AEON_USER" || \
                useradd -r -s /bin/false -d "$AEON_ROOT" -c "AEON System User" "$AEON_USER"
            ;;
        macos)
            # macOS system user creation
            local maxid
            maxid=$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -n | tail -1)
            local newid=$((maxid + 1))
            
            dscl . -create "/Users/$AEON_USER"
            dscl . -create "/Users/$AEON_USER" UserShell /usr/bin/false
            dscl . -create "/Users/$AEON_USER" RealName "AEON System User"
            dscl . -create "/Users/$AEON_USER" UniqueID "$newid"
            dscl . -create "/Users/$AEON_USER" PrimaryGroupID 20
            dscl . -create "/Users/$AEON_USER" NFSHomeDirectory "$AEON_ROOT"
            ;;
    esac
}

setup_directories() {
    log "Setting up directory structure..."
    
    mkdir -p "$AEON_ROOT"
    mkdir -p "$AEON_ROOT/library/orchestrator"
    mkdir -p "$AEON_ROOT/manifest/config"
    mkdir -p "$AEON_ROOT/logs"
    mkdir -p "$AEON_ROOT/data"
    
    # Set ownership
    chown -R "$AEON_USER:$(id -gn "$AEON_USER")" "$AEON_ROOT"
    
    log "Directory structure created"
}

setup_sudoers() {
    log "Configuring sudoers for $AEON_USER..."
    
    local sudoers_file="/etc/sudoers.d/$AEON_USER"
    local sudoers_content
    
    sudoers_content="# AEON System User - Automated Operations
# Generated by AEON installer v$AEON_VERSION

# Reboot commands
$AEON_USER ALL=(ALL) NOPASSWD: /sbin/reboot
$AEON_USER ALL=(ALL) NOPASSWD: /usr/sbin/reboot
$AEON_USER ALL=(ALL) NOPASSWD: /sbin/shutdown
$AEON_USER ALL=(ALL) NOPASSWD: /usr/sbin/shutdown
$AEON_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl reboot
$AEON_USER ALL=(ALL) NOPASSWD: /bin/systemctl reboot

# Installation and operations commands
$AEON_USER ALL=(ALL) NOPASSWD: $SUDOERS_INSTALL_CMDS

# Docker commands
$AEON_USER ALL=(ALL) NOPASSWD: /usr/bin/docker
$AEON_USER ALL=(ALL) NOPASSWD: /usr/local/bin/docker
"
    
    printf "%s\n" "$sudoers_content" > "$sudoers_file"
    chmod 0440 "$sudoers_file"
    
    # Validate
    if ! visudo -c -f "$sudoers_file" >/dev/null 2>&1; then
        log_error "Sudoers file validation failed"
        rm -f "$sudoers_file"
        exit 1
    fi
    
    log "Sudoers configuration completed"
}

# =============================================================================
# DOWNLOAD FILES
# =============================================================================

download_files() {
    log "Downloading AEON files from GitHub..."
    
    local files
    files="library/orchestrator/orchestrator.json.py
manifest/manifest.install.json
manifest/config/manifest.config.cursed.json"
    
    local IFS_OLD="$IFS"
    IFS="
"
    for file in $files; do
        IFS="$IFS_OLD"
        local url="${GITHUB_RAW_BASE}/${file}"
        local dest="${AEON_ROOT}/${file}"
        local dest_dir
        dest_dir="$(dirname "$dest")"
        
        mkdir -p "$dest_dir"
        
        log "Downloading: $file"
        if ! curl -fsSL -o "$dest" "$url"; then
            log_error "Failed to download: $url"
            exit 1
        fi
        
        chown "$AEON_USER:$(id -gn "$AEON_USER")" "$dest"
    done
    IFS="$IFS_OLD"
    
    # Make orchestrator executable
    chmod +x "$AEON_ROOT/library/orchestrator/orchestrator.json.py"
    
    log "All files downloaded successfully"
}

# =============================================================================
# ORCHESTRATOR EXECUTION
# =============================================================================

setup_python_venv() {
    local venv_path="$AEON_ROOT/venv"
    
    if [ -d "$venv_path" ]; then
        log "Python venv already exists"
        return
    fi
    
    log "Creating Python virtual environment..."
    sudo -u "$AEON_USER" python3 -m venv "$venv_path"
    
    # Install dependencies if needed
    if [ -f "$AEON_ROOT/requirements.txt" ]; then
        log "Installing Python dependencies..."
        sudo -u "$AEON_USER" "$venv_path/bin/pip" install --quiet --upgrade pip
        sudo -u "$AEON_USER" "$venv_path/bin/pip" install --quiet -r "$AEON_ROOT/requirements.txt"
    fi
}

run_orchestrator() {
    log "Running orchestrator..."
    
    # Build transfer flags
    local transfer_flags=""
    if [ "$FLAG_CLI_ENABLE" -eq 1 ]; then
        transfer_flags="$transfer_flags --cli-enable"
    fi
    if [ "$FLAG_WEB_ENABLE" -eq 1 ]; then
        transfer_flags="$transfer_flags --web-enable"
    fi
    if [ "$FLAG_NONINTERACTIVE" -eq 1 ]; then
        transfer_flags="$transfer_flags --noninteractive"
    fi
    
    # Determine mode
    local mode="$AEON_ORCH_MODE"
    if [ "$mode" = "auto" ]; then
        if command -v docker >/dev/null 2>&1; then
            # Check if daemon is reachable
            local timeout_cmd=""
            if command -v timeout >/dev/null 2>&1; then
                timeout_cmd="timeout 5"
            fi
            
            if $timeout_cmd docker info >/dev/null 2>&1; then
                mode="docker"
                log "Auto-selected Docker mode"
            else
                mode="native"
                log "Auto-selected native mode (Docker daemon unreachable)"
            fi
        else
            mode="native"
            log "Auto-selected native mode (Docker not available)"
        fi
    fi
    
    case "$mode" in
        native)
            run_orchestrator_native "$transfer_flags"
            ;;
        docker)
            run_orchestrator_docker "$transfer_flags"
            ;;
        *)
            log_error "Invalid orchestrator mode: $mode"
            exit 1
            ;;
    esac
}

run_orchestrator_native() {
    local flags="$1"
    
    log "Running orchestrator in native mode..."
    setup_python_venv
    
    local venv_python="$AEON_ROOT/venv/bin/python"
    local orchestrator="$AEON_ROOT/library/orchestrator/orchestrator.json.py"
    
    sudo -u "$AEON_USER" "$venv_python" "$orchestrator" \
        $flags \
        --file:/manifest/manifest.install.json \
        --config:/manifest/config/manifest.config.cursed.json
}

run_orchestrator_docker() {
    local flags="$1"
    
    log "Running orchestrator in Docker mode..."
    
    # Pull image if configured
    if [ "$AEON_ORCH_DOCKER_PULL" -eq 1 ]; then
        log "Pulling Docker image: $AEON_ORCH_DOCKER_IMAGE"
        docker pull "$AEON_ORCH_DOCKER_IMAGE"
    fi
    
    # Build docker run command
    local docker_args="-v $AEON_ROOT:$AEON_ROOT -w $AEON_ROOT"
    
    if [ "$AEON_ORCH_DOCKER_SOCKET" -eq 1 ] && [ -S /var/run/docker.sock ]; then
        docker_args="$docker_args -v /var/run/docker.sock:/var/run/docker.sock"
    fi
    
    local orchestrator="/library/orchestrator/orchestrator.json.py"
    
    docker run --rm $docker_args "$AEON_ORCH_DOCKER_IMAGE" \
        python "$orchestrator" \
        $flags \
        --file:/manifest/manifest.install.json \
        --config:/manifest/config/manifest.config.cursed.json
}

# =============================================================================
# FINALIZE
# =============================================================================

finalize_installation() {
    if [ "$SILENT_MODE" -eq 1 ]; then
        # Move log to final location if possible
        if [ -n "$AEON_ROOT" ] && mkdir -p "$AEON_ROOT/logs" 2>/dev/null; then
            local final_log="$AEON_ROOT/logs/install-$(date +%Y%m%d-%H%M%S).log"
            if [ -f "$LOG_FILE" ]; then
                cp "$LOG_FILE" "$final_log" 2>/dev/null || true
                chown "$AEON_USER:$(id -gn "$AEON_USER")" "$final_log" 2>/dev/null || true
            fi
        fi
        # Don't print anything in silent mode
    else
        log ""
        log "========================================="
        log "AEON Installation Complete!"
        log "========================================="
        log "Version: $AEON_VERSION"
        log "Root: $AEON_ROOT"
        log "User: $AEON_USER"
        log ""
        log "Next steps:"
        log "  - Review logs in $AEON_ROOT/logs/"
        log "  - Check configuration in $AEON_ROOT/manifest/"
        log ""
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    # Root check (already redirected if silent mode)
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Parse args (may enable silent mode if not already enabled)
    parse_args "$@"
    
    log "AEON Installer v$AEON_VERSION"
    log "Starting installation..."
    
    # Detection
    detect_os
    detect_brew_user
    detect_brew_path
    
    # Installation
    install_always_tools
    install_python
    install_docker
    
    # User & permissions
    create_system_user
    setup_directories
    setup_sudoers
    
    # Download files
    download_files
    
    # Run orchestrator
    run_orchestrator
    
    # Done
    finalize_installation
}

main "$@"