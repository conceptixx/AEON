#!/usr/bin/env python3
# v2.0.0
"""create_user - Migrated to v2.0"""

import asyncio

TASK_NAME = "create_user"
TASK_DESCRIPTION = "create user"
DEPENDS_ON = []

async def resolve(context, dependencies, event_data):
    config = context.get("task_config", {}).get("create_user", {})
    env_flags = context.get("environment_flags", {})
    silent = env_flags.get("silent_mode", False)
    
    if not silent:
        print(f"   └─ Executing create_user...")
    await asyncio.sleep(0.3)
    
    return {"completed": True, "task": "create_user"}

async def reject(context, error, event_data):
    print(f"   └─ create_user failed: {error}")
    raise error
