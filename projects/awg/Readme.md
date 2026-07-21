# AWG HDL Project

Target: KCU116 + AD9144 FMC DAC.

Tool version: Vivado 2021.2.

Start here:

- `BUILD_AND_USE.md` - repo map, build steps, outputs, and handoff checklist.
- `SYSTEM_OVERVIEW.md` - system behavior and current architecture.
- `SYSTEM_BLOCK_DIAGRAM_AND_DATAPATHS.md` - datapaths and block diagrams.
- `PHASE_E_CLOSURE_REPORT.md` - HDL build state and closure gates.
- `PHASE_F_FIRMWARE_CLOSURE_PROMPT.md` - firmware handoff for the generated XSA.

Main commands for the external build machine:

```powershell
cd C:\path\to\hdl-adi-fork
.\projects\awg\build_awg_kcu116.ps1 -Variant C1
.\projects\awg\build_awg_kcu116.ps1 -Variant Direct
```

Use `BUILD_AND_USE.md` before running either command. It explains required
tools, generated files, build variants, logs, and the firmware handoff.
