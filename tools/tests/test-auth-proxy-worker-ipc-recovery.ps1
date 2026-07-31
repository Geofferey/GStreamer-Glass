# SPDX-License-Identifier: AGPL-3.0-only

# Regression coverage for the auth proxy worker's single request/reply pipe.
# Wait-UiResponsiveTask pumps WinForms events, so the command path must reject
# reentrancy; any timeout/broken reply must recycle both pipe and worker because
# the outstanding ReadLineAsync makes that channel permanently ambiguous.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$proxyPath = Join-Path $repoRoot 'src\33-LetsEncrypt.ps1'
$mainPath = Join-Path $repoRoot 'src\90-MainWindow.ps1'
$proxySource = Get-Content -Raw -LiteralPath $proxyPath
$mainSource = Get-Content -Raw -LiteralPath $mainPath

function Assert-IpcInvariant {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-FunctionSource {
    param([string]$Source, [string]$FunctionName)
    $pattern = '(?ms)^function\s+' + [regex]::Escape($FunctionName) +
        '\s*\{(?<Body>.*?)(?=^function\s+[A-Za-z0-9_-]+\s*\{|\z)'
    $match = [regex]::Match($Source, $pattern)
    if (-not $match.Success) { throw "Could not find function '$FunctionName'." }
    return $match.Value
}

$resetSource = Get-FunctionSource -Source $proxySource -FunctionName 'Reset-FailedAuthProxyWorker'
$sendSource = Get-FunctionSource -Source $proxySource -FunctionName 'Send-AuthProxyWorkerCommand'

Assert-IpcInvariant ($proxySource -match '\$script:AuthProxyWorkerCommandInFlight\s*=\s*\$false') (
    'The auth proxy worker command channel has no initialized single-flight state.'
)
Assert-IpcInvariant ($sendSource -match 'if\s*\(\$script:AuthProxyWorkerCommandInFlight\)') (
    'Send-AuthProxyWorkerCommand does not reject a reentrant request on its single reader.'
)
Assert-IpcInvariant (([regex]::Matches($sendSource, 'Reset-FailedAuthProxyWorker')).Count -ge 4) (
    'Every reentrant, timeout, closed-pipe, and exception path must recycle the poisoned worker channel.'
)
Assert-IpcInvariant ($sendSource -match '(?ms)finally\s*\{\s*\$script:AuthProxyWorkerCommandInFlight\s*=\s*\$false\s*\}') (
    'Send-AuthProxyWorkerCommand does not release its single-flight state in finally.'
)
foreach ($stateName in @(
    'LetsEncryptTlsProxies', 'LetsEncryptTlsProxyConfigurationSignature', 'LetsEncryptAuthenticationSessionKey',
    'PlaintextAuthProxies', 'PlaintextAuthProxyConfigurationSignature', 'PlaintextAuthenticationSessionKey'
)) {
    Assert-IpcInvariant ($resetSource -notmatch ('\$script:' + [regex]::Escape($stateName) + '\s*=')) (
        "Reset-FailedAuthProxyWorker clears desired family state '$stateName'; the supervisor would no longer know what to rebuild."
    )
}
Assert-IpcInvariant ($mainSource -match '(?ms)-not\s+\$script:AuthProxyWorkerCommandInFlight\s+-and\s+-not\s+\(Test-AuthProxyWorkerRunning\)') (
    'The UI supervisor can restart the worker reentrantly before the failed outer command has unwound.'
)

# Execute the real reset helper against harmless stand-ins and prove desired
# family state survives while process/pipe state is discarded.
Invoke-Expression $resetSource
$script:LetsEncryptTlsProxies = @([pscustomobject]@{ Label = 'TLS desired' })
$script:LetsEncryptTlsProxyConfigurationSignature = 'tls-signature'
$script:LetsEncryptAuthenticationSessionKey = [byte[]](1..32)
$script:PlaintextAuthProxies = @([pscustomobject]@{ Label = 'Plaintext desired' })
$script:PlaintextAuthProxyConfigurationSignature = 'plain-signature'
$script:PlaintextAuthenticationSessionKey = [byte[]](33..64)
$script:AuthProxyWorkerProcess = [pscustomobject]@{ HasExited = $true; Id = 12345 }
$script:TestPipeCloseCount = 0
function Append-Log { param([string]$Message) }
function Close-AuthProxyWorkerPipe { $script:TestPipeCloseCount++ }
function Stop-ProcessTreeById { param([int]$ProcessId) throw 'Exited stand-in must never be killed.' }

Reset-FailedAuthProxyWorker -Reason 'test failure'
Assert-IpcInvariant ($null -eq $script:AuthProxyWorkerProcess -and $script:TestPipeCloseCount -eq 1) (
    'IPC reset did not discard the failed process and close its pipe exactly once.'
)
Assert-IpcInvariant (
    @($script:LetsEncryptTlsProxies).Count -eq 1 -and
    $script:LetsEncryptTlsProxyConfigurationSignature -eq 'tls-signature' -and
    $script:LetsEncryptAuthenticationSessionKey.Length -eq 32 -and
    @($script:PlaintextAuthProxies).Count -eq 1 -and
    $script:PlaintextAuthProxyConfigurationSignature -eq 'plain-signature' -and
    $script:PlaintextAuthenticationSessionKey.Length -eq 32
) 'IPC reset did not preserve all desired proxy-family state for supervision.'

Write-Output 'Auth proxy IPC is single-flight and recycles ambiguous channels.'
Write-Output 'Failed-worker reset preserves desired family state for supervised reconstruction.'
Write-Output ''
Write-Output 'Auth proxy worker IPC recovery checks passed.'
