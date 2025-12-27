# -*- coding: utf-8 -*-
"""
Orchestrator Main Entry Point

Orchestrates the complete execution flow:
1. Parse command line arguments
2. Auto-discover or validate paths
3. Load process definition
4. Initialize task registry with configurable state file
5. Execute entry point task
6. Handle success/error reporting

sys.path: Must contain '/path/to/aeon'
Location: library/python/orchestrator/engines/main.py
"""

import sys
import asyncio
from pathlib import Path

from library.python.orchestrator.core.registry import HierarchicalFutureRegistry
from library.python.orchestrator.core.task_loader import TaskLoader
from library.python.orchestrator.parser.orchestrator_parser_api import load_process_definition
from library.python.aeonlibs.utils.security import validate_path_security
from library.python.orchestrator.engines.cli import parse_orchestrator_args
from library.python.orchestrator.engines.discovery import discover_aeon_paths


async def main() -> None:
    """
    Main orchestrator execution.
    
    :exit_codes:
        0: Success
        1: Command line error or process failure
    """
    # Parse command line arguments (root and repo are now OPTIONAL)
    process_file, aeon_root, aeon_repo_rel, user_flags, arguments = parse_orchestrator_args(sys.argv)
    
    # Validate required arguments
    if not process_file:
        print("Usage: python orchestrator.py --file:PROCESS.json [FLAGS]")
        print("\nExamples:")
        print("  python orchestrator.py --file:install.instruct.json")
        print("  python orchestrator.py --file:install.instruct.json -c -w")
        print("  python orchestrator.py --file:install.instruct.json --root:/opt/aeon --repo:tmp/repo")
        print("  python orchestrator.py --file:smoketest.instruct.json")
        print("\nNote: --root and --repo are optional and will be auto-discovered if not provided.")
        sys.exit(1)
    
    # AUTO-DISCOVERY: If root/repo not provided via CLI, discover them
    if not aeon_root or not aeon_repo_rel:
        print("🔍 Auto-discovering AEON paths...")
        discovered_root, discovered_repo = discover_aeon_paths()
        
        # Use CLI values if provided, otherwise use discovered values
        if not aeon_root:
            aeon_root = discovered_root
        if not aeon_repo_rel and discovered_repo:
            # Convert discovered repo (absolute) to relative path
            if discovered_repo and aeon_root:
                aeon_repo_rel = str(Path(discovered_repo).relative_to(aeon_root))
        
        # Validation: ensure we found at least the root
        if not aeon_root:
            print("❌ Error: Could not auto-discover AEON root directory")
            print("\nAuto-discovery looks for:")
            print("  - A directory named 'aeon' with both 'library/' and 'tmp/' subdirectories")
            print("  - Repository in 'tmp/' with 'library/' subdirectory")
            print("\nPlease provide --root explicitly:")
            print("  python orchestrator.py --file:PROCESS.json --root:/opt/aeon")
            sys.exit(1)
        
        if discovered_root or discovered_repo:
            print(f"   ✓ Discovered Root: {aeon_root}")
            if discovered_repo:
                print(f"   ✓ Discovered Repo: {discovered_repo} (relative: {aeon_repo_rel})")
    
    # Compose repository path (always relative to root for security)
    if aeon_repo_rel:
        aeon_repo = f"{aeon_root}/{aeon_repo_rel}"
    else:
        # Default to tmp/repo if no repo specified
        aeon_repo_rel = "tmp/repo"
        aeon_repo = f"{aeon_root}/{aeon_repo_rel}"
    
    # Security validation: ensure repo is contained within root
    if not validate_path_security(aeon_repo, aeon_root):
        print("❌ Error: --repo must be relative to --root (security violation)")
        print(f"\n  Root: {aeon_root}")
        print(f"  Repo: {aeon_repo}")
        print(f"\nExample:")
        print(f"  --root:/opt/aeon --repo:tmp/repo")
        print(f"  Result: /opt/aeon/tmp/repo ✓")
        sys.exit(1)
    
    # Resolve process file path (search order: repo_dir -> root_dir -> error)
    process_file_path = None
    
    if Path(process_file).is_absolute():
        # Absolute path provided - use as-is
        process_file_path = process_file
    else:
        # Relative path - search in order: repo_dir -> root_dir
        search_locations = []
        
        # Priority 1: repo_dir (if different from root)
        if aeon_repo != aeon_root:
            repo_candidate = Path(aeon_repo) / process_file
            search_locations.append(("repo", str(repo_candidate)))
        
        # Priority 2: root_dir (always check)
        root_candidate = Path(aeon_root) / process_file
        search_locations.append(("root", str(root_candidate)))
        
        # Search in order until found
        for location_name, candidate_path in search_locations:
            if Path(candidate_path).is_file():
                process_file_path = candidate_path
                break
    
    # Validate file was found
    if not process_file_path or not Path(process_file_path).is_file():
        print(f"❌ Process file not found: {process_file}")
        print(f"\nSearched locations:")
        if not Path(process_file).is_absolute():
            for location_name, candidate_path in search_locations:
                exists = "✓" if Path(candidate_path).is_file() else "✗"
                print(f"   {exists} {location_name}: {candidate_path}")
        else:
            print(f"   ✗ {process_file_path}")
        sys.exit(1)
    
    # Load process definition (auto-detect format via ParserFactory)
    try:
        process_def = load_process_definition(process_file_path)
    except FileNotFoundError as e:
        print(f"❌ {e}")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error loading process file: {e}")
        sys.exit(1)
    
    # Display execution header
    print("\n" + "=" * 60)
    print(f"🚀 AEON Orchestrator v2.3.1 - {process_def.name} v{process_def.version}")
    print("=" * 60)
    
    # Show configuration summary
    if user_flags or arguments:
        print("\n🔧 Flags:")
        if user_flags:
            flag_strs = []
            for flag, value in user_flags.items():
                if value is True:
                    flag_strs.append(flag)
                else:
                    flag_strs.append(f"{flag}={value}")
            print(f"   User: {', '.join(flag_strs)}")
        if arguments:
            print(f"   Args: {', '.join(arguments)}")
    
    # Show path configuration
    print("\n📁 Paths:")
    print(f"   Root: {aeon_root}")
    print(f"   Repo: {aeon_repo}")
    print(f"        (relative: {aeon_repo_rel})")
    
    # Show state file location (from process definition)
    state_file_display = process_def.aeon_state
    if not Path(state_file_display).is_absolute():
        state_file_display = f"{aeon_root}/{state_file_display}"
    print(f"   State: {state_file_display}")
    
    print()
    
    # Create task loader with aeon_repo for per-task path resolution
    # task_directories is now optional (legacy support only)
    task_loader = TaskLoader(task_directories=None, aeon_repo=aeon_repo)
    
    # Create main registry/orchestrator with aeon_root for state file resolution
    registry = HierarchicalFutureRegistry(task_loader, process_def, aeon_root=aeon_root)
    
    # Populate shared execution context
    registry.context["process_def"] = process_def  # For config_handler access
    registry.context["user_flags"] = user_flags
    registry.context["arguments"] = arguments
    registry.context["aeon_root"] = aeon_root
    registry.context["aeon_repo"] = aeon_repo
    
    # Load all task definitions
    print(f"📦 Loading tasks...")
    for task_entry in process_def.tasks:
        if "task" in task_entry:
            task_name = task_entry["task"]
            registry.load_task(task_name, task_entry)
            print(f"   └─ {task_name}")
    
    print()
    
    # Execute from configured entry point
    entry_task = process_def.entry_point.get("task")
    entry_method = process_def.entry_point.get("method", "resolve")
    
    if not entry_task:
        print("❌ No entry_point.task specified in process file")
        sys.exit(1)
    
    print(f"🎯 Entry Point: {entry_task}.{entry_method}()\n")
    
    try:
        # Begin execution chain from entry point
        result = await registry.execute_task(
            task_name=entry_task,
            method=entry_method,
            event_data={
                "user_flags": user_flags,
                "arguments": arguments
            }
        )
        
        print(f"\n✅ Process completed successfully")
        
    except Exception as e:
        print(f"\n❌ Process failed: {e}")
        sys.exit(1)
