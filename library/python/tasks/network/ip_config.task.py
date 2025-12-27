#!/usr/bin/env python3
# v2.0.0
"""ip_config - Migrated to v2.0"""

import asyncio

TASK_NAME = "ip_config"
TASK_DESCRIPTION = "ip config"
DEPENDS_ON = []

async def resolve(context, dependencies, event_data):
    config = context.get("task_config", {}).get("ip_config", {})
    env_flags = context.get("environment_flags", {})
    silent = env_flags.get("silent_mode", False)
    
    if not silent:
        print(f"   └─ Executing ip_config...")
    await asyncio.sleep(0.3)
    
    return {"completed": True, "task": "ip_config"}

async def reject(context, error, event_data):
    print(f"   └─ ip_config failed: {error}")
    raise error
