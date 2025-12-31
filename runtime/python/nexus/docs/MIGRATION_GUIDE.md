# NEXUS v2 → v2 Enterprise - Migration Guide

## 🎯 Overview

This guide shows you how to upgrade from **NEXUS v2 Basic (Level 14.5)** to **NEXUS v2 Enterprise (Level 18-25)**.

**Key Point:** Migration is **non-breaking**. All existing code continues to work.

---

## 📋 What Changes?

### Files to Replace

| Old File | New File | Changes |
|----------|----------|---------|
| `core/loader.py` | `core/loader.py` | ✅ Added: Auto-detection of state stores |
| `core/module.py` | `core/module.py` | ✅ Added: Enterprise features (optional) |
| `daemon.py` | `daemon.py` | ✅ Added: Cluster support (optional) |

### Files to Add (NEW)

| File | Purpose |
|------|---------|
| `aeon_interface/status.py` | AEON status integration |
| `aeon_interface/live.py` | AEON liveness probes |
| `aeon_interface/command.py` | AEON command interface |
| `aeon_interface/__init__.py` | AEON interface exports |

### Files Unchanged

✅ These files need **NO changes**:
- `core/config.py`
- `core/resolver.py`
- `core/__init__.py`
- `__init__.py`
- `modules/*` (all existing modules)
- `requirements.txt`

---

## 🚀 Migration Steps

### Step 1: Backup Current Installation

```bash
cd /aeon/runtime/python
cp -r nexus nexus_v2_backup_$(date +%Y%m%d)
```

### Step 2: Replace Files

```bash
cd /aeon/runtime/python/nexus

# Replace core files (enterprise features)
cp /path/to/upgrade/core/loader.py core/
cp /path/to/upgrade/core/module.py core/
cp /path/to/upgrade/daemon.py .

# Add AEON interface
mkdir -p aeon_interface
cp /path/to/upgrade/aeon_interface/* aeon_interface/
```

### Step 3: Install AEON Interface

```bash
# Create AEON interface symlinks
mkdir -p /aeon/interfaces/python/nexus
cd /aeon/interfaces/python/nexus

ln -s /aeon/runtime/python/nexus/aeon_interface/status.py status.py
ln -s /aeon/runtime/python/nexus/aeon_interface/live.py live.py
ln -s /aeon/runtime/python/nexus/aeon_interface/command.py command.py
ln -s /aeon/runtime/python/nexus/aeon_interface/__init__.py __init__.py
```

### Step 4: Test Basic Functionality

```bash
cd /aeon/runtime/python/nexus
python -m pytest tests/  # If you have tests
python example_daemon.py  # Should work unchanged
```

### Step 5: (Optional) Enable Enterprise Features

```bash
# Install enterprise packages (as needed)
pip install nexus-v2-redis-state      # Distributed state
pip install nexus-v2-cluster           # HA clustering
pip install nexus-v2-tracing           # Distributed tracing
pip install nexus-v2-multitenancy      # Multi-tenancy
# etc.
```

---

## 🔄 What Happens After Migration?

### Without Enterprise Packages

Your NEXUS runs **exactly as before** (Level 14.5):
- ✅ File-based state
- ✅ Single instance
- ✅ All modules work
- ✅ No breaking changes

**Output:**
```
NEXUS v2 Universal Daemon - Initializing
Capability Level: LEVEL-14.5-BASIC
Using file-based state store (Level 14.5)
Running modules...
```

### With Enterprise Packages

Features **activate automatically**:

```bash
# After: pip install nexus-v2-redis-state nexus-v2-cluster
NEXUS v2 Universal Daemon - Initializing
Capability Level: LEVEL-18-ENTERPRISE
✅ Using Redis state store (Level 18+)
✅ Cluster management available (Level 18-20)
✅ Load balancing available (Level 18-20)
🎖️  LEADER MODE - Managing cluster
Running modules...
```

---

## 📁 File Tree Comparison

### Before (v2 Basic)

```
/aeon/runtime/python/nexus/
├── core/
│   ├── __init__.py
│   ├── config.py
│   ├── loader.py      ← Will be replaced
│   ├── module.py      ← Will be replaced
│   └── resolver.py
├── modules/
│   └── vitals/
│       ├── __init__.py
│       └── heartbeat_client.py
├── __init__.py
├── daemon.py          ← Will be replaced
├── example_daemon.py
└── requirements.txt
```

### After (v2 Enterprise)

```
/aeon/runtime/python/nexus/
├── core/
│   ├── __init__.py
│   ├── config.py
│   ├── loader.py      ✅ UPDATED (auto-detection)
│   ├── module.py      ✅ UPDATED (enterprise features)
│   └── resolver.py
├── modules/
│   ├── vitals/
│   │   ├── __init__.py
│   │   └── heartbeat_client.py
│   ├── mesh/          ✅ NEW (empty, ready for modules)
│   ├── cortex/        ✅ NEW
│   ├── autonomic/     ✅ NEW
│   └── substrate/     ✅ NEW
├── aeon_interface/    ✅ NEW
│   ├── __init__.py
│   ├── status.py
│   ├── live.py
│   └── command.py
├── __init__.py
├── daemon.py          ✅ UPDATED (cluster support)
├── example_daemon.py
└── requirements.txt

/aeon/interfaces/python/nexus/  ✅ NEW
├── __init__.py -> /aeon/runtime/python/nexus/aeon_interface/__init__.py
├── status.py -> /aeon/runtime/python/nexus/aeon_interface/status.py
├── live.py -> /aeon/runtime/python/nexus/aeon_interface/live.py
└── command.py -> /aeon/runtime/python/nexus/aeon_interface/command.py
```

---

## 🧪 Testing After Migration

### Test 1: Basic Functionality

```bash
cd /aeon/runtime/python/nexus
python example_daemon.py
```

**Expected:** Daemon starts normally, no errors.

### Test 2: AEON Interface

```bash
# Test status
python /aeon/interfaces/python/nexus/status.py

# Test liveness
python /aeon/interfaces/python/nexus/live.py liveness

# Test readiness
python /aeon/interfaces/python/nexus/live.py readiness
```

**Expected:** JSON output with status information.

### Test 3: Enterprise Features (if installed)

```bash
# Check detected level
python -c "
from nexus_v2_enterprise import UniversalDaemon
import asyncio

async def test():
    daemon = UniversalDaemon()
    await daemon.initialize()
    print(f'Level: {daemon._detected_level}')

asyncio.run(test())
"
```

**Expected:** Shows detected level (14.5, 18, 20, etc.)

---

## 🔧 Rollback (if needed)

If anything goes wrong:

```bash
cd /aeon/runtime/python
rm -rf nexus
mv nexus_v2_backup_YYYYMMDD nexus
```

Your system is back to the previous state.

---

## ❓ FAQ

**Q: Will my existing modules break?**  
A: No. All existing modules continue to work unchanged.

**Q: Do I need to install enterprise packages?**  
A: No. They're optional. NEXUS works fine without them.

**Q: Can I install enterprise features gradually?**  
A: Yes! Install one package at a time as needed.

**Q: What if I don't want clustering?**  
A: Don't install `nexus-v2-cluster`. NEXUS runs single-instance.

**Q: Can I mix Basic and Enterprise modules?**  
A: Yes! All module categories work together.

**Q: How do I know which level I'm running?**  
A: Check the startup log or use AEON status interface.

---

## 📞 Support

If you encounter issues:

1. Check logs: `journalctl -u nexus -f`
2. Verify file permissions: `ls -la /aeon/runtime/python/nexus`
3. Test AEON interface: `python /aeon/interfaces/python/nexus/live.py`
4. Rollback if needed (see above)

---

**Migration Time: ~10 minutes**  
**Downtime Required: ~30 seconds (daemon restart)**  
**Risk Level: Low (non-breaking changes)**

**Made with ❤️ and German Engineering**
