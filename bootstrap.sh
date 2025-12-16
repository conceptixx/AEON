#!/bin/bash
################################################################################
# AEON Bootstrap Installer
# File: bootstrap.sh
# Version: 0.1.0
################################################################################

# ============================================================================
# SELF-EXTRACTION FOR PIPED EXECUTION
# ============================================================================
if [[ "${AEON_BOOTSTRAP_REEXEC:-}" != "true" ]]; then
    if [[ ! -t 0 ]]; then
        TEMP_SCRIPT="/tmp/aeon-bootstrap-$$.sh"
        
        # Read script content and save to temp
        {
            echo '#!/usr/bin/env bash'
            echo 'set -euo pipefail'
            cat
        } > "$TEMP_SCRIPT"
        chmod +x "$TEMP_SCRIPT"
        
        # Re-execute from temp file
        AEON_BOOTSTRAP_REEXEC=true exec "$TEMP_SCRIPT" "$@"
        
        # Cleanup on failure
        rm -f "$TEMP_SCRIPT"
        exit 1
    fi
fi

# ============================================================================
# SELF-CLEANUP AFTER PIPED EXECUTION
# ============================================================================
if [[ "${AEON_BOOTSTRAP_REEXEC:-}" == "true" ]]; then
    trap 'rm -f "/tmp/aeon-bootstrap-$$.sh"' EXIT
fi

# ============================================================================
# MAIN EXECUTION
# ============================================================================
set -euo pipefail

bootstrap_main() {

    #    Configuration
    local aeon_repo="https://github.com/conceptixx/AEON.git"
    local aeon_raw="https://raw.githubusercontent.com/conceptixx/AEON/main"
    local install_dir="/opt/aeon"

    local lib_modules=(
        "dependecies.sh"
        "common.sh"
        "progress.sh"
        "preflight.sh"
        "discovery.sh"
        "hardware.sh"
        "validation.sh"
        "parallel.sh"
        "user.sh"
        "reboot.sh"
        "swarm.sh"
        "report.sh"
        "scoring.py"
    )

    local remote_scripts=(
        "dependencies.remote.sh"
        "hardware.remote.sh"
    )

    # Colors
    local red='\033[0;31m'
    local green='\033[0;32m'
    local yellow='\033[1;33m'
    local bold='\033[1m'
    local nocolor='\033[0m'

    local output_mode=0
    local skip_prompts=false
    local force_remove=false
    local keep_files=false

    # ============================================================================
    # BANNER
    # ============================================================================

    #
    # print banner
    # Displays the AEON ASCII art logo
    #
    print_banner() {
        clear
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
            local padding=$(( (80 - text_length) / 2 ))
            printf "%${padding}s%s\n" "" "$line"
        done
        # print linebreak
        echo ""
    }

    # ============================================================================
    # PRE-CHECKS
    # ============================================================================

    #
    # check_root
    # Verifies the script is running with root privileges
    #
    check_root() {
            __echo 0 "Checking sudo ..."
        if [[ $EUID -ne 0 ]]; then
            __echo 2 "${red}${bold}This script must be run as root${nocolor}"
            __echo 0 ""
            __echo 1 "${yellow}Please run:${nocolor}"
            __echo 1 "${yellow}  curl -fsSL https://raw.githubusercontent.com/conceptixx/AEON/main/bootstrap.sh | sudo bash${nocolor}"
            __echo 0 ""
            exit 1
        fi
        __echo 0 " - Check for root user ${green}${bold}successful${nocolor}"
    }

    #
    # check_previous_install
    # Checks if AEON is already installed and handles reinstallation
    #
    check_previous_install() {
        # check for previous installation
        __echo 0 "Checking prerequisites ..."
        # Check if already installed
        if [[ -d "$install_dir" ]]; then
            # previous installation detected
            __echo 1 "   ${yellow}AEON is already installed at $install_dir${nocolor}"
            if ! $skip_prompts; then
                # Check if we can access terminal
                if [[ -t 1 ]] && [[ -c /dev/tty ]]; then
                    printf "   Reinstall? [y/N]: " > /dev/tty
                    read -r response < /dev/tty
                else
                    # Non-interactive - default to no
                    printf "   Reinstall? [y/N]: n (non-interactive mode)" >&2
                    response="n"
                fi
                # Normalize response
                response=$(echo "$response" | tr '[:upper:]' '[:lower:]' | xargs)
                # cancel if not confirmed
                if [[ "$response" != "y" ]] && [[ "$response" != "yes" ]]; then
                    __echo 2 " - Installation ${red}${bold}cancelled${nocolor}"
                    __echo 0 ""
                    __echo 1 "   ${yellow}To force reinstall run:${nocolor}"
                    __echo 1 "   ${yellow}curl -fsSL https://raw.githubusercontent.com/conceptixx/AEON/main/bootstrap.sh | sudo bash ${red} -s -- --force${yellow}${nocolor}"
                    __echo 0 ""
                    exit 0
                fi
            fi
            if ! $force_remove; then
                # remove only installation files
                __echo 0 "   Removing existing installation (keep files)"
                rm -f -- "${lib_modules[@]}/#/$install_dir/lib/"
                rm -f -- "${remote_scripts[@]}/#/$install_dir/remote/"
                keep_files=true
            else
                # remove previuos installation
                __echo 0 "   Removing existing installation (remove files)"
                rm -rf "$install_dir"
            fi
        fi
        __echo 0  " - Check for prerequisites ${green}${bold}successful${nocolor}"
    }

    # ============================================================================
    # INSTALLATION
    # ============================================================================

    #
    # install_via_git
    # Installs AEON by cloning the GitHub repository
    #
    install_via_git() {
        # try to clone git repo
        __echo 0 "   Cloning AEON repository..."
        # if git command not available download and install git
        if ! command -v git &>/dev/null; then
            __echo 1 "   ${yellow}Git not found, installing git${nocolor}"
            apt-get update -qq
            apt-get install -y -qq git
        fi
        # clone git repo
        git clone --quiet "$aeon_repo" "$install_dir"
        __echo 0 " - Repository cloned ${green}${bold}successful${nocolor}"
    }

    #
    # install_via_download
    # Installs AEON by downloading individual files directly
    #
    install_via_download() {
        __echo 0 "   Downloading AEON components..."
echo "1."
        # Ensure curl/wget available
        if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
            apt-get update -qq
            apt-get install -y -qq curl wget
        fi
echo "2."
        # Create directory structure
        mkdir -p "$install_dir"/{lib,remote,config,data,secrets,logs,reports,docs,examples}
echo "3."
        # Download main script
        curl -fsSL "$aeon_raw/aeon-go.sh" -o "$install_dir/aeon-go.sh"
echo "4."
        # Download lib modules
        for module in "${lib_modules[@]}"; do
            echo 0 "loading ... $aeon_raw/lib/$module -> $install_dir/lib/$module"
            curl -fsSL "$aeon_raw/lib/$module" -o "$install_dir/lib/$module"
            chmod +x "$install_dir/lib/$module"
        done
        # Download remote scripts
        for script in "${remote_scripts[@]}"; do
            curl -fsSL "$aeon_raw/remote/$script" -o "$install_dir/remote/$script"
            chmod +x "$install_dir/remote/$script"
        done
        __echo 0 " - Components downloaded ${green}${bold}successful${nocolor}"
    }

    #
    # perform_installation
    # Main installation orchestrator - tries git first, falls back to download
    #
    perform_installation() {
        __echo 0 "Installing AEON... $keep_files"
        if ! $keep_files; then
            # Try git first, fallback to direct download
            if command -v git &>/dev/null; then
                install_via_git
            else
                __echo 1 "   ${yellow}Git not available, using direct download${nocolor}"
                install_via_download
            fi
        else
            __echo 1 "   keeping files, ${yellow}using direct download${nocolor}"
            install_via_download
        fi
        # Set permissions
        chmod 755 "$install_dir"
        __echo 0 "   AEON setup prepared ($install_dir/aeon_go.sh)"
    }

    # ============================================================================
    # POST-INSTALLATION
    # ============================================================================

    #
    # run_aeon_go_installer
    # Displays completion message and runs aeon_go.sh
    #
    run_aeon_go_installer() {
        __echo 0 "   Starting AEON installation..."
#        local seconds=30
#        local i
#        for ((i=seconds; i>0; i--)); do
#            printf "\rPress any key to continue (auto in %2ds)\033[K" "$i"
#            if read -r -n 1 -s -t 1; then
#                break
#            fi
#        done
    # Auto-launch aeon-go.sh
    sleep 20
    cd "$install_dir"
    exec bash aeon_go.sh
}

    # ============================================================================
    # MAIN EXECUTION
    # ============================================================================

    #
    # main
    # Main execution function - orchestrates the bootstrap process
    #
    main() {
        print_banner

        check_root
        check_previous_install
        perform_installation
        run_aeon_go_installer
    }
    
    #
    # __show_version
    # shows the version of the bootstrap.sh file
    #
    __show_version() {
        print_banner
        echo " version: $version"
        echo ""
    }
    __show_help() {
        print_banner
        echo -e "${yellow}${bold}Usage:${nocolor}"
        echo -e "   curl -fsSL https://raw.githubusercontent.com/conceptixx/AEON/main/bootstrap.sh | sudo bash ${yellow}-s -- [OPTIONS]${nocolor}"
        echo ""
        echo -e "${yellow}${bold}Options:${nocolor}"
        echo -e "   -h, --help              ${yellow}Show this help${nocolor}"
        echo -e "   -V, --version           ${yellow}Show version${nocolor}"
        echo -e "   -q, --quiet             ${yellow}Reduce output${nocolor}"
        echo -e "   -qq, --silent           ${yellow}Cancel output${nocolor}"
        echo -e "   -y, --yes               ${yellow}Assume ${green}yes${yellow} for prompts${nocolor}"
        echo -e "   -f, --force             ${yellow}Force reinstall${nocolor}"
        echo ""
    }
    __echo() {
        local min_mode="${1}"
        shift
        local output="$*"
        if (( min_mode >= output_mode )); then
            printf '%b\n' "$output"
        fi
    }

    # dispatcher
    while (($#)); do
        arg="$1"

        # Only normalize long options (case-insensitive for --something)
        if [[ "$arg" == --* ]]; then
            arg="${arg,,}"   # lowercase (bash)
            fi
        # check for options
        case "$arg" in
            # show help screen
            -h|--help)
            __show_help
            exit 0
            ;;
            # show version
            -V|--version)
            __show_version
            exit 0
            ;;
            # turn on quiet mode
            -q|--quiet)
            output_mode=$((output_mode + 1))
            shift
            continue
            ;;
            # turn on silent mode
            -qq|--silent)
            output_mode=$((output_mode + 2))
            shift
            continue
            ;;
            # skip prompts
            -y|--yes)
            skip_prompts=true
            shift
            continue
            ;;
            # force remove
            -f|--force)
            force_remove=true
            shift
            continue
            ;;

            *)
            # positional arg
            __show_help
            exit 0
            ;;
        esac
    done
    
    main
}
#
# automatic execution
# entrypoint main
#
bootstrap_main "$@"

