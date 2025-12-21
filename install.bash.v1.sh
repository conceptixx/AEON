#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# AEON Installation Script - install.bash.sh
# Must run as root. Supports Linux (Ubuntu/Debian/Raspbian/WSL) and macOS.
###############################################################################

AEON_BASE_URL="https://raw.githubusercontent.com/conceptixx/AEON/main"
AEON_ROOT="/opt/aeon"
AEON_USER="aeon-system"
AEON_LOGDIR="${AEON_ROOT}/logfiles"
LOG_TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOGFILE="${AEON_LOGDIR}/install.bash.${LOG_TIMESTAMP}.log"

AEON_ORCH_MODE="auto"
AEON_ORCH_DOCKER_IMAGE="python:3.11-slim"
AEON_ORCH_DOCKER_PULL=1
AEON_ORCH_DOCKER_SOCKET=1

SUDOERS_INSTALL_CMDS="/usr/bin/apt-get /usr/bin/apt /usr/bin/dpkg /usr/bin/apt-cache /usr/bin/apt-mark \
/usr/bin/curl /usr/bin/wget /usr/bin/tee /bin/mkdir /bin/cp /bin/mv /bin/rm /bin/ln /bin/chmod /bin/chown \
/bin/systemctl /usr/sbin/service /usr/bin/journalctl \
/usr/sbin/useradd /usr/sbin/usermod /usr/sbin/groupadd /usr/sbin/groupmod \
/usr/bin/python3 /usr/bin/pip /usr/bin/pip3 /usr/local/bin/python3 /usr/local/bin/pip /usr/local/bin/pip3 \
/usr/local/bin/brew /opt/homebrew/bin/brew"

FLAG_CLI=""
FLAG_WEB=""
FLAG_NONINTERACTIVE=0
DETECTED_OS=""

###############################################################################
# Early silent-mode activation
#
# Requirement: If -n/--noninteractive is present, the script must be silent
# (no stdout/stderr output) and log everything to LOGFILE.
#
# We do a minimal pre-scan here in the global scope so even the earliest
# log/error output is redirected.
###############################################################################
for __aeon_arg in "$@"; do
    __aeon_lower="$(printf '%s' "$__aeon_arg" | tr '[:upper:]' '[:lower:]')"
    case "$__aeon_lower" in
        -n|--noninteractive)
            FLAG_NONINTERACTIVE=1
            break
            ;;
    esac
done

if [ "$FLAG_NONINTERACTIVE" -eq 1 ]; then
    mkdir -p "$AEON_LOGDIR" 2>/dev/null || true
    exec >>"$LOGFILE" 2>&1
fi

###############################################################################
# Pre-scan for -n/--noninteractive before any output
###############################################################################
pre_scan_silent() {
    for arg in "$@"; do
        local lower
        lower="$(printf '%s' "$arg" | tr '[:upper:]' '[:lower:]')"
        case "$lower" in
            -n|--noninteractive)
                FLAG_NONINTERACTIVE=1
                return
                ;;
        esac
    done
}

###############################################################################
# Setup logging (create dir, redirect if silent)
###############################################################################
setup_logging() {
    mkdir -p "$AEON_LOGDIR" 2>/dev/null || true
    if [ "$FLAG_NONINTERACTIVE" -eq 1 ]; then
        exec >>"$LOGFILE" 2>&1
    fi
}

###############################################################################
# Logging helpers
###############################################################################
log_info() {
    printf '[INFO] %s\n' "$*"
}

log_error() {
    printf '[ERROR] %s\n' "$*" >&2
}

log_warn() {
    printf '[WARN] %s\n' "$*" >&2
}

###############################################################################
# Usage
###############################################################################
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

OPTIONS:
  -c, -C, --cli-enable, --enable-cli       Enable CLI mode
  -w, -W, --web-enable, --enable-web       Enable Web mode
  -n, -N, --noninteractive                 Silent mode (log only)

All long flags are case-insensitive.
EOF
}

###############################################################################
# Parse flags
###############################################################################
parse_flags() {
    for arg in "$@"; do
        local lower
        lower="$(printf '%s' "$arg" | tr '[:upper:]' '[:lower:]')"
        case "$lower" in
            -c|--cli-enable|--enable-cli)
                FLAG_CLI="--enable-cli"
                ;;
            -w|--web-enable|--enable-web)
                FLAG_WEB="--enable-web"
                ;;
            -n|--noninteractive)
                FLAG_NONINTERACTIVE=1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown argument: $arg"
                usage
                exit 2
                ;;
        esac
    done
}

###############################################################################
# Check root
###############################################################################
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

###############################################################################
# Detect OS
###############################################################################
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [ -n "${ID:-}" ]; then
            DETECTED_OS="$ID"
        fi
    fi
    
    if [ "$(uname)" = "Darwin" ]; then
        DETECTED_OS="macos"
    fi
    
    if [ -z "$DETECTED_OS" ]; then
        DETECTED_OS="linux"
    fi
    
    log_info "Detected OS: $DETECTED_OS"
}

###############################################################################
# Ensure common tools
###############################################################################
ensure_common() {
    log_info "Ensuring common tools: curl, wget, ca-certificates"
    
    case "$DETECTED_OS" in
        macos)
            if ! command -v curl >/dev/null 2>&1; then
                log_error "curl not found on macOS"
                exit 1
            fi
            if ! command -v wget >/dev/null 2>&1; then
                if command -v brew >/dev/null 2>&1; then
                    brew install wget
                else
                    log_warn "wget not found, but continuing"
                fi
            fi
            ;;
        ubuntu|debian|raspbian)
            apt-get update -qq
            apt-get install -y -qq curl wget ca-certificates
            ;;
        *)
            log_warn "Unknown OS, attempting apt-get"
            apt-get update -qq || true
            apt-get install -y -qq curl wget ca-certificates || true
            ;;
    esac
}

###############################################################################
# Ensure Linux tools
###############################################################################
ensure_linux() {
    log_info "Installing Linux-specific tools"
    apt-get update -qq
    apt-get install -y -qq python3 python3-pip python3-venv python-is-python3
}

###############################################################################
# Ensure macOS tools
###############################################################################
ensure_macos() {
    log_info "Checking macOS tools"
    
    if ! command -v brew >/dev/null 2>&1; then
        log_error "Homebrew not found. Please install from https://brew.sh"
        exit 1
    fi
    
    if ! command -v python3 >/dev/null 2>&1; then
        log_info "Installing python3 via brew"
        brew install python3
    fi
    
    if ! python3 -m venv --help >/dev/null 2>&1; then
        log_warn "venv module check failed, but continuing"
    fi
}

###############################################################################
# Ensure Docker on Linux
###############################################################################
ensure_docker_linux() {
    if command -v docker >/dev/null 2>&1; then
        log_info "Docker already installed"
        return
    fi
    
    log_info "Installing Docker Engine"
    
    local distro="$DETECTED_OS"
    if [ "$distro" = "raspbian" ]; then
        distro="debian"
    fi
    
    case "$distro" in
        ubuntu|debian)
            ;;
        *)
            log_error "Unsupported distro for Docker installation: $distro"
            exit 1
            ;;
    esac
    
    apt-get update -qq
    apt-get install -y -qq apt-transport-https ca-certificates curl gnupg lsb-release
    
    mkdir -p /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/${distro}/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/%s %s stable\n' \
        "$(dpkg --print-architecture)" "$distro" "$(lsb_release -cs)" | \
        tee /etc/apt/sources.list.d/docker.list >/dev/null
    
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable docker
        systemctl start docker
    else
        service docker start || true
    fi
    
    log_info "Docker installed successfully"
}

###############################################################################
# Download repository file
###############################################################################
download_repo_file() {
    local remote_path="$1"
    local local_path="$2"
    
    mkdir -p "$(dirname "$local_path")"
    
    local url="${AEON_BASE_URL}${remote_path}"
    log_info "Downloading: $url -> $local_path"
    
    if ! curl -fsSL "$url" -o "$local_path"; then
        log_error "Failed to download $url"
        exit 1
    fi
}

###############################################################################
# Ensure AEON user and sudoers
###############################################################################
ensure_user_sudoers() {
    log_info "Creating system user: $AEON_USER"
    
    if ! id "$AEON_USER" >/dev/null 2>&1; then
        if [ "$DETECTED_OS" = "macos" ]; then
            local maxid
            maxid=$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -n | tail -1)
            local newid=$((maxid + 1))
            dscl . -create "/Users/$AEON_USER"
            dscl . -create "/Users/$AEON_USER" UserShell /usr/bin/false
            dscl . -create "/Users/$AEON_USER" UniqueID "$newid"
            dscl . -create "/Users/$AEON_USER" PrimaryGroupID 20
        else
            useradd -r -s /usr/sbin/nologin "$AEON_USER" 2>/dev/null || \
            useradd -r -s /bin/false "$AEON_USER" 2>/dev/null || true
        fi
    fi
    
    log_info "Setting ownership: $AEON_ROOT -> $AEON_USER"
    chown -R "$AEON_USER:$AEON_USER" "$AEON_ROOT" 2>/dev/null || \
    chown -R "$AEON_USER:staff" "$AEON_ROOT" 2>/dev/null || true
    
    local sudoers_file="/etc/sudoers.d/aeon-system"
    log_info "Creating sudoers file: $sudoers_file"
    
    cat >"$sudoers_file" <<SUDOEOF
# AEON system user permissions
$AEON_USER ALL=(ALL) NOPASSWD: /sbin/reboot
$AEON_USER ALL=(ALL) NOPASSWD: /sbin/shutdown -r now
$AEON_USER ALL=(ALL) NOPASSWD: /bin/systemctl reboot
$AEON_USER ALL=(ALL) NOPASSWD: $SUDOERS_INSTALL_CMDS
$AEON_USER ALL=(ALL) NOPASSWD: /usr/bin/docker
$AEON_USER ALL=(ALL) NOPASSWD: /usr/local/bin/docker
SUDOEOF
    
    chmod 0440 "$sudoers_file"
    
    if command -v visudo >/dev/null 2>&1; then
        if ! visudo -c -f "$sudoers_file"; then
            log_error "Sudoers file validation failed"
            rm -f "$sudoers_file"
            exit 1
        fi
    fi
    
    log_info "Sudoers configured successfully"
}

###############################################################################
# Ensure venv
###############################################################################
ensure_venv() {
    local venv_path="${AEON_ROOT}/venv"
    
    if [ -d "$venv_path" ]; then
        log_info "Virtual environment already exists: $venv_path"
        return
    fi
    
    log_info "Creating virtual environment: $venv_path"
    python3 -m venv "$venv_path"
    
    log_info "Upgrading pip in venv"
    "$venv_path/bin/pip" install --upgrade pip -q 2>/dev/null || true
    
    chown -R "$AEON_USER:$AEON_USER" "$venv_path" 2>/dev/null || \
    chown -R "$AEON_USER:staff" "$venv_path" 2>/dev/null || true
}

###############################################################################
# Run orchestrator in native mode
###############################################################################
run_orchestrator_native() {
    log_info "Running orchestrator in NATIVE mode"
    
    local orch_script="${AEON_ROOT}/library/orchestrator/orchestrator.json.py"
    local venv_python="${AEON_ROOT}/venv/bin/python"
    
    local args=""
    [ -n "$FLAG_CLI" ] && args="$args $FLAG_CLI"
    [ -n "$FLAG_WEB" ] && args="$args $FLAG_WEB"
    [ "$FLAG_NONINTERACTIVE" -eq 1 ] && args="$args --noninteractive"
    
    args="$args --file:/manifest/manifest.install.json"
    args="$args --config:/manifest/config/manifest.config.cursed.json"
    
    log_info "Executing: sudo -u $AEON_USER $venv_python $orch_script $args"
    
    if [ "$DETECTED_OS" = "macos" ]; then
        sudo -u "$AEON_USER" "$venv_python" "$orch_script" $args
    else
        sudo -u "$AEON_USER" "$venv_python" "$orch_script" $args
    fi
}

###############################################################################
# Run orchestrator in docker mode
###############################################################################
run_orchestrator_docker() {
    log_info "Running orchestrator in DOCKER mode"
    
    if [ "$AEON_ORCH_DOCKER_PULL" -eq 1 ]; then
        log_info "Pulling Docker image: $AEON_ORCH_DOCKER_IMAGE"
        docker pull "$AEON_ORCH_DOCKER_IMAGE"
    fi
    
    local orch_script="/opt/aeon/library/orchestrator/orchestrator.json.py"
    
    local args=""
    [ -n "$FLAG_CLI" ] && args="$args $FLAG_CLI"
    [ -n "$FLAG_WEB" ] && args="$args $FLAG_WEB"
    [ "$FLAG_NONINTERACTIVE" -eq 1 ] && args="$args --noninteractive"
    
    args="$args --file:/manifest/manifest.install.json"
    args="$args --config:/manifest/config/manifest.config.cursed.json"
    
    local docker_args="--rm -v ${AEON_ROOT}:/opt/aeon -w /opt/aeon"
    
    if [ "$AEON_ORCH_DOCKER_SOCKET" -eq 1 ] && [ -S /var/run/docker.sock ]; then
        docker_args="$docker_args -v /var/run/docker.sock:/var/run/docker.sock"
    fi
    
    log_info "Executing: docker run $docker_args $AEON_ORCH_DOCKER_IMAGE python3 $orch_script $args"
    
    docker run $docker_args "$AEON_ORCH_DOCKER_IMAGE" python3 "$orch_script" $args
}

###############################################################################
# Run orchestrator with mode detection
###############################################################################
run_orchestrator() {
    local mode="$AEON_ORCH_MODE"
    
    if [ "$mode" = "auto" ]; then
        if command -v docker >/dev/null 2>&1; then
            if command -v timeout >/dev/null 2>&1; then
                timeout 5 docker info >/dev/null 2>&1 && mode="docker" || mode="native"
            else
                docker info >/dev/null 2>&1 && mode="docker" || mode="native"
            fi
        else
            mode="native"
        fi
        log_info "Auto-detected mode: $mode"
    fi
    
    case "$mode" in
        docker)
            run_orchestrator_docker
            ;;
        native)
            run_orchestrator_native
            ;;
        *)
            log_error "Invalid AEON_ORCH_MODE: $mode"
            exit 1
            ;;
    esac
}

###############################################################################
# Main
###############################################################################
main() {
    pre_scan_silent "$@"
    setup_logging
    
    log_info "=== AEON Installation Started ==="
    
    check_root
    parse_flags "$@"
    detect_os
    ensure_common
    
    case "$DETECTED_OS" in
        macos)
            ensure_macos
            ;;
        ubuntu|debian|raspbian)
            ensure_linux
            ensure_docker_linux
            ;;
        *)
            log_warn "Unknown OS: $DETECTED_OS, attempting Linux setup"
            ensure_linux
            ensure_docker_linux
            ;;
    esac
    
    log_info "Downloading AEON repository files"
    download_repo_file "/library/orchestrator/orchestrator.json.py" \
                       "${AEON_ROOT}/library/orchestrator/orchestrator.json.py"
    download_repo_file "/manifest/manifest.install.json" \
                       "${AEON_ROOT}/manifest/manifest.install.json"
    download_repo_file "/manifest/config/manifest.config.cursed.json" \
                       "${AEON_ROOT}/manifest/config/manifest.config.cursed.json"
    
    ensure_user_sudoers
    
    if [ "$AEON_ORCH_MODE" = "native" ] || \
       { [ "$AEON_ORCH_MODE" = "auto" ] && ! command -v docker >/dev/null 2>&1; }; then
        ensure_venv
    fi
    
    run_orchestrator
    
    log_info "=== AEON Installation Completed Successfully ==="
}

main "$@"