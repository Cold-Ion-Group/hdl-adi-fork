#!/bin/bash
# Run CORDIC DDS Testbench
# Usage: ./run_dds_tb.sh

set -e

echo "====================================="
echo "CORDIC DDS Testbench"
echo "====================================="

# Set paths
HDL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../../../.." && pwd )"
SIM_DIR="$(pwd)"
COMMON_DIR="$HDL_DIR/library/common"

echo "HDL Directory: $HDL_DIR"
echo "Simulation Directory: $SIM_DIR"

# Source files
SRC_FILES=(
    "$COMMON_DIR/ad_dds_sine_cordic.v"
    "$COMMON_DIR/ad_dds_cordic_pipe.v"
    "$COMMON_DIR/ad_dds_1.v"
    "$COMMON_DIR/ad_dds_2.v"
    "$COMMON_DIR/ad_dds.v"
    "$COMMON_DIR/ad_dds_sine.v"
    "ad_dds_cordic_tb.v"
)

# Check if files exist
echo ""
echo "Checking source files..."
for file in "${SRC_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "ERROR: File not found: $file"
        exit 1
    fi
    echo "  ✓ $file"
done

echo ""
echo "Running iverilog..."

# Compile with Icarus Verilog
iverilog -g2012 \
    -o ad_dds_cordic_tb.vvp \
    "${SRC_FILES[@]}" \
    -I"$COMMON_DIR" \
    -DTIMEOUT=500000

if [ $? -eq 0 ]; then
    echo "Compilation successful!"
    echo ""
    echo "Running simulation..."
    echo "====================================="
    
    # Run simulation
    vvp ad_dds_cordic_tb.vvp
    
    echo ""
    echo "====================================="
    echo "Simulation complete!"
    echo ""
    echo "Generated files:"
    ls -lh dds_output.txt ad_dds_cordic_tb.vcd 2>/dev/null || true
    echo ""
    echo "To view waveforms: gtkwave ad_dds_cordic_tb.vcd"
    echo "To analyze output: python3 analyze_dds.py"
    echo "====================================="
else
    echo "Compilation failed!"
    exit 1
fi
