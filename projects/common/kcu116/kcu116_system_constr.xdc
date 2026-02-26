# modified by Prerna Baranwal
# constraints

set_property -dict {PACKAGE_PIN B9 IOSTANDARD LVCMOS33} [get_ports sys_rst]

# uart

set_property -dict {PACKAGE_PIN W13 IOSTANDARD LVCMOS33} [get_ports uart_sout]
set_property -dict {PACKAGE_PIN W12 IOSTANDARD LVCMOS33} [get_ports uart_sin]

# Pins assosciated with ethernet has been removed because there is no license.


# sw/led
set_property -dict {PACKAGE_PIN C9 IOSTANDARD LVCMOS33} [get_ports {gpio_bd[0]}]
set_property -dict {PACKAGE_PIN D9 IOSTANDARD LVCMOS33} [get_ports {gpio_bd[1]}]
set_property -dict {PACKAGE_PIN E10 IOSTANDARD LVCMOS33} [get_ports {gpio_bd[2]}]
set_property -dict {PACKAGE_PIN E11 IOSTANDARD LVCMOS33} [get_ports {gpio_bd[3]}]
set_property -dict {PACKAGE_PIN F9 IOSTANDARD LVCMOS33} [get_ports {gpio_bd[4]}]
set_property -dict {PACKAGE_PIN F10 IOSTANDARD LVCMOS33} [get_ports {gpio_bd[5]}]
set_property -dict {PACKAGE_PIN G9 IOSTANDARD LVCMOS33} [get_ports {gpio_bd[6]}]
set_property -dict {PACKAGE_PIN G10 IOSTANDARD LVCMOS33} [get_ports {gpio_bd[7]}]
set_property -dict {PACKAGE_PIN G11 IOSTANDARD LVCMOS33 DRIVE 8} [get_ports {gpio_bd[8]}]
set_property -dict {PACKAGE_PIN H11 IOSTANDARD LVCMOS33 DRIVE 8} [get_ports {gpio_bd[9]}]
set_property -dict {PACKAGE_PIN H9 IOSTANDARD LVCMOS33 DRIVE 8} [get_ports {gpio_bd[10]}]
set_property -dict {PACKAGE_PIN J9 IOSTANDARD LVCMOS33 DRIVE 8} [get_ports {gpio_bd[11]}]
set_property -dict {PACKAGE_PIN A10 IOSTANDARD LVCMOS33 DRIVE 8} [get_ports {gpio_bd[12]}]
set_property -dict {PACKAGE_PIN B11 IOSTANDARD LVCMOS33 DRIVE 8} [get_ports {gpio_bd[13]}]
set_property -dict {PACKAGE_PIN B10 IOSTANDARD LVCMOS33 DRIVE 8} [get_ports {gpio_bd[14]}]
set_property -dict {PACKAGE_PIN C11 IOSTANDARD LVCMOS33 DRIVE 8} [get_ports {gpio_bd[15]}]
set_property -dict {PACKAGE_PIN A9 IOSTANDARD LVCMOS33 DRIVE 8} [get_ports {gpio_bd[16]}]

# iic

set_property -dict {PACKAGE_PIN AE13 IOSTANDARD LVCMOS33} [get_ports iic_scl]
set_property -dict {PACKAGE_PIN AF13 IOSTANDARD LVCMOS33} [get_ports iic_sda]

# 300 MHz clock pin

set_property -dict {PACKAGE_PIN K22} [get_ports sys_clk_p]
set_property -dict {PACKAGE_PIN K23} [get_ports sys_clk_n]


#Setting the Configuration Bank Voltage Select
set_property CFGBVS GND [current_design]
# TODO : if there is an error it may be due to the configuration voltage
set_property CONFIG_VOLTAGE 1.8 [current_design]

# Create SPI clock



set_property INTERNAL_VREF 0.84 [get_iobanks 66]
create_generated_clock -name spi_clk -source [get_pins i_system_wrapper/system_i/axi_spi/ext_spi_clk] -divide_by 2 [get_pins i_system_wrapper/system_i/axi_spi/sck_o]

####################################################################################
# Constraints from file : 'system_axi_ddr_cntrl_0_board.xdc'
####################################################################################

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk]

