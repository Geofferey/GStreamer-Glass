# SPDX-License-Identifier: AGPL-3.0-only

# Regression coverage for a class of PowerShell bug that ordinary
# parse-checking (Parser::ParseFile, used throughout this repo's build/test
# scripts) never catches: code that is syntactically VALID -- the file
# parses cleanly, ParseFile finds nothing wrong -- but throws the moment it
# actually EXECUTES, unconditionally, regardless of any runtime data.
#
# The concrete case this was written for: the controlled-live-worker's RTP
# port handling used [uint32](if ($start.MinRtpPort) { ... } else { ... }) --
# an if-statement wrapped in bare parens with a type-cast prefix. PowerShell
# only allows a statement keyword (if/switch/try/for/foreach/while) to
# produce a value when it is either the direct right-hand side of an
# assignment (no wrapping parens: $x = if (...) {...} else {...}) or wrapped
# in the subexpression operator ($(...)). A bare "(if ...)" instead makes
# the parser treat "if" as an attempted command invocation, failing with
# "The term 'if' is not recognized as the name of a cmdlet..." every single
# time that line ran -- not conditionally, not only for certain input, every
# time. It parsed fine and shipped fine; it only ever failed at the one
# moment it actually mattered (going live with the controlled worker), which
# is exactly why it went unnoticed for as long as it did and took real
# runtime reproduction (not code reading) to actually pin down.
#
# Two layers here, matching the two ways this class of bug gets caught:
#   1. A static source scan for the dangerous shape itself, across every
#      src/*.ps1 file -- catches this exact anti-pattern anywhere in the
#      codebase, present or future, without needing to know which specific
#      feature it's hiding in.
#   2. A behavioral regression test that extracts and actually EXECUTES the
#      real, current controlled-live-worker RTP port computation (not a
#      hand-maintained copy of it, the literal source text) against
#      representative inputs -- locks in the actual fix, and would fail if
#      this specific logic ever regresses again in some new way.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$srcDir = Join-Path $repoRoot 'src'

function Assert-Hazard {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

# --- 1. Static scan -----------------------------------------------------
# A bare "(" immediately followed by a statement keyword is invalid as a
# value-producing expression regardless of what (if anything) precedes it --
# the type-cast in the real bug wasn't the root problem, the bare parens
# were. Comments are excluded (best-effort: text from the first unquoted-ish
# "#" onward is stripped before matching) so documentation discussing this
# exact pattern -- like this file, and the fix's own explanatory comment --
# doesn't trip its own detector.
$hazardPattern = '\((?:if|switch|try|for|foreach|while)\s*\('
$offenders = @()
$sourceFiles = Get-ChildItem -Path $srcDir -Filter '*.ps1' -File
foreach ($file in $sourceFiles) {
    $lines = Get-Content -LiteralPath $file.FullName
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $hashIndex = $line.IndexOf('#')
        $codePart = if ($hashIndex -ge 0) { $line.Substring(0, $hashIndex) } else { $line }
        $matchesOnLine = [regex]::Matches($codePart, $hazardPattern)
        foreach ($m in $matchesOnLine) {
            # The one safe form: "$(if (...) ...)" -- the subexpression
            # operator, not a bare grouping paren. Skip it specifically.
            $precedingChar = if ($m.Index -gt 0) { $codePart[$m.Index - 1] } else { $null }
            if ($precedingChar -eq '$') { continue }
            $offenders += "$($file.Name):$($i + 1): $($line.Trim())"
        }
    }
}
Assert-Hazard ($offenders.Count -eq 0) (
    "Found statement-as-bare-parenthesized-expression hazard(s) -- these parse " +
    "cleanly but throw `"The term '<keyword>' is not recognized...`" the moment " +
    "they actually execute, unconditionally:`n" + ($offenders -join "`n") +
    "`n`nFix: drop the wrapping parens (`$x = if (...) {...} else {...}`) or use `$(...)` instead of bare `(...)`."
)
Write-Output "Static scan: no bare-parenthesized statement-keyword hazards found across $($sourceFiles.Count) source files."

# --- 2. Behavioral regression -------------------------------------------
# Extracts the real, current computation from 00-Setup.ps1 (not a
# hand-copy) and actually executes it, so this fails if the logic
# regresses in some NEW way too, not just if this exact anti-pattern comes
# back.
$setupPath = Join-Path $srcDir '00-Setup.ps1'
$setupSource = Get-Content -Raw -LiteralPath $setupPath
$snippetStart = '$workerMinRtpPort = if ($start.MinRtpPort)'
$snippetStartIndex = $setupSource.IndexOf($snippetStart)
if ($snippetStartIndex -lt 0) {
    throw "Could not locate the controlled-live-worker RTP port computation in $setupPath (looked for the line starting `"$snippetStart`") -- this test needs updating to match wherever that logic now lives."
}
$snippetEndMarker = '[GstControlledScenePreview]::StartLive('
$snippetEndIndex = $setupSource.IndexOf($snippetEndMarker, $snippetStartIndex)
if ($snippetEndIndex -lt 0) {
    throw 'Could not find the end of the RTP port computation snippet (the StartLive call that follows it) -- this test needs updating.'
}
$computationSnippet = $setupSource.Substring($snippetStartIndex, $snippetEndIndex - $snippetStartIndex)

function Get-ControlledWorkerRtpPortsFromRealSource {
    param($start, [string]$Snippet)
    # $start is consumed by the extracted snippet itself (it references
    # $start.MinRtpPort/$start.MaxRtpPort directly) -- Invoke-Expression
    # runs the ACTUAL source text in this function's scope so
    # $workerMinRtpPort/$workerMaxRtpPort end up defined here afterward.
    Invoke-Expression $Snippet
    return @{ Min = $workerMinRtpPort; Max = $workerMaxRtpPort }
}

$zeroCase = Get-ControlledWorkerRtpPortsFromRealSource -Snippet $computationSnippet -start ([pscustomobject]@{ MinRtpPort = 0; MaxRtpPort = 0 })
Assert-Hazard ($zeroCase.Min -eq [uint32]0 -and $zeroCase.Max -eq [uint32]0) "Zero MinRtpPort/MaxRtpPort did not compute to 0/0 (got Min=$($zeroCase.Min) Max=$($zeroCase.Max))."

$nonzeroCase = Get-ControlledWorkerRtpPortsFromRealSource -Snippet $computationSnippet -start ([pscustomobject]@{ MinRtpPort = 5000; MaxRtpPort = 5100 })
Assert-Hazard ($nonzeroCase.Min -eq [uint32]5000 -and $nonzeroCase.Max -eq [uint32]5100) "Nonzero MinRtpPort/MaxRtpPort did not round-trip correctly (got Min=$($nonzeroCase.Min) Max=$($nonzeroCase.Max))."

# Also against a real ConvertFrom-Json payload, matching exactly what the
# worker receives over its named pipe -- catches a future regression where
# the JSON round-trip itself (e.g. numeric vs string typing from
# ConvertFrom-Json) breaks this computation in a way the plain
# pscustomobject cases above wouldn't reveal.
$jsonStart = [pscustomobject]@{ Type = 'Start'; MinRtpPort = 7000; MaxRtpPort = 7100 } | ConvertTo-Json -Compress | ConvertFrom-Json
$jsonCase = Get-ControlledWorkerRtpPortsFromRealSource -Snippet $computationSnippet -start $jsonStart
Assert-Hazard ($jsonCase.Min -eq [uint32]7000 -and $jsonCase.Max -eq [uint32]7100) "RTP port computation from a real JSON round-trip did not match (got Min=$($jsonCase.Min) Max=$($jsonCase.Max))."

Write-Output "Behavioral regression: controlled-live-worker RTP port computation passed for zero, nonzero, and JSON-sourced inputs (executed from the real, current source text)."
Write-Output ""
Write-Output "PowerShell runtime hazard checks passed."
