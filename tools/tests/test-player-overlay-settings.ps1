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
$pipPosition = $utilityMarkup.Value.IndexOf('id="viewerPipButton"', [System.StringComparison]::Ordinal)
$settingsPosition = $utilityMarkup.Value.IndexOf('id="viewerSettingsButton"', [System.StringComparison]::Ordinal)
Assert-OverlaySettings ($debugPosition -ge 0 -and $pipPosition -gt $debugPosition -and $settingsPosition -gt $pipPosition) 'The PiP shortcut must appear immediately left of the settings gear.'

foreach ($id in @('viewerSettingsPanel', 'viewerSettingStatus', 'viewerSettingStats', 'viewerSettingControls', 'viewerSettingNativeControls', 'viewerSettingPip', 'viewerSettingPipDisablesBackgroundAudio', 'viewerSettingMediaNotificationAnchor', 'viewerSettingDebug')) {
    Assert-OverlaySettings ($index.Contains("id=`"$id`"")) "Missing viewer setting control '$id'."
}

Assert-OverlaySettings ($player.Contains("VIEWER_DISPLAY_SETTINGS_KEY = 'gstglass-viewer-display-v1'")) 'Viewer display preferences are not persisted under a stable key.'
foreach ($setting in @('statusOverlay', 'statsOverlay', 'playbackControls', 'nativeMediaControls', 'pictureInPictureShortcut', 'pipDisablesBackgroundAudio', 'mediaNotificationAnchor', 'debugShortcut')) {
    Assert-OverlaySettings ($player.Contains($setting)) "Player does not implement viewer setting '$setting'."
}
Assert-OverlaySettings ($player.Contains("localStorage.setItem(VIEWER_DISPLAY_SETTINGS_KEY")) 'Viewer settings are not written to local storage.'
Assert-OverlaySettings ($player.Contains("localStorage.removeItem(VIEWER_DISPLAY_SETTINGS_KEY")) 'Viewer settings cannot be reset to configured defaults.'
Assert-OverlaySettings ($css -match 'body\.hideStatusOverlay\s+\.overlay\s*\{\s*display:\s*none\s*!important') 'Status overlay suppression CSS is missing.'
Assert-OverlaySettings ($css -match 'body\.isFullscreen\.uiActive\s+\.viewerUtilityBar') 'The settings gear is not recoverable after interaction in immersive mode.'
Assert-OverlaySettings ($css.Contains('--glass-overlay-background: linear-gradient(180deg, rgba(10,14,22,.82), rgba(10,14,22,.48))')) 'The canonical status-overlay color is not exposed as a shared surface token.'
Assert-OverlaySettings ($css.Contains('--glass-overlay-blur: blur(10px)')) 'The canonical status-overlay Gaussian blur is not exposed as a shared surface token.'
foreach ($surface in @('.overlay', '.fullscreenButton', '.viewerSettingsPanel', '.statsOverlay')) {
    $surfaceRule = [regex]::Match($css, "(?s)$([regex]::Escape($surface))\s*\{.*?\}")
    Assert-OverlaySettings ($surfaceRule.Success -and $surfaceRule.Value.Contains('background: var(--glass-overlay-background)') -and $surfaceRule.Value.Contains('backdrop-filter: var(--glass-overlay-blur)')) "Player surface '$surface' does not share the status-overlay color and blur."
}
Assert-OverlaySettings ($css -match '(?s)\.glassControls\s*\{.*?background:\s*linear-gradient\(180deg, rgba\(9,13,20,\.82\), rgba\(5,8,13,\.94\)\).*?backdrop-filter:\s*blur\(12px\)') 'The media playback bar no longer uses its established darker surface and blur.'
Assert-OverlaySettings ($css -match '(?s)\.statsOverlay\s*\{.*?opacity:\s*1\s*;') 'The connection-statistics surface is faded instead of matching the other overlays.'
foreach ($fadedStatsOpacity in @('body.isFullscreen .statsOverlay', 'body.isFullscreen.uiActive .statsOverlay', 'body.isFullscreen.uiPinned .statsOverlay')) {
    Assert-OverlaySettings (-not ($css -match "$([regex]::Escape($fadedStatsOpacity))\s*\{\s*opacity:")) "Connection statistics still has a context-specific opacity override for '$fadedStatsOpacity'."
}
Assert-OverlaySettings ($css -match '(?s)\.debugLink,\s*\.viewerPipButton,\s*\.viewerSettingsButton\s*\{.*?background:\s*var\(--glass-overlay-background\).*?backdrop-filter:\s*var\(--glass-overlay-blur\)') 'Viewer utility overlays do not share the status-overlay color and blur.'
Assert-OverlaySettings ($index.Contains('player.css?v=3.8.30') -and $serviceWorker.Contains('player.css?v=3.8.30')) 'Player settings CSS version is inconsistent between the page and service worker.'
Assert-OverlaySettings ($player.Contains('video.controls = enabled')) 'Native browser controls are not gated by the viewer setting.'
Assert-OverlaySettings ($player.Contains("video.controlsList.remove('nofullscreen')")) 'Native mode does not restore the browser fullscreen control.'
Assert-OverlaySettings ($player.Contains('video.disableRemotePlayback = !enabled')) 'Native mode does not restore the browser remote-playback policy.'
Assert-OverlaySettings ($player -match 'function fullscreenTarget[\s\S]*?desktopCustomControls = !mobileBrowser && !nativeMediaControlsEnabled\(\)') 'Desktop fullscreen does not honor the native/custom controls preference.'
Assert-OverlaySettings ($player -match "function handleVideoActivation[\s\S]*?if \(nativeMediaControlsEnabled\(\)\)") 'Glass still intercepts clicks intended for the native media controls.'
Assert-OverlaySettings ($player.Contains("applyLogicalMediaState('native-video-pause')")) 'Native pause is not bridged into the logical media controller.'
Assert-OverlaySettings ($serviceWorker.Contains("gstglass-pwa-3.8-viewer-auth-63")) 'Service-worker cache no longer includes the current viewer release.'

Write-Host 'PASS: viewer overlay settings are persistent and the gear is to the right of debug.'
