![AEON Banner](.github/assets/aeon_banner_v2_2400x600.png)

# common.sh - AEON Core Utilities Module

## 📋 Overview

**File:** `lib/common.sh`  
**Type:** Library module (sourced, not executed)  
**Version:** 0.1.0  
**Purpose:** Foundation module providing shared utilities for all AEON modules

**Quick Description:**  
The common utilities module is the **foundation** of AEON. It provides logging, color definitions, display functions, and utility functions used throughout the entire system. Every other module depends on this.

---

## 🎯 Purpose & Context

### **Why This Module Exists**

Without `common.sh`, every module would need to:
- Define its own color codes (RED, GREEN, etc.)
- Implement its own logging function
- Duplicate utility functions (command_exists, ensure_directory, etc.)
- Repeat box-drawing and formatting code

This module eliminates all that duplication by providing a **single source of truth** for common functionality.

### **Design Philosophy**

1. **Zero Dependencies** - This is the base module, it depends on nothing
2. **Comprehensive** - Provides everything modules commonly need
3. **Safe** - Prevents double-sourcing, handles errors gracefully
4. **Extensible** - Easy to add new utility functions

---

## 🚀 Usage

### **Primary Usage (Sourced by Other Modules)**

```bash
#!/bin/bash

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || {
    echo "ERROR: Failed to source common.sh" >&2
    exit 1
}

# Now you can use all common functions
log INFO "Starting process..."
print_header "Phase 1: Initialization"

if command_exists docker; then
    log SUCCESS "Docker is available"
fi
```

### **Standalone Testing**

```bash
# Test common utilities
source /opt/aeon/lib/common.sh

# Test logging
log INFO "This is an info message"
log SUCCESS "This is a success message"
log ERROR "This is an error message"

# Test utilities
if command_exists bash; then
    echo "Bash is installed"
fi

# Test display
print_header "Test Header"
print_banner
```

---

## 🏗️ Architecture

### **Module Structure**

```
common.sh
├── Double-sourcing prevention
├── Constants
│   ├── Version info
│   ├── Directory paths
│   ├── Color codes (ANSI)
│   └── Box drawing characters (UTF-8)
│
├── Logging Functions
│   ├── log()
│   ├── log_debug()
│   └── log_to_file()
│
├── Display Functions
│   ├── print_header()
│   ├── print_banner()
│   ├── print_line()
│   └── print_box()
│
├── Utility Functions
│   ├── command_exists()
│   ├── ensure_directory()
│   ├── get_timestamp()
│   ├── get_script_dir()
│   ├── join_array()
│   ├── trim()
│   ├── to_lower()
│   ├── to_upper()
│   ├── contains()
│   ├── is_root()
│   ├── confirm()
│   └── retry()
│
├── File Utilities
│   ├── file_exists()
│   ├── dir_exists()
│   ├── is_writable()
│   └── get_file_size()
│
├── JSON Utilities
│   ├── json_get()
│   └── json_validate()
│
└── Initialization
    └── Export functions for subshells
```

---

## 📚 Constants Reference

### **Version Information**

```bash
readonly AEON_VERSION="0.1.0"
```

Current AEON version number.

---

### **Directory Paths**

All directory constants can be overridden via environment variables:

```bash
: "${AEON_DIR:=/opt/aeon}"
readonly AEON_DIR

readonly LIB_DIR="$AEON_DIR/lib"
readonly REMOTE_DIR="$AEON_DIR/remote"
readonly CONFIG_DIR="$AEON_DIR/config"
readonly DATA_DIR="$AEON_DIR/data"
readonly SECRETS_DIR="$AEON_DIR/secrets"
readonly LOG_DIR="$AEON_DIR/logs"
readonly REPORT_DIR="$AEON_DIR/reports"
```

**Usage:**
```bash
# Default location
source /opt/aeon/lib/common.sh

# Custom location
AEON_DIR=/custom/path source /custom/path/lib/common.sh
```

---

### **Color Codes (ANSI Escape Sequences)**

```bash
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly WHITE='\033[0;37m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly UNDERLINE='\033[4m'
readonly NC='\033[0m'  # No Color / Reset
```

**Usage:**
```bash
echo -e "${RED}Error message${NC}"
echo -e "${GREEN}Success message${NC}"
echo -e "${BOLD}${CYAN}Important info${NC}"
```

---

### **Box Drawing Characters (UTF-8)**

```bash
readonly BOX_H='═'      # Horizontal line
readonly BOX_V='║'      # Vertical line
readonly BOX_TL='╔'     # Top-left corner
readonly BOX_TR='╗'     # Top-right corner
readonly BOX_BL='╚'     # Bottom-left corner
readonly BOX_BR='╝'     # Bottom-right corner
```

**Usage:**
```bash
echo "${BOX_TL}${BOX_H}${BOX_H}${BOX_H}${BOX_TR}"
echo "${BOX_V} Text ${BOX_V}"
echo "${BOX_BL}${BOX_H}${BOX_H}${BOX_H}${BOX_BR}"
```

**Output:**
```
╔═══╗
║ Text ║
╚═══╝
```

---

### **Icons/Emoji**

```bash
readonly ICON_SUCCESS='✅'
readonly ICON_ERROR='❌'
readonly ICON_WARNING='⚠️ '
readonly ICON_INFO='ℹ️ '
readonly ICON_STEP='▶'
readonly ICON_BULLET='•'
readonly ICON_MANAGER='🔷'
readonly ICON_WORKER='🔶'
readonly ICON_LEADER='⭐'
```

---

## 📚 Functions Reference

### **Logging Functions**

#### **log(level, message)**

Unified logging function with color coding and file output.

**Type:** Logging function  
**Parameters:**
- `level` - Log level: ERROR, WARN, INFO, SUCCESS, STEP, DEBUG
- `message` - Message text (supports multiple arguments)

**Returns:** None  
**Side Effects:**
- Prints to stdout (INFO, SUCCESS, STEP, DEBUG)
- Prints to stderr (ERROR, WARN)
- Appends to `$AEON_LOG_FILE` if writable

**Color Mapping:**
- `ERROR` → Red with ❌ (stderr)
- `WARN` → Yellow with ⚠️
- `INFO` → Cyan with ℹ️
- `SUCCESS` → Green with ✅
- `STEP` → Bold Blue with ▶
- `DEBUG` → Dim gray (only if `AEON_DEBUG=1`)

**Example:**
```bash
log INFO "Starting installation"
log SUCCESS "Installation complete"
log ERROR "Connection failed"
log WARN "Low disk space"
log STEP "Phase 1: Initialization"
log DEBUG "Variable value: $var"
```

**Output:**
```
ℹ️  Starting installation
✅ Installation complete
❌ Connection failed
⚠️  Low disk space
▶ Phase 1: Initialization
```

---

#### **log_debug(message)**

Convenience function for debug logging.

**Parameters:**
- `message` - Debug message

**Behavior:**
- Only logs if `AEON_DEBUG=1` environment variable is set
- Uses dim color to distinguish from normal logs

**Example:**
```bash
AEON_DEBUG=1 ./script.sh  # Debug messages shown
./script.sh                # Debug messages hidden
```

---

#### **log_to_file(level, message)**

Log to file only, no console output.

**Parameters:**
- `level` - Log level
- `message` - Message text

**Use Case:**  
Background processes, verbose logging that shouldn't clutter console.

**Example:**
```bash
log_to_file INFO "Background task started"
log_to_file DEBUG "Processing record $i"
```

---

### **Display Functions**

#### **print_header(text)**

Print a formatted section header with box drawing.

**Parameters:**
- `text` - Header text

**Output Width:** 60 characters

**Example:**
```bash
print_header "Phase 1: Initialization"
```

**Output:**
```
╔════════════════════════════════════════════════════════════╗
║  Phase 1: Initialization                                   ║
╚════════════════════════════════════════════════════════════╝
```

---

#### **print_banner()**

Display AEON ASCII art banner with version information.

**Parameters:** None  
**Side Effects:** Clears screen first

**Example:**
```bash
print_banner
```

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

╔════════════════════════════════════════════════════════════╗
║  Version: 0.1.0                                            ║
║  Installation Directory: /opt/aeon                         ║
╚════════════════════════════════════════════════════════════╝
```

---

#### **print_line(char, width)**

Print a horizontal line.

**Parameters:**
- `char` - Character to use (default: `═`)
- `width` - Line width (default: 60)

**Example:**
```bash
print_line           # Uses default ═
print_line "─" 80    # Single-line, 80 chars wide
print_line "=" 40    # ASCII, 40 chars wide
```

---

#### **print_box(lines...)**

Print text in a box.

**Parameters:**
- `lines` - Multiple line arguments

**Example:**
```bash
print_box "Line 1" "Line 2" "Line 3"
```

**Output:**
```
╔═══════╗
║ Line 1  ║
║ Line 2  ║
║ Line 3  ║
╚═══════╝
```

---

### **Utility Functions**

#### **command_exists(command)**

Check if a command exists in PATH.

**Parameters:**
- `command` - Command name to check

**Returns:**
- 0 if command exists
- 1 if command does not exist

**Example:**
```bash
if command_exists docker; then
    log SUCCESS "Docker is installed"
else
    log ERROR "Docker not found"
fi
```

**Why This Instead of `which`:**
- More reliable across different systems
- Works with shell functions and aliases
- POSIX compliant

---

#### **ensure_directory(path, permissions)**

Create directory if it doesn't exist, set permissions.

**Parameters:**
- `path` - Directory path to create
- `permissions` - Octal permissions (default: 755)

**Returns:**
- 0 on success
- 1 on failure

**Side Effects:**
- Creates directory with `mkdir -p`
- Sets permissions with `chmod`
- Logs debug message

**Example:**
```bash
ensure_directory "/opt/aeon/data"
ensure_directory "/opt/aeon/secrets" 700
```

---

#### **get_timestamp(format)**

Get current timestamp in specified format.

**Parameters:**
- `format` - Format type: `iso`, `unix`, `readable` (default: iso)

**Returns:**  
Formatted timestamp string

**Formats:**
- `iso` → `2025-12-14T15:30:45Z` (ISO 8601 UTC)
- `unix` → `1734190245` (Unix epoch seconds)
- `readable` → `2025-12-14 15:30:45`

**Example:**
```bash
timestamp=$(get_timestamp)           # ISO format
unix_time=$(get_timestamp unix)      # Unix timestamp
readable=$(get_timestamp readable)   # Human readable
```

---

#### **get_script_dir()**

Get the absolute path to the directory containing the calling script.

**Parameters:** None  
**Returns:** Absolute directory path

**Use Case:**  
Reliably finding module files relative to script location.

**Example:**
```bash
SCRIPT_DIR=$(get_script_dir)
source "$SCRIPT_DIR/other_module.sh"
```

**Why This Works:**
- Resolves symlinks
- Returns absolute path
- Works regardless of current directory

---

#### **join_array(delimiter, elements...)**

Join array elements with a delimiter.

**Parameters:**
- `delimiter` - String to join with
- `elements` - Array elements (remaining arguments)

**Returns:**  
Joined string

**Example:**
```bash
result=$(join_array ", " "apple" "banana" "cherry")
echo "$result"  # "apple, banana, cherry"

# With array
items=("one" "two" "three")
result=$(join_array " | " "${items[@]}")
echo "$result"  # "one | two | three"
```

---

#### **trim(string)**

Remove leading and trailing whitespace.

**Parameters:**
- `string` - String to trim

**Returns:**  
Trimmed string

**Example:**
```bash
result=$(trim "  hello world  ")
echo "$result"  # "hello world"
```

---

#### **to_lower(string)**

Convert string to lowercase.

**Parameters:**
- `string` - String to convert

**Returns:**  
Lowercase string

**Example:**
```bash
result=$(to_lower "HELLO WORLD")
echo "$result"  # "hello world"
```

---

#### **to_upper(string)**

Convert string to uppercase.

**Parameters:**
- `string` - String to convert

**Returns:**  
Uppercase string

**Example:**
```bash
result=$(to_upper "hello world")
echo "$result"  # "HELLO WORLD"
```

---

#### **contains(haystack, needle)**

Check if string contains substring.

**Parameters:**
- `haystack` - String to search in
- `needle` - String to search for

**Returns:**
- 0 if found
- 1 if not found

**Example:**
```bash
if contains "hello world" "world"; then
    echo "Found!"
fi

# Case sensitive
contains "Hello" "hello"  # Returns 1 (not found)
```

---

#### **is_root()**

Check if running as root (UID 0).

**Parameters:** None  
**Returns:**
- 0 if root
- 1 if not root

**Example:**
```bash
if is_root; then
    log SUCCESS "Running as root"
else
    log ERROR "Must be run as root"
    exit 1
fi
```

---

#### **confirm(prompt, default)**

Ask user for yes/no confirmation.

**Parameters:**
- `prompt` - Question to ask
- `default` - Default answer: `y` or `n` (default: `n`)

**Returns:**
- 0 if user confirms (yes)
- 1 if user declines (no)

**Behavior:**
- Displays `[Y/n]` or `[y/N]` based on default
- Accepts: y, Y, n, N, or Enter (uses default)

**Example:**
```bash
if confirm "Proceed with installation?"; then
    log INFO "Installing..."
else
    log INFO "Installation cancelled"
    exit 0
fi

# With default yes
if confirm "Continue?" "y"; then
    echo "Continuing..."
fi
```

---

#### **retry(max_attempts, command, args...)**

Retry a command with exponential backoff.

**Parameters:**
- `max_attempts` - Maximum number of attempts
- `command` - Command to execute
- `args` - Command arguments

**Returns:**
- 0 if command succeeds within max attempts
- 1 if all attempts fail

**Backoff:**
- Attempt 1: immediate
- Attempt 2: 1 second delay
- Attempt 3: 2 second delay
- Attempt 4: 4 second delay
- etc. (doubles each time)

**Example:**
```bash
# Retry ping up to 3 times
if retry 3 ping -c 1 192.168.1.1; then
    log SUCCESS "Host reachable"
else
    log ERROR "Host unreachable after 3 attempts"
fi

# Retry SSH connection
retry 5 ssh user@host "echo test"
```

---

### **File Utilities**

#### **file_exists(path)**

Check if file exists and is readable.

**Parameters:**
- `path` - File path

**Returns:**
- 0 if file exists and is readable
- 1 otherwise

**Example:**
```bash
if file_exists "/etc/config.conf"; then
    log INFO "Config file found"
fi
```

---

#### **dir_exists(path)**

Check if directory exists.

**Parameters:**
- `path` - Directory path

**Returns:**
- 0 if directory exists
- 1 otherwise

**Example:**
```bash
if dir_exists "/opt/aeon"; then
    log INFO "AEON directory exists"
fi
```

---

#### **is_writable(path)**

Check if path is writable.

**Parameters:**
- `path` - Path to check (file or directory)

**Returns:**
- 0 if writable
- 1 if not writable

**Example:**
```bash
if is_writable "/opt/aeon/data"; then
    log SUCCESS "Data directory is writable"
fi
```

---

#### **get_file_size(path)**

Get file size in bytes.

**Parameters:**
- `path` - File path

**Returns:**  
File size in bytes (or "0" if file doesn't exist)

**Example:**
```bash
size=$(get_file_size "/var/log/aeon.log")
log INFO "Log file size: ${size} bytes"

# Convert to MB
size_mb=$((size / 1024 / 1024))
log INFO "Log file size: ${size_mb}MB"
```

---

### **JSON Utilities**

#### **json_get(file, query)**

Extract value from JSON file using jq.

**Parameters:**
- `file` - JSON file path
- `query` - jq query string

**Returns:**  
Extracted value (stdout)

**Requirements:**  
`jq` must be installed

**Example:**
```bash
# Get single value
ip=$(json_get "devices.json" ".devices[0].ip")

# Get array length
count=$(json_get "devices.json" ".devices | length")

# Complex query
top_device=$(json_get "roles.json" \
    '.assignments[] | select(.role == "manager") | .device.ip')
```

---

#### **json_validate(file)**

Validate JSON file syntax.

**Parameters:**
- `file` - JSON file path

**Returns:**
- 0 if valid JSON
- 1 if invalid or file missing

**Example:**
```bash
if json_validate "/opt/aeon/data/config.json"; then
    log SUCCESS "JSON is valid"
else
    log ERROR "Invalid JSON"
fi
```

---

## 🔗 Dependencies

### **External Commands Used**

**Required:**
- `bash` (≥4.0)
- `date` - Timestamps
- `mkdir` - Directory creation
- `chmod` - Permissions
- `stat` - File information

**Optional:**
- `jq` - JSON operations (required for `json_*` functions)

### **No Module Dependencies**

This is the **base module** - it has no dependencies on other AEON modules.

---

## 🔌 Integration

### **Sourced By**

Every AEON module sources `common.sh`:

```
common.sh (base)
    ↓
    ├─> preflight.sh
    ├─> discovery.sh
    ├─> hardware.sh
    ├─> validation.sh
    ├─> parallel.sh
    ├─> user.sh
    ├─> reboot.sh
    ├─> swarm.sh
    └─> report.sh
```

### **Usage Pattern**

```bash
#!/bin/bash
# Every module follows this pattern

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || {
    echo "ERROR: Failed to source common.sh" >&2
    exit 1
}

# Now common utilities are available
log INFO "Module loaded"
```

---

## ⚠️ Important Notes

### **Double-Sourcing Prevention**

The module prevents being sourced multiple times:

```bash
[[ -n "${AEON_COMMON_LOADED:-}" ]] && return 0
readonly AEON_COMMON_LOADED=1
```

**Why This Matters:**
- Avoids redefining readonly variables (would cause error)
- Improves performance (skip redundant loading)
- Prevents initialization code from running twice

---

### **Environment Variable Override**

Directory paths can be overridden:

```bash
# Default
AEON_DIR=/opt/aeon

# Custom installation
AEON_DIR=/custom/path source /custom/path/lib/common.sh
```

---

### **Function Exports**

Functions are exported for use in subshells:

```bash
export -f log command_exists ensure_directory
```

**Use Case:**
```bash
# Functions available in subshell
(
    log INFO "In subshell"
    command_exists docker && echo "Docker found"
)
```

---

## 📖 Examples

### **Example 1: Basic Module Using Common**

```bash
#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

my_function() {
    log STEP "Starting my function"
    
    if ! command_exists docker; then
        log ERROR "Docker is required"
        return 1
    fi
    
    ensure_directory "/tmp/mydata"
    log SUCCESS "Setup complete"
}

my_function
```

---

### **Example 2: Using Display Functions**

```bash
source /opt/aeon/lib/common.sh

print_banner

print_header "System Information"

log INFO "Hostname: $(hostname)"
log INFO "Kernel: $(uname -r)"

print_line
```

---

### **Example 3: JSON Processing**

```bash
source /opt/aeon/lib/common.sh

if ! json_validate "data.json"; then
    log ERROR "Invalid JSON"
    exit 1
fi

device_count=$(json_get "data.json" ".devices | length")
log INFO "Found $device_count devices"

first_ip=$(json_get "data.json" ".devices[0].ip")
log INFO "First device: $first_ip"
```

---

### **Example 4: User Confirmation**

```bash
source /opt/aeon/lib/common.sh

print_header "Dangerous Operation"

log WARN "This will delete all data!"

if confirm "Are you absolutely sure?" "n"; then
    log INFO "Proceeding with deletion..."
else
    log INFO "Operation cancelled"
    exit 0
fi
```

---

## 🔧 Troubleshooting

### **Issue: Colors Not Showing**

**Cause:** Terminal doesn't support ANSI colors  
**Solution:** Use `TERM=xterm-256color`

```bash
TERM=xterm-256color ./script.sh
```

---

### **Issue: Box Characters Show as ?**

**Cause:** Terminal encoding not UTF-8  
**Solution:** Set encoding to UTF-8

```bash
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
```

---

### **Issue: "readonly variable" Error**

**Cause:** Sourcing common.sh multiple times  
**Solution:** This is normal, the module handles it

The second source returns early, no action needed.

---

### **Issue: json_* Functions Not Working**

**Cause:** `jq` not installed  
**Solution:** Install jq

```bash
sudo apt-get install jq
```

---

## 📊 Statistics

```
File: lib/common.sh
Lines: 722
Functions: 30+
Constants: 20+
Dependencies: None (base module)
Used By: All AEON modules
```

---

## 🎯 Design Principles

1. **Zero Dependencies** - Foundation module
2. **Comprehensive** - Provides all common needs
3. **Safe** - Error handling, double-source prevention
4. **Documented** - Every function documented
5. **Tested** - Can be tested standalone
6. **Extensible** - Easy to add new utilities

---

## 📞 Related Documentation

- [preflight.sh](./preflight.sh.md) - Pre-flight checks (uses common.sh)
- [hardware.sh](./hardware.sh.md) - Hardware orchestration (uses common.sh)
- [validation.sh](./validation.sh.md) - Validation (uses common.sh)
- [AEON Architecture](../architecture/OVERVIEW.md) - System design

---

**This documentation is for AEON version 0.1.0**  
**Last Updated:** 2025-12-14  
**Maintained by:** AEON Development Team
