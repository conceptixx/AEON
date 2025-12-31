![Banner](/.github/assets/aeon_banner_v2_2400x600.png)

# AEON-NEXUS - Universal Daemon v2.0.0 - Enterprise Edition - Interface Specification

## 📡 Overview

The AEON Interface provides programmatic access to NEXUS for the AEON orchestration layer.

**Location:** `/aeon/interfaces/python/nexus/`

**Purpose:**
- Query NEXUS status from AEON
- Perform liveness/readiness checks
- Execute commands on NEXUS daemon

---

## 🔌 Interface Components

### 1. Status Interface (`status.py`)

**Purpose:** Read-only status information

**Functions:**

```python
from aeon.interfaces.python.nexus import get_status

# Get full daemon status
status = await get_status()

# Get specific module status
status = await get_status("vitals/heartbeat-client")
```

**Response Format:**
```json
{
  "running": true,
  "level": "level-20-enterprise",
  "uptime_seconds": 3600.5,
  "security": {
    "principal": "admin@company.com",
    "roles": ["admin"]
  },
  "features": {
    "cluster": true,
    "tracing": true,
    "compliance": false
  },
  "modules": {
    "total_discovered": 15,
    "total_loaded": 15,
    "by_state": {
      "started": 14,
      "stopped": 1
    }
  },
  "health": {
    "statistics": {
      "total": 15,
      "healthy": 14,
      "degraded": 1,
      "unhealthy": 0
    }
  }
}
```

---

### 2. Liveness Probe (`live.py`)

**Purpose:** Health checks for AEON monitoring

**Functions:**

```python
from aeon.interfaces.python.nexus import check_liveness, check_readiness

# Liveness: Is daemon alive?
result = await check_liveness()

# Readiness: Can daemon accept work?
result = await check_readiness()
```

**Liveness Response:**
```json
{
  "live": true,
  "timestamp": 1735689600.123,
  "daemon_running": true
}
```

**Readiness Response:**
```json
{
  "ready": true,
  "timestamp": 1735689600.456,
  "details": {
    "total_modules": 15,
    "healthy_modules": 14,
    "unhealthy_modules": 0,
    "health_ratio": 0.93
  }
}
```

**CLI Usage:**
```bash
# Liveness check
python /aeon/interfaces/python/nexus/live.py liveness
echo $?  # 0 = alive, 1 = dead

# Readiness check
python /aeon/interfaces/python/nexus/live.py readiness
echo $?  # 0 = ready, 1 = not ready

# Critical modules only
python /aeon/interfaces/python/nexus/live.py critical
```

---

### 3. Command Interface (`command.py`)

**Purpose:** Execute operations on NEXUS

**Supported Commands:**

| Command | Parameters | Description |
|---------|------------|-------------|
| `reload_module` | `module_id`, `strategy` | Hot-reload a module |
| `start_module` | `module_id` | Start a stopped module |
| `stop_module` | `module_id` | Stop a running module |
| `get_status` | `module_id` (optional) | Get status |
| `get_metrics` | `module_id` (optional) | Export Prometheus metrics |
| `trigger_chaos` | `experiment`, params | Run chaos experiment |
| `scale_module` | `module_id`, `replicas` | Scale module instances |
| `configure` | `module_id`, `key`, `value` | Runtime config change |

**Function Usage:**
```python
from aeon.interfaces.python.nexus import execute_command

# Reload a module
result = await execute_command("reload_module", {
    "module_id": "vitals/heartbeat-client",
    "strategy": "graceful"
})

# Get metrics
result = await execute_command("get_metrics", {
    "module_id": "vitals/heartbeat-client"
})

# Configure at runtime
result = await execute_command("configure", {
    "module_id": "vitals/heartbeat-client",
    "key": "interval_ms",
    "value": 5000
})
```

**CLI Usage:**
```bash
# Reload module
python /aeon/interfaces/python/nexus/command.py reload_module \
  '{"module_id": "vitals/heartbeat-client"}'

# Get metrics
python /aeon/interfaces/python/nexus/command.py get_metrics \
  '{"module_id": "vitals/heartbeat-client"}'
```

**Response Format:**
```json
{
  "success": true,
  "result": {
    "module_id": "vitals/heartbeat-client",
    "reloaded": true,
    "strategy": "graceful"
  }
}
```

---

## 🔗 Integration with AEON

### Setup

1. **Ensure NEXUS is installed:**
   ```bash
   ls -la /aeon/runtime/python/nexus
   ```

2. **Create AEON interface symlinks:**
   ```bash
   mkdir -p /aeon/interfaces/python/nexus
   cd /aeon/interfaces/python/nexus
   
   ln -s /aeon/runtime/python/nexus/aeon_interface/status.py status.py
   ln -s /aeon/runtime/python/nexus/aeon_interface/live.py live.py
   ln -s /aeon/runtime/python/nexus/aeon_interface/command.py command.py
   ln -s /aeon/runtime/python/nexus/aeon_interface/__init__.py __init__.py
   ```

3. **Initialize interfaces in NEXUS startup:**
   ```python
   from nexus_v2_enterprise import UniversalDaemon
   from aeon.interfaces.python.nexus import init_interfaces
   
   daemon = UniversalDaemon()
   await daemon.initialize()
   
   # Initialize AEON interface
   init_interfaces(daemon)
   
   await daemon.discover_and_load_modules(...)
   await daemon.start()
   await daemon.run()
   ```

---

## 📊 Monitoring Integration

### Kubernetes Probes

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nexus-daemon
spec:
  containers:
  - name: nexus
    image: nexus:latest
    
    livenessProbe:
      exec:
        command:
        - python
        - /aeon/interfaces/python/nexus/live.py
        - liveness
      initialDelaySeconds: 10
      periodSeconds: 30
    
    readinessProbe:
      exec:
        command:
        - python
        - /aeon/interfaces/python/nexus/live.py
        - readiness
      initialDelaySeconds: 5
      periodSeconds: 10
```

### Prometheus Scraping

```yaml
scrape_configs:
  - job_name: 'nexus'
    static_configs:
      - targets: ['nexus:9090']
    metrics_path: '/metrics'
```

**Get metrics via interface:**
```bash
python /aeon/interfaces/python/nexus/command.py get_metrics > /tmp/metrics.txt
```

---

## 🔒 Security

### RBAC Integration

The command interface respects NEXUS security contexts:

```python
from nexus_v2_enterprise import SecurityContext

# Define security context for AEON
aeon_security = SecurityContext(
    principal="aeon-orchestrator",
    roles=["aeon", "operator"],
    permissions=[
        "module.reload",
        "module.start",
        "module.stop",
        "module.configure",
        "chaos.trigger",
    ]
)

daemon = UniversalDaemon(security_context=aeon_security)
```

**Permission Checks:**
- Commands are validated against security context
- Operations fail with `PermissionError` if unauthorized
- Audit log tracks all command executions

---

## 🎯 Example: AEON Orchestration Script

```python
#!/usr/bin/env python3
"""
AEON Orchestration Script
Monitors NEXUS and takes automated actions
"""

import asyncio
import sys
sys.path.insert(0, "/aeon/interfaces/python")

from nexus import get_status, check_readiness, execute_command


async def monitor_and_orchestrate():
    """Monitor NEXUS and take actions"""
    
    while True:
        # Check readiness
        ready = await check_readiness()
        
        if not ready.get("ready"):
            # Not ready - investigate
            status = await get_status()
            
            unhealthy_ratio = status["health"]["statistics"]["unhealthy"] / \
                            status["health"]["statistics"]["total"]
            
            if unhealthy_ratio > 0.2:  # More than 20% unhealthy
                print("⚠️  High unhealthy ratio, triggering healing...")
                
                # Execute healing command
                result = await execute_command("trigger_healing", {})
                
                if result["success"]:
                    print("✓ Healing triggered successfully")
                else:
                    print(f"✗ Healing failed: {result.get('error')}")
        
        else:
            print("✓ NEXUS healthy")
        
        # Wait before next check
        await asyncio.sleep(60)


if __name__ == "__main__":
    asyncio.run(monitor_and_orchestrate())
```

---

## 📚 API Reference

### Status Interface

```python
class StatusInterface:
    async def get_status() -> Dict[str, Any]
    async def get_module_status(module_id: str) -> Dict[str, Any]
    def get_capability_level() -> str
    def get_features() -> Dict[str, bool]
```

### Liveness Probe

```python
class LivenessProbe:
    async def check_liveness() -> Dict[str, Any]
    async def check_readiness() -> Dict[str, Any]
    async def check_critical_modules() -> Dict[str, Any]
```

### Command Interface

```python
class CommandInterface:
    async def execute_command(
        command_type: str,
        params: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]
```

---

## 🔧 Troubleshooting

### Interface Not Found

```bash
# Check symlinks
ls -la /aeon/interfaces/python/nexus

# Recreate if missing
cd /aeon/interfaces/python/nexus
ln -s /aeon/runtime/python/nexus/aeon_interface/* .
```

### Permission Denied

```bash
# Check permissions
ls -la /aeon/runtime/python/nexus/aeon_interface

# Fix if needed
chmod +x /aeon/runtime/python/nexus/aeon_interface/*.py
```

### Import Error

```python
# Ensure path is correct
import sys
sys.path.insert(0, "/aeon/runtime/python")

from nexus_v2_enterprise import UniversalDaemon
```

---

**Made with ❤️ and German Engineering**
