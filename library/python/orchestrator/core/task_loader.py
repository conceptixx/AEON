# -*- coding: utf-8 -*-
"""
Task Loader

Dynamic loader for task modules with caching.

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
    
    Implements discovery and loading of Python modules that define tasks.
    Supports multiple file naming conventions and directory structures.
    
    :caching: Memoization prevents duplicate module loading
    :discovery: Searches multiple directories with fallback patterns
    :error_handling: Clear FileNotFoundError with search details
    """
    
    def __init__(self, task_directories: List[str]):
        """
        Initialize loader with search paths.
        
        :param task_directories: List of directories to search for tasks
        """
        self.task_directories = task_directories
        self.loaded_tasks: Dict[str, TaskDefinition] = {}
    
    def load(self, task_name: str) -> TaskDefinition:
        """
        Load task module and create definition object.
        
        Search algorithm:
        1. Check cache for already loaded task
        2. Search directories in order
        3. Try multiple filename patterns
        4. Load module and extract metadata
        
        :param task_name: Name of task to load
        :return: Fully populated TaskDefinition
        :raises FileNotFoundError: If no matching module file found
        :raises ImportError: If module cannot be loaded or parsed
        """
        # Check cache first (memoization pattern)
        if task_name in self.loaded_tasks:
            return self.loaded_tasks[task_name]
        
        # Search for task file across configured directories
        task_file = None
        for directory in self.task_directories:
            # Try multiple naming conventions for flexibility
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
            raise FileNotFoundError(
                f"Task file not found: {task_name}. "
                f"Searched in: {self.task_directories}"
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
