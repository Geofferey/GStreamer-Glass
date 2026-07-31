# SPDX-License-Identifier: AGPL-3.0-only

# Regression coverage for a same-port self-loop freeze reached through a
# second door: Resume-ActiveAuthenticationProxyForwarding was called
# unconditionally right after the proxy-(re)start block in both
# Start-GstStream code paths (controlled-live-worker and plain gst-launch),
# while every other call in that same block (Start-LetsEncryptTlsProxies,
# Start-PlaintextAuthProxies, Add-UpnpPortMappings, Update-DdnsRecord) is
# correctly gated on $transportEnabled.
#
# Concrete failure this caused: with "Enable experimental scene composition"
# UNCHECKED and "Preview" checked, a genuine full Stop (not Restart) with an
# active viewer and plaintext auth enabled triggers Sync-StandalonePreviewState
# -> Start-GstStream -PreviewOnly once the stop completes (the composition-ON
# path instead reuses the separate in-process GstControlledScenePreview
# preview and never re-enters Start-GstStream at all, which is why the bug
# only reproduced with composition off). PreviewOnly forces
# $transportEnabled = $false, so the proxy-(re)start calls are correctly
# skipped -- but the unconditional Resume call still un-paused the
# still-alive plaintext auth proxy left over from the just-stopped stream,
# pointing it at an internal forward target nothing is listening on (no
# webrtcsink server in preview-only mode). That is exactly the precondition
# for the same-port self-loop CPU-pegging freeze already fixed once this
# project's history (Suspend/Resume/DisconnectActiveConnections in
# src/00-Setup.ps1's TlsTerminatingProxy) -- reached again through an
# unguarded call site rather than a regression in that mechanism itself.
#
# This is a static source check, not a runtime one: reproducing the actual
# freeze needs a live GStreamer process, a real viewer connection, and a
# genuine Stop/Preview-restart timing window, none of which are practical to
# simulate headlessly. Instead this asserts the invariant that would have
# caught the bug before it shipped -- every call to
# Resume-ActiveAuthenticationProxyForwarding in the stream lifecycle must be
# nested inside an "if ($transportEnabled)" guard, matching every sibling
# proxy-(re)start call in the same block.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$lifecyclePath = Join-Path $repoRoot 'src\27-StreamLifecycle.ps1'

function Assert-Gating {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$lines = Get-Content -LiteralPath $lifecyclePath
$callSites = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'Resume-ActiveAuthenticationProxyForwarding') {
        $callSites += $i
    }
}

Assert-Gating ($callSites.Count -gt 0) (
    "Could not find any call to Resume-ActiveAuthenticationProxyForwarding in $lifecyclePath -- " +
    "this test needs updating to match wherever that logic now lives."
)

$ungated = @()
foreach ($lineIndex in $callSites) {
    # Walk backward through non-blank, non-comment-only lines looking for the
    # guarding "if ($transportEnabled)" within the same nesting level. Five
    # lines is enough headroom for the explanatory comment block that sits
    # directly above each call site without wandering into an unrelated guard.
    $found = $false
    $lookback = [Math]::Max(0, $lineIndex - 5)
    for ($j = $lineIndex; $j -ge $lookback; $j--) {
        if ($lines[$j] -match '\$transportEnabled') {
            $found = $true
            break
        }
    }
    if (-not $found) {
        $ungated += "$([System.IO.Path]::GetFileName($lifecyclePath)):$($lineIndex + 1): $($lines[$lineIndex].Trim())"
    }
}

Assert-Gating ($ungated.Count -eq 0) (
    "Found Resume-ActiveAuthenticationProxyForwarding call(s) not gated on " +
    "`$transportEnabled -- these resume a still-alive auth proxy even on a " +
    "Preview/Recording-only run where nothing is listening on its internal " +
    "forward target, reproducing the same-port self-loop CPU-pegging freeze:`n" +
    ($ungated -join "`n") +
    "`n`nFix: wrap the call in `"if (`$transportEnabled) { ... }`", matching the other proxy-(re)start calls in the same block."
)

Write-Output "Found $($callSites.Count) Resume-ActiveAuthenticationProxyForwarding call site(s) in $([System.IO.Path]::GetFileName($lifecyclePath)), all correctly gated on `$transportEnabled."
Write-Output ""
Write-Output "Proxy forwarding resume gating checks passed."
