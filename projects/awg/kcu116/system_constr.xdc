# modified by Prerna Baranwal for KCU116 and AD9144
# awg

# DAC FMC signals
# IBUFDS logic is 1.8 V on the end of the DAC
set_property -dict {PACKAGE_PIN AC19 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {tx_sync_p[0]}]
set_property -dict {PACKAGE_PIN AD19 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {tx_sync_n[0]}]
set_property -dict {PACKAGE_PIN Y17 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {tx_sync_p[1]}]
set_property -dict {PACKAGE_PIN AA17 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {tx_sync_n[1]}]
set_property -dict {PACKAGE_PIN AD20 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports tx_sysref_p]
set_property -dict {PACKAGE_PIN AE20 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports tx_sysref_n]


# SPI Chip Selects: CS[0]=AD9516 clock (AA19), CS[1]=AD9144 DAC (AB20)
set_property -dict {PACKAGE_PIN AA19 IOSTANDARD LVCMOS18} [get_ports spi_csn_clk]
set_property -dict {PACKAGE_PIN AB20 IOSTANDARD LVCMOS18} [get_ports spi_csn_dac]

set_property  -dict {PACKAGE_PIN  AA20  IOSTANDARD LVCMOS18} [get_ports spi_miso]                           
set_property  -dict {PACKAGE_PIN  AC17  IOSTANDARD LVCMOS18} [get_ports spi_mosi]                            
set_property  -dict {PACKAGE_PIN  AB19  IOSTANDARD LVCMOS18} [get_ports spi_en] 

set_property -dict {PACKAGE_PIN AB17 IOSTANDARD LVCMOS18} [get_ports spi_clk]


# only 2 control pins for ad9144
set_property -dict {PACKAGE_PIN AD16 IOSTANDARD LVCMOS18} [get_ports {dac_ctrl[0]}]
set_property -dict {PACKAGE_PIN AE16 IOSTANDARD LVCMOS18} [get_ports {dac_ctrl[1]}]






# clocks


# FMC refclk (GBTCLK0)
set_property -dict {PACKAGE_PIN K7} [get_ports tx_ref_clk_p]
set_property -dict {PACKAGE_PIN K6} [get_ports tx_ref_clk_n]



set_property -dict {PACKAGE_PIN F6} [get_ports {tx_data_n[3]}]
set_property -dict {PACKAGE_PIN F7} [get_ports {tx_data_p[3]}]
set_property -dict {PACKAGE_PIN E4} [get_ports {tx_data_n[2]}]
set_property -dict {PACKAGE_PIN E5} [get_ports {tx_data_p[2]}]
set_property -dict {PACKAGE_PIN D6} [get_ports {tx_data_n[1]}]
set_property -dict {PACKAGE_PIN D7} [get_ports {tx_data_p[1]}]
set_property -dict {PACKAGE_PIN B6} [get_ports {tx_data_n[0]}]
set_property -dict {PACKAGE_PIN B7} [get_ports {tx_data_p[0]}]

# ONLY 4 CHANNELS ARE  THERE FOR TX




####################################################################################
# Constraints from file : 'kcu116_system_constr.xdc'
####################################################################################


set tx_refclk_mhz 122.88
if {[info exists ::env(AWG_TX_REFCLK_MHZ)]} {
  set tx_refclk_mhz $::env(AWG_TX_REFCLK_MHZ)
}
set tx_refclk_period [expr {1000.0 / $tx_refclk_mhz}]
set tx_refclk_half_period [expr {$tx_refclk_period / 2.0}]
create_clock -period $tx_refclk_period -name tx_ref_clk \
  -waveform [list 0.000 $tx_refclk_half_period] -add [get_ports tx_ref_clk_p]
set_case_analysis 0 [get_pins -quiet -hier {*_channel/TXSYSCLKSEL[0]}]
set_case_analysis 0 [get_pins -quiet -hier {*_channel/TXSYSCLKSEL[1]}]
set_case_analysis 0 [get_pins -quiet -hier {*_channel/TXOUTCLKSEL[0]}]
set_case_analysis 0 [get_pins -quiet -hier {*_channel/TXOUTCLKSEL[1]}]
set_case_analysis 1 [get_pins -quiet -hier {*_channel/TXOUTCLKSEL[2]}]
create_generated_clock -name tx_div_clk [get_pins i_system_wrapper/system_i/util_awg_xcvr/inst/i_xch_0/i_gtye4_channel/TXOUTCLK]

####################################################################################
# Constraints from file : 'kcu116_system_constr.xdc'
####################################################################################

