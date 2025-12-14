# discovery.sh - AEON Network Discovery Module

## 📋 Overview

**File:** `lib/discovery.sh`  
**Type:** Library module (can be sourced or executed standalone)  
**Version:** 0.1.0  
**Purpose:** Discover devices on the network that can join the AEON cluster

**Quick Description:**  
Scans the network for devices, tests SSH connectivity, detects device types (Raspberry Pi, LLM Computer, Host Computer), and generates `discovered_devices.json` with all accessible devices.

---

## 🎯 Purpose & Discovery Methods

### **Why This Module Exists**

Before AEON can create a cluster, it needs to know:
- What devices are on the network?
- Which devices are accessible via SSH?
- What type of device is each one?
- What credentials work for each device?

### **Discovery Methods**

1. **Network Scanning**
   - nmap (preferred, fast)
   - Ping sweep (fallback, slower)

2. **SSH Connectivity Testing**
   - Tests common credentials
   - Supports custom credentials
   - Parallel connection testing

3. **Device Type Detection**
   - Raspberry Pi (via /proc/device-tree/model)
   - LLM Computer (via hostname pattern)
   - Host Computer (fallback)

4. **Validation**
   - Ensures minimum 3 Raspberry Pis
   - Checks SSH accessibility

---

## 🚀 Usage

### **Mode 1: Interactive (Wizard)**

```bash
# Run as standalone script
bash lib/discovery.sh interactive

# Or specify output file
bash lib/discovery.sh interactive /custom/path/devices.json
```

**Interactive wizard prompts for:**
- Network range (default: 192.168.1.0/24)
- SSH username (default: pi)
- SSH password

---

### **Mode 2: Automated (Non-Interactive)**

```bash
# Fully automated discovery
bash lib/discovery.sh automated \
    192.168.1.0/24 \
    pi \
    raspberry \
    /opt/aeon/data/discovered_devices.json
```

**Arguments:**
1. Network range (CIDR notation)
2. SSH username
3. SSH password
4. Output file (optional, default: /opt/aeon/data/discovered_devices.json)

---

### **Mode 3: Sourced (Called by aeon-go.sh)**

```bash
#!/bin/bash

source /opt/aeon/lib/discovery.sh

# Run automated discovery
automated_discovery \
    "192.168.1.0/24" \
    "pi" \
    "raspberry" \
    "/opt/aeon/data/discovered_devices.json" || exit 1

log SUCCESS "Discovery complete"
```

---

## 🏗️ Architecture

### **Execution Flow**

```
Discovery Process
    │
    ├─> 1. Network Scanning
    │      ├─> check_scan_tools()
    │      │     Check for nmap, fallback to ping
    │      │
    │      └─> discover_network_devices()
    │            ├─> scan_network_nmap() [if nmap available]
    │            └─> scan_network_ping() [fallback]
    │              Result: DISCOVERED_IPS[]
    │
    ├─> 2. SSH Testing
    │      └─> test_ssh_accessibility()
    │            ├─> For each IP in DISCOVERED_IPS[]
    │            │     ├─> find_ssh_credentials()
    │            │     │     ├─> Try custom credentials
    │            │     │     └─> Try common defaults
    │            │     └─> test_ssh_connection()
    │            │
    │            Result: ACCESSIBLE_DEVICES[]
    │
    ├─> 3. Device Classification
    │      └─> classify_devices()
    │            ├─> For each accessible device
    │            │     └─> detect_device_type()
    │            │           ├─> Check /proc/device-tree/model → Pi
    │            │           ├─> Check hostname pattern → LLM
    │            │           └─> Default → Host
    │            │
    │            └─> count_raspberry_pis()
    │                  Validate ≥3 Pis
    │
    └─> 4. Save Results
           └─> save_discovered_devices()
                 Generate discovered_devices.json
```

---

## 📚 Configuration

```bash
# Timeouts
DISCOVERY_TIMEOUT=300      # Max discovery time (5 min)
PING_TIMEOUT=1             # Ping timeout per host
SSH_TIMEOUT=5              # SSH connection timeout
SSH_RETRIES=2              # SSH retry attempts
PARALLEL_SCAN_JOBS=50      # Parallel ping jobs

# Default SSH users to try
DEFAULT_SSH_USERS=(
    "pi"         # Raspberry Pi default
    "ubuntu"     # Ubuntu default
    "aeon"       # AEON custom user
    "aeon-llm"   # LLM computer
    "aeon-host"  # Host computer
)

# Common passwords to try
common_passwords=(
    "raspberry"  # Pi default
    "ubuntu"     # Ubuntu default
    "aeon"       # AEON custom
    "pi"         # Alternative
)
```

---

## 📚 Key Functions

### **Network Scanning**

#### **check_scan_tools()**
Check which network scanning tool is available.

**Returns:**
- Sets `SCAN_METHOD` to "nmap" or "ping"

**Priority:**
1. nmap (preferred - fast)
2. ping sweep (fallback - slower)

---

#### **scan_network_nmap(network_range)**
Fast network scan using nmap.

**Parameters:**
- `network_range` - CIDR notation (e.g., 192.168.1.0/24)

**Returns:**
- List of alive IPs (stdout)

**Method:**
```bash
nmap -sn -T4 192.168.1.0/24 -oG - | \
    grep "Status: Up" | \
    awk '{print $2}'
```

**Excludes:** Entry device's own IP

**Speed:** ~10-30 seconds for /24 network

---

#### **scan_network_ping(network_range)**
Ping sweep fallback (when nmap unavailable).

**Parameters:**
- `network_range` - CIDR notation

**Returns:**
- List of alive IPs (stdout)

**Method:**
```bash
# Parallel ping of all .1 to .254
for i in 1..254; do
    ping -c 1 -W 1 192.168.1.$i &
done
```

**Parallel Jobs:** 50 simultaneous pings  
**Speed:** ~30-60 seconds for /24 network

**Note:** Only supports /24 networks currently

---

#### **discover_network_devices(network_range)**
Main network discovery function.

**Parameters:**
- `network_range` - CIDR notation (default: 192.168.1.0/24)

**Returns:**
- 0 if devices found
- 1 if no devices found

**Side Effects:**
- Populates `DISCOVERED_IPS[]` global array
- Logs discovered IPs

**Example Output:**
```
▶ Network Discovery
ℹ️  Network range: 192.168.1.0/24
✅ nmap found - will use for network scanning
ℹ️  Scanning network with nmap: 192.168.1.0/24
✅ Found 12 device(s) on network
ℹ️    • 192.168.1.101
ℹ️    • 192.168.1.102
...
```

---

### **SSH Connectivity**

#### **test_ssh_connection(ip, user, password)**
Test SSH connection to a single device.

**Parameters:**
- `ip` - Device IP address
- `user` - SSH username
- `password` - SSH password

**Returns:**
- 0 if connection succeeds
- 1 if connection fails

**Method:**
```bash
sshpass -p "$password" ssh \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=5 \
    "${user}@${ip}" "exit 0"
```

**Timeout:** 5 seconds

---

#### **find_ssh_credentials(ip, custom_user, custom_password)**
Find working SSH credentials for a device.

**Parameters:**
- `ip` - Device IP
- `custom_user` - Custom username (optional)
- `custom_password` - Custom password (optional)

**Returns:**
- "user:password" string if successful
- Empty + exit 1 if no credentials work

**Process:**
1. Try custom credentials (if provided)
2. Try all combinations of:
   - DEFAULT_SSH_USERS × common_passwords

**Example:**
```bash
# Returns: "pi:raspberry"
credentials=$(find_ssh_credentials "192.168.1.101" "" "")
```

---

#### **test_ssh_accessibility(user, password)**
Test SSH access to all discovered devices.

**Parameters:**
- `user` - Default SSH username (optional)
- `password` - Default SSH password (optional)

**Returns:**
- 0 if at least one device accessible
- 1 if no devices accessible

**Side Effects:**
- Populates `ACCESSIBLE_DEVICES[]` array
- Format: "ip:user:password"

**Progress Display:**
```
Testing [3/12] 192.168.1.103...
```

**Result:**
```
✅ [192.168.1.101] SSH accessible (pi)
✅ [192.168.1.102] SSH accessible (pi)
⚠️  [192.168.1.103] SSH not accessible
...
✅ SSH access confirmed for 10/12 device(s)
```

---

### **Device Classification**

#### **detect_device_type(ip, user, password)**
Detect what type of device this is.

**Parameters:**
- `ip` - Device IP
- `user` - SSH username
- `password` - SSH password

**Returns:**
- "raspberry_pi" - Raspberry Pi detected
- "llm_computer" - LLM computer (hostname contains "llm")
- "host_computer" - Default/unknown

**Detection Logic:**
```bash
# Check if Raspberry Pi
if ssh "cat /proc/device-tree/model" | grep -i "raspberry"; then
    echo "raspberry_pi"
    
# Check hostname for "llm"
elif ssh "hostname" | grep -i "llm"; then
    echo "llm_computer"
    
# Default
else
    echo "host_computer"
fi
```

---

#### **classify_devices()**
Classify all accessible devices and validate minimum requirements.

**Returns:**
- 0 if valid cluster (≥3 Raspberry Pis)
- 1 if insufficient Pis

**Process:**
1. Detect device type for each accessible device
2. Count Raspberry Pis
3. Validate ≥3 Pis (for manager quorum)

**Output:**
```
▶ Device Classification

ℹ️  Classifying 10 device(s)...

  [192.168.1.101] Raspberry Pi
  [192.168.1.102] Raspberry Pi
  [192.168.1.103] Raspberry Pi
  [192.168.1.104] LLM Computer
  [192.168.1.105] Host Computer
  ...

✅ Found 5 Raspberry Pi(s)
✅ Found 2 LLM Computer(s)
✅ Found 3 Host Computer(s)
✅ Minimum requirements met (5 Raspberry Pis)
```

---

#### **count_raspberry_pis()**
Count and validate Raspberry Pis in ACCESSIBLE_DEVICES.

**Returns:**
- 0 if ≥3 Pis
- 1 if <3 Pis

**Why 3 Minimum:**
Docker Swarm needs ODD number of managers (3, 5, or 7) for Raft consensus. Minimum viable cluster = 3 managers = 3 Pis.

---

### **Save Results**

#### **save_discovered_devices(output_file)**
Generate and save discovered_devices.json.

**Parameters:**
- `output_file` - Path to save JSON

**Returns:**
- 0 on success
- 1 on failure

**Output Format:**
```json
{
  "discovery_time": "2025-12-14T15:30:45Z",
  "network_range": "192.168.1.0/24",
  "total_discovered": 12,
  "total_accessible": 10,
  "devices": [
    {
      "ip": "192.168.1.101",
      "hostname": "pi5-master-01",
      "device_type": "raspberry_pi",
      "ssh_user": "pi",
      "ssh_password": "raspberry"
    },
    {
      "ip": "192.168.1.104",
      "hostname": "llm-beast",
      "device_type": "llm_computer",
      "ssh_user": "aeon-llm",
      "ssh_password": "aeon"
    }
  ]
}
```

**Security Note:** Passwords stored in plain text - ensure file permissions are restrictive (600).

---

### **Orchestration**

#### **interactive_discovery(output_file)**
Interactive wizard for discovery.

**Parameters:**
- `output_file` - Output path (default: /opt/aeon/data/discovered_devices.json)

**Returns:**
- 0 on success
- 1 on failure

**Prompts:**
1. Network range (CIDR)
2. Default SSH username
3. Default SSH password

**Full Flow:**
```
AEON Network Discovery
═══════════════════════════════════════

ℹ️  This wizard will discover devices on your network.

Network Configuration
Enter network range (CIDR) [192.168.1.0/24]: 

SSH Credentials
Enter default SSH credentials (will try common defaults if left blank)
Default SSH user [pi]: 
Default SSH password: 

[... discovery process ...]

Discovery Complete
═══════════════════════════════════════

✅ Discovery Summary:
ℹ️    • Total devices found: 10
ℹ️    • Raspberry Pis: 5
ℹ️    • LLM Computers: 2
ℹ️    • Host Computers: 3
ℹ️    • Results: /opt/aeon/data/discovered_devices.json

✅ Ready to proceed with cluster setup
```

---

#### **automated_discovery(network_range, ssh_user, ssh_password, output_file)**
Non-interactive discovery for automation.

**Parameters:**
- `network_range` - CIDR notation
- `ssh_user` - SSH username
- `ssh_password` - SSH password
- `output_file` - Output path

**Returns:**
- 0 on success
- 1 on failure

**Use Case:** Called by aeon-go.sh for automated setup

**Example:**
```bash
automated_discovery \
    "192.168.1.0/24" \
    "pi" \
    "raspberry" \
    "/opt/aeon/data/discovered_devices.json"
```

---

## 🔗 Dependencies

### **External Commands**

**Required:**
- `bash` (≥4.0)
- `sshpass` - SSH with password
- `ssh` - Remote shell
- `jq` - JSON processing
- `hostname` - Get local IP
- `sort` - Sort IPs
- `awk`, `cut`, `grep` - Text processing

**Optional (for faster scanning):**
- `nmap` - Network scanner (highly recommended)

**If nmap missing:**
- `ping` - Fallback network scan

### **Module Dependencies**

**None** - This module is self-contained (includes own logging)

**Why:** Discovery may run before common.sh is available

---

## 🔌 Integration

### **Called By**

```
aeon-go.sh (Phase 2)
    ↓
automated_discovery()
```

### **Calls**

```
discovery.sh
    ├─> nmap (optional)
    ├─> ping (fallback)
    ├─> sshpass + ssh (required)
    └─> jq (required)
```

---

## 📖 Examples

### **Example 1: Interactive Discovery**

```bash
# Run wizard
sudo bash lib/discovery.sh interactive

# Custom output location
sudo bash lib/discovery.sh interactive /tmp/my-devices.json
```

---

### **Example 2: Automated Discovery**

```bash
# With defaults
sudo bash lib/discovery.sh automated \
    192.168.1.0/24 \
    pi \
    raspberry

# Custom output
sudo bash lib/discovery.sh automated \
    10.0.0.0/24 \
    ubuntu \
    ubuntu123 \
    /custom/path/devices.json
```

---

### **Example 3: Sourced by Script**

```bash
#!/bin/bash

source /opt/aeon/lib/discovery.sh

# Automated discovery
automated_discovery \
    "192.168.1.0/24" \
    "pi" \
    "raspberry" \
    "/opt/aeon/data/discovered_devices.json" || {
    echo "Discovery failed!"
    exit 1
}

# Process results
device_count=$(jq '.devices | length' /opt/aeon/data/discovered_devices.json)
echo "Found $device_count devices"
```

---

## ⚠️ Error Scenarios

### **No Devices Found**

```
❌ No devices found on network 192.168.1.0/24
```

**Causes:**
- Wrong network range
- Devices not powered on
- Firewall blocking ping/SSH

**Solutions:**
```bash
# Check your IP and network
ip addr show

# Manually ping a known device
ping 192.168.1.100

# Check nmap is working
nmap -sn 192.168.1.0/24
```

---

### **No SSH Access**

```
⚠️  [192.168.1.101] SSH not accessible
⚠️  [192.168.1.102] SSH not accessible
...
❌ No devices have SSH access
```

**Causes:**
- SSH not enabled
- Wrong credentials
- Firewall blocking port 22

**Solutions:**
```bash
# Enable SSH on Raspberry Pi
# Via raspi-config:
sudo raspi-config
# Interface Options → SSH → Enable

# Test SSH manually
ssh pi@192.168.1.101

# Check if SSH is running
ssh pi@192.168.1.101 "systemctl status ssh"
```

---

### **Insufficient Raspberry Pis**

```
❌ Minimum 3 Raspberry Pis required (found 2)
ℹ️  AEON requires at least 3 Raspberry Pis for manager quorum
```

**Solution:** Add more Raspberry Pis to the network

---

### **nmap Not Found**

```
⚠️  nmap not found - will use ping sweep (slower)
ℹ️  Install nmap for faster scanning: sudo apt install nmap
```

**Not an error** - Discovery continues with ping sweep

**To fix:**
```bash
sudo apt-get update
sudo apt-get install nmap
```

---

## 🔧 Output File Structure

**discovered_devices.json:**

```json
{
  "discovery_time": "2025-12-14T15:30:45Z",
  "network_range": "192.168.1.0/24",
  "total_discovered": 12,
  "total_accessible": 10,
  "devices": [
    {
      "ip": "192.168.1.101",
      "hostname": "pi5-master-01",
      "device_type": "raspberry_pi",
      "ssh_user": "pi",
      "ssh_password": "raspberry"
    },
    {
      "ip": "192.168.1.102",
      "hostname": "pi5-master-02",
      "device_type": "raspberry_pi",
      "ssh_user": "pi",
      "ssh_password": "raspberry"
    },
    {
      "ip": "192.168.1.104",
      "hostname": "llm-beast",
      "device_type": "llm_computer",
      "ssh_user": "aeon-llm",
      "ssh_password": "aeon"
    }
  ]
}
```

**Used By:**
- `hardware.sh` - Load devices for hardware detection
- `validation.sh` - Validate cluster requirements
- `user.sh` - Create aeon user on all devices
- `dependencies.remote.sh` - Install dependencies

---

## 📊 Performance

**Typical Times:**

```
Network Scan (nmap):     10-30 seconds
Network Scan (ping):     30-60 seconds
SSH Testing (10 devices): 20-30 seconds
Device Classification:    10-20 seconds
JSON Generation:          1-2 seconds

Total (nmap):            ~1-2 minutes
Total (ping):            ~2-3 minutes
```

**Parallel Processing:**
- Ping sweep: 50 parallel jobs
- SSH testing: Sequential (to avoid overwhelming devices)

---

## 📊 Statistics

```
File: lib/discovery.sh
Lines: 613
Functions: 14
Configuration: 8 constants
Dependencies: sshpass, ssh, jq, nmap (optional)
```

---

## 🎯 Design Principles

1. **Dual Mode** - Interactive wizard + automated
2. **Fallback** - nmap preferred, ping as fallback
3. **Credential Discovery** - Try common defaults
4. **Validation** - Ensure minimum requirements
5. **Security** - Store credentials (warning about plaintext)

---

**Last Updated:** 2025-12-14  
**AEON Version:** 0.1.0
