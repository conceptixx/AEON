#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# AEON Installation Script - install.bash.sh
#
# - Must run as root.
# - OS: Linux (Ubuntu/Debian/Raspbian/WSL) and macOS.
# - Flags (max 3): -c/-C/--cli-enable/--enable-cli, -w/-W/--web-enable/--enable-web, -n/-N/--noninteractive
#   Long flags are case-insensitive.
# - -c/-w are only forwarded to orchestrator.json.py.
# - -n enables absolute silent mode (no stdout/stderr), logging to file.
###############################################################################

# ----------------------------- Config (Header) ------------------------------

AEON_BASE_URL="https://raw.githubusercontent.com/conceptixx/AEON/main"
AEON_ROOT="/opt/aeon"
AEON_USER="aeon-system"

AEON_LOGDIR="${AEON_ROOT}/logfiles"   # preferred
AEON_LOGDIR_FALLBACK="/tmp/aeon-logfiles"  # used if AEON_LOGDIR cannot be created/opened early

AEON_ORCH_MODE="auto"                 # auto|native|docker
AEON_ORCH_DOCKER_IMAGE="python:3.11-slim"
AEON_ORCH_DOCKER_PULL=1
AEON_ORCH_DOCKER_SOCKET=1

# "Broad" install/ops commands for NOPASSWD in sudoers (user-editable)
SUDOERS_INSTALL_CMDS="/usr/bin/apt-get /usr/bin/apt /usr/bin/dpkg /usr/bin/apt-cache /usr/bin/apt-mark \
/usr/bin/curl /usr/bin/wget /usr/bin/tee /bin/mkdir /bin/cp /bin/mv /bin/rm /bin/ln /bin/chmod /bin/chown \
/bin/systemctl /usr/sbin/service /usr/bin/journalctl \
/usr/sbin/useradd /usr/sbin/usermod /usr/sbin/groupadd /usr/sbin/groupmod \
/usr/bin/python3 /usr/bin/pip /usr/bin/pip3 /usr/local/bin/python3 /usr/local/bin/pip /usr/local/bin/pip3 \
/usr/local/bin/brew /opt/homebrew/bin/brew"

SUDOERS_REBOOT_CMDS="/sbin/reboot /usr/sbin/reboot /sbin/shutdown -r now /usr/sbin/shutdown -r now /bin/systemctl reboot /usr/bin/systemctl reboot"
SUDOERS_DOCKER_CMDS="/usr/bin/docker /usr/local/bin/docker"

# ----------------------------- State ----------------------------------------

FLAG_CLI=0
FLAG_WEB=0
FLAG_NONINTERACTIVE=0
DETECTED_OS=""

LOG_TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOGFILE=""  # computed in early silent init

# ----------------------------- Helpers --------------------------------------

to_lower() {
  # Bash 3.2 safe
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

log_info() { printf '[INFO] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*" >&2; }
log_error(){ printf '[ERROR] %s\n' "$*" >&2; }

usage() {
  cat <<EOF
Usage: $0 [-c|--cli-enable] [-w|--web-enable] [-n|--noninteractive]
Only these flags are allowed (max 3). Long flags are case-insensitive.
EOF
}

die_usage() {
  log_error "$*"
  usage
  exit 2
}

die() {
  log_error "$*"
  exit 1
}

# ----------------------------- Early silent mode ----------------------------

early_init_silent() {
  # Pre-scan args in global scope for -n/--noninteractive (case-insensitive).
  # Must not print anything.
  local arg lower
  for arg in "$@"; do
    lower="$(to_lower "$arg")"
    case "$lower" in
      -n|--noninteractive) FLAG_NONINTERACTIVE=1; break ;;
    esac
  done

  if [ "$FLAG_NONINTERACTIVE" -eq 1 ]; then
    local logdir candidate
    logdir="$AEON_LOGDIR"

    # Try preferred logdir silently (may fail before root check).
    if ( mkdir -p "$logdir" ) 2>/dev/null; then
      candidate="${logdir}/install.bash.${LOG_TIMESTAMP}.log"
      if ! ( : >>"$candidate" ) 2>/dev/null; then
        logdir="$AEON_LOGDIR_FALLBACK"
      fi
    else
      logdir="$AEON_LOGDIR_FALLBACK"
    fi

    ( mkdir -p "$logdir" ) 2>/dev/null || true
    candidate="${logdir}/install.bash.${LOG_TIMESTAMP}.log"

    # Ensure file is openable without emitting errors.
    if ( : >>"$candidate" ) 2>/dev/null; then
      LOGFILE="$candidate"
    else
      LOGFILE="/tmp/install.bash.${LOG_TIMESTAMP}.log"
      ( : >>"$LOGFILE" ) 2>/dev/null || true
    fi

    # Redirect everything to logfile.
    exec >>"$LOGFILE" 2>&1
  fi
}

early_init_silent "$@"

# ----------------------------- Core functions -------------------------------

check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "This script must be run as root."
  fi
}

parse_flags() {
  local count=0 arg lower
  for arg in "$@"; do
    count=$((count + 1))
    if [ "$count" -gt 3 ]; then
      die_usage "Maximum 3 flags allowed."
    fi

    lower="$(to_lower "$arg")"
    case "$lower" in
      -c|--cli-enable|--enable-cli) FLAG_CLI=1 ;;
      -w|--web-enable|--enable-web) FLAG_WEB=1 ;;
      -n|--noninteractive)          FLAG_NONINTERACTIVE=1 ;; # keep consistent
      -*)
        die_usage "Unknown flag: $arg"
        ;;
      *)
        die_usage "Unexpected argument: $arg (only flags allowed)"
        ;;
    esac
  done
}

detect_os() {
  if [ "$(uname -s 2>/dev/null || true)" = "Darwin" ]; then
    DETECTED_OS="macos"
    return
  fi

  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [ -n "${ID:-}" ]; then
      DETECTED_OS="$ID"
      return
    fi
  fi

  DETECTED_OS="linux"
}

apt_env() {
  export DEBIAN_FRONTEND=noninteractive
  export APT_LISTCHANGES_FRONTEND=none
}

ensure_common() {
  case "$DETECTED_OS" in
    macos)
      # Requirement: ensure curl, wget, ca-certificates, plus brew presence.
      if ! command -v brew >/dev/null 2>&1; then
        die "Homebrew not found. Install from https://brew.sh and re-run."
      fi

      if ! command -v curl >/dev/null 2>&1; then
        brew install curl
      fi

      if ! command -v wget >/dev/null 2>&1; then
        brew install wget
      fi

      # ca-certificates (brew formula)
      if ! brew list --formula 2>/dev/null | grep -q '^ca-certificates$'; then
        brew install ca-certificates
      fi
      ;;
    ubuntu|debian|raspbian|linux)
      apt_env
      apt-get update -qq
      apt-get install -y -qq curl wget ca-certificates
      ;;
    *)
      # best effort for unknown linux
      apt_env
      apt-get update -qq || true
      apt-get install -y -qq curl wget ca-certificates || true
      ;;
  esac
}

ensure_macos() {
  if [ "$DETECTED_OS" != "macos" ]; then return; fi
  # brew already ensured in ensure_common
  if ! command -v python3 >/dev/null 2>&1; then
    brew install python
  fi
  # venv comes with python; pip comes with brew python
  python3 -m venv --help >/dev/null 2>&1 || die "python3 venv module not available."
}

ensure_linux() {
  case "$DETECTED_OS" in
    ubuntu|debian|raspbian|linux)
      apt_env
      apt-get update -qq
      apt-get install -y -qq python3 python3-pip python3-venv python-is-python3
      ;;
    *)
      die "Unsupported Linux distro for package installation (apt-based required)."
      ;;
  esac
}

linux_codename() {
  # Prefer VERSION_CODENAME from os-release, fallback to lsb_release.
  local code=""
  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    code="${VERSION_CODENAME:-}"
  fi
  if [ -z "$code" ] && command -v lsb_release >/dev/null 2>&1; then
    code="$(lsb_release -cs 2>/dev/null || true)"
  fi
  printf '%s' "$code"
}

ensure_docker_linux() {
  if [ "$DETECTED_OS" = "macos" ]; then
    # Do not auto-install Docker Desktop. Only check.
    if ! command -v docker >/dev/null 2>&1; then
      die "Docker not found on macOS. Please install Docker Desktop, then re-run."
    fi
    return
  fi

  if command -v docker >/dev/null 2>&1; then
    return
  fi

  local distro="$DETECTED_OS"
  if [ "$distro" = "raspbian" ]; then
    distro="debian"
  fi

  case "$distro" in
    ubuntu|debian|linux) ;;
    *) die "Unsupported distro for Docker installation: $distro" ;;
  esac

  apt_env
  apt-get update -qq
  apt-get install -y -qq apt-transport-https ca-certificates curl gnupg lsb-release

  mkdir -p /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${distro}/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  local codename
  codename="$(linux_codename)"
  if [ -z "$codename" ]; then
    die "Unable to determine distro codename for Docker repo."
  fi

  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/%s %s stable\n' \
    "$(dpkg --print-architecture)" "$distro" "$codename" > /etc/apt/sources.list.d/docker.list

  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable docker >/dev/null 2>&1 || true
    systemctl start docker >/dev/null 2>&1 || true
  else
    service docker start >/dev/null 2>&1 || true
  fi
}

download_repo_file() {
  local remote_path="$1"
  local local_path="$2"
  local url="${AEON_BASE_URL}${remote_path}"

  mkdir -p "$(dirname "$local_path")"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$local_path" || die "Failed to download $url"
  else
    wget -q "$url" -O "$local_path" || die "Failed to download $url"
  fi
}

ensure_user_sudoers() {
  if id "$AEON_USER" >/dev/null 2>&1; then
    :
  else
    if [ "$DETECTED_OS" = "macos" ]; then
      # Create a system-style user via dscl (no login)
      local maxid newid
      maxid="$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -n | tail -1)"
      newid=$((maxid + 1))
      dscl . -create "/Users/$AEON_USER"
      dscl . -create "/Users/$AEON_USER" UserShell /usr/bin/false
      dscl . -create "/Users/$AEON_USER" UniqueID "$newid"
      dscl . -create "/Users/$AEON_USER" PrimaryGroupID 20
    else
      # system user without login; home optional but helpful for tools
      useradd -r -m -d "/var/lib/${AEON_USER}" -s /usr/sbin/nologin "$AEON_USER" 2>/dev/null || \
      useradd -r -m -d "/var/lib/${AEON_USER}" -s /bin/false "$AEON_USER" 2>/dev/null || \
      useradd -r -s /usr/sbin/nologin "$AEON_USER" 2>/dev/null || \
      useradd -r -s /bin/false "$AEON_USER" 2>/dev/null || true
    fi
  fi

  mkdir -p "$AEON_ROOT"
  chown -R "$AEON_USER:$AEON_USER" "$AEON_ROOT" 2>/dev/null || \
  chown -R "$AEON_USER:staff" "$AEON_ROOT" 2>/dev/null || true

  local sudoers_file="/etc/sudoers.d/aeon-system"
  cat >"$sudoers_file" <<SUDOEOF
# AEON system user permissions (NOPASSWD)
$AEON_USER ALL=(ALL) NOPASSWD: $SUDOERS_REBOOT_CMDS
$AEON_USER ALL=(ALL) NOPASSWD: $SUDOERS_INSTALL_CMDS
$AEON_USER ALL=(ALL) NOPASSWD: $SUDOERS_DOCKER_CMDS
SUDOEOF

  chmod 0440 "$sudoers_file"
  if command -v visudo >/dev/null 2>&1; then
    visudo -c -f "$sudoers_file" >/dev/null 2>&1 || { rm -f "$sudoers_file"; die "Sudoers validation failed."; }
  fi
}

ensure_venv() {
  local venv_path="${AEON_ROOT}/venv"
  if [ -d "$venv_path" ]; then
    return
  fi
  python3 -m venv "$venv_path"
  "$venv_path/bin/pip" install --upgrade pip -q 2>/dev/null || true
  chown -R "$AEON_USER:$AEON_USER" "$venv_path" 2>/dev/null || \
  chown -R "$AEON_USER:staff" "$AEON_ROOT/venv" 2>/dev/null || true
}

build_orchestrator_args() {
  # returns args via stdout (space-separated, safe for our known tokens)
  local args=""
  [ "$FLAG_CLI" -eq 1 ] && args="$args --enable-cli"
  [ "$FLAG_WEB" -eq 1 ] && args="$args --enable-web"
  [ "$FLAG_NONINTERACTIVE" -eq 1 ] && args="$args --noninteractive"
  args="$args --file:/manifest/manifest.install.json"
  args="$args --config:/manifest/config/manifest.config.cursed.json"
  printf '%s' "$args"
}

run_orchestrator_native() {
  ensure_venv
  local orch_script="${AEON_ROOT}/library/orchestrator/orchestrator.json.py"
  local venv_python="${AEON_ROOT}/venv/bin/python"
  local args
  args="$(build_orchestrator_args)"
  sudo -u "$AEON_USER" "$venv_python" "$orch_script" $args
}

docker_daemon_ok() {
  if ! command -v docker >/dev/null 2>&1; then return 1; fi
  if command -v timeout >/dev/null 2>&1; then
    timeout 5 docker info >/dev/null 2>&1
  else
    docker info >/dev/null 2>&1
  fi
}

run_orchestrator_docker() {
  docker_daemon_ok || die "Docker daemon not available for docker mode."

  if [ "$AEON_ORCH_DOCKER_PULL" -eq 1 ]; then
    docker pull "$AEON_ORCH_DOCKER_IMAGE" >/dev/null 2>&1 || die "Failed to pull Docker image."
  fi

  local args
  args="$(build_orchestrator_args)"

  local docker_args
  docker_args=(--rm -v "${AEON_ROOT}:/opt/aeon" -w /opt/aeon)

  if [ "$AEON_ORCH_DOCKER_SOCKET" -eq 1 ] && [ -S /var/run/docker.sock ]; then
    docker_args+=(-v /var/run/docker.sock:/var/run/docker.sock)
  fi

  docker run "${docker_args[@]}" "$AEON_ORCH_DOCKER_IMAGE" python3 /opt/aeon/library/orchestrator/orchestrator.json.py $args
}

run_orchestrator() {
  local mode="$AEON_ORCH_MODE"
  if [ "$mode" = "auto" ]; then
    if docker_daemon_ok; then mode="docker"; else mode="native"; fi
  fi

  case "$mode" in
    native) run_orchestrator_native ;;
    docker) run_orchestrator_docker ;;
    *) die "Invalid AEON_ORCH_MODE: $mode" ;;
  esac
}

main() {
  check_root
  parse_flags "$@"
  detect_os

  # Setup logdir for non-silent runs too (best effort)
  mkdir -p "$AEON_LOGDIR" 2>/dev/null || true

  # Only now it's acceptable to output (unless -n redirected already)
  log_info "AEON install.bash.sh started (os=${DETECTED_OS}, mode=${AEON_ORCH_MODE})"

  ensure_common

  if [ "$DETECTED_OS" = "macos" ]; then
    ensure_macos
    # Docker: only check, no auto-install (handled in ensure_docker_linux)
    ensure_docker_linux || true
  else
    ensure_linux
    ensure_docker_linux
  fi

  ensure_user_sudoers

  # Always download orchestrator + manifests
  download_repo_file "/library/orchestrator/orchestrator.json.py" "${AEON_ROOT}/library/orchestrator/orchestrator.json.py"
  download_repo_file "/manifest/manifest.install.json" "${AEON_ROOT}/manifest/manifest.install.json"
  download_repo_file "/manifest/config/manifest.config.cursed.json" "${AEON_ROOT}/manifest/config/manifest.config.cursed.json"

  # Ownership after downloads
  chown -R "$AEON_USER:$AEON_USER" "$AEON_ROOT" 2>/dev/null || \
  chown -R "$AEON_USER:staff" "$AEON_ROOT" 2>/dev/null || true

  run_orchestrator
  log_info "AEON install.bash.sh completed successfully"
}

main "$@"
