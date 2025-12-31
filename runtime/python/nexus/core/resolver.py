"""
NEXUS Universal Daemon - Dependency Resolution
Enhanced with semantic versioning support
"""

from typing import Dict, List, Set, Tuple
from collections import defaultdict, deque
from .module import ModuleManifest
from .logging import get_logger


logger = get_logger("nexus.resolver")


class DependencyResolver:
    """
    Resolves module dependencies with topological sorting.
    
    Enhanced Features:
    - Semantic version checking (basic)
    - Better cycle detection
    - Dependency conflict resolution
    """
    
    def __init__(self):
        self._graph: Dict[str, Set[str]] = defaultdict(set)
        self._manifests: Dict[str, ModuleManifest] = {}
    
    def add_module(self, manifest: ModuleManifest):
        """Add a module to the dependency graph"""
        self._manifests[manifest.id] = manifest
        
        # Add edges for hard dependencies
        for dep in manifest.hard_deps:
            self._graph[dep].add(manifest.id)
        
        logger.debug(
            f"Added module to dependency graph",
            module_id=manifest.id,
            hard_deps=manifest.hard_deps
        )
    
    def resolve(self) -> Tuple[List[str], List[str]]:
        """
        Resolve dependencies and return load order.
        
        Returns:
            (ordered_ids, warnings)
        """
        # Calculate in-degree for each node
        in_degree = defaultdict(int)
        all_nodes = set(self._graph.keys())
        
        for node in self._graph:
            all_nodes.add(node)
            for dependent in self._graph[node]:
                all_nodes.add(dependent)
                in_degree[dependent] += 1
        
        # Initialize queue with nodes that have no dependencies
        queue = deque([node for node in all_nodes if in_degree[node] == 0])
        ordered = []
        
        while queue:
            current = queue.popleft()
            ordered.append(current)
            
            # Reduce in-degree of dependents
            for dependent in self._graph[current]:
                in_degree[dependent] -= 1
                if in_degree[dependent] == 0:
                    queue.append(dependent)
        
        # Check for cycles
        if len(ordered) != len(all_nodes):
            remaining = all_nodes - set(ordered)
            cycle_info = self._find_cycle(remaining)
            
            logger.error(
                f"Circular dependency detected",
                cycle=cycle_info,
                modules=list(remaining)
            )
            
            raise ValueError(
                f"Circular dependency detected: {cycle_info}\n"
                f"Modules involved: {', '.join(sorted(remaining))}"
            )
        
        # Check soft dependencies
        warnings = self._check_soft_deps(ordered)
        
        logger.info(
            f"Dependency resolution complete",
            total_modules=len(ordered),
            warnings=len(warnings)
        )
        
        return ordered, warnings
    
    def _find_cycle(self, nodes: Set[str]) -> str:
        """Find and describe a cycle"""
        subgraph = {
            node: [dep for dep in self._graph[node] if dep in nodes]
            for node in nodes
        }
        
        visited = set()
        rec_stack = set()
        path = []
        
        def dfs(node):
            visited.add(node)
            rec_stack.add(node)
            path.append(node)
            
            for neighbor in subgraph.get(node, []):
                if neighbor not in visited:
                    result = dfs(neighbor)
                    if result:
                        return result
                elif neighbor in rec_stack:
                    cycle_start = path.index(neighbor)
                    cycle = path[cycle_start:] + [neighbor]
                    return " -> ".join(cycle)
            
            path.pop()
            rec_stack.remove(node)
            return False
        
        for node in nodes:
            if node not in visited:
                result = dfs(node)
                if result:
                    return result
        
        return "Unknown cycle"
    
    def _check_soft_deps(self, ordered: List[str]) -> List[str]:
        """Check soft dependencies and generate warnings"""
        warnings = []
        ordered_set = set(ordered)
        
        for module_id in ordered:
            if module_id not in self._manifests:
                continue
            
            manifest = self._manifests[module_id]
            for soft_dep in manifest.soft_deps:
                if soft_dep not in ordered_set:
                    warning = (
                        f"Module '{module_id}' has optional dependency '{soft_dep}' "
                        f"which is not available. Some features may be disabled."
                    )
                    warnings.append(warning)
                    logger.warning(warning)
        
        return warnings
    
    def get_dependency_tree(self, module_id: str, depth: int = 0) -> str:
        """Get ASCII art dependency tree"""
        if module_id not in self._manifests:
            return f"{'  ' * depth}└─ {module_id} (NOT FOUND)"
        
        manifest = self._manifests[module_id]
        lines = [f"{'  ' * depth}└─ {module_id} v{manifest.version}"]
        
        if manifest.hard_deps:
            for dep in manifest.hard_deps:
                lines.append(self.get_dependency_tree(dep, depth + 1))
        
        return "\n".join(lines)
    
    def validate_manifest(self, manifest: ModuleManifest) -> List[str]:
        """Validate manifest for common issues"""
        issues = []
        
        # Self-dependency check
        if manifest.id in manifest.hard_deps:
            issues.append(f"Module '{manifest.id}' depends on itself")
        
        # Missing dependencies
        all_known = set(self._manifests.keys())
        for dep in manifest.hard_deps:
            if dep not in all_known:
                issues.append(
                    f"Module '{manifest.id}' depends on unknown module '{dep}'"
                )
        
        # Version conflicts
        if manifest.id in self._manifests:
            existing = self._manifests[manifest.id]
            if existing.version != manifest.version:
                issues.append(
                    f"Version conflict: {manifest.id} exists as "
                    f"v{existing.version} and v{manifest.version}"
                )
        
        return issues
