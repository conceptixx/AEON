# user.sh - AEON User Management Module

## 📋 Overview

**File:** `lib/user.sh`  
**Type:** Library module  
**Version:** 0.1.0  
**Purpose:** Create and manage the AEON system user across all cluster devices

**Quick Description:**  
Creates a dedicated `aeon` user on all devices with limited sudo access (reboot only), manages passwords securely, and sets proper ownership of `/opt/aeon`.

---

## 🎯 Purpose

### **Why AEON Needs Its Own User**

1. **Security:** Limited sudo access (only reboot commands)
2. **Isolation:** Separate from default users (pi, ubuntu)
3. **Automation:** Consistent user across all devices
4. **Ownership:** Full control of `/opt/aeon` directory

### **AEON User Permissions**

✅ **CAN:**
- `sudo reboot`
- `sudo reboot now`
- `sudo systemctl reboot`
- Full read/write to `/opt/aeon`

❌ **CANNOT:**
- Any other sudo commands
- System-wide changes
- Access other users' files

---

## 🚀 Usage

```bash
source /opt/aeon/lib/user.sh

# Create AEON user on local device
create_aeon_user || exit 1

# Create AEON user on all cluster devices
create_aeon_user_cluster \
    "$DATA_DIR/discovered_devices.json" || exit 1
```

---

## 📚 Key Functions

### **generate_secure_password()**
Generate cryptographically secure 32-character password.

**Uses:** openssl or /dev/urandom  
**Returns:** Password string (stdout)

---

### **create_aeon_user()**
Create AEON user on local device.

**Steps:**
1. Check if user exists
2. Create user and group
3. Generate secure password
4. Set password
5. Create home directory
6. Configure limited sudo access
7. Save password to `.aeon.env`
8. Set ownership of `/opt/aeon`

**Returns:** 0 on success, 1 on failure

---

### **configure_sudoers()**
Configure limited sudo access for AEON user.

**Creates:** `/etc/sudoers.d/aeon`

**Content:**
```
aeon ALL=(ALL) NOPASSWD: /sbin/reboot, /sbin/reboot now, /bin/systemctl reboot
```

**Validates:** Sudoers syntax with `visudo -c`

---

### **create_aeon_user_cluster(devices_json)**
Create AEON user on all devices in parallel.

**Parameters:**
- `devices_json` - Path to discovered_devices.json

**Uses:** parallel.sh for concurrent creation

---

## 🔐 Security

**Password Storage:**
```bash
# /opt/aeon/.aeon.env (600 permissions)
AEON_USER=aeon
AEON_PASSWORD=randomly_generated_32_chars
```

**Sudoers Validation:**
```bash
# Always validates before activating
visudo -cf /etc/sudoers.d/aeon
```

---

## 📊 Statistics

```
File: lib/user.sh
Lines: 591
Functions: 8
Security: Limited sudo, secure passwords
```

---

**Last Updated:** 2025-12-14
