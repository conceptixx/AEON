#!/bin/bash
################################################################################
# AEON User Management System
# File: lib/aeon_user.sh
# Version: 0.1.0
#
# Purpose: Create and manage the AEON system user with controlled sudo access
#
# The AEON user:
#   - Can ONLY run: sudo reboot, sudo reboot now, sudo systemctl reboot
#   - Has full ownership of /opt/aeon
#   - Password stored securely in /opt/aeon/.aeon.env
#   - Used for automated system operations
#
# Security:
#   - Limited sudo commands (reboot only)
#   - Strong password generation
#   - Proper file permissions
#   - Sudoers validation
################################################################################

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

AEON_USER="aeon"
AEON_GROUP="aeon"
AEON_HOME="/home/aeon"
AEON_DIR="/opt/aeon"
AEON_ENV_FILE="$AEON_DIR/.aeon.env"
SUDOERS_FILE="/etc/sudoers.d/aeon"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================================
# LOGGING
# ============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    
    case "$level" in
        ERROR)
            echo -e "${RED}❌ $message${NC}" >&2
            ;;
        WARN)
            echo -e "${YELLOW}⚠️  $message${NC}"
            ;;
        INFO)
            echo -e "${CYAN}ℹ️  $message${NC}"
            ;;
        SUCCESS)
            echo -e "${GREEN}✅ $message${NC}"
            ;;
        STEP)
            echo -e "${BOLD}${CYAN}▶ $message${NC}"
            ;;
    esac
}

# ============================================================================
# PASSWORD GENERATION
# ============================================================================

generate_secure_password() {
    # Generate a cryptographically secure password
    # 32 characters: alphanumeric + special chars
    local password
    
    if command -v openssl &>/dev/null; then
        # Use openssl for best randomness
        password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    elif [[ -f /dev/urandom ]]; then
        # Fallback to /dev/urandom
        password=$(tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c 32)
    else
        # Last resort: use date + random
        password=$(date +%s | sha256sum | base64 | head -c 32)
    fi
    
    echo "$password"
}

# ============================================================================
# USER CREATION
# ============================================================================

check_user_exists() {
    if id "$AEON_USER" &>/dev/null; then
        return 0  # User exists
    else
        return 1  # User does not exist
    fi
}

create_aeon_user() {
    log STEP "Creating AEON system user..."
    
    if check_user_exists; then
        log INFO "User '$AEON_USER' already exists"
        return 0
    fi
    
    # Create group first
    if ! getent group "$AEON_GROUP" &>/dev/null; then
        log INFO "Creating group '$AEON_GROUP'..."
        groupadd "$AEON_GROUP" || {
            log ERROR "Failed to create group"
            return 1
        }
    fi
    
    # Create user with home directory
    log INFO "Creating user '$AEON_USER'..."
    useradd -m -s /bin/bash -g "$AEON_GROUP" -d "$AEON_HOME" "$AEON_USER" || {
        log ERROR "Failed to create user"
        return 1
    }
    
    log SUCCESS "User '$AEON_USER' created"
    return 0
}

set_aeon_password() {
    local password="$1"
    
    log STEP "Setting password for AEON user..."
    
    # Set password using chpasswd
    echo "$AEON_USER:$password" | chpasswd || {
        log ERROR "Failed to set password"
        return 1
    }
    
    log SUCCESS "Password set for user '$AEON_USER'"
    return 0
}

# ============================================================================
# SUDOERS CONFIGURATION
# ============================================================================

create_sudoers_file() {
    local allow_reboot="$1"
    
    log STEP "Configuring sudo permissions..."
    
    if [[ "$allow_reboot" != "true" ]]; then
        log INFO "Reboot permission disabled (as per configuration)"
        
        # Create empty sudoers file (user exists but no sudo)
        cat > "$SUDOERS_FILE" << 'EOF'
# AEON User Sudoers Configuration
# Reboot permission: DISABLED
# No sudo commands allowed for aeon user
EOF
        chmod 0440 "$SUDOERS_FILE"
        log SUCCESS "Sudoers file created (reboot disabled)"
        return 0
    fi
    
    log INFO "Configuring limited sudo access (reboot only)..."
    
    # Create sudoers file with ONLY reboot permissions
    cat > "$SUDOERS_FILE" << 'EOF'
# AEON User Sudoers Configuration
# This file grants the AEON user LIMITED sudo access
# ONLY for system reboot operations
#
# Commands allowed:
#   - sudo reboot
#   - sudo reboot now
#   - sudo systemctl reboot
#   - sudo shutdown -r now
#
# Security: NOPASSWD allows automated reboots
# Limitation: No other sudo commands permitted

# AEON user reboot permissions
aeon ALL=(ALL) NOPASSWD: /sbin/reboot
aeon ALL=(ALL) NOPASSWD: /usr/sbin/reboot
aeon ALL=(ALL) NOPASSWD: /bin/systemctl reboot
aeon ALL=(ALL) NOPASSWD: /usr/bin/systemctl reboot
aeon ALL=(ALL) NOPASSWD: /sbin/shutdown -r now
aeon ALL=(ALL) NOPASSWD: /usr/sbin/shutdown -r now

# Explicitly deny all other sudo commands
aeon ALL=(ALL) !ALL
EOF
    
    # Set proper permissions (sudoers files must be 0440)
    chmod 0440 "$SUDOERS_FILE"
    
    # Validate sudoers file
    if visudo -c -f "$SUDOERS_FILE" &>/dev/null; then
        log SUCCESS "Sudoers file created and validated"
        return 0
    else
        log ERROR "Sudoers file validation failed!"
        rm -f "$SUDOERS_FILE"
        return 1
    fi
}

# ============================================================================
# DIRECTORY PERMISSIONS
# ============================================================================

set_aeon_directory_ownership() {
    local allow_system_access="$1"
    
    log STEP "Configuring AEON directory permissions..."
    
    if [[ "$allow_system_access" != "true" ]]; then
        log WARN "System access disabled - AEON user will NOT own /opt/aeon"
        log WARN "This may break automated operations!"
        return 0
    fi
    
    # Ensure /opt/aeon exists
    if [[ ! -d "$AEON_DIR" ]]; then
        log ERROR "/opt/aeon does not exist"
        return 1
    fi
    
    log INFO "Setting ownership of $AEON_DIR to $AEON_USER:$AEON_GROUP..."
    
    # Change ownership recursively
    chown -R "$AEON_USER:$AEON_GROUP" "$AEON_DIR" || {
        log ERROR "Failed to change ownership"
        return 1
    }
    
    # Set directory permissions
    # 755 for directories (rwxr-xr-x)
    find "$AEON_DIR" -type d -exec chmod 755 {} \; 2>/dev/null || true
    
    # 644 for regular files (rw-r--r--)
    find "$AEON_DIR" -type f -exec chmod 644 {} \; 2>/dev/null || true
    
    # 700 for secrets directory (rwx------)
    if [[ -d "$AEON_DIR/secrets" ]]; then
        chmod 700 "$AEON_DIR/secrets"
        find "$AEON_DIR/secrets" -type f -exec chmod 600 {} \; 2>/dev/null || true
    fi
    
    # Make scripts executable
    if [[ -d "$AEON_DIR/lib" ]]; then
        find "$AEON_DIR/lib" -type f -name "*.sh" -exec chmod 755 {} \; 2>/dev/null || true
    fi
    
    if [[ -d "$AEON_DIR/remote" ]]; then
        find "$AEON_DIR/remote" -type f -name "*.sh" -exec chmod 755 {} \; 2>/dev/null || true
    fi
    
    log SUCCESS "Directory permissions configured"
    return 0
}

# ============================================================================
# PASSWORD STORAGE
# ============================================================================

save_aeon_credentials() {
    local password="$1"
    
    log STEP "Saving AEON credentials..."
    
    # Create .aeon.env file
    cat > "$AEON_ENV_FILE" << EOF
# AEON System Credentials
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# WARNING: Keep this file secure!

AEON_USER="$AEON_USER"
AEON_PASSWORD="$password"

# Usage:
#   source /opt/aeon/.aeon.env
#   ssh $AEON_USER@<host>  # Use $AEON_PASSWORD when prompted
EOF
    
    # Secure permissions (only readable by owner)
    chmod 600 "$AEON_ENV_FILE"
    chown "$AEON_USER:$AEON_GROUP" "$AEON_ENV_FILE"
    
    log SUCCESS "Credentials saved to $AEON_ENV_FILE"
    return 0
}

# ============================================================================
# VERIFICATION
# ============================================================================

verify_aeon_user_setup() {
    log STEP "Verifying AEON user setup..."
    
    local errors=0
    
    # Check user exists
    if check_user_exists; then
        log SUCCESS "✓ User '$AEON_USER' exists"
    else
        log ERROR "✗ User '$AEON_USER' does not exist"
        ((errors++))
    fi
    
    # Check home directory
    if [[ -d "$AEON_HOME" ]]; then
        log SUCCESS "✓ Home directory exists: $AEON_HOME"
    else
        log ERROR "✗ Home directory missing"
        ((errors++))
    fi
    
    # Check sudoers file
    if [[ -f "$SUDOERS_FILE" ]]; then
        log SUCCESS "✓ Sudoers file exists: $SUDOERS_FILE"
        
        # Validate sudoers
        if visudo -c -f "$SUDOERS_FILE" &>/dev/null; then
            log SUCCESS "✓ Sudoers file is valid"
        else
            log ERROR "✗ Sudoers file is invalid"
            ((errors++))
        fi
    else
        log WARN "⚠ Sudoers file not created (reboot may be disabled)"
    fi
    
    # Check AEON directory ownership
    if [[ -d "$AEON_DIR" ]]; then
        local owner=$(stat -c '%U' "$AEON_DIR")
        
        if [[ "$owner" == "$AEON_USER" ]]; then
            log SUCCESS "✓ AEON directory owned by $AEON_USER"
        else
            log WARN "⚠ AEON directory owned by $owner (not $AEON_USER)"
        fi
    fi
    
    # Check credentials file
    if [[ -f "$AEON_ENV_FILE" ]]; then
        log SUCCESS "✓ Credentials file exists"
        
        # Check permissions
        local perms=$(stat -c '%a' "$AEON_ENV_FILE")
        if [[ "$perms" == "600" ]]; then
            log SUCCESS "✓ Credentials file has secure permissions (600)"
        else
            log WARN "⚠ Credentials file permissions: $perms (should be 600)"
        fi
    else
        log ERROR "✗ Credentials file missing"
        ((errors++))
    fi
    
    echo ""
    
    if [[ $errors -eq 0 ]]; then
        log SUCCESS "All verifications passed"
        return 0
    else
        log ERROR "$errors verification(s) failed"
        return 1
    fi
}

# ============================================================================
# TEST SUDO ACCESS
# ============================================================================

test_sudo_reboot() {
    log STEP "Testing sudo reboot access..."
    
    # Test if user can run sudo reboot (dry run)
    if su - "$AEON_USER" -c "sudo -n -l reboot" &>/dev/null; then
        log SUCCESS "✓ User '$AEON_USER' can run sudo reboot"
        return 0
    else
        log WARN "⚠ Cannot verify sudo access (this is normal if reboot is disabled)"
        return 0
    fi
}

# ============================================================================
# MAIN SETUP FUNCTION
# ============================================================================

setup_aeon_user() {
    local allow_reboot="${1:-true}"
    local allow_system_access="${2:-true}"
    
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  AEON System User Setup${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    log INFO "Configuration:"
    log INFO "  Allow reboot: $allow_reboot"
    log INFO "  Allow system access: $allow_system_access"
    echo ""
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log ERROR "This function must be run as root"
        return 1
    fi
    
    # Generate secure password
    local password=$(generate_secure_password)
    log INFO "Generated secure password (32 characters)"
    
    # Create user
    create_aeon_user || return 1
    
    # Set password
    set_aeon_password "$password" || return 1
    
    # Configure sudoers
    create_sudoers_file "$allow_reboot" || return 1
    
    # Set directory ownership
    set_aeon_directory_ownership "$allow_system_access" || return 1
    
    # Save credentials
    save_aeon_credentials "$password" || return 1
    
    # Verify setup
    echo ""
    verify_aeon_user_setup || return 1
    
    # Test sudo access
    if [[ "$allow_reboot" == "true" ]]; then
        echo ""
        test_sudo_reboot
    fi
    
    # Summary
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Setup Complete${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    log SUCCESS "AEON user created and configured"
    echo ""
    log INFO "User: $AEON_USER"
    log INFO "Home: $AEON_HOME"
    log INFO "Credentials: $AEON_ENV_FILE"
    echo ""
    
    if [[ "$allow_reboot" == "true" ]]; then
        log INFO "Sudo permissions: REBOOT ONLY"
        log INFO "  ✓ sudo reboot"
        log INFO "  ✓ sudo reboot now"
        log INFO "  ✓ sudo systemctl reboot"
    else
        log WARN "Sudo permissions: DISABLED"
    fi
    
    echo ""
    
    if [[ "$allow_system_access" == "true" ]]; then
        log INFO "System access: /opt/aeon (full ownership)"
    else
        log WARN "System access: DISABLED"
    fi
    
    echo ""
    log WARN "⚠️  IMPORTANT: Save credentials from $AEON_ENV_FILE"
    echo ""
    
    return 0
}

# ============================================================================
# REMOVE AEON USER
# ============================================================================

remove_aeon_user() {
    log STEP "Removing AEON user..."
    
    if ! check_user_exists; then
        log INFO "User '$AEON_USER' does not exist"
        return 0
    fi
    
    # Remove sudoers file
    if [[ -f "$SUDOERS_FILE" ]]; then
        log INFO "Removing sudoers file..."
        rm -f "$SUDOERS_FILE"
    fi
    
    # Remove user
    log INFO "Removing user '$AEON_USER'..."
    userdel -r "$AEON_USER" 2>/dev/null || {
        log WARN "Failed to remove user (may need manual cleanup)"
    }
    
    # Remove credentials file
    if [[ -f "$AEON_ENV_FILE" ]]; then
        log INFO "Removing credentials file..."
        shred -vfz -n 10 "$AEON_ENV_FILE" 2>/dev/null || rm -f "$AEON_ENV_FILE"
    fi
    
    log SUCCESS "AEON user removed"
    return 0
}

# ============================================================================
# GET AEON PASSWORD
# ============================================================================

get_aeon_password() {
    if [[ ! -f "$AEON_ENV_FILE" ]]; then
        log ERROR "Credentials file not found: $AEON_ENV_FILE"
        return 1
    fi
    
    # Source the file and extract password
    source "$AEON_ENV_FILE"
    echo "$AEON_PASSWORD"
}

# ============================================================================
# EXPORT FUNCTIONS
# ============================================================================

export -f setup_aeon_user
export -f remove_aeon_user
export -f get_aeon_password
export -f check_user_exists
export -f verify_aeon_user_setup

# ============================================================================
# STANDALONE EXECUTION
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    
    case "${1:-setup}" in
        setup)
            setup_aeon_user "true" "true"
            ;;
        setup-no-reboot)
            setup_aeon_user "false" "true"
            ;;
        setup-no-access)
            setup_aeon_user "true" "false"
            ;;
        setup-minimal)
            setup_aeon_user "false" "false"
            ;;
        remove)
            remove_aeon_user
            ;;
        verify)
            verify_aeon_user_setup
            ;;
        password)
            get_aeon_password
            ;;
        *)
            echo "Usage: $0 {setup|setup-no-reboot|setup-no-access|setup-minimal|remove|verify|password}"
            echo ""
            echo "Commands:"
            echo "  setup              - Full setup (reboot + system access)"
            echo "  setup-no-reboot    - Setup without reboot permission"
            echo "  setup-no-access    - Setup without /opt/aeon ownership"
            echo "  setup-minimal      - Setup with minimal permissions"
            echo "  remove             - Remove AEON user completely"
            echo "  verify             - Verify AEON user configuration"
            echo "  password           - Display AEON user password"
            echo ""
            exit 1
            ;;
    esac
fi
