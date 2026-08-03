# SPDX-License-Identifier: AGPL-3.0-only

# Regression coverage for independent output-queue buffer counts (audio
# final queue, video sender/pacing queue). Both used to hardcode their
# buffer count instead of exposing it: the audio output queue silently
# doubled whatever the input queue's buffer field said
# (Get-AudioFinalQueue: $numAudioQueueBuffers.Value * 2), and the video
# sender queue picked a bare literal (2 or 4) based on sender queue mode
# name inside Get-DirectWebRtcPacingQueue, with no UI control at all. Both
# are now independent NumericUpDown fields ($numAudioOutputQueueBuffers,
# $numDirectWebRtcSenderQueueBuffers), matching the "Honest Controls"
# transparency the four independent leaky= controls already established
# for these same four queues (see test-queue-leak-mode.ps1).
#
# Apply-ThreadingProfile and Apply-DirectWebRtcSmoothnessProfile still set
# the new fields per preset so every named profile's effective pipeline is
# unchanged from before this change -- only 'Custom' lets them diverge.
#
# Extracts and executes the REAL functions from src/18-ThreadingAndDebug.ps1
# and src/17-DirectWebRtcPipeline.ps1 (not hand-copies), matching this
# repo's established convention.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$devicesPath = Join-Path $repoRoot 'src\16-CaptureAndAudioDevices.ps1'
$recordingPath = Join-Path $repoRoot 'src\21-Recording.ps1'
$webRtcPipelinePath = Join-Path $repoRoot 'src\17-DirectWebRtcPipeline.ps1'
$threadingPath = Join-Path $repoRoot 'src\18-ThreadingAndDebug.ps1'

function Assert-QueueBufferCount {
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

# Get-ComboSelectedOrDefault (src/21-Recording.ps1) -- a dependency of the
# leak resolvers and of Get-DirectWebRtcPacingQueue's mode lookup.
Invoke-Expression (Get-FunctionSourceText -Path $recordingPath `
    -StartMarker 'function Get-ComboSelectedOrDefault {' `
    -EndMarker "`n}")

# The real leak-resolution chain -- Get-AudioInputQueue/Get-AudioFinalQueue/
# Get-DirectWebRtcPacingQueue all call into it for their -Leak argument;
# not the focus of this test, but required for these functions to run.
Invoke-Expression (Get-FunctionSourceText -Path $devicesPath `
    -StartMarker 'function Get-CoercedLiveQueueLeakValue {' `
    -EndMarker "function Get-EffectiveAudioOutputQueueLeakValue { return Get-EffectiveQueueLeakValue -Combo `$cmbAudioOutputQueueLeakMode }")

# The real New-LiveQueueString -- needed to see the actual max-size-buffers=
# text each function under test produces.
Invoke-Expression (Get-FunctionSourceText -Path $webRtcPipelinePath `
    -StartMarker 'function New-LiveQueueString {' `
    -EndMarker "`n}")

# Get-EffectiveAudioQueueCapMs -- a dependency of Get-AudioInputQueue/
# Get-AudioFinalQueue for their -MaxTimeMs argument.
Invoke-Expression (Get-FunctionSourceText -Path $threadingPath `
    -StartMarker 'function Get-EffectiveAudioQueueCapMs {' `
    -EndMarker "`n}")

# The real functions under test.
Invoke-Expression (Get-FunctionSourceText -Path $threadingPath `
    -StartMarker 'function Get-AudioInputQueue {' `
    -EndMarker "`n}")
Invoke-Expression (Get-FunctionSourceText -Path $threadingPath `
    -StartMarker 'function Get-AudioFinalQueue {' `
    -EndMarker "`n}")
Invoke-Expression (Get-FunctionSourceText -Path $webRtcPipelinePath `
    -StartMarker 'function Get-DirectWebRtcPacingQueue {' `
    -EndMarker "`n}")

function New-TestComboBox {
    param([string[]]$Items, [string]$Selected)
    $combo = New-Object System.Windows.Forms.ComboBox
    $null = $combo.Items.AddRange($Items)
    $combo.SelectedItem = $Selected
    return $combo
}

function New-TestNumericUpDown {
    param([int]$Minimum = 0, [int]$Maximum = 999, [decimal]$Value)
    $numeric = New-Object System.Windows.Forms.NumericUpDown
    $numeric.Minimum = $Minimum
    $numeric.Maximum = $Maximum
    $numeric.Value = $Value
    return $numeric
}

$script:DefaultThreadingProfile = 'Live strict'
$script:DefaultWebRtcSenderQueueMode = 'Leaky live'
$leakItems = @('Default', 'Downstream - drop old', 'Upstream - drop new', 'No leak - block')

$cmbThreadingProfile = New-TestComboBox -Items @('Live strict', 'Balanced', 'Non-blocking brutal', 'Blocking diagnostic', 'Custom') -Selected 'Live strict'
$cmbVideoOutputQueueLeakMode = New-TestComboBox -Items $leakItems -Selected 'Default'
$cmbAudioInputQueueLeakMode = New-TestComboBox -Items $leakItems -Selected 'Default'
$cmbAudioOutputQueueLeakMode = New-TestComboBox -Items $leakItems -Selected 'Default'

$numAudioQueueCapMs = New-TestNumericUpDown -Maximum 500 -Value 0
$numAudioQueueBuffers = New-TestNumericUpDown -Minimum 1 -Maximum 32 -Value 5
$numAudioOutputQueueBuffers = New-TestNumericUpDown -Minimum 1 -Maximum 64 -Value 13

$cmbWebRtcSenderQueueMode = New-TestComboBox -Items @('Leaky live', 'Small cushion', 'Non-leaky experimental') -Selected 'Leaky live'
$numDirectWebRtcPacingMs = New-TestNumericUpDown -Maximum 500 -Value 0
$numDirectWebRtcSenderQueueBuffers = New-TestNumericUpDown -Minimum 1 -Maximum 32 -Value 9

# --- 1. The audio output queue's buffer count comes from its own field,
#         not double the input field -- the exact coupling this change
#         removes. 13 != 5 * 2 (10), so this also proves it isn't
#         accidentally still reading the input field under another name. ---
$inputQueue = Get-AudioInputQueue
Assert-QueueBufferCount ($inputQueue -match 'max-size-buffers=5\b') "Audio input queue should use numAudioQueueBuffers (5), got: $inputQueue"
$finalQueue = Get-AudioFinalQueue
Assert-QueueBufferCount ($finalQueue -match 'max-size-buffers=13\b') "Audio final queue should use numAudioOutputQueueBuffers (13), not double the input value, got: $finalQueue"
Write-Output "Audio final queue's buffer count is independent of the input queue's -- no more hardcoded doubling."

# --- 2. Get-AudioInputQueue's -Multiplier param (used by the audiomixer
#         chain shapes in src/19-AudioChains.ps1) still scales the INPUT
#         queue correctly -- confirms this change didn't disturb it. ---
$multipliedInputQueue = Get-AudioInputQueue -Multiplier 2
Assert-QueueBufferCount ($multipliedInputQueue -match 'max-size-buffers=10\b') "Get-AudioInputQueue -Multiplier 2 should still emit 5*2=10, got: $multipliedInputQueue"
Write-Output "Get-AudioInputQueue -Multiplier still scales the input queue independently of the final queue's own field."

# --- 3. The video sender queue's buffer count comes from its own field
#         regardless of sender queue mode -- previously a bare literal (2
#         for Leaky live, 4 otherwise) baked into the mode switch. ---
foreach ($mode in @('Leaky live', 'Small cushion', 'Non-leaky experimental')) {
    $cmbWebRtcSenderQueueMode.SelectedItem = $mode
    $pacingQueue = Get-DirectWebRtcPacingQueue
    Assert-QueueBufferCount ($pacingQueue -match 'max-size-buffers=9\b') "Sender queue mode '$mode' should use numDirectWebRtcSenderQueueBuffers (9) regardless of mode, got: $pacingQueue"
}
Write-Output "Video sender/pacing queue's buffer count is independent of sender queue mode across all three modes."

# --- 4. Apply-ThreadingProfile's real source sets numAudioOutputQueueBuffers
#         for every non-Custom preset, so named profiles stay fully
#         specified rather than silently inheriting whatever was last set. ---
$applyThreadingProfileSource = Get-FunctionSourceText -Path $threadingPath `
    -StartMarker 'function Apply-ThreadingProfile {' `
    -EndMarker "Update-CommandPreview`n}"
foreach ($presetName in @('Live strict', 'Balanced', 'Non-blocking brutal', 'Blocking diagnostic')) {
    $presetBlockPattern = "'$presetName' \{[^}]*\}"
    $presetMatch = [regex]::Match($applyThreadingProfileSource, $presetBlockPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    Assert-QueueBufferCount $presetMatch.Success "Could not find the '$presetName' block in Apply-ThreadingProfile -- this test needs updating."
    Assert-QueueBufferCount ($presetMatch.Value -match '\$numAudioOutputQueueBuffers\.Value\s*=') "Threading profile '$presetName' does not set `$numAudioOutputQueueBuffers."
}
Write-Output "Every threading profile sets `$numAudioOutputQueueBuffers directly."

# --- 5. Apply-DirectWebRtcSmoothnessProfile's real source sets
#         numDirectWebRtcSenderQueueBuffers for every non-Custom preset. ---
$applySmoothnessProfileSource = Get-FunctionSourceText -Path $webRtcPipelinePath `
    -StartMarker 'function Apply-DirectWebRtcSmoothnessProfile {' `
    -EndMarker "`$script:ApplyingDirectWebRtcSmoothnessProfile = `$false`n    }`n}"
foreach ($presetName in @('Sane defaults', 'Lowest latency', 'Balanced smooth', 'WAN smooth', 'Adaptive viewer')) {
    $presetBlockPattern = "'$presetName' \{[^}]*\}"
    $presetMatch = [regex]::Match($applySmoothnessProfileSource, $presetBlockPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    Assert-QueueBufferCount $presetMatch.Success "Could not find the '$presetName' block in Apply-DirectWebRtcSmoothnessProfile -- this test needs updating."
    Assert-QueueBufferCount ($presetMatch.Value -match '\$numDirectWebRtcSenderQueueBuffers\.Value\s*=') "Smoothness profile '$presetName' does not set `$numDirectWebRtcSenderQueueBuffers."
}
Write-Output "Every smoothness profile sets `$numDirectWebRtcSenderQueueBuffers directly."

Write-Output ""
Write-Output "Queue buffer count checks passed."
