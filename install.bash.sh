#!/usr/bin/env bash
set -e

# AEON payload: root-exec verification script
# Accepts only: -c/-C/--cli-enable/--enable-cli, -w/-W/--web-enable/--enable-web, -n/-N/--noninteractive
# Long flags case-insensitive. No other args.

usage() {
  cat <<'EOF'
Usage: install.bash.sh [-c|--cli-enable] [-w|--web-enable] [-n|--noninteractive]
Only these flags are allowed. Long flags are case-insensitive.
EOF
}

to_lower() {
  # Bash 3.2 safe; avoids echo -n pitfalls
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

die_usage() {
  printf 'ERROR: %s\n' "$*" >&2
  usage >&2
  exit 2
}

# ---- Flag parsing (normalize to canonical long flags) ----
ENABLE_CLI=0
ENABLE_WEB=0
NONINTERACTIVE=0
FLAG_COUNT=0

for arg in "$@"; do
  FLAG_COUNT=$((FLAG_COUNT + 1))
  lower_arg="$(to_lower "$arg")"

  case "$lower_arg" in
    -c|--cli-enable|--enable-cli) ENABLE_CLI=1 ;;
    -w|--web-enable|--enable-web) ENABLE_WEB=1 ;;
    -n|--noninteractive)          NONINTERACTIVE=1 ;;
    -*)
      die_usage "Unknown flag: $arg"
      ;;
    *)
      die_usage "Unexpected argument: $arg (only flags allowed)"
      ;;
  esac
done

if [ "$FLAG_COUNT" -gt 3 ]; then
  die_usage "Maximum 3 flags allowed."
fi

NORMALIZED_FLAGS=""
[ "$ENABLE_CLI" -eq 1 ] && NORMALIZED_FLAGS="$NORMALIZED_FLAGS --enable-cli"
[ "$ENABLE_WEB" -eq 1 ] && NORMALIZED_FLAGS="$NORMALIZED_FLAGS --enable-web"
[ "$NONINTERACTIVE" -eq 1 ] && NORMALIZED_FLAGS="$NORMALIZED_FLAGS --noninteractive"

# ---- Root check ----
EUID_NOW="$(id -u 2>/dev/null || echo 99999)"
if [ "$EUID_NOW" -ne 0 ]; then
  printf 'ERROR: This script must run as root (it is designed to be launched by the bootstrap via sudo/root).\n' >&2
  printf '       Current uid: %s\n' "$EUID_NOW" >&2
  exit 10
fi

# ---- Info ----
OS_NAME="$(uname -s 2>/dev/null || echo Unknown)"
KERNEL_REL="$(uname -r 2>/dev/null || echo Unknown)"

printf '[AEON] install.bash.sh running as root ✅\n'
printf '[AEON] OS: %s | Kernel: %s | UID: %s\n' "$OS_NAME" "$KERNEL_REL" "$EUID_NOW"
printf '[AEON] Flags:%s\n' "${NORMALIZED_FLAGS:- (none)}"
printf '\n'

# ---- Root-only operation that does NOT install anything ----
# This proves we can perform privileged actions without prefixing sudo inside this script.
TEST_DIR="/root/aeon_root_test.$$"
printf '[AEON] Root-only test: create + write + remove in %s ...\n' "$TEST_DIR"
mkdir -p "$TEST_DIR" || { echo "[AEON] FAIL: mkdir in /root failed"; exit 11; }
printf 'root-ok\n' > "$TEST_DIR/proof.txt" || { echo "[AEON] FAIL: write in /root failed"; exit 12; }
rm -f "$TEST_DIR/proof.txt" && rmdir "$TEST_DIR" || true
printf '[AEON] Root-only test: PASS ✅\n'
printf '\n'

# ---- apt-get demonstration (optional / best effort) ----
if command -v apt-get >/dev/null 2>&1; then
  printf '[AEON] apt-get detected: %s\n' "$(command -v apt-get)"
  printf '[AEON] Demonstration: running "apt-get update" WITHOUT sudo (should work because we are already root).\n'
  printf '[AEON] Note: This refreshes package lists; it does NOT install packages.\n\n'

  set +e
  apt-get update
  rc=$?
  set -e

  if [ "$rc" -eq 0 ]; then
    printf '\n[AEON] apt-get update: PASS ✅ (rc=%s)\n' "$rc"
  else
    printf '\n[AEON] apt-get update: FAIL ⚠️ (rc=%s)\n' "$rc"
    printf '[AEON] This can fail if network/DNS is blocked or apt is locked. Root privilege is still confirmed.\n'
  fi
else
  printf '[AEON] apt-get not found on this system.\n'
  printf '[AEON] That is expected on macOS. For Debian/Ubuntu/RaspiOS/WSL Ubuntu, apt-get should exist.\n'
fi

printf '\n[AEON] Done.\n'
exit 0