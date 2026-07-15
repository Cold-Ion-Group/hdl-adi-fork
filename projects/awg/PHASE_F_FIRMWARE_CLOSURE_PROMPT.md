# Phase F Firmware Closure Prompt

Use this prompt as the firmware handoff for closing Phase F. Phase F is the
firmware/runtime closure layer on top of the already implemented Phase E HDL
datapaths. Do not treat this as an HDL change request unless a verified HDL ABI
defect is found.

## Prompt for the Firmware Engineer

You are joining the AWG firmware work after Phase E HDL closure. Your job is to
close the firmware and runtime data path for scheduler DMA refill and 10G
Ethernet streaming, using the existing HDL ABI. Do not assume undocumented
registers, XPAR names, PG203 management offsets, DMA behavior, clock rates, or
buffer addresses. Verify each one from the checked-out sources, generated XSA,
generated `xparameters.h`, or the relevant IP product guide before relying on it.

### Repositories and Current State

HDL repo:

- Path used during HDL work: `C:\Users\fpga_\yr\hdl-adi-fork`
- Current HDL branch observed: `control-plane-work`
- Current HDL commit observed: `2e31480ec awg: add Phase E HDL closure verification`
- Phase E HDL report: `projects/awg/PHASE_E_CLOSURE_REPORT.md`

Firmware repo:

- Path observed: `C:\Users\fpga_\yr\no-OS-adi-fork`
- Current firmware branch observed: `tmp-dump`
- Current firmware commit observed: `89b0bd3da gitmodule update to use pivate fork for our implementation of no-os`
- Current firmware state has no AWG scheduler driver modules yet. The existing
  `projects/fmcdac/src/app/fmcdac.c` is a monolithic AD9144/KCU116 bring-up app
  with an optional DAC DMA example. `projects/fmcdac/src.mk` already includes
  `drivers/axi_core/axi_dmac/axi_dmac.c`.
- The firmware worktree had modified submodules and untracked project docs when
  inspected. Preserve user-owned changes.

Build blocker from HDL closure:

- The Phase E design synthesized, implemented, and routed cleanly, but
  bitstream/XSA generation was blocked on the installed PG203 `xxv_ethernet`
  license. Full firmware/hardware closure requires a licensed bitstream and XSA.
- Do not claim Ethernet runtime closure until a licensed XSA/bitstream is used.

### HDL ABI Facts to Use

Scheduler base address in the KCU116 BD:

- `awg_timed_ctrl_0`: `0x44AA0000`
- `axi_sched_dma`: `0x44AB0000`
- `eth_mac_10g`: `0x44C00000`
- `axi_eth_rx_dma`: `0x44AC0000`
- `axi_eth_tx_dma`: `0x44AD0000`
- Existing DAC DMA `axi_ad9144_dma`: `0x7C420000`

Interrupt wiring in the KCU116 BD:

- `awg_timed_ctrl_0/irq`: `mb-14`, `ps-11`
- `axi_sched_dma/irq`: `mb-12`, `ps-13`
- `axi_eth_rx_dma/irq`: `mb-10`, `ps-14`
- `axi_eth_tx_dma/irq`: `mb-9`, `ps-15`
- Existing `axi_ad9144_jesd/irq`: `mb-15`, `ps-10`
- Existing `axi_ad9144_dma/irq`: `mb-13`, `ps-12`
- PG203 `eth_mac_10g` is currently polled; the selected configuration did not
  expose a discrete interrupt pin in the BD.

Scheduler stream ABI source of truth:

- HDL header: `projects/awg/common/awg_sched_regs.h`
- RTL: `projects/awg/common/awg_timed_ctrl.v`
- Firmware should mirror or include the header exactly for offsets, masks, event
  flags, and event size. Do not hand-maintain divergent constants.

Important scheduler register bits:

- `STATUS[0]`: armed
- `STATUS[1]`: running
- `STATUS[2]`: done
- `STATUS[3]`: error
- `STATUS[15:8]`: error code
- `STREAM_CTRL[0]`: stream mode enable
- `STREAM_CTRL[1]`: software write overflow sticky, write-one-to-clear
- `STREAM_CTRL[2]`: EOF seen, read-only
- `STREAM_CTRL[3]`: DMA ingress mode enable
- `IRQ_STATUS[4]`: low watermark sticky downward-crossing event
- `IRQ_STATUS[5]`: empty stall sticky event

Important scheduler behavior:

- Legacy fixed-length preload mode must remain bit-exact.
- Idle is represented by no active `STATUS` state bit set.
- `STREAM_CTRL.MODE` and `STREAM_CTRL.DMA_MODE` are captured at `CTRL.ARM` and
  locked for that run.
- `CTRL.STOP` aborts execution but does not flush the stream FIFO.
- `CTRL.RESET_SOFT` is the stream recovery path and flushes the FIFO.
- In software stream mode, writing `EVT_WCTRL.PUSH` attempts one atomic FIFO
  push and sets `STREAM_CTRL.OVERFLOW` if the FIFO is full.
- In DMA stream mode, `axi_sched_dma` drives the FIFO AXI-Stream port. FIFO
  fullness backpressures DMA with `tready`; software write overflow is not the
  expected DMA-mode full indication.
- `STREAM_DEPTH` is authoritative. Default HDL currently reports 511 usable
  events because `util_axis_fifo` usable depth is `2^STREAM_ADDR_WIDTH - 1`.
- `FREE_SPACE` is the hardware FIFO room value; use it as truth for refill.
- `OCCUPANCY` is derived from FIFO depth minus FIFO room.
- EOF is event `flags[1]` and is considered seen only after the EOF event
  successfully fires and is popped.
- Pre-fire errors must not be treated as consumed events.

Event format:

- Event size is 32 bytes.
- `EVT_WDATA0`: `timestamp[31:0]`
- `EVT_WDATA1`: `timestamp[63:32]`
- `EVT_WDATA2[15:0]`: `flags[15:0]`
- `EVT_WDATA2[31:16]`: `channel[15:0]`
- `EVT_WDATA3..6`: `payload[127:0]`
- Packed 256-bit DMA event word uses the same layout plus 32 reserved high bits.
- `flags[0]`: `PHASE_REINIT`
- `flags[1]`: `EOF`

Phase E DMA topology:

- `axi_sched_dma`: memory-to-AXIS, 256-bit source, 256-bit destination,
  non-cyclic, ID 2, DDR master on HP2. It pushes one 32-byte AWG event per DMA
  beat into `awg_timed_ctrl_0/dma_s_axis`.
- `axi_eth_rx_dma`: AXIS-to-memory, 64-bit MAC RX stream source, 256-bit DDR
  destination, non-cyclic, ID 3, DDR master on HP3.
- `axi_eth_tx_dma`: memory-to-AXIS, 256-bit DDR source, 64-bit MAC TX stream
  destination, non-cyclic, ID 4, DDR master on HP3.
- Existing `axi_ad9144_dma` remains the DAC waveform DMA and is unrelated to
  scheduler refill.

### Required Firmware Scope

Implement Phase F in small, reviewable pieces. Keep feature gates so existing
DDS/JESD bring-up continues to build and run without the new streaming path.

Suggested feature gates:

- `FMCDAC_AWG_SCHED`: scheduler driver and legacy/stream smoke tests
- `FMCDAC_AWG_SCHED_DMA_REFILL`: `axi_sched_dma` refill path
- `FMCDAC_AWG_SCHED_ETH`: PG203 MAC plus Ethernet RX/TX DMA transport

Required new or refactored firmware files:

- `projects/fmcdac/src/app/awg_sched_regs.h`
- `projects/fmcdac/src/app/awg_event.h`
- `projects/fmcdac/src/app/awg_sched.{c,h}`
- `projects/fmcdac/src/app/awg_stream_ring.{c,h}`
- `projects/fmcdac/src/app/awg_stream_proto.{c,h}`
- `projects/fmcdac/src/app/awg_eth_mac.{c,h}`
- `projects/fmcdac/src/app/awg_eth_rx.{c,h}`
- `projects/fmcdac/src/app/awg_eth_tx.{c,h}`
- Update `projects/fmcdac/src.mk`
- Update `projects/fmcdac/src/app/parameters.h`
- Update `projects/fmcdac/src/app/app_config.h`
- Integrate from `projects/fmcdac/src/app/fmcdac.c` without destabilizing
  existing AD9516, AD9144, JESD, DDS, and diagnostics paths.

### Phase F.0: Generated XSA and Constants Gate

Before implementing runtime behavior:

1. Generate or obtain a licensed Phase E XSA/bitstream.
2. Import the XSA into the firmware build and inspect generated `xparameters.h`.
3. Verify that generated base-address macros exist or add local fallbacks only
   with compile-time assertions against the expected addresses above.
4. Verify interrupt IDs from generated `xparameters.h`; do not guess names.
5. Confirm the MicroBlaze interrupt controller API already used by this no-OS
   tree, then add the required IRQ source file(s) to `src.mk` if missing.
6. Confirm cacheability and DDR address ranges for all DMA buffers.
7. Confirm the scheduler clock tick frequency used for event timestamps. The
   HDL scheduler clock is `util_awg_xcvr/tx_out_clk_0`; do not hardcode its
   frequency unless it is tied to the current JESD configuration in one
   documented constant.

Acceptance for F.0:

- Firmware build consumes the Phase E XSA.
- `parameters.h` has scheduler, scheduler DMA, Ethernet MAC, RX DMA, and TX DMA
  base addresses and IRQ IDs.
- `awg_sched_regs.h` matches the HDL header offsets and masks.
- Existing DDS/JESD firmware still builds with Phase F feature gates disabled.

### Phase F.1: Scheduler Driver and Software Stream Fallback

Implement the scheduler register driver first, before DMA or Ethernet:

- Probe `IP_ID`, `IP_VERSION`, and `STREAM_DEPTH`.
- Expose `awg_sched_read_status()`, `awg_sched_soft_reset()`,
  `awg_sched_set_stream_mode()`, `awg_sched_set_dma_mode()`,
  `awg_sched_set_low_wmark()`, `awg_sched_arm()`, `awg_sched_run()`,
  `awg_sched_stop()`, and IRQ clear helpers.
- Add `awg_sched_write_event_mmio()` shared by legacy preload and software
  stream fallback.
- Preserve legacy fixed-length mode: write event memory with `EVT_WADDR`,
  `EVT_WDATA0..6`, `EVT_WCTRL.PUSH`, set `EVENT_COUNT`, arm, run.
- Add software stream fallback from the Phase B contract, using `FREE_SPACE` and
  `STREAM_CTRL.OVERFLOW`.

Acceptance for F.1:

- Legacy finite scheduler sequence fires and reports `IRQ_DONE`.
- Software stream finite EOF sequence fires and reports `EOF_SEEN | IRQ_DONE`.
- `STREAM_DEPTH`, `FREE_SPACE`, and `OCCUPANCY` are logged and sane.
- `STOP` leaves FIFO contents intact; `RESET_SOFT` clears stream counters and
  FIFO occupancy.
- No existing DAC/DDS bring-up behavior regresses.

### Phase F.2: DMA-Backed Scheduler Refill

Implement the `axi_sched_dma` refill path:

- Use the existing ADI `axi_dmac` driver unless a verified driver defect blocks
  the work.
- Initialize `axi_sched_dma` as memory-to-device with IRQ enabled.
- In this no-OS driver, `axi_dmac_transfer_start()` detects direction by probing
  memory-mapped source/destination registers. For memory-to-AXIS, only
  `src_addr` is written; `dest_addr` is ignored by direction logic. Verify this
  in the exact driver revision before relying on it.
- Create a DDR event ring of 32-byte aligned `awg_event_v1_t` entries.
- Keep producer and MicroBlaze-read indices separate.
- Never submit a single DMA transfer that crosses the physical ring end.
- Submit at most `min(ring_avail, FREE_SPACE, contiguous_to_ring_end,
  DMA_MAX_EVENTS)` events.
- Flush data cache for the source event range before starting scheduler DMA.
- Maintain one scheduler DMA in flight unless the driver and hardware are
  explicitly proven to queue safely.
- On scheduler DMA EOT, advance the ring read pointer by the number of submitted
  events, clear in-flight state, and immediately resubmit if ring data and FIFO
  free space remain.
- On scheduler low-watermark IRQ, set a lightweight refill-pending flag. Keep
  large DMA submission work in foreground or a bounded deferred handler.

Acceptance for F.2:

- DMA mode is selected by writing `STREAM_CTRL.MODE | STREAM_CTRL.DMA_MODE`
  before `CTRL.ARM`.
- A finite sequence DMA-refills into the scheduler FIFO and reaches EOF cleanly.
- `STREAM_PUSHES` increases by one per 32-byte DMA event beat.
- `STREAM_STALLS` remains zero when the ring has sufficient prefetched events.
- Ring wrap is tested by forcing `read_index` near the ring end and proving that
  the transfer is split correctly.
- Scheduler DMA EOT IRQ is handled without losing events.
- Software stream fallback still works when `DMA_MODE` is disabled.

### Phase F.3: 10G MAC Bring-Up

Bring up `eth_mac_10g` only after F.2 is stable:

- Use PG203 `xxv_ethernet` v4.0 documentation and generated IP collateral for
  the exact AXI-Lite register map.
- Do not invent MAC management offsets.
- Configure/reset the MAC and PCS/PMA as required for 10G BASE-R SFP0.
- Control `sfp0_tx_disable` through GPIO bit 26. Clear it to enable the SFP TX.
- Poll MAC/link status at `0x44C00000`; no MAC interrupt is wired in the HDL.
- Log link-up state, block lock, local/remote fault status, and any available
  error/statistics counters.

Acceptance for F.3:

- Firmware can reset/configure the MAC and report link status.
- SFP0 TX disable is controlled intentionally.
- Link-up and link-down cases are distinguishable in logs.
- MAC polling does not block the scheduler DMA refill path.

### Phase F.4: Ethernet RX/TX DMA Transport

Implement Ethernet frame movement with ADI DMAC:

- `axi_eth_rx_dma`: device-to-memory, MAC RX AXIS to DDR.
- `axi_eth_tx_dma`: memory-to-device, DDR to MAC TX AXIS.
- Use 64-byte minimum Ethernet frame handling and align buffers to 32 bytes or
  stricter if cacheline size requires it.
- For RX, start with a small number of fixed DDR frame buffers or ping-pong
  buffers. The ADI DMAC has no hardware scatter-gather descriptor ring here, so
  firmware must re-arm after each completed frame or batch.
- Invalidate RX cache ranges after RX DMA EOT and before parsing.
- Flush TX cache ranges before TX DMA start.
- Confirm from DMAC status or transfer metadata how many bytes were received
  for each RX frame; if the driver does not expose this cleanly, add a small,
  reviewed helper rather than guessing frame length.
- TX path is required for ARP replies, optional ping replies, ACK/status frames,
  and diagnostics.

Acceptance for F.4:

- RX DMA receives raw Ethernet frames into DDR.
- TX DMA transmits a known raw Ethernet frame.
- RX/TX EOT interrupts are handled and counted.
- No DMA buffer crosses an invalid DDR boundary.
- Cache maintenance is proven with changing payload patterns.

### Phase F.5: Minimal Network and Stream Protocol

Implement only the minimum network stack needed for the AWG stream:

- Static MAC address and static IPv4 address.
- ARP responder for the FPGA IP.
- Optional ICMP echo responder for bring-up.
- UDP receive filter by destination MAC/IP/port.
- UDP transmit for ACK/status frames.
- No TCP, DHCP, or lwIP unless explicitly approved.

Use a transport-independent stream protocol parser. The same parser should be
usable from UART/debug paths and Ethernet RX.

Recommended frame:

```text
u32 magic      // 0x53415747, "GWAS" little endian
u32 seq
u16 n_events
u16 flags      // bit0=open, bit1=close_with_eof
awg_event_v1_t events[n_events]
u32 crc32_ieee
```

Recommended ACK:

```text
u32 magic
u32 seq_acked
u32 ddr_free_events
u32 status
u32 stream_free_events
u32 stream_stalls
u32 irq_status
```

Acceptance for F.5:

- Host can resolve FPGA MAC by ARP.
- Host can send UDP event frames that firmware validates by magic, length, seq,
  and CRC.
- Valid events enter the DDR event ring and are drained by scheduler DMA.
- Bad CRC, bad sequence, unsupported flags, ring-full, scheduler hard error, and
  DMA error produce distinct status bits.
- ACK/status TX works through `axi_eth_tx_dma`.

### Phase F.6: Host and Runtime Verification

Provide a host sender that can run deterministic tests and stress tests:

- Static IP/MAC configuration.
- Event-frame construction.
- CRC32 and sequence numbers.
- Rate control and burst mode.
- Optional ACK wait and retransmit policy.
- Telemetry capture from firmware logs or a debug register/serial path.

Required bench tests:

1. Legacy scheduler finite sequence still passes.
2. Software stream fallback finite EOF sequence passes.
3. DMA refill finite EOF sequence passes.
4. DMA refill ring-wrap test passes.
5. Ethernet ARP and optional ping pass.
6. UDP RX/TX DMA smoke passes with known payload.
7. UDP-to-event-ring-to-scheduler-DMA-to-EOF path passes.
8. Sustained stream at increasing rates records:
   - `COMMIT_COUNT`
   - `STREAM_PUSHES`
   - `STREAM_STALLS`
   - `IRQ_STATUS`
   - `OCCUPANCY`
   - `FREE_SPACE`
   - scheduler DMA EOT/error counts
   - Ethernet RX/TX counts and CRC/drop counts
9. Long soak records zero scheduler errors and no unbounded backlog at the
   selected acceptance rate.

Do not claim Regime C until the event-rate target, transport bandwidth, queue
occupancy, and analog/timing evidence are all captured. The HDL Regime C target
is 130 ns event spacing, about 7.692 ME/s, which is about 246 MB/s of raw
32-byte event payload before UDP/Ethernet framing.

### Implementation Rules

- Keep legacy behavior intact and test it every time.
- Keep ISR work bounded. Use ISR flags plus foreground drain/re-arm work unless
  a short ISR is proven sufficient.
- Read `STREAM_DEPTH` at runtime; never hardcode 511.
- Use `FREE_SPACE` as hardware truth for scheduler FIFO refill.
- Treat low-watermark IRQ as an edge, not a level. Include periodic or
  opportunistic drain paths.
- Use `RESET_SOFT` after stream overflow, hard scheduler error, or any aborted
  stream recovery.
- Do not modify HDL to work around firmware uncertainty. Escalate only with a
  minimal failing test and register/DMA evidence.
- Preserve existing no-OS build style and avoid large framework imports.

### Artifacts Required for Closure

Provide a Phase F firmware closure report with:

- HDL commit hash and firmware commit hash.
- XSA/bitstream path and Vivado version.
- XPAR base address and IRQ table generated from the XSA.
- Feature flags used for each test.
- Scheduler ABI probe output: `IP_ID`, `IP_VERSION`, `STREAM_DEPTH`.
- DMA capability probe output for all three Phase E DMAs.
- MAC link/status log.
- Test matrix with pass/fail and logs.
- Sustained-rate results and queue telemetry.
- Any residual warnings or known limits.

## Non-Goals for Phase F

- New HDL transport features.
- New PG203 interrupt wiring.
- lwIP/TCP/DHCP.
- RFSoC measurement appliance implementation.
- Publication-grade analog/RF proof. Phase F should expose the runtime stream
  path needed for that work, but analog publication closure is a later
  measurement phase.
