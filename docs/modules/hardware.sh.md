![AEON Banner](/.github/assets/aeon_banner_v2_2400x600.png)

# hardware.sh - AEON Hardware Detection Orchestration Module

## 📋 Overview

**File:** `lib/hardware.sh`  
**Type:** Library module (sourced)  
**Version:** 0.1.0  
**Purpose:** Orchestrate parallel hardware profile collection from all discovered devices

**Quick Description:**  
Coordinates the transfer and execution of `hardware.remote.sh` across all devices, collects results, and aggregates into `hw_profiles.json`.

---

## 🎯 Purpose

Collect detailed hardware specifications from every device:
- RAM size
- Storage type and size (NVME, SD, HDD)
- CPU cores
- Network speed
- Cooling (passive/active)
- PoE capability

This data is used by `scoring.py` to assign manager/worker roles.

---

## 🚀 Usage

```bash
source /opt/aeon/lib/hardware.sh

run_hardware_detection \
    "$DATA_DIR/discovered_devices.json" \
    "$DATA_DIR/hw_profiles.json" || exit 1
```

**Input:** `discovered_devices.json` (from discovery phase)  
**Output:** `hw_profiles.json` (hardware profiles)

---

## 🏗️ Architecture

```
run_hardware_detection()
    │
    ├─> load_discovered_devices()
    │     Read discovered_devices.json
    │
    ├─> build_device_array()
    │     Format: "ip:user:password"
    │
    ├─> transfer_detection_script()
    │     Copy hardware.remote.sh → all devices
    │     Uses: parallel_file_transfer()
    │
    ├─> execute_hardware_detection()
    │     Run hardware.remote.sh on all devices
    │     Uses: parallel_exec()
    │
    ├─> collect_hardware_results()
    │     SSH to each device
    │     Collect JSON output
    │     Aggregate into single structure
    │
    ├─> aggregate_profiles()
    │     Validate JSON
    │     Save to hw_profiles.json
    │
    └─> display_hardware_summary()
          Show Pi count, RAM, storage
```

---

## 📚 Key Functions

### **load_discovered_devices(file)**
Load and validate discovered devices JSON.

**Returns:** 0 on success, 1 on failure  
**Sets:** `DISCOVERED_DEVICES_FILE` global variable

---

### **build_device_array(array_ref)**
Build array for parallel execution.

**Format:** `"ip:user:password"`  
**Example:** `"192.168.1.101:pi:raspberry"`

---

### **transfer_detection_script(devices_ref)**
Transfer `hardware.remote.sh` to all devices in parallel.

**Uses:** `parallel_file_transfer()` from parallel.sh  
**Remote Path:** `/tmp/aeon_detect_hardware.sh`

---

### **execute_hardware_detection(devices_ref)**
Execute detection script on all devices in parallel.

**Command:** `bash /tmp/aeon_detect_hardware.sh`  
**Uses:** `parallel_exec()` from parallel.sh

---

### **collect_hardware_results(devices_ref)**
SSH to each device and collect JSON output.

**Method:**
```bash
sshpass -p "$password" ssh "${user}@${ip}" \
    "bash /tmp/aeon_detect_hardware.sh"
```

**Aggregates into:**
```json
{
  "devices": [
    { "ip": "...", "hostname": "...", "ram_gb": 8, ... },
    { "ip": "...", "hostname": "...", "ram_gb": 4, ... }
  ]
}
```

---

### **validate_hardware_profile(profile)**
Validate single profile has required fields.

**Required Fields:**
- ip, hostname, device_type, model
- ram_gb, storage_type, storage_size_gb
- cpu_cores

---

### **aggregate_profiles(json, output_file)**
Save aggregated profiles to file.

**Steps:**
1. Validate JSON structure
2. Pretty-print with `jq`
3. Save to `hw_profiles.json`
4. Validate saved file

---

### **display_hardware_summary(hw_file)**
Display summary of collected hardware.

**Shows:**
- Raspberry Pi count
- LLM Computer count
- Host Computer count
- Total RAM (GB)
- Total Storage (GB)

---

### **run_hardware_detection(input, output)**
Main orchestration function.

**Arguments:**
- `input` - discovered_devices.json path
- `output` - hw_profiles.json path

**Returns:** 0 on success, 1 on failure

---

## 🔗 Dependencies

**Module Dependencies:**
- `lib/common.sh` - Logging, utilities
- `lib/parallel.sh` - Parallel execution

**External Scripts:**
- `remote/hardware.remote.sh` - Runs on devices

**System Commands:**
- `sshpass` - SSH with password
- `ssh` - Remote execution
- `jq` - JSON processing

---

## 📖 Example

```bash
#!/bin/bash

source /opt/aeon/lib/hardware.sh

# Run hardware detection
run_hardware_detection \
    "/opt/aeon/data/discovered_devices.json" \
    "/opt/aeon/data/hw_profiles.json" || exit 1

# Result: hw_profiles.json created
log SUCCESS "Hardware profiles collected"
```

---

## 🔧 Output Format

**hw_profiles.json:**
```json
{
  "devices": [
    {
      "ip": "192.168.1.101",
      "hostname": "pi5-master-01",
      "device_type": "raspberry_pi",
      "model": "Raspberry Pi 5 Model B Rev 1.0",
      "ram_gb": 8,
      "storage_type": "nvme",
      "storage_size_gb": 512,
      "network_speed_mbps": 1000,
      "has_poe": true,
      "has_active_cooling": true,
      "cpu_cores": 4
    }
  ]
}
```

---

## ⚠️ Error Handling

**Script Not Found:**
```
❌ Hardware detection script not found: /opt/aeon/remote/hardware.remote.sh
```
**Recovery:** Ensure bootstrap installed all files

**Transfer Failed:**
```
❌ Failed to transfer detection script to some devices
```
**Recovery:** Check SSH connectivity

**No Results:**
```
⚠️  Failed to collect from 192.168.1.101
```
**Recovery:** SSH manually to debug

---

## 📊 Statistics

```
File: lib/hardware.sh
Lines: 423
Functions: 12
Dependencies: common.sh, parallel.sh
Remote Script: hardware.remote.sh
```

---

**Last Updated:** 2025-12-14  
**AEON Version:** 0.1.0
