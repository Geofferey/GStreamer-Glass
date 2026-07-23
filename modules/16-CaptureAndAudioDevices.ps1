function Update-TransportUi {
    $enabled = Test-TransportEnabled
    foreach ($control in @($cmbProtocol, $txtDestination, $lblDestination, $cmbTimingMode, $chkStartMediaMtx)) {
        if ($control) { $control.Enabled = $enabled }
    }

    Update-MediaMtxUi
    Update-DirectWebRtcUi
    Update-ProtocolUi
    Update-CommandPreview
}

function Get-SelectedCaptureMethodName {
    $name = [string]$cmbCaptureMethod.SelectedItem
    if (-not [string]::IsNullOrWhiteSpace($name) -and $script:CaptureMethodCatalog.Contains($name)) {
        return $name
    }

    if ($chkFullscreenApp.Checked) {
        return 'Fullscreen App - D3D11 / WGC'
    }

    return $script:DefaultCaptureMethodName
}

function Get-SelectedCaptureMethod {
    $name = Get-SelectedCaptureMethodName
    return $script:CaptureMethodCatalog[$name]
}

function Test-FullscreenCaptureMode {
    $method = Get-SelectedCaptureMethod
    return [bool]$method.RequiresFullscreenWindow
}

function Sync-LegacyFullscreenFlag {
    $isFullscreenMode = Test-FullscreenCaptureMode
    if ($chkFullscreenApp.Checked -ne $isFullscreenMode) {
        $chkFullscreenApp.Checked = $isFullscreenMode
    }
}

function Update-CaptureModeUi {
    $methodName = Get-SelectedCaptureMethodName
    $method = Get-SelectedCaptureMethod
    $isFullscreenMode = [bool]$method.RequiresFullscreenWindow

    if ($cmbCaptureMethod.SelectedItem -ne $methodName -and $cmbCaptureMethod.Items.Contains($methodName)) {
        $cmbCaptureMethod.SelectedItem = $methodName
    }

    if ($chkFullscreenApp.Checked -ne $isFullscreenMode) {
        $chkFullscreenApp.Checked = $isFullscreenMode
    }

    $numMonitor.Enabled = -not $isFullscreenMode

    if ($isFullscreenMode) {
        if ($script:CaptureWindowHwnd -ne [IntPtr]::Zero -and $script:CaptureWindowTitle) {
            $lblCaptureModeStatus.Text = "Fullscreen target: $($script:CaptureWindowTitle)"
            $lblCaptureModeStatus.ForeColor = [System.Drawing.Color]::DarkGreen
        }
        else {
            $lblCaptureModeStatus.Text = 'Fullscreen WGC - waiting starts automatically'
            $lblCaptureModeStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
    }
    else {
        $hint = switch ([string]$method.Method) {
            'MonitorD3D11Dxgi' { 'DXGI monitor capture' }
            'MonitorD3D11Wgc'  { 'WGC monitor capture' }
            'MonitorGdi'       { 'GDI fallback capture' }
            default            { 'Monitor capture' }
        }
        $lblCaptureModeStatus.Text = "$hint (index $([int]$numMonitor.Value))"
        $lblCaptureModeStatus.ForeColor = [System.Drawing.Color]::DimGray
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$method.Description)) {
        $toolTip.SetToolTip($cmbCaptureMethod, [string]$method.Description)
    }
}

function Resolve-FullscreenCaptureTarget {
    param([switch]$Quiet)

    if (-not (Test-FullscreenCaptureMode)) {
        $script:CaptureWindowHwnd = [IntPtr]::Zero
        $script:CaptureWindowTitle = ''
        Update-CaptureModeUi
        return $true
    }

    $gstPid = 0
    if ((Test-DirectWebRtcUnifiedPublisher) -and $script:GstVideoProcess -and -not $script:GstVideoProcess.HasExited) {
        $gstPid = $script:GstVideoProcess.Id
    }
    elseif ($script:GstProcess -and -not $script:GstProcess.HasExited) {
        $gstPid = $script:GstProcess.Id
    }

    $candidate = [GstPreviewNative]::FindTopmostFullscreenWindow($PID, $gstPid)
    if ($candidate -eq [IntPtr]::Zero) {
        $script:CaptureWindowHwnd = [IntPtr]::Zero
        $script:CaptureWindowTitle = ''
        Update-CaptureModeUi

        return $false
    }

    $script:CaptureWindowHwnd = $candidate
    $script:CaptureWindowTitle = [GstPreviewNative]::GetWindowTitleSafe($candidate)
    Update-CaptureModeUi
    return $true
}

function Get-QueueLeakValue {
    $mode = Get-ComboSelectedOrDefault $cmbQueueLeakMode $script:DefaultQueueLeakMode
    switch ($mode) {
        'Upstream - drop new' { return 'upstream' }
        'No leak - block' { return 'no' }
        default { return 'downstream' }
    }
}

function Get-EffectiveLiveQueueLeakValue {
    # Live streaming should not silently preserve old frames. Blocking queues are
    # allowed only in the explicit Blocking diagnostic profile; otherwise a stale
    # saved setting of 'No leak - block' is coerced to downstream/drop-old.
    $leak = Get-QueueLeakValue
    $profile = Get-ComboSelectedOrDefault $cmbThreadingProfile $script:DefaultThreadingProfile
    if ($leak -eq 'no' -and $profile -ne 'Blocking diagnostic') { return 'downstream' }
    return $leak
}

function Get-AudioTimingMode {
    return (Get-ComboSelectedOrDefault $cmbAudioTimingMode $script:DefaultAudioTimingMode)
}

function Get-WasapiClockOption {
    $clockMode = Get-ComboSelectedOrDefault $cmbAudioClockMode $script:DefaultAudioClockMode
    $timingMode = Get-AudioTimingMode
    if ($clockMode -eq 'System clock / no WASAPI clock' -or $timingMode -in @('WASAPI no pipeline clock','WASAPI no clock + retimestamp')) {
        return 'provide-clock=false'
    }
    return ''
}

function Get-WasapiTimestampOption {
    $timingMode = Get-AudioTimingMode
    if ($timingMode -in @('WASAPI retimestamp','WASAPI no clock + retimestamp')) { return 'do-timestamp=true' }
    return ''
}

function Get-WasapiSlaveMethodOption {
    $mode = Get-ComboSelectedOrDefault $cmbAudioSlaveMethod $script:DefaultAudioSlaveMethod
    switch ($mode) {
        'None' { return 'slave-method=none' }
        'Skew' { return 'slave-method=skew' }
        'Resample' { return 'slave-method=resample' }
        'Retimestamp' { return 'slave-method=re-timestamp' }
        default { return '' }
    }
}

function Get-WasapiLowLatencyOption {
    if ($chkWasapiLowLatencyOverride -and $chkWasapiLowLatencyOverride.Checked) { return 'low-latency=true' }
    return ''
}

function Get-WasapiBufferTimeOption {
    if (-not $chkAudioBufferOverride -or -not $chkAudioBufferOverride.Checked) { return '' }
    $ms = [int]$numAudioBufferMs.Value
    if ($ms -le 0) { return '' }
    return ('buffer-time=' + ([int64]$ms * 1000))
}

function Get-WasapiLatencyTimeOption {
    if (-not $chkAudioLatencyOverride -or -not $chkAudioLatencyOverride.Checked) { return '' }
    $ms = [int]$numAudioLatencyMs.Value
    if ($ms -le 0) { return '' }
    return ('latency-time=' + ([int64]$ms * 1000))
}

function Get-AudioSampleRateOverrideValue {
    if (-not $chkAudioSampleRateOverride -or -not $chkAudioSampleRateOverride.Checked) { return 0 }
    $rate = [int]$numAudioSampleRate.Value
    if ($rate -le 0) { return 0 }
    return $rate
}

function Get-AudioRawCapsString {
    param(
        [ValidateSet('S16LE','F32LE')][string]$Format = 'S16LE',
        [int]$Channels = 2
    )

    $fields = New-Object System.Collections.Generic.List[string]
    $fields.Add('audio/x-raw')
    $fields.Add("format=$Format")
    $rate = Get-AudioSampleRateOverrideValue
    if ($rate -gt 0) { $fields.Add("rate=$rate") }
    if ($Channels -gt 0) { $fields.Add("channels=$Channels") }
    return ('"' + ($fields -join ',') + '"')
}

function Clean-GstDevicePropertyValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $v = $Value.Trim()
    $v = $v -replace '^\([^)]+\)\s*', ''
    $v = $v.Trim()
    if ($v.Length -ge 2 -and $v.StartsWith('"') -and $v.EndsWith('"')) {
        $v = $v.Substring(1, $v.Length - 2)
    }
    return $v.Trim()
}

function Get-GstDeviceMonitorPath {
    $gstPath = $txtGstPath.Text.Trim()
    if (-not [string]::IsNullOrWhiteSpace($gstPath) -and (Test-Path -LiteralPath $gstPath)) {
        # Windows PowerShell can throw a ParameterBindingException for Split-Path -LiteralPath ... -Parent.
        # Use .NET path handling here so the Refresh audio devices button is ps2exe/WinPS safe.
        $dir = [System.IO.Path]::GetDirectoryName($gstPath)
        if (-not [string]::IsNullOrWhiteSpace($dir)) {
            $candidate = Join-Path -Path $dir -ChildPath 'gst-device-monitor-1.0.exe'
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
    }
    return 'gst-device-monitor-1.0.exe'
}

function Set-AudioDeviceComboDefaults {
    if ($cmbDesktopAudioDevice) {
        $cmbDesktopAudioDevice.BeginUpdate()
        try {
            $cmbDesktopAudioDevice.Items.Clear()
            [void]$cmbDesktopAudioDevice.Items.Add($script:DefaultAudioOutputDeviceLabel)
            $cmbDesktopAudioDevice.SelectedIndex = 0
        }
        finally { $cmbDesktopAudioDevice.EndUpdate() }
    }
    if ($cmbMicAudioDevice) {
        $cmbMicAudioDevice.BeginUpdate()
        try {
            $cmbMicAudioDevice.Items.Clear()
            [void]$cmbMicAudioDevice.Items.Add($script:DefaultAudioInputDeviceLabel)
            $cmbMicAudioDevice.SelectedIndex = 0
        }
        finally { $cmbMicAudioDevice.EndUpdate() }
    }
    $script:AudioOutputDeviceMap = @{}
    $script:AudioInputDeviceMap = @{}
}

function Add-AudioDeviceComboItem {
    param(
        [ValidateSet('Output','Input')][string]$Kind,
        [string]$Name,
        [string]$DeviceId
    )

    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $cleanName = $Name.Trim()
    $cleanId = (Clean-GstDevicePropertyValue $DeviceId)
    if ([string]::IsNullOrWhiteSpace($cleanId)) { $cleanId = $cleanName }

    $shortId = $cleanId
    if ($shortId.Length -gt 28) { $shortId = $shortId.Substring($shortId.Length - 28) }
    $label = "$cleanName  [$shortId]"

    if ($Kind -eq 'Output') {
        if (-not $cmbDesktopAudioDevice.Items.Contains($label)) { [void]$cmbDesktopAudioDevice.Items.Add($label) }
        $script:AudioOutputDeviceMap[$label] = $cleanId
    }
    else {
        if (-not $cmbMicAudioDevice.Items.Contains($label)) { [void]$cmbMicAudioDevice.Items.Add($label) }
        $script:AudioInputDeviceMap[$label] = $cleanId
    }
}

function Restore-AudioDeviceSelection {
    param(
        [ValidateSet('Output','Input')][string]$Kind,
        [string]$Label,
        [string]$DeviceId
    )

    if ([string]::IsNullOrWhiteSpace($Label)) { return }
    $combo = if ($Kind -eq 'Output') { $cmbDesktopAudioDevice } else { $cmbMicAudioDevice }
    $mapName = if ($Kind -eq 'Output') { 'AudioOutputDeviceMap' } else { 'AudioInputDeviceMap' }
    if (-not $combo) { return }

    if (-not $combo.Items.Contains($Label)) {
        [void]$combo.Items.Add($Label)
        if (-not [string]::IsNullOrWhiteSpace($DeviceId)) {
            (Get-Variable -Name $mapName -Scope Script).Value[$Label] = [string]$DeviceId
        }
    }
    if ($combo.Items.Contains($Label)) { $combo.SelectedItem = $Label }
}

function Refresh-AudioDevices {
    param([switch]$Quiet)

    $previousOutput = if ($cmbDesktopAudioDevice -and $cmbDesktopAudioDevice.SelectedItem) { [string]$cmbDesktopAudioDevice.SelectedItem } else { $script:DefaultAudioOutputDeviceLabel }
    $previousInput = if ($cmbMicAudioDevice -and $cmbMicAudioDevice.SelectedItem) { [string]$cmbMicAudioDevice.SelectedItem } else { $script:DefaultAudioInputDeviceLabel }

    Set-AudioDeviceComboDefaults

    $monitor = Get-GstDeviceMonitorPath
    try {
        $raw = & $monitor Audio/Source Audio/Sink 2>&1 | Out-String
        $lines = $raw -split "`r?`n"
        $device = $null
        $outputCount = 0
        $inputCount = 0

        function Flush-ParsedAudioDevice {
            param($Parsed)
            if ($null -eq $Parsed) { return }
            $name = [string]$Parsed.Name
            $class = [string]$Parsed.Class
            $devId = [string]$Parsed.DeviceId
            if ([string]::IsNullOrWhiteSpace($name)) { return }
            if ($class -match 'Audio/Sink') {
                Add-AudioDeviceComboItem -Kind Output -Name $name -DeviceId $devId
                $script:__AudioDeviceOutputCount++
            }
            elseif ($class -match 'Audio/Source') {
                Add-AudioDeviceComboItem -Kind Input -Name $name -DeviceId $devId
                $script:__AudioDeviceInputCount++
            }
        }

        $script:__AudioDeviceOutputCount = 0
        $script:__AudioDeviceInputCount = 0
        foreach ($line in $lines) {
            if ($line -match '^\s*Device found:') {
                Flush-ParsedAudioDevice $device
                $device = [ordered]@{ Name = ''; Class = ''; DeviceId = '' }
                continue
            }
            if ($null -eq $device) { continue }
            if ($line -match '^\s*name\s*:\s*(.+)$') {
                $device.Name = (Clean-GstDevicePropertyValue $Matches[1])
                continue
            }
            if ($line -match '^\s*class\s*:\s*(.+)$') {
                $device.Class = (Clean-GstDevicePropertyValue $Matches[1])
                continue
            }
            if ($line -match '^\s*(device\.strid|device\.id|device\.path|wasapi\.[^=]*strid|wasapi\.[^=]*id)\s*=\s*(.+)$') {
                if ([string]::IsNullOrWhiteSpace([string]$device.DeviceId)) {
                    $device.DeviceId = (Clean-GstDevicePropertyValue $Matches[2])
                }
                continue
            }
            if ($line -match '^\s*(device\.name|wasapi\.device\.description)\s*=\s*(.+)$') {
                if ([string]::IsNullOrWhiteSpace([string]$device.Name)) {
                    $device.Name = (Clean-GstDevicePropertyValue $Matches[2])
                }
                continue
            }
        }
        Flush-ParsedAudioDevice $device
        $outputCount = [int]$script:__AudioDeviceOutputCount
        $inputCount = [int]$script:__AudioDeviceInputCount
        Remove-Variable -Name __AudioDeviceOutputCount -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name __AudioDeviceInputCount -Scope Script -ErrorAction SilentlyContinue

        if ($cmbDesktopAudioDevice.Items.Contains($previousOutput)) { $cmbDesktopAudioDevice.SelectedItem = $previousOutput }
        if ($cmbMicAudioDevice.Items.Contains($previousInput)) { $cmbMicAudioDevice.SelectedItem = $previousInput }
        if ($lblAudioDeviceStatus) {
            $lblAudioDeviceStatus.Text = "Audio devices: $outputCount output / $inputCount input"
            $lblAudioDeviceStatus.ForeColor = if ($outputCount -gt 0 -or $inputCount -gt 0) { [System.Drawing.Color]::DarkGreen } else { [System.Drawing.Color]::DarkOrange }
        }
        if (-not $Quiet) { Append-Log "Audio device refresh: $outputCount output loopback device(s), $inputCount input capture device(s)." }
    }
    catch {
        if ($lblAudioDeviceStatus) {
            $lblAudioDeviceStatus.Text = 'Audio device refresh failed; using defaults'
            $lblAudioDeviceStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        if (-not $Quiet) { Append-Log "Audio device refresh failed: $($_.Exception.Message)" }
    }

    try {
        Update-CommandPreview
    }
    catch {
        if (-not $Quiet) { Append-Log "Audio device refresh preview update failed: $($_.Exception.Message)" }
    }
}

function Get-SelectedWasapiDeviceOption {
    param([ValidateSet('Output','Input')][string]$Kind)

    if ($Kind -eq 'Output') {
        if (-not $cmbDesktopAudioDevice -or -not $cmbDesktopAudioDevice.SelectedItem) { return '' }
        $label = [string]$cmbDesktopAudioDevice.SelectedItem
        if ($label -eq $script:DefaultAudioOutputDeviceLabel) { return '' }
        $id = [string]$script:AudioOutputDeviceMap[$label]
    }
    else {
        if (-not $cmbMicAudioDevice -or -not $cmbMicAudioDevice.SelectedItem) { return '' }
        $label = [string]$cmbMicAudioDevice.SelectedItem
        if ($label -eq $script:DefaultAudioInputDeviceLabel) { return '' }
        $id = [string]$script:AudioInputDeviceMap[$label]
    }

    if ([string]::IsNullOrWhiteSpace($id)) { return '' }
    return ('device=' + (Quote-GstValue $id))
}

function Get-SelectedAudioDeviceId {
    param([ValidateSet('Output','Input')][string]$Kind)
    if ($Kind -eq 'Output') {
        $label = if ($cmbDesktopAudioDevice -and $cmbDesktopAudioDevice.SelectedItem) { [string]$cmbDesktopAudioDevice.SelectedItem } else { '' }
        return [string]$script:AudioOutputDeviceMap[$label]
    }
    $label = if ($cmbMicAudioDevice -and $cmbMicAudioDevice.SelectedItem) { [string]$cmbMicAudioDevice.SelectedItem } else { '' }
    return [string]$script:AudioInputDeviceMap[$label]
}

function Get-AudioSourceSelectionSummary {
    $parts = New-Object System.Collections.Generic.List[string]
    if ($chkDesktopAudio.Checked) {
        $label = if ($cmbDesktopAudioDevice -and $cmbDesktopAudioDevice.SelectedItem) { [string]$cmbDesktopAudioDevice.SelectedItem } else { $script:DefaultAudioOutputDeviceLabel }
        $parts.Add("desktop loopback=$label")
    }
    if ($chkMic.Checked) {
        $label = if ($cmbMicAudioDevice -and $cmbMicAudioDevice.SelectedItem) { [string]$cmbMicAudioDevice.SelectedItem } else { $script:DefaultAudioInputDeviceLabel }
        $parts.Add("mic/input=$label")
    }
    if ($parts.Count -eq 0) { return 'none' }
    return ($parts -join '; ')
}

function Get-WasapiSourceString {
    param([switch]$Loopback)

    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add('wasapi2src')
    $deviceOpt = if ($Loopback) { Get-SelectedWasapiDeviceOption -Kind Output } else { Get-SelectedWasapiDeviceOption -Kind Input }
    if (-not [string]::IsNullOrWhiteSpace($deviceOpt)) { $parts.Add($deviceOpt) }
    foreach ($opt in @(
        (Get-WasapiClockOption),
        (Get-WasapiTimestampOption),
        (Get-WasapiSlaveMethodOption),
        (Get-WasapiLowLatencyOption),
        (Get-WasapiBufferTimeOption),
        (Get-WasapiLatencyTimeOption)
    )) {
        if (-not [string]::IsNullOrWhiteSpace($opt)) { $parts.Add($opt) }
    }

    if ($Loopback) { $parts.Add('loopback=true') }
    return ($parts -join ' ')
}

function Get-VideoPipelineClockMode {
    return (Get-ComboSelectedOrDefault $cmbVideoPipelineClockMode $script:DefaultVideoPipelineClockMode)
}

function Get-SplitAudioPipelineClockMode {
    $mode = Get-ComboSelectedOrDefault $cmbSplitAudioPipelineClockMode $script:DefaultSplitAudioPipelineClockMode
    if ($mode -eq 'Follow video/master') { return (Get-VideoPipelineClockMode) }
    return $mode
}

function Get-ClockSelectIdForMode {
    param([Parameter(Mandatory)][string]$Mode)

    switch ($Mode) {
        'System monotonic' { return 'monotonic' }
        'System realtime'  { return 'realtime' }
        default            { return '' }
    }
}

function Wrap-GstPipelineWithClockSelect {
    param(
        [Parameter(Mandatory)][string]$Pipeline,
        [Parameter(Mandatory)][string]$ClockMode
    )

    $clockId = Get-ClockSelectIdForMode -Mode $ClockMode
    if ([string]::IsNullOrWhiteSpace($clockId)) { return $Pipeline }

    # clockselect is a GstPipeline subclass exposed specifically so gst-launch can
    # force a pipeline clock. Parentheses contain the complete graph; shell escape
    # backslashes shown in Unix documentation are not part of Windows ArgumentList.
    return "clockselect. ( clock-id=$clockId $Pipeline )"
}

function Get-VideoTimestampMode {
    return (Get-ComboSelectedOrDefault $cmbVideoTimestampMode $script:DefaultVideoTimestampMode)
}

function Get-VideoSourceTimestampOption {
    switch (Get-VideoTimestampMode) {
        'Pipeline running-time' { return 'do-timestamp=true' }
        'Source timestamps'     { return 'do-timestamp=false' }
        default                 { return '' }
    }
}

function Add-VideoSourceTimestampOption {
    param([Parameter(Mandatory)][string]$SourceText)

    $option = Get-VideoSourceTimestampOption
    if ([string]::IsNullOrWhiteSpace($option)) { return $SourceText }
    return "$SourceText $option"
}

function Get-VideoSyncMode {
    return (Get-ComboSelectedOrDefault $cmbVideoSyncMode $script:DefaultVideoSyncMode)
}

function Get-AudioSyncMode {
    return (Get-ComboSelectedOrDefault $cmbAudioSyncMode $script:DefaultAudioSyncMode)
}

