# -*- coding: utf-8 -*-
"""
Nested Dictionary Helpers

Utilities for safe access and manipulation of nested dictionary structures
using dot notation.

sys.path: Must contain '/path/to/aeon'
Location: library/python/aeonlibs/helper/nested.py
"""

from typing import Any


def get_nested(data: dict, key_path: str, default=None) -> Any:
    """
    Safely retrieve values from nested dictionaries using dot notation.
    
    This function provides null-safe access to nested dictionary structures,
    preventing KeyError exceptions for missing keys. It follows the principle
    of "graceful degradation" by returning defaults instead of raising errors.
    
    :param data: Dictionary to traverse
    :param key_path: Dot-separated path to target key (e.g., "a.b.c")
    :param default: Value to return if path doesn't exist
    :return: Value at key_path or default
    
    :example:
        >>> get_nested({"a": {"b": {"c": 123}}}, "a.b.c")
        123
        >>> get_nested({"a": {}}, "a.b.c", default=0)
        0
    """
    if not key_path:
        return default
    
    keys = key_path.split(".")
    value = data
    
    # Traverse each level of the hierarchy
    for key in keys:
        if isinstance(value, dict):
            value = value.get(key)
            if value is None:
                return default
        else:
            return default
    
    return value if value is not None else default


def set_nested(data: dict, key_path: str, value: Any) -> None:
    """
    Set values in nested dictionaries using dot notation.
    
    Creates intermediate dictionaries as needed. This function enables
    structured configuration management by allowing hierarchical data
    manipulation without manual dictionary creation.
    
    :param data: Dictionary to modify
    :param key_path: Dot-separated path to target key
    :param value: Value to set at key_path
    :raises ValueError: If key_path is empty
    :raises TypeError: If intermediate structure blocks path creation
    
    :example:
        >>> d = {}
        >>> set_nested(d, "a.b.c", 123)
        >>> print(d)
        {"a": {"b": {"c": 123}}}
    """
    if not key_path:
        raise ValueError("key_path cannot be empty")
    
    keys = key_path.split(".")
    current = data
    
    # Navigate to the parent container, creating dicts as needed
    for key in keys[:-1]:
        if key not in current:
            current[key] = {}
        elif not isinstance(current[key], dict):
            # Overwrite non-dict values with dicts
            current[key] = {}
        current = current[key]
    
    # Set the final value
    current[keys[-1]] = value