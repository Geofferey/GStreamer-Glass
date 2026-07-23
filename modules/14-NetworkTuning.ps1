# Module: 14-NetworkTuning.ps1 (auto-extracted by tools/Split-Monolith.ps1 -- edit here, then run tools/Build-Monolith.ps1)

function Ensure-NetworkRecoveryDirectory {
    if (-not (Test-Path -LiteralPath $script:NetworkRecoveryDirectory)) {
        $null = New-Item -ItemType Directory -Path $script:NetworkRecoveryDirectory -Force
    }
}

function Get-SelectedNetworkAdapterName {
    $item = [string]$cmbNetworkAdapter.SelectedItem
    if ([string]::IsNullOrWhiteSpace($item)) { return '' }
    return ($item -split '\s+\|\s+', 2)[0].Trim()
}

function Refresh-NetworkAdapters {
    try {
        $previous = Get-SelectedNetworkAdapterName
        $cmbNetworkAdapter.Items.Clear()
        if (-not (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue)) {
            $lblNetworkStatus.Text = 'Get-NetAdapter unavailable on this system.'
            $lblNetworkStatus.ForeColor = [System.Drawing.Color]::DarkRed
            return
        }

        $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Sort-Object @{Expression={ if ($_.Status -eq 'Up') { 0 } else { 1 } }}, Name)
        foreach ($adapter in $adapters) {
            $display = "$($adapter.Name) | $($adapter.InterfaceDescription) [$($adapter.Status)]"
            $null = $cmbNetworkAdapter.Items.Add($display)
        }

        if ($cmbNetworkAdapter.Items.Count -gt 0) {
            $matchIndex = -1
            if (-not [string]::IsNullOrWhiteSpace($previous)) {
                for ($i = 0; $i -lt $cmbNetworkAdapter.Items.Count; $i++) {
                    if ([string]$cmbNetworkAdapter.Items[$i] -like "$previous |*") { $matchIndex = $i; break }
                }
            }
            if ($matchIndex -lt 0) { $matchIndex = 0 }
            $cmbNetworkAdapter.SelectedIndex = $matchIndex
            $lblNetworkStatus.Text = "Adapter ready: $(Get-SelectedNetworkAdapterName)"
            $lblNetworkStatus.ForeColor = [System.Drawing.Color]::DimGray
        }
        else {
            $lblNetworkStatus.Text = 'No network adapters detected.'
            $lblNetworkStatus.ForeColor = [System.Drawing.Color]::DarkRed
        }
    }
    catch {
        $lblNetworkStatus.Text = "Adapter refresh failed: $($_.Exception.Message)"
        $lblNetworkStatus.ForeColor = [System.Drawing.Color]::DarkRed
    }
}

function Normalize-UdpOffloadState {
    param([AllowNull()][object]$State)

    $value = ([string]$State).Trim().ToLowerInvariant()
    switch ($value) {
        'enabled' { return 'enabled' }
        'disabled' { return 'disabled' }
        default { return '' }
    }
}

function Get-UdpGlobalState {
    $state = [ordered]@{ Uso = ''; Uro = ''; Raw = '' }
    try {
        $raw = (& netsh interface udp show global 2>&1 | Out-String).Trim()
        $state.Raw = $raw
        foreach ($line in ($raw -split "`r?`n")) {
            if ($line -match '(?i)\buso\b.*:\s*(?<value>enabled|disabled)') { $state.Uso = $matches['value'].ToLowerInvariant(); continue }
            if ($line -match '(?i)segmentation.*:\s*(?<value>enabled|disabled)') { $state.Uso = $matches['value'].ToLowerInvariant(); continue }
            if ($line -match '(?i)\buro\b.*:\s*(?<value>enabled|disabled)') { $state.Uro = $matches['value'].ToLowerInvariant(); continue }
            if ($line -match '(?i)receive.*(?:offload|coalescing).*:\s*(?<value>enabled|disabled)') { $state.Uro = $matches['value'].ToLowerInvariant(); continue }
        }
    }
    catch {}
    return $state
}

function Get-SnapshotUdpOffloadState {
    param(
        [AllowNull()][object]$UdpGlobal,
        [ValidateSet('uso','uro')][string]$Name
    )

    if (-not $UdpGlobal) { return '' }

    $direct = ''
    try {
        if ($Name -eq 'uso') { $direct = Normalize-UdpOffloadState $UdpGlobal.Uso }
        else { $direct = Normalize-UdpOffloadState $UdpGlobal.Uro }
    }
    catch {}
    if ($direct) { return $direct }

    try {
        $raw = [string]$UdpGlobal.Raw
        foreach ($line in ($raw -split "`r?`n")) {
            if ($Name -eq 'uso') {
                if ($line -match '(?i)\buso\b.*:\s*(?<value>enabled|disabled)') { return $matches['value'].ToLowerInvariant() }
                if ($line -match '(?i)segmentation.*:\s*(?<value>enabled|disabled)') { return $matches['value'].ToLowerInvariant() }
            }
            else {
                if ($line -match '(?i)\buro\b.*:\s*(?<value>enabled|disabled)') { return $matches['value'].ToLowerInvariant() }
                if ($line -match '(?i)receive.*(?:offload|coalescing).*:\s*(?<value>enabled|disabled)') { return $matches['value'].ToLowerInvariant() }
            }
        }
    }
    catch {}

    return ''
}

function Set-UdpGlobalOffload {
    param(
        [ValidateSet('uso','uro')][string]$Name,
        [ValidateSet('enabled','disabled')][string]$State
    )

    try {
        $result = (& netsh interface udp set global ("$Name=$State") 2>&1 | Out-String).Trim()
        Append-Log "Network tuning: netsh interface udp set global $Name=$State - $result"
        return $true
    }
    catch {
        Append-Log "Network tuning warning: could not set UDP $Name to $State - $($_.Exception.Message)"
        return $false
    }
}

function Get-NetworkSnapshotObject {
    param([Parameter(Mandatory)][string]$AdapterName)

    $advanced = @()
    if (Get-Command Get-NetAdapterAdvancedProperty -ErrorAction SilentlyContinue) {
        try {
            $advanced = @(Get-NetAdapterAdvancedProperty -Name $AdapterName -ErrorAction SilentlyContinue | ForEach-Object {
                [ordered]@{
                    DisplayName = [string]$_.DisplayName
                    DisplayValue = [string]$_.DisplayValue
                    RegistryKeyword = [string]$_.RegistryKeyword
                    RegistryValue = @($_.RegistryValue)
                }
            })
        }
        catch {}
    }

    $power = [ordered]@{}
    if (Get-Command Get-NetAdapterPowerManagement -ErrorAction SilentlyContinue) {
        try {
            $pm = Get-NetAdapterPowerManagement -Name $AdapterName -ErrorAction SilentlyContinue
            foreach ($propName in @('AllowComputerToTurnOffDevice','WakeOnMagicPacket','WakeOnPattern','DeviceSleepOnDisconnect','ArpOffload','NSOffload','RsnRekeyOffload','D0PacketCoalescing')) {
                if ($pm.PSObject.Properties.Name -contains $propName) {
                    $power[$propName] = [string]$pm.$propName
                }
            }
        }
        catch {}
    }

    return [ordered]@{
        Version = $script:AppVersion
        Timestamp = (Get-Date).ToString('o')
        ComputerName = $env:COMPUTERNAME
        AdapterName = $AdapterName
        UdpGlobal = Get-UdpGlobalState
        AdvancedProperties = $advanced
        PowerManagement = $power
        QosPolicyName = 'GStreamerGlass-Transport'
    }
}

function Write-NetworkRecoveryScript {
    Ensure-NetworkRecoveryDirectory
    $template = @'
param([string]$SnapshotPath = '__SNAPSHOT_PATH__')

function Normalize-UdpOffloadState {
    param([string]$State)
    $value = ([string]$State).Trim().ToLowerInvariant()
    if ($value -eq 'enabled' -or $value -eq 'disabled') { return $value }
    return ''
}

function Get-SnapshotUdpOffloadState {
    param($UdpGlobal, [string]$Name)
    if (-not $UdpGlobal) { return '' }
    $direct = ''
    try {
        if ($Name -eq 'uso') { $direct = Normalize-UdpOffloadState ([string]$UdpGlobal.Uso) }
        else { $direct = Normalize-UdpOffloadState ([string]$UdpGlobal.Uro) }
    } catch {}
    if ($direct) { return $direct }

    try {
        $raw = [string]$UdpGlobal.Raw
        foreach ($line in ($raw -split "`r?`n")) {
            if ($Name -eq 'uso') {
                if ($line -match '(?i)\buso\b.*:\s*(?<value>enabled|disabled)') { return $matches['value'].ToLowerInvariant() }
                if ($line -match '(?i)segmentation.*:\s*(?<value>enabled|disabled)') { return $matches['value'].ToLowerInvariant() }
            }
            else {
                if ($line -match '(?i)\buro\b.*:\s*(?<value>enabled|disabled)') { return $matches['value'].ToLowerInvariant() }
                if ($line -match '(?i)receive.*(?:offload|coalescing).*:\s*(?<value>enabled|disabled)') { return $matches['value'].ToLowerInvariant() }
            }
        }
    } catch {}
    return ''
}

function Set-UdpGlobalSafe {
    param([string]$Name, [string]$State)
    $safeState = Normalize-UdpOffloadState $State
    if ([string]::IsNullOrWhiteSpace($safeState)) { return }
    try { & netsh interface udp set global "$Name=$safeState" | Out-Null } catch { Write-Warning $_.Exception.Message }
}

if (-not (Test-Path -LiteralPath $SnapshotPath)) {
    Write-Error "Snapshot not found: $SnapshotPath"
    exit 1
}

$snapshot = Get-Content -LiteralPath $SnapshotPath -Raw | ConvertFrom-Json
$adapterName = [string]$snapshot.AdapterName

try {
    if (Get-Command Remove-NetQosPolicy -ErrorAction SilentlyContinue) {
        Remove-NetQosPolicy -Name ([string]$snapshot.QosPolicyName) -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    }
} catch { Write-Warning $_.Exception.Message }

try {
    if ($snapshot.UdpGlobal) {
        Set-UdpGlobalSafe -Name 'uso' -State (Get-SnapshotUdpOffloadState -UdpGlobal $snapshot.UdpGlobal -Name 'uso')
        Set-UdpGlobalSafe -Name 'uro' -State (Get-SnapshotUdpOffloadState -UdpGlobal $snapshot.UdpGlobal -Name 'uro')
    }
} catch { Write-Warning $_.Exception.Message }

try {
    if ((Get-Command Set-NetAdapterAdvancedProperty -ErrorAction SilentlyContinue) -and $snapshot.AdvancedProperties) {
        foreach ($prop in $snapshot.AdvancedProperties) {
            if (-not [string]::IsNullOrWhiteSpace([string]$prop.DisplayName)) {
                Set-NetAdapterAdvancedProperty -Name $adapterName -DisplayName ([string]$prop.DisplayName) -DisplayValue ([string]$prop.DisplayValue) -NoRestart -ErrorAction SilentlyContinue | Out-Null
            }
        }
    }
} catch { Write-Warning $_.Exception.Message }

try {
    if ((Get-Command Set-NetAdapterPowerManagement -ErrorAction SilentlyContinue) -and $snapshot.PowerManagement) {
        $params = @{ Name = $adapterName; ErrorAction = 'SilentlyContinue' }
        foreach ($p in $snapshot.PowerManagement.PSObject.Properties) {
            if (-not [string]::IsNullOrWhiteSpace([string]$p.Value)) { $params[$p.Name] = [string]$p.Value }
        }
        if ($params.Count -gt 2) { Set-NetAdapterPowerManagement @params | Out-Null }
    }
} catch { Write-Warning $_.Exception.Message }

Write-Host "GStreamer Glass network settings restored from $SnapshotPath"
'@
    $scriptText = $template.Replace('__SNAPSHOT_PATH__', $script:NetworkSnapshotPath.Replace("'", "''"))
    Set-Content -LiteralPath $script:NetworkRecoveryScriptPath -Value $scriptText -Encoding UTF8
}

function Save-NetworkSnapshot {
    param([switch]$Quiet)

    Ensure-NetworkRecoveryDirectory
    $adapterName = Get-SelectedNetworkAdapterName
    if ([string]::IsNullOrWhiteSpace($adapterName)) {
        throw 'Select a network adapter first.'
    }

    $snapshot = Get-NetworkSnapshotObject -AdapterName $adapterName
    $json = $snapshot | ConvertTo-Json -Depth 12
    $json | Set-Content -LiteralPath $script:NetworkSnapshotPath -Encoding UTF8
    $timestampPath = Join-Path $script:NetworkRecoveryDirectory ("network-snapshot-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $json | Set-Content -LiteralPath $timestampPath -Encoding UTF8
    Write-NetworkRecoveryScript

    if (-not $Quiet) {
        Append-Log "Network tuning snapshot saved: $script:NetworkSnapshotPath"
        $lblNetworkStatus.Text = "Snapshot saved for $adapterName"
        $lblNetworkStatus.ForeColor = [System.Drawing.Color]::DarkGreen
    }

    return $snapshot
}

function Set-NetworkAppliedState {
    param([bool]$Active)
    Ensure-NetworkRecoveryDirectory
    $script:NetworkTuningApplied = $Active
    [ordered]@{
        Active = $Active
        Timestamp = (Get-Date).ToString('o')
        SnapshotPath = $script:NetworkSnapshotPath
        AdapterName = Get-SelectedNetworkAdapterName
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:NetworkAppliedStatePath -Encoding UTF8
}

function Get-NetworkAppliedState {
    try {
        if (Test-Path -LiteralPath $script:NetworkAppliedStatePath) {
            return Get-Content -LiteralPath $script:NetworkAppliedStatePath -Raw | ConvertFrom-Json
        }
    }
    catch {}
    return $null
}

function Register-NetworkRecoveryTask {
    if (-not $chkNetworkRecoveryTask.Checked) { return }
    try {
        Write-NetworkRecoveryScript
        $tr = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$script:NetworkRecoveryScriptPath`""
        & schtasks.exe /Create /TN $script:NetworkRecoveryTaskName /SC ONLOGON /TR $tr /F 2>&1 | Out-Null
        Append-Log "Network recovery task registered: $script:NetworkRecoveryTaskName"
    }
    catch {
        Append-Log "Network tuning warning: recovery task registration failed - $($_.Exception.Message)"
    }
}

function Unregister-NetworkRecoveryTask {
    try {
        & schtasks.exe /Delete /TN $script:NetworkRecoveryTaskName /F 2>&1 | Out-Null
    }
    catch {}
}

function Set-AdapterAdvancedPropertyByCandidates {
    param(
        [Parameter(Mandatory)][string]$AdapterName,
        [Parameter(Mandatory)][string[]]$DisplayNames,
        [Parameter(Mandatory)][string[]]$DesiredValues
    )

    if (-not (Get-Command Get-NetAdapterAdvancedProperty -ErrorAction SilentlyContinue) -or -not (Get-Command Set-NetAdapterAdvancedProperty -ErrorAction SilentlyContinue)) {
        return $false
    }

    foreach ($displayName in $DisplayNames) {
        $prop = $null
        try { $prop = Get-NetAdapterAdvancedProperty -Name $AdapterName -DisplayName $displayName -ErrorAction SilentlyContinue | Select-Object -First 1 } catch {}
        if (-not $prop) {
            try { $prop = Get-NetAdapterAdvancedProperty -Name $AdapterName -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*$displayName*" } | Select-Object -First 1 } catch {}
        }
        if (-not $prop) { continue }

        foreach ($desired in $DesiredValues) {
            try {
                Set-NetAdapterAdvancedProperty -Name $AdapterName -DisplayName $prop.DisplayName -DisplayValue $desired -NoRestart -ErrorAction Stop | Out-Null
                Append-Log "Network tuning: $($prop.DisplayName) -> $desired"
                return $true
            }
            catch {}
        }
    }

    return $false
}

function Set-NetworkPowerSavingDisabled {
    param([Parameter(Mandatory)][string]$AdapterName)
    if (-not (Get-Command Set-NetAdapterPowerManagement -ErrorAction SilentlyContinue)) { return $false }
    try {
        Set-NetAdapterPowerManagement -Name $AdapterName -AllowComputerToTurnOffDevice Disabled -ErrorAction Stop | Out-Null
        Append-Log 'Network tuning: adapter power saving disabled.'
        return $true
    }
    catch {
        Append-Log "Network tuning warning: adapter power saving was not changed - $($_.Exception.Message)"
        return $false
    }
}

function Apply-NetworkProfileToUi {
    $profile = [string]$cmbNetworkProfile.SelectedItem
    switch ($profile) {
        'No changes' {
            $chkNetworkTuningEnabled.Checked = $false
            $chkNetworkDscp.Checked = $false
            $cmbNetworkUso.SelectedItem = 'Leave unchanged'
            $cmbNetworkUro.SelectedItem = 'Leave unchanged'
            $chkNetworkDisablePowerSaving.Checked = $false
            $cmbNetworkInterruptModeration.SelectedItem = 'Leave unchanged'
            $chkNetworkDisableEee.Checked = $false
        }
        'Low latency LAN' {
            $chkNetworkTuningEnabled.Checked = $true
            $chkNetworkDscp.Checked = $true
            $numNetworkDscp.Value = 34
            $cmbNetworkQosProtocol.SelectedItem = 'UDP'
            $cmbNetworkUso.SelectedItem = 'Leave unchanged'
            $cmbNetworkUro.SelectedItem = 'Disable'
            $chkNetworkDisablePowerSaving.Checked = $true
            $cmbNetworkInterruptModeration.SelectedItem = 'Disable'
            $chkNetworkDisableEee.Checked = $true
            $chkNetworkRestoreOnStop.Checked = $true
            $chkNetworkRestoreOnExit.Checked = $true
            $chkNetworkRecoveryTask.Checked = $true
        }
        'Stable WAN' {
            $chkNetworkTuningEnabled.Checked = $true
            $chkNetworkDscp.Checked = $true
            $numNetworkDscp.Value = 34
            $cmbNetworkQosProtocol.SelectedItem = 'UDP'
            $cmbNetworkUso.SelectedItem = 'Enable'
            $cmbNetworkUro.SelectedItem = 'Enable'
            $chkNetworkDisablePowerSaving.Checked = $true
            $cmbNetworkInterruptModeration.SelectedItem = 'Enable / Adaptive'
            $chkNetworkDisableEee.Checked = $true
            $chkNetworkRestoreOnStop.Checked = $true
            $chkNetworkRestoreOnExit.Checked = $true
            $chkNetworkRecoveryTask.Checked = $true
        }
    }
    Update-NetworkUi
}

function Update-NetworkUi {
    $enabled = [bool]$chkNetworkTuningEnabled.Checked
    foreach ($control in @($cmbNetworkAdapter,$btnRefreshNetworkAdapters,$cmbNetworkProfile,$chkNetworkRestoreOnStop,$chkNetworkRestoreOnExit,$chkNetworkRecoveryTask,$btnNetworkSnapshot,$btnNetworkRestore,$btnOpenNetworkRecovery,$btnResetNetwork)) {
        if ($control) { $control.Enabled = $true }
    }
    foreach ($control in @($chkNetworkDscp,$numNetworkDscp,$cmbNetworkQosProtocol,$txtNetworkPorts,$cmbNetworkUso,$cmbNetworkUro,$chkNetworkDisablePowerSaving,$cmbNetworkInterruptModeration,$chkNetworkDisableEee,$btnNetworkApply)) {
        if ($control) { $control.Enabled = $enabled }
    }
    $numNetworkDscp.Enabled = $enabled -and $chkNetworkDscp.Checked
    $cmbNetworkQosProtocol.Enabled = $enabled -and $chkNetworkDscp.Checked
    $txtNetworkPorts.Enabled = $enabled -and $chkNetworkDscp.Checked

    if ($enabled) {
        $lblNetworkStatus.Text = 'Network tuning armed - snapshot required before apply.'
        $lblNetworkStatus.ForeColor = [System.Drawing.Color]::DarkOrange
    }
    else {
        $lblNetworkStatus.Text = 'Network tuning disabled'
        $lblNetworkStatus.ForeColor = [System.Drawing.Color]::DimGray
    }
}

function New-QosPolicyForGStreamer {
    param([Parameter(Mandatory)][int]$DscpValue)

    if (-not (Get-Command New-NetQosPolicy -ErrorAction SilentlyContinue)) {
        Append-Log 'Network tuning warning: New-NetQosPolicy is unavailable.'
        return
    }

    $policyName = 'GStreamerGlass-Transport'
    try { Remove-NetQosPolicy -Name $policyName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}

    $params = @{
        Name = $policyName
        AppPathNameMatchCondition = 'gst-launch-1.0.exe'
        DSCPAction = $DscpValue
        ErrorAction = 'Stop'
    }

    $proto = [string]$cmbNetworkQosProtocol.SelectedItem
    if ($proto -in @('UDP','TCP')) { $params.IPProtocolMatchCondition = $proto }

    $ports = $txtNetworkPorts.Text.Trim()
    if (-not [string]::IsNullOrWhiteSpace($ports)) {
        $params.IPDstPortMatchCondition = $ports
    }

    try {
        New-NetQosPolicy @params | Out-Null
        Append-Log "Network tuning: QoS DSCP policy created for gst-launch-1.0.exe DSCP=$DscpValue protocol=$proto ports=$(if ($ports) { $ports } else { 'any' })."
    }
    catch {
        Append-Log "Network tuning warning: QoS policy failed - $($_.Exception.Message)"
    }
}

function Apply-NetworkTuningForSession {
    if (-not $chkNetworkTuningEnabled.Checked) { return $true }

    if (-not (Test-IsAdministrator)) {
        [System.Windows.Forms.MessageBox]::Show(
            'Windows network tuning requires running GStreamer Glass as Administrator. No OS tuning was applied.',
            $script:AppName,
            'OK',
            'Warning'
        ) | Out-Null
        return $false
    }

    try {
        $snapshot = Save-NetworkSnapshot -Quiet
        Register-NetworkRecoveryTask
        $adapterName = [string]$snapshot.AdapterName

        Append-Log "Network tuning: applying profile '$([string]$cmbNetworkProfile.SelectedItem)' to adapter '$adapterName'."

        if ($chkNetworkDscp.Checked) {
            New-QosPolicyForGStreamer -DscpValue ([int]$numNetworkDscp.Value)
        }

        switch ([string]$cmbNetworkUso.SelectedItem) {
            'Enable' { Set-UdpGlobalOffload -Name uso -State enabled | Out-Null }
            'Disable' { Set-UdpGlobalOffload -Name uso -State disabled | Out-Null }
        }
        switch ([string]$cmbNetworkUro.SelectedItem) {
            'Enable' { Set-UdpGlobalOffload -Name uro -State enabled | Out-Null }
            'Disable' { Set-UdpGlobalOffload -Name uro -State disabled | Out-Null }
        }

        if ($chkNetworkDisablePowerSaving.Checked) {
            Set-NetworkPowerSavingDisabled -AdapterName $adapterName | Out-Null
        }

        switch ([string]$cmbNetworkInterruptModeration.SelectedItem) {
            'Disable' {
                Set-AdapterAdvancedPropertyByCandidates -AdapterName $adapterName -DisplayNames @('Interrupt Moderation','Interrupt Moderation Rate') -DesiredValues @('Disabled','Off') | Out-Null
            }
            'Enable / Adaptive' {
                Set-AdapterAdvancedPropertyByCandidates -AdapterName $adapterName -DisplayNames @('Interrupt Moderation','Interrupt Moderation Rate') -DesiredValues @('Adaptive','Enabled','On') | Out-Null
            }
        }

        if ($chkNetworkDisableEee.Checked) {
            Set-AdapterAdvancedPropertyByCandidates -AdapterName $adapterName -DisplayNames @('Energy Efficient Ethernet','EEE','Green Ethernet','Advanced EEE') -DesiredValues @('Disabled','Off') | Out-Null
        }

        Set-NetworkAppliedState -Active $true
        $lblNetworkStatus.Text = 'Network tuning applied. Recovery snapshot saved.'
        $lblNetworkStatus.ForeColor = [System.Drawing.Color]::DarkGreen
        return $true
    }
    catch {
        Append-Log "Network tuning failed before stream start: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            "Network tuning failed before stream start.`r`n`r`n$($_.Exception.Message)",
            $script:AppName,
            'OK',
            'Warning'
        ) | Out-Null
        return $false
    }
}

function Restore-NetworkTuning {
    param([switch]$Quiet)

    if (-not (Test-Path -LiteralPath $script:NetworkSnapshotPath)) {
        if (-not $Quiet) { Append-Log 'Network restore: no snapshot found.' }
        return $false
    }

    if (-not (Test-IsAdministrator)) {
        if (-not $Quiet) {
            [System.Windows.Forms.MessageBox]::Show(
                'Restoring Windows network tuning requires running as Administrator.',
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
        }
        return $false
    }

    try {
        $snapshot = Get-Content -LiteralPath $script:NetworkSnapshotPath -Raw | ConvertFrom-Json
        $adapterName = [string]$snapshot.AdapterName
        Append-Log "Network restore: restoring adapter '$adapterName' from $script:NetworkSnapshotPath"

        try {
            if (Get-Command Remove-NetQosPolicy -ErrorAction SilentlyContinue) {
                Remove-NetQosPolicy -Name ([string]$snapshot.QosPolicyName) -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                Append-Log 'Network restore: removed GStreamer Glass QoS policy.'
            }
        }
        catch {}

        if ($snapshot.UdpGlobal) {
            $usoRestoreState = Get-SnapshotUdpOffloadState -UdpGlobal $snapshot.UdpGlobal -Name uso
            $uroRestoreState = Get-SnapshotUdpOffloadState -UdpGlobal $snapshot.UdpGlobal -Name uro
            if ($usoRestoreState) {
                Set-UdpGlobalOffload -Name uso -State $usoRestoreState | Out-Null
            }
            elseif ($snapshot.UdpGlobal.Uso) {
                Append-Log "Network restore: skipped invalid saved UDP USO state '$($snapshot.UdpGlobal.Uso)'."
            }
            if ($uroRestoreState) {
                Set-UdpGlobalOffload -Name uro -State $uroRestoreState | Out-Null
            }
            elseif ($snapshot.UdpGlobal.Uro) {
                Append-Log "Network restore: skipped invalid saved UDP URO state '$($snapshot.UdpGlobal.Uro)'."
            }
        }

        if ((Get-Command Set-NetAdapterAdvancedProperty -ErrorAction SilentlyContinue) -and $snapshot.AdvancedProperties) {
            foreach ($prop in $snapshot.AdvancedProperties) {
                if (-not [string]::IsNullOrWhiteSpace([string]$prop.DisplayName)) {
                    try {
                        Set-NetAdapterAdvancedProperty -Name $adapterName -DisplayName ([string]$prop.DisplayName) -DisplayValue ([string]$prop.DisplayValue) -NoRestart -ErrorAction SilentlyContinue | Out-Null
                    }
                    catch {}
                }
            }
            Append-Log 'Network restore: adapter advanced properties restored where supported.'
        }

        if ((Get-Command Set-NetAdapterPowerManagement -ErrorAction SilentlyContinue) -and $snapshot.PowerManagement) {
            try {
                $params = @{ Name = $adapterName; ErrorAction = 'SilentlyContinue' }
                foreach ($p in $snapshot.PowerManagement.PSObject.Properties) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$p.Value)) { $params[$p.Name] = [string]$p.Value }
                }
                if ($params.Count -gt 2) { Set-NetAdapterPowerManagement @params | Out-Null }
                Append-Log 'Network restore: adapter power management restored where supported.'
            }
            catch {}
        }

        Unregister-NetworkRecoveryTask
        Set-NetworkAppliedState -Active $false
        $lblNetworkStatus.Text = 'Network settings restored from snapshot.'
        $lblNetworkStatus.ForeColor = [System.Drawing.Color]::DarkGreen
        return $true
    }
    catch {
        Append-Log "Network restore failed: $($_.Exception.Message)"
        if (-not $Quiet) {
            [System.Windows.Forms.MessageBox]::Show(
                "Network restore failed.`r`n`r`n$($_.Exception.Message)",
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
        }
        return $false
    }
}

function Check-PendingNetworkRecovery {
    $state = Get-NetworkAppliedState
    if ($state -and $state.Active -eq $true) {
        $result = [System.Windows.Forms.MessageBox]::Show(
            "GStreamer Glass detected Windows network tuning from a previous session.`r`n`r`nRestore the saved network snapshot now?",
            $script:AppName,
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            Restore-NetworkTuning | Out-Null
        }
        else {
            $lblNetworkStatus.Text = 'Previous network tuning is still marked active.'
            $lblNetworkStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
    }
}

