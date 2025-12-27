#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# v2.3.0
"""
Config Handler v2.3 - Security-First Multi-File Configuration
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Features:
- Multi-file config management based on manifest
- Timestamped backups (YYMMDD+seconds format)
- Search path: root → repo (FAIL if not found)
- All paths relative to aeon_root (security!)
- Load from multiple config files
- Save to multiple config files

AEON v2.3 - Event-Driven Architecture
"""

import json
from pathlib import Path
from datetime import datetime

TASK_NAME = "config_handler"
TASK_DESCRIPTION = "Security-first multi-file configuration management"
DEPENDS_ON = []

# ============================================
# HELPER FUNCTIONS
# ============================================

def get_timestamp():
    """Generate YYMMDD+seconds_of_day timestamp
    
    Example: 2025-12-26 20:41:32 → 25122674492
    """
    now = datetime.now()
    yymmdd = now.strftime("%y%m%d")
    seconds_of_day = now.hour * 3600 + now.minute * 60 + now.second
    return f"{yymmdd}{seconds_of_day:05d}"


def extract_by_prefix(data: dict, key_prefix: str) -> dict:
    """Extract all keys starting with prefix"""
    result = {}
    for key, value in data.items():
        if key.startswith(key_prefix):
            result[key] = value
    return result


def flatten_dict(d: dict, parent_key: str = '', sep: str = '.') -> dict:
    """Flatten nested dict to dot notation"""
    items = []
    for k, v in d.items():
        new_key = f"{parent_key}{sep}{k}" if parent_key else k
        if isinstance(v, dict):
            items.extend(flatten_dict(v, new_key, sep=sep).items())
        else:
            items.append((new_key, v))
    return dict(items)


def unflatten_dict(d: dict, sep: str = '.') -> dict:
    """Unflatten dot notation to nested dict"""
    result = {}
    for key, value in d.items():
        parts = key.split(sep)
        current = result
        for part in parts[:-1]:
            if part not in current:
                current[part] = {}
            current = current[part]
        current[parts[-1]] = value
    return result


# ============================================
# LIFECYCLE HOOKS
# ============================================

async def on_load(context, dependencies, event_data):
    """Load config files with search path: root → repo → FAIL"""
    
    aeon_root = context.get("aeon_root")
    aeon_repo = context.get("aeon_repo")
    
    if not aeon_root:
        raise ValueError("aeon_root missing in context (--root flag required)")
    
    if not aeon_repo:
        raise ValueError("aeon_repo missing in context")
    
    process_def = context.get("process_def")
    if not process_def:
        raise ValueError("process_def missing in context")
    
    config_manifest = process_def.config if hasattr(process_def, 'config') else []
    
    if not isinstance(config_manifest, list):
        print("   └─ ⚠️  No config manifest (old format)")
        context["system_config"] = {}
        context["pending_config"] = {}
        context["config_manifest"] = []
        return {"config_loaded": False}
    
    print(f"   └─ Loading {len(config_manifest)} config files...")
    
    system_config_flat = {}
    
    for config_entry in config_manifest:
        file_rel = config_entry.get("file")
        if not file_rel:
            continue
        
        base = config_entry.get("base", "root")
        base_path = aeon_root if base == "root" else aeon_repo
        
        # 1. Try to load existing config
        config_path = Path(base_path) / file_rel
        
        if config_path.exists():
            print(f"      ├─ ✅ Config: {file_rel}")
            with open(config_path, 'r') as f:
                file_data = json.load(f)
        else:
            # 2. Search for defaults
            defaults_config = config_entry.get("defaults", {})
            defaults_file = defaults_config.get("file")
            search_path = defaults_config.get("search", ["root", "repo"])
            
            file_data = None
            found_in = None
            
            for search_base in search_path:
                search_base_path = aeon_root if search_base == "root" else aeon_repo
                defaults_path = Path(search_base_path) / defaults_file
                
                if defaults_path.exists():
                    print(f"      ├─ ✅ Defaults ({search_base}): {defaults_file}")
                    with open(defaults_path, 'r') as f:
                        file_data = json.load(f)
                    found_in = search_base
                    break
            
            # 3. FAIL if not found
            if file_data is None:
                raise FileNotFoundError(
                    f"Config not found: {file_rel}\n"
                    f"  Searched:\n"
                    f"    - Config: {base_path}/{file_rel}\n"
                    f"    - Defaults (root): {aeon_root}/{defaults_file}\n"
                    f"    - Defaults (repo): {aeon_repo}/{defaults_file}\n"
                    f"  \n"
                    f"  Please provide either the config file or defaults file!"
                )
        
        # Flatten and merge
        flat_data = flatten_dict(file_data)
        system_config_flat.update(flat_data)
    
    context["system_config"] = system_config_flat
    context["pending_config"] = {}
    context["config_manifest"] = config_manifest
    
    print(f"   └─ ✅ Total: {len(system_config_flat)} config keys loaded")
    
    return {"config_loaded": True, "keys": len(system_config_flat)}


async def on_force(context, dependencies, event_data):
    """Reset state file"""
    
    aeon_root = context.get("aeon_root")
    task_config = context.get("task_config", {}).get("config_handler", {})
    state_file_rel = task_config.get("state_file", "runtime/state/.aeon_state.json")
    
    if aeon_root:
        state_file = Path(aeon_root) / state_file_rel
    else:
        state_file = Path(".aeon_state.json")
    
    if state_file.exists():
        print(f"   └─ 🔄 Resetting state: {state_file}")
        state_file.unlink()
        print(f"   └─ ✅ State file deleted")
        return {"state_reset": True}
    else:
        print(f"   └─ No state file to reset")
        return {"state_reset": False}


async def before_resolve(context, dependencies, event_data):
    """Validate pending config"""
    
    pending = context.get("pending_config", {})
    
    if not pending:
        print("   └─ No pending config to validate")
        return {"validated": True}
    
    print(f"   └─ Validating {len(pending)} pending keys...")
    
    # Basic validation
    for key, value in pending.items():
        if "ip_address" in key or "ip" in key:
            if isinstance(value, str) and len(value.split(".")) != 4:
                raise ValueError(f"Invalid IP: {key}={value}")
    
    print(f"   └─ ✅ Validation passed")
    return {"validated": True}


async def on_success(context, dependencies, event_data):
    """Create timestamped backups"""
    
    aeon_root = context.get("aeon_root")
    config_manifest = context.get("config_manifest", [])
    timestamp = get_timestamp()
    
    print(f"   └─ Creating backups (timestamp: {timestamp})...")
    
    backed_up = 0
    
    for config_entry in config_manifest:
        file_rel = config_entry.get("file")
        if not file_rel:
            continue
        
        base = config_entry.get("base", "root")
        base_path = aeon_root
        
        file_path = Path(base_path) / file_rel
        
        if file_path.exists():
            stem = file_path.stem
            suffix = file_path.suffix
            backup_name = f"{stem}.{timestamp}{suffix}"
            backup_path = file_path.parent / "backups" / backup_name
            
            backup_path.parent.mkdir(parents=True, exist_ok=True)
            
            import shutil
            shutil.copy2(file_path, backup_path)
            
            backed_up += 1
    
    print(f"   └─ ✅ {backed_up} backups created")


async def on_error(context, dependencies, event_data):
    """Restore from latest backup"""
    
    print("   └─ ⚠️  Restoring from latest backups...")
    
    aeon_root = context.get("aeon_root")
    config_manifest = context.get("config_manifest", [])
    
    restored = 0
    
    for config_entry in config_manifest:
        file_rel = config_entry.get("file")
        if not file_rel:
            continue
        
        base = config_entry.get("base", "root")
        base_path = aeon_root
        
        file_path = Path(base_path) / file_rel
        backup_dir = file_path.parent / "backups"
        
        if backup_dir.exists():
            backups = sorted(backup_dir.glob(f"{file_path.stem}.*{file_path.suffix}"), reverse=True)
            
            if backups:
                latest = backups[0]
                import shutil
                shutil.copy2(latest, file_path)
                restored += 1
    
    print(f"   └─ ✅ {restored} files restored")


# ============================================
# MAIN METHODS
# ============================================

async def resolve(context, dependencies, event_data):
    """Save config to multiple files"""
    
    import asyncio
    
    aeon_root = context.get("aeon_root")
    if not aeon_root:
        raise ValueError("aeon_root missing in context")
    
    config_manifest = context.get("config_manifest", [])
    pending = context.get("pending_config", {})
    current = context.get("system_config", {})
    
    # Merge pending into current
    if pending:
        print(f"   └─ Merging {len(pending)} pending keys...")
        current.update(pending)
    
    # Add metadata
    current["metadata.last_updated"] = datetime.now().isoformat()
    current["metadata.version"] = "2.3.0"
    
    # Save to EACH file
    print(f"   └─ Saving to {len(config_manifest)} files...")
    
    saved_count = 0
    
    for config_entry in config_manifest:
        file_rel = config_entry.get("file")
        if not file_rel:
            continue
        
        base = config_entry.get("base", "root")
        base_path = aeon_root
        
        # Determine prefix from defaults data
        defaults_data = config_entry.get("defaults", {}).get("data", {})
        if defaults_data:
            first_key = list(defaults_data.keys())[0]
            prefix = first_key.split(".")[0]
        else:
            # Fallback: use filename
            prefix = Path(file_rel).stem.split(".")[-1]
        
        # Extract relevant keys
        file_data_flat = extract_by_prefix(current, prefix)
        
        # Unflatten for pretty JSON
        file_data = unflatten_dict(file_data_flat)
        
        # Save
        file_path = Path(base_path) / file_rel
        file_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(file_path, 'w') as f:
            json.dump(file_data, f, indent=2)
        
        saved_count += 1
    
    # Update context
    context["system_config"] = current
    context["pending_config"] = {}
    
    await asyncio.sleep(0.1)
    
    print(f"   └─ ✅ Config saved to {saved_count} files")
    
    return {
        "config_saved": True,
        "files": saved_count,
        "keys": len(current)
    }


async def reject(context, error, event_data):
    """Error handler"""
    print(f"   └─ ❌ Config save failed: {error}")
    raise error


# ============================================
# API METHODS
# ============================================

async def get_config(context, dependencies, event_data):
    """Get full config (flat)"""
    return context.get("system_config", {})


async def get_value(context, dependencies, event_data):
    """Get specific value by key path"""
    key = event_data.get("key", "")
    config = context.get("system_config", {})
    return config.get(key)


async def set_value(context, dependencies, event_data):
    """Set value (staged)"""
    key = event_data.get("key", "")
    value = event_data.get("value")
    
    if not key:
        raise ValueError("key is required")
    
    if "pending_config" not in context:
        context["pending_config"] = {}
    
    context["pending_config"][key] = value
    
    print(f"   └─ Staged: {key} = {value}")
    
    return {"staged": True, "key": key, "value": value}


async def commit(context, dependencies, event_data):
    """Commit staged config"""
    print("   └─ Committing staged config...")
    return await resolve(context, dependencies, event_data)


async def rollback(context, dependencies, event_data):
    """Discard pending changes"""
    context["pending_config"] = {}
    print("   └─ ✅ Pending config discarded")
    return {"rollback": True}
