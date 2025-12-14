# bootstrap.sh - AEON Bootstrap Installer

## 📋 Overview

**File:** `bootstrap.sh`  
**Type:** Standalone bash script  
**Version:** 0.1.0  
**Purpose:** One-command installer that downloads and sets up AEON on the entry device

**Quick Description:**  
The bootstrap script is the **entry point** for AEON installation. It downloads all required files, sets up the directory structure, and prepares the system to run the main orchestrator (`aeon-go.sh`).

---

## 🎯 Purpose & Context

### **Why This Script Exists**

AEON needs a way for users to install the system with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/conceptixx/AEON/main/bootstrap.sh | sudo bash
```

This script:
1. **Validates** the system can run AEON (root, prerequisites)
2. **Downloads** all AEON components from GitHub
3. **Organizes** files into proper directory structure
4. **Prepares** the system to run the main orchestrator

### **Design Decisions**

- **Self-contained**: Works without any existing AEON files
- **Fallback strategy**: Tries `git clone` first, falls back to direct downloads
- **Idempotent**: Can be run multiple times safely
- **Non-destructive**: Asks before overwriting existing installations

---

## 🚀 Usage

### **Primary Usage (One-Command Install)**

```bash
curl -fsSL https://raw.githubusercontent.com/conceptixx/AEON/main/bootstrap.sh | sudo bash
```

Or with wget:

```bash
wget -qO- https://raw.githubusercontent.com/conceptixx/AEON/main/bootstrap.sh | sudo bash
```

### **Manual Download & Run**

```bash
wget https://raw.githubusercontent.com/conceptixx/AEON/main/bootstrap.sh
chmod +x bootstrap.sh
sudo ./bootstrap.sh
```

### **Exit Codes**

| Code | Meaning |
|------|---------|
| 0 | Success - AEON installed |
| 1 | Error - Not running as root |
| 0 | User cancelled reinstall |

---

## 🏗️ Architecture

### **Execution Flow**

```
User runs bootstrap.sh
    │
    ├─> print_banner()              Display AEON logo
    │
    ├─> check_root()                Verify running as root
    │                                Exit if not root
    │
    ├─> check_prerequisites()       Check if already installed
    │                                Ask user if reinstall
    │                                Remove old installation if yes
    │
    ├─> Installation Strategy:
    │   ├─> Try: install_via_git()
    │   │         ├─> Check if git available
    │   │         ├─> Install git if missing
    │   │         └─> git clone repository
    │   │
    │   └─> Fallback: install_via_download()
    │             ├─> Create directory structure
    │             ├─> Download aeon-go.sh
    │             ├─> Download lib modules (parallel.sh, etc.)
    │             ├─> Download remote scripts
    │             └─> Make all scripts executable
    │
    └─> show_next_steps()           Display completion message
                                     Show how to run aeon-go.sh
```

### **Installation Methods**

#### **Method 1: Git Clone (Preferred)**

```bash
git clone https://github.com/conceptixx/AEON.git /opt/aeon
```

**Advantages:**
- Gets entire repository with history
- Easy to update (`git pull`)
- Includes all documentation
- Preserves file permissions

#### **Method 2: Direct Download (Fallback)**

```bash
curl -fsSL $AEON_RAW/aeon-go.sh -o /opt/aeon/aeon-go.sh
curl -fsSL $AEON_RAW/lib/parallel.sh -o /opt/aeon/lib/parallel.sh
# ... repeat for each file
```

**When Used:**
- Git not available and can't be installed
- User doesn't want git dependency
- Minimal installation preferred

**Advantages:**
- No git dependency
- Smaller download (only needed files)
- Works in restricted environments

---

## 📚 Functions Reference (API)

### **print_banner()**

Displays the AEON ASCII art logo and bootstrap title.

**Type:** Display function  
**Parameters:** None  
**Returns:** None  
**Side Effects:** Clears screen, prints to stdout  

**Purpose:**  
Provides visual feedback that bootstrap is running and establishes AEON branding.

```bash
print_banner() {
    clear
    cat << 'EOF'
     █████╗ ███████╗ ██████╗ ███╗   ██╗
    ██╔══██╗██╔════╝██╔═══██╗████╗  ██║
    # ... ASCII art ...
EOF
}
```

---

### **log(level, message)**

Logs messages with appropriate color coding and formatting.

**Type:** Utility function  
**Parameters:**
- `level` - Log level: ERROR, WARN, INFO, SUCCESS, STEP
- `message` - Message to display

**Returns:** None  
**Side Effects:** Prints colored message to stdout/stderr  

**Color Coding:**
- `ERROR` - Red ❌ (outputs to stderr)
- `WARN` - Yellow ⚠️
- `INFO` - Cyan ℹ️
- `SUCCESS` - Green ✅
- `STEP` - Blue ▶

**Example:**
```bash
log INFO "Downloading AEON components..."
log SUCCESS "Installation complete"
log ERROR "Git not available"
```

---

### **check_root()**

Verifies the script is running with root privileges.

**Type:** Validation function  
**Parameters:** None  
**Returns:** None (exits on failure)  
**Exit Code:** 1 if not root  

**Purpose:**  
AEON installation requires root to:
- Install system packages
- Create `/opt/aeon` directory
- Set proper permissions

**Implementation:**
```bash
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log ERROR "This script must be run as root"
        echo ""
        echo -e "${YELLOW}Please run:${NC}"
        echo -e "  ${CYAN}curl -fsSL ... | sudo bash${NC}"
        exit 1
    fi
}
```

**Error Message:**  
If not root, displays helpful message with correct command syntax.

---

### **check_prerequisites()**

Checks if AEON is already installed and handles reinstallation.

**Type:** Validation function  
**Parameters:** None  
**Returns:** 0 on success, exits 0 if user cancels  

**Behavior:**

1. Checks if `/opt/aeon` exists
2. If exists:
   - Warns user
   - Prompts for confirmation to reinstall
   - If yes: removes existing installation
   - If no: exits gracefully
3. If not exists: continues

**Example Flow:**
```
AEON is already installed at /opt/aeon
Reinstall? [y/N] n
Installation cancelled
(exits with code 0)
```

**Implementation:**
```bash
check_prerequisites() {
    log STEP "Checking prerequisites..."
    
    if [[ -d "$INSTALL_DIR" ]]; then
        log WARN "AEON is already installed at $INSTALL_DIR"
        read -p "Reinstall? [y/N] " -n 1 -r
        echo ""
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log INFO "Installation cancelled"
            exit 0
        fi
        
        log WARN "Removing existing installation..."
        rm -rf "$INSTALL_DIR"
    fi
    
    log SUCCESS "Prerequisites checked"
}
```

---

### **install_via_git()**

Installs AEON by cloning the GitHub repository.

**Type:** Installation function  
**Parameters:** None  
**Returns:** None  
**Side Effects:** 
- Installs git if missing
- Clones repository to `/opt/aeon`

**Prerequisites:**
- Root access
- Internet connectivity

**Steps:**
1. Check if git is installed
2. If not installed:
   - Warn user
   - Install git via apt-get
3. Clone repository:
   ```bash
   git clone --quiet "$AEON_REPO" "$INSTALL_DIR"
   ```
4. Log success

**Configuration:**
```bash
AEON_REPO="https://github.com/conceptixx/AEON.git"
INSTALL_DIR="/opt/aeon"
```

**Advantages:**
- Complete repository with history
- Easy updates via `git pull`
- All documentation included

---

### **install_via_download()**

Installs AEON by downloading individual files directly.

**Type:** Installation function  
**Parameters:** None  
**Returns:** None  
**Side Effects:**
- Creates directory structure
- Downloads individual files via curl
- Sets executable permissions

**Used When:**
- Git not available
- Minimal installation preferred
- Restricted environment

**Directory Structure Created:**
```
/opt/aeon/
├── lib/
├── remote/
├── config/
├── data/
├── secrets/
├── logs/
├── reports/
├── docs/
└── examples/
```

**Files Downloaded:**

**Main Script:**
- `aeon-go.sh`

**Library Modules:**
- `lib/parallel.sh`
- `lib/aeon_user.sh`
- `lib/scoring.py`
- `lib/02-discovery.sh`
- `lib/06-reboot.sh`
- `lib/07-swarm.sh`
- `lib/08-report.sh`

**Remote Scripts:**
- `remote/install_dependencies.sh`
- `remote/detect_hardware.sh`

**Download Pattern:**
```bash
curl -fsSL "$AEON_RAW/path/to/file" -o "$INSTALL_DIR/path/to/file"
```

Where:
```bash
AEON_RAW="https://raw.githubusercontent.com/conceptixx/AEON/main"
```

**Post-Download:**
```bash
chmod +x "$INSTALL_DIR"/*.sh
chmod +x "$INSTALL_DIR"/lib/*.sh
chmod +x "$INSTALL_DIR"/lib/*.py
chmod +x "$INSTALL_DIR"/remote/*.sh
```

**Error Handling:**
- Ensures curl/wget available
- Creates all directories first
- Makes all scripts executable

---

### **perform_installation()**

Main installation orchestrator - tries git first, falls back to download.

**Type:** Orchestration function  
**Parameters:** None  
**Returns:** None  
**Side Effects:** Installs AEON to `/opt/aeon`

**Logic Flow:**
```bash
perform_installation() {
    log STEP "Installing AEON..."
    echo ""
    
    # Try git first
    if command -v git &>/dev/null; then
        install_via_git
    else
        log WARN "Git not available, using direct download"
        install_via_download
    fi
    
    # Set permissions
    chmod 755 "$INSTALL_DIR"
    
    log SUCCESS "AEON installed to $INSTALL_DIR"
}
```

**Decision Tree:**
```
Is git available?
├─ Yes → install_via_git()
└─ No  → install_via_download()
```

---

### **show_next_steps()**

Displays completion message with next steps for the user.

**Type:** Display function  
**Parameters:** None  
**Returns:** None  
**Side Effects:** Prints to stdout

**Information Shown:**

1. **Completion Banner**
   - Success message
   - Visual separator

2. **Installation Details**
   - Location: `/opt/aeon`
   - Main script: `aeon-go.sh`

3. **Next Steps**
   - How to start AEON installation
   - Alternative run methods

4. **Requirements Reminder**
   - Minimum 3 Raspberry Pis
   - SSH enabled on all devices
   - Network connectivity

5. **Documentation Links**
   - GitHub repository
   - Local docs location

**Example Output:**
```
════════════════════════════════════════════════════════
  ✅ AEON Bootstrap Complete!
════════════════════════════════════════════════════════

Installation Details:
  • Location: /opt/aeon
  • Main Script: /opt/aeon/aeon-go.sh

Next Steps:

  1. Start AEON Installation:
     cd /opt/aeon
     sudo bash aeon-go.sh

  2. Or run directly:
     sudo bash /opt/aeon/aeon-go.sh

Requirements:
  • Minimum 3 Raspberry Pis on local network
  • SSH enabled on all devices
  • Network connectivity between devices

Documentation:
  • GitHub: https://github.com/conceptixx/AEON
  • Local Docs: /opt/aeon/docs/
```

---

### **main()**

Main execution function - orchestrates the bootstrap process.

**Type:** Entry point function  
**Parameters:** None  
**Returns:** None  

**Execution Order:**
```bash
main() {
    print_banner              # Display logo
    check_root                # Verify root privileges
    check_prerequisites       # Check existing installation
    perform_installation      # Install AEON
    show_next_steps          # Display next steps
}

main "$@"
```

**Error Handling:**
- Exits on root check failure
- Exits on user cancellation
- Continues through installation

---

## 🔗 Dependencies

### **System Requirements**

**Operating System:**
- Linux (Ubuntu 20.04+, Debian 10+, Raspberry Pi OS)
- macOS (with bash 4+)
- Windows WSL2

**Bash Version:**
- Minimum: bash 4.0
- Recommended: bash 5.0+

**Required Commands:**
```bash
curl      # For downloading files
wget      # Alternative to curl
git       # Optional, for git clone method
```

### **Network Requirements**

- **Internet connectivity** - To download from GitHub
- **HTTPS access** - To raw.githubusercontent.com
- **DNS resolution** - To resolve github.com

### **Permissions**

- **Root access required** - Must run with sudo
- **Write access to `/opt`** - Creates `/opt/aeon` directory

### **Automatic Dependencies**

The script automatically installs:
- `curl` - If not present and wget available
- `wget` - If not present and curl available
- `git` - If not present (for git clone method)

---

## 🔌 Integration Points

### **Called By**

**User** → `bootstrap.sh` (one-command install)

```bash
curl -fsSL https://raw.githubusercontent.com/.../bootstrap.sh | sudo bash
```

### **Calls / Downloads**

**GitHub Repository:**
- `https://github.com/conceptixx/AEON.git` (via git clone)
- `https://raw.githubusercontent.com/conceptixx/AEON/main/...` (direct download)

**Files Downloaded:**
1. `aeon-go.sh` - Main orchestrator
2. `lib/*.sh` - Library modules
3. `lib/*.py` - Python modules
4. `remote/*.sh` - Remote execution scripts

### **Prepares For**

**Next Step:** User runs `aeon-go.sh`

```bash
cd /opt/aeon
sudo bash aeon-go.sh
```

### **Integration Diagram**

```
┌─────────────────────┐
│   User Terminal     │
│   curl ... | bash   │
└──────────┬──────────┘
           │
           v
┌─────────────────────┐
│   bootstrap.sh      │ ← This Script
│   ├─ Download files │
│   └─ Setup dirs     │
└──────────┬──────────┘
           │
           v
┌─────────────────────┐
│  /opt/aeon/         │
│  ├─ aeon-go.sh      │
│  ├─ lib/            │
│  ├─ remote/         │
│  └─ docs/           │
└──────────┬──────────┘
           │
           v
┌─────────────────────┐
│   User runs         │
│   aeon-go.sh        │
└─────────────────────┘
```

---

## ⚠️ Error Handling

### **Exit Codes**

| Code | Condition | Meaning |
|------|-----------|---------|
| 0 | Normal | Installation successful |
| 0 | User cancel | User chose not to reinstall |
| 1 | Not root | Script not run with sudo |

### **Error Scenarios**

#### **Scenario 1: Not Running as Root**

```
❌ This script must be run as root

Please run:
  curl -fsSL https://raw.githubusercontent.com/.../bootstrap.sh | sudo bash
```

**Recovery:** Run with sudo

---

#### **Scenario 2: Existing Installation**

```
⚠️  AEON is already installed at /opt/aeon
Reinstall? [y/N]
```

**Options:**
- `y` - Removes old installation, proceeds
- `n` - Exits gracefully

---

#### **Scenario 3: No Internet Connection**

**Symptoms:**
- curl/wget download failures
- Git clone timeout

**Manual Recovery:**
```bash
# Check internet
ping -c 1 github.com

# Check DNS
nslookup github.com

# Try alternative download
wget https://github.com/conceptixx/AEON/archive/refs/heads/main.zip
```

---

#### **Scenario 4: GitHub Unavailable**

**Alternative:** Manual installation

```bash
# Download release archive
wget https://github.com/conceptixx/AEON/releases/latest/download/aeon.tar.gz

# Extract
tar -xzf aeon.tar.gz -C /opt/

# Rename
mv /opt/AEON-main /opt/aeon
```

---

## 📖 Examples

### **Example 1: Standard Installation**

```bash
# One-command install
curl -fsSL https://raw.githubusercontent.com/conceptixx/AEON/main/bootstrap.sh | sudo bash

# Output:
     █████╗ ███████╗ ██████╗ ███╗   ██╗
    ██╔══██╗██╔════╝██╔═══██╗████╗  ██║
    ...
    
▶ Checking prerequisites...
✅ Prerequisites checked
▶ Installing AEON...
▶ Cloning AEON repository...
✅ Repository cloned
✅ AEON installed to /opt/aeon

════════════════════════════════════════════════════════
  ✅ AEON Bootstrap Complete!
════════════════════════════════════════════════════════
```

---

### **Example 2: Reinstallation**

```bash
$ curl -fsSL https://raw.githubusercontent.com/.../bootstrap.sh | sudo bash

▶ Checking prerequisites...
⚠️  AEON is already installed at /opt/aeon
Reinstall? [y/N] y

⚠️  Removing existing installation...
▶ Installing AEON...
✅ AEON installed to /opt/aeon
```

---

### **Example 3: Manual Download & Run**

```bash
# Download bootstrap
wget https://raw.githubusercontent.com/conceptixx/AEON/main/bootstrap.sh

# Make executable
chmod +x bootstrap.sh

# Run
sudo ./bootstrap.sh
```

---

### **Example 4: Without Git (Fallback)**

```bash
# Remove git (for testing)
sudo apt-get remove git

# Run bootstrap
curl -fsSL https://raw.githubusercontent.com/.../bootstrap.sh | sudo bash

# Output:
⚠️  Git not available, using direct download
▶ Downloading AEON components...
✅ Components downloaded
```

---

## 🔧 Troubleshooting

### **Issue: Permission Denied**

```
curl: (23) Failed writing body
```

**Cause:** Not running as root  
**Solution:** Add `sudo`

```bash
curl -fsSL https://raw.githubusercontent.com/.../bootstrap.sh | sudo bash
```

---

### **Issue: curl: command not found**

**Solution:** Use wget instead

```bash
wget -qO- https://raw.githubusercontent.com/.../bootstrap.sh | sudo bash
```

Or install curl:
```bash
sudo apt-get update
sudo apt-get install curl
```

---

### **Issue: /opt read-only**

**Cause:** Filesystem mounted read-only  
**Check:**
```bash
mount | grep /opt
```

**Solution:** Remount as read-write
```bash
sudo mount -o remount,rw /opt
```

---

### **Issue: Download Timeout**

**Symptoms:**
```
curl: (28) Operation timed out after 30000 milliseconds
```

**Solutions:**

1. Check internet:
   ```bash
   ping -c 1 8.8.8.8
   ```

2. Try alternate method:
   ```bash
   git clone https://github.com/conceptixx/AEON.git /opt/aeon
   ```

3. Use proxy (if behind firewall):
   ```bash
   export https_proxy=http://proxy.example.com:8080
   curl -fsSL ... | sudo bash
   ```

---

## 📝 Configuration

### **Constants**

```bash
AEON_REPO="https://github.com/conceptixx/AEON.git"
AEON_RAW="https://raw.githubusercontent.com/conceptixx/AEON/main"
INSTALL_DIR="/opt/aeon"
```

**Customization:**

To install to different location:
```bash
# Edit bootstrap.sh
INSTALL_DIR="/custom/path/aeon"
```

---

## 🎯 Design Philosophy

### **Principles**

1. **Simplicity** - One command to get started
2. **Robustness** - Handles failures gracefully
3. **Idempotency** - Safe to run multiple times
4. **Transparency** - Shows what it's doing
5. **Helpful** - Provides next steps

### **User Experience**

- **Minimal interaction** - Auto-detects and handles most scenarios
- **Clear feedback** - Colored output shows progress
- **Helpful errors** - Shows exactly what went wrong and how to fix
- **Next steps** - Never leaves user wondering "what now?"

---

## 📊 Statistics

```
File: bootstrap.sh
Lines of Code: ~200
Functions: 6
Exit Points: 2
External Commands: curl, wget, git, apt-get
Supported OS: Linux, macOS, Windows WSL
```

---

## 🔄 Version History

**0.1.0** (Current)
- Initial release
- Git clone support
- Direct download fallback
- Prerequisite checking
- Next steps display

---

## 📞 Related Documentation

- [aeon-go.sh Documentation](./aeon-go.sh.md) - Main orchestrator
- [AEON Architecture](../docs/architecture/OVERVIEW.md) - System design
- [Quick Start Guide](../docs/installation/QUICK_START.md) - Getting started

---

**This documentation is for AEON version 0.1.0**  
**Last Updated:** 2025-12-14  
**Maintained by:** AEON Development Team
