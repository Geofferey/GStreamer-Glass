# SPDX-License-Identifier: AGPL-3.0-only

# Regression coverage for two related fixes to the Video/Recording tabs'
# encoder GOP and RTP config-interval handling:
#
# 1. GOP is now a literal value, not fps * value. Get-EncoderElementChain
#    and Get-RecordingEncoderElementChain used to compute
#    `$gopSize = [Math]::Max(1, $fps * [int]$numGopSeconds.Value)` before
#    handing it to whichever encoder property consumes it (gop-size,
#    key-int-max, keyframe-max-dist -- all genuinely frame-count
#    properties; none take seconds). Per explicit correction from the
#    operator: "1 should not = 60 ... if we want a GOP of 60 we put 60" --
#    whatever's typed is now written into the pipeline as-is, with no
#    fps-based conversion. The field name/label stayed the same ('GOP
#    size'); only the formula and label text changed.
#
# 2. config-interval (SPS/PPS/VPS repeat interval, H.264/H.265 only) is now
#    a real control ($numConfigInterval) instead of hardcoded -1, wired
#    into the general streaming encoder chain (Get-EncoderElementChain) and
#    the unified A/V publisher's RTP payloader/receiver definitions
#    (Get-DirectWebRtcUnifiedRtpVideoDefinition). Deliberately NOT wired
#    into Get-RecordingEncoderElementChain's hardcoded -1 (recording has no
#    RTP/late-joiner concept) or the separate
#    chkDirectWebRtcInternalRepeatHeaders boolean flag (a different
#    mechanism entirely, serialized to the unified publisher's internal
#    Rust-side webrtcsink, not a PowerShell pipeline string).
#
# Get-EncoderElementChain and Get-RecordingEncoderElementChain have a large
# dependency surface (capture/encoder selection, bitrate, tune, preset,
# custom options, Add-EncoderFamilyOptions, ...), so rather than stand up
# that whole harness, this test verifies their REAL source text directly --
# matching this repo's established fallback for functions too large to
# practically drive end to end (see the Apply-ThreadingProfile /
# Apply-DirectWebRtcSmoothnessProfile preset checks in
# test-queue-buffer-counts.ps1). Get-DirectWebRtcUnifiedRtpVideoDefinition
# is small enough to execute for real and is exercised directly.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$encodingPath = Join-Path $repoRoot 'src\22-Encoding.ps1'
$recordingPath = Join-Path $repoRoot 'src\21-Recording.ps1'
$webRtcPipelinePath = Join-Path $repoRoot 'src\17-DirectWebRtcPipeline.ps1'

function Assert-GopConfigInterval {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-FunctionSourceText {
    param([string]$Path, [string]$StartMarker, [string]$EndMarker)
    $source = Get-Content -Raw -LiteralPath $Path
    $startIndex = $source.IndexOf($StartMarker)
    if ($startIndex -lt 0) { throw "Could not find `"$StartMarker`" in $Path -- this test needs updating to match wherever that logic now lives." }
    $endIndex = $source.IndexOf($EndMarker, $startIndex)
    if ($endIndex -lt 0) { throw "Could not find the end marker `"$EndMarker`" after `"$StartMarker`" in $Path -- this test needs updating." }
    $endIndex += $EndMarker.Length
    return $source.Substring($startIndex, $endIndex - $startIndex)
}

# --- 1. Get-EncoderElementChain (general streaming path, all protocols):
#         gop-size is the literal field value, not fps * value; and
#         config-interval reads the new control, not a hardcoded -1. ---
$encoderChainSource = Get-FunctionSourceText -Path $encodingPath `
    -StartMarker 'function Get-EncoderElementChain {' `
    -EndMarker "return (`$parts -join ' ')`n}"

Assert-GopConfigInterval ($encoderChainSource.Contains('$gopSize = [Math]::Max(1, [int]$numGopSeconds.Value)')) `
    "Get-EncoderElementChain should compute gopSize as the literal numGopSeconds value, no fps multiplication. Source: $encoderChainSource"
Assert-GopConfigInterval ($encoderChainSource -notmatch '\$fps\s*\*\s*\[int\]\$numGopSeconds') `
    "Get-EncoderElementChain still multiplies numGopSeconds by fps -- the old derived-seconds behavior has come back."
Assert-GopConfigInterval ($encoderChainSource.Contains('config-interval=$([int]$numConfigInterval.Value)')) `
    "Get-EncoderElementChain should emit config-interval from numConfigInterval.Value, not a hardcoded literal. Source: $encoderChainSource"
Assert-GopConfigInterval (-not $encoderChainSource.Contains("'config-interval=-1'")) `
    "Get-EncoderElementChain still hardcodes config-interval=-1 as a literal string."
Write-Output "Get-EncoderElementChain: GOP is literal (no fps multiply) and config-interval reads the new control."

# --- 2. Get-RecordingEncoderElementChain: GOP is also literal (same
#         GStreamer property, same fix); config-interval stays hardcoded
#         -1 there on purpose (no RTP/late-joiner concept for local files,
#         and the operator asked for the Video/streaming tab specifically). ---
$recordingChainSource = Get-FunctionSourceText -Path $recordingPath `
    -StartMarker 'function Get-RecordingEncoderElementChain {' `
    -EndMarker "return (`$parts -join ' ')`n}"

Assert-GopConfigInterval ($recordingChainSource.Contains('$gopSize = [Math]::Max(1, [int]$numRecordingGopSeconds.Value)')) `
    "Get-RecordingEncoderElementChain should compute gopSize as the literal numRecordingGopSeconds value, no fps multiplication. Source: $recordingChainSource"
Assert-GopConfigInterval ($recordingChainSource -notmatch '\$fps\s*\*\s*\[int\]\$numRecordingGopSeconds') `
    "Get-RecordingEncoderElementChain still multiplies numRecordingGopSeconds by fps -- the old derived-seconds behavior has come back."
Assert-GopConfigInterval ($recordingChainSource.Contains("'config-interval=-1'")) `
    "Get-RecordingEncoderElementChain's config-interval should still be the hardcoded -1 -- recording is deliberately out of scope for the new control; if this changed on purpose, update this test."
Write-Output "Get-RecordingEncoderElementChain: GOP is literal (no fps multiply); config-interval intentionally left hardcoded."

# --- 3. Get-DirectWebRtcUnifiedRtpVideoDefinition (unified A/V publisher
#         payloader/receiver definitions): executed for real. Both H264 and
#         H265 branches' Payloader and Receiver strings must reflect
#         numConfigInterval.Value, not a hardcoded -1, for any value
#         (including 0 and positive N, not just -1). ---
Invoke-Expression (Get-FunctionSourceText -Path $webRtcPipelinePath `
    -StartMarker 'function Get-DirectWebRtcUnifiedRtpVideoDefinition {' `
    -EndMarker "`n}")

# Test scaffolding: Get-DirectWebRtcUnifiedRtpVideoDefinition's only real
# dependency besides numConfigInterval is Get-SelectedEncoderDefinition,
# which itself reads a large $script:EncoderCatalog table set up in
# 00-Setup.ps1. Standing that up is unrelated to what this test verifies
# (config-interval wiring), so it's stubbed directly rather than extracted.
function Get-SelectedEncoderDefinition {
    return [pscustomobject]@{ Codec = $script:TestCodec }
}

foreach ($testValue in @(-1, 0, 5)) {
    $numConfigInterval = [pscustomobject]@{ Value = $testValue }
    foreach ($codec in @('H264', 'H265')) {
        $script:TestCodec = $codec
        $definition = Get-DirectWebRtcUnifiedRtpVideoDefinition
        Assert-GopConfigInterval ($definition.Payloader -match "config-interval=$testValue\b") `
            "$codec payloader should emit config-interval=$testValue, got: $($definition.Payloader)"
        Assert-GopConfigInterval ($definition.Receiver -match "config-interval=$testValue\b") `
            "$codec receiver should emit config-interval=$testValue, got: $($definition.Receiver)"
    }
}
Write-Output "Get-DirectWebRtcUnifiedRtpVideoDefinition: H264/H265 payloader and receiver both reflect numConfigInterval.Value for -1, 0, and a positive value."

Write-Output ""
Write-Output "GOP / config-interval checks passed."
