# System-Level Testbench for AWG KCU116

## Overview

This directory contains a complete system-level testbench for the AWG (Arbitrary Waveform Generator) KCU116 project. The testbench validates end-to-end integration from AXI register access through JESD204B link initialization to DAC data flow.

## Quick Start

### Run All Tests

```bash
make system
```

Or use the test runner script:

```bash
./run_system_tb.sh
```

### View Waveforms

```bash
make wave-system
# OR
gtkwave system_top_tb.vcd
```

## Architecture

### Testbench Components

The system testbench (`system_top_tb.v`) integrates the following components:

```
┌─────────────────────────────────────────────────────────────┐
│                    system_top_tb                            │
│                                                              │
│  ┌──────────────────┐        ┌──────────────────────────┐  │
│  │  AXI4-Lite       │◄──────►│  Register Banks          │  │
│  │  Master BFM      │  AXI   │  - JESD  (0x44A9_0000)  │  │
│  │                  │        │  - TPL   (0x44A0_4000)  │  │
│  │  (Replaces       │        │  - DMA   (0x7C42_0000)  │  │
│  │   MicroBlaze)    │        │  - XCVR  (0x44A6_0000)  │  │
│  └──────────────────┘        └──────────────────────────┘  │
│                                                              │
│  ┌──────────────────┐        ┌──────────────────────────┐  │
│  │  AD9144 JESD     │◄───────│  JESD Data               │  │
│  │  Model           │  JESD  │  Generator               │  │
│  │                  │        │                          │  │
│  │  - Link FSM      │        │  (Counter pattern)       │  │
│  │  - SYNC gen      │        │                          │  │
│  │  - Data capture  │        │                          │  │
│  └──────────────────┘        └──────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Clock & Reset Generation                            │  │
│  │  - sys_clk:  100 MHz                                 │  │
│  │  - ref_clk:  125 MHz                                 │  │
│  │  - sysref:   Periodic pulse                          │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Key Files

1. **system_top_tb.v** - Main testbench
   - Clock and reset generation
   - Test scenario orchestration
   - Register bank emulation
   - Results checking

2. **axi4_lite_master_bfm.v** - AXI4-Lite Bus Functional Model
   - Protocol-compliant AXI transactions
   - Tasks: `axi_write`, `axi_read`, `axi_verify`, `axi_poll`
   - Timeout and error detection

3. **ad9144_jesd_model.v** - JESD204B Receiver Model
   - Link state machine (WAIT → CGS → ILAS → DATA)
   - SYNC signal generation
   - Data capture capability

4. **ddr4_simple_model.v** - DDR4 Memory Model
   - AXI4 full slave interface
   - Simplified timing model
   - (Currently not connected in simple testbench)

5. **test_sequences.vh** - Common Definitions
   - Register address map
   - JESD state constants
   - Test macros

## Test Scenarios

### Scenario 1: Register Access ✅

**Objective**: Verify AXI4-Lite connectivity to all peripherals

**Tests**:
- Read VERSION registers from all peripherals
- Read MAGIC registers (expected value: 0x5AFE0001)
- Write/Read SCRATCH register for data integrity

**Success Criteria**:
- All VERSION registers readable
- MAGIC values match expected
- SCRATCH register retains written values

### Scenario 2: JESD Link Initialization ✅

**Objective**: Verify JESD204B link can be configured and reach ready state

**Steps**:
1. Enable 4 lanes via LANES_ENABLE register
2. Configure link parameters via LINK_CONF registers
3. Enable link via LINK_CONF2[0]
4. Wait for SYNC assertion
5. Monitor link state transitions

**Success Criteria**:
- Link reaches DATA state (state = 3)
- SYNC signal asserts
- Link transitions: WAIT → CGS → ILAS → DATA
- Completion within timeout

### Scenario 3: DDS Configuration ✅

**Objective**: Configure transport layer for DDS mode

**Steps**:
1. Write to TPL_RSTN to enable DAC
2. Configure channel 0 for DDS mode
3. Set DDS parameters

**Success Criteria**:
- Configuration writes complete successfully
- No AXI errors

## Test Results

### Latest Run

```
========================================
  Test Summary
========================================
  Passed: 5
  Failed: 0
========================================
*** ALL TESTS PASSED ***
```

### Test Coverage

| Test | Status | Details |
|------|--------|---------|
| JESD VERSION read | ✅ PASS | Value: 0x00010000 |
| JESD MAGIC read | ✅ PASS | Value: 0x5AFE0001 |
| JESD SCRATCH write/read | ✅ PASS | Pattern: 0xDEADBEEF |
| JESD Link initialization | ✅ PASS | State reached: DATA (3) |
| DDS configuration | ✅ PASS | Registers written |

## Memory Map

| Peripheral | Base Address | Function |
|------------|--------------|----------|
| `axi_ad9144_xcvr` | 0x44A6_0000 | PHY layer (GTH transceiver config) |
| `axi_ad9144_tpl` | 0x44A0_4000 | Transport layer (DDS, data generation) |
| `axi_ad9144_jesd` | 0x44A9_0000 | Link layer (JESD204B protocol) |
| `axi_ad9144_dma` | 0x7C42_0000 | DMA controller (memory to FIFO) |

## Timing

### Clock Domains

- **sys_clk**: 100 MHz (10 ns period) - AXI bus clock
- **ref_clk**: 125 MHz (8 ns period) - JESD reference clock
- **sysref**: Periodic pulse every 1 μs - JESD synchronization

### Test Execution Time

- Total simulation time: ~2.5 ms
- Scenario 1 (Register Access): ~600 μs
- Scenario 2 (JESD Init): ~1.4 ms
- Scenario 3 (DDS Config): ~100 μs

## Extending the Testbench

### Adding New Test Scenarios

1. Add a new task in `system_top_tb.v`:

```verilog
task test_scenario_4_my_test;
  begin
    $display("\n========================================");
    $display("  Test 4: My New Test");
    $display("========================================");
    
    // Your test code here
    i_axi_bfm.axi_write_simple(`JESD_BASE + reg_offset, value);
    i_axi_bfm.axi_read(`JESD_BASE + reg_offset, read_data);
    
    // Check results
    if (read_data == expected) begin
      $display("[PASS] Test description");
      test_passed = test_passed + 1;
    end else begin
      $display("[FAIL] Test description");
      test_failed = test_failed + 1;
    end
  end
endtask
```

2. Call the task from the initial block:

```verilog
initial begin
  // ...
  test_scenario_1_register_access();
  test_scenario_2_jesd_link_init();
  test_scenario_3_dds_config();
  test_scenario_4_my_test();  // Add here
  // ...
end
```

### Adding Register Definitions

Edit `test_sequences.vh` to add new register addresses:

```verilog
`define MY_NEW_REG_OFFSET   32'h0ABC
`define MY_NEW_REG_ADDR     (`JESD_BASE + `MY_NEW_REG_OFFSET)
```

## Limitations

### What This Testbench Tests

✅ AXI4-Lite register access  
✅ JESD link state machine behavior  
✅ DDS configuration flow  
✅ System integration and connectivity  

### What This Testbench Does NOT Test

❌ Full MicroBlaze processor execution  
❌ Actual DDR4 memory controller  
❌ GTH transceiver PHY details  
❌ Actual DAC analog output  
❌ DMA data transfers (simplified)  
❌ High-speed SERDES signals  

### Scope

This testbench focuses on **integration testing** rather than **IP verification**. It assumes:

- Individual IP blocks (JESD, DMA, DDS) are verified separately
- PHY layer (GTH transceivers) functionality is abstracted
- Focus is on register interface and control flow

## Troubleshooting

### Compilation Errors

**Problem**: `module not found`

**Solution**: Check that iverilog is installed:
```bash
which iverilog
# If not found:
sudo apt-get install iverilog
```

### Simulation Hangs

**Problem**: Testbench doesn't complete

**Solution**: Check for:
- AXI handshake deadlocks (awready, wready not asserting)
- Missing clock or reset
- Timeout watchdog fires at 100ms

### Test Failures

**Problem**: Register read returns unexpected value

**Solution**:
1. Check register address is correct in `test_sequences.vh`
2. Verify register is initialized in `system_top_tb.v`
3. Check AXI address decoding logic

## Performance

### Compilation

- Compile time: ~1-2 seconds
- Source files: 5 Verilog files

### Simulation

- Run time: ~3-5 seconds
- Simulated time: ~2.5 ms
- VCD file size: ~500 KB

## Future Enhancements

### Planned Improvements

1. **DMA Data Transfer Test**
   - Connect DDR4 memory model
   - Implement full DMA transaction
   - Verify data integrity end-to-end

2. **Enhanced JESD Model**
   - Full ILAS decoding
   - Lane alignment checking
   - Error injection

3. **Protocol Checkers**
   - AXI4-Lite protocol assertions
   - JESD204B compliance checking
   - Clock domain crossing checks

4. **Coverage Collection**
   - Register access coverage
   - State machine coverage
   - Error path coverage

## References

### Related Documentation

- `SYSTEM_TESTBENCH_PLAN.md` - Detailed test plan
- `README.md` - DDS/CORDIC unit tests
- `TEST_VERIFICATION_REPORT.md` - Unit test results

### External References

- [JESD204B Specification](https://www.jedec.org/standards-documents/docs/jesd204b)
- [AXI4-Lite Specification](https://developer.arm.com/architectures/system-architectures/amba/amba-specifications)
- [AD9144 Datasheet](https://www.analog.com/en/products/ad9144.html)

## License

This testbench follows the same licensing as the parent HDL repository.

---

**Last Updated**: November 2025  
**Status**: ✅ All tests passing  
**Maintainer**: System Integration Team
