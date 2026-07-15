# Publication‑grade system specification and measurement requirements for the FPGA‑JESD‑DAC algorithmic AWG

## Executive summary

This specification frames a plan for an algorithmic arbitrary waveform generator (AWG) built around a high‑speed JESD204B transmit chain: FPGA waveform synthesis → JESD204B serializer → quad 16‑bit DAC (AD9144) with a low‑jitter clock fanout (AD9516‑1). The primary publication aim is **to demonstrate AWG capability beyond memory‑centric playback**—specifically, longer “unique waveform horizon” for complex sequences at a fixed DAC sample rate—with rigor comparable to commercial AWG and control‑system benchmarks, while maintaining credible RF metrics (SFDR, noise, phase noise) and deterministic timing (JESD204B subclass‑1). The approach prioritizes deterministic timing and payload/system correctness first (already completed per your S0/S1 gate), then transitions to a measurement‑driven characterization that is reproducible, automatable, and comparable to external baselines such as ARTIQ‑class experiment control stacks.

The proposed spec uses **datasheet‑anchored envelope limits** (AD9144 sample rate/interpolation/JESD speed, AD9516 jitter/skew/output limits, FPGA transceiver refclk tolerances and line‑rate capability) and defines **measurable system targets** for: (i) clocking/jitter and SYSREF alignment, (ii) JESD204B link robustness and deterministic latency, (iii) DAC operating points (sample rates and interpolation), (iv) synthesizer features (FPGA DDS + optional on‑chip NCO), (v) RF output fidelity and stability, and (vi) memory‑efficiency and agility advantages relative to memory‑based baselines and ARTIQ‑driven hardware paradigms.

## System requirements and target specifications

### Current baseline framing (implementation-state cross-check)

- **Current demonstrated system state:** the present hardware evidence is still the current 250 MHz / 2-channel lab baseline, not yet the full end-goal envelope.
- **Current default configuration:** JESD mode 4, 4-lane GTH TX, 983.04 MSPS FPGA/JESD input, AD9144 2× interpolation enabled, and **1966.08 MHz** internal DAC clock.
- **Current alternate comparison mode:** 1× interpolation at the same 983.04 MSPS FPGA/JESD input remains a useful comparison/fallback mode, but it is **not** the current default.
- **Ultimate capability target:** preserve the intended **10–450 MHz / quad-channel** AWG framing. The current baseline and the final target are intentionally distinct claims.
- **Open or later-phase paths:** acceptance-grade phase noise, multi-boot deterministic-latency capture, dynamic SFDR during rapid retunes/chirps, raw PHY-level PRBS generation, DMA playback, NCO-assisted placement, image-mode filtering, and true >491.52 MHz FPGA-generated bandwidth expansion remain separate work items.

### Current HDL/firmware status (July 2026)

- Phase E HDL is implemented for KCU116: scheduler DMA ingress, SFP0 PG203
  `xxv_ethernet`, Ethernet RX DMA, and Ethernet TX DMA are present in the block
  design and routed timing-clean.
- Local bitstream/XSA generation is blocked by the installed PG203 license. The
  design reached routed implementation; the license failure occurs at
  `write_bitstream`.
- Firmware Phase F is pending. The current no-OS `fmcdac` app has AD9144/JESD
  bring-up and the existing DAC DMA example, but no scheduler DMA refill,
  PG203 MAC management, Ethernet RX/TX DMA transport, ARP/UDP parser, or host
  UDP sender modules yet.
- Publication claims about unbounded Regime C streaming require Phase F firmware
  closure plus runtime telemetry and analog/timing measurements. HDL closure
  alone is not sufficient evidence for those claims.

### System envelope (datasheet‑anchored capabilities)

- **DAC and JESD envelope**
  - Quad, 16‑bit DAC; **maximum DAC sample rate 2.8 GSPS**. 
  - **Interpolation modes:** 1× / 2× / 4× / 8×. 
  - **JESD204B lane speed range:** **1.44 Gbps to 12.4 Gbps per lane** (max depends on SVDD12 condition). 
  - Up to **8 JESD204B lanes** supported by the DAC interface. 
  - AD9144 supports **JESD204B Subclass 0 and Subclass 1** (not Subclass 2). 

- **Clock distribution envelope**
  - AD9516‑1 outputs: LVPECL to **1.6 GHz**, LVDS to **800 MHz**, CMOS to **250 MHz**. 
  - Additive jitter: **225 fs rms** (LVPECL); LVDS has additive jitter class and delay features. 
  - Channel‑to‑channel skew (paired outputs) **<10 ps** (datasheet feature). 

- **FPGA transceiver and board‑level envelope**
  - On the current KCU116/XCKU5P implementation, the FMC quad uses **GTH** transceivers with FMC refclk routing; FMC_HPC0 GBTCLKx route into the active GTH quad on the evaluation board. 
  - GTH line‑rate support includes JESD204a/b compliance up to at least 12.5 Gbps in protocol lists, and GTH line‑rate capability is device/speed‑grade/package dependent with noted package limits. 
  - Transceiver reference clock frequency switching characteristics show a wide refclk range (example table: **60–820 MHz**).

### Publication‑grade system requirements (targets)

A. **Clocking and synchronization**
- **CLK‑1 (DACCLK input electrical):** DACCLK at AD9144 CLK± within 400–2000 mVpp differential, self‑biased common‑mode ~600 mV (AC‑coupled), and **≤2.8 GHz** max clock rate. (Target: comply by design; verify with scope).   
- **CLK‑2 (distribution constraints):** AD9516 outputs must stay within output‑type max frequencies (LVDS ≤800 MHz; LVPECL ≤1.6 GHz; CMOS ≤250 MHz).   
- **CLK‑3 (additive jitter budget):** Added jitter from clock distribution shall be consistent with AD9516 spec (e.g., 225 fs rms additive jitter for LVPECL).   
- **CLK‑4 (SYSREF timing):** Subclass‑1 SYSREF must meet **tSSD ≥131 ps, tHSD ≥119 ps, KOW = 20 ps** relative to DAC clock at the AD9144 pins; SYSREF frequency relationship must follow **fSYSREF = fDATA/(K×S)**.
- **CLK‑5 (clock skew for coherence):** Output skew between clocks feeding DAC and FPGA shall be measured and bounded; use AD9516 skew specs as reference (e.g., LVDS outputs sharing divider have bounded skew; across dividers larger).   

B. **JESD204B link integrity and deterministic latency**
- **JESD‑1 (lane rate):** Operating lane rate shall remain within AD9144 JESD limits **1.44–12.4 Gbps**. 
- **JESD‑2 (deterministic latency policy):** System MUST support and benchmark in **Subclass‑1** using SYSREF; deterministic latency must be repeatable across power cycles and resynchronization events. Current firmware/readback infrastructure exists, but acceptance-grade multi-boot evidence is still an open capture task.  
- **JESD‑3 (subclass‑1 physical requirements):** SYSREF distribution skew must be less than allowed uncertainty; SYSREF must be phase aligned to DAC clock; link alignment should be to within **½ DAC clock period** (AD9144 subclass‑1 statement). 
- **JESD‑4 (physical layer impedance):** Differential impedance of lanes and key LVDS timing signals should align with 100 Ω ±20% guidance for JESD204B and controlled impedance routing for SYNCOUT/SYSREF/CLK signals. 
- **JESD‑5 (physical BER tests):** Provide PRBS/BER proxy testing using AD9144 PHY PRBS checker capability. In the current project this remains a proxy only: TX-side raw GTH PHY PRBS generation is not yet implemented in HDL.  

C. **DAC operating points and interpolation**
- **DAC‑1 (validated baseline mode):** Current default characterization mode is **983.04 MSPS FPGA/JESD input** with **2× interpolation enabled**, giving an **AD9144 internal DAC clock of 1966.08 MHz**. This is the current demonstrated two-channel baseline for publication-grade RF and timing evidence. 1× mode at the same FPGA/JESD input rate remains useful as a comparison/fallback operating mode, but it should not be treated as the current default.  
- **DAC‑2 (supported update‑rate envelope):** DAC update rate capability consistent with datasheet tables (e.g., interpolation‑dependent maximum update rates; supply‑dependent max). citeturn9view0turn2view0  
- **DAC‑3 (data‑rate constraint disclosure):** For publication, explicitly report both:
  - “Maximum DAC update rate” per interpolation mode, and  
  - “Adjusted DAC update rate” (interface‑limited input data rate) as shown in AD9144 Table 2. citeturn9view0  

D. **Synthesis capabilities (FPGA DDS + optional on‑chip NCO)**
- **SYN‑1 (FPGA DDS):** Provide stable single‑tone, phase‑continuous frequency stepping, amplitude scaling, and programmable phase. (Accumulator widths and update granularity are HDL‑dependent; must be reported from HDL.)  
- **SYN‑2 (on‑chip NCO option):** If used, use AD9144 fine NCO with:
  - **48‑bit FTW (FTW0..FTW5)** and explicit update handshake, citeturn10view1turn10view2  
  - **phase offset** registers with defined update semantics, citeturn10view1  
  - NCO alignment modes (SYSREF alignment or data‑key alignment) and status PASS/FAIL bits. citeturn10view0  

E. **Analog output amplitude, linearity, and operational limits**
- **ANA‑1 (IOUTFS programmability):** Full‑scale output current programmable over roughly **13.9 mA to 27.0 mA** typical range; register mapping/meaning must be documented in system spec. citeturn9view0turn7view4  
- **ANA‑2 (output compliance):** Respect **output compliance range −250 mV to +750 mV** at DAC outputs; benchmark measurements shall document the output network used and ensure compliance for all tested amplitudes. citeturn7view1  
- **ANA‑3 (settling):** Step response should be consistent with datasheet settling time definition (e.g., 20 ns to ±0.5 LSB). citeturn9view0  
- **ANA‑4 (downstream protection):** Document and test emergency stop / transmit enable behavior (datasheet feature) as part of safety/operational limits. citeturn2view0turn9view0  

F. **RF performance targets (publication‑grade)**
- **RF‑1 (SFDR definition and reporting):** Use AD9144 SFDR definition (spur vs peak within DC..Nyquist); report SFDR over a sweep of fOUT and digital back‑off. citeturn8view0  
- **RF‑2 (baseline SFDR target in the current default mode):** MUST meet conservative thresholds aligned to AD9144 typical curves for the current **983.04 MSPS FPGA/JESD input + 1966.08 MHz internal DAC clock (2× interpolation)** operating point:
  - at **‑6 dBFS** back‑off, **SFDR ≥55 dBc** for fOUT in [10, 450] MHz (first Nyquist) (threshold chosen to be below typical curves). citeturn11view0  
  - at low frequencies (≤100 MHz), SHOULD meet **SFDR ≥65 dBc** at ‑6 dBFS. citeturn11view0  
- **RF‑3 (noise spectral density):** Report NSD (dBm/Hz) vs fOUT for key back‑off points using datasheet plots as reference. citeturn11view1turn11view2  
- **RF‑4 (IMD3):** For two‑tone tests, report IMD3 vs fOUT and tone spacing/back‑off. citeturn11view0turn11view1  
- **RF‑5 (phase noise at output):** Report output phase noise (dBc/Hz) vs offset for representative fOUT; datasheet provides phase noise example plots comparing PLL on/off. Current automation does not yet close this requirement at acceptance grade, so treat it as open. citeturn11view2  

G. **Clock jitter / phase noise impact disclosure**
- **JIT‑1 (clock‑jitter‑limited SNR model):** MUST include a section that computes jitter‑limited SNR using standard relationship (commonly cited for sampled systems) and compares it to measured SNR; one authoritative reference is entity["company","Analog Devices","semiconductor company"] tutorial/application material on aperture jitter vs SNR. citeturn12search2turn12search8  
- **JIT‑2 (refclk phase noise mask compliance):** For FPGA SERDES reference clock, SHOULD document compliance vs transceiver refclk phase‑noise mask tables (example masks in DS892). citeturn5view2  

H. **Timing determinism and agility**
- **TIM‑1 (deterministic latency repeatability):** MUST quantify deterministic latency repeatability across:
  - N cold boots,  
  - N JESD resyncs,  
  - with SYSREF one‑shot and (if used) gapped periodic SYSREF.  
  Deterministic latency definition and repeatability requirement should follow JESD204B subclass literature. citeturn15view0turn15view1  
- **TIM‑2 (event update latency):** MUST quantify frequency/phase/amplitude update latency and jitter; report percentiles and worst‑case. The current benchmark flow establishes steady-state throughput and RTT baselines, but dynamic SFDR during rapid retunes or chirps remains open.  
- **TIM‑2a (commit-time classification):** MUST validate commit scheduler classification for **early** (`target_time > sched_now`), **due** (`target_time == sched_now`), and **late** (`target_time < sched_now`) requests in hardware traces and register readback.
- **TIM‑2b (missed-deadline policy, current RTL):** If an event timestamp is already in the past at fetch-time (`ts < now` on first compare), the engine enters `ERROR` and raises `IRQ_ERROR|IRQ_UNDERRUN` (`ERR_MISSED_DEADLINE`). This is the currently implemented behavior in RTL; continue-on-late telemetry policy is deferred.
- **TIM‑3 (SYSREF periodicity rules):** If SYSREF is periodic/gapped periodic, period must be integer multiple of LMFC to avoid SYSREF mid‑multiframe (per subclass‑1 guidance). citeturn15view1  

I. **Memory efficiency and “unique waveform horizon”**
- **MEM‑1 (primary AWG claim metric):** MUST report:
  - Effective unique waveform horizon \(T_\text{unique}\) achievable without repetition, and  
  - Memory footprint of waveform description + runtime state.  
- **MEM‑2 (compression advantage):** MUST compute compression ratio against sample‑buffer representation at the same fs, bit depth, channels. (For 16‑bit real: bytes/sec = 2·fs per channel; for I/Q or multichannel scale accordingly.)  
- **MEM‑3 (baseline comparators):** SHOULD include:
  - a memory‑AWG class benchmark (commercial finite‑memory AWG) where memory depth is a hard cap (e.g., up to 32 GSamples for a Tek class instrument). citeturn14search0turn14search4  
  - an ARTIQ DDS RAM baseline where profile RAM address is 10‑bit (1024 entries), illustrating ramp/sequence limits for RAM‑mode waveforms. citeturn13search1turn13search29  

J. **Multi‑channel coherence**
- **COH‑1 (phase coherence across channels):** MUST measure relative phase and drift between channels driven from the same clock domain; skew constraints from AD9516 provide a reference expectation. citeturn4view0turn4view2  
- **COH‑2 (restart determinism):** MUST measure phase at t=0 across N restarts (subclass‑1 enabled) and quantify distribution.

K. **Environmental and soak stability**
- **REL‑1 (soak):** MUST perform ≥8 hour continuous operation test with periodic status capture; report link errors, amplitude drift, frequency drift, and temperature.  
- **REL‑2 (supply sensitivity):** SHOULD document supply voltage ranges and stability requirements; AD9144 provides operating ranges for rails and power recommendations. citeturn9view0turn8view2  

L. **Safety and operational limits**
- **SAFE‑1 (output disable default):** MUST ensure output is off/blanked on error or during initialization; document e‑stop/transmit enable semantics. citeturn2view0turn9view0  
- **SAFE‑2 (electrical limits):** MUST respect DAC compliance, clock input amplitude limits, and power rail limits per datasheet. citeturn7view1turn9view0  

### Current measured status note (April 2026 bench baseline)

These notes capture the current demonstrated state without changing the long-term requirements above.

- **Bench baseline configuration:** JESD mode 4, 2 channels, 983.04 MSPS FPGA/JESD input, 2× interpolation, **1966.08 MHz** internal DAC clock.
- **DDS-band status:** current FSH8 evidence shows mild droop, not collapse, through the previously suspected region. Relative to the 10 MHz reference, measured deltas were `-0.587 dB @ 200 MHz`, `-0.818 dB @ 230 MHz`, `-1.621 dB @ 260 MHz`, `-1.244 dB @ 290 MHz`, and `-2.768 dB @ 330 MHz`.
- **Steady-state SFDR baseline:** `59.96 dBc @ 50 MHz`, `58.05 dBc @ 100 MHz`, `55.37 dBc @ 150 MHz`, `57.44 dBc @ 200 MHz`, `55.19 dBc @ 250 MHz`, `53.87 dBc @ 300 MHz`, `52.39 dBc @ 350 MHz`, and `48.59 dBc @ 400 MHz`. These are the current structured bench baselines, but they remain below the long-term acceptance target.
- **Throughput baseline:** about `736,980` AXI MMIO writes/s, `5,945` AD9144 SPI writes/s, and `838` DDS pair updates/s.
- **UART RTT baseline:** `16` samples, `3170.6 us` min, `3455.8 us` average, `5125.6 us` max.
- **Current primary automation scope:** FSH8-based DDS-band measurement, segmented SFDR spur sweeps, throughput capture, and UART RTT capture. NCO testing is secondary/opt-in rather than the main evaluation path.
- **Still open / blocked:** acceptance-grade phase noise, dynamic SFDR during rapid retunes or chirps, complete deterministic-latency evidence across repeated cold boots/resyncs, and raw PHY-level PRBS generation.
- **>491.52 MHz note:** 2× interpolation improves the current default analog operating point, but it does **not** extend FPGA-generated bandwidth above `491.52 MHz`. AD9144 on-chip NCO placement, image-mode/RF-filter paths, and true higher-bandwidth JESD/HDL work remain distinct later-phase options; the current driver "mode 9" does **not** solve this limit.

## Measurement methods, instruments, settings, thresholds, and artifacts

The table below provides requirement‑by‑requirement measurement procedures. Instrument models are intentionally open‑ended; specify your available instruments in the benchmark harness metadata. In the current implementation state, the primary automated campaign is the **FSH8-based DDS-band flow plus segmented SFDR spur sweeps**, supplemented by throughput and UART RTT capture; acceptance-grade phase-noise and dynamic-SFDR closure remain outside the current automated scope.

**Standard artifacts (apply to all tests)**
- `run.json` (metadata): build IDs, configuration (K/L/M/F/S, fs, interpolation, lane rate), clock tree mode, SYSREF mode, temperatures, instrument IDs, calibration info.
- `metrics.csv` (row‑based): timestamp, test_id, channel, f_out_cmd, f_out_meas, amplitude, SFDR, noise, link_state, error counters, etc.
- `traces/`:
  - SA traces as `freq_hz, power_dbm` CSV + PNG screenshots.
  - Scope waveforms as CSV (time, voltage) or instrument native (WFM/HDF5) + PNG screenshots.
  - Register dumps `regs_ad9144.json`, `regs_ad9516.json`, `regs_fpga.json`.

### Measurement matrix and pass/fail criteria

| Req ID | Measurement method | Instruments & settings | Pass/Fail thresholds | Artifacts |
|---|---|---|---|---|
| CLK‑1 | Measure DACCLK at AD9144 CLK± pins (or closest test point); verify differential amplitude and common‑mode under AC coupling | ≥1 GHz scope + differential probe; 50 Ω where appropriate; measure Vpp(diff), Vcm | PASS if 0.4–2.0 Vpp(diff) and Vcm matches datasheet expectations; FAIL otherwise | Scope waveform CSV + screenshot; `clk_dacclk.json` |
| CLK‑2 | Verify AD9516 output frequencies and output mode configuration | Frequency counter or scope; also firmware register dump | PASS if outputs within LVDS/LVPECL/CMOS max frequencies; LVDS ≤800 MHz, LVPECL ≤1.6 GHz, CMOS ≤250 MHz citeturn2view1 | `regs_ad9516.json`; `clk_outputs.csv` |
| CLK‑3 | Distribution additive jitter characterization (if instrument supports); otherwise infer via phase noise at clock output | Phase noise analyzer or SA PN mode; integrate 12 kHz–20 MHz (and also 200 kHz–10 MHz for cross); compare to datasheet typical jitter plots | SHOULD: additive jitter consistent with datasheet class (e.g., 225 fs rms LVPECL) citeturn4view0turn4view1 | PN trace CSV; `jitter_integrals.json` |
| CLK‑4 | SYSREF frequency and timing relationship validation: verify fSYSREF = fDATA/(K×S) and setup/hold compliance | 2‑ch scope: DACCLK and SYSREF; measure relative timing; ensure no SYSREF edges in keep‑out window | PASS if setup ≥131 ps, hold ≥119 ps, and KOW respected citeturn9view0 | Scope traces; `sysref_timing.csv` |
| CLK‑5 | Clock skew: measure skew between SYSREF to DAC and SYSREF to FPGA; also clock to DAC vs clock to FPGA | 4‑ch scope or time‑interval analyzer; matched probes; measure Δt distribution | PASS if skew < target uncertainty budget for deterministic latency (set by TIM‑1); SHOULD be consistent with AD9516 skew ranges citeturn4view2 | `skew_histogram.csv` |
| JESD‑1 | Lane rate sanity: compute lane rate from configuration; corroborate with link clock (lane/40) where available | Firmware readback + scope on link clock test pin; ensure within per‑lane 1.44–12.4 Gbps range citeturn9view0 | PASS if config‑computed and measured link clock within ±100 ppm | `jesd_linkclock.csv`, `run.json` |
| JESD‑2 | Subclass‑1 enablement verification | Register readback on AD9144 subclass registers; link status; confirm SYSREF capture mode used | PASS if subclass = 1 and SYSREF handling correct; AD9144 supports subclass 0/1 only citeturn3view3 | `regs_ad9144.json` |
| JESD‑3 | Deterministic latency repeatability (time‑domain) | Scope captures of waveform marker edge relative to trigger across N cycles; compute phase/time drift distribution | MUST PASS: time/phase distribution bounded per TIM‑1; use “≤½ DAC clock” as target intuition citeturn3view3turn15view0 | `det_latency_trials.csv`, waveforms |
| JESD‑4 | Verify controlled impedance assumptions indirectly via eye margin/PRBS robustness | PRBS/BERT proxy + link error counters over time; optionally eye diagram if tools permit | PASS if zero PRBS proxy errors for T minutes at target lane rate; note that the present project still lacks TX-side raw GTH PHY PRBS generation, so AD9144 PHY PRBS remains a proxy rather than full BER closure citeturn3view2 | `prbs_results.csv` |
| DAC‑1 | Baseline mode confirmation: FPGA/JESD input = 983.04 MSPS, interpolation = 2× default, internal DAC clock = 1966.08 MHz | Readback registers; verify DAC clock, LMFC, SYSREF relations; optionally repeat in 1× comparison mode | PASS if all values consistent with configuration; document both FPGA/JESD input rate and internal DAC clock / Nyquist interpretation | `regs_ad9144.json`, `config.csv` |
| DAC‑2 | DAC update‑rate envelope reporting | Document and test select rates; must reference datasheet max. Update rate depends on supply citeturn9view0 | PASS if selected test rates ≤ datasheet limits and operate stably | `rate_sweep.csv` |
| DAC‑3 | Report interface‑limited adjusted data rate constraints | Use AD9144 Table 2 adjusted rates; ensure test plan does not violate | PASS if any claimed “input data rate” respects adjusted limits citeturn9view0 | `rate_constraints.md` |
| SYN‑1 | FPGA DDS tone accuracy & stability | SA frequency counter function or time‑domain FFT; measure f_out error and drift over time | PASS if frequency error ≤1 ppm (locked to clock) and drift bounded over soak | `tone_accuracy.csv` |
| SYN‑2 | On‑chip NCO programming proof (if enabled) | Write FTW registers and FTW_UPDATE_REQ; verify ftw_update_ack and output frequency shift | PASS if FTW/ack sequence works and measured f_out matches expected; FTW regs 48‑bit citeturn10view1turn10view2 | `nco_programming_log.json`, SA trace |
| ANA‑1 | IOUTFS setting verification | Read back DAC gain registers; measure output amplitude vs IOUTFS codes | PASS if amplitude scales monotonically and matches expected mapping; IOUTFS range 13.9–27.0 mA citeturn7view4turn7view1 | `ioutfs_sweep.csv` |
| ANA‑2 | Output compliance check under max amplitude | Measure DAC output swing at the DAC pins or model the load network; ensure compliance not exceeded | PASS if output stays within −250..+750 mV compliance at DAC outputs citeturn7view1 | `compliance_check.md`, scope traces |
| ANA‑3 | Settling time | Produce step pattern; measure 20 ns scale settling; compare to ±0.5 LSB criterion | PASS if settling ≤ datasheet 20 ns typical target citeturn9view0 | Scope trace + derived settling metrics |
| RF‑1 | SFDR sweep measurement per datasheet definition | SA: current primary automation uses an FSH8 carrier sweep plus segmented left/right spur sweeps; RBW 1 kHz (or 100 Hz for low offsets), VBW ≤ RBW, exclude DC and document harmonic handling/windowing | PASS if computed SFDR meets RF‑2 thresholds; SFDR definition per datasheet citeturn8view0 | `sfdr_sweep.csv`, SA traces |
| RF‑2 | SFDR thresholds in the current default 2× mode | Use defined sweep points: 10, 50, 100, 200, 300, 400, 450 MHz; back‑off = −6 dBFS | MUST: ≥55 dBc across band; SHOULD: ≥65 dBc ≤100 MHz; thresholds set below typical curves and compared against the present 983.04 MSPS input / 1966.08 MHz DAC-clock baseline citeturn11view0 | `sfdr_points.csv` |
| RF‑3 | NSD measurement | SA in noise density mode or compute from spectrum around tone; document reference impedance and RBW corrections | PASS if NSD within expected band and consistent with datasheet trend shapes citeturn11view1turn11view2 | `nsd.csv`, traces |
| RF‑4 | IMD3 two‑tone | Two tones at f1,f2 with defined spacing (1, 16, 35 MHz examples) and back‑off; measure IMD3 products | Report IMD3; compare to datasheet exemplars; do not claim pass unless threshold defined from use case citeturn11view1turn11view0 | `imd3.csv`, traces |
| RF‑5 | Output phase noise | SA PN mode at representative f_out; compare PLL on/off if relevant; integrate jitter offsets | Report and compare; include phase noise plot like datasheet provides citeturn11view2turn4view3 | `phase_noise.csv` |
| JIT‑1 | Jitter‑limited SNR calculation section | Use formula reference; compute required clock jitter at each f_out; compare with measured SNR | PASS (documentation): include computed SNR_jitter vs measured SNR and discuss deltas citeturn12search2turn12search8 | `snr_jitter_model.ipynb` |
| TIM‑2 | Agility latency (freq/phase/amp hop) + commit-time classification | Insert marker (time‑domain) and command update; capture time‑to‑settle and any transients. Explicitly run early/due/late vectors and read scheduler status/IRQ registers. | MUST: report p50/p95/p99/max latency; MUST show expected behavior for early/due/late classes; for a missed deadline (`ts < now` at first compare), MUST transition to `ERROR` with `ERR_MISSED_DEADLINE` and assert `IRQ_UNDERRUN`. | `latency_stats.csv`, `commit_timing_validation.csv`, waveforms, register dumps |
| TIM‑3 | SYSREF periodicity rules | If periodic SYSREF, verify period = integer multiple of LMFC; verify no mid‑multiframe pulses | PASS if compliant and aligned; subclass‑1 guidance citeturn15view1 | `sysref_period_check.csv` |
| MEM‑1 | Unique waveform horizon vs memory | For each waveform class, compute stored parameters memory; compute equivalent sample‑buffer memory at same fs and bits | MUST: provide tables and plots for horizon vs bytes | `memory_horizon.csv` |
| MEM‑3 | External comparator documentation | Use published memory depths to contextualize sample‑buffer limits (e.g., 32 GSamples class). citeturn14search0turn14search4 | PASS (documentation): comparator table is accurate and clearly normalized | `comparators.md` |
| COH‑1 | Inter‑channel phase coherence | Dual‑channel capture; compute phase difference vs time; optionally VSA cross‑channel measurement | MUST: report phase drift and coherence; tie to clock skew expectations citeturn4view0turn4view2 | `coherence.csv` |
| REL‑1 | 8h soak | Automated periodic captures: link status, RF tone frequency/amplitude, temperature | MUST: zero link drops; bounded drift; all raw telemetry saved | `soak_timeseries.csv` |
| SAFE‑2 | Electrical limits compliance | Checklist + measured evidence that supplies, compliance limits, and clock amplitude are within datasheet ranges | MUST: no violations; documented in report citeturn9view0turn7view1 | `safety_checklist.md` |

## Workplan mapping and staged measurement schedule

This maps each requirement group to your previously defined stages (S2–S6), Tracks (A–H), and Suites (S0–S5). Since you have completed S0/S1 gates, focus now begins at S2.

### Requirement‑to‑plan mapping

| Requirement group | Stage | Track(s) | Suite(s) | When to measure | Stage acceptance tie‑in |
|---|---|---|---|---|---|
| Clock/SYSREF: CLK‑1..CLK‑5, TIM‑3 | S2 | Track A (clock determinism), Track C (analog integrity) | Suite S0 (regression), Suite S5 (coherence) | Pre‑S2 exit and re‑measure post any clock tree change | S2 exit requires SYSREF timing compliance and bounded skew |
| JESD envelope + deterministic: JESD‑1..JESD‑5, TIM‑1 | S2 | Track A + Track B | Suite S0, Suite S1 | Pre‑S2 exit + after any JESD parameter change | S2 exit requires deterministic latency repeatability evidence |
| DAC operating points: DAC‑1..DAC‑3 | S2 → S3 | Track C + Track E | Suite S2 (spectral), Suite S4 (long duration) | Baseline before benchmark campaign; again when expanding rates | S3 entry requires baseline mode fully characterized |
| RF fidelity: RF‑1..RF‑5, JIT‑1 | S3 → S5 | Track C + Track D + Track G | Suite S2 | Baseline in S3; full sweeps in S5 | S5 exit requires complete spectral dataset with CIs |
| Agility/latency: TIM‑2, SYN‑1 | S3 → S5 | Track D + Track E + Track G | Suite S3 | Implement in S3; campaign in S5 | Must support publication claims about real‑time control |
| Memory advantage: MEM‑1..MEM‑3 | S3 → S6 | Track E + Track G + Track H | Suite S4 | Define in S3; measure in S5; finalize in S6 | Central publication claim: quantified compression/horizon |
| Multi‑channel coherence: COH‑1..COH‑2 | S3 → S5 | Track C + Track D | Suite S5 | Baseline S3; campaign S5 | Needed for AWG credibility (I/Q or multi‑channel experiments) |
| ARTIQ comparison hooks (comparators): MEM‑3 + TIM‑2 (external) | S4 | Track F | (external mapping) | Only after baseline is fixed | Ensures apples‑to‑apples comparison |
| Packaging and reproducibility: SAFE‑x, REL‑x, metadata | S6 | Track H | All | Final pass | Publication‑grade reproducibility bundle |

### Mermaid staged measurement timeline

```mermaid
gantt
    title Staged measurement schedule for publication-grade AWG benchmark (S2–S6)
    dateFormat  YYYY-MM-DD
    axisFormat  %b %d

    section S2 Bring-up closure (determinism-ready)
    Clock tree + SYSREF timing (CLK-1..5, TIM-3)    :a1, 2026-02-19, 7d
    Subclass-1 latency repeatability (TIM-1/JESD-2) :a2, after a1, 7d
    PRBS + long link soak gate (JESD-5/REL-1-lite)  :a3, after a2, 5d

    section S3 Benchmark infrastructure ready
    Automation harness (artifacts, SCPI, logs)      :b1, 2026-03-10, 10d
    Baseline spectral sweep @983MSPS (RF-1..5)      :b2, after b1, 10d
    Agility/latency suite (TIM-2)                   :b3, after b1, 7d
    Memory metric definitions + baselines (MEM-1..3):b4, after b1, 10d

    section S4 External baseline integration
    ARTIQ workload parity implementation            :c1, 2026-04-05, 14d
    Side-by-side pilot run                          :c2, after c1, 7d

    section S5 Benchmark campaign
    Full RF matrix + repetitions                     :d1, 2026-04-26, 21d
    Long-duration horizons + soak tests              :d2, parallel d1, 21d
    Coherence + restart determinism                  :d3, parallel d1, 14d

    section S6 Packaging and publication
    Repro bundle + scripts + dataset freeze          :e1, 2026-05-20, 10d
    Final report figures + methods + threats         :e2, after e1, 10d
```

## Prioritization, dependencies, and source basis

### MUST / SHOULD / NICE priorities and dependencies

**MUST (publication blockers)**
- Subclass‑1 deterministic latency repeatability (TIM‑1, JESD‑2/3) depends on: CLK‑4/5, TIM‑3, SYSREF distribution rules. citeturn15view0turn3view3turn9view0  
- Spectral sweep and reporting with correct definitions (RF‑1..RF‑3) depends on: stable clocking, stable link, calibrated measurement chain. citeturn8view0turn11view0  
- Memory efficiency/horizon metrics (MEM‑1/2) depends on: a defined waveform ISA and logging of parameter memory footprint.  
- Reproducible automated capture + artifacts (Track D) depends on: stable firmware interface and instrument SCPI link.

**SHOULD (strongly recommended for credible comparison)**
- Two‑tone IMD3 and phase noise reporting (RF‑4/5) depends on SA/VSA capability. citeturn11view2turn11view1  
- NCO feature disclosure (SYN‑2) if you intend to claim high‑IF placement flexibility; depends on using FTW registers and update handshake. citeturn10view1turn10view2  
- ARTIQ baseline comparison (Track F) depends on finished S3 harness and workload taxonomy. For ARTIQ timing, include underflow semantics and slack reporting. citeturn13search0turn13search4  

**NICE (add value, not required for first paper)**
- Eye diagram/BER at the lane level (requires specialized gear).
- Expanded sample‑rate modes beyond the current **983.04 MSPS FPGA/JESD input baseline** (requires additional validation using AD9144 update‑rate tables). citeturn9view0  

### Primary sources used and key sections/pages

Because direct citation of your attached firmware/HDL is not available in this environment, the spec anchors on official/public primary sources and treats HDL‑specific parameters (DDS accumulator widths, internal datapath widths, event scheduler granularity) as “to be reported from HDL.” Implementation-state notes below were cross-checked against the current local `fmcdac/docu` set.

- **Current implementation-state cross-checks (local project docs)**
  - `clock_architecture.md`: current default clock tree, 2× interpolation baseline, and OUT1/OUT6/OUT7/OUT9 routing.
  - `CURRENT_EVALUATION_STATUS.md` and `BENCHMARK_RESULTS_AND_HISTORY.md`: current DDS-band, SFDR, throughput, and UART RTT baselines.
  - `AUTOMATION_AND_IMPLEMENTATION_STATUS.md`: primary FSH8 automation scope and current open items.
  - `MODE9_HDL_REQUIREMENTS.md`: why the current driver "mode 9" does not solve >491.52 MHz FPGA bandwidth.

- **AD9144 datasheet (Rev. D, Analog Devices)**  
  - Features: interpolation modes, fixed latency and protection features. citeturn2view0turn8view3  
  - DC/Digital specifications: max sample rate, JESD lane rate limits, SYSREF timing, clock input limits, update‑rate tables. citeturn9view0  
  - Subclass support and deterministic latency requirements (Subclass 0/1; SYSREF alignment and “½ DAC clock” statement). citeturn3view3  
  - NCO: alignment modes; FTW registers and update handshake. citeturn10view0turn10view1turn10view2  
  - Typical performance plots (SFDR/IMD/NSD/phase noise) used to set conservative thresholds and define sweep points. citeturn11view0turn11view1turn11view2  

- **AD9516‑1 datasheet (Rev. C, Analog Devices)**  
  - Output type frequency limits and additive jitter; skew. citeturn2view1turn4view0turn4view2  
  - Phase noise and jitter terminology / plots; output synchronization mechanisms. citeturn4view3turn4view4  

- **JESD204B background**
  - entity["organization","JEDEC","semiconductor standards body"] JESD204B summary guidance (survival guide): lane rate classes up to 12.5 Gbps, SYSREF role, subclass definitions, 100 Ω interface expectations. citeturn2view2  
  - entity["company","Texas Instruments","semiconductor company"] subclass‑1 practical guidance: SYSREF options (one‑shot/gapped/periodic), SYSREF period integer multiple of LMFC, distribution requirements. citeturn15view1  
  - Analog Devices technical article on deterministic latency definition and repeatability across power cycles/resync. citeturn15view0  

- **FPGA/board transceiver docs**
  - KCU116 / XCKU5P documentation: GTH quad mapping and FMC refclk connectivity for the current implementation. citeturn5view1  
  - XCKU5P transceiver documentation: GTH line-rate table and package-limit notes relevant to the 4-lane 9.8304 Gbps JESD link. citeturn6view4turn6view1  
  - Transceiver reference clock range and phase noise mask examples. citeturn5view2  

- **Comparator baseline (memory‑based AWG and ARTIQ ecosystem)**
  - entity["company","Tektronix","test and measurement company"] AWG70000B: memory depth and general constraints for long waveforms. citeturn14search0turn14search4  
  - entity["company","Keysight Technologies","test and measurement company"], entity["company","National Instruments","test and measurement company"]: referenced only for context, not required for your core benchmark claims. citeturn14search17turn14search3  
  - entity["organization","M-Labs","artiq developer"] ARTIQ timing/RTIO underflow semantics and RAM‑profile address width (10‑bit). citeturn13search0turn13search29turn13search1  
  - M‑Labs Phaser datasheet (if you use Phaser as an AWG comparator). citeturn13search2turn13search6  

### Open‑ended items to extract from HDL/firmware for publication completeness

These are not optional for a publication‑grade “system spec” section; they simply require extracting and reporting values from HDL/firmware:
- FPGA DDS architecture: phase accumulator width, LUT/CORDIC depth, dithering, spur mitigation strategy, update handshake and pipeline latency.
- Data path width/packing: confirmed sample format, interleaving, and any rounding/saturation.
- Control update granularity: minimum time between parameter updates without underflow/overflow, and whether updates are deterministic vs host‑timed.

These items directly affect **SYN‑1, TIM‑2, MEM‑1**, and the fairness of ARTIQ comparisons.
