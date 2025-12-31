# NEXUS v2 - Module Lifecycle Guide

**Complete Guide to Building Enterprise-Grade Modules**

---

## Table of Contents

1. [Introduction](#introduction)
2. [Module Lifecycle States](#module-lifecycle-states)
3. [Creating Your First Module](#creating-your-first-module)
4. [Security Integration (NEW in v2)](#security-integration-new-in-v2)
5. [Configuration Management](#configuration-management)
6. [Secret Management (NEW in v2)](#secret-management-new-in-v2)
7. [Observability (NEW in v2)](#observability-new-in-v2)
8. [State Persistence (NEW in v2)](#state-persistence-new-in-v2)
9. [Background Tasks](#background-tasks)
10. [Error Handling](#error-handling)
11. [Health Checks](#health-checks)
12. [Dependencies](#dependencies)
13. [Best Practices](#best-practices)
14. [Complete Example](#complete-example)

---

## Introduction

NEXUS v2 provides an enterprise-grade module system with:

- **Security:** RBAC with SecurityContext and permission checks
- **Secrets:** Vault/File/Env integration
- **Observability:** Structured logging, Prometheus metrics, operation tracking
- **Resilience:** State persistence, consistent error handling
- **Architecture:** Clean separation of concerns

Every module follows a **5-phase lifecycle**:

```
UNLOADED → init() → LOADED → load() → LOADED → start() → STARTED
    ↑                                                         ↓
    └──────── unload() ← STOPPED ← stop() ──────────────────┘
```

---

## Module Lifecycle States

### State Diagram

```
┌─────────────┐
│  UNLOADED   │  Initial state
└──────┬──────┘
       │ init()
       ↓
┌─────────────┐
│   LOADED    │  Config loaded, resources reserved
└──────┬──────┘
       │ start()
       ↓
┌─────────────┐
│   STARTED   │  Active work in progress
└──────┬──────┘
       │ stop()
       ↓
┌─────────────┐
│   STOPPED   │  Gracefully stopped
└──────┬──────┘
       │ unload()
       ↓
┌─────────────┐
│  UNLOADED   │  All resources released
└─────────────┘

      FAILED    Can occur at any point on error
```

### State Descriptions

| State | Description | Valid Operations |
|-------|-------------|------------------|
| **UNLOADED** | Module not loaded | init() |
| **LOADED** | Config loaded, ready to start | start(), unload() |
| **STARTED** | Actively running | stop() |
| **STOPPED** | Gracefully stopped | unload(), start() |
| **FAILED** | Error occurred | unload() |

---

## Creating Your First Module

### Minimal Module

```python
from nexus_v2.core import BaseModule, ModuleManifest, ModuleState

class HelloModule(BaseModule):
    """Minimal working module"""
    
    @classmethod
    def get_manifest(cls) -> ModuleManifest:
        return ModuleManifest(
            id="demo/hello",
            group="demo",
            version="1.0.0",
            description="Hello world module"
        )
    
    async def init(self, context):
        """Load configuration, validate"""
        self.logger.info("Hello, initializing!")
        self._set_state(ModuleState.LOADED)
    
    async def load(self, context):
        """Reserve resources"""
        self.logger.info("Loading resources...")
    
    async def start(self):
        """Begin active work"""
        self.logger.info("Starting work!")
        self._set_state(ModuleState.STARTED)
    
    async def stop(self):
        """Stop gracefully"""
        self.logger.info("Stopping work...")
        self._set_state(ModuleState.STOPPED)
    
    async def unload(self):
        """Release resources"""
        self.logger.info("Goodbye!")
        self._set_state(ModuleState.UNLOADED)
    
    async def health(self):
        """Health check"""
        return {
            "status": "healthy" if self.is_started else "degraded",
            "ready": self.is_started,
            "live": True
        }
```

---

## Security Integration (NEW in v2)

### RBAC (Role-Based Access Control)

**1. Define Required Permissions in Manifest**

```python
@classmethod
def get_manifest(cls):
    return ModuleManifest(
        id="database/postgres",
        group="database",
        version="1.0.0",
        # ✅ v2: Security metadata
        required_permissions=["database.admin", "database.write"],
        sensitive=True  # Contains secrets/PII
    )
```

**2. Check Permissions Before Operations**

```python
async def start(self):
    # ✅ v2: Check permission
    self._require_permission("database.admin")
    
    # Only reached if permission granted
    await self._start_server()
    self._set_state(ModuleState.STARTED)
```

**3. Access Security Context**

```python
async def init(self, context):
    if self.security_context:
        self.logger.info(
            f"Running as: {self.security_context.principal}",
            extra={
                "principal": self.security_context.principal,
                "roles": self.security_context.roles
            }
        )
    
    self._set_state(ModuleState.LOADED)
```

### Permission Enforcement

The `_require_permission()` helper raises `PermissionError` if:
- No security context is set
- Principal doesn't have the required permission

```python
try:
    self._require_permission("admin.action")
except PermissionError as e:
    self.logger.error(f"Access denied: {e}")
    raise
```

---

## Configuration Management

### Type-Safe Configuration

```python
async def init(self, context):
    config = context["config"]
    
    # ✅ Type-safe with automatic conversion
    self._port = config.get(
        self.manifest.id,
        "port",
        default=8080,
        expected_type=int  # Validates and converts
    )
    
    self._timeout = config.get(
        self.manifest.id,
        "timeout_ms",
        default=5000,
        expected_type=int
    )
    
    # Validate
    if self._port < 1024 or self._port > 65535:
        raise ValueError(f"Invalid port: {self._port}")
    
    self._set_state(ModuleState.LOADED)
```

### Configuration Precedence

Configuration is resolved from 5 layers (highest to lowest priority):

1. **Runtime overrides** - `config.set_runtime_override()`
2. **Environment variables** - `NEXUS_GROUP_MODULE_KEY`
3. **User config** - `~/.nexus/config.yaml`
4. **Module defaults** - `manifest.config_keys`
5. **System config** - `/etc/nexus/config.yaml`

**Example YAML:**
```yaml
database:
  postgres:
    host: "localhost"
    port: 5432
    database: "myapp"
    pool_size: 10
```

**Example Environment:**
```bash
export NEXUS_DATABASE_POSTGRES_HOST="prod-db.company.com"
export NEXUS_DATABASE_POSTGRES_PORT="5432"
```

### Hot-Reload Callbacks

```python
async def init(self, context):
    config = context["config"]
    
    # ✅ v2: Register callback for config changes
    config.register_reload_callback(
        self.manifest.id,
        self._on_config_change
    )
    
    self._load_config(config)
    self._set_state(ModuleState.LOADED)

def _on_config_change(self, key: str, value: Any):
    """Called when config changes at runtime"""
    self.logger.info(f"Config changed: {key} = {value}")
    
    if key == "pool_size":
        self._adjust_pool_size(value)
```

---

## Secret Management (NEW in v2)

### Fetching Secrets from Vault

```python
async def init(self, context):
    config = context["config"]
    
    # ✅ v2: Get secret from Vault, NOT from YAML
    self._db_password = config.get(
        self.manifest.id,
        "password",
        secret=True  # Fetched from secret provider
    )
    
    self._api_key = config.get(
        self.manifest.id,
        "api_key",
        secret=True
    )
    
    self.logger.info("Secrets loaded from Vault")
    self._set_state(ModuleState.LOADED)
```

**Never log secrets:**
```python
# ❌ WRONG - logs secret
self.logger.info(f"Using password: {self._db_password}")

# ✅ CORRECT - logs that secret was loaded
self.logger.info("Database password loaded from Vault")
```

### Setting Secrets

```python
# Store secret in Vault
config.set_secret(
    self.manifest.id,
    "api_key",
    "sk-prod-123456789"
)
# Audit log entry created automatically
```

---

## Observability (NEW in v2)

### Structured Logging

```python
async def start(self):
    # ✅ v2: Structured logging with metadata
    self.logger.info(
        "Starting database connection pool",
        extra={
            "module_id": self.manifest.id,
            "pool_size": self._pool_size,
            "host": self._host,
            "port": self._port
        }
    )
    
    self._set_state(ModuleState.STARTED)
```

**Output:**
```
2025-12-31 12:00:00 - nexus.module.database/postgres - INFO - Starting database connection pool
  Extra: {"module_id": "database/postgres", "pool_size": 10, "host": "localhost", "port": 5432}
```

### Metrics Collection

**1. Automatic Operation Tracking**

```python
async def execute_query(self, query):
    # ✅ v2: Track operation with metrics
    async with self._track_operation("database_query"):
        result = await self._db.execute(query)
        return result
    
    # Automatically tracked:
    # - database_query_total (counter)
    # - database_query_success (counter)
    # - database_query_error (counter on exception)
    # - database_query_duration_seconds (histogram)
```

**2. Manual Metrics**

```python
async def _process_batch(self):
    # Counter
    self.metrics.increment("batch_processed_total")
    
    # Gauge
    self.metrics.gauge("queue_size", len(self._queue))
    
    # Histogram
    self.metrics.histogram("batch_size", len(batch))
```

**3. Export Metrics**

```python
# Prometheus format
metrics = module.metrics.export_prometheus()

# Output:
# nexus_database_postgres_batch_processed_total 15000
# nexus_database_postgres_queue_size 42
# nexus_database_postgres_batch_size_count 1500
# nexus_database_postgres_batch_size_sum 45000
```

### Resource Tracking

Automatic resource tracking per module:

```python
# Tracked automatically
module._resource_usage
# {
#   "cpu_seconds": 120.3,
#   "memory_mb": 45.2,
#   "requests_total": 15000,
#   "errors_total": 3
# }

# Update manually
self._resource_usage["requests_total"] += 1
```

---

## State Persistence (NEW in v2)

### Saving State

State is automatically persisted when module stops:

```python
async def stop(self):
    # Do your cleanup
    await self._cleanup()
    
    self._set_state(ModuleState.STOPPED)
    
    # State automatically saved by loader:
    # {
    #   "stopped_at": "2025-12-31T12:00:00",
    #   "uptime_seconds": 3600.5,
    #   "resource_usage": {...}
    # }
```

### Loading State

State is automatically restored on load:

```python
async def init(self, context):
    # ✅ v2: Check for persisted state
    if 'persisted_state' in context:
        state = context['persisted_state']
        
        # Restore your module state
        self._request_count = state.get('request_count', 0)
        self._last_run = state.get('last_run')
        
        self.logger.info(
            f"Restored state: {self._request_count} requests processed",
            extra={"request_count": self._request_count}
        )
    
    self._set_state(ModuleState.LOADED)
```

### Custom State

Add custom state to be persisted:

```python
async def stop(self):
    # Your custom state will be included if you add it to context
    # during load phase
    
    self._set_state(ModuleState.STOPPED)
```

**Note:** StateStore saves automatically. To add custom fields, implement your own StateStore.

---

## Background Tasks

### Spawning Tasks

```python
async def start(self):
    # ✅ v2: Spawn tracked background task
    self._worker_task = self._spawn_background_task(
        self._worker_loop(),
        name="worker_loop"
    )
    
    self._heartbeat_task = self._spawn_background_task(
        self._heartbeat_loop(),
        name="heartbeat"
    )
    
    self._set_state(ModuleState.STARTED)
```

### Background Task Pattern

```python
async def _worker_loop(self):
    """Long-running background task"""
    try:
        while True:
            # Do work
            await self._process_batch()
            
            # Sleep
            await asyncio.sleep(1.0)
            
    except asyncio.CancelledError:
        self.logger.info("Worker loop cancelled")
        raise  # Important: re-raise
    except Exception as e:
        self.logger.error(f"Worker error: {e}", exc_info=True)
        self._set_state(ModuleState.FAILED)
        self.metrics.increment("worker_errors_total")
```

### Automatic Cleanup

Background tasks are automatically cancelled on stop:

```python
async def stop(self):
    # ✅ v2: Automatic cleanup of background tasks
    # _cancel_background_tasks() called automatically
    
    self._set_state(ModuleState.STOPPED)
```

**Manual cleanup:**
```python
async def stop(self):
    # Cancel with custom timeout
    await self._cancel_background_tasks(timeout=10.0)
    
    self._set_state(ModuleState.STOPPED)
```

---

## Error Handling

### v2 Improvement: Always Use Exceptions

**v1 (inconsistent):**
```python
# ❌ v1: Mixed return values
async def init(self, context):
    if error:
        return False  # Sometimes
    raise RuntimeError("error")  # Sometimes
```

**v2 (consistent):**
```python
# ✅ v2: Always raise exceptions
async def init(self, context):
    if error:
        raise ValueError("Invalid configuration")
    
    self._set_state(ModuleState.LOADED)
```

### Exception Types

| Exception | When to Use |
|-----------|-------------|
| `ValueError` | Invalid configuration or input |
| `RuntimeError` | General runtime errors |
| `PermissionError` | Authorization failure |
| `ConnectionError` | Failed to connect to dependency |
| `TimeoutError` | Operation timeout |

### Error Handling in Lifecycle

```python
async def init(self, context):
    try:
        config = context["config"]
        
        # Validate config
        self._port = config.get(self.manifest.id, "port", expected_type=int)
        if self._port < 1024:
            raise ValueError(f"Port must be >= 1024, got {self._port}")
        
        self._set_state(ModuleState.LOADED)
        
    except KeyError as e:
        self.logger.error(f"Missing required config: {e}")
        self._last_error = e
        self._set_state(ModuleState.FAILED)
        raise
    except ValueError as e:
        self.logger.error(f"Invalid config: {e}")
        self._last_error = e
        self._set_state(ModuleState.FAILED)
        raise
    except Exception as e:
        self.logger.error(f"Init failed: {e}", exc_info=True)
        self._last_error = e
        self._set_state(ModuleState.FAILED)
        raise
```

---

## Health Checks

### Basic Health Check

```python
async def health(self):
    """Basic health check"""
    return {
        "status": "healthy" if self.is_started else "degraded",
        "ready": self.is_started,  # Can accept work
        "live": True,  # Process responsive
        "details": {}
    }
```

### Advanced Health Check

```python
async def health(self):
    """Advanced health check with metrics"""
    
    # Determine status
    if not self.is_started:
        status = "degraded"
    elif self._error_count > 10:
        status = "unhealthy"
    elif self._error_count > 5:
        status = "degraded"
    else:
        status = "healthy"
    
    return {
        "status": status,
        "ready": self.is_started and self._error_count < 10,
        "live": self._worker_task is not None,
        "details": {
            "uptime_seconds": self.uptime_seconds,
            "requests_total": self._request_count,
            "errors_total": self._error_count,
            "queue_size": len(self._queue),
            "active_connections": self._pool.active if self._pool else 0,
            # v2: Resource usage
            "resource_usage": self._resource_usage
        }
    }
```

### Health Check States

| Status | Description | Action |
|--------|-------------|--------|
| **healthy** | Fully operational | None |
| **degraded** | Operational but impaired | Monitor closely |
| **unhealthy** | Not operational | Restart or repair |

---

## Dependencies

### Hard Dependencies

Required modules that must be loaded first:

```python
@classmethod
def get_manifest(cls):
    return ModuleManifest(
        id="services/api",
        group="services",
        version="1.0.0",
        hard_deps=[
            "database/postgres",  # Must be loaded
            "cache/redis"
        ]
    )
```

**Access dependencies:**
```python
async def load(self, context):
    registry = context["registry"]
    
    # Get dependency instance
    db = registry.get_instance("database/postgres")
    if not db:
        raise RuntimeError("Database dependency not available")
    
    self._db = db
```

### Soft Dependencies

Optional modules:

```python
@classmethod
def get_manifest(cls):
    return ModuleManifest(
        id="services/api",
        group="services",
        version="1.0.0",
        soft_deps=[
            "metrics/prometheus"  # Optional
        ]
    )
```

**Check soft dependencies:**
```python
async def load(self, context):
    registry = context["registry"]
    
    # Optional: Use if available
    metrics = registry.get_instance("metrics/prometheus")
    if metrics:
        self.logger.info("Prometheus integration enabled")
        self._metrics_enabled = True
    else:
        self.logger.warning("Prometheus not available")
        self._metrics_enabled = False
```

---

## Best Practices

### DO ✅

1. **Always use type hints**
   ```python
   async def init(self, context: Dict[str, Any]) -> None:
   ```

2. **Set state explicitly**
   ```python
   self._set_state(ModuleState.LOADED)
   ```

3. **Use structured logging**
   ```python
   self.logger.info("Event", extra={"key": "value"})
   ```

4. **Track operations**
   ```python
   async with self._track_operation("query"):
       await db.query()
   ```

5. **Check permissions**
   ```python
   self._require_permission("admin.action")
   ```

6. **Validate configuration**
   ```python
   if port < 1024:
       raise ValueError("Invalid port")
   ```

7. **Handle CancelledError**
   ```python
   except asyncio.CancelledError:
       logger.info("Cancelled")
       raise  # Re-raise!
   ```

8. **Make unload() idempotent**
   ```python
   if self._resource:
       self._resource.close()
       self._resource = None
   ```

### DON'T ❌

1. **Don't use blocking code**
   ```python
   time.sleep(1)  # ❌ Blocks event loop
   await asyncio.sleep(1)  # ✅ Async
   ```

2. **Don't log secrets**
   ```python
   logger.info(f"Password: {pw}")  # ❌
   logger.info("Password loaded")  # ✅
   ```

3. **Don't return False**
   ```python
   if error:
       return False  # ❌ v1 style
   if error:
       raise RuntimeError("error")  # ✅ v2 style
   ```

4. **Don't forget to re-raise CancelledError**
   ```python
   except asyncio.CancelledError:
       pass  # ❌ Swallows cancellation
   except asyncio.CancelledError:
       raise  # ✅ Propagates
   ```

5. **Don't hardcode paths**
   ```python
   path = "/var/lib/app"  # ❌
   path = config.get(..., "data_dir")  # ✅
   ```

---

## Complete Example

Here's a complete, production-ready module:

```python
from nexus_v2.core import BaseModule, ModuleManifest, ModuleState
from typing import Dict, Any
import asyncio

class DatabaseModule(BaseModule):
    """
    Production database module demonstrating all v2 features
    """
    
    @classmethod
    def get_manifest(cls) -> ModuleManifest:
        return ModuleManifest(
            id="database/postgres",
            group="database",
            version="2.0.0",
            description="PostgreSQL database connection pool",
            required=True,
            provides=["database.connection"],
            hard_deps=[],
            config_keys={
                "host": "localhost",
                "port": 5432,
                "database": "app",
                "pool_size": 10,
                "timeout_ms": 5000
            },
            resources={
                "memory_mb": 100,
                "connections": 10
            },
            # v2: Security
            required_permissions=["database.admin"],
            sensitive=True,
            # v2: Metadata
            author="NEXUS Project",
            license="MIT"
        )
    
    def __init__(self, manifest: ModuleManifest):
        super().__init__(manifest)
        
        # Config
        self._host = None
        self._port = None
        self._database = None
        self._pool_size = None
        self._timeout_ms = None
        
        # State
        self._pool = None
        self._health_task = None
        self._query_count = 0
        self._error_count = 0
    
    async def init(self, context: Dict[str, Any]):
        """Initialize with config and secrets"""
        try:
            config = context["config"]
            
            # v2: Structured logging
            self.logger.info(
                "Initializing database module",
                extra={"module_id": self.manifest.id}
            )
            
            # Load config (type-safe)
            self._host = config.get(
                self.manifest.id, "host",
                default="localhost", expected_type=str
            )
            self._port = config.get(
                self.manifest.id, "port",
                default=5432, expected_type=int
            )
            self._database = config.get(
                self.manifest.id, "database",
                expected_type=str  # Required
            )
            self._pool_size = config.get(
                self.manifest.id, "pool_size",
                default=10, expected_type=int
            )
            self._timeout_ms = config.get(
                self.manifest.id, "timeout_ms",
                default=5000, expected_type=int
            )
            
            # v2: Get secret from Vault
            self._password = config.get(
                self.manifest.id, "password",
                secret=True
            )
            
            # Validate
            if self._port < 1 or self._port > 65535:
                raise ValueError(f"Invalid port: {self._port}")
            if self._pool_size < 1:
                raise ValueError(f"Invalid pool_size: {self._pool_size}")
            
            # v2: Restore state
            if 'persisted_state' in context:
                state = context['persisted_state']
                self._query_count = state.get('query_count', 0)
                self.logger.info(
                    f"Restored state: {self._query_count} queries",
                    extra={"query_count": self._query_count}
                )
            
            self.logger.info(
                "Configuration loaded",
                extra={
                    "host": self._host,
                    "port": self._port,
                    "database": self._database,
                    "pool_size": self._pool_size
                }
            )
            
            self._set_state(ModuleState.LOADED)
            
        except Exception as e:
            self.logger.error(f"Init failed: {e}", exc_info=True)
            self._last_error = e
            self._set_state(ModuleState.FAILED)
            raise
    
    async def load(self, context: Dict[str, Any]):
        """Create connection pool"""
        try:
            # v2: Track operation
            async with self._track_operation("create_pool"):
                # Simulate pool creation
                await asyncio.sleep(0.1)
                self._pool = {
                    "active": 0,
                    "idle": self._pool_size
                }
            
            self.logger.info("Connection pool created")
            
        except Exception as e:
            self.logger.error(f"Load failed: {e}", exc_info=True)
            self._last_error = e
            self._set_state(ModuleState.FAILED)
            raise
    
    async def start(self):
        """Start database operations"""
        try:
            # v2: Check permission
            self._require_permission("database.admin")
            
            # v2: Track operation
            async with self._track_operation("start"):
                # Start health check loop
                self._health_task = self._spawn_background_task(
                    self._health_check_loop(),
                    name="db_health_check"
                )
            
            self._set_state(ModuleState.STARTED)
            
            # v2: Metrics
            self.metrics.gauge("pool_size", float(self._pool_size))
            
            self.logger.info("Database operations started")
            
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
        """Stop database operations gracefully"""
        try:
            self.logger.info("Stopping database operations...")
            
            # v2: Track operation
            async with self._track_operation("stop"):
                # Cancel background tasks
                await self._cancel_background_tasks(timeout=5.0)
            
            self._set_state(ModuleState.STOPPED)
            
            self.logger.info(
                f"Stopped (processed {self._query_count} queries)",
                extra={"query_count": self._query_count}
            )
            
        except Exception as e:
            self.logger.error(f"Stop failed: {e}", exc_info=True)
            self._last_error = e
            raise
    
    async def unload(self):
        """Close connection pool"""
        try:
            # v2: Idempotent cleanup
            if self._pool:
                await asyncio.sleep(0.05)  # Simulate pool close
                self._pool = None
            
            self._set_state(ModuleState.UNLOADED)
            self.logger.info("Connection pool closed")
            
        except Exception as e:
            self.logger.error(f"Unload failed: {e}", exc_info=True)
            self._last_error = e
            raise
    
    async def health(self) -> Dict[str, Any]:
        """Detailed health check"""
        
        # Determine status
        if not self.is_started:
            status = "degraded"
        elif self._error_count > 10:
            status = "unhealthy"
        elif self._error_count > 5:
            status = "degraded"
        else:
            status = "healthy"
        
        return {
            "status": status,
            "ready": self.is_started and self._error_count < 10,
            "live": self._pool is not None,
            "details": {
                "uptime_seconds": self.uptime_seconds,
                "query_count": self._query_count,
                "error_count": self._error_count,
                "pool": {
                    "active": self._pool["active"] if self._pool else 0,
                    "idle": self._pool["idle"] if self._pool else 0,
                    "size": self._pool_size
                },
                "resource_usage": self._resource_usage
            }
        }
    
    # Public API
    
    async def execute_query(self, query: str):
        """Execute database query"""
        if not self.is_started:
            raise RuntimeError("Database not started")
        
        # v2: Track operation
        async with self._track_operation("execute_query"):
            try:
                # Simulate query execution
                await asyncio.sleep(0.01)
                
                # Update metrics
                self._query_count += 1
                self._resource_usage["requests_total"] += 1
                
                # v2: Metrics
                self.metrics.increment("queries_total")
                self.metrics.gauge("active_queries", float(self._pool["active"]))
                
                return {"rows": []}
                
            except Exception as e:
                self._error_count += 1
                self._resource_usage["errors_total"] += 1
                self.metrics.increment("query_errors_total")
                raise
    
    # Private methods
    
    async def _health_check_loop(self):
        """Periodic health checks"""
        try:
            while True:
                # Update pool metrics
                if self._pool:
                    self.metrics.gauge("pool_active", float(self._pool["active"]))
                    self.metrics.gauge("pool_idle", float(self._pool["idle"]))
                
                await asyncio.sleep(10)
                
        except asyncio.CancelledError:
            self.logger.info("Health check loop cancelled")
            raise
        except Exception as e:
            self.logger.error(f"Health check error: {e}", exc_info=True)
            self._set_state(ModuleState.FAILED)
```

---

## Summary

NEXUS v2 provides:

✅ **Security:** RBAC, Secret Management, Audit Logging  
✅ **Observability:** Structured Logging, Prometheus Metrics, Resource Tracking  
✅ **Resilience:** State Persistence, Consistent Error Handling  
✅ **Architecture:** Clean abstractions, Separation of Concerns  

**Key v2 Improvements:**
- Always use exceptions (not `return False`)
- Use `_require_permission()` for authorization
- Use `_track_operation()` for metrics
- Use `config.get(..., secret=True)` for secrets
- Check `persisted_state` in init()

---

**For more examples, see:**
- [modules/vitals/heartbeat_client.py](modules/vitals/heartbeat_client.py)
- [example_daemon.py](example_daemon.py)
- [NEXUS_V2_FINAL.md](NEXUS_V2_FINAL.md)

**Made with ❤️ and German Engineering**  
**NEXUS Project - 2025**
