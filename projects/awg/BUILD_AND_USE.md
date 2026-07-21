# Build and Use the KCU116 AWG HDL

This project builds the KCU116 and AD9144 AWG hardware design. The result is a
bitstream for the FPGA and an XSA for the no-OS firmware build.

## Find the Main Files

Start in the HDL repository:

```powershell
Set-Location <workspace>\hdl-adi-fork
```

The main paths are:

| Path | Purpose |
| --- | --- |
| `projects/awg/common/` | Shared scheduler, extension, JESD, and block-design sources |
| `projects/awg/common/awg_sched_regs.h` | Scheduler register ABI used by HDL and firmware |
| `projects/awg/kcu116/` | KCU116 top level, constraints, Makefile, and Vivado scripts |
| `projects/awg/kcu116/system_project.tcl` | Vivado project entry point |
| `projects/awg/kcu116/phase_e_build.ps1` | Existing simulation, build, and closure engine |
| `projects/awg/build_awg_kcu116.ps1` | Clean-machine operator entry point |
| `projects/awg/write_awg_build_manifest.ps1` | Hash and source manifest writer used by the wrapper |

## Install the Build Tools

Use a Windows build machine with:

- Vivado 2021.2 and the KCU116 board files.
- A full license for XXV Ethernet v4.0. This IP is documented in AMD PG210.
- GNU Make in a shell environment that supports the ADI HDL Makefiles.
- PowerShell.

Keep Vivado 2021.2 at the default path or pass its `vivado.bat` path to the
wrapper. Do not bypass the Vivado version check for a release build.

## Choose the Hardware Variant

- `C1` includes the runtime-selectable C1 decoder. This is the default.
- `Direct` removes the C1 decoder datapath and keeps direct pass-through.

Both variants keep the same extension control address.

## Build the Full HDL System

From `hdl-adi-fork`, build the C1 variant:

```powershell
powershell -ExecutionPolicy Bypass `
  -File .\projects\awg\build_awg_kcu116.ps1 `
  -Variant C1 `
  -Jobs 4
```

Build the direct variant:

```powershell
powershell -ExecutionPolicy Bypass `
  -File .\projects\awg\build_awg_kcu116.ps1 `
  -Variant Direct `
  -Jobs 4
```

Use a different Vivado installation when needed:

```powershell
powershell -ExecutionPolicy Bypass `
  -File .\projects\awg\build_awg_kcu116.ps1 `
  -Variant C1 `
  -VivadoBat D:\Xilinx\Vivado\2021.2\bin\vivado.bat
```

The wrapper does the following:

1. Packages all required ADI HDL IP libraries with GNU Make.
2. Sets `AWG_ENABLE_C1` from `-Variant`.
3. Runs the scheduler regression unless it is explicitly skipped.
4. Calls `kcu116/phase_e_build.ps1` for the Vivado build.
5. Runs the block-design and post-implementation closure gates.
6. Fails unless the licensed bitstream and XSA both exist.

Use `-SkipSchedulerRegression` only when the same source revision already has a
recorded passing scheduler regression.

## Copy a Build Bundle

Pass an absolute output directory to keep the firmware handoff files together:

```powershell
powershell -ExecutionPolicy Bypass `
  -File .\projects\awg\build_awg_kcu116.ps1 `
  -Variant C1 `
  -ArtifactRoot D:\awg-builds
```

The wrapper creates a UTC-stamped directory such as
`D:\awg-builds\20260721_120000_123_awg_kcu116-c1\`. The bundle contains:

- `system_top.bit`
- `system_top.xsa`
- `awg_sched_regs.h`
- `awg_extension_regs.h`
- `awg_kcu116_c1_manifest.json` or `awg_kcu116_direct_manifest.json`
- Phase E build reports and logs

Keep the bitstream, XSA, scheduler ABI header, and firmware build from the same
source revision and variant.

`-ArtifactRoot` must be outside the HDL Git worktree. The wrapper refuses to
merge two build bundles with the same name.

## Find the Normal Build Outputs

Without `-ArtifactRoot`, use these files:

```text
projects/awg/kcu116/awg_kcu116.runs/impl_1/system_top.bit
projects/awg/kcu116/awg_kcu116.sdk/system_top.xsa
```

Important reports are under:

```text
projects/awg/kcu116/phase_e_logs/
```

Scheduler simulation logs are under:

```text
projects/awg/common/tb/phase_e_scheduler_regression/<timestamp>/
```

## Use the HDL Build

1. Give `system_top.xsa` to the no-OS firmware build.
2. Build the FMCDAC firmware against that exact XSA.
3. Program the matching `system_top.bit` and firmware image.
4. Start with the normal DDS/JESD bring-up.
5. Enable scheduler DMA and Ethernet streaming only after link and scheduler
   probes pass.

The XSA generates the firmware base-address and interrupt definitions. Do not
replace them with guessed values.

## License Failure

The XXV Ethernet v4.0 core requires a bitstream-generation license. Without it,
Vivado can finish routing but cannot create the bitstream or bitstream-inclusive
XSA. The wrapper treats missing outputs as a failed build.

The `allow_license_block` argument in `phase_e_post_impl_verify.tcl` is only for
reviewing a routed design. It does not produce a usable hardware handoff and is
not full system closure.

## Clean Generated Files

Clean only the KCU116 project outputs:

```powershell
make -C projects/awg/kcu116 clean
```

Also remove packaged copies of the project IP libraries:

```powershell
make -C projects/awg/kcu116 clean-all
```
