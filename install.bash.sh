#!/usr/bin/env bash
# AEON Installation Script
# Supports: Linux (Ubuntu/Debian/Raspbian), macOS, WSL
# Bash 3.2+ compatible
# VERSION: 1.2.0

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

AEON_VERSION="6.1.0"
AEON_REPO_URL="https://github.com/conceptixx/AEON.git"

# Orchestrator configuration
AEON_ORCH_MODE="native"

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
REPO_DIR=""
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
        printf "[AEON_BASH][%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
    else
        printf "[AEON_BASH] %s\n" "$*"
    fi
}

log_error() {
    if [ "$SILENT_MODE" -eq 1 ]; then
        printf "[AEON_BASH][%s][ERROR] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
    else
        printf "[AEON_BASH][ERROR] %s\n" "$*" >&2
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
            local pkgs="curl git"
            local missing=""
            
            for pkg in $pkgs; do
                if ! command -v "$pkg" >/dev/null 2>&1; then
                    missing="$missing $pkg"
                fi
            done
            
            if [ -n "$missing" ]; then
                log "Installing missing tools:$missing"
                
                if [ "$APT_UPDATED" -eq 0 ]; then
                    apt-get update -qq
                    APT_UPDATED=1
                fi
                
                apt-get install -y -qq $missing
            else
                log "All required tools already installed"
            fi
            ;;
        macos)
            if ! command -v git >/dev/null 2>&1; then
                log "Installing git via Homebrew..."
                sudo -u "$BREW_USER" -H "$BREW_PATH" install git
            else
                log "git already installed"
            fi
            ;;
    esac
}

install_python() {
    log "Checking Python 3..."
    
    if command -v python3 >/dev/null 2>&1; then
        log "Python 3 already installed: $(python3 --version 2>&1)"
        return
    fi
    
    log "Installing Python 3..."
    
    case "$OS_TYPE" in
        linux|wsl)
            if [ "$APT_UPDATED" -eq 0 ]; then
                apt-get update -qq
                APT_UPDATED=1
            fi
            apt-get install -y -qq python3 python3-pip python3-venv
            ;;
        macos)
            sudo -u "$BREW_USER" -H "$BREW_PATH" install python3
            ;;
    esac
    
    log "Python 3 installed: $(python3 --version 2>&1)"
}

install_docker() {
    log "Checking Docker..."
    
    if command -v docker >/dev/null 2>&1; then
        log "Docker already installed: $(docker --version 2>&1 | head -n1)"
        return
    fi
    
    log "Docker not found - skipping Docker installation"
    log "Install manually if needed: https://docs.docker.com/engine/install/"
}

# =============================================================================
# SYSTEM USER
# =============================================================================

create_system_user() {
    if id -u "$AEON_USER" >/dev/null 2>&1; then
        log "System user $AEON_USER already exists"
        return
    fi
    
    log "Creating system user: $AEON_USER"
    
    case "$OS_TYPE" in
        linux|wsl)
            useradd -r -m -d "/home/$AEON_USER" -s /bin/bash "$AEON_USER"
            
            if command -v docker >/dev/null 2>&1; then
                if getent group docker >/dev/null 2>&1; then
                    usermod -aG docker "$AEON_USER" 2>/dev/null || true
                    log "Added $AEON_USER to docker group"
                fi
            fi
            ;;
        macos)
            local next_uid=400
            while dscl . -list /Users UniqueID | awk '{print $2}' | grep -q "^${next_uid}$"; do
                next_uid=$((next_uid + 1))
            done
            
            dscl . -create "/Users/$AEON_USER"
            dscl . -create "/Users/$AEON_USER" UserShell /bin/bash
            dscl . -create "/Users/$AEON_USER" UniqueID "$next_uid"
            dscl . -create "/Users/$AEON_USER" PrimaryGroupID 20
            dscl . -create "/Users/$AEON_USER" NFSHomeDirectory "/Users/$AEON_USER"
            
            mkdir -p "/Users/$AEON_USER"
            chown "$AEON_USER:staff" "/Users/$AEON_USER"
            ;;
    esac
    
    log "System user created successfully"
}

# =============================================================================
# DIRECTORIES
# =============================================================================

setup_directories() {
    log "Setting up AEON directories..."
    
    local dirs="library manifest logfiles tmp"
    
    for dir in $dirs; do
        local path="$AEON_ROOT/$dir"
        if [ ! -d "$path" ]; then
            mkdir -p "$path"
            log "Created directory: $path"
        fi
    done
    
    chown -R "$AEON_USER:$(id -gn "$AEON_USER")" "$AEON_ROOT"
    
    log "Directory structure ready"
}

# =============================================================================
# SUDOERS
# =============================================================================

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
# CLONE REPOSITORY
# =============================================================================

clone_repo() {
    log "Cloning/updating AEON repository..."
    
    REPO_DIR="${AEON_ROOT}/tmp/repo"
    
    if [ -d "$REPO_DIR/.git" ]; then
        log "Repository exists, updating..."
        
        if ! sudo -u "$AEON_USER" -H sh -c "cd '$REPO_DIR' && git fetch --all --prune"; then
            log_error "Failed to fetch repository updates"
            exit 1
        fi
        
        if ! sudo -u "$AEON_USER" -H sh -c "cd '$REPO_DIR' && git reset --hard origin/main"; then
            log_error "Failed to reset repository"
            exit 1
        fi
        
        if ! sudo -u "$AEON_USER" -H sh -c "cd '$REPO_DIR' && git clean -fd"; then
            log_error "Failed to clean repository"
            exit 1
        fi
        
        log "Repository updated successfully"
    else
        log "Cloning repository..."
        mkdir -p "$(dirname "$REPO_DIR")"
        
        if ! sudo -u "$AEON_USER" -H git clone --depth 1 "$AEON_REPO_URL" "$REPO_DIR"; then
            log_error "Failed to clone repository"
            exit 1
        fi
        
        log "Repository cloned successfully"
    fi
    
    chown -R "$AEON_USER:$(id -gn "$AEON_USER")" "$REPO_DIR"
    
    log "Repository ready at: $REPO_DIR"
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
    log "Running orchestrator in native mode..."
    
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
    
    setup_python_venv
    
    local orchestrator="${REPO_DIR}/library/orchestrator/orchestrator.json.py"
    local manifest="${REPO_DIR}/manifest/manifest.install.json"
    local config="${REPO_DIR}/manifest/config/manifest.config.cursed.json"
    
    if [ ! -f "$orchestrator" ]; then
        log_error "Orchestrator not found at: $orchestrator"
        return 1
    fi
    
    # Orchestrator soll relativ zum Repo arbeiten
    local orch_root="$REPO_DIR"
    local manifest_rel="/manifest/manifest.install.json"
    local config_rel="/manifest/config/manifest.config.cursed.json"

    sudo -u "$AEON_USER" -H AEON_ROOT="${orch_root}" python3 "${orchestrator}" \
        $transfer_flags \
        --file:"${manifest_rel}" \
        --config:"${config_rel}"

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
    
    clone_repo
    
    if ! run_orchestrator; then
        log_error "Orchestrator execution failed"
        finalize_installation
        exit 1
    fi
    
    finalize_installation
    exit 0
}

main "$@"