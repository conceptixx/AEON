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
    
    Search Algorithm (EXACT ORDER):
    1. Start from script location (__file__)
    2. Walk upward through parent directories
    3. Find root_dir: first parent with BOTH /library AND /tmp subdirectories
    4. From root_dir, search downward:
       - Check root_dir/tmp for subdirectories
       - Find repo_dir: first subdir under /tmp that has /library
    
    Example Walk from /opt/aeon/tmp/repo/library/python/orchestrator/engines/orchestrator.py:
    - .../engines → no library, no tmp ✗
    - .../orchestrator → no library, no tmp ✗
    - .../python → no library, no tmp ✗
    - .../library → no library, no tmp ✗
    - .../repo → no library, no tmp ✗
    - .../tmp → no library, no tmp ✗
    - .../aeon → HAS library AND tmp ✓ → root_dir = /opt/aeon
    
    Then from root_dir (/opt/aeon):
    - root_dir/tmp → no library ✗
    - root_dir/tmp/repo → HAS library ✓ → repo_dir = /opt/aeon/tmp/repo
    
    :param start_dir: Starting directory for upward search (defaults to this file's location)
    :return: Tuple of (aeon_root, aeon_repo) as absolute paths, or (None, None) if not found
    
    :example:
        # Case 1: Standard install (repo under tmp)
        # From /opt/aeon/tmp/repo/library/python/orchestrator/engines/orchestrator.py
        >>> discover_aeon_paths()
        ('/opt/aeon', '/opt/aeon/tmp/repo')
        
        # Case 2: Development (root IS repo)
        # From /Users/name/Desktop/AEON/library/python/orchestrator/engines/discovery.py
        >>> discover_aeon_paths()
        ('/Users/name/Desktop/AEON', '/Users/name/Desktop/AEON')
    """
    # STEP 1: Start from script location
    if start_dir:
        current = Path(start_dir).resolve()
    else:
        current = Path(__file__).resolve().parent
    
    aeon_root = None
    aeon_repo = None
    
    # STEP 2: Walk UPWARD to find root_dir (has BOTH /library AND /tmp)
    for parent in [current] + list(current.parents):
        has_library = (parent / "library").is_dir()
        has_tmp = (parent / "tmp").is_dir()
        
        # Found root_dir: has BOTH library AND tmp
        if has_library and has_tmp:
            aeon_root = str(parent)
            break
    
    # No root found
    if not aeon_root:
        return None, None
    
    # STEP 3: From root_dir, search DOWNWARD in /tmp for repo_dir
    root_path = Path(aeon_root)
    tmp_path = root_path / "tmp"
    
    # Check if root_dir itself is repo (has library/python/orchestrator)
    if (root_path / "library" / "python" / "orchestrator").is_dir():
        # Root IS repo (development mode)
        aeon_repo = str(root_path)
    else:
        # Search in root_dir/tmp/* for subdirectory with /library
        if tmp_path.is_dir():
            for subdir in tmp_path.iterdir():
                if subdir.is_dir():
                    # Check if this subdir has /library
                    if (subdir / "library").is_dir():
                        # Verify it's AEON repo (has orchestrator structure)
                        if (subdir / "library" / "python" / "orchestrator").is_dir():
                            aeon_repo = str(subdir)
                            break
        
        # If no repo found under /tmp, root IS repo
        if not aeon_repo:
            aeon_repo = str(root_path)
    
    return aeon_root, aeon_repo
