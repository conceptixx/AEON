# 📘 AEON Parallel Execution Module - Complete Documentation

## 📋 Overview

The **Parallel Execution Module** (`lib/parallel.sh`) is a comprehensive Bash library for executing commands on multiple remote devices simultaneously. It provides real-time progress tracking, error handling, retry logic, and result aggregation.

---

## 🎯 Key Features

### ✅ **Core Capabilities**
- Execute commands on multiple devices in parallel
- Transfer files to multiple devices simultaneously
- Wait for devices to come online (post-reboot scenarios)
- Real-time progress visualization with dynamic progress bars
- Automatic retry on failures (configurable)
- Comprehensive result aggregation (JSON output)
- Intelligent error handling and logging

### ✅ **Production-Ready**
- Dependency auto-installation
- Graceful timeout handling
- Process cleanup on exit
- Detailed logging
- Archive logs for debugging
- Terminal width detection for responsive UI

---

## 📦 Installation

### **1. Copy Module to AEON Directory**
```bash
sudo mkdir -p /opt/aeon/lib
sudo cp parallel.sh /opt/aeon/lib/
```

### **2. Verify Installation**
```bash
source /opt/aeon/lib/parallel.sh
type parallel_init  # Should output function definition
```

### **3. Dependencies**
The module will auto-install missing dependencies:
- `sshpass` - Password-based SSH authentication
- `ssh` - Remote command execution
- `scp` - File transfer
- `bc` - Calculations
- `jq` - JSON parsing (optional, for enhanced output)

---

## 🚀 Quick Start

### **Basic Usage Example**

```bash
#!/bin/bash

# 1. Source the module
source /opt/aeon/lib/parallel.sh

# 2. Initialize parallel execution
parallel_init

# 3. Define devices (format: ip:user:password)
devices=(
    "192.168.1.100:pi:raspberry"
    "192.168.1.101:pi:raspberry"
    "192.168.1.102:pi:raspberry"
    "192.168.1.103:aeon-llm:password123"
)

# 4. Execute command on all devices in parallel
parallel_exec devices[@] \
    "apt-get update && apt-get upgrade -y" \
    "Updating system packages"

# 5. Collect results
results=$(parallel_collect_results)

# 6. Parse results
success_rate=$(echo "$results" | jq -r '.success_rate')

if (( $(echo "$success_rate >= 95" | bc -l) )); then
    echo "✅ Installation successful ($success_rate% success rate)"
else
    echo "❌ Installation failed on some devices ($success_rate% success rate)"
fi

# 7. Cleanup
parallel_cleanup
```

---

## 📚 Function Reference

### **1. `parallel_init()`**

**Purpose:** Initialize the parallel execution environment

**Usage:**
```bash
parallel_init
```

**What it does:**
- Checks and installs missing dependencies
- Creates temporary job tracking directory
- Sets up logging infrastructure
- Initializes cleanup trap

**Returns:**
- `0` on success
- `1` on failure

**Example:**
```bash
source /opt/aeon/lib/parallel.sh
parallel_init || {
    echo "Failed to initialize parallel execution"
    exit 1
}
```

---

### **2. `parallel_exec(devices_array, command, description)`**

**Purpose:** Execute a command on multiple devices in parallel

**Parameters:**
- `devices_array` - Array reference containing device specs (ip:user:password)
- `command` - Command string to execute on each device
- `description` - Human-readable description for progress display

**Usage:**
```bash
devices=("192.168.1.100:pi:pass" "192.168.1.101:pi:pass")

parallel_exec devices[@] \
    "uname -a" \
    "Getting system information"
```

**What it does:**
- Spawns SSH connections to all devices in background
- Displays real-time progress with progress bars
- Tracks job status (running, success, failed)
- Handles failures with automatic retries
- Records output and errors per device

**Output Example:**
```
Getting system information

192.168.1.100 ████████████████████████ 100% Complete (12s)
192.168.1.101 ████████████████░░░░░░░░  75% Running... (8s)
192.168.1.102 ████████████████████████ 100% Complete (10s)

Overall: [███████████████████░░░░░] [2/3] | Elapsed: 12s | ETA: 4s
```

---

### **3. `parallel_file_transfer(devices_array, local_file, remote_path)`**

**Purpose:** Copy a file to multiple devices in parallel

**Parameters:**
- `devices_array` - Array reference containing device specs
- `local_file` - Path to local file to transfer
- `remote_path` - Destination path on remote devices

**Usage:**
```bash
devices=("192.168.1.100:pi:pass" "192.168.1.101:pi:pass")

parallel_file_transfer devices[@] \
    "/opt/aeon/scripts/install.sh" \
    "/tmp/install.sh"
```

**What it does:**
- Uses `scp` to copy file to all devices simultaneously
- Shows transfer progress per device
- Verifies successful transfer
- Continues even if some transfers fail

---

### **4. `parallel_wait_online(devices_array, timeout)`**

**Purpose:** Wait for devices to come back online (post-reboot)

**Parameters:**
- `devices_array` - Array reference containing device specs
- `timeout` - Maximum wait time in seconds (default: 300)

**Usage:**
```bash
devices=("192.168.1.100:pi:pass" "192.168.1.101:pi:pass")

# Wait up to 5 minutes for devices to come online
parallel_wait_online devices[@] 300
```

**What it does:**
- Continuously polls devices via SSH
- Updates status in real-time
- Shows elapsed time and ETA
- Returns success when all devices online
- Returns failure if timeout exceeded

**Output Example:**
```
Waiting for devices to come back online (timeout: 5m)

✓ 192.168.1.100 - Online (18s)
⏳ 192.168.1.101 - Waiting... (42s)
✓ 192.168.1.102 - Online (25s)

[2/3] devices online | Elapsed: 42s | Timeout in: 4m 18s
```

---

### **5. `parallel_collect_results()`**

**Purpose:** Aggregate results from all parallel jobs into JSON

**Usage:**
```bash
results=$(parallel_collect_results)
echo "$results" | jq '.'
```

**Returns:** JSON object with structure:
```json
{
  "timestamp": "2025-12-13T15:30:42Z",
  "total_devices": 4,
  "successful": 3,
  "failed": 1,
  "success_rate": 75.0,
  "devices": [
    {
      "ip": "192.168.1.100",
      "status": "success",
      "duration_seconds": 127,
      "exit_code": 0,
      "output": "Command output here...",
      "error": ""
    },
    {
      "ip": "192.168.1.101",
      "status": "failed",
      "duration_seconds": 180,
      "exit_code": 255,
      "output": "",
      "error": "Connection timeout"
    }
  ]
}
```

**What it does:**
- Collects output from all devices
- Aggregates timing information
- Calculates success statistics
- Generates formatted summary
- Saves to JSON file

---

### **6. `parallel_cleanup()`**

**Purpose:** Clean up parallel execution artifacts

**Usage:**
```bash
parallel_cleanup
```

**What it does:**
- Kills any lingering SSH processes
- Archives logs to `/opt/aeon/logs/parallel_TIMESTAMP/`
- Removes temporary job directory
- Releases all resources

**Note:** Automatically called on script exit via trap

---

## ⚙️ Configuration

### **Environment Variables**

Configure module behavior via environment variables:

```bash
# Maximum parallel jobs (default: 10)
export PARALLEL_MAX_JOBS=20

# SSH connection timeout in seconds (default: 30)
export PARALLEL_SSH_TIMEOUT=60

# Number of retries on failure (default: 3)
export PARALLEL_RETRY_COUNT=5

# Delay between retries in seconds (default: 5)
export PARALLEL_RETRY_DELAY=10

# Enable debug output (default: 0)
export DEBUG=1
```

**Example:**
```bash
# Configure before sourcing module
export PARALLEL_MAX_JOBS=15
export PARALLEL_SSH_TIMEOUT=45
export DEBUG=1

source /opt/aeon/lib/parallel.sh
parallel_init
```

---

## 🎨 Progress Bar Customization

The module automatically detects terminal width and adapts progress bars. You can also customize:

```bash
# In your script, before calling parallel_exec
export TERM=xterm-256color  # Enable colors
```

---

## 🔍 Debugging

### **Enable Debug Mode**

```bash
export DEBUG=1
source /opt/aeon/lib/parallel.sh
```

**Output:**
```
🔍 Parallel execution module loaded (version 0.1.0)
🔍 [192.168.1.100] Attempt 1/3
🔍 [192.168.1.100] Command succeeded
```

### **View Logs**

Logs are stored in the temporary job directory:

```bash
# Main log
cat ${PARALLEL_JOB_DIR}/parallel.log

# Per-device output
cat ${PARALLEL_JOB_DIR}/results/192.168.1.100.out

# Per-device errors
cat ${PARALLEL_JOB_DIR}/errors/192.168.1.100.err
```

After cleanup, logs are archived:

```bash
ls -la /opt/aeon/logs/parallel_*/
```

---

## 📊 Advanced Usage Examples

### **Example 1: Staged Deployment**

```bash
#!/bin/bash
source /opt/aeon/lib/parallel.sh
parallel_init

# Define device groups
managers=("192.168.1.100:pi:pass" "192.168.1.101:pi:pass")
workers=("192.168.1.102:pi:pass" "192.168.1.103:pi:pass")

# Stage 1: Update managers first
parallel_exec managers[@] \
    "apt-get update && apt-get upgrade -y" \
    "Updating managers"

# Stage 2: Update workers
parallel_exec workers[@] \
    "apt-get update && apt-get upgrade -y" \
    "Updating workers"

parallel_cleanup
```

---

### **Example 2: Conditional Execution Based on Results**

```bash
#!/bin/bash
source /opt/aeon/lib/parallel.sh
parallel_init

devices=("192.168.1.100:pi:pass" "192.168.1.101:pi:pass")

# Check Docker installation
parallel_exec devices[@] \
    "docker --version" \
    "Checking Docker"

results=$(parallel_collect_results)

# Parse which devices don't have Docker
devices_needing_docker=$(echo "$results" | jq -r '.devices[] | select(.status != "success") | .ip')

if [[ -n "$devices_needing_docker" ]]; then
    echo "Installing Docker on devices: $devices_needing_docker"
    
    # Create new device array for devices needing Docker
    # ... (construct array from IPs)
    
    parallel_exec devices_to_install[@] \
        "curl -fsSL https://get.docker.com | sh" \
        "Installing Docker"
fi

parallel_cleanup
```

---

### **Example 3: File Distribution + Execution**

```bash
#!/bin/bash
source /opt/aeon/lib/parallel.sh
parallel_init

devices=("192.168.1.100:pi:pass" "192.168.1.101:pi:pass")

# Step 1: Transfer script
parallel_file_transfer devices[@] \
    "/opt/aeon/scripts/setup.sh" \
    "/tmp/setup.sh"

# Step 2: Make executable
parallel_exec devices[@] \
    "chmod +x /tmp/setup.sh" \
    "Setting permissions"

# Step 3: Execute script
parallel_exec devices[@] \
    "/tmp/setup.sh --verbose" \
    "Running setup script"

# Step 4: Collect results
results=$(parallel_collect_results)

parallel_cleanup
```

---

### **Example 4: Synchronized Reboot**

```bash
#!/bin/bash
source /opt/aeon/lib/parallel.sh
parallel_init

devices=("192.168.1.100:pi:pass" "192.168.1.101:pi:pass")

# Reboot all devices
parallel_exec devices[@] \
    "sudo reboot" \
    "Rebooting devices"

# Wait for them to come back (5 minute timeout)
echo "Waiting for devices to reboot..."
sleep 30  # Give them time to actually go down

parallel_wait_online devices[@] 300

echo "All devices back online!"

parallel_cleanup
```

---

## 🛠️ Troubleshooting

### **Issue: "sshpass not found"**

**Solution:**
```bash
sudo apt-get update
sudo apt-get install -y sshpass
```

The module will attempt to auto-install, but may need manual intervention.

---

### **Issue: "Connection timeout"**

**Causes:**
- Device is offline
- Firewall blocking SSH (port 22)
- Wrong credentials
- Network issues

**Debug:**
```bash
# Test SSH manually
ssh pi@192.168.1.100 "echo ok"

# Check if device is reachable
ping 192.168.1.100

# Verify SSH service
nmap -p 22 192.168.1.100
```

---

### **Issue: Progress bars look corrupted**

**Solution:**
```bash
# Ensure proper terminal
export TERM=xterm-256color

# Or disable colors
export NO_COLOR=1
```

---

### **Issue: Some devices fail randomly**

**Increase retry count:**
```bash
export PARALLEL_RETRY_COUNT=5
export PARALLEL_RETRY_DELAY=10
```

---

## 📈 Performance Considerations

### **Optimal Parallel Job Count**

- **Default: 10** - Good for most scenarios
- **Low-end systems:** 5 - Reduces load
- **High-end systems:** 20+ - Maximize throughput
- **Network-bound:** 50+ - If network is the bottleneck

```bash
export PARALLEL_MAX_JOBS=20
```

---

### **Memory Usage**

Each parallel job requires:
- ~5MB for SSH process
- ~1MB for output buffering

**Example:** 20 parallel jobs = ~120MB RAM

---

## 🔒 Security Considerations

### **Password Handling**

- Passwords stored in memory only
- Not written to disk (except in job tracking during execution)
- Cleared on cleanup
- Use SSH keys for production (recommended)

### **SSH Key-Based Authentication (Recommended)**

```bash
# Set up SSH keys first
ssh-copy-id pi@192.168.1.100

# Then use without password
devices=("192.168.1.100:pi:" "192.168.1.101:pi:")

parallel_exec devices[@] "uname -a" "Test"
```

---

## 🎯 Integration with AEON Bootstrap

### **In aeon-go.sh:**

```bash
# Source parallel module
source /opt/aeon/lib/parallel.sh

# Initialize
parallel_init

# Load discovered devices
devices=($(cat $DATA_DIR/discovered_devices.json | jq -r '.[] | "\(.ip):\(.user):\(env.CLUSTER_PASSWORD)"'))

# Install dependencies on all devices
parallel_file_transfer devices[@] \
    "/opt/aeon/remote/install_dependencies.sh" \
    "/tmp/install_dependencies.sh"

parallel_exec devices[@] \
    "bash /tmp/install_dependencies.sh" \
    "Installing AEON dependencies"

# Collect results
results=$(parallel_collect_results)

# Check success rate
success_rate=$(echo "$results" | jq -r '.success_rate')

if (( $(echo "$success_rate >= 95" | bc -l) )); then
    log SUCCESS "Installation successful on ${success_rate}% of devices"
else
    log ERROR "Installation failed - success rate: ${success_rate}%"
    exit 1
fi

# Cleanup
parallel_cleanup
```

---

## 📝 API Reference Summary

| Function | Purpose | Returns |
|----------|---------|---------|
| `parallel_init()` | Initialize environment | 0=success, 1=failure |
| `parallel_exec(devices, cmd, desc)` | Execute command | 0=success |
| `parallel_file_transfer(devices, local, remote)` | Copy file | 0=success |
| `parallel_wait_online(devices, timeout)` | Wait for devices | 0=all online, 1=timeout |
| `parallel_collect_results()` | Get results JSON | JSON string |
| `parallel_cleanup()` | Clean up resources | void |

---

## 🎉 Module Complete!

The **Parallel Execution Module** is production-ready and provides:

✅ Robust parallel execution
✅ Beautiful real-time progress
✅ Comprehensive error handling
✅ Result aggregation
✅ Easy integration

**Total Lines of Code:** ~800 lines
**Features:** 6 main functions + 10+ utilities
**Error Handling:** Retry logic, timeouts, graceful failures
**Logging:** Detailed logs + archived history

---

**Next:** Use this module in the Dependency Installer! 🚀
