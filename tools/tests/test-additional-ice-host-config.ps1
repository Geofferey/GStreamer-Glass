# SPDX-License-Identifier: AGPL-3.0-only

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$pipelinePath = Join-Path $repoRoot 'src\17-DirectWebRtcPipeline.ps1'
$uiPath = Join-Path $repoRoot 'src\12-MainDashboardUi.ps1'
$settingsPath = Join-Path $repoRoot 'src\24-Settings.ps1'
$playerPath = Join-Path $repoRoot 'gstwebrtc-api\dist\player.js'

function Assert-AdditionalIceHost {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($pipelinePath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors) { throw ($parseErrors | Out-String) }
$requiredFunctions = @(
    'ConvertTo-DirectWebRtcAdditionalIceHostEntries',
    'Get-DirectWebRtcAdditionalIceHostEntriesFromUi',
    'Get-DirectWebRtcAdditionalIceHostTextFromUi',
    'Set-DirectWebRtcAdditionalIceHostTextToUi',
    'Get-DirectWebRtcAdditionalIceHostsForPlayer',
    'Get-DirectWebRtcAdditionalIceHostForPlayer'
)
foreach ($functionName in $requiredFunctions) {
    $definition = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName
    }, $true)
    Assert-AdditionalIceHost ($null -ne $definition) "Required function $functionName is missing."
    Invoke-Expression $definition.Extent.Text
}

$script:messages = New-Object System.Collections.Generic.List[string]
function Append-Log { param([string]$Message) $script:messages.Add($Message) }

Add-Type -AssemblyName System.Windows.Forms
$lstDirectWebRtcAdditionalIceHosts = New-Object System.Windows.Forms.ListBox
$txtDirectWebRtcAdditionalIceHost = New-Object System.Windows.Forms.TextBox
Set-DirectWebRtcAdditionalIceHostTextToUi "203.0.113.9`r`n198.51.100.44`r`n203.0.113.9"
Assert-AdditionalIceHost ($lstDirectWebRtcAdditionalIceHosts.Items.Count -eq 2) 'Saved host text did not migrate into the visible de-duplicated list.'
Assert-AdditionalIceHost ((Get-DirectWebRtcAdditionalIceHostTextFromUi) -eq "203.0.113.9`r`n198.51.100.44") 'Visible list did not serialize in display order.'
$ordered = @(Get-DirectWebRtcAdditionalIceHostsForPlayer)
Assert-AdditionalIceHost (($ordered -join ',') -eq '203.0.113.9,198.51.100.44') 'Ordered IPv4 hosts were not preserved and de-duplicated.'
Assert-AdditionalIceHost ((Get-DirectWebRtcAdditionalIceHostForPlayer) -eq '203.0.113.9') 'IPv4 host did not pass through unchanged.'

Set-DirectWebRtcAdditionalIceHostTextToUi 'http://203.0.113.9:50000/'
Assert-AdditionalIceHost ([string]::IsNullOrWhiteSpace([string](Get-DirectWebRtcAdditionalIceHostForPlayer))) 'URL/port text was accepted as an ICE host.'

Set-DirectWebRtcAdditionalIceHostTextToUi 'localhost'
Assert-AdditionalIceHost ((Get-DirectWebRtcAdditionalIceHostForPlayer) -eq '127.0.0.1') 'DNS hostname did not resolve to IPv4.'

$ui = Get-Content -Raw -LiteralPath $uiPath
$settings = Get-Content -Raw -LiteralPath $settingsPath
$pipeline = Get-Content -Raw -LiteralPath $pipelinePath
$player = Get-Content -Raw -LiteralPath $playerPath
Assert-AdditionalIceHost ($ui -match "ICE candidate overrides") 'Network tab ICE candidates section is missing.'
Assert-AdditionalIceHost ($ui -match 'btnDirectWebRtcAdditionalIceHostAdd') 'Additional ICE host Add button is missing from the Network tab.'
Assert-AdditionalIceHost ($ui -match 'btnDirectWebRtcAdditionalIceHostUp') 'Additional ICE host Move Up button is missing from the Network tab.'
Assert-AdditionalIceHost ($ui -match 'btnDirectWebRtcAdditionalIceHostDown') 'Additional ICE host Move Down button is missing from the Network tab.'
Assert-AdditionalIceHost ($ui -match 'btnDirectWebRtcAdditionalIceHostRemove') 'Additional ICE host Remove button is missing from the Network tab.'
Assert-AdditionalIceHost ($settings -match 'DirectWebRtcAdditionalIceHost') 'Additional ICE host is not persisted in settings.'
Assert-AdditionalIceHost ($pipeline -match 'additionalIceHosts = @\(\$additionalIceHosts\)') 'Resolved ordered hosts are not written to gstglass-config.js.'
Assert-AdditionalIceHost ($pipeline -match 'minRtpPort = \[int\]\$numDirectWebRtcMinRtpPort\.Value') 'Minimum mapped RTP port is not written to player config.'
Assert-AdditionalIceHost ($pipeline -match 'maxRtpPort = \[int\]\$numDirectWebRtcMaxRtpPort\.Value') 'Maximum mapped RTP port is not written to player config.'
Assert-AdditionalIceHost ($player -match "connectionMode\(\) !== 'proxy'") 'Mapped candidate injection is not limited to WAN/proxy mode.'

Write-Output 'Additional ICE host UI/configuration checks passed.'
