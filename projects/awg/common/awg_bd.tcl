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
# Top level ports

create_bd_port -dir I dac_fifo_bypass

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
adi_tpl_jesd204_tx_create axi_ad9144_tpl $NUM_OF_LANES \
                                         $NUM_OF_CONVERTERS \
                                         $SAMPLES_PER_FRAME \
                                         $SAMPLE_WIDTH \

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

ad_connect  util_awg_xcvr/tx_out_clk_0 axi_ad9144_tpl/link_clk
ad_connect  axi_ad9144_jesd/tx_data axi_ad9144_tpl/link
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





# interconnect (cpu)

ad_cpu_interconnect 0x44A60000 axi_ad9144_xcvr
ad_cpu_interconnect 0x44A04000 axi_ad9144_tpl
ad_cpu_interconnect 0x44A90000 axi_ad9144_jesd
ad_cpu_interconnect 0x7c420000 axi_ad9144_dma


# interconnect (mem/dac)

ad_mem_hp1_interconnect $sys_cpu_clk sys_ps7/S_AXI_HP1
ad_mem_hp1_interconnect $sys_cpu_clk axi_ad9144_dma/m_src_axi


# interrupts

ad_cpu_interrupt ps-10 mb-15 axi_ad9144_jesd/irq

ad_cpu_interrupt ps-12 mb-13 axi_ad9144_dma/irq



ad_connect axi_dac_fifo/bypass dac_fifo_bypass
