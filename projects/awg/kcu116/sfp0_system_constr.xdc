# Phase E.2 SFP0 constraints.
#
# This file is intentionally guarded.  The SFP0 PACKAGE_PIN locations, GT quad,
# and lane mapping must be verified against the official KCU116 schematic and
# user guide before these constraints are enabled.

set awg_sfp0_pinout_verified 0
if {$awg_sfp0_pinout_verified != 1} {
  error "AWG SFP0 pinout is not verified. Check KCU116 schematic/user guide, add verified PACKAGE_PIN constraints in sfp0_system_constr.xdc, then set awg_sfp0_pinout_verified to 1."
}

# Verified constraints should cover these top-level ports:
#   sfp0_ref_clk_p / sfp0_ref_clk_n  : 156.25 MHz GT reference clock
#   sfp0_rx_p      / sfp0_rx_n       : SFP0 GT RX lane
#   sfp0_tx_p      / sfp0_tx_n       : SFP0 GT TX lane
#   sfp0_tx_disable                  : SFP0 TX_DISABLE control
#   sfp0_rate_select0                : SFP0 rate-select control
#   sfp0_rate_select1                : SFP0 rate-select control
#   sfp0_mod_abs                     : SFP0 module-absent status
#   sfp0_rx_los                      : SFP0 RX loss-of-signal status
#   sfp0_tx_fault                    : SFP0 TX fault status
#
# Example structure after verification:
#   set_property -dict {PACKAGE_PIN <verified> IOSTANDARD LVCMOS18} [get_ports sfp0_tx_disable]
#   create_clock -period 6.400 -name sfp0_ref_clk [get_ports sfp0_ref_clk_p]
