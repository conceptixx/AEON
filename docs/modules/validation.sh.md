# validation.sh - AEON Requirements Validation Module

## 📋 Overview

**File:** `lib/validation.sh`  
**Type:** Library module (sourced)  
**Version:** 0.1.0  
**Purpose:** Validate cluster meets minimum requirements before proceeding

**Quick Description:**  
Ensures the cluster has sufficient Raspberry Pis, validates hardware specs, and confirms the cluster is viable for fault-tolerant operation.

---

## 🎯 Purpose

**Validates:**
- ✅ Minimum 3 Raspberry Pis (for 3 managers)
- ✅ Total device count
- ✅ Hardware specifications (RAM, storage, CPU)
- ✅ Cluster size viability
- ✅ Manager capacity (ODD count: 3, 5, or 7)
- ✅ Data completeness

**Critical Check:**  
At least 3 Raspberry Pis are **required** for a fault-tolerant Docker Swarm cluster with Raft consensus.

---

## 🚀 Usage

```bash
source /opt/aeon/lib/validation.sh

# Run all validations
run_validation "$DATA_DIR/hw_profiles.json" || exit 1

# Passed - continue with installation
log SUCCESS "Cluster meets requirements"
```

---

## 🏗️ Architecture

```
run_validation()
    │
    ├─> validate_hardware_file()        [critical]
    │     Check file exists, readable, valid JSON
    │
    ├─> validate_raspberry_pi_count()   [critical]
    │     Minimum 3 Pis required
    │
    ├─> validate_total_device_count()   [critical]
    │     Minimum 3 total devices
    │
    ├─> validate_cluster_size()         [important]
    │     Check fault tolerance possible
    │
    ├─> validate_manager_capacity()     [important]
    │     Ensure ODD manager count (3, 5, 7)
    │
    ├─> validate_required_fields()      [warning]
    │     Check all devices have complete data
    │
    ├─> validate_device_hardware()      [warning]
    │     Check RAM, storage, CPU minimums
    │
    ├─> validate_network_connectivity() [informational]
    │     Note: Full check during swarm setup
    │
    └─> generate_validation_report()
          Show pass/warn/fail counts
```

---

## 📚 Configuration

```bash
# Minimum requirements
readonly MIN_RASPBERRY_PIS=3
readonly MIN_TOTAL_DEVICES=3
readonly MIN_RAM_PER_PI_GB=2
readonly MIN_STORAGE_PER_PI_GB=8
readonly MIN_CPU_CORES=2

# Manager count (must be ODD)
readonly MIN_MANAGERS=3
readonly MAX_MANAGERS=7
```

---

## 📚 Key Functions

### **validate_raspberry_pi_count(hw_file)**
Check minimum Raspberry Pi count.

**Requirement:** ≥3 Raspberry Pis  
**Why:** Need 3 managers for fault tolerance

**Error if < 3:**
```
❌ Insufficient Raspberry Pis: 2 found, minimum 3 required

ℹ️  AEON requires at least 3 Raspberry Pis for a fault-tolerant cluster
ℹ️  Current cluster has: 2 Raspberry Pi(s)

ℹ️  To fix this:
ℹ️    1. Add more Raspberry Pis to your network
ℹ️    2. Ensure they are powered on and accessible
ℹ️    3. Ensure SSH is enabled on all Pis
ℹ️    4. Re-run AEON installation
```

---

### **validate_total_device_count(hw_file)**
Validate total device count.

**Requirement:** ≥3 total devices  
**Counts:** Pis + LLM computers + Host computers

---

### **validate_device_hardware(hw_file)**
Check each device meets minimum specs.

**Checks:**
- RAM ≥ 2GB (warning if less)
- Storage ≥ 8GB (warning if less)
- CPU cores ≥ 2 (warning if less)

**Warnings, not errors** - cluster still functions

---

### **validate_cluster_size(hw_file)**
Check cluster is viable for fault tolerance.

**Calculates:**
- Manager count based on Pi count
- Fault tolerance: `(managers - 1) / 2`

**Example:**
```
✅ Cluster can have 3 managers
✅ Fault tolerance: Can lose 1 manager(s) and maintain quorum
```

**Manager Count Logic:**
- 3-4 Pis → 3 managers
- 5-6 Pis → 5 managers  
- 7+ Pis → 7 managers

---

### **validate_manager_capacity(hw_file)**
Ensure enough Pis for ODD manager count.

**Docker Swarm requires:**
- ODD number of managers (3, 5, 7)
- For Raft consensus algorithm

---

### **validate_required_fields(hw_file)**
Check all devices have complete data.

**Required fields per device:**
- ip, hostname, device_type, model
- ram_gb, storage_type, storage_size_gb
- cpu_cores

**Warns if missing, doesn't fail**

---

### **validate_hardware_file(hw_file)**
Validate file structure.

**Checks:**
1. File exists
2. File is readable
3. Valid JSON
4. Has 'devices' array

---

### **generate_validation_report()**
Display validation summary.

**Shows:**
```
════════════════════════════════════════

ℹ️  Validation Summary:
ℹ️    ✅ Passed: 8
ℹ️    ⚠️  Warnings: 2
ℹ️    ❌ Errors: 0

✅ All critical validations passed
ℹ️  Cluster can proceed with warnings

════════════════════════════════════════
```

---

### **run_validation(hw_file)**
Main orchestration function.

**Returns:**
- 0 if all critical validations pass
- 1 if any critical validation fails

**Critical vs Non-Critical:**
- **Critical** (must pass):
  - Hardware file valid
  - ≥3 Raspberry Pis
  - ≥3 total devices
- **Important** (should pass):
  - Cluster size viable
  - Manager capacity sufficient
- **Warnings** (inform only):
  - Hardware specs below recommended
  - Missing data fields

---

## 🔗 Dependencies

**Module Dependencies:**
- `lib/common.sh` - Logging, utilities

**External Commands:**
- `jq` - JSON querying

---

## 📖 Example

```bash
#!/bin/bash

source /opt/aeon/lib/validation.sh

# Validate hardware profiles
if run_validation "$DATA_DIR/hw_profiles.json"; then
    log SUCCESS "Cluster validated"
else
    log ERROR "Validation failed"
    exit 1
fi
```

---

## ⚠️ Error Scenarios

**Insufficient Pis:**
```
❌ Insufficient Raspberry Pis: 2 found, minimum 3 required
```
**Fix:** Add more Raspberry Pis

**Invalid JSON:**
```
❌ Invalid JSON in hardware profiles file
```
**Fix:** Check file corruption, re-run hardware detection

**Below Spec:**
```
⚠️  Device pi-worker-01 (192.168.1.103) has only 1GB RAM (minimum: 2GB)
⚠️  2 device(s) below recommended specifications
ℹ️  Cluster will still function, but performance may be impacted
```
**Fix:** Optional, cluster still works

---

## 📊 Validation Counters

**Global Variables:**
```bash
VALIDATION_PASSED=0    # Incremented for each pass
VALIDATION_WARNINGS=0  # Incremented for each warning
VALIDATION_ERRORS=0    # Incremented for each error
```

**Used by report to show summary**

---

## 📊 Statistics

```
File: lib/validation.sh
Lines: 513
Functions: 13
Critical Checks: 3
Important Checks: 2
Warning Checks: 2
Dependencies: common.sh
```

---

**Last Updated:** 2025-12-14  
**AEON Version:** 0.1.0
