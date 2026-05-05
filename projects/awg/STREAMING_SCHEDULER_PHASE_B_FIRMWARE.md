# Streaming Scheduler Phase B Firmware Handoff

This document freezes the firmware contract for the Phase A HDL stream-mode scheduler and scopes the Phase B firmware work. It intentionally covers firmware, DDR staging, ISR policy, and host framing. It does not require more HDL work unless the ABI below is violated.

## Phase A ABI Status

The firmware ABI is frozen in:

- `projects/awg/common/awg_sched_regs.h`
- `projects/awg/common/awg_timed_ctrl.v`

Firmware should copy or include the constants from `awg_sched_regs.h`. If a no-OS tree keeps its own mirrored header, keep it byte-for-byte equivalent for offsets, bit masks, IRQ bits, and event flags.

The IP identity contract is:

- `IP_ID = 0x41574753`
- `IP_VERSION = 0x00010000`
- `IP_CAPS[31:24] = legacy event memory address width`
- `IP_CAPS[23:16] = payload bits = 128`
- `IP_CAPS[15:8] = timestamp bits = 64`
- `STREAM_DEPTH` register is the authoritative stream FIFO capacity in events

Do not hardcode the stream FIFO depth in firmware. Read `STREAM_DEPTH` at startup and derive defaults from it.

## Register Summary

Base address in the current KCU116 design is `0x44AA0000`.

| Offset | Name | Firmware Use |
| --- | --- | --- |
| `0x00` | `CTRL` | Write command bits: run, arm, stop, soft reset, IRQ gate |
| `0x04` | `STATUS` | Read state and error code |
| `0x08` | `EVENT_COUNT` | Legacy fixed-length mode only |
| `0x10` | `ERR_REG` | Low-cost error-code readback, mirrors `STATUS[15:8]` |
| `0x14` | `IP_ID` | Probe for scheduler presence |
| `0x18` | `IP_VERSION` | ABI version check |
| `0x1C` | `IP_CAPS` | Legacy capability discovery |
| `0x3C` | `IRQ_STATUS` | Sticky W1C IRQ vector |
| `0x40` | `EVT_WADDR` | Legacy preload address only |
| `0x44..0x5C` | `EVT_WDATA0..6` | Event shadow registers |
| `0x60` | `EVT_WCTRL` | Write `PUSH` to commit one event |
| `0x64` | `IRQ_ENABLE` | IRQ mask |
| `0x78` | `STREAM_CTRL` | Stream mode control and stream-only sticky flags |
| `0x7C` | `OCCUPANCY` | Current stream FIFO occupancy in events |
| `0x80` | `FREE_SPACE` | Current stream FIFO free space in events |
| `0x84` | `LOW_WMARK` | Runtime low-watermark threshold in events |
| `0x88` | `STREAM_DEPTH` | Stream FIFO capacity in events |
| `0x8C` | `STREAM_PUSHES` | Accepted stream pushes since reset/soft reset |
| `0x90` | `STREAM_STALLS` | Scheduler cycles spent waiting on empty stream FIFO |

`CTRL` command bits are `RUN=bit0`, `ARM=bit1`, `STOP=bit2`, `RESET_SOFT=bit3`, and `IRQ_ENABLE=bit8`. `TIME_RELOAD_CTRL` owns time-load commands: `ARM_ON_SYSREF=bit0`, `LOAD_NOW=bit1`.

## Event Format

Each event is written as seven 32-bit MMIO words followed by `EVT_WCTRL.PUSH`.

| Register | Event Field |
| --- | --- |
| `EVT_WDATA0` | `timestamp[31:0]` |
| `EVT_WDATA1` | `timestamp[63:32]` |
| `EVT_WDATA2[15:0]` | `flags[15:0]` |
| `EVT_WDATA2[31:16]` | `channel[15:0]` |
| `EVT_WDATA3` | `payload[31:0]` |
| `EVT_WDATA4` | `payload[63:32]` |
| `EVT_WDATA5` | `payload[95:64]` |
| `EVT_WDATA6` | `payload[127:96]` |

Defined event flags:

- `flags[0] = PHASE_REINIT`
- `flags[1] = EOF`

EOF means the event is applied normally. After that successful fire and FIFO pop, the engine transitions to `DONE` and sets `STREAM_CTRL.EOF_SEEN`.

## Stream-Mode Semantics

Legacy mode remains the fixed-length preload path:

1. Write events into `EVT_WADDR` + `EVT_WDATA0..6` + `EVT_WCTRL.PUSH`.
2. Write `EVENT_COUNT`.
3. Arm and run with `STREAM_CTRL.MODE = 0`.

Stream mode changes only the destination of `EVT_WCTRL.PUSH`:

1. Set `STREAM_CTRL.MODE = 1` before `CTRL.ARM`.
2. Push events by writing `EVT_WDATA0..6`, then `EVT_WCTRL.PUSH`.
3. The push is atomic at `EVT_WCTRL`.
4. If the stream FIFO is full, the event is refused, `STREAM_CTRL.OVERFLOW` is set, and `STREAM_PUSHES` does not increment.
5. `EVENT_COUNT` and `EVT_WADDR` remain readable/writable but are ignored by stream execution.

`STREAM_CTRL.MODE` is captured at `ARM`. Changing it while armed/running does not affect the active shot. To change mode, stop or reset, then arm again.

`CTRL.STOP` aborts execution but does not flush stream FIFO contents.

`CTRL.RESET_SOFT` flushes the stream FIFO, clears stream-only counters/flags, clears `EOF_SEEN`, and returns the engine to clean idle.

## IRQ Contract

`IRQ_STATUS` is sticky write-one-to-clear.

| Bit | Name | Meaning |
| --- | --- | --- |
| `0` | `DONE` | Shot completed cleanly |
| `1` | `ERROR` | Any hard scheduler error |
| `2` | `SPACING_VIOLATION` | Event spacing/reinit spacing violation |
| `3` | `UNDERRUN` | Hard missed-deadline companion |
| `4` | `LOW_WATERMARK` | Stream FIFO crossed downward to `OCCUPANCY <= LOW_WMARK` |
| `5` | `EMPTY_STALL` | Stream engine entered empty wait |

`LOW_WATERMARK` is an edge event only. Firmware must not rely on repeated IRQs while occupancy stays below threshold. Phase B must therefore include a polled or opportunistic refill path in addition to the IRQ path.

`EMPTY_STALL` is not a hard error by itself. It means the stream engine is waiting for the next event. If the next event later arrives late relative to the scheduler time, the existing missed-deadline path raises `ERROR | UNDERRUN` with `ERR_MISSED_DEADLINE`.

## Required Firmware API

Add these APIs without changing the existing legacy preload API:

```c
typedef struct {
    void     *staging_buffer;
    uint32_t  staging_capacity;
    uint32_t  low_wmark_events;
    uint32_t  refill_chunk_max;
    uint32_t  poll_interval_us;
} awg_sched_stream_cfg_t;

int  awg_sched_stream_open(const awg_sched_stream_cfg_t *cfg);
int  awg_sched_stream_push(const awg_event_v1_t *ev, uint32_t n);
int  awg_sched_stream_drain_step(void);
int  awg_sched_stream_close(bool send_eof);
void awg_sched_stream_irq_handler(uint32_t irq_status);
```

Expected responsibilities:

- `open`: validate IP ID/version, read `STREAM_DEPTH`, configure `LOW_WMARK`, allocate or attach DDR staging ring, set stream mode, clear stale IRQs and overflow state.
- `push`: append host-provided events to the DDR staging ring, then opportunistically call `drain_step`.
- `drain_step`: move as many events as allowed from DDR staging into the HDL stream FIFO.
- `close`: mark the final staged event with EOF, or append a zero-payload EOF event if needed.
- `irq_handler`: acknowledge stream IRQ bits and set a lightweight refill-pending flag; do not perform large MMIO bursts inside the ISR.

## DDR Staging Ring

Use DDR as a software ring of `awg_event_v1_t` entries.

Recommended defaults:

- `staging_capacity = 32768` events, about 1 MiB at 32 bytes/event
- `low_wmark_events = STREAM_DEPTH / 4`
- `refill_chunk_max = min(128, STREAM_DEPTH / 4)`
- `poll_interval_us = 1000`

The ring should track at least:

- producer write index
- MicroBlaze drain/read index
- capacity
- overflow or drop policy

Use power-of-two capacity if possible so index wrap is cheap and unambiguous.

## Refill Policy

Phase B must use three refill triggers:

1. IRQ-driven: on `IRQ_LOW_WATERMARK`, ISR sets `g_refill_pending = 1`.
2. Opportunistic: `awg_sched_stream_push()` calls `awg_sched_stream_drain_step()` after appending to DDR.
3. Periodic: main loop calls `awg_sched_stream_drain_step()` every `poll_interval_us`.

`drain_step` must be idempotent. It should read fresh hardware and DDR state every call:

```c
free_space = reg_read(FREE_SPACE);
ddr_avail = ring_available();
n = min(free_space, ddr_avail, refill_chunk_max);

for (i = 0; i < n; i++)
    awg_sched_write_one_event(&ring[read_index++]);
```

Clear `g_refill_pending` only after a drain attempt observes no immediate work or fills the HDL FIFO. Treat the flag as a hint, not as a counted queue.

## MMIO Write Helper

Refactor the existing legacy event write sequence into a shared helper:

```c
static int awg_sched_write_one_event(const awg_event_v1_t *ev)
{
    reg_write(EVT_WDATA0, lower_32(ev->timestamp));
    reg_write(EVT_WDATA1, upper_32(ev->timestamp));
    reg_write(EVT_WDATA2, ((uint32_t)ev->channel << 16) | ev->flags);
    reg_write(EVT_WDATA3, ev->payload[0]);
    reg_write(EVT_WDATA4, ev->payload[1]);
    reg_write(EVT_WDATA5, ev->payload[2]);
    reg_write(EVT_WDATA6, ev->payload[3]);
    reg_write(EVT_WCTRL, AWG_SCHED_EVT_WCTRL_PUSH);

    if (reg_read(STREAM_CTRL) & AWG_SCHED_STREAM_CTRL_OVERFLOW)
        return -EAGAIN;

    return 0;
}
```

Legacy mode should set `EVT_WADDR` before this helper. Stream mode should not touch `EVT_WADDR`.

For stream mode, checking `FREE_SPACE` before writing is the fast path. Checking `STREAM_CTRL.OVERFLOW` after writing is the defensive path.

## Host Frame Parser

The firmware parser should be transport-independent. UART, Ethernet, and debug transports should all feed the same byte-stream parser.

Proposed frame:

```text
u32 magic      // 0x53415747, "GWAS" in little endian
u32 seq
u16 n_events
u16 flags      // bit0=open, bit1=close_with_eof
awg_event_v1_t events[n_events]
u32 crc32_ieee
```

Proposed ACK:

```text
u32 magic
u32 seq_acked
u32 ddr_free_events
u32 status
```

`status` should report parser errors, DDR ring full, scheduler overflow, and scheduler hard error distinctly.

## Startup Sequence

Recommended stream startup:

1. Probe `IP_ID` and `IP_VERSION`.
2. Read `STREAM_DEPTH`.
3. Write `CTRL.RESET_SOFT`.
4. Write `STREAM_CTRL.MODE = 1`.
5. Write `LOW_WMARK`.
6. Clear all `IRQ_STATUS` bits with `AWG_SCHED_IRQ_ALL`.
7. Enable the top-level IRQ gate with `CTRL.IRQ_ENABLE` if the firmware uses hardware interrupts.
8. Enable `DONE | ERROR | LOW_WATERMARK | EMPTY_STALL` in `IRQ_ENABLE`.
9. Pre-fill HDL FIFO from DDR ring if data is available.
10. Write `CTRL.ARM`.
11. Write `CTRL.RUN`.

For finite streams, the host or firmware must ensure the final event has `AWG_SCHED_EVENT_FLAG_EOF` set.

## Error Handling

On `STREAM_CTRL.OVERFLOW`:

1. Stop the active stream if running.
2. Record artifacts: `STATUS`, `ERR_REG`, `IRQ_STATUS`, `OCCUPANCY`, `FREE_SPACE`, `STREAM_PUSHES`, `STREAM_STALLS`.
3. Clear overflow by writing `STREAM_CTRL.OVERFLOW = 1`.
4. Use `CTRL.RESET_SOFT` before reusing stream mode.

On `IRQ_EMPTY_STALL` without `IRQ_ERROR`:

1. Drain immediately if DDR has data.
2. Log `STREAM_STALLS`.
3. Continue unless policy says empty wait is unacceptable.

On `IRQ_ERROR`:

1. Stop issuing new HDL pushes.
2. Snapshot artifacts.
3. Clear IRQs only after artifacts are captured.
4. Recover with `CTRL.RESET_SOFT`.

## Firmware Tests

Minimum tests before bench use:

- Legacy preload still writes identical event words and uses `EVENT_COUNT`.
- `stream_open` validates ID/version and programs `LOW_WMARK`.
- `stream_push` appends to DDR and performs opportunistic drain.
- `drain_step` respects `FREE_SPACE`, DDR availability, and `refill_chunk_max`.
- Hardware overflow returns `-EAGAIN` and does not advance DDR read index as if accepted.
- EOF close sets `AWG_SCHED_EVENT_FLAG_EOF` on the final event.
- ISR only acknowledges IRQs and sets flags; refill is done in foreground.
- Poll path drains when no IRQ edge is generated.

## Bench Bring-Up Checklist

1. Run legacy deterministic scheduler path with `STREAM_CTRL.MODE = 0`.
2. Run stream smoke with a finite EOF-marked sequence and low event rate.
3. Confirm `STREAM_PUSHES == fired event count` after clean EOF.
4. Confirm `EOF_SEEN`, `IRQ_DONE`, and `STATUS.DONE`.
5. Force low-watermark by using a small prefill and verify refill IRQ.
6. Pause producer and verify `EMPTY_STALL` without hard error.
7. Push a late event after empty wait and verify `ERR_MISSED_DEADLINE | IRQ_UNDERRUN | IRQ_ERROR`.
8. Run reset recovery: `CTRL.RESET_SOFT`, verify FIFO empty and stream counters clear.
