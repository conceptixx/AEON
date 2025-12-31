"""
NEXUS v2 - Module Loader
Addresses Review: Monolithic Loader, No State Persistence, SRP Violation
"""

import asyncio
import importlib
import inspect
import json
import logging
from typing import Dict, List, Optional, Set, Type
from pathlib import Path
from abc import ABC, abstractmethod

from .module import BaseModule, ModuleManifest, ModuleState, SecurityContext
from .resolver import DependencyResolver
from .config import ConfigurationManager


logger = logging.getLogger(__name__)


class StateStore(ABC):
    """
    Abstract state store for module persistence.
    Addresses Review: No Data Persistence
    """
    
    @abstractmethod
    async def save_state(self, module_id: str, state: Dict):
        """Save module state"""
        pass
    
    @abstractmethod
    async def load_state(self, module_id: str) -> Optional[Dict]:
        """Load module state"""
        pass
    
    @abstractmethod
    async def delete_state(self, module_id: str):
        """Delete module state"""
        pass


class FileStateStore(StateStore):
    """File-based state store"""
    
    def __init__(self, state_dir: Path):
        self.state_dir = Path(state_dir)
        self.state_dir.mkdir(parents=True, exist_ok=True)
    
    async def save_state(self, module_id: str, state: Dict):
        """Save module state to JSON file"""
        state_file = self.state_dir / f"{module_id.replace('/', '_')}.json"
        
        with open(state_file, 'w') as f:
            json.dump(state, f, indent=2)
        
        logger.debug(f"Saved state for {module_id}")
    
    async def load_state(self, module_id: str) -> Optional[Dict]:
        """Load module state from JSON file"""
        state_file = self.state_dir / f"{module_id.replace('/', '_')}.json"
        
        if not state_file.exists():
            return None
        
        try:
            with open(state_file) as f:
                state = json.load(f)
            
            logger.debug(f"Loaded state for {module_id}")
            return state
        except Exception as e:
            logger.error(f"Failed to load state for {module_id}: {e}")
            return None
    
    async def delete_state(self, module_id: str):
        """Delete module state"""
        state_file = self.state_dir / f"{module_id.replace('/', '_')}.json"
        
        if state_file.exists():
            state_file.unlink()
            logger.debug(f"Deleted state for {module_id}")


class ModuleRegistry:
    """
    Module registry - separation of concerns.
    Addresses Review: God Class
    """
    
    def __init__(self):
        self._manifests: Dict[str, ModuleManifest] = {}
        self._classes: Dict[str, Type[BaseModule]] = {}
        self._instances: Dict[str, BaseModule] = {}
    
    def register_manifest(self, manifest: ModuleManifest):
        """Register module manifest"""
        self._manifests[manifest.id] = manifest
    
    def register_class(self, module_id: str, module_class: Type[BaseModule]):
        """Register module class"""
        self._classes[module_id] = module_class
    
    def register_instance(self, module_id: str, instance: BaseModule):
        """Register module instance"""
        self._instances[module_id] = instance
    
    def unregister_instance(self, module_id: str):
        """Unregister module instance"""
        if module_id in self._instances:
            del self._instances[module_id]
    
    def get_manifest(self, module_id: str) -> Optional[ModuleManifest]:
        """Get module manifest"""
        return self._manifests.get(module_id)
    
    def get_class(self, module_id: str) -> Optional[Type[BaseModule]]:
        """Get module class"""
        return self._classes.get(module_id)
    
    def get_instance(self, module_id: str) -> Optional[BaseModule]:
        """Get module instance"""
        return self._instances.get(module_id)
    
    def get_all_manifests(self) -> List[ModuleManifest]:
        """Get all registered manifests"""
        return list(self._manifests.values())
    
    def get_all_instances(self) -> List[BaseModule]:
        """Get all registered instances"""
        return list(self._instances.values())


class ModuleDiscovery:
    """
    Module discovery - separation of concerns.
    Addresses Review: SRP Violation
    """
    
    def __init__(self, registry: ModuleRegistry):
        self.registry = registry
    
    def discover_modules(self, package_names: List[str]) -> List[ModuleManifest]:
        """
        Discover modules from Python packages.
        
        Args:
            package_names: List of package names to scan
        
        Returns:
            List of discovered manifests
        """
        discovered = []
        
        for package_name in package_names:
            try:
                package = importlib.import_module(package_name)
                package_path = Path(package.__file__).parent
                
                # Scan all .py files in package
                for py_file in package_path.glob("*.py"):
                    if py_file.name.startswith("_"):
                        continue
                    
                    module_name = f"{package_name}.{py_file.stem}"
                    try:
                        module = importlib.import_module(module_name)
                        
                        # Find BaseModule subclasses
                        for name, obj in inspect.getmembers(module, inspect.isclass):
                            if (issubclass(obj, BaseModule) and 
                                obj is not BaseModule and
                                not inspect.isabstract(obj)):
                                
                                manifest = obj.get_manifest()
                                discovered.append(manifest)
                                
                                # Register
                                self.registry.register_manifest(manifest)
                                self.registry.register_class(manifest.id, obj)
                    
                    except Exception as e:
                        logger.warning(f"Failed to load module {module_name}: {e}")
            
            except Exception as e:
                logger.warning(f"Failed to discover package {package_name}: {e}")
        
        return discovered


class ModuleLifecycleManager:
    """
    Module lifecycle management - separation of concerns.
    Addresses Review: SRP Violation
    """
    
    def __init__(
        self,
        registry: ModuleRegistry,
        config: ConfigurationManager,
        state_store: Optional[StateStore] = None
    ):
        self.registry = registry
        self.config = config
        self.state_store = state_store
    
    async def load_single_module(
        self,
        module_id: str,
        context: Dict,
        security_context: Optional[SecurityContext] = None
    ) -> bool:
        """
        Load a single module through its lifecycle.
        
        Improved error handling - uses exceptions.
        """
        try:
            # Check if already loaded
            instance = self.registry.get_instance(module_id)
            if instance and instance.is_loaded:
                logger.info(f"Module {module_id} already loaded")
                return True
            
            # Get manifest and class
            manifest = self.registry.get_manifest(module_id)
            module_class = self.registry.get_class(module_id)
            
            if not manifest or not module_class:
                raise ValueError(f"Module {module_id} not found")
            
            # Check permissions
            if security_context and manifest.required_permissions:
                for permission in manifest.required_permissions:
                    if not security_context.has_permission(permission):
                        raise PermissionError(
                            f"Module {module_id} requires permission: {permission}"
                        )
            
            # Register module defaults
            self.config.register_module_defaults(module_id, manifest.config_keys)
            
            # Instantiate
            instance = module_class(manifest)
            if security_context:
                instance.security_context = security_context
            
            self.registry.register_instance(module_id, instance)
            
            # Load persisted state if available
            if self.state_store:
                state = await self.state_store.load_state(module_id)
                if state:
                    context['persisted_state'] = state
                    logger.info(f"Loaded persisted state for {module_id}")
            
            # init phase
            logger.info(f"[{module_id}] Initializing...")
            await instance.init(context)
            
            if instance.state != ModuleState.LOADED:
                raise RuntimeError(f"Module {module_id} not in LOADED state after init")
            
            # load phase
            logger.info(f"[{module_id}] Loading...")
            await instance.load(context)
            
            logger.info(f"[{module_id}] Loaded successfully")
            return True
            
        except Exception as e:
            logger.error(f"Failed to load module {module_id}: {e}", exc_info=True)
            
            # Mark as failed
            if module_id in self.registry._instances:
                self.registry._instances[module_id]._set_state(ModuleState.FAILED)
                self.registry._instances[module_id]._last_error = e
            
            raise  # Re-raise instead of returning False
    
    async def start_module(self, module_id: str) -> bool:
        """Start a loaded module"""
        try:
            instance = self.registry.get_instance(module_id)
            if not instance:
                raise ValueError(f"Module {module_id} not found")
            
            if instance.state != ModuleState.LOADED:
                raise RuntimeError(
                    f"Module {module_id} not in LOADED state (current: {instance.state.value})"
                )
            
            logger.info(f"[{module_id}] Starting...")
            await instance.start()
            
            if instance.state == ModuleState.STARTED:
                logger.info(f"[{module_id}] Started successfully")
                return True
            else:
                raise RuntimeError(f"Module {module_id} not in STARTED state after start")
                
        except Exception as e:
            logger.error(f"Failed to start module {module_id}: {e}", exc_info=True)
            raise
    
    async def stop_module(self, module_id: str, timeout: float = 30.0) -> bool:
        """Stop a started module"""
        try:
            instance = self.registry.get_instance(module_id)
            if not instance:
                raise ValueError(f"Module {module_id} not found")
            
            if instance.state != ModuleState.STARTED:
                logger.warning(f"Module {module_id} not in STARTED state, skipping stop")
                return True
            
            logger.info(f"[{module_id}] Stopping...")
            
            try:
                await asyncio.wait_for(instance.stop(), timeout=timeout)
                
                if instance.state == ModuleState.STOPPED:
                    logger.info(f"[{module_id}] Stopped successfully")
                    
                    # Save state before unload
                    if self.state_store:
                        state = {
                            'stopped_at': instance._stop_time.isoformat() if instance._stop_time else None,
                            'uptime_seconds': instance.uptime_seconds,
                            'resource_usage': instance._resource_usage
                        }
                        await self.state_store.save_state(module_id, state)
                    
                    return True
                else:
                    raise RuntimeError(f"Module {module_id} not in STOPPED state after stop")
                    
            except asyncio.TimeoutError:
                logger.error(f"[{module_id}] Stop timeout after {timeout}s")
                raise
                
        except Exception as e:
            logger.error(f"Failed to stop module {module_id}: {e}", exc_info=True)
            raise
    
    async def unload_module(self, module_id: str) -> bool:
        """Unload a stopped module"""
        try:
            instance = self.registry.get_instance(module_id)
            if not instance:
                logger.warning(f"Module {module_id} not found, already unloaded?")
                return True
            
            logger.info(f"[{module_id}] Unloading...")
            await instance.unload()
            
            if instance.state == ModuleState.UNLOADED:
                logger.info(f"[{module_id}] Unloaded successfully")
                
                # Remove from registry
                self.registry.unregister_instance(module_id)
                return True
            else:
                raise RuntimeError(f"Module {module_id} not in UNLOADED state after unload")
                
        except Exception as e:
            logger.error(f"Failed to unload module {module_id}: {e}", exc_info=True)
            raise


class ModuleLoader:
    """
    Module loader - orchestrates discovery, lifecycle, and dependency resolution.
    
    Improvements from Review:
    - Separated concerns (Discovery, Lifecycle, Registry)
    - State persistence
    - Consistent error handling (exceptions)
    - Security context propagation
    """
    
    def __init__(
        self,
        config: ConfigurationManager,
        state_store: Optional[StateStore] = None
    ):
        self.config = config
        self.state_store = state_store or FileStateStore(Path.home() / ".nexus" / "state")
        
        # Components
        self.registry = ModuleRegistry()
        self.resolver = DependencyResolver()
        self.discovery = ModuleDiscovery(self.registry)
        self.lifecycle = ModuleLifecycleManager(self.registry, config, self.state_store)
        
        # State tracking
        self._loading = False
        self._load_lock = asyncio.Lock()
    
    def discover_modules(self, package_names: List[str]) -> List[ModuleManifest]:
        """Discover modules from packages"""
        manifests = self.discovery.discover_modules(package_names)
        
        # Add to resolver
        for manifest in manifests:
            self.resolver.add_module(manifest)
        
        return manifests
    
    async def load_modules(
        self,
        module_ids: Optional[List[str]] = None,
        parallel: bool = True,
        security_context: Optional[SecurityContext] = None
    ) -> Dict[str, bool]:
        """
        Load modules in dependency order.
        
        Args:
            module_ids: Specific modules to load, or None for all
            parallel: Enable parallel loading of independent modules
            security_context: Security context for authorization
        
        Returns:
            Dict mapping module_id -> success boolean
        """
        async with self._load_lock:
            self._loading = True
            
            try:
                # Resolve dependencies
                load_order, warnings = self.resolver.resolve()
                
                # Print warnings
                for warning in warnings:
                    logger.warning(warning)
                
                # Filter to requested modules if specified
                if module_ids:
                    load_order = [mid for mid in load_order if mid in module_ids]
                
                # Build dependency levels for parallel loading
                levels = self._build_dependency_levels(load_order)
                
                results = {}
                context = {
                    "config": self.config,
                    "registry": self.registry,
                }
                
                # Load level by level
                for level in levels:
                    if parallel and len(level) > 1:
                        # Parallel load modules in same level
                        tasks = [
                            self.lifecycle.load_single_module(mid, context, security_context)
                            for mid in level
                        ]
                        level_results = await asyncio.gather(*tasks, return_exceptions=True)
                        
                        for mid, result in zip(level, level_results):
                            if isinstance(result, Exception):
                                logger.error(f"Error loading {mid}: {result}")
                                results[mid] = False
                            else:
                                results[mid] = result
                    else:
                        # Sequential load
                        for mid in level:
                            try:
                                results[mid] = await self.lifecycle.load_single_module(
                                    mid, context, security_context
                                )
                            except Exception as e:
                                logger.error(f"Error loading {mid}: {e}")
                                results[mid] = False
                
                return results
                
            finally:
                self._loading = False
    
    async def start_modules(
        self,
        module_ids: Optional[List[str]] = None
    ) -> Dict[str, bool]:
        """Start loaded modules"""
        if module_ids is None:
            module_ids = [mid for mid, instance in self.registry._instances.items()]
        
        results = {}
        
        for module_id in module_ids:
            try:
                results[module_id] = await self.lifecycle.start_module(module_id)
            except Exception as e:
                logger.error(f"Failed to start {module_id}: {e}")
                results[module_id] = False
        
        return results
    
    async def stop_modules(
        self,
        module_ids: Optional[List[str]] = None,
        timeout: float = 30.0
    ) -> Dict[str, bool]:
        """Stop started modules in reverse dependency order"""
        if module_ids is None:
            module_ids = [mid for mid, instance in self.registry._instances.items()]
        
        # Stop in reverse dependency order
        load_order, _ = self.resolver.resolve()
        stop_order = [mid for mid in reversed(load_order) if mid in module_ids]
        
        results = {}
        
        for module_id in stop_order:
            try:
                results[module_id] = await self.lifecycle.stop_module(module_id, timeout)
            except Exception as e:
                logger.error(f"Failed to stop {module_id}: {e}")
                results[module_id] = False
        
        return results
    
    async def unload_modules(
        self,
        module_ids: Optional[List[str]] = None
    ) -> Dict[str, bool]:
        """Unload stopped modules in reverse dependency order"""
        if module_ids is None:
            module_ids = [mid for mid, instance in self.registry._instances.items()]
        
        # Unload in reverse dependency order
        load_order, _ = self.resolver.resolve()
        unload_order = [mid for mid in reversed(load_order) if mid in module_ids]
        
        results = {}
        
        for module_id in unload_order:
            try:
                results[module_id] = await self.lifecycle.unload_module(module_id)
            except Exception as e:
                logger.error(f"Failed to unload {module_id}: {e}")
                results[module_id] = False
        
        return results
    
    def _build_dependency_levels(self, ordered_ids: List[str]) -> List[List[str]]:
        """Build dependency levels for parallel loading"""
        levels = []
        remaining = set(ordered_ids)
        loaded = set()
        
        while remaining:
            current_level = []
            
            for module_id in list(remaining):
                manifest = self.registry.get_manifest(module_id)
                if not manifest:
                    continue
                
                deps_satisfied = all(
                    dep in loaded or dep not in remaining
                    for dep in manifest.hard_deps
                )
                
                if deps_satisfied:
                    current_level.append(module_id)
            
            if not current_level:
                break
            
            levels.append(current_level)
            loaded.update(current_level)
            remaining -= set(current_level)
        
        return levels
    
    def get_module(self, module_id: str) -> Optional[BaseModule]:
        """Get loaded module instance"""
        return self.registry.get_instance(module_id)
    
    def get_status(self) -> Dict[str, Any]:
        """Get loader status"""
        return {
            "total_discovered": len(self.registry._manifests),
            "total_loaded": len(self.registry._instances),
            "modules": {
                module_id: {
                    "state": instance.state.value,
                    "uptime_seconds": instance.uptime_seconds,
                }
                for module_id, instance in self.registry._instances.items()
            }
        }
