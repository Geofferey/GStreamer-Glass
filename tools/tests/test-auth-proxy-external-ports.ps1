# SPDX-License-Identifier: AGPL-3.0-only

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$proxyPath = Join-Path $repoRoot 'src\33-LetsEncrypt.ps1'
$pipelinePath = Join-Path $repoRoot 'src\17-DirectWebRtcPipeline.ps1'
$upnpPath = Join-Path $repoRoot 'src\31-UpnpPortForwarding.ps1'
$windowPath = Join-Path $repoRoot 'src\90-MainWindow.ps1'
$proxySource = Get-Content -Raw -LiteralPath $proxyPath
$pipelineSource = Get-Content -Raw -LiteralPath $pipelinePath
$upnpSource = Get-Content -Raw -LiteralPath $upnpPath
$windowSource = Get-Content -Raw -LiteralPath $windowPath

function Assert-AuthProxyPort([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Get-FunctionFromFile([string]$Path, [string]$Name) {
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors) { throw ($errors | Out-String) }
    $definition = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)
    if (-not $definition) { throw "Required function '$Name' is missing from $Path." }
    return $definition.Extent.Text
}

foreach ($name in @(
    'Get-LetsEncryptSignalingProxyPort',
    'Get-LetsEncryptSplitAudioProxyPort',
    'Get-LetsEncryptWebServerProxyPort',
    'Get-PlaintextAuthSignalingProxyPort',
    'Get-PlaintextAuthSplitAudioProxyPort',
    'Get-PlaintextAuthWebServerProxyPort',
    'Get-EmbeddedTlsPortConflicts',
    'Test-AuthenticationProxyListenerActive',
    'Update-EmbeddedTlsUi'
)) {
    Invoke-Expression (Get-FunctionFromFile -Path $proxyPath -Name $name)
}
foreach ($name in @('Get-DirectWebRtcEffectiveExternalSignalingPort', 'Get-DirectWebRtcEffectiveSplitAudioExternalSignalingPort')) {
    Invoke-Expression (Get-FunctionFromFile -Path $pipelinePath -Name $name)
}
Invoke-Expression (Get-FunctionFromFile -Path $upnpPath -Name 'Get-UpnpRequiredMappings')

$numLetsEncryptSignalingExternalPort = [pscustomobject]@{ Value = 18189; Enabled = $false }
$numLetsEncryptSplitAudioExternalPort = [pscustomobject]@{ Value = 18190; Enabled = $false }
$numLetsEncryptWebServerExternalPort = [pscustomobject]@{ Value = 18889; Enabled = $false }
$numDirectWebRtcSignalingPort = [pscustomobject]@{ Value = 8189 }
$script:EmbeddedTlsActiveForTest = $false
$script:PlaintextAuthActiveForTest = $false
$script:SplitPipelinesForTest = $true
function Test-EmbeddedTlsActive { return [bool]$script:EmbeddedTlsActiveForTest }
function Test-PlaintextAuthActive { return [bool]$script:PlaintextAuthActiveForTest }
function Test-EmbeddedTlsInsecurePortsRestricted { return $true }
function Test-UpnpSignalingMappedExternally { return $false }
function Test-DirectWebRtcSplitAvPipelines { return [bool]$script:SplitPipelinesForTest }
function Test-DirectWebRtcUnifiedPublisher { return $false }
function Test-DirectWebRtcSharedSignaling { return $false }
function Get-DirectWebRtcSplitAudioSignalingPort { return 8190 }

Assert-AuthProxyPort ((Get-LetsEncryptSignalingProxyPort) -eq 18189) 'Video proxy override was not preserved.'
Assert-AuthProxyPort ((Get-LetsEncryptSplitAudioProxyPort) -eq 18190) 'Audio proxy override was not preserved.'
Assert-AuthProxyPort ((Get-LetsEncryptWebServerProxyPort -InternalPort 8889) -eq 18889) 'Web proxy override was not preserved.'

# Stored values are inert until an actual listener family is active.
Assert-AuthProxyPort (-not (Test-AuthenticationProxyListenerActive)) 'Proxy-listener state became active from port values alone.'
Assert-AuthProxyPort ((Get-DirectWebRtcEffectiveExternalSignalingPort) -eq 0) 'Video override leaked into player config with authentication/TLS proxying disabled.'
Assert-AuthProxyPort ((Get-DirectWebRtcEffectiveSplitAudioExternalSignalingPort) -eq 0) 'Audio override leaked into player config with authentication/TLS proxying disabled.'

$script:PlaintextAuthActiveForTest = $true
Assert-AuthProxyPort (Test-AuthenticationProxyListenerActive) 'Allowed plaintext authentication did not activate proxy listener ports.'
Assert-AuthProxyPort ((Get-DirectWebRtcEffectiveExternalSignalingPort) -eq 18189) 'Plaintext auth did not expose the configured video proxy listener.'
Assert-AuthProxyPort ((Get-DirectWebRtcEffectiveSplitAudioExternalSignalingPort) -eq 18190) 'Plaintext auth did not expose the configured audio proxy listener.'
Assert-AuthProxyPort ((Get-PlaintextAuthSignalingProxyPort) -eq 18189) 'Plaintext video auth ignored the external listener override.'
Assert-AuthProxyPort ((Get-PlaintextAuthSplitAudioProxyPort) -eq 18190) 'Plaintext audio auth ignored the external listener override.'
Assert-AuthProxyPort ((Get-PlaintextAuthWebServerProxyPort -InternalPort 8889) -eq 18889) 'Plaintext web auth ignored the external listener override.'

# UPnP must map the actual plaintext proxy listeners 1:1, never bypass them
# by forwarding the public port directly to the loopback-only upstream.
$script:SplitPipelinesForTest = $false
$script:DirectWebRtcProtocolName = 'GST WebRTC'
$script:UpnpMappingTag = 'GStreamer Glass '
$cmbProtocol = [pscustomobject]@{ SelectedItem = $script:DirectWebRtcProtocolName }
$chkUpnpMapSignaling = [pscustomobject]@{ Checked = $true }
$chkUpnpMapWebServer = [pscustomobject]@{ Checked = $true }
$chkUpnpMapRtp = [pscustomobject]@{ Checked = $false }
$txtDestination = [pscustomobject]@{ Text = 'http://0.0.0.0:8889/' }
function Get-DirectWebRtcWebServerBindAddress { param([string]$Destination) return 'http://127.0.0.1:8889/' }
function Normalize-DirectWebRtcWebAddress { param([string]$Destination) return $Destination }
$proxyMappings = @(Get-UpnpRequiredMappings)
$videoMapping = $proxyMappings | Where-Object { $_.Description -match 'Video signalling' } | Select-Object -First 1
$webMapping = $proxyMappings | Where-Object { $_.Description -match 'Web viewer' } | Select-Object -First 1
Assert-AuthProxyPort ($videoMapping.ExternalPort -eq 18189 -and $videoMapping.InternalPort -eq 18189) 'UPnP bypassed the configured plaintext video proxy listener.'
Assert-AuthProxyPort ($webMapping.ExternalPort -eq 18889 -and $webMapping.InternalPort -eq 18889) 'UPnP bypassed the configured plaintext web proxy listener.'

# When both families run, TLS owns the shared overrides and plaintext retains
# its internal-port listeners so the two families cannot bind the same ports.
$script:EmbeddedTlsActiveForTest = $true
$script:SplitPipelinesForTest = $true
Assert-AuthProxyPort ((Get-PlaintextAuthSignalingProxyPort) -eq 8189) 'Simultaneous TLS/plaintext auth assigned both families the video override port.'
Assert-AuthProxyPort ((Get-PlaintextAuthSplitAudioProxyPort) -eq 8190) 'Simultaneous TLS/plaintext auth assigned both families the audio override port.'
Assert-AuthProxyPort ((Get-PlaintextAuthWebServerProxyPort -InternalPort 8889) -eq 8889) 'Simultaneous TLS/plaintext auth assigned both families the web override port.'
$numLetsEncryptSignalingExternalPort.Value = 8189
$numLetsEncryptSplitAudioExternalPort.Value = 8190
$numLetsEncryptWebServerExternalPort.Value = 8889
$simultaneousConflicts = @(Get-EmbeddedTlsPortConflicts)
Assert-AuthProxyPort ($simultaneousConflicts.Count -eq 3) 'Simultaneous TLS/plaintext auth did not reject listener-port collisions between proxy families.'
$numLetsEncryptSignalingExternalPort.Value = 18189
$numLetsEncryptSplitAudioExternalPort.Value = 18190
$numLetsEncryptWebServerExternalPort.Value = 18889

# Embedded-TLS UI state must never gray the listener fields again.
$chkEmbeddedTlsEnabled = [pscustomobject]@{ Checked = $false }
$txtTlsCertificatePath = [pscustomobject]@{ Enabled = $true }
$btnBrowseTlsCertificatePath = [pscustomobject]@{ Enabled = $true }
$txtTlsPrivateKeyPath = [pscustomobject]@{ Enabled = $true }
$btnBrowseTlsPrivateKeyPath = [pscustomobject]@{ Enabled = $true }
$chkTlsAllowInsecurePorts = [pscustomobject]@{ Enabled = $false }
$lblEmbeddedTlsStatus = $null
Update-EmbeddedTlsUi
Assert-AuthProxyPort ($numLetsEncryptSignalingExternalPort.Enabled -and $numLetsEncryptSplitAudioExternalPort.Enabled -and $numLetsEncryptWebServerExternalPort.Enabled) 'External authentication-proxy ports are still gated by Use embedded TLS.'
Assert-AuthProxyPort (-not $txtTlsCertificatePath.Enabled -and -not $txtTlsPrivateKeyPath.Enabled) 'Disabling embedded TLS no longer gates its certificate-only controls.'

$plaintextStart = [regex]::Match($proxySource, '(?ms)^function\s+Start-PlaintextAuthProxies\s*\{.*?(?=^function\s+[A-Za-z0-9_-]+\s*\{|\z)').Value
Assert-AuthProxyPort ($plaintextStart -match 'ExternalPort\s*=\s*\$videoExternalPort;\s*InternalPort\s*=\s*\$videoInternalPort') 'Plaintext video proxy descriptors do not separate listener and upstream ports.'
Assert-AuthProxyPort ($plaintextStart -match 'Get-PlaintextAuthWebServerProxyPort') 'Plaintext web proxy does not consume the shared external listener field.'
Assert-AuthProxyPort ($plaintextStart -match 'Ports\s*=\s*@\(\$ports\)') 'Plaintext worker does not receive the external/internal port descriptors.'
Assert-AuthProxyPort ($upnpSource -match '\$authenticationProxyActive\s*=\s*Test-AuthenticationProxyListenerActive') 'UPnP does not route to a plaintext authentication proxy listener.'
Assert-AuthProxyPort ($pipelineSource -notmatch '\$numLetsEncrypt(?:Signaling|SplitAudio|WebServer)ExternalPort') 'Proxy listener controls directly alter the generated GStreamer pipeline.'
Assert-AuthProxyPort ($windowSource -match 'TLS or allowed plaintext auth') 'External listener tooltips still describe the ports as TLS-only.'

Write-Output 'Authentication proxy ports stay editable, remain inert without a proxy, and drive both TLS and plaintext listener families.'
