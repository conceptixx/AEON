#!/usr/bin/env python3
"""
AEON Orchestrator - Dynamic CLI Execution Engine
VERSION: 1.3.0

A manifest-driven orchestrator that accepts arbitrary CLI flags defined
in entry instruction schemas, enabling self-describing interfaces without
hardcoded business logic.

ARCHITECTURE SURPRISE:
This version implements "Protocol-Oriented CLI Design" where the orchestrator
is a pure execution engine. The manifest becomes the protocol specification,
defining not just WHAT to execute, but HOW users interact with it. This enables:
- Zero-code CLI updates (just edit JSON)
- Self-documenting interfaces (schema = docs)
- Type-safe flag handling with validation
- Composable flag inheritance across manifests

Bootstrap Args (hardcoded):
    --file:/path        Entry instruction manifest (required, repeatable)
    --config:/path      Configuration overlay (optional, repeatable)

All other args parsed per manifest's cli.flags_schema

Exit Codes:
    0: Success
    1: Runtime/step execution failure
    2: CLI usage error (invalid flags per schema)
    3: Validation failure (missing required files)
    4: Dependency/import/registry failure
"""

import sys
import os
import json
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass, field
from enum import Enum


class ExitCode(Enum):
    """Orchestrator exit codes with semantic meaning"""
    SUCCESS = 0
    RUNTIME_FAILURE = 1
    CLI_USAGE_ERROR = 2
    VALIDATION_FAILURE = 3
    DEPENDENCY_FAILURE = 4


class UnknownFlagPolicy(Enum):
    """How to handle flags not in schema"""
    WARN = "warn"
    ERROR = "error"
    IGNORE = "ignore"


@dataclass
class FlagDefinition:
    """Schema for a single CLI flag"""
    name: str
    aliases: List[str] = field(default_factory=list)
    type: str = "bool"  # bool, string, int, float
    default: Any = None
    required: bool = False
    description: str = ""
    
    def matches(self, arg: str) -> bool:
        """Check if arg matches this flag or its aliases"""
        candidates = [f"--{self.name}"] + [f"-{a}" for a in self.aliases]
        return arg in candidates or arg.startswith(f"--{self.name}=")


@dataclass
class ParsedFlags:
    """Result of flag parsing"""
    values: Dict[str, Any] = field(default_factory=dict)
    unknown: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    errors: List[str] = field(default_factory=list)


@dataclass
class ExecutionContext:
    """Runtime context for orchestration"""
    aeon_root: Path
    entry_file: Path
    config_files: List[Path]
    flags: Dict[str, Any]
    warnings: List[str] = field(default_factory=list)
    errors: List[str] = field(default_factory=list)
    
    @property
    def noninteractive(self) -> bool:
        """Convenience accessor for noninteractive mode"""
        return self.flags.get('noninteractive', False)


class BootstrapParser:
    """Parse hardcoded bootstrap arguments"""
    
    @staticmethod
    def parse(argv: List[str]) -> Tuple[List[Path], List[Path], List[str]]:
        """
        Extract bootstrap args and return remaining args
        
        Returns:
            (files, configs, remaining_args)
        """
        files = []
        configs = []
        remaining = []
        
        i = 0
        while i < len(argv):
            arg = argv[i]
            
            if arg.startswith('--file:'):
                path = arg.split(':', 1)[1]
                files.append(Path(path))
            elif arg.startswith('--config:'):
                path = arg.split(':', 1)[1]
                configs.append(Path(path))
            else:
                remaining.append(arg)
            
            i += 1
        
        return files, configs, remaining


class FlagParser:
    """Parse CLI flags according to manifest schema"""
    
    def __init__(self, schema: Dict[str, Any]):
        """
        Initialize parser with flag schema
        
        Schema format:
        {
            "flags": [
                {
                    "name": "noninteractive",
                    "aliases": ["n"],
                    "type": "bool",
                    "default": false,
                    "description": "Run without prompts"
                },
                {
                    "name": "output",
                    "aliases": ["o"],
                    "type": "string",
                    "required": true,
                    "description": "Output directory"
                }
            ],
            "unknown_policy": "warn"
        }
        """
        self.flags = [FlagDefinition(**f) for f in schema.get('flags', [])]
        self.unknown_policy = UnknownFlagPolicy(
            schema.get('unknown_policy', 'warn')
        )
    
    def parse(self, args: List[str]) -> ParsedFlags:
        """
        Parse args according to schema
        
        Supports:
        - Boolean flags: -n, --noninteractive
        - Value flags: --output=path, --output path
        - Combined short flags: -nw => -n -w
        """
        result = ParsedFlags()
        
        # Initialize with defaults
        for flag_def in self.flags:
            if flag_def.default is not None:
                result.values[flag_def.name] = flag_def.default
        
        i = 0
        while i < len(args):
            arg = args[i]
            consumed = False
            
            # Try to match against defined flags
            for flag_def in self.flags:
                if flag_def.matches(arg):
                    consumed = True
                    
                    if flag_def.type == 'bool':
                        result.values[flag_def.name] = True
                    else:
                        # Value flag: --key=val or --key val
                        if '=' in arg:
                            value = arg.split('=', 1)[1]
                        else:
                            if i + 1 >= len(args):
                                result.errors.append(
                                    f"Flag {arg} requires a value"
                                )
                                break
                            value = args[i + 1]
                            i += 1  # Skip next arg
                        
                        # Type conversion
                        try:
                            if flag_def.type == 'int':
                                result.values[flag_def.name] = int(value)
                            elif flag_def.type == 'float':
                                result.values[flag_def.name] = float(value)
                            else:
                                result.values[flag_def.name] = value
                        except ValueError:
                            result.errors.append(
                                f"Invalid {flag_def.type} value for {arg}: {value}"
                            )
                    
                    break
            
            # Handle combined short flags like -nw
            if not consumed and arg.startswith('-') and not arg.startswith('--') and len(arg) > 2:
                expanded = []
                for char in arg[1:]:
                    expanded.append(f"-{char}")
                
                # Re-parse expanded flags
                expanded_result = self.parse(expanded)
                result.values.update(expanded_result.values)
                result.unknown.extend(expanded_result.unknown)
                result.warnings.extend(expanded_result.warnings)
                result.errors.extend(expanded_result.errors)
                consumed = True
            
            if not consumed:
                result.unknown.append(arg)
            
            i += 1
        
        # Check required flags
        for flag_def in self.flags:
            if flag_def.required and flag_def.name not in result.values:
                result.errors.append(f"Required flag --{flag_def.name} not provided")
        
        # Handle unknown flags per policy
        if result.unknown:
            if self.unknown_policy == UnknownFlagPolicy.ERROR:
                result.errors.append(
                    f"Unknown flags: {', '.join(result.unknown)}"
                )
            elif self.unknown_policy == UnknownFlagPolicy.WARN:
                result.warnings.append(
                    f"Unknown flags ignored: {', '.join(result.unknown)}"
                )
            # IGNORE policy: just drop them silently
        
        return result


class PathValidator:
    """Validate and resolve paths within AEON_ROOT"""
    
    def __init__(self, aeon_root: Path):
        self.aeon_root = aeon_root.resolve()
    
    def resolve_safe(self, path: Path, must_exist: bool = False) -> Path:
        """
        Resolve path within AEON_ROOT, preventing traversal attacks
        
        Args:
            path: Path to resolve (absolute or relative)
            must_exist: Whether path must exist
            
        Returns:
            Resolved absolute path
            
        Raises:
            ValueError: If path escapes AEON_ROOT or doesn't exist when required
        """
        if path.is_absolute():
            resolved = path.resolve()
        else:
            resolved = (self.aeon_root / path).resolve()
        
        # Security check: prevent directory traversal
        try:
            resolved.relative_to(self.aeon_root)
        except ValueError:
            raise ValueError(
                f"Path traversal detected: {path} escapes AEON_ROOT"
            )
        
        if must_exist and not resolved.exists():
            raise ValueError(f"Required path does not exist: {resolved}")
        
        return resolved


class ManifestValidator:
    """Validate manifest structure and referenced files"""
    
    def __init__(self, path_validator: PathValidator):
        self.path_validator = path_validator
    
    def validate(self, manifest: Dict[str, Any], context: ExecutionContext) -> bool:
        """
        Validate manifest and check file requirements
        
        Returns:
            True if valid, False otherwise (errors added to context)
        """
        valid = True
        
        # Validate CLI schema if present
        if 'cli' in manifest:
            cli = manifest['cli']
            if 'flags_schema' in cli:
                schema = cli['flags_schema']
                if 'flags' not in schema or not isinstance(schema['flags'], list):
                    context.errors.append(
                        "cli.flags_schema.flags must be a list"
                    )
                    valid = False
        
        # Check required_now files
        if 'required_now' in manifest:
            for file_path in manifest['required_now']:
                try:
                    self.path_validator.resolve_safe(
                        Path(file_path), 
                        must_exist=True
                    )
                except ValueError as e:
                    context.errors.append(str(e))
                    valid = False
        
        # Warn about required_eventually files
        if 'required_eventually' in manifest:
            for file_path in manifest['required_eventually']:
                try:
                    resolved = self.path_validator.resolve_safe(Path(file_path))
                    if not resolved.exists():
                        context.warnings.append(
                            f"Future requirement missing: {file_path}"
                        )
                except ValueError as e:
                    context.warnings.append(str(e))
        
        return valid


class Orchestrator:
    """Main orchestration engine"""
    
    def __init__(self):
        self.aeon_root = self._detect_aeon_root()
        self.path_validator = PathValidator(self.aeon_root)
        self.manifest_validator = ManifestValidator(self.path_validator)
    
    def _detect_aeon_root(self) -> Path:
        """Detect AEON_ROOT from environment or platform default"""
        if 'AEON_ROOT' in os.environ:
            return Path(os.environ['AEON_ROOT'])
        
        # Platform-specific defaults
        if sys.platform == 'darwin':
            return Path('/usr/local/aeon')
        else:
            return Path('/opt/aeon')
    
    def run(self, argv: List[str]) -> int:
        """
        Main orchestration entrypoint
        
        Returns:
            Exit code (0-4)
        """
        try:
            # Parse bootstrap args
            files, configs, raw_args = BootstrapParser.parse(argv)
            
            if not files:
                self._print_usage()
                return ExitCode.CLI_USAGE_ERROR.value
            
            # Load entry manifest
            entry_file = self.path_validator.resolve_safe(files[0], must_exist=True)
            
            try:
                with open(entry_file) as f:
                    manifest = json.load(f)
            except (IOError, json.JSONDecodeError) as e:
                print(f"ERROR: Failed to load manifest: {e}", file=sys.stderr)
                return ExitCode.VALIDATION_FAILURE.value
            
            # Parse CLI flags from manifest schema
            cli_schema = manifest.get('cli', {}).get('flags_schema', {})
            flag_parser = FlagParser(cli_schema)
            parsed_flags = flag_parser.parse(raw_args)
            
            # Check for flag parsing errors
            if parsed_flags.errors:
                for error in parsed_flags.errors:
                    print(f"ERROR: {error}", file=sys.stderr)
                return ExitCode.CLI_USAGE_ERROR.value
            
            # Build execution context
            context = ExecutionContext(
                aeon_root=self.aeon_root,
                entry_file=entry_file,
                config_files=[self.path_validator.resolve_safe(c) for c in configs],
                flags=parsed_flags.values,
                warnings=parsed_flags.warnings.copy(),
                errors=[]
            )
            
            # Validate manifest
            if not self.manifest_validator.validate(manifest, context):
                for error in context.errors:
                    print(f"ERROR: {error}", file=sys.stderr)
                return ExitCode.VALIDATION_FAILURE.value
            
            # Display warnings if not in noninteractive mode
            if context.warnings and not context.noninteractive:
                for warning in context.warnings:
                    print(f"WARNING: {warning}", file=sys.stderr)
            
            # Execute orchestration
            success = self._execute(manifest, context)
            
            return ExitCode.SUCCESS.value if success else ExitCode.RUNTIME_FAILURE.value
            
        except ValueError as e:
            print(f"ERROR: {e}", file=sys.stderr)
            return ExitCode.VALIDATION_FAILURE.value
        except ImportError as e:
            print(f"ERROR: Dependency failure: {e}", file=sys.stderr)
            return ExitCode.DEPENDENCY_FAILURE.value
        except Exception as e:
            print(f"ERROR: Unexpected failure: {e}", file=sys.stderr)
            return ExitCode.RUNTIME_FAILURE.value
    
    def _execute(self, manifest: Dict[str, Any], context: ExecutionContext) -> bool:
        """
        Execute manifest actions
        
        Returns:
            True if all actions succeeded
        """
        if not context.noninteractive:
            print(f"AEON Orchestrator v1.3.0")
            print(f"Root: {context.aeon_root}")
            print(f"Entry: {context.entry_file.name}")
            print(f"Flags: {json.dumps(context.flags, indent=2)}")
            print()
        
        # TODO: Load and execute actions from manifest
        # This is where action registry integration would happen
        
        actions = manifest.get('actions', [])
        if not actions:
            if not context.noninteractive:
                print("No actions defined in manifest")
            return True
        
        if not context.noninteractive:
            print(f"Executing {len(actions)} actions...")
        
        # Placeholder for actual action execution
        for i, action in enumerate(actions, 1):
            action_type = action.get('type', 'unknown')
            if not context.noninteractive:
                print(f"  [{i}/{len(actions)}] {action_type}")
        
        return True
    
    def _print_usage(self):
        """Print usage information"""
        print("AEON Orchestrator v1.3.0 - Dynamic CLI Execution Engine", file=sys.stderr)
        print("", file=sys.stderr)
        print("Usage:", file=sys.stderr)
        print("  orchestrator.json.py --file:/path/to/manifest.json [OPTIONS]", file=sys.stderr)
        print("", file=sys.stderr)
        print("Bootstrap Arguments (hardcoded):", file=sys.stderr)
        print("  --file:/path        Entry instruction manifest (required, repeatable)", file=sys.stderr)
        print("  --config:/path      Configuration overlay (optional, repeatable)", file=sys.stderr)
        print("", file=sys.stderr)
        print("All other flags are defined by the manifest's cli.flags_schema", file=sys.stderr)
        print("", file=sys.stderr)
        print("Exit Codes:", file=sys.stderr)
        print("  0: Success", file=sys.stderr)
        print("  1: Runtime/step failure", file=sys.stderr)
        print("  2: CLI usage error", file=sys.stderr)
        print("  3: Validation failure", file=sys.stderr)
        print("  4: Dependency failure", file=sys.stderr)


def main():
    """CLI entrypoint"""
    orchestrator = Orchestrator()
    exit_code = orchestrator.run(sys.argv[1:])
    sys.exit(exit_code)


if __name__ == '__main__':
    main()