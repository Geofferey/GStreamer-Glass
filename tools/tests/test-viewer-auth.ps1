# SPDX-License-Identifier: AGPL-3.0-only

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$setupPath = Join-Path $PSScriptRoot '..\..\src\00-Setup.ps1'
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

# Plaintext-auth counterpart to Send-TlsRequest -- no SslStream wrapping,
# used against a proxy started with a null certificate (see
# TlsTerminatingProxy.Start / "Allow plaintext auth").
function Send-PlainRequest {
    param([int]$Port, [string]$Request)

    $client = [System.Net.Sockets.TcpClient]::new('127.0.0.1', $Port)
    try {
        $stream = $client.GetStream()
        $requestBytes = [System.Text.Encoding]::UTF8.GetBytes($Request)
        $stream.Write($requestBytes, 0, $requestBytes.Length)
        $stream.Flush()

        $response = [System.IO.MemoryStream]::new()
        $buffer = New-Object byte[] 4096
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $response.Write($buffer, 0, $read)
        }
        return [System.Text.Encoding]::UTF8.GetString($response.ToArray())
    }
    finally {
        $client.Dispose()
    }
}

function New-TestAccount {
    param([string]$Username, [string]$PasswordHash, [string]$TotpSecret = '')
    $account = [TlsTerminatingProxy+AuthenticationAccount]::new()
    $account.Username = $Username
    $account.PasswordHash = $PasswordHash
    $account.TotpSecret = $TotpSecret
    return $account
}

# ComputeTotpCode/Base32Decode are private -- reflection is the only way to
# compute "the code a real authenticator app would show right now" without
# widening the class's public surface just for tests.
function Get-CurrentTotpCode {
    param([string]$Secret)
    $decodeMethod = [TlsTerminatingProxy].GetMethod('Base32Decode', [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Static)
    $computeMethod = [TlsTerminatingProxy].GetMethod('ComputeTotpCode', [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Static)
    $secretBytes = $decodeMethod.Invoke($null, @($Secret))
    $currentStep = [long]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() / 30)
    return $computeMethod.Invoke($null, @($secretBytes, $currentStep))
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
$multiAccountProxy = $null
$totpProxy = $null
$plaintextProxy = $null
$passwordHash = [TlsTerminatingProxy]::HashAuthenticationPassword('glass-auth-test-password')
$sessionKey = [TlsTerminatingProxy]::CreateAuthenticationSessionKey()
$accounts = [TlsTerminatingProxy+AuthenticationAccount[]]@((New-TestAccount 'viewer' $passwordHash))
$proxy.ConfigureAuthentication(
    $true,
    $accounts,
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
    $secondProxy.ConfigureAuthentication($true, $accounts, $sessionKey, 12)
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

    # This is one shared account with no per-user identity -- multiple
    # viewers can be signed in at once, each with their own independently
    # issued token. One viewer's logout must revoke only their own token,
    # never every other viewer's session table-wide.
    $response = Send-TlsRequest $proxyPort "POST /auth/login HTTP/1.1`r`nHost: localhost`r`nContent-Type: application/x-www-form-urlencoded`r`nContent-Length: $loginLength`r`nConnection: close`r`n`r`n$loginBody"
    $viewerACookie = (([regex]::Match($response, '(?im)^Set-Cookie:\s*(.+)$')).Groups[1].Value.Trim()).Split(';')[0]
    $response = Send-TlsRequest $proxyPort "POST /auth/login HTTP/1.1`r`nHost: localhost`r`nContent-Type: application/x-www-form-urlencoded`r`nContent-Length: $loginLength`r`nConnection: close`r`n`r`n$loginBody"
    $viewerBCookie = (([regex]::Match($response, '(?im)^Set-Cookie:\s*(.+)$')).Groups[1].Value.Trim()).Split(';')[0]
    Assert-ViewerAuth ($viewerACookie -ne $viewerBCookie) 'Two independent logins unexpectedly produced the same session token.'
    $response = Send-TlsRequest $proxyPort "GET /auth/logout HTTP/1.1`r`nHost: localhost`r`nCookie: $viewerACookie`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 303') 'Viewer A logout did not redirect.'
    $response = Send-TlsRequest $proxyPort "GET /live/ HTTP/1.1`r`nHost: localhost`r`nCookie: $viewerACookie`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 303') 'Viewer A session remained valid after their own logout.'
    $viewerBUpstream = [ViewerAuthTestUpstream]::ServeOne($upstreamPort, 'viewer-ok')
    $response = Send-TlsRequest $proxyPort "GET /live/ HTTP/1.1`r`nHost: localhost`r`nCookie: $viewerBCookie`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth ($response -match 'viewer-ok') 'Viewer B was signed out by Viewer A logging out -- logout must only revoke its own session.'
    Assert-ViewerAuth $viewerBUpstream.Result.StartsWith('GET /live/') 'Viewer B request did not reach the upstream as expected.'

    # True multi-user: two DISTINCT named accounts (not just two sessions
    # under one shared login). Each must only authenticate with its own
    # credentials, never the other's, and removing one account must revoke
    # only that account's own already-active session.
    $multiAccountProxyPort = Get-FreeTcpPort
    $multiAccountProxy = [TlsTerminatingProxy]::new()
    $alicePasswordHash = [TlsTerminatingProxy]::HashAuthenticationPassword('alice-test-password')
    $bobPasswordHash = [TlsTerminatingProxy]::HashAuthenticationPassword('bob-test-password')
    $multiAccountProxy.ConfigureAuthentication(
        $true,
        [TlsTerminatingProxy+AuthenticationAccount[]]@((New-TestAccount 'alice' $alicePasswordHash), (New-TestAccount 'bob' $bobPasswordHash)),
        $sessionKey,
        12
    )
    $multiAccountProxy.Start($multiAccountProxyPort, '127.0.0.1', $upstreamPort, $certificate)
    Start-Sleep -Milliseconds 50

    $aliceWrongBody = 'username=alice&password=bob-test-password&return=%2Flive%2F'
    $aliceWrongLength = [System.Text.Encoding]::UTF8.GetByteCount($aliceWrongBody)
    $response = Send-TlsRequest $multiAccountProxyPort "POST /auth/login HTTP/1.1`r`nHost: localhost`r`nContent-Type: application/x-www-form-urlencoded`r`nContent-Length: $aliceWrongLength`r`nConnection: close`r`n`r`n$aliceWrongBody"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 401') "Alice was authenticated using Bob's password."

    $aliceBody = 'username=alice&password=alice-test-password&return=%2Flive%2F'
    $aliceLength = [System.Text.Encoding]::UTF8.GetByteCount($aliceBody)
    $response = Send-TlsRequest $multiAccountProxyPort "POST /auth/login HTTP/1.1`r`nHost: localhost`r`nContent-Type: application/x-www-form-urlencoded`r`nContent-Length: $aliceLength`r`nConnection: close`r`n`r`n$aliceBody"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 303') "Alice was not authenticated with her own correct password."
    $aliceCookie = (([regex]::Match($response, '(?im)^Set-Cookie:\s*(.+)$')).Groups[1].Value.Trim()).Split(';')[0]

    $bobBody = 'username=bob&password=bob-test-password&return=%2Flive%2F'
    $bobLength = [System.Text.Encoding]::UTF8.GetByteCount($bobBody)
    $response = Send-TlsRequest $multiAccountProxyPort "POST /auth/login HTTP/1.1`r`nHost: localhost`r`nContent-Type: application/x-www-form-urlencoded`r`nContent-Length: $bobLength`r`nConnection: close`r`n`r`n$bobBody"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 303') "Bob was not authenticated with his own correct password."
    $bobCookie = (([regex]::Match($response, '(?im)^Set-Cookie:\s*(.+)$')).Groups[1].Value.Trim()).Split(';')[0]

    Assert-ViewerAuth ($aliceCookie -ne $bobCookie) "Alice and Bob unexpectedly received the same session token."

    # Removing Alice's account (reconfiguring with only Bob) must revoke
    # Alice's already-active session immediately, without touching Bob's.
    $multiAccountProxy.ConfigureAuthentication(
        $true,
        [TlsTerminatingProxy+AuthenticationAccount[]]@((New-TestAccount 'bob' $bobPasswordHash)),
        $sessionKey,
        12
    )
    $response = Send-TlsRequest $multiAccountProxyPort "GET /live/ HTTP/1.1`r`nHost: localhost`r`nCookie: $aliceCookie`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 303') "Removing Alice's account did not revoke her active session."
    $bobUpstream = [ViewerAuthTestUpstream]::ServeOne($upstreamPort, 'bob-still-ok')
    $response = Send-TlsRequest $multiAccountProxyPort "GET /live/ HTTP/1.1`r`nHost: localhost`r`nCookie: $bobCookie`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth ($response -match 'bob-still-ok') "Removing Alice's account incorrectly revoked Bob's unrelated session."
    Assert-ViewerAuth $bobUpstream.Result.StartsWith('GET /live/') "Bob's request did not reach the upstream as expected."
    $multiAccountProxy.Stop()
    $multiAccountProxy = $null

    # Optional per-account TOTP second factor (RFC 6238). An account with a
    # TotpSecret must never get a session from password alone; a wrong code
    # must never issue one either; a correct code must; and an account with
    # no TotpSecret must be completely unaffected (single-step login as before).
    $totpProxyPort = Get-FreeTcpPort
    $totpProxy = [TlsTerminatingProxy]::new()
    $totpPasswordHash = [TlsTerminatingProxy]::HashAuthenticationPassword('totp-test-password')
    $totpSecret = [TlsTerminatingProxy]::GenerateTotpSecret()
    $plainPasswordHash = [TlsTerminatingProxy]::HashAuthenticationPassword('plain-test-password')
    $totpProxy.ConfigureAuthentication(
        $true,
        [TlsTerminatingProxy+AuthenticationAccount[]]@(
            (New-TestAccount 'totp-viewer' $totpPasswordHash $totpSecret),
            (New-TestAccount 'plain-viewer' $plainPasswordHash)
        ),
        $sessionKey,
        12
    )
    $totpProxy.Start($totpProxyPort, '127.0.0.1', $upstreamPort, $certificate)
    Start-Sleep -Milliseconds 50

    $totpLoginBody = 'username=totp-viewer&password=totp-test-password&return=%2Flive%2F'
    $totpLoginLength = [System.Text.Encoding]::UTF8.GetByteCount($totpLoginBody)
    $response = Send-TlsRequest $totpProxyPort "POST /auth/login HTTP/1.1`r`nHost: localhost`r`nContent-Type: application/x-www-form-urlencoded`r`nContent-Length: $totpLoginLength`r`nConnection: close`r`n`r`n$totpLoginBody"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 200') 'Correct password for a 2FA account did not return the code-entry challenge.'
    Assert-ViewerAuth ($response -notmatch 'Set-Cookie') 'A session cookie was issued before the 2FA code was verified.'
    Assert-ViewerAuth ($response -match 'name="pending" value="([^"]+)"') 'Challenge page did not contain a pending token.'
    $totpPendingToken = [System.Uri]::UnescapeDataString(($Matches[1] -replace '&amp;', '&'))

    $wrongCodeBody = "pending=$([System.Uri]::EscapeDataString($totpPendingToken))&code=000000&return=%2Flive%2F"
    $wrongCodeLength = [System.Text.Encoding]::UTF8.GetByteCount($wrongCodeBody)
    $response = Send-TlsRequest $totpProxyPort "POST /auth/verify HTTP/1.1`r`nHost: localhost`r`nContent-Type: application/x-www-form-urlencoded`r`nContent-Length: $wrongCodeLength`r`nConnection: close`r`n`r`n$wrongCodeBody"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 401') 'A wrong 2FA code was accepted.'
    Assert-ViewerAuth ($response -notmatch 'Set-Cookie') 'A session cookie was issued for a wrong 2FA code.'

    $currentCode = Get-CurrentTotpCode $totpSecret
    $correctCodeBody = "pending=$([System.Uri]::EscapeDataString($totpPendingToken))&code=$currentCode&return=%2Flive%2F"
    $correctCodeLength = [System.Text.Encoding]::UTF8.GetByteCount($correctCodeBody)
    $response = Send-TlsRequest $totpProxyPort "POST /auth/verify HTTP/1.1`r`nHost: localhost`r`nContent-Type: application/x-www-form-urlencoded`r`nContent-Length: $correctCodeLength`r`nConnection: close`r`n`r`n$correctCodeBody"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 303') 'The correct 2FA code was not accepted.'
    $totpCookieHeader = ([regex]::Match($response, '(?im)^Set-Cookie:\s*(.+)$')).Groups[1].Value.Trim()
    Assert-ViewerAuth ($totpCookieHeader.Length -gt 0) 'No session cookie was issued after the correct 2FA code.'
    $totpCookiePair = $totpCookieHeader.Split(';')[0]
    $totpUpstream = [ViewerAuthTestUpstream]::ServeOne($upstreamPort, '2fa-session-ok')
    $response = Send-TlsRequest $totpProxyPort "GET /live/ HTTP/1.1`r`nHost: localhost`r`nCookie: $totpCookiePair`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth ($response -match '2fa-session-ok') 'The session issued after 2FA verification was not honored for a real request.'
    Assert-ViewerAuth $totpUpstream.Result.StartsWith('GET /live/') '2FA-authenticated request did not reach the upstream.'

    $wrongPasswordBody = 'username=totp-viewer&password=not-the-password&return=%2Flive%2F'
    $wrongPasswordLength = [System.Text.Encoding]::UTF8.GetByteCount($wrongPasswordBody)
    $response = Send-TlsRequest $totpProxyPort "POST /auth/login HTTP/1.1`r`nHost: localhost`r`nContent-Type: application/x-www-form-urlencoded`r`nContent-Length: $wrongPasswordLength`r`nConnection: close`r`n`r`n$wrongPasswordBody"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 401') 'A wrong password for a 2FA account was not rejected outright.'
    Assert-ViewerAuth ($response -notmatch 'name="pending"') 'A wrong password leaked a pending 2FA token.'

    $plainLoginBody = 'username=plain-viewer&password=plain-test-password&return=%2Flive%2F'
    $plainLoginLength = [System.Text.Encoding]::UTF8.GetByteCount($plainLoginBody)
    $response = Send-TlsRequest $totpProxyPort "POST /auth/login HTTP/1.1`r`nHost: localhost`r`nContent-Type: application/x-www-form-urlencoded`r`nContent-Length: $plainLoginLength`r`nConnection: close`r`n`r`n$plainLoginBody"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 303') 'An account with no TOTP secret was forced through the 2FA challenge.'
    Assert-ViewerAuth ($response -match 'Set-Cookie') 'An account with no TOTP secret did not get a session on the correct password alone.'
    $totpProxy.Stop()
    $totpProxy = $null

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

    # Plaintext auth (certificate = null): "Allow plaintext auth" runs the
    # exact same login/session/routing gate without a TLS handshake at all,
    # for when Glass's plain ports are reached directly (something else
    # terminates TLS, or the operator accepts the cleartext-cookie risk).
    # The critical, easy-to-get-wrong part is the session cookie: it must
    # NOT carry "Secure" here, or the browser would silently refuse to send
    # it back over the plain connection and every session would look
    # logged-out immediately after a successful login.
    # authenticationFailures is a static, process-wide, per-source-IP rate
    # limiter (intentional -- it must catch credential stuffing across every
    # exposed proxy, not just one). Every request in this whole suite comes
    # from 127.0.0.1, and the rate-limit test just above deliberately left
    # that IP rate-limited (429) as its last act -- without clearing it here,
    # every request below (even a correct login) would keep getting 429,
    # which would look like a plaintext-auth bug but isn't one.
    $failuresField = [TlsTerminatingProxy].GetField('authenticationFailures', [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Static)
    $failuresField.GetValue($null).Clear()

    $plaintextUpstreamPort = Get-FreeTcpPort
    $plaintextProxyPort = Get-FreeTcpPort
    $plaintextProxy = [TlsTerminatingProxy]::new()
    $plaintextProxy.ConfigureAuthentication($true, $accounts, $sessionKey, 12)
    $plaintextProxy.Start($plaintextProxyPort, '127.0.0.1', $plaintextUpstreamPort, $null)
    Start-Sleep -Milliseconds 100

    $response = Send-PlainRequest $plaintextProxyPort "GET / HTTP/1.1`r`nHost: localhost`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 303') 'Plaintext mode: unauthenticated viewer was not redirected.'
    Assert-ViewerAuth ($response -match 'Location: /auth/login\?return=') 'Plaintext mode: login redirect was missing.'

    # Wrong-password rejection/rate-limiting is identical shared code already
    # proven above against the TLS proxy (and rate-limiting is keyed by
    # source IP process-wide, so repeating it here from the same 127.0.0.1
    # would just hit the rate limit the earlier block already triggered,
    # not prove anything new) -- this section only covers what's actually
    # different in plaintext mode: no TLS handshake, and the cookie must
    # NOT be marked Secure.
    $response = Send-PlainRequest $plaintextProxyPort "POST /auth/login HTTP/1.1`r`nHost: localhost`r`nContent-Type: application/x-www-form-urlencoded`r`nContent-Length: $loginLength`r`nConnection: close`r`n`r`n$loginBody"
    Assert-ViewerAuth $response.StartsWith('HTTP/1.1 303') 'Plaintext mode: correct password was not accepted.'
    $plaintextCookieHeader = ([regex]::Match($response, '(?im)^Set-Cookie:\s*(.+)$')).Groups[1].Value.Trim()
    Assert-ViewerAuth ($plaintextCookieHeader -match 'HttpOnly') 'Plaintext mode: authentication cookie was not HttpOnly.'
    Assert-ViewerAuth ($plaintextCookieHeader -notmatch 'Secure') 'Plaintext mode: authentication cookie was marked Secure -- the browser would never send it back over this plain connection.'
    Assert-ViewerAuth ($plaintextCookieHeader -match 'SameSite=Strict') 'Plaintext mode: authentication cookie was not SameSite=Strict.'
    $plaintextCookiePair = $plaintextCookieHeader.Split(';')[0]

    $plaintextUpstream = [ViewerAuthTestUpstream]::ServeOne($plaintextUpstreamPort, 'plaintext-ok')
    $response = Send-PlainRequest $plaintextProxyPort "GET / HTTP/1.1`r`nHost: localhost`r`nCookie: $plaintextCookiePair`r`nConnection: close`r`n`r`n"
    Assert-ViewerAuth ($response -match 'plaintext-ok') 'Plaintext mode: an authenticated session was not let through to upstream.'
    Assert-ViewerAuth $plaintextUpstream.Result.StartsWith('GET /') 'Plaintext mode: unexpected request reached the upstream.'

    # DisconnectActiveConnections ("Keep auth on restarts"): a viewer's
    # already-open, pumping connection to upstream must be severed
    # promptly and cleanly on demand, without stopping the proxy's own
    # listener -- simulating "sever this viewer before we kill the real
    # GST process underneath it" during a restart.
    $disconnectUpstreamPort = Get-FreeTcpPort
    $disconnectProxyPort = Get-FreeTcpPort
    $disconnectProxy = [TlsTerminatingProxy]::new()
    $disconnectProxy.ConfigureAuthentication($true, $accounts, $sessionKey, 12)
    $disconnectUpstreamListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $disconnectUpstreamPort)
    $disconnectUpstreamListener.Start()
    $disconnectProxy.Start($disconnectProxyPort, '127.0.0.1', $disconnectUpstreamPort, $certificate)
    Start-Sleep -Milliseconds 100
    try {
        $disconnectAcceptTask = $disconnectUpstreamListener.AcceptTcpClientAsync()
        $disconnectValidation = [System.Net.Security.RemoteCertificateValidationCallback]{ param($s,$c,$ch,$e) return $true }
        $disconnectClient = [System.Net.Sockets.TcpClient]::new('127.0.0.1', $disconnectProxyPort)
        $disconnectSsl = [System.Net.Security.SslStream]::new($disconnectClient.GetStream(), $false, $disconnectValidation)
        $disconnectSsl.AuthenticateAsClient('localhost')
        $disconnectRequest = "GET /live/ HTTP/1.1`r`nHost: localhost`r`nCookie: $cookiePair`r`nConnection: Upgrade`r`nUpgrade: websocket`r`nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==`r`nSec-WebSocket-Version: 13`r`n`r`n"
        $disconnectRequestBytes = [System.Text.Encoding]::UTF8.GetBytes($disconnectRequest)
        $disconnectSsl.Write($disconnectRequestBytes, 0, $disconnectRequestBytes.Length)
        $disconnectSsl.Flush()

        # Bounded wait, not GetAwaiter().GetResult() -- fail fast with a
        # clear message rather than hang if the proxy never forwards.
        Assert-ViewerAuth ($disconnectAcceptTask.Wait(5000)) 'DisconnectActiveConnections setup: upstream never saw the forwarded connection.'
        $null = $disconnectAcceptTask.GetAwaiter().GetResult()
        Start-Sleep -Milliseconds 150

        $disconnectStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $disconnectProxy.DisconnectActiveConnections()
        $disconnectStopwatch.Stop()
        Assert-ViewerAuth ($disconnectStopwatch.ElapsedMilliseconds -lt 1000) "DisconnectActiveConnections took $($disconnectStopwatch.ElapsedMilliseconds) ms -- expected a near-instant local call."

        $disconnectSsl.ReadTimeout = 3000
        $disconnectBuffer = New-Object byte[] 4096
        $disconnectReadCount = -1
        try { $disconnectReadCount = $disconnectSsl.Read($disconnectBuffer, 0, $disconnectBuffer.Length) } catch { $disconnectReadCount = 0 }
        Assert-ViewerAuth ($disconnectReadCount -eq 0) 'Viewer connection was not closed by DisconnectActiveConnections.'

        # The proxy's own listener must still be alive afterward --
        # disconnecting active connections must never tear down the proxy
        # itself (that's the whole point of "Keep auth on restarts"). Stop
        # the manually-managed upstream listener FIRST -- ServeOne binds a
        # brand new TcpListener on the same port, and two listeners
        # contending for one port makes new connections behave
        # unpredictably (this is what looked like a hang here before).
        try { $disconnectUpstreamListener.Stop() } catch {}
        $disconnectSecondUpstream = [ViewerAuthTestUpstream]::ServeOne($disconnectUpstreamPort, 'still-listening-ok')
        $response = Send-TlsRequest $disconnectProxyPort "GET /live/ HTTP/1.1`r`nHost: localhost`r`nCookie: $cookiePair`r`nConnection: close`r`n`r`n"
        Assert-ViewerAuth ($response -match 'still-listening-ok') 'Proxy listener did not survive DisconnectActiveConnections.'
        $null = $disconnectSecondUpstream.Result
    }
    finally {
        try { $disconnectSsl.Dispose() } catch {}
        try { $disconnectClient.Dispose() } catch {}
        try { $disconnectProxy.Stop() } catch {}
        try { $disconnectUpstreamListener.Stop() } catch {}
    }

    # PauseForwarding/ResumeForwarding: the actual root cause of the
    # reported UI freeze. A plaintext-auth relay's external and internal
    # ports are the SAME number by design (transparent same-port takeover
    # -- no override field exists for this, unlike the TLS proxy, which
    # normally uses a different external port and never hits this). Its
    # external listener binds 0.0.0.0, which on Windows also answers a
    # loopback connect to that port when nothing is bound to 127.0.0.1
    # specifically (verified directly against a real TcpListener) -- so
    # while GST is briefly down mid-restart, this proxy's own attempt to
    # reach "127.0.0.1:samePort" could be accepted by its OWN listener,
    # forwarding the request back into itself and recursing without bound
    # (pegging a CPU core and making the whole host process, including
    # Glass's own UI thread, look hung). While paused, a request that
    # would otherwise be forwarded must get an immediate 503 instead of
    # ever attempting that connection.
    $pausePort = Get-FreeTcpPort
    $pauseProxy = [TlsTerminatingProxy]::new()
    $pauseProxy.ConfigureAuthentication($true, $accounts, $sessionKey, 12)
    # External == internal, same port number -- the exact same-port
    # transparent takeover Start-PlaintextAuthProxies uses. No upstream
    # listener is started at all: this simulates GST being down.
    $pauseProxy.Start($pausePort, '127.0.0.1', $pausePort, $null)
    Start-Sleep -Milliseconds 100
    try {
        $pauseLoginResponse = Send-PlainRequest $pausePort "POST /auth/login HTTP/1.1`r`nHost: localhost`r`nContent-Type: application/x-www-form-urlencoded`r`nContent-Length: $loginLength`r`nConnection: close`r`n`r`n$loginBody"
        Assert-ViewerAuth $pauseLoginResponse.StartsWith('HTTP/1.1 303') 'PauseForwarding setup: login did not succeed.'
        $pauseCookiePair = (([regex]::Match($pauseLoginResponse, '(?im)^Set-Cookie:\s*(.+)$')).Groups[1].Value.Trim()).Split(';')[0]

        $pauseProxy.PauseForwarding()
        $pauseStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $pauseResponse = Send-PlainRequest $pausePort "GET /live/ HTTP/1.1`r`nHost: localhost`r`nCookie: $pauseCookiePair`r`nConnection: close`r`n`r`n"
        $pauseStopwatch.Stop()
        Assert-ViewerAuth $pauseResponse.StartsWith('HTTP/1.1 503') 'Paused forwarding did not return 503 -- it may have attempted the unsafe same-port connection instead.'
        Assert-ViewerAuth ($pauseStopwatch.ElapsedMilliseconds -lt 2000) "Paused forwarding took $($pauseStopwatch.ElapsedMilliseconds) ms -- expected an immediate local response, not an attempted connection."
    }
    finally {
        try { $pauseProxy.Stop() } catch {}
    }

    'TLS authentication integration checks passed.'
}
catch {
    while ($message = $proxy.PollLogMessage()) {
        Write-Warning "TLS proxy: $message"
    }
    if ($plaintextProxy) {
        while ($message = $plaintextProxy.PollLogMessage()) {
            Write-Warning "Plaintext proxy: $message"
        }
    }
    throw
}
finally {
    if ($plaintextProxy) { $plaintextProxy.Stop() }
    if ($transitionProxy) { $transitionProxy.Stop() }
    if ($multiAccountProxy) { $multiAccountProxy.Stop() }
    if ($totpProxy) { $totpProxy.Stop() }
    if ($secondProxy) { $secondProxy.Stop() }
    $proxy.Stop()
    $certificate.Dispose()
    $rsa.PersistKeyInCsp = $false
    $rsa.Dispose()
}
