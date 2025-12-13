#!/usr/bin/env python3
################################################################################
# AEON Scoring & Role Assignment Module
# File: lib/scoring.py
# Version: 0.1.0
#
# Purpose: Score Raspberry Pi devices and assign manager/worker roles
#          based on hardware capabilities, ensuring cluster requirements.
#
# Requirements:
#   - Minimum 3 Raspberry Pis (HARD requirement)
#   - Manager count must be ODD (Raft consensus)
#   - Managers: 3-7 (Docker Swarm best practice)
#   - Only Raspberry Pis can be managers (24/7 availability)
#   - LLM/Host computers always workers
#
# Scoring factors:
#   - Model (Pi 5 > Pi 4 > Pi 3)
#   - RAM (8GB > 4GB > 2GB)
#   - Storage (NVMe > SSD > SD)
#   - Network speed
#   - Power reliability (PoE, UPS)
#   - Cooling
################################################################################

import json
import sys
import math
from typing import List, Dict, Any, Tuple
from dataclasses import dataclass, asdict
from enum import Enum

################################################################################
# DATA STRUCTURES
################################################################################

class DeviceType(Enum):
    """Device type classification"""
    RASPBERRY_PI = "raspberry_pi"
    LLM_COMPUTER = "llm_computer"
    HOST_COMPUTER = "host_computer"
    UNKNOWN = "unknown"

class PiModel(Enum):
    """Raspberry Pi models with scores"""
    PI5 = ("pi5", 50)
    PI4 = ("pi4", 25)
    PI3 = ("pi3", 10)
    CM4 = ("cm4", 20)
    UNKNOWN = ("unknown", 0)
    
    def __init__(self, model_id: str, score: int):
        self.model_id = model_id
        self.score = score

class StorageType(Enum):
    """Storage types with scores"""
    NVME = ("nvme", 30)
    SSD = ("ssd", 25)
    EMMC = ("emmc", 15)
    SD = ("sd", 10)
    UNKNOWN = ("unknown", 5)
    
    def __init__(self, type_id: str, score: int):
        self.type_id = type_id
        self.score = score

@dataclass
class Device:
    """Device information"""
    ip: str
    hostname: str
    device_type: str
    model: str = "unknown"
    ram_gb: int = 0
    storage_type: str = "unknown"
    storage_size_gb: int = 0
    network_speed_mbps: int = 100
    has_poe: bool = False
    has_ups: bool = False
    has_active_cooling: bool = False
    has_heatsink: bool = False
    cpu_cores: int = 4
    score: int = 0

@dataclass
class RoleAssignment:
    """Role assignment result"""
    device: Device
    role: str  # "manager" or "worker"
    rank: int  # Lower rank = higher priority manager
    reason: str

@dataclass
class AssignmentResult:
    """Complete assignment result"""
    assignments: List[RoleAssignment]
    total_devices: int
    total_pis: int
    manager_count: int
    worker_count: int
    pi_managers: int
    pi_workers: int
    llm_workers: int
    host_workers: int
    fault_tolerance: int  # Number of manager failures tolerated
    meets_requirements: bool
    warnings: List[str]
    errors: List[str]

################################################################################
# SCORING ENGINE
################################################################################

class DeviceScorer:
    """Calculate device scores based on hardware capabilities"""
    
    # Scoring weights
    MODEL_WEIGHT = 50
    RAM_WEIGHT = 40
    STORAGE_TYPE_WEIGHT = 30
    STORAGE_SIZE_WEIGHT = 20
    NETWORK_WEIGHT = 10
    POWER_WEIGHT = 10
    COOLING_WEIGHT = 5
    
    MAX_THEORETICAL_SCORE = 170  # Maximum possible score
    MIN_VIABLE_SCORE = 60        # Minimum for manager consideration
    
    @classmethod
    def score_device(cls, device: Device) -> int:
        """Calculate total score for a device"""
        
        # Only score Raspberry Pis (others get 0)
        if device.device_type != DeviceType.RASPBERRY_PI.value:
            return 0
        
        score = 0
        
        # Model score (50 points max)
        score += cls._score_model(device.model)
        
        # RAM score (40 points max)
        score += cls._score_ram(device.ram_gb)
        
        # Storage type score (30 points max)
        score += cls._score_storage_type(device.storage_type)
        
        # Storage size bonus (20 points max)
        score += cls._score_storage_size(device.storage_size_gb)
        
        # Network speed bonus (10 points max)
        score += cls._score_network(device.network_speed_mbps)
        
        # Power reliability bonus (10 points max)
        score += cls._score_power(device.has_poe, device.has_ups)
        
        # Cooling bonus (5 points max)
        score += cls._score_cooling(device.has_active_cooling, device.has_heatsink)
        
        return score
    
    @staticmethod
    def _score_model(model: str) -> int:
        """Score based on Pi model"""
        model_lower = model.lower()
        
        if "pi 5" in model_lower or "pi5" in model_lower:
            return PiModel.PI5.score
        elif "pi 4" in model_lower or "pi4" in model_lower:
            return PiModel.PI4.score
        elif "pi 3" in model_lower or "pi3" in model_lower:
            return PiModel.PI3.score
        elif "cm4" in model_lower or "compute module 4" in model_lower:
            return PiModel.CM4.score
        else:
            return PiModel.UNKNOWN.score
    
    @staticmethod
    def _score_ram(ram_gb: int) -> int:
        """Score based on RAM size"""
        if ram_gb >= 8:
            return 40
        elif ram_gb >= 4:
            return 20
        elif ram_gb >= 2:
            return 10
        elif ram_gb >= 1:
            return 5
        else:
            return 0
    
    @staticmethod
    def _score_storage_type(storage_type: str) -> int:
        """Score based on storage type"""
        storage_lower = storage_type.lower()
        
        if "nvme" in storage_lower:
            return StorageType.NVME.score
        elif "ssd" in storage_lower:
            return StorageType.SSD.score
        elif "emmc" in storage_lower or "mmc" in storage_lower:
            return StorageType.EMMC.score
        elif "sd" in storage_lower or "card" in storage_lower:
            return StorageType.SD.score
        else:
            return StorageType.UNKNOWN.score
    
    @staticmethod
    def _score_storage_size(size_gb: int) -> int:
        """Bonus points for storage size"""
        if size_gb >= 512:
            return 20
        elif size_gb >= 256:
            return 15
        elif size_gb >= 128:
            return 10
        elif size_gb >= 64:
            return 5
        else:
            return 0
    
    @staticmethod
    def _score_network(speed_mbps: int) -> int:
        """Bonus points for network speed"""
        if speed_mbps >= 2500:  # 2.5 Gbps+
            return 10
        elif speed_mbps >= 1000:  # 1 Gbps
            return 8
        elif speed_mbps >= 100:   # 100 Mbps
            return 4
        else:
            return 0
    
    @staticmethod
    def _score_power(has_poe: bool, has_ups: bool) -> int:
        """Bonus points for power reliability"""
        score = 0
        
        if has_poe:
            score += 10  # PoE is most reliable
        elif has_ups:
            score += 8   # UPS is good backup
        else:
            score += 5   # Standard power (assume no undervoltage)
        
        return score
    
    @staticmethod
    def _score_cooling(has_active_cooling: bool, has_heatsink: bool) -> int:
        """Bonus points for cooling"""
        if has_active_cooling:
            return 5
        elif has_heatsink:
            return 3
        else:
            return 0

################################################################################
# ROLE ASSIGNMENT ENGINE
################################################################################

class RoleAssigner:
    """Assign manager/worker roles based on scores and requirements"""
    
    MIN_MANAGERS = 3
    MAX_MANAGERS = 7
    TARGET_MANAGER_PERCENTAGE = 0.6  # Aim for ~60% of Pis as managers
    
    @classmethod
    def assign_roles(cls, devices: List[Device]) -> AssignmentResult:
        """Assign roles to all devices"""
        
        errors = []
        warnings = []
        
        # Separate devices by type
        pis = [d for d in devices if d.device_type == DeviceType.RASPBERRY_PI.value]
        llm_computers = [d for d in devices if d.device_type == DeviceType.LLM_COMPUTER.value]
        host_computers = [d for d in devices if d.device_type == DeviceType.HOST_COMPUTER.value]
        
        # Validate minimum requirements
        if len(pis) < cls.MIN_MANAGERS:
            errors.append(f"Insufficient Raspberry Pis: {len(pis)} found, minimum {cls.MIN_MANAGERS} required")
            return cls._create_error_result(devices, errors)
        
        # Score all Pis
        for pi in pis:
            pi.score = DeviceScorer.score_device(pi)
        
        # Sort Pis by score (highest first)
        pis.sort(key=lambda x: x.score, reverse=True)
        
        # Calculate manager count
        manager_count = cls._calculate_manager_count(len(pis))
        
        # Validate manager count
        if manager_count < cls.MIN_MANAGERS:
            errors.append(f"Cannot assign {manager_count} managers (minimum {cls.MIN_MANAGERS})")
            return cls._create_error_result(devices, errors)
        
        if manager_count > cls.MAX_MANAGERS:
            warnings.append(f"Manager count capped at {cls.MAX_MANAGERS} (calculated {manager_count})")
            manager_count = cls.MAX_MANAGERS
        
        # Ensure ODD number of managers
        if manager_count % 2 == 0:
            manager_count += 1
            warnings.append(f"Manager count adjusted to {manager_count} (must be ODD for Raft consensus)")
        
        # Final validation
        if manager_count > len(pis):
            errors.append(f"Not enough Pis for {manager_count} managers (only {len(pis)} available)")
            return cls._create_error_result(devices, errors)
        
        # Assign roles
        assignments = []
        
        # Top-scored Pis become managers
        for i, pi in enumerate(pis[:manager_count]):
            assignment = RoleAssignment(
                device=pi,
                role="manager",
                rank=i + 1,
                reason=f"High score ({pi.score}/{DeviceScorer.MAX_THEORETICAL_SCORE}), rank #{i+1}"
            )
            assignments.append(assignment)
        
        # Remaining Pis become workers
        for i, pi in enumerate(pis[manager_count:]):
            assignment = RoleAssignment(
                device=pi,
                role="worker",
                rank=manager_count + i + 1,
                reason=f"Lower score ({pi.score}/{DeviceScorer.MAX_THEORETICAL_SCORE}), rank #{manager_count + i + 1}"
            )
            assignments.append(assignment)
        
        # LLM computers are always workers
        for llm in llm_computers:
            assignment = RoleAssignment(
                device=llm,
                role="worker",
                rank=0,  # Not ranked (not eligible for manager)
                reason="LLM computer - always worker (GPU workload)"
            )
            assignments.append(assignment)
        
        # Host computers are always workers
        for host in host_computers:
            assignment = RoleAssignment(
                device=host,
                role="worker",
                rank=0,  # Not ranked (not eligible for manager)
                reason="Host computer - always worker (not 24/7 available)"
            )
            assignments.append(assignment)
        
        # Calculate fault tolerance
        fault_tolerance = (manager_count - 1) // 2
        
        # Create result
        result = AssignmentResult(
            assignments=assignments,
            total_devices=len(devices),
            total_pis=len(pis),
            manager_count=manager_count,
            worker_count=len(devices) - manager_count,
            pi_managers=manager_count,
            pi_workers=len(pis) - manager_count,
            llm_workers=len(llm_computers),
            host_workers=len(host_computers),
            fault_tolerance=fault_tolerance,
            meets_requirements=True,
            warnings=warnings,
            errors=errors
        )
        
        return result
    
    @classmethod
    def _calculate_manager_count(cls, pi_count: int) -> int:
        """Calculate optimal manager count based on Pi count"""
        
        if pi_count < cls.MIN_MANAGERS:
            return 0  # Error case
        elif pi_count == 3:
            return 3  # All 3 must be managers (100%)
        elif pi_count == 4:
            return 3  # 3 managers (75%)
        elif pi_count == 5:
            return 3  # 3 managers (60%)
        else:
            # Target ~60% as managers
            target = math.ceil(pi_count * cls.TARGET_MANAGER_PERCENTAGE)
            
            # Ensure ODD
            if target % 2 == 0:
                target += 1
            
            # Cap at MAX_MANAGERS
            return min(target, cls.MAX_MANAGERS)
    
    @staticmethod
    def _create_error_result(devices: List[Device], errors: List[str]) -> AssignmentResult:
        """Create an error result when requirements not met"""
        
        # Create empty assignments
        assignments = [
            RoleAssignment(
                device=device,
                role="unassigned",
                rank=0,
                reason="Requirements not met"
            )
            for device in devices
        ]
        
        return AssignmentResult(
            assignments=assignments,
            total_devices=len(devices),
            total_pis=len([d for d in devices if d.device_type == DeviceType.RASPBERRY_PI.value]),
            manager_count=0,
            worker_count=0,
            pi_managers=0,
            pi_workers=0,
            llm_workers=0,
            host_workers=0,
            fault_tolerance=0,
            meets_requirements=False,
            warnings=[],
            errors=errors
        )

################################################################################
# JSON I/O
################################################################################

def load_devices_from_json(json_file: str) -> List[Device]:
    """Load devices from JSON file"""
    
    with open(json_file, 'r') as f:
        data = json.load(f)
    
    devices = []
    
    for device_data in data.get('devices', []):
        device = Device(
            ip=device_data.get('ip', ''),
            hostname=device_data.get('hostname', ''),
            device_type=device_data.get('device_type', 'unknown'),
            model=device_data.get('model', 'unknown'),
            ram_gb=device_data.get('ram_gb', 0),
            storage_type=device_data.get('storage_type', 'unknown'),
            storage_size_gb=device_data.get('storage_size_gb', 0),
            network_speed_mbps=device_data.get('network_speed_mbps', 100),
            has_poe=device_data.get('has_poe', False),
            has_ups=device_data.get('has_ups', False),
            has_active_cooling=device_data.get('has_active_cooling', False),
            has_heatsink=device_data.get('has_heatsink', False),
            cpu_cores=device_data.get('cpu_cores', 4)
        )
        devices.append(device)
    
    return devices

def save_assignments_to_json(result: AssignmentResult, output_file: str):
    """Save assignment results to JSON file"""
    
    # Convert to dictionary
    output = {
        "summary": {
            "total_devices": result.total_devices,
            "total_pis": result.total_pis,
            "manager_count": result.manager_count,
            "worker_count": result.worker_count,
            "pi_managers": result.pi_managers,
            "pi_workers": result.pi_workers,
            "llm_workers": result.llm_workers,
            "host_workers": result.host_workers,
            "fault_tolerance": result.fault_tolerance,
            "meets_requirements": result.meets_requirements
        },
        "warnings": result.warnings,
        "errors": result.errors,
        "assignments": []
    }
    
    # Add assignments
    for assignment in result.assignments:
        output["assignments"].append({
            "device": {
                "ip": assignment.device.ip,
                "hostname": assignment.device.hostname,
                "device_type": assignment.device.device_type,
                "model": assignment.device.model,
                "ram_gb": assignment.device.ram_gb,
                "storage_type": assignment.device.storage_type,
                "storage_size_gb": assignment.device.storage_size_gb,
                "network_speed_mbps": assignment.device.network_speed_mbps,
                "score": assignment.device.score
            },
            "role": assignment.role,
            "rank": assignment.rank,
            "reason": assignment.reason
        })
    
    # Write to file
    with open(output_file, 'w') as f:
        json.dump(output, f, indent=2)

################################################################################
# PRETTY PRINTING
################################################################################

def print_assignment_report(result: AssignmentResult):
    """Print beautiful assignment report to console"""
    
    # Colors
    BOLD = '\033[1m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    RED = '\033[0;31m'
    CYAN = '\033[0;36m'
    NC = '\033[0m'
    
    print()
    print(f"{BOLD}{'═' * 70}{NC}")
    print(f"{BOLD}{CYAN}  AEON ROLE ASSIGNMENT REPORT{NC}")
    print(f"{BOLD}{'═' * 70}{NC}")
    print()
    
    # Summary
    print(f"{BOLD}CLUSTER OVERVIEW{NC}")
    print(f"  Total devices: {result.total_devices}")
    print(f"  Raspberry Pis: {result.total_pis}")
    print(f"  LLM computers: {result.llm_workers}")
    print(f"  Host computers: {result.host_workers}")
    print()
    
    print(f"{BOLD}ROLE DISTRIBUTION{NC}")
    print(f"  Manager nodes: {GREEN}{result.manager_count}{NC} (all Raspberry Pis)")
    print(f"  Worker nodes: {result.worker_count}")
    print(f"    • Pi workers: {result.pi_workers}")
    print(f"    • LLM workers: {result.llm_workers}")
    print(f"    • Host workers: {result.host_workers}")
    print()
    
    print(f"{BOLD}FAULT TOLERANCE{NC}")
    print(f"  Manager failures tolerated: {GREEN}{result.fault_tolerance}{NC}")
    print(f"  Consensus: Raft (requires {result.manager_count // 2 + 1}/{result.manager_count} managers)")
    print()
    
    # Errors
    if result.errors:
        print(f"{BOLD}{RED}ERRORS{NC}")
        for error in result.errors:
            print(f"  {RED}✗{NC} {error}")
        print()
    
    # Warnings
    if result.warnings:
        print(f"{BOLD}{YELLOW}WARNINGS{NC}")
        for warning in result.warnings:
            print(f"  {YELLOW}⚠{NC} {warning}")
        print()
    
    # Assignments
    print(f"{BOLD}DEVICE ASSIGNMENTS{NC}")
    print()
    
    # Managers first
    managers = [a for a in result.assignments if a.role == "manager"]
    if managers:
        print(f"  {BOLD}{GREEN}MANAGERS{NC} (Top-scored Raspberry Pis)")
        print(f"  {'─' * 66}")
        
        for assignment in sorted(managers, key=lambda x: x.rank):
            device = assignment.device
            print(f"  #{assignment.rank} {device.hostname} ({device.ip})")
            print(f"      Model: {device.model} | RAM: {device.ram_gb}GB | Storage: {device.storage_type} ({device.storage_size_gb}GB)")
            print(f"      Score: {GREEN}{device.score}/{DeviceScorer.MAX_THEORETICAL_SCORE}{NC} | {assignment.reason}")
            print()
    
    # Workers
    workers = [a for a in result.assignments if a.role == "worker"]
    if workers:
        print(f"  {BOLD}WORKERS{NC}")
        print(f"  {'─' * 66}")
        
        # Pi workers
        pi_workers = [a for a in workers if a.device.device_type == DeviceType.RASPBERRY_PI.value]
        if pi_workers:
            print(f"  {CYAN}Raspberry Pi Workers{NC}")
            for assignment in sorted(pi_workers, key=lambda x: x.rank):
                device = assignment.device
                print(f"    • {device.hostname} ({device.ip})")
                print(f"      Score: {device.score}/{DeviceScorer.MAX_THEORETICAL_SCORE} | {assignment.reason}")
            print()
        
        # LLM workers
        llm_workers = [a for a in workers if a.device.device_type == DeviceType.LLM_COMPUTER.value]
        if llm_workers:
            print(f"  {CYAN}LLM Computer Workers{NC}")
            for assignment in llm_workers:
                device = assignment.device
                print(f"    • {device.hostname} ({device.ip})")
                print(f"      {assignment.reason}")
            print()
        
        # Host workers
        host_workers = [a for a in workers if a.device.device_type == DeviceType.HOST_COMPUTER.value]
        if host_workers:
            print(f"  {CYAN}Host Computer Workers{NC}")
            for assignment in host_workers:
                device = assignment.device
                print(f"    • {device.hostname} ({device.ip})")
                print(f"      {assignment.reason}")
            print()
    
    # Final status
    print(f"{'─' * 70}")
    if result.meets_requirements:
        print(f"{GREEN}{BOLD}✓ REQUIREMENTS MET - Cluster configuration valid{NC}")
    else:
        print(f"{RED}{BOLD}✗ REQUIREMENTS NOT MET - Cannot proceed{NC}")
    print(f"{'─' * 70}")
    print()

################################################################################
# MAIN
################################################################################

def main():
    """Main entry point"""
    
    if len(sys.argv) < 2:
        print("Usage: python3 scoring.py <input_json> [output_json]")
        print()
        print("Example:")
        print("  python3 scoring.py /opt/aeon/data/hw_profiles.json /opt/aeon/data/role_assignments.json")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else None
    
    # Load devices
    try:
        devices = load_devices_from_json(input_file)
    except Exception as e:
        print(f"ERROR: Failed to load input file: {e}")
        sys.exit(1)
    
    # Assign roles
    result = RoleAssigner.assign_roles(devices)
    
    # Print report
    print_assignment_report(result)
    
    # Save to file
    if output_file:
        try:
            save_assignments_to_json(result, output_file)
            print(f"✅ Results saved to: {output_file}")
            print()
        except Exception as e:
            print(f"ERROR: Failed to save output file: {e}")
            sys.exit(1)
    
    # Exit code
    sys.exit(0 if result.meets_requirements else 1)

if __name__ == "__main__":
    main()
