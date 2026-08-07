# SPDX-License-Identifier: AGPL-3.0-only

# Regression coverage for UPnP restart churn: every restart (manual Restart
# button or truly automatic) used to call Add-UpnpPortMappings again on the
# way back up, even though Stop-GstStream/Stop-ControlledLiveStream already
# skip Remove-UpnpPortMappings on a restart -- meaning the mappings were
# never actually gone, but the app still re-contacted the router (discovery
# + a full StaticPortMappingCollection enumeration) on every single restart
# cycle. Routers can rate-limit or otherwise dislike this kind of frequent
# UPnP churn, so a restart should leave already-live mappings completely
# untouched end to end: only a genuine Start maps, only a genuine Stop
# unmaps, and each direction checks whether there is anything to do before
# ever touching the router.
#
# This is source-text verified rather than executed: these functions are
# deeply tied to live WinForms controls and a real UPnP-capable router,
# neither of which are practical to stand up in an isolated test, matching
# this repo's established fallback for functions too heavy to drive end to
# end (see test-queue-buffer-counts.ps1, test-app-exit-graceful-stop.ps1).

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$streamLifecyclePath = Join-Path $repoRoot 'src\27-StreamLifecycle.ps1'
$upnpPath = Join-Path $repoRoot 'src\31-UpnpPortForwarding.ps1'

function Assert-UpnpRestartNoRemap {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$streamLifecycleSource = Get-Content -Raw -LiteralPath $streamLifecyclePath
if (-not $streamLifecycleSource.Contains('function Start-GstStream {')) {
    throw "Could not find Start-GstStream in $streamLifecyclePath -- this test needs updating to match wherever that logic now lives."
}
$upnpSource = Get-Content -Raw -LiteralPath $upnpPath
if (-not $upnpSource.Contains('function Add-UpnpPortMappings {')) {
    throw "Could not find Add-UpnpPortMappings in $upnpPath -- this test needs updating to match wherever that logic now lives."
}
if (-not $upnpSource.Contains('function Remove-UpnpPortMappings {')) {
    throw "Could not find Remove-UpnpPortMappings in $upnpPath -- this test needs updating to match wherever that logic now lives."
}

# --- 1. Every Add-UpnpPortMappings call site inside Start-GstStream is
#         gated on -not $Automatic -- every restart resumption (manual
#         Restart-button or truly automatic) funnels through -Automatic, so
#         this excludes restarts specifically while leaving a genuine direct
#         Start/Go-Live call (no -Automatic) unaffected. ---
$addCallCount = ([regex]::Matches($streamLifecycleSource, [regex]::Escape('try { Add-UpnpPortMappings }'))).Count
Assert-UpnpRestartNoRemap ($addCallCount -eq 2) `
    "Expected exactly 2 Add-UpnpPortMappings call sites in Start-GstStream (plain gst-launch path and controlled-live-stream path), found $addCallCount. If a new call site was added, it needs the same -not `$Automatic gate as the existing two."
$automaticGatedAddCount = ([regex]::Matches($streamLifecycleSource, [regex]::Escape('-and -not $Automatic) {') + '\s*\r?\n\s*try \{ Add-UpnpPortMappings \}')).Count
Assert-UpnpRestartNoRemap ($automaticGatedAddCount -eq 2) `
    "Expected both Add-UpnpPortMappings call sites to be gated on '-and -not `$Automatic', found $automaticGatedAddCount gated correctly. Without this gate, every restart (manual or automatic) re-contacts the router even though the mappings from before the restart were never removed."
Write-Output "Start-GstStream: both Add-UpnpPortMappings call sites are gated on -not `$Automatic (skipped on every restart resumption)."

# --- 2. Every Remove-UpnpPortMappings call site inside the normal stop
#         teardown (Stop-GstStream's plain path, Stop-ControlledLiveStream)
#         is gated on -not $Restart -- the mirror-image gate, already
#         present before this fix but locked in here since it's now the
#         other half of the same "leave mappings untouched across a
#         restart" guarantee. ---
$removeCallCount = ([regex]::Matches($streamLifecycleSource, [regex]::Escape('try { Remove-UpnpPortMappings } catch {}'))).Count
Assert-UpnpRestartNoRemap ($removeCallCount -ge 2) `
    "Expected at least 2 Remove-UpnpPortMappings call sites (Stop-ControlledLiveStream and Stop-GstStream's plain-path teardown), found $removeCallCount."
$restartGatedRemoveCount = ([regex]::Matches($streamLifecycleSource, [regex]::Escape('if (-not $Restart) {') + '\s*\r?\n\s*try \{ Remove-UpnpPortMappings \} catch \{\}')).Count
Assert-UpnpRestartNoRemap ($restartGatedRemoveCount -eq 2) `
    "Expected exactly 2 Remove-UpnpPortMappings call sites gated on 'if (-not `$Restart)', found $restartGatedRemoveCount. Without this gate, a restart would unmap ports that Start-GstStream's resumption (gated on -not `$Automatic) no longer re-maps, leaving the stream unreachable after a restart."
Write-Output "Stop-GstStream / Stop-ControlledLiveStream: both normal-teardown Remove-UpnpPortMappings call sites are gated on -not `$Restart."

# --- 3. Add-UpnpPortMappings and Remove-UpnpPortMappings each check whether
#         there is anything to do BEFORE touching the router at all -- the
#         actual "check if already mapped/unmapped" requirement, and what
#         makes even a genuine Start/Stop cheap to call repeatedly. ---
Assert-UpnpRestartNoRemap ($upnpSource.Contains('if ($script:ActiveUpnpMappings.Count -gt 0) { return }')) `
    "Add-UpnpPortMappings should return immediately if mappings are already tracked as active, without contacting the router at all."
$addFunctionStart = $upnpSource.IndexOf('function Add-UpnpPortMappings {')
$addGuardIndex = $upnpSource.IndexOf('if ($script:ActiveUpnpMappings.Count -gt 0) { return }')
$addNatDiscoveryIndex = $upnpSource.IndexOf('Get-UpnpNatDevice', $addFunctionStart)
Assert-UpnpRestartNoRemap ($addGuardIndex -gt $addFunctionStart -and $addGuardIndex -lt $addNatDiscoveryIndex) `
    "The 'already mapped' guard in Add-UpnpPortMappings must run before any router discovery/contact (Get-UpnpNatDevice), not after -- otherwise the router still gets contacted on every call regardless of the guard."

Assert-UpnpRestartNoRemap ($upnpSource.Contains('if ($script:ActiveUpnpMappings.Count -eq 0) { return }')) `
    "Remove-UpnpPortMappings should return immediately if nothing is tracked as active, without contacting the router at all."
Write-Output "Add-UpnpPortMappings / Remove-UpnpPortMappings: both check for existing state before ever contacting the router."

Write-Output ""
Write-Output "UPnP restart-no-remap checks passed."
