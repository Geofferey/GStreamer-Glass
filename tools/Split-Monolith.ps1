<#
.SYNOPSIS
    AST-based one-time/repeatable splitter: buckets every top-level function
    definition in GStreamer-Glass.ps1 into a feature module file per
    module-map.psd1, and writes all remaining top-level code (verbatim, in
    original relative order) into 00-Setup.ps1 / 90-MainWindow.ps1.

    Run tools/Build-Monolith.ps1 afterward to reassemble GStreamer-Glass.ps1.
#>

[CmdletBinding()]
param(
    [string]$SourcePath = (Join-Path $PSScriptRoot '..\modules\.original-backup.ps1'),
    [string]$ModulesDir = (Join-Path $PSScriptRoot '..\modules'),
    [string]$MapPath = (Join-Path $PSScriptRoot 'module-map.psd1')
)

$ErrorActionPreference = 'Stop'

function Write-Utf8Bom {
    param([string]$Path, [string]$Text)
    $enc = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

$sourceFull = (Resolve-Path $SourcePath).Path
$moduleMap = Import-PowerShellDataFile -Path $MapPath

# Invert the manifest: function name -> target module file. Fail fast on any
# function assigned to more than one module (a manifest authoring mistake).
$nameToModule = @{}
foreach ($moduleFile in $moduleMap.Keys) {
    foreach ($fn in $moduleMap[$moduleFile]) {
        if ($nameToModule.ContainsKey($fn)) {
            throw "Function '$fn' is assigned to multiple modules in the manifest (already mapped to '$($nameToModule[$fn])', also found in '$moduleFile')."
        }
        $nameToModule[$fn] = $moduleFile
    }
}

# Read without a leading BOM character in the returned string, but detect it existed.
$streamReader = New-Object System.IO.StreamReader($sourceFull, [System.Text.Encoding]::UTF8, $true)
$rawText = $streamReader.ReadToEnd()
$streamReader.Close()

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($rawText, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "Source file has $($parseErrors.Count) parse error(s); aborting split. First error: $($parseErrors[0])"
}

$funcAsts = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
$funcAsts = @($funcAsts | Sort-Object { $_.Extent.StartOffset })

Write-Output "Found $($funcAsts.Count) top-level function definitions."

# Slice the source into alternating Remainder/Function segments in original order.
$segments = New-Object System.Collections.Generic.List[object]
$cursor = 0
foreach ($f in $funcAsts) {
    $start = $f.Extent.StartOffset
    $end = $f.Extent.EndOffset
    if ($start -gt $cursor) {
        $segments.Add([pscustomobject]@{ Type = 'Remainder'; Text = $rawText.Substring($cursor, $start - $cursor) })
    }
    $segments.Add([pscustomobject]@{ Type = 'Function'; Name = $f.Name; Text = $rawText.Substring($start, $end - $start) })
    $cursor = $end
}
if ($cursor -lt $rawText.Length) {
    $segments.Add([pscustomobject]@{ Type = 'Remainder'; Text = $rawText.Substring($cursor) })
}

# Bucket functions into their module buffers; remainder before the first
# function becomes 00-Setup.ps1, remainder after that point becomes 90-MainWindow.ps1.
$moduleBuffers = @{}
foreach ($k in $moduleMap.Keys) { $moduleBuffers[$k] = New-Object System.Text.StringBuilder }

$setupBuilder = New-Object System.Text.StringBuilder
$mainWindowBuilder = New-Object System.Text.StringBuilder
$seenFirstFunction = $false
$missingMappings = New-Object System.Collections.Generic.List[string]
$extractedNames = New-Object System.Collections.Generic.List[string]

foreach ($seg in $segments) {
    if ($seg.Type -eq 'Remainder') {
        if (-not $seenFirstFunction) {
            [void]$setupBuilder.Append($seg.Text)
        }
        else {
            [void]$mainWindowBuilder.Append($seg.Text)
        }
    }
    else {
        $seenFirstFunction = $true
        $extractedNames.Add($seg.Name)
        $target = $nameToModule[$seg.Name]
        if (-not $target) {
            $missingMappings.Add($seg.Name)
            continue
        }
        [void]$moduleBuffers[$target].Append($seg.Text)
        [void]$moduleBuffers[$target].Append("`n`n")
    }
}

if ($missingMappings.Count -gt 0) {
    throw "The following $($missingMappings.Count) function(s) are not present in module-map.psd1 -- add them before re-running:`n$($missingMappings -join "`n")"
}

# Manifest entries that never matched a real function in the source (typo /
# stale entry) are just as dangerous as a missing one -- catch those too.
$astNameSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$extractedNames)
$staleMappings = $nameToModule.Keys | Where-Object { -not $astNameSet.Contains($_) }
if ($staleMappings.Count -gt 0) {
    throw "The following manifest entries do not correspond to any function found in the source (typo or stale entry):`n$($staleMappings -join "`n")"
}

if (-not (Test-Path $ModulesDir)) { New-Item -ItemType Directory -Path $ModulesDir | Out-Null }

Write-Utf8Bom -Path (Join-Path $ModulesDir '00-Setup.ps1') -Text $setupBuilder.ToString()

foreach ($moduleFile in ($moduleMap.Keys | Sort-Object)) {
    $header = "# Module: $moduleFile (auto-extracted by tools/Split-Monolith.ps1 -- edit here, then run tools/Build-Monolith.ps1)`n`n"
    Write-Utf8Bom -Path (Join-Path $ModulesDir $moduleFile) -Text ($header + $moduleBuffers[$moduleFile].ToString())
}

$mainWindowHeader = "# Module: 90-MainWindow.ps1 (auto-extracted by tools/Split-Monolith.ps1 -- UI construction, event wiring, Application.Run)`n`n"
Write-Utf8Bom -Path (Join-Path $ModulesDir '90-MainWindow.ps1') -Text ($mainWindowHeader + $mainWindowBuilder.ToString())

Write-Output "Split complete: $($extractedNames.Count) functions across $($moduleMap.Keys.Count) domain modules, plus 00-Setup.ps1 and 90-MainWindow.ps1."
