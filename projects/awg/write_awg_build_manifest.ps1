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
