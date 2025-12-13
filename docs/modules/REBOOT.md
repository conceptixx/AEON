# 🔄 AEON Synchronized Reboot - Complete Documentation

## 📋 Overview

The **Synchronized Reboot Module** (`lib/06-reboot.sh`) orchestrates cluster-wide reboots in a controlled sequence to maintain consensus and prevent split-brain conditions during system reboots.

---

## 🎯 Purpose

### **Why Synchronized Reboot?**

After dependency installation, many devices need to reboot for changes to take effect (kernel updates, Docker configuration, cgroup memory, etc.). Simply rebooting all devices at once can cause:

❌ **Split-brain** - Managers come online at different times  
❌ **Lost quorum** - Not enough managers online for consensus  
❌ **Failed cluster** - Services don't start properly  
❌ **Data inconsistency** - Distributed state corrupted

**Synchronized reboot solves this!**

---

## 🔄 Reboot Sequence

### **3-Stage Sequential Reboot**

```
Stage 1: Workers (Parallel)
   ↓
   Wait for all workers online
   ↓
Stage 2: Managers (Sequential, one at a time)
   ↓
   Wait for each manager online before next
   ↓
Stage 3: Entry Device (LAST!)
   ↓
   Script terminates, device reboots
   ↓
   Resume on next boot
```

---

## 📊 Detailed Stage Breakdown

### **Stage 1: Worker Reboot (Parallel)**

**Who:** All worker nodes (Pi workers, LLM computers, Host computers)

**How:** Parallel reboot (all at once)

**Why parallel?**
- Workers are stateless in control plane
- No quorum requirements
- Faster overall time
- Managers stay online to maintain cluster

**Sequence:**
```
1. Send reboot command to ALL workers (parallel)
2. Wait 30 seconds for shutdown
3. Wait up to 5 minutes for all to come online
4. Verify Docker health on each worker
5. Continue to Stage 2
```

**Timeline:**
```
T+0s:    Send reboot to all workers
T+30s:   Workers shutdown complete
T+90s:   First workers coming online
T+120s:  Most workers online
T+330s:  Timeout if not all online
```

---

### **Stage 2: Manager Reboot (Sequential)**

**Who:** Manager nodes (except entry device)

**How:** Sequential, one at a time

**Why sequential?**
- Maintain quorum during reboot
- Prevent split-brain
- One manager down = cluster still has majority
- Raft consensus requires majority online

**Sequence:**
```
For each manager (except entry):
  1. Send reboot command
  2. Wait 60 seconds for shutdown
  3. Wait up to 5 minutes for online
  4. Verify Docker health
  5. Proceed to next manager
```

**Timeline (3 managers example):**
```
Manager 1:
  T+0s:    Reboot manager 1
  T+60s:   Shutdown complete
  T+150s:  Manager 1 back online
  
Manager 2:
  T+150s:  Reboot manager 2
  T+210s:  Shutdown complete
  T+300s:  Manager 2 back online
  
Total: ~5 minutes for 2 additional managers
```

**Quorum Math:**
```
3 managers total:
  - Minimum quorum: 2
  - Reboot 1 at a time
  - Always have 2+ online ✓

5 managers total:
  - Minimum quorum: 3
  - Reboot 1 at a time
  - Always have 4+ online ✓
```

---

### **Stage 3: Entry Device Reboot (LAST!)**

**Who:** The device running aeon-go.sh

**How:** Simple reboot

**Why last?**
- Maintains orchestration control
- Ensures all others are online first
- Can save checkpoint before reboot
- Script can resume on next boot

**Sequence:**
```
1. Verify all workers + managers online
2. Save checkpoint file
3. Countdown 5 seconds
4. Reboot
5. [Device reboots]
6. [Script resumes on next boot - optional]
```

**Checkpoint File:**
```bash
/opt/aeon/data/.reboot_checkpoint

Contents:
REBOOT_STAGE=complete
REBOOT_TIME=2025-12-13T20:45:00Z
```

---

## 🚀 Usage

### **Basic Usage (from aeon-go.sh)**

```bash
#!/bin/bash

# Source modules
source /opt/aeon/lib/parallel.sh
source /opt/aeon/lib/06-reboot.sh

# Initialize parallel execution
parallel_init

# Check if reboot needed
if check_devices_need_reboot "/opt/aeon/data/installation_results.json"; then
    log INFO "Reboot required, initiating synchronized reboot..."
    
    # Load AEON credentials
    source /opt/aeon/.aeon.env
    
    # Execute synchronized reboot
    synchronized_reboot \
        "/opt/aeon/data/role_assignments.json" \
        "$(hostname -I | awk '{print $1}')" \
        "$AEON_USER" \
        "$AEON_PASSWORD"
else
    log SUCCESS "No reboot required, continuing..."
fi
```

---

### **Function Signature**

```bash
synchronized_reboot <role_assignments> <entry_ip> <user> <password>
```

**Parameters:**
- `role_assignments` - Path to role_assignments.json
- `entry_ip` - IP of entry device (this device)
- `user` - SSH user (typically "aeon")
- `password` - SSH password

---

### **Dry Run (Testing)**

```bash
# Test reboot sequence without actually rebooting
bash /opt/aeon/lib/06-reboot.sh --dry-run \
    /opt/aeon/data/role_assignments.json \
    192.168.1.100
```

**Output:**
```
═══════════════════════════════════════════════════════════
  Synchronized Reboot - DRY RUN
═══════════════════════════════════════════════════════════

ℹ️  This is a DRY RUN - no actual reboots will occur

REBOOT PLAN:

Stage 1: Workers (Parallel)
  • 192.168.1.103
  • 192.168.1.104
  • 192.168.1.200
  Wait: 30s + 300s (online)

Stage 2: Managers (Sequential)
  • 192.168.1.101
    Wait: 60s + 300s (online)
  • 192.168.1.102
    Wait: 60s + 300s (online)

Stage 3: Entry Device
  • 192.168.1.100
  Wait: 90s + 300s (online)

ℹ️  Estimated total reboot time: 24 minutes

✅ Dry run complete - no devices rebooted
```

---

## 📺 Console Output (Real Reboot)

```
═══════════════════════════════════════════════════════════
  Synchronized Cluster Reboot
═══════════════════════════════════════════════════════════

ℹ️  Entry device: 192.168.1.100
ℹ️  Reboot user: aeon

▶ Classifying devices for reboot order...
ℹ️  Worker devices: 3
ℹ️  Manager devices (excluding entry): 2
ℹ️  Entry device: 192.168.1.100

ℹ️  Devices requiring reboot: 6


═══════════════════════════════════════════════════════════
  Stage 1: Rebooting Workers
═══════════════════════════════════════════════════════════

▶ Rebooting worker nodes (3 device(s))...

Rebooting worker nodes

192.168.1.103 ████████████████████████ 100% Complete (15s)
192.168.1.104 ████████████████████████ 100% Complete (12s)
192.168.1.200 ████████████████████████ 100% Complete (14s)

Overall: [███████████████████████] [3/3] 100%

✅ Reboot command sent to 3 device(s)
ℹ️  Waiting 30s for workers to shutdown...
ℹ️  Waiting for workers to come back online...

Waiting for devices to come back online (timeout: 5m)

✓ 192.168.1.103 - Online (42s)
✓ 192.168.1.104 - Online (38s)
✓ 192.168.1.200 - Online (51s)

[3/3] devices online

✅ All devices are back online
▶ Verifying cluster health after reboot...
ℹ️  [192.168.1.103] ✓ Docker running, load: 0.15
ℹ️  [192.168.1.104] ✓ Docker running, load: 0.08
ℹ️  [192.168.1.200] ✓ Docker running, load: 0.42
ℹ️  Health check results: 3 healthy, 0 unhealthy
✅ All devices healthy


═══════════════════════════════════════════════════════════
  Stage 2: Rebooting Managers (Sequential)
═══════════════════════════════════════════════════════════

⚠️  Rebooting managers one at a time to maintain quorum...
ℹ️  Rebooting manager: 192.168.1.101

[Reboot progress for 192.168.1.101...]

✅ Manager 192.168.1.101 is back online
ℹ️  [192.168.1.101] ✓ Docker running, load: 0.12

ℹ️  Rebooting manager: 192.168.1.102

[Reboot progress for 192.168.1.102...]

✅ Manager 192.168.1.102 is back online
ℹ️  [192.168.1.102] ✓ Docker running, load: 0.09

✅ All managers rebooted successfully


═══════════════════════════════════════════════════════════
  Stage 3: Rebooting Entry Device
═══════════════════════════════════════════════════════════

⚠️  Entry device will now reboot
⚠️  You will lose connection to this script
⚠️  The device will come back online automatically

ℹ️  Entry device IP: 192.168.1.100
ℹ️  Expected downtime: ~90s

ℹ️  Checkpoint saved to /opt/aeon/data/.reboot_checkpoint
ℹ️  Initiating entry device reboot in 5 seconds...
Rebooting in 5 seconds... 
Rebooting in 4 seconds... 
Rebooting in 3 seconds... 
Rebooting in 2 seconds... 
Rebooting in 1 seconds... 

⚠️  Rebooting NOW...
Connection to 192.168.1.100 closed by remote host.
```

---

## ⏱️ Timeline Example

### **6-Device Cluster (3 workers, 2 managers + entry)**

```
T+0:00   Stage 1: Reboot 3 workers (parallel)
T+0:30   Workers shutting down
T+1:00   Workers starting to come online
T+2:00   All workers verified online and healthy

T+2:00   Stage 2: Reboot manager 1
T+2:60   Manager 1 shutting down
T+3:30   Manager 1 online and verified

T+3:30   Stage 2: Reboot manager 2
T+4:30   Manager 2 shutting down
T+5:00   Manager 2 online and verified

T+5:00   Stage 3: Reboot entry device
T+5:05   Entry device rebooting
T+6:30   Entry device back online

Total time: ~6.5 minutes
```

---

## 🔒 Safety Features

### **1. Quorum Maintenance**

```bash
# 5 managers total, minimum quorum = 3

Reboot sequence:
  Start: 5 online (5 > 3) ✓
  Manager 1 down: 4 online (4 > 3) ✓
  Manager 1 back: 5 online (5 > 3) ✓
  Manager 2 down: 4 online (4 > 3) ✓
  Manager 2 back: 5 online (5 > 3) ✓
  ...
  
Always maintain quorum!
```

---

### **2. Health Verification**

After each device/group comes online:
```bash
✓ Docker service running
✓ Docker daemon accessible  
✓ System load reasonable
```

If health check fails:
```
⚠️  Device unhealthy, retrying...
[Retry 3 times]

If still fails:
  - Continue with warning (workers)
  - Ask user confirmation (managers)
```

---

### **3. Timeout Protection**

```bash
Default timeouts:
  - Worker online: 300s (5 min)
  - Manager online: 300s (5 min)
  - Entry online: 300s (5 min)

If timeout exceeded:
  - Log error
  - Show which devices failed
  - Allow user to retry or abort
```

---

### **4. User Confirmation (Managers)**

```bash
If manager fails to come online:
  
  ❌ Manager 192.168.1.101 failed to come back online!
  ❌ This may cause cluster issues!
  
  Continue with remaining reboots? [y/N]
  
If user says 'N': Abort entire sequence
If user says 'Y': Continue (at their own risk)
```

---

### **5. Checkpoint Recovery**

```bash
# Before entry device reboots
echo "REBOOT_STAGE=complete" > /opt/aeon/data/.reboot_checkpoint
echo "REBOOT_TIME=$(date -u)" >> /opt/aeon/data/.reboot_checkpoint

# On next boot (optional)
if [[ -f /opt/aeon/data/.reboot_checkpoint ]]; then
    log SUCCESS "Reboot completed successfully"
    # Resume installation from checkpoint
fi
```

---

## 🔧 Configuration

### **Timing Parameters**

```bash
# In 06-reboot.sh or aeon.conf

REBOOT_WORKER_DELAY=30          # Wait after workers reboot (seconds)
REBOOT_MANAGER_DELAY=60         # Wait after managers reboot (seconds)
REBOOT_ENTRY_DELAY=90           # Wait after entry reboot (seconds)
REBOOT_ONLINE_TIMEOUT=300       # Max wait for online (5 minutes)
REBOOT_HEALTH_CHECK_RETRIES=3   # Health check retry count
```

**Adjust based on:**
- Storage speed (SD cards slower than NVMe)
- Network speed (faster network = faster reboot detection)
- Device count (more devices = may need longer timeout)

---

## 🎯 Integration with AEON

### **In aeon-go.sh**

```bash
# After dependency installation
print_header "Phase 7: Synchronized Reboot (if needed)"

# Check if any devices need reboot
if check_devices_need_reboot "$DATA_DIR/installation_results.json"; then
    
    log WARN "Some devices require reboot for changes to take effect"
    
    # Ask user
    read -p "Proceed with synchronized reboot? [Y/n] " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        
        # Load AEON credentials
        source /opt/aeon/.aeon.env
        
        # Execute synchronized reboot
        synchronized_reboot \
            "$DATA_DIR/role_assignments.json" \
            "$(hostname -I | awk '{print $1}')" \
            "$AEON_USER" \
            "$AEON_PASSWORD"
        
        # This point is only reached if script is run again after reboot
        log SUCCESS "Synchronized reboot completed"
        
    else
        log WARN "Reboot skipped by user"
        log WARN "Manual reboot required before cluster will function properly"
    fi
    
else
    log SUCCESS "No devices require reboot"
fi
```

---

## 📊 Performance Metrics

### **Timing Analysis**

| Cluster Size | Workers | Managers | Total Time | Bottleneck |
|--------------|---------|----------|------------|------------|
| 3 Pis | 0 | 2 | ~8 min | Sequential managers |
| 5 Pis | 2 | 2 | ~10 min | Sequential managers |
| 10 Pis | 3 | 6 | ~25 min | Sequential managers |
| 10 Pis + 2 LLM | 5 | 6 | ~25 min | Sequential managers |

**Key insight:** Manager count dominates total time (sequential reboot)

---

### **Optimization Strategies**

**Already optimized:**
- ✅ Workers reboot in parallel (fast)
- ✅ Entry device last (maintains control)
- ✅ Health checks prevent false "online" detection

**Could be faster (but riskier):**
- ❌ Reboot 2 managers at once (risks quorum)
- ❌ Skip health checks (risks unhealthy devices)
- ❌ Shorter timeouts (risks false failures)

**Recommendation:** Current approach is optimal balance of speed vs safety!

---

## ⚠️ Error Handling

### **Error 1: Worker Fails to Come Online**

```
❌ Some workers failed to come back online within 300s

Workers that failed:
  • 192.168.1.104

⚠️  Continuing anyway (workers are not critical for cluster formation)...
```

**Action:** Continue (workers not critical)

---

### **Error 2: Manager Fails to Come Online**

```
❌ Manager 192.168.1.101 failed to come back online!
❌ This may cause cluster issues!

Continue with remaining reboots? [y/N]
```

**Action:** User decides

---

### **Error 3: Lost Quorum During Reboot**

```
❌ CRITICAL: Quorum lost during manager reboot!
❌ Only 1/3 managers online (need 2/3)

ABORT reboot sequence? [Y/n]
```

**Action:** Abort recommended (cluster broken)

---

## 🎯 Best Practices

### **1. Always Use Dry Run First**

```bash
# Test reboot sequence
bash /opt/aeon/lib/06-reboot.sh --dry-run \
    /opt/aeon/data/role_assignments.json \
    192.168.1.100

# Review the plan, then run for real
```

---

### **2. Ensure Stable Power**

Before reboot:
- ✅ All devices plugged in
- ✅ UPS/PoE working
- ✅ No pending power issues

**Why:** Reboot during power issue = disaster

---

### **3. Monitor First Reboot Closely**

```bash
# SSH to another device to monitor
ssh pi@192.168.1.101

# Watch system logs
journalctl -f

# Watch AEON logs
tail -f /opt/aeon/logs/reboot.log
```

---

### **4. Backup Role Assignments**

```bash
# Before reboot
cp /opt/aeon/data/role_assignments.json \
   /opt/aeon/data/role_assignments.json.backup
```

**Why:** If something goes wrong, can retry with same roles

---

## 🎉 Summary

The **Synchronized Reboot Module** provides:

✅ **Safe** - Maintains quorum throughout
✅ **Intelligent** - Workers parallel, managers sequential
✅ **Monitored** - Health checks after each stage
✅ **Recoverable** - Checkpoints and user confirmation
✅ **Fast** - Optimized sequence (workers parallel)
✅ **Production-Ready** - Error handling, timeouts, retries

**Total Lines of Code:** ~600 lines Bash
**Stages:** 3 (Workers → Managers → Entry)
**Safety Features:** 5 layers
**Estimated Time:** 2-25 minutes (depends on cluster size)

---

## 🚀 Next Steps

**This module integrates with:**
1. ✅ **Parallel Execution** - Uses parallel_exec and parallel_wait_online
2. ✅ **Role Assignment** - Uses role_assignments.json
3. ✅ **AEON User** - Uses AEON credentials for SSH
4. ⏳ **Docker Swarm Setup** - Runs after reboot completes

**Ready for production! 🎯**
