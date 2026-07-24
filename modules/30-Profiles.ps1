function Get-BuiltInProfiles {
    # Bundled preset numeric choices (GOP length, encoder preset/tune, bitrate) are informed
    # engineering judgment based on each protocol's typical latency/quality tradeoff, not an
    # official GStreamer-published preset table -- GStreamer does not publish one. Applying any
    # profile first runs Reset-AllAppDefaults for a fully deterministic baseline, then overlays
    # only the fields below -- so these are deltas from that baseline, not a full 190-field
    # enumeration.
    return @(
        [ordered]@{
            _Schema              = 'GStreamerGlassProfile'
            _SchemaVersion       = 1
            _AppVersion          = $script:AppVersion
            _ProfileName         = 'WHIP - Low Latency'
            _ProfileDescription  = 'Short GOP, no B-frames/lookahead, ultra-low-latency tune for WHIP publishing.'
            _CompatibleProtocols = @('WHIP')
            _IsBuiltIn           = $true
            Protocol             = 'WHIP'
            GopSeconds           = 1
            RateControl          = 'cbr'
            EncoderTune          = 'ultra-low-latency'
            Multipass            = 'disabled'
            BFrames              = 0
            LookAhead            = $false
            AdaptiveQuantization = $false
            TemporalAq           = $false
            WhipAudioCodec       = 'Opus'
            AudioBitrateKbps     = 160
        }
        [ordered]@{
            _Schema              = 'GStreamerGlassProfile'
            _SchemaVersion       = 1
            _AppVersion          = $script:AppVersion
            _ProfileName         = 'GST WebRTC - Low Latency'
            _ProfileDescription  = 'Same low-latency tuning as the WHIP preset, for the built-in web viewer.'
            _CompatibleProtocols = @('GST WebRTC')
            _IsBuiltIn           = $true
            Protocol             = 'GST WebRTC'
            GopSeconds           = 1
            RateControl          = 'cbr'
            EncoderTune          = 'ultra-low-latency'
            Multipass            = 'disabled'
            BFrames              = 0
            LookAhead            = $false
            AdaptiveQuantization = $false
            TemporalAq           = $false
            GstWebRtcAudioCodec  = 'Opus'
            AudioBitrateKbps     = 160
        }
        [ordered]@{
            _Schema              = 'GStreamerGlassProfile'
            _SchemaVersion       = 1
            _AppVersion          = $script:AppVersion
            _ProfileName         = 'SRT - Balanced'
            _ProfileDescription  = 'Longer GOP with B-frames/lookahead for better quality per bit. SRT latency near the documented srtsink default (125ms).'
            _CompatibleProtocols = @('SRT')
            _IsBuiltIn           = $true
            Protocol             = 'SRT'
            GopSeconds           = 2
            RateControl          = 'vbr'
            EncoderTune          = 'high-quality'
            Multipass            = 'two-pass-quarter'
            BFrames              = 2
            LookAhead            = $true
            LookAheadFrames      = 20
            AdaptiveQuantization = $true
            TemporalAq           = $true
            VideoBitrateKbps     = 16000
            SrtLatency           = 125
            SrtAudioCodec        = 'Opus'
            AudioBitrateKbps     = 192
        }
        [ordered]@{
            _Schema              = 'GStreamerGlassProfile'
            _SchemaVersion       = 1
            _AppVersion          = $script:AppVersion
            _ProfileName         = 'RTMP - Quality'
            _ProfileDescription  = 'Longer GOP and higher-quality encoder tuning with a static bitrate (RTMP has no congestion-control concept).'
            _CompatibleProtocols = @('RTMP')
            _IsBuiltIn           = $true
            Protocol             = 'RTMP'
            GopSeconds           = 2
            Preset               = 'p5'
            RateControl          = 'vbr'
            EncoderTune          = 'high-quality'
            Multipass            = 'two-pass-quarter'
            BFrames              = 3
            LookAhead            = $true
            LookAheadFrames      = 32
            AdaptiveQuantization = $true
            TemporalAq           = $true
            VideoBitrateKbps     = 18000
            RtmpAudioCodec       = 'AAC'
            AudioBitrateKbps     = 192
        }
        [ordered]@{
            _Schema              = 'GStreamerGlassProfile'
            _SchemaVersion       = 1
            _AppVersion          = $script:AppVersion
            _ProfileName         = 'RTSP - Balanced'
            _ProfileDescription  = 'Longer GOP with B-frames/lookahead for better quality per bit, similar to the SRT balanced preset.'
            _CompatibleProtocols = @('RTSP')
            _IsBuiltIn           = $true
            Protocol             = 'RTSP'
            GopSeconds           = 2
            RateControl          = 'vbr'
            EncoderTune          = 'high-quality'
            Multipass            = 'two-pass-quarter'
            BFrames              = 2
            LookAhead            = $true
            LookAheadFrames      = 20
            AdaptiveQuantization = $true
            TemporalAq           = $true
            VideoBitrateKbps     = 16000
            RtspTransport        = 'TCP'
            RtspAudioCodec       = 'Opus'
            AudioBitrateKbps     = 192
        }
    )
}

function Ensure-ProfilesDirectory {
    if (-not (Test-Path -LiteralPath $script:ProfilesDirectory)) {
        $null = New-Item -ItemType Directory -Path $script:ProfilesDirectory -Force
    }
}

function Get-UserProfiles {
    Ensure-ProfilesDirectory
    $profiles = New-Object System.Collections.Generic.List[object]
    foreach ($file in (Get-ChildItem -Path $script:ProfilesDirectory -Filter '*.json' -ErrorAction SilentlyContinue)) {
        try {
            $obj = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            if ($obj._ProfileName) {
                $profiles.Add($obj)
            }
        }
        catch {
            Append-Log "Could not read profile file $($file.FullName): $($_.Exception.Message)"
        }
    }
    # NOTE: `@($profiles)` (wrapping a List[object] in the array subexpression operator) throws
    # "Argument types do not match" from PSToObjectArrayBinder/MaybeDebase on this PowerShell
    # runtime -- reproduced directly, isolated to List[object] specifically (List[string]/List[int]
    # are unaffected). .ToArray() is a plain .NET call that never goes through that binder.
    return $profiles.ToArray()
}

function Get-AllProfiles {
    # See the .ToArray() note in Get-UserProfiles above -- same reason here.
    $all = New-Object System.Collections.Generic.List[object]
    foreach ($p in (Get-BuiltInProfiles)) { $all.Add($p) }
    foreach ($p in (Get-UserProfiles)) { $all.Add($p) }
    return $all.ToArray()
}

function Test-ProfileProtocolCompatibility {
    param(
        [Parameter(Mandatory)]$Profile,
        [Parameter(Mandatory)][string]$Protocol
    )
    $compat = @($Profile._CompatibleProtocols)
    return ($compat -contains 'ALL' -or $compat -contains $Protocol)
}

function Get-CompatibleProfileNames {
    param([Parameter(Mandatory)][string]$Protocol)
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($p in (Get-AllProfiles)) {
        if (Test-ProfileProtocolCompatibility -Profile $p -Protocol $Protocol) {
            $names.Add([string]$p._ProfileName)
        }
    }
    return @($names)
}

function Refresh-ProfileList {
    if (-not $cmbProfilePreset) { return }
    $protocol = [string]$cmbProtocol.SelectedItem
    if ([string]::IsNullOrWhiteSpace($protocol)) { $protocol = 'WHIP' }
    $previous = [string]$cmbProfilePreset.SelectedItem
    $names = Get-CompatibleProfileNames -Protocol $protocol

    $cmbProfilePreset.BeginUpdate()
    try {
        $cmbProfilePreset.Items.Clear()
        foreach ($name in $names) { $null = $cmbProfilePreset.Items.Add($name) }
        if ($previous -and $cmbProfilePreset.Items.Contains($previous)) {
            $cmbProfilePreset.SelectedItem = $previous
        }
        elseif ($cmbProfilePreset.Items.Count -gt 0) {
            $cmbProfilePreset.SelectedIndex = 0
        }
    }
    finally {
        $cmbProfilePreset.EndUpdate()
    }
    Update-ProfileSelectionUi
}

function Update-ProfileSelectionUi {
    if (-not $cmbProfilePreset) { return }
    $selected = [string]$cmbProfilePreset.SelectedItem
    $profile = if ($selected) { Get-AllProfiles | Where-Object { [string]$_._ProfileName -eq $selected } | Select-Object -First 1 } else { $null }

    if ($profile) {
        $isBuiltIn = [bool]$profile._IsBuiltIn
        $protocols = ([string[]]@($profile._CompatibleProtocols)) -join ', '
        $description = [string]$profile._ProfileDescription
        if ($lblProfileDescription) {
            $kind = if ($isBuiltIn) { 'Built-in' } else { 'Custom' }
            $lblProfileDescription.Text = "$kind * compatible with: $protocols. $description"
        }
        if ($btnSaveProfile) { $btnSaveProfile.Enabled = -not $isBuiltIn }
        if ($btnDeleteProfile) { $btnDeleteProfile.Enabled = -not $isBuiltIn }
    }
    else {
        if ($lblProfileDescription) { $lblProfileDescription.Text = 'No profile selected.' }
        if ($btnSaveProfile) { $btnSaveProfile.Enabled = $false }
        if ($btnDeleteProfile) { $btnDeleteProfile.Enabled = $false }
    }
}

function Get-CurrentSettingsSnapshot {
    # Mirrors Export-LabConfiguration's own "save first so the export reflects exact current UI
    # state" approach.
    Save-Settings
    Update-CommandPreview
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
        throw "The live settings file was not created: $script:ConfigPath"
    }
    return (Get-Content -LiteralPath $script:ConfigPath -Raw | ConvertFrom-Json)
}

function Save-ProfileAs {
    Add-Type -AssemblyName Microsoft.VisualBasic
    $name = [Microsoft.VisualBasic.Interaction]::InputBox('Enter a name for this profile:', 'Save Profile As', '')
    if ([string]::IsNullOrWhiteSpace($name)) { return }

    Ensure-ProfilesDirectory
    $fileName = Get-SafeRecordingToken -Value $name
    $path = Join-Path $script:ProfilesDirectory "$fileName.json"
    if (Test-Path -LiteralPath $path) {
        $result = [System.Windows.Forms.MessageBox]::Show(
            "A profile named '$name' already exists. Overwrite it?",
            $script:AppName,
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($result -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }

    try {
        $snapshot = Get-CurrentSettingsSnapshot
        $protocol = [string]$cmbProtocol.SelectedItem
        $export = [ordered]@{
            _Schema              = 'GStreamerGlassProfile'
            _SchemaVersion       = 1
            _AppVersion          = $script:AppVersion
            _SavedUtc            = [DateTime]::UtcNow.ToString('o')
            _ProfileName         = $name
            _ProfileDescription  = ''
            _CompatibleProtocols = @($protocol)
            _IsBuiltIn           = $false
        }
        foreach ($property in $snapshot.PSObject.Properties) {
            $export[$property.Name] = $property.Value
        }
        $export | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
        Append-Log "Profile saved: $name"
        Refresh-ProfileList
        if ($cmbProfilePreset.Items.Contains($name)) { $cmbProfilePreset.SelectedItem = $name }
    }
    catch {
        Append-Log "Could not save profile: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show("Could not save profile: $($_.Exception.Message)", $script:AppName, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
}

function Save-CurrentProfile {
    $selected = [string]$cmbProfilePreset.SelectedItem
    if ([string]::IsNullOrWhiteSpace($selected)) { return }
    $profile = Get-AllProfiles | Where-Object { [string]$_._ProfileName -eq $selected } | Select-Object -First 1
    if (-not $profile -or [bool]$profile._IsBuiltIn) {
        [System.Windows.Forms.MessageBox]::Show('Built-in profiles cannot be overwritten. Use "Save As..." to create a custom copy.', $script:AppName, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }

    Ensure-ProfilesDirectory
    $fileName = Get-SafeRecordingToken -Value $selected
    $path = Join-Path $script:ProfilesDirectory "$fileName.json"
    try {
        $snapshot = Get-CurrentSettingsSnapshot
        $export = [ordered]@{
            _Schema              = 'GStreamerGlassProfile'
            _SchemaVersion       = 1
            _AppVersion          = $script:AppVersion
            _SavedUtc            = [DateTime]::UtcNow.ToString('o')
            _ProfileName         = $selected
            _ProfileDescription  = [string]$profile._ProfileDescription
            _CompatibleProtocols = @($profile._CompatibleProtocols)
            _IsBuiltIn           = $false
        }
        foreach ($property in $snapshot.PSObject.Properties) {
            $export[$property.Name] = $property.Value
        }
        $export | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
        Append-Log "Profile updated: $selected"
    }
    catch {
        Append-Log "Could not save profile: $($_.Exception.Message)"
    }
}

function Invoke-LoadSelectedProfile {
    $selected = [string]$cmbProfilePreset.SelectedItem
    if ([string]::IsNullOrWhiteSpace($selected)) { return }
    $profile = Get-AllProfiles | Where-Object { [string]$_._ProfileName -eq $selected } | Select-Object -First 1
    if (-not $profile) { return }

    $result = [System.Windows.Forms.MessageBox]::Show(
        "Apply profile '$selected'? This replaces ALL current settings with the profile's saved values.",
        $script:AppName,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $script:LoadingSettings = $true
    $script:SuppressProtocolChange = $true
    try {
        # Full re-replace: reset to a fully known baseline first, then overlay only the
        # profile's own fields, so applying never leaves stale leftover values from before.
        Reset-AllAppDefaults
        Restore-SettingsFromObject -Settings $profile
        Save-Settings
        Append-Log "Profile applied: $selected"
    }
    catch {
        Append-Log "Could not apply profile: $($_.Exception.Message)"
    }
    finally {
        $script:SuppressProtocolChange = $false
        $script:LoadingSettings = $false
        Update-TransportUi
        Update-DirectWebRtcUi
        Update-EncoderUi
        Update-RecordingUi
        Update-NetworkUi
        Update-SceneUi
        Update-CommandPreview
    }
}

function Remove-SelectedProfile {
    $selected = [string]$cmbProfilePreset.SelectedItem
    if ([string]::IsNullOrWhiteSpace($selected)) { return }
    $profile = Get-AllProfiles | Where-Object { [string]$_._ProfileName -eq $selected } | Select-Object -First 1
    if (-not $profile -or [bool]$profile._IsBuiltIn) {
        [System.Windows.Forms.MessageBox]::Show('Built-in profiles cannot be deleted.', $script:AppName, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }

    $result = [System.Windows.Forms.MessageBox]::Show(
        "Delete profile '$selected'? This cannot be undone.",
        $script:AppName,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $fileName = Get-SafeRecordingToken -Value $selected
    $path = Join-Path $script:ProfilesDirectory "$fileName.json"
    try {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
        Append-Log "Profile deleted: $selected"
        Refresh-ProfileList
    }
    catch {
        Append-Log "Could not delete profile: $($_.Exception.Message)"
    }
}

function Import-ProfileFile {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = 'GStreamer Glass files (*.gstglass.json)|*.gstglass.json|JSON files (*.json)|*.json|All files (*.*)|*.*'
    $dialog.Title = 'Import Profile'
    if ($dialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }

    try {
        $imported = Get-Content -LiteralPath $dialog.FileName -Raw | ConvertFrom-Json
        $defaultName = [System.IO.Path]::GetFileNameWithoutExtension($dialog.FileName)
        if ($imported._ProfileName) { $defaultName = [string]$imported._ProfileName }

        Add-Type -AssemblyName Microsoft.VisualBasic
        $name = [Microsoft.VisualBasic.Interaction]::InputBox('Enter a name to save this imported profile as:', 'Import Profile', $defaultName)
        if ([string]::IsNullOrWhiteSpace($name)) { return }

        $compatibleProtocols = if ($imported._CompatibleProtocols) { @($imported._CompatibleProtocols) } elseif ($imported.Protocol) { @([string]$imported.Protocol) } else { @('ALL') }

        Ensure-ProfilesDirectory
        $fileName = Get-SafeRecordingToken -Value $name
        $path = Join-Path $script:ProfilesDirectory "$fileName.json"

        $export = [ordered]@{
            _Schema              = 'GStreamerGlassProfile'
            _SchemaVersion       = 1
            _AppVersion          = $script:AppVersion
            _SavedUtc            = [DateTime]::UtcNow.ToString('o')
            _ProfileName         = $name
            _ProfileDescription  = if ($imported._ProfileDescription) { [string]$imported._ProfileDescription } else { "Imported from $([System.IO.Path]::GetFileName($dialog.FileName))" }
            _CompatibleProtocols = $compatibleProtocols
            _IsBuiltIn           = $false
        }
        foreach ($property in $imported.PSObject.Properties) {
            if ($property.Name.StartsWith('_')) { continue }
            $export[$property.Name] = $property.Value
        }
        $export | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
        Append-Log "Profile imported: $name"
        Refresh-ProfileList
        if ($cmbProfilePreset.Items.Contains($name)) { $cmbProfilePreset.SelectedItem = $name }
    }
    catch {
        Append-Log "Could not import profile: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show("Could not import profile: $($_.Exception.Message)", $script:AppName, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
}

function Export-SelectedProfile {
    $selected = [string]$cmbProfilePreset.SelectedItem
    if ([string]::IsNullOrWhiteSpace($selected)) { return }
    $profile = Get-AllProfiles | Where-Object { [string]$_._ProfileName -eq $selected } | Select-Object -First 1
    if (-not $profile) { return }

    try {
        $dialog = New-Object System.Windows.Forms.SaveFileDialog
        $dialog.Filter = 'GStreamer Glass profile (*.gstglass.json)|*.gstglass.json|All files (*.*)|*.*'
        $dialog.DefaultExt = 'gstglass.json'
        $dialog.AddExtension = $true
        $dialog.OverwritePrompt = $true
        $dialog.FileName = (Get-SafeRecordingToken -Value $selected) + '.gstglass.json'
        if ($dialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }

        $profile | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $dialog.FileName -Encoding UTF8
        Append-Log "Profile exported: $selected -> $($dialog.FileName)"
    }
    catch {
        Append-Log "Could not export profile: $($_.Exception.Message)"
    }
}
