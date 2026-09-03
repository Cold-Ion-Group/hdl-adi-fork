param(
  [ValidateSet("C1", "Direct")]
  [string]$Variant = "C1",
  [Parameter(Mandatory = $true)]
  [string]$OutputDir,
  [string]$BitPath,
  [string]$XsaPath,
  [string]$LogDir
)

$ErrorActionPreference = "Stop"

function Resolve-OrCreateDirectory {
  param([string]$Path)
  if (!(Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
  return (Resolve-Path -LiteralPath $Path).Path
}

function Get-OptionalFileRecord {
  param([string]$Path, [string]$Role)
  if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $null
  }
  $item = Get-Item -LiteralPath $Path
  $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $Path
  return [ordered]@{
    role = $Role
    path = $item.FullName
    bytes = $item.Length
    sha256 = $hash.Hash.ToLowerInvariant()
    last_write_utc = $item.LastWriteTimeUtc.ToString("o")
  }
}

$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = (Resolve-Path (Join-Path $ProjectDir "..\..")).Path
$Kcu116Dir = Join-Path $ProjectDir "kcu116"

# Release evidence is valid only for the pinned two-converter construction
# used by build_awg_kcu116.ps1.  Fail closed if this writer is invoked under a
# stale or externally overridden build environment.
$ExpectedBuildEnvironment = [ordered]@{
  AWG_ENABLE_C1 = $(if ($Variant -eq "C1") { "1" } else { "0" })
  ADI_DAC_DEVICE = "AD9144"
  ADI_DAC_MODE = "04"
  ADI_NUM_LINKS = "1"
  AWG_TX_REFCLK_MHZ = "122.88"
  AWG_QPLL_ENABLE = "1"
  AWG_QPLL_REFCLK_DIV = "1"
  AWG_QPLL_FBDIV = "40"
  AWG_TX_OUT_DIV = "1"
}
foreach ($Name in $ExpectedBuildEnvironment.Keys) {
  $Actual = [Environment]::GetEnvironmentVariable($Name, "Process")
  if ($Actual -ne $ExpectedBuildEnvironment[$Name]) {
    throw ("Active-build environment mismatch for {0}: expected {1}, got {2}" -f
      $Name, $ExpectedBuildEnvironment[$Name], $Actual)
  }
}

$ContractSourcePaths = [ordered]@{
  awg_bd = Join-Path $ProjectDir "common\awg_bd.tcl"
  scheduler = Join-Path $ProjectDir "common\awg_timed_ctrl.v"
  extension = Join-Path $ProjectDir "common\awg_extension.v"
  jesd_config = Join-Path $ProjectDir "common\config.tcl"
  system_project = Join-Path $Kcu116Dir "system_project.tcl"
  cordic_core = Join-Path $RepoDir "library\jesd204\ad_ip_jesd204_tpl_dac\ad_ip_jesd204_tpl_dac_core.v"
}
$ContractSources = [ordered]@{}
foreach ($Name in $ContractSourcePaths.Keys) {
  $SourcePath = $ContractSourcePaths[$Name]
  if (!(Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    throw "Active-build contract source is missing: $SourcePath"
  }
  $ContractSources[$Name] = [ordered]@{
    file = (Resolve-Path -LiteralPath $SourcePath).Path
    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourcePath).Hash.ToLowerInvariant()
  }
}

if ([string]::IsNullOrWhiteSpace($BitPath)) {
  $BitPath = Join-Path $Kcu116Dir "awg_kcu116.runs\impl_1\system_top.bit"
}
if ([string]::IsNullOrWhiteSpace($XsaPath)) {
  $XsaPath = Join-Path $Kcu116Dir "awg_kcu116.sdk\system_top.xsa"
}
if ([string]::IsNullOrWhiteSpace($LogDir)) {
  $LogDir = Join-Path $Kcu116Dir "phase_e_logs"
}

$CandidateOutputDir = [IO.Path]::GetFullPath($OutputDir)
$ForbiddenRoots = @($RepoDir)
$SuperProjectOutput = @(
  & git -C $RepoDir rev-parse --show-superproject-working-tree 2>$null
)
$SuperProject = if ($LASTEXITCODE -eq 0 -and $SuperProjectOutput.Count -gt 0) {
  ($SuperProjectOutput -join '').Trim()
} else {
  ''
}
if (![string]::IsNullOrWhiteSpace($SuperProject)) {
  $ForbiddenRoots += (Resolve-Path -LiteralPath $SuperProject).Path
}

foreach ($root in $ForbiddenRoots) {
  $rootResolved = (Resolve-Path -LiteralPath $root).Path.TrimEnd('\', '/')
  $rootPrefix = $rootResolved + [IO.Path]::DirectorySeparatorChar
  if ($CandidateOutputDir.Equals($rootResolved,
        [System.StringComparison]::OrdinalIgnoreCase) -or
      $CandidateOutputDir.StartsWith($rootPrefix,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDir must be outside the Git worktree: $CandidateOutputDir"
  }
}
$ResolvedOutputDir = Resolve-OrCreateDirectory $CandidateOutputDir

$gitSha = (& git -C $RepoDir rev-parse HEAD).Trim()
$gitStatus = @(& git -C $RepoDir status --short)

$artifacts = @()
$bitRecord = Get-OptionalFileRecord -Path $BitPath -Role "bitstream"
if ($null -ne $bitRecord) { $artifacts += $bitRecord }
$xsaRecord = Get-OptionalFileRecord -Path $XsaPath -Role "xsa"
if ($null -ne $xsaRecord) { $artifacts += $xsaRecord }

if (Test-Path -LiteralPath $LogDir -PathType Container) {
  Get-ChildItem -LiteralPath $LogDir -File | Sort-Object Name | ForEach-Object {
    $record = Get-OptionalFileRecord -Path $_.FullName -Role "log_or_report"
    if ($null -ne $record) { $artifacts += $record }
  }
}
foreach ($abi in @(
  @{ Name = 'awg_sched_regs.h'; Role = 'scheduler_abi' },
  @{ Name = 'awg_extension_regs.h'; Role = 'extension_abi' }
)) {
  $record = Get-OptionalFileRecord `
    -Path (Join-Path $ResolvedOutputDir $abi.Name) `
    -Role $abi.Role
  if ($null -ne $record) { $artifacts += $record }
}

$VivadoVersion = if (Get-Command vivado -ErrorAction SilentlyContinue) {
  (& vivado -version 2>$null | Select-Object -First 1)
} else {
  'not found'
}

$manifest = [ordered]@{
  schema = "awg-hdl/build-manifest/1.0"
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
  variant = $Variant
  awg_enable_c1 = $(if ($Variant -eq "C1") { 1 } else { 0 })
  repository = [ordered]@{
    path = $RepoDir
    head = $gitSha
    dirty_status = $gitStatus
  }
  toolchain = [ordered]@{
    required_vivado = '2021.2'
    vivado = $VivadoVersion
  }
  active_build = [ordered]@{
    schema = "awg-hdl/active-build/1.0"
    board = "kcu116"
    variant = $Variant
    build_environment = $ExpectedBuildEnvironment
    scheduler = [ordered]@{
      identity = [ordered]@{ ip_id = "0x41574753"; ip_version = "0x00010000"; ip_caps = "0x08804000" }
      base_address = "0x44AA0000"
      clock_hz = [ordered]@{ numerator = 245760000; denominator = 1 }
      dds_phase_accumulator_bits = 32
      cordic_angle_bits = 16
      min_spacing_ticks = 8
      usable_fifo_entries = 511
      frozen_module_default_channels = 8
      instantiated_channels = 2
    }
    extensions = [ordered]@{
      base_address = "0x44AE0000"
      awgx = [ordered]@{
        ip_id = "0x41574758"
        ip_version = "0x00010000"
        caps = $(if ($Variant -eq "C1") { "0x0000001F" } else { "0x0000000F" })
      }
      awgc = [ordered]@{ ip_id = "0x41574743"; ip_version = "0x00010000"; caps = "0x00402010" }
    }
    address_map = [ordered]@{
      tpl = "0x44A04000"; xcvr = "0x44A60000"; jesd_tx = "0x44A90000"
      scheduler = "0x44AA0000"; scheduler_dma = "0x44AB0000"
      eth_rx_dma = "0x44AC0000"; eth_tx_dma = "0x44AD0000"
      extensions = "0x44AE0000"; eth_mac_10g = "0x44C00000"; dac_dma = "0x7C420000"
    }
    interrupts = [ordered]@{
      jesd_tx = 15; scheduler = 14; dac_dma = 13; scheduler_dma = 12
      eth_rx_dma = 10; eth_tx_dma = 9; eth_mac_10g = "polled-no-discrete-irq"
      processing_system = [ordered]@{
        jesd_tx = 10; scheduler = 11; dac_dma = 12; scheduler_dma = 13
        eth_rx_dma = 14; eth_tx_dma = 15
      }
    }
    jesd = [ordered]@{
      mode = 4; converters = 2; lanes = 4; octets_per_frame = 1
      frames_per_multiframe = 32; bits_per_sample = 16; subclass = 1
    }
    source_provenance = $ContractSources
  }
  expected_outputs = [ordered]@{
    bitstream = (Resolve-Path -LiteralPath $BitPath -ErrorAction SilentlyContinue).Path
    xsa = (Resolve-Path -LiteralPath $XsaPath -ErrorAction SilentlyContinue).Path
    logs = (Resolve-Path -LiteralPath $LogDir -ErrorAction SilentlyContinue).Path
  }
  artifacts = $artifacts
}

$manifestPath = Join-Path $ResolvedOutputDir ("awg_kcu116_{0}_manifest.json" -f $Variant.ToLowerInvariant())
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host "Wrote AWG build manifest: $manifestPath"
