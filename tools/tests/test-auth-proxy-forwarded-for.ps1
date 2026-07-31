# SPDX-License-Identifier: AGPL-3.0-only

# Focused plaintext integration coverage for trusted X-Forwarded-For handling.
# This deliberately avoids SChannel so it can run on hosts where the broader
# TLS integration test cannot create/use an ephemeral certificate.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$setupPath = Join-Path $repoRoot 'src\00-Setup.ps1'
$proxyPath = Join-Path $repoRoot 'src\33-LetsEncrypt.ps1'
$settingsPath = Join-Path $repoRoot 'src\24-Settings.ps1'
$uiPath = Join-Path $repoRoot 'src\90-MainWindow.ps1'
$setupSource = Get-Content -Raw -LiteralPath $setupPath

function Assert-ForwardedFor {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$marker = "if (-not ('TlsTerminatingProxy' -as [type])) {"
$blockStart = $setupSource.IndexOf($marker)
if ($blockStart -lt 0) { throw 'TlsTerminatingProxy block was not found.' }
$hereStart = $setupSource.IndexOf("@'", $blockStart) + 2
$hereEnd = $setupSource.IndexOf("'@", $hereStart)
if ($hereStart -lt 2 -or $hereEnd -lt 0) { throw 'TlsTerminatingProxy C# here-string was not found.' }
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

function New-Account {
    param([string]$Username, [string]$PasswordHash)
    $account = [TlsTerminatingProxy+AuthenticationAccount]::new()
    $account.Username = $Username
    $account.PasswordHash = $PasswordHash
    return $account
}

function New-LoginRequest {
    param([string]$Password, [string]$ForwardedFor)
    $body = 'username=viewer&password=' + [Uri]::EscapeDataString($Password) + '&return=%2Flive%2F'
    $forwardedHeader = if ([string]::IsNullOrWhiteSpace($ForwardedFor)) { '' } else { "X-Forwarded-For: $ForwardedFor`r`n" }
    return "POST /auth/login HTTP/1.1`r`nHost: localhost`r`n${forwardedHeader}Content-Type: application/x-www-form-urlencoded`r`nContent-Length: $([System.Text.Encoding]::UTF8.GetByteCount($body))`r`nConnection: close`r`n`r`n$body"
}

$password = 'forwarded-for-test-password'
$passwordHash = [TlsTerminatingProxy]::HashAuthenticationPassword($password)
$account = New-Account 'viewer' $passwordHash
$sessionKey = [TlsTerminatingProxy]::CreateAuthenticationSessionKey()
$failuresField = [TlsTerminatingProxy].GetField('authenticationFailures', [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Static)
$failures = $failuresField.GetValue($null)
$failures.Clear()

# An untrusted direct peer cannot forge its identity with XFF.
$untrustedProxy = [TlsTerminatingProxy]::new()
$untrustedPort = Get-FreeTcpPort
$untrustedProxy.ConfigureAuthentication($true, [TlsTerminatingProxy+AuthenticationAccount[]]@($account), $sessionKey, 12)
$untrustedProxy.ConfigureTrustedForwardingProxies([string[]]@('192.0.2.200'))
$untrustedProxy.Start($untrustedPort, '127.0.0.1', (Get-FreeTcpPort), $null)
Start-Sleep -Milliseconds 75
try {
    $response = Send-PlainRequest $untrustedPort (New-LoginRequest $password '198.51.100.99')
    Assert-ForwardedFor $response.StartsWith('HTTP/1.1 303') 'Untrusted-peer login did not succeed.'
    $messages = @()
    while ($message = $untrustedProxy.PollLogMessage()) { $messages += $message }
    Assert-ForwardedFor (($messages -join "`n") -match "authenticated from 127\.0\.0\.1") 'An untrusted peer was allowed to spoof its authentication log identity with XFF.'
    Assert-ForwardedFor (($messages -join "`n") -notmatch '198\.51\.100\.99') 'Spoofed XFF appeared as the effective client identity.'
}
finally { $untrustedProxy.Stop() }

# A trusted two-proxy chain resolves to the first untrusted client. Distinct
# clients must also receive distinct failure buckets instead of sharing the
# immediate proxy's address.
$trustedProxy = [TlsTerminatingProxy]::new()
$trustedPort = Get-FreeTcpPort
$trustedProxy.ConfigureAuthentication($true, [TlsTerminatingProxy+AuthenticationAccount[]]@($account), $sessionKey, 12)
$trustedProxy.ConfigureTrustedForwardingProxies([string[]]@('127.0.0.1', '127.0.0.2'))
$trustedProxy.Start($trustedPort, '127.0.0.1', (Get-FreeTcpPort), $null)
Start-Sleep -Milliseconds 75
try {
    $null = Send-PlainRequest $trustedPort (New-LoginRequest 'wrong-one' '198.51.100.10, 127.0.0.2')
    $null = Send-PlainRequest $trustedPort (New-LoginRequest 'wrong-two' '203.0.113.20, 127.0.0.2')
    $failureKeys = @($failures.Keys)
    Assert-ForwardedFor ($failureKeys -contains '198.51.100.10') 'First proxied client did not receive its own authentication failure bucket.'
    Assert-ForwardedFor ($failureKeys -contains '203.0.113.20') 'Second proxied client did not receive its own authentication failure bucket.'
    Assert-ForwardedFor ($failureKeys -notcontains '127.0.0.1') 'Proxied clients were still collapsed into the immediate proxy failure bucket.'

    $response = Send-PlainRequest $trustedPort (New-LoginRequest $password '198.51.100.10, 127.0.0.2')
    Assert-ForwardedFor $response.StartsWith('HTTP/1.1 303') 'Trusted-chain login did not succeed.'
    Assert-ForwardedFor (-not (@($failures.Keys) -contains '198.51.100.10')) 'Successful login did not clear only that proxied client failure bucket.'
    Assert-ForwardedFor (@($failures.Keys) -contains '203.0.113.20') 'Successful login cleared another proxied client failure bucket.'

    $messages = @()
    while ($message = $trustedProxy.PollLogMessage()) { $messages += $message }
    Assert-ForwardedFor (($messages -join "`n") -match "viewer 'viewer' authenticated from 198\.51\.100\.10") 'Trusted XFF client IP was not used in the authentication audit log.'
}
finally {
    $trustedProxy.Stop()
    $failures.Clear()
}

# Static wiring checks cover the GUI/settings/worker boundary that the direct
# class integration above intentionally bypasses.
$proxySource = Get-Content -Raw -LiteralPath $proxyPath
$settingsSource = Get-Content -Raw -LiteralPath $settingsPath
$uiSource = Get-Content -Raw -LiteralPath $uiPath
Assert-ForwardedFor ($uiSource -match 'lstViewerAuthenticationTrustedProxies') 'Trusted proxy list is not exposed in the GUI.'
Assert-ForwardedFor ($uiSource -match 'btnViewerAuthenticationTrustedProxyAdd') 'Trusted proxy Add button is missing.'
Assert-ForwardedFor ($uiSource -match 'btnViewerAuthenticationTrustedProxyRemove') 'Trusted proxy Remove button is missing.'
Assert-ForwardedFor ($uiSource -notmatch 'btnViewerAuthenticationTrustedProxy(?:Up|Down)') 'Trusted proxy list unexpectedly has ordering controls.'
Assert-ForwardedFor ($settingsSource -match 'ViewerAuthenticationTrustedProxies') 'Trusted proxy addresses are not persisted in settings.'
Assert-ForwardedFor (([regex]::Matches($proxySource, 'TrustedForwardingProxyAddresses')).Count -eq 2) 'Trusted proxy addresses are not sent to both auth proxy families.'
Assert-ForwardedFor ($setupSource -match 'ConfigureTrustedForwardingProxies\(\[string\[\]\]@\(\$Command\.TrustedForwardingProxyAddresses\)\)') 'Auth worker does not configure trusted forwarding peers on new proxy instances.'

$tokens = $null
$parseErrors = $null
$proxyAst = [System.Management.Automation.Language.Parser]::ParseFile($proxyPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors) { throw ($parseErrors | Out-String) }
foreach ($functionName in @(
    'ConvertTo-ViewerAuthenticationTrustedProxyAddresses',
    'Get-ViewerAuthenticationTrustedProxyAddresses',
    'Set-ViewerAuthenticationTrustedProxyAddresses'
)) {
    $definition = $proxyAst.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName
    }, $true)
    Assert-ForwardedFor ($null -ne $definition) "Trusted proxy UI function $functionName is missing."
    Invoke-Expression $definition.Extent.Text
}
Add-Type -AssemblyName System.Windows.Forms
$script:lstViewerAuthenticationTrustedProxies = New-Object System.Windows.Forms.ListBox
$script:txtViewerAuthenticationTrustedProxy = New-Object System.Windows.Forms.TextBox
Set-ViewerAuthenticationTrustedProxyAddresses -Value '172.16.80.1, ::ffff:127.0.0.1 172.16.80.1'
$normalizedTrustedProxies = @(Get-ViewerAuthenticationTrustedProxyAddresses)
Assert-ForwardedFor (($normalizedTrustedProxies -join ',') -eq '172.16.80.1,127.0.0.1') 'Trusted proxy UI input was not normalized and deduplicated.'
Assert-ForwardedFor ($lstViewerAuthenticationTrustedProxies.Items.Count -eq 2) 'Legacy trusted proxy string did not migrate into the visible list.'
$invalidRejected = $false
try { $null = @(ConvertTo-ViewerAuthenticationTrustedProxyAddresses -Value 'not-an-ip') }
catch { $invalidRejected = $true }
Assert-ForwardedFor $invalidRejected 'Invalid trusted proxy UI input was silently accepted.'

Write-Output 'Untrusted peers cannot spoof client identity through X-Forwarded-For.'
Write-Output 'Trusted proxy chains produce distinct audit and rate-limit identities per client.'
Write-Output 'Trusted proxy GUI/settings/worker wiring and validation checks passed.'
