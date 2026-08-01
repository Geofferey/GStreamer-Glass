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

if ($manifest.display -ne 'fullscreen') {
    throw "PWA manifest display must request fullscreen immersive mode."
}

$displayOverride = @($manifest.display_override)
if ($displayOverride.Count -lt 2 -or $displayOverride[0] -ne 'fullscreen' -or $displayOverride[1] -ne 'standalone') {
    throw "PWA display_override must prefer fullscreen and fall back to standalone."
}

$stableManifestUrl = 'manifest.webmanifest?v=3.8.40'
if ($index -notmatch [regex]::Escape($stableManifestUrl)) {
    throw "index.html changed the established manifest URL; installed PWA updates require it to remain stable."
}
if ($serviceWorker -notmatch [regex]::Escape($stableManifestUrl)) {
    throw "The service worker does not cache the established PWA manifest URL."
}
if ($index -notmatch [regex]::Escape('player.css?v=3.8.27') -or
    $serviceWorker -notmatch [regex]::Escape('player.css?v=3.8.27')) {
    throw "The immersive player stylesheet version is inconsistent between the page and service worker."
}
if ($setup -notmatch [regex]::Escape('manifest.webmanifest?v=3.8.40')) {
    throw "The authentication login page does not advertise the same established PWA manifest URL."
}
if ($serviceWorker -notmatch "CACHE_NAME\s*=\s*'gstglass-pwa-3\.8-viewer-auth-52'") {
    throw "The service-worker cache no longer includes the immersive viewer-theme update."
}

if ($player -notmatch [regex]::Escape("['fullscreen', 'standalone', 'minimal-ui']")) {
    throw "The player does not recognize the installed PWA display modes."
}
if ($player -notmatch "pwaDisplayMode\(\)\s*===\s*'fullscreen'") {
    throw "The player does not treat manifest fullscreen as an already immersive application window."
}
if ($playerCss -notmatch 'overscroll-behavior:\s*none') {
    throw "The player viewport does not suppress disruptive PWA overscroll actions."
}
if ($manifest.theme_color -ne '#000000' -or
    $index -notmatch '<meta\s+name="theme-color"\s+content="#000000">') {
    throw "The installed viewer and its manifest do not use a black system-bar theme."
}
if ($setup -notmatch '<meta name=\\"theme-color\\" content=\\"#07111f\\">') {
    throw "The authentication page no longer preserves its blue theme color."
}
if ($player -notmatch 'applyViewerThemeColor' -or $player -notmatch "VIEWER_THEME_COLOR\s*=\s*'#000000'") {
    throw "The viewer does not re-apply its black theme after PWA navigation or resume."
}

Write-Host 'PASS: the PWA requests immersive fullscreen mode with an installed-app fallback.'
