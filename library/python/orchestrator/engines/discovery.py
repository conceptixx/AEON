# -*- coding: utf-8 -*-
"""
AEON Path Auto-Discovery

Auto-discovery of AEON root and repository directories by traversing
upward from the starting directory.

sys.path: Must contain '/path/to/aeon'
Location: library/python/orchestrator/engines/discovery.py
"""

from pathlib import Path
from typing import Optional, Tuple


def discover_aeon_paths(start_dir: Optional[str] = None) -> Tuple[Optional[str], Optional[str]]:
    """
    Discover AEON root and repository directories by traversing upward from start directory.
    
    Discovery Algorithm:
    1. Start from start_dir (or current working directory)
    2. Walk upward through parent directories
    3. Check each directory for AEON markers:
       - REPO: Has /library subdirectory AND is located in /tmp → found repo_dir
       - ROOT: Has both /library AND /tmp subdirectories AND is located in /aeon → found root_dir
    
    Detection Rules:
    - Repo Dir: ../tmp/repo_dir/library exists → repo_dir = absolute path
    - Root Dir: ../aeon/tmp AND ../aeon/library exist → root_dir = absolute path to ../aeon
    
    :param start_dir: Starting directory for upward search (defaults to CWD)
    :return: Tuple of (aeon_root, aeon_repo) as absolute paths, or (None, None) if not found
    
    :example:
        # From /opt/aeon/tmp/repo/library/tasks
        >>> discover_aeon_paths()
        ('/opt/aeon', '/opt/aeon/tmp/repo')
        
        # From /usr/local/aeon/tmp/workspace/src
        >>> discover_aeon_paths()
        ('/usr/local/aeon', '/usr/local/aeon/tmp/workspace')
    """
    # Start from specified directory or current working directory
    current = Path(start_dir).resolve() if start_dir else Path.cwd().resolve()
    
    aeon_root = None
    aeon_repo = None
    
    # Walk upward through directory tree
    for parent in [current] + list(current.parents):
        # Check if this directory has /library subdirectory
        has_library = (parent / "library").is_dir()
        has_tmp = (parent / "tmp").is_dir()
        
        # REPO DETECTION: ../tmp/repo_dir/library
        # If current dir has /library AND parent is named "tmp"
        if has_library and parent.parent.name == "tmp":
            aeon_repo = str(parent)
        
        # ROOT DETECTION: ../aeon/tmp AND ../aeon/library
        # If current dir has both /library and /tmp AND parent is named "aeon"
        if has_library and has_tmp and parent.name == "aeon":
            aeon_root = str(parent)
        
        # Alternative ROOT DETECTION: check if this IS the aeon directory
        # by having both tmp/ and library/ subdirectories
        if has_library and has_tmp:
            # This could be the root if it's named "aeon" or contains both markers
            # Check if parent path contains "aeon" or this is a likely root
            if parent.name == "aeon" or (parent / "tmp").is_dir() and (parent / "library").is_dir():
                aeon_root = str(parent)
        
        # If we found both, we can stop searching
        if aeon_root and aeon_repo:
            break
    
    # Validation: if we found a repo but no root, try to infer root
    if aeon_repo and not aeon_root:
        # Repo should be at: /path/to/aeon/tmp/repo_name
        # So root should be 2 levels up from repo
        repo_path = Path(aeon_repo)
        potential_root = repo_path.parent.parent  # Go up from repo_name → tmp → aeon
        
        # Verify this is a valid root (has library/ and tmp/)
        if (potential_root / "library").is_dir() and (potential_root / "tmp").is_dir():
            aeon_root = str(potential_root)
    
    # Validation: if we found a root but no repo, try to use default
    if aeon_root and not aeon_repo:
        # Try default location: root/tmp/repo
        default_repo = Path(aeon_root) / "tmp" / "repo"
        if default_repo.is_dir():
            aeon_repo = str(default_repo)
    
    return aeon_root, aeon_repo
