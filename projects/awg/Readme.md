# AWG HDL Project
# Designed and developed by Prerna Baranwal 
Hardware used: AD9144, KCU116
Libraries used: https://github.com/analogdevicesinc/
Vivado version: 2021.R2

## Scheduler documentation

- `STREAMING_SCHEDULER_PHASE_B_FIRMWARE.md` documents the Phase A/B software-refill stream ABI and remains the fallback contract.
- `PHASE_E_CLOSURE_REPORT.md` records the current HDL/build state: scheduler DMA ingress, SFP0 10G MAC, Ethernet RX DMA, Ethernet TX DMA, routed timing, and the PG203 bitstream-license blocker.
- `PHASE_F_FIRMWARE_CLOSURE_PROMPT.md` is the firmware handoff for closing runtime scheduler DMA refill and 10G UDP transport on top of the Phase E HDL.
- `SYSTEM_OVERVIEW.md` and `SYSTEM_BLOCK_DIAGRAM_AND_DATAPATHS.md` summarize the current KCU116/AD9144 system and datapaths.
