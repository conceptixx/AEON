#!/bin/bash
################################################################################
# AEON Hardware Detection Script (Remote)
# File: remote/hardware.remote.sh
# Version: 0.1.0
#
# Purpose: Run on each device to collect hardware information
#          Outputs JSON to stdout
#
# This script is transferred to and executed on each discovered device
################################################################################

set -euo pipefail

# ============================================================================
# HARDWARE DETECTION FUNCTIONS
# ============================================================================

detect_model() {
    # Check if Raspberry Pi
    if grep -qi "raspberry" /proc/cpuinfo 2>/dev/null; then
        # Get Pi model from /proc/cpuinfo
        grep "Model" /proc/cpuinfo | cut -d: -f2 | xargs || echo "Raspberry Pi"
    else
        # Try to get CPU model
        if [[ -f /proc/cpuinfo ]]; then
            grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs || echo "Unknown"
        else
            echo "Unknown"
        fi
    fi
}

detect_device_type() {
    # Check if Raspberry Pi
    if grep -qi "raspberry" /proc/cpuinfo 2>/dev/null; then
        echo "raspberry_pi"
    else
        # Check hostname for LLM/Host conventions
        local hostname=$(hostname)
        if [[ "$hostname" =~ ^aeon-llm ]]; then
            echo "llm_computer"
        elif [[ "$hostname" =~ ^aeon-host ]]; then
            echo "host_computer"
        else
            echo "host_computer"  # Default
        fi
    fi
}

detect_ram() {
    # Get RAM in GB
    if [[ -f /proc/meminfo ]]; then
        local ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        local ram_gb=$((ram_kb / 1024 / 1024))
        
        # Round to nearest power of 2
        if [[ $ram_gb -ge 7 ]]; then
            echo 8
        elif [[ $ram_gb -ge 3 ]]; then
            echo 4
        elif [[ $ram_gb -ge 1 ]]; then
            echo 2
        else
            echo 1
        fi
    else
        echo 0
    fi
}

detect_storage_type() {
    # Detect storage type priority: NVMe > SSD > eMMC > SD
    
    if command -v lsblk &>/dev/null; then
        # Check for NVMe
        if lsblk -d -o NAME,TYPE | grep -q "nvme"; then
            echo "nvme"
            return
        fi
        
        # Check for SSD (sda/sdb usually)
        if lsblk -d -o NAME,TYPE | grep -q "sda\|sdb"; then
            # Try to detect if it's SSD or HDD
            if [[ -f /sys/block/sda/queue/rotational ]]; then
                local rotational=$(cat /sys/block/sda/queue/rotational)
                if [[ "$rotational" == "0" ]]; then
                    echo "ssd"
                    return
                fi
            else
                # Assume SSD if can't determine
                echo "ssd"
                return
            fi
        fi
        
        # Check for eMMC
        if lsblk -d -o NAME,TYPE | grep -q "mmcblk0boot\|mmcblk1"; then
            echo "emmc"
            return
        fi
        
        # Check for SD card
        if lsblk -d -o NAME,TYPE | grep -q "mmcblk"; then
            echo "sd"
            return
        fi
    fi
    
    # Default
    echo "sd"
}

detect_storage_size() {
    local storage_type="$1"
    
    if ! command -v lsblk &>/dev/null; then
        echo 0
        return
    fi
    
    local device=""
    
    case "$storage_type" in
        nvme)
            device=$(lsblk -d -o NAME,TYPE | grep "nvme" | head -1 | awk '{print $1}')
            ;;
        ssd)
            device=$(lsblk -d -o NAME,TYPE | grep "sd" | head -1 | awk '{print $1}')
            ;;
        emmc)
            device=$(lsblk -d -o NAME,TYPE | grep "mmcblk0boot\|mmcblk1" | head -1 | awk '{print $1}')
            ;;
        sd)
            device=$(lsblk -d -o NAME,TYPE | grep "mmcblk" | head -1 | awk '{print $1}')
            ;;
    esac
    
    if [[ -n "$device" ]]; then
        # Get size in GB
        local size_bytes=$(lsblk -b -d -o SIZE,NAME | grep "$device" | awk '{print $1}')
        if [[ -n "$size_bytes" ]]; then
            echo $((size_bytes / 1024 / 1024 / 1024))
        else
            echo 0
        fi
    else
        echo 0
    fi
}

detect_network_speed() {
    # Try to detect network speed
    
    # Check eth0 first
    if command -v ethtool &>/dev/null && ethtool eth0 &>/dev/null; then
        if ethtool eth0 2>/dev/null | grep -q "2500baseT"; then
            echo 2500
        elif ethtool eth0 2>/dev/null | grep -q "1000baseT"; then
            echo 1000
        elif ethtool eth0 2>/dev/null | grep -q "100baseT"; then
            echo 100
        else
            echo 100  # Default
        fi
    else
        echo 100  # Default assumption
    fi
}

detect_poe() {
    # Detect PoE HAT (difficult to detect reliably)
    # Check for PoE HAT fan
    if [[ -d /sys/class/thermal/cooling_device0 ]] && \
       grep -q "rpi-poe-fan" /sys/class/thermal/cooling_device0/type 2>/dev/null; then
        echo true
    else
        echo false
    fi
}

detect_cooling() {
    # Detect active cooling (fan)
    
    # Check for fan device
    if [[ -d /sys/class/thermal/cooling_device0 ]]; then
        echo true  # Has some cooling device
    else
        echo false
    fi
}

detect_heatsink() {
    # Heatsink is hard to detect, assume true for most Pis
    local device_type=$(detect_device_type)
    
    if [[ "$device_type" == "raspberry_pi" ]]; then
        # Assume most Pis have at least a heatsink
        echo true
    else
        # Assume servers/workstations have cooling
        echo true
    fi
}

detect_cpu_cores() {
    if command -v nproc &>/dev/null; then
        nproc
    elif [[ -f /proc/cpuinfo ]]; then
        grep -c "^processor" /proc/cpuinfo
    else
        echo 4  # Default
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    # Collect all hardware information
    local ip=$(hostname -I | awk '{print $1}')
    local hostname=$(hostname)
    local device_type=$(detect_device_type)
    local model=$(detect_model)
    local ram_gb=$(detect_ram)
    local storage_type=$(detect_storage_type)
    local storage_size_gb=$(detect_storage_size "$storage_type")
    local network_speed_mbps=$(detect_network_speed)
    local has_poe=$(detect_poe)
    local has_active_cooling=$(detect_cooling)
    local has_heatsink=$(detect_heatsink)
    local cpu_cores=$(detect_cpu_cores)
    
    # Output JSON
    cat <<EOF
{
  "ip": "$ip",
  "hostname": "$hostname",
  "device_type": "$device_type",
  "model": "$model",
  "ram_gb": $ram_gb,
  "storage_type": "$storage_type",
  "storage_size_gb": $storage_size_gb,
  "network_speed_mbps": $network_speed_mbps,
  "has_poe": $has_poe,
  "has_ups": false,
  "has_active_cooling": $has_active_cooling,
  "has_heatsink": $has_heatsink,
  "cpu_cores": $cpu_cores
}
EOF
}

# Run main function
main

