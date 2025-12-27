# -*- coding: utf-8 -*-
"""
Orchestrator Parser API

Orchestrator-spezifische Parser-Funktionen.
Nutzt die generelle ParserAPI und wandelt in ProcessDefinition um.

sys.path requirements: '/path/to/aeon' must be in sys.path
Import: from library.python.orchestrator.parser.orchestrator_parser_api import load_process_definition
"""

from typing import Any, Dict

from library.python.parser.parser_api import ParserFactory
from library.python.orchestrator.core.core_segments import ProcessDefinition


def load_process_definition(process_file: str) -> ProcessDefinition:
    """
    Lade Process Definition aus Datei (auto-detect format).
    
    Unterstützt: .json, .yaml, .toml (je nach registrierten Parsern)
    
    :param process_file: Pfad zur Process Definition Datei
    :return: ProcessDefinition Objekt
    :raises ValueError: Unbekanntes Dateiformat
    :raises ParseError: Datei kann nicht geparst werden
    
    :example:
        >>> process_def = load_process_definition("install.instruct.json")
        >>> print(process_def.name)
        'install'
    """
    # Auto-detect und parse
    data = ParserFactory.load(process_file)
    
    # Konvertiere zu ProcessDefinition
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


def save_process_definition(process_def: ProcessDefinition, process_file: str) -> None:
    """
    Speichere Process Definition in Datei (auto-detect format).
    
    :param process_def: ProcessDefinition Objekt
    :param process_file: Ziel-Dateipfad
    """
    data = {
        "process_name": process_def.name,
        "version": process_def.version,
        "description": process_def.description,
        "task_directories": process_def.task_directories,
        "tasks": process_def.tasks,
        "entry_point": process_def.entry_point,
        "config": process_def.config,
        "aeon_state": process_def.aeon_state,
    }
    
    ParserFactory.dump(data, process_file)