# SPDX-License-Identifier: AGPL-3.0-only

# Exercises the auth worker through the actual packaged PS2EXE host. Console
# PowerShell does not always expose public fields from dynamically compiled CLR
# types the same way, which previously produced blank temporary-link records
# and a Unix-epoch expiration in the UI despite source-level tests passing.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ExecutablePath
)

$ErrorActionPreference = 'Stop'
$ExecutablePath = (Resolve-Path -LiteralPath $ExecutablePath).Path
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$rejectionImagePath = Join-Path $repoRoot 'gstwebrtc-api\dist\temporary-viewer-link-unavailable.png'

function Assert-CompiledTemporaryLink {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-FreeTcpPort {
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}

function Send-PlainRequest {
    param([int]$Port, [string]$Request)
    $client = New-Object System.Net.Sockets.TcpClient('127.0.0.1', $Port)
    try {
        $stream = $client.GetStream()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Request)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
        $response = New-Object System.IO.MemoryStream
        $buffer = New-Object byte[] 4096
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) { $response.Write($buffer, 0, $read) }
        return [System.Text.Encoding]::UTF8.GetString($response.ToArray())
    }
    finally { $client.Dispose() }
}

$pipeName = 'gstglass-auth-link-smoke-' + [Guid]::NewGuid().ToString('N')
$pipe = $null
$reader = $null
$writer = $null
$worker = $null

function Send-WorkerCommand {
    param([Parameter(Mandatory)]$Command)
    $writer.WriteLine(($Command | ConvertTo-Json -Compress -Depth 8))
    $readTask = $reader.ReadLineAsync()
    if (-not $readTask.Wait(10000)) { throw "Compiled auth worker timed out handling '$($Command.Type)'." }
    if ([string]::IsNullOrWhiteSpace([string]$readTask.Result)) { throw "Compiled auth worker closed the pipe handling '$($Command.Type)'." }
    return $readTask.Result | ConvertFrom-Json
}

try {
    $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(
        '.',
        $pipeName,
        [System.IO.Pipes.PipeDirection]::InOut,
        [System.IO.Pipes.PipeOptions]::None
    )
    $worker = Start-Process `
        -FilePath $ExecutablePath `
        -ArgumentList @('-AuthProxyWorker', '-AuthProxyWorkerPipe', $pipeName) `
        -WindowStyle Hidden `
        -PassThru
    $pipe.Connect(10000)
    $reader = New-Object System.IO.StreamReader($pipe, [System.Text.Encoding]::UTF8, $false, 4096, $true)
    $writer = New-Object System.IO.StreamWriter($pipe, (New-Object System.Text.UTF8Encoding($false)), 4096, $true)
    $writer.AutoFlush = $true

    $sessionKey = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($sessionKey)
    $externalPort = Get-FreeTcpPort
    $internalPort = Get-FreeTcpPort
    $startReply = Send-WorkerCommand @{
        Type = 'StartFamily'
        Family = 'Plaintext'
        CertificatePfxBase64 = ''
        AuthenticationEnabled = $true
        AuthenticationMountPath = '/live'
        TemporaryLinkUnavailableImagePath = $rejectionImagePath
        TrustedForwardingProxyAddresses = @()
        Accounts = @(@{ Username = 'viewer'; PasswordHash = 'compiled-smoke-placeholder'; TotpSecret = '' })
        SessionKeyBase64 = [Convert]::ToBase64String($sessionKey)
        SessionHours = 12
        Ports = @(@{
            Label = 'compiled temporary-link smoke'
            ExternalPort = $externalPort
            InternalPort = $internalPort
            DirectoryRedirectPath = '/live'
            PathRoutes = @()
        })
    }
    Assert-CompiledTemporaryLink ([string]$startReply.Status -eq 'Ready') "Compiled auth worker failed to start: $($startReply.Error)"

    $createReply = Send-WorkerCommand @{ Type = 'CreateTemporaryLink'; Username = 'viewer'; DurationMinutes = 5; SingleUse = $false; BoundAddress = '' }
    Assert-CompiledTemporaryLink ([string]$createReply.Status -eq 'Ready') "Compiled auth worker failed to create a link: $($createReply.Error)"
    Assert-CompiledTemporaryLink (-not [string]::IsNullOrWhiteSpace([string]$createReply.Link.Token)) 'Compiled auth worker returned an empty temporary-link token.'
    Assert-CompiledTemporaryLink ([string]$createReply.Link.Username -eq 'viewer') 'Compiled auth worker returned an empty or incorrect temporary-link username.'
    Assert-CompiledTemporaryLink ([long]$createReply.Link.Expires -gt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) 'Compiled auth worker returned a Unix-epoch temporary-link expiration.'
    Assert-CompiledTemporaryLink (-not [bool]$createReply.Link.SingleUse) 'Compiled auth worker changed the reusable-link flag.'

    $redeemTarget = '/auth/session?token=' + [Uri]::EscapeDataString([string]$createReply.Link.Token) + '&return=%2Flive%2F'
    $previewResponse = Send-PlainRequest $externalPort "HEAD $redeemTarget HTTP/1.1`r`nHost: localhost`r`nConnection: close`r`n`r`n"
    Assert-CompiledTemporaryLink $previewResponse.StartsWith('HTTP/1.1 204') 'Compiled auth worker did not safely ignore a HEAD preview probe.'
    $previewResponse = Send-PlainRequest $externalPort "GET $redeemTarget HTTP/1.1`r`nHost: localhost`r`nConnection: close`r`n`r`n"
    Assert-CompiledTemporaryLink $previewResponse.StartsWith('HTTP/1.1 200') 'Compiled auth worker did not return the preview-safe confirmation page.'
    Assert-CompiledTemporaryLink ($previewResponse -match '(?im)^X-Robots-Tag:\s*noindex, nofollow, noarchive, nosnippet, noimageindex\s*$') 'Compiled auth worker confirmation page is indexable.'
    Assert-CompiledTemporaryLink ($previewResponse -notmatch '(?im)^Set-Cookie:') 'Compiled auth worker consumed a temporary link during GET preview.'
    $redeemBody = 'token=' + [Uri]::EscapeDataString([string]$createReply.Link.Token) + '&return=%2Flive%2F'
    $redeemLength = [System.Text.Encoding]::UTF8.GetByteCount($redeemBody)
    $redeemResponse = Send-PlainRequest $externalPort "POST /auth/session HTTP/1.1`r`nHost: localhost`r`nContent-Type: application/x-www-form-urlencoded`r`nContent-Length: $redeemLength`r`nConnection: close`r`n`r`n$redeemBody"
    Assert-CompiledTemporaryLink $redeemResponse.StartsWith('HTTP/1.1 303') 'Compiled auth worker could not redeem its generated temporary link.'
    $cookie = ([regex]::Match($redeemResponse, '(?im)^Set-Cookie:\s*([^;]+)')).Groups[1].Value.Trim()
    $statusResponse = Send-PlainRequest $externalPort "GET /auth/status HTTP/1.1`r`nHost: localhost`r`nCookie: $cookie`r`nConnection: close`r`n`r`n"
    Assert-CompiledTemporaryLink ($statusResponse -match '\{"authenticated":true\}') 'Compiled auth worker did not recognize the temporary-link session before revocation.'

    $listReply = Send-WorkerCommand @{ Type = 'ListTemporaryLinks' }
    $listed = @($listReply.TemporaryLinks)
    Assert-CompiledTemporaryLink ($listed.Count -eq 1) 'Compiled auth worker did not list exactly one generated link.'
    Assert-CompiledTemporaryLink ([string]$listed[0].Token -eq [string]$createReply.Link.Token) 'Compiled auth worker list response lost or changed the token.'

    $revokeReply = Send-WorkerCommand @{ Type = 'RevokeTemporaryLink'; Token = [string]$createReply.Link.Token }
    Assert-CompiledTemporaryLink ([bool]$revokeReply.Removed) 'Compiled auth worker did not remove the selected temporary link.'
    Assert-CompiledTemporaryLink ([string]$revokeReply.Username -eq 'viewer') 'Compiled auth worker link revocation lost the affected username.'
    Assert-CompiledTemporaryLink ([int]$revokeReply.SessionsRevoked -ge 1) 'Compiled auth worker did not invalidate the redeemed viewer session.'
    $redeemResponse = Send-PlainRequest $externalPort "GET $redeemTarget HTTP/1.1`r`nHost: localhost`r`nConnection: close`r`n`r`n"
    Assert-CompiledTemporaryLink $redeemResponse.StartsWith('HTTP/1.1 410') 'Compiled auth worker accepted a revoked temporary link.'
    Assert-CompiledTemporaryLink ($redeemResponse -match '(?im)^Content-Type:\s*image/png\s*$') 'Compiled auth worker did not serve the temporary-link rejection image.'
    $statusResponse = Send-PlainRequest $externalPort "GET /auth/status HTTP/1.1`r`nHost: localhost`r`nCookie: $cookie`r`nConnection: close`r`n`r`n"
    Assert-CompiledTemporaryLink ($statusResponse -match '\{"authenticated":false\}') 'Compiled auth worker still authenticated a session after its link was revoked.'
    $listReply = Send-WorkerCommand @{ Type = 'ListTemporaryLinks' }
    Assert-CompiledTemporaryLink (@($listReply.TemporaryLinks | Where-Object { $null -ne $_ }).Count -eq 0) "Compiled auth worker still listed a revoked temporary link: $($listReply | ConvertTo-Json -Compress -Depth 5)"

    $null = Send-WorkerCommand @{ Type = 'Shutdown' }
    if (-not $worker.WaitForExit(5000)) { throw 'Compiled auth worker did not exit after Shutdown.' }
}
finally {
    if ($writer) { $writer.Dispose() }
    if ($reader) { $reader.Dispose() }
    if ($pipe) { $pipe.Dispose() }
    if ($worker) {
        if (-not $worker.HasExited) { $worker.Kill(); $worker.WaitForExit() }
        $worker.Dispose()
    }
}

Write-Output 'Compiled auth-worker temporary-link JSON round trip passed.'
