# SPDX-License-Identifier: AGPL-3.0-only

# Regression coverage for the independent video/audio queue-leak controls.
# GStreamer's queue "leaky" property is independent per element instance --
# nothing in GStreamer ties queues together. There used to be one shared
# "Queue leak" dropdown driving almost every live queue; it was removed as
# redundant once the Video and Audio tabs each got their own control. Each
# control's true default is nothing selected at all -- Get-EffectiveVideo/
# AudioQueueLeakValue return '' in that state, and New-LiveQueueString
# treats a blank -Leak as "omit the leaky= property entirely" (GStreamer's
# own queue default, which blocks) rather than substituting some other
# value. The only thing that keeps that blocking default from being what
# most users actually get is Apply-ThreadingProfile explicitly setting both
# combos as part of every non-Custom profile -- covered by inspecting that
# function's real source text below, since driving the whole WinForms
# profile-switch UI here isn't practical.
#
# Extracts and executes the REAL functions from src/16-CaptureAndAudioDevices.ps1
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

function Assert-QueueLeak {
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

# Get-ComboSelectedOrDefault (src/21-Recording.ps1) -- a dependency of
# Get-CoercedLiveQueueLeakValue.
Invoke-Expression (Get-FunctionSourceText -Path $recordingPath `
    -StartMarker 'function Get-ComboSelectedOrDefault {' `
    -EndMarker "`n}")

# The real resolution chain: Get-CoercedLiveQueueLeakValue,
# Get-EffectiveVideoQueueLeakValue, Get-EffectiveAudioQueueLeakValue -- one
# contiguous block in the real file.
Invoke-Expression (Get-FunctionSourceText -Path $devicesPath `
    -StartMarker 'function Get-CoercedLiveQueueLeakValue {' `
    -EndMarker 'function Get-EffectiveAudioQueueLeakValue {
    $selected = [string]$cmbAudioQueueLeakMode.SelectedItem
    if ([string]::IsNullOrWhiteSpace($selected)) { return '''' }
    $raw = switch ($selected) {
        ''Upstream - drop new'' { ''upstream'' }
        ''No leak - block'' { ''no'' }
        default { ''downstream'' }
    }
    return Get-CoercedLiveQueueLeakValue -RawValue $raw
}')

# The real New-LiveQueueString -- proves the "blank means omit the leaky=
# property, not substitute a value" mechanism end to end.
Invoke-Expression (Get-FunctionSourceText -Path $webRtcPipelinePath `
    -StartMarker 'function New-LiveQueueString {' `
    -EndMarker "`n}")

function New-TestComboBox {
    param([string[]]$Items, [int]$SelectedIndex = -1)
    $combo = New-Object System.Windows.Forms.ComboBox
    $null = $combo.Items.AddRange($Items)
    $combo.SelectedIndex = $SelectedIndex
    return $combo
}

$script:DefaultThreadingProfile = 'Live strict'
$leakItems = @('Downstream - drop old', 'Upstream - drop new', 'No leak - block')

$cmbThreadingProfile = New-TestComboBox -Items @('Live strict', 'Balanced', 'Non-blocking brutal', 'Blocking diagnostic', 'Custom') -SelectedIndex 0
$cmbVideoQueueLeakMode = New-TestComboBox -Items $leakItems
$cmbAudioQueueLeakMode = New-TestComboBox -Items $leakItems

# --- 1. True default (nothing selected) resolves to '' -- omit, not a
#         substituted value -- for both video and audio, independent of
#         whatever the threading profile combo says. ---
foreach ($profileSelection in @('Live strict', 'Blocking diagnostic')) {
    $cmbThreadingProfile.SelectedItem = $profileSelection
    Assert-QueueLeak ((Get-EffectiveVideoQueueLeakValue) -eq '') "Video with nothing selected should resolve to '' (omit), got '$(Get-EffectiveVideoQueueLeakValue)' under profile '$profileSelection'."
    Assert-QueueLeak ((Get-EffectiveAudioQueueLeakValue) -eq '') "Audio with nothing selected should resolve to '' (omit), got '$(Get-EffectiveAudioQueueLeakValue)' under profile '$profileSelection'."
}
$cmbThreadingProfile.SelectedItem = 'Live strict'
Write-Output "Nothing-selected resolves to '' (omit) for both video and audio, regardless of threading profile."

# --- 2. New-LiveQueueString actually omits the leaky= property for a blank
#         Leak, and includes it for an explicit one. ---
$omittedQueue = New-LiveQueueString -Buffers 2 -MaxTimeMs 0 -Leak (Get-EffectiveVideoQueueLeakValue)
Assert-QueueLeak ($omittedQueue -notmatch 'leaky=') "A blank effective leak value should produce a queue string with no leaky= property at all, got: $omittedQueue"
Assert-QueueLeak ($omittedQueue -match '^queue max-size-buffers=2') "The omitted-leak queue string lost its other properties: $omittedQueue"
$explicitQueue = New-LiveQueueString -Buffers 2 -MaxTimeMs 0 -Leak 'downstream'
Assert-QueueLeak ($explicitQueue -match 'leaky=downstream$') "An explicit leak value should still produce leaky=<value>, got: $explicitQueue"
Write-Output "New-LiveQueueString omits leaky= entirely for a blank value and includes it for an explicit one."

# --- 3. Explicit video/audio overrides resolve independently of each
#         other. ---
$cmbVideoQueueLeakMode.SelectedItem = 'Upstream - drop new'
$cmbAudioQueueLeakMode.SelectedItem = 'No leak - block'
$cmbThreadingProfile.SelectedItem = 'Live strict'
Assert-QueueLeak ((Get-EffectiveVideoQueueLeakValue) -eq 'upstream') "Video override did not resolve to its own explicit value (got '$(Get-EffectiveVideoQueueLeakValue)')."
# Audio explicitly asked for 'No leak - block' outside the Blocking diagnostic
# profile -- must be coerced to downstream, the same safety rule the old
# global setting used to apply.
Assert-QueueLeak ((Get-EffectiveAudioQueueLeakValue) -eq 'downstream') "Audio override 'No leak - block' was not coerced to downstream outside Blocking diagnostic profile (got '$(Get-EffectiveAudioQueueLeakValue)')."
Write-Output "Video and audio overrides resolve independently of each other."

# --- 4. In the Blocking diagnostic profile, an explicit 'No leak - block'
#         override is honored (not coerced). ---
$cmbThreadingProfile.SelectedItem = 'Blocking diagnostic'
Assert-QueueLeak ((Get-EffectiveAudioQueueLeakValue) -eq 'no') "Audio override 'No leak - block' should be honored (not coerced) inside the Blocking diagnostic profile (got '$(Get-EffectiveAudioQueueLeakValue)')."
$cmbThreadingProfile.SelectedItem = 'Live strict'
Write-Output "The 'no'-outside-Blocking-diagnostic coercion still applies to explicit video/audio overrides."

# --- 5. Apply-ThreadingProfile's real source sets BOTH new combos for
#         every non-Custom profile, and never references the removed
#         global $cmbQueueLeakMode -- the actual safety net that keeps
#         "nothing selected" from being what most users experience. ---
# Apply-ThreadBudget (a different function in this same file) also has its
# own 'Balanced'-named case block -- scope the search to just
# Apply-ThreadingProfile's own body so that unrelated block can't produce a
# false match.
$applyThreadingProfileSource = Get-FunctionSourceText -Path $threadingPath `
    -StartMarker 'function Apply-ThreadingProfile {' `
    -EndMarker "Update-CommandPreview`n}"
Assert-QueueLeak ($applyThreadingProfileSource -notmatch 'cmbQueueLeakMode') "Apply-ThreadingProfile still references the removed global `$cmbQueueLeakMode combo."
foreach ($presetName in @('Live strict', 'Balanced', 'Non-blocking brutal', 'Blocking diagnostic')) {
    $presetBlockPattern = "'$presetName' \{[^}]*\}"
    $presetMatch = [regex]::Match($applyThreadingProfileSource, $presetBlockPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    Assert-QueueLeak $presetMatch.Success "Could not find the '$presetName' block in Apply-ThreadingProfile -- this test needs updating."
    Assert-QueueLeak ($presetMatch.Value -match '\$cmbVideoQueueLeakMode\.SelectedItem\s*=') "Threading profile '$presetName' does not set `$cmbVideoQueueLeakMode."
    Assert-QueueLeak ($presetMatch.Value -match '\$cmbAudioQueueLeakMode\.SelectedItem\s*=') "Threading profile '$presetName' does not set `$cmbAudioQueueLeakMode."
}
Write-Output "Every threading profile sets both new per-stream combos directly; no reference to the removed global combo remains."

Write-Output ""
Write-Output "Queue leak mode checks passed."
