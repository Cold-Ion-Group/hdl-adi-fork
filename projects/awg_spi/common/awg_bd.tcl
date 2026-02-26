# modified by Prerna Baranwal for the cold ion group 
# dac connection is used here from the link: https://wiki.analog.com/resources/eval/user-guides/ad-dac-fmc-ebz 
#
# Parameter description:
#   JESD_M : Number of converters per link
#   JESD_L : Number of lanes per link
#   JESD_S : Number of samples per frame
#

source $ad_hdl_dir/library/jesd204/scripts/jesd204.tcl
#source $ad_hdl_dir/projects/common/xilinx/data_offload_bd.tcl

# JESD204B interface configurations

set JESD_M    $ad_project_params(JESD_M)
set JESD_L    $ad_project_params(JESD_L)
set NUM_LINKS $ad_project_params(NUM_LINKS)
set NUM_OF_CONVERTERS [expr $NUM_LINKS * $JESD_M]
set NUM_OF_LANES [expr $NUM_LINKS * $JESD_L]
set SAMPLES_PER_FRAME $ad_project_params(JESD_S)
set SAMPLE_WIDTH $ad_project_params(JESD_NP)

set DAC_DATA_WIDTH [expr $NUM_OF_LANES * 32]
set SAMPLES_PER_CHANNEL [expr $DAC_DATA_WIDTH / $NUM_OF_CONVERTERS / $SAMPLE_WIDTH]

set MAX_NUM_OF_LANES 8
# Top level ports
#TODO: if there are buffer issues later on, this might be causing those. 
create_bd_port -dir I dac_fifo_bypass

#set TX_NUM_OF_LANES $ad_project_params(TX_JESD_L)           ; # L
#set TX_NUM_OF_CONVERTERS $ad_project_params(TX_JESD_M)      ; # M
#set TX_SAMPLES_PER_FRAME $ad_project_params(TX_JESD_S)      ; # S
#set TX_SAMPLE_WIDTH 16                                      ; # N/NP
#set TX_SAMPLES_PER_CHANNEL [expr $TX_NUM_OF_LANES * 32 / ($TX_NUM_OF_CONVERTERS * $TX_SAMPLE_WIDTH)]

#set dac_data_width [expr $TX_SAMPLE_WIDTH * $TX_NUM_OF_CONVERTERS * $TX_SAMPLES_PER_CHANNEL]

#set RX_NUM_OF_LANES $ad_project_params(RX_JESD_L)           ; # L
#set RX_NUM_OF_CONVERTERS $ad_project_params(RX_JESD_M)      ; # M
#set RX_SAMPLES_PER_FRAME $ad_project_params(RX_JESD_S)      ; # S
#set RX_SAMPLE_WIDTH 16                                      ; # N/NP
#set RX_SAMPLES_PER_CHANNEL [expr $RX_NUM_OF_LANES * 32 / ($RX_NUM_OF_CONVERTERS * $RX_SAMPLE_WIDTH)]

#set adc_data_width [expr $RX_SAMPLE_WIDTH * $RX_NUM_OF_CONVERTERS * $RX_SAMPLES_PER_CHANNEL]

#set MAX_TX_NUM_OF_LANES 4
#set MAX_RX_NUM_OF_LANES 4

# dac peripherals
# JESD204 PHY layer peripheral
ad_ip_instance axi_adxcvr axi_ad9144_xcvr [list \
  NUM_OF_LANES $NUM_OF_LANES \
  QPLL_ENABLE 1 \
  TX_OR_RX_N 1 \
]
# JESD204 link layer peripheral
adi_axi_jesd204_tx_create axi_ad9144_jesd $NUM_OF_LANES $NUM_LINKS

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


# TODO: cyclic mode is set as 1 to stream data without cpu intervention, if there is a fault in adaptation then it might come from here
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

#ad_data_offload_create axi_ad9144_offload \
#                       1 \
#                       $dac_offload_type \
#                       $dac_offload_size \
#                       $dac_data_width \
#                       $dac_data_width \
#                       $plddr_offload_axi_data_width



# synchronization interface
#ad_connect axi_ad9144_offload/init_req axi_ad9144_dma/m_axis_xfer_req
#ad_connect axi_ad9144_offload/sync_ext GND


#TODO: fifo logic inserted here: may/may not cause issues:
set dac_dma_data_width $DAC_DATA_WIDTH 
ad_dacfifo_create axi_dac_fifo \
                  $DAC_DATA_WIDTH \
                  $dac_dma_data_width \
                  $dac_fifo_address_width




# adc peripherals

#ad_ip_instance axi_adxcvr axi_ad9680_xcvr [list \
#  NUM_OF_LANES $RX_NUM_OF_LANES \
#  QPLL_ENABLE 0 \
#  TX_OR_RX_N 0 \
#]

#adi_axi_jesd204_rx_create axi_ad9680_jesd $RX_NUM_OF_LANES

#adi_tpl_jesd204_rx_create axi_ad9680_tpl $RX_NUM_OF_LANES \
#                                         $RX_NUM_OF_CONVERTERS \
#                                         $RX_SAMPLES_PER_FRAME \
#                                         $RX_SAMPLE_WIDTH
#ad_ip_parameter axi_ad9680_tpl/adc_tpl_core CONFIG.CONVERTER_RESOLUTION 14
#ad_ip_parameter axi_ad9680_tpl/adc_tpl_core CONFIG.TWOS_COMPLEMENT 0

#ad_ip_instance util_cpack2 axi_ad9680_cpack [list \
#  NUM_OF_CHANNELS $RX_NUM_OF_CONVERTERS \
#  SAMPLES_PER_CHANNEL $RX_SAMPLES_PER_CHANNEL \
#  SAMPLE_DATA_WIDTH $RX_SAMPLE_WIDTH \
#]

#d_ip_instance axi_dmac axi_ad9680_dma [list \
# DMA_TYPE_SRC 1 \
#  DMA_TYPE_DEST 0 \
#  ID 0 \
#  AXI_SLICE_SRC 0 \
#  AXI_SLICE_DEST 0 \
#  SYNC_TRANSFER_START 0 \
#  DMA_LENGTH_WIDTH 24 \
# DMA_2D_TRANSFER 0 \
#  CYCLIC 0 \
#  DMA_DATA_WIDTH_SRC $adc_data_width \
#  DMA_DATA_WIDTH_DEST 64 \
#]




#ad_data_offload_create axi_ad9680_offload \
#                       0 \
#                       $adc_offload_type \
#                       $adc_offload_size \
#                       $adc_data_width \
#                       $adc_data_width \
#                       $plddr_offload_axi_data_width

# synchronization interface
# ad_connect axi_ad9680_offload/init_req axi_ad9680_dma/s_axis_xfer_req
# ad_connect axi_ad9680_offload/sync_ext GND

# shared transceiver core, no receiver core

# RX_NUM_OF_LANES is set as 0 because there is no rx connection, only tx connection is present. 
ad_ip_instance util_adxcvr util_awg_xcvr [list \
  RX_NUM_OF_LANES 0 \
  TX_NUM_OF_LANES $MAX_NUM_OF_LANES \
  TX_LANE_INVERT [expr 0x0F] \
  QPLL_REFCLK_DIV 1 \
  QPLL_FBDIV_RATIO 1 \
  QPLL_FBDIV 0x80 \
  TX_OUT_DIV 1 \
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



#create_bd_port -dir I tx_ref_clk_0
#create_bd_port -dir I rx_ref_clk_0

#ad_xcvrpll  tx_ref_clk_0 util_awg_xcvr/qpll_ref_clk_*
#ad_xcvrpll  rx_ref_clk_0 util_awg_xcvr/cpll_ref_clk_*





ad_xcvrpll  axi_ad9144_xcvr/up_pll_rst util_awg_xcvr/up_qpll_rst_*
ad_xcvrpll  axi_ad9144_xcvr/up_pll_rst util_awg_xcvr/up_cpll_rst_*

# connections (dac)
# removed 0 1 2 3 from this amd kept it as blank, keeping in mind the earlier format 
ad_xcvrcon  util_awg_xcvr axi_ad9144_xcvr axi_ad9144_jesd {} {} {} $MAX_NUM_OF_LANES
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

# TODO this place. modified dac to ad9144, hence this might cause some issue. 
# TODO reset has changed from changed from areset signal to reset, initially it was unsyncronised and now it is syncronised 
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


#ad_connect  $sys_cpu_clk axi_ad9144_offload/s_axi_aclk
#ad_connect  util_awg_xcvr/tx_out_clk_0 axi_ad9144_offload/m_axis_aclk
#ad_connect  $sys_cpu_clk axi_ad9144_offload/s_axis_aclk
#ad_connect  $sys_cpu_clk axi_ad9144_dma/m_axis_aclk

#ad_connect  $sys_cpu_resetn axi_ad9144_offload/s_axi_aresetn
#ad_connect  axi_ad9144_jesd_rstgen/peripheral_aresetn axi_ad9144_offload/m_axis_aresetn
#ad_connect  $sys_cpu_resetn axi_ad9144_offload/s_axis_aresetn
#ad_connect  $sys_cpu_resetn axi_ad9144_dma/m_src_axi_aresetn

#ad_connect axi_ad9144_upack/s_axis axi_ad9144_offload/m_axis
#ad_connect axi_ad9144_offload/s_axis axi_ad9144_dma/m_axis

# connections (adc)

#ad_xcvrcon  util_awg_xcvr axi_ad9680_xcvr axi_ad9680_jesd {} {} {} $MAX_RX_NUM_OF_LANES
#ad_connect  util_awg_xcvr/rx_out_clk_0 axi_ad9680_tpl/link_clk
#ad_connect  axi_ad9680_jesd/rx_sof axi_ad9680_tpl/link_sof
#ad_connect  axi_ad9680_jesd/rx_data_tdata axi_ad9680_tpl/link_data
#ad_connect  axi_ad9680_jesd/rx_data_tvalid axi_ad9680_tpl/link_valid

#ad_connect  util_awg_xcvr/rx_out_clk_0 axi_ad9680_cpack/clk
#ad_connect  axi_ad9680_jesd_rstgen/peripheral_reset axi_ad9680_cpack/reset

#ad_connect  axi_ad9680_tpl/adc_valid_0 axi_ad9680_cpack/fifo_wr_en
#for {set i 0} {$i < $RX_NUM_OF_CONVERTERS} {incr i} {
#  ad_connect  axi_ad9680_tpl/adc_enable_$i axi_ad9680_cpack/enable_$i
#  ad_connect  axi_ad9680_tpl/adc_data_$i axi_ad9680_cpack/fifo_wr_data_$i
#}
#ad_connect  axi_ad9680_tpl/adc_dovf axi_ad9680_cpack/fifo_wr_overflow

#ad_connect  $sys_cpu_clk axi_ad9680_offload/s_axi_aclk
#ad_connect  util_awg_xcvr/rx_out_clk_0 axi_ad9680_offload/s_axis_aclk
#ad_connect  $sys_cpu_clk axi_ad9680_offload/m_axis_aclk
#ad_connect  $sys_cpu_clk axi_ad9680_dma/s_axis_aclk

#ad_connect  $sys_cpu_resetn axi_ad9680_offload/s_axi_aresetn
#ad_connect  axi_ad9680_jesd_rstgen/peripheral_aresetn axi_ad9680_offload/s_axis_aresetn
#ad_connect  $sys_cpu_resetn axi_ad9680_dma/m_dest_axi_aresetn
#ad_connect  $sys_cpu_resetn axi_ad9680_offload/m_axis_aresetn

#ad_connect  axi_ad9680_cpack/packed_fifo_wr_en axi_ad9680_offload/i_data_offload/s_axis_valid
#ad_connect  axi_ad9680_cpack/packed_fifo_wr_data axi_ad9680_offload/i_data_offload/s_axis_data

#ad_connect axi_ad9680_offload/m_axis axi_ad9680_dma/s_axis

# interconnect (cpu)

ad_cpu_interconnect 0x44A60000 axi_ad9144_xcvr
ad_cpu_interconnect 0x44A04000 axi_ad9144_tpl
ad_cpu_interconnect 0x44A90000 axi_ad9144_jesd
ad_cpu_interconnect 0x7c420000 axi_ad9144_dma
# TODO there is no offload configured here, and it instead uses the fifo logic. If there is an error, it might be caused due to this
#ad_cpu_interconnect 0x7c440000 axi_ad9144_offload
#ad_cpu_interconnect 0x44A50000 axi_ad9680_xcvr
#ad_cpu_interconnect 0x44A10000 axi_ad9680_tpl
#ad_cpu_interconnect 0x44AA0000 axi_ad9680_jesd
#ad_cpu_interconnect 0x7c400000 axi_ad9680_dma
#ad_cpu_interconnect 0x7c460000 axi_ad9680_offload

# gt uses hp3, and 100MHz clock for both DRP and AXI4
# not required as adc is not connected 
#ad_mem_hp3_interconnect $sys_cpu_clk sys_ps7/S_AXI_HP3
#ad_mem_hp3_interconnect $sys_cpu_clk axi_ad9680_xcvr/m_axi

# interconnect (mem/dac)

ad_mem_hp1_interconnect $sys_cpu_clk sys_ps7/S_AXI_HP1
ad_mem_hp1_interconnect $sys_cpu_clk axi_ad9144_dma/m_src_axi
#ad_mem_hp2_interconnect $sys_cpu_clk sys_ps7/S_AXI_HP2
#ad_mem_hp2_interconnect $sys_cpu_clk axi_ad9680_dma/m_dest_axi

# interrupts

ad_cpu_interrupt ps-10 mb-15 axi_ad9144_jesd/irq
#ad_cpu_interrupt ps-11 mb-14 axi_ad9680_jesd/irq
ad_cpu_interrupt ps-12 mb-13 axi_ad9144_dma/irq
#ad_cpu_interrupt ps-13 mb-12 axi_ad9680_dma/irq


ad_connect axi_dac_fifo/bypass dac_fifo_bypass