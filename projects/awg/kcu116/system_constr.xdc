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

# Scheduler commit marker: probe this pin (single-ended) against GND to capture commit pulses.
set_property -dict {PACKAGE_PIN AF19 IOSTANDARD LVCMOS18} [get_ports marker_commit]






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


set tx_refclk_mhz $::env(AWG_TX_REFCLK_MHZ)
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

# ---------------------------------------------------------------------------
# SYSREF CDC constraints for jesd_sysref_sync (Subclass 1)
# ---------------------------------------------------------------------------
# sysref_in arrives via IBUFDS (not an IOB FF) and is asynchronous relative
# to device_clk (tx_div_clk, 245.76 MHz).  The three-stage shift register
# sysref_ff[0:2] implements the synchronizer; sysref_ff[0] is the metastable
# capture stage and must be marked ASYNC_REG to receive placement guidance.
# A set_false_path to sysref_ff_reg[0] silences unconstrained-path warnings
# on the IBUFDS→fabric combinatorial arc and is consistent with the ADI core
# treatment of asynchronous SYSREF signals (see axi_jesd204_tx_constr.xdc).
# Do NOT replace this with set_input_delay: the sysref edge relationship to
# device_clk is intentionally undefined at synthesis time.
set_property ASYNC_REG TRUE \
  [get_cells -hier -filter {NAME =~ *jesd_sysref_sync*sysref_ff_reg[*]}]

set_false_path \
  -to [get_cells -hier -filter {NAME =~ *jesd_sysref_sync*sysref_ff_reg[0]}]

# sync_in (SYNC~) arrives via IBUFDS and is also asynchronous relative to
# device_clk.  The two-stage synchronizer sync_ff1/sync_ff2 handles capture.
set_property ASYNC_REG TRUE \
  [get_cells -hier -filter {NAME =~ *jesd_sysref_sync*sync_ff1_reg[*]}] \
  [get_cells -hier -filter {NAME =~ *jesd_sysref_sync*sync_ff2_reg[*]}]

set_false_path \
  -to [get_cells -hier -filter {NAME =~ *jesd_sysref_sync*sync_ff1_reg[*]}]

# ---------------------------------------------------------------------------
# AWG timed-control CDC constraints
# ---------------------------------------------------------------------------
# s_axi_aclk is the 100 MHz CPU/AXI clock (mmcm_clkout1). sched_clk is the
# JESD TX clock from util_awg_xcvr/tx_out_clk_0 (tx_div_clk). These clock
# domains are intentionally asynchronous. Constrain only the known CDC
# capture points and handshake snapshot buses; same-clock scheduler and AXI
# timing remains fully checked.
set_property ASYNC_REG TRUE \
  [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/*_sync1_reg*}] \
  [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/*_sync2_reg*}] \
  [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/*_s1_reg*}] \
  [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/*_s2_reg*}] \
  [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/i_stream_fifo/*cdc_sync_stage1_reg*}] \
  [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/i_stream_fifo/*cdc_sync_stage2_reg*}]

# Single-bit toggles and stable scalar/vector values captured by first-stage
# synchronizers.
set_false_path \
  -to [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/*_sync1_reg*}]
set_false_path \
  -to [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/time_now_*_s1_reg[*]}]
set_false_path \
  -to [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/time_reload_*_s1_reg[*]}]
set_false_path \
  -to [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/event_count_s1_reg[*]}]
set_false_path \
  -to [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/mode_stream_cfg_s1_reg}]
set_false_path \
  -to [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/low_wmark_s1_reg[*]}]
set_false_path \
  -to [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/*_gray_sync1_reg[*]}]
set_false_path \
  -to [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/i_stream_fifo/*cdc_sync_stage1_reg*}]

# Event write payload/address is held in the AXI domain and committed when the
# synchronized event-write toggle is observed in sched_clk.
set_false_path \
  -from [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/event_wr_addr_cfg_reg[*]}] \
  -to   [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/event_mem_reg*}]
set_false_path \
  -from [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/event_wr_data_cfg_reg[*]}] \
  -to   [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/event_mem_reg*}]

# Snapshot buses are updated in sched_clk, then sampled by the AXI domain only
# after status_snap_tgl has crossed its 2-FF synchronizer.
set_false_path \
  -from [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/status_sched_snap_reg[*]}] \
  -to   [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/status_shadow_reg[*]}]
set_false_path \
  -from [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/last_exec_sched_snap_reg[*]}] \
  -to   [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/last_exec_shadow_reg[*]}]
set_false_path \
  -from [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/cur_event_snap_reg[*]}] \
  -to   [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/cur_event_shadow_reg[*]}]
set_false_path \
  -from [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/irq_snap_reg[*]}] \
  -to   [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/irq_status_axi_reg[*]}]
set_false_path \
  -from [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/eof_seen_sched_snap_reg}] \
  -to   [get_cells -quiet -hier -filter {NAME =~ *awg_timed_ctrl_0/inst/eof_seen_shadow_reg}]
