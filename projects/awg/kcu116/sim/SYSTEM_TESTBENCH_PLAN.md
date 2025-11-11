# System-Level Testbench Plan for AWG KCU116

**Date**: November 12, 2025  
**Scope**: End-to-end integration testing from MicroBlaze to JESD204 TX  
**Objective**: Verify complete data flow without simulating IP cores (MicroBlaze, DDR4, GTH transceivers)

---

## System Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           system_top                                     │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │                       system_wrapper (Block Design)                 │  │
│  │                                                                      │  │
│  │  ┌──────────────┐         AXI4-Lite Interconnect                   │  │
│  │  │  MicroBlaze  │◄────────────┬─────────────┬────────────┬────────►│  │
│  │  │   (Skip)     │             │             │            │         │  │
│  │  └──────────────┘             │             │            │         │  │
│  │                                │             │            │         │  │
│  │  ┌──────────────┐         ┌───▼─────┐  ┌───▼──────┐ ┌──▼────────┐│  │
│  │  │   DDR4       │◄────────│ DMA     │  │ JESD TX  │ │ TPL DAC   ││  │
│  │  │   (Model)    │         │ AXI     │  │  Link    │ │ (DDS)     ││  │
│  │  └──────────────┘         │ DMAC    │  │  Layer   │ │           ││  │
│  │                           │         │  │          │ │           ││  │
│  │                           └────┬────┘  └────┬─────┘ └─────┬─────┘│  │
│  │                                │            │             │       │  │
│  │                           ┌────▼────────────▼─────────────▼─────┐ │  │
│  │                           │     DAC FIFO (util_dacfifo)         │ │  │
│  │                           └──────────────────────────────────────┘ │  │
│  │                                                                      │  │
│  │  ┌──────────────────────────────────────────────────────────────┐  │  │
│  │  │  PHY Layer: axi_adxcvr + util_adxcvr                        │  │  │
│  │  │  (GTH Transceivers - Skip detailed simulation)               │  │  │
│  │  └──────────────────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Memory Map (from awg_bd.tcl)

| Component | Base Address | Function |
|-----------|--------------|----------|
| `axi_ad9144_xcvr` | 0x44A6_0000 | PHY layer control (GTH transceiver config) |
| `axi_ad9144_tpl` | 0x44A0_4000 | Transport layer (DDS, data pattern generation) |
| `axi_ad9144_jesd` | 0x44A9_0000 | Link layer (JESD204B protocol) |
| `axi_ad9144_dma` | 0x7C42_0000 | DMA controller (memory to DAC FIFO) |

### Interrupt Map
- **IRQ 10/15**: `axi_ad9144_jesd/irq` - JESD link events
- **IRQ 12/13**: `axi_ad9144_dma/irq` - DMA transfer complete

---

## Test Strategy

### What We CAN Test (Integration Focus)
✅ **AXI4-Lite Register Access** - Write/Read to all peripherals  
✅ **DMA Data Flow** - Memory → DAC FIFO → Transport Layer  
✅ **JESD204 Link Layer** - Link initialization, sync detection  
✅ **Transport Layer (DDS)** - Data generation and formatting  
✅ **DAC FIFO** - Buffering and clock domain crossing  
✅ **Control Flow** - GPIO, SPI, configuration sequences  
✅ **Interrupt Generation** - DMA complete, JESD events  

### What We SKIP (IP Core Internals)
❌ **MicroBlaze Execution** - Use BFM (Bus Functional Model)  
❌ **DDR4 Controller** - Use simplified memory model  
❌ **GTH Transceiver Details** - Abstract PHY layer  
❌ **XDMA/PCIe** - Not present in this design  

---

## Testbench Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                    system_top_tb.v (Top Testbench)                       │
│                                                                            │
│  ┌────────────────┐         ┌────────────────────────────────────────┐   │
│  │  AXI4-Lite     │         │         Clock & Reset                  │   │
│  │  Master BFM    │──AXI───►│         Generation                     │   │
│  │  (MicroBlaze   │         │         - sys_clk: 100 MHz            │   │
│  │   replacement) │         │         - tx_ref_clk: 125/250 MHz     │   │
│  └────────────────┘         │         - tx_sysref: JESD SYSREF      │   │
│                              └────────────────────────────────────────┘   │
│  ┌────────────────┐                                                      │
│  │  DDR4 Memory   │                                                      │
│  │  Model (Simple)│◄─────AXI4────────┐                                  │
│  └────────────────┘                  │                                  │
│                                       │                                  │
│  ┌────────────────────────────────────▼──────────────────────────────┐  │
│  │                      system_top (DUT)                             │  │
│  │                                                                    │  │
│  │  - Full system_wrapper instantiation                              │  │
│  │  - All AXI interconnects                                           │  │
│  │  - JESD204 TX chain                                                │  │
│  │  - DMA and FIFOs                                                   │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                       │                                  │
│  ┌────────────────────────────────────▼──────────────────────────────┐  │
│  │  AD9144 DAC Model                                                  │  │
│  │  - JESD204B receiver                                               │  │
│  │  - SYNC generation                                                 │  │
│  │  - Data capture and verification                                   │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  Test Sequencer                                                   │   │
│  │  1. Reset sequence                                                 │   │
│  │  2. Configure JESD link (write registers)                          │   │
│  │  3. Configure DDS tones                                            │   │
│  │  4. Setup DMA transfer                                             │   │
│  │  5. Wait for link sync                                             │   │
│  │  6. Verify data on JESD TX lanes                                   │   │
│  │  7. Check interrupts                                               │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Test Scenarios

### Scenario 1: Register Access Test ✓ Basic
**Objective**: Verify AXI4-Lite connectivity to all peripherals

**Steps**:
1. Write/Read SCRATCH registers in all peripherals
2. Verify VERSION registers match expected values
3. Check all address decoding works correctly

**Expected Results**:
- All writes return `OKAY` response
- Reads return written values (for R/W registers)
- No AXI protocol violations

---

### Scenario 2: JESD Link Initialization ✓ Critical
**Objective**: Verify JESD204B link can be configured and brought up

**Steps**:
1. Configure `axi_ad9144_jesd` link parameters:
   - Lanes: `NUM_LANES` (from design)
   - M, L, S, NP parameters
   - Scrambling enable
2. Configure `axi_ad9144_xcvr` PHY:
   - Lane enables
   - Reference clock settings
3. Enable link and wait for SYNC assertion
4. Monitor link state machine transitions
5. Check interrupt generation

**Expected Results**:
- Link transitions through CGS → ILAS → DATA states
- SYNC goes high (AD9144 asserts SYNC)
- No lane errors reported
- JESD interrupt fires on sync event

**Register Sequence** (from axi_jesd204_tx_regmap_tb.v):
```
0x200: Lane enable mask
0x210: Octets per frame, frames per multiframe
0x218: Link enable mask
0x240: Scrambler enable, char replacement
0xC0:  Reset control
```

---

### Scenario 3: DDS Pattern Generation ✓ Integration
**Objective**: Verify transport layer can generate test patterns

**Steps**:
1. Configure `axi_ad9144_tpl` DDS:
   - DDS mode (vs DMA mode)
   - Tone 1 and Tone 2 frequencies
   - Amplitude scaling
2. Enable DAC channels
3. Capture data from JESD TX lanes
4. Verify frequency content matches configuration

**Expected Results**:
- JESD lanes output non-zero data
- FFT of captured data shows expected tones
- No underflow errors (DAC_DUNF = 0)

**TPL Registers** (from ad_ip_jesd204_tpl_dac docs):
```
0x40: DAC channel control (enable, DDS select)
0x44: DDS tone 1 frequency word
0x48: DDS tone 1 scale
0x4C: DDS tone 2 frequency word
0x50: DDS tone 2 scale
```

---

### Scenario 4: DMA Transfer ✓ End-to-End
**Objective**: Full data path from DDR4 → DMA → FIFO → JESD → DAC

**Steps**:
1. Initialize DDR4 memory model with known pattern
2. Configure `axi_ad9144_dma`:
   - Source address (DDR4)
   - Transfer length
   - Enable cyclic mode
3. Start DMA transfer
4. Monitor FIFO levels
5. Capture JESD output
6. Verify data integrity
7. Check DMA interrupt

**Expected Results**:
- DMA reads from memory correctly
- Data appears on JESD lanes
- Captured pattern matches memory content
- DMA interrupt fires on completion
- No FIFO underflow/overflow

**DMA Registers** (from axi_dmac docs):
```
0x400: Control (enable, pause)
0x404: Transfer ID
0x408: Transfer submit
0x418: Source address (low 32 bits)
0x41C: Source address (high 32 bits)
0x420: Destination address
0x424: Transfer length
0x428: Flags (cyclic, last)
```

---

### Scenario 5: Clock Domain Crossing ✓ Robustness
**Objective**: Verify proper CDC through DAC FIFO

**Steps**:
1. Set up DMA transfer with sys_clk domain
2. DAC FIFO operates in link_clk domain
3. Vary clock phase relationships
4. Monitor for metastability or data corruption

**Expected Results**:
- No data corruption across clock domains
- FIFO read/write pointers maintain proper spacing
- No underflow/overflow under normal operation

---

### Scenario 6: Error Injection & Recovery ✓ Robustness
**Objective**: Test error handling and recovery mechanisms

**Error Cases**:
1. **FIFO Underflow**: Stop DMA while DAC running
2. **Link Desync**: Corrupt SYSREF timing
3. **AXI Protocol Error**: Invalid address access
4. **Lane Alignment Error**: Misaligned SYNC timing

**Expected Results**:
- Errors properly flagged in status registers
- Interrupts generated for critical errors
- System recoverable via register reset
- No system hang or lockup

---

## Implementation Files

### 1. Main Testbench: `system_top_tb.v`
```verilog
`timescale 1ns/1ps

module system_top_tb;
  // Clock generation
  // Reset sequencing
  // AXI4-Lite BFM instantiation
  // system_top DUT instantiation
  // AD9144 model instantiation
  // Test scenarios
endmodule
```

### 2. AXI4-Lite Master BFM: `axi4_lite_master_bfm.v`
```verilog
module axi4_lite_master_bfm (
  input axi_aclk,
  input axi_aresetn,
  // AXI4-Lite master interface
  // Task interfaces for write/read
);
  task axi_write(input [31:0] addr, input [31:0] data);
  task axi_read(input [31:0] addr, output [31:0] data);
endmodule
```

### 3. DDR4 Memory Model: `ddr4_simple_model.v`
```verilog
module ddr4_simple_model (
  // Simplified AXI4 interface
  // Internal memory array
  // Basic read/write logic
);
endmodule
```

### 4. AD9144 DAC Model: `ad9144_model.v`
```verilog
module ad9144_model (
  // JESD204B receiver
  // SYNC generation logic
  // Data capture and checking
  input [3:0] tx_data_p, tx_data_n,
  output [1:0] tx_sync_p, tx_sync_n,
  input tx_sysref
);
endmodule
```

### 5. Test Sequences: `test_sequences.vh`
```verilog
// Register addresses
`define JESD_BASE 32'h44A90000
`define TPL_BASE  32'h44A04000
`define DMA_BASE  32'h7C420000
`define XCVR_BASE 32'h44A60000

// Common test tasks
task jesd_link_init();
task dds_configure();
task dma_setup();
```

### 6. Checker Modules: `protocol_checkers.v`
```verilog
// AXI4-Lite protocol checker
// JESD204B link state monitor
// Data integrity checker
```

---

## Simulation Environment

### Tools Required
1. **Vivado Simulator (xsim)** - For Xilinx primitives (IBUFDS, OBUFDS, etc.)
2. **GTKWave** - Waveform viewing
3. **Python** - Post-processing and analysis
4. **Makefile** - Build automation

### Compilation Strategy
```makefile
# Use Vivado xsim for full system simulation
xvlog -sv system_top_tb.v
xvlog system_top.v
xvlog system_wrapper.v  # Generated from block design
xelab -debug all system_top_tb -s system_top_sim
xsim system_top_sim -runall
```

### Block Design Handling
The `system_wrapper.v` is generated from the Vivado block design. We have two options:

**Option A**: Generate wrapper from existing design
```tcl
open_project kcu116.xpr
open_bd_design system_bd.bd
make_wrapper -files [get_files system_bd.bd] -top
```

**Option B**: Stub out complex IPs for simulation
- Replace MicroBlaze with AXI BFM
- Replace DDR4 controller with simple model
- Keep JESD204 and DMA as-is (they're synthesizable RTL)

---

## Metrics & Success Criteria

### Coverage Goals
- ✅ All AXI registers accessed at least once
- ✅ All JESD link states exercised
- ✅ Both DDS and DMA modes tested
- ✅ All interrupt sources verified
- ✅ Error injection for each error type

### Performance Targets
- Link initialization: < 10 ms (simulation time)
- DMA throughput: Match calculated bandwidth
- FIFO utilization: Stay within 20-80% range

### Verification Checkpoints
1. ✓ AXI protocol compliance (no violations)
2. ✓ JESD204B link state machine correct
3. ✓ Data integrity end-to-end
4. ✓ Interrupt timing accurate
5. ✓ No race conditions or deadlocks
6. ✓ Clock domain crossing safe

---

## Challenges & Mitigation

### Challenge 1: Block Design Complexity
**Issue**: Vivado block design includes many auto-generated connections

**Mitigation**:
- Export block design as HDL wrapper
- Use Vivado simulator (xsim) for native support
- Simplify by removing unused peripherals in testbench

### Challenge 2: GTH Transceiver Simulation
**Issue**: GTH transceivers are complex and slow to simulate

**Mitigation**:
- Abstract PHY layer for most tests
- Use behavioral models for SERDES
- Focus on parallel data interface, not serial

### Challenge 3: Timing Closure in Simulation
**Issue**: Real timing not modeled in RTL simulation

**Mitigation**:
- Use conservative delays
- Focus on functional correctness
- Rely on Vivado implementation for timing

### Challenge 4: Memory Model Complexity
**Issue**: Full DDR4 controller simulation is very slow

**Mitigation**:
- Use simplified AXI4 memory model
- Parameterized latency for realism
- Skip DDR4 protocol details

---

## Development Phases

### Phase 1: Infrastructure (Week 1) ✓ Priority 1
- [ ] Create testbench skeleton
- [ ] Implement AXI4-Lite BFM
- [ ] Build simple memory model
- [ ] Get basic compilation working

### Phase 2: Register Tests (Week 1-2) ✓ Priority 1
- [ ] Test AXI connectivity
- [ ] Verify register map
- [ ] Check reset behavior

### Phase 3: JESD Link (Week 2-3) ✓ Priority 2
- [ ] Implement AD9144 model (simplified)
- [ ] Test link initialization
- [ ] Verify state machine
- [ ] Capture lane data

### Phase 4: DDS Mode (Week 3) ✓ Priority 2
- [ ] Configure DDS tones
- [ ] Verify output patterns
- [ ] FFT analysis

### Phase 5: DMA Mode (Week 4) ✓ Priority 3
- [ ] End-to-end DMA test
- [ ] Data integrity checks
- [ ] Performance measurement

### Phase 6: Error Testing (Week 4-5) ✓ Priority 3
- [ ] Inject various errors
- [ ] Verify recovery
- [ ] Stress testing

---

## Acceptance Criteria

For the system testbench to be considered complete:

1. ✅ All 6 test scenarios pass
2. ✅ Zero AXI protocol violations
3. ✅ JESD link achieves DATA state
4. ✅ Data integrity verified end-to-end
5. ✅ All interrupts fire correctly
6. ✅ Error cases handled gracefully
7. ✅ Documentation complete with waveforms
8. ✅ Reusable for future development

---

## Next Steps

**Immediate Actions**:
1. Review this plan and get approval
2. Set up Vivado simulation environment
3. Generate system_wrapper from block design
4. Create skeleton testbench
5. Implement AXI4-Lite BFM first

**Questions to Resolve**:
1. Do you want to use Vivado xsim or try with Verilator/Icarus?
2. Should we generate system_wrapper or create manual stubs?
3. What's the priority order of test scenarios?
4. Any specific test cases from your use case?

---

**Ready to proceed?** Let me know if you want me to start implementing Phase 1!
