#!/usr/bin/env python3
"""
AEON Orchestrator v1.0
Minimal, modular Python orchestrator for instruction-based workflows
"""

import sys
import os
import json
import platform
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


class OrchestratorContext:
    """Execution context passed to all actions"""
    def __init__(self, aeon_root: str, flags: Dict[str, bool], noninteractive: bool):
        self.aeon_root = aeon_root
        self.cli_enabled = flags.get('cli', False)
        self.web_enabled = flags.get('web', False)
        self.noninteractive = noninteractive
        self.step_results = {}
        self.loaded_configs = {}
        self.loaded_instructions = {}
        self.warnings = []


class OrchestratorError(Exception):
    """Base exception with exit code"""
    exit_code = 1


class UsageError(OrchestratorError):
    exit_code = 2


class ValidationError(OrchestratorError):
    exit_code = 3


class DependencyError(OrchestratorError):
    exit_code = 4


class UserAbortError(OrchestratorError):
    exit_code = 5


def determine_aeon_root() -> str:
    """Determine AEON_ROOT from env or platform defaults"""
    if 'AEON_ROOT' in os.environ:
        return os.environ['AEON_ROOT']
    
    if platform.system() == 'Darwin':
        return '/usr/local/aeon'
    else:
        return '/opt/aeon'


def resolve_path(path: str, aeon_root: str) -> str:
    """Resolve relative paths to absolute within AEON_ROOT"""
    if path.startswith('/'):
        # Absolute path within AEON_ROOT
        return os.path.join(aeon_root, path.lstrip('/'))
    else:
        # Relative path
        return os.path.join(aeon_root, path)


def load_json_file(path: str) -> Dict[str, Any]:
    """Load and parse JSON file with error handling"""
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        raise ValidationError(f"JSON parse error in {path}: {e}")
    except FileNotFoundError:
        raise ValidationError(f"File not found: {path}")
    except Exception as e:
        raise ValidationError(f"Error loading {path}: {e}")


def validate_instruction_schema(data: Dict[str, Any], path: str):
    """Validate instruction JSON schema"""
    if not isinstance(data, dict):
        raise ValidationError(f"Invalid instruction format in {path}")
    
    if data.get('schema') != 'aeon.instructions':
        raise ValidationError(f"Invalid schema in {path}, expected 'aeon.instructions'")
    
    if data.get('version') != '1.0':
        raise ValidationError(f"Invalid version in {path}, expected '1.0'")


def parse_cli_args(args: List[str]) -> Tuple[str, List[str], Dict[str, bool], bool]:
    """Parse CLI arguments and return (entry_file, config_files, flags, noninteractive)"""
    entry_file = None
    config_files = []
    flags = {'cli': False, 'web': False}
    noninteractive = False
    unknown_flags = []
    
    i = 0
    while i < len(args):
        arg = args[i]
        
        # Handle --file:<path>
        if arg.startswith('--file:'):
            entry_file = arg.split(':', 1)[1]
        # Handle --config:<path>
        elif arg.startswith('--config:'):
            config_files.append(arg.split(':', 1)[1])
        # Handle CLI flags (case-insensitive long form)
        elif arg.lower() in ['-c', '--cli-enable', '--enable-cli']:
            flags['cli'] = True
        # Handle web flags (case-insensitive long form)
        elif arg.lower() in ['-w', '--web-enable', '--enable-web']:
            flags['web'] = True
        # Handle noninteractive flags (case-insensitive long form)
        elif arg.lower() in ['-n', '--noninteractive', '--noninteractive']:
            noninteractive = True
        # Unknown flags that look like flags
        elif arg.startswith('-'):
            unknown_flags.append(arg)
        
        i += 1
    
    if not entry_file:
        raise UsageError("Required argument --file:<path> not provided")
    
    if unknown_flags:
        raise UsageError(f"Unknown flags: {', '.join(unknown_flags)}")
    
    return entry_file, config_files, flags, noninteractive


def check_expected_files(expected: List[Dict[str, str]], aeon_root: str, context: OrchestratorContext):
    """Check expected_files policies: required_now, required_eventually, optional"""
    for file_spec in expected:
        path = resolve_path(file_spec['path'], aeon_root)
        policy = file_spec.get('policy', 'optional')
        
        if policy == 'required_now':
            if not os.path.exists(path):
                raise ValidationError(f"Required file missing: {path}")
        elif policy == 'required_eventually':
            if not os.path.exists(path):
                context.warnings.append(f"File will be required eventually: {path}")


def load_action_registry(aeon_root: str) -> Dict[str, Dict[str, Any]]:
    """Load action registry from registry.json"""
    registry_path = resolve_path('/library/python/aeon/actions/registry.json', aeon_root)
    
    if not os.path.exists(registry_path):
        raise DependencyError(f"Action registry not found: {registry_path}")
    
    return load_json_file(registry_path)


def resolve_action(action_name: str, registry: Dict[str, Dict[str, Any]], aeon_root: str):
    """Resolve action to callable function"""
    if action_name not in registry:
        raise DependencyError(f"Action not found in registry: {action_name}")
    
    action_spec = registry[action_name]
    module_name = action_spec.get('module')
    callable_name = action_spec.get('callable')
    
    if not module_name or not callable_name:
        raise DependencyError(f"Invalid registry entry for action: {action_name}")
    
    # Setup sys.path to include library/python
    lib_path = resolve_path('/library/python', aeon_root)
    if lib_path not in sys.path:
        sys.path.insert(0, lib_path)
    
    try:
        module = __import__(module_name, fromlist=[callable_name])
        callable_func = getattr(module, callable_name)
        return callable_func
    except ImportError as e:
        raise DependencyError(f"Failed to import module {module_name}: {e}")
    except AttributeError:
        raise DependencyError(f"Callable {callable_name} not found in module {module_name}")


def resolve_reference(ref: str, context: OrchestratorContext, aeon_root: str) -> Any:
    """Resolve @step:<id> or @config:<id> references"""
    if ref.startswith('@step:'):
        step_id = ref[6:]
        if step_id not in context.step_results:
            raise OrchestratorError(f"Step result not found: {step_id}")
        return context.step_results[step_id]
    
    elif ref.startswith('@config:'):
        config_id = ref[8:]
        
        # Demand-load config if not already loaded
        if config_id not in context.loaded_configs:
            # Need to find config path in refs (would be loaded from instruction)
            raise OrchestratorError(f"Config not loaded: {config_id}")
        
        return context.loaded_configs[config_id]
    
    return ref


def resolve_args(args: Dict[str, Any], context: OrchestratorContext, aeon_root: str) -> Dict[str, Any]:
    """Recursively resolve references in args"""
    if isinstance(args, dict):
        return {k: resolve_args(v, context, aeon_root) for k, v in args.items()}
    elif isinstance(args, list):
        return [resolve_args(item, context, aeon_root) for item in args]
    elif isinstance(args, str) and args.startswith('@'):
        return resolve_reference(args, context, aeon_root)
    else:
        return args


def execute_step(step: Dict[str, Any], context: OrchestratorContext, registry: Dict[str, Dict[str, Any]], aeon_root: str) -> Tuple[str, Any]:
    """Execute a single step and return (status, result)"""
    step_id = step.get('id')
    action_name = step.get('action')
    args = step.get('args', {})
    
    # Resolve action
    action_func = resolve_action(action_name, registry, aeon_root)
    
    # Resolve args
    resolved_args = resolve_args(args, context, aeon_root)
    
    # Execute action
    try:
        result = action_func(context, resolved_args)
        
        # Check for user abort
        if isinstance(result, dict) and result.get('aborted'):
            raise UserAbortError("User aborted execution")
        
        # Store result
        if step_id:
            context.step_results[step_id] = result
        
        return ('success', result)
    
    except UserAbortError:
        raise
    except Exception as e:
        raise OrchestratorError(f"Action {action_name} failed: {e}")


def load_configs_and_instructions(instruction_data: Dict[str, Any], context: OrchestratorContext, aeon_root: str):
    """Load referenced configs (demand-load instructions on use)"""
    refs = instruction_data.get('refs', {})
    
    # Load configs immediately
    if 'configs' in refs:
        for config_id, config_path in refs['configs'].items():
            resolved_path = resolve_path(config_path, aeon_root)
            config_data = load_json_file(resolved_path)
            context.loaded_configs[config_id] = config_data
    
    # Store instruction refs for demand-loading (not loading now)
    if 'instructions' in refs:
        context.loaded_instructions = refs['instructions']


def execute_flow(flow_steps: List[Dict[str, Any]], context: OrchestratorContext, registry: Dict[str, Dict[str, Any]], aeon_root: str) -> List[Dict[str, Any]]:
    """Execute a flow and return step results"""
    step_results = []
    step_ids = set()
    
    for step in flow_steps:
        step_id = step.get('id')
        
        # Check for duplicate IDs
        if step_id and step_id in step_ids:
            raise ValidationError(f"Duplicate step id: {step_id}")
        if step_id:
            step_ids.add(step_id)
        
        # Execute step
        status, result = execute_step(step, context, registry, aeon_root)
        
        step_results.append({
            'id': step_id,
            'action': step.get('action'),
            'status': status,
            'result': result
        })
    
    return step_results


def write_result_json(output_path: str, result_data: Dict[str, Any], aeon_root: str):
    """Write result JSON to output path"""
    resolved_path = resolve_path(output_path, aeon_root)
    
    # Ensure directory exists
    os.makedirs(os.path.dirname(resolved_path), exist_ok=True)
    
    with open(resolved_path, 'w', encoding='utf-8') as f:
        json.dump(result_data, f, indent=2, ensure_ascii=False)


def print_summary(result_data: Dict[str, Any]):
    """Print stdout summary if enabled"""
    print("\n=== AEON Orchestrator Result ===")
    print(f"Mode: {result_data['meta']['mode']}")
    print(f"Timestamp: {result_data['meta']['timestamp']}")
    
    if result_data.get('warnings'):
        print(f"\nWarnings: {len(result_data['warnings'])}")
        for warning in result_data['warnings']:
            print(f"  - {warning}")
    
    print(f"\nSteps executed: {len(result_data['steps'])}")
    for step in result_data['steps']:
        status_icon = 'OK' if step['status'] == 'success' else 'FAIL'
        print(f"  [{status_icon}] {step['id'] or 'unnamed'}: {step['action']}")
    
    print("\n================================")


def main():
    """Main orchestrator entry point"""
    exit_code = 0
    
    try:
        # Parse CLI
        entry_file, config_files, flags, noninteractive = parse_cli_args(sys.argv[1:])
        
        # Determine AEON_ROOT
        aeon_root = determine_aeon_root()
        
        # Create context
        context = OrchestratorContext(aeon_root, flags, noninteractive)
        
        # Load entry instruction
        entry_path = resolve_path(entry_file, aeon_root)
        instruction_data = load_json_file(entry_path)
        validate_instruction_schema(instruction_data, entry_path)
        
        # Load configs and prepare instruction refs
        load_configs_and_instructions(instruction_data, context, aeon_root)
        
        # Check expected files
        expected_files = instruction_data.get('expected_files', [])
        check_expected_files(expected_files, aeon_root, context)
        
        # Load action registry
        registry = load_action_registry(aeon_root)
        
        # Determine flow
        flows = instruction_data.get('flows', {})
        if noninteractive:
            if 'noninteractive' not in flows:
                raise ValidationError("Noninteractive mode requested but no noninteractive flow defined")
            flow_steps = flows['noninteractive']
            mode = 'noninteractive'
        else:
            if 'interactive' not in flows:
                raise ValidationError("No interactive flow defined")
            flow_steps = flows['interactive']
            mode = 'interactive'
        
        # Execute flow
        step_results = execute_flow(flow_steps, context, registry, aeon_root)
        
        # Prepare result
        result_data = {
            'meta': {
                'timestamp': datetime.utcnow().isoformat() + 'Z',
                'aeon_root': aeon_root,
                'mode': mode,
                'flags': flags,
                'entry_path': entry_path
            },
            'warnings': context.warnings,
            'steps': step_results
        }
        
        # Write result
        outputs = instruction_data.get('outputs', {})
        result_path = outputs.get('result', '/runtime/last_result.json')
        write_result_json(result_path, result_data, aeon_root)
        
        # Print summary
        if outputs.get('stdout_summary', True):
            print_summary(result_data)
        
    except UsageError as e:
        print(f"[AEON][orchestrator.json][ERROR]: {e}", file=sys.stderr)
        exit_code = e.exit_code
    except ValidationError as e:
        print(f"[AEON][orchestrator.json][ERROR]: {e}", file=sys.stderr)
        exit_code = e.exit_code
    except DependencyError as e:
        print(f"[AEON][orchestrator.json][ERROR]: {e}", file=sys.stderr)
        exit_code = e.exit_code
    except UserAbortError as e:
        print(f"[AEON][orchestrator.json][ABORTED]: {e}", file=sys.stderr)
        exit_code = e.exit_code
    except OrchestratorError as e:
        print(f"[AEON][orchestrator.json][ERROR]: {e}", file=sys.stderr)
        exit_code = e.exit_code
    except Exception as e:
        print(f"[AEON][orchestrator.json][UNEXPECTED ERROR]: {e}", file=sys.stderr)
        exit_code = 1
    
    sys.exit(exit_code)


if __name__ == '__main__':
    main()
