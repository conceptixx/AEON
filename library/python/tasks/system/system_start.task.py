#!/usr/bin/env python3
# v2.0.0
"""system_start - Migrated to v2.0"""

import asyncio

TASK_NAME = "system_start"
TASK_DESCRIPTION = "system start"
DEPENDS_ON = []

async def resolve(context, dependencies, event_data):
    config = context.get("task_config", {}).get("system_start", {})
    env_flags = context.get("environment_flags", {})
    silent = env_flags.get("silent_mode", False)
    
    if not silent:
        print(f"   └─ Executing system_start...")
    await asyncio.sleep(0.3)
    
    return {"completed": True, "task": "system_start"}

async def reject(context, error, event_data):
    print(f"   └─ system_start failed: {error}")
    raise error
