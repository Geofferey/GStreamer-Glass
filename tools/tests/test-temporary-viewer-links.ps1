# SPDX-License-Identifier: AGPL-3.0-only

# Plaintext integration coverage for temporary viewer links. Avoids SChannel
# so expiry, single-use consumption, revocation, and IP binding run reliably
# on both Windows PowerShell 5.1 and PowerShell 7 hosts.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$setupSource = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'src\00-Setup.ps1')
$proxySource = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'src\33-LetsEncrypt.ps1')
$settingsSource = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'src\24-Settings.ps1')
$uiSource = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'src\90-MainWindow.ps1')
$layoutSource = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'src\12-MainDashboardUi.ps1')

function Assert-TemporaryLink {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$marker = "if (-not ('TlsTerminatingProxy' -as [type])) {"
$blockStart = $setupSource.IndexOf($marker)
$hereStart = $setupSource.IndexOf("@'", $blockStart) + 2
$hereEnd = $setupSource.IndexOf("'@", $hereStart)
if ($blockStart -lt 0 -or $hereStart -lt 2 -or $hereEnd -lt 0) { throw 'TlsTerminatingProxy C# block was not found.' }
Add-Type -TypeDefinition $setupSource.Substring($hereStart, $hereEnd - $hereStart) -ErrorAction Stop

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}

function Send-PlainRequest {
    param([int]$Port, [string]$Request)
    $client = [System.Net.Sockets.TcpClient]::new('127.0.0.1', $Port)
    try {
        $stream = $client.GetStream()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Request)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
        $response = [System.IO.MemoryStream]::new()
        $buffer = New-Object byte[] 4096
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) { $response.Write($buffer, 0, $read) }
        return [System.Text.Encoding]::UTF8.GetString($response.ToArray())
    }
    finally { $client.Dispose() }
}

function Redeem-Link {
    param([int]$Port, [string]$Token, [string]$ForwardedFor = '')
    $xff = if ($ForwardedFor) { "X-Forwarded-For: $ForwardedFor`r`n" } else { '' }
    $target = '/auth/session?token=' + [Uri]::EscapeDataString($Token) + '&return=%2Flive%2F'
    return Send-PlainRequest $Port "GET $target HTTP/1.1`r`nHost: localhost`r`n${xff}Connection: close`r`n`r`n"
}

$account = [TlsTerminatingProxy+AuthenticationAccount]::new()
$account.Username = 'viewer'
$account.PasswordHash = [TlsTerminatingProxy]::HashAuthenticationPassword('temporary-link-test-password')
$proxy = [TlsTerminatingProxy]::new()
$proxy.ConfigureAuthentication($true, [TlsTerminatingProxy+AuthenticationAccount[]]@($account), [TlsTerminatingProxy]::CreateAuthenticationSessionKey(), 24)
$proxy.ConfigureTrustedForwardingProxies([string[]]@('127.0.0.1'))
$port = Get-FreeTcpPort
$proxy.Start($port, '127.0.0.1', (Get-FreeTcpPort), $null)
Start-Sleep -Milliseconds 75

try {
    $reusable = $proxy.CreateTemporaryAuthenticationLink('viewer', 5, $false, '')
    $response = Redeem-Link $port $reusable.Token
    Assert-TemporaryLink $response.StartsWith('HTTP/1.1 303') 'Reusable temporary link was not accepted.'
    $cookieHeader = ([regex]::Match($response, '(?im)^Set-Cookie:\s*(.+)$')).Groups[1].Value.Trim()
    $cookiePair = $cookieHeader.Split(';')[0]
    $maxAge = [int]([regex]::Match($cookieHeader, 'Max-Age=(\d+)').Groups[1].Value)
    Assert-TemporaryLink ($maxAge -gt 0 -and $maxAge -le 300) 'Temporary link issued a session beyond its own five-minute expiration.'

    $response = Redeem-Link $port $reusable.Token
    Assert-TemporaryLink $response.StartsWith('HTTP/1.1 303') 'Reusable temporary link could not be redeemed twice before expiration.'

    $response = Send-PlainRequest $port "GET /auth/status HTTP/1.1`r`nHost: localhost`r`nCookie: $cookiePair`r`nConnection: close`r`n`r`n"
    Assert-TemporaryLink ($response -match '\{"authenticated":true\}') 'Temporary-link session cookie did not authenticate the viewer.'

    $singleUse = $proxy.CreateTemporaryAuthenticationLink('viewer', 5, $true, '')
    $response = Redeem-Link $port $singleUse.Token
    Assert-TemporaryLink $response.StartsWith('HTTP/1.1 303') 'Single-use temporary link failed on first redemption.'
    $response = Redeem-Link $port $singleUse.Token
    Assert-TemporaryLink $response.StartsWith('HTTP/1.1 410') 'Single-use temporary link was accepted more than once.'

    $bound = $proxy.CreateTemporaryAuthenticationLink('viewer', 5, $false, '198.51.100.10')
    $response = Redeem-Link $port $bound.Token '203.0.113.20'
    Assert-TemporaryLink $response.StartsWith('HTTP/1.1 403') 'IP-restricted link accepted the wrong forwarded client.'
    $response = Redeem-Link $port $bound.Token '198.51.100.10'
    Assert-TemporaryLink $response.StartsWith('HTTP/1.1 303') 'IP-restricted link rejected its configured forwarded client.'
    $boundCookie = ([regex]::Match($response, '(?im)^Set-Cookie:\s*([^;]+)')).Groups[1].Value.Trim()

    $response = Send-PlainRequest $port "GET /auth/status HTTP/1.1`r`nHost: localhost`r`nX-Forwarded-For: 198.51.100.10`r`nCookie: $boundCookie`r`nConnection: close`r`n`r`n"
    Assert-TemporaryLink ($response -match '\{"authenticated":true\}') 'IP-bound session did not validate from its configured client.'
    $response = Send-PlainRequest $port "GET /auth/status HTTP/1.1`r`nHost: localhost`r`nX-Forwarded-For: 203.0.113.20`r`nCookie: $boundCookie`r`nConnection: close`r`n`r`n"
    Assert-TemporaryLink ($response -match '\{"authenticated":false\}') 'IP-bound session remained valid from a different client.'

    $exportedSessions = @($proxy.ExportActiveAuthenticationSessions())
    Assert-TemporaryLink (@($exportedSessions | Where-Object { $_.BoundAddress -eq '198.51.100.10' }).Count -ge 1) 'IP binding was not included in the persisted session state.'

    $persistedLink = $proxy.CreateTemporaryAuthenticationLink('viewer', 5, $false, '')
    $linkSnapshot = @($proxy.ExportTemporaryAuthenticationLinks())
    Assert-TemporaryLink ($proxy.RevokeTemporaryAuthenticationLink($persistedLink.Token)) 'Temporary-link revocation did not report success.'
    $response = Redeem-Link $port $persistedLink.Token
    Assert-TemporaryLink $response.StartsWith('HTTP/1.1 410') 'Revoked temporary link remained usable.'
    $proxy.RestoreTemporaryAuthenticationLinks([TlsTerminatingProxy+TemporaryAuthenticationLinkState[]]$linkSnapshot)
    $response = Redeem-Link $port $persistedLink.Token
    Assert-TemporaryLink $response.StartsWith('HTTP/1.1 303') 'Encrypted-state-compatible temporary-link restore did not reactivate the link.'
    $revokedCookie = ([regex]::Match($response, '(?im)^Set-Cookie:\s*([^;]+)')).Groups[1].Value.Trim()
    $revocation = $proxy.RevokeTemporaryAuthenticationLinkAndSessions($persistedLink.Token)
    Assert-TemporaryLink ([bool]$revocation.LinkRemoved) 'Active link revocation did not remove the bearer token.'
    Assert-TemporaryLink ([string]$revocation.Username -eq 'viewer') 'Active link revocation did not identify its viewer account.'
    Assert-TemporaryLink ([int]$revocation.SessionsRevoked -ge 1) 'Active link revocation did not invalidate the viewer account sessions.'
    $response = Send-PlainRequest $port "GET /auth/status HTTP/1.1`r`nHost: localhost`r`nCookie: $revokedCookie`r`nConnection: close`r`n`r`n"
    Assert-TemporaryLink ($response -match '\{"authenticated":false\}') 'A session issued by a revoked temporary link remained authenticated.'
    $replacementLink = $proxy.CreateTemporaryAuthenticationLink('viewer', 5, $false, '')
    Assert-TemporaryLink (-not [string]::IsNullOrWhiteSpace([string]$replacementLink.Token)) 'Revoking link sessions removed or disabled the underlying password account.'
}
finally {
    $proxy.Stop()
}

# Behavioral regression for the WinForms JIT crash caused by a synchronous
# SelectedIndexChanged event observing a transient/empty temporary-link row.
# Execute the real current helper body so this fails if a future edit again
# passes an empty token into Get-ViewerAuthenticationTemporaryLinkUrl.
function Get-FunctionDefinitionFromSource {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Name)
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Source, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "Could not parse source while locating ${Name}: $($errors[0].Message)" }
    $functionAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)
    if (-not $functionAst) { throw "Function '$Name' was not found in current source." }
    return $functionAst.Extent.Text
}

Add-Type -AssemblyName System.Windows.Forms
. ([scriptblock]::Create((Get-FunctionDefinitionFromSource -Source $proxySource -Name 'Show-SelectedViewerAuthenticationTemporaryLink')))

$lstViewerAuthenticationTemporaryLinks = New-Object System.Windows.Forms.ListBox
$txtViewerAuthenticationGeneratedTemporaryLink = New-Object System.Windows.Forms.TextBox
$script:UpdatingViewerAuthenticationTemporaryLinkList = $false
$script:TemporaryLinkUrlBuildCalls = 0
function Update-ViewerAuthenticationTemporaryLinkUi {}
function Append-Log { param([string]$Message) }
function Get-ViewerAuthenticationTemporaryLinkUrl {
    param([Parameter(Mandatory)][string]$Token)
    $script:TemporaryLinkUrlBuildCalls++
    return "https://viewer.example/auth/session?token=$Token"
}
$lstViewerAuthenticationTemporaryLinks.Add_SelectedIndexChanged({ Show-SelectedViewerAuthenticationTemporaryLink })

$script:ViewerAuthenticationTemporaryLinks = @([pscustomobject]@{ Token = '' })
[void]$lstViewerAuthenticationTemporaryLinks.Items.Add('transient row')
$selectionFailure = $null
try { $lstViewerAuthenticationTemporaryLinks.SelectedIndex = 0 }
catch { $selectionFailure = $_ }
Assert-TemporaryLink ($null -eq $selectionFailure) 'Selecting a transient row with an empty token escaped the WinForms event handler.'
Assert-TemporaryLink ($script:TemporaryLinkUrlBuildCalls -eq 0) 'The selection handler passed an empty token into the URL builder.'
Assert-TemporaryLink ([string]::IsNullOrEmpty($txtViewerAuthenticationGeneratedTemporaryLink.Text)) 'A transient row left a stale generated link visible.'

$lstViewerAuthenticationTemporaryLinks.SelectedIndex = -1
$script:ViewerAuthenticationTemporaryLinks = @([pscustomobject]@{ Token = 'valid-token' })
$lstViewerAuthenticationTemporaryLinks.SelectedIndex = 0
Assert-TemporaryLink ($script:TemporaryLinkUrlBuildCalls -eq 1) 'A valid selected temporary link did not reach the URL builder exactly once.'
Assert-TemporaryLink ($txtViewerAuthenticationGeneratedTemporaryLink.Text -match 'token=valid-token$') 'A valid selected temporary link was not displayed.'

# The worker must flatten dynamically-compiled C# link state into an ordinary
# PSCustomObject before JSON serialization; this is the contract that differs
# in the packaged Windows PowerShell host and produced blank/epoch UI rows.
. ([scriptblock]::Create((Get-FunctionDefinitionFromSource -Source $setupSource -Name 'ConvertTo-AuthProxyTemporaryLinkRecord')))
$ipcRecord = ConvertTo-AuthProxyTemporaryLinkRecord $reusable
$ipcRoundTrip = $ipcRecord | ConvertTo-Json -Compress | ConvertFrom-Json
Assert-TemporaryLink ($ipcRecord -is [pscustomobject]) 'The worker did not materialize temporary-link state as a host-independent PSCustomObject.'
Assert-TemporaryLink ([string]$ipcRoundTrip.Token -eq [string]$reusable.Token) 'The worker JSON contract lost the temporary-link token.'
Assert-TemporaryLink ([string]$ipcRoundTrip.Username -eq 'viewer') 'The worker JSON contract lost the temporary-link username.'
Assert-TemporaryLink ([long]$ipcRoundTrip.Expires -gt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) 'The worker JSON contract lost the temporary-link expiration.'

# A malformed response must be discarded instead of rendering a blank account
# with 1970/1969 epoch time. Drive the real synchronization function with the
# exact broken record shape seen in the packaged UI.
. ([scriptblock]::Create((Get-FunctionDefinitionFromSource -Source $proxySource -Name 'Sync-ViewerAuthenticationTemporaryLinks')))
$script:TemporaryLinkTestReply = [pscustomobject]@{
    Status = 'Ready'
    Error = ''
    TemporaryLinks = @([pscustomobject]@{ Token = ''; Username = ''; Expires = 0; SingleUse = $false; BoundAddress = '' })
}
$script:TemporaryLinkTestLogs = @()
function Test-AuthProxyWorkerRunning { return $true }
function Send-AuthProxyWorkerCommand { param($Command, [int]$TimeoutMs); return $script:TemporaryLinkTestReply }
function Append-Log { param([string]$Message); $script:TemporaryLinkTestLogs += $Message }
Sync-ViewerAuthenticationTemporaryLinks
Assert-TemporaryLink ($lstViewerAuthenticationTemporaryLinks.Items.Count -eq 0) 'A malformed temporary-link record rendered a permanent epoch row.'
Assert-TemporaryLink (@($script:ViewerAuthenticationTemporaryLinks).Count -eq 0) 'A malformed temporary-link record remained selectable in UI state.'
Assert-TemporaryLink (@($script:TemporaryLinkTestLogs | Where-Object { $_ -match 'discarded 1 malformed' }).Count -eq 1) 'Discarding a malformed worker link was not logged.'

$script:TemporaryLinkTestReply.TemporaryLinks = $null
$script:TemporaryLinkTestLogs = @()
Sync-ViewerAuthenticationTemporaryLinks
Assert-TemporaryLink (@($script:TemporaryLinkTestLogs | Where-Object { $_ -match 'discarded .* malformed' }).Count -eq 0) 'An empty/null worker link array emitted a false malformed-record warning.'

# Account list refreshes used to preserve only a prior selection, leaving the
# Generate button disabled after load even when exactly one account existed.
foreach ($name in @('Get-ViewerAuthenticationAccountLabel', 'Get-SelectedViewerAuthenticationUsername', 'Sync-ViewerAuthenticationAccountsListBox')) {
    . ([scriptblock]::Create((Get-FunctionDefinitionFromSource -Source $proxySource -Name $name)))
}
$lstViewerAuthenticationAccounts = New-Object System.Windows.Forms.ListBox
$script:ViewerAuthenticationAccounts = @([pscustomobject]@{ Username = 'viewer'; PasswordHash = 'test'; TotpSecret = '' })
Sync-ViewerAuthenticationAccountsListBox
Assert-TemporaryLink ($lstViewerAuthenticationAccounts.SelectedIndex -eq 0) 'The first viewer account was not selected automatically after list synchronization.'
Assert-TemporaryLink ((Get-SelectedViewerAuthenticationUsername) -eq 'viewer') 'Automatic account selection did not expose the viewer username to temporary-link generation.'

# The optional proxy-domain field changes only the origin of generated links.
# Bare host:port input defaults to HTTPS, explicit HTTP remains available, and
# blank input preserves the existing locally-derived viewer origin.
foreach ($name in @('Get-ViewerAuthenticationTemporaryLinkBaseUri', 'Get-ViewerAuthenticationTemporaryLinkUrl')) {
    . ([scriptblock]::Create((Get-FunctionDefinitionFromSource -Source $proxySource -Name $name)))
}
$txtViewerAuthenticationTemporaryLinkProxyDomain = New-Object System.Windows.Forms.TextBox
function Get-DirectWebRtcViewerUrl { return 'http://127.0.0.1:8889/live/?ignored=1' }
function Get-DirectWebRtcWebPathForTemporaryLink { return '/live/' }

$txtViewerAuthenticationTemporaryLinkProxyDomain.Text = 'live.netlabwork.net:8889'
$proxyUrl = [Uri](Get-ViewerAuthenticationTemporaryLinkUrl -Token 'proxy-token')
Assert-TemporaryLink ($proxyUrl.Scheme -eq 'https' -and $proxyUrl.Host -eq 'live.netlabwork.net' -and $proxyUrl.Port -eq 8889) 'A bare proxy domain did not replace the link origin using HTTPS.'
Assert-TemporaryLink ($proxyUrl.AbsolutePath -eq '/auth/session' -and $proxyUrl.Query -match 'token=proxy-token') 'Proxy-domain link generation changed the auth path or lost its token.'

$txtViewerAuthenticationTemporaryLinkProxyDomain.Text = 'http://stream.example.test:8080'
$proxyUrl = [Uri](Get-ViewerAuthenticationTemporaryLinkUrl -Token 'plaintext-token')
Assert-TemporaryLink ($proxyUrl.Scheme -eq 'http' -and $proxyUrl.Host -eq 'stream.example.test' -and $proxyUrl.Port -eq 8080) 'An explicitly plaintext proxy origin was not preserved.'

$txtViewerAuthenticationTemporaryLinkProxyDomain.Clear()
$proxyUrl = [Uri](Get-ViewerAuthenticationTemporaryLinkUrl -Token 'fallback-token')
Assert-TemporaryLink ($proxyUrl.Scheme -eq 'http' -and $proxyUrl.Host -eq '127.0.0.1' -and $proxyUrl.Port -eq 8889) 'Blank proxy domain did not preserve the existing viewer origin.'

$txtViewerAuthenticationTemporaryLinkProxyDomain.Text = 'ftp://invalid.example.test'
$invalidProxyRejected = $false
try { $null = Get-ViewerAuthenticationTemporaryLinkBaseUri }
catch { $invalidProxyRejected = $true }
Assert-TemporaryLink $invalidProxyRejected 'A non-HTTP(S) proxy domain was accepted for a viewer authentication link.'

Assert-TemporaryLink ($uiSource -match 'Generate temporary link') 'Temporary-link generation controls are missing from the UI.'
Assert-TemporaryLink ($uiSource -match 'Single-use link') 'Single-use option is missing from the UI.'
Assert-TemporaryLink ($layoutSource -match 'Proxy domain \(link only\)') 'The proxy-domain field is missing from the Viewer Authentication layout.'
Assert-TemporaryLink ($layoutSource -match 'Restrict to client IP') 'Client-IP restriction is missing from the Viewer Authentication layout.'
Assert-TemporaryLink ($settingsSource -match 'ViewerAuthenticationTemporaryLinkMinutes') 'Temporary-link defaults are not persisted.'
Assert-TemporaryLink ($settingsSource -match 'ViewerAuthenticationTemporaryLinkProxyDomain') 'The temporary-link proxy domain is not persisted.'
Assert-TemporaryLink ($proxySource -match "Type\s*=\s*'CreateTemporaryLink'") 'Temporary-link creation is not wired to the auth worker.'
Assert-TemporaryLink ($proxySource -match "Type\s*=\s*'RevokeTemporaryLink'") 'Temporary-link revocation is not wired to the auth worker.'

Write-Output 'Reusable, single-use, account-session revocation, expiry-bounded, and IP-bound temporary viewer links passed.'
Write-Output 'Temporary-link WinForms selection reentrancy regression passed.'
Write-Output 'Packaged-worker JSON, malformed epoch-row rejection, and automatic account selection passed.'
Write-Output 'Temporary-link proxy-domain origin override and fallback behavior passed.'
Write-Output 'Temporary-link worker persistence and Viewer Authentication UI wiring passed.'
