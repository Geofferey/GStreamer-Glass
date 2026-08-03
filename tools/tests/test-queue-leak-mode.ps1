# SPDX-License-Identifier: AGPL-3.0-only

# Regression coverage for the four independent per-queue leak controls
# (video input/output, audio input/output). GStreamer's queue "leaky"
# property is independent per element instance -- nothing in GStreamer
# ties queues together, and this app is a transparent pipeline
# constructor, so each of the four live queues gets its own control rather
# than being bundled under a shared per-stream or global setting (both
# existed at earlier points in this app's history; removed as redundant
# once every queue had its own home).
#
# 'Default' is an explicit, visible combo item -- not just nothing
# selected -- meaning omit the leaky= property entirely and let
# GStreamer's own queue default (which blocks) apply. New-LiveQueueString
# treats a blank -Leak the same way. The only thing that keeps that
# blocking default from being what most users actually get is
# Apply-ThreadingProfile explicitly setting all four combos as part of
# every non-Custom profile -- covered by inspecting that function's real
# source text below, since driving the whole WinForms profile-switch UI
# here isn't practical.
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
# Get-EffectiveQueueLeakValue, and its four named wrappers -- one
# contiguous block in the real file.
Invoke-Expression (Get-FunctionSourceText -Path $devicesPath `
    -StartMarker 'function Get-CoercedLiveQueueLeakValue {' `
    -EndMarker "function Get-EffectiveAudioOutputQueueLeakValue { return Get-EffectiveQueueLeakValue -Combo `$cmbAudioOutputQueueLeakMode }")

# The real New-LiveQueueString -- proves the "blank means omit the leaky=
# property, not substitute a value" mechanism end to end.
Invoke-Expression (Get-FunctionSourceText -Path $webRtcPipelinePath `
    -StartMarker 'function New-LiveQueueString {' `
    -EndMarker "`n}")

function New-TestComboBox {
    param([string[]]$Items, [string]$Selected = 'Default')
    $combo = New-Object System.Windows.Forms.ComboBox
    $null = $combo.Items.AddRange($Items)
    $combo.SelectedItem = $Selected
    return $combo
}

$script:DefaultThreadingProfile = 'Live strict'
$leakItems = @('Default', 'Downstream - drop old', 'Upstream - drop new', 'No leak - block')

$cmbThreadingProfile = New-TestComboBox -Items @('Live strict', 'Balanced', 'Non-blocking brutal', 'Blocking diagnostic', 'Custom') -Selected 'Live strict'
$cmbVideoInputQueueLeakMode = New-TestComboBox -Items $leakItems
$cmbVideoOutputQueueLeakMode = New-TestComboBox -Items $leakItems
$cmbAudioInputQueueLeakMode = New-TestComboBox -Items $leakItems
$cmbAudioOutputQueueLeakMode = New-TestComboBox -Items $leakItems

$queueControls = @(
    [pscustomobject]@{ Name = 'video input'; Combo = $cmbVideoInputQueueLeakMode; Resolve = { Get-EffectiveVideoInputQueueLeakValue } }
    [pscustomobject]@{ Name = 'video output'; Combo = $cmbVideoOutputQueueLeakMode; Resolve = { Get-EffectiveVideoOutputQueueLeakValue } }
    [pscustomobject]@{ Name = 'audio input'; Combo = $cmbAudioInputQueueLeakMode; Resolve = { Get-EffectiveAudioInputQueueLeakValue } }
    [pscustomobject]@{ Name = 'audio output'; Combo = $cmbAudioOutputQueueLeakMode; Resolve = { Get-EffectiveAudioOutputQueueLeakValue } }
)

# --- 1. 'Default' (the true default item, not just nothing selected)
#         resolves to '' -- omit, not a substituted value -- for all four
#         controls, independent of the threading profile. ---
foreach ($queueControl in $queueControls) {
    foreach ($profileSelection in @('Live strict', 'Blocking diagnostic')) {
        $cmbThreadingProfile.SelectedItem = $profileSelection
        $resolved = & $queueControl.Resolve
        Assert-QueueLeak ($resolved -eq '') "$($queueControl.Name) on 'Default' should resolve to '' (omit), got '$resolved' under profile '$profileSelection'."
    }
}
$cmbThreadingProfile.SelectedItem = 'Live strict'
Write-Output "'Default' resolves to '' (omit) for all four queue controls, regardless of threading profile."

# --- 2. New-LiveQueueString actually omits the leaky= property for a blank
#         Leak, and includes it for an explicit one. ---
$omittedQueue = New-LiveQueueString -Buffers 2 -MaxTimeMs 0 -Leak (Get-EffectiveVideoInputQueueLeakValue)
Assert-QueueLeak ($omittedQueue -notmatch 'leaky=') "A blank effective leak value should produce a queue string with no leaky= property at all, got: $omittedQueue"
Assert-QueueLeak ($omittedQueue -match '^queue max-size-buffers=2') "The omitted-leak queue string lost its other properties: $omittedQueue"
$explicitQueue = New-LiveQueueString -Buffers 2 -MaxTimeMs 0 -Leak 'downstream'
Assert-QueueLeak ($explicitQueue -match 'leaky=downstream$') "An explicit leak value should still produce leaky=<value>, got: $explicitQueue"
Write-Output "New-LiveQueueString omits leaky= entirely for a blank value and includes it for an explicit one."

# --- 3. Each of the four controls resolves independently -- setting one
#         to an explicit value does not affect the other three, which stay
#         on 'Default' (omit). ---
$cmbVideoInputQueueLeakMode.SelectedItem = 'Upstream - drop new'
Assert-QueueLeak ((Get-EffectiveVideoInputQueueLeakValue) -eq 'upstream') "Video input did not resolve to its own explicit value (got '$(Get-EffectiveVideoInputQueueLeakValue)')."
Assert-QueueLeak ((Get-EffectiveVideoOutputQueueLeakValue) -eq '') "Video output should be unaffected by video input's override (got '$(Get-EffectiveVideoOutputQueueLeakValue)')."
Assert-QueueLeak ((Get-EffectiveAudioInputQueueLeakValue) -eq '') "Audio input should be unaffected by video input's override (got '$(Get-EffectiveAudioInputQueueLeakValue)')."
Assert-QueueLeak ((Get-EffectiveAudioOutputQueueLeakValue) -eq '') "Audio output should be unaffected by video input's override (got '$(Get-EffectiveAudioOutputQueueLeakValue)')."
$cmbVideoInputQueueLeakMode.SelectedItem = 'Default'

# Audio output explicitly asks for 'No leak - block' outside the Blocking
# diagnostic profile -- must be coerced to downstream, the same safety
# rule a single removed global setting used to apply, now enforced
# identically for each of the four controls via the shared
# Get-CoercedLiveQueueLeakValue helper.
$cmbAudioOutputQueueLeakMode.SelectedItem = 'No leak - block'
Assert-QueueLeak ((Get-EffectiveAudioOutputQueueLeakValue) -eq 'downstream') "Audio output 'No leak - block' was not coerced to downstream outside Blocking diagnostic profile (got '$(Get-EffectiveAudioOutputQueueLeakValue)')."
$cmbThreadingProfile.SelectedItem = 'Blocking diagnostic'
Assert-QueueLeak ((Get-EffectiveAudioOutputQueueLeakValue) -eq 'no') "Audio output 'No leak - block' should be honored (not coerced) inside the Blocking diagnostic profile (got '$(Get-EffectiveAudioOutputQueueLeakValue)')."
$cmbThreadingProfile.SelectedItem = 'Live strict'
$cmbAudioOutputQueueLeakMode.SelectedItem = 'Default'
Write-Output "All four controls resolve independently of each other, and the Blocking-diagnostic coercion applies identically to each."

# --- 4. Apply-ThreadingProfile's real source sets all FOUR new combos for
#         every non-Custom profile, and never references any removed
#         combo name -- the actual safety net that keeps 'Default' from
#         being what most users experience. ---
$applyThreadingProfileSource = Get-FunctionSourceText -Path $threadingPath `
    -StartMarker 'function Apply-ThreadingProfile {' `
    -EndMarker "Update-CommandPreview`n}"
foreach ($removedName in @('cmbQueueLeakMode', 'cmbVideoQueueLeakMode', 'cmbAudioQueueLeakMode')) {
    Assert-QueueLeak ($applyThreadingProfileSource -notmatch $removedName) "Apply-ThreadingProfile still references the removed `$$removedName combo."
}
foreach ($presetName in @('Live strict', 'Balanced', 'Non-blocking brutal', 'Blocking diagnostic')) {
    $presetBlockPattern = "'$presetName' \{[^}]*\}"
    $presetMatch = [regex]::Match($applyThreadingProfileSource, $presetBlockPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    Assert-QueueLeak $presetMatch.Success "Could not find the '$presetName' block in Apply-ThreadingProfile -- this test needs updating."
    foreach ($comboName in @('cmbVideoInputQueueLeakMode', 'cmbVideoOutputQueueLeakMode', 'cmbAudioInputQueueLeakMode', 'cmbAudioOutputQueueLeakMode')) {
        Assert-QueueLeak ($presetMatch.Value -match "\`$$comboName\.SelectedItem\s*=") "Threading profile '$presetName' does not set `$$comboName."
    }
}
Write-Output "Every threading profile sets all four per-queue combos directly; no reference to any removed combo remains."

Write-Output ""
Write-Output "Queue leak mode checks passed."
