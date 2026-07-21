[CmdletBinding()]
param(
  [ValidateSet("C1", "Direct")]
  [string]$Variant = "C1",

  [string]$VivadoBat = "C:\Xilinx\Vivado\2021.2\bin\vivado.bat",

  [ValidateRange(1, 256)]
  [int]$Jobs = 4,

  [string]$ArtifactRoot,

  [switch]$SkipSchedulerRegression,

  [switch]$AllowDirtySource
)

$ErrorActionPreference = "Stop"

$AwgDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$HdlDir = (Resolve-Path (Join-Path $AwgDir "..\..")).Path
$Kcu116Dir = Join-Path $AwgDir "kcu116"
$PhaseEBuild = Join-Path $Kcu116Dir "phase_e_build.ps1"
$BitFile = Join-Path $Kcu116Dir "awg_kcu116.runs\impl_1\system_top.bit"
$XsaFile = Join-Path $Kcu116Dir "awg_kcu116.sdk\system_top.xsa"
$LogDir = Join-Path $Kcu116Dir "phase_e_logs"
$AbiHeader = Join-Path $AwgDir "common\awg_sched_regs.h"
$ExtensionAbiHeader = Join-Path $AwgDir "common\awg_extension_regs.h"
$ManifestWriter = Join-Path $AwgDir "write_awg_build_manifest.ps1"

if (!(Test-Path -LiteralPath $VivadoBat -PathType Leaf)) {
  throw "Vivado 2021.2 batch launcher not found: $VivadoBat"
}

$MakeCommand = Get-Command make -CommandType Application -ErrorAction SilentlyContinue
if ($null -eq $MakeCommand) {
  throw "GNU Make was not found. Install it and add it to PATH."
}
$MakePath = @($MakeCommand)[0].Source

if (!(Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) {
  throw "Git was not found. Install it and add it to PATH."
}
$DirtySource = @(& git -C $HdlDir status --porcelain)
if ($LASTEXITCODE -ne 0) {
  throw "Could not read Git status for $HdlDir"
}
if ($DirtySource.Count -gt 0 -and !$AllowDirtySource) {
  throw "The HDL worktree is dirty. Commit/stash it, or pass -AllowDirtySource for a development build."
}

if ($ArtifactRoot -and ![System.IO.Path]::IsPathRooted($ArtifactRoot)) {
  throw "ArtifactRoot must be an absolute path: $ArtifactRoot"
}

$AbsoluteArtifactRoot = ''
if ($ArtifactRoot) {
  $AbsoluteArtifactRoot = [System.IO.Path]::GetFullPath($ArtifactRoot)
  $ForbiddenRoots = @($HdlDir)
  $SuperProjectOutput = @(
    & git -C $HdlDir rev-parse --show-superproject-working-tree 2>$null
  )
  if ($LASTEXITCODE -eq 0 -and $SuperProjectOutput.Count -gt 0) {
    $SuperProject = ($SuperProjectOutput -join '').Trim()
    if (![string]::IsNullOrWhiteSpace($SuperProject)) {
      $ForbiddenRoots += (Resolve-Path -LiteralPath $SuperProject).Path
    }
  }
  foreach ($Root in $ForbiddenRoots) {
    $RootPath = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')
    $RootPrefix = $RootPath + [IO.Path]::DirectorySeparatorChar
    if ($AbsoluteArtifactRoot.Equals($RootPath,
          [StringComparison]::OrdinalIgnoreCase) -or
        $AbsoluteArtifactRoot.StartsWith($RootPrefix,
          [StringComparison]::OrdinalIgnoreCase)) {
      throw "ArtifactRoot must be outside the Git worktree: $AbsoluteArtifactRoot"
    }
  }
  if (!(Test-Path -LiteralPath $AbsoluteArtifactRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $AbsoluteArtifactRoot -Force | Out-Null
  }
  if (!(Test-Path -LiteralPath $ManifestWriter -PathType Leaf)) {
    throw "Build manifest writer not found: $ManifestWriter"
  }
}

$OriginalPath = $env:Path
$OriginalC1 = $env:AWG_ENABLE_C1
$HadOriginalC1 = Test-Path Env:AWG_ENABLE_C1

try {
  $VivadoBin = Split-Path -Parent $VivadoBat
  $env:Path = "$VivadoBin;$OriginalPath"
  $env:AWG_ENABLE_C1 = if ($Variant -eq "C1") { "1" } else { "0" }

  Write-Host "AWG KCU116 variant: $Variant (AWG_ENABLE_C1=$env:AWG_ENABLE_C1)"
  Write-Host "Packaging required ADI HDL libraries..."

  Push-Location $HdlDir
  try {
    & $MakePath -C projects/awg/kcu116 lib REQUIRED_VIVADO_VERSION=2021.2
    if ($LASTEXITCODE -ne 0) {
      throw "ADI HDL library packaging failed with exit code $LASTEXITCODE"
    }
  } finally {
    Pop-Location
  }

  Write-Host "Running the Phase E build and closure gates..."
  if ($SkipSchedulerRegression) {
    & $PhaseEBuild `
      -VivadoBat $VivadoBat `
      -Jobs $Jobs `
      -SkipSchedulerRegression
  } else {
    & $PhaseEBuild `
      -VivadoBat $VivadoBat `
      -Jobs $Jobs
  }

  $Missing = @()
  if (!(Test-Path -LiteralPath $BitFile -PathType Leaf)) {
    $Missing += $BitFile
  }
  if (!(Test-Path -LiteralPath $XsaFile -PathType Leaf)) {
    $Missing += $XsaFile
  }
  if ($Missing.Count -ne 0) {
    throw ("Licensed AWG build incomplete. Missing: " + ($Missing -join "; ") +
      ". A full XXV Ethernet v4.0 license is required.")
  }

  Write-Host "Licensed AWG build completed."
  Write-Host "Bitstream: $BitFile"
  Write-Host "XSA: $XsaFile"

  if ($ArtifactRoot) {
    $Stamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff")
    $BundleName = "{0}_awg_kcu116-{1}" -f $Stamp, $Variant.ToLowerInvariant()
    $BundleDir = Join-Path $AbsoluteArtifactRoot $BundleName
    $BundleLogDir = Join-Path $BundleDir "phase_e_logs"

    if (Test-Path -LiteralPath $BundleDir) {
      throw "Artifact bundle already exists: $BundleDir"
    }
    New-Item -ItemType Directory -Path $BundleDir | Out-Null
    Copy-Item -LiteralPath $BitFile -Destination (Join-Path $BundleDir "system_top.bit") -Force
    Copy-Item -LiteralPath $XsaFile -Destination (Join-Path $BundleDir "system_top.xsa") -Force
    Copy-Item -LiteralPath $AbiHeader -Destination (Join-Path $BundleDir "awg_sched_regs.h") -Force
    Copy-Item -LiteralPath $ExtensionAbiHeader -Destination (Join-Path $BundleDir "awg_extension_regs.h") -Force

    if (Test-Path -LiteralPath $LogDir -PathType Container) {
      New-Item -ItemType Directory -Force -Path $BundleLogDir | Out-Null
      Get-ChildItem -LiteralPath $LogDir -File | Copy-Item -Destination $BundleLogDir -Force
    }

    & $ManifestWriter `
      -Variant $Variant `
      -OutputDir $BundleDir `
      -BitPath (Join-Path $BundleDir "system_top.bit") `
      -XsaPath (Join-Path $BundleDir "system_top.xsa") `
      -LogDir $BundleLogDir
    if (-not $?) {
      throw "HDL build manifest generation failed."
    }

    Write-Host "Artifact bundle: $BundleDir"
  }
} finally {
  $env:Path = $OriginalPath
  if ($HadOriginalC1) {
    $env:AWG_ENABLE_C1 = $OriginalC1
  } else {
    Remove-Item Env:AWG_ENABLE_C1 -ErrorAction SilentlyContinue
  }
}
