#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
AEON Orchestrator - Main Entry Point

This is the primary entry point for running AEON orchestrator processes.
Sets up Python path and executes the main orchestrator logic.

Usage:
    python orchestrator.py --file:PROCESS.json [OPTIONS]
    
Examples:
    python orchestrator.py --file:install.instruct.json
    python orchestrator.py --file:install.instruct.json --root:/opt/aeon
    python orchestrator.py --file:smoketest.instruct.json --root:/opt/aeon --repo:tmp/repo

Location: library/python/orchestrator/engines/orchestrator.py
"""

import sys
import asyncio
from pathlib import Path


def setup_python_path():
    """
    Setup sys.path to enable library.python.* imports.
    
    Adds the AEON root directory to sys.path, which should be 4 levels up:
    orchestrator.py (here) → engines/ → orchestrator/ → python/ → library/ → AEON_ROOT
    """
    # Get AEON root (4 levels up from this file)
    orchestrator_file = Path(__file__).resolve()
    aeon_root = orchestrator_file.parents[4]  # Up 4 levels to /path/to/aeon
    
    # Add to sys.path if not already there
    aeon_root_str = str(aeon_root)
    if aeon_root_str not in sys.path:
        sys.path.insert(0, aeon_root_str)
    
    return aeon_root


if __name__ == "__main__":
    # Setup Python path BEFORE any library imports
    aeon_root = setup_python_path()
    
    # NOW we can import from library.python
    from library.python.orchestrator.engines.main import main
    
    # Run orchestrator
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n\n⚠️  Interrupted by user")
        sys.exit(130)
    except Exception as e:
        print(f"\n\n❌ Fatal error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
