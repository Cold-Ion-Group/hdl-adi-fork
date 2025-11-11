#!/bin/bash
# System-Level Test Runner for AWG KCU116
#
# This script runs the system-level testbench and reports results
#
# Usage: ./run_system_tb.sh

set -e

echo "========================================"
echo "  AWG System-Level Test Runner"
echo "========================================"
echo ""

# Check if iverilog is installed
if ! command -v iverilog &> /dev/null; then
    echo "ERROR: iverilog not found. Please install it:"
    echo "  sudo apt-get install iverilog"
    exit 1
fi

# Clean previous results
echo "Cleaning previous simulation artifacts..."
rm -f system_top_tb.vvp system_top_tb.vcd
echo ""

# Compile and run testbench
echo "Running system testbench..."
echo "========================================"
make system

# Check results
if [ $? -eq 0 ]; then
    echo ""
    echo "========================================"
    echo "  System Test PASSED"
    echo "========================================"
    echo ""
    echo "Generated files:"
    echo "  - system_top_tb.vcd  : Waveform data"
    echo ""
    echo "To view waveforms:"
    echo "  make wave-system"
    echo "  OR"
    echo "  gtkwave system_top_tb.vcd"
    echo ""
    exit 0
else
    echo ""
    echo "========================================"
    echo "  System Test FAILED"
    echo "========================================"
    exit 1
fi
