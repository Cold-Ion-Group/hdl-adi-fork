# Phase E.2 Ethernet clock-domain constraints.
#
# PG203 RX/TX user clocks are generated from the SFP0 MGT reference clock and
# are asynchronous to the board/system clock domain.  The Ethernet RX/TX DMAs
# and PG203 control/status logic contain the required CDC; timing these paths
# as phase-related to sys_cpu_clk creates false setup violations on reset and
# CSR synchronizer paths.

set eth_mac_user_clks [concat \
  [get_clocks -quiet -regexp {^rxoutclk_out\[0\]$}] \
  [get_clocks -quiet -regexp {^txoutclk_out\[0\]$}] \
  [get_clocks -quiet -regexp {^txoutclkpcs_out\[0\]$}]]
set sys_cpu_clks [get_clocks -quiet mmcm_clkout1]

if {[llength $eth_mac_user_clks] > 0 && [llength $sys_cpu_clks] > 0} {
  puts "Applying Phase E Ethernet clock groups: sys_cpu=$sys_cpu_clks eth=$eth_mac_user_clks"
  set_clock_groups -asynchronous \
    -group $sys_cpu_clks \
    -group $eth_mac_user_clks
} else {
  puts "INFO: Phase E Ethernet clock groups not applied in this design stage: sys_cpu='$sys_cpu_clks' eth='$eth_mac_user_clks'"
}
