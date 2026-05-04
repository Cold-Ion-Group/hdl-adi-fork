source ../../scripts/adi_env.tcl
source $ad_hdl_dir/library/scripts/adi_ip_xilinx.tcl

catch {set_param ips.enableInterfaceArrayInference false}

adi_ip_create awg_timed_ctrl
adi_ip_files awg_timed_ctrl [list \
  "$ad_hdl_dir/projects/awg/common/awg_timed_ctrl.v" \
]

adi_ip_properties awg_timed_ctrl

set cc [ipx::current_core]

ipx::infer_bus_interface sched_clk xilinx.com:signal:clock_rtl:1.0 $cc
ipx::infer_bus_interface sched_reset xilinx.com:signal:reset_rtl:1.0 $cc
ipx::infer_bus_interface irq xilinx.com:signal:interrupt_rtl:1.0 $cc

ipx::save_core $cc
