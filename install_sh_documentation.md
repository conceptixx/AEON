# AEON Bootstrap Installer (install.sh) - Documentation

## Overview

`install.sh` is the minimal bootstrap script that serves as the entry point for AEON installation. Its primary responsibility is to detect the operating system, ensure required download tools are available, and delegate the actual installation to the appropriate platform-specific installer.

## Table of Contents

- [Purpose](#purpose)
- [Architecture](#architecture)
- [Usage](#usage)
- [Command-Line Options](#command-line-options)
- [Installation Flow](#installation-flow)
- [Operating System Support](#operating-system-support)
- [Error Handling](#error-handling)
- [Exit Codes](#exit-codes)
- [Technical Details](#technical-details)
- [Troubleshooting](#troubleshooting)

## Purpose

The bootstrap installer acts as a **platform-agnostic entry point** with these key responsibilities:

1. **OS Detection** - Identify Linux, macOS, or Windows environment
2. **Tool Verification** - Ensure curl or wget is available for downloads
3. **Delegation** - Download and execute the appropriate platform-specific installer
4. **Windows Handling** - Special case for Windows, delegates to WSL (Windows Subsystem for Linux)

## Architecture

```
install.sh (Bootstrap)
    │
    ├──> Linux/macOS: Downloads install.bash.sh and executes it
    │
    └──> Windows: Ensures WSL is installed, then executes in WSL
```

### Design Philosophy

- **Minimal footprint** - Does not install AEON itself, only bootstraps the process
- **Fail-fast** - Validates requirements before proceeding
- **Platform-aware** - Adapts behavior based on detected OS
- **Idempotent** - Safe to run multiple times

## Usage

### Basic Installation

```bash
# Download and run (one-liner from GitHub)
bash <(curl -fsSL https://raw.githubusercontent.com/conceptixx/AEON/main/install.sh)

# Or download first, then execute
curl -fsSL https://raw.githubusercontent.com/conceptixx/AEON/main/install.sh -o install.sh
chmod +x install.sh
sudo ./install.sh
```

### With Options

```bash
# Enable CLI mode
sudo ./install.sh --enable-cli

# Enable both CLI and Web modes
sudo ./install.sh --enable-cli --enable-web

# Silent/non-interactive mode (for automation)
sudo ./install.sh --noninteractive

# All options combined
sudo ./install.sh -c -w -n
```

## Command-Line Options

| Flag | Aliases | Description | Use Case |
|------|---------|-------------|----------|
| `-c` | `--cli-enable`, `--enable-cli` | Enable CLI mode | For command-line interface users |
| `-w` | `--web-enable`, `--enable-web` | Enable Web interface | For browser-based access |
| `-n` | `--noninteractive` | Silent mode | CI/CD pipelines, automated deployments |

### Flag Details

#### CLI Enable (`-c`)
- Enables command-line interface features
- Required for terminal-based interaction with AEON
- Can be combined with web mode

#### Web Enable (`-w`)
- Enables web interface components
- Allows browser-based access to AEON
- Can be combined with CLI mode

#### Noninteractive (`-n`)
- Suppresses all interactive prompts
- Redirects all output to log files only
- Essential for automation and scripting
- No console output until completion

### Flag Validation

- **Maximum**: 3 flags (one of each type)
- **Case-insensitive**: `-C` and `-c` are equivalent
- **Normalization**: All flag variants are converted to standard format
- **Unknown flags**: Cause immediate exit with error code 2

## Installation Flow

```
┌─────────────────────────────────────┐
│ 1. Parse Command-Line Arguments    │
│    - Normalize flags               │
│    - Validate flag count           │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ 2. Detect Operating System         │
│    - Check $OSTYPE variable        │
│    - Set OS_TYPE and paths         │
└──────────────┬──────────────────────┘
               │
      ┌────────┴────────┐
      │                 │
      ▼                 ▼
┌───────────┐   ┌──────────────┐
│ Windows?  │   │ Linux/macOS  │
└─────┬─────┘   └──────┬───────┘
      │                │
      ▼                ▼
┌──────────────┐  ┌────────────────────┐
│ WSL Handling │  │ 3. Ensure Download │
│ - Check WSL  │  │    Tool Available  │
│ - Install if │  │    - curl (prefer) │
│   missing    │  │    - wget (fallback)│
│ - Launch in  │  │    - Auto-install  │
│   Ubuntu     │  └────────┬───────────┘
└──────────────┘           │
                           ▼
                  ┌──────────────────────┐
                  │ 4. Download Installer│
                  │    - Create temp file│
                  │    - Download script │
                  │    - Set execute perm│
                  └────────┬─────────────┘
                           │
                           ▼
                  ┌──────────────────────┐
                  │ 5. Execute Installer │
                  │    - Run with sudo   │
                  │    - Pass flags      │
                  └──────────────────────┘
```

### Step-by-Step Breakdown

#### Step 1: Argument Parsing
- Iterates through all command-line arguments
- Normalizes each flag using `normalize_flag()` function
- Builds `NORMALIZED_FLAGS` array with validated flags
- Enforces maximum of 3 flags

#### Step 2: OS Detection
Uses bash's `$OSTYPE` variable to detect platform:

```bash
linux-gnu*    → Linux
darwin*       → macOS  
msys*|mingw*  → Windows (Git Bash/MSYS2/Cygwin)
```

Sets appropriate directories:
- Linux/WSL: `/opt/aeon`
- macOS: `/usr/local/aeon`

#### Step 3: Windows/WSL Handling

For Windows environments, the script:

1. **Check WSL Availability**
   ```powershell
   wsl.exe --version
   ```

2. **Install WSL if Missing**
   ```powershell
   Start-Process powershell -Verb RunAs -ArgumentList '-Command wsl --install -d Ubuntu-22.04'
   ```

3. **Verify Ubuntu Distribution**
   ```bash
   wsl.exe -d Ubuntu-22.04 -- bash -c "exit 0"
   ```

4. **Execute Bootstrap in WSL**
   - Constructs command string
   - Installs curl if needed
   - Downloads installer
   - Executes with all flags passed through

#### Step 4: Download Tool Verification

Priority order:
1. **curl** (preferred) - More reliable, better error handling
2. **wget** (fallback) - Universally available alternative
3. **Auto-install** - Attempts installation if neither found

Auto-installation uses platform-specific package managers:
- **Linux**: apt-get, yum, or dnf
- **macOS**: Homebrew (brew)

#### Step 5: Installer Download and Execution

```bash
# Download to temporary file
$DOWNLOADER "https://raw.githubusercontent.com/conceptixx/AEON/main/install.bash.sh" > "$TEMP_FILE"

# Copy to target directory with sudo
sudo cp "$TEMP_FILE" "/opt/aeon/tmp/install.bash.sh"

# Make executable
sudo chmod +x "/opt/aeon/tmp/install.bash.sh"

# Execute with appropriate privileges
sudo "/opt/aeon/tmp/install.bash.sh" "${NORMALIZED_FLAGS[@]}"
```

## Operating System Support

### Linux

**Supported Distributions:**
- Ubuntu 18.04+
- Debian 10+
- Raspbian
- Other systemd-based distributions

**Requirements:**
- systemd init system
- apt package manager (or manual curl/wget installation)
- sudo configured

**Installation Location:** `/opt/aeon`

### macOS

**Supported Versions:**
- macOS 10.14 (Mojave) and later
- Both Intel and Apple Silicon (M1/M2/M3)

**Requirements:**
- Homebrew package manager
- Xcode Command Line Tools

**Installation Location:** `/usr/local/aeon`

**Special Considerations:**
- Homebrew cannot run as root
- Script detects console user for brew operations
- Uses `dscl` for user management

### Windows (via WSL)

**Requirements:**
- Windows 10 version 2004+ (Build 19041+) or Windows 11
- WSL 2 capable hardware
- Administrator privileges for WSL installation

**Process:**
1. Bootstrap detects Windows environment
2. Checks for WSL installation
3. Installs WSL with Ubuntu-22.04 if missing
4. Delegates entire installation to WSL environment
5. AEON runs within WSL, not natively on Windows

**Why WSL:**
- AEON requires Unix-like environment
- Native Windows support not currently available
- WSL provides full Linux compatibility

## Error Handling

### Error Categories

#### 1. Argument Errors (Exit Code 2)
```bash
# Unknown flag
./install.sh --invalid-flag
# ERROR: Unknown flag: --invalid-flag

# Too many flags  
./install.sh -c -w -n -c
# ERROR: Maximum 3 flags allowed
```

#### 2. Runtime Errors (Exit Code 1)
```bash
# Missing download tools (and cannot install)
# [ERROR] Could not install curl/wget. Please install manually.

# WSL not available on Windows
# [ERROR] WSL not found. Manual steps required:
# 1. Open PowerShell as Administrator
# 2. Run: wsl --install -d Ubuntu-22.04
# ...

# Network connectivity issues
# (curl/wget will fail with their own error messages)
```

#### 3. Permission Errors (Exit Code 1)
```bash
# Not running with sudo
./install.sh
# Installer will fail when trying to create /opt/aeon
```

### Graceful Degradation

The script attempts to recover from errors when possible:

- **Missing curl/wget**: Attempts auto-installation via package manager
- **Permission issues**: Provides clear instructions for manual resolution
- **WSL missing**: Attempts automatic installation with admin elevation

### Cleanup on Exit

```bash
trap "rm -f '$TEMP_FILE'" EXIT
```

The trap ensures temporary files are cleaned up even if:
- Script exits normally
- Script encounters error (with `set -e`)
- User interrupts with Ctrl+C

## Exit Codes

| Code | Meaning | Common Causes |
|------|---------|---------------|
| `0` | Success | Installation completed successfully |
| `1` | Runtime Error | Network failure, permission denied, missing dependencies |
| `2` | Invalid Arguments | Unknown flag, too many flags |

### Checking Exit Status

```bash
# In shell script
./install.sh --enable-cli
if [ $? -eq 0 ]; then
    echo "Installation successful"
else
    echo "Installation failed with code $?"
fi

# With error handling
./install.sh --enable-cli || {
    echo "Installation failed!"
    exit 1
}
```

## Technical Details

### Bash Compatibility

**Minimum Version:** Bash 3.2 (macOS default)

**Compatibility Features:**
- Uses `printf` instead of `echo` for portability
- Avoids bash 4+ specific features (e.g., associative arrays)
- Uses `$(command)` instead of backticks
- Portable `command -v` for command existence checks

### Process Substitution

```bash
exec > >(tee -a "$LOG_FILE") 2>&1
```

This advanced bash feature:
- Creates a FIFO pipe to the `tee` command
- Redirects both stdout (1) and stderr (2)
- Allows simultaneous output to console and file

**Compatibility Note:** Process substitution requires bash 3.0+

### Variable Scoping

```bash
normalize_flag() {
    local flag="$1"      # Local to function
    local lower_flag     # Also local
    AEON_FLAG_N=1        # Global variable
}
```

- Use `local` for function-scoped variables
- Global variables use UPPERCASE naming convention
- Side effects (like `AEON_FLAG_N=1`) are clearly documented

### String Safety

```bash
# Safe - handles strings with spaces, special chars
lower_flag=$(printf '%s' "$flag" | tr '[:upper:]' '[:lower:]')

# Unsafe - can break with special strings
lower_flag=$(echo "$flag" | tr '[:upper:]' '[:lower:]')
```

The script consistently uses `printf` for safer string handling.

### Array Handling

```bash
# Build array
NORMALIZED_FLAGS+=("$normalized")

# Pass array to command
sudo "$INSTALLER" "${NORMALIZED_FLAGS[@]}"
```

**Quoting:** `"${array[@]}"` properly handles elements with spaces

## Troubleshooting

### Issue: "WSL not found" on Windows

**Symptoms:**
```
[WARN] WSL not found. Attempting installation...
[ERROR] Could not auto-install WSL. Manual steps required:
```

**Solution:**
1. Open PowerShell as Administrator
2. Run: `wsl --install -d Ubuntu-22.04`
3. Restart computer if prompted
4. Run install.sh again

**Alternative:** Install WSL manually through Windows Features

### Issue: "Neither curl nor wget found"

**Symptoms:**
```
[WARN] Neither curl nor wget found. Attempting installation...
[ERROR] Could not install curl/wget. Please install manually.
```

**Solutions:**

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install curl
```

**macOS without Homebrew:**
```bash
# Install Homebrew first
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Then install curl
brew install curl
```

**RHEL/CentOS:**
```bash
sudo yum install curl
# or
sudo dnf install curl
```

### Issue: "Permission denied" errors

**Symptoms:**
```
mkdir: cannot create directory '/opt/aeon': Permission denied
```

**Solution:**
Always run with sudo:
```bash
sudo ./install.sh
```

### Issue: Network connectivity problems

**Symptoms:**
- curl/wget timeouts
- "Failed to download" errors
- DNS resolution failures

**Solutions:**
1. Check internet connectivity: `ping 8.8.8.8`
2. Check DNS resolution: `nslookup raw.githubusercontent.com`
3. Try alternative DNS: `sudo vi /etc/resolv.conf` (add `nameserver 8.8.8.8`)
4. Check firewall/proxy settings
5. If behind corporate proxy, set environment variables:
   ```bash
   export http_proxy="http://proxy.company.com:8080"
   export https_proxy="http://proxy.company.com:8080"
   sudo -E ./install.sh
   ```

### Issue: Script hangs or shows no output

**Symptoms:**
- Script runs but shows nothing
- Appears frozen

**Possible Causes:**
1. Running in noninteractive mode without realizing it
2. Output redirected elsewhere
3. Waiting for user input that's not visible

**Solutions:**
1. Check if `-n` flag was accidentally used
2. Wait for completion (check log files in `/opt/aeon/logfiles/`)
3. Run in interactive mode explicitly (don't use `-n`)
4. Check for background processes: `ps aux | grep install`

### Issue: "Unknown flag" error

**Symptoms:**
```
ERROR: Unknown flag: --web
Usage: ./install.sh [-c|--cli-enable] [-w|--web-enable] [-n|--noninteractive]
```

**Solution:**
Use exact flag names (check spelling):
- ✅ Correct: `--web-enable` or `-w`
- ❌ Wrong: `--web`

### Debugging Mode

To enable detailed debugging, modify the script:

```bash
# Add after the shebang line
set -x  # Enable command tracing

# Your existing set -e
set -e
```

This will print each command before execution.

### Log File Locations

Even if installation fails, logs may be available:

**Temporary log (if AEON_ROOT not yet determined):**
```
/tmp/aeon-install-{PID}.log
```

**Final log location:**
```
/opt/aeon/logfiles/install.bash.YYYYMMDD-HHMMSS.log
```

**View logs:**
```bash
# Most recent install log
ls -lt /opt/aeon/logfiles/ | head -n 2

# View specific log
tail -f /opt/aeon/logfiles/install.bash.20240115-143022.log
```

### Getting Help

If troubleshooting doesn't resolve your issue:

1. **Check logs** - Review installation logs for detailed error messages
2. **GitHub Issues** - Search existing issues: https://github.com/conceptixx/AEON/issues
3. **Create Issue** - Provide:
   - Operating system and version
   - Full error message
   - Contents of log file
   - Steps to reproduce

## Advanced Usage

### Custom Installation Directory

Currently not supported via flags. To change installation directory:

1. Edit the script before running:
   ```bash
   # Change this line
   AEON_WORKING_DIR="/opt/aeon"
   # To your preferred location
   AEON_WORKING_DIR="/custom/path/aeon"
   ```

2. Ensure you have write permissions to the target directory

### Running Without Internet

The bootstrap script requires internet connectivity to download `install.bash.sh`. For offline installation:

1. **Download both scripts on a connected machine:**
   ```bash
   curl -O https://raw.githubusercontent.com/conceptixx/AEON/main/install.sh
   curl -O https://raw.githubusercontent.com/conceptixx/AEON/main/install.bash.sh
   ```

2. **Transfer to offline machine**

3. **Run install.bash.sh directly:**
   ```bash
   sudo ./install.bash.sh --enable-cli --enable-web
   ```

Note: The main installer (install.bash.sh) will still need internet for git clone and package installation.

### Automation Examples

**Ansible:**
```yaml
- name: Install AEON
  shell: |
    curl -fsSL https://raw.githubusercontent.com/conceptixx/AEON/main/install.sh | \
    sudo bash -s -- --enable-cli --noninteractive
  args:
    creates: /opt/aeon/venv
```

**Docker/Cloud-Init:**
```bash
#!/bin/bash
curl -fsSL https://raw.githubusercontent.com/conceptixx/AEON/main/install.sh -o /tmp/install.sh
chmod +x /tmp/install.sh
/tmp/install.sh --enable-cli --enable-web --noninteractive
```

**CI/CD Pipeline:**
```yaml
# GitHub Actions example
- name: Install AEON
  run: |
    curl -fsSL https://raw.githubusercontent.com/conceptixx/AEON/main/install.sh | \
    sudo bash -s -- -n -c
  
- name: Verify installation
  run: |
    test -d /opt/aeon || exit 1
    test -f /opt/aeon/venv/bin/python || exit 1
```

## Security Considerations

### Running Scripts from Internet

The one-liner installation downloads and executes a script:
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/conceptixx/AEON/main/install.sh)
```

**Risks:**
- Executes code directly without review
- Vulnerable to MITM attacks (mitigated by HTTPS)
- Requires trust in source repository

**Best Practices:**
1. **Review first** (recommended for production):
   ```bash
   curl -fsSL https://raw.githubusercontent.com/conceptixx/AEON/main/install.sh -o install.sh
   less install.sh  # Review the script
   chmod +x install.sh
   sudo ./install.sh
   ```

2. **Verify checksums** (if provided):
   ```bash
   sha256sum install.sh
   # Compare with published checksum
   ```

3. **Use specific commit** (instead of main branch):
   ```bash
   curl -fsSL https://raw.githubusercontent.com/conceptixx/AEON/abc123def/install.sh | sudo bash
   ```

### Sudo Usage

The script requires sudo for:
- Creating system directories (`/opt/aeon`)
- Installing packages
- Creating system user
- Modifying sudoers configuration

**Principle of Least Privilege:**
The script uses sudo only when necessary and creates a restricted service account (aeon-system) for AEON operations rather than running as root.

### File Permissions

Temporary files are created with secure permissions:
```bash
touch "$TEMP_LOG" && chmod 600 "$TEMP_LOG"
```

- `600` = rw------- (only owner can read/write)
- Prevents other users from accessing potentially sensitive log data

## See Also

- **install.bash.sh Documentation** - Main installer with detailed system setup
- **AEON Architecture Guide** - Understanding AEON components
- **Orchestrator Documentation** - How manifest-based installation works
- **Troubleshooting Guide** - Common issues and solutions

## Contributing

Found an issue or have improvement suggestions?

1. Fork the repository
2. Create a feature branch
3. Submit a pull request with your changes
4. Include tests and documentation updates

## License

AEON Bootstrap Installer is part of the AEON project. See main repository for license information.
