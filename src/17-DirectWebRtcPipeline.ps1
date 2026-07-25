function Get-DirectWebRtcAvPipelineMode {
    if ($null -eq $cmbDirectWebRtcAvPipelineMode) { return $script:DefaultDirectWebRtcAvPipelineMode }
    return (Get-ComboSelectedOrDefault $cmbDirectWebRtcAvPipelineMode $script:DefaultDirectWebRtcAvPipelineMode)
}

function Test-DirectWebRtcSplitAvPipelines {
    return ((Get-DirectWebRtcAvPipelineMode) -like 'Split A/V pipelines*')
}

function Get-DirectWebRtcMediaStreamGrouping {
    if ($null -eq $cmbDirectWebRtcMediaStreamGrouping) { return $script:DefaultDirectWebRtcMediaStreamGrouping }
    return (Get-ComboSelectedOrDefault $cmbDirectWebRtcMediaStreamGrouping $script:DefaultDirectWebRtcMediaStreamGrouping)
}

function Test-DirectWebRtcSeparateMediaStreams {
    $directSplitMode = (Test-DirectWebRtcProtocol) -and (Test-DirectWebRtcSplitAvPipelines)
    return ((Test-WebRtcTransportProtocol) -and -not $directSplitMode -and ((Get-DirectWebRtcMediaStreamGrouping) -like 'Separate audio/video MediaStreams*'))
}

function Get-DirectWebRtcMediaStreamId {
    param([ValidateSet('video','audio')][string]$Kind)

    $fallback = if ($Kind -eq 'audio') { $script:DefaultDirectWebRtcAudioMediaStreamId } else { $script:DefaultDirectWebRtcVideoMediaStreamId }
    $control = if ($Kind -eq 'audio') { $txtDirectWebRtcAudioMediaStreamId } else { $txtDirectWebRtcVideoMediaStreamId }
    if ($null -eq $control) { return $fallback }
    $value = [string]$control.Text
    if ([string]::IsNullOrWhiteSpace($value)) { return $fallback }
    return $value.Trim()
}

function Get-WebRtcMediaStreamPadOptions {
    param([bool]$HasAudio)

    if (-not (Test-DirectWebRtcSeparateMediaStreams)) { return @() }

    $videoMsid = Quote-GstValue (Get-DirectWebRtcMediaStreamId -Kind video)
    $options = @("video_0::msid=$videoMsid")
    if ($HasAudio) {
        $audioMsid = Quote-GstValue (Get-DirectWebRtcMediaStreamId -Kind audio)
        $options += "audio_0::msid=$audioMsid"
    }
    return $options
}

function Test-DirectWebRtcUnifiedPublisher {
    return ((Test-DirectWebRtcSplitAvPipelines) -and $chkDirectWebRtcUnifiedPublisher -and $chkDirectWebRtcUnifiedPublisher.Checked)
}

function Test-DirectWebRtcSharedSignaling {
    return ((Test-DirectWebRtcSplitAvPipelines) -and -not (Test-DirectWebRtcUnifiedPublisher) -and $chkDirectWebRtcSharedSignaling -and $chkDirectWebRtcSharedSignaling.Checked)
}

function Get-DirectWebRtcSplitAudioSignalingPort {
    if (Test-DirectWebRtcSharedSignaling) { return [int]$numDirectWebRtcSignalingPort.Value }
    return [int]$numDirectWebRtcSplitAudioSignalingPort.Value
}

function Get-DirectWebRtcSignalingClientHost {
    $hostText = $txtDirectWebRtcSignalingHost.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($hostText) -or $hostText -in @('0.0.0.0','*','::','[::]')) { return '127.0.0.1' }
    $hostText = $hostText.Trim('[',']')
    if ($hostText -match ':') { return "[$hostText]" }
    return $hostText
}

function Get-DirectWebRtcSharedSignallerUri {
    $clientHost = Get-DirectWebRtcSignalingClientHost
    return "ws://${clientHost}:$([int]$numDirectWebRtcSignalingPort.Value)"
}

function Get-DirectWebRtcSplitAudioWsUrlForPlayer {
    # Proxy-aware default: do NOT hardcode 127.0.0.1 into gstglass-config.js.
    # player.js derives ws/wss + host from the actual primary viewer socket.
    # Separate mode uses splitAudioSignalingPort; shared mode reuses the exact
    # primary signalling WebSocket and selects the audio producer by metadata.
    return ''
}

function Get-DirectWebRtcSplitAudioWsUrlDescriptionForLog {
    if (Test-DirectWebRtcSharedSignaling) { return 'same primary signalling WebSocket/server' }
    return "auto/proxy-aware from viewer page host on port $(Get-DirectWebRtcSplitAudioSignalingPort)"
}

function Get-BranchClockSyncElement {
    param([Parameter(Mandatory)][string]$Mode)

    switch ($Mode) {
        'sync=true'  { return 'clocksync sync=true' }
        'sync=false' { return 'clocksync sync=false' }
        default      { return '' }
    }
}

function Get-VideoBranchSyncSuffix {
    $sync = Get-BranchClockSyncElement -Mode (Get-VideoSyncMode)
    if ([string]::IsNullOrWhiteSpace($sync)) { return '' }
    return " ! $sync"
}

function Get-AudioBranchSyncSuffix {
    $sync = Get-BranchClockSyncElement -Mode (Get-AudioSyncMode)
    if ([string]::IsNullOrWhiteSpace($sync)) { return '' }
    return " ! $sync"
}

function Get-VideoPreviewSinkSyncOption {
    # Preserve historical GStreamer Glass behavior: local preview used d3d11videosink sync=false.
    # The explicit Video sync mode overrides that only when the user selects sync=true/sync=false.
    $mode = Get-VideoSyncMode
    switch ($mode) {
        'sync=true'  { return 'sync=true' }
        'sync=false' { return 'sync=false' }
        default      { return 'sync=false' }
    }
}

function Get-EffectiveAudioTimingSummary {
    $timing = Get-AudioTimingMode
    $clockMode = Get-ComboSelectedOrDefault $cmbAudioClockMode $script:DefaultAudioClockMode
    $clockOpt = Get-WasapiClockOption

    if ($timing -eq 'Synthetic silent audio') {
        return 'synthetic source; WASAPI timing controls bypassed'
    }

    $items = New-Object System.Collections.Generic.List[string]
    foreach ($opt in @(
        $clockOpt,
        (Get-WasapiTimestampOption),
        (Get-WasapiSlaveMethodOption),
        (Get-WasapiLowLatencyOption),
        (Get-WasapiBufferTimeOption),
        (Get-WasapiLatencyTimeOption)
    )) {
        if (-not [string]::IsNullOrWhiteSpace($opt)) { $items.Add($opt) }
    }

    $sampleRate = Get-AudioSampleRateOverrideValue
    if ($sampleRate -gt 0) { $items.Add("raw-rate=$sampleRate") }

    if ($items.Count -eq 0) {
        $items.Add('plugin defaults; no WASAPI timing overrides emitted')
    }

    $note = ''
    if ($clockMode -eq 'Plugin default / allow WASAPI clock' -and $clockOpt -eq 'provide-clock=false') {
        $note = ' UI note: the selected Audio timing mode explicitly disables the WASAPI clock.'
    }

    return (($items -join ' ') + $note)
}

function New-LiveQueueString {
    param(
        [int]$Buffers = 2,
        [int]$MaxTimeMs = 0,
        [string]$Leak = ''
    )

    if ([string]::IsNullOrWhiteSpace($Leak)) { $Leak = Get-EffectiveLiveQueueLeakValue }
    $Buffers = [Math]::Max(1, $Buffers)
    $ns = [int64]([Math]::Max(0, $MaxTimeMs)) * 1000000
    return "queue max-size-buffers=$Buffers max-size-bytes=0 max-size-time=$ns leaky=$Leak"
}

function Set-WebRtcRecoveryMode {
    param([string]$Mode)
    if ([string]::IsNullOrWhiteSpace($Mode) -or -not $cmbWebRtcRecoveryMode.Items.Contains($Mode)) {
        $Mode = $script:DefaultWebRtcRecoveryMode
    }
    $cmbWebRtcRecoveryMode.SelectedItem = $Mode
    switch ($Mode) {
        'None' {
            $chkDirectWebRtcFec.Checked = $false
            $chkDirectWebRtcRetransmission.Checked = $false
        }
        'FEC only' {
            $chkDirectWebRtcFec.Checked = $true
            $chkDirectWebRtcRetransmission.Checked = $false
        }
        'FEC + RTX' {
            $chkDirectWebRtcFec.Checked = $true
            $chkDirectWebRtcRetransmission.Checked = $true
        }
        default {
            $chkDirectWebRtcFec.Checked = $false
            $chkDirectWebRtcRetransmission.Checked = $true
        }
    }
}

function Get-WebRtcRecoveryFlags {
    $mode = Get-ComboSelectedOrDefault $cmbWebRtcRecoveryMode $script:DefaultWebRtcRecoveryMode
    switch ($mode) {
        'None' { return [ordered]@{ Fec = 'false'; Retransmission = 'false'; Mode = 'None' } }
        'FEC only' { return [ordered]@{ Fec = 'true'; Retransmission = 'false'; Mode = 'FEC only' } }
        'FEC + RTX' { return [ordered]@{ Fec = 'true'; Retransmission = 'true'; Mode = 'FEC + RTX' } }
        default { return [ordered]@{ Fec = 'false'; Retransmission = 'true'; Mode = 'RTX only' } }
    }
}

function Apply-DirectWebRtcSmoothnessProfile {
    param([switch]$Force)

    if ($script:ApplyingDirectWebRtcSmoothnessProfile) { return }
    $script:ApplyingDirectWebRtcSmoothnessProfile = $true
    try {
        $profile = Get-ComboSelectedOrDefault $cmbDirectWebRtcSmoothnessProfile $script:DefaultDirectWebRtcSmoothnessProfile
        if ($profile -eq 'Custom' -and -not $Force) { return }

        switch ($profile) {
            'Sane defaults' {
                $cmbWebRtcSenderQueueMode.SelectedItem = 'Leaky live'
                $numDirectWebRtcPacingMs.Value = 0
                $numDirectWebRtcPlayerJitterMs.Value = $script:DefaultDirectWebRtcPlayerJitterMs
                $numDirectWebRtcVideoJitterMs.Value = $script:DefaultDirectWebRtcVideoJitterMs
                $cmbDirectWebRtcCongestion.SelectedItem = 'disabled'
                $cmbDirectWebRtcMitigation.SelectedItem = 'none'
                Set-WebRtcRecoveryMode 'None'
            }
            'Lowest latency' {
                $cmbWebRtcSenderQueueMode.SelectedItem = 'Leaky live'
                $numDirectWebRtcPacingMs.Value = 0
                $numDirectWebRtcPlayerJitterMs.Value = 0
                $numDirectWebRtcVideoJitterMs.Value = 0
                $cmbDirectWebRtcCongestion.SelectedItem = 'disabled'
                $cmbDirectWebRtcMitigation.SelectedItem = 'none'
                Set-WebRtcRecoveryMode 'None'
            }
            'Balanced smooth' {
                $cmbWebRtcSenderQueueMode.SelectedItem = 'Small cushion'
                $numDirectWebRtcPacingMs.Value = 40
                $numDirectWebRtcPlayerJitterMs.Value = 60
                $numDirectWebRtcVideoJitterMs.Value = 40
                $cmbDirectWebRtcCongestion.SelectedItem = 'gcc'
                $cmbDirectWebRtcMitigation.SelectedItem = 'none'
                Set-WebRtcRecoveryMode 'RTX only'
            }
            'WAN smooth' {
                $cmbWebRtcSenderQueueMode.SelectedItem = 'Small cushion'
                $numDirectWebRtcPacingMs.Value = 80
                $numDirectWebRtcPlayerJitterMs.Value = 100
                $numDirectWebRtcVideoJitterMs.Value = 80
                $cmbDirectWebRtcCongestion.SelectedItem = 'gcc'
                $cmbDirectWebRtcMitigation.SelectedItem = 'none'
                Set-WebRtcRecoveryMode 'RTX only'
            }
            'Adaptive viewer' {
                $cmbWebRtcSenderQueueMode.SelectedItem = 'Small cushion'
                $numDirectWebRtcPacingMs.Value = 60
                $numDirectWebRtcPlayerJitterMs.Value = 80
                $numDirectWebRtcVideoJitterMs.Value = 60
                $cmbDirectWebRtcCongestion.SelectedItem = 'gcc'
                $cmbDirectWebRtcMitigation.SelectedItem = 'none'
                Set-WebRtcRecoveryMode 'RTX only'
            }
        }
    }
    finally {
        $script:ApplyingDirectWebRtcSmoothnessProfile = $false
    }
}

function Get-DirectWebRtcPacingQueue {
    if ($chkBudgetSenderQueue -and -not $chkBudgetSenderQueue.Checked) { return 'identity' }
    $mode = Get-ComboSelectedOrDefault $cmbWebRtcSenderQueueMode $script:DefaultWebRtcSenderQueueMode
    # Structurally honest: the visible cap is the emitted cap. Zero means no
    # max-size-time limit in every mode; presets may set a nonzero value explicitly.
    $ms = [Math]::Max(0, [int]$numDirectWebRtcPacingMs.Value)
    $leak = Get-EffectiveLiveQueueLeakValue

    if ($mode -eq 'Leaky live') {
        # Leaky live means newest-frame-wins. Do not let a global stale 'No leak'
        # setting override this and create rubber-band latency.
        if ($leak -eq 'no') { $leak = 'downstream' }
        return (New-LiveQueueString -Buffers 2 -MaxTimeMs $ms -Leak $leak)
    }

    if ($mode -eq 'Small cushion') {
        return (New-LiveQueueString -Buffers 4 -MaxTimeMs $ms -Leak $leak)
    }

    return (New-LiveQueueString -Buffers 4 -MaxTimeMs $ms -Leak 'no')
}

function Write-DirectWebRtcWebClientConfig {
    param([switch]$Quiet)

    # Always resolve through the Player tab working-dir logic. Quiet callers still
    # need manual working-dir selections and versioned AppData sync to apply.
    $webDir = Get-DirectWebRtcWebDirectory
    if ([string]::IsNullOrWhiteSpace($webDir)) { return }

    try {
        $configPath = Join-Path $webDir 'gstglass-config.js'
        $smoothnessProfile = [string]$cmbDirectWebRtcSmoothnessProfile.SelectedItem
        $playerSettings = Get-PlayerSettingsFromUi
        $audioTarget = [int]$playerSettings.AudioJbufMs
        $videoTarget = [int]$playerSettings.VideoJbufMs
        $jbufMax = [int]$playerSettings.JbufMaxMs
        $watchdog = [string]$playerSettings.JbufWatchdogMode
        $statsOverlayEnabled = [bool]$playerSettings.StatsOverlay
        $jbufDebugEnabled = [bool]$playerSettings.JbufDebug
        $videoSignalingPort = [int]$numDirectWebRtcSignalingPort.Value

        $effectiveAvPipelineMode = if (Test-DirectWebRtcUnifiedPublisher) { 'Unified publisher - one producer' } else { [string](Get-DirectWebRtcAvPipelineMode) }
        $effectiveSharedSignaling = [bool](Test-DirectWebRtcSharedSignaling)
        $effectiveMediaStreamGrouping = if (Test-DirectWebRtcSeparateMediaStreams) { [string](Get-DirectWebRtcMediaStreamGrouping) } else { $script:DefaultDirectWebRtcMediaStreamGrouping }
        $videoMediaStreamId = [string](Get-DirectWebRtcMediaStreamId -Kind video)
        $audioMediaStreamId = [string](Get-DirectWebRtcMediaStreamId -Kind audio)

        $data = [ordered]@{
            version = $script:AppVersion
            source = 'gstglass-config.js'
            writtenUtc = [DateTime]::UtcNow.ToString('o')
            smoothnessProfile = $smoothnessProfile
            recoveryMode = [string]$cmbWebRtcRecoveryMode.SelectedItem
            senderQueueMode = [string]$cmbWebRtcSenderQueueMode.SelectedItem
            senderQueueCapMs = [int]$numDirectWebRtcPacingMs.Value
            pacingMs = [int]$numDirectWebRtcPacingMs.Value
            playerJitterMs = $audioTarget
            browserJitterTargetMs = $audioTarget
            browserJitterHintMs = $audioTarget
            jitterBufferTargetMs = $audioTarget
            jbufTargetMs = $audioTarget
            audioJbufMs = $audioTarget
            videoJbufMs = $videoTarget
            directWebRtcOpusMode = [string]$cmbDirectWebRtcOpusMode.SelectedItem
            directWebRtcOpusFrameMs = [string]$cmbDirectWebRtcOpusFrameMs.SelectedItem
            directWebRtcOpusAudioType = [string]$cmbDirectWebRtcOpusAudioType.SelectedItem
            directWebRtcOpusInbandFec = [bool]$chkDirectWebRtcOpusFec.Checked
            directWebRtcOpusDtx = [bool]$chkDirectWebRtcOpusDtx.Checked
            jbufWatchdogMode = $watchdog
            jbufWatchdog = $watchdog
            jbufMaxMs = $jbufMax
            jbufTrendWindowSec = 3
            jbufDebug = $jbufDebugEnabled
            adaptiveJitter = ($smoothnessProfile -eq 'Adaptive viewer')
            adaptiveJitterMinMs = [int]([Math]::Min($audioTarget, $videoTarget))
            adaptiveJitterMaxMs = [int]([Math]::Max([Math]::Max($audioTarget, $videoTarget), 500))
            keepAliveSeconds = 15
            statsOverlay = $statsOverlayEnabled
            liveEdgeGreenMs = [int]$playerSettings.LiveEdgeGreenMs
            liveEdgeYellowMs = [int]$playerSettings.LiveEdgeYellowMs
            liveEdgeAverageSec = [int]$playerSettings.LiveEdgeAverageSec
            screenWakeLock = $true
            connectionMode = 'auto'
            playerSeparateHtmlMediaElements = [bool]$playerSettings.SeparateHtmlMediaElements
            separateHtmlMediaElements = [bool]$playerSettings.SeparateHtmlMediaElements
            playerAvRenderMode = [string]$playerSettings.AvRenderMode
            avRenderMode = [string]$playerSettings.AvRenderMode
            avPipelineMode = $effectiveAvPipelineMode
            directWebRtcAvPipelineMode = $effectiveAvPipelineMode
            mediaStreamGrouping = $effectiveMediaStreamGrouping
            avMediaStreamGrouping = $effectiveMediaStreamGrouping
            separateMediaStreams = [bool](Test-DirectWebRtcSeparateMediaStreams)
            videoMediaStreamId = $videoMediaStreamId
            audioMediaStreamId = $audioMediaStreamId
            videoMsid = $videoMediaStreamId
            audioMsid = $audioMediaStreamId
            unifiedPublisher = [bool](Test-DirectWebRtcUnifiedPublisher)
            transportClockSignaling = [string](Get-TimingMode)
            splitClockSignalingOverrides = [bool](Test-SplitClockSignalingOverridesActive)
            splitVideoClockSignaling = if (Test-WebRtcClockSignalingForSink -SinkRole Video) { 'RFC7273 NTP/PTP signaling' } else { 'Off / plugin default' }
            splitAudioClockSignaling = if (Test-WebRtcClockSignalingForSink -SinkRole Audio) { 'RFC7273 NTP/PTP signaling' } else { 'Off / plugin default' }
            controlDataChannel = [bool]$chkDirectWebRtcControlDataChannel.Checked
            bundlePolicy = if ((Get-ComboSelectedOrDefault $cmbDirectWebRtcBundlePolicy $script:DefaultDirectWebRtcBundlePolicy) -eq 'Max bundle') { 'max-bundle' } else { 'default' }
            internalRtpMtu = [int]$numDirectWebRtcInternalRtpMtu.Value
            internalRepeatHeaders = [bool]$chkDirectWebRtcInternalRepeatHeaders.Checked
            splitPlayerSyncMode = [string]$playerSettings.SplitPlayerSyncMode
            splitAudioWatchdogMode = [string]$playerSettings.SplitPlayerSyncMode
            splitAudioStallSeconds = [int]$playerSettings.SplitAudioStallSeconds
            splitAudioWarmupSeconds = [int]$playerSettings.SplitAudioWarmupSeconds
            splitAudioEqualizeSeconds = [int]$playerSettings.SplitAudioWarmupSeconds
            jbufWatchdogWarmupSeconds = [int]$playerSettings.JbufWatchdogWarmupSeconds
            watchdogWarmupSeconds = [int]$playerSettings.WatchdogWarmupSeconds
            splitAvOffsetWarnMs = [int]$playerSettings.SplitAvOffsetWarnMs
            splitAvOffsetBaselineMs = [int]$playerSettings.SplitAvOffsetBaselineMs
            splitAvBaselineMs = [int]$playerSettings.SplitAvOffsetBaselineMs
            splitAvBaselineLearnTicks = 5
            signalingPort = $videoSignalingPort
            videoSignalingPort = $videoSignalingPort
            splitAudioWsUrl = if ((Test-DirectWebRtcSplitAvPipelines) -and -not (Test-DirectWebRtcUnifiedPublisher)) { [string](Get-DirectWebRtcSplitAudioWsUrlForPlayer) } else { '' }
            splitAudioSignalingPort = if ((Test-DirectWebRtcSplitAvPipelines) -and -not (Test-DirectWebRtcUnifiedPublisher)) { [int](Get-DirectWebRtcSplitAudioSignalingPort) } else { 0 }
            sharedSignaling = $effectiveSharedSignaling
            splitSharedSignaling = $effectiveSharedSignaling
            videoProducerName = 'gstglass-video'
            splitAudioProducerName = 'gstglass-audio'
            webPath = [string]$playerSettings.WebPath
            bundledWebMode = [string]$playerSettings.BundledWebMode
            bundledWebDirectory = [string]$playerSettings.BundledWebDirectory
            workingWebMode = [string]$playerSettings.WorkingWebMode
            webDirectory = [string]$playerSettings.WebDirectory
            servedWebDirectory = [string]$webDir
            runtimeConfigPath = [string](Join-Path $webDir 'gstglass-config.js')
            timingMode = [string]$cmbTimingMode.SelectedItem
            videoPipelineClockMode = [string](Get-VideoPipelineClockMode)
            videoTimestampMode = [string](Get-VideoTimestampMode)
            splitAudioPipelineClockMode = [string](Get-SplitAudioPipelineClockMode)
            audioTransportMode = [string]$cmbAudioTransportMode.SelectedItem
            audioClockMode = [string]$cmbAudioClockMode.SelectedItem
            congestionControl = [string]$cmbDirectWebRtcCongestion.SelectedItem
            threadingProfile = [string]$cmbThreadingProfile.SelectedItem
            queueLeakMode = [string]$cmbQueueLeakMode.SelectedItem
        }
        $json = $data | ConvertTo-Json -Compress
        Set-Content -LiteralPath $configPath -Value "window.GST_GLASS_CONFIG = $json;" -Encoding UTF8
        Update-DirectWebRtcWebUiStatus
        if (-not $Quiet) {
            Append-Log "Direct WebRTC client config written from UI: audio/video target $audioTarget/$videoTarget ms, max $jbufMax ms, watchdog $watchdog, separateHtmlElements=$($playerSettings.SeparateHtmlMediaElements), MediaStream grouping=$effectiveMediaStreamGrouping (V=$videoMediaStreamId A=$audioMediaStreamId), statsOverlay=$statsOverlayEnabled, jbufDebug=$jbufDebugEnabled, served=$webDir."
        }
    }
    catch {
        Append-Log "Direct WebRTC client config could not be written: $($_.Exception.Message)"
    }
}

function Build-DirectWebRtcEncodedVideoBranch {
    # webrtcsink accepts encoded video/x-h264/h265/av1 on its video pad. The
    # raw-feed experiment could not discover a usable encoder for D3D11 frames
    # on this Windows package, so use our known-good explicit encoder branch and
    # let webrtcsink own signalling, SDP, RTP/WebRTC transport, and browser fanout.
    $encoded = Build-VideoBranch -Protocol $script:DirectWebRtcProtocolName
    $pacingQueue = Get-DirectWebRtcPacingQueue
    $videoSync = Get-VideoBranchSyncSuffix
    return "$encoded$videoSync ! $pacingQueue ! out.video_0"
}

function Get-DirectWebRtcWebServerPathSegment {
    # gst-plugin-webrtc's warp route expects an exact path segment without a
    # leading slash. The UI/viewer URL stays browser-friendly as /live, but the
    # GStreamer property must be live or warp panics: exact path segments should
    # not contain a slash.
    $path = Normalize-DirectWebRtcWebPath $txtDirectWebRtcWebPath.Text
    if ($path -eq '/') { return '' }
    return $path.Trim('/').Trim()
}

function Get-DirectWebRtcUnifiedRtpVideoDefinition {
    $definition = Get-SelectedEncoderDefinition
    $codec = [string]$definition.Codec

    switch ($codec) {
        'H264' {
            return [pscustomobject]@{
                Codec = 'H264'
                PayloadType = 96
                RtpCaps = 'application/x-rtp,media=(string)video,encoding-name=(string)H264,payload=(int)96,clock-rate=(int)90000'
                Payloader = 'rtph264pay pt=96 config-interval=-1 aggregate-mode=zero-latency'
                Receiver = 'rtph264depay ! h264parse config-interval=-1 ! "video/x-h264,stream-format=byte-stream,alignment=au"'
            }
        }
        'H265' {
            return [pscustomobject]@{
                Codec = 'H265'
                PayloadType = 96
                RtpCaps = 'application/x-rtp,media=(string)video,encoding-name=(string)H265,payload=(int)96,clock-rate=(int)90000'
                Payloader = 'rtph265pay pt=96 config-interval=-1 aggregate-mode=zero-latency'
                Receiver = 'rtph265depay ! h265parse config-interval=-1 ! "video/x-h265,stream-format=byte-stream,alignment=au"'
            }
        }
        default {
            throw "Unified A/V publisher bridge currently supports H264 and H265 only; selected codec is $codec."
        }
    }
}

function Build-DirectWebRtcUnifiedVideoBridgeArguments {
    if (-not (Test-DirectWebRtcUnifiedPublisher)) { return '' }

    $rtp = Get-DirectWebRtcUnifiedRtpVideoDefinition
    $videoPort = [int]$numDirectWebRtcBridgeVideoPort.Value
    $encodedVideo = Build-VideoBranch -Protocol $script:DirectWebRtcProtocolName
    $videoSyncSuffix = Get-VideoBranchSyncSuffix
    $bridgeQueue = Get-DirectWebRtcPacingQueue
    $pipeline = "$encodedVideo$videoSyncSuffix ! $bridgeQueue ! $($rtp.Payloader) ! udpsink host=127.0.0.1 port=$videoPort sync=false async=false"
    $pipeline = Wrap-GstPipelineWithClockSelect -Pipeline $pipeline -ClockMode (Get-VideoPipelineClockMode)

    $flags = '-e'
    if ($chkVerbose.Checked) { $flags += ' -v' }
    return "$flags $pipeline"
}

function Build-DirectWebRtcUnifiedAudioBridgeArguments {
    if (-not (Test-DirectWebRtcUnifiedPublisher)) { return '' }

    $audioTransportMode = Get-ComboSelectedOrDefault $cmbAudioTransportMode $script:DefaultAudioTransportMode
    if ($audioTransportMode -ne 'Normal audio' -or (-not ($chkDesktopAudio.Checked -or $chkMic.Checked))) { return '' }

    $audioRaw = Build-RawAudioChain
    if ([string]::IsNullOrWhiteSpace($audioRaw)) { return '' }

    $directOpusMode = Get-ComboSelectedOrDefault $cmbDirectWebRtcOpusMode $script:DefaultDirectWebRtcOpusMode
    if ($directOpusMode -eq 'Raw audio to webrtcsink') {
        throw 'Unified A/V publisher bridge requires Explicit Opus encoder mode so the split audio process can cross the RTP bridge as encoded Opus.'
    }

    $directOpusBitrate = [int]$numAudioBitrate.Value * 1000
    $directOpusFrameMs = Get-ComboSelectedOrDefault $cmbDirectWebRtcOpusFrameMs $script:DefaultDirectWebRtcOpusFrameMs
    $directOpusAudioType = Get-ComboSelectedOrDefault $cmbDirectWebRtcOpusAudioType $script:DefaultDirectWebRtcOpusAudioType
    $directOpusFec = if ($chkDirectWebRtcOpusFec.Checked) { 'true' } else { 'false' }
    $directOpusDtx = if ($chkDirectWebRtcOpusDtx.Checked) { 'true' } else { 'false' }
    $directOpus = "opusenc bitrate=$directOpusBitrate bitrate-type=cbr frame-size=$directOpusFrameMs audio-type=$directOpusAudioType inband-fec=$directOpusFec dtx=$directOpusDtx ! opusparse ! `"audio/x-opus`""
    $audioPort = [int]$numDirectWebRtcBridgeAudioPort.Value
    $audioSyncSuffix = Get-AudioBranchSyncSuffix
    $audioBridgeSync = if ($chkDirectWebRtcAudioBridgePacing.Checked) { 'true' } else { 'false' }
    $pipeline = "$audioRaw ! $directOpus ! $(Get-AudioFinalQueue)$audioSyncSuffix ! rtpopuspay pt=97 dtx=$directOpusDtx ! udpsink host=127.0.0.1 port=$audioPort sync=$audioBridgeSync async=false"
    $pipeline = Wrap-GstPipelineWithClockSelect -Pipeline $pipeline -ClockMode (Get-SplitAudioPipelineClockMode)

    $flags = '-e'
    if ($chkVerbose.Checked) { $flags += ' -v' }
    return "$flags $pipeline"
}

function Get-DirectWebRtcTurnOption {
    if (-not $chkDirectWebRtcTurnEnabled.Checked) { return '' }

    $turnServer = $txtDirectWebRtcTurn.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($turnServer)) { return '' }

    # webrtcsink and whipclientsink inherit GstBaseWebRTCSink.  That base
    # element exposes TURN as a GstValueArray named turn-servers, not the
    # singular webrtcbin convenience property turn-server.  Build a one-item
    # array value and let Quote-GstValue preserve the embedded URI quotes for
    # gst-launch on Windows: turn-servers=<"turn://user:pass@host:port">.
    $turnArray = '<"' + $turnServer.Replace('"', '\"') + '">' 
    return ' turn-servers=' + (Quote-GstValue $turnArray)
}

function Get-DirectWebRtcVideoBitrateEnvelope {
    $videoBitrateKbps = [Math]::Max(1, [int]$numVideoBitrate.Value)
    $configuredStartKbps = if ($numDirectWebRtcStartBitrateKbps) {
        [Math]::Max(0, [int]$numDirectWebRtcStartBitrateKbps.Value)
    }
    else {
        [int]$script:DefaultDirectWebRtcStartBitrateKbps
    }
    $configuredMaxKbps = [Math]::Max(0, [int]$numMaxVideoBitrate.Value)

    # Zero deliberately preserves the historic behavior: start at the Video
    # target bitrate.  When the user supplies an explicit start estimate, keep
    # it inside an explicitly configured Video max instead of silently
    # widening that max.  Auto mode retains the old max>=start safeguard for
    # backward compatibility with existing configurations.
    $startKbps = if ($configuredStartKbps -gt 0) { $configuredStartKbps } else { $videoBitrateKbps }
    if ($configuredStartKbps -gt 0 -and $configuredMaxKbps -gt 0) {
        $startKbps = [Math]::Min($startKbps, $configuredMaxKbps)
    }
    $startBitrate = [Math]::Max(1000, ([int64]$startKbps * 1000))
    $maxBitrate = if ($configuredMaxKbps -gt 0) {
        [Math]::Max($startBitrate, ([int64]$configuredMaxKbps * 1000))
    }
    else {
        $startBitrate
    }

    $configuredMinKbps = if ($numDirectWebRtcMinBitrateKbps) {
        [Math]::Max(0, [int]$numDirectWebRtcMinBitrateKbps.Value)
    }
    else {
        [int]$script:DefaultDirectWebRtcMinBitrateKbps
    }

    if ($configuredMinKbps -gt 0) {
        # Explicit override: parsed exactly as typed, unclamped, for testing.
        $minBitrate = [int64]$configuredMinKbps * 1000
    }
    else {
        $smoothProfile = Get-ComboSelectedOrDefault $cmbDirectWebRtcSmoothnessProfile $script:DefaultDirectWebRtcSmoothnessProfile
        $autoMinBitrate = switch ($smoothProfile) {
            'Lowest latency' { [Math]::Max(1000, [int64]($startBitrate / 2)) }
            'Balanced smooth' { [Math]::Max(1000, [int64]($startBitrate * 0.75)) }
            'WAN smooth' { [Math]::Max(1000, [int64]($startBitrate * 0.60)) }
            default { [Math]::Min(1000000, [Math]::Max(1000, [int64]($startBitrate / 4))) }
        }
        $minBitrate = [int64][Math]::Min($autoMinBitrate, $startBitrate)
    }

    return [pscustomobject]@{
        MinBitrate = [int64]$minBitrate
        StartBitrate = [int64]$startBitrate
        MaxBitrate = [int64]$maxBitrate
        ConfiguredStartKbps = [int]$configuredStartKbps
        ConfiguredMinKbps = [int]$configuredMinKbps
        EffectiveStartKbps = [int]$startKbps
    }
}

function Build-DirectWebRtcUnifiedPublisherArguments {
    if (-not (Test-DirectWebRtcUnifiedPublisher)) { return '' }

    $destination = $txtDestination.Text.Trim()
    $webAddress = Quote-GstValue (Normalize-DirectWebRtcWebAddress $destination)
    $webPathSegment = Get-DirectWebRtcWebServerPathSegment
    $webPathOption = if ([string]::IsNullOrWhiteSpace($webPathSegment)) { '' } else { ' web-server-path=' + (Quote-GstValue $webPathSegment) }
    $webDirectory = Get-DirectWebRtcWebDirectory
    $webDirectoryOption = if ([string]::IsNullOrWhiteSpace($webDirectory)) { '' } else { ' web-server-directory=' + (Quote-GstValue $webDirectory) }
    $signalHostText = $txtDirectWebRtcSignalingHost.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($signalHostText)) { $signalHostText = $script:DefaultDirectWebRtcSignalingHost }
    $signalHost = Quote-GstValue $signalHostText
    $signalPort = [int]$numDirectWebRtcSignalingPort.Value
    $stunServer = $txtDirectWebRtcStun.Text.Trim()
    $stunOption = if ([string]::IsNullOrWhiteSpace($stunServer)) { '' } else { ' stun-server=' + (Quote-GstValue $stunServer) }
    $turnOption = Get-DirectWebRtcTurnOption
    $timestampOption = Get-AbsoluteTimestampTransportOption -Protocol $script:DirectWebRtcProtocolName -SinkRole Global
    $timestampOption = if ([string]::IsNullOrWhiteSpace($timestampOption)) { '' } else { " $timestampOption" }
    $congestion = Get-ComboSelectedOrDefault $cmbDirectWebRtcCongestion 'gcc'
    $mitigation = Get-ComboSelectedOrDefault $cmbDirectWebRtcMitigation 'none'
    $recoveryFlags = Get-WebRtcRecoveryFlags
    $fec = [string]$recoveryFlags.Fec
    $retx = [string]$recoveryFlags.Retransmission
    $bitrateEnvelope = Get-DirectWebRtcVideoBitrateEnvelope
    $startBitrate = [int64]$bitrateEnvelope.StartBitrate
    $maxBitrate = [int64]$bitrateEnvelope.MaxBitrate
    $minBitrate = [int64]$bitrateEnvelope.MinBitrate

    $videoRtp = Get-DirectWebRtcUnifiedRtpVideoDefinition
    $mediaType = Get-CodecMediaType -Codec ([string]$videoRtp.Codec)
    $videoPort = [int]$numDirectWebRtcBridgeVideoPort.Value
    $audioPort = [int]$numDirectWebRtcBridgeAudioPort.Value
    $jitterMs = [int]$numDirectWebRtcBridgeJitterMs.Value
    $publisherQueueMs = [int]$numDirectWebRtcPublisherQueueMs.Value
    $videoCaps = Quote-GstValue ([string]$videoRtp.RtpCaps)
    $audioCaps = Quote-GstValue 'application/x-rtp,media=(string)audio,encoding-name=(string)OPUS,payload=(int)97,clock-rate=(int)48000,encoding-params=(string)2'

    $sinkProps = @(
        'webrtcsink',
        'name=out',
        "video-caps=`"$mediaType`"",
        'audio-caps="audio/x-opus"',
        'run-signalling-server=true',
        'run-web-server=true',
        "signalling-server-host=$signalHost",
        "signalling-server-port=$signalPort",
        "web-server-host-addr=$webAddress",
        "congestion-control=$congestion",
        "do-fec=$fec",
        "do-retransmission=$retx",
        "enable-mitigation-modes=$mitigation",
        "min-bitrate=$minBitrate",
        "start-bitrate=$startBitrate",
        "max-bitrate=$maxBitrate",
        'meta="meta,name=gstglass-av"'
    )
    $sinkProps += Get-WebRtcMediaStreamPadOptions -HasAudio $true
    if ($chkDirectWebRtcControlDataChannel.Checked) { $sinkProps += 'enable-control-data-channel=true' }

    # Preserve RTP-derived cadence across the process boundary.  The f10 graph
    # forced udpsrc arrival timestamps and then fed webrtcsink with no buffering,
    # which converted Windows scheduling bursts into choppy audio and triggered
    # the internal appsink 20 ms processing-deadline warnings.
    $bridgeJitter = if ($jitterMs -gt 0) { "rtpjitterbuffer latency=$jitterMs drop-on-latency=false do-lost=true ! " } else { '' }
    $publisherQueueNs = [int64]$publisherQueueMs * 1000000
    $publisherQueue = if ($publisherQueueMs -gt 0) { "queue max-size-buffers=0 max-size-bytes=0 max-size-time=$publisherQueueNs leaky=no ! " } else { '' }
    $videoInput = "udpsrc port=$videoPort caps=$videoCaps ! $bridgeJitter$($videoRtp.Receiver) ! $publisherQueue" + 'out.video_0'
    $audioInput = "udpsrc port=$audioPort caps=$audioCaps ! $bridgeJitter" + 'rtpopusdepay ! opusparse ! "audio/x-opus" ! ' + $publisherQueue + 'out.audio_0'
    $pipeline = (($sinkProps -join ' ') + $timestampOption + $stunOption + $turnOption + $webPathOption + $webDirectoryOption + " $videoInput $audioInput")
    $pipeline = Wrap-GstPipelineWithClockSelect -Pipeline $pipeline -ClockMode (Get-VideoPipelineClockMode)

    $flags = '-e'
    if ($chkVerbose.Checked) { $flags += ' -v' }
    return "$flags $pipeline"
}

function Build-DirectWebRtcAudioOnlyArguments {
    if (Test-DirectWebRtcUnifiedPublisher) { return (Build-DirectWebRtcUnifiedAudioBridgeArguments) }

    $audioTransportMode = Get-ComboSelectedOrDefault $cmbAudioTransportMode $script:DefaultAudioTransportMode
    if ($audioTransportMode -ne 'Normal audio' -or (-not ($chkDesktopAudio.Checked -or $chkMic.Checked))) {
        return ''
    }

    $audioRaw = Build-RawAudioChain
    if ([string]::IsNullOrWhiteSpace($audioRaw)) { return '' }

    $signalHostText = $txtDirectWebRtcSignalingHost.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($signalHostText)) { $signalHostText = $script:DefaultDirectWebRtcSignalingHost }
    $signalHost = Quote-GstValue $signalHostText
    $signalPort = Get-DirectWebRtcSplitAudioSignalingPort
    $sharedSignaling = Test-DirectWebRtcSharedSignaling
    $stunServer = $txtDirectWebRtcStun.Text.Trim()
    $stunOption = if ([string]::IsNullOrWhiteSpace($stunServer)) { '' } else { ' stun-server=' + (Quote-GstValue $stunServer) }
    $turnOption = Get-DirectWebRtcTurnOption
    $timestampOption = Get-AbsoluteTimestampTransportOption -Protocol $script:DirectWebRtcProtocolName -SinkRole Audio
    $timestampOption = if ([string]::IsNullOrWhiteSpace($timestampOption)) { '' } else { " $timestampOption" }
    $congestion = Get-ComboSelectedOrDefault $cmbDirectWebRtcCongestion 'gcc'
    $mitigation = Get-ComboSelectedOrDefault $cmbDirectWebRtcMitigation 'none'
    $recoveryFlags = Get-WebRtcRecoveryFlags
    $fec = [string]$recoveryFlags.Fec
    $retx = [string]$recoveryFlags.Retransmission
    $startBitrate = [Math]::Max(1000, ([int]$numAudioBitrate.Value * 1000))
    $maxBitrate = $startBitrate
    $minBitrate = [Math]::Max(1000, [int]($startBitrate / 2))

    $sinkProps = @(
        'webrtcsink',
        'name=aout',
        'audio-caps="audio/x-opus"'
    )
    if ($sharedSignaling) {
        $sharedUri = Quote-GstValue (Get-DirectWebRtcSharedSignallerUri)
        $sinkProps += "signaller::uri=$sharedUri"
        $sinkProps += 'meta="meta,name=gstglass-audio,kind=audio"'
    }
    else {
        $sinkProps += 'run-signalling-server=true'
        $sinkProps += 'run-web-server=false'
        $sinkProps += "signalling-server-host=$signalHost"
        $sinkProps += "signalling-server-port=$signalPort"
    }
    $sinkProps += @(
        "congestion-control=$congestion",
        "do-fec=$fec",
        "do-retransmission=$retx",
        "enable-mitigation-modes=$mitigation",
        "min-bitrate=$minBitrate",
        "start-bitrate=$startBitrate",
        "max-bitrate=$maxBitrate"
    )

    $directOpusMode = Get-ComboSelectedOrDefault $cmbDirectWebRtcOpusMode $script:DefaultDirectWebRtcOpusMode
    $audioSyncSuffix = Get-AudioBranchSyncSuffix
    if ($directOpusMode -eq 'Raw audio to webrtcsink') {
        $audioBranch = "$audioRaw ! $(Get-AudioFinalQueue)$audioSyncSuffix ! aout.audio_0"
    }
    else {
        $directOpusBitrate = [int]$numAudioBitrate.Value * 1000
        $directOpusFrameMs = Get-ComboSelectedOrDefault $cmbDirectWebRtcOpusFrameMs $script:DefaultDirectWebRtcOpusFrameMs
        $directOpusAudioType = Get-ComboSelectedOrDefault $cmbDirectWebRtcOpusAudioType $script:DefaultDirectWebRtcOpusAudioType
        $directOpusFec = if ($chkDirectWebRtcOpusFec.Checked) { 'true' } else { 'false' }
        $directOpusDtx = if ($chkDirectWebRtcOpusDtx.Checked) { 'true' } else { 'false' }
        $directOpus = "opusenc bitrate=$directOpusBitrate bitrate-type=cbr frame-size=$directOpusFrameMs audio-type=$directOpusAudioType inband-fec=$directOpusFec dtx=$directOpusDtx ! opusparse ! `"audio/x-opus`""
        $audioBranch = "$audioRaw ! $directOpus ! $(Get-AudioFinalQueue)$audioSyncSuffix ! aout.audio_0"
    }

    $pipeline = "$(($sinkProps -join ' '))$timestampOption$stunOption$turnOption $audioBranch"
    $pipeline = Wrap-GstPipelineWithClockSelect -Pipeline $pipeline -ClockMode (Get-SplitAudioPipelineClockMode)

    $flags = '-e'
    if ($chkVerbose.Checked) { $flags += ' -v' }
    return "$flags $pipeline"
}

