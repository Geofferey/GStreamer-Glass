# SPDX-License-Identifier: AGPL-3.0-only

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$setupPath = Join-Path $PSScriptRoot '..\src\00-Setup.ps1'
$source = Get-Content -Raw -LiteralPath $setupPath
$marker = "if (-not ('TlsTerminatingProxy' -as [type])) {"
$blockStart = $source.IndexOf($marker)
if ($blockStart -lt 0) { throw 'TlsTerminatingProxy block was not found.' }
$hereStart = $source.IndexOf("@'", $blockStart) + 2
$hereEnd = $source.IndexOf("'@", $hereStart)
if ($hereStart -lt 2 -or $hereEnd -lt 0) { throw 'TlsTerminatingProxy C# here-string was not found.' }
Add-Type -TypeDefinition $source.Substring($hereStart, $hereEnd - $hereStart) -ErrorAction Stop

if (-not ('ViewerAuthTestUpstream' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading.Tasks;

public static class ViewerAuthTestUpstream
{
    public static async Task<string> ServeOne(int port, string bodyText)
    {
        TcpListener listener = new TcpListener(IPAddress.Loopback, port);
        listener.Start();
        try
        {
            using (TcpClient client = await listener.AcceptTcpClientAsync())
            using (NetworkStream stream = client.GetStream())
            {
                MemoryStream request = new MemoryStream();
                byte[] one = new byte[1];
                byte[] terminator = new byte[] { 13, 10, 13, 10 };
                int matched = 0;
                while (request.Length < 16384)
                {
                    int read = await stream.ReadAsync(one, 0, 1);
                    if (read <= 0) break;
                    request.WriteByte(one[0]);
                    matched = one[0] == terminator[matched] ? matched + 1 : (one[0] == terminator[0] ? 1 : 0);
                    if (matched == terminator.Length) break;
                }

                byte[] body = Encoding.UTF8.GetBytes(bodyText);
                byte[] header = Encoding.ASCII.GetBytes(
                    "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: " +
                    body.Length + "\r\nConnection: close\r\n\r\n");
                await stream.WriteAsync(header, 0, header.Length);
                await stream.WriteAsync(body, 0, body.Length);
                return Encoding.ASCII.GetString(request.ToArray());
            }
        }
        finally
        {
            listener.Stop();
        }
    }
}
'@ -ErrorAction Stop
}

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}

function Send-TlsRequest {
    param([int]$Port, [string]$Request)

    $client = [System.Net.Sockets.TcpClient]::new('127.0.0.1', $Port)
    $validation = [System.Net.Security.RemoteCertificateValidationCallback]{
        param($sender, $certificate, $chain, $errors)
        return $true
    }
    $ssl = [System.Net.Security.SslStream]::new($client.GetStream(), $false, $validation)
    try {
        $ssl.AuthenticateAsClient('localhost')
        $requestBytes = [System.Text.Encoding]::UTF8.GetBytes($Request)
        $ssl.Write($requestBytes, 0, $requestBytes.Length)
        $ssl.Flush()

        $response = [System.IO.MemoryStream]::new()
        $buffer = New-Object byte[] 4096
        while (($read = $ssl.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $response.Write($buffer, 0, $read)
        }
        return [System.Text.Encoding]::UTF8.GetString($response.ToArray())
    }
    finally {
        $ssl.Dispose()
        $client.Dispose()
    }
}

function Assert-ViewerAuth {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$csp = [System.Security.Cryptography.CspParameters]::new(24)
$csp.KeyContainerName = 'GstGlassViewerAuthTest-' + [Guid]::NewGuid().ToString('N')
$rsa = [System.Security.Cryptography.RSACryptoServiceProvider]::new(2048, $csp)
$certificateRequest = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
    'CN=localhost',
    $rsa,
    [System.Security.Cryptography.HashAlgorithmName]::SHA256,
    [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
)
$certificate = $certificateRequest.CreateSelfSigned(
    [DateTimeOffset]::UtcNow.AddMinutes(-1),
    [DateTimeOffset]::UtcNow.AddDays(1)
)

$upstreamPort = Get-FreeTcpPort
$proxyPort = Get-FreeTcpPort
$proxy = [TlsTerminatingProxy]::new()
$secondProxy = $null
$passwordHash = [TlsTerminatingProxy]::HashAuthenticationPassword('glass-auth-test-password')
$sessionKey = [TlsTerminatingProxy]::CreateAuthenticationSessionKey()
$proxy.ConfigureAuthentication(
    $true,
    'viewer',
    $passwordHash,
    $sessionKey,
    12
)
$proxy.DirectoryRedirectPath = '/live'
$proxy.Start($proxyPort, '127.0.0.1', $upstreamPort, $certificate)
Start-Sleep -Milliseconds 100

try {
    $response = Send-TlsRequest $proxyPort "GET /live HTTP/1.1`r`nHost: localhost`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 301') 'Bare directory path was not redirected to add a trailing slash.'
    Assert-ViewerAuth ($response -match '(?im)^Location: /live/\r?$') 'Trailing-slash redirect target was wrong.'

    $response = Send-TlsRequest $proxyPort "GET /live?foo=bar HTTP/1.1`r`nHost: localhost`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth ($response -match '(?im)^Location: /live/\?foo=bar\r?$') 'Trailing-slash redirect did not preserve the query string.'

    $response = Send-TlsRequest $proxyPort "GET /live/ HTTP/1.1`r`nHost: localhost`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 303') 'Unauthenticated viewer was not redirected.'
    Assert-ViewerAuth ($response -match 'Location: /__gstglass/auth/login\?return=') 'Login redirect was missing.'

    $response = Send-TlsRequest $proxyPort "GET /__gstglass/auth/login?return=%2Flive%2F HTTP/1.1`r`nHost: localhost`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 200') 'Login page was not served.'
    Assert-ViewerAuth ($response -match 'type="password"') 'Login page password field was missing.'

    $wrongBody = 'username=viewer&password=wrong-password&return=%2Flive%2F'
    $wrongLength = [System.Text.Encoding]::UTF8.GetByteCount($wrongBody)
    $response = Send-TlsRequest $proxyPort "POST /__gstglass/auth/login HTTP/1.1`r`nHost: localhost`r`nContent-Type: application/x-www-form-urlencoded`r`nContent-Length: $wrongLength`r`nConnection: close`r`n`r`n$wrongBody"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 401') 'Wrong password was not rejected.'

    $loginBody = 'username=viewer&password=glass-auth-test-password&return=%2Flive%2F'
    $loginLength = [System.Text.Encoding]::UTF8.GetByteCount($loginBody)
    $response = Send-TlsRequest $proxyPort "POST /__gstglass/auth/login HTTP/1.1`r`nHost: localhost`r`nContent-Type: application/x-www-form-urlencoded`r`nContent-Length: $loginLength`r`nConnection: close`r`n`r`n$loginBody"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 303') 'Correct password was not accepted.'
    $cookieHeader = ([regex]::Match($response, '(?im)^Set-Cookie:\s*(.+)$')).Groups[1].Value.Trim()
    Assert-ViewerAuth ($cookieHeader -match 'HttpOnly') 'Authentication cookie was not HttpOnly.'
    Assert-ViewerAuth ($cookieHeader -match 'Secure') 'Authentication cookie was not Secure.'
    Assert-ViewerAuth ($cookieHeader -match 'SameSite=Strict') 'Authentication cookie was not SameSite=Strict.'
    $cookiePair = $cookieHeader.Split(';')[0]

    $viewerUpstream = [ViewerAuthTestUpstream]::ServeOne($upstreamPort, 'viewer-ok')
    $response = Send-TlsRequest $proxyPort "GET /live/ HTTP/1.1`r`nHost: localhost`r`nCookie: $cookiePair`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth ($response -match 'viewer-ok') 'Authorized viewer request did not reach the upstream.'
    Assert-ViewerAuth $viewerUpstream.Result.StartsWith('GET /live/') 'Unexpected authorized viewer request reached the upstream.'

    $secondProxyPort = Get-FreeTcpPort
    $secondProxy = [TlsTerminatingProxy]::new()
    $secondProxy.ConfigureAuthentication($true, 'viewer', $passwordHash, $sessionKey, 12)
    $secondProxy.Start($secondProxyPort, '127.0.0.1', $upstreamPort, $certificate)
    Start-Sleep -Milliseconds 50
    $secondUpstream = [ViewerAuthTestUpstream]::ServeOne($upstreamPort, 'second-port-ok')
    $response = Send-TlsRequest $secondProxyPort "GET / HTTP/1.1`r`nHost: localhost`r`nCookie: $cookiePair`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth ($response -match 'second-port-ok') 'Session cookie was not valid on the second TLS signaling port.'
    Assert-ViewerAuth $secondUpstream.Result.StartsWith('GET /') 'Unexpected request reached the second TLS signaling port.'

    $response = Send-TlsRequest $proxyPort "GET /live/GstSignal/video HTTP/1.1`r`nHost: localhost`r`nUpgrade: websocket`r`nConnection: Upgrade`r`nSec-WebSocket-Key: test`r`nSec-WebSocket-Version: 13`r`n`r`n"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 401') 'Unauthenticated WebSocket was not rejected.'

    $webSocketUpstream = [ViewerAuthTestUpstream]::ServeOne($upstreamPort, 'ws-ok')
    $response = Send-TlsRequest $proxyPort "GET /live/GstSignal/video HTTP/1.1`r`nHost: localhost`r`nCookie: $cookiePair`r`nUpgrade: websocket`r`nConnection: Upgrade`r`nSec-WebSocket-Key: test`r`nSec-WebSocket-Version: 13`r`n`r`n"
    Assert-ViewerAuth ($response -match 'ws-ok') 'Authorized WebSocket handshake did not reach the upstream.'
    Assert-ViewerAuth ($webSocketUpstream.Result -match 'Upgrade: websocket') 'WebSocket upgrade header was not forwarded.'

    $response = Send-TlsRequest $proxyPort "GET /__gstglass/auth/login?return=https%3A%2F%2Fevil.example HTTP/1.1`r`nHost: localhost`r`nCookie: $cookiePair`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth ($response -match '(?im)^Location: /live/\r?$') 'External post-login redirect was not rejected.'

    $response = Send-TlsRequest $proxyPort "GET /__gstglass/auth/logout/ HTTP/1.1`r`nHost: localhost`r`nCookie: $cookiePair`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 303') 'Logout (with a trailing slash) did not redirect.'
    Assert-ViewerAuth ($response -match '(?im)^Set-Cookie: GstGlassAuth=;.*Max-Age=0') 'Logout did not expire the browser cookie.'
    $response = Send-TlsRequest $proxyPort "GET /live/ HTTP/1.1`r`nHost: localhost`r`nCookie: $cookiePair`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 303') 'Logged-out session token remained valid.'

    for ($attempt = 1; $attempt -le 5; $attempt++) {
        $response = Send-TlsRequest $proxyPort "POST /__gstglass/auth/login HTTP/1.1`r`nHost: localhost`r`nContent-Type: application/x-www-form-urlencoded`r`nContent-Length: $wrongLength`r`nConnection: close`r`n`r`n$wrongBody"
        Assert-ViewerAuth $response.StartsWith('HTTP/1.1 401') "Failed login attempt $attempt was not rejected."
    }
    $response = Send-TlsRequest $proxyPort "POST /__gstglass/auth/login HTTP/1.1`r`nHost: localhost`r`nContent-Type: application/x-www-form-urlencoded`r`nContent-Length: $wrongLength`r`nConnection: close`r`n`r`n$wrongBody"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 429') 'Repeated failed logins were not rate-limited.'
    Assert-ViewerAuth ($response -match '(?im)^Retry-After:') 'Rate-limited response did not include Retry-After.'

    'TLS authentication integration checks passed.'
}
catch {
    while ($message = $proxy.PollLogMessage()) {
        Write-Warning "TLS proxy: $message"
    }
    throw
}
finally {
    if ($secondProxy) { $secondProxy.Stop() }
    $proxy.Stop()
    $certificate.Dispose()
    $rsa.PersistKeyInCsp = $false
    $rsa.Dispose()
}
