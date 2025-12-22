# AEON Primary Installation Script (install_bash.sh) - Documentation

## Overview

`install_bash.sh` is the main AEON installation script that performs the complete system setup after being downloaded by the bootstrap script (`install.sh`). It handles OS-specific configuration, package installation, user creation, directory setup, repository cloning, and orchestrator execution.

## Table of Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Installation Process](#installation-process)
- [Command-Line Options](#command-line-options)
- [Configuration Variables](#configuration-variables)
- [Key Functions](#key-functions)
- [Operating System Support](#operating-system-support)
- [Silent Mode](#silent-mode)
- [Error Handling](#error-handling)
- [Logging](#logging)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [Advanced Topics](#advanced-topics)

## Architecture

### Design Principles

1. **Idempotent**: Safe to run multiple times without breaking existing installation
2. **Atomic**: Each function performs a single, well-defined task
3. **Fail-Fast**: Exits immediately on errors (via `set -e`)
4. **Auditable**: Comprehensive logging of all operations
5. **Secure**: Creates restricted service account, validates sudoers configuration

### Component Structure

```
install_bash.sh
├── Configuration         (Lines 1-40)
├── Pre-scan             (Lines 45-57)
├── Argument Parsing     (Lines 63-101)
├── Logging Functions    (Lines 107-174)
├── OS Detection         (Lines 180-261)
├── Package Install      (Lines 264-357)
├── System User          (Lines 340-383)
├── Directory Setup      (Lines 389-405)
├── Sudoers Config       (Lines 411-443)
├── Repository Clone     (Lines 449-488)
├── Orchestrator         (Lines 494-548)
├── Finalization         (Lines 554-573)
└── Main Flow            (Lines 579-620)
```

## Prerequisites

### System Requirements

**Hardware:**
- **RAM**: 2GB minimum, 4GB recommended
- **Disk**: 5GB free space minimum
- **CPU**: Any modern x86_64 or ARM64 processor

**Software:**
- **OS**: Linux (Ubuntu 18.04+, Debian 10+), macOS 10.14+, or WSL
- **Bash**: Version 3.2 or higher
- **Root Access**: sudo privileges required
- **Internet**: Active connection for package installation and git clone

### Platform-Specific Requirements

**Linux:**
- systemd init system
- apt package manager (Ubuntu/Debian) or manual package installation
- User with sudo privileges

**macOS:**
- Homebrew package manager installed
- Xcode Command Line Tools
- Non-root user account (Homebrew requirement)

**WSL:**
- WSL 2 recommended
- Ubuntu 22.04 distribution
- Windows 10 Build 19041+ or Windows 11

## Installation Process

### High-Level Flow

```
┌──────────────────────────────────────┐
│ 1. Initialize                         │
│    - Parse arguments                  │
│    - Validate root privileges         │
│    - Detect OS                        │
└─────────────┬────────────────────────┘
              │
              ▼
┌──────────────────────────────────────┐
│ 2. Setup Logging                      │
│    - Create log directory             │
│    - Configure output redirection     │
│    - Migrate temp logs                │
└─────────────┬────────────────────────┘
              │
              ▼
┌──────────────────────────────────────┐
│ 3. Platform Detection                 │
│    - Detect Homebrew user (macOS)     │
│    - Find Homebrew path (macOS)       │
└─────────────┬────────────────────────┘
              │
              ▼
┌──────────────────────────────────────┐
│ 4. Install Dependencies               │
│    - Essential tools (git, curl)      │
│    - Python 3.8+                      │
│    - Docker (if available)            │
└─────────────┬────────────────────────┘
              │
              ▼
┌──────────────────────────────────────┐
│ 5. Create System User                 │
│    - Create 'aeon-system' user        │
│    - Set up home directory            │
│    - Add to docker group              │
└─────────────┬────────────────────────┘
              │
              ▼
┌──────────────────────────────────────┐
│ 6. Setup Directory Structure          │
│    - /opt/aeon/library                │
│    - /opt/aeon/manifest               │
│    - /opt/aeon/logfiles               │
│    - /opt/aeon/tmp                    │
└─────────────┬────────────────────────┘
              │
              ▼
┌──────────────────────────────────────┐
│ 7. Configure Sudoers                  │
│    - Create /etc/sudoers.d/aeon-system│
│    - Grant passwordless sudo          │
│    - Validate syntax                  │
└─────────────┬────────────────────────┘
              │
              ▼
┌──────────────────────────────────────┐
│ 8. Clone Repository                   │
│    - Git clone from GitHub            │
│    - Or update if exists              │
│    - Set permissions                  │
└─────────────┬────────────────────────┘
              │
              ▼
┌──────────────────────────────────────┐
│ 9. Setup Python Environment           │
│    - Create virtual environment       │
│    - Install dependencies             │
└─────────────┬────────────────────────┘
              │
              ▼
┌──────────────────────────────────────┐
│ 10. Execute Orchestrator              │
│     - Run manifest-based installer    │
│     - Process installation actions    │
└─────────────┬────────────────────────┘
              │
              ▼
┌──────────────────────────────────────┐
│ 11. Finalize                          │
│     - Set final permissions           │
│     - Display completion summary      │
│     - Show next steps                 │
└──────────────────────────────────────┘
```

### Detailed Step Breakdown

#### Step 1: Initialization

```bash
parse_args "$@"        # Parse command-line flags
[ "$(id -u)" -ne 0 ]   # Verify root privileges
detect_os              # Determine OS type and set AEON_ROOT
```

**What it does:**
- Validates all command-line arguments
- Ensures script is running as root
- Detects Linux, macOS, or WSL
- Sets appropriate installation paths

#### Step 2: Logging Setup

```bash
setup_logging          # Configure log files and output redirection
```

**Interactive Mode:**
- Output goes to both console and log file using `tee`
- User sees progress in real-time

**Silent Mode:**
- All output redirected to log file only
- No console output (perfect for automation)

**Log Location:**
```
/opt/aeon/logfiles/install.bash.YYYYMMDD-HHMMSS.log
```

#### Step 3: Platform Detection (macOS only)

```bash
detect_brew_user       # Find non-root user for Homebrew
detect_brew_path       # Locate brew executable
```

**Why Necessary:**
Homebrew explicitly forbids root execution. The script must:
1. Identify a non-root user (from SUDO_USER or console user)
2. Execute `brew` commands as that user

#### Step 4: Dependency Installation

```bash
install_always_tools   # git, curl, build-essential
install_python         # Python 3.8+, pip, venv
install_docker         # Docker CE (optional)
```

**Package Installation Logic:**

**Linux (apt):**
```bash
# Update package lists (once per run)
apt-get update -qq

# Install packages
apt-get install -y git curl build-essential python3 python3-pip python3-venv
```

**macOS (brew):**
```bash
# Run as non-root user
sudo -u "$BREW_USER" -H "$BREW_PATH" install git python@3.11
```

**Idempotency:**
- Checks if package already installed before attempting installation
- Uses `dpkg -l` (Linux) or `brew list` (macOS) to verify

#### Step 5: System User Creation

```bash
create_system_user     # Create aeon-system service account
```

**Linux Implementation:**
```bash
useradd --system \                    # System account
        --shell /bin/bash \            # Login shell
        --home-dir /opt/aeon \        # Home directory
        --create-home \                # Create home dir
        --user-group \                 # Create group with same name
        aeon-system                    # Username
```

**macOS Implementation:**
```bash
# Find next available UID starting from 400
next_uid=400
while dscl . -list /Users UniqueID | grep -q "^${next_uid}$"; do
    next_uid=$((next_uid + 1))
done

# Create user with dscl
dscl . -create "/Users/aeon-system"
dscl . -create "/Users/aeon-system" UserShell /bin/bash
dscl . -create "/Users/aeon-system" UniqueID "$next_uid"
dscl . -create "/Users/aeon-system" PrimaryGroupID 20
```

**Purpose:**
- Dedicated service account for AEON operations
- Runs with restricted permissions
- Not a regular user account (no password login)

#### Step 6: Directory Structure

```bash
setup_directories
```

Creates:
```
/opt/aeon/
├── library/       # AEON libraries and modules
├── manifest/      # Installation manifests and configs
├── logfiles/      # All installation and operation logs
└── tmp/           # Temporary files, repository clone
```

**Permissions:**
- Owner: `aeon-system:aeon-system`
- Mode: Default (typically 755 for dirs)

#### Step 7: Sudoers Configuration

```bash
setup_sudoers
```

Creates `/etc/sudoers.d/aeon-system`:

```sudoers
# Shutdown/reboot permissions
aeon-system ALL=(ALL) NOPASSWD: /sbin/shutdown
aeon-system ALL=(ALL) NOPASSWD: /usr/bin/systemctl reboot

# Installation and operations commands
aeon-system ALL=(ALL) NOPASSWD: /usr/bin/apt,/usr/bin/apt-get,/usr/bin/dpkg, \
                                 /usr/bin/systemctl,/usr/bin/python3, \
                                 /usr/bin/docker,/bin/chown,/bin/chmod, \
                                 ... (truncated for brevity)
```

**Security Validation:**
```bash
visudo -c -f /etc/sudoers.d/aeon-system
```

If syntax validation fails, the file is removed and installation exits.

**Why These Permissions:**
- **Package managers**: Install AEON dependencies
- **Service control**: Start/stop AEON services
- **Docker**: Manage containers
- **File operations**: Manage AEON files
- **System control**: Controlled shutdown/reboot

#### Step 8: Repository Clone

```bash
clone_repo
```

**Fresh Installation:**
```bash
git clone --depth 1 https://github.com/conceptixx/AEON.git /opt/aeon/tmp/repo
```

**Existing Installation:**
```bash
cd /opt/aeon/tmp/repo
git fetch --all --prune
git reset --hard origin/main
git clean -fd
```

**Shallow Clone (`--depth 1`):**
- Downloads only latest commit
- Faster installation
- Smaller disk usage
- Sufficient for installation purposes

#### Step 9: Python Virtual Environment

```bash
setup_python_venv
```

```bash
# Create venv
python3 -m venv /opt/aeon/venv

# Upgrade pip
/opt/aeon/venv/bin/pip install --upgrade pip

# Install dependencies from requirements.txt
/opt/aeon/venv/bin/pip install -r /opt/aeon/requirements.txt
```

**Why Virtual Environment:**
- Isolated Python dependencies
- Doesn't interfere with system Python
- Reproducible installations
- Easy to remove/recreate

#### Step 10: Orchestrator Execution

```bash
run_orchestrator
```

The orchestrator is the intelligence of AEON installation:

```bash
sudo -u "$AEON_USER" -H \
  AEON_ROOT="/opt/aeon/tmp/repo" \
  python3 "${REPO_DIR}/library/orchestrator/orchestrator.json.py" \
    --cli-enable \                              # Optional flags
    --web-enable \                              # passed from command line
    --file:"manifest/manifest.install.json" \   # Main manifest
    --config:"manifest/config/manifest.config.cursed.json"  # Config
```
--file: is influenced by the global `"AEON_ORCH_REL"`
  - if set to 1 the path manifest/manifest.install.json is used
  - if set to 0 the path `${AEON_ROOT}`/tmp/repo/manifest/manifest.install.json is used

--config: is influenced by the global `"AEON_ORCH_REL"`
  - if set to 1 the path manifest/config/manifest.config.cursed.json is used
  - if set to 0 the path `${AEON_ROOT}`/tmp/repo/manifest/config/manifest.config.cursed.json is used


**What Orchestrator Does:**
1. Reads manifest files (JSON-based installation instructions)
2. Processes actions sequentially:
   - File creation
   - Service installation
   - Configuration updates
   - Validation checks
3. Handles dependencies between actions
4. Provides detailed progress logging

#### Step 11: Finalization

```bash
finalize_installation
```

**Tasks:**
- Set final file permissions
- Display completion summary:
  - AEON version
  - Installation root
  - System user
  - Next steps
- Show log file locations

**Example Output:**
```
=========================================
AEON Installation Complete!
=========================================
Version: 6.1.0
Root: /opt/aeon
User: aeon-system

Next steps:
  - Review logs in /opt/aeon/logfiles/
  - Check configuration in /opt/aeon/manifest/
```

## Command-Line Options

### Available Flags

| Flag | Long Form | Description | Default |
|------|-----------|-------------|---------|
| `-c` | `--cli-enable`, `--enable-cli` | Enable CLI features | Disabled |
| `-w` | `--web-enable`, `--enable-web` | Enable web interface | Disabled |
| `-n` | `--noninteractive` | Silent mode (no console output) | Interactive |

### Usage Examples

**Interactive installation with CLI:**
```bash
sudo ./install_bash.sh --cli-enable
```

**Silent installation with both modes:**
```bash
sudo ./install_bash.sh -c -w -n
```

**View installation progress:**
```bash
# In another terminal during silent installation
tail -f /opt/aeon/logfiles/install.bash.*.log
```

## Configuration Variables

### Core Constants

```bash
AEON_VERSION="6.1.0"                          # Target version
AEON_REPO_URL="https://github.com/conceptixx/AEON.git"  # Git repository
AEON_ORCH_MODE="native"                       # Orchestrator mode (native/docker)
AEON_ORCH_REL=1                               # Orchestrator path handling (absolute=0 / relative=1)
AEON_ORCH_REPO="/tmp/repo"                    # Orchestrator repo path
AEON_USER="aeon-system"                       # Service account name
```

### Sudoers Commands List

```bash
SUDOERS_INSTALL_CMDS="/usr/bin/apt,/usr/bin/apt-get,..."
```

**Purpose:** Defines which commands the AEON system user can execute with sudo.

**Categories:**
1. **Package Management**: apt, apt-get, dpkg, snap, brew
2. **Service Control**: systemctl, service
3. **Python**: python3, pip3
4. **Docker**: docker, docker-compose
5. **File Operations**: chown, chmod, mkdir, rm, cp, mv
6. **Network Tools**: curl, wget, git

### Global State Variables

| Variable | Type | Purpose | Set By |
|----------|------|---------|--------|
| `OS_TYPE` | String | Operating system (linux/macos/wsl) | `detect_os()` |
| `AEON_ROOT` | Path | Installation root directory | `detect_os()` |
| `REPO_DIR` | Path | Repository clone location | `clone_repo()` |
| `BREW_USER` | String | Non-root user for brew (macOS) | `detect_brew_user()` |
| `BREW_PATH` | Path | Brew executable path (macOS) | `detect_brew_path()` |
| `LOG_FILE` | Path | Main log file path | `setup_logging()` |
| `TEMP_LOG` | Path | Temporary log (silent mode) | Pre-scan |
| `SILENT_MODE` | Boolean (0/1) | Silent vs interactive | Pre-scan |
| `APT_UPDATED` | Boolean (0/1) | Whether apt-get update ran | Package install |

## Key Functions

### detect_os()

**Purpose:** Detect operating system and set appropriate paths

**Implementation:**
```bash
detect_os() {
    local uname_s="$(uname -s)"
    
    case "$uname_s" in
        Linux*)
            # Check for WSL
            if grep -qi microsoft /proc/version 2>/dev/null; then
                OS_TYPE="wsl"
            else
                OS_TYPE="linux"
            fi
            AEON_ROOT="/opt/aeon"
            ;;
        Darwin*)
            OS_TYPE="macos"
            AEON_ROOT="/usr/local/aeon"
            ;;
        *)
            log_error "Unsupported OS: $uname_s"
            exit 1
            ;;
    esac
}
```

**WSL Detection:**
Checks `/proc/version` for "microsoft" string:
```bash
# WSL /proc/version contains:
# Linux version 5.10.16.3-microsoft-standard-WSL2
```

### install_package_idempotent()

**Purpose:** Install package only if not already installed

**Signature:**
```bash
install_package_idempotent "package-name"
```

**Linux Implementation:**
```bash
install_package_idempotent() {
    local pkg="$1"
    
    # Check if installed
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        log "$pkg already installed"
        return 0
    fi
    
    # Update package lists (once per run)
    if [ "$APT_UPDATED" -eq 0 ]; then
        apt-get update -qq
        APT_UPDATED=1
    fi
    
    # Install package
    log "Installing $pkg..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" || return 1
}
```

**macOS Implementation:**
```bash
# Check if installed
if sudo -u "$BREW_USER" -H "$BREW_PATH" list "$pkg" >/dev/null 2>&1; then
    log "$pkg already installed"
    return 0
fi

# Install
sudo -u "$BREW_USER" -H "$BREW_PATH" install "$pkg"
```

**Key Features:**
- Idempotent (safe to run multiple times)
- Minimizes `apt-get update` calls (expensive operation)
- Respects non-root requirement for Homebrew

### create_system_user()

**Purpose:** Create dedicated AEON service account

**Linux (useradd):**
```bash
useradd --system \
        --shell /bin/bash \
        --home-dir "$AEON_ROOT" \
        --create-home \
        --user-group \
        aeon-system
```

**macOS (dscl):**
```bash
# Find available UID
next_uid=400
while dscl . -list /Users UniqueID | grep -q "^${next_uid}$"; do
    next_uid=$((next_uid + 1))
done

# Create user
dscl . -create "/Users/aeon-system"
dscl . -create "/Users/aeon-system" UserShell /bin/bash
dscl . -create "/Users/aeon-system" UniqueID "$next_uid"
dscl . -create "/Users/aeon-system" PrimaryGroupID 20
dscl . -create "/Users/aeon-system" NFSHomeDirectory "/Users/aeon-system"
```

**Docker Group Addition:**
```bash
if command -v docker >/dev/null 2>&1; then
    if getent group docker >/dev/null 2>&1; then
        usermod -aG docker "$AEON_USER"
    fi
fi
```

**Special Considerations:**
- System user (not shown in login screen)
- No password (not used for interactive login)
- UID < 1000 on Linux (system account range)
- UID >= 400 on macOS (avoiding system UID ranges 0-399)

### clone_repo()

**Purpose:** Clone or update AEON repository

**Strategy:**

**If repository doesn't exist:**
```bash
git clone --depth 1 "$AEON_REPO_URL" "$REPO_DIR"
```

**If repository exists:**
```bash
cd "$REPO_DIR"
git fetch --all --prune       # Update remote references
git reset --hard origin/main  # Force local to match remote
git clean -fd                 # Remove untracked files
```

**Why Reset Instead of Pull:**
- More reliable in automation
- Handles local modifications
- Ensures clean state
- `--hard` discards local changes
- `-fd` removes untracked files and directories

**Ownership:**
```bash
chown -R "$AEON_USER:$(id -gn "$AEON_USER")" "$REPO_DIR"
```

All files owned by aeon-system user.

### run_orchestrator()

**Purpose:** Execute manifest-based installation

**Process:**
1. Setup Python virtual environment
2. Construct command with flags
3. Execute orchestrator as aeon-system user
4. Handle exit code

**Command Construction:**
```bash
local transfer_flags=""
[ "$FLAG_CLI_ENABLE" -eq 1 ] && transfer_flags="$transfer_flags --cli-enable"
[ "$FLAG_WEB_ENABLE" -eq 1 ] && transfer_flags="$transfer_flags --web-enable"
[ "$FLAG_NONINTERACTIVE" -eq 1 ] && transfer_flags="$transfer_flags --noninteractive"
```

**Execution:**
```bash
sudo -u "$AEON_USER" -H \
  AEON_ROOT="${orch_root}" \
  python3 "${orchestrator}" \
    $transfer_flags \
    --file:"${manifest_rel}" \
    --config:"${config_rel}"
```

**Environment Variables:**
- `AEON_ROOT`: Base directory for orchestrator operations
- Passed via `sudo -u` to maintain context

**Return Handling:**
```bash
if ! run_orchestrator; then
    log_error "Orchestrator execution failed"
    finalize_installation
    exit 1
fi
```

## Operating System Support

### Linux (Ubuntu/Debian)

**Tested Distributions:**
- Ubuntu 20.04 LTS (Focal Fossa)
- Ubuntu 22.04 LTS (Jammy Jellyfish)
- Debian 10 (Buster)
- Debian 11 (Bullseye)
- Raspberry Pi OS (Raspbian)

**Package Manager:** apt/apt-get

**Init System:** systemd (required)

**Installation Location:** `/opt/aeon`

**Key Differences:**
- Uses `useradd` for user creation
- Package installation via `apt-get`
- systemd service management
- Standard Linux permissions model

### macOS

**Supported Versions:**
- macOS 10.14 (Mojave) - Bash 3.2
- macOS 10.15 (Catalina) - Bash 3.2
- macOS 11 (Big Sur) - zsh default, bash available
- macOS 12 (Monterey) - zsh default
- macOS 13 (Ventura) - zsh default
- macOS 14 (Sonoma) - zsh default

**Architectures:**
- Intel (x86_64)
- Apple Silicon (ARM64/M1/M2/M3)

**Package Manager:** Homebrew (required)

**Installation Location:** `/usr/local/aeon`

**Key Differences:**
- Uses `dscl` for user creation (Directory Service Command Line)
- Package installation via Homebrew
- No systemd (uses launchd)
- Homebrew must run as non-root user
- Different UID ranges (400+ for service accounts)

**Homebrew Considerations:**
```bash
# Intel Macs
/usr/local/bin/brew

# Apple Silicon Macs  
/opt/homebrew/bin/brew
```

The script checks both locations automatically.

### WSL (Windows Subsystem for Linux)

**Supported Distributions:**
- Ubuntu 20.04 (via wsl --install)
- Ubuntu 22.04 (recommended, via wsl --install)

**Detection Method:**
```bash
grep -qi microsoft /proc/version
```

**Installation Location:** `/opt/aeon`

**Behavior:**
- Treated as Linux with minor adjustments
- Same package installation as Ubuntu
- File permissions work normally
- Network accessible from Windows host

**Limitations:**
- systemd may require configuration in WSL 2
- Docker Desktop integration recommended
- File I/O slower than native Linux

## Silent Mode

### Activation

**Automatic Detection:**
The script scans for `-n`/`--noninteractive` flag before any output:

```bash
for arg in "$@"; do
    case "$(printf '%s\n' "$arg" | tr '[:upper:]' '[:lower:]')" in
        -n|--noninteractive)
            # Immediate redirection
            TEMP_LOG="/tmp/aeon-install-$$.log"
            exec 1>"$TEMP_LOG" 2>&1
            SILENT_MODE=1
            break
            ;;
    esac
done
```

### Behavior Changes

**Console Output:**
- **Interactive**: All output to both console and log file (via `tee`)
- **Silent**: All output only to log file

**Log Format:**
- **Interactive**: Simple format
  ```
  [AEON_BASH] Installing dependencies...
  ```
- **Silent**: Includes timestamps
  ```
  [AEON_BASH][2024-01-15 14:30:22] Installing dependencies...
  ```

**User Prompts:**
- None (script never prompts for input)
- All decisions made based on detection/defaults

### Use Cases

**CI/CD Pipelines:**
```yaml
# GitLab CI
script:
  - curl -fsSL https://install.aeon.sh | sudo bash -s -- -n -c
```

**Ansible Automation:**
```yaml
- name: Install AEON silently
  shell: ./install_bash.sh --noninteractive --cli-enable
  args:
    creates: /opt/aeon/venv
```

**Cron Jobs:**
```bash
0 2 * * 0 /path/to/install_bash.sh -n -c -w 2>&1 | mail -s "AEON Update" admin@example.com
```

### Monitoring Silent Installation

**Real-time Log Viewing:**
```bash
# In another terminal
tail -f /opt/aeon/logfiles/install.bash.*.log
```

**Or watch temp log:**
```bash
# Find most recent temp log
watch -n 1 'tail -20 /tmp/aeon-install-*.log'
```

## Error Handling

### Error Modes

**Strict Mode:**
```bash
set -euo pipefail
```

- `-e`: Exit on any command failure
- `-u`: Error on undefined variables  
- `-o pipefail`: Pipelines fail if any stage fails

**Effect:**
If any command returns non-zero exit code, script immediately exits.

### Error Recovery Patterns

**Graceful Degradation:**
```bash
# chown can fail if user doesn't exist yet - that's OK
chown "$AEON_USER:..." "$path" 2>/dev/null || true
```

The `|| true` prevents exit on failure.

**Validated Operations:**
```bash
# Sudoers file must pass validation or be removed
if ! visudo -c -f "$sudoers_file" >/dev/null 2>&1; then
    log_error "Sudoers file validation failed"
    rm -f "$sudoers_file"  # Don't leave invalid file
    exit 1
fi
```

**Conditional Checks:**
```bash
# Only proceed if directory creation succeeded
mkdir -p "$logdir" 2>/dev/null || {
    log_error "Cannot create log directory: $logdir"
    return  # Exit function, not entire script
}
```

### Common Error Scenarios

**1. Insufficient Privileges**
```bash
# Symptom
mkdir: cannot create directory '/opt/aeon': Permission denied

# Cause
Not running with sudo

# Solution
sudo ./install_bash.sh
```

**2. Package Installation Failure**
```bash
# Symptom
E: Unable to locate package git

# Cause
Package lists not updated or package not available

# Solution
sudo apt-get update
sudo apt-get install git
```

**3. Git Clone Failure**
```bash
# Symptom
fatal: unable to access 'https://github.com/...': Could not resolve host

# Cause
Network connectivity or DNS issues

# Solution
# Check network
ping 8.8.8.8
# Check DNS
nslookup github.com
# Update DNS if needed
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf
```

**4. Homebrew Not Found (macOS)**
```bash
# Symptom
[ERROR] Homebrew not found. Please install Homebrew first:

# Cause
Homebrew not installed

# Solution
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**5. Python Version Mismatch**
```bash
# Symptom
ModuleNotFoundError: No module named 'venv'

# Cause
Python 3 installed but without venv module

# Solution (Ubuntu/Debian)
sudo apt-get install python3-venv
```

## Logging

### Log File Hierarchy

```
/opt/aeon/logfiles/
├── install.bash.20240115-143022.log    # Installation run 1
├── install.bash.20240115-150311.log    # Installation run 2
└── install.bash.20240116-091455.log    # Installation run 3
```

### Log File Format

**Structure:**
```
[AEON_BASH][TIMESTAMP] MESSAGE
[AEON_BASH][TIMESTAMP][ERROR] ERROR_MESSAGE
```

**Example:**
```
[AEON_BASH][2024-01-15 14:30:22] Detected OS: linux
[AEON_BASH][2024-01-15 14:30:22] AEON_ROOT: /opt/aeon
[AEON_BASH][2024-01-15 14:30:23] Logging to file: /opt/aeon/logfiles/install.bash.20240115-143022.log
[AEON_BASH][2024-01-15 14:30:25] Using curl
[AEON_BASH][2024-01-15 14:30:25] Installing git...
[AEON_BASH][2024-01-15 14:30:45] git successfully installed
[AEON_BASH][2024-01-15 14:30:45] Creating system user: aeon-system
[AEON_BASH][2024-01-15 14:30:46] System user created successfully
```

### Log Rotation

**Manual Cleanup:**
```bash
# Keep only last 7 days
find /opt/aeon/logfiles/ -name "install.bash.*.log" -mtime +7 -delete

# Keep only last 10 files
ls -t /opt/aeon/logfiles/install.bash.*.log | tail -n +11 | xargs rm -f
```

**Automated Cleanup (cron):**
```bash
# Add to /etc/cron.weekly/aeon-log-cleanup
#!/bin/bash
find /opt/aeon/logfiles/ -name "install.bash.*.log" -mtime +30 -delete
```

### Log Analysis

**Find Errors:**
```bash
grep "ERROR" /opt/aeon/logfiles/install.bash.*.log
```

**Installation Duration:**
```bash
LOG=/opt/aeon/logfiles/install.bash.20240115-143022.log
START=$(head -n 1 "$LOG" | cut -d'[' -f3 | cut -d']' -f1)
END=$(tail -n 1 "$LOG" | cut -d'[' -f3 | cut -d']' -f1)
echo "Started: $START"
echo "Ended: $END"
```

**Most Recent Installation:**
```bash
ls -t /opt/aeon/logfiles/install.bash.*.log | head -n 1 | xargs less
```

## Security

### Principle of Least Privilege

**Service Account:**
- Dedicated user (`aeon-system`)
- No password (cannot login interactively)
- System account (UID < 1000 on Linux)
- Specific sudo permissions only

**Sudo Permissions:**
Only necessary commands:
```
- Package management (apt, yum, dnf, brew)
- Service control (systemctl, service)
- Docker operations
- File ownership/permissions
- Shutdown/reboot (controlled operations)
```

**Not Permitted:**
- Shell access as other users
- Password changes
- User creation/deletion
- Unrestricted sudo access

### Sudoers Validation

**Syntax Check:**
```bash
visudo -c -f /etc/sudoers.d/aeon-system
```

If validation fails:
1. Log error
2. Remove invalid file
3. Exit installation

**File Permissions:**
```bash
chmod 0440 /etc/sudoers.d/aeon-system
```

- Owner: root
- Mode: 0440 (read-only, no write or execute)

### Secure File Creation

**Temporary Log Files:**
```bash
TEMP_LOG="/tmp/aeon-install-$$.log"
touch "$TEMP_LOG" && chmod 600 "$TEMP_LOG"
```

Mode 600 = rw-------
- Only owner can read/write
- Prevents information disclosure

**Process ID in Filename:**
`$$` ensures unique filename per process, preventing race conditions.

### Password-less Operations

**No Credentials Stored:**
- No passwords written to disk
- No API keys in scripts
- No authentication tokens

**Sudo Without Password:**
- Configured via sudoers file
- Specific commands only
- Audited via sudo logs

### Audit Trail

**Comprehensive Logging:**
- Every operation logged
- Timestamps for all actions
- Error messages preserved
- Log files protected (owned by aeon-system)

**System Logs:**
```bash
# View sudo operations
sudo journalctl -u sudo | grep aeon-system

# View system messages
sudo tail -f /var/log/syslog | grep aeon
```

## Troubleshooting

### Issue: "This script must be run as root"

**Symptoms:**
```
Error: This script must be run as root
```

**Cause:**
Not running with sudo or as root user.

**Solution:**
```bash
sudo ./install_bash.sh [options]
```

**Check Privileges:**
```bash
# Check if you have sudo
sudo -v

# Run with sudo
sudo ./install_bash.sh
```

### Issue: Package installation fails

**Symptoms:**
```
E: Unable to locate package <name>
E: Could not get lock /var/lib/dpkg/lock-frontend
```

**Solutions:**

**Update package lists:**
```bash
sudo apt-get update
```

**Fix broken packages:**
```bash
sudo apt-get install -f
sudo dpkg --configure -a
```

**Kill blocking processes:**
```bash
sudo killall apt apt-get
sudo rm /var/lib/apt/lists/lock
sudo rm /var/cache/apt/archives/lock
sudo rm /var/lib/dpkg/lock*
```

### Issue: Git clone fails

**Symptoms:**
```
fatal: unable to access 'https://github.com/conceptixx/AEON.git'
fatal: could not resolve host
```

**Diagnosis:**
```bash
# Test connectivity
ping github.com

# Test DNS
nslookup github.com

# Test HTTPS
curl -I https://github.com
```

**Solutions:**

**DNS Issues:**
```bash
# Use Google DNS
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
echo "nameserver 8.8.4.4" | sudo tee -a /etc/resolv.conf
```

**Proxy Configuration:**
```bash
# Set proxy
export https_proxy=http://proxy.company.com:8080
export http_proxy=http://proxy.company.com:8080

# Run with preserved environment
sudo -E ./install_bash.sh
```

**Firewall:**
```bash
# Allow HTTPS
sudo ufw allow 443/tcp
```

### Issue: Python venv creation fails

**Symptoms:**
```
The virtual environment was not created successfully because ensurepip is not available
```

**Cause:**
Python3 installed without venv module.

**Solution (Ubuntu/Debian):**
```bash
sudo apt-get install python3-venv python3-pip
```

**Solution (macOS):**
```bash
brew install python@3.11
```

### Issue: Homebrew user not found (macOS)

**Symptoms:**
```
[ERROR] Cannot determine non-root user for Homebrew on macOS
```

**Cause:**
Script cannot identify non-root user for Homebrew.

**Solution:**
Set SUDO_USER manually:
```bash
export SUDO_USER=$(whoami)
sudo -E ./install_bash.sh
```

### Issue: Orchestrator execution fails

**Symptoms:**
```
[ERROR] Orchestrator execution failed
[ERROR] Orchestrator not found at: /opt/aeon/tmp/repo/library/orchestrator/orchestrator.json.py
```

**Diagnosis:**
```bash
# Check repository
ls -la /opt/aeon/tmp/repo/

# Check orchestrator
ls -la /opt/aeon/tmp/repo/library/orchestrator/

# Check manifest
ls -la /opt/aeon/tmp/repo/manifest/
```

**Solutions:**

**Repository incomplete:**
```bash
# Remove and re-clone
sudo rm -rf /opt/aeon/tmp/repo
sudo -u aeon-system git clone https://github.com/conceptixx/AEON.git /opt/aeon/tmp/repo
```

**Python dependencies:**
```bash
# Check venv
/opt/aeon/venv/bin/python --version
/opt/aeon/venv/bin/pip list

# Reinstall dependencies
sudo -u aeon-system /opt/aeon/venv/bin/pip install -r /opt/aeon/tmp/repo/requirements.txt
```

### Issue: Permission denied errors

**Symptoms:**
```
chown: changing ownership of '/opt/aeon': Operation not permitted
mkdir: cannot create directory '/opt/aeon': Permission denied
```

**Cause:**
Insufficient privileges or incorrect file ownership.

**Solutions:**

**Ensure sudo:**
```bash
sudo ./install_bash.sh
```

**Fix ownership:**
```bash
sudo chown -R root:root /opt/aeon
sudo chmod 755 /opt/aeon
```

**Check SELinux (if applicable):**
```bash
# Check status
getenforce

# Temporarily disable
sudo setenforce 0

# Permanent (not recommended for production)
sudo vi /etc/selinux/config
# Set: SELINUX=permissive
```

### Debugging Mode

**Enable verbose output:**

Edit script, add after shebang:
```bash
set -x  # Enable command tracing
```

**Run with bash -x:**
```bash
sudo bash -x ./install_bash.sh
```

**Check specific sections:**
```bash
# Test OS detection
bash -c 'source ./install_bash.sh; detect_os; echo OS=$OS_TYPE ROOT=$AEON_ROOT'

# Test package installation (dry run)
bash -c 'DRY_RUN=1 source ./install_bash.sh; install_always_tools'
```

## Advanced Topics

### Custom Installation Path

**Default Paths:**
- Linux/WSL: `/opt/aeon`
- macOS: `/usr/local/aeon`

**To Change:**

Edit the script before running:
```bash
# Find this section (around line 190):
case "$uname_s" in
    Linux*)
        AEON_ROOT="/opt/aeon"      # Change this
        ;;
    Darwin*)
        AEON_ROOT="/usr/local/aeon"  # Or this
        ;;
esac
```

**Considerations:**
- Must have write permissions
- Sudoers paths may need adjustment
- Update orchestrator AEON_ROOT environment variable

### Running Orchestrator Separately

After installation, you can run orchestrator manually:

```bash
# Switch to aeon-system user
sudo -u aeon-system -i

# Activate venv
source /opt/aeon/venv/bin/activate

# Run orchestrator
AEON_ROOT=/opt/aeon python3 \
  /opt/aeon/tmp/repo/library/orchestrator/orchestrator.json.py \
  --file:/opt/aeon/manifest/custom-manifest.json \
  --config:/opt/aeon/manifest/config/manifest.config.cursed.json
```

### Docker Mode (Alternative Orchestrator Execution)

**Enable Docker Mode:**

Edit script:
```bash
AEON_ORCH_MODE="docker"  # Change from "native"
```

**Implementation:**
```bash
docker run --rm \
  -v /opt/aeon:/opt/aeon \
  -e AEON_ROOT=/opt/aeon \
  aeon/orchestrator:latest \
  python3 /opt/aeon/library/orchestrator/orchestrator.json.py \
  --file:/manifest/manifest.install.json
```

**When to Use:**
- Python version conflicts
- Isolated execution environment
- Consistent environment across systems

### Unattended Installation

**Complete Automation:**
```bash
#!/bin/bash
# Complete AEON installation script

set -e

# Download installer
curl -fsSL https://raw.githubusercontent.com/conceptixx/AEON/main/install.bash.sh \
  -o /tmp/install_bash.sh

chmod +x /tmp/install_bash.sh

# Run silently
/tmp/install_bash.sh --cli-enable --web-enable --noninteractive

# Verify installation
if [ -d /opt/aeon/venv ]; then
    echo "AEON installed successfully"
    
    # Post-installation tasks
    systemctl enable aeon-service  # If service file exists
    systemctl start aeon-service
else
    echo "AEON installation failed"
    exit 1
fi
```

### Multi-Instance Installation

**Not Officially Supported**, but possible with modifications:

```bash
# Create separate installations
AEON_ROOT=/opt/aeon-prod ./install_bash.sh
AEON_ROOT=/opt/aeon-dev ./install_bash.sh

# Use different users
AEON_USER=aeon-prod ./install_bash.sh
AEON_USER=aeon-dev ./install_bash.sh
```

**Challenges:**
- Sudoers conflicts
- Port conflicts (web interface)
- Shared system resources

### Integration with Configuration Management

**Ansible:**
```yaml
---
- name: Install AEON
  hosts: aeon_servers
  become: yes
  
  tasks:
    - name: Download AEON installer
      get_url:
        url: https://raw.githubusercontent.com/conceptixx/AEON/main/install.bash.sh
        dest: /tmp/install_bash.sh
        mode: '0755'
    
    - name: Run AEON installer
      command: /tmp/install_bash.sh --cli-enable --noninteractive
      args:
        creates: /opt/aeon/venv
      
    - name: Verify installation
      stat:
        path: /opt/aeon/venv/bin/python
      register: aeon_venv
      
    - name: Check installation
      fail:
        msg: "AEON installation failed"
      when: not aeon_venv.stat.exists
```

**Puppet:**
```puppet
class aeon {
  exec { 'download_aeon_installer':
    command => '/usr/bin/curl -fsSL https://raw.githubusercontent.com/conceptixx/AEON/main/install.bash.sh -o /tmp/install_bash.sh',
    creates => '/opt/aeon/venv',
  }
  
  exec { 'install_aeon':
    command => '/bin/bash /tmp/install_bash.sh --cli-enable --noninteractive',
    require => Exec['download_aeon_installer'],
    creates => '/opt/aeon/venv',
  }
}
```

### Health Checks

**Post-Installation Validation:**
```bash
#!/bin/bash
# AEON Installation Health Check

echo "Checking AEON installation..."

# Check directory structure
for dir in library manifest logfiles tmp; do
    if [ ! -d "/opt/aeon/$dir" ]; then
        echo "❌ Missing directory: $dir"
        exit 1
    fi
done
echo "✅ Directory structure OK"

# Check user
if ! id aeon-system >/dev/null 2>&1; then
    echo "❌ System user not found"
    exit 1
fi
echo "✅ System user OK"

# Check Python venv
if [ ! -f "/opt/aeon/venv/bin/python" ]; then
    echo "❌ Python venv not found"
    exit 1
fi
echo "✅ Python venv OK"

# Check repository
if [ ! -d "/opt/aeon/tmp/repo/.git" ]; then
    echo "❌ Repository not cloned"
    exit 1
fi
echo "✅ Repository OK"

# Check sudoers
if [ ! -f "/etc/sudoers.d/aeon-system" ]; then
    echo "❌ Sudoers not configured"
    exit 1
fi
echo "✅ Sudoers OK"

# Check permissions
if [ "$(stat -c %U /opt/aeon)" != "aeon-system" ]; then
    echo "❌ Incorrect ownership"
    exit 1
fi
echo "✅ Permissions OK"

echo "✅ All health checks passed!"
```

## See Also

- **install.sh Documentation** - Bootstrap installer guide
- **Orchestrator Documentation** - Manifest-based installation system
- **AEON Architecture** - System design and components
- **Security Guide** - Best practices and hardening
- **API Documentation** - AEON REST API reference

## Contributing

Improvements and bug fixes welcome!

1. Fork the repository
2. Create feature branch
3. Add tests for changes
4. Update documentation
5. Submit pull request

## License

Part of the AEON project. See repository for license details.
