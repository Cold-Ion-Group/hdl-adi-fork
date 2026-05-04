# modified by Prerna Baranwal for kcu116 - ad9144

set dac_fifo_address_width 14

source $ad_hdl_dir/projects/common/kcu116/kcu116_system_bd.tcl
source $ad_hdl_dir/projects/common/xilinx/dacfifo_bd.tcl

# Avoid Vivado module-reference IP-XACT slicing s_axi_wdata/rdata into bogus
# per-bit interface arrays when packaging awg_timed_ctrl.
catch {set_param ips.enableInterfaceArrayInference false}

add_files -norecurse ../common/jesd_sysref_sync.v
source ../common/awg_bd.tcl
source $ad_hdl_dir/projects/scripts/adi_pd.tcl

#system ID
ad_ip_parameter axi_sysid_0 CONFIG.ROM_ADDR_BITS 9
ad_ip_parameter rom_sys_0 CONFIG.PATH_TO_FILE "[pwd]/mem_init_sys.txt"
ad_ip_parameter rom_sys_0 CONFIG.ROM_ADDR_BITS 9


set ADI_DAC_DEVICE $::env(ADI_DAC_DEVICE)
set ADI_DAC_MODE $::env(ADI_DAC_MODE)
set sys_cstring "$ADI_DAC_DEVICE - $ADI_DAC_MODE"
set sys_cstring "JESD:M=$ad_project_params(JESD_M)\
L=$ad_project_params(JESD_L)\
S=$ad_project_params(JESD_S)\
NP=$ad_project_params(JESD_NP)\
LINKS=$ad_project_params(NUM_LINKS)\
DEVICE_CODE=$ad_project_params(DEVICE_CODE)\
DAC_DEVICE=$ADI_DAC_DEVICE\
DAC_MODE=$ADI_DAC_MODE\
DAC_FIFO_ADDR_WIDTH=$dac_fifo_address_width"

sysid_gen_sys_init_file $sys_cstring

ad_ip_parameter axi_ad9144_jesd/tx CONFIG.SYSREF_IOB false
