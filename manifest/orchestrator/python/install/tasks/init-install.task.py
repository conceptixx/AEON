#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# v2.1.1
"""
Init Install Task
~~~~~~~~~~~~~~~~~

Installation initialization - TWO-STEP logic:
1. Determine WHAT to install (enable flags)
2. Determine WHAT to execute (execution mode)

Flag Logic (CORRECTED):

Step 1 - Install (Enable):
  IF --enable-cli:     cli-tui-enable = true
  IF --enable-web:     web-gui-enable = true
  IF !--enable-cli && !--enable-web: cli-tui-enable = true (DEFAULT)

Step 2 - Execute:
  IF --noninteractive: install-defaults = true
  ELSE IF --enable-cli: cli-tui-execute = true
  ELSE IF --enable-web: web-gui-execute = true
  ELSE: cli-tui-execute = true (DEFAULT)

:copyright: (c) 2025 AEON System
:license: MIT
:version: 2.1.1
"""

TASK_NAME = "init-install"
TASK_DESCRIPTION = "Process installation flags (two-step logic)"
DEPENDS_ON = []

# ============================================
# LIFECYCLE HOOKS
# ============================================

async def process_flags(context, dependencies, event_data):
    """
    on_load: Process user flags with TWO-STEP logic
    
    Step 1: What to INSTALL?
    Step 2: What to EXECUTE?
    """
    
    user_flags = event_data.get("user_flags", {})
    
    print("\n🔧 Processing Installation Flags...")
    
    # Check input flags
    cli_flag = (
        user_flags.get("-c") or 
        user_flags.get("-C") or 
        user_flags.get("--enable-cli") or 
        user_flags.get("--cli-enable")
    )
    
    web_flag = (
        user_flags.get("-w") or 
        user_flags.get("-W") or 
        user_flags.get("--enable-web") or 
        user_flags.get("--web-enable")
    )
    
    noninteractive_flag = (
        user_flags.get("-n") or 
        user_flags.get("-N") or 
        user_flags.get("--noninteractive") or 
        user_flags.get("--non-interactive")
    )
    
    # Initialize environment flags
    env_flags = {
        "cli-tui-enable": False,
        "web-gui-enable": False,
        "install-defaults": False,
        "cli-tui-execute": False,
        "web-gui-execute": False
    }
    
    # ============================================
    # STEP 1: What to INSTALL? (Enable Flags)
    # ============================================
    
    print("\n📦 Step 1: What to INSTALL?")
    
    if cli_flag:
        env_flags["cli-tui-enable"] = True
        print("   ├─ --enable-cli detected")
        print("   └─ CLI TUI will be installed")
    
    if web_flag:
        env_flags["web-gui-enable"] = True
        print("   ├─ --enable-web detected")
        print("   └─ Web GUI + nginx will be installed")
    
    # DEFAULT: If nothing enabled, enable CLI TUI
    if not cli_flag and not web_flag:
        env_flags["cli-tui-enable"] = True
        print("   ├─ No --enable flags")
        print("   └─ CLI TUI will be installed (DEFAULT)")
    
    # ============================================
    # STEP 2: What to EXECUTE? (Execution Mode)
    # ============================================
    
    print("\n⚡ Step 2: What to EXECUTE?")
    
    if noninteractive_flag:
        env_flags["install-defaults"] = True
        print("   ├─ --noninteractive detected")
        print("   └─ Install with DEFAULTS (no TUI/GUI execution)")
    
    elif cli_flag:
        env_flags["cli-tui-execute"] = True
        print("   ├─ --enable-cli detected")
        print("   └─ CLI TUI will be EXECUTED")
    
    elif web_flag:
        env_flags["web-gui-execute"] = True
        print("   ├─ --enable-web detected")
        print("   └─ Web GUI will be EXECUTED")
    
    else:
        # DEFAULT: Execute CLI TUI
        env_flags["cli-tui-execute"] = True
        print("   ├─ No execution flags")
        print("   └─ CLI TUI will be EXECUTED (DEFAULT)")
    
    # Store in context
    context["environment_flags"] = env_flags
    
    # ============================================
    # SUMMARY
    # ============================================
    
    print("\n" + "=" * 60)
    print("📋 Installation Plan")
    print("=" * 60)
    
    # What will be installed
    print("\n🔧 Components to INSTALL:")
    if env_flags["cli-tui-enable"]:
        print("   ✅ CLI TUI (from repo)")
    if env_flags["web-gui-enable"]:
        print("   ✅ Web GUI + nginx (from repo)")
    
    # Execution mode
    print("\n⚡ Execution Mode:")
    if env_flags["install-defaults"]:
        print("   🚀 Non-Interactive (defaults)")
        print("      └─ Install → EXIT")
    elif env_flags["cli-tui-execute"]:
        print("   🖥️  Interactive CLI TUI")
        print("      └─ Curses Menu → Config → Install → EXIT")
    elif env_flags["web-gui-execute"]:
        print("   🌐 Interactive Web GUI")
        print("      └─ http://localhost:5000 → Config → Install → EXIT")
    
    print("=" * 60)
    print()
    
    return {
        "initialized": True,
        "flags": env_flags
    }


# ============================================
# MAIN METHODS
# ============================================

async def resolve(context, dependencies, event_data):
    """
    Main execution - returns environment setup
    """
    
    env_flags = context.get("environment_flags", {})
    
    # Determine next step
    next_step = None
    
    if env_flags.get("install-defaults"):
        next_step = "install_with_defaults"
    elif env_flags.get("cli-tui-execute"):
        next_step = "launch_cli_tui"
    elif env_flags.get("web-gui-execute"):
        next_step = "launch_web_gui"
    
    result = {
        "environment_flags": env_flags,
        "next_step": next_step,
        "components_to_install": []
    }
    
    # List components
    if env_flags.get("cli-tui-enable"):
        result["components_to_install"].append("cli-tui")
    
    if env_flags.get("web-gui-enable"):
        result["components_to_install"].append("web-gui")
        result["components_to_install"].append("nginx")
    
    return result


async def reject(context, error, event_data):
    """Error handler"""
    print(f"   └─ ❌ Init-Install failed: {error}")
    raise error
