# SPDX-License-Identifier: AGPL-3.0-only

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$setupPath = Join-Path $repoRoot 'src\00-Setup.ps1'
$proxyStartupPath = Join-Path $repoRoot 'src\33-LetsEncrypt.ps1'
$restartImagePath = Join-Path $repoRoot 'gstwebrtc-api\dist\auth-proxy\well-be-right-back.png'
$restartMp4Path = Join-Path $repoRoot 'gstwebrtc-api\dist\auth-proxy\well-be-right-back-glitch.mp4'
$restartWebmPath = Join-Path $repoRoot 'gstwebrtc-api\dist\auth-proxy\well-be-right-back-glitch.webm'
$restartPortraitImagePath = Join-Path $repoRoot 'gstwebrtc-api\dist\auth-proxy\well-be-right-back-portrait.png'
$restartPortraitMp4Path = Join-Path $repoRoot 'gstwebrtc-api\dist\auth-proxy\well-be-right-back-portrait-glitch.mp4'
$restartPortraitWebmPath = Join-Path $repoRoot 'gstwebrtc-api\dist\auth-proxy\well-be-right-back-portrait-glitch.webm'
$webUiManifestPath = Join-Path $repoRoot 'gstwebrtc-api\dist\gstglass-webui-manifest.json'

function Assert-RestartImage([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

Assert-RestartImage (Test-Path -LiteralPath $restartImagePath -PathType Leaf) 'The stream-restart image is missing.'
Assert-RestartImage (Test-Path -LiteralPath $restartMp4Path -PathType Leaf) 'The stream-restart MP4 is missing.'
Assert-RestartImage (Test-Path -LiteralPath $restartWebmPath -PathType Leaf) 'The stream-restart WebM is missing.'
Assert-RestartImage (Test-Path -LiteralPath $restartPortraitImagePath -PathType Leaf) 'The portrait stream-restart image is missing.'
Assert-RestartImage (Test-Path -LiteralPath $restartPortraitMp4Path -PathType Leaf) 'The portrait stream-restart MP4 is missing.'
Assert-RestartImage (Test-Path -LiteralPath $restartPortraitWebmPath -PathType Leaf) 'The portrait stream-restart WebM is missing.'

$proxyStartupSource = Get-Content -Raw -LiteralPath $proxyStartupPath
$webUiManifest = Get-Content -Raw -LiteralPath $webUiManifestPath | ConvertFrom-Json
Assert-RestartImage (@($webUiManifest.assets) -contains 'auth-proxy/well-be-right-back.png') 'The packaged Web UI omits the stream-restart image.'
Assert-RestartImage (@($webUiManifest.assets) -contains 'auth-proxy/well-be-right-back-glitch.mp4') 'The packaged Web UI omits the stream-restart MP4.'
Assert-RestartImage (@($webUiManifest.assets) -contains 'auth-proxy/well-be-right-back-glitch.webm') 'The packaged Web UI omits the stream-restart WebM.'
Assert-RestartImage (@($webUiManifest.assets) -contains 'auth-proxy/well-be-right-back-portrait.png') 'The packaged Web UI omits the portrait stream-restart image.'
Assert-RestartImage (@($webUiManifest.assets) -contains 'auth-proxy/well-be-right-back-portrait-glitch.mp4') 'The packaged Web UI omits the portrait stream-restart MP4.'
Assert-RestartImage (@($webUiManifest.assets) -contains 'auth-proxy/well-be-right-back-portrait-glitch.webm') 'The packaged Web UI omits the portrait stream-restart WebM.'
Assert-RestartImage ($proxyStartupSource.Contains("Resolve-AuthProxyAssetPath -FileName 'well-be-right-back.png'")) 'Proxy startup does not resolve the stream-restart image.'
Assert-RestartImage ($proxyStartupSource.Contains("Resolve-AuthProxyAssetPath -FileName 'well-be-right-back-glitch.mp4'")) 'Proxy startup does not resolve the stream-restart MP4.'
Assert-RestartImage ($proxyStartupSource.Contains("Resolve-AuthProxyAssetPath -FileName 'well-be-right-back-glitch.webm'")) 'Proxy startup does not resolve the stream-restart WebM.'
Assert-RestartImage (($proxyStartupSource | Select-String -Pattern 'RestartImagePath\s*=\s*\$restartImagePath' -AllMatches).Matches.Count -eq 2) 'TLS and plaintext proxy families do not both pass the stream-restart image to the worker.'
Assert-RestartImage (($proxyStartupSource | Select-String -Pattern 'RestartVideoMp4Path\s*=\s*\$restartVideoMp4Path' -AllMatches).Matches.Count -eq 2) 'TLS and plaintext proxy families do not both pass the stream-restart MP4 to the worker.'
Assert-RestartImage (($proxyStartupSource | Select-String -Pattern 'RestartVideoWebmPath\s*=\s*\$restartVideoWebmPath' -AllMatches).Matches.Count -eq 2) 'TLS and plaintext proxy families do not both pass the stream-restart WebM to the worker.'
Assert-RestartImage (($proxyStartupSource | Select-String -Pattern 'RestartPortraitImagePath\s*=\s*\$restartPortraitImagePath' -AllMatches).Matches.Count -eq 2) 'TLS and plaintext proxy families do not both pass the portrait stream-restart image to the worker.'
Assert-RestartImage (($proxyStartupSource | Select-String -Pattern 'RestartPortraitVideoMp4Path\s*=\s*\$restartPortraitVideoMp4Path' -AllMatches).Matches.Count -eq 2) 'TLS and plaintext proxy families do not both pass the portrait stream-restart MP4 to the worker.'
Assert-RestartImage (($proxyStartupSource | Select-String -Pattern 'RestartPortraitVideoWebmPath\s*=\s*\$restartPortraitVideoWebmPath' -AllMatches).Matches.Count -eq 2) 'TLS and plaintext proxy families do not both pass the portrait stream-restart WebM to the worker.'

$source = Get-Content -Raw -LiteralPath $setupPath
Assert-RestartImage ($source.Contains('$proxy.ConfigureRestartImage([string]$Command.RestartImagePath)')) 'The auth worker does not apply its configured stream-restart image.'
Assert-RestartImage ($source.Contains('$proxy.ConfigureRestartVideos(')) 'The auth worker does not apply its configured stream-restart videos.'
Assert-RestartImage ($source.Contains('$proxy.ConfigureRestartPortraitImage([string]$Command.RestartPortraitImagePath)')) 'The auth worker does not apply its configured portrait stream-restart image.'
Assert-RestartImage ($source.Contains('$proxy.ConfigureRestartPortraitVideos(')) 'The auth worker does not apply its configured portrait stream-restart videos.'
$marker = "if (-not ('TlsTerminatingProxy' -as [type])) {"
$blockStart = $source.IndexOf($marker)
Assert-RestartImage ($blockStart -ge 0) 'TlsTerminatingProxy block was not found.'
$hereStart = $source.IndexOf("@'", $blockStart) + 2
$hereEnd = $source.IndexOf("'@", $hereStart)
Assert-RestartImage ($hereStart -ge 2 -and $hereEnd -gt $hereStart) 'TlsTerminatingProxy C# here-string was not found.'
Add-Type -TypeDefinition $source.Substring($hereStart, $hereEnd - $hereStart) -ErrorAction Stop

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}

function Send-PlainRequestBytes([int]$Port, [string]$Path = '/live/') {
    $client = [System.Net.Sockets.TcpClient]::new('127.0.0.1', $Port)
    try {
        $stream = $client.GetStream()
        $request = [System.Text.Encoding]::ASCII.GetBytes("GET $Path HTTP/1.1`r`nHost: localhost`r`nConnection: close`r`n`r`n")
        $stream.Write($request, 0, $request.Length)
        $stream.Flush()
        $response = [System.IO.MemoryStream]::new()
        try {
            $buffer = New-Object byte[] 8192
            while ($true) {
                try { $read = $stream.Read($buffer, 0, $buffer.Length) }
                catch {
                    if ($response.Length -gt 0) { break }
                    throw
                }
                if ($read -le 0) { break }
                $response.Write($buffer, 0, $read)
            }
            return $response.ToArray()
        }
        finally { $response.Dispose() }
    }
    finally { $client.Dispose() }
}

function Split-HttpResponse([byte[]]$ResponseBytes) {
    $headerEnd = -1
    for ($index = 0; $index -le $ResponseBytes.Length - 4; $index++) {
        if ($ResponseBytes[$index] -eq 13 -and $ResponseBytes[$index + 1] -eq 10 -and
            $ResponseBytes[$index + 2] -eq 13 -and $ResponseBytes[$index + 3] -eq 10) {
            $headerEnd = $index
            break
        }
    }
    Assert-RestartImage ($headerEnd -ge 0) 'Proxy response did not contain a complete HTTP header.'
    $header = [System.Text.Encoding]::ASCII.GetString($ResponseBytes, 0, $headerEnd)
    $bodyOffset = $headerEnd + 4
    $body = New-Object byte[] ($ResponseBytes.Length - $bodyOffset)
    if ($body.Length -gt 0) { [Array]::Copy($ResponseBytes, $bodyOffset, $body, 0, $body.Length) }
    return @{ Header = $header; Body = $body }
}

function Invoke-PausedProxyResponse(
    [string]$ImagePath,
    [string]$Mp4Path = '',
    [string]$WebmPath = '',
    [string]$PortraitImagePath = '',
    [string]$PortraitMp4Path = '',
    [string]$PortraitWebmPath = '',
    [string]$DirectoryRedirectPath = '/live'
) {
    $port = Get-FreeTcpPort
    $proxy = [TlsTerminatingProxy]::new()
    try {
        $proxy.ConfigureRestartImage($ImagePath)
        $proxy.ConfigureRestartVideos($Mp4Path, $WebmPath)
        $proxy.ConfigureRestartPortraitImage($PortraitImagePath)
        $proxy.ConfigureRestartPortraitVideos($PortraitMp4Path, $PortraitWebmPath)
        # Without this, the restart/holding page falls back to the built-in
        # minimal page (LoadTemplateText/ConfigureMediaMessageTemplate,
        # src/00-Setup.ps1), which lacks the black-viewport CSS, wake-lock,
        # and MediaSession script the assertions below check for.
        $proxy.ConfigureMediaMessageTemplate((Join-Path $repoRoot 'gstwebrtc-api\dist\auth-proxy\media-message.html'))
        # Force the proxy to consume the request header before returning its
        # local response. Closing a Windows socket with unread request bytes can
        # generate an RST that discards an otherwise-valid response in transit.
        $proxy.DirectoryRedirectPath = $DirectoryRedirectPath
        $proxy.Start($port, '127.0.0.1', $port, $null)
        $proxy.PauseForwarding()
        Start-Sleep -Milliseconds 100
        $page = Split-HttpResponse (Send-PlainRequestBytes $port)
        $mp4 = if ($Mp4Path) { Split-HttpResponse (Send-PlainRequestBytes $port '/auth/assets/well-be-right-back.mp4') } else { $null }
        $webm = if ($WebmPath) { Split-HttpResponse (Send-PlainRequestBytes $port '/auth/assets/well-be-right-back.webm') } else { $null }
        $portraitImage = if ($PortraitImagePath) { Split-HttpResponse (Send-PlainRequestBytes $port '/auth/assets/well-be-right-back-portrait.png') } else { $null }
        $portraitMp4 = if ($PortraitMp4Path) { Split-HttpResponse (Send-PlainRequestBytes $port '/auth/assets/well-be-right-back-portrait.mp4') } else { $null }
        $portraitWebm = if ($PortraitWebmPath) { Split-HttpResponse (Send-PlainRequestBytes $port '/auth/assets/well-be-right-back-portrait.webm') } else { $null }
        $pausedStatus = Split-HttpResponse (Send-PlainRequestBytes $port '/auth/stream-status')
        $proxy.ResumeForwarding()
        $resumedStatus = Split-HttpResponse (Send-PlainRequestBytes $port '/auth/stream-status')
        return @{ Page = $page; Mp4 = $mp4; Webm = $webm; PortraitImage = $portraitImage; PortraitMp4 = $portraitMp4; PortraitWebm = $portraitWebm; PausedStatus = $pausedStatus; ResumedStatus = $resumedStatus }
    }
    finally { try { $proxy.Stop() } catch {} }
}

$responses = Invoke-PausedProxyResponse $restartImagePath $restartMp4Path $restartWebmPath $restartPortraitImagePath $restartPortraitMp4Path $restartPortraitWebmPath
$imageResponse = $responses.Page
Assert-RestartImage $imageResponse.Header.StartsWith('HTTP/1.1 503 Service Unavailable') 'Paused proxy did not return HTTP 503.'
Assert-RestartImage ($imageResponse.Header -match '(?im)^Content-Type:\s*text/html; charset=utf-8\s*$') 'Paused proxy did not return the restart artwork in a message page.'
Assert-RestartImage ($imageResponse.Header -match '(?im)^Retry-After:\s*2\s*$') 'Paused proxy lost its retry guidance.'
Assert-RestartImage ($imageResponse.Header -match '(?im)^X-GStreamer-Glass-Forwarding-Paused:\s*1\s*$') 'Paused proxy lost the player-visible forwarding marker.'
Assert-RestartImage ($imageResponse.Header -notmatch '(?im)^Refresh:') 'Restart video is reset by a full-page Refresh header.'
$imageHtml = [System.Text.Encoding]::UTF8.GetString($imageResponse.Body)
Assert-RestartImage ($imageHtml.Contains('html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#000')) 'Restart message page does not enforce a black viewport.'
Assert-RestartImage ($imageHtml.Contains('video,picture,img{display:block;width:100vw;height:100vh;height:100dvh;background:#000}')) 'Restart message media is not sized to fill the viewport.'
Assert-RestartImage ($imageHtml.Contains('video,img{object-fit:cover;object-position:center')) 'Restart message media does not dynamically cover and remain centered in the viewport.'
Assert-RestartImage (-not $imageHtml.Contains('object-fit:contain')) 'Restart message media still uses letterboxed contain sizing.'
Assert-RestartImage ($imageHtml.Contains('<video autoplay muted loop playsinline preload="auto" poster="/auth/assets/well-be-right-back.png"')) 'Restart message page does not autoplay its looping video with the PNG poster.'
Assert-RestartImage ($imageHtml.Contains('<source src="/auth/assets/well-be-right-back.webm" type="video/webm">')) 'Restart message page does not prefer its WebM source.'
Assert-RestartImage ($imageHtml.Contains('<source src="/auth/assets/well-be-right-back.mp4" type="video/mp4">')) 'Restart message page does not offer its MP4 fallback.'
Assert-RestartImage ($imageHtml.Contains('data-portrait-poster="/auth/assets/well-be-right-back-portrait.png"')) 'Restart message page does not expose its portrait poster.'
Assert-RestartImage ($imageHtml.Contains('data-portrait-webm="/auth/assets/well-be-right-back-portrait.webm"')) 'Restart message page does not expose its portrait WebM.'
Assert-RestartImage ($imageHtml.Contains('data-portrait-mp4="/auth/assets/well-be-right-back-portrait.mp4"')) 'Restart message page does not expose its portrait MP4.'
Assert-RestartImage ($imageHtml.Contains("matchMedia('(orientation: portrait)')")) 'Restart message page does not detect portrait orientation.'
Assert-RestartImage ($imageHtml.Contains("q.addEventListener('change',rotate)")) 'Restart message page does not swap media after rotation.'
Assert-RestartImage ($imageHtml.Contains("fetch('/auth/stream-status?reload='")) 'Restart message page does not poll proxy forwarding state.'
Assert-RestartImage ($imageHtml.Contains('data-return="/live/"')) 'Restart message page does not retain the configured viewer mount.'
Assert-RestartImage ($imageHtml.Contains("'wakeLock' in navigator")) 'Restart message page does not request a screen wake lock.'
Assert-RestartImage ($imageHtml.Contains("'mediaSession' in navigator")) 'Restart message page does not present itself as active media.'
Assert-RestartImage ($imageResponse.Header -match "(?im)^Content-Security-Policy:.*media-src 'self' data:") 'Restart message page CSP blocks its videos.'
Assert-RestartImage ($imageResponse.Header -match "(?im)^Content-Security-Policy:.*connect-src 'self'") 'Restart message page CSP blocks its readiness poll.'
Assert-RestartImage ($imageResponse.Header -match "(?im)^Content-Security-Policy:.*script-src 'nonce-") 'Restart message page CSP does not authorize only its nonce script.'

$expectedMp4 = [System.IO.File]::ReadAllBytes($restartMp4Path)
$expectedWebm = [System.IO.File]::ReadAllBytes($restartWebmPath)
Assert-RestartImage ($responses.Mp4.Header -match '(?im)^Content-Type:\s*video/mp4\s*$') 'Restart MP4 asset route has the wrong content type.'
Assert-RestartImage ([Convert]::ToBase64String($responses.Mp4.Body) -eq [Convert]::ToBase64String($expectedMp4)) 'Restart MP4 asset route changed the configured bytes.'
Assert-RestartImage ($responses.Webm.Header -match '(?im)^Content-Type:\s*video/webm\s*$') 'Restart WebM asset route has the wrong content type.'
Assert-RestartImage ([Convert]::ToBase64String($responses.Webm.Body) -eq [Convert]::ToBase64String($expectedWebm)) 'Restart WebM asset route changed the configured bytes.'
$expectedPortraitImage = [System.IO.File]::ReadAllBytes($restartPortraitImagePath)
$expectedPortraitMp4 = [System.IO.File]::ReadAllBytes($restartPortraitMp4Path)
$expectedPortraitWebm = [System.IO.File]::ReadAllBytes($restartPortraitWebmPath)
Assert-RestartImage ($responses.PortraitImage.Header -match '(?im)^Content-Type:\s*image/png\s*$') 'Portrait restart image asset route has the wrong content type.'
Assert-RestartImage ([Convert]::ToBase64String($responses.PortraitImage.Body) -eq [Convert]::ToBase64String($expectedPortraitImage)) 'Portrait restart image asset route changed the configured bytes.'
Assert-RestartImage ($responses.PortraitMp4.Header -match '(?im)^Content-Type:\s*video/mp4\s*$') 'Portrait restart MP4 asset route has the wrong content type.'
Assert-RestartImage ([Convert]::ToBase64String($responses.PortraitMp4.Body) -eq [Convert]::ToBase64String($expectedPortraitMp4)) 'Portrait restart MP4 asset route changed the configured bytes.'
Assert-RestartImage ($responses.PortraitWebm.Header -match '(?im)^Content-Type:\s*video/webm\s*$') 'Portrait restart WebM asset route has the wrong content type.'
Assert-RestartImage ([Convert]::ToBase64String($responses.PortraitWebm.Body) -eq [Convert]::ToBase64String($expectedPortraitWebm)) 'Portrait restart WebM asset route changed the configured bytes.'
Assert-RestartImage ([System.Text.Encoding]::UTF8.GetString($responses.PausedStatus.Body).Contains('"forwardingPaused":true')) 'Stream-status endpoint did not report paused forwarding.'
Assert-RestartImage ([System.Text.Encoding]::UTF8.GetString($responses.ResumedStatus.Body).Contains('"forwardingPaused":false')) 'Stream-status endpoint did not report resumed forwarding.'

$customMountResponse = (Invoke-PausedProxyResponse -ImagePath $restartImagePath -Mp4Path $restartMp4Path -WebmPath $restartWebmPath -PortraitImagePath $restartPortraitImagePath -PortraitMp4Path $restartPortraitMp4Path -PortraitWebmPath $restartPortraitWebmPath -DirectoryRedirectPath '/watch').Page
$customMountHtml = [System.Text.Encoding]::UTF8.GetString($customMountResponse.Body)
Assert-RestartImage ($customMountHtml.Contains('data-return="/watch/"')) 'Restart page hardcodes the default viewer mount instead of using Web Player Hosting URL path.'

$fallbackResponse = (Invoke-PausedProxyResponse '').Page
$fallbackText = [System.Text.Encoding]::UTF8.GetString($fallbackResponse.Body)
Assert-RestartImage ($fallbackResponse.Header -match '(?im)^Content-Type:\s*text/plain; charset=utf-8\s*$') 'Missing restart artwork did not use the text fallback.'
Assert-RestartImage ($fallbackText -eq 'Stream is restarting.') 'Missing restart artwork changed the established fallback message.'

Write-Output 'Proxy restart video, readiness polling, packaged assets, and text fallback checks passed.'
