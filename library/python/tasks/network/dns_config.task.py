#!/usr/bin/env python3
# v2.0.0
"""dns_config - Migrated to v2.0"""

import asyncio

TASK_NAME = "dns_config"
TASK_DESCRIPTION = "dns config"
DEPENDS_ON = []

async def resolve(context, dependencies, event_data):
    config = context.get("task_config", {}).get("dns_config", {})
    env_flags = context.get("environment_flags", {})
    silent = env_flags.get("silent_mode", False)
    
    if not silent:
        print(f"   └─ Executing dns_config...")
    await asyncio.sleep(0.3)
    
    return {"completed": True, "task": "dns_config"}

async def reject(context, error, event_data):
    print(f"   └─ dns_config failed: {error}")
    raise error
