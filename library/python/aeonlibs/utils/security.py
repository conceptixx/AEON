# -*- coding: utf-8 -*-
"""
Security Utilities

Path validation and security functions to prevent directory traversal attacks
and enforce security boundaries.

sys.path: Must contain '/path/to/aeon'
Location: library/python/aeonlibs/utils/security.py
"""

from pathlib import Path


class SecurityError(Exception):
    """Path security validation failed"""
    pass


def validate_path_security(path: str, root: str) -> bool:
    """
    Validate that a path is contained within a root directory.
    
    This is the core security function preventing directory traversal attacks.
    It ensures all file operations remain within the designated AEON root,
    implementing the principle of least privilege for filesystem access.
    
    :param path: Path to validate (absolute or relative)
    :param root: Root directory that must contain the path
    :return: True if path is under root, False otherwise
    
    :security_note:
        Uses Path.resolve() to normalize paths before comparison,
        preventing symlink attacks and ../ traversal.
    
    :example:
        >>> validate_path_security("/opt/aeon/tmp/repo", "/opt/aeon")
        True
        >>> validate_path_security("/tmp/evil", "/opt/aeon")
        False
    """
    # Resolve to absolute paths to eliminate symlinks and relative components
    abs_path = Path(path).resolve()
    abs_root = Path(root).resolve()
    
    # Check if path is descendant of root
    try:
        abs_path.relative_to(abs_root)
        return True
    except ValueError:
        # Path is outside root boundary
        return False


def resolve_path(path: str, aeon_root: str, path_type: str = "file") -> str:
    """
    Resolve a relative path to absolute with security validation.
    
    SECURITY: All paths MUST be relative to aeon_root.
    Absolute paths are rejected to prevent directory traversal attacks.
    
    :param path: Relative path to resolve
    :param aeon_root: Root directory for resolution
    :param path_type: Type descriptor for error messages
    :return: Absolute path within aeon_root
    :raises ValueError: If path is absolute
    :raises SecurityError: If resolved path is outside aeon_root
    
    :example:
        >>> resolve_path("manifest/install.json", "/opt/aeon")
        '/opt/aeon/manifest/install.json'
        
        >>> resolve_path("/etc/passwd", "/opt/aeon")
        ValueError: Security violation: file path must be relative
        
        >>> resolve_path("../../etc/passwd", "/opt/aeon")
        SecurityError: Security violation: file path outside root
    """
    # Reject absolute paths
    if Path(path).is_absolute():
        raise ValueError(
            f"Security violation: {path_type} path must be relative.\n"
            f"  Given: {path}\n"
            f"  Root: {aeon_root}\n"
            f"\n"
            f"Example:\n"
            f"  ✓ manifest/install.json\n"
            f"  ✗ /opt/aeon/manifest/install.json"
        )
    
    # Resolve to absolute path
    absolute_path = Path(aeon_root) / path
    
    # Validate security boundary
    if not validate_path_security(str(absolute_path), aeon_root):
        raise SecurityError(
            f"Security violation: {path_type} path outside root.\n"
            f"  Given: {path}\n"
            f"  Resolves to: {absolute_path.resolve()}\n"
            f"  Root: {aeon_root}\n"
            f"\n"
            f"Attempted directory traversal detected.\n"
            f"All paths must resolve to locations within the AEON root."
        )
    
    return str(absolute_path)