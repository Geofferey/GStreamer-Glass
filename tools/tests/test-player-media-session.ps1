$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$distRoot = Join-Path $repoRoot 'gstwebrtc-api\dist'
$player = Get-Content -LiteralPath (Join-Path $distRoot 'player.js') -Raw
$serviceWorker = Get-Content -LiteralPath (Join-Path $distRoot 'sw.js') -Raw
$webUiManifest = Get-Content -LiteralPath (Join-Path $distRoot 'gstglass-webui-manifest.json') -Raw | ConvertFrom-Json

function Assert-MediaSession([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

Assert-MediaSession ($player.Contains("'mediaSession' in navigator")) 'The player does not feature-detect the Media Session API.'
Assert-MediaSession ($player.Contains('new MediaMetadata({')) 'The player does not publish live-stream media metadata.'
Assert-MediaSession ($player.Contains("title: document.title || 'GStreamer Glass Live'")) 'Media metadata does not identify the live viewer.'
Assert-MediaSession ($player.Contains("artist: location.host || location.hostname")) 'Media metadata does not retain the viewer origin in the OS surface.'
Assert-MediaSession ($player.Contains("./icons/gstreamer-glass-192.png") -and $player.Contains("./icons/gstreamer-glass-512.png")) 'Media metadata artwork is incomplete.'

foreach ($action in @('play', 'pause', 'stop')) {
    Assert-MediaSession ($player.Contains("installMediaSessionAction('$action'")) "Missing Media Session '$action' action."
}

Assert-MediaSession (-not $player.Contains("installMediaSessionAction('seek")) 'A live WebRTC stream must not advertise seek controls.'
Assert-MediaSession (-not $player.Contains('setPositionState(')) 'A live WebRTC stream must not publish a finite playback position.'
Assert-MediaSession ($player -match "function applyLogicalMediaState[\s\S]*?syncMediaSessionPlaybackState\(\)") 'Logical player changes are not synchronized to the OS playback state.'
Assert-MediaSession ($player -match "function stopSession[\s\S]*?syncMediaSessionPlaybackState\(\)") 'Session teardown does not clear the OS playback state.'
Assert-MediaSession ($player.Contains("FRONTEND_VERSION = '3.8-viewer-auth-44'")) 'The frontend version was not advanced for native and OS media controls.'
Assert-MediaSession ($serviceWorker.Contains("gstglass-pwa-3.8-viewer-auth-52")) 'The PWA cache was not advanced for native and OS media controls.'
Assert-MediaSession ($webUiManifest.webUiVersion -eq '3.8.52') 'The packaged Web UI version was not advanced for native and OS media controls.'

Write-Host 'PASS: the live PWA exposes synchronized OS media playback controls.'
