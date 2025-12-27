# -*- coding: utf-8 -*-
"""
Process Loader (DEPRECATED)

This file is DEPRECATED. Use library.python.orchestrator.parser.orchestrator_parser_api instead.

The new parser system provides:
- Auto-detection of file formats (JSON, YAML, TOML)
- Extensible parser architecture
- Better error handling

sys.path: Must contain '/path/to/aeon'
Location: library/python/orchestrator/parser/process_loader.py
"""

import json

from library.python.orchestrator.core.core_segments import ProcessDefinition


class ProcessLoader:
    """
    Loader for process definition files (.instruct.json).
    
    DEPRECATED: Use load_process_definition() from orchestrator_parser_api instead.
    
    Parses JSON configuration files that define complete workflows.
    Validates required fields and provides sensible defaults.
    
    :file_format: JSON with specific schema
    :validation: Required fields with default values
    :error_handling: JSON parsing errors with line numbers
    """
    
    def load(self, process_file: str) -> ProcessDefinition:
        """
        Load and parse process definition from JSON file.
        
        DEPRECATED: Use load_process_definition() instead.
        
        :param process_file: Path to .instruct.json file
        :return: ProcessDefinition object
        :raises FileNotFoundError: If process_file doesn't exist
        :raises json.JSONDecodeError: If file contains invalid JSON
        :raises KeyError: If required fields are missing
        """
        with open(process_file, 'r') as f:
            data = json.load(f)
        
        return ProcessDefinition(
            name=data.get("process_name", "unknown"),
            version=data.get("version", "2.0.0"),
            description=data.get("description", ""),
            task_directories=data.get("task_directories", ["./tasks"]),
            tasks=data.get("tasks", []),
            entry_point=data.get("entry_point", 
                                 {"task": "system_start", "method": "resolve"}),
            config=data.get("config", {}),
            aeon_state=data.get("aeon_state", "runtime/states/.aeon_state.json")
        )
