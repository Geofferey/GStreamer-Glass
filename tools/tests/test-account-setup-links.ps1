# SPDX-License-Identifier: AGPL-3.0-only

# End-to-end coverage for one-time viewer account setup/password-reset links.
# The test uses the plaintext proxy so it exercises the real HTTP handler,
# PBKDF2 password replacement, TOTP enrollment/preservation, purpose isolation,
# session revocation, and the worker-to-UI persistence payload without SChannel.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$setupSource = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'src\00-Setup.ps1')
$proxySource = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'src\33-LetsEncrypt.ps1')

function Assert-AccountSetupLink {
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

function ConvertTo-FormBody {
    param([hashtable]$Values)
    return (($Values.GetEnumerator() | ForEach-Object {
        [Uri]::EscapeDataString([string]$_.Key) + '=' + [Uri]::EscapeDataString([string]$_.Value)
    }) -join '&')
}

function Send-Form {
    param([int]$Port, [string]$Path, [hashtable]$Values, [string]$ForwardedFor = '')
    $body = ConvertTo-FormBody $Values
    $length = [System.Text.Encoding]::UTF8.GetByteCount($body)
    $xff = if ($ForwardedFor) { "X-Forwarded-For: $ForwardedFor`r`n" } else { '' }
    return Send-PlainRequest $Port "POST $Path HTTP/1.1`r`nHost: localhost`r`n${xff}Content-Type: application/x-www-form-urlencoded`r`nContent-Length: $length`r`nConnection: close`r`n`r`n$body"
}

function Open-SetupLink {
    param([int]$Port, [string]$Token)
    $target = '/auth/setup?token=' + [Uri]::EscapeDataString($Token) + '&return=%2Flive%2F'
    return Send-PlainRequest $Port "GET $target HTTP/1.1`r`nHost: localhost`r`nConnection: close`r`n`r`n"
}

function Submit-SetupLink {
    param([int]$Port, [string]$Token, [string]$Password, [string]$Confirmation = $Password, [string]$Code = '', [string]$ForwardedFor = '')
    return Send-Form $Port '/auth/setup' @{
        token = $Token
        return = '/live/'
        password = $Password
        confirm = $Confirmation
        code = $Code
    } $ForwardedFor
}

function Submit-Login {
    param([int]$Port, [string]$Username, [string]$Password)
    return Send-Form $Port '/auth/login' @{ username = $Username; password = $Password; return = '/live/' }
}

function Get-CurrentTotpCode {
    param([string]$Secret)
    $flags = [System.Reflection.BindingFlags]'NonPublic,Static'
    $decode = [TlsTerminatingProxy].GetMethod('Base32Decode', $flags)
    $compute = [TlsTerminatingProxy].GetMethod('ComputeTotpCode', $flags)
    $secretBytes = [byte[]]$decode.Invoke($null, @($Secret))
    $step = [long][Math]::Floor(([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) / 30.0)
    return [string]$compute.Invoke($null, @($secretBytes, $step))
}

$oldPassword = 'old-account-password-123!'
$account = [TlsTerminatingProxy+AuthenticationAccount]::new()
$account.Username = 'viewer'
$account.PasswordHash = [TlsTerminatingProxy]::HashAuthenticationPassword($oldPassword)
$account.TotpSecret = ''
$proxy = [TlsTerminatingProxy]::new()
$proxy.ConfigureAuthentication($true, [TlsTerminatingProxy+AuthenticationAccount[]]@($account), [TlsTerminatingProxy]::CreateAuthenticationSessionKey(), 24)
$proxy.ConfigureTrustedForwardingProxies([string[]]@('127.0.0.1'))
$port = Get-FreeTcpPort
$proxy.Start($port, '127.0.0.1', (Get-FreeTcpPort), $null)
Start-Sleep -Milliseconds 75

try {
    $setup = $proxy.CreateAuthenticationSetupLink('viewer', 5, $false, '')
    Assert-AccountSetupLink ([string]$setup.Purpose -eq 'setup' -and [bool]$setup.SingleUse) 'Account setup link was not purpose-tagged and forced single-use.'
    $response = Send-PlainRequest $port "HEAD /auth/setup?token=$([Uri]::EscapeDataString($setup.Token)) HTTP/1.1`r`nHost: localhost`r`nConnection: close`r`n`r`n"
    Assert-AccountSetupLink $response.StartsWith('HTTP/1.1 204') 'A setup-link preview HEAD request was not safely ignored.'
    $response = Open-SetupLink $port $setup.Token
    Assert-AccountSetupLink $response.StartsWith('HTTP/1.1 200') 'A valid account setup link did not show the setup form.'
    Assert-AccountSetupLink ($response -match 'autocomplete="new-password"' -and $response -match 'Set up viewer') 'Account setup form is missing its password enrollment fields.'
    Assert-AccountSetupLink ($response -match 'body\{margin:0;min-height:100vh;display:grid;place-items:center' -and $response -match 'main\{width:min\(92vw,420px\)') 'Account setup page drifted from the centered login-card layout.'
    Assert-AccountSetupLink ($response -notmatch '(?im)^Set-Cookie:') 'Opening an account setup link authenticated the viewer before completion.'

    $wrongPurposeTarget = '/auth/session?token=' + [Uri]::EscapeDataString($setup.Token) + '&return=%2Flive%2F'
    $response = Send-PlainRequest $port "GET $wrongPurposeTarget HTTP/1.1`r`nHost: localhost`r`nConnection: close`r`n`r`n"
    Assert-AccountSetupLink $response.StartsWith('HTTP/1.1 410') 'An account setup token was accepted by the temporary viewer-session endpoint.'
    $response = Submit-SetupLink $port $setup.Token 'new-account-password-456!' 'does-not-match'
    Assert-AccountSetupLink $response.StartsWith('HTTP/1.1 400') 'Mismatched setup passwords were accepted.'
    $response = Open-SetupLink $port $setup.Token
    Assert-AccountSetupLink $response.StartsWith('HTTP/1.1 200') 'A validation error consumed the one-time account setup link.'

    $newPassword = 'new-account-password-456!'
    $response = Submit-SetupLink $port $setup.Token $newPassword
    Assert-AccountSetupLink $response.StartsWith('HTTP/1.1 303') 'A valid password-only account setup was not completed.'
    $update = $proxy.PollAuthenticationAccountUpdate()
    Assert-AccountSetupLink ($null -ne $update -and [string]$update.Username -eq 'viewer') 'Completed setup did not enqueue a durable account update.'
    Assert-AccountSetupLink ([TlsTerminatingProxy]::IsAuthenticationPasswordHashValid([string]$update.PasswordHash)) 'Account setup returned an invalid derived password hash.'
    Assert-AccountSetupLink ([string]$update.PasswordHash -notmatch [regex]::Escape($newPassword)) 'Plaintext password leaked into the account update payload.'
    $response = Submit-SetupLink $port $setup.Token $newPassword
    Assert-AccountSetupLink $response.StartsWith('HTTP/1.1 410') 'A completed account setup link was usable twice.'
    $response = Submit-Login $port 'viewer' $oldPassword
    Assert-AccountSetupLink $response.StartsWith('HTTP/1.1 401') 'The old password still authenticated after account setup.'
    $response = Submit-Login $port 'viewer' $newPassword
    Assert-AccountSetupLink $response.StartsWith('HTTP/1.1 303') 'The password established through the setup link did not authenticate.'

    # Requiring new 2FA embeds a fresh enrollment secret in the protected link
    # state and accepts the change only after a matching current code.
    $totpSetup = $proxy.CreateAuthenticationSetupLink('viewer', 5, $true, '')
    Assert-AccountSetupLink ([bool]$totpSetup.RequireTotp -and -not [string]::IsNullOrWhiteSpace([string]$totpSetup.TotpSecret)) '2FA-required setup link has no enrollment secret.'
    $response = Open-SetupLink $port $totpSetup.Token
    Assert-AccountSetupLink ($response -match [regex]::Escape([string]$totpSetup.TotpSecret)) 'The setup page did not display its new authenticator secret.'
    Assert-AccountSetupLink ($response -match '<code class="uri"><a href="otpauth://totp/') 'The boxed authenticator URI is not a clickable otpauth link.'
    $response = Submit-SetupLink $port $totpSetup.Token 'totp-account-password-789!' -Code '000000'
    Assert-AccountSetupLink $response.StartsWith('HTTP/1.1 401') 'A wrong new-enrollment TOTP code was accepted.'
    $totpCode = Get-CurrentTotpCode $totpSetup.TotpSecret
    $response = Submit-SetupLink $port $totpSetup.Token 'totp-account-password-789!' -Code $totpCode
    Assert-AccountSetupLink $response.StartsWith('HTTP/1.1 303') 'A correct new-enrollment TOTP code was rejected.'
    $totpUpdate = $proxy.PollAuthenticationAccountUpdate()
    Assert-AccountSetupLink ([string]$totpUpdate.TotpSecret -eq [string]$totpSetup.TotpSecret) 'Fresh 2FA enrollment was not returned for persistence.'

    # A later password-only setup must preserve existing 2FA and require its
    # current code; the link is authorization to reset the password, not an
    # implicit switch for bypassing or disabling a configured second factor.
    $preserveSetup = $proxy.CreateAuthenticationSetupLink('viewer', 5, $false, '')
    $response = Open-SetupLink $port $preserveSetup.Token
    Assert-AccountSetupLink ($response -match 'existing two-factor enrollment will be preserved') 'Existing 2FA was not identified on a password-only setup page.'
    $response = Submit-SetupLink $port $preserveSetup.Token 'preserved-totp-password-012!'
    Assert-AccountSetupLink $response.StartsWith('HTTP/1.1 401') 'Password-only setup bypassed an existing TOTP enrollment.'
    $totpCode = Get-CurrentTotpCode $totpSetup.TotpSecret
    $response = Submit-SetupLink $port $preserveSetup.Token 'preserved-totp-password-012!' -Code $totpCode
    Assert-AccountSetupLink $response.StartsWith('HTTP/1.1 303') 'Existing TOTP could not authorize a password-only setup.'
    $preservedUpdate = $proxy.PollAuthenticationAccountUpdate()
    Assert-AccountSetupLink ([string]$preservedUpdate.TotpSecret -eq [string]$totpSetup.TotpSecret) 'Password-only setup replaced or disabled existing 2FA.'

    # Purpose and 2FA enrollment state must survive the same DPAPI-cache model
    # used for viewer links (the class-level export/restore contract tested here).
    $persistedSetup = $proxy.CreateAuthenticationSetupLink('viewer', 5, $true, '198.51.100.10')
    $snapshot = @($proxy.ExportTemporaryAuthenticationLinks())
    Assert-AccountSetupLink ($proxy.RevokeTemporaryAuthenticationLink($persistedSetup.Token)) 'Setup link could not be revoked before restore testing.'
    $proxy.RestoreTemporaryAuthenticationLinks([TlsTerminatingProxy+TemporaryAuthenticationLinkState[]]$snapshot)
    $restored = @($proxy.ExportTemporaryAuthenticationLinks()) | Where-Object { $_.Token -eq $persistedSetup.Token } | Select-Object -First 1
    Assert-AccountSetupLink ($null -ne $restored -and [string]$restored.Purpose -eq 'setup' -and [bool]$restored.RequireTotp) 'Setup-link purpose or 2FA requirement was lost during restore.'
    Assert-AccountSetupLink ([string]$restored.TotpSecret -eq [string]$persistedSetup.TotpSecret) 'Setup-link TOTP enrollment secret was lost during restore.'
    $response = Submit-SetupLink $port $persistedSetup.Token 'ip-bound-password-345!' -Code (Get-CurrentTotpCode $persistedSetup.TotpSecret) -ForwardedFor '203.0.113.20'
    Assert-AccountSetupLink $response.StartsWith('HTTP/1.1 403') 'IP-bound account setup accepted the wrong client.'
}
finally {
    $proxy.Stop()
}

# Exercise the actual UI-side persistence consumer with a worker-shaped update.
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

. ([scriptblock]::Create((Get-FunctionDefinitionFromSource -Source $proxySource -Name 'Drain-LetsEncryptTlsProxyLogs')))
$uiPasswordHash = [TlsTerminatingProxy]::HashAuthenticationPassword('ui-persisted-password-678!')
$script:AuthProxyWorkerCommandInFlight = $false
$script:LetsEncryptTlsProxies = @([pscustomobject]@{ Label = 'test' })
$script:PlaintextAuthProxies = @()
$script:ViewerAuthenticationAccounts = @([pscustomobject]@{ Username = 'viewer'; PasswordHash = 'old'; TotpSecret = '' })
$script:UiSaveCalls = 0
$script:UiAccountSyncCalls = 0
$script:UiLinkSyncCalls = 0
function Test-AuthProxyWorkerRunning { return $true }
function Send-AuthProxyWorkerCommand {
    param($Command, [int]$TimeoutMs, [switch]$NoUiPump)
    return [pscustomobject]@{
        Status = 'Ready'
        Messages = @()
        AccountUpdates = @([pscustomobject]@{ Username = 'viewer'; PasswordHash = $uiPasswordHash; TotpSecret = 'TESTSECRET'; SessionsRevoked = 2 })
    }
}
function Append-Log { param([string]$Message) }
function Sync-ViewerAuthenticationAccountsListBox { $script:UiAccountSyncCalls++ }
function Sync-ViewerAuthenticationTemporaryLinks { $script:UiLinkSyncCalls++ }
function Save-Settings { $script:UiSaveCalls++ }
Drain-LetsEncryptTlsProxyLogs
Assert-AccountSetupLink ([string]$script:ViewerAuthenticationAccounts[0].PasswordHash -eq $uiPasswordHash) 'UI did not accept the worker-derived password hash.'
Assert-AccountSetupLink ([string]$script:ViewerAuthenticationAccounts[0].TotpSecret -eq 'TESTSECRET') 'UI did not accept the worker TOTP enrollment update.'
Assert-AccountSetupLink ($script:UiSaveCalls -eq 1 -and $script:UiAccountSyncCalls -eq 1 -and $script:UiLinkSyncCalls -eq 1) 'UI did not save and refresh exactly once after a completed account setup.'

Assert-AccountSetupLink ($proxySource -match "Type\s*=\s*'CreateAccountSetupLink'") 'Auth worker lacks the account setup link command.'
Assert-AccountSetupLink ($proxySource -match 'AccountUpdates') 'Auth worker does not return completed credential updates to the UI.'
Write-Output 'One-time account password setup, purpose isolation, password replacement, and UI persistence passed.'
Write-Output 'New 2FA enrollment, existing 2FA preservation, IP restriction, and setup-link restore passed.'
