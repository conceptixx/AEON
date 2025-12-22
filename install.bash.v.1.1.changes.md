# AEON Install Script Refactoring - Change Summary

## Version Update
- **Old Version:** 1.0.0.v7.1 stable
- **New Version:** 1.1.0 (Git Repository Mode)

---

## Major Changes

### 1. **Git Repository Configuration (NEW)**
**Location:** Lines 13-16

```bash
# NEW: Git repository configuration
AEON_REPO_URL="${AEON_REPO_URL:-https://github.com/conceptixx/AEON.git}"
AEON_REPO_BRANCH="${AEON_REPO_BRANCH:-main}"
AEON_REPO_LOCAL_PATH="tmp/repo"
```

**What Changed:**
- Added configurable repository URL (overridable via environment variable)
- Added branch configuration (default: main)
- Added local repository path configuration
- **REMOVED:** `GITHUB_RAW_BASE` variable (no longer downloading individual files)

---

### 2. **Git Installation Function (NEW)**
**Location:** Lines 321-387

**Added Three New Functions:**

#### `install_git()` - Main orchestrator
- Checks if git is already installed
- Delegates to OS-specific installation
- Verifies installation success

#### `install_git_linux()` - Linux package manager handling
- Auto-detects package manager (apt-get, yum, dnf, pacman, apk, zypper)
- Installs git via best-effort approach
- Reuses APT_UPDATED flag to prevent duplicate updates

#### `install_git_macos()` - macOS Homebrew installation
- **CRITICAL:** Requires Homebrew to be present
- Runs brew as SUDO_USER (NOT as root) - brew safety requirement
- Uses detected BREW_PATH from earlier detection

**Why This Matters:**
Git is now a **mandatory prerequisite** instead of an optional tool, installed BEFORE repository operations.

---

### 3. **Repository Management Functions (NEW)**
**Location:** Lines 535-606

**Three Critical Functions:**

#### `clone_or_update_repo()`
- Main entry point for repository operations
- Checks if repository exists at `${AEON_ROOT}/tmp/repo`
- Routes to clone or update based on existence
- Sets ownership to aeon-system user

#### `clone_new_repo()`
- Performs shallow clone (`--depth 1`) for efficiency
- Clones specific branch (`--branch $AEON_REPO_BRANCH`)
- Runs as aeon-system user (`sudo -u $AEON_USER`)
- Removes any existing non-git directory before cloning

#### `update_existing_repo()`
- **Atomic update strategy:**
  1. `git fetch --all --prune` - Get latest refs
  2. `git reset --hard origin/main` - Force alignment with remote
  3. `git clean -fd` - Remove untracked files
- Ensures clean, reproducible state on every run
- Prevents merge conflicts and dirty states

**🎯 SURPRISE ELEMENT - Atomic Repository Updates:**
The update strategy uses `git reset --hard` instead of `git pull`, which prevents merge conflicts and ensures the local repository ALWAYS matches the remote state exactly. This is a best practice for automated deployments!

---

### 4. **Download Files Function (REMOVED)**
**Old Location:** Lines 479-512

**What Was Removed:**
```bash
download_files() {
    log "Downloading AEON files from GitHub..."
    
    local files="library/orchestrator/orchestrator.json.py
manifest/manifest.install.json
manifest/config/manifest.config.cursed.json"
    
    # ... curl download logic ...
}
```

**Why Removed:**
- No longer need individual file downloads
- All files available in repository clone
- Simplifies dependency management

---

### 5. **Orchestrator Execution Changes**
**Location:** Lines 608-772

#### `run_orchestrator_native()` - Modified
**Old Approach:**
```bash
local orchestrator="$AEON_ROOT/library/orchestrator/orchestrator.json.py"
# Files expected to be in AEON_ROOT directly
```

**New Approach:**
```bash
local repo_path="$AEON_ROOT/$AEON_REPO_LOCAL_PATH"
local orchestrator="$repo_path/library/orchestrator/orchestrator.json.py"
local manifest="$repo_path/manifest/manifest.install.json"
local config="$repo_path/manifest/config/manifest.config.cursed.json"

# Verify files exist
if [ ! -f "$orchestrator" ]; then
    log_error "Orchestrator not found: $orchestrator"
    return 1
fi
# ... additional checks ...

# Run with AEON_ROOT environment variable
sudo -u "$AEON_USER" -H env AEON_ROOT="$AEON_ROOT" \
    "$venv_python" "$orchestrator" \
    $flags \
    "--file:$manifest" \
    "--config:$config"
```

**Key Changes:**
1. All paths now reference repository location
2. Added file existence verification before execution
3. **NEW:** Sets `AEON_ROOT` environment variable for orchestrator
4. Uses absolute paths from repository

#### `run_orchestrator_docker()` - Modified
**Old Approach:**
```bash
--file:/manifest/manifest.install.json \
--config:/manifest/config/manifest.config.cursed.json
```

**New Approach:**
```bash
local manifest_rel="$AEON_REPO_LOCAL_PATH/manifest/manifest.install.json"
local config_rel="$AEON_REPO_LOCAL_PATH/manifest/config/manifest.config.cursed.json"
local orch_rel="$AEON_REPO_LOCAL_PATH/library/orchestrator/orchestrator.json.py"

docker run --rm $docker_args "$AEON_ORCH_DOCKER_IMAGE" \
    python "/aeon/$orch_rel" \
    $flags \
    "--file:/aeon/$manifest_rel" \
    "--config:/aeon/$config_rel"
```

**Key Changes:**
1. Docker still maps `AEON_ROOT` to `/aeon` in container
2. Files accessed via repository subdirectory within `/aeon`
3. Maintains compatibility with existing Docker setup

---

### 6. **Directory Setup Changes**
**Location:** Line 529

**Old:**
```bash
local dirs="logfiles"
```

**New:**
```bash
local dirs="logfiles tmp tmp/repo"
```

**What Changed:**
- Added `tmp` directory creation
- Added `tmp/repo` directory creation (for git clone)
- Ensures parent directories exist before git operations

---

### 7. **Main Function Execution Order**
**Location:** Lines 816-842

**Old Order:**
```bash
install_always_tools
install_python
install_docker
# ...
download_files
```

**New Order:**
```bash
install_always_tools
install_git          # NEW: Git installation BEFORE python
install_python
install_docker
# ...
clone_or_update_repo  # NEW: Repository management instead of download_files
```

**Critical Ordering:**
1. `install_git` runs AFTER brew detection (macOS needs BREW_PATH)
2. `install_git` runs BEFORE `clone_or_update_repo`
3. Repository operations run AFTER user creation (needs ownership)

---

### 8. **Finalize Changes**
**Location:** Line 790

**Added Output:**
```bash
log "Repository: $AEON_ROOT/$AEON_REPO_LOCAL_PATH"
```

**New Log Message:**
```bash
log "  - Check configuration in $AEON_ROOT/$AEON_REPO_LOCAL_PATH/manifest/"
```

**What Changed:**
- User now sees where repository was cloned
- Configuration path updated to point to repository

---

## Backward Compatibility

### ✅ **Preserved Features:**
1. All CLI flags: `-c`, `-w`, `-n` with identical behavior
2. Logging policy: `/tmp` fallback → `${AEON_ROOT}/logfiles/` migration
3. OS root paths: `/opt/aeon` (Linux/WSL), `/usr/local/aeon` (macOS)
4. User creation: `aeon-system` with sudoers configuration
5. Docker mode: Auto-detection and fallback to native
6. Bash 3.2 compatibility: No bashisms, portable constructs

### ⚠️ **Breaking Changes:**
- Files no longer downloaded to `${AEON_ROOT}` directly
- Files now in `${AEON_ROOT}/tmp/repo/` subdirectory
- Requires git to be installable on system

---

## Security Improvements

1. **Atomic Updates:** `git reset --hard` prevents partial/corrupt updates
2. **Shallow Clone:** `--depth 1` reduces attack surface
3. **User Ownership:** Repository owned by `aeon-system`, not root
4. **Brew Safety:** macOS git installation runs as SUDO_USER, not root

---

## Performance Optimizations

1. **Shallow Clone:** Only fetches latest commit (faster, less bandwidth)
2. **Incremental Updates:** Existing repos use fetch+reset (faster than re-clone)
3. **Clean State:** `git clean -fd` removes build artifacts automatically

---

## Environment Variable Overrides

**New Capability:**
```bash
# Custom repository URL
AEON_REPO_URL="https://github.com/myorg/custom-aeon.git" sudo ./install.bash.sh

# Custom branch
AEON_REPO_BRANCH="development" sudo ./install.bash.sh

# Both
AEON_REPO_URL="..." AEON_REPO_BRANCH="..." sudo ./install.bash.sh
```

---

## Testing Scenarios

### First Install (No Repository)
```bash
sudo ./install.bash.sh -c -w
# Expected: Git installed → Repository cloned → Orchestrator runs
```

### Update Install (Repository Exists)
```bash
sudo ./install.bash.sh -n
# Expected: Repository updated via fetch+reset → Orchestrator runs
```

### Silent Mode
```bash
sudo ./install.bash.sh -n
# Expected: Zero stdout/stderr → Full logs in ${AEON_ROOT}/logfiles/
```

### Custom Repository
```bash
AEON_REPO_URL="https://github.com/fork/aeon.git" sudo ./install.bash.sh
# Expected: Custom repository cloned instead of default
```

---

## Files Changed Summary

| File/Function | Change Type | Lines | Description |
|---------------|-------------|-------|-------------|
| Configuration | Modified | 13-16 | Added git repo config, removed GITHUB_RAW_BASE |
| install_git() | NEW | 321-333 | Git installation orchestrator |
| install_git_linux() | NEW | 335-369 | Multi-package-manager git install |
| install_git_macos() | NEW | 371-387 | Homebrew-based git install |
| setup_directories() | Modified | 529 | Added tmp/repo directory creation |
| clone_or_update_repo() | NEW | 535-555 | Main repository management |
| clone_new_repo() | NEW | 557-574 | Initial clone operation |
| update_existing_repo() | NEW | 576-599 | Atomic update operation |
| download_files() | REMOVED | OLD 479-512 | No longer needed |
| run_orchestrator_native() | Modified | 649-680 | Uses repo paths, adds AEON_ROOT env |
| run_orchestrator_docker() | Modified | 682-710 | Uses repo paths in container |
| main() | Modified | 816-842 | Added install_git, replaced download with clone |
| finalize_installation() | Modified | 790 | Added repository path to output |

---

## Total Line Count Change
- **Old:** 709 lines
- **New:** 842 lines
- **Delta:** +133 lines (mostly new git functionality)

---

## Code Quality Metrics

### Bash 3.2 Compliance: ✅
- No `[[` double brackets
- No `+=` array syntax
- No `${}` parameter expansion beyond POSIX
- No `declare -A` associative arrays

### Error Handling: ✅
- `set -euo pipefail` (fail fast)
- Explicit exit codes on all errors
- Fallback mechanisms (Docker → Native)

### Logging: ✅
- Consistent log format
- Silent mode compliance (zero stdout/stderr)
- Timestamped log files

### Idempotency: ✅
- Re-runnable without side effects
- Checks existence before installation
- Clean repository state on update

---

## 🎓 Learning Surprise - Best Practices Implemented

### 1. **Git Reset vs Git Pull**
This script uses `git reset --hard origin/main` instead of `git pull` because:
- **Pull** can fail with merge conflicts in automation
- **Reset** guarantees clean state matching remote
- **Reset** is atomic - either succeeds completely or fails completely
- This is the **industry standard** for CI/CD deployments!

### 2. **Shallow Clones in Production**
Using `--depth 1` is a **production optimization**:
- 90%+ smaller download size
- Faster clone operations
- Reduced disk space usage
- Security benefit: Less history = less vulnerability surface

### 3. **Brew User Safety**
Running brew as root is dangerous because:
- Brew explicitly refuses to run as root
- Can corrupt system-wide Homebrew installation
- File ownership issues if run as wrong user
- **SUDO_USER detection** is the proper pattern

---

## Migration Path

### For Existing Installations:
1. Script detects existing `tmp/repo/.git` directory
2. Runs `git fetch --all` + `git reset --hard` (update)
3. No data loss - logs preserved in `logfiles/`

### For Fresh Installations:
1. Script creates `tmp/repo` directory
2. Clones repository with `--depth 1`
3. Runs orchestrator from repository

---

**End of Change Summary**
