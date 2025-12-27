# -*- coding: utf-8 -*-
"""
Task Loader

Dynamic loader for task modules with caching and per-task path support.

sys.path: Must contain '/path/to/aeon'
Location: library/python/orchestrator/core/task_loader.py
"""

import importlib.util
from pathlib import Path
from typing import Dict, List

from library.python.orchestrator.core.core_segments import TaskDefinition


class TaskLoader:
    """
    Dynamic loader for task modules with caching.
    
    Supports two loading modes:
    1. Per-task path: Each task specifies its own location via "path" field
    2. Legacy: Search in global task_directories (deprecated, for compatibility)
    
    :caching: Memoization prevents duplicate module loading
    :discovery: Uses task-specific path or falls back to directory search
    :error_handling: Clear FileNotFoundError with search details
    """
    
    def __init__(self, task_directories: List[str] = None, aeon_repo: str = None):
        """
        Initialize loader with search paths.
        
        :param task_directories: List of directories to search for tasks (legacy, optional)
        :param aeon_repo: Repository root path for resolving task paths
        """
        self.task_directories = task_directories or []
        self.aeon_repo = aeon_repo
        self.loaded_tasks: Dict[str, TaskDefinition] = {}
    
    def load(self, task_name: str, task_config: Dict = None) -> TaskDefinition:
        """
        Load task module and create definition object.
        
        Search algorithm:
        1. Check cache for already loaded task
        2. If task_config["path"] exists, use that path (PRIORITY)
        3. Else search task_directories (legacy fallback)
        4. Try multiple filename patterns
        5. Load module and extract metadata
        
        :param task_name: Name of task to load
        :param task_config: Task configuration dict (may contain "path" field)
        :return: Fully populated TaskDefinition
        :raises FileNotFoundError: If no matching module file found
        :raises ImportError: If module cannot be loaded or parsed
        """
        # Check cache first (memoization pattern)
        if task_name in self.loaded_tasks:
            return self.loaded_tasks[task_name]
        
        task_config = task_config or {}
        
        # Search for task file across configured directories
        task_file = None
        
        # PRIORITY: Use task-specific path if provided
        if "path" in task_config:
            task_path_rel = task_config["path"]
            
            if not self.aeon_repo:
                raise ValueError("aeon_repo required when using task 'path' field")
            
            # Resolve relative to aeon_repo
            task_dir = Path(self.aeon_repo) / task_path_rel
            
            # Try multiple naming conventions
            candidates = [
                task_dir / f"{task_name}.task.py",
                task_dir / f"{task_name}.py",
                task_dir / task_name / "__init__.py"
            ]
            for candidate in candidates:
                if candidate.exists():
                    task_file = candidate
                    break
        
        # FALLBACK: Search legacy task_directories
        if not task_file and self.task_directories:
            for directory in self.task_directories:
                candidates = [
                    Path(directory) / f"{task_name}.task.py",
                    Path(directory) / f"{task_name}.py",
                    Path(directory) / task_name / "__init__.py"
                ]
                for candidate in candidates:
                    if candidate.exists():
                        task_file = candidate
                        break
                if task_file:
                    break
        
        if not task_file:
            search_info = []
            if "path" in task_config:
                search_info.append(f"Task path: {self.aeon_repo}/{task_config['path']}")
            if self.task_directories:
                search_info.append(f"Directories: {self.task_directories}")
            
            raise FileNotFoundError(
                f"Task file not found: {task_name}. "
                f"Searched: {'; '.join(search_info)}"
            )
        
        # Dynamic module loading using importlib
        spec = importlib.util.spec_from_file_location(task_name, task_file)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        
        # Extract task metadata with sensible defaults
        task_def = TaskDefinition(
            name=getattr(module, 'TASK_NAME', task_name),
            description=getattr(module, 'TASK_DESCRIPTION', ''),
            module=module,
            depends_on=getattr(module, 'DEPENDS_ON', []),
            config=getattr(module, 'CONFIG', {}),
            resolve_func=getattr(module, 'resolve', None),
            reject_func=getattr(module, 'reject', None)
        )
        
        # Cache for future requests
        self.loaded_tasks[task_name] = task_def
        return task_def
