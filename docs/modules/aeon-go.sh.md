![AEON Banner](/.github/assets/aeon_banner_v2_2400x600.png)

# aeon-go.sh - AEON Main Orchestrator

## 📋 Overview

**File:** `aeon-go.sh`  
**Type:** Standalone bash script (main entry point)  
**Version:** 0.1.0  
**Purpose:** Complete end-to-end orchestration of AEON cluster setup

**Quick Description:**  
The main orchestrator that transforms a collection of Raspberry Pis and computers into a fully operational Docker Swarm cluster through 10 automated phases.

---

## 🎯 Purpose & Context

### **Why This Script Exists**

After `bootstrap.sh` installs AEON, users need a way to:
1. Discover all devices on the network
2. Assess their hardware capabilities
3. Intelligently assign roles (managers vs workers)
4. Install all dependencies
5. Configure the cluster
6. Form a Docker Swarm
7. Generate installation reports

This script does ALL of that in one execution.

### **The "One Command" Experience**

```bash
sudo bash aeon-go.sh
```

**Result:** Fully operational Docker Swarm cluster in 20-30 minutes

### **Design Philosophy**

- **Automated** - Minimal user interaction
- **Intelligent** - Makes smart decisions based on hardware
- **Fault-tolerant** - Handles errors gracefully
- **Transparent** - Shows exactly what's happening
- **Modular** - Each phase is independent
- **Resumable** - Can recover from failures

---

## 🚀 Usage

### **Standard Usage**

```bash
cd /opt/aeon
sudo bash aeon-go.sh
```

### **User Interaction Required**

The script will prompt for:

1. **Network range** (default: 192.168.1.0/24)
   ```
   Enter network range [192.168.1.0/24]: 
   ```

2. **SSH credentials** (for device access)
   ```
   Enter default SSH user [pi]: 
   Enter default SSH password: 
   ```

3. **Reboot confirmation** (optional)
   ```
   Proceed with reboot? [y/N]
   ```

### **Exit Codes**

| Code | Meaning |
|------|---------|
| 0 | Success - Cluster created |
| 1 | Error - Installation failed |

---

## 🏗️ Architecture

### **10-Phase Workflow**

```
┌─────────────────────────────────────────────┐
│  Phase 1: Pre-flight Checks                 │
│  ├─ Root verification                       │
│  ├─ Internet connectivity                   │
│  ├─ Disk space                              │
│  ├─ Tool installation                       │
│  └─ Directory creation                      │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│  Phase 2: Network Discovery                 │
│  ├─ Scan network (nmap/ping)                │
│  ├─ Test SSH connectivity                   │
│  ├─ Classify devices (Pi/LLM/Host)          │
│  └─ Output: discovered_devices.json         │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│  Phase 3: Hardware Detection                │
│  ├─ Transfer detect_hardware.sh             │
│  ├─ Execute in parallel                     │
│  ├─ Collect hardware profiles               │
│  └─ Output: hw_profiles.json                │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│  Phase 4: Requirements Validation           │
│  ├─ Check minimum 3 Raspberry Pis           │
│  ├─ Verify cluster requirements             │
│  └─ Validate or exit                        │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│  Phase 5: Role Assignment                   │
│  ├─ Score devices (0-170 points)            │
│  ├─ Assign managers (top-scored Pis, ODD)   │
│  ├─ Assign workers (remaining + LLM/Host)   │
│  └─ Output: role_assignments.json           │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│  Phase 6: Dependency Installation           │
│  ├─ Transfer install_dependencies.sh        │
│  ├─ Execute in parallel                     │
│  ├─ Install Docker, packages                │
│  └─ Output: installation_results.json       │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│  Phase 7: AEON User Setup                   │
│  ├─ Generate secure credentials             │
│  ├─ Create AEON user on all devices         │
│  ├─ Configure limited sudo                  │
│  └─ Output: .aeon.env                       │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│  Phase 8: Synchronized Reboot (if needed)   │
│  ├─ Workers reboot (parallel)               │
│  ├─ Managers reboot (sequential)            │
│  ├─ Entry device reboot (last)              │
│  └─ Verify all online                       │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│  Phase 9: Docker Swarm Setup                │
│  ├─ Initialize on first manager             │
│  ├─ Join managers (sequential, 5s delay)    │
│  ├─ Join workers (parallel)                 │
│  ├─ Create overlay networks                 │
│  └─ Verify cluster health                   │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│  Phase 10: Report Generation                │
│  ├─ Generate terminal report                │
│  ├─ Generate markdown report                │
│  ├─ Generate JSON report                    │
│  └─ Display completion summary              │
└─────────────────────────────────────────────┘
```

### **Data Flow**

```
discovered_devices.json
    ↓
hw_profiles.json
    ↓
role_assignments.json
    ↓
installation_results.json
    ↓
.aeon.env
    ↓
swarm_status.json
    ↓
reports/aeon-report-TIMESTAMP.{md,json}
```

---

## 📚 Functions Reference (API)

### **Configuration Functions**

#### **print_banner()**

**Purpose:** Display AEON ASCII art logo and version information

**Type:** Display function  
**Parameters:** None  
**Returns:** None  
**Side Effects:** Clears screen, prints banner  

**Output:**
```
     █████╗ ███████╗ ██████╗ ███╗   ██╗
    ██╔══██╗██╔════╝██╔═══██╗████╗  ██║
    ███████║█████╗  ██║   ██║██╔██╗ ██║
    ██╔══██║██╔══╝  ██║   ██║██║╚██╗██║
    ██║  ██║███████╗╚██████╔╝██║ ╚████║
    ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝

    Autonomous Evolving Orchestration Network
    Distributed AI Infrastructure Platform

════════════════════════════════════════════════════════
  Version: 0.1.0
  Installation Directory: /opt/aeon
════════════════════════════════════════════════════════
```

---

#### **log(level, message)**

**Purpose:** Unified logging with color coding

**Type:** Utility function  
**Parameters:**
- `level` - ERROR, WARN, INFO, SUCCESS, STEP
- `message` - Message text

**Returns:** None  
**Side Effects:** 
- Prints to stdout/stderr
- Logs to `/opt/aeon/logs/aeon-go.log`

**Color Mapping:**
- ERROR → Red ❌ (stderr)
- WARN → Yellow ⚠️
- INFO → Cyan ℹ️
- SUCCESS → Green ✅
- STEP → Bold Blue ▶

**Example:**
```bash
log STEP "Scanning network..."
log SUCCESS "Found 6 devices"
log ERROR "Installation failed"
```

---

#### **print_header(text)**

**Purpose:** Display section headers

**Type:** Display function  
**Parameters:**
- `text` - Header text

**Example Output:**
```
════════════════════════════════════════════════════════
  Phase 2: Network Discovery
════════════════════════════════════════════════════════
```

---

### **Phase 1: Pre-flight Checks**

#### **check_root()**

**Purpose:** Verify script runs as root

**Type:** Validation function  
**Parameters:** None  
**Returns:** None (exits on failure)  
**Exit Code:** 1 if not root

**Checks:**
```bash
if [[ $EUID -ne 0 ]]; then
    exit 1
fi
```

**Required Because:**
- Need to install system packages
- Need to create `/opt/aeon` directories
- Need to modify system configurations

---

#### **check_internet()**

**Purpose:** Verify internet connectivity

**Type:** Validation function  
**Parameters:** None  
**Returns:** 0 on success, 1 on failure

**Method:**
```bash
ping -c 1 -W 3 8.8.8.8
```

**Why 8.8.8.8:**
- Google DNS (highly available)
- IP address (avoids DNS resolution)
- Quick response time

**Required For:**
- Package installation
- Docker installation
- Repository updates

---

#### **check_disk_space()**

**Purpose:** Ensure sufficient disk space

**Type:** Validation function  
**Parameters:** None  
**Returns:** 0 if sufficient, 1 if insufficient

**Requirement:** Minimum 1GB free on `/`

**Check Method:**
```bash
available=$(df / | tail -1 | awk '{print $4}')  # KB
required=$((1024 * 1024))  # 1GB in KB
```

**Why 1GB:**
- Docker images
- System packages
- AEON files
- Log files

---

#### **check_required_tools()**

**Purpose:** Install missing required tools

**Type:** Setup function  
**Parameters:** None  
**Returns:** 0 on success

**Required Tools:**
- `curl` - File downloads
- `wget` - Fallback downloads
- `jq` - JSON parsing
- `git` - Version control
- `sshpass` - SSH automation
- `python3` - Scoring algorithm

**Auto-Install:**
```bash
apt-get update -qq
apt-get install -y -qq "${missing_tools[@]}"
```

---

#### **create_directories()**

**Purpose:** Create AEON directory structure

**Type:** Setup function  
**Parameters:** None  
**Returns:** 0 on success

**Structure Created:**
```
/opt/aeon/
├── lib/           # Module libraries
├── remote/        # Remote execution scripts
├── config/        # Configuration files
├── data/          # Runtime data (JSON)
├── secrets/       # Credentials (chmod 700)
├── logs/          # Log files
└── reports/       # Installation reports
```

**Permissions:**
- Most dirs: `755` (rwxr-xr-x)
- secrets: `700` (rwx------)

---

#### **run_preflight_checks()**

**Purpose:** Orchestrate all pre-flight checks

**Type:** Orchestration function  
**Parameters:** None  
**Returns:** 0 on success, exits on failure

**Calls In Order:**
1. `check_root()`
2. `check_internet()`
3. `check_disk_space()`
4. `check_required_tools()`
5. `create_directories()`

**Exit Policy:** Fails fast on any error

---

### **Phase 2: Network Discovery**

#### **run_discovery_phase()**

**Purpose:** Discover and classify all devices on network

**Type:** Orchestration function  
**Parameters:** None  
**Returns:** 0 on success, 1 on failure

**User Interaction:**
1. Prompts for network range
2. Prompts for SSH user
3. Prompts for SSH password (hidden)

**Calls:**
```bash
source /opt/aeon/lib/02-discovery.sh
run_discovery "$NETWORK_RANGE" "$DEFAULT_USER" "$DEFAULT_PASSWORD" \
    "$DATA_DIR/discovered_devices.json"
```

**Output File:** `discovered_devices.json`
```json
{
  "discovery_time": "2025-12-14T...",
  "network_range": "192.168.1.0/24",
  "total_discovered": 6,
  "total_accessible": 6,
  "devices": [
    {
      "ip": "192.168.1.101",
      "hostname": "pi5-master-01",
      "device_type": "raspberry_pi",
      "model": "Raspberry Pi 5 Model B Rev 1.0",
      "ssh_user": "pi",
      "ssh_password": "raspberry"
    }
  ]
}
```

**Integration:** Sources `lib/02-discovery.sh` module

---

### **Phase 3: Hardware Detection**

#### **run_hardware_detection()**

**Purpose:** Collect hardware specs from all devices

**Type:** Orchestration function  
**Parameters:** None  
**Returns:** 0 on success, 1 on failure

**Process:**

1. **Load discovered devices:**
   ```bash
   jq -c '.devices[]' discovered_devices.json
   ```

2. **Build device array:**
   ```bash
   devices+=("${ip}:${user}:${password}")
   ```

3. **Transfer detection script:**
   ```bash
   parallel_file_transfer devices[@] \
       "detect_hardware.sh" \
       "/tmp/detect_hardware.sh"
   ```

4. **Execute in parallel:**
   ```bash
   parallel_exec devices[@] \
       "bash /tmp/detect_hardware.sh" \
       "Collecting hardware profiles"
   ```

5. **Aggregate results:**
   ```bash
   hw_profiles='{"devices":['
   # SSH to each device, collect JSON
   hw_profiles+=']}'
   ```

**Output File:** `hw_profiles.json`
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

**Integration:** Uses `lib/parallel.sh` and `remote/detect_hardware.sh`

---

### **Phase 4: Requirements Validation**

#### **run_validation()**

**Purpose:** Ensure minimum cluster requirements met

**Type:** Validation function  
**Parameters:** None  
**Returns:** 0 on success, 1 on failure

**Checks:**

1. **Minimum Raspberry Pi Count:**
   ```bash
   pi_count=$(jq '[.devices[] | select(.device_type == "raspberry_pi")] | length' \
       hw_profiles.json)
   
   if [[ $pi_count -lt 3 ]]; then
       log ERROR "Insufficient Raspberry Pis: $pi_count found, minimum 3 required"
       return 1
   fi
   ```

**Why 3 Pis Minimum:**
- Docker Swarm requires odd number of managers
- Minimum for fault tolerance: 3 managers
- Can lose 1 manager and maintain quorum

**Future Checks (Planned):**
- Minimum RAM per Pi
- Network connectivity between devices
- Compatible OS versions

---

### **Phase 5: Role Assignment**

#### **run_role_assignment()**

**Purpose:** Score devices and assign manager/worker roles

**Type:** Orchestration function  
**Parameters:** None  
**Returns:** 0 on success, 1 on failure

**Process:**

```bash
python3 /opt/aeon/lib/scoring.py \
    "$DATA_DIR/hw_profiles.json" \
    "$DATA_DIR/role_assignments.json"
```

**Algorithm:** See `scoring.py` documentation

**Output File:** `role_assignments.json`
```json
{
  "timestamp": "2025-12-14T...",
  "summary": {
    "total_devices": 6,
    "manager_count": 3,
    "worker_count": 3,
    "fault_tolerance": 1
  },
  "assignments": [
    {
      "rank": 1,
      "role": "manager",
      "device": {
        "ip": "192.168.1.101",
        "hostname": "pi5-master-01",
        "score": 163,
        "model": "Raspberry Pi 5 Model B Rev 1.0"
      }
    }
  ]
}
```

**Display:** Shows manager/worker counts and fault tolerance

**Integration:** Calls `lib/scoring.py` (Python module)

---

### **Phase 6: Dependency Installation**

#### **run_installation()**

**Purpose:** Install Docker and dependencies on all devices

**Type:** Orchestration function  
**Parameters:** None  
**Returns:** 0 on success (partial failures logged)

**Process:**

1. **Build device list from role assignments**
2. **Transfer installer script:**
   ```bash
   parallel_file_transfer devices[@] \
       "install_dependencies.sh" \
       "/tmp/install_dependencies.sh"
   ```

3. **Execute in parallel:**
   ```bash
   parallel_exec devices[@] \
       "sudo bash /tmp/install_dependencies.sh" \
       "Installing dependencies"
   ```

4. **Collect results:**
   ```bash
   results=$(parallel_collect_results)
   ```

**Output File:** `installation_results.json`
```json
{
  "successful": 6,
  "failed": 0,
  "devices": [
    {
      "ip": "192.168.1.101",
      "status": "success",
      "docker_version": "24.0.7",
      "reboot_required": false
    }
  ]
}
```

**Parallel Execution:** All devices install simultaneously

**Integration:** Uses `lib/parallel.sh` and `remote/install_dependencies.sh`

---

### **Phase 7: AEON User Setup**

#### **run_user_setup()**

**Purpose:** Create AEON automation user on all devices

**Type:** Orchestration function  
**Parameters:** None  
**Returns:** 0 on success, 1 on failure

**Process:**

1. **Generate credentials:**
   ```bash
   source /opt/aeon/lib/aeon_user.sh
   generate_aeon_password
   ```

2. **Save credentials:**
   ```bash
   save_aeon_credentials "$SECRETS_DIR/.aeon.env"
   ```

3. **Deploy to all devices:**
   ```bash
   setup_aeon_user_on_devices devices[@]
   ```

**Credentials File:** `/opt/aeon/secrets/.aeon.env`
```bash
AEON_USER="aeon"
AEON_PASSWORD="<randomly generated 32 chars>"
```

**Permissions:** `chmod 700` on secrets directory

**User Capabilities:**
- Limited sudo (reboot only)
- SSH access with password
- Member of docker group

**Integration:** Uses `lib/aeon_user.sh` module

---

### **Phase 8: Synchronized Reboot**

#### **run_reboot_phase()**

**Purpose:** Reboot devices if needed while maintaining cluster quorum

**Type:** Orchestration function  
**Parameters:** None  
**Returns:** 0 on success (or skip)

**Decision Logic:**

```bash
source /opt/aeon/lib/06-reboot.sh

if ! check_devices_need_reboot "$DATA_DIR/installation_results.json"; then
    log INFO "No reboot required"
    return 0
fi
```

**User Confirmation:**
```
Proceed with reboot? [y/N]
```

**Reboot Sequence:**

1. **Workers** - Reboot in parallel
2. **Managers** - Reboot sequentially (maintain quorum)
3. **Entry Device** - Reboot last
4. **Verify** - Wait for all devices online

**Why This Order:**
- Workers can reboot freely (no quorum impact)
- Managers must maintain majority (sequential)
- Entry device reboots last (can monitor others)

**Integration:** Uses `lib/06-reboot.sh` module

---

### **Phase 9: Docker Swarm Setup**

#### **run_swarm_setup()**

**Purpose:** Initialize and form Docker Swarm cluster

**Type:** Orchestration function  
**Parameters:** None  
**Returns:** 0 on success, 1 on failure

**Process:**

```bash
source /opt/aeon/lib/07-swarm.sh
source /opt/aeon/.aeon.env

setup_docker_swarm \
    "$DATA_DIR/role_assignments.json" \
    "$AEON_USER" \
    "$AEON_PASSWORD"
```

**Swarm Formation Steps:**

1. **Initialize** - On first manager (rank #1)
2. **Extract Tokens** - Manager and worker join tokens
3. **Join Managers** - Sequential with 5s Raft delay
4. **Join Workers** - Parallel
5. **Create Networks** - aeon-overlay (10.0.1.0/24)
6. **Verify** - Cluster health check

**Timeline:**
- Initialize: ~5s
- Manager joins: ~10s per manager
- Worker joins: ~15s (parallel)
- Networks: ~5s
- Total: ~60-90s for 6 devices

**Integration:** Uses `lib/07-swarm.sh` module

---

### **Phase 10: Report Generation**

#### **run_report_generation()**

**Purpose:** Generate beautiful installation reports

**Type:** Orchestration function  
**Parameters:** None  
**Returns:** 0 on success (non-critical)

**Process:**

```bash
source /opt/aeon/lib/08-report.sh
export AEON_LOG_DIR="$LOG_DIR"

generate_installation_report "$DATA_DIR" "all"
```

**Reports Generated:**

1. **Terminal Report** - Colored, formatted display
2. **Markdown Report** - `reports/aeon-report-TIMESTAMP.md`
3. **JSON Report** - `reports/aeon-report-TIMESTAMP.json`

**Report Sections:**
- Executive summary
- Cluster topology
- Device details
- Network configuration
- Quick start guide

**Integration:** Uses `lib/08-report.sh` module

---

### **Completion Functions**

#### **print_completion()**

**Purpose:** Display final success message and quick start guide

**Type:** Display function  
**Parameters:** None  
**Returns:** None

**Information Shown:**

1. **Success Banner**
2. **Cluster Summary** - Device counts, fault tolerance
3. **Quick Start Commands**
4. **Resource Locations** - Logs, reports, docs

**Example Output:**
```
════════════════════════════════════════════════════════
  🎉 AEON CLUSTER INSTALLATION COMPLETE! 🎉
════════════════════════════════════════════════════════

Cluster Summary:
  • Total Devices: 6
  • Managers: 3
  • Workers: 3

Quick Start:

  1. Connect to cluster:
     ssh aeon@192.168.1.101

  2. View cluster:
     docker node ls

  3. Deploy a service:
     docker service create --name web --replicas 3 --publish 80:80 nginx

Resources:
  • Installation Log: /opt/aeon/logs/aeon-go.log
  • Reports: /opt/aeon/reports/
  • Documentation: https://github.com/conceptixx/AEON
```

---

### **Error Handling**

#### **handle_error(line_number)**

**Purpose:** Trap and handle script errors

**Type:** Error handler  
**Parameters:**
- `line_number` - Line where error occurred

**Installation:**
```bash
trap 'handle_error $LINENO' ERR
```

**Behavior:**
1. Log error message with line number
2. Show log file location
3. Exit with error code

**Example Output:**
```
❌ Installation failed at line 342
ℹ️  Check logs: /opt/aeon/logs/aeon-go.log
```

---

### **Main Function**

#### **main()**

**Purpose:** Main orchestration - calls all phases in order

**Type:** Entry point  
**Parameters:** None  
**Returns:** 0 on success, 1 on failure

**Flow:**
```bash
main() {
    local start_time=$(date +%s)
    
    print_banner
    run_preflight_checks || exit 1
    run_discovery_phase || exit 1
    run_hardware_detection || exit 1
    run_validation || exit 1
    run_role_assignment || exit 1
    run_installation || exit 1
    run_user_setup || exit 1
    run_reboot_phase || true      # Non-critical
    run_swarm_setup || exit 1
    run_report_generation || true # Non-critical
    
    print_completion
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log SUCCESS "Total time: $((duration / 60))m $((duration % 60))s"
}

main "$@"
```

**Error Policy:**
- Phases 1-7, 9: Critical (exit on failure)
- Phases 8, 10: Non-critical (continue on failure)

**Timing:** Tracks total installation time

---

## 🔗 Dependencies

### **External Scripts (Sourced)**

All located in `/opt/aeon/lib/`:

1. **parallel.sh** - Parallel execution framework
   - `parallel_init()`
   - `parallel_file_transfer()`
   - `parallel_exec()`
   - `parallel_collect_results()`

2. **02-discovery.sh** - Network discovery
   - `run_discovery()`

3. **aeon_user.sh** - User management
   - `generate_aeon_password()`
   - `save_aeon_credentials()`
   - `setup_aeon_user_on_devices()`

4. **06-reboot.sh** - Synchronized reboot
   - `check_devices_need_reboot()`
   - `synchronized_reboot()`

5. **07-swarm.sh** - Docker Swarm
   - `setup_docker_swarm()`

6. **08-report.sh** - Report generation
   - `generate_installation_report()`

### **External Scripts (Executed)**

1. **lib/scoring.py** - Python scoring algorithm
   - Input: `hw_profiles.json`
   - Output: `role_assignments.json`

2. **remote/detect_hardware.sh** - Hardware detection
   - Transferred and executed on all devices
   - Returns JSON hardware profile

3. **remote/install_dependencies.sh** - Dependency installer
   - Transferred and executed on all devices
   - Installs Docker and packages

### **System Commands**

**Required:**
- `bash` (≥4.0)
- `jq` - JSON parsing
- `sshpass` - SSH automation
- `python3` - Scoring algorithm

**Auto-installed:**
- `curl`, `wget` - Downloads
- `git` - Version control

---

## 🔌 Integration Points

### **Called By**

**User** → `aeon-go.sh`

```bash
cd /opt/aeon
sudo bash aeon-go.sh
```

### **Calls (Sources) These Modules**

```
aeon-go.sh
├─> lib/parallel.sh
├─> lib/02-discovery.sh
├─> lib/aeon_user.sh
├─> lib/06-reboot.sh
├─> lib/07-swarm.sh
└─> lib/08-report.sh
```

### **Executes These Scripts**

```
aeon-go.sh
├─> python3 lib/scoring.py
├─> bash remote/detect_hardware.sh (on all devices)
└─> bash remote/install_dependencies.sh (on all devices)
```

### **Data Flow**

```
Network Scan
    ↓
discovered_devices.json
    ↓
Hardware Detection
    ↓
hw_profiles.json
    ↓
Scoring Algorithm
    ↓
role_assignments.json
    ↓
Installation
    ↓
installation_results.json
    ↓
User Setup
    ↓
.aeon.env
    ↓
Swarm Formation
    ↓
Reports
```

---

## ⚠️ Error Handling

### **Critical Phases (Exit on Failure)**

Phases 1-7, 9:
- Pre-flight checks
- Discovery
- Hardware detection
- Validation
- Role assignment
- Installation
- User setup
- Swarm setup

**Behavior:** Exits immediately with code 1

---

### **Non-Critical Phases**

Phases 8, 10:
- Reboot (optional)
- Report generation (informational)

**Behavior:** Logs warning, continues

---

### **Common Error Scenarios**

#### **Scenario 1: Not Running as Root**

```
❌ This script must be run as root

Please run: sudo bash aeon-go.sh
```

**Recovery:** Run with sudo

---

#### **Scenario 2: No Internet**

```
❌ No internet connection
```

**Recovery:**
1. Check network: `ping 8.8.8.8`
2. Fix connectivity
3. Re-run

---

#### **Scenario 3: Insufficient Devices**

```
❌ Insufficient Raspberry Pis: 2 found, minimum 3 required
```

**Recovery:**
1. Add more Raspberry Pis to network
2. Ensure SSH enabled
3. Re-run

---

#### **Scenario 4: Discovery Found No Devices**

```
⚠️  No devices discovered
```

**Possible Causes:**
- Wrong network range
- Devices offline
- Firewall blocking

**Recovery:**
1. Verify network range
2. Check devices are on and connected
3. Re-run

---

#### **Scenario 5: Installation Failed on Some Devices**

```
⚠️  2 device(s) failed installation
  • 192.168.1.104: Connection timeout
  • 192.168.1.105: Package installation error
```

**Recovery:**
1. SSH to failed devices manually
2. Check logs: `/var/log/aeon-install.log`
3. Fix issues
4. Re-run or continue with remaining devices

---

## 📖 Examples

### **Example 1: Standard Installation**

```bash
# Start installation
cd /opt/aeon
sudo bash aeon-go.sh

# User inputs
Enter network range [192.168.1.0/24]: ↵
Enter default SSH user [pi]: ↵
Enter default SSH password: raspberry

# Phases execute...
[~20 minutes]

# Completion
🎉 AEON CLUSTER INSTALLATION COMPLETE! 🎉

# Result
ssh aeon@192.168.1.101
docker node ls
```

---

### **Example 2: Custom Network Range**

```bash
sudo bash aeon-go.sh

Enter network range [192.168.1.0/24]: 10.0.0.0/24
Enter default SSH user [pi]: ubuntu
Enter default SSH password: ubuntu
```

---

### **Example 3: Skip Reboot**

```bash
# During Phase 8:
Proceed with reboot? [y/N] n

⚠️  Reboot skipped by user

# Installation continues...
```

---

### **Example 4: View Progress Logs**

```bash
# In another terminal during installation:
tail -f /opt/aeon/logs/aeon-go.log
```

---

## 🔧 Troubleshooting

### **Issue: Script Hangs at Discovery**

**Symptoms:**
```
▶ Scanning network with nmap: 192.168.1.0/24
[hangs]
```

**Causes:**
- Very large network range
- Slow network
- Many devices

**Solutions:**

1. **Use smaller range:**
   ```bash
   # Instead of /24 (254 hosts)
   Enter network range: 192.168.1.100/28  # 14 hosts
   ```

2. **Wait longer:**
   - /24 network: ~30s
   - /16 network: several minutes

---

### **Issue: All Devices Classified as "Host"**

**Symptoms:**
```
❌ Insufficient Raspberry Pis: 0 found, minimum 3 required
```

**Causes:**
- Raspberry Pis not accessible
- Wrong credentials
- Not actually Raspberry Pis

**Solutions:**

1. **Verify manually:**
   ```bash
   ssh pi@192.168.1.101
   cat /proc/cpuinfo | grep "Raspberry"
   ```

2. **Check credentials:**
   ```bash
   ssh pi@192.168.1.101  # Should work
   ```

---

### **Issue: Docker Installation Fails**

**Symptoms:**
```
⚠️  3 device(s) failed installation
  • 192.168.1.101: Package installation error
```

**Solutions:**

1. **Check internet on device:**
   ```bash
   ssh pi@192.168.1.101
   ping 8.8.8.8
   ```

2. **Check disk space:**
   ```bash
   ssh pi@192.168.1.101
   df -h /
   ```

3. **Manual install:**
   ```bash
   ssh pi@192.168.1.101
   curl -fsSL https://get.docker.com | sudo bash
   ```

---

### **Issue: Swarm Formation Fails**

**Symptoms:**
```
❌ Docker Swarm setup failed
```

**Causes:**
- Docker not running
- Network issues
- Firewall blocking

**Solutions:**

1. **Check Docker:**
   ```bash
   ssh aeon@192.168.1.101
   docker info
   ```

2. **Check firewall:**
   ```bash
   # Required ports
   sudo ufw allow 2377/tcp
   sudo ufw allow 7946/tcp
   sudo ufw allow 7946/udp
   sudo ufw allow 4789/udp
   ```

3. **Manual swarm init:**
   ```bash
   ssh aeon@192.168.1.101
   docker swarm init --advertise-addr 192.168.1.101
   ```

---

## 📊 Timeline

**Typical 6-Device Cluster:**

```
Phase 1: Pre-flight              ~30s
Phase 2: Discovery               ~30s
Phase 3: Hardware Detection      ~20s
Phase 4: Validation               ~5s
Phase 5: Role Assignment          ~5s
Phase 6: Installation         ~5-8 min (parallel)
Phase 7: AEON User               ~30s
Phase 8: Reboot              ~6-8 min (optional)
Phase 9: Swarm Setup             ~90s
Phase 10: Report                 ~10s
─────────────────────────────────────
TOTAL: 15-20 min (without reboot)
       22-30 min (with reboot)
```

---

## 📝 Configuration

### **Constants**

```bash
AEON_VERSION="0.1.0"
AEON_DIR="/opt/aeon"
DATA_DIR="$AEON_DIR/data"
LOG_DIR="$AEON_DIR/logs"
SECRETS_DIR="$AEON_DIR/secrets"
REPORT_DIR="$AEON_DIR/reports"
DEFAULT_NETWORK_RANGE="192.168.1.0/24"
```

### **Customization**

**Change network default:**
```bash
# Edit aeon-go.sh
DEFAULT_NETWORK_RANGE="10.0.0.0/24"
```

**Change installation directory:**
```bash
# Edit aeon-go.sh
AEON_DIR="/custom/path"
```

---

## 🎯 Design Philosophy

### **Principles**

1. **User-Centric** - Minimal interaction, clear feedback
2. **Fault-Tolerant** - Handles failures gracefully
3. **Modular** - Each phase is independent
4. **Transparent** - Shows what's happening
5. **Resumable** - Can recover from failures

### **Best Practices Followed**

- **DRY** - Don't Repeat Yourself (shared functions)
- **KISS** - Keep It Simple, Stupid (clear flow)
- **Fail Fast** - Exit early on critical errors
- **Log Everything** - Full audit trail
- **User Feedback** - Constant progress updates

---

## 📊 Statistics

```
File: aeon-go.sh
Lines of Code: ~600
Functions: 15
Phases: 10
External Modules: 6
External Scripts: 3
Average Runtime: 20-30 minutes
```

---

## 🔄 Version History

**0.1.0** (Current)
- Initial release
- 10-phase installation
- Full module integration
- Error handling
- Progress reporting

---

## 📞 Related Documentation

- [bootstrap.sh Documentation](./bootstrap.sh.md) - Bootstrap installer
- [Parallel Module](../docs/modules/PARALLEL_MODULE.md) - Parallel execution
- [Discovery Module](../docs/modules/DISCOVERY.md) - Network discovery
- [Scoring Algorithm](../docs/modules/SCORING.md) - Role assignment
- [Swarm Setup](../docs/modules/SWARM.md) - Docker Swarm formation
- [Architecture Overview](../docs/architecture/OVERVIEW.md) - System design

---

**This documentation is for AEON version 0.1.0**  
**Last Updated:** 2025-12-14  
**Maintained by:** AEON Development Team
