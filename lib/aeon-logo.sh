#!/usr/bin/env bash

# --- Color mapping (256-color). Adjust as you like. ---
color256() {
  case "$1" in
    B) echo 0 ;;        # black
    W) echo 15 ;;       # white
    G) echo 246 ;;      # grey
    C) echo 62 ;;       # bright cyan
    *) echo 0  ;;       # fallback
  esac
}

# Repeat helper (multibyte-safe enough for our use)
_repeat_char() {
  local __count="$1"
  local __ch="$2"
  local __i
  for ((__i=0; __i<__count; __i++)); do
    printf '%s' "$__ch"
  done
}

set_single() {
  local count="$1"
  # local fgcolor not used
  local bgcolor="$2"

  local __bg
  __bg="$(color256 "$bgcolor")"

  # Background only + spaces (no FG set)
  printf '\e[48;5;%sm' "$__bg"
  printf '%*s' "$count" ""
}

set_dual() {
  local count="$1"
  local fgcolor="$2"   # lower half color (Y)
  local bgcolor="$3"   # upper half color (X)

  local __fg __bg
  __fg="$(color256 "$fgcolor")"
  __bg="$(color256 "$bgcolor")"

  # For "▄": FG = lower half, BG = upper half
  printf '\e[38;5;%sm\e[48;5;%sm' "$__fg" "$__bg"
  _repeat_char "$count" "▄"
}

set_linebreak() {
  # reset + newline
  printf '\e[0m\n'
}

# -------------------------------------------------------
# One combined array: "function:count:fgcolor:bgcolor"
# - For set_single: fgcolor is empty
# - For set_linebreak: count=0 and colors empty
# -------------------------------------------------------

RENDER_STEPS=(
  # line 1
  "set_single:5::B"  "set_single:4::W"  "set_single:7::B"  "set_single:10::W" "set_single:3::B"
  "set_dual:1:W:B"   "set_single:7::W"  "set_dual:1:W:B"   "set_single:3::B"  "set_single:3::W" "set_single:5::B" "set_single:3::W"
  "set_linebreak:0::"

  # line 2
  "set_single:4::B"  "set_dual:1:W:B"   "set_single:4::W"  "set_dual:1:W:B"   "set_single:5::B"
  "set_dual:1:G:B"   "set_dual:3:C:W"   "set_dual:7:B:W"   "set_single:2::B"  "set_dual:1:W:B"
  "set_single:3::W"  "set_dual:1:B:W"   "set_dual:2:G:W"   "set_dual:2:C:W"   "set_single:1::W"
  "set_dual:1:W:B"   "set_single:2::B"  "set_single:4::W"  "set_single:4::B"  "set_single:3::W"
  "set_linebreak:0::"

  # line 3
  "set_single:4::B"  "set_single:6::W"  "set_single:2::B"  "set_dual:1:G:B"   "set_single:2::G"
  "set_dual:1:B:G"   "set_dual:3:W:C"   "set_single:2::G"  "set_dual:2:G:B"   "set_single:5::B"
  "set_single:1::W"  "set_dual:2:C:W"   "set_single:2::G"  "set_dual:3:B:G"   "set_dual:1:W:C"
  "set_single:2::C"  "set_dual:1:G:B"   "set_single:1::B"  "set_single:5::W"  "set_single:3::B" "set_single:3::W"
  "set_linebreak:0::"

  # line 4
  "set_single:2::B"  "set_dual:1:W:B"   "set_single:2::W"  "set_dual:1:B:W"   "set_single:2::B"
  "set_dual:1:B:W"   "set_single:1::W"  "set_dual:1:C:W"   "set_dual:1:C:G"   "set_single:1::G"
  "set_dual:1:B:G"   "set_single:2::B"  "set_single:5::W"  "set_dual:1:W:C"   "set_single:1::C"
  "set_single:1::G"  "set_dual:1:G:B"   "set_single:2::B"  "set_dual:1:G:B"   "set_single:2::C"
  "set_dual:1:W:C"   "set_single:5::B"  "set_single:2::W"  "set_dual:1:W:C"   "set_single:2::G"
  "set_dual:1:C:W"   "set_single:2::W"  "set_single:1::B"  "set_single:3::W"  "set_single:1::B" "set_single:3::W"
  "set_linebreak:0::"

  # line 5
  "set_single:3::B"  "set_single:3::W"  "set_single:2::B"  "set_single:2::W"  "set_single:1::C"
  "set_single:1::G"  "set_single:4::B"  "set_single:3::W"  "set_dual:4:W:B"   "set_single:1::B"
  "set_single:4::G"  "set_single:3::W"  "set_single:5::B"  "set_single:3::W"  "set_single:1::B"
  "set_single:1::G"  "set_single:1::C"  "set_single:5::W"  "set_single:2::B"  "set_single:3::W"
  "set_linebreak:0::"

  # line 6
  "set_single:2::B"  "set_single:3::W"  "set_single:4::B"  "set_single:1::W"  "set_dual:1:W:C"
  "set_single:1::C"  "set_single:1::G"  "set_dual:1:G:B"   "set_single:2::B"  "set_single:3::W"
  "set_single:2::B"  "set_dual:1:G:B"   "set_single:2::G"  "set_dual:1:B:G"   "set_single:2::B"
  "set_dual:1:B:G"   "set_single:2::C"  "set_dual:1:C:W"   "set_single:5::B"  "set_single:2::W"
  "set_dual:1:C:W"   "set_single:2::G"  "set_dual:1:W:C"   "set_single:2::W"  "set_single:2::B" "set_single:6::W"
  "set_linebreak:0::"

  # line 7
  "set_single:1::B"  "set_single:11::W" "set_dual:1:W:C"   "set_single:2::G"  "set_dual:1:G:B"
  "set_dual:3:C:W"   "set_single:2::G"  "set_dual:2:B:G"   "set_single:5::B"  "set_single:1::W"
  "set_dual:2:W:C"   "set_single:2::G"  "set_dual:3:G:B"   "set_dual:1:C:W"   "set_single:2::C"
  "set_dual:1:B:G"   "set_single:1::B"  "set_single:3::W"  "set_single:3::B"  "set_single:5::W"
  "set_linebreak:0::"

  # line 8
  "set_dual:1:W:B"   "set_single:2::W"  "set_dual:8:B:W"   "set_single:2::W"  "set_dual:1:W:B"
  "set_single:1::B"  "set_dual:1:B:G"   "set_dual:3:W:C"   "set_dual:7:W:B"   "set_single:2::B"
  "set_dual:1:B:W"   "set_single:3::W"  "set_dual:1:W:B"   "set_dual:2:W:G"   "set_dual:2:W:C"
  "set_single:1::W"  "set_dual:1:B:W"   "set_single:2::B"  "set_single:3::W"  "set_single:4::B" "set_single:4::W"
  "set_linebreak:0::"

  # line 9
  "set_single:3::W"  "set_single:8::B"  "set_single:3::W"  "set_single:2::B"  "set_single:10::W"
  "set_single:3::B"  "set_dual:1:B:W"   "set_single:7::W"  "set_dual:1:B:W"   "set_single:3::B"
  "set_single:3::W"  "set_single:5::B"  "set_single:3::W"
  "set_linebreak:0::"
)

render_all() {
  local __entry __fn __count __fg __bg
  for __entry in "${RENDER_STEPS[@]}"; do
    IFS=':' read -r __fn __count __fg __bg <<< "$__entry"
    case "$__fn" in
      set_single)   set_single "$__count" "$__bg" ;;
      set_dual)     set_dual   "$__count" "$__fg" "$__bg" ;;
      set_linebreak)set_linebreak ;;
      *) echo "Unknown fn: $__fn" >&2; return 1 ;;
    esac
  done
}

# Example:
render_all