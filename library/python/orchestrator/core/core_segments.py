# -*- coding: utf-8 -*-
"""
Orchestrator Core Data Models

All core data structures for the AEON orchestrator:
- TaskState: Finite state machine states
- TaskDefinition: Complete task definition with behavior and config
- ProcessDefinition: Workflow blueprint from .instruct.json files

sys.path: Must contain '/path/to/aeon'
Location: library/python/orchestrator/core/core_segments.py
"""

from enum import Enum
from dataclasses import dataclass, field
from typing import Any, Dict, List, Callable, Optional


class TaskState(Enum):
    """
    Finite state machine states for task execution.
    
    Tasks transition through these states during their lifecycle:
    NOT_STARTED → PENDING → [RESOLVED|REJECTED|BLOCKED|INCOMPLETE]
    
    :state NOT_STARTED: Initial state before any execution
    :state PENDING: Currently executing
    :state RESOLVED: Successfully completed
    :state REJECTED: Failed with error
    :state INCOMPLETE: Partial completion (may retry)
    :state BLOCKED: Waiting for dependencies or external conditions
    """
    NOT_STARTED = "not_started"
    PENDING = "pending"
    RESOLVED = "resolved"
    REJECTED = "rejected"
    INCOMPLETE = "incomplete"
    BLOCKED = "blocked"


@dataclass
class TaskDefinition:
    """
    Complete definition of a task's behavior and configuration.
    
    This is the primary data structure representing a unit of work
    in the AEON system. It encapsulates:
    - Execution logic (resolve/reject functions)
    - Dependencies and relationships
    - Lifecycle hooks for event-driven behavior
    - Configuration with inheritance
    
    :attribute name: Unique identifier for the task
    :attribute description: Human-readable description
    :attribute module: Loaded Python module containing task logic
    :attribute depends_on: List of task names that must complete first
    :attribute hooks: Map of lifecycle event names to method names
    :attribute config: Merged configuration (defaults + process + runtime)
    :attribute force_execute: If True, execute even if already resolved
    :attribute resolve_func: Async function that performs the main work
    :attribute reject_func: Async function called on failure
    :attribute hook_funcs: Resolved hook functions from module
    """
    name: str
    description: str
    module: Any
    
    # Dependencies (can be overridden in process file)
    depends_on: List[str] = field(default_factory=list)
    
    # Lifecycle hooks
    hooks: Dict[str, str] = field(default_factory=dict)
    # {"on_load": "method_name", "before_resolve": "method_name", ...}
    
    # Config (merged from defaults + process + runtime)
    config: Dict[str, Any] = field(default_factory=dict)
    
    # Force execution modes
    force_execute: bool = False
    
    # Main methods
    resolve_func: Optional[Callable] = None
    reject_func: Optional[Callable] = None
    
    # Hook functions (resolved from module)
    hook_funcs: Dict[str, Callable] = field(default_factory=dict)


@dataclass
class ProcessDefinition:
    """
    Blueprint for executing a complete workflow.
    
    Loaded from .instruct.json files, this defines:
    - Which tasks to run and in what order
    - Configuration defaults and overrides
    - Directory structure for task discovery
    - Entry point for execution
    - State file location for persistence
    
    :attribute name: Process name for logging and identification
    :attribute version: Semantic version for compatibility tracking
    :attribute description: Human-readable process description
    :attribute task_directories: Paths to search for task modules (relative to root)
    :attribute tasks: List of task configurations with overrides
    :attribute entry_point: Starting task and method for execution
    :attribute config: Global configuration shared across all tasks
    :attribute aeon_state: Path to state file (relative to root, defaults to "runtime/states/.aeon_state.json")
    """
    name: str
    version: str
    description: str
    task_directories: List[str]
    tasks: List[Any]
    entry_point: Dict[str, str]  # {"task": "name", "method": "resolve"}
    config: Dict[str, Any] = field(default_factory=dict)
    aeon_state: str = "runtime/states/.aeon_state.json"  # Relative to aeon_root