# SPDX-License-Identifier: AGPL-3.0-only

# Regression coverage for the ORDERING invariants that make the auth-proxy
# teardown sequence in src/27-StreamLifecycle.ps1 actually safe, as opposed
# to the gating invariant covered separately by
# test-proxy-forwarding-resume-gating.ps1. Both Stop-ControlledLiveStream and
# Stop-GstStream established two orderings the hard way, through real
# whole-app UI freezes and login-redirect failures, that a well-intentioned
# refactor (reordering statements, hoisting a call, "simplifying" a
# try/catch) could silently break without any parse error and without
# failing until reproduced against a live viewer:
#
#   1. Suspend-ActiveAuthenticationProxyForwarding / Disconnect-
#      ActiveAuthenticationProxyConnections MUST run before
#      Stop-ProcessTreeById kills the GStreamer process. This is the actual
#      fix for the same-port self-loop CPU-pegging whole-app freeze: a
#      still-alive plaintext/TLS auth proxy must stop forwarding and drop
#      any live connection BEFORE the process it forwards to disappears,
#      not after -- killing first and pausing/disconnecting second leaves a
#      window where the proxy can route its own reconnect attempt back into
#      its own listener.
#   2. Set-DirectWebRtcAuthRevokedMarker MUST run before
#      Revoke-ActiveAuthenticationProxySessions. This is the explicit,
#      previously-stated requirement that "redirect has to occur before
#      auth revoke if state json is used" -- the state-json marker a viewer
#      polls to know it should return to /auth/ has to be in place before
#      the session that would otherwise let it keep loading /live/ is
#      actually invalidated, or a viewer can race the revoke and land on a
#      dead session with no marker telling it to leave.
#
# This is a static source check: reproducing either failure mode for real
# needs a live GStreamer process, an active viewer connection, and precise
# timing, none of which are practical to simulate headlessly. This instead
# asserts the statement ordering that keeps both fixes in effect.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$lifecyclePath = Join-Path $repoRoot 'src\27-StreamLifecycle.ps1'
$fileName = [System.IO.Path]::GetFileName($lifecyclePath)

function Assert-Ordering {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$lines = Get-Content -LiteralPath $lifecyclePath

# --- Locate the two teardown function bodies ----------------------------
$functionStarts = @{}
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^function\s+([A-Za-z0-9_-]+)\s*\{') {
        $functionStarts[$i] = $Matches[1]
    }
}
$orderedStartLines = $functionStarts.Keys | Sort-Object

function Get-FunctionBodyRange {
    param([string]$FunctionName)
    $startLine = $null
    foreach ($lineIndex in $orderedStartLines) {
        if ($functionStarts[$lineIndex] -eq $FunctionName) { $startLine = $lineIndex; break }
    }
    if ($null -eq $startLine) {
        throw "Could not find 'function $FunctionName' in $fileName -- this test needs updating to match wherever that function now lives."
    }
    $endLine = $lines.Count - 1
    foreach ($lineIndex in $orderedStartLines) {
        if ($lineIndex -gt $startLine) { $endLine = $lineIndex - 1; break }
    }
    return @{ Start = $startLine; End = $endLine }
}

function Find-LineIndexesInRange {
    param([string]$Pattern, [hashtable]$Range)
    # Comment text is excluded from matching (best-effort: everything from the
    # first unquoted-ish "#" onward) so prose mentioning a function name --
    # e.g. explanatory comments referencing a sibling call elsewhere -- is
    # never mistaken for an actual call to it.
    $foundIndexes = @()
    for ($i = $Range.Start; $i -le $Range.End; $i++) {
        $line = $lines[$i]
        $hashIndex = $line.IndexOf('#')
        $codePart = if ($hashIndex -ge 0) { $line.Substring(0, $hashIndex) } else { $line }
        if ($codePart -match $Pattern) { $foundIndexes += $i }
    }
    return $foundIndexes
}

$targetFunctions = @('Stop-ControlledLiveStream', 'Stop-GstStream')

foreach ($functionName in $targetFunctions) {
    $range = Get-FunctionBodyRange -FunctionName $functionName

    # --- Invariant 1: Suspend/Disconnect before every process kill ------
    $killIndexes = Find-LineIndexesInRange -Pattern 'Stop-ProcessTreeById\s+-ProcessId' -Range $range
    Assert-Ordering ($killIndexes.Count -gt 0) (
        "Could not find any Stop-ProcessTreeById call inside $functionName in $fileName -- " +
        "this test needs updating to match how that function now tears down the GStreamer process."
    )
    $suspendIndexes = Find-LineIndexesInRange -Pattern 'Suspend-ActiveAuthenticationProxyForwarding' -Range $range
    $disconnectIndexes = Find-LineIndexesInRange -Pattern 'Disconnect-ActiveAuthenticationProxyConnections' -Range $range
    Assert-Ordering ($suspendIndexes.Count -gt 0) (
        "$functionName in $fileName kills the GStreamer process but never calls " +
        "Suspend-ActiveAuthenticationProxyForwarding -- a still-alive auth proxy would keep " +
        "forwarding into a process that is about to disappear, reproducing the same-port " +
        "self-loop CPU-pegging whole-app freeze."
    )
    Assert-Ordering ($disconnectIndexes.Count -gt 0) (
        "$functionName in $fileName kills the GStreamer process but never calls " +
        "Disconnect-ActiveAuthenticationProxyConnections -- a live viewer connection would be " +
        "left to notice the process died on its own instead of being cleanly severed first."
    )
    $firstKillIndex = ($killIndexes | Measure-Object -Minimum).Minimum
    $earliestSuspend = ($suspendIndexes | Measure-Object -Minimum).Minimum
    $earliestDisconnect = ($disconnectIndexes | Measure-Object -Minimum).Minimum
    Assert-Ordering ($earliestSuspend -lt $firstKillIndex) (
        "$($fileName):$($earliestSuspend + 1): Suspend-ActiveAuthenticationProxyForwarding in " +
        "$functionName must run BEFORE Stop-ProcessTreeById " +
        "($($fileName):$($firstKillIndex + 1)), not after -- this ordering is the actual fix " +
        "for the same-port self-loop CPU-pegging whole-app freeze."
    )
    Assert-Ordering ($earliestDisconnect -lt $firstKillIndex) (
        "$($fileName):$($earliestDisconnect + 1): Disconnect-ActiveAuthenticationProxyConnections " +
        "in $functionName must run BEFORE Stop-ProcessTreeById " +
        "($($fileName):$($firstKillIndex + 1)), not after."
    )

    # --- Invariant 2: revoked-marker set before sessions are revoked ----
    $markerIndexes = Find-LineIndexesInRange -Pattern 'Set-DirectWebRtcAuthRevokedMarker' -Range $range
    $revokeIndexes = Find-LineIndexesInRange -Pattern 'Revoke-ActiveAuthenticationProxySessions' -Range $range
    if ($revokeIndexes.Count -gt 0) {
        Assert-Ordering ($markerIndexes.Count -gt 0) (
            "$functionName in $fileName calls Revoke-ActiveAuthenticationProxySessions but never " +
            "Set-DirectWebRtcAuthRevokedMarker -- a viewer whose session gets revoked here has no " +
            "state-json marker telling it to return to /auth/, so it can be left stuck on a dead " +
            "session instead of redirected to login."
        )
        $earliestMarker = ($markerIndexes | Measure-Object -Minimum).Minimum
        $earliestRevoke = ($revokeIndexes | Measure-Object -Minimum).Minimum
        Assert-Ordering ($earliestMarker -lt $earliestRevoke) (
            "$($fileName):$($earliestMarker + 1): Set-DirectWebRtcAuthRevokedMarker in " +
            "$functionName must run BEFORE Revoke-ActiveAuthenticationProxySessions " +
            "($($fileName):$($earliestRevoke + 1)) -- the redirect marker has to be in place " +
            "before the session that would otherwise let a viewer keep loading /live/ is " +
            "actually invalidated, per the explicit 'redirect has to occur before auth revoke " +
            "if state json is used' requirement."
        )
    }

    Write-Output "${functionName}: Suspend/Disconnect confirmed before every process kill; revoked-marker confirmed before session revoke."
}

Write-Output ""
Write-Output "Auth proxy teardown ordering checks passed."
