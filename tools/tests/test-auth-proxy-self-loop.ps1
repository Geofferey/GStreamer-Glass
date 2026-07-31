# SPDX-License-Identifier: AGPL-3.0-only

# End-to-end regression for the plaintext relay's same-port topology. When the
# real loopback upstream is absent, Windows can route the proxy's connection
# back into its own 0.0.0.0 listener. The forwarded hop marker must turn that
# first recursive request into a bounded 502 rather than allowing unbounded
# proxy-to-self recursion and CPU/thread-pool exhaustion.

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

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}

function Send-PlainRequest {
    param([int]$Port, [string]$Request)

    $client = [System.Net.Sockets.TcpClient]::new()
    $client.ReceiveTimeout = 3000
    $client.SendTimeout = 3000
    $client.Connect('127.0.0.1', $Port)
    try {
        $stream = $client.GetStream()
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($Request)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
        $response = [System.IO.MemoryStream]::new()
        $buffer = New-Object byte[] 4096
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $response.Write($buffer, 0, $read)
        }
        return [System.Text.Encoding]::ASCII.GetString($response.ToArray())
    }
    finally {
        $client.Dispose()
    }
}

function Assert-SelfLoopInvariant {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$port = Get-FreeTcpPort
$proxy = [TlsTerminatingProxy]::new()
# A nonempty mount makes the proxy inspect/rewrite the first request exactly as
# the real plaintext-auth family does, without requiring a password login in
# this narrowly-scoped forwarding test.
$proxy.AuthenticationMountPath = '/live'
$proxy.Start($port, '127.0.0.1', $port, $null)
Start-Sleep -Milliseconds 100
try {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $response = Send-PlainRequest $port "GET /live/ HTTP/1.1`r`nHost: localhost`r`nConnection: close`r`n`r`n"
    $stopwatch.Stop()

    Assert-SelfLoopInvariant $response.StartsWith('HTTP/1.1 502') (
        "Same-port proxy recursion did not terminate with 502. Response began: $($response.Substring(0, [Math]::Min(80, $response.Length)))"
    )
    Assert-SelfLoopInvariant ($stopwatch.ElapsedMilliseconds -lt 2500) (
        "Same-port proxy recursion took $($stopwatch.ElapsedMilliseconds) ms instead of failing locally within the bounded test window."
    )

    $messages = @()
    while ($message = $proxy.PollLogMessage()) { $messages += $message }
    Assert-SelfLoopInvariant (($messages -join "`n") -match 'blocked a recursive same-port proxy request') (
        'The proxy returned 502 but did not record the same-port loop diagnosis.'
    )
}
finally {
    $proxy.Stop()
}

Write-Output 'Same-port plaintext proxy loop terminated with a bounded 502 response.'
Write-Output 'Auth proxy self-loop regression check passed.'
