proc phase_e_post_fail {msg} {
  return -code error "PHASE_E_POST_VERIFY: $msg"
}

proc phase_e_report_has_severe {text} {
  return [regexp -nocase {(CRITICAL WARNING|ERROR:)} $text]
}

proc phase_e_check_cell_present {pattern} {
  if {[llength [get_cells -quiet -hierarchical $pattern]] == 0} {
    phase_e_post_fail "implemented design missing cell pattern $pattern"
  }
}

proc phase_e_source_extra_constraints {} {
  if {[file exists sfp0_clock_constr.tcl]} {
    source sfp0_clock_constr.tcl
  }
}

proc phase_e_post_impl_verify {{project_name awg_kcu116}} {
  file mkdir phase_e_logs
  set allow_license_block 0
  set synth_timing_status "not run"
  if {[info exists ::env(AWG_PHASE_E_ALLOW_LICENSE_BLOCK)] && $::env(AWG_PHASE_E_ALLOW_LICENSE_BLOCK) == 1} {
    set allow_license_block 1
  }

  if {[llength [get_runs synth_1]] != 0} {
    open_run synth_1 -name phase_e_synth_check
    phase_e_source_extra_constraints
    report_timing_summary -file phase_e_logs/phase_e_timing_synth_summary.rpt -warn_on_violation
    set synth_timing [report_timing_summary -return_string]
    if {[regexp -nocase {(VIOLATED|Timing constraints are not met)} $synth_timing]} {
      set synth_timing_status "violated; see phase_e_timing_synth_summary.rpt"
      puts "PHASE_E_POST_VERIFY: post-synthesis timing report has violations; archived for review"
    } else {
      set synth_timing_status "met"
    }
    close_design
  }

  open_run impl_1
  phase_e_source_extra_constraints

  foreach pattern {
    *eth_mac_10g*
    *axi_eth_rx_dma*
    *axi_eth_tx_dma*
    *axi_sched_dma*
    *awg_timed_ctrl_0*
  } {
    phase_e_check_cell_present $pattern
  }

  set setup_path [get_timing_paths -setup -max_paths 1]
  if {[llength $setup_path] != 0} {
    set setup_slack [get_property SLACK $setup_path]
    if {$setup_slack < 0} {
      phase_e_post_fail "negative setup slack $setup_slack"
    }
  }

  set hold_path [get_timing_paths -hold -max_paths 1]
  if {[llength $hold_path] != 0} {
    set hold_slack [get_property SLACK $hold_path]
    if {$hold_slack < 0} {
      phase_e_post_fail "negative hold slack $hold_slack"
    }
  }

  report_timing_summary -file phase_e_logs/phase_e_timing_impl_summary.rpt -warn_on_violation
  report_drc -file phase_e_logs/phase_e_drc.rpt
  report_methodology -file phase_e_logs/phase_e_methodology.rpt
  report_clock_interaction -file phase_e_logs/phase_e_clock_interaction.rpt
  report_utilization -hierarchical -file phase_e_logs/phase_e_utilization_hier.rpt
  check_timing -override_defaults no_clock -verbose -file phase_e_logs/phase_e_no_clock.rpt

  set timing_text [report_timing_summary -return_string]
  if {[regexp -nocase {(VIOLATED|Timing constraints are not met)} $timing_text]} {
    phase_e_post_fail "post-implementation timing summary reports violations"
  }

  foreach report_cmd {report_drc report_methodology} report_name {DRC methodology} {
    set report_text [$report_cmd -return_string]
    if {[phase_e_report_has_severe $report_text]} {
      phase_e_post_fail "$report_name has errors or critical warnings"
    }
  }

  set bit_file "$project_name.runs/impl_1/system_top.bit"
  set xsa_file "$project_name.sdk/system_top.xsa"
  set missing_outputs [list]
  if {![file exists $bit_file]} {
    lappend missing_outputs "bitstream $bit_file"
  }
  if {![file exists $xsa_file]} {
    lappend missing_outputs "hardware handoff $xsa_file"
  }
  if {[llength $missing_outputs] != 0 && !$allow_license_block} {
    phase_e_post_fail "missing [join $missing_outputs { and }]"
  }

  set fh [open phase_e_logs/phase_e_post_impl_summary.txt w]
  if {[llength $missing_outputs] == 0} {
    puts $fh "Phase E post-implementation verification passed"
  } else {
    puts $fh "Phase E routed verification passed; bitstream/handoff generation blocked"
    puts $fh "Missing outputs: [join $missing_outputs {; }]"
  }
  puts $fh "Vivado: [version]"
  puts $fh "Bitstream: $bit_file"
  puts $fh "XSA: $xsa_file"
  puts $fh "Post-synthesis timing: $synth_timing_status"
  if {[info exists setup_slack]} { puts $fh "Setup slack: $setup_slack" }
  if {[info exists hold_slack]} { puts $fh "Hold slack: $hold_slack" }
  close $fh

  if {[llength $missing_outputs] == 0} {
    puts "PHASE_E_POST_VERIFY: passed"
  } else {
    puts "PHASE_E_POST_VERIFY: routed checks passed with missing licensed outputs"
  }
}

if {[info exists argv0] && [file normalize $argv0] eq [file normalize [info script]]} {
  if {[llength $argv] > 0} {
    open_project [lindex $argv 0]
  }
  if {[llength $argv] > 1 && [lindex $argv 1] eq "allow_license_block"} {
    set ::env(AWG_PHASE_E_ALLOW_LICENSE_BLOCK) 1
  }
  phase_e_post_impl_verify
}
