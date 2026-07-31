# SPDX-License-Identifier: AGPL-3.0-only

<#
.SYNOPSIS
    One-shot build: reassembles out/GStreamer-Glass.ps1 from src/*.ps1,
    compiles out/GStreamer Glass.exe with ps12exe, then runs build.iss
    through the Inno Setup command-line compiler.

.DESCRIPTION
    Requires:
      - ps12exe (Install-Module ps12exe -Scope CurrentUser)
      - Inno Setup 6 or 7

    The application version is read from $script:AppVersion in
    src/00-Setup.ps1. PowerShell passes only that version to Inno Setup;
    build.iss remains the sole owner of installer configuration.
#>

[CmdletBinding()]
param(
    [string]$SrcDir = (Join-Path $PSScriptRoot 'src'),
    [string]$OutDir = (Join-Path $PSScriptRoot 'out'),
    [string]$IconPath = (Join-Path $PSScriptRoot 'icons\Glass2Glass-Streamer.ico'),
    [string]$IssPath = (Join-Path $PSScriptRoot 'build.iss')
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

# Step 4: exercise DPAPI inside the compiled PS12EXE host. Console PowerShell
# loads a broader default assembly set than the shipped no-console executable,
# so a source-level cache test alone cannot catch a missing System.Security.dll.
$cryptoSmoke = Start-Process `
    -FilePath $exePath `
    -ArgumentList @('-AuthCacheCryptoSelfTest') `
    -WindowStyle Hidden `
    -PassThru `
    -Wait
try {
    if ($cryptoSmoke.ExitCode -ne 0) {
        throw "Compiled auth-cache DPAPI smoke test failed with exit code $($cryptoSmoke.ExitCode)."
    }
}
finally {
    $cryptoSmoke.Dispose()
}
Write-Output 'Compiled auth-cache DPAPI smoke test passed.'

# The GUI host is deliberately MTA, so OLE-backed clipboard operations must
# always cross onto GstClipboard's dedicated STA helper thread.
$clipboardSmoke = Start-Process `
    -FilePath $exePath `
    -ArgumentList @('-ClipboardApartmentSelfTest') `
    -WindowStyle Hidden `
    -PassThru `
    -Wait
try {
    if ($clipboardSmoke.ExitCode -ne 0) {
        throw "Compiled clipboard apartment smoke test failed with exit code $($clipboardSmoke.ExitCode)."
    }
}
finally {
    $clipboardSmoke.Dispose()
}
Write-Output 'Compiled clipboard STA-helper smoke test passed.'

# Exercise the temporary-link IPC contract inside the compiled host too. The
# PS2EXE Windows PowerShell adapter has previously serialized dynamically
# compiled CLR fields differently from console PowerShell, yielding blank
# records and an epoch date only in the installed application.
& (Join-Path $PSScriptRoot 'tools\tests\test-compiled-auth-proxy-temporary-links.ps1') -ExecutablePath $exePath

# Step 5: run the standalone Inno Setup script from the command line.
# Installer files, paths, architecture, shortcuts, and output naming remain
# entirely managed by build.iss.
if (-not (Test-Path -LiteralPath $IssPath -PathType Leaf)) {
    throw "Inno Setup script not found: $IssPath"
}

$isccCommand = Get-Command ISCC.exe -ErrorAction SilentlyContinue
$iscc = if ($isccCommand) {
    $isccCommand.Source
}
else {
    @(
        (Join-Path $env:ProgramFiles 'Inno Setup 7\ISCC.exe')
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 7\ISCC.exe')
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
}

if (-not $iscc) {
    throw 'ISCC.exe was not found. Install Inno Setup 6/7 or add its directory to PATH.'
}

& $iscc "/DMyAppVersion=$rawVersion" $IssPath

if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed with exit code $LASTEXITCODE."
}

Write-Output "Installer build completed from '$IssPath' (v$rawVersion)"
