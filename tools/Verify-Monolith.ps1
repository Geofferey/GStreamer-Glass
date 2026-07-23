<#
.SYNOPSIS
    Parses the rebuilt GStreamer-Glass.ps1 with the PowerShell AST parser
    (must be zero syntax errors) and diffs its top-level function name set
    against a baseline (the pre-split original) -- must be an exact match.
#>

[CmdletBinding()]
param(
    [string]$RebuiltPath = (Join-Path $PSScriptRoot '..\out\GStreamer-Glass.ps1'),
    [string]$BaselinePath = (Join-Path $PSScriptRoot '..\modules\.original-backup.ps1')
)

$ErrorActionPreference = 'Stop'

function Get-TopLevelFunctionNames {
    param([string]$Path)
    $reader = New-Object System.IO.StreamReader($Path, [System.Text.Encoding]::UTF8, $true)
    try { $text = $reader.ReadToEnd() } finally { $reader.Close() }
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$parseErrors)
    [pscustomobject]@{
        ParseErrors = $parseErrors
        Names       = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false) | ForEach-Object { $_.Name })
    }
}

$rebuiltFull = (Resolve-Path $RebuiltPath).Path
$baselineFull = (Resolve-Path $BaselinePath).Path

$ok = $true

$rebuilt = Get-TopLevelFunctionNames -Path $rebuiltFull
if ($rebuilt.ParseErrors.Count -gt 0) {
    $ok = $false
    Write-Output "FAIL: rebuilt file has $($rebuilt.ParseErrors.Count) parse error(s):"
    $rebuilt.ParseErrors | ForEach-Object { Write-Output "  - $_" }
}
else {
    Write-Output "PASS: rebuilt file parses with 0 errors."
}

$baseline = Get-TopLevelFunctionNames -Path $baselineFull

$rebuiltSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$rebuilt.Names)
$baselineSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$baseline.Names)

$missing = $baseline.Names | Where-Object { -not $rebuiltSet.Contains($_) } | Sort-Object -Unique
$extra = $rebuilt.Names | Where-Object { -not $baselineSet.Contains($_) } | Sort-Object -Unique

$rebuiltDupes = $rebuilt.Names | Group-Object | Where-Object Count -gt 1

if ($missing.Count -gt 0) {
    $ok = $false
    Write-Output "FAIL: $($missing.Count) function(s) present in baseline but missing from rebuilt file:"
    $missing | ForEach-Object { Write-Output "  - $_" }
}
if ($extra.Count -gt 0) {
    $ok = $false
    Write-Output "FAIL: $($extra.Count) function(s) present in rebuilt file but not in baseline:"
    $extra | ForEach-Object { Write-Output "  - $_" }
}
if ($rebuiltDupes.Count -gt 0) {
    $ok = $false
    Write-Output "FAIL: $($rebuiltDupes.Count) function name(s) defined more than once in rebuilt file:"
    $rebuiltDupes | ForEach-Object { Write-Output "  - $($_.Name) x$($_.Count)" }
}

if ($missing.Count -eq 0 -and $extra.Count -eq 0 -and $rebuiltDupes.Count -eq 0) {
    Write-Output "PASS: function set matches baseline exactly ($($baseline.Names.Count) functions, no duplicates)."
}

Write-Output ("Baseline size: {0} KB / Rebuilt size: {1} KB" -f `
    [math]::Round((Get-Item $baselineFull).Length / 1KB, 1), `
    [math]::Round((Get-Item $rebuiltFull).Length / 1KB, 1))

if (-not $ok) {
    Write-Output "VERIFICATION FAILED"
    exit 1
}
Write-Output "VERIFICATION PASSED"
