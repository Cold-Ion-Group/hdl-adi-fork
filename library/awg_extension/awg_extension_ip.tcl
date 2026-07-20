source ../../scripts/adi_env.tcl
source $ad_hdl_dir/library/scripts/adi_ip_xilinx.tcl

adi_ip_create awg_extension
adi_ip_files awg_extension [list \
  "$ad_hdl_dir/projects/awg/common/awg_extension.v" \
]
adi_ip_properties awg_extension

set cc [ipx::current_core]
set_property version {1.0} $cc

adi_add_bus "s_axis" "slave" \
  "xilinx.com:interface:axis_rtl:1.0" \
  "xilinx.com:interface:axis:1.0" \
  [list {"s_axis_tready" "TREADY"} {"s_axis_tvalid" "TVALID"} {"s_axis_tdata" "TDATA"}]
adi_add_bus "m_axis" "master" \
  "xilinx.com:interface:axis_rtl:1.0" \
  "xilinx.com:interface:axis:1.0" \
  [list {"m_axis_tready" "TREADY"} {"m_axis_tvalid" "TVALID"} {"m_axis_tdata" "TDATA"}]
adi_add_bus_clock "s_axi_aclk" "s_axi:s_axis:m_axis" "s_axi_aresetn"

ipx::save_core $cc
