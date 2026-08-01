$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$distRoot = Join-Path $repoRoot 'gstwebrtc-api\dist'
$player = Get-Content -LiteralPath (Join-Path $distRoot 'player.js') -Raw
$serviceWorker = Get-Content -LiteralPath (Join-Path $distRoot 'sw.js') -Raw
$webUiManifest = Get-Content -LiteralPath (Join-Path $distRoot 'gstglass-webui-manifest.json') -Raw | ConvertFrom-Json

function Assert-SignalingHeartbeat([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

Assert-SignalingHeartbeat ($player.Contains('function signalingHeartbeatTimeoutMs()')) 'The player has no bounded signaling heartbeat deadline.'
Assert-SignalingHeartbeat ($player.Contains('return Math.max(15000, interval * 3)')) 'The signaling heartbeat does not tolerate multiple missed probes.'
Assert-SignalingHeartbeat ($player -match "(?s)function startKeepAlive\(\).*?sendPrimaryKeepAliveProbe\('open', true\).*?setInterval\(primaryKeepAliveTick, interval\)") 'Primary signaling does not probe immediately before starting its periodic watchdog.'
Assert-SignalingHeartbeat ($player -match "(?s)function splitStartKeepAlive\(.*?sendSplitKeepAliveProbe\(reason, true\).*?setInterval\(splitKeepAliveTick, interval\)") 'Split-audio signaling does not probe immediately before starting its periodic watchdog.'

foreach ($requiredState in @('lastKeepAliveResponseAt', 'lastSignalingMessageAt', 'keepAliveOutstandingSince', 'lastKeepAliveTickAt', 'signalingRecoveryCount')) {
    Assert-SignalingHeartbeat ($player.Contains($requiredState)) "Missing signaling heartbeat state '$requiredState'."
}

Assert-SignalingHeartbeat ($player -match "function notePrimarySignalingMessage[\s\S]*?type === 'list'[\s\S]*?lastKeepAliveResponseAt") 'Primary signaling does not acknowledge heartbeat responses.'
Assert-SignalingHeartbeat ($player -match "function noteSplitSignalingMessage[\s\S]*?type === 'list'[\s\S]*?lastKeepAliveResponseAt") 'Split-audio signaling does not acknowledge heartbeat responses.'
Assert-SignalingHeartbeat ($player -match "function primaryKeepAliveTick[\s\S]*?keepAliveOutstandingSince[\s\S]*?reconnectStalePrimarySignaling") 'Primary signaling never recovers an unanswered heartbeat.'
Assert-SignalingHeartbeat ($player -match "function splitKeepAliveTick[\s\S]*?keepAliveOutstandingSince[\s\S]*?reconnectStaleSplitSignaling") 'Split-audio signaling never recovers an unanswered heartbeat.'
Assert-SignalingHeartbeat (($player | Select-String -Pattern "close\(4000, 'signaling heartbeat timeout'" -AllMatches).Matches.Count -eq 2) 'Both signaling transports must close stale sockets with the diagnostic heartbeat code.'

foreach ($resumeReason in @('visibility-visible', 'pageshow', 'window-focus', 'online')) {
    Assert-SignalingHeartbeat ($player.Contains("probeSignalingOnResume('$resumeReason')")) "Signaling is not probed after '$resumeReason'."
}
Assert-SignalingHeartbeat ($player -match "(?s)resumedAfterTimerGap.*?keepAliveOutstandingSince = 0.*?timer-resume") 'Timer suspension can still be mistaken for an unanswered heartbeat.'
Assert-SignalingHeartbeat ($player.Contains("log('primary signaling closed'")) 'Primary WebSocket close diagnostics are missing.'
Assert-SignalingHeartbeat ($player.Contains('lastSignalingCloseCode') -and $player.Contains('lastSignalingCloseReason')) 'Primary close code and reason are not retained for diagnostics.'
Assert-SignalingHeartbeat ($player.Contains('signalingHeartbeat: { enabled:')) 'Heartbeat health is not exposed through GstGlassPlayer.state().'

Assert-SignalingHeartbeat ($player.Contains("FRONTEND_VERSION = '3.8-viewer-auth-49'")) 'The frontend version was not advanced for the current viewer release.'
Assert-SignalingHeartbeat ($serviceWorker.Contains("gstglass-pwa-3.8-viewer-auth-60")) 'The PWA cache was not advanced for the current viewer release.'
Assert-SignalingHeartbeat ($webUiManifest.webUiVersion -eq '3.8.58') 'The packaged Web UI version was not advanced for the current viewer release.'

Write-Host 'PASS: primary and split-audio signaling heartbeats detect stale sockets and recover safely after timer suspension.'
