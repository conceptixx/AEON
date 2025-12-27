#!/usr/bin/env python3
# v2.0.0
"""system_ready - Migrated to v2.0"""

import asyncio

TASK_NAME = "system_ready"
TASK_DESCRIPTION = "system ready"
DEPENDS_ON = []

async def resolve(context, dependencies, event_data):
    config = context.get("task_config", {}).get("system_ready", {})
    env_flags = context.get("environment_flags", {})
    silent = env_flags.get("silent_mode", False)
    
    if not silent:
        print(f"   └─ Executing system_ready...")
    await asyncio.sleep(0.3)
    
    return {"completed": True, "task": "system_ready"}

async def reject(context, error, event_data):
    print(f"   └─ system_ready failed: {error}")
    raise error
