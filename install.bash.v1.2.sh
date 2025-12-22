#!/usr/bin/env bash
# VERSION: 1.2.0
# AEON Installation Script
# Implements silent mode, git-based architecture, and robust orchestrator execution

set -euo pipefail

#==============================================================================
# CONFIGURATION VARIABLES
#==============================================================================

REPO_URL="https://github.com/conceptixx/AEON.git"
REPO_BRANCH="main"
AEON_USER="aeon-system"

# Sudoers policy for aeon-system user
SUDOERS_REBOOT_CMDS="/sbin/reboot,/usr/sbin/reboot,/sbin/shutdown,/usr/sbin/shutdown"
SUDOERS_INSTALL_CMDS="/usr/bin/curl,/usr/bin/wget,/usr/bin/apt,/usr/bin/apt-get,/usr/bin/dpkg,/usr/bin/yum,/usr/bin/dnf,/usr/bin/pacman,/usr/bin/apk,/usr/bin/zypper,/opt/homebrew/bin/brew,/usr/local/bin/brew"
SUDOERS_DOCKER_CMDS="/usr/bin/docker"

#==============================================================================
# GLOBALS
#==============================================================================

OS_TYPE=""
AEON_ROOT=""
TEMP_LOG=""
FINAL_LOG=""
FLAG_CLI=0
FLAG_WEB=0
FLAG_NONINTERACTIVE=0
AEON_ORCH_MODE="${AEON_ORCH_MODE:-auto}"

#==============================================================================
# LOGGING FUNCTIONS
#==============================================================================

log_raw() {
    local msg="$1"
    if [[ $FLAG_NONINTERACTIVE -eq 1 ]]; then
        echo "$msg" >> "$TEMP_LOG" 2>&1 || true
    else
        echo "$msg"
        [[ -n "$TEMP_LOG" ]] && echo "$msg" >> "$TEMP_LOG" 2>&1 || true
    fi
}

log_info() {
    log_raw "[INFO] $1"
}

log_error() {
    log_raw "[ERROR] $1"
}

log_warn() {
    log_raw "[WARN] $1"
}

migrate_logs() {
    if [[ -n "$TEMP_LOG" ]] && [[ -f "$TEMP_LOG" ]] && [[ -n "$FINAL_LOG" ]]; then
        local log_dir
        log_dir="$(dirname "$FINAL_LOG")"
        mkdir -p "$log_dir" 2>/dev/null || true
        if [[ -d "$log_dir" ]]; then
            cat "$TEMP_LOG" > "$FINAL_LOG" 2>/dev/null || true
            rm -f "$TEMP_LOG" 2>/dev/null || true
            TEMP_LOG="$FINAL_LOG"
        fi
    fi
}

#==============================================================================
# UTILITY FUNCTIONS
#==============================================================================

to_lower() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

exit_with_code() {
    local code=$1
    local msg="${2:-}"
    [[ -n "$msg" ]] && log_error "$msg"
    migrate_logs
    exit "$code"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        if [[ $FLAG_NONINTERACTIVE -eq 1 ]]; then
            exit 1
        else
            exit_with_code 1 "This script must be run as root (use sudo)"
        fi
    fi
}

detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS_TYPE="macos"
        AEON_ROOT="/usr/local/aeon"
    elif [[ "$OSTYPE" == "linux-gnu"* ]] || [[ -f /proc/version ]]; then
        OS_TYPE="linux"
        AEON_ROOT="/opt/aeon"
    else
        exit_with_code 1 "Unsupported OS: $OSTYPE"
    fi
    log_info "Detected OS: $OS_TYPE, AEON_ROOT: $AEON_ROOT"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

#==============================================================================
# ARGUMENT PARSING
#==============================================================================

parse_args() {
    local flag_count=0
    while [[ $# -gt 0 ]]; do
        local arg="$1"
        local arg_lower
        arg_lower="$(to_lower "$arg")"
        
        case "$arg_lower" in
            -c|--cli-enable|--enable-cli)
                FLAG_CLI=1
                ((flag_count++))
                ;;
            -w|--web-enable|--enable-web)
                FLAG_WEB=1
                ((flag_count++))
                ;;
            -n|--noninteractive)
                FLAG_NONINTERACTIVE=1
                ((flag_count++))
                ;;
            *)
                exit_with_code 2 "Unknown flag: $arg"
                ;;
        esac
        shift
    done
    
    if [[ $flag_count -gt 3 ]]; then
        exit_with_code 2 "Too many flags (max 3)"
    fi
}

#==============================================================================
# SYSTEM USER CREATION
#==============================================================================

create_system_user() {
    log_info "Creating system user: $AEON_USER"
    
    if [[ "$OS_TYPE" == "linux" ]]; then
        if id "$AEON_USER" >/dev/null 2>&1; then
            log_info "User $AEON_USER already exists"
        else
            useradd -r -s /usr/sbin/nologin -d "$AEON_ROOT" -M "$AEON_USER" 2>/dev/null || \
            useradd -r -s /sbin/nologin -d "$AEON_ROOT" -M "$AEON_USER" 2>/dev/null || \
            useradd -r -s /bin/false -d "$AEON_ROOT" -M "$AEON_USER" || \
                exit_with_code 1 "Failed to create system user"
        fi
    elif [[ "$OS_TYPE" == "macos" ]]; then
        if dscl . -read "/Users/$AEON_USER" >/dev/null 2>&1; then
            log_info "User $AEON_USER already exists"
        else
            local max_uid
            max_uid=$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -n | tail -1)
            local new_uid=$((max_uid + 1))
            [[ $new_uid -lt 500 ]] && new_uid=500
            
            dscl . -create "/Users/$AEON_USER"
            dscl . -create "/Users/$AEON_USER" UserShell /usr/bin/false
            dscl . -create "/Users/$AEON_USER" RealName "AEON System User"
            dscl . -create "/Users/$AEON_USER" UniqueID "$new_uid"
            dscl . -create "/Users/$AEON_USER" PrimaryGroupID 20
            dscl . -create "/Users/$AEON_USER" NFSHomeDirectory "$AEON_ROOT"
        fi
    fi
}

#==============================================================================
# SUDOERS CONFIGURATION
#==============================================================================

configure_sudoers() {
    log_info "Configuring sudoers for $AEON_USER"
    
    local sudoers_file="/etc/sudoers.d/$AEON_USER"
    local sudoers_content="# AEON System User Privileges
$AEON_USER ALL=(ALL) NOPASSWD: $SUDOERS_REBOOT_CMDS
$AEON_USER ALL=(ALL) NOPASSWD: $SUDOERS_INSTALL_CMDS
$AEON_USER ALL=(ALL) NOPASSWD: $SUDOERS_DOCKER_CMDS
"
    
    echo "$sudoers_content" > "$sudoers_file"
    chmod 0440 "$sudoers_file"
    
    if ! visudo -c -f "$sudoers_file" >/dev/null 2>&1; then
        rm -f "$sudoers_file"
        exit_with_code 1 "Invalid sudoers configuration"
    fi
    
    log_info "Sudoers configuration validated"
}

#==============================================================================
# DEPENDENCY INSTALLATION
#==============================================================================

install_dependencies_linux() {
    log_info "Installing dependencies for Linux"
    
    local pkg_manager=""
    local install_cmd=""
    local update_cmd=""
    
    if command_exists apt-get; then
        pkg_manager="apt"
        update_cmd="apt-get update -qq"
        install_cmd="apt-get install -y -qq"
    elif command_exists yum; then
        pkg_manager="yum"
        update_cmd="yum makecache -q"
        install_cmd="yum install -y -q"
    elif command_exists dnf; then
        pkg_manager="dnf"
        update_cmd="dnf makecache -q"
        install_cmd="dnf install -y -q"
    elif command_exists pacman; then
        pkg_manager="pacman"
        update_cmd="pacman -Sy --noconfirm"
        install_cmd="pacman -S --noconfirm --needed"
    elif command_exists apk; then
        pkg_manager="apk"
        update_cmd="apk update -q"
        install_cmd="apk add -q"
    elif command_exists zypper; then
        pkg_manager="zypper"
        update_cmd="zypper refresh"
        install_cmd="zypper install -y"
    else
        exit_with_code 1 "No supported package manager found"
    fi
    
    log_info "Using package manager: $pkg_manager"
    eval "$update_cmd" >/dev/null 2>&1 || true
    
    local base_packages="git ca-certificates"
    if ! command_exists curl && ! command_exists wget; then
        base_packages="$base_packages curl"
    fi
    
    eval "$install_cmd $base_packages" >/dev/null 2>&1 || true
    
    if [[ "$pkg_manager" == "apt" ]]; then
        eval "$install_cmd python3 python3-venv python3-pip python-is-python3" >/dev/null 2>&1 || true
    elif [[ "$pkg_manager" == "yum" ]] || [[ "$pkg_manager" == "dnf" ]]; then
        eval "$install_cmd python3 python3-pip" >/dev/null 2>&1 || true
    else
        eval "$install_cmd python3" >/dev/null 2>&1 || true
    fi
    
    if ! command_exists python3; then
        exit_with_code 1 "Failed to install python3"
    fi
}

install_dependencies_macos() {
    log_info "Installing dependencies for macOS"
    
    if ! command_exists brew; then
        exit_with_code 1 "Homebrew is required on macOS. Install from https://brew.sh (DO NOT run as root)"
    fi
    
    if ! command_exists git; then
        sudo -u "$SUDO_USER" brew install git >/dev/null 2>&1 || true
    fi
    
    if ! command_exists python3; then
        sudo -u "$SUDO_USER" brew install python3 >/dev/null 2>&1 || exit_with_code 1 "Failed to install python3"
    fi
}

install_docker_linux() {
    log_info "Checking Docker availability on Linux"
    
    if command_exists docker; then
        if timeout 5 docker info >/dev/null 2>&1; then
            log_info "Docker daemon is available"
            return 0
        else
            log_warn "Docker command exists but daemon is not available"
        fi
    fi
    
    log_info "Installing Docker Engine"
    
    local distro=""
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        distro="$ID"
    fi
    
    if [[ "$distro" == "ubuntu" ]] || [[ "$distro" == "debian" ]]; then
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq ca-certificates curl gnupg >/dev/null 2>&1 || true
        
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/${distro}/gpg -o /etc/apt/keyrings/docker.asc 2>/dev/null || true
        chmod a+r /etc/apt/keyrings/docker.asc 2>/dev/null || true
        
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${distro} $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
        
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io >/dev/null 2>&1 || true
        
        systemctl start docker >/dev/null 2>&1 || true
        systemctl enable docker >/dev/null 2>&1 || true
    else
        log_warn "Docker auto-install only supported on Ubuntu/Debian. Skipping Docker installation."
    fi
    
    if command_exists docker && timeout 5 docker info >/dev/null 2>&1; then
        log_info "Docker installed and running"
        usermod -aG docker "$AEON_USER" 2>/dev/null || true
        return 0
    else
        log_warn "Docker installation unsuccessful or daemon not available"
        return 1
    fi
}

check_docker_macos() {
    log_info "Checking Docker on macOS"
    
    if command_exists docker && timeout 5 docker info >/dev/null 2>&1; then
        log_info "Docker is available on macOS"
        return 0
    else
        log_warn "Docker not available on macOS (will use native mode)"
        return 1
    fi
}

#==============================================================================
# GIT REPOSITORY MANAGEMENT
#==============================================================================

setup_git_repo() {
    log_info "Setting up AEON repository"
    
    local repo_path="$AEON_ROOT/tmp/repo"
    
    mkdir -p "$AEON_ROOT/tmp"
    chown -R "$AEON_USER:$(id -gn "$AEON_USER" 2>/dev/null || echo "$AEON_USER")" "$AEON_ROOT/tmp" 2>/dev/null || \
    chown -R "$AEON_USER:staff" "$AEON_ROOT/tmp" 2>/dev/null || \
    chown -R "$AEON_USER" "$AEON_ROOT/tmp"
    
    if [[ -d "$repo_path/.git" ]]; then
        log_info "Repository exists, updating"
        sudo -u "$AEON_USER" git -C "$repo_path" fetch origin >/dev/null 2>&1 || exit_with_code 1 "Failed to fetch repository"
        sudo -u "$AEON_USER" git -C "$repo_path" reset --hard "origin/$REPO_BRANCH" >/dev/null 2>&1 || exit_with_code 1 "Failed to reset repository"
        sudo -u "$AEON_USER" git -C "$repo_path" clean -fd >/dev/null 2>&1 || true
    else
        log_info "Cloning repository"
        rm -rf "$repo_path"
        sudo -u "$AEON_USER" git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$repo_path" >/dev/null 2>&1 || exit_with_code 1 "Failed to clone repository"
    fi
    
    log_info "Repository setup complete"
}

sync_runtime_files() {
    log_info "Syncing runtime files from repository"
    
    local repo_path="$AEON_ROOT/tmp/repo"
    
    if [[ -d "$repo_path/library" ]]; then
        if [[ ! -d "$AEON_ROOT/library" ]] || [[ -z "$(ls -A "$AEON_ROOT/library" 2>/dev/null)" ]]; then
            log_info "Copying library files"
            mkdir -p "$AEON_ROOT/library"
            cp -r "$repo_path/library"/* "$AEON_ROOT/library/" 2>/dev/null || true
        fi
    fi
    
    mkdir -p "$AEON_ROOT/manifest/config"
    
    if [[ -f "$repo_path/manifest.install.json" ]] && [[ ! -f "$AEON_ROOT/manifest/manifest.install.json" ]]; then
        cp "$repo_path/manifest.install.json" "$AEON_ROOT/manifest/" 2>/dev/null || true
    fi
    
    if [[ -f "$repo_path/manifest.config.cursed.json" ]] && [[ ! -f "$AEON_ROOT/manifest/config/manifest.config.cursed.json" ]]; then
        cp "$repo_path/manifest.config.cursed.json" "$AEON_ROOT/manifest/config/" 2>/dev/null || true
    fi
    
    chown -R "$AEON_USER:$(id -gn "$AEON_USER" 2>/dev/null || echo "$AEON_USER")" "$AEON_ROOT" 2>/dev/null || \
    chown -R "$AEON_USER:staff" "$AEON_ROOT" 2>/dev/null || \
    chown -R "$AEON_USER" "$AEON_ROOT"
    
    log_info "Runtime files synced"
}

#==============================================================================
# ORCHESTRATOR EXECUTION
#==============================================================================

run_orchestrator_docker() {
    log_info "Running orchestrator in Docker mode"
    
    local orch_args=""
    [[ $FLAG_CLI -eq 1 ]] && orch_args="$orch_args --enable-cli"
    [[ $FLAG_WEB -eq 1 ]] && orch_args="$orch_args --enable-web"
    orch_args="$orch_args --file:/manifest/manifest.install.json --config:/manifest/config/manifest.config.cursed.json"
    
    local docker_cmd="docker run --rm -v $AEON_ROOT:/aeon -e AEON_ROOT=/aeon -w /aeon python:3.11-slim python /aeon/tmp/repo/orchestrator.json.py $orch_args"
    
    if sudo -u "$AEON_USER" $docker_cmd >/dev/null 2>&1; then
        log_info "Orchestrator completed successfully (Docker mode)"
        return 0
    else
        log_warn "Docker mode failed, falling back to native mode"
        return 1
    fi
}

run_orchestrator_native() {
    log_info "Running orchestrator in native mode"
    
    local venv_path="$AEON_ROOT/tmp/venv"
    
    if [[ ! -d "$venv_path" ]]; then
        log_info "Creating Python virtual environment"
        sudo -u "$AEON_USER" python3 -m venv "$venv_path" >/dev/null 2>&1 || exit_with_code 1 "Failed to create venv"
    fi
    
    local orch_args=""
    [[ $FLAG_CLI -eq 1 ]] && orch_args="$orch_args --enable-cli"
    [[ $FLAG_WEB -eq 1 ]] && orch_args="$orch_args --enable-web"
    orch_args="$orch_args --file:/manifest/manifest.install.json --config:/manifest/config/manifest.config.cursed.json"
    
    local orch_script="$AEON_ROOT/tmp/repo/orchestrator.json.py"
    
    if [[ ! -f "$orch_script" ]]; then
        exit_with_code 1 "Orchestrator script not found: $orch_script"
    fi
    
    sudo -u "$AEON_USER" AEON_ROOT="$AEON_ROOT" "$venv_path/bin/python" "$orch_script" $orch_args >/dev/null 2>&1 || exit_with_code 1 "Orchestrator failed"
    
    log_info "Orchestrator completed successfully (native mode)"
}

run_orchestrator() {
    log_info "Determining orchestrator execution mode: $AEON_ORCH_MODE"
    
    local use_docker=0
    
    if [[ "$AEON_ORCH_MODE" == "docker" ]]; then
        use_docker=1
    elif [[ "$AEON_ORCH_MODE" == "native" ]]; then
        use_docker=0
    else
        if command_exists docker && timeout 5 docker info >/dev/null 2>&1; then
            use_docker=1
        else
            use_docker=0
        fi
    fi
    
    if [[ $use_docker -eq 1 ]]; then
        if run_orchestrator_docker; then
            return 0
        fi
    fi
    
    run_orchestrator_native
}

#==============================================================================
# MAIN EXECUTION
#==============================================================================

main() {
    TEMP_LOG="/tmp/aeon-install-$$.log"
    touch "$TEMP_LOG" 2>/dev/null || TEMP_LOG="/tmp/aeon-install.log"
    
    parse_args "$@"
    
    check_root
    detect_os
    
    mkdir -p "$AEON_ROOT/logfiles" 2>/dev/null || true
    FINAL_LOG="$AEON_ROOT/logfiles/install.bash.$(date +%Y%m%d-%H%M%S).log"
    migrate_logs
    
    log_info "AEON Installation Starting - Version 1.2.0"
    log_info "Flags: CLI=$FLAG_CLI, WEB=$FLAG_WEB, NonInteractive=$FLAG_NONINTERACTIVE"
    
    if [[ "$OS_TYPE" == "linux" ]]; then
        install_dependencies_linux
        install_docker_linux || log_warn "Proceeding without Docker"
    else
        install_dependencies_macos
        check_docker_macos || log_warn "Proceeding without Docker"
    fi
    
    create_system_user
    configure_sudoers
    
    mkdir -p "$AEON_ROOT"
    mkdir -p "$AEON_ROOT/tmp"
    mkdir -p "$AEON_ROOT/logfiles"
    
    setup_git_repo
    sync_runtime_files
    
    chown -R "$AEON_USER:$(id -gn "$AEON_USER" 2>/dev/null || echo "$AEON_USER")" "$AEON_ROOT" 2>/dev/null || \
    chown -R "$AEON_USER:staff" "$AEON_ROOT" 2>/dev/null || \
    chown -R "$AEON_USER" "$AEON_ROOT"
    
    run_orchestrator
    
    log_info "AEON Installation Complete"
    log_info "Logs available at: $FINAL_LOG"
    
    exit 0
}

if [[ $FLAG_NONINTERACTIVE -eq 1 ]]; then
    exec 1>/dev/null 2>&1
fi

main "$@"