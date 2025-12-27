# -*- coding: utf-8 -*-
"""
CLI Argument Parser

Parse command line arguments with flexible syntax support.

sys.path: Must contain '/path/to/aeon'
Location: library/python/orchestrator/engines/cli.py
"""

from typing import Any, Dict, List, Tuple, Optional


def parse_orchestrator_args(argv: List[str]) -> Tuple[Optional[str], Optional[str], Optional[str], Dict[str, Any], List[str]]:
    """
    Parse command line arguments with flexible syntax support.
    
    Supports multiple syntax styles for user convenience:
    - --root:PATH or --root=PATH (OPTIONAL - auto-discovered if not provided)
    - --repo:PATH or --repo=PATH (OPTIONAL - auto-discovered if not provided)
    - Colon or equals as key-value separators
    
    Security Note: --repo paths MUST be relative to --root
    
    :param argv: Command line arguments (typically sys.argv)
    :return: Tuple of (process_file, aeon_root, aeon_repo_rel, user_flags, arguments)
    
    :example:
        >>> parse_orchestrator_args([
            "orchestrator.py",
            "--file:install.instruct.json",
            "--root=/opt/aeon",
            "--repo:tmp/repo",
            "--ip=192.168.1.1"
        ])
        ("install.instruct.json", "/opt/aeon", "tmp/repo", 
         {"--ip": "192.168.1.1"}, [])
        
        # Optional root/repo (will be auto-discovered)
        >>> parse_orchestrator_args([
            "orchestrator.py",
            "--file:install.instruct.json",
            "--ip=192.168.1.1"
        ])
        ("install.instruct.json", None, None, 
         {"--ip": "192.168.1.1"}, [])
    """
    process_file = None
    aeon_root = None
    aeon_repo_rel = None
    user_flags = {}
    arguments = []
    
    i = 1  # Skip script name
    while i < len(argv):
        arg = argv[i]
        
        # Process file specification
        if arg.startswith('--file=') or arg.startswith('--file:'):
            process_file = arg.split('=', 1)[1] if '=' in arg else arg.split(':', 1)[1]
        
        # Root path (absolute path required) - NOW OPTIONAL
        elif arg.startswith('--root=') or arg.startswith('--root:'):
            aeon_root = arg.split('=', 1)[1] if '=' in arg else arg.split(':', 1)[1]
        
        # Repo path (MUST be relative to root for security) - NOW OPTIONAL
        elif arg.startswith('--repo=') or arg.startswith('--repo:'):
            aeon_repo_rel = arg.split('=', 1)[1] if '=' in arg else arg.split(':', 1)[1]
            # Remove leading slash to ensure it's relative
            aeon_repo_rel = aeon_repo_rel.lstrip('/')
        
        # Long flags with values
        elif arg.startswith('--'):
            if '=' in arg or ':' in arg:
                separator = '=' if '=' in arg else ':'
                flag_name, flag_value = arg.split(separator, 1)
                user_flags[flag_name] = flag_value
            else:
                user_flags[arg] = True
        
        # Short flags
        elif arg.startswith('-') and len(arg) > 1:
            if '=' in arg or ':' in arg:
                separator = '=' if '=' in arg else ':'
                flag_name, flag_value = arg.split(separator, 1)
                user_flags[flag_name] = flag_value
            else:
                user_flags[arg] = True
        
        # Positional arguments
        else:
            arguments.append(arg)
        
        i += 1
    
    return process_file, aeon_root, aeon_repo_rel, user_flags, arguments
