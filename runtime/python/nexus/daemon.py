"""
NEXUS v2 - Universal Daemon
Enterprise-Grade Orchestrator with Security & Observability
"""

import asyncio
import signal
import logging
from typing import Dict, List, Optional, Any
from pathlib import Path

from .core.config import ConfigurationManager
from .core.loader import ModuleLoader
from .core.module import ModuleState, SecurityContext


logger = logging.getLogger(__name__)


class UniversalDaemon:
    """
    Universal Daemon - Enterprise-grade orchestrator.
    
    Improvements from v1:
    - Security context propagation
    - State persistence
    - Structured logging
    - Better error handling
    - Graceful shutdown with state save
    """
    
    def __init__(
        self,
        config_path: Optional[str] = None,
        security_context: Optional[SecurityContext] = None
    ):
        self.config = ConfigurationManager()
        
        # Load configuration
        if config_path:
            self.config.load_user_config(config_path)
        else:
            try:
                self.config.load_system_config()
            except Exception as e:
                logger.warning(f"No system config: {e}")
            
            try:
                self.config.load_user_config()
            except Exception as e:
                logger.warning(f"No user config: {e}")
        
        self.loader = ModuleLoader(self.config)
        self.security_context = security_context
        
        # Daemon state
        self._running = False
        self._shutdown_event = asyncio.Event()
        self._shutdown_timeout = 60.0
    
    async def initialize(self):
        """Initialize daemon"""
        logger.info("=" * 60)
        logger.info("NEXUS v2 Universal Daemon - Initializing")
        logger.info("=" * 60)
        
        if self.security_context:
            logger.info(
                f"Security context: {self.security_context.principal}",
                extra={
                    "principal": self.security_context.principal,
                    "roles": self.security_context.roles
                }
            )
    
    async def discover_and_load_modules(
        self,
        module_packages: List[str],
        parallel: bool = True
    ) -> bool:
        """
        Discover and load modules from packages.
        
        Args:
            module_packages: List of package names to scan
            parallel: Enable parallel loading
        
        Returns:
            True if all required modules loaded successfully
        """
        logger.info("Scanning for modules...")
        manifests = self.loader.discover_modules(module_packages)
        
        logger.info(f"Found {len(manifests)} modules:")
        for manifest in manifests:
            required_str = "REQUIRED" if manifest.required else "optional"
            perms_str = f" [perms: {', '.join(manifest.required_permissions)}]" if manifest.required_permissions else ""
            logger.info(f"  - {manifest.id} ({manifest.group}) [{required_str}]{perms_str}")
        
        # Load modules
        logger.info("Loading modules in dependency order...")
        try:
            results = await self.loader.load_modules(
                parallel=parallel,
                security_context=self.security_context
            )
            
            # Check results
            failed = [mid for mid, success in results.items() if not success]
            
            if failed:
                logger.error(f"Failed to load {len(failed)} modules:")
                for mid in failed:
                    logger.error(f"  - {mid}")
                
                # Check if any required modules failed
                required_failed = [
                    mid for mid in failed
                    if self.loader.registry.get_manifest(mid) and
                       self.loader.registry.get_manifest(mid).required
                ]
                
                if required_failed:
                    logger.critical(f"Required modules failed: {required_failed}")
                    return False
            
            logger.info(f"Successfully loaded {len(results) - len(failed)}/{len(results)} modules")
            return True
            
        except PermissionError as e:
            logger.error(f"Authorization failed: {e}")
            return False
        except Exception as e:
            logger.error(f"Load failed: {e}", exc_info=True)
            return False
    
    async def start(self) -> bool:
        """
        Start all loaded modules.
        
        Returns:
            True if all required modules started successfully
        """
        logger.info("Starting modules...")
        try:
            results = await self.loader.start_modules()
            
            failed = [mid for mid, success in results.items() if not success]
            
            if failed:
                logger.warning(f"{len(failed)} modules failed to start:")
                for mid in failed:
                    logger.warning(f"  - {mid}")
            
            logger.info(f"{len(results) - len(failed)}/{len(results)} modules running")
            
            self._running = True
            return len(failed) == 0
            
        except Exception as e:
            logger.error(f"Start failed: {e}", exc_info=True)
            return False
    
    async def run(self):
        """
        Run daemon until shutdown signal.
        """
        if not self._running:
            raise RuntimeError("Daemon not started. Call start() first.")
        
        logger.info("=" * 60)
        logger.info("NEXUS v2 Universal Daemon - Running")
        logger.info("Press Ctrl+C to shutdown gracefully")
        logger.info("=" * 60)
        
        # Install signal handlers
        loop = asyncio.get_running_loop()
        
        for sig in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(
                sig,
                lambda: asyncio.create_task(self.shutdown())
            )
        
        # Wait for shutdown event
        await self._shutdown_event.wait()
        
        logger.info("Daemon stopped")
    
    async def shutdown(self, timeout: Optional[float] = None):
        """
        Gracefully shutdown daemon with state persistence.
        
        Args:
            timeout: Timeout for shutdown in seconds (default: 60)
        """
        if not self._running:
            return
        
        timeout = timeout or self._shutdown_timeout
        
        logger.info("=" * 60)
        logger.info("NEXUS v2 Universal Daemon - Shutting down")
        logger.info("=" * 60)
        
        try:
            # Stop modules
            logger.info("Stopping modules...")
            stop_results = await asyncio.wait_for(
                self.loader.stop_modules(timeout=30.0),
                timeout=timeout * 0.6
            )
            
            failed_stop = [mid for mid, success in stop_results.items() if not success]
            if failed_stop:
                logger.warning(f"{len(failed_stop)} modules failed to stop cleanly")
            
            # Unload modules
            logger.info("Unloading modules...")
            unload_results = await asyncio.wait_for(
                self.loader.unload_modules(),
                timeout=timeout * 0.4
            )
            
            failed_unload = [mid for mid, success in unload_results.items() if not success]
            if failed_unload:
                logger.warning(f"{len(failed_unload)} modules failed to unload cleanly")
            
            logger.info("Cleanup complete")
            
        except asyncio.TimeoutError:
            logger.error(f"Shutdown timeout after {timeout}s - forcing exit")
        except Exception as e:
            logger.error(f"Shutdown error: {e}", exc_info=True)
        finally:
            self._running = False
            self._shutdown_event.set()
    
    async def reload_module(
        self,
        module_id: str,
        strategy: str = "graceful"
    ) -> bool:
        """
        Hot-reload a module.
        
        Args:
            module_id: Module to reload
            strategy: "graceful" (stop->unload->load->start)
        
        Returns:
            True if reload successful
        """
        logger.info(f"Reloading {module_id} (strategy: {strategy})")
        
        instance = self.loader.get_module(module_id)
        if not instance:
            logger.error(f"Module {module_id} not found")
            return False
        
        manifest = instance.manifest
        if not manifest.hot_unload_allowed:
            logger.error(f"Module {module_id} does not allow hot reload")
            logger.error(f"  Reason: {manifest.hot_unload_reason}")
            return False
        
        try:
            if strategy == "graceful":
                # Stop -> Unload -> Load -> Start
                await self.loader.lifecycle.stop_module(module_id)
                await self.loader.lifecycle.unload_module(module_id)
                
                context = {
                    "config": self.config,
                    "registry": self.loader.registry,
                }
                
                await self.loader.lifecycle.load_single_module(
                    module_id, context, self.security_context
                )
                await self.loader.lifecycle.start_module(module_id)
            
            else:
                logger.error(f"Unknown reload strategy: {strategy}")
                return False
            
            logger.info(f"Successfully reloaded {module_id}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to reload {module_id}: {e}", exc_info=True)
            return False
    
    async def get_status(self) -> Dict[str, Any]:
        """
        Get daemon status with health checks.
        """
        loader_status = self.loader.get_status()
        
        # Collect health from all modules
        health_checks = {}
        for module_id in list(self.loader.registry._instances.keys()):
            instance = self.loader.registry.get_instance(module_id)
            if not instance:
                continue
                
            try:
                health = await asyncio.wait_for(
                    instance.health(),
                    timeout=5.0
                )
                health_checks[module_id] = health
            except asyncio.TimeoutError:
                health_checks[module_id] = {
                    "status": "unhealthy",
                    "error": "health check timeout"
                }
            except Exception as e:
                health_checks[module_id] = {
                    "status": "unhealthy",
                    "error": str(e)
                }
        
        # Aggregate health statistics
        total_modules = len(health_checks)
        healthy_count = sum(
            1 for h in health_checks.values()
            if h.get("status") == "healthy"
        )
        
        return {
            "running": self._running,
            "security_context": {
                "principal": self.security_context.principal if self.security_context else None,
                "roles": self.security_context.roles if self.security_context else []
            },
            "modules": loader_status,
            "health": {
                "checks": health_checks,
                "statistics": {
                    "total": total_modules,
                    "healthy": healthy_count,
                    "degraded": sum(
                        1 for h in health_checks.values()
                        if h.get("status") == "degraded"
                    ),
                    "unhealthy": total_modules - healthy_count
                }
            }
        }
    
    async def export_metrics(self) -> str:
        """
        Export all module metrics in Prometheus format.
        """
        lines = []
        
        for module_id in list(self.loader.registry._instances.keys()):
            instance = self.loader.registry.get_instance(module_id)
            if instance:
                lines.append(instance.metrics.export_prometheus())
        
        return "\n".join(lines)


# Convenience function for simple daemon startup
async def run_daemon(
    module_packages: List[str],
    config_path: Optional[str] = None,
    security_context: Optional[SecurityContext] = None
):
    """
    Simple daemon startup helper.
    
    Args:
        module_packages: List of package names to load modules from
        config_path: Optional path to config file
        security_context: Optional security context for RBAC
    """
    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    daemon = UniversalDaemon(config_path, security_context)
    
    await daemon.initialize()
    
    success = await daemon.discover_and_load_modules(
        module_packages=module_packages,
        parallel=True
    )
    
    if not success:
        logger.critical("Failed to load required modules")
        return
    
    await daemon.start()
    await daemon.run()
