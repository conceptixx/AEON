#!/usr/bin/env python3
import json
import os
import sys

def _read_json(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def _status(name: str, data: dict) -> str:
    val = data.get(name, None)
    if val is True:
        return "success"
    return "failed"

def main(argv: list[str]) -> int:
    # We only simulate: parse args but don't enforce strict schema yet
    # Expected installer passes:
    #   --enable-cli / --enable-web / --noninteractive (optional)
    #   --file:/manifest/manifest.install.json
    #   --config:/manifest/config/manifest.config.cursed.json

    file_arg = None
    cfg_arg = None

    for a in argv[1:]:
        if a.startswith("--file:"):
            file_arg = a[len("--file:"):]
        elif a.startswith("--config:"):
            cfg_arg = a[len("--config:"):]
        # ignore others for simulation

    # Default mapping (relative to /opt/aeon in installer design)
    # But we accept absolute paths too.
    root = os.environ.get("AEON_ROOT", "/opt/aeon")
    if file_arg and file_arg.startswith("/"):
        install_path = os.path.join(root, file_arg.lstrip("/"))
    elif file_arg:
        install_path = os.path.join(root, file_arg)
    else:
        install_path = os.path.join(root, "manifest/manifest.install.json")

    if cfg_arg and cfg_arg.startswith("/"):
        config_path = os.path.join(root, cfg_arg.lstrip("/"))
    elif cfg_arg:
        config_path = os.path.join(root, cfg_arg)
    else:
        config_path = os.path.join(root, "manifest/config/manifest.config.cursed.json")

    # Load and report
    rc = 0
    try:
        install_data = _read_json(install_path)
        print(f"manifest.install.json - {_status('manifest.install.json', install_data)}")
        if _status("manifest.install.json", install_data) != "success":
            rc = 2
    except Exception as e:
        print(f"manifest.install.json - failed ({e.__class__.__name__}: {e})")
        rc = 2

    try:
        config_data = _read_json(config_path)
        print(f"manifest.config.cursed.json - {_status('manifest.config.cursed.json', config_data)}")
        if _status("manifest.config.cursed.json", config_data) != "success":
            rc = 2
    except Exception as e:
        print(f"manifest.config.cursed.json - failed ({e.__class__.__name__}: {e})")
        rc = 2

    return rc

if __name__ == "__main__":
    raise SystemExit(main(sys.argv))