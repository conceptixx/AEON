"""
NEXUS v2 - Enterprise-Grade Universal Daemon
Security-hardened, Observable, Resilient Module Orchestration

Improvements from v1:
- RBAC (Role-Based Access Control)
- Secret Management (Vault, File, Env)
- State Persistence
- Structured Logging
- Prometheus Metrics
- Audit Logging
- Separation of Concerns
- Consistent Error Handling

Author: Nicolas Höller
Version: 2.0.0
License: MIT
"""

from .core.module import (
    BaseModule,
    ModuleManifest,
    ModuleState,
    SecurityContext,
    MetricsCollector
)
from .core.config import (
    ConfigurationManager,
    SecretProvider,
    VaultSecretProvider,
    FileSecretProvider,
    EnvSecretProvider
)
from .core.loader import (
    ModuleLoader,
    StateStore,
    FileStateStore,
    ModuleRegistry
)
from .core.resolver import DependencyResolver
from .daemon import UniversalDaemon, run_daemon

__all__ = [
    # Core Module Components
    "BaseModule",
    "ModuleManifest",
    "ModuleState",
    "SecurityContext",
    "MetricsCollector",
    
    # Configuration & Secrets
    "ConfigurationManager",
    "SecretProvider",
    "VaultSecretProvider",
    "FileSecretProvider",
    "EnvSecretProvider",
    
    # Module Loading & State
    "ModuleLoader",
    "StateStore",
    "FileStateStore",
    "ModuleRegistry",
    "DependencyResolver",
    
    # Daemon
    "UniversalDaemon",
    "run_daemon",
]

__version__ = "2.0.0"
__author__ = "Nicolas Höller"
