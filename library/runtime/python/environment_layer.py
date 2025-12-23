#!/usr/bin/env python3
"""
AEON Environment Layer v0.3.1

PATCH RELEASE: Fixes environment precedence bug (R6 violation)

Changes from v0.3.0:
- Added priority-based precedence to EnvState.set_var() 
- OS env now properly wins over dotenv (R6 MUST compliance)
- Hardened dotenv value quoting with escape sequences
- Added rollback safety to set_env() file writes

Deterministic, scoped dotenv loading for AEON/library/ with directory-level
opt-in/out control via <DIRNAME>_CANONICAL_IGNORE flags.

Features:
- AEON base directory detection and path validation
- Scoped dotenv loading with directory gating
- Environment precedence: OS > CLI overlay > manifest > dotenv (FIXED)
- READONLY locks for immutable variables
- Ops functions: env_list, env_debug, set_env, unset_env
- Atomic dotenv writes with comment preservation
"""

import os
import sys
import re
import json
import tempfile
import shutil
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any
from dataclasses import dataclass, field
from enum import Enum


__version__ = "0.3.1"


class EnvSource(Enum):
    """Source of an environment variable with priority support."""
    OS = "os"
    CLI_OVERLAY = "cli_overlay"
    MANIFEST = "manifest"
    DOTENV = "dotenv"
    RUNTIME_SET = "runtime_set"
    
    def priority(self) -> int:
        """
        Return numeric priority for precedence enforcement.
        
        Higher number = higher priority (wins in conflicts).
        R6 MUST: OS > CLI_OVERLAY > MANIFEST > DOTENV
        
        Priority scale:
          1 = DOTENV (lowest)
          2 = MANIFEST
          3 = CLI_OVERLAY
          4 = OS
          5 = RUNTIME_SET (highest, explicit runtime override)
        """
        priorities = {
            EnvSource.DOTENV: 1,
            EnvSource.MANIFEST: 2,
            EnvSource.CLI_OVERLAY: 3,
            EnvSource.OS: 4,
            EnvSource.RUNTIME_SET: 5,
        }
        return priorities[self]


@dataclass
class EnvVarMetadata:
    """Metadata for a single environment variable."""
    name: str
    value: str
    source: EnvSource
    origin_file: Optional[str] = None
    readonly: bool = False
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            "name": self.name,
            "value": self.value,
            "source": self.source.value,
            "origin_file": self.origin_file,
            "readonly": self.readonly
        }


@dataclass
class EnvState:
    """
    Environment state with per-key metadata and debug traces.
    
    This is the core state container that tracks all environment variables,
    their sources, and readonly locks.
    
    v0.3.1: Now enforces priority-based precedence in set_var().
    """
    variables: Dict[str, EnvVarMetadata] = field(default_factory=dict)
    loaded_files: List[str] = field(default_factory=list)
    ignored_dirs: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    aeon_base: Optional[Path] = None
    python_base: Optional[Path] = None
    
    def set_var(self, name: str, value: str, source: EnvSource, 
                origin_file: Optional[str] = None, readonly: bool = False) -> bool:
        """
        Set a variable with priority-based precedence enforcement.
        
        v0.3.1 FIX: Now checks both readonly AND priority before allowing override.
        
        Precedence rules:
        1. If existing var is readonly: BLOCK all overrides
        2. Else: Allow override ONLY if new_priority >= old_priority
        3. Same priority may override (needed for "later dotenv wins")
        
        This ensures OS > CLI > MANIFEST > DOTENV (R6 MUST).
        
        Args:
            name: Variable name
            value: Variable value
            source: Source layer (determines priority)
            origin_file: Optional file path (for dotenv tracing)
            readonly: If True, locks this variable against future overwrites
        
        Returns:
            True if variable was set, False if blocked by readonly or priority.
        """
        existing = self.variables.get(name)
        
        # Rule 1: Readonly lock blocks ALL overrides
        if existing and existing.readonly:
            return False
        
        # Rule 2: Priority-based precedence
        if existing:
            new_priority = source.priority()
            old_priority = existing.source.priority()
            
            # Allow override only if new priority >= old priority
            if new_priority < old_priority:
                return False
        
        # Set or update variable
        self.variables[name] = EnvVarMetadata(
            name=name,
            value=value,
            source=source,
            origin_file=origin_file,
            readonly=readonly
        )
        return True
    
    def get_var(self, name: str) -> Optional[EnvVarMetadata]:
        """Get variable metadata."""
        return self.variables.get(name)
    
    def remove_var(self, name: str) -> bool:
        """Remove a variable if not readonly-locked."""
        if name in self.variables and self.variables[name].readonly:
            return False
        if name in self.variables:
            del self.variables[name]
            return True
        return False


class AEONPathError(Exception):
    """Raised when path validation fails."""
    pass


class AEONEnvError(Exception):
    """Raised for environment layer errors."""
    pass


def canonicalize_dirname(dirname: str) -> str:
    """
    Convert directory name to canonical form for ignore flags.
    
    Rules:
    - Convert to uppercase
    - Replace non-alphanumeric with underscore
    
    Example: "my-actions" -> "MY_ACTIONS"
    """
    return re.sub(r'[^A-Z0-9]+', '_', dirname.upper())


def detect_aeon_base(script_path: Optional[Path] = None, 
                     provided_base: Optional[Path] = None) -> Path:
    """
    Detect AEON base directory.
    
    Priority order:
    1) OS env AEON_BASEDIR if set
    2) provided_base argument
    3) Auto-detect from script_path by searching upward for marker dirs
    
    Marker directories: library/, logfiles/, tmp/
    
    Raises:
        AEONPathError if base directory cannot be determined
    """
    # Priority 1: OS environment
    if "AEON_BASEDIR" in os.environ:
        base = Path(os.environ["AEON_BASEDIR"]).resolve()
        if _validate_aeon_base(base):
            return base
    
    # Priority 2: Provided base
    if provided_base:
        base = Path(provided_base).resolve()
        if _validate_aeon_base(base):
            return base
    
    # Priority 3: Auto-detect from script path
    if script_path:
        current = Path(script_path).resolve()
        for parent in [current] + list(current.parents):
            if _validate_aeon_base(parent):
                return parent
    
    raise AEONPathError(
        "Cannot detect AEON base directory. "
        "Set AEON_BASEDIR environment variable or provide base_dir parameter."
    )


def _validate_aeon_base(path: Path) -> bool:
    """Check if path contains required AEON marker directories."""
    required = ["library", "logfiles", "tmp"]
    return all((path / marker).is_dir() for marker in required)


def validate_relative_path(path_str: str, base_dir: Path) -> Path:
    """
    Validate that path is relative to base_dir and contains no traversals.
    
    Rules:
    - Must be relative (no absolute paths)
    - No '..' traversal allowed
    - After normalization, must remain within base_dir
    
    Raises:
        AEONPathError if validation fails
    """
    path_obj = Path(path_str)
    
    # Reject absolute paths
    if path_obj.is_absolute():
        raise AEONPathError(f"Absolute paths not allowed: {path_str}")
    
    # Reject '..' traversal
    if ".." in path_obj.parts:
        raise AEONPathError(f"Path traversal (..) not allowed: {path_str}")
    
    # Normalize and check containment
    full_path = (base_dir / path_obj).resolve()
    try:
        full_path.relative_to(base_dir.resolve())
    except ValueError:
        raise AEONPathError(f"Path escapes base directory: {path_str}")
    
    return full_path


def parse_dotenv_line(line: str) -> Optional[Tuple[str, str, bool]]:
    """
    Parse a single dotenv line.
    
    Returns:
        (key, value, is_readonly) tuple or None if not a key=value line
    """
    line = line.strip()
    
    # Skip empty lines and comments
    if not line or line.startswith("#"):
        return None
    
    # Match KEY=VALUE or READONLY_KEY=VALUE
    match = re.match(r'^(READONLY_)?([A-Z0-9_]+)\s*=\s*(.*)$', line)
    if not match:
        return None
    
    readonly_prefix, key, value = match.groups()
    is_readonly = bool(readonly_prefix)
    
    # Remove quotes if present
    value = value.strip()
    if (value.startswith('"') and value.endswith('"')) or \
       (value.startswith("'") and value.endswith("'")):
        value = value[1:-1]
        # Unescape standard sequences
        value = value.replace('\\n', '\n')
        value = value.replace('\\r', '\r')
        value = value.replace('\\t', '\t')
        value = value.replace('\\\\', '\\')
        value = value.replace('\\"', '"')
    
    return (key, value, is_readonly)


def quote_value(value: str) -> str:
    """
    Quote a value for safe dotenv storage with proper escaping.
    
    v0.3.1: Hardened quoting with escape sequences for special characters.
    
    Escapes: backslash, double-quote, newline, carriage return, tab
    Quotes: when value contains special chars
    """
    # Escape special characters
    escaped = value.replace('\\', '\\\\')  # Backslash FIRST
    escaped = escaped.replace('"', '\\"')   # Double quote
    escaped = escaped.replace('\n', '\\n')  # Newline
    escaped = escaped.replace('\r', '\\r')  # Carriage return
    escaped = escaped.replace('\t', '\\t')  # Tab
    
    # Quote if value contains spaces, #, or special chars
    if any(char in value for char in [' ', '#', '"', "'", '\n', '\r', '\t']):
        return f'"{escaped}"'
    
    # Quote if starts/ends with whitespace
    if value != value.strip():
        return f'"{escaped}"'
    
    return escaped


class AtomicDotenvWriter:
    """
    Context manager for atomic dotenv file writing with comment preservation.
    
    v0.3.1: Enhanced error handling and rollback safety.
    
    Usage:
        with AtomicDotenvWriter(filepath) as writer:
            writer.set_key("FOO", "bar")
            writer.set_key("READONLY_BAZ", "qux")
    """
    
    def __init__(self, filepath: Path):
        self.filepath = filepath
        self.lines: List[str] = []
        self.keys_seen: set = set()
        self.temp_file: Optional[Path] = None
        
        # Load existing content if file exists
        if filepath.exists():
            with open(filepath, 'r', encoding='utf-8') as f:
                self.lines = [line.rstrip('\n\r') for line in f]
    
    def __enter__(self):
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Write atomically on successful exit."""
        if exc_type is None:
            self._write_atomic()
        return False
    
    def set_key(self, key: str, value: str, readonly: bool = False):
        """Set or update a key=value pair."""
        # Validate key
        if not re.match(r'^[A-Z0-9_]+$', key):
            raise AEONEnvError(f"Invalid key format: {key}")
        
        prefix = "READONLY_" if readonly else ""
        full_key = f"{prefix}{key}"
        line_to_write = f"{full_key}={quote_value(value)}"
        
        # Try to update existing key
        updated = False
        for i, line in enumerate(self.lines):
            parsed = parse_dotenv_line(line)
            if parsed:
                existing_key, _, existing_readonly = parsed
                existing_full_key = f"{'READONLY_' if existing_readonly else ''}{existing_key}"
                if existing_full_key == full_key:
                    self.lines[i] = line_to_write
                    updated = True
                    break
        
        # Add new key if not found
        if not updated:
            self.lines.append(line_to_write)
        
        self.keys_seen.add(full_key)
    
    def remove_key(self, key: str, comment_out: bool = True):
        """Remove or comment out a key."""
        patterns = [
            f"^{key}=",
            f"^READONLY_{key}="
        ]
        
        new_lines = []
        for line in self.lines:
            if any(re.match(pattern, line.strip()) for pattern in patterns):
                if comment_out:
                    new_lines.append(f"# {line}")
            else:
                new_lines.append(line)
        
        self.lines = new_lines
    
    def _write_atomic(self):
        """
        Write to temp file, then replace original.
        
        v0.3.1: Enhanced with proper error handling.
        """
        # Create temp file in same directory for atomic rename
        temp_fd, temp_path = tempfile.mkstemp(
            dir=self.filepath.parent,
            prefix=f".{self.filepath.name}.",
            suffix=".tmp"
        )
        
        try:
            with os.fdopen(temp_fd, 'w', encoding='utf-8') as f:
                for line in self.lines:
                    f.write(line + '\n')
            
            # Atomic replace
            shutil.move(temp_path, self.filepath)
        except Exception:
            # Clean up temp file on error
            if os.path.exists(temp_path):
                os.unlink(temp_path)
            raise


class EnvironmentLoader:
    """
    Main environment loader with scoped dotenv loading and directory gating.
    
    v0.3.1: Priority-based precedence now properly enforced via EnvState.set_var().
    """
    
    def __init__(self, script_path: Optional[Path] = None,
                 base_dir: Optional[Path] = None,
                 strict: bool = False):
        """
        Initialize environment loader.
        
        Args:
            script_path: Path to the python script (for auto-detection)
            base_dir: Explicit AEON base directory
            strict: If True, missing CANONICAL_IGNORE flags are errors
        """
        self.strict = strict
        self.state = EnvState()
        
        # Detect AEON base
        self.state.aeon_base = detect_aeon_base(script_path, base_dir)
        self.state.python_base = self.state.aeon_base / "library" / "python"
        
        # Load OS environment first (highest priority)
        self._load_os_environment()
    
    def _load_os_environment(self):
        """Load existing OS environment variables."""
        for key, value in os.environ.items():
            self.state.set_var(key, value, EnvSource.OS)
    
    def load_for_script(self, script_path: Path, 
                       cli_overlay: Optional[Dict[str, str]] = None,
                       manifest_vars: Optional[Dict[str, str]] = None):
        """
        Load environment for a specific script.
        
        Load order (base -> specific):
        1. OS env (already loaded, highest priority) ← v0.3.1: now enforced
        2. Dotenv files (lowest priority)
        3. Manifest vars (override dotenv)
        4. CLI overlay (override manifest)
        
        v0.3.1: The load order no longer determines precedence; priority does.
        
        Args:
            script_path: Path to the Python script
            cli_overlay: CLI flag overrides
            manifest_vars: Manifest-defined variables
        """
        script_path = Path(script_path).resolve()
        
        # Validate script is under python base
        try:
            rel_path = script_path.relative_to(self.state.python_base)
        except ValueError:
            raise AEONPathError(
                f"Script must be under {self.state.python_base}: {script_path}"
            )
        
        # Collect dotenv files to load
        dotenv_files = self._discover_dotenv_files(script_path)
        
        # Load dotenv files (lowest priority - will not override OS)
        for env_file in dotenv_files:
            self._load_dotenv_file(env_file)
        
        # Apply manifest vars (override dotenv, but not OS)
        if manifest_vars:
            for key, value in manifest_vars.items():
                if not self.state.set_var(key, value, EnvSource.MANIFEST):
                    self.state.warnings.append(
                        f"Manifest var blocked by higher priority: {key}"
                    )
        
        # Apply CLI overlay (override manifest and dotenv, but not OS)
        if cli_overlay:
            for key, value in cli_overlay.items():
                if not self.state.set_var(key, value, EnvSource.CLI_OVERLAY):
                    self.state.warnings.append(
                        f"CLI overlay blocked: {key} (readonly or higher priority)"
                    )
    
    def _discover_dotenv_files(self, script_path: Path) -> List[Path]:
        """
        Discover dotenv files for a script, respecting directory gating.
        
        Returns list in load order (base -> specific).
        """
        files = []
        script_path = script_path.resolve()
        
        # Get path components from python base to script
        rel_path = script_path.relative_to(self.state.python_base)
        path_parts = rel_path.parts[:-1]  # Exclude script filename
        
        # Check python base __init__.env
        base_init = self.state.python_base / "__init__.env"
        if base_init.exists():
            if self._check_directory_allowed(self.state.python_base):
                files.append(base_init)
            else:
                self.state.ignored_dirs.append(str(self.state.python_base))
                return []  # Entire tree ignored
        
        # Walk through subdirectories
        current_path = self.state.python_base
        for part in path_parts:
            current_path = current_path / part
            
            # Check if this directory is allowed
            if not self._check_directory_allowed(current_path):
                self.state.ignored_dirs.append(str(current_path))
                return files  # Stop here, subtree ignored
            
            # Add __init__.env if exists
            init_env = current_path / "__init__.env"
            if init_env.exists():
                files.append(init_env)
        
        # Add script-specific env file
        script_basename = script_path.stem  # filename without .py
        script_env = script_path.parent / f"{script_basename}.env"
        if script_env.exists():
            files.append(script_env)
        
        return files
    
    def _check_directory_allowed(self, dir_path: Path) -> bool:
        """
        Check if directory scope is allowed via CANONICAL_IGNORE flag.
        
        Returns:
            True if allowed (CANONICAL_IGNORE=false or not present in non-strict)
            False if ignored (CANONICAL_IGNORE=true)
        """
        init_env = dir_path / "__init__.env"
        if not init_env.exists():
            return True  # No __init__.env means no gating
        
        # Parse for CANONICAL_IGNORE flag
        dirname = dir_path.name
        canonical_name = canonicalize_dirname(dirname)
        flag_name = f"{canonical_name}_CANONICAL_IGNORE"
        
        # Quick parse to find the flag
        flag_value = None
        try:
            with open(init_env, 'r', encoding='utf-8') as f:
                for line in f:
                    parsed = parse_dotenv_line(line)
                    if parsed:
                        key, value, _ = parsed
                        if key == flag_name:
                            flag_value = value.lower()
                            break
        except Exception as e:
            self.state.warnings.append(f"Error reading {init_env}: {e}")
            return False  # Safe default
        
        # Interpret flag
        if flag_value is None:
            if self.strict:
                raise AEONEnvError(
                    f"Missing {flag_name} in {init_env} (strict mode)"
                )
            else:
                self.state.warnings.append(
                    f"Missing {flag_name} in {init_env}, treating as 'true' (ignored)"
                )
                return False  # Safe default: ignore
        
        if flag_value == "true":
            return False  # Explicitly ignored
        elif flag_value == "false":
            return True  # Explicitly allowed
        else:
            if self.strict:
                raise AEONEnvError(
                    f"Invalid {flag_name}={flag_value} in {init_env}"
                )
            else:
                self.state.warnings.append(
                    f"Invalid {flag_name}={flag_value}, treating as 'true' (ignored)"
                )
                return False  # Safe default
    
    def _load_dotenv_file(self, filepath: Path):
        """Load a single dotenv file with READONLY support."""
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                for line in f:
                    parsed = parse_dotenv_line(line)
                    if parsed:
                        key, value, is_readonly = parsed
                        
                        # Skip control variables (CANONICAL_IGNORE)
                        if "_CANONICAL_IGNORE" in key:
                            continue
                        
                        # Set variable (respects priority and readonly locks)
                        # v0.3.1: This now correctly blocks dotenv from overriding OS
                        success = self.state.set_var(
                            key, value, EnvSource.DOTENV,
                            origin_file=str(filepath),
                            readonly=is_readonly
                        )
                        
                        if not success:
                            self.state.warnings.append(
                                f"Dotenv blocked by higher priority or readonly: {key} in {filepath}"
                            )
            
            self.state.loaded_files.append(str(filepath))
        
        except Exception as e:
            self.state.warnings.append(f"Error loading {filepath}: {e}")


# ============================================================================
# OPS FUNCTIONS
# ============================================================================

def env_list(state: EnvState, format: str = "text", 
             show_sensitive: bool = False) -> str:
    """
    List all environment variables with metadata.
    
    Args:
        state: EnvState instance
        format: "text" or "json"
        show_sensitive: If False, redact values for sensitive-looking keys
    
    Returns:
        Formatted string (text or JSON)
    """
    if format == "json":
        data = []
        for var in sorted(state.variables.values(), key=lambda v: v.name):
            var_dict = var.to_dict()
            if not show_sensitive and _is_sensitive_key(var.name):
                var_dict["value"] = "***REDACTED***"
            data.append(var_dict)
        return json.dumps(data, indent=2)
    
    else:  # text format
        lines = []
        lines.append("=" * 80)
        lines.append("ENVIRONMENT VARIABLES")
        lines.append("=" * 80)
        
        for var in sorted(state.variables.values(), key=lambda v: v.name):
            value = var.value
            if not show_sensitive and _is_sensitive_key(var.name):
                value = "***REDACTED***"
            
            lines.append(f"\n{var.name}")
            lines.append(f"  Value:    {value}")
            lines.append(f"  Source:   {var.source.value}")
            if var.origin_file:
                lines.append(f"  Origin:   {var.origin_file}")
            lines.append(f"  Readonly: {var.readonly}")
        
        lines.append("\n" + "=" * 80)
        return "\n".join(lines)


def env_debug(state: EnvState, show_values: bool = False) -> str:
    """
    Print debug information about environment loading.
    
    Args:
        state: EnvState instance
        show_values: If True, include variable values
    
    Returns:
        Debug information as string
    """
    lines = []
    lines.append("=" * 80)
    lines.append("ENVIRONMENT DEBUG")
    lines.append("=" * 80)
    
    # Directories
    lines.append(f"\nAEON Base:   {state.aeon_base}")
    lines.append(f"Python Base: {state.python_base}")
    
    # Loaded files
    lines.append(f"\nLoaded .env files ({len(state.loaded_files)}):")
    for filepath in state.loaded_files:
        lines.append(f"  - {filepath}")
    
    # Ignored directories
    if state.ignored_dirs:
        lines.append(f"\nIgnored directories ({len(state.ignored_dirs)}):")
        for dirpath in state.ignored_dirs:
            lines.append(f"  - {dirpath}")
    
    # Variables
    lines.append(f"\nTotal variables: {len(state.variables)}")
    
    # By source
    by_source = {}
    for var in state.variables.values():
        source = var.source.value
        by_source[source] = by_source.get(source, 0) + 1
    
    lines.append("\nBy source:")
    for source, count in sorted(by_source.items()):
        lines.append(f"  {source}: {count}")
    
    # Readonly locks
    readonly_vars = [v.name for v in state.variables.values() if v.readonly]
    if readonly_vars:
        lines.append(f"\nReadonly locks ({len(readonly_vars)}):")
        for name in sorted(readonly_vars):
            lines.append(f"  - {name}")
    
    # Variable listing
    if show_values:
        lines.append("\nVariables (name=value):")
        for var in sorted(state.variables.values(), key=lambda v: v.name):
            lines.append(f"  {var.name}={var.value}")
    else:
        lines.append("\nVariable names:")
        for name in sorted(state.variables.keys()):
            readonly_marker = " [RO]" if state.variables[name].readonly else ""
            lines.append(f"  - {name}{readonly_marker}")
    
    # Warnings
    if state.warnings:
        lines.append(f"\nWarnings ({len(state.warnings)}):")
        for warning in state.warnings:
            lines.append(f"  ! {warning}")
    
    lines.append("\n" + "=" * 80)
    return "\n".join(lines)


def set_env(state: EnvState, name: str, value: str,
            save: bool = False,
            save_path: Optional[str] = None,
            readonly: bool = False,
            script_path: Optional[Path] = None) -> bool:
    """
    Set an environment variable (runtime and/or persistent).
    
    v0.3.1: Enhanced with rollback safety for file writes.
    
    Args:
        state: EnvState instance
        name: Variable name
        value: Variable value
        save: If True, save to script-specific .env file
        save_path: Explicit save path (overrides save)
        readonly: If True, write as READONLY_<n>
        script_path: Required if save=True and save_path not provided
    
    Returns:
        True if successful, False if blocked by readonly lock or priority
    """
    # Validate key format
    if not re.match(r'^[A-Z0-9_]+$', name):
        raise AEONEnvError(f"Invalid variable name: {name}")
    
    # Save to file FIRST (before runtime), for rollback safety
    if save_path or save:
        if save_path:
            # Validate explicit path
            target_path = validate_relative_path(save_path, state.aeon_base)
        else:
            # Default: script-specific .env
            if not script_path:
                raise AEONEnvError("script_path required when save=True")
            
            script_path = Path(script_path).resolve()
            script_basename = script_path.stem
            target_path = script_path.parent / f"{script_basename}.env"
        
        # Write atomically (may raise exception)
        with AtomicDotenvWriter(target_path) as writer:
            writer.set_key(name, value, readonly=readonly)
    
    # Only set runtime AFTER successful file write
    success = state.set_var(name, value, EnvSource.RUNTIME_SET, readonly=readonly)
    if not success:
        return False
    
    # Also set in actual process environment
    os.environ[name] = value
    
    return True


def unset_env(state: EnvState, name: str,
              save: bool = False,
              save_path: Optional[str] = None,
              script_path: Optional[Path] = None) -> bool:
    """
    Unset an environment variable (runtime and/or persistent).
    
    Args:
        state: EnvState instance
        name: Variable name
        save: If True, comment out in script-specific .env file
        save_path: Explicit save path (overrides save)
        script_path: Required if save=True and save_path not provided
    
    Returns:
        True if successful, False if blocked by readonly lock
    """
    # Remove from runtime
    success = state.remove_var(name)
    if not success:
        return False
    
    # Also remove from process environment
    if name in os.environ:
        del os.environ[name]
    
    # Comment out in file if requested
    if save_path or save:
        if save_path:
            target_path = validate_relative_path(save_path, state.aeon_base)
        else:
            if not script_path:
                raise AEONEnvError("script_path required when save=True")
            
            script_path = Path(script_path).resolve()
            script_basename = script_path.stem
            target_path = script_path.parent / f"{script_basename}.env"
        
        if target_path.exists():
            with AtomicDotenvWriter(target_path) as writer:
                writer.remove_key(name, comment_out=True)
    
    return True


def _is_sensitive_key(key: str) -> bool:
    """Check if a key looks like it might contain sensitive data."""
    sensitive_patterns = [
        'PASSWORD', 'SECRET', 'TOKEN', 'KEY', 'CREDENTIALS',
        'API_KEY', 'AUTH', 'PRIVATE'
    ]
    key_upper = key.upper()
    return any(pattern in key_upper for pattern in sensitive_patterns)


# ============================================================================
# CONVENIENCE API
# ============================================================================

def quick_load(script_path: Optional[str] = None,
               base_dir: Optional[str] = None,
               cli_overlay: Optional[Dict[str, str]] = None,
               strict: bool = False) -> EnvState:
    """
    Convenience function for quick environment loading.
    
    Args:
        script_path: Path to the calling script (auto-detect if None)
        base_dir: AEON base directory (auto-detect if None)
        cli_overlay: CLI flag overrides
        strict: Strict mode for CANONICAL_IGNORE validation
    
    Returns:
        Loaded EnvState instance
    
    Example:
        state = quick_load(__file__)
        print(env_debug(state))
    """
    # Auto-detect script path
    if script_path is None:
        import inspect
        frame = inspect.currentframe()
        if frame and frame.f_back:
            script_path = frame.f_back.f_code.co_filename
    
    if script_path:
        script_path = Path(script_path)
    
    loader = EnvironmentLoader(
        script_path=script_path,
        base_dir=Path(base_dir) if base_dir else None,
        strict=strict
    )
    
    if script_path:
        loader.load_for_script(script_path, cli_overlay=cli_overlay)
    
    return loader.state


# ============================================================================
# CLI INTERFACE (for direct execution)
# ============================================================================

def main():
    """CLI interface for environment layer operations."""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="AEON Environment Layer CLI v0.3.1",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Debug environment for a script
  python environment_layer.py debug --script myscript.py
  
  # List all variables
  python environment_layer.py list --script myscript.py
  
  # Set a variable (runtime only)
  python environment_layer.py set FOO bar --script myscript.py
  
  # Set and save to script.env
  python environment_layer.py set FOO bar --script myscript.py --save
  
  # Set as readonly
  python environment_layer.py set FOO bar --script myscript.py --save --readonly
"""
    )
    
    parser.add_argument('--script', required=True, help='Script path')
    parser.add_argument('--base-dir', help='AEON base directory')
    parser.add_argument('--strict', action='store_true', help='Strict mode')
    
    subparsers = parser.add_subparsers(dest='command', required=True)
    
    # Debug command
    debug_parser = subparsers.add_parser('debug', help='Show debug information')
    debug_parser.add_argument('--show-values', action='store_true',
                             help='Show variable values')
    
    # List command
    list_parser = subparsers.add_parser('list', help='List all variables')
    list_parser.add_argument('--format', choices=['text', 'json'], default='text')
    list_parser.add_argument('--show-sensitive', action='store_true',
                            help='Show sensitive values')
    
    # Set command
    set_parser = subparsers.add_parser('set', help='Set a variable')
    set_parser.add_argument('name', help='Variable name')
    set_parser.add_argument('value', help='Variable value')
    set_parser.add_argument('--save', action='store_true', help='Save to .env file')
    set_parser.add_argument('--save-path', help='Explicit save path')
    set_parser.add_argument('--readonly', action='store_true', help='Set as readonly')
    
    # Unset command
    unset_parser = subparsers.add_parser('unset', help='Unset a variable')
    unset_parser.add_argument('name', help='Variable name')
    unset_parser.add_argument('--save', action='store_true',
                             help='Comment out in .env file')
    unset_parser.add_argument('--save-path', help='Explicit save path')
    
    args = parser.parse_args()
    
    # Load environment
    try:
        script_path = Path(args.script)
        loader = EnvironmentLoader(
            script_path=script_path,
            base_dir=Path(args.base_dir) if args.base_dir else None,
            strict=args.strict
        )
        loader.load_for_script(script_path)
        
        # Execute command
        if args.command == 'debug':
            print(env_debug(loader.state, show_values=args.show_values))
        
        elif args.command == 'list':
            print(env_list(loader.state, format=args.format,
                          show_sensitive=args.show_sensitive))
        
        elif args.command == 'set':
            success = set_env(
                loader.state, args.name, args.value,
                save=args.save,
                save_path=args.save_path,
                readonly=args.readonly,
                script_path=script_path
            )
            if success:
                print(f"✓ Set {args.name}={args.value}")
            else:
                print(f"✗ Blocked by readonly lock or priority: {args.name}")
                sys.exit(1)
        
        elif args.command == 'unset':
            success = unset_env(
                loader.state, args.name,
                save=args.save,
                save_path=args.save_path,
                script_path=script_path
            )
            if success:
                print(f"✓ Unset {args.name}")
            else:
                print(f"✗ Blocked by readonly lock: {args.name}")
                sys.exit(1)
    
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
