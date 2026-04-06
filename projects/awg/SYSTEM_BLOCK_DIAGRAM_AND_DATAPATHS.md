# System Block Diagram and Datapaths (Mermaid)

This document describes the implemented architecture in this repository:

- HDL: `hdl-adi-fork/projects/awg`
- Firmware: `no-OS-adi-fork/projects/fmcdac`
- Hardware target: KCU116 + AD9144 FMC DAC + AD9516 clocking

## 0) Framing: Current Baseline vs Target

- Current demonstrated / measured state: 2-channel JESD mode 4 operation; the present lab baseline is the current 250 MHz / 2-channel bring-up and benchmark state.
- Current default configuration: 4-lane GTH TX, 983.04 MSPS FPGA/JESD input, AD9144 2× interpolation enabled, 1966.08 MHz internal DAC clock, and AD9516 routing per `clock_architecture.md`:
  - OUT1 = DAC clock reference
  - OUT6 = DAC SYSREF
  - OUT7 = FPGA SYSREF
  - OUT9 = FPGA REFCLK
- Ultimate target capability: preserve the broader 10–450 MHz / quad-channel AWG framing. This document explains the current datapath and the hooks for later phases; it does not redefine the end goal downward.
- Open / later-phase options: DMA playback, AD9144 on-chip NCO placement, image-zone filtering, and true >491.52 MHz FPGA-generated bandwidth expansion remain distinct paths and should not be conflated with the current default DDS datapath.

--------------------------------------------------------------------------------

## 1) Full System Block Diagram (Structural, Not Flowchart)

```mermaid
block-beta
  columns 4

  block:EXT["External Clock and Sync"]
    columns 1
    SRC["122.88 MHz Source"]
    AD9516["AD9516 Clock Distributor"]
    SRC --> AD9516
  end

  block:FPGA["KCU116 FPGA"]
    columns 2
    MB["MicroBlaze no-OS app\nfmcdac"]
    SPI["AXI SPI"]

    AXI["AXI Control Peripherals\naxi_ad9144_tpl 0x44A04000\naxi_ad9144_jesd 0x44A90000\naxi_ad9144_xcvr 0x44A60000\naxi_ad9144_dma 0x7C420000"]
    DDR["DDR Controller"]

    DMAC["axi_dmac MM to AXIS"]
    FIFO["util_dacfifo"]

    UPACK["util_upack2"]
    TPL["ad_ip_jesd204_tpl_dac\nsource mux DDS DMA PN Pattern"]

    JESD["axi_jesd204_tx\ninternal SYSREF capture"]
    XCVR["axi_adxcvr and util_adxcvr GTH TX\n4 lanes @ 9.8304 Gbps"]

    GPIO["GPIO dac_fifo_bypass and dac_ctrl"]

    MB --> AXI
    MB --> SPI
    AXI --> DMAC
    AXI --> TPL
    AXI --> JESD
    AXI --> XCVR
    DDR --> DMAC
    DMAC --> FIFO
    FIFO --> UPACK
    UPACK --> TPL
    TPL --> JESD
    JESD --> XCVR
    GPIO --> FIFO
  end

  DAC["AD9144 DAC\nJESD Receiver plus DAC Core"]
  RF["Analog RF Output"]

  SPI --> AD9516
  SPI --> DAC
  AD9516 --> XCVR
  AD9516 --> JESD
  AD9516 --> DAC
  XCVR --> DAC
  DAC --> RF
```

--------------------------------------------------------------------------------

## 2) Firmware Control Flow

```mermaid
flowchart TD
  A[Reset and Boot] --> B[MicroBlaze app starts]
  B --> C[GPIO init dac_ctrl reset txen]
  C --> D[SPI init]
  D --> E[Configure AD9516 OUT1 OUT6 OUT7 OUT9 clocks and SYSREF]
  E --> F[Configure AD9144 PLL JESD DAC current default 2x interp]
  F --> G[Init JESD TX and XCVR]
  G --> H[Init AXI DAC core and source select]
  H --> I[Run self-tests plus DDS-band SFDR throughput UART RTT flow]
```

--------------------------------------------------------------------------------

## 3) TPL Source-Select Datapath

```mermaid
flowchart LR
  DMAIN[dma_data from util_upack2] --> IQCOR[IQ correction or channel formatting]
  DDSCFG[FPGA DDS config regs] --> DDS[ad_dds chain]
  PAT[Pattern data]
  PN[TPL PN7 or PN15 generator]
  ZERO[Zero constant]

  IQCOR -->|dac_data_sel 2 DMA| SEL{Source select mux}
  PAT -->|dac_data_sel 1 SED| SEL
  ZERO -->|dac_data_sel 3 ZERO| SEL
  PN -->|dac_data_sel 4 5 6 7 PN| SEL
  DDS -->|default DDS| SEL

  SEL --> FR[TPL framer]
  FR --> JT[JESD TX]
```

Key point:
- FPGA CORDIC is only in the DDS branch.
- DMA branch does not use FPGA CORDIC.
- AD9144 on-chip NCO, if enabled later, is downstream of the JESD receiver and is not the same block as the FPGA DDS/CORDIC chain.

--------------------------------------------------------------------------------

## 4) Datapath A: DDS/CORDIC Path (Current default benchmark path)

```mermaid
flowchart LR
  R[AXI writes DDS freq phase scale] --> REGMAP[ad_ip_jesd204_tpl_dac_regmap]
  REGMAP --> CH[ad_ip_jesd204_tpl_dac_channel]
  CH --> DDS[ad_dds]
  DDS --> DDS2[ad_dds_2]
  DDS2 --> DDS1[ad_dds_1]
  DDS1 --> CORDIC[ad_dds_sine_cordic]
  CORDIC --> MUXSEL[source mux default DDS]
  MUXSEL --> FR[TPL framer]
  FR --> JT[JESD TX]
  JT --> GTH[GTH TX]
  GTH --> DAC[AD9144 DAC]
```

--------------------------------------------------------------------------------

## 5) Datapath B: DMA Waveform Path (Present in hardware; not in current automated baseline)

```mermaid
flowchart LR
  WAVE[Waveform buffer in DDR] --> DMAC[axi_dmac]
  DMAC --> FIFO[util_dacfifo capture and loop]
  FIFO --> UPACK[util_upack2]
  UPACK --> CHIN[TPL channel dma_data input]
  CHIN --> MUXSEL[source mux select DMA]
  MUXSEL --> FR[TPL framer]
  FR --> JT[JESD TX]
  JT --> GTH[GTH TX]
  GTH --> DAC[AD9144 DAC]
```

Notes:
- `util_dacfifo` loops one captured segment using `dma_xfer_last`.
- `dac_fifo_bypass` selects FIFO mode vs bypass mode.
- This path exists in the hardware/source-mux architecture, but the current primary firmware and host benchmark flow do not exercise DMA playback yet.

--------------------------------------------------------------------------------

## 6) Datapath C: STPL and TPL PN Test Paths

```mermaid
flowchart TD
  S[Firmware sets data select mode] --> M{Mode}
  M -->|SED pattern| P1[Pattern words through TPL]
  M -->|PN modes| P2[Internal PN generator in TPL]
  P1 --> J[JESD TX and GTH]
  P2 --> J
  J --> D[AD9144 receiver and checker]
  D --> R[STPL or TPL-PN result readback]
```

Notes:
- These are TPL/data-path integrity tests, not the raw GTH PHY PRBS mode.
- The AD9144 PHY PRBS checker remains a separate, currently limited diagnostic because the TX-side raw PHY pattern source is not implemented in the present HDL.

--------------------------------------------------------------------------------

## 7) Optional AD9144 Internal NCO Overlay

```mermaid
flowchart LR
  IN[FPGA stream from DDS path or DMA path] --> CORE[AD9144 digital datapath]
  CORE --> NCO[Optional AD9144 internal NCO if enabled]
  NCO --> OUT[Analog output]
```

This NCO is DAC-internal, not FPGA CORDIC.
It remains an opt-in diagnostic or later-phase placement aid; the current primary benchmark path is still FPGA DDS -> TPL -> JESD -> AD9144.

--------------------------------------------------------------------------------

## 8) Clock and SYSREF Flow

```mermaid
flowchart LR
  AD9516[AD9516-1]
  AD9516 -->|OUT9 FPGA REFCLK 122.88 MHz| XCVR[util_adxcvr and GTH clocks]
  AD9516 -->|OUT7 FPGA SYSREF 30.72 MHz| JESD[axi_jesd204_tx internal SYSREF capture]
  AD9516 -->|OUT1 DAC clock ref 122.88 MHz| DACREF[AD9144 PLL reference]
  AD9516 -->|OUT6 DAC SYSREF 30.72 MHz| DACSYS[AD9144 SYSREF]
  JESD --> XCVR
  XCVR -->|4 JESD lanes @ 9.8304 Gbps| DACCORE[AD9144 JESD RX and DAC core]
  DACREF --> DACCORE
  DACSYS --> DACCORE
```

Notes:
- Current default runtime is 2× interpolation: FPGA/JESD input stays at 983.04 MSPS while the AD9144 internal DAC clock runs at 1966.08 MHz.
- 1× mode remains a valid comparison or fallback mode, but OUT1/OUT6/OUT7/OUT9 routing stays the same; only the AD9144 internal PLL/interpolation setting changes.

--------------------------------------------------------------------------------

## 9) Data-Select Mode Matrix

| Mode | Meaning | CORDIC involved |
|---|---|---|
| `AXI_DAC_DATA_SEL_DDS` | FPGA DDS synthesis path | Yes, if `DDS_TYPE=1` |
| `AXI_DAC_DATA_SEL_DMA` | DDR to DMAC streaming path | No |
| `AXI_DAC_DATA_SEL_SED` | Short pattern test path | No |
| `AXI_DAC_DATA_SEL_ZERO` | Zero output path | No |
| `AXI_DAC_DATA_SEL_PN*` | PN generator test path | No |

--------------------------------------------------------------------------------

## 10) Current Implementation Boundaries

Implemented and exercised in the current default baseline:
- DDS/CORDIC synthesis path.
- Source-select mux between DDS, DMA, pattern, PN, and zero.
- STPL and TPL PN validation paths.
- Subclass-1 bring-up with OUT1/OUT6/OUT7/OUT9 clocking and internal SYSREF capture in `axi_jesd204_tx`.

Implemented but not part of the current primary automated benchmark path:
- DMA waveform path through DMAC and util_dacfifo.
- Optional AD9144 on-chip NCO control for later placement experiments.
- DMA playback or alternate-source experiments as a discriminator if DDS-band or SFDR evidence later requires them.

Blocked or later-phase architectural work:
- True >491.52 MHz FPGA-generated bandwidth expansion via a different JESD/HDL architecture; the current driver "mode 9" does not provide that capability.
- Timestamped event scheduler.
- Hardware list and branch playback engine with deterministic branch latency.
- Atomic staged commit unit for time-tagged FTW/POW/ASF updates.
