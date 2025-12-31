"""
NEXUS v2 - Enterprise Module Base
Addresses Review: Security, Observability, Error Handling
"""

from abc import ABC, abstractmethod
from enum import Enum
from typing import Dict, List, Any, Optional, Set, Callable
from dataclasses import dataclass, field
import asyncio
import logging
import time
from datetime import datetime
from contextlib import asynccontextmanager


# Structured logging
logger = logging.getLogger(__name__)


class ModuleState(Enum):
    """Module lifecycle states"""
    UNLOADED = "unloaded"
    LOADED = "loaded"
    STARTED = "started"
    STOPPED = "stopped"
    FAILED = "failed"


class SecurityContext:
    """
    Security context for module operations.
    Addresses Review: No Authentication/Authorization
    """
    
    def __init__(
        self,
        principal: str,
        roles: List[str],
        permissions: List[str]
    ):
        self.principal = principal
        self.roles = roles
        self.permissions = permissions
        self.authenticated_at = datetime.now()
    
    def has_permission(self, permission: str) -> bool:
        """Check if principal has permission"""
        return permission in self.permissions or "admin" in self.roles
    
    def has_role(self, role: str) -> bool:
        """Check if principal has role"""
        return role in self.roles


@dataclass
class ModuleManifest:
    """
    Module descriptor - declarative, introspectable, versionable.
    Enhanced with security and operational metadata.
    """
    id: str
    group: str
    version: str
    description: str = ""
    required: bool = False
    provides: List[str] = field(default_factory=list)
    consumes: List[str] = field(default_factory=list)
    hard_deps: List[str] = field(default_factory=list)
    soft_deps: List[str] = field(default_factory=list)
    config_keys: Dict[str, Any] = field(default_factory=dict)
    resources: Dict[str, Any] = field(default_factory=dict)
    hot_unload_allowed: bool = True
    hot_unload_reason: str = ""
    
    # Security metadata
    required_permissions: List[str] = field(default_factory=list)
    sensitive: bool = False  # Contains secrets/PII
    
    # Operational metadata
    author: str = ""
    license: str = ""
    source_url: str = ""
    
    def __post_init__(self):
        """Validate manifest on creation"""
        if not self.id or "/" not in self.id:
            raise ValueError(f"Invalid module ID: {self.id}. Must be 'group/name'")
        
        group_from_id = self.id.split("/")[0]
        if self.group != group_from_id:
            raise ValueError(
                f"Group mismatch: manifest.group={self.group} but "
                f"id={self.id} implies {group_from_id}"
            )


class MetricsCollector:
    """
    Metrics collection interface.
    Addresses Review: No Metrics Exposition
    """
    
    def __init__(self, module_id: str):
        self.module_id = module_id
        self._counters: Dict[str, int] = {}
        self._gauges: Dict[str, float] = {}
        self._histograms: Dict[str, List[float]] = {}
    
    def increment(self, name: str, value: int = 1, labels: Dict[str, str] = None):
        """Increment counter"""
        key = self._make_key(name, labels)
        self._counters[key] = self._counters.get(key, 0) + value
        logger.debug(f"[{self.module_id}] Counter {name}={self._counters[key]}")
    
    def gauge(self, name: str, value: float, labels: Dict[str, str] = None):
        """Set gauge value"""
        key = self._make_key(name, labels)
        self._gauges[key] = value
        logger.debug(f"[{self.module_id}] Gauge {name}={value}")
    
    def histogram(self, name: str, value: float, labels: Dict[str, str] = None):
        """Record histogram value"""
        key = self._make_key(name, labels)
        if key not in self._histograms:
            self._histograms[key] = []
        self._histograms[key].append(value)
        logger.debug(f"[{self.module_id}] Histogram {name}={value}")
    
    def _make_key(self, name: str, labels: Optional[Dict[str, str]]) -> str:
        """Create metric key with labels"""
        if not labels:
            return name
        label_str = ",".join(f"{k}={v}" for k, v in sorted(labels.items()))
        return f"{name}{{{label_str}}}"
    
    def export_prometheus(self) -> str:
        """Export metrics in Prometheus format"""
        lines = []
        
        # Counters
        for key, value in self._counters.items():
            lines.append(f'nexus_{self.module_id.replace("/", "_")}_{key} {value}')
        
        # Gauges
        for key, value in self._gauges.items():
            lines.append(f'nexus_{self.module_id.replace("/", "_")}_{key} {value}')
        
        # Histograms (simplified - just count)
        for key, values in self._histograms.items():
            lines.append(f'nexus_{self.module_id.replace("/", "_")}_{key}_count {len(values)}')
            if values:
                lines.append(f'nexus_{self.module_id.replace("/", "_")}_{key}_sum {sum(values)}')
        
        return "\n".join(lines)


class BaseModule(ABC):
    """
    Enhanced Universal Module Interface.
    
    Improvements from Review:
    - Consistent error handling (exceptions, not return False)
    - Integrated metrics collection
    - Structured logging
    - Security context awareness
    - Resource tracking
    """
    
    def __init__(self, manifest: ModuleManifest):
        self.manifest = manifest
        self._state = ModuleState.UNLOADED
        self._last_error: Optional[Exception] = None
        self._background_tasks: Set[asyncio.Task] = set()
        self._start_time: Optional[datetime] = None
        self._stop_time: Optional[datetime] = None
        
        # Observability
        self.metrics = MetricsCollector(manifest.id)
        self.logger = logging.getLogger(f"nexus.module.{manifest.id}")
        
        # Security
        self._security_context: Optional[SecurityContext] = None
        
        # Resource tracking
        self._resource_usage = {
            "cpu_seconds": 0.0,
            "memory_mb": 0.0,
            "requests_total": 0,
            "errors_total": 0
        }
    
    @classmethod
    @abstractmethod
    def get_manifest(cls) -> ModuleManifest:
        """Return module manifest - called before instantiation"""
        pass
    
    @abstractmethod
    async def init(self, context: Dict[str, Any]):
        """
        Initialize module - load config, validate dependencies.
        
        Raises:
            ValueError: Invalid configuration
            RuntimeError: Initialization failure
        """
        pass
    
    @abstractmethod
    async def load(self, context: Dict[str, Any]):
        """
        Load module - reserve resources, connect to dependencies.
        
        Raises:
            ConnectionError: Failed to connect to dependency
            ResourceError: Failed to allocate resources
        """
        pass
    
    @abstractmethod
    async def start(self):
        """
        Start module - begin active work.
        
        Raises:
            RuntimeError: Failed to start
        """
        pass
    
    @abstractmethod
    async def stop(self):
        """
        Stop module gracefully.
        
        Raises:
            TimeoutError: Stop timeout exceeded
        """
        pass
    
    @abstractmethod
    async def unload(self):
        """
        Unload module - release all resources.
        Must be idempotent.
        """
        pass
    
    @abstractmethod
    async def health(self) -> Dict[str, Any]:
        """
        Health check - return module status.
        
        Returns:
            {
                "status": "healthy" | "degraded" | "unhealthy",
                "ready": bool,
                "live": bool,
                "details": {...}
            }
        """
        pass
    
    # Protected helper methods
    
    def _set_state(self, new_state: ModuleState):
        """Thread-safe state transition with logging"""
        old_state = self._state
        self._state = new_state
        
        self.logger.info(
            f"State transition: {old_state.value} -> {new_state.value}",
            extra={
                "module_id": self.manifest.id,
                "old_state": old_state.value,
                "new_state": new_state.value
            }
        )
        
        if new_state == ModuleState.STARTED:
            self._start_time = datetime.now()
            self.metrics.gauge("state", 1.0)
        elif new_state in (ModuleState.STOPPED, ModuleState.FAILED):
            self._stop_time = datetime.now()
            self.metrics.gauge("state", 0.0)
    
    def _spawn_background_task(self, coro, name: str = None):
        """
        Spawn a tracked background task with automatic cleanup.
        """
        task = asyncio.create_task(coro, name=name or f"{self.manifest.id}_bg")
        self._background_tasks.add(task)
        task.add_done_callback(self._background_tasks.discard)
        
        self.metrics.increment("background_tasks_spawned")
        return task
    
    async def _cancel_background_tasks(self, timeout: float = 5.0):
        """Cancel all background tasks with timeout"""
        if not self._background_tasks:
            return
        
        self.logger.info(f"Cancelling {len(self._background_tasks)} background tasks")
        
        for task in self._background_tasks:
            task.cancel()
        
        try:
            await asyncio.wait_for(
                asyncio.gather(*self._background_tasks, return_exceptions=True),
                timeout=timeout
            )
        except asyncio.TimeoutError:
            self.logger.warning(f"Background task cancellation timeout after {timeout}s")
            # Force cleanup
            for task in self._background_tasks:
                if not task.done():
                    task.cancel()
    
    @asynccontextmanager
    async def _track_operation(self, operation: str):
        """
        Context manager for tracking operations with metrics.
        
        Usage:
            async with self._track_operation("database_query"):
                await db.query(...)
        """
        start = time.time()
        self.metrics.increment(f"{operation}_total")
        
        try:
            yield
            self.metrics.increment(f"{operation}_success")
        except Exception as e:
            self.metrics.increment(f"{operation}_error")
            self.logger.error(f"{operation} failed: {e}", exc_info=True)
            raise
        finally:
            duration = time.time() - start
            self.metrics.histogram(f"{operation}_duration_seconds", duration)
    
    def _require_permission(self, permission: str):
        """
        Check if current security context has permission.
        
        Raises:
            PermissionError: If permission not granted
        """
        if not self._security_context:
            raise PermissionError("No security context set")
        
        if not self._security_context.has_permission(permission):
            raise PermissionError(
                f"Permission denied: {permission} "
                f"(principal: {self._security_context.principal})"
            )
    
    # Public properties
    
    @property
    def state(self) -> ModuleState:
        """Current module state"""
        return self._state
    
    @property
    def is_loaded(self) -> bool:
        """Is module loaded?"""
        return self._state in (ModuleState.LOADED, ModuleState.STARTED)
    
    @property
    def is_started(self) -> bool:
        """Is module started?"""
        return self._state == ModuleState.STARTED
    
    @property
    def uptime_seconds(self) -> Optional[float]:
        """Module uptime in seconds, or None if not started"""
        if not self._start_time:
            return None
        
        end_time = self._stop_time or datetime.now()
        return (end_time - self._start_time).total_seconds()
    
    @property
    def security_context(self) -> Optional[SecurityContext]:
        """Current security context"""
        return self._security_context
    
    @security_context.setter
    def security_context(self, ctx: SecurityContext):
        """Set security context"""
        self._security_context = ctx
        self.logger.info(
            f"Security context set: {ctx.principal}",
            extra={"principal": ctx.principal, "roles": ctx.roles}
        )
