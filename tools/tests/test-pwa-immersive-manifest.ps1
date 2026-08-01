$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$distRoot = Join-Path $repoRoot 'gstwebrtc-api\dist'
$manifestPath = Join-Path $distRoot 'manifest.webmanifest'
$indexPath = Join-Path $distRoot 'index.html'
$serviceWorkerPath = Join-Path $distRoot 'sw.js'
$playerPath = Join-Path $distRoot 'player.js'
$playerCssPath = Join-Path $distRoot 'player.css'
$setupPath = Join-Path $repoRoot 'src\00-Setup.ps1'

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$index = Get-Content -LiteralPath $indexPath -Raw
$serviceWorker = Get-Content -LiteralPath $serviceWorkerPath -Raw
$player = Get-Content -LiteralPath $playerPath -Raw
$playerCss = Get-Content -LiteralPath $playerCssPath -Raw
$setup = Get-Content -LiteralPath $setupPath -Raw

if ($manifest.display -ne 'standalone') {
    throw "PWA manifest display must request standalone mode."
}

$displayOverride = @($manifest.display_override)
if ($displayOverride.Count -ne 1 -or $displayOverride[0] -ne 'standalone') {
    throw "PWA display_override must consistently request standalone mode."
}
if ($manifest.start_url -ne './?source=pwa') {
    throw "The PWA start URL no longer uses the established mounted-viewer launch marker."
}
$stableManifestUrl = 'manifest.webmanifest?v=3.8.40'
if ($index -notmatch [regex]::Escape($stableManifestUrl)) {
    throw "index.html changed the established manifest URL; installed PWA updates require it to remain stable."
}
if ($serviceWorker -notmatch [regex]::Escape($stableManifestUrl)) {
    throw "The service worker does not cache the established PWA manifest URL."
}
if ($index -notmatch [regex]::Escape('player.css?v=3.8.30') -or
    $serviceWorker -notmatch [regex]::Escape('player.css?v=3.8.30')) {
    throw "The immersive player stylesheet version is inconsistent between the page and service worker."
}
if ($setup -notmatch [regex]::Escape('manifest.webmanifest?v=3.8.40')) {
    throw "The authentication login page does not advertise the same established PWA manifest URL."
}
if ($serviceWorker -notmatch "CACHE_NAME\s*=\s*'gstglass-pwa-3\.8-viewer-auth-60'") {
    throw "The service-worker cache no longer includes the current immersive viewer release."
}
if ($setup -notmatch 'window\.visualViewport' -or
    $setup -notmatch 'navigator\.virtualKeyboard' -or
    $setup -notmatch "cardBottom=card\.offsetTop\+card\.offsetHeight" -or
    $setup -notmatch "overlap=Math\.max\(0,Math\.ceil\(cardBottom-bottom\)\)" -or
    $setup -notmatch "amount=overlap\?overlap\+32:0" -or
    $setup -notmatch "if\(amount===appliedLift\)return" -or
    $setup -match "card\.style\.transform='';requestAnimationFrame" -or
    $setup -notmatch "'translateY\(-'\+amount\+'px\)'" -or
    $setup -match '@media\(display-mode:standalone\)\{main\{(?:transform|padding-block):') {
    throw "The login card no longer stays centered until the detected keyboard boundary requires an upward lift."
}

if ($player -notmatch [regex]::Escape("['fullscreen', 'standalone', 'minimal-ui']")) {
    throw "The player does not recognize the installed PWA display modes."
}
if ($player -notmatch "pwaDisplayMode\(\)\s*===\s*'fullscreen'") {
    throw "The player does not treat manifest fullscreen as an already immersive application window."
}
if ($player -notmatch 'function\s+elementFullscreenActive\s*\(' -or
    $player -notmatch 'function\s+togglePlayerFullscreen[\s\S]*?elementFullscreenActive\(\)') {
    throw "The player does not keep PWA immersive state separate from interactive element fullscreen."
}
if ($playerCss -notmatch 'overscroll-behavior:\s*none') {
    throw "The player viewport does not suppress disruptive PWA overscroll actions."
}
if ($manifest.theme_color -ne '#07111f') {
    throw "The installed PWA no longer provides a dark-blue launch fallback for Android system chrome."
}
if ($index -notmatch '<meta\s+name="theme-color"\s+content="#000000">') {
    throw "The live viewer page does not request black system chrome."
}
if ($setup -notmatch '<meta name=\\"theme-color\\" content=\\"#07111f\\">' -or
    $setup -notmatch '--system-chrome-color:#07111f' -or
    $setup -notmatch "getPropertyValue\('--system-chrome-color'\)" -or
    $setup -notmatch "addEventListener\('pageshow',function\(\)\{theme\(\);queueLift\(\);\}\)") {
    throw "The authentication page does not dynamically reapply its CSS-owned system-chrome color."
}
if ($player -notmatch 'applyViewerThemeColor' -or $player -notmatch "VIEWER_THEME_COLOR\s*=\s*'#000000'") {
    throw "The viewer does not force and re-apply black system chrome after PWA navigation or resume."
}

Write-Host 'PASS: the standalone PWA dynamically paints login chrome, forces the player black, and retains element fullscreen.'
