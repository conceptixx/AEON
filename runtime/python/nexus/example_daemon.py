#!/usr/bin/env python3
"""
NEXUS v2 - Example Daemon Runner
Demonstrates enterprise features:
- Security context (RBAC)
- Configuration management
- State persistence
- Metrics export
"""

import asyncio
import logging
import os
from pathlib import Path

from nexus_v2 import (
    UniversalDaemon,
    SecurityContext,
    ConfigurationManager,
    FileSecretProvider
)


# Configure structured logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger(__name__)


async def main():
    """Run the daemon with v2 features"""
    
    logger.info("NEXUS v2 - Example Daemon")
    logger.info("=" * 60)
    
    # ============================================================
    # 1. Security Context (RBAC)
    # ============================================================
    
    # In production: Get from authentication service
    security_ctx = SecurityContext(
        principal="admin@company.com",
        roles=["admin", "operator"],
        permissions=[
            "module.load",
            "module.unload",
            "module.start",
            "module.stop",
            "heartbeat.send"
        ]
    )
    
    logger.info(f"Security context: {security_ctx.principal}")
    logger.info(f"  Roles: {', '.join(security_ctx.roles)}")
    logger.info(f"  Permissions: {len(security_ctx.permissions)}")
    
    # ============================================================
    # 2. Configuration with Secrets
    # ============================================================
    
    # Setup secret provider (File-based for development)
    # In production: Use VaultSecretProvider
    secrets_dir = Path.home() / ".nexus" / "secrets"
    secrets_dir.mkdir(parents=True, exist_ok=True)
    
    secret_provider = FileSecretProvider(secrets_dir)
    
    # Example: Store a secret
    try:
        secret_provider.set_secret("example/api_key", "demo-secret-key-12345")
        logger.info("Demo secret stored in ~/.nexus/secrets/")
    except Exception as e:
        logger.warning(f"Could not store secret: {e}")
    
    # ============================================================
    # 3. Create Daemon with State Persistence
    # ============================================================
    
    daemon = UniversalDaemon(
        config_path=None,  # Use default locations
        security_context=security_ctx
    )
    
    # Initialize
    await daemon.initialize()
    
    # ============================================================
    # 4. Discover and Load Modules
    # ============================================================
    
    success = await daemon.discover_and_load_modules(
        module_packages=["nexus_v2.modules.vitals"],
        parallel=True  # Parallel loading enabled
    )
    
    if not success:
        logger.critical("Failed to load required modules")
        return 1
    
    # ============================================================
    # 5. Start Modules
    # ============================================================
    
    await daemon.start()
    
    # ============================================================
    # 6. Get Status & Metrics
    # ============================================================
    
    # Wait a bit for some heartbeats
    await asyncio.sleep(2)
    
    # Get status
    status = await daemon.get_status()
    logger.info("\n" + "=" * 60)
    logger.info("DAEMON STATUS")
    logger.info("=" * 60)
    logger.info(f"Running: {status['running']}")
    logger.info(f"Modules: {status['modules']['total_loaded']}")
    logger.info(f"Health: {status['health']['statistics']['healthy']}/{status['health']['statistics']['total']} healthy")
    
    # Export metrics
    metrics = await daemon.export_metrics()
    logger.info("\n" + "=" * 60)
    logger.info("PROMETHEUS METRICS (Sample)")
    logger.info("=" * 60)
    for line in metrics.split('\n')[:10]:  # First 10 lines
        if line:
            logger.info(line)
    
    # ============================================================
    # 7. Run until interrupted
    # ============================================================
    
    logger.info("\n" + "=" * 60)
    logger.info("Daemon is running. Press Ctrl+C to stop.")
    logger.info("=" * 60)
    
    try:
        await daemon.run()
    except KeyboardInterrupt:
        logger.info("\nShutdown requested")
    
    return 0


if __name__ == "__main__":
    exit_code = asyncio.run(main())
    exit(exit_code)
