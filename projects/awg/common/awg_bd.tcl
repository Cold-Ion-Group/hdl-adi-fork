# modified by Prerna Baranwal for the cold ion group 
# dac connection is used here from the link: https://wiki.analog.com/resources/eval/user-guides/ad-dac-fmc-ebz 
#
# Parameter description:
#   JESD_M : Number of converters per link
#   JESD_L : Number of lanes per link
#   JESD_S : Number of samples per frame
#

source $ad_hdl_dir/library/jesd204/scripts/jesd204.tcl


# JESD204B interface configurations

set JESD_M    $ad_project_params(JESD_M)
set JESD_L    $ad_project_params(JESD_L)
set NUM_LINKS $ad_project_params(NUM_LINKS)
set NUM_OF_CONVERTERS [expr $NUM_LINKS * $JESD_M]
set NUM_OF_LANES [expr $NUM_LINKS * $JESD_L]
set SAMPLES_PER_FRAME $ad_project_params(JESD_S)
set SAMPLE_WIDTH $ad_project_params(JESD_NP)

# K (FRAMES_PER_MULTIFRAME) is NOT a build-time IP parameter in this codebase.
# The axi_jesd204_tx / jesd204_tx cores have no CONFIG.FRAMES_PER_MULTIFRAME
# synthesis parameter.  K=32, subclass=1, and all other link-layer settings are
# programmed exclusively through the AXI register interface at runtime by firmware
# (JESD TX AXI base 0x44A90000, registers CONF0/CONF1).
# Reference: library/jesd204/scripts/jesd204.tcl  adi_axi_jesd204_tx_create

set DAC_DATA_WIDTH [expr $NUM_OF_LANES * 32]
set SAMPLES_PER_CHANNEL [expr $DAC_DATA_WIDTH / $NUM_OF_CONVERTERS / $SAMPLE_WIDTH] 
set MAX_NUM_OF_LANES 8

# Transceiver clocking (override via environment)
set awg_qpll_enable [get_env_param AWG_QPLL_ENABLE 1]
set awg_qpll_refclk_div [get_env_param AWG_QPLL_REFCLK_DIV 1]
set awg_qpll_fbdiv [get_env_param AWG_QPLL_FBDIV 20]
set awg_tx_out_div [get_env_param AWG_TX_OUT_DIV 1]
set awg_enable_c1 [get_env_param AWG_ENABLE_C1 1]
# Top level ports

create_bd_port -dir I dac_fifo_bypass

# SFP0 GT pins for the Phase E.2 10G Ethernet dataplane.  The low-speed
# module/status/control pins are handled in system_top.v via spare AXI GPIO bits.
create_bd_port -dir I sfp0_ref_clk_p
create_bd_port -dir I sfp0_ref_clk_n
create_bd_port -dir I sfp0_rx_p
create_bd_port -dir I sfp0_rx_n
create_bd_port -dir O sfp0_tx_p
create_bd_port -dir O sfp0_tx_n

# dac peripherals
# JESD204 PHY layer peripheral
ad_ip_instance axi_adxcvr axi_ad9144_xcvr [list \
 NUM_OF_LANES $NUM_OF_LANES \
  QPLL_ENABLE $awg_qpll_enable \
  TX_OR_RX_N 1 \
]

# =============================================================================
# JESD204 link layer peripheral
# adi_axi_jesd204_tx_create creates a hierarchy containing:
#   - axi_jesd204_tx  (AXI register interface, base 0x44A90000)
#   - jesd204_tx      (link layer core, LMFC/sysref capture logic)
# All link parameters (K, subclass, etc.) are runtime AXI register fields.
# =============================================================================
adi_axi_jesd204_tx_create axi_ad9144_jesd $NUM_OF_LANES $NUM_LINKS

# =============================================================================
# JESD204 transport layer peripheral
# TPL hierarchy interface contract (created by adi_tpl_jesd204_tx_create):
#   AXI-exposed control plane (CPU-visible @ 0x44A04000):
#     - axi_ad9144_tpl/s_axi_aclk
#     - axi_ad9144_tpl/s_axi_aresetn
#     - axi_ad9144_tpl/s_axi              (AXI4-Lite slave)
#   Streaming/data-plane interfaces (external to hierarchy, not register control):
#     - axi_ad9144_tpl/link_clk
#     - axi_ad9144_tpl/link               (AXIS toward JESD TX link layer)
#     - axi_ad9144_tpl/dac_dunf
#     - axi_ad9144_tpl/dac_enable_<i>, axi_ad9144_tpl/dac_valid_<i>, axi_ad9144_tpl/dac_data_<i>
#   Extended scheduled-control pins exported at hierarchy boundary:
#     - sched_scale_s / sched_init_s / sched_incr_s / sched_apply_s
#     - sched_phase_reinit
#   Scheduler epoch anchor input:
#     - sysref_pulse (from jesd_sysref_sync)
adi_tpl_jesd204_tx_create axi_ad9144_tpl $NUM_OF_LANES \
                                         $NUM_OF_CONVERTERS \
                                         $SAMPLES_PER_FRAME \
                                         $SAMPLE_WIDTH \

# 32-bit DDS phase width → ≤ 0.25 Hz frequency resolution at 983 MSPS
# The TPL core is wrapped in a hierarchy; the actual IP is at .../dac_tpl_core
ad_ip_parameter axi_ad9144_tpl/dac_tpl_core CONFIG.DDS_PHASE_DW 32
ad_ip_parameter axi_ad9144_tpl/dac_tpl_core CONFIG.EXT_SYNC 1

ad_ip_instance util_upack2 axi_ad9144_upack [list \
  NUM_OF_CHANNELS $NUM_OF_CONVERTERS \
  SAMPLES_PER_CHANNEL $SAMPLES_PER_CHANNEL \
  SAMPLE_DATA_WIDTH $SAMPLE_WIDTH \
]

set dac_dma_data_width $DAC_DATA_WIDTH


ad_ip_instance axi_dmac axi_ad9144_dma [list \
  DMA_TYPE_SRC 0 \
  DMA_TYPE_DEST 1 \
  AXI_SLICE_SRC 0 \
  AXI_SLICE_DEST 0 \
  DMA_LENGTH_WIDTH 24 \
  DMA_2D_TRANSFER 0 \
  CYCLIC 1 \
  ID 1\
  DMA_DATA_WIDTH_SRC 64 \
  DMA_DATA_WIDTH_DEST $DAC_DATA_WIDTH \
]

ad_ip_instance axi_dmac axi_sched_dma [list \
  DMA_TYPE_SRC 0 \
  DMA_TYPE_DEST 1 \
  AXI_SLICE_SRC 1 \
  AXI_SLICE_DEST 1 \
  DMA_LENGTH_WIDTH 24 \
  DMA_2D_TRANSFER 0 \
  CYCLIC 0 \
  ID 2 \
  DMA_DATA_WIDTH_SRC 256 \
  DMA_DATA_WIDTH_DEST 256 \
  MAX_BYTES_PER_BURST 128 \
  DMA_AXI_PROTOCOL_SRC 1 \
]

ad_ip_instance xxv_ethernet eth_mac_10g
ad_ip_parameter eth_mac_10g CONFIG.LINE_RATE 10
ad_ip_parameter eth_mac_10g CONFIG.NUM_OF_CORES 1
ad_ip_parameter eth_mac_10g CONFIG.CORE {Ethernet MAC+PCS/PMA 64-bit}
ad_ip_parameter eth_mac_10g CONFIG.BASE_R_KR {BASE-R}
ad_ip_parameter eth_mac_10g CONFIG.GT_REF_CLK_FREQ 156.25
ad_ip_parameter eth_mac_10g CONFIG.GT_DRP_CLK 100.00
ad_ip_parameter eth_mac_10g CONFIG.INCLUDE_AXI4_INTERFACE 1
ad_ip_parameter eth_mac_10g CONFIG.INCLUDE_USER_FIFO 1
ad_ip_parameter eth_mac_10g CONFIG.INCLUDE_STATISTICS_COUNTERS 1

# SFP0 lane selection verified against UG1239 v1.3 Tables 3-8 and 3-10.
# The matching package pins are constrained in kcu116/sfp0_system_constr.xdc.
ad_ip_parameter eth_mac_10g CONFIG.GT_GROUP_SELECT Quad_X0Y1
ad_ip_parameter eth_mac_10g CONFIG.LANE1_GT_LOC X0Y4

ad_ip_instance axi_dmac axi_eth_rx_dma [list \
  DMA_TYPE_SRC 1 \
  DMA_TYPE_DEST 0 \
  AXI_SLICE_SRC 1 \
  AXI_SLICE_DEST 1 \
  DMA_LENGTH_WIDTH 24 \
  DMA_2D_TRANSFER 0 \
  CYCLIC 0 \
  ID 3 \
  DMA_DATA_WIDTH_SRC 64 \
  DMA_DATA_WIDTH_DEST 256 \
  MAX_BYTES_PER_BURST 128 \
  DMA_AXI_PROTOCOL_DEST 1 \
]

ad_ip_instance axi_dmac axi_eth_tx_dma [list \
  DMA_TYPE_SRC 0 \
  DMA_TYPE_DEST 1 \
  AXI_SLICE_SRC 1 \
  AXI_SLICE_DEST 1 \
  DMA_LENGTH_WIDTH 24 \
  DMA_2D_TRANSFER 0 \
  CYCLIC 0 \
  ID 4 \
  DMA_DATA_WIDTH_SRC 256 \
  DMA_DATA_WIDTH_DEST 64 \
  MAX_BYTES_PER_BURST 128 \
  DMA_AXI_PROTOCOL_SRC 1 \
]

ad_ip_instance xlconstant eth_axis_zero_1
ad_ip_parameter eth_axis_zero_1 CONFIG.CONST_WIDTH 1
ad_ip_parameter eth_axis_zero_1 CONFIG.CONST_VAL 0

ad_ip_instance xlconstant eth_axis_zero_4
ad_ip_parameter eth_axis_zero_4 CONFIG.CONST_WIDTH 4
ad_ip_parameter eth_axis_zero_4 CONFIG.CONST_VAL 0

ad_ip_instance xlconstant eth_axis_zero_8
ad_ip_parameter eth_axis_zero_8 CONFIG.CONST_WIDTH 8
ad_ip_parameter eth_axis_zero_8 CONFIG.CONST_VAL 0

ad_ip_instance xlconstant eth_axis_zero_56
ad_ip_parameter eth_axis_zero_56 CONFIG.CONST_WIDTH 56
ad_ip_parameter eth_axis_zero_56 CONFIG.CONST_VAL 0

ad_ip_instance xlconstant eth_gt_outclksel
ad_ip_parameter eth_gt_outclksel CONFIG.CONST_WIDTH 3
ad_ip_parameter eth_gt_outclksel CONFIG.CONST_VAL 4









set dac_dma_data_width $DAC_DATA_WIDTH 
ad_dacfifo_create axi_dac_fifo \
                  $DAC_DATA_WIDTH \
                  $dac_dma_data_width \
                  $dac_fifo_address_width



ad_ip_instance util_adxcvr util_awg_xcvr [list \
  RX_NUM_OF_LANES 0 \
  TX_NUM_OF_LANES $MAX_NUM_OF_LANES \
  TX_LANE_INVERT [expr 0x00] \
  QPLL_REFCLK_DIV $awg_qpll_refclk_div \
  QPLL_FBDIV_RATIO 1 \
  QPLL_FBDIV $awg_qpll_fbdiv \
  TX_OUT_DIV $awg_tx_out_div \
]

ad_connect  $sys_cpu_resetn util_awg_xcvr/up_rstn
ad_connect  $sys_cpu_clk util_awg_xcvr/up_clk

# reference clocks & resets


for {set i 0} {$i < $MAX_NUM_OF_LANES} {incr i} {
  if {$i % 4 == 0} {
    create_bd_port -dir I tx_ref_clk_${i}
    ad_xcvrpll tx_ref_clk_${i} util_awg_xcvr/qpll_ref_clk_${i}
    set quad_ref_clk tx_ref_clk_${i}
  }
  ad_xcvrpll $quad_ref_clk util_awg_xcvr/cpll_ref_clk_${i}
}







ad_xcvrpll  axi_ad9144_xcvr/up_pll_rst util_awg_xcvr/up_qpll_rst_*
ad_xcvrpll  axi_ad9144_xcvr/up_pll_rst util_awg_xcvr/up_cpll_rst_*


ad_xcvrcon  util_awg_xcvr axi_ad9144_xcvr axi_ad9144_jesd {} {} {} $MAX_NUM_OF_LANES

# Synchronize SYSREF and SYNC~ into the device clock domain.
create_bd_cell -type module -reference jesd_sysref_sync jesd_sysref_sync
set_property -dict [list \
  CONFIG.SYNC_WIDTH $NUM_LINKS \
  CONFIG.ARM_DELAY_CYCLES 0 \
] [get_bd_cells jesd_sysref_sync]

ad_connect util_awg_xcvr/tx_out_clk_0 jesd_sysref_sync/device_clk
ad_connect axi_ad9144_jesd_rstgen/peripheral_reset jesd_sysref_sync/reset

set sysref_net [get_bd_nets -quiet -of_objects [get_bd_pins axi_ad9144_jesd/sysref]]
if {$sysref_net ne ""} {
  disconnect_bd_net $sysref_net [get_bd_pins axi_ad9144_jesd/sysref]
}

set sync_net [get_bd_nets -quiet -of_objects [get_bd_pins axi_ad9144_jesd/sync]]
if {$sync_net ne ""} {
  disconnect_bd_net $sync_net [get_bd_pins axi_ad9144_jesd/sync]
}

ad_connect tx_sysref_0 jesd_sysref_sync/sysref_in
ad_connect tx_sync_0 jesd_sysref_sync/sync_in
ad_connect jesd_sysref_sync/sysref_pulse axi_ad9144_jesd/sysref
ad_connect jesd_sysref_sync/sync_out axi_ad9144_jesd/sync

ad_ip_instance awg_timed_ctrl awg_timed_ctrl_0 [list \
  NUM_CHANNELS $NUM_OF_CONVERTERS \
  DDS_PHASE_DW 32 \
]

# A single address-stable extension block supports two build variants.
# AWG_ENABLE_C1=0 prunes the decoder datapath while retaining discovery and
# direct pass-through; AWG_ENABLE_C1=1 adds the runtime-selectable C1 decoder.
ad_ip_instance awg_extension awg_extension_0 [list \
  C1_IMPLEMENTED $awg_enable_c1 \
]

ad_connect sys_cpu_clk awg_timed_ctrl_0/s_axi_aclk
ad_connect sys_cpu_resetn awg_timed_ctrl_0/s_axi_aresetn
ad_connect sys_cpu_clk awg_extension_0/s_axi_aclk
ad_connect sys_cpu_resetn awg_extension_0/s_axi_aresetn
ad_connect awg_extension_0/extension_error awg_timed_ctrl_0/extension_error
ad_connect awg_extension_0/extension_error_toggle awg_timed_ctrl_0/extension_error_toggle
ad_connect util_awg_xcvr/tx_out_clk_0 awg_timed_ctrl_0/sched_clk
ad_connect axi_ad9144_jesd_rstgen/peripheral_reset awg_timed_ctrl_0/sched_reset
ad_connect jesd_sysref_sync/sysref_pulse awg_timed_ctrl_0/sysref_pulse

create_bd_port -dir O marker_commit
ad_connect marker_commit awg_timed_ctrl_0/marker_commit

# Measurement-only coherent event bundle.  Package-pin selection belongs to
# the verified 1.8-V FMC interposer XDC and is intentionally not guessed here.
create_bd_port -dir O event_toggle
create_bd_port -dir O epoch
create_bd_port -dir O -from 15 -to 0 event_seq_gray
create_bd_port -dir O awg_error
create_bd_port -dir O error_toggle
ad_connect event_toggle awg_timed_ctrl_0/event_toggle
ad_connect epoch awg_timed_ctrl_0/epoch
ad_connect event_seq_gray awg_timed_ctrl_0/event_seq_gray
ad_connect awg_error awg_timed_ctrl_0/awg_error
ad_connect error_toggle awg_timed_ctrl_0/error_toggle

# marker_start and marker_done are available for scope probing but are not
# routed to top-level pins by default.  Add create_bd_port / XDC constraints
# here when lab probing of execution boundaries is needed.

# Connect awg_timed_ctrl_0 interrupt into the CPU interrupt fabric.
# Uses mb-14 / ps-11 (adjacent to the JESD and DMA interrupts at mb-15/13).
ad_cpu_interrupt ps-11 mb-14 awg_timed_ctrl_0/irq

ad_connect  util_awg_xcvr/tx_out_clk_0 axi_ad9144_tpl/link_clk
ad_connect  axi_ad9144_jesd/tx_data axi_ad9144_tpl/link
ad_connect awg_timed_ctrl_0/sched_scale_s axi_ad9144_tpl/sched_scale_s
ad_connect awg_timed_ctrl_0/sched_init_s axi_ad9144_tpl/sched_init_s
ad_connect awg_timed_ctrl_0/sched_incr_s axi_ad9144_tpl/sched_incr_s
ad_connect awg_timed_ctrl_0/sched_apply_s axi_ad9144_tpl/sched_apply_s
ad_connect awg_timed_ctrl_0/sched_phase_reinit axi_ad9144_tpl/sched_phase_reinit
ad_connect  util_awg_xcvr/tx_out_clk_0 axi_ad9144_upack/clk
ad_connect  axi_ad9144_jesd_rstgen/peripheral_reset axi_ad9144_upack/reset
#ad_connect  axi_ad9144_tpl/dac_dunf axi_ad9144_upack/fifo_rd_underflow

ad_connect  axi_ad9144_tpl/dac_valid_0 axi_ad9144_upack/fifo_rd_en




for {set i 0} {$i < $NUM_OF_CONVERTERS} {incr i} {
  ad_connect  axi_ad9144_tpl/dac_enable_$i axi_ad9144_upack/enable_$i
  ad_connect  axi_ad9144_tpl/dac_data_$i axi_ad9144_upack/fifo_rd_data_$i
}


ad_connect util_awg_xcvr/tx_out_clk_0 axi_dac_fifo/dac_clk
ad_connect axi_ad9144_jesd_rstgen/peripheral_reset axi_dac_fifo/dac_rst
ad_connect axi_ad9144_upack/s_axis_valid VCC
ad_connect axi_ad9144_upack/s_axis_ready axi_dac_fifo/dac_valid
ad_connect axi_ad9144_upack/s_axis_data axi_dac_fifo/dac_data
ad_connect axi_ad9144_tpl/dac_dunf axi_dac_fifo/dac_dunf

ad_connect sys_cpu_clk axi_dac_fifo/dma_clk
ad_connect sys_cpu_reset axi_dac_fifo/dma_rst
ad_connect sys_cpu_clk axi_ad9144_dma/m_axis_aclk
ad_connect sys_cpu_resetn axi_ad9144_dma/m_src_axi_aresetn
ad_connect axi_dac_fifo/dma_xfer_req axi_ad9144_dma/m_axis_xfer_req
ad_connect axi_dac_fifo/dma_ready axi_ad9144_dma/m_axis_ready
ad_connect axi_dac_fifo/dma_data axi_ad9144_dma/m_axis_data

 
ad_connect axi_dac_fifo/dma_valid axi_ad9144_dma/m_axis_valid
ad_connect axi_dac_fifo/dma_xfer_last axi_ad9144_dma/m_axis_last

ad_connect sys_cpu_clk axi_sched_dma/m_axis_aclk
ad_connect sys_cpu_resetn axi_sched_dma/m_src_axi_aresetn
ad_connect axi_sched_dma/m_axis_data awg_extension_0/s_axis_tdata
ad_connect axi_sched_dma/m_axis_valid awg_extension_0/s_axis_tvalid
ad_connect axi_sched_dma/m_axis_ready awg_extension_0/s_axis_tready
ad_connect awg_extension_0/m_axis_tdata awg_timed_ctrl_0/dma_s_axis_tdata
ad_connect awg_extension_0/m_axis_tvalid awg_timed_ctrl_0/dma_s_axis_tvalid
ad_connect awg_extension_0/m_axis_tready awg_timed_ctrl_0/dma_s_axis_tready

# 10G Ethernet MAC, RX DMA, and TX DMA.
set eth_gt_rxp_pin [get_bd_pins -quiet eth_mac_10g/gt_rxp_in_0]
if {$eth_gt_rxp_pin eq ""} {
  set eth_gt_rxp_pin [get_bd_pins eth_mac_10g/gt_rxp_in]
}
set eth_gt_rxn_pin [get_bd_pins -quiet eth_mac_10g/gt_rxn_in_0]
if {$eth_gt_rxn_pin eq ""} {
  set eth_gt_rxn_pin [get_bd_pins eth_mac_10g/gt_rxn_in]
}
set eth_gt_txp_pin [get_bd_pins -quiet eth_mac_10g/gt_txp_out_0]
if {$eth_gt_txp_pin eq ""} {
  set eth_gt_txp_pin [get_bd_pins eth_mac_10g/gt_txp_out]
}
set eth_gt_txn_pin [get_bd_pins -quiet eth_mac_10g/gt_txn_out_0]
if {$eth_gt_txn_pin eq ""} {
  set eth_gt_txn_pin [get_bd_pins eth_mac_10g/gt_txn_out]
}

ad_connect sfp0_ref_clk_p eth_mac_10g/gt_refclk_p
ad_connect sfp0_ref_clk_n eth_mac_10g/gt_refclk_n
connect_bd_net [get_bd_ports sfp0_rx_p] $eth_gt_rxp_pin
connect_bd_net [get_bd_ports sfp0_rx_n] $eth_gt_rxn_pin
connect_bd_net $eth_gt_txp_pin [get_bd_ports sfp0_tx_p]
connect_bd_net $eth_gt_txn_pin [get_bd_ports sfp0_tx_n]

ad_connect sys_cpu_clk eth_mac_10g/dclk
ad_connect sys_cpu_clk eth_mac_10g/s_axi_aclk_0
ad_connect sys_cpu_resetn eth_mac_10g/s_axi_aresetn_0
ad_connect sys_cpu_reset eth_mac_10g/sys_reset
ad_connect sys_cpu_reset eth_mac_10g/rx_reset_0
ad_connect sys_cpu_reset eth_mac_10g/tx_reset_0
ad_connect sys_cpu_reset eth_mac_10g/gtwiz_reset_rx_datapath_0
ad_connect sys_cpu_reset eth_mac_10g/gtwiz_reset_tx_datapath_0
ad_connect sys_cpu_reset eth_mac_10g/qpllreset_in_0
ad_connect eth_mac_10g/rx_clk_out_0 eth_mac_10g/rx_core_clk_0
ad_connect eth_gt_outclksel/dout eth_mac_10g/rxoutclksel_in_0
ad_connect eth_gt_outclksel/dout eth_mac_10g/txoutclksel_in_0
ad_connect eth_axis_zero_1/dout eth_mac_10g/ctl_tx_send_idle_0
ad_connect eth_axis_zero_1/dout eth_mac_10g/ctl_tx_send_lfi_0
ad_connect eth_axis_zero_1/dout eth_mac_10g/ctl_tx_send_rfi_0
ad_connect eth_axis_zero_1/dout eth_mac_10g/pm_tick_0
ad_connect eth_axis_zero_56/dout eth_mac_10g/tx_preamblein_0
ad_connect eth_axis_zero_1/dout eth_mac_10g/tx_axis_tuser_0

ad_connect eth_mac_10g/rx_clk_out_0 axi_eth_rx_dma/s_axis_aclk
ad_connect sys_cpu_resetn axi_eth_rx_dma/m_dest_axi_aresetn
ad_connect eth_mac_10g/rx_axis_tdata_0 axi_eth_rx_dma/s_axis_data
ad_connect eth_mac_10g/rx_axis_tkeep_0 axi_eth_rx_dma/s_axis_keep
ad_connect eth_mac_10g/rx_axis_tkeep_0 axi_eth_rx_dma/s_axis_strb
ad_connect eth_mac_10g/rx_axis_tvalid_0 axi_eth_rx_dma/s_axis_valid
ad_connect eth_mac_10g/rx_axis_tlast_0 axi_eth_rx_dma/s_axis_last
ad_connect eth_mac_10g/rx_axis_tuser_0 axi_eth_rx_dma/s_axis_user
ad_connect eth_axis_zero_8/dout axi_eth_rx_dma/s_axis_id
ad_connect eth_axis_zero_4/dout axi_eth_rx_dma/s_axis_dest

ad_connect eth_mac_10g/tx_clk_out_0 axi_eth_tx_dma/m_axis_aclk
ad_connect sys_cpu_resetn axi_eth_tx_dma/m_src_axi_aresetn
ad_connect axi_eth_tx_dma/m_axis_data eth_mac_10g/tx_axis_tdata_0
ad_connect axi_eth_tx_dma/m_axis_keep eth_mac_10g/tx_axis_tkeep_0
ad_connect axi_eth_tx_dma/m_axis_valid eth_mac_10g/tx_axis_tvalid_0
ad_connect axi_eth_tx_dma/m_axis_last eth_mac_10g/tx_axis_tlast_0
ad_connect eth_mac_10g/tx_axis_tready_0 axi_eth_tx_dma/m_axis_ready





# interconnect (cpu)

ad_cpu_interconnect 0x44A60000 axi_ad9144_xcvr
ad_cpu_interconnect 0x44A04000 axi_ad9144_tpl
ad_cpu_interconnect 0x44A90000 axi_ad9144_jesd
ad_cpu_interconnect 0x44AA0000 awg_timed_ctrl_0
ad_cpu_interconnect 0x44AB0000 axi_sched_dma
ad_cpu_interconnect 0x44AE0000 awg_extension_0
ad_cpu_interconnect 0x44C00000 eth_mac_10g s_axi_0
ad_cpu_interconnect 0x44AC0000 axi_eth_rx_dma
ad_cpu_interconnect 0x44AD0000 axi_eth_tx_dma
ad_cpu_interconnect 0x7c420000 axi_ad9144_dma


# interconnect (mem/dac)

ad_mem_hp1_interconnect $sys_cpu_clk sys_ps7/S_AXI_HP1
ad_mem_hp1_interconnect $sys_cpu_clk axi_ad9144_dma/m_src_axi
ad_mem_hp2_interconnect $sys_cpu_clk sys_ps7/S_AXI_HP2
ad_mem_hp2_interconnect $sys_cpu_clk axi_sched_dma/m_src_axi
ad_mem_hp3_interconnect $sys_cpu_clk sys_ps7/S_AXI_HP3
ad_mem_hp3_interconnect $sys_cpu_clk axi_eth_rx_dma/m_dest_axi
ad_mem_hp3_interconnect $sys_cpu_clk axi_eth_tx_dma/m_src_axi


# interrupts

ad_cpu_interrupt ps-10 mb-15 axi_ad9144_jesd/irq

ad_cpu_interrupt ps-12 mb-13 axi_ad9144_dma/irq
ad_cpu_interrupt ps-13 mb-12 axi_sched_dma/irq
ad_cpu_interrupt ps-14 mb-10 axi_eth_rx_dma/irq
ad_cpu_interrupt ps-15 mb-9 axi_eth_tx_dma/irq

# PG203 xxv_ethernet v4.0 does not expose a discrete interrupt pin in the
# AXI4-Lite MAC+PCS/PMA configuration used here; firmware can poll MAC status
# registers at 0x44C00000 until an interrupt-capable configuration is proven.



ad_connect axi_dac_fifo/bypass dac_fifo_bypass
