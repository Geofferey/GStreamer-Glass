# SPDX-License-Identifier: AGPL-3.0-only

# Regression coverage for the UI/lifecycle contract around the persistent
# auth proxy worker:
#
# - While "Require viewer login for HTTPS/WSS" remains enabled, the existing
#   Keep-auth/session-revocation behavior owns proxy lifetime unchanged.
# - Once viewer authentication is unchecked, both Stop and Restart must tear
#   down the stale worker before any controlled-live early return. A later
#   Restart may then rebuild only the proxy families requested by the current
#   UI configuration.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$proxyPath = Join-Path $repoRoot 'src\33-LetsEncrypt.ps1'
$lifecyclePath = Join-Path $repoRoot 'src\27-StreamLifecycle.ps1'
$proxySource = Get-Content -Raw -LiteralPath $proxyPath
$lifecycleSource = Get-Content -Raw -LiteralPath $lifecyclePath

function Assert-LifecycleInvariant {
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

$helperSource = Get-FunctionSource -Source $proxySource -FunctionName 'Stop-AuthProxyWorkerIfViewerAuthenticationDisabled'
Assert-LifecycleInvariant ($helperSource -match 'if\s*\(Test-ViewerAuthenticationEnabled\)\s*\{\s*return\s+\$false\s*\}') (
    'Disabled-auth teardown must return without touching the worker while viewer authentication remains enabled; ' +
    'the existing Keep-auth/session-revocation behavior must stay unchanged.'
)
Assert-LifecycleInvariant ($helperSource -match '(?m)^\s*Stop-AuthProxyWorker\s*$') (
    'Disabled-auth teardown must call Stop-AuthProxyWorker, not merely stop one proxy family or revoke sessions.'
)

$stopSource = Get-FunctionSource -Source $lifecycleSource -FunctionName 'Stop-GstStream'
$teardownIndex = $stopSource.IndexOf('Stop-AuthProxyWorkerIfViewerAuthenticationDisabled')
$controlledReturnIndex = $stopSource.IndexOf('if (Stop-ControlledLiveStream')
Assert-LifecycleInvariant ($teardownIndex -ge 0) (
    'Stop-GstStream must apply disabled-auth worker teardown for both Stop and Restart.'
)
Assert-LifecycleInvariant ($controlledReturnIndex -ge 0 -and $teardownIndex -lt $controlledReturnIndex) (
    'Disabled-auth worker teardown must occur before Stop-GstStream delegates to Stop-ControlledLiveStream and returns.'
)

$prefix = $stopSource.Substring(0, $teardownIndex)
$lastRestartGate = $prefix.LastIndexOf('if (-not $Restart)')
Assert-LifecycleInvariant ($lastRestartGate -lt 0) (
    'Disabled-auth worker teardown must not be gated to full Stop only; Restart must end the stale worker too.'
)

# With viewer auth still enabled, the checkbox is authoritative for both a
# genuine Stop and Restart. Both lifecycle implementations must revoke only
# when Keep-auth is unchecked; neither may key that decision off $Restart.
foreach ($functionName in @('Stop-ControlledLiveStream', 'Stop-GstStream')) {
    $functionSource = Get-FunctionSource -Source $lifecycleSource -FunctionName $functionName
    Assert-LifecycleInvariant ($functionSource -match '(?ms)if\s*\(\(Test-ViewerAuthenticationEnabled\)\s*-and\s*-not\s*\(Test-KeepAuthenticationProxiesOnRestart\)\)\s*\{.*?Revoke-ActiveAuthenticationProxySessions') (
        "$functionName does not preserve authenticated sessions when Keep auth on restarts is checked."
    )
}

# Execute the real helper body with controlled stand-ins so the source-level
# checks above are backed by its actual branching behavior.
Invoke-Expression $helperSource
$script:TestViewerAuthenticationEnabled = $false
$script:TestAuthProxyWorkerRunning = $false
$script:TestAuthProxyWorkerStopCount = 0
$script:LetsEncryptTlsProxies = @()
$script:PlaintextAuthProxies = @()

function Test-ViewerAuthenticationEnabled { return [bool]$script:TestViewerAuthenticationEnabled }
function Test-AuthProxyWorkerRunning { return [bool]$script:TestAuthProxyWorkerRunning }
function Append-Log { param([string]$Message) }
function Stop-AuthProxyWorker {
    $script:TestAuthProxyWorkerStopCount++
    $script:TestAuthProxyWorkerRunning = $false
    $script:LetsEncryptTlsProxies = @()
    $script:PlaintextAuthProxies = @()
}

$script:TestViewerAuthenticationEnabled = $true
$script:TestAuthProxyWorkerRunning = $true
$enabledResult = Stop-AuthProxyWorkerIfViewerAuthenticationDisabled
Assert-LifecycleInvariant (-not $enabledResult -and $script:TestAuthProxyWorkerStopCount -eq 0) (
    'The helper stopped the worker while viewer authentication was still enabled.'
)

$script:TestViewerAuthenticationEnabled = $false
$disabledResult = Stop-AuthProxyWorkerIfViewerAuthenticationDisabled
Assert-LifecycleInvariant ($disabledResult -and $script:TestAuthProxyWorkerStopCount -eq 1) (
    'The helper did not stop a running worker after viewer authentication was disabled.'
)

$script:LetsEncryptTlsProxies = @([pscustomobject]@{ Label = 'stale TLS family state' })
$staleStateResult = Stop-AuthProxyWorkerIfViewerAuthenticationDisabled
Assert-LifecycleInvariant ($staleStateResult -and $script:TestAuthProxyWorkerStopCount -eq 2) (
    'The helper did not clear stale proxy-family state when the worker process was already gone.'
)

Write-Output 'Viewer-auth enabled path preserves the existing worker lifecycle.'
Write-Output 'Keep auth on restarts controls session preservation for both Stop and Restart paths.'
Write-Output 'Viewer-auth disabled path stops the worker before controlled/standard Stop and Restart teardown diverge.'
Write-Output ''
Write-Output 'Disabled-auth proxy worker teardown checks passed.'
