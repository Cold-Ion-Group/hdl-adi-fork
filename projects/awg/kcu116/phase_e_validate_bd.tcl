proc phase_e_fail {msg} {
  return -code error "PHASE_E_BD_VALIDATE: $msg"
}

proc phase_e_assert_cell {name} {
  if {[llength [get_bd_cells -quiet $name]] != 1} {
    phase_e_fail "missing BD cell $name"
  }
}

proc phase_e_assert_param {cell param expected} {
  set obj [get_bd_cells $cell]
  set actual [get_property "CONFIG.$param" $obj]
  set actual_l [string tolower $actual]
  set expected_l [string tolower $expected]
  set equal [expr {$actual eq $expected}]
  if {!$equal} {
    if {(($expected_l eq "0") && ($actual_l eq "false")) ||
        (($expected_l eq "false") && ($actual_l eq "0")) ||
        (($expected_l eq "1") && ($actual_l eq "true")) ||
        (($expected_l eq "true") && ($actual_l eq "1"))} {
      set equal 1
    }
  }
  if {!$equal} {
    phase_e_fail "$cell CONFIG.$param expected '$expected' got '$actual'"
  }
}

proc phase_e_assert_addr {segment offset} {
  set found 0
  foreach seg [get_bd_addr_segs -quiet -hierarchical *] {
    if {[string match "*$segment*" $seg]} {
      set actual [get_property OFFSET $seg]
      if {[string equal -nocase $actual $offset]} {
        set found 1
      }
    }
  }
  if {!$found} {
    phase_e_fail "missing address segment matching $segment at $offset"
  }
}

proc phase_e_assert_net_has_pin {net_pattern pin_pattern} {
  set found 0
  foreach net [get_bd_nets -quiet -hierarchical $net_pattern] {
    foreach pin [get_bd_pins -quiet -of_objects $net] {
      if {[string match $pin_pattern $pin]} {
        set found 1
      }
    }
  }
  if {!$found} {
    phase_e_fail "no net '$net_pattern' contains pin '$pin_pattern'"
  }
}

proc phase_e_validate_bd {{project_name awg_kcu116}} {
  file mkdir phase_e_logs

  set bd_file [get_files -quiet */system.bd]
  if {$bd_file eq ""} {
    set bd_file [get_files -quiet "$project_name.srcs/sources_1/bd/system/system.bd"]
  }
  if {$bd_file eq ""} {
    phase_e_fail "system.bd is not present in the current project"
  }
  open_bd_design $bd_file
  validate_bd_design

  foreach cell {
    eth_mac_10g
    axi_eth_rx_dma
    axi_eth_tx_dma
    axi_sched_dma
    awg_timed_ctrl_0
    awg_extension_0
    axi_ad9144_dma
  } {
    phase_e_assert_cell $cell
  }

  set mac_vlnv [get_property VLNV [get_bd_cells eth_mac_10g]]
  if {$mac_vlnv ne "xilinx.com:ip:xxv_ethernet:4.0"} {
    phase_e_fail "eth_mac_10g VLNV expected xilinx.com:ip:xxv_ethernet:4.0 got $mac_vlnv"
  }
  set mac_license [get_property -quiet REQUIRES_LICENSE [get_ipdefs -all xilinx.com:ip:xxv_ethernet:4.0]]
  if {$mac_license ne "1"} {
    phase_e_fail "xxv_ethernet:4.0 REQUIRES_LICENSE expected 1 got '$mac_license'"
  }

  phase_e_assert_param eth_mac_10g LINE_RATE 10
  phase_e_assert_param eth_mac_10g NUM_OF_CORES 1
  phase_e_assert_param eth_mac_10g GT_REF_CLK_FREQ 156.25
  phase_e_assert_param eth_mac_10g GT_DRP_CLK 100.00
  phase_e_assert_param eth_mac_10g INCLUDE_AXI4_INTERFACE 1
  phase_e_assert_param eth_mac_10g INCLUDE_USER_FIFO 1
  phase_e_assert_param eth_mac_10g GT_GROUP_SELECT Quad_X0Y1
  phase_e_assert_param eth_mac_10g LANE1_GT_LOC X0Y4

  phase_e_assert_param axi_sched_dma DMA_TYPE_SRC 0
  phase_e_assert_param axi_sched_dma DMA_TYPE_DEST 1
  phase_e_assert_param axi_sched_dma DMA_DATA_WIDTH_SRC 256
  phase_e_assert_param axi_sched_dma DMA_DATA_WIDTH_DEST 256
  phase_e_assert_param axi_sched_dma CYCLIC 0
  phase_e_assert_param axi_sched_dma ID 2

  set expected_c1 1
  if {[info exists ::env(AWG_ENABLE_C1)]} {
    set expected_c1 $::env(AWG_ENABLE_C1)
  }
  phase_e_assert_param awg_extension_0 C1_IMPLEMENTED $expected_c1

  phase_e_assert_param axi_eth_rx_dma DMA_TYPE_SRC 1
  phase_e_assert_param axi_eth_rx_dma DMA_TYPE_DEST 0
  phase_e_assert_param axi_eth_rx_dma DMA_DATA_WIDTH_SRC 64
  phase_e_assert_param axi_eth_rx_dma DMA_DATA_WIDTH_DEST 256
  phase_e_assert_param axi_eth_rx_dma CYCLIC 0
  phase_e_assert_param axi_eth_rx_dma ID 3

  phase_e_assert_param axi_eth_tx_dma DMA_TYPE_SRC 0
  phase_e_assert_param axi_eth_tx_dma DMA_TYPE_DEST 1
  phase_e_assert_param axi_eth_tx_dma DMA_DATA_WIDTH_SRC 256
  phase_e_assert_param axi_eth_tx_dma DMA_DATA_WIDTH_DEST 64
  phase_e_assert_param axi_eth_tx_dma CYCLIC 0
  phase_e_assert_param axi_eth_tx_dma ID 4

  phase_e_assert_addr SEG_data_eth_mac_10g 0x44C00000
  phase_e_assert_addr SEG_data_axi_eth_rx_dma 0x44AC0000
  phase_e_assert_addr SEG_data_axi_eth_tx_dma 0x44AD0000
  phase_e_assert_addr SEG_data_axi_sched_dma 0x44AB0000
  phase_e_assert_addr SEG_data_awg_extension_0 0x44AE0000

  phase_e_assert_net_has_pin *axi_eth_rx_dma*irq* *sys_concat_intc/In10
  phase_e_assert_net_has_pin *axi_eth_tx_dma*irq* *sys_concat_intc/In9
  phase_e_assert_net_has_pin *axi_sched_dma*irq* *sys_concat_intc/In12

  foreach port {sfp0_ref_clk_p sfp0_ref_clk_n sfp0_rx_p sfp0_rx_n sfp0_tx_p sfp0_tx_n} {
    if {[llength [get_bd_ports -quiet $port]] != 1} {
      phase_e_fail "missing BD SFP0 port $port"
    }
  }

  set fh [open phase_e_logs/phase_e_bd_summary.txt w]
  puts $fh "Phase E BD validation passed"
  puts $fh "eth_mac_10g VLNV: $mac_vlnv"
  puts $fh "xxv_ethernet REQUIRES_LICENSE: $mac_license"
  puts $fh "Address segments:"
  set summary_segs {}
  foreach pattern {*eth_mac_10g* *axi_eth_rx_dma* *axi_eth_tx_dma* *axi_sched_dma*} {
    foreach seg [get_bd_addr_segs -quiet -hierarchical $pattern] {
      lappend summary_segs $seg
    }
  }
  foreach seg [lsort -unique $summary_segs] {
    puts $fh "  $seg OFFSET=[get_property OFFSET $seg] RANGE=[get_property RANGE $seg]"
  }
  close $fh

  puts "PHASE_E_BD_VALIDATE: passed"
}

if {[info exists argv0] && [file normalize $argv0] eq [file normalize [info script]]} {
  if {[llength $argv] > 0} {
    open_project [lindex $argv 0]
  }
  phase_e_validate_bd
}
