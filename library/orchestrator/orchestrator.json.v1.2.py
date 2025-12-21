#!/usr/bin/env python3
"""
AEON Orchestrator v1.0.2
Minimal, modular instruction-based orchestration engine
"""
import sys
import os
import json
import importlib
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Any, Optional


class AEONOrchestrator:
    """Main orchestration engine for AEON instruction sets."""
    
    def __init__(self):
        self.aeon_root = self._determine_aeon_root()
        self.context = {
            "AEON_ROOT": self.aeon_root,
            "noninteractive": False,
            "cli_enabled": False,
            "web_enabled": False
        }
        self.warnings = []
        self.loaded_configs = {}
        self.loaded_instructions = {}
        self.step_results = {}
        self.registry = None
        self.expected_files_map = {}  # NEW: Map of file paths to their specs
        
    def _determine_aeon_root(self) -> str:
        """Determine AEON_ROOT from environment or platform defaults."""
        if "AEON_ROOT" in os.environ:
            return os.environ["AEON_ROOT"]
        
        # Platform-specific defaults
        if sys.platform == "darwin":
            return "/usr/local/aeon"
        return "/opt/aeon"
    
    def _resolve_path(self, path: str) -> Path:
        """Resolve path relative to AEON_ROOT if it starts with /."""
        if path.startswith("/"):
            return Path(self.aeon_root) / path.lstrip("/")
        return Path(path)
    
    def _load_json(self, path: str) -> Dict:
        """Load and parse JSON file."""
        resolved = self._resolve_path(path)
        try:
            with open(resolved, 'r') as f:
                return json.load(f)
        except json.JSONDecodeError as e:
            print(f"ERROR: JSON parse error in {resolved}: {e}", file=sys.stderr)
            sys.exit(3)
        except FileNotFoundError:
            print(f"ERROR: File not found: {resolved}", file=sys.stderr)
            sys.exit(3)
    
    def _load_registry(self) -> Dict:
        """Load action registry."""
        registry_path = Path(self.aeon_root) / "library/python/aeon/actions/registry.json"
        if not registry_path.exists():
            print(f"ERROR: Registry not found: {registry_path}", file=sys.stderr)
            sys.exit(4)
        
        try:
            with open(registry_path, 'r') as f:
                return json.load(f)
        except json.JSONDecodeError as e:
            print(f"ERROR: Registry JSON parse error: {e}", file=sys.stderr)
            sys.exit(3)
    
    def _check_expected_files(self, expected_files: List[Dict]):
        """Check expected files according to their policies."""
        for file_spec in expected_files:
            path = file_spec.get("path")
            policy = file_spec.get("policy", "optional")
            resolved = self._resolve_path(path)
            
            # NEW: Store in map for later requires_files validation
            self.expected_files_map[path] = {
                "policy": policy,
                "resolved": resolved
            }
            
            if policy == "required_now":
                if not resolved.exists():
                    print(f"ERROR: Required file missing: {resolved}", file=sys.stderr)
                    sys.exit(3)
            elif policy == "required_eventually":
                if not resolved.exists():
                    self.warnings.append(f"Required eventually file missing: {resolved}")
    
    def _resolve_action(self, action_name: str) -> callable:
        """Resolve action name to callable via registry."""
        if self.registry is None:
            self.registry = self._load_registry()
        
        if action_name not in self.registry:
            print(f"ERROR: Action not found in registry: {action_name}", file=sys.stderr)
            sys.exit(4)
        
        action_spec = self.registry[action_name]
        module_name = action_spec.get("module")
        callable_name = action_spec.get("callable")
        
        if not module_name or not callable_name:
            print(f"ERROR: Invalid registry entry for {action_name}", file=sys.stderr)
            sys.exit(4)
        
        # Ensure library is in path
        lib_path = Path(self.aeon_root) / "library/python"
        if str(lib_path) not in sys.path:
            sys.path.insert(0, str(lib_path))
        
        try:
            module = importlib.import_module(module_name)
        except ImportError as e:
            print(f"ERROR: Cannot import module {module_name}: {e}", file=sys.stderr)
            sys.exit(4)
        
        if not hasattr(module, callable_name):
            print(f"ERROR: Callable {callable_name} not found in {module_name}", file=sys.stderr)
            sys.exit(4)
        
        return getattr(module, callable_name)
    
    def _resolve_reference(self, ref: str) -> Any:
        """Resolve @step:<id> or @config:<id> references."""
        if ref.startswith("@step:"):
            step_id = ref[6:]
            if step_id not in self.step_results:
                print(f"ERROR: Referenced step not found: {step_id}", file=sys.stderr)
                sys.exit(1)
            return self.step_results[step_id]
        
        elif ref.startswith("@config:"):
            config_id = ref[8:]
            if config_id not in self.loaded_configs:
                print(f"ERROR: Referenced config not found: {config_id}", file=sys.stderr)
                sys.exit(1)
            return self.loaded_configs[config_id]
        
        return ref
    
    def _resolve_args(self, args: Dict) -> Dict:
        """Recursively resolve references in arguments."""
        resolved = {}
        for key, value in args.items():
            if isinstance(value, str) and value.startswith("@"):
                resolved[key] = self._resolve_reference(value)
            elif isinstance(value, dict):
                resolved[key] = self._resolve_args(value)
            elif isinstance(value, list):
                resolved[key] = [
                    self._resolve_reference(v) if isinstance(v, str) and v.startswith("@") else v
                    for v in value
                ]
            else:
                resolved[key] = value
        return resolved
    
    def _validate_requires_files(self, step: Dict):
        """NEW: Validate requires_files before step execution."""
        requires_files = step.get("requires_files", [])
        if not requires_files:
            return
        
        step_id = step.get("id", "<unknown>")
        
        for required_path in requires_files:
            # Check if path is in expected_files
            if required_path not in self.expected_files_map:
                print(f"ERROR: Step '{step_id}' requires_files references unknown path: {required_path}", file=sys.stderr)
                print(f"  Path must be declared in expected_files section", file=sys.stderr)
                sys.exit(3)
            
            file_spec = self.expected_files_map[required_path]
            resolved_path = file_spec["resolved"]
            policy = file_spec["policy"]
            
            # If policy is required_eventually and file doesn't exist: FAIL
            if policy == "required_eventually" and not resolved_path.exists():
                print(f"ERROR: Step '{step_id}' requires file with policy 'required_eventually' that does not exist:", file=sys.stderr)
                print(f"  Path: {required_path}", file=sys.stderr)
                print(f"  Resolved: {resolved_path}", file=sys.stderr)
                sys.exit(1)
            
            # For any other policy, still check existence
            if not resolved_path.exists():
                print(f"ERROR: Step '{step_id}' requires missing file:", file=sys.stderr)
                print(f"  Path: {required_path}", file=sys.stderr)
                print(f"  Resolved: {resolved_path}", file=sys.stderr)
                sys.exit(1)
    
    def _execute_step(self, step: Dict) -> Dict:
        """Execute a single step."""
        step_id = step.get("id")
        action_name = step.get("action")
        args = step.get("args", {})
        
        # NEW: Validate requires_files before execution
        self._validate_requires_files(step)
        
        # Resolve arguments
        resolved_args = self._resolve_args(args)
        
        # Get action callable
        action_fn = self._resolve_action(action_name)
        
        # Execute
        try:
            result = action_fn(self.context, resolved_args)
            return {
                "id": step_id,
                "action": action_name,
                "status": "success",
                "result": result
            }
        except Exception as e:
            print(f"ERROR: Step {step_id} failed: {e}", file=sys.stderr)
            return {
                "id": step_id,
                "action": action_name,
                "status": "failed",
                "error": str(e)
            }
    
    def _execute_flow(self, steps: List[Dict]) -> List[Dict]:
        """Execute a flow of steps."""
        results = []
        step_ids = set()
        
        # Check for duplicate IDs
        for step in steps:
            step_id = step.get("id")
            if step_id in step_ids:
                print(f"ERROR: Duplicate step ID: {step_id}", file=sys.stderr)
                sys.exit(3)
            step_ids.add(step_id)
        
        # Execute steps
        for step in steps:
            result = self._execute_step(step)
            results.append(result)
            
            # Store result for references
            self.step_results[result["id"]] = result.get("result")
            
            # Stop on failure
            if result["status"] == "failed":
                sys.exit(1)
        
        return results
    
    def _write_result(self, instruction: Dict, step_results: List[Dict]):
        """Write result JSON to output path."""
        outputs = instruction.get("outputs", {})
        result_path = outputs.get("result", "/runtime/last_result.json")
        resolved_path = self._resolve_path(result_path)
        
        # Ensure directory exists
        resolved_path.parent.mkdir(parents=True, exist_ok=True)
        
        result = {
            "meta": {
                "timestamp": datetime.now().isoformat(),
                "AEON_ROOT": self.aeon_root,
                "mode": "noninteractive" if self.context["noninteractive"] else "interactive",
                "flags": {
                    "cli_enabled": self.context["cli_enabled"],
                    "web_enabled": self.context["web_enabled"]
                },
                "entry_path": self.context.get("entry_path", "")
            },
            "warnings": self.warnings,
            "steps": step_results
        }
        
        with open(resolved_path, 'w') as f:
            json.dump(result, f, indent=2)
        
        return resolved_path
    
    def _print_summary(self, step_results: List[Dict]):
        """Print stdout summary if enabled."""
        print("=" * 60)
        print("AEON Orchestrator v1.0.2 - Execution Summary")
        print("=" * 60)
        
        for step in step_results:
            status_icon = "✓" if step["status"] == "success" else "✗"
            print(f"{status_icon} {step['id']}: {step['action']} - {step['status'].upper()}")
            
            if step["status"] == "success" and step.get("result"):
                # Print key outcomes
                result = step["result"]
                if isinstance(result, dict):
                    for key, value in list(result.items())[:3]:  # First 3 items
                        print(f"  → {key}: {value}")
        
        print("=" * 60)
    
    def run(self, entry_path: str):
        """Main orchestration entry point."""
        self.context["entry_path"] = entry_path
        
        # Load entry instruction
        instruction = self._load_json(entry_path)
        
        # Validate schema
        if instruction.get("schema") != "aeon.instructions":
            print("ERROR: Invalid schema", file=sys.stderr)
            sys.exit(3)
        
        if instruction.get("version") != "1.0":
            print("ERROR: Unsupported version", file=sys.stderr)
            sys.exit(3)
        
        # Load referenced configs (demand-load)
        refs = instruction.get("refs", {})
        if "configs" in refs:
            for config_id, config_path in refs["configs"].items():
                self.loaded_configs[config_id] = self._load_json(config_path)
        
        # Check expected files
        expected_files = instruction.get("expected_files", [])
        self._check_expected_files(expected_files)
        
        # Select flow
        flows = instruction.get("flows", {})
        if self.context["noninteractive"]:
            if "noninteractive" not in flows:
                print("ERROR: Noninteractive flow not defined", file=sys.stderr)
                sys.exit(3)
            steps = flows["noninteractive"]
        else:
            if "interactive" not in flows:
                print("ERROR: Interactive flow not defined", file=sys.stderr)
                sys.exit(3)
            steps = flows["interactive"]
        
        # Execute flow
        step_results = self._execute_flow(steps)
        
        # Write result
        result_path = self._write_result(instruction, step_results)
        
        # Print summary if enabled
        outputs = instruction.get("outputs", {})
        if outputs.get("stdout_summary", True):
            self._print_summary(step_results)
        
        print(f"\nResult written to: {result_path}")


def parse_args(argv: List[str]) -> Dict[str, Any]:
    """Parse command line arguments."""
    args = {
        "file": None,
        "configs": [],
        "noninteractive": False,
        "cli_enabled": False,
        "web_enabled": False
    }
    
    warnings = []
    i = 0
    
    while i < len(argv):
        arg = argv[i]
        
        # File argument (required)
        if arg.startswith("--file:") or arg.startswith("--FILE:"):
            args["file"] = arg.split(":", 1)[1]
        
        # Config argument (repeatable)
        elif arg.startswith("--config:") or arg.startswith("--CONFIG:"):
            args["configs"].append(arg.split(":", 1)[1])
        
        # CLI flags
        elif arg.lower() in ["-c", "--cli-enable", "--enable-cli"]:
            args["cli_enabled"] = True
        elif arg.lower() in ["-C"]:
            args["cli_enabled"] = False
        
        # Web flags
        elif arg.lower() in ["-w", "--web-enable", "--enable-web"]:
            args["web_enabled"] = True
        elif arg.lower() in ["-W"]:
            args["web_enabled"] = False
        
        # Noninteractive flags
        elif arg.lower() in ["-n", "--noninteractive", "--NONINTERACTIVE"]:
            args["noninteractive"] = True
        elif arg.lower() in ["-N"]:
            args["noninteractive"] = False
        
        # Unknown flag (looks like a flag)
        elif arg.startswith("-"):
            print(f"ERROR: Unknown flag: {arg}", file=sys.stderr)
            sys.exit(2)
        
        # NEW: Unknown non-flag argument becomes warning
        else:
            warnings.append(f"Unknown argument ignored: {arg}")
        
        i += 1
    
    return args, warnings


def main():
    """Main entry point."""
    if len(sys.argv) < 2:
        print("Usage: orchestrator.json.py --file:<path> [options]", file=sys.stderr)
        print("Options:", file=sys.stderr)
        print("  --file:<path>         Entry instruction file (required)", file=sys.stderr)
        print("  --config:<path>       Additional config file (repeatable)", file=sys.stderr)
        print("  -n, --noninteractive  Run in noninteractive mode", file=sys.stderr)
        print("  -c, --cli-enable      Enable CLI mode", file=sys.stderr)
        print("  -w, --web-enable      Enable web mode", file=sys.stderr)
        sys.exit(2)
    
    # Parse arguments
    args, warnings = parse_args(sys.argv[1:])
    
    # Validate required arguments
    if not args["file"]:
        print("ERROR: --file:<path> is required", file=sys.stderr)
        sys.exit(2)
    
    # Create orchestrator
    orchestrator = AEONOrchestrator()
    orchestrator.context["noninteractive"] = args["noninteractive"]
    orchestrator.context["cli_enabled"] = args["cli_enabled"]
    orchestrator.context["web_enabled"] = args["web_enabled"]
    orchestrator.warnings.extend(warnings)
    
    # Run orchestration
    orchestrator.run(args["file"])


if __name__ == "__main__":
    main()
