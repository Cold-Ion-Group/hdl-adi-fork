#!/bin/bash
# Run CORDIC Sine/Cosine Unit Test
# Usage: ./run_cordic_tb.sh

set -e

echo "====================================="
echo "CORDIC Sine/Cosine Unit Test"
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
    "cordic_sine_tb.v"
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
    -o cordic_sine_tb.vvp \
    "${SRC_FILES[@]}" \
    -I"$COMMON_DIR" \
    -DTIMEOUT=500000

if [ $? -eq 0 ]; then
    echo "Compilation successful!"
    echo ""
    echo "Running simulation..."
    echo "====================================="
    
    # Run simulation
    vvp cordic_sine_tb.vvp
    
    echo ""
    echo "====================================="
    echo "Simulation complete!"
    echo ""
    echo "Generated files:"
    ls -lh cordic_sine_output.txt cordic_cosine_output.txt cordic_sine_tb.vcd 2>/dev/null || true
    echo ""
    echo "To view waveforms: gtkwave cordic_sine_tb.vcd"
    echo "====================================="
else
    echo "Compilation failed!"
    exit 1
fi
