# modified by Prerna Baranwal for KCU116 and AD9144
# awg

# DAC FMC signals

set_property -dict {PACKAGE_PIN AC19 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {tx_sync_p[0]}]
set_property -dict {PACKAGE_PIN AD19 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {tx_sync_n[0]}]
set_property -dict {PACKAGE_PIN Y17 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {tx_sync_p[1]}]
set_property -dict {PACKAGE_PIN AA17 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {tx_sync_n[1]}]
set_property -dict {PACKAGE_PIN AD20 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports tx_sysref_p]
set_property -dict {PACKAGE_PIN AE20 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports tx_sysref_n]
# TO DO: changed it to LVCMOS18, may cause issues later on, as its connected to the Vadj of 1.8 v
set_property -dict {PACKAGE_PIN AA19 IOSTANDARD LVCMOS18} [get_ports spi_csn_clk]
set_property -dict {PACKAGE_PIN AB20 IOSTANDARD LVCMOS18} [get_ports spi_csn_dac]
set_property -dict {PACKAGE_PIN AB17 IOSTANDARD LVCMOS18} [get_ports spi_clk]
set_property -dict {PACKAGE_PIN AC18 IOSTANDARD LVCMOS18} [get_ports spi_sdio]
set_property -dict {PACKAGE_PIN AF17 IOSTANDARD LVCMOS18} [get_ports spi_dir]


#set_property LOC GTHE4_COMMON_X1Y1 [get_cells -hierarchical -filter {NAME =~ *i_ibufds_rx_ref_clk}]
set_property LOC GTYE4_COMMON_X0Y3 [get_cells -hierarchical -filter {NAME =~ *i_ibufds_tx_ref_clk}]


# For AD9135-FMC-EBZ, AD9136-FMC-EBZ, AD9144-FMC-EBZ, AD9152-FMC-EBZ, AD9154-FMC-EBZ
set_property -dict {PACKAGE_PIN AD16 IOSTANDARD LVCMOS18} [get_ports {dac_ctrl[0]}]
set_property -dict {PACKAGE_PIN AE16 IOSTANDARD LVCMOS18} [get_ports {dac_ctrl[3]}]

# For AD9171-FMC-EBZ, AD9172-FMC-EBZ, AD9173-FMC-EBZ
set_property -dict {PACKAGE_PIN Y20 IOSTANDARD LVCMOS18} [get_ports {dac_ctrl[1]}]
set_property -dict {PACKAGE_PIN Y21 IOSTANDARD LVCMOS18} [get_ports {dac_ctrl[2]}]
# For AD916(1,2,3,4)-FMC-EBZ
set_property -dict {PACKAGE_PIN AD18 IOSTANDARD LVCMOS18} [get_ports {dac_ctrl[4]}]



# clocks

# TODO  this is problematic !!

set_property -dict {PACKAGE_PIN K7} [get_ports tx_ref_clk_p]
#set_property  -dict {PACKAGE_PIN  AB21} [get_ports tx_ref_clk_p]                                              ; ## D04  FMC_HPC0_GBTCLK0_M2C_P
set_property -dict {PACKAGE_PIN K6} [get_ports tx_ref_clk_n]
#set_property  -dict {PACKAGE_PIN  AC21} [get_ports tx_ref_clk_n]                                              ; ## D05  FMC_HPC0_GBTCLK0_M2C_N



#create_clock -name rx_ref_clk   -period  2.00 [get_ports rx_ref_clk_p]

# For transceiver output clocks use reference clock divided by two
# This will help autoderive the clocks correcly

#set_case_analysis -quiet 0 [get_pins -quiet -hier *_channel/RXSYSCLKSEL[0]]
#set_case_analysis -quiet 0 [get_pins -quiet -hier *_channel/RXSYSCLKSEL[1]]
#set_case_analysis -quiet 0 [get_pins -quiet -hier *_channel/RXOUTCLKSEL[0]]
#set_case_analysis -quiet 0 [get_pins -quiet -hier *_channel/RXOUTCLKSEL[1]]
#set_case_analysis -quiet 1 [get_pins -quiet -hier *_channel/RXOUTCLKSEL[2]]

#create_generated_clock -name rx_div_clk   [get_pins i_system_wrapper/system_i/util_awg_xcvr/inst/i_xch_0/i_gthe3_channel/RXOUTCLK]

#TODO: major issues are from here  gt pin assignments

#set_property  -dict {PACKAGE_PIN  A4} [get_ports tx_data_p[4]] ; ## A10  FMC_HPC0_DP3_M2C_P
#set_property  -dict {PACKAGE_PIN  A3} [get_ports tx_data_n[4]] ; ## A11  FMC_HPC0_DP3_M2C_N
#set_property  -dict {PACKAGE_PIN  D2} [get_ports tx_data_p[5]] ; ## C06  FMC_HPC0_DP0_M2C_P
#set_property  -dict {PACKAGE_PIN  D1} [get_ports tx_data_n[5]] ; ## C07  FMC_HPC0_DP0_M2C_N
#set_property  -dict {PACKAGE_PIN  B2} [get_ports tx_data_p[6]] ; ## A06  FMC_HPC0_DP2_M2C_P
#set_property  -dict {PACKAGE_PIN  B1} [get_ports tx_data_n[6]] ; ## A07  FMC_HPC0_DP2_M2C_N
#set_property  -dict {PACKAGE_PIN  C4} [get_ports tx_data_p[7]] ; ## A02  FMC_HPC0_DP1_M2C_P
#set_property  -dict {PACKAGE_PIN  C3} [get_ports tx_data_n[7]] ; ## A03  FMC_HPC0_DP1_M2C_N
#set_property  -dict {PACKAGE_PIN  B7} [get_ports tx_data_p[0]] ; ## A30  FMC_HPC0_DP3_C2M_P (tx_data_p[0])
#set_property  -dict {PACKAGE_PIN  B6} [get_ports tx_data_n[0]] ; ## A31  FMC_HPC0_DP3_C2M_N (tx_data_n[0])
#set_property  -dict {PACKAGE_PIN  F7} [get_ports tx_data_p[1]] ; ## C02  FMC_HPC0_DP0_C2M_P (tx_data_p[3])
#set_property  -dict {PACKAGE_PIN  F6} [get_ports tx_data_n[1]] ; ## C03  FMC_HPC0_DP0_C2M_N (tx_data_n[3])
#set_property  -dict {PACKAGE_PIN  D7} [get_ports tx_data_p[2]] ; ## A26  FMC_HPC0_DP2_C2M_P (tx_data_p[1])
#set_property  -dict {PACKAGE_PIN  D6} [get_ports tx_data_n[2]] ; ## A27  FMC_HPC0_DP2_C2M_N (tx_data_n[1])
#set_property  -dict {PACKAGE_PIN  E5} [get_ports tx_data_p[3]] ; ## A22  FMC_HPC0_DP1_C2M_P (tx_data_p[2])
#set_property  -dict {PACKAGE_PIN  E4} [get_ports tx_data_n[3]] ; ## A23  FMC_HPC0_DP1_C2M_N (tx_data_n[2])
# TODO: set up the GTY configuration for FMC transceiver


# unfortunately X0Y0 is used as a clock , this corresponds to the bank 227

set_property LOC GTYE4_CHANNEL_X0Y12 [get_cells -hierarchical -filter {NAME =~ *util_awg_xcvr/inst/i_xch_0/i_gtye4_channel}]
set_property LOC GTYE4_CHANNEL_X0Y13 [get_cells -hierarchical -filter {NAME =~ *util_awg_xcvr/inst/i_xch_1/i_gtye4_channel}]
set_property LOC GTYE4_CHANNEL_X0Y14 [get_cells -hierarchical -filter {NAME =~ *util_awg_xcvr/inst/i_xch_2/i_gtye4_channel}]
set_property LOC GTYE4_CHANNEL_X0Y15 [get_cells -hierarchical -filter {NAME =~ *util_awg_xcvr/inst/i_xch_3/i_gtye4_channel}]
# TODO: this may cause issues later on as these are not assosciated to FMC
set_property LOC GTYE4_CHANNEL_X0Y4 [get_cells -hierarchical -filter {NAME =~ *util_awg_xcvr/inst/i_xch_4/i_gtye4_channel}]
set_property LOC GTYE4_CHANNEL_X0Y5 [get_cells -hierarchical -filter {NAME =~ *util_awg_xcvr/inst/i_xch_5/i_gtye4_channel}]
set_property LOC GTYE4_CHANNEL_X0Y6 [get_cells -hierarchical -filter {NAME =~ *util_awg_xcvr/inst/i_xch_6/i_gtye4_channel}]
set_property LOC GTYE4_CHANNEL_X0Y7 [get_cells -hierarchical -filter {NAME =~ *util_awg_xcvr/inst/i_xch_7/i_gtye4_channel}]











create_clock -period 2.000 -name tx_ref_clk -waveform {0.000 1.000} -add [get_ports tx_ref_clk_p]
set_case_analysis 0 [get_pins -quiet -hier {*_channel/TXSYSCLKSEL[0]}]
set_case_analysis 0 [get_pins -quiet -hier {*_channel/TXSYSCLKSEL[1]}]
set_case_analysis 0 [get_pins -quiet -hier {*_channel/TXOUTCLKSEL[0]}]
set_case_analysis 0 [get_pins -quiet -hier {*_channel/TXOUTCLKSEL[1]}]
set_case_analysis 1 [get_pins -quiet -hier {*_channel/TXOUTCLKSEL[2]}]
create_generated_clock -name tx_div_clk [get_pins i_system_wrapper/system_i/util_awg_xcvr/inst/i_xch_0/i_gtye4_channel/TXOUTCLK]

####################################################################################
# Constraints from file : 'kcu116_system_constr.xdc'
####################################################################################

