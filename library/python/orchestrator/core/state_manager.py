# -*- coding: utf-8 -*-
"""
State Manager

Persistent state management for task execution with disk persistence.

sys.path: Must contain '/path/to/aeon'
Location: library/python/orchestrator/core/state_manager.py
"""

import json
from pathlib import Path
from typing import Dict, Optional
from datetime import datetime

from library.python.orchestrator.core.core_segments import TaskState


class StateManager:
    """
    Persistent state management for task execution.
    
    Implements a simple key-value store with disk persistence.
    This enables idempotent execution and crash recovery by
    remembering which tasks have completed successfully.
    
    :design_pattern: Memento Pattern - captures and restores object state
    :persistence: JSON file with human-readable format
    :thread_safety: Not thread-safe; designed for single-process execution
    """
    
    def __init__(self, state_file: str = ".aeon_state.json", aeon_root: str = None):
        """
        Initialize StateManager with persistence file.
        
        :param state_file: Path to JSON file for state storage (relative to aeon_root if provided)
        :param aeon_root: Root directory for AEON installation (makes state_file relative to this)
        """
        # If aeon_root is provided and state_file is relative, make it absolute
        if aeon_root and not Path(state_file).is_absolute():
            self.state_file = str(Path(aeon_root) / state_file)
        else:
            self.state_file = state_file
        
        # Ensure parent directory exists
        state_path = Path(self.state_file)
        state_path.parent.mkdir(parents=True, exist_ok=True)
        
        self.states: Dict[str, Dict] = {}
        self.load()
    
    def load(self) -> None:
        """Load state from disk, creating empty state if file doesn't exist."""
        if Path(self.state_file).exists():
            with open(self.state_file, 'r') as f:
                self.states = json.load(f)
    
    def save(self) -> None:
        """Serialize state to disk with pretty formatting."""
        with open(self.state_file, 'w') as f:
            json.dump(self.states, f, indent=2, default=str)
    
    def get_state(self, task_name: str) -> TaskState:
        """
        Retrieve current state of a task.
        
        :param task_name: Name of the task to query
        :return: Current task state
        """
        state_str = self.states.get(task_name, {}).get("state", "not_started")
        return TaskState(state_str)
    
    def set_state(self, task_name: str, state: TaskState) -> None:
        """
        Update state of a task with timestamp.
        
        :param task_name: Name of the task to update
        :param state: New state value
        """
        if task_name not in self.states:
            self.states[task_name] = {}
        self.states[task_name]["state"] = state.value
        self.states[task_name]["updated_at"] = datetime.now().isoformat()
        self.save()
    
    def get_result(self, task_name: str) -> Optional[Dict]:
        """
        Retrieve stored result from a completed task.
        
        :param task_name: Name of the task
        :return: Result dictionary or None if not found
        """
        return self.states.get(task_name, {}).get("result")
    
    def set_result(self, task_name: str, result: Dict) -> None:
        """
        Store result from a completed task.
        
        :param task_name: Name of the task
        :param result: Result data to store
        """
        if task_name not in self.states:
            self.states[task_name] = {}
        self.states[task_name]["result"] = result
        self.save()
    
    def reset_all(self) -> None:
        """Clear all stored state, typically for clean restart."""
        self.states = {}
        self.save()
