# modified by Prerna Baranwal for kcu 116, ad 9144 
source ../../../scripts/adi_env.tcl
source $ad_hdl_dir/projects/scripts/adi_project_xilinx.tcl
source $ad_hdl_dir/projects/scripts/adi_board.tcl
source ../common/config.tcl

# get_env_param retrieves parameter value from the environment if exists,
# other case use the default value
#


# Parameter description:
#  JESD_M : Number of converters per link
#   JESD_L : Number of lanes per link
#   JESD_S : Number of samples per frame

adi_project awg_kcu116 0 [list \
  JESD_M    [get_config_param M] \
  JESD_L    [get_config_param L] \
  JESD_S    [get_config_param S] \
  JESD_NP   [get_config_param NP] \
  NUM_LINKS $num_links \
  DEVICE_CODE $device_code \
]

adi_project_files awg_kcu116 [list \
"../common/awg_spi.v" \
  "system_top.v" \
  "system_constr.xdc"\
  "$ad_hdl_dir/library/common/ad_iobuf.v" \
  "$ad_hdl_dir/projects/common/kcu116/kcu116_system_constr.xdc" ]

## To improve timing in DDR4 MIG
# not that relevant
set_property strategy Performance_Retiming [get_runs impl_1]

adi_project_run awg_kcu116

