$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$distRoot = Join-Path $repoRoot 'gstwebrtc-api\dist'
$index = Get-Content -LiteralPath (Join-Path $distRoot 'index.html') -Raw
$player = Get-Content -LiteralPath (Join-Path $distRoot 'player.js') -Raw
$css = Get-Content -LiteralPath (Join-Path $distRoot 'player.css') -Raw
$serviceWorker = Get-Content -LiteralPath (Join-Path $distRoot 'sw.js') -Raw

function Assert-OverlaySettings([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

$utilityMarkup = [regex]::Match($index, '(?s)<div id="viewerUtilityBar".*?</div>')
Assert-OverlaySettings $utilityMarkup.Success 'The viewer utility bar is missing.'
$debugPosition = $utilityMarkup.Value.IndexOf('id="debugLink"', [System.StringComparison]::Ordinal)
$settingsPosition = $utilityMarkup.Value.IndexOf('id="viewerSettingsButton"', [System.StringComparison]::Ordinal)
Assert-OverlaySettings ($debugPosition -ge 0 -and $settingsPosition -gt $debugPosition) 'The settings gear must appear to the right of the debug shortcut.'

foreach ($id in @('viewerSettingsPanel', 'viewerSettingStatus', 'viewerSettingStats', 'viewerSettingControls', 'viewerSettingNativeControls', 'viewerSettingMediaNotificationAnchor', 'viewerSettingDebug')) {
    Assert-OverlaySettings ($index.Contains("id=`"$id`"")) "Missing viewer setting control '$id'."
}

Assert-OverlaySettings ($player.Contains("VIEWER_DISPLAY_SETTINGS_KEY = 'gstglass-viewer-display-v1'")) 'Viewer display preferences are not persisted under a stable key.'
foreach ($setting in @('statusOverlay', 'statsOverlay', 'playbackControls', 'nativeMediaControls', 'mediaNotificationAnchor', 'debugShortcut')) {
    Assert-OverlaySettings ($player.Contains($setting)) "Player does not implement viewer setting '$setting'."
}
Assert-OverlaySettings ($player.Contains("localStorage.setItem(VIEWER_DISPLAY_SETTINGS_KEY")) 'Viewer settings are not written to local storage.'
Assert-OverlaySettings ($player.Contains("localStorage.removeItem(VIEWER_DISPLAY_SETTINGS_KEY")) 'Viewer settings cannot be reset to configured defaults.'
Assert-OverlaySettings ($css -match 'body\.hideStatusOverlay\s+\.overlay\s*\{\s*display:\s*none\s*!important') 'Status overlay suppression CSS is missing.'
Assert-OverlaySettings ($css -match 'body\.isFullscreen\.uiActive\s+\.viewerUtilityBar') 'The settings gear is not recoverable after interaction in immersive mode.'
Assert-OverlaySettings ($index.Contains('player.css?v=3.8.27') -and $serviceWorker.Contains('player.css?v=3.8.27')) 'Player settings CSS version is inconsistent between the page and service worker.'
Assert-OverlaySettings ($player.Contains('video.controls = enabled')) 'Native browser controls are not gated by the viewer setting.'
Assert-OverlaySettings ($player.Contains("video.controlsList.remove('nofullscreen')")) 'Native mode does not restore the browser fullscreen control.'
Assert-OverlaySettings ($player.Contains('video.disableRemotePlayback = !enabled')) 'Native mode does not restore the browser remote-playback policy.'
Assert-OverlaySettings ($player -match "function handleVideoActivation[\s\S]*?if \(nativeMediaControlsEnabled\(\)\)") 'Glass still intercepts clicks intended for the native media controls.'
Assert-OverlaySettings ($player.Contains("applyLogicalMediaState('native-video-pause')")) 'Native pause is not bridged into the logical media controller.'
Assert-OverlaySettings ($serviceWorker.Contains("gstglass-pwa-3.8-viewer-auth-53")) 'Service-worker cache no longer includes the viewer settings release.'

Write-Host 'PASS: viewer overlay settings are persistent and the gear is to the right of debug.'
