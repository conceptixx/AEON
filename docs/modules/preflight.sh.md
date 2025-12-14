![AEON Banner](.github/assets/aeon_banner_v2_2400x600.png)

# preflight.sh - AEON Pre-flight Checks Module

## 📋 Overview

**File:** `lib/preflight.sh`  
**Type:** Library module (sourced, not executed)  
**Version:** 0.1.0  
**Purpose:** Verify system meets requirements before AEON installation

**Quick Description:**  
The pre-flight checks module validates that the entry device has everything needed to run AEON: root privileges, internet connectivity, disk space, required tools, and proper directory structure.

---

## 🎯 Purpose & Context

### **Why This Module Exists**

Before installing AEON across a cluster, we must ensure the entry device (the device running `aeon-go.sh`) meets minimum requirements. Running pre-flight checks prevents failures mid-installation and provides clear error messages if something is missing.

### **What Gets Validated**

✅ **Root privileges** - Must run as root  
✅ **Bash version** - Minimum bash 4.0  
✅ **Internet connectivity** - Required for downloads  
✅ **DNS resolution** - Package repositories need DNS  
✅ **Disk space** - Minimum 1GB free  
✅ **Write permissions** - Can create AEON directories  
✅ **Required tools** - Auto-installs if missing  
✅ **Directory structure** - Creates all needed directories  
✅ **OS compatibility** - Detects Linux/macOS  
✅ **System resources** - Reports CPU/RAM  

### **Fail Fast Philosophy**

If a critical requirement isn't met, pre-flight checks **exit immediately** with a clear error message and recovery instructions.

---

## 🚀 Usage

### **Primary Usage (Called by aeon-go.sh)**

```bash
#!/bin/bash

source /opt/aeon/lib/preflight.sh

# Run all pre-flight checks
run_preflight_checks || exit 1

# If we get here, all checks passed
log SUCCESS "System ready for AEON installation"
```

### **Individual Check Usage**

```bash
source /opt/aeon/lib/preflight.sh

# Run specific checks
check_root || exit 1
check_internet || exit 1
check_disk_space || exit 1
create_directories || exit 1
```

### **Custom Requirements**

```bash
source /opt/aeon/lib/preflight.sh

# Override minimum disk space
MIN_DISK_SPACE_GB=5

# Run checks
run_preflight_checks
```

---

## 🏗️ Architecture

### **Execution Flow**

```
run_preflight_checks()
    │
    ├─> check_root()
    │   └─> Exit if not root
    │
    ├─> check_bash_version()
    │   └─> Exit if < bash 4.0
    │
    ├─> check_internet()
    │   └─> Exit if no internet
    │
    ├─> check_disk_space()
    │   └─> Exit if < 1GB free
    │
    ├─> check_disk_write()
    │   └─> Exit if cannot write
    │
    ├─> check_required_tools()
    │   ├─> Detect missing tools
    │   ├─> Install missing tools
    │   └─> Exit if installation fails
    │
    ├─> create_directories()
    │   └─> Exit if creation fails
    │
    ├─> verify_directories()
    │   └─> Exit if verification fails
    │
    ├─> check_dns_resolution() [non-critical]
    ├─> check_optional_tools() [non-critical]
    ├─> check_os_compatibility() [non-critical]
    └─> check_system_resources() [informational]
```

### **Critical vs. Non-Critical**

**Critical Checks** (exit on failure):
- Root privileges
- Bash version
- Internet connectivity
- Disk space
- Required tools
- Directory creation

**Non-Critical Checks** (warn only):
- DNS resolution
- Optional tools
- OS compatibility
- System resources

---

## 📚 Configuration Constants

```bash
# Minimum requirements
readonly MIN_DISK_SPACE_GB=1
readonly REQUIRED_BASH_VERSION=4

# Required tools (auto-installed if missing)
readonly REQUIRED_TOOLS=(
    "curl"
    "wget"
    "jq"
    "git"
    "sshpass"
    "python3"
)

# Optional tools (warn if missing)
readonly OPTIONAL_TOOLS=(
    "nmap"
    "docker"
)
```

---

## 📚 Functions Reference

### **Root & Permissions**

#### **check_root()**

Verify script is running as root (UID 0).

**Parameters:** None  
**Returns:** 0 if root, exits with 1 if not root  
**Side Effects:** Displays error message and exits if not root

**Example:**
```bash
check_root || exit 1
```

**Error Message:**
```
❌ This script must be run as root

Please run with sudo:
  sudo bash aeon-go.sh
```

**Why Root is Required:**
- Installing system packages
- Creating `/opt/aeon` directory
- Configuring system services
- Modifying firewall rules

---

#### **check_disk_write()**

Verify write permissions to installation directory.

**Parameters:** None  
**Returns:**
- 0 if writable
- 1 if not writable

**Method:**
```bash
# Try to create test directory
mkdir -p "$AEON_DIR/test_$$"
# If successful, remove it
rmdir "$AEON_DIR/test_$$"
```

---

### **Bash Version**

#### **check_bash_version()**

Verify bash version is ≥ 4.0.

**Parameters:** None  
**Returns:**
- 0 if version sufficient
- 1 if version too old

**Why Bash 4.0:**
- Associative arrays (`declare -A`)
- Parameter transformation (`${var@Q}`)
- Globstar support (`**/*`)

**Example:**
```bash
check_bash_version || exit 1
```

---

### **Network Checks**

#### **check_internet()**

Verify internet connectivity by pinging multiple DNS servers.

**Parameters:** None  
**Returns:**
- 0 if internet available
- 1 if no internet

**DNS Servers Tested:**
1. `8.8.8.8` (Google DNS)
2. `1.1.1.1` (Cloudflare DNS)
3. `9.9.9.9` (Quad9 DNS)

**Method:**
```bash
ping -c 1 -W 3 8.8.8.8
```

**Why Multiple DNS Servers:**
- Redundancy (if one is down)
- Faster success (tries next immediately)
- Different network paths

**Example:**
```bash
if check_internet; then
    log SUCCESS "Internet available"
else
    log ERROR "No internet connection"
    exit 1
fi
```

---

#### **check_dns_resolution()**

Verify DNS resolution works (non-critical).

**Parameters:** None  
**Returns:**
- 0 if DNS works
- 1 if DNS fails

**Method:**
```bash
host github.com || nslookup github.com
```

**Use Case:**  
Warns if DNS has issues but doesn't block installation.

---

### **Storage Checks**

#### **check_disk_space()**

Verify sufficient disk space available (minimum 1GB).

**Parameters:** None  
**Returns:**
- 0 if sufficient
- 1 if insufficient

**Calculation:**
```bash
available_kb=$(df / | tail -1 | awk '{print $4}')
available_gb=$((available_kb / 1024 / 1024))
required_kb=$((MIN_DISK_SPACE_GB * 1024 * 1024))
```

**Error Message:**
```
❌ Insufficient disk space
  Available: 0GB
  Required: 1GB

ℹ️  Please free up disk space and try again
ℹ️  You can check disk usage with: df -h /
```

**Why 1GB Minimum:**
- Docker images: ~500MB
- System packages: ~200MB
- AEON files: ~100MB
- Log files: ~100MB
- Buffer: ~100MB

---

### **Tool Management**

#### **check_tool(name)**

Check if a single tool is available.

**Parameters:**
- `name` - Tool name

**Returns:**
- 0 if available
- 1 if not available

**Example:**
```bash
if check_tool docker; then
    log INFO "Docker is installed"
fi
```

---

#### **get_package_manager()**

Detect available package manager.

**Parameters:** None  
**Returns:** Package manager name or empty string

**Supported Package Managers:**
- `apt-get` (Debian/Ubuntu)
- `yum` (RHEL/CentOS 7)
- `dnf` (Fedora/RHEL 8+)
- `brew` (macOS)
- `pacman` (Arch Linux)

**Example:**
```bash
pkg_mgr=$(get_package_manager)
if [[ "$pkg_mgr" == "apt-get" ]]; then
    log INFO "Debian-based system detected"
fi
```

---

#### **install_tool(name)**

Install a single tool using available package manager.

**Parameters:**
- `name` - Tool name to install

**Returns:**
- 0 on success
- 1 on failure

**Installation Methods:**
```bash
# apt-get (Debian/Ubuntu)
apt-get update -qq
apt-get install -y -qq "$tool"

# yum (RHEL/CentOS)
yum install -y -q "$tool"

# dnf (Fedora)
dnf install -y -q "$tool"

# brew (macOS)
brew install "$tool"

# pacman (Arch)
pacman -S --noconfirm "$tool"
```

**Example:**
```bash
if ! check_tool jq; then
    install_tool jq || exit 1
fi
```

---

#### **check_required_tools()**

Check and install all required tools.

**Parameters:** None  
**Returns:**
- 0 if all tools available (after installation)
- 1 if any tool cannot be installed

**Required Tools:**
- `curl` - Download files
- `wget` - Alternative downloader
- `jq` - JSON parsing
- `git` - Version control
- `sshpass` - SSH automation
- `python3` - Scoring algorithm

**Process:**
1. Check which tools are missing
2. Attempt to install each missing tool
3. Verify installation succeeded
4. Report any failures

**Example:**
```bash
check_required_tools || exit 1
```

---

#### **check_optional_tools()**

Check optional tools (warn if missing, don't fail).

**Parameters:** None  
**Returns:** Always 0

**Optional Tools:**
- `nmap` - Network scanning (faster discovery)
- `docker` - Container runtime (installed later if missing)

**Behavior:**
- Logs warning if missing
- Does NOT attempt installation
- Does NOT fail

---

### **Directory Management**

#### **create_directories()**

Create AEON directory structure.

**Parameters:** None  
**Returns:**
- 0 on success
- 1 if any directory creation fails

**Directories Created:**
```
/opt/aeon/           (755)
├── lib/             (755)
├── remote/          (755)
├── config/          (755)
├── data/            (755)
├── logs/            (755)
├── reports/         (755)
└── secrets/         (700) ← restricted permissions
```

**Special Permissions:**
- Most directories: `755` (rwxr-xr-x)
- Secrets directory: `700` (rwx------) - owner only

**Example:**
```bash
create_directories || exit 1
```

---

#### **verify_directories()**

Verify all directories exist and are writable.

**Parameters:** None  
**Returns:**
- 0 if all verified
- 1 if any issues

**Checks:**
- Directory exists (`-d`)
- Directory is writable (`-w`)

**Example:**
```bash
verify_directories || exit 1
```

---

### **System Information**

#### **check_os_compatibility()**

Check if OS is supported (non-critical).

**Parameters:** None  
**Returns:** Always 0

**Detected OS:**
- **Linux** - Fully supported
  - Reads `/etc/os-release` for distribution
- **macOS** - Experimental support
  - Detects version with `sw_vers`
- **Other** - Warning but continues

**Example Output:**
```
✅ Detected: Ubuntu 22.04.3 LTS
```

or

```
⚠️  Detected: macOS 14.1
⚠️  macOS support is experimental
```

---

#### **check_system_resources()**

Report system resources (informational only).

**Parameters:** None  
**Returns:** Always 0

**Reports:**
- CPU cores (via `nproc` or `sysctl`)
- Total RAM in GB (via `/proc/meminfo` or `sysctl`)

**Example Output:**
```
ℹ️  System resources:
ℹ️    • CPU cores: 4
ℹ️    • RAM: 8GB
```

---

### **Orchestration**

#### **run_preflight_checks()**

Main function - runs all pre-flight checks in order.

**Parameters:** None  
**Returns:**
- 0 if all checks pass
- Exits with 1 if any critical check fails

**Check Order:**
```
1. check_root()                 [critical]
2. check_bash_version()         [critical]
3. check_internet()             [critical]
4. check_disk_space()           [critical]
5. check_disk_write()           [critical]
6. check_required_tools()       [critical]
7. create_directories()         [critical]
8. verify_directories()         [critical]
9. check_dns_resolution()       [non-critical]
10. check_optional_tools()      [non-critical]
11. check_os_compatibility()    [non-critical]
12. check_system_resources()    [informational]
```

**Example:**
```bash
#!/bin/bash
source /opt/aeon/lib/preflight.sh

# Run all checks
run_preflight_checks || exit 1

# Checks passed - continue with installation
log SUCCESS "System ready"
```

---

## 🔗 Dependencies

### **Module Dependencies**

```bash
source "$SCRIPT_DIR/common.sh"
```

**Functions Used from common.sh:**
- `log()` - Logging
- `is_root()` - Root check
- `command_exists()` - Tool detection
- `ensure_directory()` - Directory creation
- `print_header()` - Display formatting

### **External Commands**

**Required:**
- `bash` (≥4.0)
- `ping` - Internet check
- `df` - Disk space check
- `mkdir` - Directory creation
- `chmod` - Permissions

**Conditionally Used:**
- `host` or `nslookup` - DNS check
- `nproc` or `sysctl` - CPU count
- Package manager (`apt-get`, `yum`, etc.)

---

## 🔌 Integration

### **Called By**

```
aeon-go.sh
    ↓
run_preflight_checks()
```

### **Calls**

```
preflight.sh
    ├─> common.sh (logging, utilities)
    └─> system commands (ping, df, mkdir, etc.)
```

---

## ⚠️ Error Handling

### **Critical Failures (Exit Immediately)**

#### **Not Root**
```
❌ This script must be run as root

Please run with sudo:
  sudo bash aeon-go.sh
```

**Recovery:** Run with `sudo`

---

#### **Old Bash Version**
```
❌ Bash version 4 or higher required
❌ Current version: 3.2.57
```

**Recovery:** Upgrade bash

---

#### **No Internet**
```
❌ No internet connection detected

ℹ️  Internet is required for:
ℹ️    • Package installation
ℹ️    • Docker installation
ℹ️    • Repository downloads

ℹ️  Please check your network connection and try again
```

**Recovery:**
1. Check network cable/WiFi
2. Test: `ping 8.8.8.8`
3. Check firewall rules

---

#### **Insufficient Disk Space**
```
❌ Insufficient disk space
  Available: 0GB
  Required: 1GB

ℹ️  Please free up disk space and try again
ℹ️  You can check disk usage with: df -h /
```

**Recovery:**
```bash
# Find large files
du -h / | sort -h | tail -20

# Clean package cache
sudo apt-get clean

# Remove old logs
sudo journalctl --vacuum-size=100M
```

---

#### **Tool Installation Failed**
```
❌ Failed to install: jq git

ℹ️  Please install these tools manually:
ℹ️    • jq
ℹ️    • git
```

**Recovery:**
```bash
sudo apt-get update
sudo apt-get install jq git
```

---

### **Non-Critical Warnings**

#### **DNS Issues**
```
⚠️  DNS resolution may be impaired
ℹ️  This may cause issues downloading packages
```

**Impact:** Package downloads may be slower  
**Recovery:** Continue, monitor for issues

---

#### **Optional Tools Missing**
```
⚠️  Optional tools not available: nmap
ℹ️  These are not required but recommended
```

**Impact:** Network discovery will use fallback methods  
**Recovery:** Optional, install if desired

---

## 📖 Examples

### **Example 1: Standard Usage**

```bash
#!/bin/bash

source /opt/aeon/lib/preflight.sh

print_header "Pre-flight Checks"

run_preflight_checks || exit 1

log SUCCESS "All checks passed"
```

---

### **Example 2: Custom Disk Space Requirement**

```bash
source /opt/aeon/lib/preflight.sh

# Override default 1GB minimum
MIN_DISK_SPACE_GB=5

if check_disk_space; then
    log SUCCESS "Sufficient disk space"
else
    log ERROR "Need at least 5GB free"
    exit 1
fi
```

---

### **Example 3: Individual Checks**

```bash
source /opt/aeon/lib/preflight.sh

# Only check specific requirements
check_root || exit 1
check_internet || exit 1

# Skip other checks
log INFO "Basic checks passed"
```

---

### **Example 4: Tool Installation Only**

```bash
source /opt/aeon/lib/preflight.sh

# Only ensure tools are installed
check_required_tools || exit 1

log SUCCESS "All required tools available"
```

---

## 🔧 Troubleshooting

### **Issue: Script Hangs at Internet Check**

**Symptoms:**
```
▶ Checking internet connectivity...
[hangs]
```

**Cause:** Network timeout too long  
**Solution:** Check firewall, try manual ping

```bash
# Test connectivity
ping -c 1 -W 3 8.8.8.8

# Check firewall
sudo iptables -L
```

---

### **Issue: Tool Installation Fails**

**Symptoms:**
```
❌ Failed to install: jq
```

**Causes:**
- Repository not available
- Network issues
- Package name different on this OS

**Solutions:**
```bash
# Update package list
sudo apt-get update

# Try manual install
sudo apt-get install jq

# Check package name
apt-cache search jq
```

---

### **Issue: Directory Creation Permission Denied**

**Symptoms:**
```
❌ Failed to create: /opt/aeon
```

**Cause:** Not running as root or `/opt` is read-only  
**Solution:**

```bash
# Verify root
whoami  # Should be "root"

# Check mount
mount | grep /opt

# Remount if read-only
sudo mount -o remount,rw /opt
```

---

## 📊 Statistics

```
File: lib/preflight.sh
Lines: 574
Functions: 18
Critical Checks: 8
Non-Critical Checks: 4
Dependencies: lib/common.sh
```

---

## 🎯 Design Principles

1. **Fail Fast** - Exit immediately on critical failures
2. **Clear Errors** - Explain what's wrong and how to fix
3. **Auto-Fix** - Install missing tools automatically
4. **Informative** - Report system capabilities
5. **Defensive** - Check everything before proceeding

---

## 📞 Related Documentation

- [common.sh](./common.sh.md) - Core utilities (dependency)
- [aeon-go.sh](../aeon-go.sh.md) - Main orchestrator (calls this)
- [REQUIREMENTS](../installation/REQUIREMENTS.md) - System requirements

---

**This documentation is for AEON version 0.1.0**  
**Last Updated:** 2025-12-14  
**Maintained by:** AEON Development Team
