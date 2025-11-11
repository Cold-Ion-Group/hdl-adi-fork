#!/bin/bash
# ***************************************************************************
# AWG KCU116 Simulation Workflow Runner
# Sources Xilinx tools and runs complete simulation suite
# ***************************************************************************

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================="
echo "AWG KCU116 Simulation Workflow"
echo -e "==========================================${NC}"
echo ""

# Source Xilinx tools
echo -e "${YELLOW}Sourcing Xilinx Vivado 2022.2...${NC}"
if [ -f "/tools/Xilinx/Vivado/2022.2/settings64.sh" ]; then
    source /tools/Xilinx/Vivado/2022.2/settings64.sh
    echo -e "${GREEN}✓ Vivado sourced${NC}"
else
    echo -e "${RED}✗ Vivado not found at /tools/Xilinx/Vivado/2022.2${NC}"
fi

echo -e "${YELLOW}Sourcing Xilinx Vitis 2022.2...${NC}"
if [ -f "/tools/Xilinx/Vitis/2022.2/settings64.sh" ]; then
    source /tools/Xilinx/Vitis/2022.2/settings64.sh
    echo -e "${GREEN}✓ Vitis sourced${NC}"
else
    echo -e "${YELLOW}⚠ Vitis not found (optional)${NC}"
fi

echo -e "${YELLOW}Sourcing Xilinx Vitis_HLS 2022.2...${NC}"
if [ -f "/tools/Xilinx/Vitis_HLS/2022.2/settings64.sh" ]; then
    source /tools/Xilinx/Vitis_HLS/2022.2/settings64.sh
    echo -e "${GREEN}✓ Vitis HLS sourced${NC}"
else
    echo -e "${YELLOW}⚠ Vitis HLS not found (optional)${NC}"
fi

echo ""
echo -e "${BLUE}=========================================="
echo "Tool Versions"
echo -e "==========================================${NC}"
which vivado > /dev/null 2>&1 && vivado -version | grep -i vivado || echo -e "${YELLOW}Vivado not in PATH${NC}"
which xsim > /dev/null 2>&1 && xsim -version 2>&1 | head -1 || echo -e "${YELLOW}xsim not in PATH${NC}"
which iverilog > /dev/null 2>&1 && iverilog -v 2>&1 | head -1 || echo -e "${YELLOW}Icarus Verilog not installed${NC}"
which python3 > /dev/null 2>&1 && python3 --version || echo -e "${YELLOW}Python3 not installed${NC}"

echo ""
echo -e "${BLUE}=========================================="
echo "Simulation Workflow"
echo -e "==========================================${NC}"

# Function to run test and check result
run_test() {
    local test_name=$1
    local test_cmd=$2
    
    echo ""
    echo -e "${BLUE}------------------------------------------"
    echo "Running: $test_name"
    echo -e "------------------------------------------${NC}"
    
    if eval $test_cmd; then
        echo -e "${GREEN}✓ $test_name PASSED${NC}"
        return 0
    else
        echo -e "${RED}✗ $test_name FAILED${NC}"
        return 1
    fi
}

# Track test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test 1: CORDIC Unit Test
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if run_test "CORDIC Sine/Cosine Test" "make cordic"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Test 2: DDS Test
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if run_test "DDS CORDIC Test" "make dds"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Test 3: Analyze DDS output if Python is available
if which python3 > /dev/null 2>&1; then
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if run_test "DDS Output Analysis" "make analyze"; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
else
    echo -e "${YELLOW}⚠ Skipping analysis (Python3 not found)${NC}"
fi

# Summary
echo ""
echo -e "${BLUE}=========================================="
echo "Simulation Summary"
echo -e "==========================================${NC}"
echo -e "Total Tests:  ${TOTAL_TESTS}"
echo -e "${GREEN}Passed:       ${PASSED_TESTS}${NC}"
if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "${RED}Failed:       ${FAILED_TESTS}${NC}"
else
    echo -e "Failed:       ${FAILED_TESTS}"
fi
echo -e "${BLUE}==========================================${NC}"

# List generated files
echo ""
echo -e "${BLUE}Generated Files:${NC}"
ls -lh *.vcd *.txt *.png 2>/dev/null || echo "No output files found"

echo ""
if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "  1. View waveforms: make wave-dds"
    echo "  2. View analysis:  xdg-open dds_spectrum.png"
    echo "  3. Clean up:       make clean"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    echo ""
    echo "Review the output above for errors"
    exit 1
fi
