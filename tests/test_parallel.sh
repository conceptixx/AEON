#!/bin/bash
################################################################################
# AEON Parallel Execution Module - Test Script
# File: test_parallel.sh
# Version: 0.1.0
#
# Purpose: Comprehensive testing of parallel execution module
#
# Usage: bash test_parallel.sh
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Test configuration
TEST_DEVICES=(
    "192.168.1.100:pi:raspberry"
    "192.168.1.101:pi:raspberry"
    "192.168.1.102:pi:raspberry"
)

TESTS_PASSED=0
TESTS_FAILED=0

# ============================================================================
# TEST UTILITIES
# ============================================================================

print_test_header() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  TEST: $1${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

assert_success() {
    local test_name="$1"
    local exit_code="$2"
    
    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}✓ PASS:${NC} $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAIL:${NC} $test_name (exit code: $exit_code)"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_file_exists() {
    local test_name="$1"
    local file="$2"
    
    if [[ -f "$file" ]]; then
        echo -e "${GREEN}✓ PASS:${NC} $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAIL:${NC} $test_name (file not found: $file)"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_contains() {
    local test_name="$1"
    local haystack="$2"
    local needle="$3"
    
    if echo "$haystack" | grep -q "$needle"; then
        echo -e "${GREEN}✓ PASS:${NC} $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAIL:${NC} $test_name (expected to contain: $needle)"
        ((TESTS_FAILED++))
        return 1
    fi
}

# ============================================================================
# TESTS
# ============================================================================

test_module_loading() {
    print_test_header "Module Loading"
    
    # Source the module
    source /opt/aeon/lib/parallel.sh
    
    # Check if functions are defined
    assert_success "parallel_init function exists" "$(type parallel_init &>/dev/null; echo $?)"
    assert_success "parallel_exec function exists" "$(type parallel_exec &>/dev/null; echo $?)"
    assert_success "parallel_file_transfer function exists" "$(type parallel_file_transfer &>/dev/null; echo $?)"
    assert_success "parallel_wait_online function exists" "$(type parallel_wait_online &>/dev/null; echo $?)"
    assert_success "parallel_collect_results function exists" "$(type parallel_collect_results &>/dev/null; echo $?)"
    assert_success "parallel_cleanup function exists" "$(type parallel_cleanup &>/dev/null; echo $?)"
}

test_initialization() {
    print_test_header "Initialization"
    
    source /opt/aeon/lib/parallel.sh
    
    # Initialize
    parallel_init
    local init_result=$?
    
    assert_success "parallel_init returns 0" "$init_result"
    assert_file_exists "Job directory created" "${PARALLEL_JOB_DIR}/parallel.log"
    assert_file_exists "Results directory created" "${PARALLEL_JOB_DIR}/results/.keep" || mkdir -p "${PARALLEL_JOB_DIR}/results" && touch "${PARALLEL_JOB_DIR}/results/.keep"
}

test_simple_execution() {
    print_test_header "Simple Command Execution"
    
    source /opt/aeon/lib/parallel.sh
    parallel_init
    
    # Create mock devices (localhost)
    local mock_devices=(
        "localhost:${USER}:testpass"
    )
    
    # Execute simple command
    parallel_exec mock_devices[@] "echo 'test'" "Test execution" 2>/dev/null || true
    
    # Note: This will fail without proper SSH setup, but tests the execution path
    echo -e "${CYAN}ℹ️  Note: Full execution test requires SSH-accessible devices${NC}"
}

test_progress_bar() {
    print_test_header "Progress Bar Rendering"
    
    source /opt/aeon/lib/parallel.sh
    
    # Test progress bar creation
    local bar1=$(parallel_create_progress_bar 0 100 40)
    assert_contains "Progress bar 0%" "$bar1" "0%"
    
    local bar2=$(parallel_create_progress_bar 50 100 40)
    assert_contains "Progress bar 50%" "$bar2" "50%"
    
    local bar3=$(parallel_create_progress_bar 100 100 40)
    assert_contains "Progress bar 100%" "$bar3" "100%"
}

test_duration_formatting() {
    print_test_header "Duration Formatting"
    
    source /opt/aeon/lib/parallel.sh
    
    local dur1=$(parallel_format_duration 30)
    assert_contains "30 seconds" "$dur1" "30s"
    
    local dur2=$(parallel_format_duration 90)
    assert_contains "90 seconds (1m 30s)" "$dur2" "1m"
    
    local dur3=$(parallel_format_duration 3665)
    assert_contains "3665 seconds (1h 1m 5s)" "$dur3" "1h"
}

test_cleanup() {
    print_test_header "Cleanup"
    
    source /opt/aeon/lib/parallel.sh
    parallel_init
    
    local job_dir="$PARALLEL_JOB_DIR"
    
    # Cleanup
    parallel_cleanup
    
    # Check directory removed
    if [[ ! -d "$job_dir" ]]; then
        echo -e "${GREEN}✓ PASS:${NC} Job directory cleaned up"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL:${NC} Job directory still exists"
        ((TESTS_FAILED++))
    fi
}

# ============================================================================
# DEMO (Interactive)
# ============================================================================

demo_parallel_execution() {
    print_test_header "DEMO: Parallel Execution (Interactive)"
    
    echo -e "${YELLOW}This demo shows the parallel execution module in action.${NC}"
    echo -e "${YELLOW}It will execute a simple command on multiple simulated devices.${NC}"
    echo ""
    read -p "Press Enter to continue (or Ctrl+C to skip)..."
    
    source /opt/aeon/lib/parallel.sh
    parallel_init
    
    # Simulate devices with localhost
    local demo_devices=(
        "localhost:${USER}:dummy1"
        "localhost:${USER}:dummy2"
        "localhost:${USER}:dummy3"
    )
    
    echo ""
    echo -e "${CYAN}Simulating parallel execution on 3 devices...${NC}"
    echo ""
    
    # This will show the UI but fail on SSH (expected)
    parallel_exec demo_devices[@] "echo 'Demo test'" "Running demo command" 2>/dev/null || true
    
    echo ""
    echo -e "${CYAN}Demo complete (SSH failures expected - this is a simulation)${NC}"
}

# ============================================================================
# RUN ALL TESTS
# ============================================================================

main() {
    clear
    echo ""
    echo -e "${BOLD}${CYAN}"
    cat << "BANNER"
     █████╗ ███████╗ ██████╗ ███╗   ██╗
    ██╔══██╗██╔════╝██╔═══██╗████╗  ██║
    ███████║█████╗  ██║   ██║██╔██╗ ██║
    ██╔══██║██╔══╝  ██║   ██║██║╚██╗██║
    ██║  ██║███████╗╚██████╔╝██║ ╚████║
    ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝
BANNER
    echo -e "${NC}"
    echo -e "  ${CYAN}Parallel Execution Module - Test Suite${NC}"
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Run tests
    test_module_loading
    test_initialization
    test_progress_bar
    test_duration_formatting
    test_simple_execution
    test_cleanup
    
    # Demo (optional)
    # demo_parallel_execution
    
    # Summary
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  TEST SUMMARY${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Total tests: $((TESTS_PASSED + TESTS_FAILED))"
    echo -e "  ${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "  ${RED}Failed: $TESTS_FAILED${NC}"
    echo ""
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✅ ALL TESTS PASSED!${NC}"
        echo ""
        exit 0
    else
        echo -e "${RED}${BOLD}❌ SOME TESTS FAILED${NC}"
        echo ""
        exit 1
    fi
}

# Check if module exists
if [[ ! -f "/opt/aeon/lib/parallel.sh" ]]; then
    echo -e "${RED}ERROR: Module not found at /opt/aeon/lib/parallel.sh${NC}"
    echo ""
    echo "Please install the module first:"
    echo "  sudo mkdir -p /opt/aeon/lib"
    echo "  sudo cp parallel.sh /opt/aeon/lib/"
    echo ""
    exit 1
fi

# Run tests
main "$@"
