<#
.SYNOPSIS
    One-shot build: reassembles out/GStreamer-Glass.ps1 from src/*.ps1, then
    compiles out/GStreamer Glass.exe from it with ps12exe.

.DESCRIPTION
    Requires the ps12exe module (Install-Module ps12exe -Scope CurrentUser).
    The exe's file-version resource is read straight from $script:AppVersion
    in src/00-Setup.ps1 so it can never drift from what the app reports at
    runtime -- there is nothing else to keep in sync by hand.
#>

[CmdletBinding()]
param(
    [string]$SrcDir = (Join-Path $PSScriptRoot 'src'),
    [string]$OutDir = (Join-Path $PSScriptRoot 'out'),
    [string]$IconPath = (Join-Path $PSScriptRoot 'icons\Glass2Glass-Streamer.ico')
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command ps12exe -ErrorAction SilentlyContinue)) {
    throw "ps12exe is not available on this machine. Install it with: Install-Module ps12exe -Scope CurrentUser"
}

# Step 1: reassemble the monolith from src/*.ps1.
$monolithPath = Join-Path $OutDir 'GStreamer-Glass.ps1'
& (Join-Path $PSScriptRoot 'tools\build-monolith.ps1') -SrcDir $SrcDir -OutputPath $monolithPath

# Step 2: read the app version from source so the exe resource stays honest.
$setupPath = Join-Path $SrcDir '00-Setup.ps1'
$versionMatch = Select-String -Path $setupPath -Pattern "AppVersion\s*=\s*'([^']+)'" | Select-Object -First 1
if (-not $versionMatch) { throw "Could not find `$script:AppVersion in $setupPath." }
$rawVersion = $versionMatch.Matches[0].Groups[1].Value

# Windows file-version resources are strictly numeric a.b.c.d; strip any
# trailing point-release suffix (e.g. the 'a' in '3.8.3a') and pad to 4 parts.
$numericParts = @(($rawVersion -replace '[^\d.].*$', '') -split '\.' | Where-Object { $_ -ne '' })
while ($numericParts.Count -lt 4) { $numericParts += '0' }
$exeVersion = ($numericParts[0..3] -join '.')

# Step 3: compile the exe from the freshly built monolith. Flags mirror the
# working config previously saved in tools/ps12exe/GStreamer_Glass.psccfg.
$exePath = Join-Path $OutDir 'GStreamer Glass.exe'

ps12exe `
    -inputFile $monolithPath `
    -outputFile $exePath `
    -iconFile $IconPath `
    -title 'GStreamer Glass' `
    -description 'Ultra-low-latency glass-to-glass streaming using gstreamer' `
    -company 'NETLABWORK' `
    -product 'GStreamer Glass' `
    -copyright ([string](Get-Date).Year) `
    -version $exeVersion `
    -CompilerOptions '/o+ /debug-' `
    -architecture anycpu `
    -threadingModel MTA `
    -noConsole `
    -longPaths `
    -DPIAware `
    -configFile `
    -supportOS

Write-Output "Built '$exePath' (v$rawVersion, file version $exeVersion)"
