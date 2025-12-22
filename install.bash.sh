#!/usr/bin/env bash
# AEON Installation Script
# Supports: Linux (Ubuntu/Debian/Raspbian), macOS, WSL
# Bash 3.2+ compatible
# VERSION: 1.0.0.v7.1 stable

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

AEON_VERSION="6.1.0"
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
TEMP_LOG=""
SILENT_MODE=0
APT_UPDATED=0

# =============================================================================
# PRE-SCAN NONINTERACTIVE (MUST BE FIRST - ZERO OUTPUT)
# =============================================================================

for arg in "$@"; do
    arg_lower=$(printf '%s\n' "$arg" | tr '[:upper:]' '[:lower:]')
    case "$arg_lower" in
        -n|--noninteractive)
            TEMP_LOG="/tmp/aeon-install-$$.log"
            touch "$TEMP_LOG" && chmod 600 "$TEMP_LOG" || true
            exec 1>"$TEMP_LOG" 2>&1
            SILENT_MODE=1
            FLAG_NONINTERACTIVE=1
            break
            ;;
    esac
done

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

parse_args() {
    local count=0
    local arg_lower
    
    while [ $# -gt 0 ]; do
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
                count=$((count + 1))
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
        printf "[install.bash][%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
    else
        printf "[AEON][install.bash] %s\n" "$*"
    fi
}

log_error() {
    if [ "$SILENT_MODE" -eq 1 ]; then
        printf "[install.bash][%s] ERROR: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
    else
        printf "[AEON ERROR][install.bash] %s\n" "$*" >&2
    fi
}

# =============================================================================
# LOG SETUP
# =============================================================================

setup_logging() {
    local logdir="${AEON_ROOT}/logfiles"
    
    mkdir -p "$logdir" 2>/dev/null || {
        log_error "Cannot create log directory: $logdir"
        return
    }
    
    LOG_FILE="${logdir}/install.bash.$(date +%Y%m%d-%H%M%S).log"
    
    # Only chown if user exists
    if id -u "$AEON_USER" >/dev/null 2>&1; then
        chown "$AEON_USER:$(id -gn "$AEON_USER")" "$logdir" 2>/dev/null || true
    fi
    
    if [ "$SILENT_MODE" -eq 1 ]; then
        migrate_log_to_final
    else
        exec > >(tee -a "$LOG_FILE") 2>&1
        log "Logging to file: $LOG_FILE"
    fi
}

# =============================================================================
# LOG MIGRATION (TEMP -> FINAL)
# =============================================================================

migrate_log_to_final() {
    local logdir="${AEON_ROOT}/logfiles"
    mkdir -p "$logdir" 2>/dev/null || return
    
    LOG_FILE="${logdir}/install.bash.$(date +%Y%m%d-%H%M%S).log"
    
    if [ -n "$TEMP_LOG" ] && [ -f "$TEMP_LOG" ]; then
        cat "$TEMP_LOG" >> "$LOG_FILE" 2>/dev/null || return
        rm -f "$TEMP_LOG"
    fi
    
    exec 1>>"$LOG_FILE" 2>&1
    
    # Only chown if user exists
    if id -u "$AEON_USER" >/dev/null 2>&1; then
        chown "$AEON_USER:$(id -gn "$AEON_USER")" "$logdir" 2>/dev/null || true
        chown "$AEON_USER:$(id -gn "$AEON_USER")" "$LOG_FILE" 2>/dev/null || true
    fi
    
    log "Log migrated to final location: $LOG_FILE"
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
    
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        BREW_USER="$SUDO_USER"
        log "Using SUDO_USER for brew: $BREW_USER"
        return
    fi
    
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
    
    if sudo -u "$BREW_USER" -H command -v brew >/dev/null 2>&1; then
        BREW_PATH="$(sudo -u "$BREW_USER" -H command -v brew)"
        log "Found brew in PATH: $BREW_PATH"
        return
    fi
    
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
                log "All required tools already installed"
            fi
            ;;
        macos)
            local missing_pkgs=""
            
            for pkg in curl wget; do
                if ! sudo -u "$BREW_USER" -H "$BREW_PATH" list "$pkg" >/dev/null 2>&1; then
                    missing_pkgs="$missing_pkgs $pkg"
                fi
            done
            
            if [ -n "$missing_pkgs" ]; then
                log "Installing missing packages:$missing_pkgs"
                sudo -u "$BREW_USER" -H "$BREW_PATH" install $missing_pkgs
            else
                log "All required tools already installed"
            fi
            ;;
    esac
}

install_python() {
    log "Checking Python installation..."
    
    case "$OS_TYPE" in
        linux|wsl)
            local missing_pkgs=""
            
            if ! command -v python3 >/dev/null 2>&1; then
                missing_pkgs="$missing_pkgs python3"
            fi
            if ! dpkg -s python3-venv >/dev/null 2>&1; then
                missing_pkgs="$missing_pkgs python3-venv"
            fi
            if ! dpkg -s python3-pip >/dev/null 2>&1; then
                missing_pkgs="$missing_pkgs python3-pip"
            fi
            
            if [ -n "$missing_pkgs" ]; then
                log "Installing Python packages:$missing_pkgs"
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
            if ! sudo -u "$BREW_USER" -H "$BREW_PATH" list python@3 >/dev/null 2>&1; then
                log "Installing Python..."
                sudo -u "$BREW_USER" -H "$BREW_PATH" install python@3
            else
                log "Python already installed"
            fi
            ;;
    esac
}

install_docker() {
    log "Checking Docker installation..."
    
    if command -v docker >/dev/null 2>&1; then
        log "Docker already installed"
        return
    fi
    
    case "$OS_TYPE" in
        linux|wsl)
            log "Installing Docker..."
            if [ "$APT_UPDATED" -eq 0 ]; then
                apt-get update -qq
                APT_UPDATED=1
            fi
            
            apt-get install -y -qq apt-transport-https gnupg lsb-release
            
            local distro
            distro="$(lsb_release -is | tr '[:upper:]' '[:lower:]')"
            local codename
            codename="$(lsb_release -cs)"
            
            mkdir -p /etc/apt/keyrings
            curl -fsSL "https://download.docker.com/linux/${distro}/gpg" | \
                gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
            
            printf "deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/%s %s stable\n" \
                "$(dpkg --print-architecture)" "$distro" "$codename" > /etc/apt/sources.list.d/docker.list
            
            apt-get update -qq
            apt-get install -y -qq docker-ce docker-ce-cli containerd.io
            
            systemctl enable docker >/dev/null 2>&1 || true
            systemctl start docker >/dev/null 2>&1 || true
            ;;
        macos)
            log "Docker Desktop required on macOS"
            log "Please install from: https://www.docker.com/products/docker-desktop"
            ;;
    esac
}

# =============================================================================
# USER & PERMISSIONS
# =============================================================================

create_system_user() {
    if id "$AEON_USER" >/dev/null 2>&1; then
        log "User $AEON_USER already exists"
        return
    fi
    
    log "Creating system user: $AEON_USER"
    
    case "$OS_TYPE" in
        linux|wsl)
            useradd -r -s /bin/bash -d "$AEON_ROOT" -m "$AEON_USER"
            ;;
        macos)
            local next_uid
            next_uid=$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -n | tail -1)
            next_uid=$((next_uid + 1))
            
            dscl . -create "/Users/$AEON_USER"
            dscl . -create "/Users/$AEON_USER" UserShell /bin/bash
            dscl . -create "/Users/$AEON_USER" UniqueID "$next_uid"
            dscl . -create "/Users/$AEON_USER" PrimaryGroupID 20
            dscl . -create "/Users/$AEON_USER" NFSHomeDirectory "$AEON_ROOT"
            ;;
    esac
}

setup_directories() {
    log "Setting up directory structure..."
    
    local dirs="library/orchestrator manifest/config logfiles"
    local IFS_OLD="$IFS"
    IFS=" "
    for dir in $dirs; do
        IFS="$IFS_OLD"
        mkdir -p "$AEON_ROOT/$dir"
    done
    IFS="$IFS_OLD"
    
    chown -R "$AEON_USER:$(id -gn "$AEON_USER")" "$AEON_ROOT"
    chmod -R 755 "$AEON_ROOT"
    
    log "Directory structure created"
}

setup_sudoers() {
    log "Configuring sudoers for $AEON_USER..."
    
    local sudoers_file="/etc/sudoers.d/aeon-system"
    
    local sudoers_content="# AEON System User Permissions
# Auto-generated - do not edit manually

# Shutdown/reboot
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
    
    if [ -f "$AEON_ROOT/requirements.txt" ]; then
        log "Installing Python dependencies..."
        sudo -u "$AEON_USER" "$venv_path/bin/pip" install --quiet --upgrade pip
        sudo -u "$AEON_USER" "$venv_path/bin/pip" install --quiet -r "$AEON_ROOT/requirements.txt"
    fi
}

run_orchestrator() {
    log "Running orchestrator..."
    
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
    
    local mode="$AEON_ORCH_MODE"
    if [ "$mode" = "auto" ]; then
        if command -v docker >/dev/null 2>&1; then
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
            return $?
            ;;
        docker)
            if run_orchestrator_docker "$transfer_flags"; then
                return 0
            else
                local docker_exit=$?
                log_error "Docker orchestrator failed with exit code $docker_exit"
                log "Falling back to native mode..."
                run_orchestrator_native "$transfer_flags"
                return $?
            fi
            ;;
        *)
            log_error "Invalid orchestrator mode: $mode"
            return 1
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
    
    return $?
}

run_orchestrator_docker() {
    local flags="$1"
    
    log "Running orchestrator in Docker mode..."
    
    if [ "$AEON_ORCH_DOCKER_PULL" -eq 1 ]; then
        log "Pulling Docker image: $AEON_ORCH_DOCKER_IMAGE"
        if ! docker pull "$AEON_ORCH_DOCKER_IMAGE"; then
            log_error "Failed to pull Docker image"
            return 1
        fi
    fi
    
    local docker_args="-v $AEON_ROOT:/aeon -w /aeon -e AEON_ROOT=/aeon"
    
    if [ "$AEON_ORCH_DOCKER_SOCKET" -eq 1 ] && [ -S /var/run/docker.sock ]; then
        docker_args="$docker_args -v /var/run/docker.sock:/var/run/docker.sock"
    fi
    
    docker run --rm $docker_args "$AEON_ORCH_DOCKER_IMAGE" \
        python /aeon/library/orchestrator/orchestrator.json.py \
        $flags \
        --file:/manifest/manifest.install.json \
        --config:/manifest/config/manifest.config.cursed.json
    
    return $?
}

# =============================================================================
# FINALIZE
# =============================================================================

finalize_installation() {
    if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
        chown "$AEON_USER:$(id -gn "$AEON_USER")" "$LOG_FILE" 2>/dev/null || true
    fi
    
    if [ "$SILENT_MODE" -eq 0 ]; then
        log ""
        log "========================================="
        log "AEON Installation Complete!"
        log "========================================="
        log "Version: $AEON_VERSION"
        log "Root: $AEON_ROOT"
        log "User: $AEON_USER"
        log ""
        log "Next steps:"
        log "  - Review logs in $AEON_ROOT/logfiles/"
        log "  - Check configuration in $AEON_ROOT/manifest/"
        log ""
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    parse_args "$@"
    
    if [ "$(id -u)" -ne 0 ]; then
        printf "Error: This script must be run as root\n" >&2
        exit 1
    fi
    
    detect_os
    setup_logging
    
    if [ "$SILENT_MODE" -eq 0 ]; then
        log "AEON Installer v$AEON_VERSION"
        log "Starting installation..."
    else
        log "Installation started (silent mode)"
    fi
    
    detect_brew_user
    detect_brew_path
    
    install_always_tools
    install_python
    install_docker
    
    create_system_user
    setup_directories
    setup_sudoers
    
    download_files
    
    if ! run_orchestrator; then
        log_error "Orchestrator execution failed"
        finalize_installation
        exit 1
    fi
    
    finalize_installation
    exit 0
}

main "$@"