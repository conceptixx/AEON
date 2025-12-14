![AEON Banner](/.github/assets/aeon_banner_v2_2400x600.png)

# parallel.sh - AEON Parallel Execution Module

## 📋 Overview

**File:** `lib/parallel.sh`  
**Type:** Library module (sourced)  
**Version:** 0.1.0  
**Purpose:** Execute commands on multiple devices simultaneously with progress tracking

**Quick Description:**  
Enables parallel SSH execution across all cluster devices with real-time progress bars, retry logic, error handling, and result aggregation.

---

## 🎯 Purpose

Execute commands on 10+ devices in parallel instead of sequentially:
- **Sequential:** 10 devices × 30 seconds = 5 minutes
- **Parallel:** 10 devices in parallel = ~30 seconds

**Features:**
- ✅ Parallel SSH execution (configurable max jobs)
- ✅ Real-time progress bars per device
- ✅ Automatic retry with backoff
- ✅ Error handling and logging
- ✅ File transfer (SCP) support
- ✅ Result aggregation
- ✅ Duration tracking

---

## 🚀 Usage

### **Basic Workflow**

```bash
source /opt/aeon/lib/parallel.sh

# 1. Initialize
parallel_init || exit 1

# 2. Build device array
devices=(
    "192.168.1.101:pi:raspberry"
    "192.168.1.102:pi:raspberry"
    "192.168.1.103:pi:raspberry"
)

# 3. Execute command in parallel
parallel_exec devices "docker --version" "Checking Docker"

# 4. Transfer files in parallel
parallel_file_transfer devices \
    "/local/script.sh" \
    "/remote/script.sh"

# 5. Cleanup
parallel_cleanup
```

---

## 🏗️ Architecture

```
parallel_init()
    Create temp directory for job tracking
    Check dependencies (sshpass, ssh, scp, bc)
    
parallel_exec(devices[], command, description)
    │
    ├─> For each device (up to PARALLEL_MAX_JOBS at once)
    │     └─> parallel_ssh_exec(ip, user, pass, command) &
    │           ├─> Retry up to 3 times
    │           ├─> Track status (running/success/failed)
    │           └─> Log to job directory
    │
    ├─> parallel_monitor_jobs()
    │     ├─> Update progress bars every 0.5s
    │     ├─> Show per-device status
    │     ├─> Calculate ETA
    │     └─> Display overall progress
    │
    └─> Wait for all jobs to complete

parallel_cleanup()
    Remove temp directory
```

---

## 📚 Configuration

```bash
# Global settings (can be overridden)
PARALLEL_MAX_JOBS=10          # Max concurrent SSH connections
PARALLEL_SSH_TIMEOUT=30       # SSH timeout per command (seconds)
PARALLEL_RETRY_COUNT=3        # Retry attempts
PARALLEL_RETRY_DELAY=5        # Delay between retries (seconds)
```

**Override example:**
```bash
PARALLEL_MAX_JOBS=20 parallel_exec devices "uptime"
```

---

## 📚 Key Functions

### **parallel_init()**
Initialize parallel execution framework.

**Returns:** 0 on success, 1 on failure  
**Creates:** Temp directory `/tmp/aeon-parallel-XXXXXX`

**Checks dependencies:**
- sshpass
- ssh
- scp
- bc

**Auto-installs missing dependencies if possible**

---

### **parallel_exec(devices_ref, command, description)**
Execute command on all devices in parallel.

**Parameters:**
- `devices_ref` - Array name (by reference)
- `command` - Command to execute
- `description` - Display text (e.g., "Installing Docker")

**Device Array Format:**
```bash
devices=("ip:user:password" ...)
```

**Returns:** 0 (always waits for all jobs)

**Example:**
```bash
devices=(
    "192.168.1.101:pi:raspberry"
    "192.168.1.102:pi:raspberry"
)

parallel_exec devices \
    "sudo apt-get update" \
    "Updating package lists"
```

**Progress Output:**
```
Updating package lists

192.168.1.101   [████████████████████] Complete (12s)
192.168.1.102   [████████████████████] Complete (15s)

Overall: [████████████████████] [2/2] | Elapsed: 15s | ETA: 0s

✅ All parallel executions complete
```

---

### **parallel_file_transfer(devices_ref, local_path, remote_path)**
Transfer file to all devices in parallel.

**Parameters:**
- `devices_ref` - Array name
- `local_path` - Local file path
- `remote_path` - Remote destination path

**Example:**
```bash
parallel_file_transfer devices \
    "/opt/aeon/scripts/install.sh" \
    "/tmp/install.sh"
```

**Uses SCP with:**
- StrictHostKeyChecking=no
- Automatic retry
- Progress tracking

---

### **parallel_collect_results()**
Collect results from all executed jobs.

**Returns:** JSON array of results (stdout)

**Format:**
```json
[
  {
    "ip": "192.168.1.101",
    "status": "success",
    "exit_code": 0,
    "duration": 12,
    "output": "stdout content"
  },
  {
    "ip": "192.168.1.102",
    "status": "failed",
    "exit_code": 1,
    "duration": 5,
    "error": "connection timeout"
  }
]
```

**Example:**
```bash
results=$(parallel_collect_results)
success_count=$(echo "$results" | jq '[.[] | select(.status=="success")] | length')
echo "Successful: $success_count"
```

---

### **parallel_cleanup()**
Clean up temp directory and job files.

**Returns:** Always 0

**Removes:** `/tmp/aeon-parallel-XXXXXX`

**Always call this at the end:**
```bash
trap parallel_cleanup EXIT
```

---

### **parallel_monitor_jobs(devices...)**
Real-time progress monitoring (called internally).

**Features:**
- Live updating progress bars
- Per-device status
- Duration tracking
- ETA calculation
- Overall progress

**Display:**
```
192.168.1.101   [████████░░░░░░░░░░░░] Running... (8s)
192.168.1.102   [████████████████████] Complete (12s)
192.168.1.103   [░░░░░░░░░░░░░░░░░░░░] Waiting...

Overall: [█████████░░░░░░░░░░░] [1/3] | Elapsed: 12s | ETA: 24s
```

---

### **Helper Functions**

#### **parallel_create_progress_bar(current, total, width)**
Generate ASCII progress bar.

```bash
bar=$(parallel_create_progress_bar 7 10 20)
echo "$bar"  # [██████████████░░░░░░]
```

---

#### **parallel_format_duration(seconds)**
Format seconds as human-readable.

```bash
parallel_format_duration 125   # "2m 5s"
parallel_format_duration 3665  # "1h 1m 5s"
```

---

## 🔗 Dependencies

**Required Commands:**
- `sshpass` - SSH with password
- `ssh` - Remote execution
- `scp` - File transfer
- `bc` - Calculations

**Optional:**
- `jq` - Result parsing

**Module Dependencies:**
- None (self-contained)

---

## 📖 Examples

### **Example 1: Update All Devices**

```bash
source /opt/aeon/lib/parallel.sh

parallel_init

devices=(
    "192.168.1.101:pi:raspberry"
    "192.168.1.102:pi:raspberry"
    "192.168.1.103:pi:raspberry"
)

parallel_exec devices \
    "sudo apt-get update && sudo apt-get upgrade -y" \
    "Updating all devices"

parallel_cleanup
```

---

### **Example 2: Install Docker**

```bash
parallel_exec devices \
    "curl -fsSL https://get.docker.com | sh" \
    "Installing Docker"
```

---

### **Example 3: Transfer and Execute Script**

```bash
# Transfer script
parallel_file_transfer devices \
    "/opt/aeon/remote/setup.sh" \
    "/tmp/setup.sh"

# Make executable and run
parallel_exec devices \
    "chmod +x /tmp/setup.sh && /tmp/setup.sh" \
    "Running setup script"
```

---

### **Example 4: Collect Results**

```bash
parallel_exec devices "hostname" "Getting hostnames"

results=$(parallel_collect_results)

echo "$results" | jq -r '.[] | "\(.ip): \(.output)"'
```

---

## ⚠️ Error Handling

### **Automatic Retry**

Failed commands retry up to 3 times with 5-second backoff:

```
⚠️  [192.168.1.101] Attempt 1 failed (exit: 1), retrying in 5s...
⚠️  [192.168.1.101] Attempt 2 failed (exit: 1), retrying in 5s...
❌ [192.168.1.101] All attempts failed (exit: 1)
```

---

### **Max Jobs Limit**

Prevents overwhelming network/devices:

```bash
# Max 10 concurrent (default)
PARALLEL_MAX_JOBS=10

# Increase for faster execution
PARALLEL_MAX_JOBS=20 parallel_exec ...
```

---

### **SSH Timeout**

Prevents hanging on unreachable devices:

```bash
# 30 second timeout (default)
PARALLEL_SSH_TIMEOUT=30

# Increase for slow operations
PARALLEL_SSH_TIMEOUT=120 parallel_exec ...
```

---

## 📊 Performance

**Comparison:**

| Devices | Sequential | Parallel (10 jobs) | Speedup |
|---------|------------|-------------------|---------|
| 3       | 90s        | 30s               | 3x      |
| 10      | 300s       | 30s               | 10x     |
| 20      | 600s       | 60s               | 10x     |

**Optimal Settings:**
- Small clusters (3-5): MAX_JOBS=5
- Medium clusters (6-15): MAX_JOBS=10
- Large clusters (16+): MAX_JOBS=15-20

---

## 🎯 Integration

**Used By:**
- hardware.sh - Hardware detection
- dependencies.remote.sh - Package installation
- user.sh - User creation
- reboot.sh - Synchronized reboot

**Pattern:**
```bash
source /opt/aeon/lib/parallel.sh

parallel_init
# ... operations ...
parallel_cleanup
```

---

## 📊 Statistics

```
File: lib/parallel.sh
Lines: 715
Functions: 15+
Max Concurrent: 10 (configurable)
Retry Logic: Yes (3 attempts)
Progress Display: Real-time
```

---

**Last Updated:** 2025-12-14  
**AEON Version:** 0.1.0
