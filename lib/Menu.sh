#!/bin/bash
################################################################################
# AEON Bootstrap Installer
# File: bootstrap.sh
# Version: 0.1.0
################################################################################

set -euo pipefail

# ============================================================================
# PHASE 1: SELF_INSTALLATION IF PIPED FROM CURL/WGET
# ============================================================================

# --- Script info ------------------------------------------------------------
readonly SCRIPT_NAME="$(basename "$0")"
readonly TMP_SCRIPT="/tmp/${SCRIPT_NAME}"
# check if script runs locally or piped from curl/wget
if [[ -p /dev/stdin ]] || [[ ! -t 0 ]]; then
    if [[ "${0}" == "bash" ]] || [[ "${0}" == "/bin/bash" ]] || [[ "${0##*/}" == "-bash" ]]; then
        # Read the entire script from stdin and write to temp location
        cat > "$TMP_SCRIPT" <<< '# Placeholder - will be replaced with actual script content'        
        # Replace the placeholder with the actual script content
        if [[ -f "$0" ]]; then
            cp "$0" "${TMP_SCRIPT}";
        fi
        chmod +x "${TMP_SCRIPT}"
        exec "${TMP_SCRIPT}" "$@"
        exit 0
    fi
fi

# ============================================================================
# PHASE 2: CHECK INSTALLER
# ============================================================================

bootstrap_main() {
    # Menu items / scripts to test
    OPTIONS=(
        "apt-get"
        "brew"
        "curl"
        "wget"

        "nodejs"
        "python"
        "python3"
        "python3-pip"
        "go"
        "go-tools"
        
        "sshpass"
        "docker"
        
    )
    # Color and reset codes
    ESC=$'\e'
    FGBLK="${ESC}[30m"
    FGGRN="${ESC}[32m"
    BFGBLK="${ESC}[90m"
    BFGWHT="${ESC}[97m"
    BBGWHT="${ESC}[107m"
    RESET="${ESC}[0m"
    # selector checked and disabled properties
    declare -a DISABLED
    declare -a CHECKED
    # menu options
    CURSOR=0
    ITEMS_COUNT=$(( ${#OPTIONS[@]} + 1 ))
    #
    finish() {
        for i in "${!OPTIONS[@]}"; do
            if [ "${CHECKED[i]}" -eq 1 ]; then 
                if [ "${DISABLED[i]}" -eq 0 ]; then 
                    echo "${OPTIONS[i]}";
                fi
            fi
        done
    }
    unused() {
        FGRED="${ESC}[31m"
        FGYLW="${ESC}[33m"
        FGBLU="${ESC}[34m"
        FGPUR="${ESC}[35m"
        FGCYN="${ESC}[36m"
        FGWHT="${ESC}[37m"
        BFGRED="${ESC}[91m"
        BFGGRN="${ESC}[92m"
        BFGYLW="${ESC}[93m"
        BFGBLU="${ESC}[94m"
        BFGPUR="${ESC}[95m"
        BFGCYN="${ESC}[96m"
        BGBLK="${ESC}[40m"
        BGRED="${ESC}[41m"
        BGGRN="${ESC}[42m"
        BGYLW="${ESC}[43m"
        BGBLU="${ESC}[44m"
        BGPUR="${ESC}[45m"
        BGCYN="${ESC}[46m"
        BGWHT="${ESC}[47m"
        BBGBLK="${ESC}[100m"
        BBGRED="${ESC}[101m"
        BBGGRN="${ESC}[102m"
        BBGYLW="${ESC}[103m"
        BBGBLU="${ESC}[104m"
        BBGPUR="${ESC}[105m"
        BBGCYN="${ESC}[106m"
    }
    init() {
        # trap for screen cleanup
        trap cleanup EXIT INT TERM
        # prepare menu items if package is installed
        for i in "${!OPTIONS[@]}"; do
            if have "${OPTIONS[i]}"; then
                DISABLED[i]=1;
                CHECKED[i]=1;
            else
                DISABLED[i]=0;
                CHECKED[i]=0;
            fi;
        done
    }
    # --------- ANSI Helfer ---------
    clear_esc() { 
        printf '\e[2J\e[H'; 
    }
    hide_cursor() { 
        printf '\e[?25l'; 
    }
    show_cursor() { 
        printf '\e[?25h'; 
    }
    reset_esc() { 
        printf '\e[0m'; 
    }
    # cleanup for menu exit
    cleanup() { reset_esc; show_cursor; }
    # check if package is installed 
    have() { command -v "$1" >/dev/null 2>&1; }
    # print aeon banner
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
            printf "%s%${padding}s%s%s\n" "$BFGWHT" "" "$line" "$RESET"
        done
        printf "\n"
        }
    # render
    render() {
        local padding=$(( 10 ))
        clear_esc
        print_banner
    #    printf '%s%s%s\n\n' "$BFGWHT" "$MENU_TITLE" "$RESET"
        printf "%${padding}s%s[↑]/[↓] navigate       [SPACE/ENTER] toggle       [Q] = quit%s\n\n"  "" "$BFGWHT" "$RESET"
        local i
        for i in "${!OPTIONS[@]}"; do
            local color="$BFGWHT"
            local checked="$FGGRN"
            if [ "${DISABLED[i]}" -eq 1 ]; then color="$BFGBLK"; checked="$BFGBLK"; fi
            local box=' '
            [ "${CHECKED[i]}" -eq 1 ] && box='X'
            if [ "$CURSOR" -eq "$i" ]; then color="$BBGWHT$FGBLK"; fi
            printf "%${padding}s%s[%s%s%s] %s%s\n" "" "$color" "$checked" "$box" "$color" "${OPTIONS[i]}" "$RESET"
            reset_esc
    #        printf '\n'
        done
        # Continue Zeile
        color="$BFGWHT"
        local cont_idx=$((ITEMS_COUNT - 1))
        if [ "$CURSOR" -eq "$cont_idx" ]; then color="$BBGWHT$FGBLK"; fi
        printf "\n%${padding}s%s→   CONTINUE%s" "" "$color" "$RESET"
        reset_esc
        printf '\n'
    }
    # is_selectable
    is_selectable() {
        local idx="$1"
        local cont_idx=$((ITEMS_COUNT - 1))
        [ "$idx" -eq "$cont_idx" ] && return 0
        [ "${DISABLED[idx]}" -eq 0 ]
    }
    # move_cursor
    move_cursor() {
        local dir="$1"
        local next="$CURSOR"
        local tries=0
        while :; do
            tries=$((tries+1))
            [ "$tries" -gt "$ITEMS_COUNT" ] && return 1
            if [ "$dir" = "UP" ]; then next=$(( (next - 1 + ITEMS_COUNT) % ITEMS_COUNT )); else next=$(( (next + 1) % ITEMS_COUNT )); fi
            if is_selectable "$next"; then CURSOR="$next"; return 0; fi
        done
    }
    # read_key
    read_key() {
        local k k1 k2
        IFS= read -rsn1 k || return 1
        if [[ -z "$k" ]]; then echo "ENTER"; return 0; fi
        if [[ "$k" == $'\e' ]]; then
            # Arrow keys: ESC [ A/B
            # Bash 3.2 (macOS): -t nur in ganzen Sekunden -> 1 ist safe
            if IFS= read -rsn1 -t 1 k1; then
                if IFS= read -rsn1 -t 1 k2; then
                    case "$k1$k2" in "[A") echo "UP"; return 0 ;; "[B") echo "DOWN"; return 0 ;; esac
                fi
            fi
            echo "ESC"
            return 0
        fi
        case "$k" in " ") echo "SPACE" ;; q|Q) echo "QUIT" ;; *)   echo "OTHER" ;; esac
    }
    # pad_center
    pad_center() {
        local text="$1" width="$2"
        local len=${#text}
        (( len > width )) && text="${text:0:width}" && len=$width
        local left=$(( (width - len) / 2 ))
        local right=$(( width - len - left ))
        printf '%*s%s%*s' "$left" "" "$text" "$right" ""
    }
    # draw_bg_line_center
    draw_bg_line_center() {
        local row="$1" col="$2" w="$3" text="$4" bg="$5" fg="$6" reset="$7"
        local centered
        centered="$(pad_center "$text" "$w")"
        printf '\e[%d;%dH%s%s%s%s' "$row" "$col" "$bg" "$fg" "$centered" "$reset"
    }
    # draw_bg_line_blank
    draw_bg_line_blank() {
        local row="$1" col="$2" w="$3" bg="$4" fg="$5" reset="$6"
        local blank
        blank=$(printf '%*s' "$w" '')
        printf '\e[%d;%dH%s%s%s%s' "$row" "$col" "$bg" "$fg" "$blank" "$reset"
    }
    # confirm_overlay
    confirm_overlay() {
        local rows="${LINES:-24}" cols="${COLUMNS:-80}"
        local w=42 h=7
        local r=$(( (rows - h) / 2 )); [ "$r" -lt 1 ] && r=1
        local c=$(( (cols - w) / 2 )); [ "$c" -lt 1 ] && c=1
        printf '\e[s'  # Cursor speichern
        # 7 Zeilen Hintergrund-Box
        draw_bg_line_blank  "$((r+0))" "$c" "$w" "$BBGWHT" "$FGBLK" "$RESET"
        draw_bg_line_blank  "$((r+1))" "$c" "$w" "$BBGWHT" "$FGBLK" "$RESET"
        draw_bg_line_center "$((r+2))" "$c" "$w" "Continue?" "$BBGWHT" "$FGBLK" "$RESET"
        draw_bg_line_blank  "$((r+3))" "$c" "$w" "$BBGWHT" "$FGBLK" "$RESET"
        draw_bg_line_center "$((r+4))" "$c" "$w" "[Y/ENTER] Yes    [N] No    [ESC] Cancel" "$BBGWHT" "$FGBLK" "$RESET"
        draw_bg_line_blank  "$((r+5))" "$c" "$w" "$BBGWHT" "$FGBLK" "$RESET"
        draw_bg_line_blank  "$((r+6))" "$c" "$w" "$BBGWHT" "$FGBLK" "$RESET"
        # Key-Loop
        local k
        while true; do
        IFS= read -rsn1 k || break
        [[ -z "$k" ]] && printf '\e[u' && return 0
        case "$k" in y|Y) printf '\e[u'; return 0 ;; n|N|$'\e') printf '\e[u'; return 1 ;; esac
        done
        printf '\e[u'
        return 1
    }
    # ============================================================================
    # MAIN EXECUTION
    # ============================================================================
    main() {
        init
        hide_cursor
        for ((i=0; i<ITEMS_COUNT; i++)); do
            if is_selectable "$i"; then
                CURSOR="$i";
                break;
            fi
        done
        while true; do
            render
            case "$(read_key)" in
                UP)
                    move_cursor "UP";;
                DOWN)
                    move_cursor "DOWN";;
                SPACE|ENTER)
                    if [ "$CURSOR" -lt "${#OPTIONS[@]}" ]; then
                        [ "${DISABLED[CURSOR]}" -eq 1 ] && continue;
                        CHECKED[CURSOR]=$((1 - CHECKED[CURSOR]));
                    else
                        if confirm_overlay; then
                            break;
                        fi
                    fi
                    ;;
                QUIT)
                    break;;
            esac
        done
        clear_esc
        finish
    }
main
}
# bootstrap_main
bootstrap_main
# *END*OF*FILE*