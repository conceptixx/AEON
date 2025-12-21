#!/bin/bash

# SSH Auto-Discovery and Connection Script
# This script discovers hosts on the local network, attempts SSH connections,
# and reports the status of each detected host.

# Exit on error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Arrays to store results
declare -a detected_hosts
declare -a reachable_hosts
declare -a ssh_accessible_hosts
declare -A host_info  # Associative array for host info

# Usernames and password to try
usernames=("pi" "aeon-llm" "aeon-host" "aeon")
password="raspberry"

print_status()  { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" >&2; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" >&2; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Function to print status messages
#print_status() {
#    echo -e "${BLUE}[INFO]${NC} $1"
#}

#print_success() {
#    echo -e "${GREEN}[SUCCESS]${NC} $1"
#}

#print_warning() {
#    echo -e "${YELLOW}[WARNING]${NC} $1"
#}

#print_error() {
#    echo -e "${RED}[ERROR]${NC} $1"
#}

# Function to get the host's IP address and network
get_network_info() {
    print_status "Detecting network configuration..."
    
    # Try multiple methods to get the IP address
    local ip_address
    
    # Method 1: Using hostname -I (works on most Linux systems)
    if command -v hostname &> /dev/null; then
        ip_address=$(hostname -I | awk '{print $1}')
    fi
    
    # Method 2: Using ip command (modern Linux)
    if [ -z "$ip_address" ] && command -v ip &> /dev/null; then
        ip_address=$(ip -o -4 addr show | awk '{print $4}' | cut -d'/' -f1 | head -1)
    fi
    
    # Method 3: Using ifconfig (older systems)
    if [ -z "$ip_address" ] && command -v ifconfig &> /dev/null; then
        ip_address=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1)
    fi
    
    if [ -z "$ip_address" ]; then
        print_error "Could not determine IP address. Please set it manually."
        read -p "Enter your network IP (e.g., 192.168.124.5): " ip_address
    else
        print_success "Detected IP address: $ip_address"
    fi
    
    # Extract network prefix (first three octets)
    network_prefix=$(echo "$ip_address" | cut -d'.' -f1-3)
    
    print_status "Network prefix: $network_prefix.0/24"
    echo "$network_prefix"
}

# Function to check if a host is reachable via ping
check_host_reachable() {
    local ip="$1"
    local attempt
    # Try ping (1 packet, 1 second timeout)
    for attempt in {1..3}; do
        if ping -c 1 -W 1 "$ip" &> /dev/null; then
            return 0
        fi
    done
    return 1
}

# Function to get hostname from IP
get_hostname() {
    local ip="$1"
    local hostname
    
    # Try to get hostname using nslookup
    if command -v nslookup &> /dev/null; then
        hostname=$(nslookup "$ip" 2>/dev/null | awk '/name = / {print $4}' | sed 's/\.$//')
    fi
    
    # Try using host command if nslookup failed
    if [ -z "$hostname" ] && command -v host &> /dev/null; then
        hostname=$(host "$ip" 2>/dev/null | awk '/domain name pointer/ {print $5}' | sed 's/\.$//')
    fi
    
    # If still no hostname, try using getent
    if [ -z "$hostname" ] && command -v getent &> /dev/null; then
        hostname=$(getent hosts "$ip" | awk '{print $2}' | head -1)
    fi
    
    echo "${hostname:-Unknown}"
}

# Function to test SSH connection
test_ssh_connection() {
  local ip="$1"
  local hostname="$2"

  print_status "Testing SSH connection to $ip ($hostname)..."

  local use_sshpass=0
  if command -v sshpass >/dev/null 2>&1; then
    use_sshpass=1
  fi

  for username in "${usernames[@]}"; do
    if [ "$use_sshpass" -eq 1 ]; then
      # Passwort-Login testen (nicht BatchMode!)
      if sshpass -p "$password" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=3 \
        -o ConnectionAttempts=1 \
        -o PreferredAuthentications=password \
        -o PubkeyAuthentication=no \
        -o NumberOfPasswordPrompts=1 \
        "$username@$ip" "exit" </dev/null >/dev/null 2>&1
      then
        print_success "  SSH accessible with username: $username"
        return 0
      fi
    else
      # Ohne sshpass: nur Key-based testen (sonst würde es interaktiv werden)
      if ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=3 \
        -o ConnectionAttempts=1 \
        -o BatchMode=yes \
        -o PreferredAuthentications=publickey \
        -o PasswordAuthentication=no \
        -o KbdInteractiveAuthentication=no \
        "$username@$ip" "exit" </dev/null >/dev/null 2>&1
      then
        print_success "  SSH accessible with username: $username (key)"
        return 0
      fi
    fi
  done

  return 1
}

# Function to scan the network
scan_network() {
    local network_prefix="$1"
    
    print_status "Starting network scan..."
    print_status "Scanning IP range: ${network_prefix}.1 - ${network_prefix}.254"
    echo "=========================================="
    
    # Counter for progress
    local count=0
    local total=254
    
    # Scan all IPs in the subnet
    for i in {190..200}; do
        ip="${network_prefix}.${i}"
        count=$((count + 1))
        
        # Show progress
        if [ $((count % 10)) -eq 0 ] || [ $count -eq 1 ] || [ $count -eq $total ]; then
            echo -ne "${BLUE}Scanning: $count/$total hosts${NC}\r"
        fi
        
        # Skip our own IP
        if [ "$ip" = "$(hostname -I | awk '{print $1}')" ]; then
            continue
        fi
        
        # Check if host is reachable
        if check_host_reachable "$ip"; then
            detected_hosts+=("$ip")
            
            # Get hostname
            hostname=$(get_hostname "$ip")
            host_info["$ip,hostname"]="$hostname"
            
            print_success "Found host: $ip ($hostname)"
            
            # Test SSH connection
            if test_ssh_connection "$ip" "$hostname"; then
                ssh_accessible_hosts+=("$ip")
                host_info["$ip,ssh"]="YES"
                host_info["$ip,status"]="SSH Accessible"
            else
                host_info["$ip,ssh"]="NO"
                host_info["$ip,status"]="No SSH Access"
            fi
        fi
    done
    
    echo -e "\n${GREEN}Scan completed!${NC}"
}

# Function to display results
display_results() {
    echo -e "\n${GREEN}=========================================="
    echo "           SCAN RESULTS"
    echo "==========================================${NC}"
    
    if [ ${#detected_hosts[@]} -eq 0 ]; then
        print_warning "No hosts detected on the network."
        return
    fi
    
    echo -e "\n${BLUE}Detected Hosts: ${#detected_hosts[@]}${NC}"
    echo -e "${BLUE}SSH Accessible Hosts: ${#ssh_accessible_hosts[@]}${NC}"
    
    echo -e "\n${YELLOW}┌────────────────────────────────────────────────────────────┐"
    echo -e "│ ${BLUE}IP Address${NC}         ${BLUE}Hostname${NC}              ${BLUE}Status${NC}           │"
    echo -e "├────────────────────────────────────────────────────────────┤"
    
    for ip in "${detected_hosts[@]}"; do
        hostname="${host_info["$ip,hostname"]}"
        ssh_status="${host_info["$ip,ssh"]}"
        status="${host_info["$ip,status"]}"
        
        # Truncate long hostnames for display
        if [ ${#hostname} -gt 20 ]; then
            hostname_display="${hostname:0:17}..."
        else
            hostname_display="$hostname"
        fi
        
        # Color code based on SSH status
        if [ "$ssh_status" = "YES" ]; then
            status_color="${GREEN}"
        else
            status_color="${RED}"
        fi
        
        printf "│ %-15s   %-20s   ${status_color}%-15s${NC} │\n" "$ip" "$hostname_display" "$status"
    done
    
    echo -e "${YELLOW}└────────────────────────────────────────────────────────────┘${NC}"
    
    # Display SSH accessible hosts separately
    if [ ${#ssh_accessible_hosts[@]} -gt 0 ]; then
        echo -e "\n${GREEN}SSH Accessible Hosts:${NC}"
        for ip in "${ssh_accessible_hosts[@]}"; do
            hostname="${host_info["$ip,hostname"]}"
            echo -e "  • $ip ($hostname)"
        done
    fi
}

# Function to export results to a file
export_results() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local filename="network_scan_${timestamp}.txt"
    
    echo "Network Scan Results - $(date)" > "$filename"
    echo "=================================" >> "$filename"
    echo "" >> "$filename"
    echo "Detected Hosts: ${#detected_hosts[@]}" >> "$filename"
    echo "SSH Accessible Hosts: ${#ssh_accessible_hosts[@]}" >> "$filename"
    echo "" >> "$filename"
    echo "IP Address        Hostname                SSH Access    Status" >> "$filename"
    echo "----------------------------------------------------------------" >> "$filename"
    
    for ip in "${detected_hosts[@]}"; do
        hostname="${host_info["$ip,hostname"]}"
        ssh_status="${host_info["$ip,ssh"]}"
        status="${host_info["$ip,status"]}"
        
        printf "%-15s   %-20s   %-12s   %s\n" "$ip" "$hostname" "$ssh_status" "$status" >> "$filename"
    done
    
    print_success "Results exported to: $filename"
}

# Main function
main() {
    echo -e "${GREEN}=========================================="
    echo "      Network SSH Discovery Tool"
    echo "==========================================${NC}"
    
    # Check prerequisites
    if ! command -v ssh &> /dev/null; then
#        print_error "SSH client is not installed."
#        print_error "Install with: sudo apt-get install openssh-client (Debian/Ubuntu)"
        exit 1
    fi
    
    # Get network information
    network_prefix=$(get_network_info)
    
    if [ -z "$network_prefix" ]; then
        print_error "Failed to determine network prefix."
        exit 1
    fi
    
    # Scan network
    scan_network "$network_prefix"
    
    # Display results
    display_results
    
    # Ask to export results
#    read -p "Export results to file? (y/n): " export_choice
#    if [[ "$export_choice" =~ ^[Yy]$ ]]; then
#        export_results
#    fi
    
    echo -e "\n${GREEN}Script completed!${NC}"
}

# Run main function
echo "$(date +%H:%M:%S)"
main
echo "$(date +%H:%M:%S)"
# ***END*OF*FILE***