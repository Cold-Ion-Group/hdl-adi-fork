# Phase E.2 SFP0 constraints.
#
# Pin source: AMD/Xilinx KCU116 Board User Guide UG1239 v1.3, Tables 3-8
# and 3-10.  SFP0 uses GTY bank 226 channel 0.  The 156.25 MHz reference
# clock used here is USER_MGT_SI570_CLOCK_C on MGTREFCLK1_226.
#
# UG1239 lists SFP_TX_FAULT, SFP_MOD_DETECT, SFP_LOS, and RS0/RS1 as
# test-point/resistor/I2C features, not FPGA U1 pins.  Only the GT pins and
# SFP0_TX_DISABLE_B are constrained here.

set_property -dict {PACKAGE_PIN M7} [get_ports sfp0_ref_clk_p] ; # MGTREFCLK1P_226 USER_MGT_SI570_CLOCK_C_P
set_property -dict {PACKAGE_PIN M6} [get_ports sfp0_ref_clk_n] ; # MGTREFCLK1N_226 USER_MGT_SI570_CLOCK_C_N
# PG203 emits the 156.25 MHz SFP0 refclk constraint for this GT input.

set_property -dict {PACKAGE_PIN M2} [get_ports sfp0_rx_p] ; # MGTYRXP0_226 SFP0_RX_P
set_property -dict {PACKAGE_PIN M1} [get_ports sfp0_rx_n] ; # MGTYRXN0_226 SFP0_RX_N
set_property -dict {PACKAGE_PIN N5} [get_ports sfp0_tx_p] ; # MGTYTXP0_226 SFP0_TX_P
set_property -dict {PACKAGE_PIN N4} [get_ports sfp0_tx_n] ; # MGTYTXN0_226 SFP0_TX_N

set_property -dict {PACKAGE_PIN AB14 IOSTANDARD LVCMOS33} [get_ports sfp0_tx_disable] ; # SFP0_TX_DISABLE_B
