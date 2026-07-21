# Phase E HDL/Build Closure Report

Scope: HDL/build-only closure for E.1 scheduler DMA refill plus E.2 10G SFP0 MAC, RX DMA, and TX DMA. Firmware, UDP, ARP, host transport, and live stream runtime validation are deferred.

## Source Status

- Verification date: 2026-07-15.
- Vivado: 2021.2, SW Build 3367213, IP Build 3369179.
- Git base commit verified: `7eafe892e`.
- Phase E closure commit: `2e31480ec`.
- E.1 commits are present through scheduler DMA mode, KCU116 scheduler DMA BD wiring, and DMA-mode regressions.
- E.2 HDL datapath commit is present with XXV Ethernet v4.0 (`xxv_ethernet`,
  documented by PG210), RX DMA, and TX DMA.
- SFP0 pin source: AMD/Xilinx KCU116 Board User Guide UG1239 v1.3, Tables 3-8 and 3-10.
- UG1239 shows SFP0 GT pins and `SFP0_TX_DISABLE_B` are FPGA-connected. `SFP_TX_FAULT`, `SFP_MOD_DETECT`, `SFP_LOS`, and RS0/RS1 are test-point/resistor/I2C features, so they are not constrained as FPGA top-level pins.

## Commands Run

From repo root:

```powershell
powershell -ExecutionPolicy Bypass -File projects\awg\common\tb\run_awg_scheduler_regression.ps1 -VivadoBat C:\Xilinx\Vivado\2021.2\bin\vivado.bat
```

From `projects/awg/kcu116`:

```powershell
powershell -ExecutionPolicy Bypass -File .\phase_e_build.ps1 -SkipSchedulerRegression -VivadoBat C:\Xilinx\Vivado\2021.2\bin\vivado.bat
C:\Xilinx\Vivado\2021.2\bin\vivado.bat -mode batch -source phase_e_post_impl_verify.tcl -notrace -tclargs awg_kcu116.xpr allow_license_block
```

The Vivado build commands were run outside the sandbox because local Vivado child-runner scripts use Windows WMI and fail in the sandbox with `rundef.js` access denied.

## Acceptance Status

- Scheduler regression: PASS.
  - Fresh all-pass work root: `projects/awg/common/tb/phase_e_scheduler_regression/20260715_110142`.
  - Benches covered: legacy AXI preload, stream mode lock, empty wait, EOF, hard underrun, low watermark, software overflow, soft reset flush, DMA mux, DMA backpressure/full, DMA stop vs soft reset, stream occupancy/free-space rollover.
- BD validation: PASS.
  - `phase_e_logs/phase_e_bd_summary.txt` confirms `eth_mac_10g` VLNV `xilinx.com:ip:xxv_ethernet:4.0`, `REQUIRES_LICENSE=1`, and address segments:
  - `eth_mac_10g @ 0x44C00000`
  - `axi_eth_rx_dma @ 0x44AC0000`
  - `axi_eth_tx_dma @ 0x44AD0000`
  - `axi_sched_dma @ 0x44AB0000`
- Synthesis/implementation: routed implementation completed, then bitstream
  generation failed because the XXV Ethernet core was not licensed.
  - `impl_1/runme.log` reports `write_bitstream failed` for encrypted cell `eth_mac_10g/.../i_system_eth_mac_10g_0_CORE`.
  - This is a license blocker, not an HDL/timing blocker.
- Routed timing: PASS.
  - `phase_e_logs/phase_e_timing_impl_summary.rpt`: WNS `0.503 ns`, TNS `0.000 ns`, WHS `0.010 ns`, THS `0.000 ns`.
  - `phase_e_logs/phase_e_no_clock.rpt`: `no_clock (0)`.
- DRC: PASS with warnings/advisories only.
  - `phase_e_logs/phase_e_drc.rpt`: 42 total violations, no errors or critical warnings.
- Methodology: PASS with warnings only.
  - `phase_e_logs/phase_e_methodology.rpt`: no errors or critical warnings. Remaining warnings are mostly XXV Ethernet/debug-hub reset/CDC methodology warnings and existing timing-exception warnings.
- Bitstream/XSA: BLOCKED.
  - Missing `awg_kcu116.runs/impl_1/system_top.bit` and `awg_kcu116.sdk/system_top.xsa` because XXV Ethernet bitstream generation is not licensed on this installation.

## Artifacts

- Scheduler regression logs: `projects/awg/common/tb/phase_e_scheduler_regression/20260715_110142/`.
- Main build log: `projects/awg/kcu116/phase_e_logs/phase_e_vivado_build.log`.
- BD summary: `projects/awg/kcu116/phase_e_logs/phase_e_bd_summary.txt`.
- Post-route summary: `projects/awg/kcu116/phase_e_logs/phase_e_post_impl_summary.txt`.
- Timing summaries: `projects/awg/kcu116/phase_e_logs/phase_e_timing_synth_summary.rpt`, `projects/awg/kcu116/phase_e_logs/phase_e_timing_impl_summary.rpt`.
- DRC/methodology/clock/utilization reports: `projects/awg/kcu116/phase_e_logs/phase_e_drc.rpt`, `phase_e_methodology.rpt`, `phase_e_clock_interaction.rpt`, `phase_e_utilization_hier.rpt`.

## Residual Items

- Install a full XXV Ethernet v4.0 license, then reset/regenerate
  `eth_mac_10g` output products and rerun `phase_e_build.ps1` without
  `allow_license_block`.
- After licensed bitstream generation succeeds, rerun `phase_e_post_impl_verify.tcl` without `allow_license_block` so the bitstream and XSA checks become hard pass/fail gates.
- Close Phase F firmware/runtime work using `PHASE_F_FIRMWARE_CLOSURE_PROMPT.md`:
  scheduler driver, DDR event ring, scheduler DMA refill, XXV Ethernet MAC bring-up,
  Ethernet RX/TX DMA, minimal ARP/UDP transport, host sender, and runtime soak.
