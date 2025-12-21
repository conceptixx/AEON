#!/bin/bash
################################################################################
# AEON Bootstrap Installer
# File: bootstrap.sh
# Version: 0.1.0
################################################################################

# ============================================================================
# BOOTSTRAP MAIN CLASS
# ============================================================================
bootstrap_main() {

    # set pipfail
    set -euo pipefail
    
    readonly EXIT_OK=0
    readonly EXIT_ENVIR=1
    readonly EXIT_SUDO=2
    readonly EXIT_DEPENDENCY=3
    readonly EXIT_INFO=4
    readonly EXIT_TEST=5

    # declare exit-codes
    local -r exit_codes=(
        "ok / successful"
        "unsupported (windows/unknown) environment"
        "missing permissions for sudo or root"
    )

# ============================================================================
# BOOTSTRAP MAIN CLASS
# ============================================================================

    # error_code
    # writes error code
    on_error() {
        local code="$1"
        shift
        printf '[aeon-bootstrap][${code}] %s\n' "$*" >&2;
    }

    # on_exit
    # display an exit code message at the end of error output
    on_exit() {
        local rc=$?
        if [[ "$rc" -ne 0 ]]; then
            on_error  "CODE" "error-code $rc : ${exit_codes[$rc]}"
        fi
    }

    # trap on_exit as exit code
    trap on_exit EXIT

    # =========================================================================
    # WINDOWS KILL
    # BOOTSTRAP RE-EXEC (piped self-extract)
    # BOOTSTRAP RE-EXEC (sudo elevation)
    # CLEANUP
    # =========================================================================

    # Kill Git-Bash/MSYS/Cygwin on Windows (use bootstrap.ps1 instead)
    case "$(uname -s 2>/dev/null || true)" in
        MINGW*|MSYS*|CYGWIN*)
            on_error "ERROR" "this bootstrap-script is not designed for git-bash/msys/cygwin"
            on_error "ERROR" "start windows powershell"
            on_error "ERROR" "\$u = \"https://raw.githubusercontent.com/conceptixx/aeon/main/bootstrap.ps1\""
            on_error "ERROR" "\$dst = \"\$env:TEMP\aeon-bootstrap.ps1\""
            on_error "ERROR" "iwr -useb \$u -OutFile \$dst"
            on_error "ERROR" "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \$dst -c -w"
            on_error "ERROR" "# add -n  (noninteractive)"
            exit "$EXIT_ENVIR"
            ;;
    esac

    # Self-extract when piped + 2) sudo re-exec once + 3) cleanup temp script
    if [[ "${AEON_BOOTSTRAP_REEXEC_DONE:-}" != "true" ]]; then
        # If started via pipe (curl|bash / wget|bash), write to temp file and re-exec from file
        if [[ ! -t 0 ]]; then
            AEON_BOOTSTRAP_TEMP_SCRIPT="$(mktemp /tmp/aeon-bootstrap.XXXXXX.sh)"
            {
                echo '#!/bin/bash'
                echo 'set -euo pipefail'
                cat
            } > "$AEON_BOOTSTRAP_TEMP_SCRIPT"
            chmod +x "$AEON_BOOTSTRAP_TEMP_SCRIPT"
            AEON_BOOTSTRAP_REEXEC_DONE=true \
            exec "$AEON_BOOTSTRAP_TEMP_SCRIPT" "$@" || { rm -f "$AEON_BOOTSTRAP_TEMP_SCRIPT"; exit "$EXIT_OK"; }
        fi

    # Ensure cleanup if running from a temp script (env var survives sudo re-exec below)
        if [[ -n "${AEON_BOOTSTRAP_TEMP_SCRIPT:-}" ]]; then
            trap 'rm -f "$AEON_BOOTSTRAP_TEMP_SCRIPT"' EXIT
        fi

    # Elevate to root once (no "forcing" beyond prompting when needed)
        if [[ "$(id -u)" -ne 0 ]]; then
            if command -v sudo >/dev/null 2>&1; then
                AEON_BOOTSTRAP_REEXEC_DONE=true \
                exec sudo -k -p "[aeon-bootstrap] sudo password: " \
                env AEON_BOOTSTRAP_REEXEC_DONE=true \
                AEON_BOOTSTRAP_TEMP_SCRIPT="${AEON_BOOTSTRAP_TEMP_SCRIPT:-}" \
                bash "$0" "$@" || exit 2
            else
                on_error "ERROR" "sudo not found. Please run as root or install sudo."
                exit "$EXIT_SUDO"
            fi
        fi
        AEON_BOOTSTRAP_REEXEC_DONE=true
    else
    # If we already re-exec'd earlier, still ensure cleanup when temp script var is present
        if [[ -n "${AEON_BOOTSTRAP_TEMP_SCRIPT:-}" ]]; then
            trap 'rm -f "$AEON_BOOTSTRAP_TEMP_SCRIPT"' EXIT
        fi
    fi

    # ============================================================================
    # MAIN EXECUTION
    # ============================================================================

    # set configuration variables
    local aeon_repo="https://github.com/conceptixx/AEON.git"
    local aeon_raw="https://raw.githubusercontent.com/conceptixx/AEON/main"
    local install_dir="/opt/aeon"
    local version="0.1.0.dev"
    local install_os="unknown"
    local orchestrator_path="$1"
    local manifest_file="bootstrap.manifest.json"

    # set allowed flags
    local CLI_ENABLE=0
    local WEB_ENABLE=0
    local NONINTERACTIVE=0

    # 
    local APT_UPDATED=0
    local BREW_UPDATED=0
    local APT_PKG=()
    local BREW_PKG=()

    # set generic padding for printf
    local padding=10

    # print banner
    # Displays the AEON ASCII art logo
    print_banner() {
        [[ -t 1 ]] && clear
        # define AEON logo
        local logo_lines=(
            "   █████╗  ███████╗  ██████╗  ███╗   ██╗ "
            "  ██╔══██╗ ██╔════╝ ██╔═══██╗ ████╗  ██║ "
            "  ███████║ █████╗   ██║   ██║ ██╔██╗ ██║ "
            "  ██╔══██║ ██╔══╝   ██║   ██║ ██║╚██╗██║ "
            "  ██║  ██║ ███████╗ ╚██████╔╝ ██║ ╚████║ "
            "  ╚═╝  ╚═╝ ╚══════╝  ╚═════╝  ╚═╝  ╚═══╝ "
            ""
            "Autonomous Evolving Orchestration Network"
        )
        # print AEON logo centered
        for line in "${logo_lines[@]}"; do
            local text_length=${#line}
            local padding_logo=$(( (80 - text_length) / 2 ))
            printf "%${padding_logo}s%s\n" "" "$line"
        done
        # print linebreak
        printf "%${padding}s%s\n" "" ""
    }

    # help
    # shows help screen
    usage() {
        print_banner
        printf "%${padding}s%s\n" "" ""
        printf "%${padding}s%s\n" "" "Usage:"
        printf "%${padding}s%s\n" "" "   curl -fsSL https://raw.githubusercontent.com/conceptixx/AEON/main/bootstrap.sh | sudo bash -s -- [OPTIONS]"
        printf "%${padding}s%s\n" "" ""
        printf "%${padding}s%s\n" "" "Options:"
        printf "%${padding}s%s\n" "" "-c | -C | --enable-cli | --cli-enable     install cli TUI"
        printf "%${padding}s%s\n" "" "-w | -W | --enable-web | --web-enable     install web GUI"
        printf "%${padding}s%s\n" "" "-n | -N | --noninteractive                runs install non interactive"
        printf "%${padding}s%s\n" "" "                                          no prompts - use defaults"
        printf "%${padding}s%s\n" "" ""
        exit 0
    }

    # sudo_run
    # Sudo helper: use sudo if not root; fail if neither root nor sudo available.
    run_sudo() {
        if [ "$(id -u)" -eq 0 ]; then "$@"; return 0; fi
        if have sudo; then sudo "$@"; return 0; fi
        on_error "ERROR" "This script must be run as root"
        on_error "ERROR" "Please run:"
        on_error "ERROR" "  curl -fsSL https://raw.githubusercontent.com/conceptixx/AEON/main/bootstrap.sh | sudo bash"
        exit "$EXIT_SUDO"
    }

    # need_cmd
    # command helper: returns true if command is available
    have() {
        command -v "$1" >/dev/null 2>&1;
    }

    # checks for operating systems (macos, linux)
    is_mac_os() {
        [ "$(uname -s 2>/dev/null)" = "Darwin" ]
    }
    is_linux() {
        [ "$(uname -s 2>/dev/null)" = "Linux" ] 
    }

    # system requirement installer
    apt_update_once() {
        if ! have apt-get; then return 1; fi
        if [ "${APT_UPDATED:-0}" = "1" ]; then return 0; fi
        run_sudo apt-get update -y || return 1
        APT_UPDATED="1"
        return 0
    }
    brew_update_once() {
        if ! have brew; then return 1; fi
        if [ "${BREW_UPDATED:-0}" = "1" ]; then return 0; fi
        brew update >/dev/null 2>&1 || return 1
        BREW_UPDATED="1"
        return 0
    }
    
    get_curl() {
        if ! have curl; then
            if have apt-get; then APT_PKG+=("curl"); return 0;
            elif have brew; then BREW_PKG+=("curl");return 0; fi
        fi
        return 0
    }
    get_wget() {
        if ! have wget; then
            if have apt-get; then APT_PKG+=("wget"); return 0;
            elif have brew; then BREW_PKG+=("wget");return 0; fi
        fi
        return 0
    }
    have_ca_certs() {
        if [ -r /etc/ssl/certs/ca-certificates.crt ]; then return 0; fi
        if [ -r /etc/ssl/cert.pem ] || [ -r /usr/local/etc/openssl@3/cert.pem ] || [ -r /opt/homebrew/etc/openssl@3/cert.pem ]; then return 0; fi
        return 1
    }
    check_ca_certs() {
        if have apt-get; then have update-ca-certificates && update-ca-certificates >/dev/null 2>&1 || return 0 ; fi
        if have brew; then have_ca_certs || brew install openssl@3 >/dev/null 2>&1 || return 0 ; fi
    }
    get_ca_certs() {
        have_ca_certs && return 0
        if have apt-get; then APT_PKG+=("ca-certificates"); return 0;
        elif have brew; then BREW_PKG+=("ca-certificates"); return 0; fi
        return 1
    }    
    get_brew() {
        if ! have brew; then
            if have curl; then
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || return 1
                return 0
            elif have wget; then
                /bin/bash -c "$(wget -qO- https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || return 1
                return 0
            fi
            on_error "ERROR" "no installer available for homebrew (need curl or wget)"
            exit "$EXIT_DEPENDENCY"
        fi
        return 0
    }
    get_py_is_py3() {
        if have python; then
            if ! python --version 2>&1 | grep -q '^Python 3'; then
                if have apt-get; then APT_PKG+=("python-is-python3"); fi
            fi
        fi
        return 0
    }
    get_python() {
        if ! have python; then
        if have apt-get; then APT_PKG+=("python3"); return 0;
        elif have brew; then BREW_PKG+=("python"); return 0; fi
        fi
        return 0
    }
    get_pip3() {
        if ! have pip3; then
            if have apt-get; then APT_PKG+=("python3-pip"); return 0; fi
        fi
        return 0
    }
    get_pip3_alternate() {
        if ! have pip3; then
            if have python3 && ( have curl || have wget); then
                if have curl; then run_sudo curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py || return 1 ; fi
                if have wget; then run_sudo wget -qO /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py || return 1 ; fi
                python3 /tmp/get-pip.py --user || return 1
                return 0
            fi
        fi
    }
    get_venv() {
        if have python3; then
            if ! python3 -c 'import venv' >/dev/null 2>&1 ; then 
                if have apt-get; then APT_PKG+=("python3-venv") ; fi
            fi
        fi
        return 0
    }
    get_verify() {
        local error=0
        if ! have curl ; then on_error "ERROR" "no installer available for curl (need apt-get or brew)" ; error=1 ; fi
        if ! have wget; then on_error "ERROR" "no installer available for wget (need apt-get or brew)" ; error=1 ; fi
        if ! have_ca_certs; then on_error "ERROR" "installation failed for ca-certificates" ; error=1 ; fi
        if ! have python3; then on_error "ERROR" "no installer available for python (need apt-get or brew)" ; error=1 ; fi
        if is_macos; then
            if ! have brew; then on_error "ERROR" "no installer available for homebrew (need curl or wget)" ; error=1 ; fi
        elif is_linux ; then
            if ! have pip3; then on_error "ERROR" "no installer available for pip3 (need apt-get/brew or python3 + curl/wget)" ; error=1 ; fi
            if ! python --version 2>&1 | grep -q '^Python 3'; then on_error "ERROR" "no installer available for python-is-python3" ; error=1 ; fi
            if have python3; then
                if ! python3 -c 'import venv' >/dev/null 2>&1; then
                    on_error "ERROR" "no installer available for python3 venv (need apt-get or brew)"
                    error=1
                fi
            fi
        fi
        if (( error == 1 )); then
            exit "$EXIT_DEPENDENCY"
        fi
    }
    get_install() {
        if is_linux ; then apt_update_once ; fi
        get_curl
        get_wget
        if is_macos; then get_brew ; brew_update_once ;  fi
        get_ca_certs
        get_python
        get_pip3
        get_venv
        if is_linux ; then
            run_sudo apt-get -qq install -y --no-install-recommends "${APT_PKG[@]}"
        elif is_macos ; then
            brew install "${BREW_PKG[@]}" >/dev/null 2>&1
        fi   
        get_pip3_alternate
    }

    # checks for: windows | macos | raspios | linux | unknown
    prepare_os() {
        if ! is_macos && ! is_linux; then
            on_error "ERROR" "unknown operating system detected - check website for details:"
            on_error "ERROR" "${aeon_raw}/requirements.md"
            exit "$EXIT_ENVIR"
        fi
    }

    # run python orchestrator using bootstrap.manifest.json
    run_orchestrator() {
        python "$orchestrator_path" "$@"
    }

    # Main execution function - orchestrates the bootstrap process
    main() {

        # Capability flags only; no -h/--help on purpose
        while [ $# -gt 0 ]; do
            case "$1" in
                -c|-C|--cli-enable|--enable-cli) CLI_ENABLE=1 ;;
                -w|-W|--web-enable|--enable-web) WEB_ENABLE=1 ;;
                -n|-N|--noninteractive) NONINTERACTIVE=1 ;;
                *) usage; exit 0 ;;
            esac
            shift
        done

        print_banner
        get_curl
        get_wget
        get_brew
        get_ca_certs
        get_python
        get_venv
        get_pip3
        get_pip3_alternate
        get_py_is_py3
        get_install
        get_verify
    }
    main "$@"
}
#
# automatic execution
# entrypoint main
#
bootstrap_main "$@"
# ***END*OF*FILE***