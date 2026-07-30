# SPDX-License-Identifier: AGPL-3.0-only

function Start-GstStream {
    param(
        [switch]$Automatic,
        [switch]$PreviewOnly,
        [switch]$RecordingOnly
    )

    if ($script:ControlledLiveStreamActive) { return }
    if ($script:PipelineStartInProgress) { return }

    Write-PsDebugTrace "Start-GstStream: entering (Automatic=$Automatic PreviewOnly=$PreviewOnly RecordingOnly=$RecordingOnly)"
    $script:PipelineStartInProgress = $true
    Set-RunState $false
    try {
    $script:SuppressCustomGstArgumentsOverride = [bool]$PreviewOnly

    if ($script:DynamicScenePreviewActive) {
        if ($PreviewOnly) { return }
        $transition = if ($RecordingOnly) { 'Starting recording' } else { 'Going live' }
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] ${transition}: stopping dynamic scene preview and starting the requested pipeline."
        Stop-DynamicScenePreview -Quiet
    }

    if ($PreviewOnly -and (Test-UseDynamicScenePreview)) {
        if (Start-DynamicScenePreview) { return }
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Controlled scene preview failed; continuing with the normal composed preview fallback."
    }

    if ($script:GstProcess -and -not $script:GstProcess.HasExited) {
        if ($script:PreviewOnlyMode -and -not $PreviewOnly) {
            $transition = if ($RecordingOnly) { 'Starting recording' } else { 'Going live' }
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] ${transition}: stopping local preview and starting the requested pipeline."
            $script:RestartRecordingOnlyMode = [bool]$RecordingOnly
            Stop-GstStream -Restart
        }
        return
    }

    $configuredTransportEnabled = (-not $chkTransportEnabled) -or [bool]$chkTransportEnabled.Checked
    $script:RecordingPipelineRequested = [bool](
        $chkRecordingEnabled -and
        $chkRecordingEnabled.Checked -and
        (
            $RecordingOnly -or
            ((-not $PreviewOnly) -and $configuredTransportEnabled -and $chkRecordWithStream.Checked)
        )
    )
    $script:RecordingOnlyMode = [bool]$RecordingOnly
    $script:RecordingPipelineActive = $false
    $script:ForceLocalPreviewMode = [bool]($PreviewOnly -or $RecordingOnly)
    $customGstArgumentsOverride = Test-CustomGstArgumentsOverride

    # -Silent whenever this is a timer-driven restart (every restart, manual
    # button or truly automatic, funnels through Start-GstStream -Automatic
    # via the poll timer -- see 90-MainWindow.ps1) rather than a direct
    # Start-button click: a validation failure here has no one watching for
    # a modal dialog, which would otherwise block the whole UI message loop
    # until someone happens to notice and dismiss it -- exactly what looked
    # like the UI "locking up" after removing a viewer account mid-stream.
    if (-not (Validate-Configuration -Silent:$Automatic)) {
        $script:WaitingForFullscreen = $false
        $script:RestartAt = $null
        $script:PreviewOnlyMode = $false
        $script:ForceLocalPreviewMode = $false
        $script:RecordingPipelineRequested = $false
        $script:RecordingOnlyMode = $false
        Set-RunState $false
        return
    }

    Stop-StaleManagedProcesses

    if ((-not $customGstArgumentsOverride) -and -not (Resolve-FullscreenCaptureTarget -Quiet)) {
        $firstWait = -not $script:WaitingForFullscreen
        $script:WaitingForFullscreen = $true
        $script:StopRequested = $false
        $script:RestartAt = (Get-Date).AddSeconds(2)
        $script:RestartRecordingOnlyMode = [bool]$RecordingOnly
        $statusLabel.Text = 'Waiting for a fullscreen application'
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
        Set-WaitingForFullscreenState
        if ($firstWait) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] No fullscreen application is active; waiting and retrying every 2 seconds."
        }
        $script:PreviewOnlyMode = $false
        $script:ForceLocalPreviewMode = $false
        $script:RecordingPipelineRequested = $false
        $script:RecordingOnlyMode = $false
        return
    }

    if ($script:WaitingForFullscreen) {
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Fullscreen application detected: '$($script:CaptureWindowTitle)'."
    }
    $script:WaitingForFullscreen = $false

    Save-Settings

    Reset-ProcessLogPaths
    $processDiskLogging = Test-ProcessDiskLoggingEnabled
    if ($processDiskLogging) {
        Ensure-ProcessLogDirectory
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
        $script:StdOutPath = Join-Path $script:LogDirectory "gst-$stamp-out.log"
        $script:StdErrPath = Join-Path $script:LogDirectory "gst-$stamp-err.log"
        $script:StdOutVideoPath = Join-Path $script:LogDirectory "gst-video-$stamp-out.log"
        $script:StdErrVideoPath = Join-Path $script:LogDirectory "gst-video-$stamp-err.log"
        $script:StdOutAudioPath = Join-Path $script:LogDirectory "gst-audio-$stamp-out.log"
        $script:StdErrAudioPath = Join-Path $script:LogDirectory "gst-audio-$stamp-err.log"
    }
    $script:StopRequested = $false
    $script:RestartAt = $null
    $script:PreviewHwnd = [IntPtr]::Zero
    $script:PreviewParked = $false
    Reset-PreviewAppliedState
    $controlledLiveRequested = [bool]((-not $customGstArgumentsOverride) -and (-not $RecordingOnly) -and (Test-ControlledLiveStreamRequested -PreviewOnly:$PreviewOnly))
    $script:ForceLiveScenePreviewBranch = $controlledLiveRequested
    try { $script:PipelineHasPreview = [bool]((-not $customGstArgumentsOverride) -and (Test-PreviewEnabledForCurrentPipeline)) }
    finally { $script:ForceLiveScenePreviewBranch = $false }
    $script:PreviewOnlyMode = [bool]$PreviewOnly
    $previewPlaceholder.Visible = $true
    $previewPlaceholder.Text = if ($script:PipelineHasPreview) { 'Starting preview...' } else { 'Preview disabled for this pipeline' }

    $gstPath = Resolve-GstLaunchSelection -RequestedPath $txtGstPath.Text -UpdateControl
    Prepare-GStreamerRuntime -GstPath $gstPath
    Initialize-GstJob

    if (-not (Start-ManagedMediaMtx)) {
        $statusLabel.Text = 'MediaMTX start failed'
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkRed
        $script:PreviewOnlyMode = $false
        $script:ForceLocalPreviewMode = $false
        $script:RecordingPipelineRequested = $false
        $script:RecordingOnlyMode = $false
        Set-RunState $false
        return
    }

    Write-DirectWebRtcWebClientConfig
    if (-not $PreviewOnly) {
        Set-DirectWebRtcStreamStopMarker -IntentionalStop $false
    }

    try {
        $script:ForceLiveScenePreviewBranch = $controlledLiveRequested
        $arguments = if ($customGstArgumentsOverride) { Get-CustomGstArguments } else { Build-GstArguments }
        $videoArguments = ''
        $audioArguments = ''
        if ((-not $customGstArgumentsOverride) -and (Test-TransportEnabled) -and [string]$cmbProtocol.SelectedItem -eq $script:DirectWebRtcProtocolName -and (Test-DirectWebRtcSplitAvPipelines)) {
            if (Test-DirectWebRtcUnifiedPublisher) {
                $videoArguments = Build-DirectWebRtcUnifiedVideoBridgeArguments
            }
            $audioArguments = Build-DirectWebRtcAudioOnlyArguments
        }
    }
    catch {
        $script:PreviewOnlyMode = $false
        $script:ForceLocalPreviewMode = $false
        $script:RecordingPipelineRequested = $false
        $script:RecordingOnlyMode = $false
        $statusLabel.Text = 'Start failed'
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkRed
        Set-RunState $false
        Append-Log "START ERROR: $($_.Exception.Message)"
        return
    }
    finally {
        $script:ForceLiveScenePreviewBranch = $false
    }

    $transportEnabled = Test-TransportEnabled
    $runIsPreviewOnly = [bool]$PreviewOnly
    $runNeedsUnifiedPublisherHost = (-not $customGstArgumentsOverride) -and $transportEnabled -and (Test-DirectWebRtcUnifiedPublisherHostRequired)
    $useControlledLiveStream = (
        $controlledLiveRequested -and
        -not $runNeedsUnifiedPublisherHost -and
        [string]::IsNullOrWhiteSpace($videoArguments) -and
        [string]::IsNullOrWhiteSpace($audioArguments)
    )
    # Captured here, before ForceLocalPreviewMode is cleared below, since
    # Test-DirectWebRtcPortRangeWorkerRequired calls Test-TransportEnabled
    # internally -- computing it any later would see transport as enabled
    # again (from the saved Protocol/Transport checkbox state) even though
    # this run is a suppressed preview, wrongly routing a plain preview
    # pipeline through the WebRTC port-range worker (which then fails
    # looking for a webrtcsink element that a preview pipeline never has).
    $portRangeWorkerRequested = Test-DirectWebRtcPortRangeWorkerRequired
    $script:ForceLocalPreviewMode = $false
    if ($script:PendingPipelineStop) { return }
    Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Starting full GStreamer pipeline..."
    Append-Log "Process disk logging: $(if ($processDiskLogging) { 'enabled' } else { 'disabled - UI log only' })"
    if ($customGstArgumentsOverride) {
        Append-Log 'Custom gst-launch args override: enabled. UI-generated capture, encoder, transport, preview, split-pipeline, and controlled-live pipeline templates are bypassed for this run.'
    }
    Append-Log "Transport: $(if ($transportEnabled) { 'Enabled' } elseif ($runIsPreviewOnly) { 'Disabled - local preview only' } else { 'Disabled - local recording/preview only' })"
    if ($transportEnabled) {
        Append-Log "Protocol: $([string]$cmbProtocol.SelectedItem)"
        Append-Log "Absolute timestamps: $(Get-AbsoluteTimestampStatusText)"
        if ([string]$cmbProtocol.SelectedItem -in @('WHIP', $script:DirectWebRtcProtocolName)) {
            $webRtcBitrateEnvelope = Get-DirectWebRtcVideoBitrateEnvelope
            $startSource = if ([int]$webRtcBitrateEnvelope.ConfiguredStartKbps -gt 0) { 'explicit' } else { 'Video bitrate (auto)' }
            Append-Log "WebRTC bitrate envelope: min/start/max $([int64]$webRtcBitrateEnvelope.MinBitrate)/$([int64]$webRtcBitrateEnvelope.StartBitrate)/$([int64]$webRtcBitrateEnvelope.MaxBitrate) bps; start source $startSource."
        }
        if ([string]$cmbProtocol.SelectedItem -eq 'WHIP') {
            Append-Log 'WHIP publish guard: constrained-baseline H.264 caps, GOP capped to 1s, B-frames/lookahead off, NVENC ultra-low-latency.'
            if (Test-SendAbsoluteTimestampsEnabled) {
                Append-Log 'WHIP timing: do-clock-signalling=true. Use with MediaMTX pathDefaults/useAbsoluteTimestamp=true.'
            }
            else {
                Append-Log 'WHIP timing: receiver/server timestamps. Use with MediaMTX pathDefaults/useAbsoluteTimestamp=false.'
            }
        }
        if ([string]$cmbProtocol.SelectedItem -eq $script:DirectWebRtcProtocolName) {
            Append-Log "Direct WebRTC viewer: $(Get-DirectWebRtcViewerUrl)"
            Append-Log "Direct WebRTC video signalling WebSocket/TCP: $($txtDirectWebRtcSignalingHost.Text):$([int]$numDirectWebRtcSignalingPort.Value)"
            Append-Log "Direct WebRTC smoothing: $([string]$cmbDirectWebRtcSmoothnessProfile.SelectedItem), recovery $([string]$cmbWebRtcRecoveryMode.SelectedItem), sender queue $([string]$cmbWebRtcSenderQueueMode.SelectedItem) / $([int]$numDirectWebRtcPacingMs.Value) ms cap, browser audio/video JBUF $([int]$numDirectWebRtcPlayerJitterMs.Value)/$([int]$numDirectWebRtcVideoJitterMs.Value) ms, clock signaling $([string](Get-TimingMode)), audio mode $([string]$cmbAudioTransportMode.SelectedItem)"
            Append-Log "Audio source selection: $(Get-AudioSourceSelectionSummary)"
            Append-Log "Direct WebRTC A/V pipeline topology: $([string](Get-DirectWebRtcAvPipelineMode))"
            if (Test-SplitClockSignalingOverridesActive) {
                $splitVideoClockText = if (Test-WebRtcClockSignalingForSink -SinkRole Video) { 'RFC7273 on' } else { 'off / property omitted' }
                $splitAudioClockText = if (Test-WebRtcClockSignalingForSink -SinkRole Audio) { 'RFC7273 on' } else { 'off / property omitted' }
                Append-Log "Split WebRTC sink clock signaling: video=$splitVideoClockText; audio=$splitAudioClockText."
            }
            else {
                $webRtcClockText = if (Test-WebRtcClockSignalingForSink -SinkRole Global) { 'RFC7273 on' } else { 'off / property omitted' }
                Append-Log "WebRTC sink clock signaling: $webRtcClockText."
            }
            if (Test-DirectWebRtcUnifiedPublisher) {
                Append-Log "Direct WebRTC unified-publisher lab: independent video/audio capture processes feed localhost RTP ports $([int]$numDirectWebRtcBridgeVideoPort.Value)/$([int]$numDirectWebRtcBridgeAudioPort.Value); one publisher exposes producer gstglass-av with video_0 + audio_0 on signalling port $([int]$numDirectWebRtcSignalingPort.Value)."
                $bridgeJitterText = if ([int]$numDirectWebRtcBridgeJitterMs.Value -gt 0) { [string]([int]$numDirectWebRtcBridgeJitterMs.Value) + ' ms, non-dropping' } else { 'disabled / element omitted' }
                $publisherQueueText = if ([int]$numDirectWebRtcPublisherQueueMs.Value -gt 0) { [string]([int]$numDirectWebRtcPublisherQueueMs.Value) + ' ms non-leaky per track' } else { 'disabled / element omitted' }
                $audioBridgePacingText = if ($chkDirectWebRtcAudioBridgePacing.Checked) { 'enabled (sync=true)' } else { 'disabled (sync=false)' }
                Append-Log "Unified publisher RTP timing repair: receive JBUF $bridgeJitterText; publisher queue $publisherQueueText; audio RTP pacing $audioBridgePacingText; udpsrc do-timestamp override omitted. Player uses one PeerConnection and does not open the split-audio WebSocket."
                $internalMtuText = if ([int]$numDirectWebRtcInternalRtpMtu.Value -gt 0) { [string]([int]$numDirectWebRtcInternalRtpMtu.Value) } else { 'plugin default' }
                Append-Log "Unified producer advanced: clock-signaling=$([bool](Test-WebRtcClockSignalingForSink -SinkRole Global)); control-data-channel=$($chkDirectWebRtcControlDataChannel.Checked); bundle=$([string]$cmbDirectWebRtcBundlePolicy.SelectedItem); internal RTP MTU=$internalMtuText; internal repeat headers=$($chkDirectWebRtcInternalRepeatHeaders.Checked)."
                if ($chkUnifiedBridgeKeyframeGuard.Checked) {
                    $effectiveKeyframeFrames = [Math]::Max(1, [int][Math]::Ceiling(([int]$numFps.Value * [int]$numUnifiedBridgeKeyframeIntervalMs.Value) / 1000.0))
                    Append-Log "Unified publisher keyframe guard: periodic IDR every $([int]$numUnifiedBridgeKeyframeIntervalMs.Value) ms -> encoder GOP $effectiveKeyframeFrames frames at $([int]$numFps.Value) FPS. This is the fallback for PLI/FIR requests that cannot cross the RTP process boundary."
                }
                else {
                    Append-Log "Unified publisher keyframe guard: off; encoder uses Video-tab GOP $([int]$numGopSeconds.Value) sec."
                }
            }
            elseif (Test-DirectWebRtcSplitAvPipelines) {
                if (Test-DirectWebRtcSharedSignaling) {
                    Append-Log "Direct WebRTC split signalling: SHARED on video port $([int]$numDirectWebRtcSignalingPort.Value); audio producer joins $(Get-DirectWebRtcSharedSignallerUri)."
                }
                else {
                    Append-Log "Direct WebRTC split audio signalling WebSocket/TCP: $($txtDirectWebRtcSignalingHost.Text):$(Get-DirectWebRtcSplitAudioSignalingPort)"
                }
                Append-Log "Direct WebRTC split audio player WS URL: $(Get-DirectWebRtcSplitAudioWsUrlDescriptionForLog)"
            }
            Append-Log 'Direct WebRTC media: UDP through ICE. Signalling is TCP/WebSocket on the configured port; the unified-publisher lab additionally uses localhost RTP/UDP between its three processes.'
        }
    }
    Append-Log "Capture method: $(Get-SelectedCaptureMethodName)"
    if ($chkSceneEnabled.Checked -and [string]$cmbScenePreset.SelectedItem -eq 'Desktop + webcam') {
        Append-Log "Scene input queues: $([int]$numSceneInputQueueBuffers.Value) buffers / $([int]$numSceneInputQueueCapMs.Value) ms per input, leaky=downstream. 0 ms is emitted literally with no hidden fallback."
    }
    if (Test-RecordingEnabled) {
        Append-Log "Recording file: $script:ResolvedRecordingPath"
        Append-Log "Recording encoder: $([string]$cmbRecordingEncoder.SelectedItem), $([int]$numRecordingVideoBitrate.Value) kbps, $([int]$numRecordingWidth.Value)x$([int]$numRecordingHeight.Value)@$([int]$numRecordingFps.Value)"
        Append-Log 'Recording branch guard: decoupled from the capture thread by a shallow non-leaky queue (recordq). Sustained disk/encoder overrun will backpressure capture rather than drop recorded frames; a software recording encoder can therefore throttle the live branch.'
    }

    if ($transportEnabled -and [string]$cmbProtocol.SelectedItem -eq 'SRT') {
        $srtTracks = if ($chkDesktopAudio.Checked -or $chkMic.Checked) {
            'video PID 256 + audio PID 257, both in program 1'
        }
        else {
            'video PID 256 in program 1'
        }

        Append-Log "SRT MPEG-TS mapping: $srtTracks"
        Append-Log 'SRT low-latency mux profile: mux latency 2.9 ms, PAT/PMT 600, pkt_size 1316, Opus preferred'
    }
    if (Test-FullscreenCaptureMode) {
        Append-Log "Fullscreen capture target: $($script:CaptureWindowTitle) (HWND $([uint64]$script:CaptureWindowHwnd.ToInt64()))"
    }
    $gstDebugSpec = Get-GstDebugSpec
    $requestedAudioQueueCapMs = [int]$numAudioQueueCapMs.Value
    $effectiveAudioQueueCapMs = Get-EffectiveAudioQueueCapMs
    $audioQueueCapText = if ($requestedAudioQueueCapMs -ne $effectiveAudioQueueCapMs) {
        "$requestedAudioQueueCapMs ms -> effective $effectiveAudioQueueCapMs ms"
    }
    else {
        "$requestedAudioQueueCapMs ms"
    }
    Append-Log "Threading: profile $([string]$cmbThreadingProfile.SelectedItem), priority $([string]$cmbGstProcessPriority.SelectedItem), capture queue $([int]$numCaptureQueueBuffers.Value) buffers, sender queue $([string]$cmbWebRtcSenderQueueMode.SelectedItem) / $([int]$numDirectWebRtcPacingMs.Value) ms, audio queue $([int]$numAudioQueueBuffers.Value) buffers / $audioQueueCapText, leak $([string]$cmbQueueLeakMode.SelectedItem), effective leak $(Get-EffectiveLiveQueueLeakValue), lateness tracer $($chkBufferLatenessTracer.Checked)."
    $cpuWorkerText = if ([int]$numCpuWorkerLimit.Value -eq 0) { 'auto' } else { [string]([int]$numCpuWorkerLimit.Value) }
    Append-Log "Thread budget: $([string]$cmbThreadBudget.SelectedItem), CPU workers $cpuWorkerText, boundaries capture=$($chkBudgetCaptureQueue.Checked) sender=$($chkBudgetSenderQueue.Checked) audio-input=$($chkBudgetAudioInputQueue.Checked) audio-sender=$($chkBudgetAudioFinalQueue.Checked) scene-inputs=$($chkBudgetSceneInputQueues.Checked). Total process threads are observed, not hard-capped."
    if ((Get-QueueLeakValue) -eq 'no' -and (Get-EffectiveLiveQueueLeakValue) -ne 'no') { Append-Log 'Threading guard: No leak/block was selected but coerced to downstream/drop-old outside Blocking diagnostic profile.' }
    if ($requestedAudioQueueCapMs -gt 0 -and $effectiveAudioQueueCapMs -gt $requestedAudioQueueCapMs) { Append-Log "Audio queue guard: raised nonzero audio queue cap from $requestedAudioQueueCapMs ms to $effectiveAudioQueueCapMs ms so GStreamer latency negotiation has enough headroom." }
    Append-Log "Browser JBUF guard: audio/video target $([int]$numDirectWebRtcPlayerJitterMs.Value)/$([int]$numDirectWebRtcVideoJitterMs.Value) ms, watchdog $([string]$cmbJbufWatchdogMode.SelectedItem), max $([int]$numJbufMaxMs.Value) ms, URL/config bridged."
    Append-Log "Split player sync: $([string]$cmbSplitPlayerSyncMode.SelectedItem), watchdog warmup $([int]$numSplitAudioWarmupSeconds.Value) sec applies to both JBUF and split-audio watchdogs, audio stall $([int]$numSplitAudioStallSeconds.Value) sec, offset baseline $([int]$numSplitAvOffsetBaselineMs.Value) ms (0 auto), drift warn $([int]$numSplitAvOffsetWarnMs.Value) ms. Default free-run never delays video."
    Append-Log "Direct GST WebRTC Opus: $([string]$cmbDirectWebRtcOpusMode.SelectedItem), frame $([string]$cmbDirectWebRtcOpusFrameMs.SelectedItem) ms, type $([string]$cmbDirectWebRtcOpusAudioType.SelectedItem), FEC $($chkDirectWebRtcOpusFec.Checked), DTX $($chkDirectWebRtcOpusDtx.Checked)."
    Append-Log "Pipeline clock: $([string](Get-VideoPipelineClockMode)); video timestamps $([string](Get-VideoTimestampMode)). Explicit system modes wrap the complete main graph in clockselect."
    Append-Log "Split audio process clock: $([string](Get-SplitAudioPipelineClockMode)) (UI selection $([string]$cmbSplitAudioPipelineClockMode.SelectedItem))."
    if ((Test-DirectWebRtcSplitAvPipelines) -and -not (Test-DirectWebRtcSharedSignaling) -and ([int]$numDirectWebRtcSignalingPort.Value -eq [int]$numDirectWebRtcSplitAudioSignalingPort.Value)) {
        Append-Log 'WARNING: Separate split signalling is selected but video and audio ports are identical; the second server cannot bind the same TCP port.'
    }
    $bothAudioSourcesSelected = $chkDesktopAudio.Checked -and $chkMic.Checked
    $mixerSummary = if ($bothAudioSourcesSelected -or (($chkDesktopAudio.Checked -or $chkMic.Checked) -and $chkAudioMixerMode.Checked)) { 'audio mix' } elseif ($chkDesktopAudio.Checked -or $chkMic.Checked) { 'legacy direct path' } else { 'not applicable' }
    Append-Log "Audio path: $mixerSummary (mixer flag=$($chkAudioMixerMode.Checked); desktop=$($chkDesktopAudio.Checked); microphone=$($chkMic.Checked))."
    Append-Log "Video sync mode: $([string]$cmbVideoSyncMode.SelectedItem); Audio sync mode: $([string]$cmbAudioSyncMode.SelectedItem). Explicit modes insert clocksync before compatible send/mux sinks; local preview also honors Video sync mode."
    Append-Log "Audio timing UI: clock=$([string]$cmbAudioClockMode.SelectedItem); mode=$([string]$cmbAudioTimingMode.SelectedItem); slave=$([string]$cmbAudioSlaveMethod.SelectedItem); low-latency override=$($chkWasapiLowLatencyOverride.Checked); buffer override=$($chkAudioBufferOverride.Checked) [$([int]$numAudioBufferMs.Value) ms]; latency override=$($chkAudioLatencyOverride.Checked) [$([int]$numAudioLatencyMs.Value) ms]; sample-rate override=$($chkAudioSampleRateOverride.Checked) [$([int]$numAudioSampleRate.Value) Hz]."
    Append-Log "Effective WASAPI source: $(Get-EffectiveAudioTimingSummary)"
    if (-not [string]::IsNullOrWhiteSpace($gstDebugSpec)) {
        Append-Log "GStreamer debug: GST_DEBUG=$gstDebugSpec, no color=$($chkGstDebugNoColor.Checked)."
    }
    else {
        Append-Log 'GStreamer debug: off.'
    }
    $mainLaunchExecutable = $gstPath
    $mainLaunchArguments = $arguments
    if ($useControlledLiveStream) {
        Append-Log 'Live scene editing: enabled on the actual broadcast compositor (single controlled worker pipeline).'
        Append-Log ('In-process pipeline: ' + (ConvertTo-InProcessGstLaunchDescription -Description $arguments))
        if ($processDiskLogging) {
            Append-Log 'Process disk logging: controlled worker stdout/stderr uses the normal per-run log files.'
        }
    }
    elseif ($runNeedsUnifiedPublisherHost) {
        $hostLaunch = Get-UnifiedPublisherHostLaunch -GstPath $gstPath -GstArguments $arguments
        $mainLaunchExecutable = [string]$hostLaunch.Executable
        $mainLaunchArguments = [string]$hostLaunch.Arguments
        Append-Log "Unified publisher host: $mainLaunchExecutable"
        Append-Log "Unified publisher host arguments: $mainLaunchArguments"
        Append-Log "Equivalent gst-launch arguments: $arguments"
    }
    else {
        Append-Log "Executable: $gstPath"
        Append-Log "Arguments: $arguments"
    }
    if (-not [string]::IsNullOrWhiteSpace($videoArguments)) {
        Append-Log "Video bridge executable: $gstPath"
        Append-Log "Video bridge arguments: $videoArguments"
    }
    if (-not [string]::IsNullOrWhiteSpace($audioArguments)) {
        Append-Log "Audio executable: $gstPath"
        Append-Log "Audio arguments: $audioArguments"
    }

    if ($useControlledLiveStream) {
        try {
            $pipelineDescription = ConvertTo-InProcessGstLaunchDescription -Description $arguments
            $showLivePreviewAtStart = (
                $form.Visible -and
                $form.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized -and
                -not ($transportEnabled -and $chkHidePreviewDuringStream.Checked)
            )
            $renderTarget = if ($showLivePreviewAtStart) { $previewPanel } else { Ensure-PreviewParkingWindow }
            $renderSize = if ($showLivePreviewAtStart) { $previewPanel.ClientSize } else { New-Object System.Drawing.Size(16, 16) }
            $null = $renderTarget.Handle

            $tracerEnvState = $null
            try {
                $tracerEnvState = Set-GstTracerEnvironment -Enable:([bool]$chkBufferLatenessTracer.Checked) -DebugSpec $gstDebugSpec -NoColor:([bool]$chkGstDebugNoColor.Checked)
                $workerMinRtpPort = if ($portRangeWorkerRequested) { [int]$numDirectWebRtcMinRtpPort.Value } else { 0 }
                $workerMaxRtpPort = if ($portRangeWorkerRequested) { [int]$numDirectWebRtcMaxRtpPort.Value } else { 0 }
                $workerStarted = Start-ControlledLiveWorker `
                    -Pipeline $pipelineDescription `
                    -WindowHandle $renderTarget.Handle `
                    -Width ([Math]::Max(1, $renderSize.Width)) `
                    -Height ([Math]::Max(1, $renderSize.Height)) `
                    -MinRtpPort $workerMinRtpPort `
                    -MaxRtpPort $workerMaxRtpPort
                if (-not $workerStarted) { throw 'The controlled live worker did not start.' }
            }
            finally {
                Restore-GstTracerEnvironment $tracerEnvState
            }

            $script:ControlledLiveStreamActive = $true
            $script:RecordingPipelineActive = [bool](Test-RecordingEnabled)
            $script:ControlledLivePreviewSurfaceHwnd = $renderTarget.Handle
            $script:ControlledLivePreviewAppliedSize = $renderSize
            $script:PreviewHwnd = [IntPtr]::Zero
            $script:PreviewParked = -not $showLivePreviewAtStart
            Sync-ControlledScenePreviewProperties
            Sync-ControlledLivePreviewLayout
            Save-ActiveProcessState

            # Same gate as the plain gst-launch path below: only for a genuine
            # outbound stream, never for local scene editing/preview/recording.
            if ($chkUpnpEnabled -and $chkUpnpEnabled.Checked -and $transportEnabled) {
                try { Add-UpnpPortMappings } catch { Append-Log "UPnP: $($_.Exception.Message)" }
            }
            if ($chkDdnsEnabled -and $chkDdnsEnabled.Checked -and $transportEnabled) {
                try { Update-DdnsRecord } catch { Append-Log "DDNS: $($_.Exception.Message)" }
            }
            if ($chkEmbeddedTlsEnabled -and $chkEmbeddedTlsEnabled.Checked -and $transportEnabled) {
                try { Start-LetsEncryptTlsProxies } catch { Append-Log "ACME: $($_.Exception.Message)" }
            }
            if ($chkViewerAuthenticationAllowPlaintext -and $chkViewerAuthenticationAllowPlaintext.Checked -and $transportEnabled) {
                try { Start-PlaintextAuthProxies } catch { Append-Log "AUTH: $($_.Exception.Message)" }
            }
            try { Resume-ActiveAuthenticationProxyForwarding } catch {}

            $mediaSuffix = if ($script:MediaMtxProcess -and -not $script:MediaMtxProcess.HasExited) { " + MediaMTX PID $($script:MediaMtxProcess.Id)" } else { '' }
            if ($transportEnabled) {
                $statusLabel.Text = "$([string]$cmbProtocol.SelectedItem) streaming - controlled worker PID $($script:GstProcess.Id)$mediaSuffix"
            }
            elseif ($script:RecordingPipelineActive) {
                $statusLabel.Text = "Recording locally - controlled worker PID $($script:GstProcess.Id)"
            }
            else {
                $statusLabel.Text = "Controlled live scene pipeline - worker PID $($script:GstProcess.Id)"
            }
            $statusLabel.ForeColor = [System.Drawing.Color]::DarkGreen
            Set-RunState $true
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] LIVE SCENE CONTROL ACTIVE: worker PID $($script:GstProcess.Id); editor geometry and opacity mutate its broadcast compositor over IPC."
            return
        }
        catch {
            $controlledStartCancelled = [bool]$script:PendingPipelineStop
            if ($controlledStartCancelled) {
                Append-Log 'Controlled live stream startup cancelled by the queued Stop request.'
            }
            else {
                Append-Log "Controlled live stream start error: $($_.Exception.Message)"
                Append-Log 'Falling back to the unchanged external gst-launch stream for this run.'
            }
            $script:SuppressControlledLiveStream = $true
            $script:ControlledLiveStreamActive = $false
            try {
                if ($script:GstProcess -and -not $script:GstProcess.HasExited) {
                    Stop-ProcessTreeById -ProcessId $script:GstProcess.Id
                }
            }
            catch {}
            Close-ControlledLiveWorkerPipe
            try { if ($script:GstProcess) { $script:GstProcess.Dispose() } } catch {}
            $script:GstProcess = $null
            $script:ControlledLivePreviewSurfaceHwnd = [IntPtr]::Zero
            $script:ControlledLivePreviewAppliedSize = [System.Drawing.Size]::Empty
            if ($controlledStartCancelled) { return }
            [System.Threading.Thread]::Sleep(750)
        }
    }

    $useWebRtcPortRangeWorker = (-not $useControlledLiveStream) -and (-not $runNeedsUnifiedPublisherHost) -and $portRangeWorkerRequested

    try {
        # Live scene editing is NOT in this list: GstControlledScenePreview
        # (00-Setup.ps1) hooks webrtcsink's consumer-added signal to pin the
        # ICE port range on its own hosted pipeline, exactly like the
        # separate WebRTC port-range worker does for the plain gst-launch
        # path -- so the two are no longer mutually exclusive. Split A/V
        # without a unified publisher genuinely has no mechanism to specify
        # media ports for the separate signalling pipeline yet.
        $unsupportedPortRangeTopology = (
            $runNeedsUnifiedPublisherHost -or
            ((Test-DirectWebRtcSplitAvPipelines) -and -not (Test-DirectWebRtcUnifiedPublisher))
        )
        if ($portRangeWorkerRequested -and $unsupportedPortRangeTopology) {
            throw 'The Min/Max RTP port range cannot be enforced with separate A/V publishers or advanced unified publisher host options enabled.'
        }
        $tracerEnvState = $null
        try {
            $tracerEnvState = Set-GstTracerEnvironment -Enable:([bool]$chkBufferLatenessTracer.Checked) -DebugSpec $gstDebugSpec -NoColor:([bool]$chkGstDebugNoColor.Checked)
            if ($chkBufferLatenessTracer.Checked) { Append-Log 'GStreamer buffer-lateness tracer enabled for this run.' }
            if ($useWebRtcPortRangeWorker) {
                Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Min/Max RTP port set: running webrtcsink in a dedicated native host process instead of the external gst-launch process."
                $script:GstProcess = Start-WebRtcPortRangeWorker -Pipeline $mainLaunchArguments -MinRtpPort ([int]$numDirectWebRtcMinRtpPort.Value) -MaxRtpPort ([int]$numDirectWebRtcMaxRtpPort.Value)
            }
            elseif ($processDiskLogging) {
                $script:GstProcess = Start-Process -FilePath $mainLaunchExecutable -ArgumentList $mainLaunchArguments -RedirectStandardOutput $script:StdOutPath -RedirectStandardError $script:StdErrPath -WindowStyle Hidden -PassThru
            }
            else {
                $script:GstProcess = Start-Process -FilePath $mainLaunchExecutable -ArgumentList $mainLaunchArguments -WindowStyle Hidden -PassThru
            }
        }
        finally {
            Restore-GstTracerEnvironment $tracerEnvState
        }

        Write-PsDebugTrace "Start-GstStream: main gst-launch process started (PID=$($script:GstProcess.Id))"
        Set-GstProcessPriority -Process $script:GstProcess

        # Only for a genuine outbound stream -- $transportEnabled is already
        # forced false for Preview/Recording-only runs (Test-TransportEnabled
        # checks $script:ForceLocalPreviewMode), so local-only activity never
        # touches the router. Mapping happens once per actual stream start;
        # Add-UpnpPortMappings' own reconciliation logic makes a repeat call
        # on an automatic restart a cheap no-op against already-live mappings
        # rather than a real demap/remap cycle.
        if ($chkUpnpEnabled -and $chkUpnpEnabled.Checked -and $transportEnabled) {
            try { Add-UpnpPortMappings } catch { Append-Log "UPnP: $($_.Exception.Message)" }
        }
        if ($chkDdnsEnabled -and $chkDdnsEnabled.Checked -and $transportEnabled) {
            try { Update-DdnsRecord } catch { Append-Log "DDNS: $($_.Exception.Message)" }
        }
        if ($chkEmbeddedTlsEnabled -and $chkEmbeddedTlsEnabled.Checked -and $transportEnabled) {
            try { Start-LetsEncryptTlsProxies } catch { Append-Log "ACME: $($_.Exception.Message)" }
        }
        if ($chkViewerAuthenticationAllowPlaintext -and $chkViewerAuthenticationAllowPlaintext.Checked -and $transportEnabled) {
            try { Start-PlaintextAuthProxies } catch { Append-Log "AUTH: $($_.Exception.Message)" }
        }
        try { Resume-ActiveAuthenticationProxyForwarding } catch {}

        if ($script:JobHandle -ne [IntPtr]::Zero) {
            try {
                [GstProcessJob]::AssignProcess($script:JobHandle, $script:GstProcess.Handle)
            }
            catch {
                Append-Log "WARNING: GStreamer could not be assigned to the kill-on-close job: $($_.Exception.Message)"
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($videoArguments)) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Starting split video capture / RTP bridge pipeline..."
            # Let the unified publisher bind its UDP receivers and signalling/web listeners first.
            Start-Sleep -Milliseconds 250
            $videoTracerEnvState = $null
            try {
                $videoTracerEnvState = Set-GstTracerEnvironment -Enable:([bool]$chkBufferLatenessTracer.Checked) -DebugSpec $gstDebugSpec -NoColor:([bool]$chkGstDebugNoColor.Checked)
                if ($processDiskLogging) {
                    $script:GstVideoProcess = Start-Process -FilePath $gstPath -ArgumentList $videoArguments -RedirectStandardOutput $script:StdOutVideoPath -RedirectStandardError $script:StdErrVideoPath -WindowStyle Hidden -PassThru
                }
                else {
                    $script:GstVideoProcess = Start-Process -FilePath $gstPath -ArgumentList $videoArguments -WindowStyle Hidden -PassThru
                }
            }
            finally {
                Restore-GstTracerEnvironment $videoTracerEnvState
            }
            Set-GstProcessPriority -Process $script:GstVideoProcess
            if ($script:JobHandle -ne [IntPtr]::Zero) {
                try { [GstProcessJob]::AssignProcess($script:JobHandle, $script:GstVideoProcess.Handle) }
                catch { Append-Log "WARNING: Split video bridge GStreamer could not be assigned to the kill-on-close job: $($_.Exception.Message)" }
            }
            Append-Log "Split video bridge GST PID: $($script:GstVideoProcess.Id)"
        }

        if (-not [string]::IsNullOrWhiteSpace($audioArguments)) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Starting split audio-only GStreamer pipeline..."
            $audioTracerEnvState = $null
            try {
                $audioTracerEnvState = Set-GstTracerEnvironment -Enable:([bool]$chkBufferLatenessTracer.Checked) -DebugSpec $gstDebugSpec -NoColor:([bool]$chkGstDebugNoColor.Checked)
                if ($processDiskLogging) {
                    $script:GstAudioProcess = Start-Process -FilePath $gstPath -ArgumentList $audioArguments -RedirectStandardOutput $script:StdOutAudioPath -RedirectStandardError $script:StdErrAudioPath -WindowStyle Hidden -PassThru
                }
                else {
                    $script:GstAudioProcess = Start-Process -FilePath $gstPath -ArgumentList $audioArguments -WindowStyle Hidden -PassThru
                }
            }
            finally {
                Restore-GstTracerEnvironment $audioTracerEnvState
            }
            Set-GstProcessPriority -Process $script:GstAudioProcess
            if ($script:JobHandle -ne [IntPtr]::Zero) {
                try { [GstProcessJob]::AssignProcess($script:JobHandle, $script:GstAudioProcess.Handle) }
                catch { Append-Log "WARNING: Split audio GStreamer could not be assigned to the kill-on-close job: $($_.Exception.Message)" }
            }
            Append-Log "Split audio GST PID: $($script:GstAudioProcess.Id)"
        }

        Save-ActiveProcessState
        $script:RecordingPipelineActive = [bool]((-not $customGstArgumentsOverride) -and (Test-RecordingEnabled))

        $targetSuffix = if ((Test-FullscreenCaptureMode) -and $script:CaptureWindowTitle) { " - $($script:CaptureWindowTitle)" } else { '' }
        $mediaSuffix = if (
            $script:MediaMtxProcess -and
            -not $script:MediaMtxProcess.HasExited
        ) {
            " + MediaMTX PID $($script:MediaMtxProcess.Id)"
        }
        else {
            ''
        }
        if ($customGstArgumentsOverride) {
            $statusLabel.Text = "Custom gst-launch pipeline - GST PID $($script:GstProcess.Id)$mediaSuffix"
        }
        elseif ($transportEnabled) {
            $videoSuffix = if ($script:GstVideoProcess -and -not $script:GstVideoProcess.HasExited) { " + Video PID $($script:GstVideoProcess.Id)" } else { '' }
            $audioSuffix = if ($script:GstAudioProcess -and -not $script:GstAudioProcess.HasExited) { " + Audio PID $($script:GstAudioProcess.Id)" } else { '' }
            $statusLabel.Text = "$([string]$cmbProtocol.SelectedItem) streaming - GST PID $($script:GstProcess.Id)$videoSuffix$audioSuffix$mediaSuffix$targetSuffix"
        }
        elseif ($script:RecordingPipelineActive) {
            $statusLabel.Text = "Recording locally - GST PID $($script:GstProcess.Id)$targetSuffix"
        }
        else {
            $statusLabel.Text = "Preview only - GST PID $($script:GstProcess.Id)$targetSuffix"
        }
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkGreen
        Set-RunState $true
    }
    catch {
        foreach ($failedProcess in @($script:GstProcess, $script:GstVideoProcess, $script:GstAudioProcess)) {
            if (-not $failedProcess) { continue }
            try {
                if (-not $failedProcess.HasExited) {
                    Stop-ProcessTreeById -ProcessId $failedProcess.Id
                    $failedProcess.WaitForExit(3000) | Out-Null
                }
            }
            catch {}
            try { $failedProcess.Dispose() } catch {}
        }
        Close-WebRtcPortRangeWorkerPipe
        try { Remove-UpnpPortMappings } catch {}
        if (-not (Test-KeepAuthenticationProxiesOnRestart)) {
            try { Stop-LetsEncryptTlsProxies } catch {}
            try { Stop-PlaintextAuthProxies } catch {}
        }
        $script:GstProcess = $null
        $script:GstVideoProcess = $null
        $script:GstAudioProcess = $null
        $script:PreviewOnlyMode = $false
        $script:ForceLocalPreviewMode = $false
        $script:RecordingPipelineRequested = $false
        $script:RecordingPipelineActive = $false
        $script:RecordingOnlyMode = $false
        Stop-ManagedMediaMtx -Quiet
        Remove-ActiveProcessState
        $statusLabel.Text = 'Start failed'
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkRed
        Set-RunState $false
        Append-Log "START ERROR: $($_.Exception.Message)"
        Write-PsDebugTrace "Start-GstStream: FAILED - $($_.Exception.Message)"
    }
    }
    finally {
        $script:SuppressCustomGstArgumentsOverride = $false
        $script:PipelineStartInProgress = $false
        Write-PsDebugTrace "Start-GstStream: exiting"
        if ($script:PendingPipelineStop) {
            $script:PendingPipelineStop = $false
            $script:RestartAt = $null
            $script:AutomaticRestartPending = $false
            Stop-GstStream
        }
        else {
            $running = (
                ($script:GstProcess -and -not $script:GstProcess.HasExited) -or
                $script:DynamicScenePreviewActive -or
                $script:ControlledLiveStreamActive
            )
            Set-RunState ([bool]$running)
        }
    }
}

function Stop-ControlledLiveStream {
    param(
        [switch]$Restart,
        [switch]$AutomaticRestart,
        [switch]$SuppressPreviewRestore
    )

    if (-not $script:ControlledLiveStreamActive) { return $false }

    $script:StopRequested = $true
    $script:WaitingForFullscreen = $false
    if ($Restart) {
        $script:AutomaticRestartPending = [bool]$AutomaticRestart
        $script:RestartRecordingOnlyMode = [bool]($script:RestartRecordingOnlyMode -or $script:RecordingOnlyMode)
    }
    else {
        $script:AutomaticRestartPending = $false
        $script:RestartRecordingOnlyMode = $false
    }
    $script:RestartAt = if ($Restart) { (Get-Date).AddMilliseconds(800) } else { $null }
    $workerProcess = $script:GstProcess
    if ($workerProcess -and -not $workerProcess.HasExited) {
        Append-Log (
            "[$(Get-Date -Format 'HH:mm:ss')] Stopping complete controlled live " +
            "process tree - PID $($workerProcess.Id)..."
        )
        # Sever any live viewer connections through the auth proxies FIRST,
        # and stop them from accepting any forwarding work until the new
        # process is up (only meaningful with "Keep auth on restarts", where
        # those proxies are about to keep running through this kill) -- a
        # clean, immediate disconnect now, rather than leaving that
        # connection to eventually notice this process died on its own, and
        # no new forwarding attempts that could race the restart.
        try { Suspend-ActiveAuthenticationProxyForwarding } catch {}
        try { Disconnect-ActiveAuthenticationProxyConnections } catch {}
        # Intentionally identical to every legacy publisher stop. Do not send a
        # pipe Stop command or transition the graph to NULL first: terminating
        # this process is the signalling/socket boundary the web player expects.
        Stop-ProcessTreeById -ProcessId $workerProcess.Id
        try { $workerProcess.WaitForExit(3000) | Out-Null } catch {}
    }
    Close-ControlledLiveWorkerPipe
    # Only demap on a genuine stop, not a settings-triggered restart-in-place
    # -- see the identical comment in Stop-GstStream's plain-path teardown.
    if (-not $Restart) {
        try { Remove-UpnpPortMappings } catch {}
    }
    # Torn down on EVERY stop, restart included, unless "Keep auth on
    # restarts" is checked -- this must NOT be nested inside `if (-not
    # $Restart)` above. An active, already-authenticated viewer connection
    # is still being pumped through these proxies at this exact moment;
    # leaving the proxy's listener (and that live connection) untouched
    # while the GST process underneath gets killed is what caused the UI
    # to freeze on Restart specifically (Stop tore these down and never
    # froze; Restart silently kept them alive and did).
    if (-not (Test-KeepAuthenticationProxiesOnRestart)) {
        try { Stop-LetsEncryptTlsProxies } catch {}
        try { Stop-PlaintextAuthProxies } catch {}
    }
    try { if ($workerProcess) { $workerProcess.Dispose() } } catch {}
    $script:GstProcess = $null

    $script:ControlledLiveStreamActive = $false
    $script:ControlledLivePreviewSurfaceHwnd = [IntPtr]::Zero
    $script:ControlledLivePreviewAppliedSize = [System.Drawing.Size]::Empty
    $script:PreviewHwnd = [IntPtr]::Zero
    $script:PreviewParked = $false
    $script:PipelineHasPreview = $false
    $script:PreviewOnlyMode = $false
    $script:ForceLocalPreviewMode = $false
    $script:RecordingPipelineRequested = $false
    $script:RecordingPipelineActive = $false
    $script:RecordingOnlyMode = $false
    $script:ForceLiveScenePreviewBranch = $false
    Reset-PreviewAppliedState

    $previewPlaceholder.Visible = $true
    $previewPlaceholder.Text = if ($Restart) { 'Restarting stream...' } else { 'Preview stopped' }

    Stop-ManagedMediaMtx
    # MediaMTX may emit final diagnostics while it is being stopped. Drain that
    # tail before discarding the paths so a failed relay shutdown remains visible.
    $finalText = Drain-ManagedProcessLogs
    if ($finalText) { Append-Log $finalText }
    Reset-ProcessLogPaths
    Remove-ActiveProcessState

    Set-RunState $false
    if ($Restart) {
        $statusLabel.Text = 'Restarting...'
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
    }
    else {
        $statusLabel.Text = 'Stopped'
        $statusLabel.ForeColor = [System.Drawing.Color]::Black
        $script:StopRequested = $false
        if (-not $SuppressPreviewRestore) {
            $null = $form.BeginInvoke([Action]{
                try { Sync-StandalonePreviewState -Quiet } catch {}
            })
        }
    }
    return $true
}

function Stop-GstStream {
    param(
        [switch]$Restart,
        [switch]$AutomaticRestart,
        [switch]$SuppressPreviewRestore,
        [switch]$Intentional,
        [switch]$ViewerRestart
    )

    Write-PsDebugTrace "Stop-GstStream: entering (Restart=$Restart AutomaticRestart=$AutomaticRestart Intentional=$Intentional ViewerRestart=$ViewerRestart)"
    if ($ViewerRestart) {
        Set-DirectWebRtcStreamStopMarker -IntentionalStop $false -Restarting
    }
    elseif (
        $Intentional -and
        -not $script:PreviewOnlyMode -and
        $chkSendEosOnStop -and
        $chkSendEosOnStop.Checked
    ) {
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Marking the stream intentionally stopped before pipeline teardown."
        Set-DirectWebRtcStreamStopMarker -IntentionalStop $true
    }
    if (Stop-ControlledLiveStream -Restart:$Restart -AutomaticRestart:$AutomaticRestart -SuppressPreviewRestore:$SuppressPreviewRestore) { return }

    if ($script:DynamicScenePreviewActive) {
        Stop-DynamicScenePreview
        if (-not $Restart) { return }
    }

    $script:StopRequested = $true
    $script:WaitingForFullscreen = $false
    $wasPreviewOnly = [bool]$script:PreviewOnlyMode
    $wasRecordingOnly = [bool]$script:RecordingOnlyMode

    if ($Restart) {
        $script:AutomaticRestartPending = [bool]$AutomaticRestart
        $script:RestartRecordingOnlyMode = [bool]($script:RestartRecordingOnlyMode -or $wasRecordingOnly)
        $script:RestartAt = (Get-Date).AddMilliseconds(800)
    }
    else {
        $script:AutomaticRestartPending = $false
        $script:RestartRecordingOnlyMode = $false
        $script:RestartAt = $null
    }

    $script:PreviewHwnd = [IntPtr]::Zero
    $script:PreviewParked = $false
    $script:PipelineHasPreview = $false
    $script:PreviewOnlyMode = $false
    $script:ForceLocalPreviewMode = $false
    $script:RecordingPipelineRequested = $false
    $script:RecordingPipelineActive = $false
    $script:RecordingOnlyMode = $false
    Reset-PreviewAppliedState
    $previewPlaceholder.Visible = $true
    $previewPlaceholder.Text = if ($wasPreviewOnly) { 'Preview stopped' } else { 'Preview stopped' }

    $hadGst =
        $script:GstProcess -and
        -not $script:GstProcess.HasExited

    $hadVideoGst =
        $script:GstVideoProcess -and
        -not $script:GstVideoProcess.HasExited

    $hadAudioGst =
        $script:GstAudioProcess -and
        -not $script:GstAudioProcess.HasExited

    $hadMedia =
        $script:MediaMtxProcess -and
        -not $script:MediaMtxProcess.HasExited

    if ($hadGst -or $hadVideoGst -or $hadAudioGst -or $hadMedia) {
        $statusLabel.Text = 'Stopping...'
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
    }

    # Sever any live viewer connections through the auth proxies FIRST, and
    # stop them from accepting any forwarding work until the new process is
    # up (only meaningful with "Keep auth on restarts", where those proxies
    # are about to keep running through this kill) -- a clean, immediate
    # disconnect now, rather than leaving that connection to eventually
    # notice these processes died on their own, and no new forwarding
    # attempts that could race the restart.
    if ($hadGst -or $hadVideoGst -or $hadAudioGst) {
        try { Suspend-ActiveAuthenticationProxyForwarding } catch {}
        try { Disconnect-ActiveAuthenticationProxyConnections } catch {}
    }

    # Stop the publisher first so MediaMTX sees a clean publisher disconnect,
    # then stop the managed server itself.
    if ($hadGst) {
        Append-Log (
            "[$(Get-Date -Format 'HH:mm:ss')] Stopping complete GStreamer " +
            "process tree - PID $($script:GstProcess.Id)..."
        )
        Stop-ProcessTreeById -ProcessId $script:GstProcess.Id

        try {
            $script:GstProcess.WaitForExit(3000) | Out-Null
        }
        catch {}
    }

    if ($hadVideoGst) {
        Append-Log (
            "[$(Get-Date -Format 'HH:mm:ss')] Stopping split video bridge GStreamer " +
            "process tree - PID $($script:GstVideoProcess.Id)..."
        )
        Stop-ProcessTreeById -ProcessId $script:GstVideoProcess.Id
        try { $script:GstVideoProcess.WaitForExit(3000) | Out-Null } catch {}
    }

    if ($hadAudioGst) {
        Append-Log (
            "[$(Get-Date -Format 'HH:mm:ss')] Stopping split audio GStreamer " +
            "process tree - PID $($script:GstAudioProcess.Id)..."
        )
        Stop-ProcessTreeById -ProcessId $script:GstAudioProcess.Id
        try { $script:GstAudioProcess.WaitForExit(3000) | Out-Null } catch {}
    }

    try {
        if ($script:GstProcess) {
            $script:GstProcess.Dispose()
        }
        if ($script:GstVideoProcess) {
            $script:GstVideoProcess.Dispose()
        }
        if ($script:GstAudioProcess) {
            $script:GstAudioProcess.Dispose()
        }
    }
    catch {}
    Close-WebRtcPortRangeWorkerPipe
    # Only demap on a genuine stop, not a settings-triggered restart-in-place
    # -- routers can rate-limit/dislike frequent UPnP add/remove churn, and
    # a restart is about to re-map the exact same ports moments later anyway.
    if (-not $Restart) {
        try { Remove-UpnpPortMappings } catch {}
    }
    # Torn down on EVERY stop, restart included, unless "Keep auth on
    # restarts" is checked -- deliberately NOT nested inside `if (-not
    # $Restart)` above (see the matching comment in Stop-ControlledLiveStream's
    # teardown, a few hundred lines up). Leaving an active, authenticated
    # viewer connection's proxy alive while the GST process underneath it
    # gets killed is what caused Restart specifically to freeze the UI.
    if (-not (Test-KeepAuthenticationProxiesOnRestart)) {
        try { Stop-LetsEncryptTlsProxies } catch {}
        try { Stop-PlaintextAuthProxies } catch {}
    }
    $script:GstProcess = $null
    $script:GstVideoProcess = $null
    $script:GstAudioProcess = $null

    Stop-ManagedMediaMtx

    Remove-ActiveProcessState

    if (-not $Restart) {
        $statusLabel.Text = 'Stopped'
        $statusLabel.ForeColor = [System.Drawing.Color]::Black
        Set-RunState $false
        $script:StopRequested = $false
        if (-not $wasPreviewOnly -and -not $SuppressPreviewRestore) {
            $null = $form.BeginInvoke([Action]{
                try { Sync-StandalonePreviewState -Quiet } catch {}
            })
        }
    }
    else {
        Set-RunState $false
    }
}

function Test-GStreamerElements {
    $gstPath = Resolve-GstLaunchSelection -RequestedPath $txtGstPath.Text -UpdateControl
    if (-not (Test-GstLaunchPath $gstPath)) {
        [System.Windows.Forms.MessageBox]::Show('Select a valid gst-launch-1.0.exe first.', $script:AppName, 'OK', 'Warning') | Out-Null
        return
    }

    Prepare-GStreamerRuntime -GstPath $gstPath
    $inspectPath = Join-Path (Split-Path -Parent $gstPath) 'gst-inspect-1.0.exe'
    if (-not (Test-Path -LiteralPath $inspectPath)) {
        [System.Windows.Forms.MessageBox]::Show('gst-inspect-1.0.exe was not found beside gst-launch-1.0.exe.', $script:AppName, 'OK', 'Warning') | Out-Null
        return
    }

    $transportEnabled = Test-TransportEnabled
    $definition = Get-SelectedEncoderDefinition
    $codec = [string]$definition.Codec
    $protocol = [string]$cmbProtocol.SelectedItem

    $captureMethod = Get-SelectedCaptureMethod
    $elements = New-Object System.Collections.Generic.List[string]
    $baseElements = @([string]$captureMethod.Element, 'd3d11convert')
    if ($transportEnabled) { $baseElements += [string]$definition.Element }
    foreach ($element in $baseElements) {
        if (-not [string]::IsNullOrWhiteSpace($element)) {
            $elements.Add($element)
        }
    }

    if ([string]$captureMethod.Method -eq 'MonitorGdi') {
        foreach ($element in @('videoconvert', 'videoscale', 'd3d11upload')) {
            $elements.Add($element)
        }
    }

    if ($transportEnabled -and [string]$definition.Input -eq 'I420') {
        $elements.Add('d3d11download')
        $elements.Add('videoconvert')
    }

    if ($transportEnabled -and -not [string]::IsNullOrWhiteSpace([string]$definition.Parser)) {
        $elements.Add([string]$definition.Parser)
    }

    if ($chkPreview.Checked -or $chkRecordingEnabled.Checked) {
        $elements.Add('tee')
    }

    if ($chkPreview.Checked) {
        $elements.Add('d3d11videosink')
    }

    if ($chkRecordingEnabled.Checked) {
        $recordDefinition = Get-SelectedRecordingEncoderDefinition
        foreach ($element in @(
            'matroskamux',
            'filesink',
            'd3d11convert',
            [string]$recordDefinition.Element
        )) {
            if (-not [string]::IsNullOrWhiteSpace($element)) {
                $elements.Add($element)
            }
        }

        if ([string]$recordDefinition.Input -eq 'I420') {
            $elements.Add('d3d11download')
            $elements.Add('videoconvert')
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$recordDefinition.Parser)) {
            $elements.Add([string]$recordDefinition.Parser)
        }

        if ($chkRecordingDesktopAudio.Checked -or $chkRecordingMic.Checked) {
            foreach ($element in @(
                'wasapi2src',
                'audioconvert',
                'audioresample',
                'opusenc'
            )) {
                $elements.Add($element)
            }

            if ($chkRecordingDesktopAudio.Checked -and $chkRecordingMic.Checked) {
                $elements.Add('audiomixer')
            }
        }
    }

    $userAudioEnabled =
        $transportEnabled -and
        (
            $chkDesktopAudio.Checked -or
            $chkMic.Checked
        )

    $usingWhipSilentClockAudio =
        $transportEnabled -and
        $protocol -in @('WHIP', 'GST WebRTC') -and
        -not $userAudioEnabled

    $hasAudio =
        $userAudioEnabled -or
        $usingWhipSilentClockAudio

    if ($hasAudio) {
        foreach (
            $element in @(
                'wasapi2src',
                'audioconvert',
                'audioresample',
                'volume'
            )
        ) {
            $elements.Add($element)
        }

        if (($chkDesktopAudio.Checked -and $chkMic.Checked) -or (($chkDesktopAudio.Checked -or $chkMic.Checked) -and $chkAudioMixerMode.Checked)) {
            $elements.Add('audiomixer')
        }
    }

    $audioDefinition = if ($usingWhipSilentClockAudio) {
        $script:AudioCodecCatalog['Opus']
    }
    elseif ($hasAudio) {
        Get-SelectedAudioCodecDefinition
    }
    else {
        $null
    }

    if ($transportEnabled) {
        switch ($protocol) {
        'WHIP' {
            $elements.Add('whipclientsink')

            $videoPayloader = switch ($codec) {
                'H264' { 'rtph264pay' }
                'H265' { 'rtph265pay' }
                'AV1'  { 'rtpav1pay' }
                'VP8'  { 'rtpvp8pay' }
                'VP9'  { 'rtpvp9pay' }
            }

            if ($videoPayloader) {
                $elements.Add($videoPayloader)
            }

            if ($hasAudio) {
                $elements.Add([string]$audioDefinition.Element)
                if (-not [string]::IsNullOrWhiteSpace([string]$audioDefinition.Parser)) {
                    $elements.Add([string]$audioDefinition.Parser)
                }
                if ([string]$audioDefinition.Codec -eq 'OPUS') {
                    $elements.Add('rtpopuspay')
                }
            }
        }

        'GST WebRTC' {
            $elements.Add('webrtcsink')
            if (Test-DirectWebRtcUnifiedPublisher) {
                foreach ($element in @(
                    'udpsrc',
                    'udpsink',
                    'rtpopuspay',
                    'rtpopusdepay',
                    'opusenc',
                    'opusparse'
                )) {
                    $elements.Add($element)
                }

                if ([int]$numDirectWebRtcBridgeJitterMs.Value -gt 0) {
                    $elements.Add('rtpjitterbuffer')
                }

                switch ($codec) {
                    'H264' {
                        $elements.Add('rtph264pay')
                        $elements.Add('rtph264depay')
                        $elements.Add('h264parse')
                    }
                    'H265' {
                        $elements.Add('rtph265pay')
                        $elements.Add('rtph265depay')
                        $elements.Add('h265parse')
                    }
                }
            }
            elseif ($hasAudio) {
                $elements.Add([string]$audioDefinition.Element)
                if (-not [string]::IsNullOrWhiteSpace([string]$audioDefinition.Parser)) {
                    $elements.Add([string]$audioDefinition.Parser)
                }
            }
        }

        'SRT' {
            $elements.Add('mpegtsmux')
            $elements.Add('srtsink')
            if ($hasAudio) {
                $elements.Add([string]$audioDefinition.Element)
                if (-not [string]::IsNullOrWhiteSpace([string]$audioDefinition.Parser)) {
                    $elements.Add([string]$audioDefinition.Parser)
                }
            }
        }

        'RTMP' {
            $elements.Add($(if ($codec -eq 'H264') { 'flvmux' } else { 'eflvmux' }))
            $elements.Add('rtmp2sink')
            if ($hasAudio) {
                $elements.Add([string]$audioDefinition.Element)
                if (-not [string]::IsNullOrWhiteSpace([string]$audioDefinition.Parser)) {
                    $elements.Add([string]$audioDefinition.Parser)
                }
            }
        }

        'RTSP' {
            $elements.Add('rtspclientsink')
            if ($hasAudio) {
                $elements.Add([string]$audioDefinition.Element)
                if (-not [string]::IsNullOrWhiteSpace([string]$audioDefinition.Parser)) {
                    $elements.Add([string]$audioDefinition.Parser)
                }

                $audioPayloader = switch ([string]$audioDefinition.Codec) {
                    'OPUS' { 'rtpopuspay' }
                    'AAC'  { 'rtpmp4apay' }
                    'MP3'  { 'rtpmpapay' }
                    'AC3'  { 'rtpac3pay' }
                }
                if ($audioPayloader) {
                    $elements.Add($audioPayloader)
                }
            }
        }
        }
    }

    $missing = New-Object System.Collections.Generic.List[string]
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        foreach ($element in ($elements | Select-Object -Unique)) {
            & $inspectPath $element *> $null
            if ($LASTEXITCODE -ne 0) {
                $missing.Add($element)
            }
        }
    }
    finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }

    $compatibilityWarning = $null
    if ($transportEnabled -and (Test-DirectWebRtcUnifiedPublisher) -and $codec -notin @('H264','H265')) {
        $compatibilityWarning = "Unified A/V publisher bridge currently supports H264 and H265 only; selected codec is $codec."
    }
    elseif ($transportEnabled -and (Test-DirectWebRtcUnifiedPublisher) -and (Get-ComboSelectedOrDefault $cmbDirectWebRtcOpusMode $script:DefaultDirectWebRtcOpusMode) -eq 'Raw audio to webrtcsink') {
        $compatibilityWarning = 'Unified A/V publisher bridge requires Explicit Opus encoder mode.'
    }
    elseif ($transportEnabled -and -not (Test-CodecProtocolCompatibility -Codec $codec -Protocol $protocol)) {
        $compatibilityWarning = "$codec is not supported by the $protocol pipeline template."
    }
    elseif (
        $transportEnabled -and
        $hasAudio -and
        -not $usingWhipSilentClockAudio -and
        -not (Test-AudioCodecProtocolCompatibility `
            -AudioCodecName ([string]$cmbAudioCodec.SelectedItem) `
            -Protocol $protocol)
    ) {
        $compatibilityWarning =
            "$([string]$cmbAudioCodec.SelectedItem) is not supported by $protocol."
    }

    if ($missing.Count -eq 0 -and -not $compatibilityWarning) {
        $audioSummary = if ($usingWhipSilentClockAudio) {
            'Muted Opus/WASAPI clock track (automatic)'
        }
        elseif ($hasAudio) {
            [string]$cmbAudioCodec.SelectedItem
        }
        else {
            'Disabled'
        }

        [System.Windows.Forms.MessageBox]::Show(
            (
                "All elements required by the current configuration were found." +
                "`r`n`r`nTransport: $(if ($transportEnabled) { 'Enabled - ' + $protocol } else { 'Disabled' })" +
                "`r`nCapture: $(Get-SelectedCaptureMethodName)" +
                "`r`nVideo: $(if ($transportEnabled) { [string]$definition.Element + ' (' + $codec + ')' } else { 'No network encoder branch' })" +
                "`r`nAudio: $audioSummary" +
                "`r`nRecording: $(if ($chkRecordingEnabled.Checked) { 'Enabled - ' + [string]$cmbRecordingEncoder.SelectedItem } else { 'Disabled' })"
            ),
            $script:AppName,
            'OK',
            'Information'
        ) | Out-Null
    }
    else {
        $messages = New-Object System.Collections.Generic.List[string]
        if ($missing.Count -gt 0) {
            $messages.Add("Missing GStreamer elements:`r`n$($missing -join "`r`n")")
        }
        if ($compatibilityWarning) {
            $messages.Add($compatibilityWarning)
        }

        [System.Windows.Forms.MessageBox]::Show(
            ($messages -join "`r`n`r`n"),
            $script:AppName,
            'OK',
            'Error'
        ) | Out-Null
    }
}
