####################################################################################
# Created by Prerna Baranwal for using KCU116 and AD9144 
####################################################################################

PROJECT_NAME := awg_kcu116

M_DEPS += ../common/awg_spi.v 
M_DEPS += ../common/jesd_sysref_sync.v
M_DEPS += ../common/awg_bd.tcl
M_DEPS += ../common/config.tcl
M_DEPS += sfp0_system_constr.xdc

M_DEPS += ../../scripts/adi_pd.tcl
M_DEPS += ../../common/xilinx/dacfifo_bd.tcl
M_DEPS += ../../common/kcu116/kcu116_system_constr.xdc
M_DEPS += ../../common/kcu116/kcu116_system_bd.tcl



M_DEPS += ../../../library/jesd204/scripts/jesd204.tcl
M_DEPS += ../../../library/common/ad_iobuf.v

LIB_DEPS += axi_dmac
LIB_DEPS += axi_sysid
LIB_DEPS += awg_timed_ctrl
LIB_DEPS += jesd204/ad_ip_jesd204_tpl_dac
LIB_DEPS += jesd204/axi_jesd204_tx
LIB_DEPS += jesd204/jesd204_tx
LIB_DEPS += sysid_rom
LIB_DEPS += util_dacfifo
LIB_DEPS += util_pack/util_upack2
LIB_DEPS += xilinx/axi_adxcvr
LIB_DEPS += xilinx/util_adxcvr

include ../../scripts/project-xilinx.mk
