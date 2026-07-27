# SPDX-License-Identifier: AGPL-3.0-only

<#
.SYNOPSIS
    Concatenates src/*.ps1 back into a single GStreamer-Glass.ps1 written
    to out/, in the order ps2exe needs: 00-Setup.ps1, then every domain
    module (numeric filename order), then 90-MainWindow.ps1 last.
#>

[CmdletBinding()]
param(
    [string]$SrcDir = (Join-Path $PSScriptRoot '..\src'),
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\out\GStreamer-Glass.ps1')
)

$ErrorActionPreference = 'Stop'

$outputDir = Split-Path $OutputPath -Parent
if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir | Out-Null }

function Read-Utf8 {
    param([string]$Path)
    $reader = New-Object System.IO.StreamReader($Path, [System.Text.Encoding]::UTF8, $true)
    try { return $reader.ReadToEnd() } finally { $reader.Close() }
}

$srcFull = (Resolve-Path $SrcDir).Path

$setupPath = Join-Path $srcFull '00-Setup.ps1'
$mainWindowPath = Join-Path $srcFull '90-MainWindow.ps1'

if (-not (Test-Path $setupPath)) { throw "Missing $setupPath -- run split-monolith.ps1 first." }
if (-not (Test-Path $mainWindowPath)) { throw "Missing $mainWindowPath -- run split-monolith.ps1 first." }

$domainModules = Get-ChildItem -Path $srcFull -Filter '*.ps1' |
    Where-Object { $_.Name -ne '00-Setup.ps1' -and $_.Name -ne '90-MainWindow.ps1' -and -not $_.Name.StartsWith('.') } |
    Sort-Object Name

Write-Output "Assembling: 00-Setup.ps1 + $($domainModules.Count) domain module(s) + 90-MainWindow.ps1"

$builder = New-Object System.Text.StringBuilder
[void]$builder.Append((Read-Utf8 $setupPath))

foreach ($m in $domainModules) {
    [void]$builder.Append("`n`n")
    [void]$builder.Append((Read-Utf8 $m.FullName))
}

[void]$builder.Append("`n`n")
[void]$builder.Append((Read-Utf8 $mainWindowPath))

$enc = New-Object System.Text.UTF8Encoding($true)
$resolvedOutputPath = (Resolve-Path -LiteralPath $outputDir).Path + '\' + (Split-Path $OutputPath -Leaf)
[System.IO.File]::WriteAllText($resolvedOutputPath, $builder.ToString(), $enc)

Write-Output "Wrote $resolvedOutputPath ($([math]::Round($builder.Length / 1KB, 1)) KB of text)"
