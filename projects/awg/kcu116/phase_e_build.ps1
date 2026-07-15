param(
  [string]$VivadoBat = "C:\Xilinx\Vivado\2021.2\bin\vivado.bat",
  [int]$Jobs = 4,
  [switch]$SkipSchedulerRegression,
  [switch]$SkipProjectBuild
)

$ErrorActionPreference = "Stop"

$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = (Resolve-Path (Join-Path $ProjectDir "..\..\..")).Path
$LogDir = Join-Path $ProjectDir "phase_e_logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$env:ADI_HDL_DIR_LITERAL = ($RepoDir -replace "\\", "/")
$env:ADI_MAX_OOC_JOBS = [string]$Jobs
$env:AWG_PHASE_E_VALIDATE_BD = "1"
$env:AWG_PHASE_E_POST_IMPL_VERIFY = "1"
$env:ADI_ADD_FILES_WRAPPER = "1"

if (!(Test-Path -LiteralPath $VivadoBat)) {
  throw "Vivado 2021.2 batch launcher not found: $VivadoBat"
}

if (!$SkipSchedulerRegression) {
  $RegressionPs1 = Join-Path $RepoDir "projects\awg\common\tb\run_awg_scheduler_regression.ps1"
  & $RegressionPs1 -VivadoBat $VivadoBat 2>&1 |
    Tee-Object -FilePath (Join-Path $LogDir "phase_e_scheduler_regression.log")
  if ($LASTEXITCODE -ne 0) {
    throw "Scheduler regression failed with exit code $LASTEXITCODE"
  }
}

if (!$SkipProjectBuild) {
  Push-Location $ProjectDir
  try {
    & $VivadoBat -mode batch -source system_project.tcl -notrace 2>&1 |
      Tee-Object -FilePath (Join-Path $LogDir "phase_e_vivado_build.log")
    if ($LASTEXITCODE -ne 0) {
      throw "Phase E Vivado build failed with exit code $LASTEXITCODE"
    }
  } finally {
    Pop-Location
  }
}

Write-Host "Phase E HDL/build closure completed. Logs: $LogDir"
