# SPDX-License-Identifier: AGPL-3.0-only

# The player route switch calls this connection mode WAN because it controls
# public/WAN ICE preference, not whether signaling uses a proxy. Keep the old
# "proxy" value everywhere outside that immediate switch presentation.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$playerPath = Join-Path $repoRoot 'gstwebrtc-api\dist\player.js'
$player = Get-Content -Raw -LiteralPath $playerPath

function Assert-WanModeInvariant {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

Assert-WanModeInvariant ($player -match "\['proxy',\s*'remote',\s*'relay'\]\.includes\(mode\)\)\s*return\s*'proxy'") (
    'The internal proxy mode aliases changed unexpectedly.'
)
Assert-WanModeInvariant ($player -match "return\s+normalized\s*===\s*'proxy'\s*\?\s*'WAN'") (
    'connectionModeControlLabel does not present the internal proxy value as WAN.'
)
Assert-WanModeInvariant ($player -match 'button\.textContent\s*=\s*label') (
    'The connection-mode button bypasses the WAN presentation label.'
)
Assert-WanModeInvariant ($player -match 'AUTO → LAN → WAN') (
    'The connection-mode tooltip does not advertise the AUTO/LAN/WAN cycle.'
)
Assert-WanModeInvariant ($player -match "const modes = \['auto', 'lan', 'proxy'\]") (
    'The compatibility-safe internal mode cycle changed unexpectedly; existing proxy state would no longer be preserved.'
)
Assert-WanModeInvariant ($player -match "PROXY FALLBACK: DIRECT LAN MEDIA") (
    'Internal PROXY fallback diagnostics changed with the switch label.'
)
Assert-WanModeInvariant ($player -match 'connectionMode:\s*connectionMode\(\),\s*mediaRoutePolicy:') (
    'The diagnostic state API changed with the switch label.'
)

Write-Output 'WAN is limited to the player route switch; internal proxy behavior is unchanged.'
Write-Output 'Player WAN mode label checks passed.'
