"""
Dummy actions for testing AEON Orchestrator v1.0
"""


def apply_defaults(context, args):
    """
    Apply default selections
    
    Args:
        context: OrchestratorContext
        args: dict with optional configuration
    
    Returns:
        dict with selected items and source
    """
    return {
        "selected": ["tailscale", "nginx"],
        "source": "defaults"
    }


def fake_curses_menu(context, args):
    """
    Simulate a curses menu interaction
    
    Args:
        context: OrchestratorContext
        args: dict with menu options
    
    Returns:
        dict with selected items and abort status
    
    Raises:
        RuntimeError if called in noninteractive mode
    """
    if context.noninteractive:
        raise RuntimeError("fake_curses_menu should not be called in noninteractive mode")
    
    # Simulate user selecting tailscale
    return {
        "selected": ["tailscale"],
        "aborted": False
    }


def read_json_bool(context, args):
    """
    Read a JSON file and return boolean value for a given key
    
    Args:
        context: OrchestratorContext
        args: dict with 'path' and 'key'
    
    Returns:
        bool value from JSON
    """
    import json
    import os
    
    path = args.get('path')
    key = args.get('key')
    
    if not path or not key:
        raise ValueError("read_json_bool requires 'path' and 'key' arguments")
    
    # Resolve path relative to AEON_ROOT if needed
    if not os.path.isabs(path):
        path = os.path.join(context.aeon_root, path)
    
    with open(path, 'r') as f:
        data = json.load(f)
    
    return data.get(key, False)
