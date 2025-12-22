#!/usr/bin/env bash
# AEON Installation Script
# Supports: Linux (Ubuntu/Debian/Raspbian), macOS, WSL
# Bash 3.2+ compatible
# VERSION: 1.1.0 (Git Repository Mode)

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

AEON_VERSION="6.1.0"

# Git repository configuration
AEON_REPO_URL="${AEON_REPO_URL:-https://github.com/conceptixx/AEON.git}"
AEON_REPO_BRANCH="${AEON_REPO_BRANCH:-main}"
AEON_REPO_LOCAL_PATH="tmp/repo"

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
# GIT INSTALLATION - PREREQUISITE
# =============================================================================

install_git() {
    if command -v git >/dev/null 2>&1; then
        log "Git is already installed: $(git --version)"
        return
    fi
    
    log "Installing git..."
    
    case "$OS_TYPE" in
        linux|wsl)
            install_git_linux
            ;;
        macos)
            install_git_macos
            ;;
    esac
    
    if ! command -v git >/dev/null 2>&1; then
        log_error "Git installation failed or git not in PATH"
        exit 1
    fi
    
    log "Git installed successfully: $(git --version)"
}

install_git_linux() {
    # Detect package manager and install git
    if command -v apt-get >/dev/null 2>&1; then
        log "Installing git via apt-get..."
        if [ "$APT_UPDATED" -eq 0 ]; then
            apt-get update -qq || log_error "apt-get update failed (non-fatal)"
            APT_UPDATED=1
        fi
        apt-get install -y -qq git || {
            log_error "Failed to install git via apt-get"
            exit 1
        }
    elif command -v yum >/dev/null 2>&1; then
        log "Installing git via yum..."
        yum install -y -q git || {
            log_error "Failed to install git via yum"
            exit 1
        }
    elif command -v dnf >/dev/null 2>&1; then
        log "Installing git via dnf..."
        dnf install -y -q git || {
            log_error "Failed to install git via dnf"
            exit 1
        }
    elif command -v pacman >/dev/null 2>&1; then
        log "Installing git via pacman..."
        pacman -Sy --noconfirm git || {
            log_error "Failed to install git via pacman"
            exit 1
        }
    elif command -v apk >/dev/null 2>&1; then
        log "Installing git via apk..."
        apk add --no-cache git || {
            log_error "Failed to install git via apk"
            exit 1
        }
    elif command -v zypper >/dev/null 2>&1; then
        log "Installing git via zypper..."
        zypper install -y git || {
            log_error "Failed to install git via zypper"
            exit 1
        }
    else
        log_error "No supported package manager found for git installation"
        log_error "Please install git manually: apt-get/yum/dnf/pacman/apk/zypper"
        exit 1
    fi
}

install_git_macos() {
    if [ -z "$BREW_PATH" ]; then
        log_error "Homebrew is required to install git on macOS"
        exit 1
    fi
    
    log "Installing git via Homebrew..."
    
    # Brew must NOT run as root - use detected user
    if ! sudo -u "$BREW_USER" -H "$BREW_PATH" install git; then
        log_error "Failed to install git via Homebrew"
        exit 1
    fi
}

# =============================================================================
# PACKAGE INSTALLATION - IDEMPOTENT
# =============================================================================

install_always_tools() {
    log "Checking always-required tools..."
    
    case "$OS_TYPE" in
        linux|wsl)
            if ! command -v curl >/dev/null 2>&1; then
                log "Installing curl..."
                if [ "$APT_UPDATED" -eq 0 ]; then
                    apt-get update -qq || true
                    APT_UPDATED=1
                fi
                apt-get install -y -qq curl || log_error "Failed to install curl (non-fatal)"
            fi
            ;;
        macos)
            # curl is built-in on macOS
            :
            ;;
    esac
    
    log "Always-required tools ready"
}

install_python() {
    if command -v python3 >/dev/null 2>&1; then
        log "Python3 is already installed: $(python3 --version)"
        return
    fi
    
    log "Installing Python3..."
    
    case "$OS_TYPE" in
        linux|wsl)
            if [ "$APT_UPDATED" -eq 0 ]; then
                apt-get update -qq || true
                APT_UPDATED=1
            fi
            apt-get install -y -qq python3 python3-pip python3-venv || {
                log_error "Failed to install Python3"
                exit 1
            }
            ;;
        macos)
            sudo -u "$BREW_USER" -H "$BREW_PATH" install python3 || {
                log_error "Failed to install Python3"
                exit 1
            }
            ;;
    esac
    
    log "Python3 installed: $(python3 --version)"
}

install_docker() {
    if command -v docker >/dev/null 2>&1; then
        log "Docker is already installed: $(docker --version)"
        return
    fi
    
    log "Docker is not installed (skipping - optional)"
}

# =============================================================================
# SYSTEM USER CREATION
# =============================================================================

create_system_user() {
    if id -u "$AEON_USER" >/dev/null 2>&1; then
        log "User $AEON_USER already exists"
        return
    fi
    
    log "Creating system user: $AEON_USER"
    
    case "$OS_TYPE" in
        linux|wsl)
            useradd -r -s /bin/bash -d "$AEON_ROOT" -m "$AEON_USER" || {
                log_error "Failed to create user $AEON_USER"
                exit 1
            }
            
            if command -v docker >/dev/null 2>&1; then
                if getent group docker >/dev/null 2>&1; then
                    usermod -aG docker "$AEON_USER" || true
                    log "Added $AEON_USER to docker group"
                fi
            fi
            ;;
        macos)
            local max_id
            max_id=$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -n | tail -1)
            local new_id=$((max_id + 1))
            
            dscl . -create "/Users/$AEON_USER"
            dscl . -create "/Users/$AEON_USER" UserShell /bin/bash
            dscl . -create "/Users/$AEON_USER" UniqueID "$new_id"
            dscl . -create "/Users/$AEON_USER" PrimaryGroupID 20
            dscl . -create "/Users/$AEON_USER" NFSHomeDirectory "$AEON_ROOT"
            dscl . -create "/Users/$AEON_USER" RealName "AEON System User"
            
            mkdir -p "$AEON_ROOT"
            chown "$AEON_USER:staff" "$AEON_ROOT"
            
            log "Created user $AEON_USER with ID $new_id"
            ;;
    esac
    
    log "User $AEON_USER created successfully"
}

# =============================================================================
# DIRECTORY SETUP
# =============================================================================

setup_directories() {
    log "Setting up directory structure..."
    
    local dirs="logfiles tmp tmp/repo"
    local IFS_OLD="$IFS"
    IFS=" "
    for dir in $dirs; do
        IFS="$IFS_OLD"
        local full_path="$AEON_ROOT/$dir"
        mkdir -p "$full_path"
        chown "$AEON_USER:$(id -gn "$AEON_USER")" "$full_path"
    done
    IFS="$IFS_OLD"
    
    log "Directory structure ready"
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
# GIT REPOSITORY MANAGEMENT
# =============================================================================

clone_or_update_repo() {
    log "Managing AEON repository..."
    
    local repo_path="$AEON_ROOT/$AEON_REPO_LOCAL_PATH"
    
    # Ensure parent directory exists
    mkdir -p "$(dirname "$repo_path")"
    
    if [ -d "$repo_path/.git" ]; then
        log "Repository exists at $repo_path - updating..."
        update_existing_repo "$repo_path"
    else
        log "Cloning repository from $AEON_REPO_URL..."
        clone_new_repo "$repo_path"
    fi
    
    # Set ownership to aeon-system user
    chown -R "$AEON_USER:$(id -gn "$AEON_USER")" "$repo_path"
    
    log "Repository ready at: $repo_path"
}

clone_new_repo() {
    local repo_path="$1"
    
    # Remove any existing non-git directory
    if [ -e "$repo_path" ]; then
        log "Removing existing non-repository directory..."
        rm -rf "$repo_path"
    fi
    
    # Clone as aeon-system user
    if ! sudo -u "$AEON_USER" -H git clone \
        --branch "$AEON_REPO_BRANCH" \
        --depth 1 \
        "$AEON_REPO_URL" \
        "$repo_path"; then
        log_error "Failed to clone repository from $AEON_REPO_URL"
        exit 1
    fi
    
    log "Repository cloned successfully (branch: $AEON_REPO_BRANCH)"
}

update_existing_repo() {
    local repo_path="$1"
    
    # Fetch and hard reset as aeon-system user
    cd "$repo_path"
    
    log "Fetching latest changes..."
    if ! sudo -u "$AEON_USER" -H git fetch --all --prune; then
        log_error "Failed to fetch from remote repository"
        exit 1
    fi
    
    log "Resetting to origin/$AEON_REPO_BRANCH..."
    if ! sudo -u "$AEON_USER" -H git reset --hard "origin/$AEON_REPO_BRANCH"; then
        log_error "Failed to reset repository to origin/$AEON_REPO_BRANCH"
        exit 1
    fi
    
    # Clean untracked files
    sudo -u "$AEON_USER" -H git clean -fd || true
    
    log "Repository updated successfully"
    cd - >/dev/null
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
    log "Running orchestrator from repository..."
    
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
    local repo_path="$AEON_ROOT/$AEON_REPO_LOCAL_PATH"
    local orchestrator="$repo_path/library/orchestrator/orchestrator.json.py"
    local manifest="$repo_path/manifest/manifest.install.json"
    local config="$repo_path/manifest/config/manifest.config.cursed.json"
    
    # Verify files exist
    if [ ! -f "$orchestrator" ]; then
        log_error "Orchestrator not found: $orchestrator"
        return 1
    fi
    if [ ! -f "$manifest" ]; then
        log_error "Manifest not found: $manifest"
        return 1
    fi
    if [ ! -f "$config" ]; then
        log_error "Config not found: $config"
        return 1
    fi
    
    # Run as aeon-system user with AEON_ROOT env set
    sudo -u "$AEON_USER" -H env AEON_ROOT="$AEON_ROOT" \
        "$venv_python" "$orchestrator" \
        $flags \
        "--file:$manifest" \
        "--config:$config"
    
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
    
    local repo_path="$AEON_ROOT/$AEON_REPO_LOCAL_PATH"
    local docker_args="-v $AEON_ROOT:/aeon -w /aeon -e AEON_ROOT=/aeon"
    
    if [ "$AEON_ORCH_DOCKER_SOCKET" -eq 1 ] && [ -S /var/run/docker.sock ]; then
        docker_args="$docker_args -v /var/run/docker.sock:/var/run/docker.sock"
    fi
    
    # Map repository path into container
    local manifest_rel="$AEON_REPO_LOCAL_PATH/manifest/manifest.install.json"
    local config_rel="$AEON_REPO_LOCAL_PATH/manifest/config/manifest.config.cursed.json"
    local orch_rel="$AEON_REPO_LOCAL_PATH/library/orchestrator/orchestrator.json.py"
    
    docker run --rm $docker_args "$AEON_ORCH_DOCKER_IMAGE" \
        python "/aeon/$orch_rel" \
        $flags \
        "--file:/aeon/$manifest_rel" \
        "--config:/aeon/$config_rel"
    
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
        log "Repository: $AEON_ROOT/$AEON_REPO_LOCAL_PATH"
        log ""
        log "Next steps:"
        log "  - Review logs in $AEON_ROOT/logfiles/"
        log "  - Check configuration in $AEON_ROOT/$AEON_REPO_LOCAL_PATH/manifest/"
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
        log "AEON Installer v$AEON_VERSION (Git Repository Mode)"
        log "Starting installation..."
    else
        log "Installation started (silent mode)"
    fi
    
    detect_brew_user
    detect_brew_path
    
    install_always_tools
    install_git
    install_python
    install_docker
    
    create_system_user
    setup_directories
    setup_sudoers
    
    clone_or_update_repo
    
    if ! run_orchestrator; then
        log_error "Orchestrator execution failed"
        finalize_installation
        exit 1
    fi
    
    finalize_installation
    exit 0
}

main "$@"