# -*- coding: utf-8 -*-
"""
Hierarchical Future Registry

Central orchestrator with event-driven task lifecycle management.

sys.path: Must contain '/path/to/aeon'
Location: library/python/orchestrator/core/registry.py
"""

import asyncio
from pathlib import Path
from typing import Any, Dict, List, Callable, Optional

from library.python.orchestrator.core.core_segments import ProcessDefinition, TaskDefinition, TaskState
from library.python.orchestrator.core.state_manager import StateManager
from library.python.orchestrator.core.task_loader import TaskLoader
from library.python.aeonlibs.helper.nested import get_nested


class HierarchicalFutureRegistry:
    """
    Central orchestrator with event-driven task lifecycle management.
    
    Core responsibilities:
    1. Task dependency resolution and topological sorting
    2. Lifecycle hook execution at defined points
    3. Configuration merging and inheritance
    4. State management and persistence
    5. Error handling and recovery
    
    :lifecycle:
        1. on_load - Task initialization
        2. before_resolve - Pre-execution validation
        3. on_resolve - Execution phase
        4. on_success/on_error - Post-execution handling
        5. after_resolve - Cleanup phase
    
    :config_priority: (highest to lowest)
        4. Runtime (user flags + existing config)
        3. Task-specific config (from process file)
        2. Global config (from process file) 
        1. Task defaults (from process file task entry)
    """
    
    def __init__(self, task_loader: TaskLoader, process_def: ProcessDefinition, aeon_root: str = None):
        """
        Initialize registry with task loader and process definition.
        
        :param task_loader: Loader instance for dynamic task loading
        :param process_def: Process definition from .instruct.json
        :param aeon_root: Root directory for AEON installation (for state file path resolution)
        """
        self.task_loader = task_loader
        self.process_def = process_def
        
        # Initialize StateManager with configurable state file from process definition
        state_file_path = process_def.aeon_state
        self.state_manager = StateManager(state_file=state_file_path, aeon_root=aeon_root)
        
        # Execution context shared across all tasks
        self.context: Dict = {}
        # Cache of loaded task definitions
        self.task_definitions: Dict[str, TaskDefinition] = {}
        # Cache of merged configurations
        self.task_configs: Dict[str, Dict] = {}
    
    def load_task(self, task_name: str, task_entry: Dict) -> TaskDefinition:
        """
        Load task and merge configuration with proper precedence.
        
        Configuration merging follows a specific precedence order
        where higher numbers override lower numbers:
        
        1. Task defaults (from process file task entry)
        2. Global config (from process file)
        3. Task-specific config (from process file task entry)
        4. Runtime (user flags + existing config)
        
        :param task_name: Name of task to load
        :param task_entry: Task configuration from process file
        :return: Fully configured TaskDefinition
        """
        # Load task module (may be cached)
        task_def = self.task_loader.load(task_name)
        
        # Override dependencies if specified in process file
        if "depends_on" in task_entry:
            task_def.depends_on = task_entry["depends_on"]
        
        # Configuration merging with precedence rules
        config = {}
        
        # 1. Task defaults from process file (lowest priority)
        if "defaults" in task_entry:
            config.update(task_entry["defaults"])
        
        # 2. Global process config
        # Extract task type prefix (e.g., "network" from "network_scan")
        task_config_key = task_name.split("_")[0]
        if task_config_key in self.process_def.config:
            config.update(self.process_def.config[task_config_key])
        
        # 3. Task-specific config from process
        if "config" in task_entry:
            config.update(task_entry["config"])
        
        # 4. Runtime config (existing system config)
        system_config = self.context.get("system_config", {})
        if task_config_key in system_config:
            config.update(system_config[task_config_key])
        
        # 5. User flags (highest priority)
        user_flags = self.context.get("user_flags", {})
        config = self._apply_user_flags_to_config(config, user_flags, task_name)
        
        task_def.config = config
        
        # Load and resolve lifecycle hooks
        if "hooks" in task_entry:
            task_def.hooks = task_entry["hooks"]
            # Resolve hook method names to actual functions
            for hook_name, method_name in task_def.hooks.items():
                func = getattr(task_def.module, method_name, None)
                if func:
                    task_def.hook_funcs[hook_name] = func
        
        # Force execution override
        if "force_execute" in task_entry:
            task_def.force_execute = task_entry["force_execute"]
        
        # Cache definitions and configs
        self.task_definitions[task_name] = task_def
        self.task_configs[task_name] = config
        
        # Store config in shared context for task access
        if "task_config" not in self.context:
            self.context["task_config"] = {}
        self.context["task_config"][task_name] = config
        
        return task_def
    
    def _apply_user_flags_to_config(self, config: Dict, user_flags: Dict, 
                                   task_name: str) -> Dict:
        """
        Map command-line flags to task configuration keys.
        
        This method translates user-friendly command-line arguments
        to internal configuration keys used by tasks.
        
        :param config: Current configuration dictionary
        :param user_flags: User-provided command-line flags
        :param task_name: Name of task for context-aware mapping
        :return: Updated configuration dictionary
        """
        # Generic flag-to-config mapping
        flag_mapping = {
            "--scan-range": "scan_range",
            "--scan-timeout": "scan_timeout",
            "--ip": "ip_address",
            "--netmask": "netmask"
        }
        
        # Apply mappings
        for flag, config_key in flag_mapping.items():
            if flag in user_flags:
                config[config_key] = user_flags[flag]
        
        return config
    
    async def execute_hook(self, task_name: str, hook_name: str, 
                          event_data: Dict = None) -> Optional[Dict]:
        """
        Execute a lifecycle hook function if defined.
        
        Hooks receive:
        - context: Shared execution context
        - dependencies: Results from dependent tasks
        - event_data: Hook-specific event data
        
        :param task_name: Name of task owning the hook
        :param hook_name: Hook identifier (e.g., "on_load")
        :param event_data: Additional data for hook execution
        :return: Hook return value or None
        """
        task_def = self.task_definitions.get(task_name)
        if not task_def or hook_name not in task_def.hook_funcs:
            return None
        
        hook_func = task_def.hook_funcs[hook_name]
        
        # Gather dependency results for hook context
        dep_results = {}
        for dep_name in task_def.depends_on:
            dep_results[dep_name] = self.state_manager.get_result(dep_name)
        
        event_data = event_data or {}
        result = await hook_func(
            context=self.context,
            dependencies=dep_results,
            event_data=event_data
        )
        
        return result
    
    async def execute_task(
        self,
        task_name: str,
        method: str = "resolve",
        event_data: Dict = None
    ) -> Any:
        """
        Execute task with full lifecycle management.
        
        This is the main execution engine that:
        1. Checks execution prerequisites
        2. Resolves dependencies recursively
        3. Executes lifecycle hooks
        4. Runs main task logic
        5. Handles success/error states
        
        :param task_name: Name of task to execute
        :param method: Task method to call ("resolve" or custom API method)
        :param event_data: Additional execution context
        :return: Task execution result
        :raises AttributeError: If specified method doesn't exist
        :raises Exception: Propagates task execution errors
        """
        task_def = self.task_definitions[task_name]
        event_data = event_data or {}
        
        print(f"⏳ [{task_name}] Starting")
        
        # 1. on_load hook - initialization phase
        if "on_load" in task_def.hook_funcs:
            await self.execute_hook(task_name, "on_load", event_data)
        
        # 2. Check if already resolved (idempotent execution)
        state = self.state_manager.get_state(task_name)
        if state == TaskState.RESOLVED and not task_def.force_execute:
            result = self.state_manager.get_result(task_name)
            print(f"✅ [{task_name}] Already resolved")
            return result
        
        # 3. Recursively resolve dependencies
        dep_results = {}
        for dep_name in task_def.depends_on:
            dep_state = self.state_manager.get_state(dep_name)
            if dep_state != TaskState.RESOLVED:
                # Execute dependency first (depth-first traversal)
                print(f"   └─ Resolving dependency: {dep_name}")
                await self.execute_task(dep_name, "resolve", event_data)
            dep_results[dep_name] = self.state_manager.get_result(dep_name)
        
        # 4. before_resolve hook - pre-execution validation
        if "before_resolve" in task_def.hook_funcs:
            await self.execute_hook(task_name, "before_resolve", event_data)
        
        # 5. on_resolve hook - execution phase preparation
        if "on_resolve" in task_def.hook_funcs:
            await self.execute_hook(task_name, "on_resolve", event_data)
        
        try:
            # 6. Execute main task method
            self.state_manager.set_state(task_name, TaskState.PENDING)
            
            if method == "resolve":
                result = await task_def.resolve_func(
                    context=self.context,
                    dependencies=dep_results,
                    event_data=event_data
                )
            else:
                # Custom API method invocation
                api_func = getattr(task_def.module, method, None)
                if not api_func:
                    raise AttributeError(
                        f"Method '{method}' not found in task '{task_name}'"
                    )
                result = await api_func(
                    context=self.context,
                    dependencies=dep_results,
                    event_data=event_data
                )
            
            # 7. on_success hook - post-execution success handling
            if "on_success" in task_def.hook_funcs:
                await self.execute_hook(task_name, "on_success", event_data)
            
            # Mark task as successfully resolved
            self.state_manager.set_state(task_name, TaskState.RESOLVED)
            self.state_manager.set_result(task_name, result)
            
            print(f"✅ [{task_name}] Completed")
            
            return result
            
        except Exception as e:
            # on_error hook - error handling and cleanup
            if "on_error" in task_def.hook_funcs:
                error_data = {"error": e}
                await self.execute_hook(task_name, "on_error", error_data)
            
            # Mark task as rejected (failed)
            self.state_manager.set_state(task_name, TaskState.REJECTED)
            
            # Call reject function for custom error handling
            if task_def.reject_func:
                await task_def.reject_func(self.context, e, event_data)
            
            print(f"❌ [{task_name}] Failed: {e}")
            raise
            
        finally:
            # 8. after_resolve hook - always executed (cleanup phase)
            if "after_resolve" in task_def.hook_funcs:
                await self.execute_hook(task_name, "after_resolve", event_data)
