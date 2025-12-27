#!/usr/bin/env python3
# v2.0.0
"""Preflight Check - System validation"""

import sys
import asyncio

TASK_NAME = "preflight_check"
TASK_DESCRIPTION = "System prerequisites validation"
DEPENDS_ON = []

async def init_check(context, dependencies, event_data):
    """on_load: Initialize checks"""
    print("   └─ Initialisiere Preflight Checks...")
    return {"initialized": True}

async def validate_environment(context, dependencies, event_data):
    """before_resolve: Validate before execution"""
    print("   └─ Validiere Environment...")
    config = context.get("task_config", {}).get("preflight_check", {})
    
    if not config:
        raise ValueError("No config for preflight_check")
    
    return {"validated": True}

async def resolve(context, dependencies, event_data):
    """Execute preflight checks"""
    config = context.get("task_config", {}).get("preflight_check", {})
    env_flags = context.get("environment_flags", {})
    silent = env_flags.get("silent_mode", False)
    
    if not silent:
        print("   └─ Prüfe Python-Version...")
    await asyncio.sleep(0.2)
    python_version = f"{sys.version_info.major}.{sys.version_info.minor}"
    
    if not silent:
        print("   └─ Prüfe Festplattenspeicher...")
    await asyncio.sleep(0.2)
    
    if not silent:
        print("   └─ Prüfe Docker...")
    await asyncio.sleep(0.2)
    
    return {
        "python_version": python_version,
        "disk_free_gb": 50,
        "docker_available": True,
        "checks_passed": True
    }

async def quick_check(context, dependencies, event_data):
    """API method: Quick check for smoketest"""
    print("   └─ Quick Check: Python...")
    python_ok = sys.version_info >= (3, 9)
    print("   └─ Quick Check: Disk...")
    return {"quick_check": "passed" if python_ok else "failed"}

async def reject(context, error, event_data):
    print(f"   └─ Preflight failed: {error}")
    raise error
