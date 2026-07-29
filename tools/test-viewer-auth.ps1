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
$transitionProxy = $null
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
    Assert-ViewerAuth ($response -match 'Location: /auth/login\?return=') 'Origin-level login redirect was missing.'

    $response = Send-TlsRequest $proxyPort "GET /auth/ HTTP/1.1`r`nHost: localhost`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 303') 'Unauthenticated /auth/ root was not handled by the gate.'
    Assert-ViewerAuth ($response -match '(?im)^Location: /auth/login\?return=%2Flive%2F\r?$') '/auth/ did not route an unauthenticated viewer to login.'

    $response = Send-TlsRequest $proxyPort "GET /auth/login?return=%2Flive%2F HTTP/1.1`r`nHost: localhost`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 200') 'Origin-level login route was not served.'
    Assert-ViewerAuth ($response -match 'type="password"') 'Login page password field was missing.'
    Assert-ViewerAuth ($response -match 'action="./login"') 'Login form did not preserve the /auth route.'

    $response = Send-TlsRequest $proxyPort "GET /__gstglass/auth/login?return=%2Flive%2F HTTP/1.1`r`nHost: localhost`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 200') 'Legacy root login alias was not served.'
    $response = Send-TlsRequest $proxyPort "GET /live/__gstglass/auth/login?return=%2Flive%2F HTTP/1.1`r`nHost: localhost`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 200') 'Legacy mounted login alias was not served.'

    $wrongBody = 'username=viewer&password=wrong-password&return=%2Flive%2F'
    $wrongLength = [System.Text.Encoding]::UTF8.GetByteCount($wrongBody)
    $response = Send-TlsRequest $proxyPort "POST /auth/login HTTP/1.1`r`nHost: localhost`r`nContent-Type: application/x-www-form-urlencoded`r`nContent-Length: $wrongLength`r`nConnection: close`r`n`r`n$wrongBody"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 401') 'Wrong password was not rejected.'

    $loginBody = 'username=viewer&password=glass-auth-test-password&return=%2Flive%2F'
    $loginLength = [System.Text.Encoding]::UTF8.GetByteCount($loginBody)
    $response = Send-TlsRequest $proxyPort "POST /auth/login HTTP/1.1`r`nHost: localhost`r`nContent-Type: application/x-www-form-urlencoded`r`nContent-Length: $loginLength`r`nConnection: close`r`n`r`n$loginBody"
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
    # Models the combined viewer/signaling listener: it owns the viewer auth
    # mount but has no DirectoryRedirectPath because GStreamer is its default
    # upstream on this shared external port.
    $secondProxy.AuthenticationMountPath = '/live'
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

    $response = Send-TlsRequest $proxyPort "GET /auth/login?return=https%3A%2F%2Fevil.example HTTP/1.1`r`nHost: localhost`r`nCookie: $cookiePair`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth ($response -match '(?im)^Location: /live/\r?$') 'External post-login redirect was not rejected.'

    # Authenticated requests must still be owned by the auth middleware. If
    # this endpoint falls through after login, GStreamer's static server
    # returns 404 and logout will be unreachable for the same reason.
    $response = Send-TlsRequest $proxyPort "GET /auth/login HTTP/1.1`r`nHost: localhost`r`nCookie: $cookiePair`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 303') 'Authenticated /auth/login endpoint fell through to the upstream.'
    Assert-ViewerAuth ($response -match '(?im)^Location: /live/\r?$') 'Authenticated /auth/login endpoint did not return to the viewer.'

    $response = Send-TlsRequest $proxyPort "GET /auth/ HTTP/1.1`r`nHost: localhost`r`nCookie: $cookiePair`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 303') 'Authenticated /auth/ root fell through to the upstream.'
    Assert-ViewerAuth ($response -match '(?im)^Location: /live/\r?$') 'Authenticated /auth/ root did not return to the viewer.'

    $response = Send-TlsRequest $proxyPort "GET /auth/not-a-real-endpoint HTTP/1.1`r`nHost: localhost`r`nCookie: $cookiePair`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 404') 'Unknown /auth/* path was not rejected locally.'
    Assert-ViewerAuth ($response -match 'Authentication endpoint not found') 'Unknown /auth/* path did not return the gate-owned response.'

    $logoutAssetUpstream = [ViewerAuthTestUpstream]::ServeOne($upstreamPort, 'logout-asset-ok')
    $response = Send-TlsRequest $secondProxyPort "GET /live/logout.js HTTP/1.1`r`nHost: stream.netlabwork.net:8889`r`nCookie: $cookiePair`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth ($response -match 'logout-asset-ok') 'Authenticated GET for the logout.js asset did not reach the web upstream.'
    Assert-ViewerAuth $logoutAssetUpstream.Result.StartsWith('GET /live/logout.js') 'Unexpected logout.js asset request reached the web upstream.'

    $response = Send-TlsRequest $secondProxyPort "GET /auth/logout?t=123456 HTTP/1.1`r`nHost: stream.netlabwork.net:8889`r`nCookie: $cookiePair`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 303') 'Origin-level logout endpoint did not redirect.'
    Assert-ViewerAuth ($response -match '(?im)^Set-Cookie: GstGlassAuth=;.*Max-Age=0') 'Logout did not expire the browser cookie.'
    Assert-ViewerAuth ($response -match '(?im)^Set-Cookie: GstGlassAuth=;.*Expires=Thu, 01 Jan 1970') 'Logout did not send an absolute cookie expiration.'
    Assert-ViewerAuth ($response -match '(?im)^Clear-Site-Data: "cookies", "storage"\r?$') 'Logout did not clear browser authentication state.'
    # Straight to login, not the viewer -- redirecting to the viewer first
    # just means that request immediately gets challenged and redirected to
    # login again anyway, a wasted extra round trip. The return target is
    # still the real viewer mount ("/live/"), not bare "/" -- nothing is
    # served at the site root, so re-logging in must not strand the viewer
    # on a blank/404 page.
    Assert-ViewerAuth ($response -match '(?im)^Location: /auth/login\?return=%2Flive%2F\r?$') 'Logout did not redirect straight to login with the viewer as the return target.'
    Assert-ViewerAuth ($response -notmatch '(?im)^Location: https?://') 'Logout redirect replaced the user-selected host or port.'
    $response = Send-TlsRequest $secondProxyPort "GET /live/ HTTP/1.1`r`nHost: localhost`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 303') 'Post-logout viewer request was not challenged for authentication.'
    Assert-ViewerAuth ($response -match 'Location: /auth/login\?return=') 'Post-logout viewer request did not redirect to the origin-level login route.'
    $response = Send-TlsRequest $proxyPort "GET /live/ HTTP/1.1`r`nHost: localhost`r`nCookie: $cookiePair`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 303') 'Logged-out session token remained valid.'

    # A listener can briefly have auth enforcement off while its generated
    # player config still exposes Sign out. The TLS edge must continue to own
    # logout so it never falls through to GStreamer's static-server 404.
    $transitionProxyPort = Get-FreeTcpPort
    $transitionProxy = [TlsTerminatingProxy]::new()
    $transitionProxy.AuthenticationMountPath = '/live'
    $transitionProxy.Start($transitionProxyPort, '127.0.0.1', $upstreamPort, $certificate)
    Start-Sleep -Milliseconds 50
    $response = Send-TlsRequest $transitionProxyPort "GET /auth/logout?t=123456 HTTP/1.1`r`nHost: live.netlabwork.net:8889`r`nCookie: GstGlassAuth=stale-token`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 303') 'Auth-transition logout route fell through to its upstream.'
    Assert-ViewerAuth ($response -match '(?im)^Set-Cookie: GstGlassAuth=;.*Max-Age=0') 'Auth-transition logout did not expire the browser cookie.'
    Assert-ViewerAuth ($response -match '(?im)^Location: /auth/login\?return=%2Flive%2F\r?$') 'Auth-transition logout did not redirect straight to login with the viewer as the return target.'
    $transitionProxy.Stop()
    $transitionProxy = $null

    # Real browsers keep an HTTP/1.1 connection alive by default (no explicit
    # Connection: close). This proxy only inspects the FIRST request on each
    # TCP connection before forwarding -- a naive implementation would let a
    # SECOND request reused on that same still-open connection ride straight
    # through to whatever upstream the first request picked, bypassing the
    # auth/routing gate entirely (this is exactly how /auth/logout started
    # 404ing in the field: it rode a kept-alive connection whose first
    # request had already been routed to the plain web upstream).
    $reuseValidation = [System.Net.Security.RemoteCertificateValidationCallback]{
        param($reuseSender, $reuseCertificate, $reuseChain, $reuseErrors)
        return $true
    }
    $reuseClient = [System.Net.Sockets.TcpClient]::new('127.0.0.1', $proxyPort)
    $reuseSsl = [System.Net.Security.SslStream]::new($reuseClient.GetStream(), $false, $reuseValidation)
    $reuseSsl.AuthenticateAsClient('localhost')
    $reuseFirstReq = "GET /live/ HTTP/1.1`r`nHost: localhost`r`nCookie: $cookiePair`r`n`r`n"
    $reuseFirstBytes = [System.Text.Encoding]::UTF8.GetBytes($reuseFirstReq)
    $reuseSsl.Write($reuseFirstBytes, 0, $reuseFirstBytes.Length)
    $reuseSsl.Flush()
    $reuseSsl.ReadTimeout = 3000
    $reuseBuf = New-Object byte[] 4096
    $null = $reuseSsl.Read($reuseBuf, 0, $reuseBuf.Length)
    Start-Sleep -Milliseconds 200
    $reuseBlocked = $false
    try {
        $reuseSecondReq = "GET /auth/logout HTTP/1.1`r`nHost: localhost`r`nCookie: $cookiePair`r`n`r`n"
        $reuseSecondBytes = [System.Text.Encoding]::UTF8.GetBytes($reuseSecondReq)
        $reuseSsl.Write($reuseSecondBytes, 0, $reuseSecondBytes.Length)
        $reuseSsl.Flush()
        $reuseSsl.ReadTimeout = 2000
        $reuseRead = $reuseSsl.Read($reuseBuf, 0, $reuseBuf.Length)
        $reuseBlocked = $reuseRead -le 0
    } catch { $reuseBlocked = $true }
    Assert-ViewerAuth $reuseBlocked 'A second request reused on the same kept-alive connection was not blocked -- it could bypass the auth/routing gate.'
    $reuseClient.Dispose()

    # Login again since the fresh-connection flow above just logged out.
    $response = Send-TlsRequest $proxyPort "POST /auth/login HTTP/1.1`r`nHost: localhost`r`nContent-Type: application/x-www-form-urlencoded`r`nContent-Length: $loginLength`r`nConnection: close`r`n`r`n$loginBody"
    $cookieHeader = ([regex]::Match($response, '(?im)^Set-Cookie:\s*(.+)$')).Groups[1].Value.Trim()
    $cookiePair = $cookieHeader.Split(';')[0]

    for ($attempt = 1; $attempt -le 5; $attempt++) {
        $response = Send-TlsRequest $proxyPort "POST /auth/login HTTP/1.1`r`nHost: localhost`r`nContent-Type: application/x-www-form-urlencoded`r`nContent-Length: $wrongLength`r`nConnection: close`r`n`r`n$wrongBody"
        Assert-ViewerAuth $response.StartsWith('HTTP/1.1 401') "Failed login attempt $attempt was not rejected."
    }
    $response = Send-TlsRequest $proxyPort "POST /auth/login HTTP/1.1`r`nHost: localhost`r`nContent-Type: application/x-www-form-urlencoded`r`nContent-Length: $wrongLength`r`nConnection: close`r`n`r`n$wrongBody"
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
    if ($transitionProxy) { $transitionProxy.Stop() }
    if ($secondProxy) { $secondProxy.Stop() }
    $proxy.Stop()
    $certificate.Dispose()
    $rsa.PersistKeyInCsp = $false
    $rsa.Dispose()
}
