# SPDX-License-Identifier: AGPL-3.0-only

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$setupPath = Join-Path $repoRoot 'src\00-Setup.ps1'
$proxyStartupPath = Join-Path $repoRoot 'src\33-LetsEncrypt.ps1'
$restartImagePath = Join-Path $repoRoot 'gstwebrtc-api\dist\well-be-right-back.png'
$webUiManifestPath = Join-Path $repoRoot 'gstwebrtc-api\dist\gstglass-webui-manifest.json'

function Assert-RestartImage([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

Assert-RestartImage (Test-Path -LiteralPath $restartImagePath -PathType Leaf) 'The stream-restart image is missing.'

$proxyStartupSource = Get-Content -Raw -LiteralPath $proxyStartupPath
$webUiManifest = Get-Content -Raw -LiteralPath $webUiManifestPath | ConvertFrom-Json
Assert-RestartImage (@($webUiManifest.assets) -contains 'well-be-right-back.png') 'The packaged Web UI omits the stream-restart image.'
Assert-RestartImage ($proxyStartupSource.Contains("`$fileName = 'well-be-right-back.png'")) 'Proxy startup does not resolve the stream-restart image.'
Assert-RestartImage (($proxyStartupSource | Select-String -Pattern 'RestartImagePath\s*=\s*\$restartImagePath' -AllMatches).Matches.Count -eq 2) 'TLS and plaintext proxy families do not both pass the stream-restart image to the worker.'

$source = Get-Content -Raw -LiteralPath $setupPath
Assert-RestartImage ($source.Contains('$proxy.ConfigureRestartImage([string]$Command.RestartImagePath)')) 'The auth worker does not apply its configured stream-restart image.'
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

function Send-PlainRequestBytes([int]$Port) {
    $client = [System.Net.Sockets.TcpClient]::new('127.0.0.1', $Port)
    try {
        $stream = $client.GetStream()
        $request = [System.Text.Encoding]::ASCII.GetBytes("GET /live/ HTTP/1.1`r`nHost: localhost`r`nConnection: close`r`n`r`n")
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

function Invoke-PausedProxyResponse([string]$ImagePath, [string]$DirectoryRedirectPath = '/live') {
    $port = Get-FreeTcpPort
    $proxy = [TlsTerminatingProxy]::new()
    try {
        $proxy.ConfigureRestartImage($ImagePath)
        # Force the proxy to consume the request header before returning its
        # local response. Closing a Windows socket with unread request bytes can
        # generate an RST that discards an otherwise-valid response in transit.
        $proxy.DirectoryRedirectPath = $DirectoryRedirectPath
        $proxy.Start($port, '127.0.0.1', $port, $null)
        $proxy.PauseForwarding()
        Start-Sleep -Milliseconds 100
        return Split-HttpResponse (Send-PlainRequestBytes $port)
    }
    finally { try { $proxy.Stop() } catch {} }
}

$imageResponse = Invoke-PausedProxyResponse $restartImagePath
$expectedImage = [System.IO.File]::ReadAllBytes($restartImagePath)
Assert-RestartImage $imageResponse.Header.StartsWith('HTTP/1.1 503 Service Unavailable') 'Paused proxy did not return HTTP 503.'
Assert-RestartImage ($imageResponse.Header -match '(?im)^Content-Type:\s*text/html; charset=utf-8\s*$') 'Paused proxy did not return the restart artwork in a message page.'
Assert-RestartImage ($imageResponse.Header -match '(?im)^Retry-After:\s*2\s*$') 'Paused proxy lost its retry guidance.'
Assert-RestartImage ($imageResponse.Header -match '(?im)^Refresh:\s*2; url=/live/\s*$') 'Paused proxy does not retry the configured viewer mount.'
$imageHtml = [System.Text.Encoding]::UTF8.GetString($imageResponse.Body)
Assert-RestartImage ($imageHtml.Contains('html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#000')) 'Restart message page does not enforce a black viewport.'
Assert-RestartImage ($imageHtml.Contains('<meta http-equiv="refresh" content="2;url=/live/">')) 'Restart message page does not navigate back to the viewer mount.'
Assert-RestartImage ($imageHtml.Contains('data:image/png;base64,' + [Convert]::ToBase64String($expectedImage))) 'Restart message page does not contain the configured artwork.'
Assert-RestartImage ($imageResponse.Header -match "(?im)^Content-Security-Policy:.*img-src 'self' data:") 'Restart message page CSP blocks its embedded artwork.'

$customMountResponse = Invoke-PausedProxyResponse $restartImagePath '/watch'
$customMountHtml = [System.Text.Encoding]::UTF8.GetString($customMountResponse.Body)
Assert-RestartImage ($customMountResponse.Header -match '(?im)^Refresh:\s*2; url=/watch/\s*$') 'Paused proxy hardcodes the default viewer mount instead of using Web Player Hosting URL path.'
Assert-RestartImage ($customMountHtml.Contains('<meta http-equiv="refresh" content="2;url=/watch/">')) 'Restart page hardcodes the default viewer mount instead of using Web Player Hosting URL path.'

$fallbackResponse = Invoke-PausedProxyResponse ''
$fallbackText = [System.Text.Encoding]::UTF8.GetString($fallbackResponse.Body)
Assert-RestartImage ($fallbackResponse.Header -match '(?im)^Content-Type:\s*text/plain; charset=utf-8\s*$') 'Missing restart artwork did not use the text fallback.'
Assert-RestartImage ($fallbackText -eq 'Stream is restarting.') 'Missing restart artwork changed the established fallback message.'

Write-Output 'Proxy restart artwork and text fallback checks passed.'
