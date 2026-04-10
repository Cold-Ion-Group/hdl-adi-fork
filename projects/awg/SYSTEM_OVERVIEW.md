# FMCDAC System Overview

**Platform**: AD9144-FMC-EBZ on Xilinx KCU116 (Kintex UltraScale XCKU5P)
**DAC**: AD9144 — dual 16-bit, 1966.08 MSPS (2× interpolation), JESD204B Subclass 1
**Processor**: MicroBlaze soft-core (100 MHz, bare-metal)

---

## 1. Hardware

An external 122.88 MHz reference clock feeds the AD9516-1 clock distributor on the
FMC mezzanine. The AD9516 fans out three signals:

| Output | Signal | Frequency | Destination |
|--------|--------|-----------|-------------|
| OUT1 | DAC CLK | 122.88 MHz | AD9144 PLL reference → 1966.08 MHz DAC clock (2× interp) |
| OUT6/7 | SYSREF | 30.72 MHz | AD9144 + FPGA (LMFC alignment) |
| OUT9 | REFCLK | 122.88 MHz | FPGA GTH QPLL0 → 9.83 Gbps serial lane rate |

The FPGA connects to the AD9144 over four GTH transceiver lanes carrying JESD204B
traffic. MicroBlaze controls the AD9516 and AD9144 via SPI (directly — no Linux,
no OS).

Si5328 is present on the I2C bus but **bypassed** (`SKIP_SI5328`). GTH REFCLK
comes directly from AD9516 OUT9.

## 2. Data Flow

```
 MicroBlaze (firmware)
       │
       ├── SPI ──────────────► AD9516  (clock programming)
       ├── SPI ──────────────► AD9144  (DAC config, JESD link control)
       │
       ├── AXI ──► AXI DAC TPL ──► AXI JESD TX ──► GTH TX ──► AD9144 JESD RX
       │           (DDS engine)     (link layer)    (SerDes)    (deframer)
       │           2 ch, DPW=4      SC1, K=32       4 lanes     ──► DAC0/1
       │           DDS_PHASE_DW=32                  9.83 Gbps       analog out
       │
       └── AXI ──► AXI GPIO ──► DAC_RESET, DAC_TXEN, CLKD_SYNC
```

**Data path modes** (selected per-channel via AXI DAC TPL):

| Mode | Source | Use |
|------|--------|-----|
| DDS | On-chip NCO | Tone generation (freq/scale/phase programmable) |
| SED | Fixed pattern registers | Short Transport Layer Pattern test |
| PN7/PN15 | PRBS generators | Datapath integrity verification |
| DMA | DDR via AXI DMAC | Arbitrary waveform playback (not yet exercised) |

The AD9144's receive-side XBAR remaps physical lanes {4,5,6,7} → logical {0,1,2,3}
with polarity inversion on lane 2 to match the FMC-EBZ board routing.

## 3. JESD204B Link

| Parameter | Value |
|-----------|-------|
| Mode | 4 (M=2, L=4, F=1, S=1, HD=1) |
| Subclass | 1 (deterministic latency) |
| Lane rate | 9830.4 Mbps (245.76 MHz device clock) |
| LMFC | 30.72 MHz (= fDAC / K) |
| Scrambling | Enabled |
| SYSREF edge | Rising (default); auto-tuned to falling if alignment error detected |

Link startup: FPGA JESD TX enables → AD9144 sees K28.5 (CGS) → ILAS exchange →
DATA state. SYSREF aligns both LMFC counters. The `fmcdac_sysref_tune()` function
is a safety net that sweeps edge/offset if an alignment error is detected.

## 4. DAC Operating Mode

The AD9144 DAC PLL runs at **1966.08 MHz** with **2× internal interpolation**
(the current default). The FPGA DDS and JESD link operate at 983.04 MSPS —
the interpolation filter upsamples internally, giving:

- Better image rejection (images at ±1966 MHz, not ±983 MHz)
- ~3 dB SNR improvement in-band
- Reduced sinc droop (0.6 dB vs 2.5 dB at 400 MHz)
- Relaxed analog anti-alias filter requirements

The FPGA DDS Nyquist remains **491.52 MHz** (input rate = 983 MSPS). For tones
above 491 MHz, use the AD9144 on-chip NCO (`ad9144_set_nco()`) which operates
at the full 1966 MSPS DAC rate.

## 5. Firmware Boot Sequence

```
main()
  fmcdac_reconfig()           fixed clock mode + sample rate (compile-time default)
  fmcdac_setup()
    GPIO/SPI/I2C init
    AD9516 PLL lock + output programming (CLK, SYSREF, REFCLK)
    GTH transceiver init (QPLL0 lock)
    AD9144 init (DAC PLL 1966.08 MHz, 2× interp, JESD config, SYSREF rising edge)
    JESD TX link enable → CGS → ILAS → DATA
    AXI DAC core init
  fmcdac_test()
    Link status poll (confirm DATA + CGS/Frame/Checksum/ILAS all 0x0F)
    STPL zero test       — DDS scale=0, verify DAC sees 0x0000
    STPL pattern test    — SED mode, verify 4 sample values per converter
    PRBS-7 + PRBS-15     — datapath integrity through full link
    SYSREF tune          — safety-net alignment sweep (skips if clean)
    SYSREF verify        — register dump confirming Subclass 1 state
    Latency readback     — dyn0/dyn1/var0/var1 for multi-boot comparison
    PHY PRBS (log-only)  — always fails (no TX-side PHY pattern source)
    NCO tone test        — optional AD9144 on-chip NCO diagnostic
    DDS-band diagnostic  — 10 MHz, 100 MHz, 200 MHz, 230–330 MHz (paused, host-triggered)
    SFDR test            — 50–400 MHz in 50 MHz steps (paused, host-triggered)
    Throughput benchmark — AXI MMIO, SPI, DDS pair retune rates
    UART RTT service     — host ping/pong latency measurement
    DDS sweep            — 10 → 490 MHz in 10 MHz steps, 50 ms per tone
  [fmcdac_soak()]             optional 8h link stability test (ENABLE_SOAK)
  fmcdac_remove()
```

## 6. Capabilities

**Working today:**

- Full JESD204B Subclass 1 link at 983 MSPS (1966 MSPS with 2× interp)
- 32-bit DDS frequency tuning word (sub-Hz resolution at 983 MSPS)
- DDS tone generation with real-time frequency/scale/phase control
- Batched SYNC updates — all DDS parameters committed atomically per tone change
- Shadow register cache — zero AXI reads on DDS set/get hot paths
- Automated self-test suite: STPL (zero + pattern), PRBS-7, PRBS-15
- 10–490 MHz frequency sweep (49 points, no link drops)
- DDS-band amplitude validation via R&S FSH8 (10–330 MHz verified)
- SFDR baseline via FSH8 (50–400 MHz, segmented spur search)
- Firmware throughput benchmarks (AXI MMIO: ~737K ops/s, SPI: ~6K ops/s, DDS: ~838 ops/s)
- Host UART RTT baseline (~3.5 ms average round-trip)
- Manifest-checked builds (`gen_manifest.ps1` tracks XSA + firmware commit)
- Host automation via `run_nco_scope_test.py` (DDS-band, SFDR, throughput, UART RTT)

**Not yet validated:**

- Deterministic latency across 5+ power cycles (infrastructure built, captures pending)
- DMA waveform playback from DDR
- JESD modes other than mode 4
- Acceptance-grade SFDR (current baseline ~48–60 dBc, target ≥85 dBc)
- Phase-noise measurement
- PHY-level PRBS (needs HDL changes for GTH raw PRBS generation)

## 7. Key Files

| File | Role |
|------|------|
| `projects/fmcdac/src/app/fmcdac.c` | All firmware logic (setup, test, DDS, diagnostics) |
| `drivers/dac/ad9144/ad9144.c` | AD9144 driver (PLL, JESD link, NCO, SYSREF) |
| `projects/fmcdac/src/app/parameters.h` | Base addresses, pin mappings, AD9516 output indices |
| `projects/fmcdac/docu/clock_architecture.md` | Clock tree reference (frequencies, SYSREF policy) |
| `projects/fmcdac/docu/CURRENT_EVALUATION_STATUS.md` | Active evaluation status and latest baselines |
| `projects/fmcdac/docu/BENCHMARK_RESULTS_AND_HISTORY.md` | Measurement history and run artifacts |

## 8. Forward Plan

1. **SFDR refinement** — improve measurement confidence; determine how much of the
   current ~48–60 dBc baseline is converter/board vs bench configuration.

2. **SYSREF policy closure** — measure tSSD/tHSD timing margins and finalize
   continuous-vs-gated rationale.

3. **Integration parameter contract** — publish one canonical constants table;
   eliminate conflicting values across documentation.

4. **Atomic clock path** — define the external PLL needed to derive 122.88 MHz
   from a 5/10 MHz atomic reference. See [clock_architecture.md](./clock_architecture.md).

## 9. TPL timed-control insertion map (AD9144 AWG path)

This section maps where FTW/POW/ASF-equivalent DDS controls currently enter the
`axi_ad9144_tpl/dac_tpl_core` path, and records concrete insertion boundaries.

### 9.1 Exposed vs internal-only TPL control interfaces

- **AXI-visible control interface (from block design):**
  - `axi_ad9144_tpl/s_axi_aclk`
  - `axi_ad9144_tpl/s_axi_aresetn`
  - `axi_ad9144_tpl/s_axi` (mapped at `0x44A04000`)
- **Data/stream interfaces exported by TPL hierarchy:**
  - `axi_ad9144_tpl/link_clk`
  - `axi_ad9144_tpl/link`
  - `axi_ad9144_tpl/dac_dunf`
  - `axi_ad9144_tpl/dac_enable_<i>`, `axi_ad9144_tpl/dac_valid_<i>`, `axi_ad9144_tpl/dac_data_<i>`
- **Control-relevant pins that are currently internal-only (not exported by the hierarchy):**
  - `axi_ad9144_tpl/dac_tpl_core/dac_sync_in`
  - `axi_ad9144_tpl/dac_tpl_core/dac_sync_manual_req_in`
  - `axi_ad9144_tpl/dac_tpl_core/dac_sync_manual_req_out`

### 9.2 Where DDS control words are latched (per converter/tone)

`dac_tpl_core` is `library/jesd204/ad_ip_jesd204_tpl_dac/ad_ip_jesd204_tpl_dac.v`.
Its register map and channel control path are:

1. **AXI write decode and per-channel register capture (`up_clk` domain):**
   - `ad_ip_jesd204_tpl_dac_regmap` instantiates one `up_dac_channel` per converter.
   - In `up_dac_channel`, writes latch:
     - tone0 scale/init/incr into `up_dac_dds_scale_1`, `up_dac_dds_init_1`, `up_dac_dds_incr_1`
     - tone1 scale/init/incr into `up_dac_dds_scale_2`, `up_dac_dds_init_2`, `up_dac_dds_incr_2`
     - high-word extensions (for `DDS_PHASE_DW > 16`) into
       `up_dac_dds_init_1_hi`, `up_dac_dds_incr_1_hi`, `up_dac_dds_init_2_hi`, `up_dac_dds_incr_2_hi`
2. **Commit across clock domains (`up_clk` -> `dac_clk/link_clk`):**
   - `up_xfer_cntrl` transfers packed control bus into
     `dac_dds_scale_1/2`, `dac_dds_init_1/2`, `dac_dds_incr_1/2`.
3. **Per-channel DDS use in TPL datapath (`link_clk` domain):**
   - `ad_ip_jesd204_tpl_dac_core` slices arrays per converter and drives
     `ad_ip_jesd204_tpl_dac_channel`.
   - `ad_ip_jesd204_tpl_dac_channel` maps these into `ad_dds` as:
     - `tone_1_scale`, `tone_1_init_offset`, `tone_1_freq_word`
     - `tone_2_scale`, `tone_2_init_offset`, `tone_2_freq_word`

**FTW/POW/ASF equivalence in this path**
- FTW equivalent: `dac_dds_incr_[0|1]` (channel view) / `tone_[1|2]_freq_word` (DDS core view)
- POW equivalent: `dac_dds_init_[0|1]` / `tone_[1|2]_init_offset`
- ASF equivalent: `dac_dds_scale_[0|1]` / `tone_[1|2]_scale`

### 9.3 Chosen integration strategy

**Selected approach:** add an **external scheduled-control port bundle** to the
TPL hierarchy and mux internally.

Rationale for this project:
- Keeps existing AXI register map and firmware ABI stable.
- Reuses the current per-channel/tone DDS plumbing and only adds a deterministic
  override path at the TPL boundary.
- Minimizes risk of broad regmap surgery in shared ADI library code.

### 9.4 Concrete insertion boundaries for scheduled control

Planned integration points (module/signal level):

- **Hierarchy export point (BD-visible):**
  - Extend `adi_tpl_jesd204_tx_create` (`library/jesd204/scripts/jesd204.tcl`) to
    export a scheduled-control bundle from `dac_tpl_core` up to `axi_ad9144_tpl`.
- **Top-level TPL boundary:**
  - Add new inputs in `ad_ip_jesd204_tpl_dac.v` (scheduled controls + `valid/ready`
    or strobe semantics), then feed muxed outputs into existing core inputs:
    - `dac_dds_scale_0_s`, `dac_dds_init_0_s`, `dac_dds_incr_0_s`
    - `dac_dds_scale_1_s`, `dac_dds_init_1_s`, `dac_dds_incr_1_s`
- **Mux point before per-channel slicing:**
  - Perform source select in `ad_ip_jesd204_tpl_dac.v` (or immediately in
    `ad_ip_jesd204_tpl_dac_core.v`) so downstream logic remains unchanged.
- **No change boundary (kept intact):**
  - `up_dac_channel` register bank semantics and existing AXI writes remain as the
    unscheduled/base profile source.
