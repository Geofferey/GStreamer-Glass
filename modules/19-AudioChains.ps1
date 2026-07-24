function Build-RawAudioChain {
    $desktopEnabled = $chkDesktopAudio.Checked
    $micEnabled = $chkMic.Checked

    if (-not $desktopEnabled -and -not $micEnabled) {
        return $null
    }

    $desktopVolume = Format-InvariantNumber ([double]$numDesktopVolume.Value / 100.0)
    $micVolume = Format-InvariantNumber ([double]$numMicVolume.Value / 100.0)

    # Mixer mode is deliberately forced whenever both sources are active because
    # a single downstream encoder needs one combined raw-audio stream. Otherwise
    # the flag is an optional diagnostic: whichever single source is active can
    # still be manually routed through audiomixer instead of the legacy direct
    # WASAPI -> encoder path.
    $bothAudioSourcesEnabled = $desktopEnabled -and $micEnabled
    $useMixer = $bothAudioSourcesEnabled -or (($desktopEnabled -or $micEnabled) -and $chkAudioMixerMode.Checked)

    if (-not $useMixer) {
        if ($desktopEnabled) {
            return @(
                (Get-WasapiSourceString -Loopback)
                '!'
                (Get-AudioInputQueue)
                '!'
                'audioconvert'
                '!'
                'audioresample'
                '!'
                (Get-AudioRawCapsString -Format 'S16LE' -Channels 2)
                '!'
                'volume'
                "volume=$desktopVolume"
            ) -join ' '
        }

        return @(
            (Get-WasapiSourceString)
            '!'
            (Get-AudioInputQueue)
            '!'
            'audioconvert'
            '!'
            'audioresample'
            '!'
            (Get-AudioRawCapsString -Format 'S16LE' -Channels 2)
            '!'
            'volume'
            "volume=$micVolume"
        ) -join ' '
    }

    $mixBranches = @()

    if ($desktopEnabled) {
        $mixBranches += @(
            (Get-WasapiSourceString -Loopback)
            '!'
            (Get-AudioInputQueue -Multiplier 2)
            '!'
            'audioconvert'
            '!'
            'audioresample'
            '!'
            (Get-AudioRawCapsString -Format 'F32LE' -Channels 2)
            '!'
            'volume'
            "volume=$desktopVolume"
            '!'
            'mix.'
        ) -join ' '
    }

    if ($micEnabled) {
        $mixBranches += @(
            (Get-WasapiSourceString)
            '!'
            (Get-AudioInputQueue -Multiplier 2)
            '!'
            'audioconvert'
            '!'
            'audioresample'
            '!'
            (Get-AudioRawCapsString -Format 'F32LE' -Channels 2)
            '!'
            'volume'
            "volume=$micVolume"
            '!'
            'mix.'
        ) -join ' '
    }

    $mixOutput = @(
        'mix.'
        '!'
        (Get-AudioInputQueue -Multiplier 2)
        '!'
        'audioconvert'
        '!'
        (Get-AudioRawCapsString -Format 'S16LE' -Channels 2)
    ) -join ' '

    return "audiomixer name=mix $($mixBranches -join ' ') $mixOutput"
}

function Build-WhipSilentClockAudioChain {
    # MediaMTX/GStreamer testing showed that video-only WHIP selects
    # GstSystemClock and eventually develops a small backward DTS step. A muted
    # WASAPI loopback source makes the pipeline use GstAudioSrcClock, matching
    # the stable desktop-audio path while emitting no audible sound.
    return @(
        (Get-WasapiSourceString -Loopback)
        '!'
        (Get-AudioInputQueue)
        '!'
        'audioconvert'
        '!'
        'audioresample'
        '!'
        (Get-AudioRawCapsString -Format 'S16LE' -Channels 2)
        '!'
        'volume'
        'volume=0.0'
    ) -join ' '
}

function Build-SyntheticSilentAudioChain {
    # Completely bypasses WASAPI. Use this to prove whether the browser/WebRTC
    # audio track is fine when Windows audio driver timing is removed.
    $explicitRate = Get-AudioSampleRateOverrideValue
    $samplesPerBuffer = if ($explicitRate -gt 0) { [Math]::Max(1, [int][Math]::Round($explicitRate / 100.0)) } else { 480 }
    return @(
        'audiotestsrc'
        'is-live=true'
        'do-timestamp=true'
        'wave=silence'
        "samplesperbuffer=$samplesPerBuffer"
        '!'
        (Get-AudioInputQueue)
        '!'
        'audioconvert'
        '!'
        'audioresample'
        '!'
        (Get-AudioRawCapsString -Format 'S16LE' -Channels 2)
        '!'
        'volume'
        'volume=0.0'
    ) -join ' '
}

function Get-TimingMode {
    if ($null -ne $cmbTimingMode -and $cmbTimingMode.SelectedItem) {
        return [string]$cmbTimingMode.SelectedItem
    }
    if ($chkSendAbsoluteTimestamps.Checked) {
        return 'On / protocol clock signaling'
    }
    return $script:DefaultTimingMode
}

function Test-ClockSignalingValueEnabled {
    param([AllowNull()][string]$Value)

    return ([string]$Value -in @(
        'On / protocol clock signaling',
        'Send absolute timestamps / clock signalling',
        'RFC7273 NTP/PTP signalling',
        'RFC7273 NTP/PTP signaling',
        'On',
        'Enabled'
    ))
}

function Test-SendAbsoluteTimestampsEnabled {
    return (Test-ClockSignalingValueEnabled (Get-TimingMode))
}

function Test-SplitClockSignalingOverridesActive {
    return (
        ([string]$cmbProtocol.SelectedItem -eq $script:DirectWebRtcProtocolName) -and
        (Test-TransportEnabled) -and
        (Test-DirectWebRtcSplitAvPipelines) -and
        -not (Test-DirectWebRtcUnifiedPublisher) -and
        $chkSplitClockSignalingOverrides -and
        $chkSplitClockSignalingOverrides.Checked
    )
}

function Test-WebRtcClockSignalingForSink {
    param(
        [ValidateSet('Global','Video','Audio')]
        [string]$SinkRole = 'Global'
    )

    if ((Test-SplitClockSignalingOverridesActive) -and $SinkRole -ne 'Global') {
        if ($SinkRole -eq 'Video') {
            return (Test-ClockSignalingValueEnabled ([string]$cmbSplitVideoClockSignaling.SelectedItem))
        }
        return (Test-ClockSignalingValueEnabled ([string]$cmbSplitAudioClockSignaling.SelectedItem))
    }

    return (Test-SendAbsoluteTimestampsEnabled)
}

function Get-AbsoluteTimestampTransportOption {
    param(
        [Parameter(Mandatory)][string]$Protocol,
        [ValidateSet('Global','Video','Audio')][string]$SinkRole = 'Global'
    )

    switch ($Protocol) {
        'GST WebRTC' {
            if (Test-WebRtcClockSignalingForSink -SinkRole $SinkRole) { return 'do-clock-signalling=true' }
            return ''
        }
        'WHIP' {
            if (Test-SendAbsoluteTimestampsEnabled) { return 'do-clock-signalling=true' }
            return ''
        }
        'RTSP' {
            if (Test-SendAbsoluteTimestampsEnabled) { return 'ntp-time-source=ntp' }
            return ''
        }
        default { return '' }
    }
}

function Get-AbsoluteTimestampStatusText {
    $protocol = [string]$cmbProtocol.SelectedItem

    if (-not (Test-TransportEnabled)) { return 'Transport disabled' }

    switch ($protocol) {
        'GST WebRTC' {
            if (Test-SplitClockSignalingOverridesActive) {
                $videoState = if (Test-WebRtcClockSignalingForSink -SinkRole Video) { 'on' } else { 'off' }
                $audioState = if (Test-WebRtcClockSignalingForSink -SinkRole Audio) { 'on' } else { 'off' }
                return "GST WebRTC split sinks: video RFC7273 $videoState; audio RFC7273 $audioState"
            }
            if (Test-SendAbsoluteTimestampsEnabled) { return 'GST WebRTC sink: RFC7273 do-clock-signalling=true' }
            return 'GST WebRTC sink: clock signaling off / property omitted'
        }
        'WHIP' {
            if (Test-SendAbsoluteTimestampsEnabled) { return 'WHIP sink: RFC7273 do-clock-signalling=true' }
            return 'WHIP sink: clock signaling off / property omitted'
        }
        'RTSP' {
            if (Test-SendAbsoluteTimestampsEnabled) { return 'RTSP sink: ntp-time-source=ntp' }
            return 'RTSP sink: NTP timestamp override off / property omitted'
        }
        default { return ($protocol + ': no applicable clock-signaling sink property') }
    }
}

function Update-TimestampUi {
    $protocol = [string]$cmbProtocol.SelectedItem
    $transportEnabled = Test-TransportEnabled
    $applicable = $protocol -in @('WHIP','GST WebRTC','RTSP')

    $physicalSplit = $transportEnabled -and $protocol -eq 'GST WebRTC' -and (Test-DirectWebRtcSplitAvPipelines) -and -not (Test-DirectWebRtcUnifiedPublisher)
    $splitOverrides = $physicalSplit -and $chkSplitClockSignalingOverrides.Checked

    if ($lblTimingMode) {
        $lblTimingMode.Text = switch ($protocol) {
            'WHIP' { 'WHIP clock signaling' }
            'GST WebRTC' {
                if ($splitOverrides) { 'WebRTC clock signaling (overridden)' }
                elseif ($physicalSplit) { 'WebRTC clock signaling (both sinks)' }
                else { 'WebRTC clock signaling' }
            }
            'RTSP' { 'RTSP NTP timestamps' }
            default { 'Clock signaling' }
        }
    }

    if ($cmbTimingMode) { $cmbTimingMode.Enabled = $transportEnabled -and $applicable -and -not $splitOverrides }
    $chkSendAbsoluteTimestamps.Checked = Test-SendAbsoluteTimestampsEnabled

    if ($chkSplitClockSignalingOverrides) { $chkSplitClockSignalingOverrides.Enabled = $physicalSplit }
    if ($cmbSplitVideoClockSignaling) { $cmbSplitVideoClockSignaling.Enabled = $splitOverrides }
    if ($cmbSplitAudioClockSignaling) { $cmbSplitAudioClockSignaling.Enabled = $splitOverrides }

    $lblTimestampStatus.Text = Get-AbsoluteTimestampStatusText
    $active = if ($protocol -eq 'GST WebRTC' -and (Test-SplitClockSignalingOverridesActive)) {
        (Test-WebRtcClockSignalingForSink -SinkRole Video) -or (Test-WebRtcClockSignalingForSink -SinkRole Audio)
    }
    else {
        $applicable -and (Test-SendAbsoluteTimestampsEnabled)
    }
    $lblTimestampStatus.ForeColor = if ($active) { [System.Drawing.Color]::DarkSlateBlue } else { [System.Drawing.Color]::DimGray }
}

