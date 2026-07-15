param(
  [string]$VivadoBat = "C:\Xilinx\Vivado\2021.2\bin\vivado.bat"
)

$ErrorActionPreference = "Stop"

$TbDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = (Resolve-Path (Join-Path $TbDir "..\..\..\..")).Path
$VivadoBin = Split-Path -Parent $VivadoBat
$Xvlog = Join-Path $VivadoBin "xvlog.bat"
$Xelab = Join-Path $VivadoBin "xelab.bat"
$Xsim = Join-Path $VivadoBin "xsim.bat"

foreach ($tool in @($Xvlog, $Xelab, $Xsim)) {
  if (!(Test-Path -LiteralPath $tool)) {
    throw "Missing Vivado simulator tool: $tool"
  }
}

$RunId = Get-Date -Format "yyyyMMdd_HHmmss"
$WorkRoot = Join-Path $TbDir "phase_e_scheduler_regression\$RunId"
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

$CommonSources = @(
  "library\common\ad_mem.v",
  "library\util_cdc\sync_bits.v",
  "library\util_cdc\sync_gray.v",
  "library\util_axis_fifo\util_axis_fifo_address_generator.v",
  "library\util_axis_fifo\util_axis_fifo.v",
  "projects\awg\common\awg_timed_ctrl.v"
) | ForEach-Object { Join-Path $RepoDir $_ }

$Benches = @(
  @{ Name = "legacy_axi";            File = "projects\awg\test\awg_timed_ctrl_tb.v";              Top = "awg_timed_ctrl_tb" },
  @{ Name = "mode_locked";           File = "projects\awg\common\tb\tb_mode_locked.v";            Top = "testbench" },
  @{ Name = "stream_empty_wait";     File = "projects\awg\common\tb\tb_stream_empty_wait.v";      Top = "testbench" },
  @{ Name = "stream_eof";            File = "projects\awg\common\tb\tb_stream_eof.v";             Top = "testbench" },
  @{ Name = "stream_hard_underrun";  File = "projects\awg\common\tb\tb_stream_hard_underrun.v";   Top = "testbench" },
  @{ Name = "stream_low_watermark";  File = "projects\awg\common\tb\tb_stream_low_watermark.v";   Top = "testbench" },
  @{ Name = "stream_overflow";       File = "projects\awg\common\tb\tb_stream_overflow_refused.v"; Top = "testbench" },
  @{ Name = "stream_soft_reset";     File = "projects\awg\common\tb\tb_stream_soft_reset_flush.v"; Top = "testbench" },
  @{ Name = "dma_mode_mux";          File = "projects\awg\common\tb\tb_dma_mode_mux.v";            Top = "testbench" },
  @{ Name = "dma_backpressure_full"; File = "projects\awg\common\tb\tb_dma_backpressure_full.v";   Top = "testbench" },
  @{ Name = "dma_stop_soft_reset";   File = "projects\awg\common\tb\tb_dma_stop_soft_reset.v";     Top = "testbench" },
  @{ Name = "stream_occupancy";      File = "projects\awg\common\tb\tb_stream_occupancy_rollover.v"; Top = "testbench" }
)

$Failures = 0

foreach ($bench in $Benches) {
  $Name = $bench.Name
  $BenchWork = Join-Path $WorkRoot $Name
  New-Item -ItemType Directory -Force -Path $BenchWork | Out-Null
  $BenchFile = Join-Path $RepoDir $bench.File
  $Snapshot = "sim_$Name"

  Write-Host "PHASE_E_REGRESSION: compiling $Name"
  Push-Location $BenchWork
  try {
    & $Xvlog -sv -i $TbDir -log "$Name`_xvlog.log" @CommonSources $BenchFile | Out-Host
    if ($LASTEXITCODE -ne 0) {
      throw "xvlog failed for $Name"
    }

    Write-Host "PHASE_E_REGRESSION: elaborating $Name"
    & $Xelab -debug typical -log "$Name`_xelab.log" $bench.Top -s $Snapshot | Out-Host
    if ($LASTEXITCODE -ne 0) {
      throw "xelab failed for $Name"
    }

    Write-Host "PHASE_E_REGRESSION: running $Name"
    & $Xsim $Snapshot -runall -log "$Name`_xsim.log" | Out-Host
    if ($LASTEXITCODE -ne 0) {
      throw "xsim failed for $Name"
    }

    $SimText = Get-Content "$Name`_xsim.log" -Raw
    if (($SimText -notmatch "(?m)^SUCCESS$") -or ($SimText -match "(?m)^.*FAILED")) {
      throw "$Name did not report clean SUCCESS"
    }

    Write-Host "PHASE_E_REGRESSION: $Name PASS"
  } catch {
    $Failures++
    Write-Host "PHASE_E_REGRESSION: $Name FAIL: $($_.Exception.Message)"
  } finally {
    Pop-Location
  }
}

if ($Failures -ne 0) {
  throw "PHASE_E_REGRESSION: $Failures bench(es) failed. Work root: $WorkRoot"
}

Write-Host "PHASE_E_REGRESSION: all scheduler benches passed. Work root: $WorkRoot"
