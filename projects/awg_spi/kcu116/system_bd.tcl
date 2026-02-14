# modified by Prerna Baranwal for kcu116 - ad9144

# TODO: modified this for dac fifo 
set dac_fifo_address_width 14
## Offload attributes
#set adc_offload_type 
#set adc_offload_size [expr 512 * 1024]


#TODO: left below, cross verification, 
#TODO: setting up the fifo algo 
#set dac_offload_type 0
#set dac_offload_size [expr 1 * 1024 * 1024]

#set plddr_offload_axi_data_width 0



source $ad_hdl_dir/projects/common/kcu116/kcu116_system_bd.tcl
source $ad_hdl_dir/projects/common/xilinx/dacfifo_bd.tcl
add_files -norecurse ../common/jesd_sysref_sync.v
source ../common/awg_bd.tcl
source $ad_hdl_dir/projects/scripts/adi_pd.tcl

#system ID
ad_ip_parameter axi_sysid_0 CONFIG.ROM_ADDR_BITS 9
ad_ip_parameter rom_sys_0 CONFIG.PATH_TO_FILE "[pwd]/mem_init_sys.txt"
ad_ip_parameter rom_sys_0 CONFIG.ROM_ADDR_BITS 9

#set sys_cstring "ADC_OFFLOAD_TYPE=$adc_offload_type\nDAC_OFFLOAD_TYPE=$dac_offload_type"

# TODO: modified it for making it DAC agnostic
set ADI_DAC_DEVICE $::env(ADI_DAC_DEVICE)
set ADI_DAC_MODE $::env(ADI_DAC_MODE)
set sys_cstring "$ADI_DAC_DEVICE - $ADI_DAC_MODE"
sysid_gen_sys_init_file $sys_cstring
ad_ip_parameter axi_ad9144_jesd/tx CONFIG.SYSREF_IOB false


ad_ip_parameter util_awg_xcvr CONFIG.QPLL_FBDIV 20
ad_ip_parameter util_awg_xcvr CONFIG.QPLL_REFCLK_DIV 1
ad_ip_parameter util_awg_xcvr CONFIG.CPLL_CFG0 0x67f8
ad_ip_parameter util_awg_xcvr CONFIG.CPLL_CFG1 0xa4ac
ad_ip_parameter util_awg_xcvr CONFIG.CPLL_CFG2 0x0007
