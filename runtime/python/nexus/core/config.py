"""
NEXUS v2 - Configuration Management
Addresses Review: Insecure Config, No Vault Integration
"""

import os
import yaml
import json
import logging
from typing import Dict, Any, Optional, TypeVar, Type, Protocol
from pathlib import Path
from copy import deepcopy
from abc import ABC, abstractmethod


logger = logging.getLogger(__name__)
T = TypeVar('T')


class SecretProvider(Protocol):
    """
    Protocol for secret providers.
    Addresses Review: No Integration with Vault/HSM
    """
    
    def get_secret(self, path: str) -> str:
        """Get secret value"""
        ...
    
    def set_secret(self, path: str, value: str):
        """Set secret value"""
        ...


class EnvSecretProvider:
    """Environment variable secret provider"""
    
    def get_secret(self, path: str) -> str:
        value = os.environ.get(path)
        if not value:
            raise KeyError(f"Secret not found: {path}")
        return value
    
    def set_secret(self, path: str, value: str):
        os.environ[path] = value


class FileSecretProvider:
    """
    File-based secret provider (for development).
    Production should use Vault.
    """
    
    def __init__(self, secrets_dir: Path):
        self.secrets_dir = Path(secrets_dir)
        self.secrets_dir.mkdir(parents=True, exist_ok=True)
    
    def get_secret(self, path: str) -> str:
        secret_file = self.secrets_dir / path.replace("/", "_")
        if not secret_file.exists():
            raise KeyError(f"Secret not found: {path}")
        return secret_file.read_text().strip()
    
    def set_secret(self, path: str, value: str):
        secret_file = self.secrets_dir / path.replace("/", "_")
        secret_file.write_text(value)
        secret_file.chmod(0o600)  # Owner read/write only


class VaultSecretProvider:
    """
    HashiCorp Vault secret provider.
    Addresses Review: No Vault Integration
    
    Note: Requires hvac library
    """
    
    def __init__(self, vault_addr: str, token: str):
        try:
            import hvac
            self.client = hvac.Client(url=vault_addr, token=token)
            if not self.client.is_authenticated():
                raise RuntimeError("Vault authentication failed")
        except ImportError:
            raise RuntimeError(
                "hvac library required for Vault integration. "
                "Install: pip install hvac"
            )
    
    def get_secret(self, path: str) -> str:
        try:
            response = self.client.secrets.kv.v2.read_secret(path)
            return response['data']['data']['value']
        except Exception as e:
            raise KeyError(f"Failed to get secret {path}: {e}")
    
    def set_secret(self, path: str, value: str):
        try:
            self.client.secrets.kv.v2.create_or_update_secret(
                path=path,
                secret={'value': value}
            )
        except Exception as e:
            raise RuntimeError(f"Failed to set secret {path}: {e}")


class ConfigurationManager:
    """
    Enhanced hierarchical configuration management.
    
    Improvements from Review:
    - Secret management integration
    - Configuration validation
    - Audit logging
    - Hot-reload support with callbacks
    """
    
    def __init__(self, secret_provider: Optional[SecretProvider] = None):
        self._system_config: Dict[str, Any] = {}
        self._user_config: Dict[str, Any] = {}
        self._module_defaults: Dict[str, Dict[str, Any]] = {}
        self._runtime_overrides: Dict[str, Any] = {}
        self._env_prefix = "NEXUS_"
        
        # Secret management
        self._secret_provider = secret_provider or EnvSecretProvider()
        
        # Hot-reload callbacks
        self._reload_callbacks: Dict[str, list] = {}
        
        # Audit trail
        self._audit_log: list = []
    
    def load_system_config(self, path: str = "/etc/nexus/config.yaml"):
        """Load system-wide configuration"""
        config_path = Path(path)
        if config_path.exists():
            try:
                with open(config_path) as f:
                    self._system_config = yaml.safe_load(f) or {}
                logger.info(f"Loaded system config from {path}")
                self._audit("load_system_config", {"path": path})
            except Exception as e:
                logger.error(f"Failed to load system config: {e}")
                raise
    
    def load_user_config(self, path: Optional[str] = None):
        """Load user-specific configuration"""
        if path is None:
            path = Path.home() / ".nexus" / "config.yaml"
        else:
            path = Path(path)
        
        if path.exists():
            try:
                with open(path) as f:
                    self._user_config = yaml.safe_load(f) or {}
                logger.info(f"Loaded user config from {path}")
                self._audit("load_user_config", {"path": str(path)})
            except Exception as e:
                logger.error(f"Failed to load user config: {e}")
                raise
    
    def register_module_defaults(self, module_id: str, defaults: Dict[str, Any]):
        """Register default configuration for a module"""
        group = module_id.split("/")[0]
        module_name = module_id.split("/")[1]
        
        if group not in self._module_defaults:
            self._module_defaults[group] = {}
        
        self._module_defaults[group][module_name] = deepcopy(defaults)
        logger.debug(f"Registered defaults for {module_id}")
    
    def set_runtime_override(self, module_id: str, key: str, value: Any):
        """
        Set runtime configuration override.
        Triggers reload callbacks.
        """
        if module_id not in self._runtime_overrides:
            self._runtime_overrides[module_id] = {}
        
        old_value = self._runtime_overrides[module_id].get(key)
        self._runtime_overrides[module_id][key] = value
        
        logger.info(
            f"Runtime override: {module_id}.{key} = {value}",
            extra={"module_id": module_id, "key": key}
        )
        
        self._audit("set_runtime_override", {
            "module_id": module_id,
            "key": key,
            "old_value": old_value,
            "new_value": value
        })
        
        # Trigger callbacks
        self._trigger_reload_callbacks(module_id, key, value)
    
    def get(
        self,
        module_id: str,
        key: str,
        default: Optional[T] = None,
        expected_type: Optional[Type[T]] = None,
        secret: bool = False
    ) -> T:
        """
        Get configuration value with precedence resolution.
        
        Args:
            module_id: Module ID (e.g., "vitals/heartbeat-client")
            key: Configuration key
            default: Default value if not found
            expected_type: Expected type for validation
            secret: If True, fetch from secret provider
        
        Returns:
            Configuration value
        
        Raises:
            KeyError: If required config is missing and no default
            TypeError: If value doesn't match expected_type
        """
        if secret:
            return self._get_secret(module_id, key, default, expected_type)
        
        group, module_name = module_id.split("/")
        
        # Check precedence layers
        value = None
        found = False
        source = None
        
        # 1. Runtime overrides
        if module_id in self._runtime_overrides:
            if key in self._runtime_overrides[module_id]:
                value = self._runtime_overrides[module_id][key]
                found = True
                source = "runtime"
        
        # 2. Environment variables
        if not found:
            env_key = f"{self._env_prefix}{group.upper()}_{module_name.upper().replace('-', '_')}_{key.upper()}"
            env_value = os.environ.get(env_key)
            if env_value is not None:
                value = self._parse_env_value(env_value, expected_type)
                found = True
                source = "environment"
        
        # 3. User config
        if not found:
            user_value = self._get_nested(
                self._user_config,
                [group, module_name, key]
            )
            if user_value is not None:
                value = user_value
                found = True
                source = "user"
        
        # 4. Module defaults
        if not found:
            if group in self._module_defaults:
                if module_name in self._module_defaults[group]:
                    if key in self._module_defaults[group][module_name]:
                        value = self._module_defaults[group][module_name][key]
                        found = True
                        source = "module"
        
        # 5. System config
        if not found:
            system_value = self._get_nested(
                self._system_config,
                [group, module_name, key]
            )
            if system_value is not None:
                value = system_value
                found = True
                source = "system"
        
        # Use default if nothing found
        if not found:
            if default is not None:
                value = default
                source = "default"
            else:
                raise KeyError(
                    f"Configuration key '{key}' not found for module '{module_id}' "
                    f"and no default provided"
                )
        
        # Type validation and conversion
        if expected_type is not None:
            if not isinstance(value, expected_type):
                try:
                    value = expected_type(value)
                except (ValueError, TypeError) as e:
                    raise TypeError(
                        f"Configuration value for '{module_id}.{key}' is {type(value).__name__}, "
                        f"expected {expected_type.__name__}"
                    ) from e
        
        logger.debug(f"Config {module_id}.{key} = {value} (source: {source})")
        return value
    
    def _get_secret(
        self,
        module_id: str,
        key: str,
        default: Optional[T],
        expected_type: Optional[Type[T]]
    ) -> T:
        """
        Get secret from secret provider.
        Addresses Review: Plaintext secrets in YAML
        """
        secret_path = f"nexus/{module_id}/{key}"
        
        try:
            value = self._secret_provider.get_secret(secret_path)
            
            # Type conversion
            if expected_type is not None:
                value = expected_type(value)
            
            logger.info(
                f"Retrieved secret: {module_id}.{key}",
                extra={"module_id": module_id, "key": key}
            )
            
            return value
            
        except KeyError:
            if default is not None:
                return default
            raise KeyError(f"Secret not found: {secret_path}")
    
    def set_secret(self, module_id: str, key: str, value: str):
        """
        Set secret in secret provider.
        """
        secret_path = f"nexus/{module_id}/{key}"
        self._secret_provider.set_secret(secret_path, value)
        
        logger.info(
            f"Secret set: {module_id}.{key}",
            extra={"module_id": module_id, "key": key}
        )
        
        self._audit("set_secret", {
            "module_id": module_id,
            "key": key,
            "path": secret_path
        })
    
    def register_reload_callback(
        self,
        module_id: str,
        callback: callable
    ):
        """
        Register callback for configuration changes.
        Addresses Review: No hot-reload notification
        """
        if module_id not in self._reload_callbacks:
            self._reload_callbacks[module_id] = []
        
        self._reload_callbacks[module_id].append(callback)
        logger.debug(f"Registered reload callback for {module_id}")
    
    def _trigger_reload_callbacks(self, module_id: str, key: str, value: Any):
        """Trigger reload callbacks for module"""
        if module_id in self._reload_callbacks:
            for callback in self._reload_callbacks[module_id]:
                try:
                    callback(key, value)
                except Exception as e:
                    logger.error(f"Reload callback error: {e}", exc_info=True)
    
    def get_section(self, module_id: str) -> Dict[str, Any]:
        """Get all configuration for a module"""
        group, module_name = module_id.split("/")
        
        # Start with system config
        config = deepcopy(
            self._get_nested(self._system_config, [group, module_name]) or {}
        )
        
        # Merge module defaults
        if group in self._module_defaults:
            if module_name in self._module_defaults[group]:
                defaults = self._module_defaults[group][module_name]
                config = {**defaults, **config}
        
        # Merge user config
        user_section = self._get_nested(self._user_config, [group, module_name])
        if user_section:
            config = {**config, **user_section}
        
        # Merge environment variables
        env_section = self._get_env_section(group, module_name)
        if env_section:
            config = {**config, **env_section}
        
        # Merge runtime overrides
        if module_id in self._runtime_overrides:
            config = {**config, **self._runtime_overrides[module_id]}
        
        return config
    
    def _get_nested(self, d: Dict, keys: list) -> Optional[Any]:
        """Safely get nested dictionary value"""
        current = d
        for key in keys:
            if not isinstance(current, dict):
                return None
            current = current.get(key)
            if current is None:
                return None
        return current
    
    def _parse_env_value(self, value: str, expected_type: Optional[Type]) -> Any:
        """Parse environment variable value"""
        if expected_type == bool:
            return value.lower() in ("true", "1", "yes", "on")
        elif expected_type == int:
            return int(value)
        elif expected_type == float:
            return float(value)
        elif expected_type == list:
            return [item.strip() for item in value.split(",")]
        else:
            return value
    
    def _get_env_section(self, group: str, module_name: str) -> Dict[str, Any]:
        """Get all environment variables for a module"""
        prefix = f"{self._env_prefix}{group.upper()}_{module_name.upper().replace('-', '_')}_"
        
        section = {}
        for key, value in os.environ.items():
            if key.startswith(prefix):
                config_key = key[len(prefix):].lower()
                section[config_key] = value
        
        return section
    
    def _audit(self, action: str, details: Dict[str, Any]):
        """
        Audit log for configuration changes.
        Addresses Review: No Audit Logging
        """
        entry = {
            "timestamp": logger.makeRecord(
                "", 0, "", 0, "", (), None
            ).created,
            "action": action,
            "details": details
        }
        self._audit_log.append(entry)
        
        # Keep only last 1000 entries
        if len(self._audit_log) > 1000:
            self._audit_log = self._audit_log[-1000:]
    
    def get_audit_log(self) -> list:
        """Get configuration audit log"""
        return self._audit_log.copy()
    
    def dump_config(self, module_id: str) -> str:
        """Dump effective configuration for debugging"""
        config = self.get_section(module_id)
        
        lines = [f"Configuration for {module_id}:"]
        for key, value in sorted(config.items()):
            source = self._get_source(module_id, key)
            # Mask sensitive values
            display_value = "***REDACTED***" if "password" in key.lower() or "secret" in key.lower() else value
            lines.append(f"  {key} = {display_value!r}  (source: {source})")
        
        return "\n".join(lines)
    
    def _get_source(self, module_id: str, key: str) -> str:
        """Determine which layer provided a config value"""
        group, module_name = module_id.split("/")
        
        if module_id in self._runtime_overrides and key in self._runtime_overrides[module_id]:
            return "runtime"
        
        env_key = f"{self._env_prefix}{group.upper()}_{module_name.upper().replace('-', '_')}_{key.upper()}"
        if env_key in os.environ:
            return "environment"
        
        if self._get_nested(self._user_config, [group, module_name, key]) is not None:
            return "user"
        
        if group in self._module_defaults:
            if module_name in self._module_defaults[group]:
                if key in self._module_defaults[group][module_name]:
                    return "module"
        
        if self._get_nested(self._system_config, [group, module_name, key]) is not None:
            return "system"
        
        return "unknown"
