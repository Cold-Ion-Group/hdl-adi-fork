####################################################################################
# Created by Prerna Baranwal for using KCU116 and AD9144 
####################################################################################

PROJECT_NAME := awg_kcu116
# TODO: removed spi as its not required at this stage 
M_DEPS += ../common/awg_spi.v 
M_DEPS += ../common/awg_bd.tcl
M_DEPS += ../common/config.tcl

M_DEPS += ../../scripts/adi_pd.tcl
#M_DEPS += ../../common/xilinx/data_offload_bd.tcl
# TODO: removed data off load and added dacfifo_bd
M_DEPS += ../../common/xilinx/dacfifo_bd.tcl
#####
M_DEPS += ../../common/kcu116/kcu116_system_constr.xdc
M_DEPS += ../../common/kcu116/kcu116_system_bd.tcl
######
#TODO removing this as its not involved in the data off load and weare not using this in this code. 
#M_DEPS += ../../../library/util_hbm/scripts/adi_util_hbm.tcl



M_DEPS += ../../../library/jesd204/scripts/jesd204.tcl
M_DEPS += ../../../library/common/ad_iobuf.v

LIB_DEPS += axi_dmac
LIB_DEPS += axi_sysid
#LIB_DEPS += data_offload
#LIB_DEPS += jesd204/ad_ip_jesd204_tpl_adc
LIB_DEPS += jesd204/ad_ip_jesd204_tpl_dac
#LIB_DEPS += jesd204/axi_jesd204_rx
LIB_DEPS += jesd204/axi_jesd204_tx
#LIB_DEPS += jesd204/jesd204_rx
LIB_DEPS += jesd204/jesd204_tx
LIB_DEPS += sysid_rom
LIB_DEPS += util_dacfifo
#LIB_DEPS += util_do_ram
#LIB_DEPS += util_hbm
#LIB_DEPS += util_pack/util_cpack2
LIB_DEPS += util_pack/util_upack2
LIB_DEPS += xilinx/axi_adxcvr
LIB_DEPS += xilinx/util_adxcvr

include ../../scripts/project-xilinx.mk
