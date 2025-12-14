# reboot.sh - AEON Synchronized Reboot Module

## 📋 Overview

**File:** `lib/reboot.sh`  
**Type:** Library module  
**Version:** 0.1.0  
**Purpose:** Coordinate synchronized cluster-wide reboots

**Quick Description:**  
Safely reboots all cluster devices in a controlled sequence, ensuring managers reboot last to maintain cluster quorum.

---

## 🎯 Purpose

**Why Synchronized Reboot?**

After installing Docker and configuring devices, a reboot ensures:
- Kernel updates active
- Docker service starts
- Network changes applied
- Clean state before Swarm setup

**Reboot Order:**
1. Workers first (can lose these safely)
2. Wait for workers to come back up
3. Managers last (maintain quorum until last moment)

---

## 🚀 Usage

```bash
source /opt/aeon/lib/reboot.sh

# Reboot all devices
reboot_cluster \
    "$DATA_DIR/role_assignments.json" || exit 1

# Wait for devices to come back online
wait_for_cluster_online \
    "$DATA_DIR/role_assignments.json" 300 || exit 1
```

---

## 🏗️ Architecture

```
reboot_cluster()
    │
    ├─> Load role assignments
    ├─> Separate managers and workers
    │
    ├─> Phase 1: Reboot workers
    │     └─> parallel_exec workers "sudo reboot"
    │
    ├─> Wait 30 seconds
    │
    └─> Phase 2: Reboot managers (one at a time)
          └─> For each manager: ssh reboot, wait

wait_for_cluster_online()
    │
    ├─> For each device
    │     ├─> Ping until responsive
    │     └─> SSH until accessible
    │
    └─> Return success when all online
```

---

## 📚 Key Functions

### **reboot_cluster(roles_json)**
Reboot all cluster devices in safe order.

**Parameters:**
- `roles_json` - Path to role_assignments.json

**Reboot Sequence:**
1. Workers (parallel)
2. Wait 30s
3. Managers (sequential, one at a time)

**Timeout:** 300 seconds (5 minutes)

---

### **wait_for_cluster_online(roles_json, timeout)**
Wait for all devices to come back online.

**Parameters:**
- `roles_json` - Role assignments
- `timeout` - Max wait time (default: 300s)

**Checks:**
- Ping response
- SSH accessibility

**Progress:**
```
Waiting for devices to come online...
[192.168.1.101] ✅ Online (45s)
[192.168.1.102] ✅ Online (52s)
[192.168.1.103] ⏳ Waiting...
```

---

### **reboot_device(ip, user, password)**
Reboot single device.

**Uses:** `sudo reboot` via SSH

---

## 📊 Statistics

```
File: lib/reboot.sh
Lines: ~600
Functions: 6
Typical Duration: 2-3 minutes
```

---

**Last Updated:** 2025-12-14
