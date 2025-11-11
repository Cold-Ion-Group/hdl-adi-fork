# AWG KCU116 Simulation Environment

This directory contains comprehensive simulation testbenches for the KCU116 AWG project, including both **unit tests** (CORDIC/DDS) and **system-level integration tests**.

## Overview

The AWG (Arbitrary Waveform Generator) project uses CORDIC (COordinate Rotation DIgital Computer) algorithms to generate sine and cosine waveforms for the AD9144 DAC. This simulation environment provides:

1. **Unit Tests** - CORDIC and DDS component testing
2. **System Tests** - End-to-end integration verification

## Quick Start

### System-Level Test (Recommended)

For complete end-to-end integration testing:

```bash
# Run full system testbench
make system

# Or use the runner script
./run_system_tb.sh

# View waveforms
make wave-system
```

See **[SYSTEM_TB_README.md](SYSTEM_TB_README.md)** for complete system testbench documentation.

### Unit Tests

For component-level testing:

```bash
# Run CORDIC test
make cordic

# Run DDS test
make dds

# Analyze DDS output
make analyze
```

## Directory Structure

```
sim/
├── Makefile                     # Build automation for all tests
├── README.md                   # This file
├── SYSTEM_TB_README.md         # System testbench documentation
├── SYSTEM_TESTBENCH_PLAN.md    # Detailed test plan
├── TEST_VERIFICATION_REPORT.md # Unit test results
│
├── Unit Tests:
│   ├── ad_dds_cordic_tb.v      # DDS testbench
│   ├── cordic_sine_tb.v        # CORDIC unit test
│   ├── ad_mul_sim.v            # Multiplier simulation model
│   ├── run_dds_tb.sh           # Script to run DDS test
│   ├── run_cordic_tb.sh        # Script to run CORDIC test
│   └── analyze_dds.py          # Python script for output analysis
│
└── System Tests:
    ├── system_top_tb.v         # Main system testbench
    ├── axi4_lite_master_bfm.v  # AXI4-Lite bus functional model
    ├── ddr4_simple_model.v     # DDR4 memory model
    ├── ad9144_jesd_model.v     # JESD204B receiver model
    ├── test_sequences.vh       # Register addresses and definitions
    └── run_system_tb.sh        # System test runner script
```

## Prerequisites

### Required Tools

1. **Icarus Verilog** - Open-source Verilog simulator
   ```bash
   sudo apt-get install iverilog
   ```

2. **GTKWave** - Waveform viewer
   ```bash
   sudo apt-get install gtkwave
   ```

3. **Python 3** with numpy, matplotlib, scipy (for analysis)
   ```bash
   pip3 install numpy matplotlib scipy
   ```

### Optional Tools

- **Vivado Simulator** (xsim) - If you have Xilinx Vivado installed

## Quick Start

### System-Level Integration Test

For complete end-to-end testing from register access to JESD link:

```bash
make system
```

Or using the shell script:
```bash
chmod +x run_system_tb.sh
./run_system_tb.sh
```

**What it tests:**
- AXI4-Lite register access to all peripherals
- JESD204B link initialization (WAIT → CGS → ILAS → DATA)
- Transport layer (DDS) configuration
- System integration and data flow

**See:** [SYSTEM_TB_README.md](SYSTEM_TB_README.md) for complete documentation

---

### 1. Run CORDIC Unit Test

Tests the CORDIC sine/cosine generator in isolation:

```bash
make cordic
```

Or using the shell script:
```bash
chmod +x run_cordic_tb.sh
./run_cordic_tb.sh
```

**What it tests:**
- Full angle sweep (0° to 360°)
- Specific angles (0°, 45°, 90°, 135°, 180°, 270°)
- Pythagorean identity verification (sin² + cos² = 1)

### 2. Run DDS Testbench

Tests the complete DDS with dual-tone generation:

```bash
make dds
```

Or using the shell script:
```bash
chmod +x run_dds_tb.sh
./run_dds_tb.sh
```

**Configuration:**
- **Tone 1**: Lower frequency, full amplitude
- **Tone 2**: Higher frequency (2x), half amplitude
- **Sample Rate**: 200 MHz
- **Samples**: 2048 (captures full waveform cycles)

### 3. View Waveforms

View CORDIC waveforms:
```bash
make wave-cordic
```

View DDS waveforms:
```bash
make wave-dds
```

Or directly:
```bash
gtkwave ad_dds_cordic_tb.vcd &
```

### 4. Analyze DDS Output

Analyze the DDS output and generate frequency spectrum:

```bash
make analyze
```

Or directly:
```bash
python3 analyze_dds.py
```

This generates:
- **dds_analysis.png** - Plots showing time domain and frequency spectrum
- Console output with statistics and detected frequencies

## Testbenches

### CORDIC Sine/Cosine Test (`cordic_sine_tb.v`)

**Purpose:** Verify the CORDIC algorithm for sine/cosine generation

**Parameters:**
- `CORDIC_DW`: CORDIC data width (default: 16)
- `PHASE_DW`: Phase accumulator width (default: 16)

**Tests:**
1. **Full Sweep**: Tests all phase values from 0 to 2π
2. **Specific Angles**: Validates known angles (0°, 45°, 90°, etc.)
3. **Pythagorean Identity**: Verifies sin² + cos² = 1

**Output Files:**
- `cordic_sine_output.txt`: Angle vs Sine values
- `cordic_cosine_output.txt`: Angle vs Cosine values
- `cordic_sine_tb.vcd`: Waveform data

### DDS Testbench (`ad_dds_cordic_tb.v`)

**Purpose:** Test the complete DDS system with dual-tone generation

**Parameters:**
- `CORDIC_DW`: Output data width (default: 16)
- `PHASE_DW`: Phase accumulator width (default: 16)

**Features:**
- Dual-tone generation
- Configurable frequency and amplitude
- Phase offset control
- Data format selection (offset binary / 2's complement)

**Output Files:**
- `dds_output.txt`: Sample values for analysis
- `ad_dds_cordic_tb.vcd`: Waveform data

## Analysis Tools

### Python Analyzer (`analyze_dds.py`)

Analyzes DDS output and provides:
- **Time domain plots** (full and zoomed)
- **Frequency spectrum** with FFT analysis
- **Peak detection** and frequency identification
- **Statistics** (mean, std dev, min, max, peak-to-peak)

**Usage:**
```bash
python3 analyze_dds.py [output_file.txt]
```

Default input: `dds_output.txt`

## Understanding the Results

### Expected CORDIC Behavior

1. **Accuracy**: For 16-bit CORDIC, expect < 1% error compared to ideal sine/cosine
2. **Convergence**: CORDIC converges in N iterations (where N = CORDIC_DW)
3. **Quantization**: Limited by bit width, some quantization noise expected

### Expected DDS Behavior

1. **Tone Frequencies**: Should match the configured frequency words
   - Frequency = (freq_word / 2^PHASE_DW) × Sample_Rate
   - Example: freq_word = 0x0100 → (256/65536) × 200MHz ≈ 0.78 MHz

2. **Spectral Purity**: Main tones should be clearly visible in FFT
3. **Harmonics**: Some harmonic content due to quantization

### Interpreting Frequency Spectrum

- **DC Component**: Should be near zero (offset binary format)
- **Fundamental Tones**: Two peaks corresponding to tone_1 and tone_2
- **Harmonics**: Smaller peaks at multiples of fundamental frequencies
- **Noise Floor**: Determined by CORDIC bit width

## Customization

### Changing DDS Parameters

Edit `ad_dds_cordic_tb.v`:

```verilog
// Tone 1 parameters
reg [15:0] tone_1_scale = 16'h0FFF;      // Amplitude
reg [15:0] tone_1_freq_word = 16'h0100;  // Frequency

// Tone 2 parameters
reg [15:0] tone_2_scale = 16'h0800;      // Amplitude
reg [15:0] tone_2_freq_word = 16'h0200;  // Frequency
```

### Changing CORDIC Resolution

Modify module parameters:

```verilog
parameter CORDIC_DW = 20;    // Higher resolution
parameter PHASE_DW = 20;     // Finer phase control
```

## Troubleshooting

### Compilation Errors

**Problem:** `module not found`
- **Solution:** Check that HDL_DIR path is correct
- Verify source files exist in `library/common/`

**Problem:** Syntax errors
- **Solution:** Ensure using SystemVerilog-compatible simulator
- For iverilog, use `-g2012` flag

### Simulation Issues

**Problem:** No output files generated
- **Solution:** Check simulation completed successfully
- Look for errors in console output

**Problem:** Unexpected frequency spectrum
- **Solution:** Verify freq_word calculation
- Check sample rate assumption (200 MHz)

### Analysis Issues

**Problem:** Python script fails
- **Solution:** Install required packages: `pip3 install numpy matplotlib scipy`
- Check that `dds_output.txt` exists

## Advanced Usage

### Custom Test Scenarios

Create your own testbench by modifying the existing files or creating new ones:

```verilog
// Example: Test swept frequency
initial begin
    for (int freq = 16'h0010; freq < 16'h1000; freq = freq + 16'h0010) begin
        tone_1_freq_word = freq;
        dac_data_sync = 1'b1;
        @(posedge clk);
        dac_data_sync = 1'b0;
        repeat(256) @(posedge clk);
    end
end
```

### Integration with System-Level Tests

✅ **System-level integration testbench now available!**

The `system_top_tb.v` testbench integrates multiple components including:
- JESD204B link layer (with behavioral model)
- AXI4-Lite register interface
- Transport layer (DDS configuration)
- Full system integration testing

See [SYSTEM_TB_README.md](SYSTEM_TB_README.md) for details.

## Test Coverage Summary

| Test Level | Testbench | Status | Coverage |
|------------|-----------|--------|----------|
| **Unit Test** | `cordic_sine_tb.v` | ✅ PASS | CORDIC algorithm (0-360°) |
| **Unit Test** | `ad_dds_cordic_tb.v` | ✅ PASS | DDS dual-tone generation |
| **System Test** | `system_top_tb.v` | ✅ PASS | AXI, JESD link, integration |

**Total Tests**: 3  
**Passed**: 3  
**Failed**: 0  

## References

### CORDIC Algorithm

- [Wikipedia: CORDIC](https://en.wikipedia.org/wiki/CORDIC)
- [Understanding CORDIC](https://www.ti.com/lit/an/spra291/spra291.pdf)

### AWG Project

- Project location: `projects/awg/kcu116/`
- CORDIC implementation: `library/common/ad_dds_sine_cordic.v`
- DDS implementation: `library/common/ad_dds.v`

### AD9144 DAC

- [AD9144 Product Page](https://www.analog.com/en/products/ad9144.html)
- JESD204B link layer: `library/jesd204/`

## Support

For issues or questions:
1. Check existing testbenches in `library/*/tb/`
2. Review CORDIC implementation in `library/common/`
3. Consult ADI HDL repository documentation

## License

This simulation environment follows the same licensing as the parent HDL repository.
See LICENSE files in the repository root.
