# code to select the DAC and the configuration mode, written from scratch.
# Prerna Baranwal, KCU116 + AD9144 
# TODO: check which mode needs to be setup for correct communication 
set device AD9144
set mode   04

if [info exists ::env(ADI_DAC_DEVICE)] {
  set device $::env(ADI_DAC_DEVICE)
} else {
  set env(ADI_DAC_DEVICE) $device
}

if [info exists ::env(ADI_DAC_MODE)] {
  set mode $::env(ADI_DAC_MODE)
} else {
  set env(ADI_DAC_MODE) $mode
}

#  1 - Single link
#  2 - Dual link
set num_links 1

# AD9144/AD9154
#                 Mode M L S F HD N NP
set params(AD9144,00) {4 8 1 1 1 16 16}
set params(AD9144,01) {4 8 2 2 0 16 16}
set params(AD9144,02) {4 4 1 2 0 16 16}
set params(AD9144,03) {4 2 1 4 0 16 16}
set params(AD9144,04) {2 4 1 1 1 16 16}
set params(AD9144,05) {2 4 2 2 0 16 16}
set params(AD9144,06) {2 2 1 2 0 16 16}
set params(AD9144,07) {2 1 1 4 0 16 16}
set params(AD9144,09) {1 2 1 1 1 16 16}
set params(AD9144,10) {1 1 1 2 0 16 16}
set params(AD9144,device_code) 1

set device_code $params($device,device_code)


proc get_config_param {param} {
  upvar device device
  upvar mode mode
  upvar params params

  set jesd_params {M L S F HD N NP}
  set index [lsearch $jesd_params $param]

  return [lindex $params($device,$mode) $index]
}

