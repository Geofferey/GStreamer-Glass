# SPDX-License-Identifier: AGPL-3.0-only

# Regression coverage for the video/audio queue-leak override controls.
# GStreamer's queue "leaky" property is independent per element instance --
# nothing in GStreamer itself ties queues together -- but this app used to
# route almost every live queue through one shared "Queue leak" dropdown.
# Get-EffectiveVideoQueueLeakValue/Get-EffectiveAudioQueueLeakValue add
# per-tab overrides that default to following that shared value ("Use
# global default") so existing settings/behavior are unaffected until a
# user explicitly opts in.
#
# Extracts and executes the REAL functions from src/16-CaptureAndAudioDevices.ps1
# (not a hand-copy), matching this repo's established convention, so this
# fails if the real logic regresses in some new way, not just if this exact
# bug comes back.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$devicesPath = Join-Path $repoRoot 'src\16-CaptureAndAudioDevices.ps1'
$recordingPath = Join-Path $repoRoot 'src\21-Recording.ps1'

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

# Get-ComboSelectedOrDefault (src/21-Recording.ps1) -- a dependency of every
# function under test here.
Invoke-Expression (Get-FunctionSourceText -Path $recordingPath `
    -StartMarker 'function Get-ComboSelectedOrDefault {' `
    -EndMarker "`n}")

# The real resolution chain: Get-QueueLeakValue, Get-CoercedLiveQueueLeakValue,
# Get-EffectiveLiveQueueLeakValue, Get-EffectiveVideoQueueLeakValue,
# Get-EffectiveAudioQueueLeakValue -- one contiguous block in the real file.
Invoke-Expression (Get-FunctionSourceText -Path $devicesPath `
    -StartMarker 'function Get-QueueLeakValue {' `
    -EndMarker 'function Get-EffectiveAudioQueueLeakValue {
    $mode = Get-ComboSelectedOrDefault $cmbAudioQueueLeakMode $script:DefaultAudioQueueLeakMode
    $raw = switch ($mode) {
        ''Upstream - drop new'' { ''upstream'' }
        ''No leak - block'' { ''no'' }
        ''Downstream - drop old'' { ''downstream'' }
        default { return Get-EffectiveLiveQueueLeakValue }
    }
    return Get-CoercedLiveQueueLeakValue -RawValue $raw
}')

function New-TestComboBox {
    param([string[]]$Items, [string]$Selected)
    $combo = New-Object System.Windows.Forms.ComboBox
    $null = $combo.Items.AddRange($Items)
    $combo.SelectedItem = $Selected
    return $combo
}

$script:DefaultQueueLeakMode = 'Downstream - drop old'
$script:DefaultVideoQueueLeakMode = 'Use global default'
$script:DefaultAudioQueueLeakMode = 'Use global default'
$script:DefaultThreadingProfile = 'Live strict'

$leakItems = @('Downstream - drop old', 'Upstream - drop new', 'No leak - block')
$overrideItems = @('Use global default') + $leakItems

$cmbThreadingProfile = New-TestComboBox -Items @('Live strict', 'Balanced', 'Non-blocking brutal', 'Blocking diagnostic', 'Custom') -Selected 'Live strict'
$cmbQueueLeakMode = New-TestComboBox -Items $leakItems -Selected 'Downstream - drop old'
$cmbVideoQueueLeakMode = New-TestComboBox -Items $overrideItems -Selected 'Use global default'
$cmbAudioQueueLeakMode = New-TestComboBox -Items $overrideItems -Selected 'Use global default'

# --- 1. "Use global default" tracks the global combo for every one of its
#         values, including through the Blocking-diagnostic 'no' coercion. ---
foreach ($globalSelection in $leakItems) {
    $cmbQueueLeakMode.SelectedItem = $globalSelection
    foreach ($profileSelection in @('Live strict', 'Blocking diagnostic')) {
        $cmbThreadingProfile.SelectedItem = $profileSelection
        $expected = Get-EffectiveLiveQueueLeakValue
        Assert-QueueLeak ((Get-EffectiveVideoQueueLeakValue) -eq $expected) "Video override on 'Use global default' did not track global='$globalSelection' profile='$profileSelection' (expected '$expected', got '$(Get-EffectiveVideoQueueLeakValue)')."
        Assert-QueueLeak ((Get-EffectiveAudioQueueLeakValue) -eq $expected) "Audio override on 'Use global default' did not track global='$globalSelection' profile='$profileSelection' (expected '$expected', got '$(Get-EffectiveAudioQueueLeakValue)')."
    }
}
$cmbThreadingProfile.SelectedItem = 'Live strict'
$cmbQueueLeakMode.SelectedItem = 'Downstream - drop old'
Write-Output "'Use global default' tracks the global setting across every value and both the coerced and uncoerced profile paths."

# --- 2. Explicit video/audio overrides resolve independently of each
#         other and of the (untouched) global default. ---
$cmbVideoQueueLeakMode.SelectedItem = 'Upstream - drop new'
$cmbAudioQueueLeakMode.SelectedItem = 'No leak - block'
$cmbThreadingProfile.SelectedItem = 'Live strict'
Assert-QueueLeak ((Get-EffectiveVideoQueueLeakValue) -eq 'upstream') "Video override did not resolve to its own explicit value (got '$(Get-EffectiveVideoQueueLeakValue)')."
# Audio explicitly asked for 'No leak - block' outside the Blocking diagnostic
# profile -- must be coerced to downstream, same safety rule as the global one.
Assert-QueueLeak ((Get-EffectiveAudioQueueLeakValue) -eq 'downstream') "Audio override 'No leak - block' was not coerced to downstream outside Blocking diagnostic profile (got '$(Get-EffectiveAudioQueueLeakValue)')."
Assert-QueueLeak ((Get-EffectiveLiveQueueLeakValue) -eq 'downstream') "Setting video/audio overrides must not change the untouched global default (got '$(Get-EffectiveLiveQueueLeakValue)')."
Write-Output "Video and audio overrides resolve independently of each other and leave the global default untouched."

# --- 3. In the Blocking diagnostic profile, an explicit 'No leak - block'
#         override is honored (not coerced) for whichever stream asked for it,
#         same as the global setting already behaves. ---
$cmbThreadingProfile.SelectedItem = 'Blocking diagnostic'
Assert-QueueLeak ((Get-EffectiveAudioQueueLeakValue) -eq 'no') "Audio override 'No leak - block' should be honored (not coerced) inside the Blocking diagnostic profile (got '$(Get-EffectiveAudioQueueLeakValue)')."
$cmbThreadingProfile.SelectedItem = 'Live strict'
Write-Output "The 'no'-outside-Blocking-diagnostic coercion applies identically to global, video, and audio resolution paths."

Write-Output ""
Write-Output "Queue leak mode checks passed."
