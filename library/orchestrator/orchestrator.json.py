#!/usr/bin/env python3
"""
AEON Orchestrator (Simulation Example)

- Prints a simple status summary to stdout (screen-first).
- Accepts: -c/-w/-n and long variants (case-insensitive for long flags).
- Accepts: --file:/manifest/manifest.install.json
           --config:/manifest/config/manifest.config.cursed.json
- Reads JSON files relative to AEON_ROOT (env) with OS fallbacks.
"""

import json
import os
import sys
from pathlib import Path
from typing import Optional, Tuple


def default_root() -> str:
    # Use AEON_ROOT if set by installer/docker
    env_root = os.environ.get("AEON_ROOT")
    if env_root:
        return env_root

    # Fallbacks for standalone runs
    if sys.platform == "darwin":
        return "/usr/local/aeon"
    return "/opt/aeon"


def to_lower(s: str) -> str:
    return s.lower()


def parse_args(argv: list) -> Tuple[bool, bool, bool, Optional[str], Optional[str]]:
    cli_enabled = False
    web_enabled = False
    noninteractive = False
    file_arg = None
    config_arg = None

    i = 0
    while i < len(argv):
        a = argv[i]

        # Flags (short)
        if a in ("-c", "-C"):
            cli_enabled = True
        elif a in ("-w", "-W"):
            web_enabled = True
        elif a in ("-n", "-N"):
            noninteractive = True

        # Flags (long, case-insensitive)
        else:
            al = to_lower(a)
            if al in ("--cli-enable", "--enable-cli"):
                cli_enabled = True
            elif al in ("--web-enable", "--enable-web"):
                web_enabled = True
            elif al == "--noninteractive":
                noninteractive = True

            # Path-style params
            elif al.startswith("--file:"):
                file_arg = a.split(":", 1)[1]
            elif al.startswith("--config:"):
                config_arg = a.split(":", 1)[1]
            else:
                # Ignore unknown args in simulation (screen-first)
                pass

        i += 1

    return cli_enabled, web_enabled, noninteractive, file_arg, config_arg


def normalize_repo_path(p: str) -> str:
    # We accept "/manifest/..." and "manifest/..." and normalize to "manifest/..."
    if p.startswith("/"):
        return p[1:]
    return p


def read_json_bool(path: Path, expected_key: str) -> bool:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return False

    # Accept simple forms:
    # 1) {"<expected_key>": "true"}
    # 2) {"<expected_key>": true}
    # 3) {"ok": true} or {"success": true} (best-effort)
    if isinstance(data, dict):
        if expected_key in data:
            v = data.get(expected_key)
            if isinstance(v, bool):
                return v
            if isinstance(v, (int, float)):
                return v != 0
            if isinstance(v, str):
                return v.strip().lower() in ("true", "1", "yes", "y", "ok", "success")
            return bool(v)

        # best-effort fallbacks
        for k in ("ok", "success", "passed", "true"):
            if k in data and isinstance(data[k], bool):
                return data[k]

    # If someone stores a raw boolean in JSON (rare): true/false
    if isinstance(data, bool):
        return data

    return False


def main() -> int:
    aeon_root = Path(default_root())

    cli_enabled, web_enabled, noninteractive, file_arg, config_arg = parse_args(sys.argv[1:])

    # Defaults if not provided
    if not file_arg:
        file_arg = "/manifest/manifest.install.json"
    if not config_arg:
        config_arg = "/manifest/config/manifest.config.cursed.json"

    file_rel = normalize_repo_path(file_arg)
    cfg_rel = normalize_repo_path(config_arg)

    file_path = aeon_root / file_rel
    cfg_path = aeon_root / cfg_rel

    install_ok = file_path.exists() and read_json_bool(file_path, "manifest.install.json")
    config_ok = cfg_path.exists() and read_json_bool(cfg_path, "manifest.config.cursed.json")

    # Screen-first output
    print("AEON orchestrator.json.py (simulation)")
    print(f"AEON_ROOT: {aeon_root}")
    print(f"cli-enabled: {'true' if cli_enabled else 'false'}")
    print(f"web-enabled: {'true' if web_enabled else 'false'}")
    print(f"noninteractive: {'true' if noninteractive else 'false'}")
    print(f"read manifest.install.json: {'true' if install_ok else 'false'}")
    print(f"read manifest.config.cursed.json: {'true' if config_ok else 'false'}")

    # Exit code: success only if both reads succeed
    return 0 if (install_ok and config_ok) else 1


if __name__ == "__main__":
    raise SystemExit(main())