// Test Sequences and Common Definitions for AWG System Testbench
// 
// This file contains:
// - Register address definitions (memory map)
// - Common test tasks and sequences
// - JESD204 link initialization procedures
// - DDS configuration tasks
//
// Author: System Testbench Implementation
// Date: November 2025

`ifndef TEST_SEQUENCES_VH
`define TEST_SEQUENCES_VH

//=============================================================================
// MEMORY MAP - Base Addresses (from awg_bd.tcl and SYSTEM_TESTBENCH_PLAN.md)
//=============================================================================

`define XCVR_BASE   32'h44A6_0000  // axi_ad9144_xcvr  - PHY layer
`define TPL_BASE    32'h44A0_4000  // axi_ad9144_tpl   - Transport layer (DDS)
`define JESD_BASE   32'h44A9_0000  // axi_ad9144_jesd  - Link layer
`define DMA_BASE    32'h7C42_0000  // axi_ad9144_dma   - DMA controller

//=============================================================================
// JESD204 Link Layer Registers (relative to JESD_BASE)
//=============================================================================

`define JESD_REG_VERSION           32'h0000
`define JESD_REG_ID                32'h0004
`define JESD_REG_SCRATCH           32'h0008
`define JESD_REG_MAGIC             32'h000C
`define JESD_REG_SYNTH_NUM_LANES   32'h0010
`define JESD_REG_SYNTH_DATA_PATH_WIDTH 32'h0014

`define JESD_REG_IRQ_ENABLE        32'h0080
`define JESD_REG_IRQ_PENDING       32'h0084
`define JESD_REG_IRQ_SOURCE        32'h0088

`define JESD_REG_LINK_DISABLE      32'h00C0
`define JESD_REG_LINK_STATE        32'h00C4
`define JESD_REG_LINK_CLK_RATIO    32'h00C8

`define JESD_REG_SYSREF_CONF       32'h0100
`define JESD_REG_SYSREF_LMFC_OFFSET 32'h0104
`define JESD_REG_SYSREF_STATUS     32'h0108

`define JESD_REG_LANES_ENABLE      32'h0200
`define JESD_REG_LINK_CONF0        32'h0210  // Octets per frame
`define JESD_REG_LINK_CONF1        32'h0214  // Multi-frame config
`define JESD_REG_LINK_CONF2        32'h0218  // Link enable
`define JESD_REG_LINK_CONF4        32'h021C  // Multi-link config

`define JESD_REG_LINK_STATUS       32'h0280

//=============================================================================
// Transport Layer (TPL/DDS) Registers (relative to TPL_BASE)
//=============================================================================

`define TPL_REG_VERSION            32'h0000
`define TPL_REG_ID                 32'h0004
`define TPL_REG_SCRATCH            32'h0008
`define TPL_REG_MAGIC              32'h000C

`define TPL_REG_SYNC_CONTROL       32'h0040
`define TPL_REG_CONFIG             32'h0044

// DAC Common registers
`define TPL_REG_RSTN               32'h0040
`define TPL_REG_CNTRL_1            32'h0044
`define TPL_REG_CNTRL_2            32'h0048

// Per-channel registers (channel 0 as example, stride = 0x40)
`define TPL_REG_CHAN_CNTRL_1(ch)   (32'h0400 + (ch * 32'h40) + 32'h00)
`define TPL_REG_CHAN_CNTRL_2(ch)   (32'h0400 + (ch * 32'h40) + 32'h04)
`define TPL_REG_CHAN_CNTRL_3(ch)   (32'h0400 + (ch * 32'h40) + 32'h08)
`define TPL_REG_CHAN_CNTRL_7(ch)   (32'h0400 + (ch * 32'h40) + 32'h0C)

// DDS frequency and scale registers
`define TPL_REG_CHAN_CNTRL_1_IQCOR_ENB         32'h00000001
`define TPL_REG_CHAN_CNTRL_2_DDS_SEL           32'h00000000  // DDS mode
`define TPL_REG_CHAN_CNTRL_2_DMA_SEL           32'h00000001  // DMA mode

//=============================================================================
// DMA Registers (relative to DMA_BASE)
//=============================================================================

`define DMA_REG_VERSION            32'h0000
`define DMA_REG_PERIPHERAL_ID      32'h0004
`define DMA_REG_SCRATCH            32'h0008
`define DMA_REG_ID                 32'h000C

`define DMA_REG_IRQ_MASK           32'h0080
`define DMA_REG_IRQ_PENDING        32'h0084
`define DMA_REG_IRQ_SOURCE         32'h0088

`define DMA_REG_CTRL               32'h0400
`define DMA_REG_TRANSFER_ID        32'h0404
`define DMA_REG_TRANSFER_SUBMIT    32'h0408
`define DMA_REG_FLAGS              32'h040C

`define DMA_REG_DEST_ADDRESS       32'h0410
`define DMA_REG_DEST_STRIDE        32'h0414
`define DMA_REG_SRC_ADDRESS        32'h0418
`define DMA_REG_SRC_STRIDE         32'h041C

`define DMA_REG_X_LENGTH           32'h0418
`define DMA_REG_Y_LENGTH           32'h041C

`define DMA_REG_DEST_ADDRESS_HIGH  32'h041C
`define DMA_REG_SRC_ADDRESS_HIGH   32'h0420

// DMA Control bits
`define DMA_CTRL_ENABLE            32'h00000001
`define DMA_CTRL_PAUSE             32'h00000002

// DMA Flags
`define DMA_FLAG_CYCLIC            32'h00000001
`define DMA_FLAG_LAST              32'h00000002

//=============================================================================
// XCVR (PHY Layer) Registers (relative to XCVR_BASE)
//=============================================================================

`define XCVR_REG_VERSION           32'h0000
`define XCVR_REG_ID                32'h0004
`define XCVR_REG_SCRATCH           32'h0008
`define XCVR_REG_MAGIC             32'h000C

`define XCVR_REG_RESETN            32'h0010
`define XCVR_REG_STATUS            32'h0014
`define XCVR_REG_CONTROL           32'h0020

//=============================================================================
// JESD204 Link State Machine States
//=============================================================================

`define JESD_STATE_RESET           3'h0
`define JESD_STATE_WAIT            3'h1
`define JESD_STATE_CGS             3'h2  // Code Group Sync
`define JESD_STATE_ILAS            3'h3  // Initial Lane Alignment
`define JESD_STATE_DATA            3'h4  // User Data

//=============================================================================
// Test Constants
//=============================================================================

`define MAGIC_VALUE                32'h5AFE_0001  // Expected magic for JESD/TPL
`define TEST_PATTERN               32'hDEAD_BEEF
`define TIMEOUT_CYCLES             10000

`endif // TEST_SEQUENCES_VH
