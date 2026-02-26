source ../../../scripts/adi_env.tcl
source $ad_hdl_dir/projects/scripts/adi_project_xilinx.tcl
source $ad_hdl_dir/projects/scripts/adi_board.tcl

adi_project template_kcu116
adi_project_files template_kcu116 [list \
  "$ad_hdl_dir/library/common/ad_iobuf.v" \
  "$ad_hdl_dir/projects/common/kcu116/kcu116_system_constr.xdc" \
  "system_constr.xdc"\
  "$ad_hdl_dir/projects/common/kcu116/kcu116_system_lutram_constr.xdc" \
  "system_top.v" ]
  
adi_project_run template_kcu105
