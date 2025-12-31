"""
NEXUS v2 - Heartbeat Client Module
Example module showcasing v2 features:
- Security context awareness
- Metrics collection
- Structured logging
- Operation tracking
- State persistence
"""

import asyncio
from typing import Dict, Any
from nexus_v2.core import BaseModule, ModuleManifest, ModuleState


class HeartbeatClient(BaseModule):
    """
    Heartbeat client - sends periodic heartbeat signals.
    
    v2 Enhancements:
    - Permission checks
    - Metrics export
    - Structured logging
    - Operation tracking
    """
    
    @classmethod
    def get_manifest(cls) -> ModuleManifest:
        """Define module manifest with v2 security metadata"""
        return ModuleManifest(
            id="vitals/heartbeat-client",
            group="vitals",
            version="2.0.0",
            description="Periodic heartbeat sender with metrics and security",
            required=True,
            provides=["vitals.heartbeat.sender"],
            consumes=[],
            hard_deps=[],
            soft_deps=[],
            config_keys={
                "interval_ms": 1000,
                "target": "console",
                "enabled": True,
            },
            resources={
                "threads": 1,
                "memory_mb": 10,
            },
            hot_unload_allowed=True,
            hot_unload_reason="",
            # v2: Security metadata
            required_permissions=["heartbeat.send"],
            sensitive=False,
            # v2: Operational metadata
            author="NEXUS Project",
            license="MIT"
        )
    
    def __init__(self, manifest: ModuleManifest):
        super().__init__(manifest)
        
        # Module state
        self._interval_ms = 1000
        self._target = "console"
        self._enabled = True
        self._heartbeat_task = None
        self._heartbeat_count = 0
    
    async def init(self, context: Dict[str, Any]):
        """
        Initialize module with v2 improvements.
        """
        try:
            config = context["config"]
            
            # v2: Structured logging with extra fields
            self.logger.info(
                "Initializing heartbeat client",
                extra={"module_id": self.manifest.id}
            )
            
            # Load configuration (type-safe)
            self._interval_ms = config.get(
                self.manifest.id,
                "interval_ms",
                default=1000,
                expected_type=int
            )
            
            self._target = config.get(
                self.manifest.id,
                "target",
                default="console",
                expected_type=str
            )
            
            self._enabled = config.get(
                self.manifest.id,
                "enabled",
                default=True,
                expected_type=bool
            )
            
            # Validate configuration
            if self._interval_ms < 100:
                raise ValueError("interval_ms must be >= 100")
            
            if self._interval_ms > 60000:
                raise ValueError("interval_ms must be <= 60000")
            
            # v2: Restore state if available
            if 'persisted_state' in context:
                state = context['persisted_state']
                self._heartbeat_count = state.get('heartbeat_count', 0)
                self.logger.info(
                    f"Restored state: {self._heartbeat_count} heartbeats",
                    extra={"heartbeat_count": self._heartbeat_count}
                )
            
            self.logger.info(
                "Configuration loaded",
                extra={
                    "interval_ms": self._interval_ms,
                    "target": self._target,
                    "enabled": self._enabled
                }
            )
            
            self._set_state(ModuleState.LOADED)
            
        except Exception as e:
            self.logger.error(f"Init failed: {e}", exc_info=True)
            self._last_error = e
            self._set_state(ModuleState.FAILED)
            raise  # v2: Always raise exceptions
    
    async def load(self, context: Dict[str, Any]):
        """
        Load module - prepare resources.
        """
        try:
            # v2: Track operation with metrics
            async with self._track_operation("load"):
                # In a real module: open sockets, connect to databases, etc.
                await asyncio.sleep(0.01)  # Simulate resource preparation
            
            self.logger.info("Resources prepared")
            
        except Exception as e:
            self.logger.error(f"Load failed: {e}", exc_info=True)
            self._last_error = e
            self._set_state(ModuleState.FAILED)
            raise
    
    async def start(self):
        """
        Start module - begin active work.
        """
        try:
            if not self._enabled:
                self.logger.warning("Module disabled in config, not starting")
                raise RuntimeError("Module disabled")
            
            # v2: Check permission
            if self.security_context:
                self._require_permission("heartbeat.send")
            
            # v2: Track operation
            async with self._track_operation("start"):
                # Start heartbeat loop
                self._heartbeat_task = self._spawn_background_task(
                    self._heartbeat_loop(),
                    name="heartbeat_loop"
                )
            
            self._set_state(ModuleState.STARTED)
            
            # v2: Set gauge metric
            self.metrics.gauge("enabled", 1.0)
            
            self.logger.info("Heartbeat loop started")
            
        except PermissionError as e:
            self.logger.error(f"Permission denied: {e}")
            self._last_error = e
            self._set_state(ModuleState.FAILED)
            raise
        except Exception as e:
            self.logger.error(f"Start failed: {e}", exc_info=True)
            self._last_error = e
            self._set_state(ModuleState.FAILED)
            raise
    
    async def stop(self):
        """
        Stop module gracefully with state save.
        """
        try:
            self.logger.info("Stopping heartbeat loop...")
            
            # v2: Track operation
            async with self._track_operation("stop"):
                # Cancel background tasks
                await self._cancel_background_tasks(timeout=5.0)
            
            self._set_state(ModuleState.STOPPED)
            
            # v2: Set gauge metric
            self.metrics.gauge("enabled", 0.0)
            
            self.logger.info(
                f"Stopped (sent {self._heartbeat_count} heartbeats)",
                extra={"heartbeat_count": self._heartbeat_count}
            )
            
        except Exception as e:
            self.logger.error(f"Stop failed: {e}", exc_info=True)
            self._last_error = e
            raise
    
    async def unload(self):
        """
        Unload module - release all resources.
        """
        try:
            # v2: Idempotent cleanup
            if self._heartbeat_task:
                self._heartbeat_task = None
            
            # Note: Don't reset _heartbeat_count - will be saved to state
            
            self._set_state(ModuleState.UNLOADED)
            self.logger.info("Unloaded, resources released")
            
        except Exception as e:
            self.logger.error(f"Unload failed: {e}", exc_info=True)
            self._last_error = e
            raise
    
    async def health(self) -> Dict[str, Any]:
        """
        Health check with detailed metrics.
        """
        is_healthy = (
            self.state == ModuleState.STARTED and
            self._heartbeat_task is not None and
            not self._heartbeat_task.done()
        )
        
        return {
            "status": "healthy" if is_healthy else "degraded",
            "ready": self.state == ModuleState.STARTED,
            "live": self._heartbeat_task is not None,
            "details": {
                "heartbeat_count": self._heartbeat_count,
                "interval_ms": self._interval_ms,
                "uptime_seconds": self.uptime_seconds,
                "target": self._target,
                # v2: Resource usage
                "resource_usage": self._resource_usage
            }
        }
    
    # Private methods
    
    async def _heartbeat_loop(self):
        """
        Main heartbeat loop with metrics.
        """
        try:
            while True:
                # Send heartbeat
                await self._send_heartbeat()
                
                # Wait for next interval
                await asyncio.sleep(self._interval_ms / 1000.0)
                
        except asyncio.CancelledError:
            self.logger.info("Heartbeat loop cancelled")
            raise
        except Exception as e:
            self.logger.error(f"Heartbeat loop error: {e}", exc_info=True)
            self._last_error = e
            self._set_state(ModuleState.FAILED)
            # v2: Track error
            self.metrics.increment("heartbeat_errors_total")
    
    async def _send_heartbeat(self):
        """
        Send a single heartbeat with metrics.
        """
        # v2: Track operation
        async with self._track_operation("heartbeat_send"):
            self._heartbeat_count += 1
            
            # v2: Increment counter metric
            self.metrics.increment("heartbeats_sent_total")
            
            # v2: Update gauge metrics
            self.metrics.gauge("heartbeat_count", float(self._heartbeat_count))
            
            # v2: Track resource usage
            self._resource_usage["requests_total"] += 1
            
            if self._target == "console":
                # For demonstration, print every 10th
                if self._heartbeat_count % 10 == 0:
                    self.logger.info(
                        f"❤️  Heartbeat #{self._heartbeat_count}",
                        extra={
                            "heartbeat_count": self._heartbeat_count,
                            "interval_ms": self._interval_ms
                        }
                    )
            else:
                # In production: send to actual target (socket, API, etc.)
                pass
