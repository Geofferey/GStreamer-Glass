# SPDX-License-Identifier: AGPL-3.0-only

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$setupSource = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'src\00-Setup.ps1')
$uiSource = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'src\90-MainWindow.ps1')
$layoutSource = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'src\12-MainDashboardUi.ps1')
$resetSource = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'src\15-DefaultsReset.ps1')
$settingsSource = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'src\24-Settings.ps1')
$proxySource = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'src\33-LetsEncrypt.ps1')

function Assert-StartOnLaunch([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

Assert-StartOnLaunch ($setupSource -match 'DefaultViewerAuthenticationStartOnLaunch\s*=\s*\$false') 'Start auth on launch is not safely off by default.'
Assert-StartOnLaunch ($uiSource -match "chkViewerAuthenticationStartOnLaunch\.Text\s*=\s*'Start auth on launch'") 'Start auth on launch checkbox is missing.'
Assert-StartOnLaunch ($layoutSource.IndexOf('chkViewerAuthenticationStartOnLaunch') -gt $layoutSource.IndexOf('chkViewerAuthenticationKeepOnExit')) 'Start auth on launch is not laid out below Keep auth on exit.'
Assert-StartOnLaunch ($settingsSource -match 'ViewerAuthenticationStartOnLaunch\s*=\s*\[bool\]\$chkViewerAuthenticationStartOnLaunch\.Checked') 'Start auth on launch is not saved.'
Assert-StartOnLaunch ($settingsSource -match '\$settings\.ViewerAuthenticationStartOnLaunch') 'Start auth on launch is not restored.'
Assert-StartOnLaunch ($resetSource -match 'chkViewerAuthenticationStartOnLaunch\.Checked\s*=\s*\$script:DefaultViewerAuthenticationStartOnLaunch') 'Network defaults do not reset Start auth on launch.'
Assert-StartOnLaunch ($uiSource -match '(?s)\$form\.Add_Shown\(\{.*?Load-Settings.*?Start-AuthenticationOnApplicationLaunch') 'Authentication startup is not invoked after saved settings load.'

function Get-FunctionSource([string]$Name) {
    $match = [regex]::Match($proxySource, "(?ms)^function\s+$([regex]::Escape($Name))\s*\{.*?(?=^function\s+[A-Za-z0-9_-]+\s*\{|\z)")
    Assert-StartOnLaunch $match.Success "Function $Name was not found."
    return $match.Value
}

$script:chkViewerAuthenticationStartOnLaunch = [pscustomobject]@{ Checked = $false }
$script:viewerAuthenticationEnabled = $true
$script:embeddedTlsActive = $true
$script:plaintextAuthActive = $true
$script:LetsEncryptTlsProxies = @()
$script:PlaintextAuthProxies = @()
$script:tlsStarts = 0
$script:plaintextStarts = 0
$script:suspends = 0
$script:messages = [System.Collections.Generic.List[string]]::new()

function Test-ViewerAuthenticationEnabled { return [bool]$script:viewerAuthenticationEnabled }
function Test-EmbeddedTlsActive { return [bool]$script:embeddedTlsActive }
function Test-PlaintextAuthActive { return [bool]$script:plaintextAuthActive }
function Start-LetsEncryptTlsProxies { $script:tlsStarts++; $script:LetsEncryptTlsProxies = @([pscustomobject]@{ ExternalPort = 9443; InternalPort = 8889 }) }
function Start-PlaintextAuthProxies { $script:plaintextStarts++; $script:PlaintextAuthProxies = @([pscustomobject]@{ ExternalPort = 8189; InternalPort = 8189 }) }
function Suspend-ActiveAuthenticationProxyForwarding { $script:suspends++ }
function Append-Log([string]$Message) { $script:messages.Add($Message) }

Invoke-Expression (Get-FunctionSource 'Test-StartAuthenticationOnLaunch')
Invoke-Expression (Get-FunctionSource 'Test-ActiveAuthenticationProxyHasSamePortMapping')
Invoke-Expression (Get-FunctionSource 'Start-AuthenticationOnApplicationLaunch')

Assert-StartOnLaunch (-not (Start-AuthenticationOnApplicationLaunch)) 'Unchecked Start auth on launch started listeners.'
Assert-StartOnLaunch ($script:tlsStarts -eq 0 -and $script:plaintextStarts -eq 0 -and $script:suspends -eq 0) 'Unchecked startup touched proxy lifecycle.'

$script:chkViewerAuthenticationStartOnLaunch.Checked = $true
$script:viewerAuthenticationEnabled = $false
Assert-StartOnLaunch (-not (Start-AuthenticationOnApplicationLaunch)) 'Startup ignored disabled viewer authentication.'
Assert-StartOnLaunch ($script:tlsStarts -eq 0 -and $script:plaintextStarts -eq 0) 'Disabled viewer authentication started a proxy family.'

$script:viewerAuthenticationEnabled = $true
Assert-StartOnLaunch (Start-AuthenticationOnApplicationLaunch) 'Enabled authentication families did not start on launch.'
Assert-StartOnLaunch ($script:tlsStarts -eq 1 -and $script:plaintextStarts -eq 1) 'Startup did not start each configured authentication family exactly once.'
Assert-StartOnLaunch ($script:suspends -eq 1) 'Startup proxies were not paused before their GStreamer upstream existed.'

$script:LetsEncryptTlsProxies = @()
$script:PlaintextAuthProxies = @()
$script:tlsStarts = 0
$script:plaintextStarts = 0
$script:suspends = 0
$script:embeddedTlsActive = $true
$script:plaintextAuthActive = $false
Assert-StartOnLaunch (Start-AuthenticationOnApplicationLaunch) 'Distinct-port authentication proxy did not start.'
Assert-StartOnLaunch ($script:suspends -eq 1) 'Distinct-port startup did not pause on the restart page while its upstream was absent.'

$script:LetsEncryptTlsProxies = @()
$script:PlaintextAuthProxies = @()
$script:embeddedTlsActive = $false
$script:plaintextAuthActive = $false
Assert-StartOnLaunch (-not (Start-AuthenticationOnApplicationLaunch)) 'Startup reported success without an enabled proxy family.'
Assert-StartOnLaunch ($script:suspends -eq 1) 'Startup paused forwarding when no proxy family existed.'

Write-Output 'Start auth on launch is persisted, correctly placed, gated by auth configuration, and serves the paused restart page until stream startup.'
