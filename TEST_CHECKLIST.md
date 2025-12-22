# AEON Installer v1.2.0 - Test Checklist

## Pre-Test Setup
- [ ] Backup any existing AEON installation
- [ ] Ensure you have root/sudo access
- [ ] Verify git is available (or will be installed)

---

## Linux/WSL Testing

### Basic Installation
- [ ] Run: `sudo bash install.bash.v1.2.sh`
- [ ] Verify logs start with `[AEON_BASH]` prefix
- [ ] Check AEON_ROOT set to `/opt/aeon`
- [ ] Confirm aeon-system user created
- [ ] Verify directories created: `/opt/aeon/{library,manifest,logfiles,tmp}`

### Repository Clone
- [ ] Check repo cloned to: `/opt/aeon/tmp/repo`
- [ ] Verify repo owned by aeon-system user
- [ ] Confirm git depth=1 (shallow clone)
- [ ] Check files exist:
  - `/opt/aeon/tmp/repo/library/orchestrator/orchestrator.json.py`
  - `/opt/aeon/tmp/repo/manifest/manifest.install.json`
  - `/opt/aeon/tmp/repo/manifest/config/manifest.config.cursed.json`

### Repository Update (Re-run)
- [ ] Make local changes in `/opt/aeon/tmp/repo`
- [ ] Re-run installer: `sudo bash install.bash.v1.2.sh`
- [ ] Verify local changes removed (git clean -fd)
- [ ] Confirm repo reset to origin/main
- [ ] Check log messages show "Repository exists, updating..."

### Orchestrator Execution
- [ ] Verify orchestrator runs as aeon-system user
- [ ] Check AEON_ROOT environment variable set
- [ ] Confirm paths use REPO_DIR (not /opt/aeon/library)
- [ ] Verify no Docker mode attempted (native only)

### Flag Testing
- [ ] Test: `sudo bash install.bash.v1.2.sh -c` (CLI mode)
  - [ ] Verify --cli-enable passed to orchestrator
- [ ] Test: `sudo bash install.bash.v1.2.sh -w` (Web mode)
  - [ ] Verify --web-enable passed to orchestrator
- [ ] Test: `sudo bash install.bash.v1.2.sh -n` (Silent mode)
  - [ ] Verify --noninteractive passed to orchestrator
  - [ ] Check temp log created, then migrated
  - [ ] Confirm final log in `/opt/aeon/logfiles/`
- [ ] Test: `sudo bash install.bash.v1.2.sh -c -w` (Combined)
  - [ ] Verify both flags passed

### Logs
- [ ] Check log file created: `/opt/aeon/logfiles/install.bash.YYYYMMDD-HHMMSS.log`
- [ ] Verify all log lines have `[AEON_BASH]` prefix
- [ ] Confirm errors have `[AEON_BASH][ERROR]` prefix
- [ ] Check log owned by aeon-system user

### Error Handling
- [ ] Test with invalid git URL (edit AEON_REPO_URL)
  - [ ] Verify proper error message with [AEON_BASH][ERROR]
- [ ] Test with missing orchestrator file
  - [ ] Confirm error: "Orchestrator not found at: ..."
- [ ] Test without root privileges
  - [ ] Verify error: "This script must be run as root"

---

## macOS Testing

### Basic Installation
- [ ] Run: `sudo bash install.bash.v1.2.sh`
- [ ] Verify logs start with `[AEON_BASH]` prefix
- [ ] Check AEON_ROOT set to `/usr/local/aeon`
- [ ] Confirm aeon-system user created via dscl
- [ ] Verify Homebrew detection for git installation

### Repository Clone
- [ ] Check repo cloned to: `/usr/local/aeon/tmp/repo`
- [ ] Verify repo owned by aeon-system user
- [ ] Confirm git operations run as aeon-system
- [ ] Check orchestrator files present in repo

### Repository Update (Re-run)
- [ ] Make local changes in `/usr/local/aeon/tmp/repo`
- [ ] Re-run installer: `sudo bash install.bash.v1.2.sh`
- [ ] Verify local changes removed
- [ ] Confirm repo updated successfully

### Orchestrator Execution
- [ ] Verify orchestrator runs as aeon-system user
- [ ] Check AEON_ROOT environment variable set
- [ ] Confirm native mode only (no Docker)
- [ ] Verify paths use REPO_DIR

### Bash 3.2 Compatibility
- [ ] Confirm script runs on default macOS bash (3.2)
- [ ] Verify no ${var,,} or ${var^^} usage
- [ ] Check no associative arrays (declare -A)
- [ ] Confirm `tr '[:upper:]' '[:lower:]'` used for case conversion

### Flag Testing
- [ ] Test all flags (-c, -w, -n) individually
- [ ] Test combined flags
- [ ] Verify flag forwarding to orchestrator

### Logs
- [ ] Check log created: `/usr/local/aeon/logfiles/install.bash.YYYYMMDD-HHMMSS.log`
- [ ] Verify [AEON_BASH] prefix on all lines
- [ ] Check log owned by aeon-system

---

## Cross-Platform Validation

### Silent Mode (-n)
- [ ] **Linux**: `sudo bash install.bash.v1.2.sh -n`
  - [ ] Zero stdout/stderr during execution
  - [ ] Temp log created at `/tmp/aeon-install-$$.log`
  - [ ] Temp log migrated to final location
- [ ] **macOS**: Same tests as Linux

### Log Format Consistency
- [ ] Silent mode logs: `[AEON_BASH][YYYY-MM-DD HH:MM:SS] message`
- [ ] Interactive mode logs: `[AEON_BASH] message`
- [ ] Error logs: `[AEON_BASH][ERROR] message` or `[AEON_BASH][YYYY-MM-DD HH:MM:SS][ERROR] message`

### Version Check
- [ ] Verify header shows: `# VERSION: 1.2.0`
- [ ] Check installer reports version correctly

---

## Regression Testing

### Things That Should NOT Have Changed
- [ ] Flag parsing still supports -c/-w/-n only (max 3)
- [ ] Case-insensitive long flags still work (--CLI-ENABLE)
- [ ] AEON_ROOT logic unchanged (Linux: /opt/aeon, macOS: /usr/local/aeon)
- [ ] sudoers configuration still applied
- [ ] Python venv still created
- [ ] System user home directories correct

---

## Post-Install Verification

### Final Checks
- [ ] Installation completes successfully
- [ ] Finalization message displays (non-silent mode)
- [ ] Exit code is 0 on success
- [ ] All permissions correct (aeon-system ownership)
- [ ] No Docker-related log messages
- [ ] Repository update works on subsequent runs

---

## Known Issues / Notes

1. **Git must be available**: The installer requires git. It will install it automatically on Linux/macOS.
2. **Native mode only**: Docker orchestrator mode has been completely removed.
3. **Bash 3.2 compatible**: Safe to run on older macOS systems.
4. **Repo cleanup**: Local changes in `/tmp/repo` are destroyed on re-run (by design).

---

## Quick Test Commands

```bash
# Linux/WSL - Full test
sudo bash install.bash.v1.2.sh -c -w

# Linux/WSL - Silent test
sudo bash install.bash.v1.2.sh -n

# macOS - Full test
sudo bash install.bash.v1.2.sh -c -w

# macOS - Silent test
sudo bash install.bash.v1.2.sh -n

# Verify logs
sudo tail -f /opt/aeon/logfiles/install.bash.*.log           # Linux
sudo tail -f /usr/local/aeon/logfiles/install.bash.*.log     # macOS

# Check repo
ls -la /opt/aeon/tmp/repo                                    # Linux
ls -la /usr/local/aeon/tmp/repo                              # macOS

# Verify user
id aeon-system

# Check sudoers
sudo cat /etc/sudoers.d/aeon-system
```
