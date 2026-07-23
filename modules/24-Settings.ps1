# Module: 24-Settings.ps1 (auto-extracted by tools/Split-Monolith.ps1 -- edit here, then run tools/Build-Monolith.ps1)

function Save-Settings {
    # UI events fire while Load-Settings assigns controls. Never persist that
    # partially restored state back over the complete settings file.
    if ($script:LoadingSettings) { return }

    try {
        if (-not (Test-Path -LiteralPath $script:ConfigDirectory)) {
            $null = New-Item -ItemType Directory -Path $script:ConfigDirectory -Force
        }

        $protocol = [string]$cmbProtocol.SelectedItem
        if ($protocol -and -not [string]::IsNullOrWhiteSpace($txtDestination.Text)) {
            $script:ProtocolDestinations[$protocol] = $txtDestination.Text.Trim()
        }

        $settings = [ordered]@{
            GstPath           = $txtGstPath.Text
            CustomGstArgumentsEnabled = [bool]$chkCustomGstArgumentsEnabled.Checked
            CustomGstArguments = [string]$txtCustomGstArguments.Text
            StartMediaMtx     = $chkStartMediaMtx.Checked
            MediaMtxPath      = $txtMediaMtxPath.Text
            TransportEnabled  = $chkTransportEnabled.Checked
            Protocol          = $protocol
            WhipUrl           = $script:ProtocolDestinations.WHIP
            SrtUrl            = $script:ProtocolDestinations.SRT
            RtmpUrl           = $script:ProtocolDestinations.RTMP
            RtspUrl           = $script:ProtocolDestinations.RTSP
            GstWebRtcUrl      = $script:ProtocolDestinations[$script:DirectWebRtcProtocolName]
            DirectWebRtcSignalingHost = $txtDirectWebRtcSignalingHost.Text
            DirectWebRtcSignalingPort = [int]$numDirectWebRtcSignalingPort.Value
            DirectWebRtcSplitAudioSignalingPort = [int]$numDirectWebRtcSplitAudioSignalingPort.Value
            DirectWebRtcSharedSignaling = [bool]$chkDirectWebRtcSharedSignaling.Checked
            SplitClockSignalingOverrides = [bool]$chkSplitClockSignalingOverrides.Checked
            SplitVideoClockSignaling = [string]$cmbSplitVideoClockSignaling.SelectedItem
            SplitAudioClockSignaling = [string]$cmbSplitAudioClockSignaling.SelectedItem
            DirectWebRtcMediaStreamGrouping = [string](Get-DirectWebRtcMediaStreamGrouping)
            DirectWebRtcVideoMediaStreamId = [string](Get-DirectWebRtcMediaStreamId -Kind video)
            DirectWebRtcAudioMediaStreamId = [string](Get-DirectWebRtcMediaStreamId -Kind audio)
            DirectWebRtcUnifiedPublisher = [bool]$chkDirectWebRtcUnifiedPublisher.Checked
            DirectWebRtcBridgeVideoPort = [int]$numDirectWebRtcBridgeVideoPort.Value
            DirectWebRtcBridgeAudioPort = [int]$numDirectWebRtcBridgeAudioPort.Value
            DirectWebRtcBridgeJitterMs = [int]$numDirectWebRtcBridgeJitterMs.Value
            DirectWebRtcPublisherQueueMs = [int]$numDirectWebRtcPublisherQueueMs.Value
            DirectWebRtcAudioBridgePacing = [bool]$chkDirectWebRtcAudioBridgePacing.Checked
            DirectWebRtcControlDataChannel = [bool]$chkDirectWebRtcControlDataChannel.Checked
            DirectWebRtcBundlePolicy = [string]$cmbDirectWebRtcBundlePolicy.SelectedItem
            DirectWebRtcInternalRtpMtu = [int]$numDirectWebRtcInternalRtpMtu.Value
            DirectWebRtcInternalRepeatHeaders = [bool]$chkDirectWebRtcInternalRepeatHeaders.Checked
            DirectWebRtcStunServer = $txtDirectWebRtcStun.Text
            DirectWebRtcTurnEnabled = [bool]$chkDirectWebRtcTurnEnabled.Checked
            DirectWebRtcTurnServer = $txtDirectWebRtcTurn.Text
            DirectWebRtcWebPath = $txtDirectWebRtcWebPath.Text
            DirectWebRtcBundledWebMode = [string]$cmbDirectWebRtcBundledWebMode.SelectedItem
            DirectWebRtcBundledWebDirectory = $txtDirectWebRtcBundledWebDirectory.Text
            DirectWebRtcWorkingWebMode = [string]$cmbDirectWebRtcWorkingWebMode.SelectedItem
            DirectWebRtcWorkingWebDirectory = $txtDirectWebRtcWebDirectory.Text
            DirectWebRtcWebDirectory = $txtDirectWebRtcWebDirectory.Text
            DirectWebRtcCongestion = [string]$cmbDirectWebRtcCongestion.SelectedItem
            DirectWebRtcStartBitrateKbps = [int]$numDirectWebRtcStartBitrateKbps.Value
            DirectWebRtcMitigation = [string]$cmbDirectWebRtcMitigation.SelectedItem
            WebRtcRecoveryMode = [string]$cmbWebRtcRecoveryMode.SelectedItem
            WebRtcSenderQueueMode = [string]$cmbWebRtcSenderQueueMode.SelectedItem
            DirectWebRtcFec = $chkDirectWebRtcFec.Checked
            DirectWebRtcRetransmission = $chkDirectWebRtcRetransmission.Checked
            DirectWebRtcSmoothnessProfile = [string]$cmbDirectWebRtcSmoothnessProfile.SelectedItem
            DirectWebRtcPacingMs = [int]$numDirectWebRtcPacingMs.Value
            WebRtcSenderQueueCapMs = [int]$numDirectWebRtcPacingMs.Value
            DirectWebRtcPlayerJitterMs = [int]$numDirectWebRtcPlayerJitterMs.Value
            DirectWebRtcAudioJitterMs = [int]$numDirectWebRtcPlayerJitterMs.Value
            DirectWebRtcVideoJitterMs = [int]$numDirectWebRtcVideoJitterMs.Value
            DirectWebRtcOpusMode = [string]$cmbDirectWebRtcOpusMode.SelectedItem
            DirectWebRtcOpusFrameMs = [string]$cmbDirectWebRtcOpusFrameMs.SelectedItem
            DirectWebRtcOpusAudioType = [string]$cmbDirectWebRtcOpusAudioType.SelectedItem
            DirectWebRtcOpusFec = [bool]$chkDirectWebRtcOpusFec.Checked
            DirectWebRtcOpusDtx = [bool]$chkDirectWebRtcOpusDtx.Checked
            JbufWatchdogMode = [string]$cmbJbufWatchdogMode.SelectedItem
            JbufMaxMs = [int]$numJbufMaxMs.Value
            PlayerStatsOverlay = [bool]$chkPlayerStatsOverlay.Checked
            PlayerJbufDebug = [bool]$chkPlayerJbufDebug.Checked
            LiveEdgeGreenMs = [int]$numLiveEdgeGreenMs.Value
            LiveEdgeYellowMs = [int]$numLiveEdgeYellowMs.Value
            LiveEdgeAverageSec = [int]$numLiveEdgeAverageSec.Value
            PlayerUrlOverrides = [bool]$chkPlayerUrlOverrides.Checked
            PlayerSeparateHtmlMediaElements = [bool]$chkPlayerSeparateHtmlMediaElements.Checked
            SeparateHtmlMediaElements = [bool]$chkPlayerSeparateHtmlMediaElements.Checked
            PlayerAvRenderMode = if ($chkPlayerSeparateHtmlMediaElements.Checked) { 'Decoupled video/audio elements' } else { 'Synced single media element' }
            DirectWebRtcAvPipelineMode = [string](Get-DirectWebRtcAvPipelineMode)
            SplitPlayerSyncMode = [string](Get-ComboSelectedOrDefault $cmbSplitPlayerSyncMode $script:DefaultSplitPlayerSyncMode)
            SplitAudioStallSeconds = [int]$numSplitAudioStallSeconds.Value
            SplitAudioWarmupSeconds = [int]$numSplitAudioWarmupSeconds.Value
            JbufWatchdogWarmupSeconds = [int]$numSplitAudioWarmupSeconds.Value
            WatchdogWarmupSeconds = [int]$numSplitAudioWarmupSeconds.Value
            SplitAvOffsetBaselineMs = [int]$numSplitAvOffsetBaselineMs.Value
            SplitAvOffsetWarnMs = [int]$numSplitAvOffsetWarnMs.Value
            VideoPipelineClockMode = [string]$cmbVideoPipelineClockMode.SelectedItem
            VideoTimestampMode = [string]$cmbVideoTimestampMode.SelectedItem
            SplitAudioPipelineClockMode = [string]$cmbSplitAudioPipelineClockMode.SelectedItem
            VideoSyncMode = [string]$cmbVideoSyncMode.SelectedItem
            AudioSyncMode = [string]$cmbAudioSyncMode.SelectedItem
            ThreadingProfile = [string]$cmbThreadingProfile.SelectedItem
            GstProcessPriority = [string]$cmbGstProcessPriority.SelectedItem
            ThreadBudget = [string]$cmbThreadBudget.SelectedItem
            CpuWorkerLimit = [int]$numCpuWorkerLimit.Value
            BudgetCaptureQueue = $chkBudgetCaptureQueue.Checked
            BudgetSenderQueue = $chkBudgetSenderQueue.Checked
            BudgetAudioInputQueue = $chkBudgetAudioInputQueue.Checked
            BudgetAudioFinalQueue = $chkBudgetAudioFinalQueue.Checked
            BudgetSceneInputQueues = $chkBudgetSceneInputQueues.Checked
            QueueLeakMode = [string]$cmbQueueLeakMode.SelectedItem
            CaptureQueueBuffers = [int]$numCaptureQueueBuffers.Value
            AudioQueueBuffers = [int]$numAudioQueueBuffers.Value
            AudioQueueCapMs = [int]$numAudioQueueCapMs.Value
            BufferLatenessTracer = $chkBufferLatenessTracer.Checked
            GstDebugMode     = [string]$cmbGstDebugMode.SelectedItem
            GstDebugSpec     = $txtGstDebugSpec.Text
            GstDebugNoColor  = $chkGstDebugNoColor.Checked
            SrtLatency        = [int]$numSrtLatency.Value
            RtspTransport     = [string]$cmbRtspTransport.SelectedItem
            MonitorIndex      = [int]$numMonitor.Value
            ShowCursor        = $chkCursor.Checked
            CaptureMethod     = Get-SelectedCaptureMethodName
            SceneEnabled      = $chkSceneEnabled.Checked
            ScenePreset       = [string]$cmbScenePreset.SelectedItem
            SceneCompositor   = [string]$cmbSceneCompositor.SelectedItem
            SceneInputQueueBuffers = [int]$numSceneInputQueueBuffers.Value
            SceneInputQueueCapMs = [int]$numSceneInputQueueCapMs.Value
            WebcamDevice      = [string]$cmbWebcamDevice.SelectedItem
            WebcamLayout      = [string]$cmbWebcamLayout.SelectedItem
            WebcamWidth       = [int]$numWebcamWidth.Value
            WebcamHeight      = [int]$numWebcamHeight.Value
            WebcamX           = [int]$numWebcamX.Value
            WebcamY           = [int]$numWebcamY.Value
            WebcamFps         = [int]$numWebcamFps.Value
            WebcamOpacity     = [int]$numWebcamOpacity.Value
            WebcamBorder      = [int]$numWebcamBorder.Value
            WebcamMirror      = $chkWebcamMirror.Checked
            WebcamAspectLock  = $chkWebcamAspectLock.Checked
            FullscreenApp     = Test-FullscreenCaptureMode
            SendAbsoluteTimestamps = (Test-SendAbsoluteTimestampsEnabled)
            TimingMode             = [string]$cmbTimingMode.SelectedItem
            RecordingEnabled  = $chkRecordingEnabled.Checked
            RecordWithStream  = $chkRecordWithStream.Checked
            RecordingDirectory = $txtRecordingDirectory.Text
            RecordingTemplate = $txtRecordingTemplate.Text
            RecordingEncoder  = [string]$cmbRecordingEncoder.SelectedItem
            RecordingPreset   = [string]$cmbRecordingPreset.SelectedItem
            RecordingProfile  = [string]$cmbRecordingProfile.SelectedItem
            RecordingWidth    = [int]$numRecordingWidth.Value
            RecordingHeight   = [int]$numRecordingHeight.Value
            RecordingFps      = [int]$numRecordingFps.Value
            RecordingVideoBitrateKbps = [int]$numRecordingVideoBitrate.Value
            RecordingRateControl = [string]$cmbRecordingRateControl.SelectedItem
            RecordingMaxVideoBitrateKbps = [int]$numRecordingMaxVideoBitrate.Value
            RecordingConstantQp = [int]$numRecordingConstantQp.Value
            RecordingGopSeconds = [int]$numRecordingGopSeconds.Value
            RecordingBFrames  = [int]$numRecordingBFrames.Value
            RecordingTune     = [string]$cmbRecordingTune.SelectedItem
            RecordingMultipass = [string]$cmbRecordingMultipass.SelectedItem
            RecordingLookAhead = $chkRecordingLookAhead.Checked
            RecordingLookAheadFrames = [int]$numRecordingLookAheadFrames.Value
            RecordingSpatialAq = $chkRecordingSpatialAq.Checked
            RecordingTemporalAq = $chkRecordingTemporalAq.Checked
            RecordingAqStrength = [int]$numRecordingAqStrength.Value
            RecordingVbvBufferKbits = [int]$numRecordingVbvBuffer.Value
            RecordingCustomEncoderOptions = $txtRecordingCustomEncoderOptions.Text
            RecordingDesktopAudio = $chkRecordingDesktopAudio.Checked
            RecordingMicrophone = $chkRecordingMic.Checked
            RecordingAudioBitrateKbps = [int]$numRecordingAudioBitrate.Value
            Preview           = $chkPreview.Checked
            HidePreviewDuringStream = $chkHidePreviewDuringStream.Checked
            DynamicScenePreviews = $chkDynamicScenePreviews.Checked
            LiveSceneEditing   = $chkLiveSceneEditing.Checked
            StandardPreviewOffSceneTab = $chkStandardPreviewOffSceneTab.Checked
            AutoRestart       = $chkAutoRestart.Checked
            Verbose           = $chkVerbose.Checked
            DiskProcessLogging = $chkDiskProcessLogging.Checked
            MinimizeToTray    = [bool]($chkMinimizeToTray.Checked -or $chkStartMinimized.Checked)
            StartMinimized    = $chkStartMinimized.Checked
            NetworkTuningEnabled = $chkNetworkTuningEnabled.Checked
            NetworkAdapter    = Get-SelectedNetworkAdapterName
            NetworkProfile    = [string]$cmbNetworkProfile.SelectedItem
            NetworkDscpEnabled = $chkNetworkDscp.Checked
            NetworkDscpValue  = [int]$numNetworkDscp.Value
            NetworkQosProtocol = [string]$cmbNetworkQosProtocol.SelectedItem
            NetworkQosPorts   = $txtNetworkPorts.Text
            NetworkUso        = [string]$cmbNetworkUso.SelectedItem
            NetworkUro        = [string]$cmbNetworkUro.SelectedItem
            NetworkDisablePowerSaving = $chkNetworkDisablePowerSaving.Checked
            NetworkInterruptModeration = [string]$cmbNetworkInterruptModeration.SelectedItem
            NetworkDisableEee = $chkNetworkDisableEee.Checked
            NetworkRestoreOnStop = $chkNetworkRestoreOnStop.Checked
            NetworkRestoreOnExit = $chkNetworkRestoreOnExit.Checked
            NetworkRecoveryTask = $chkNetworkRecoveryTask.Checked
            Width             = [int]$numWidth.Value
            Height            = [int]$numHeight.Value
            Fps               = [int]$numFps.Value
            VideoBitrateKbps  = [int]$numVideoBitrate.Value
            RateControl       = [string]$cmbRateControl.SelectedItem
            MaxVideoBitrateKbps = [int]$numMaxVideoBitrate.Value
            ConstantQp        = [int]$numConstantQp.Value
            GopSeconds        = [int]$numGopSeconds.Value
            UnifiedBridgeKeyframeGuard = [bool]$chkUnifiedBridgeKeyframeGuard.Checked
            UnifiedBridgeKeyframeIntervalMs = [int]$numUnifiedBridgeKeyframeIntervalMs.Value
            Encoder           = [string]$cmbEncoder.SelectedItem
            Preset            = [string]$cmbPreset.SelectedItem
            Profile           = [string]$cmbProfile.SelectedItem
            EncoderTune       = [string]$cmbEncoderTune.SelectedItem
            Multipass         = [string]$cmbMultipass.SelectedItem
            VbvBufferKbits    = [int]$numVbvBuffer.Value
            BFrames           = [int]$numBFrames.Value
            LookAhead         = $chkLookAhead.Checked
            LookAheadFrames   = [int]$numLookAheadFrames.Value
            AdaptiveQuantization = $chkAdaptiveQuantization.Checked
            SpatialAq         = $chkAdaptiveQuantization.Checked
            TemporalAq        = $chkTemporalAq.Checked
            AqStrength        = [int]$numAqStrength.Value
            CustomEncoderOptions = $txtCustomEncoderOptions.Text
            WhipAudioCodec    = [string]$script:ProtocolAudioCodecs.WHIP
            GstWebRtcAudioCodec = [string]$script:ProtocolAudioCodecs[$script:DirectWebRtcProtocolName]
            SrtAudioCodec     = [string]$script:ProtocolAudioCodecs.SRT
            RtmpAudioCodec    = [string]$script:ProtocolAudioCodecs.RTMP
            RtspAudioCodec    = [string]$script:ProtocolAudioCodecs.RTSP
            AudioTransportMode = [string]$cmbAudioTransportMode.SelectedItem
            AudioClockMode = [string]$cmbAudioClockMode.SelectedItem
            AudioTimingMode = [string]$cmbAudioTimingMode.SelectedItem
            AudioSlaveMethod = [string]$cmbAudioSlaveMethod.SelectedItem
            WasapiLowLatencyOverride = [bool]$chkWasapiLowLatencyOverride.Checked
            AudioBufferOverride = [bool]$chkAudioBufferOverride.Checked
            AudioBufferMs = [int]$numAudioBufferMs.Value
            AudioLatencyOverride = [bool]$chkAudioLatencyOverride.Checked
            AudioLatencyMs = [int]$numAudioLatencyMs.Value
            AudioSampleRateOverride = [bool]$chkAudioSampleRateOverride.Checked
            AudioSampleRateHz = [int]$numAudioSampleRate.Value
            DesktopAudio      = $chkDesktopAudio.Checked
            AudioMixerMode    = $chkAudioMixerMode.Checked
            DesktopVolume     = [int]$numDesktopVolume.Value
            DesktopAudioDevice = if ($cmbDesktopAudioDevice.SelectedItem) { [string]$cmbDesktopAudioDevice.SelectedItem } else { $script:DefaultAudioOutputDeviceLabel }
            DesktopAudioDeviceId = Get-SelectedAudioDeviceId -Kind Output
            Microphone        = $chkMic.Checked
            MicrophoneVolume  = [int]$numMicVolume.Value
            MicrophoneDevice  = if ($cmbMicAudioDevice.SelectedItem) { [string]$cmbMicAudioDevice.SelectedItem } else { $script:DefaultAudioInputDeviceLabel }
            MicrophoneDeviceId = Get-SelectedAudioDeviceId -Kind Input
            AudioBitrateKbps  = [int]$numAudioBitrate.Value
        }

        $settings | ConvertTo-Json | Set-Content -LiteralPath $script:ConfigPath -Encoding UTF8
    }
    catch {
        Append-Log "Could not save settings: $($_.Exception.Message)"
    }
}

function Export-LabConfiguration {
    try {
        # Save first so the export is based on the exact current UI state.
        Save-Settings
        Update-CommandPreview

        if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
            throw "The live settings file was not created: $script:ConfigPath"
        }

        $savedSettings =
            Get-Content -LiteralPath $script:ConfigPath -Raw |
            ConvertFrom-Json

        # Keep the settings flat so this file can later be imported directly or
        # used as settings.json. Metadata keys are prefixed and ignored by older
        # builds that do not know about them.
        $export = [ordered]@{
            _Schema           = 'GStreamerGlassLabConfig'
            _SchemaVersion    = 1
            _AppVersion       = $script:AppVersion
            _ExportedUtc      = [DateTime]::UtcNow.ToString('o')
            _GeneratedCommand = [string]$txtCommand.Text
        }

        foreach ($property in $savedSettings.PSObject.Properties) {
            $export[$property.Name] = $property.Value
        }

        $dialog = New-Object System.Windows.Forms.SaveFileDialog
        try {
            $dialog.Title = 'Export GStreamer Glass lab configuration'
            $dialog.Filter = 'GStreamer Glass lab config (*.gstglass.json)|*.gstglass.json|JSON files (*.json)|*.json|All files (*.*)|*.*'
            $dialog.DefaultExt = 'gstglass.json'
            $dialog.AddExtension = $true
            $dialog.OverwritePrompt = $true
            $dialog.RestoreDirectory = $true
            $dialog.FileName = 'GStreamer-Glass-' + $script:AppVersion + '-LabConfig-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.gstglass.json'

            if ($dialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) {
                return
            }

            $export |
                ConvertTo-Json -Depth 12 |
                Set-Content -LiteralPath $dialog.FileName -Encoding UTF8

            Append-Log "Lab configuration exported: $($dialog.FileName)"
            $statusLabel.Text = 'Lab config exported'
            $statusLabel.ForeColor = [System.Drawing.Color]::DarkGreen

            [System.Windows.Forms.MessageBox]::Show(
                "Exported the complete UI configuration and exact generated command.`r`n`r`n$($dialog.FileName)",
                $script:AppName,
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
        finally {
            $dialog.Dispose()
        }
    }
    catch {
        Append-Log "Could not export lab configuration: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            "Could not export the lab configuration.`r`n`r`n$($_.Exception.Message)",
            $script:AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

function Load-Settings {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
        return
    }

    $script:LoadingSettings = $true
    try {
        $settings = Get-Content -LiteralPath $script:ConfigPath -Raw | ConvertFrom-Json
        $script:SuppressProtocolChange = $true

        if ($settings.GstPath) {
            $loadedGstPath = [string]$settings.GstPath
            if (Test-GstLaunchPath $loadedGstPath) {
                $txtGstPath.Text = Normalize-GstLaunchPath $loadedGstPath
            }
            else {
                $txtGstPath.Text = Find-GstLaunch
                Append-Log "Saved GStreamer executable was not found: $loadedGstPath"
                Append-Log "Using detected GStreamer executable: $($txtGstPath.Text)"
            }
        }
        if ($settings.MediaMtxPath) {
            $txtMediaMtxPath.Text = [string]$settings.MediaMtxPath
        }
        if ($null -ne $settings.CustomGstArguments) {
            $txtCustomGstArguments.Text = [string]$settings.CustomGstArguments
        }
        if ($null -ne $settings.CustomGstArgumentsEnabled) {
            $chkCustomGstArgumentsEnabled.Checked = [bool]$settings.CustomGstArgumentsEnabled
        }
        if ($null -ne $settings.StartMediaMtx) {
            $chkStartMediaMtx.Checked = [bool]$settings.StartMediaMtx
        }
        if ($null -ne $settings.TransportEnabled) {
            $chkTransportEnabled.Checked = [bool]$settings.TransportEnabled
        }
        if ($settings.WhipUrl) { $script:ProtocolDestinations.WHIP = [string]$settings.WhipUrl }
        if ($settings.SrtUrl) { $script:ProtocolDestinations.SRT = [string]$settings.SrtUrl }
        if ($settings.RtmpUrl) { $script:ProtocolDestinations.RTMP = [string]$settings.RtmpUrl }
        if ($settings.RtspUrl) { $script:ProtocolDestinations.RTSP = [string]$settings.RtspUrl }
        if ($settings.GstWebRtcUrl) { $script:ProtocolDestinations[$script:DirectWebRtcProtocolName] = [string]$settings.GstWebRtcUrl }
        if ($settings.DirectWebRtcSignalingHost) { $txtDirectWebRtcSignalingHost.Text = [string]$settings.DirectWebRtcSignalingHost }
        if ($null -ne $settings.DirectWebRtcSignalingPort) {
            $loadedDirectWebRtcSignalPort = [int]$settings.DirectWebRtcSignalingPort
            if ($loadedDirectWebRtcSignalPort -eq 8443) {
                # v3.7.21 used 8443. The user's proxy layout expects the WebSocket
                # signalling listener on 8189, so migrate the stale saved value.
                $loadedDirectWebRtcSignalPort = $script:DefaultDirectWebRtcSignalingPort
                Append-Log 'Migrated legacy Direct WebRTC signalling port 8443 to 8189.'
            }
            $numDirectWebRtcSignalingPort.Value = [decimal]$loadedDirectWebRtcSignalPort
        }
        if ($null -ne $settings.DirectWebRtcSplitAudioSignalingPort) {
            $loadedAudioSignalPort = [int]$settings.DirectWebRtcSplitAudioSignalingPort
            $numDirectWebRtcSplitAudioSignalingPort.Value = [decimal]([Math]::Min(65535, [Math]::Max(1, $loadedAudioSignalPort)))
        }
        elseif ($null -ne $settings.DirectWebRtcSignalingPort) {
            $legacyAudioPort = [Math]::Min(65535, ([int]$numDirectWebRtcSignalingPort.Value + [int]$script:DefaultDirectWebRtcSplitAudioPortOffset))
            $numDirectWebRtcSplitAudioSignalingPort.Value = [decimal]$legacyAudioPort
        }
        if ($null -ne $settings.DirectWebRtcSharedSignaling) { $chkDirectWebRtcSharedSignaling.Checked = [bool]$settings.DirectWebRtcSharedSignaling }
        if ($settings.DirectWebRtcMediaStreamGrouping -and $cmbDirectWebRtcMediaStreamGrouping.Items.Contains([string]$settings.DirectWebRtcMediaStreamGrouping)) { $cmbDirectWebRtcMediaStreamGrouping.SelectedItem = [string]$settings.DirectWebRtcMediaStreamGrouping }
        if ($null -ne $settings.DirectWebRtcVideoMediaStreamId) { $txtDirectWebRtcVideoMediaStreamId.Text = [string]$settings.DirectWebRtcVideoMediaStreamId }
        if ($null -ne $settings.DirectWebRtcAudioMediaStreamId) { $txtDirectWebRtcAudioMediaStreamId.Text = [string]$settings.DirectWebRtcAudioMediaStreamId }
        if ($null -ne $settings.DirectWebRtcUnifiedPublisher) { $chkDirectWebRtcUnifiedPublisher.Checked = [bool]$settings.DirectWebRtcUnifiedPublisher }
        if ($null -ne $settings.DirectWebRtcBridgeVideoPort) { $numDirectWebRtcBridgeVideoPort.Value = [decimal]([Math]::Min(65535, [Math]::Max(1, [int]$settings.DirectWebRtcBridgeVideoPort))) }
        if ($null -ne $settings.DirectWebRtcBridgeAudioPort) { $numDirectWebRtcBridgeAudioPort.Value = [decimal]([Math]::Min(65535, [Math]::Max(1, [int]$settings.DirectWebRtcBridgeAudioPort))) }
        if ($null -ne $settings.DirectWebRtcBridgeJitterMs) { $numDirectWebRtcBridgeJitterMs.Value = [decimal]([Math]::Min(2000, [Math]::Max(0, [int]$settings.DirectWebRtcBridgeJitterMs))) }
        if ($null -ne $settings.DirectWebRtcPublisherQueueMs) { $numDirectWebRtcPublisherQueueMs.Value = [decimal]([Math]::Min(2000, [Math]::Max(0, [int]$settings.DirectWebRtcPublisherQueueMs))) }
        if ($null -ne $settings.DirectWebRtcAudioBridgePacing) { $chkDirectWebRtcAudioBridgePacing.Checked = [bool]$settings.DirectWebRtcAudioBridgePacing }
        if ($null -ne $settings.SplitClockSignalingOverrides) { $chkSplitClockSignalingOverrides.Checked = [bool]$settings.SplitClockSignalingOverrides }
        if ($settings.SplitVideoClockSignaling -and $cmbSplitVideoClockSignaling.Items.Contains([string]$settings.SplitVideoClockSignaling)) { $cmbSplitVideoClockSignaling.SelectedItem = [string]$settings.SplitVideoClockSignaling }
        if ($settings.SplitAudioClockSignaling -and $cmbSplitAudioClockSignaling.Items.Contains([string]$settings.SplitAudioClockSignaling)) { $cmbSplitAudioClockSignaling.SelectedItem = [string]$settings.SplitAudioClockSignaling }
        if ($null -ne $settings.DirectWebRtcControlDataChannel) { $chkDirectWebRtcControlDataChannel.Checked = [bool]$settings.DirectWebRtcControlDataChannel }
        if ($settings.DirectWebRtcBundlePolicy -and $cmbDirectWebRtcBundlePolicy.Items.Contains([string]$settings.DirectWebRtcBundlePolicy)) { $cmbDirectWebRtcBundlePolicy.SelectedItem = [string]$settings.DirectWebRtcBundlePolicy }
        if ($null -ne $settings.DirectWebRtcInternalRtpMtu) { $numDirectWebRtcInternalRtpMtu.Value = [decimal]([Math]::Min(65535, [Math]::Max(0, [int]$settings.DirectWebRtcInternalRtpMtu))) }
        if ($null -ne $settings.DirectWebRtcInternalRepeatHeaders) { $chkDirectWebRtcInternalRepeatHeaders.Checked = [bool]$settings.DirectWebRtcInternalRepeatHeaders }
        if ($null -ne $settings.DirectWebRtcStunServer) { $txtDirectWebRtcStun.Text = [string]$settings.DirectWebRtcStunServer }
        if ($null -ne $settings.DirectWebRtcTurnEnabled) { $chkDirectWebRtcTurnEnabled.Checked = [bool]$settings.DirectWebRtcTurnEnabled }
        if ($null -ne $settings.DirectWebRtcTurnServer) { $txtDirectWebRtcTurn.Text = [string]$settings.DirectWebRtcTurnServer }
        if ($null -ne $settings.DirectWebRtcWebPath) { $txtDirectWebRtcWebPath.Text = [string]$settings.DirectWebRtcWebPath }
        if ($settings.DirectWebRtcBundledWebMode -and $cmbDirectWebRtcBundledWebMode.Items.Contains([string]$settings.DirectWebRtcBundledWebMode)) { $cmbDirectWebRtcBundledWebMode.SelectedItem = [string]$settings.DirectWebRtcBundledWebMode }
        if ($null -ne $settings.DirectWebRtcBundledWebDirectory) { $txtDirectWebRtcBundledWebDirectory.Text = [string]$settings.DirectWebRtcBundledWebDirectory }
        if ($settings.DirectWebRtcWorkingWebMode -and $cmbDirectWebRtcWorkingWebMode.Items.Contains([string]$settings.DirectWebRtcWorkingWebMode)) { $cmbDirectWebRtcWorkingWebMode.SelectedItem = [string]$settings.DirectWebRtcWorkingWebMode }
        if ($null -ne $settings.DirectWebRtcWorkingWebDirectory) { $txtDirectWebRtcWebDirectory.Text = [string]$settings.DirectWebRtcWorkingWebDirectory }
        elseif ($null -ne $settings.DirectWebRtcWebDirectory) { $txtDirectWebRtcWebDirectory.Text = [string]$settings.DirectWebRtcWebDirectory }
        if ($settings.DirectWebRtcCongestion -and $cmbDirectWebRtcCongestion.Items.Contains([string]$settings.DirectWebRtcCongestion)) { $cmbDirectWebRtcCongestion.SelectedItem = [string]$settings.DirectWebRtcCongestion }
        if ($null -ne $settings.DirectWebRtcStartBitrateKbps) { $numDirectWebRtcStartBitrateKbps.Value = [decimal]([Math]::Min([int]$numDirectWebRtcStartBitrateKbps.Maximum, [Math]::Max([int]$numDirectWebRtcStartBitrateKbps.Minimum, [int]$settings.DirectWebRtcStartBitrateKbps))) }
        if ($settings.DirectWebRtcMitigation -and $cmbDirectWebRtcMitigation.Items.Contains([string]$settings.DirectWebRtcMitigation)) { $cmbDirectWebRtcMitigation.SelectedItem = [string]$settings.DirectWebRtcMitigation }
        if ($settings.WebRtcRecoveryMode -and $cmbWebRtcRecoveryMode.Items.Contains([string]$settings.WebRtcRecoveryMode)) {
            Set-WebRtcRecoveryMode ([string]$settings.WebRtcRecoveryMode)
        }
        elseif ($null -ne $settings.DirectWebRtcFec -or $null -ne $settings.DirectWebRtcRetransmission) {
            $legacyFec = if ($null -ne $settings.DirectWebRtcFec) { [bool]$settings.DirectWebRtcFec } else { $false }
            $legacyRtx = if ($null -ne $settings.DirectWebRtcRetransmission) { [bool]$settings.DirectWebRtcRetransmission } else { $true }
            if ($legacyFec -and $legacyRtx) { Set-WebRtcRecoveryMode 'FEC + RTX' }
            elseif ($legacyFec) { Set-WebRtcRecoveryMode 'FEC only' }
            elseif ($legacyRtx) { Set-WebRtcRecoveryMode 'RTX only' }
            else { Set-WebRtcRecoveryMode 'None' }
        }
        if ($settings.WebRtcSenderQueueMode -and $cmbWebRtcSenderQueueMode.Items.Contains([string]$settings.WebRtcSenderQueueMode)) { $cmbWebRtcSenderQueueMode.SelectedItem = [string]$settings.WebRtcSenderQueueMode }
        if ($settings.DirectWebRtcSmoothnessProfile -and $cmbDirectWebRtcSmoothnessProfile.Items.Contains([string]$settings.DirectWebRtcSmoothnessProfile)) { $cmbDirectWebRtcSmoothnessProfile.SelectedItem = [string]$settings.DirectWebRtcSmoothnessProfile }
        if ($null -ne $settings.DirectWebRtcPacingMs) { $numDirectWebRtcPacingMs.Value = [decimal]([Math]::Min([int]$numDirectWebRtcPacingMs.Maximum, [Math]::Max([int]$numDirectWebRtcPacingMs.Minimum, [int]$settings.DirectWebRtcPacingMs))) }
        if ($null -ne $settings.DirectWebRtcAudioJitterMs) { $numDirectWebRtcPlayerJitterMs.Value = [decimal]([Math]::Min([int]$numDirectWebRtcPlayerJitterMs.Maximum, [Math]::Max([int]$numDirectWebRtcPlayerJitterMs.Minimum, [int]$settings.DirectWebRtcAudioJitterMs))) }
        elseif ($null -ne $settings.DirectWebRtcPlayerJitterMs) { $numDirectWebRtcPlayerJitterMs.Value = [decimal]([Math]::Min([int]$numDirectWebRtcPlayerJitterMs.Maximum, [Math]::Max([int]$numDirectWebRtcPlayerJitterMs.Minimum, [int]$settings.DirectWebRtcPlayerJitterMs))) }
        if ($null -ne $settings.DirectWebRtcVideoJitterMs) { $numDirectWebRtcVideoJitterMs.Value = [decimal]([Math]::Min([int]$numDirectWebRtcVideoJitterMs.Maximum, [Math]::Max([int]$numDirectWebRtcVideoJitterMs.Minimum, [int]$settings.DirectWebRtcVideoJitterMs))) }
        if ($settings.DirectWebRtcOpusMode -and $cmbDirectWebRtcOpusMode.Items.Contains([string]$settings.DirectWebRtcOpusMode)) { $cmbDirectWebRtcOpusMode.SelectedItem = [string]$settings.DirectWebRtcOpusMode }
        if ($settings.DirectWebRtcOpusFrameMs -and $cmbDirectWebRtcOpusFrameMs.Items.Contains([string]$settings.DirectWebRtcOpusFrameMs)) { $cmbDirectWebRtcOpusFrameMs.SelectedItem = [string]$settings.DirectWebRtcOpusFrameMs }
        if ($settings.DirectWebRtcOpusAudioType -and $cmbDirectWebRtcOpusAudioType.Items.Contains([string]$settings.DirectWebRtcOpusAudioType)) { $cmbDirectWebRtcOpusAudioType.SelectedItem = [string]$settings.DirectWebRtcOpusAudioType }
        if ($null -ne $settings.DirectWebRtcOpusFec) { $chkDirectWebRtcOpusFec.Checked = [bool]$settings.DirectWebRtcOpusFec }
        if ($null -ne $settings.DirectWebRtcOpusDtx) { $chkDirectWebRtcOpusDtx.Checked = [bool]$settings.DirectWebRtcOpusDtx }
        if ($settings.JbufWatchdogMode -and $cmbJbufWatchdogMode.Items.Contains([string]$settings.JbufWatchdogMode)) { $cmbJbufWatchdogMode.SelectedItem = [string]$settings.JbufWatchdogMode }
        if ($null -ne $settings.JbufMaxMs) { $numJbufMaxMs.Value = [decimal]([Math]::Min([int]$numJbufMaxMs.Maximum, [Math]::Max([int]$numJbufMaxMs.Minimum, [int]$settings.JbufMaxMs))) }
        if ($null -ne $settings.PlayerStatsOverlay) { $chkPlayerStatsOverlay.Checked = [bool]$settings.PlayerStatsOverlay }
        if ($null -ne $settings.PlayerJbufDebug) { $chkPlayerJbufDebug.Checked = [bool]$settings.PlayerJbufDebug }
        if ($null -ne $settings.LiveEdgeGreenMs) { $numLiveEdgeGreenMs.Value = [decimal]([Math]::Min([int]$numLiveEdgeGreenMs.Maximum, [Math]::Max([int]$numLiveEdgeGreenMs.Minimum, [int]$settings.LiveEdgeGreenMs))) }
        if ($null -ne $settings.LiveEdgeYellowMs) { $numLiveEdgeYellowMs.Value = [decimal]([Math]::Min([int]$numLiveEdgeYellowMs.Maximum, [Math]::Max([int]$numLiveEdgeYellowMs.Minimum, [int]$settings.LiveEdgeYellowMs))) }
        if ($null -ne $settings.LiveEdgeAverageSec) { $numLiveEdgeAverageSec.Value = [decimal]([Math]::Min([int]$numLiveEdgeAverageSec.Maximum, [Math]::Max([int]$numLiveEdgeAverageSec.Minimum, [int]$settings.LiveEdgeAverageSec))) }
        if ($numLiveEdgeYellowMs.Value -le $numLiveEdgeGreenMs.Value) { $numLiveEdgeYellowMs.Value = [decimal]([Math]::Min([int]$numLiveEdgeYellowMs.Maximum, [int]$numLiveEdgeGreenMs.Value + 1)) }
        if ($null -ne $settings.PlayerUrlOverrides) { $chkPlayerUrlOverrides.Checked = [bool]$settings.PlayerUrlOverrides }
        if ($null -ne $settings.PlayerSeparateHtmlMediaElements) {
            $chkPlayerSeparateHtmlMediaElements.Checked = [bool]$settings.PlayerSeparateHtmlMediaElements
        }
        elseif ($null -ne $settings.SeparateHtmlMediaElements) {
            $chkPlayerSeparateHtmlMediaElements.Checked = [bool]$settings.SeparateHtmlMediaElements
        }
        elseif ($settings.DirectWebRtcMediaStreamGrouping -and ([string]$settings.DirectWebRtcMediaStreamGrouping -like 'Separate audio/video MediaStreams*')) {
            # f40-f42 forced separate HTML elements whenever MSIDs were split. Preserve
            # that effective behavior once while migrating to the explicit Player toggle.
            $chkPlayerSeparateHtmlMediaElements.Checked = $true
        }
        elseif ($settings.PlayerAvRenderMode) {
            $chkPlayerSeparateHtmlMediaElements.Checked = ([string]$settings.PlayerAvRenderMode -like 'Decoupled*')
        }
        if ($settings.DirectWebRtcAvPipelineMode -and $cmbDirectWebRtcAvPipelineMode.Items.Contains([string]$settings.DirectWebRtcAvPipelineMode)) { $cmbDirectWebRtcAvPipelineMode.SelectedItem = [string]$settings.DirectWebRtcAvPipelineMode }
        if ($settings.SplitPlayerSyncMode -and $cmbSplitPlayerSyncMode.Items.Contains([string]$settings.SplitPlayerSyncMode)) { $cmbSplitPlayerSyncMode.SelectedItem = [string]$settings.SplitPlayerSyncMode }
        if ($null -ne $settings.SplitAudioStallSeconds) { $numSplitAudioStallSeconds.Value = [decimal]([Math]::Min([int]$numSplitAudioStallSeconds.Maximum, [Math]::Max([int]$numSplitAudioStallSeconds.Minimum, [int]$settings.SplitAudioStallSeconds))) }
        if ($null -ne $settings.JbufWatchdogWarmupSeconds) { $numSplitAudioWarmupSeconds.Value = [decimal]([Math]::Min([int]$numSplitAudioWarmupSeconds.Maximum, [Math]::Max([int]$numSplitAudioWarmupSeconds.Minimum, [int]$settings.JbufWatchdogWarmupSeconds))) } elseif ($null -ne $settings.WatchdogWarmupSeconds) { $numSplitAudioWarmupSeconds.Value = [decimal]([Math]::Min([int]$numSplitAudioWarmupSeconds.Maximum, [Math]::Max([int]$numSplitAudioWarmupSeconds.Minimum, [int]$settings.WatchdogWarmupSeconds))) } elseif ($null -ne $settings.SplitAudioWarmupSeconds) { $numSplitAudioWarmupSeconds.Value = [decimal]([Math]::Min([int]$numSplitAudioWarmupSeconds.Maximum, [Math]::Max([int]$numSplitAudioWarmupSeconds.Minimum, [int]$settings.SplitAudioWarmupSeconds))) }
        if ($null -ne $settings.SplitAvOffsetBaselineMs) { $numSplitAvOffsetBaselineMs.Value = [decimal]([Math]::Min([int]$numSplitAvOffsetBaselineMs.Maximum, [Math]::Max([int]$numSplitAvOffsetBaselineMs.Minimum, [int]$settings.SplitAvOffsetBaselineMs))) }
        if ($null -ne $settings.SplitAvOffsetWarnMs) { $numSplitAvOffsetWarnMs.Value = [decimal]([Math]::Min([int]$numSplitAvOffsetWarnMs.Maximum, [Math]::Max([int]$numSplitAvOffsetWarnMs.Minimum, [int]$settings.SplitAvOffsetWarnMs))) }
        if ($settings.ThreadingProfile -and $cmbThreadingProfile.Items.Contains([string]$settings.ThreadingProfile)) { $cmbThreadingProfile.SelectedItem = [string]$settings.ThreadingProfile }
        if ($settings.GstProcessPriority -and $cmbGstProcessPriority.Items.Contains([string]$settings.GstProcessPriority)) { $cmbGstProcessPriority.SelectedItem = [string]$settings.GstProcessPriority }
        if ($settings.ThreadBudget -and $cmbThreadBudget.Items.Contains([string]$settings.ThreadBudget)) { $cmbThreadBudget.SelectedItem = [string]$settings.ThreadBudget }
        if ($null -ne $settings.CpuWorkerLimit) { $numCpuWorkerLimit.Value = [decimal]([Math]::Min([int]$numCpuWorkerLimit.Maximum, [Math]::Max(0, [int]$settings.CpuWorkerLimit))) }
        if ($null -ne $settings.BudgetCaptureQueue) { $chkBudgetCaptureQueue.Checked = [bool]$settings.BudgetCaptureQueue }
        if ($null -ne $settings.BudgetSenderQueue) { $chkBudgetSenderQueue.Checked = [bool]$settings.BudgetSenderQueue }
        if ($null -ne $settings.BudgetAudioInputQueue) { $chkBudgetAudioInputQueue.Checked = [bool]$settings.BudgetAudioInputQueue }
        if ($null -ne $settings.BudgetAudioFinalQueue) { $chkBudgetAudioFinalQueue.Checked = [bool]$settings.BudgetAudioFinalQueue }
        $chkBudgetSceneInputQueues.Checked = $true
        $chkBudgetSceneInputQueues.Enabled = $false
        if ($settings.QueueLeakMode -and $cmbQueueLeakMode.Items.Contains([string]$settings.QueueLeakMode)) { $cmbQueueLeakMode.SelectedItem = [string]$settings.QueueLeakMode }
        if ($null -ne $settings.CaptureQueueBuffers) { $numCaptureQueueBuffers.Value = [decimal]([Math]::Min([int]$numCaptureQueueBuffers.Maximum, [Math]::Max([int]$numCaptureQueueBuffers.Minimum, [int]$settings.CaptureQueueBuffers))) }
        if ($null -ne $settings.AudioQueueBuffers) { $numAudioQueueBuffers.Value = [decimal]([Math]::Min([int]$numAudioQueueBuffers.Maximum, [Math]::Max([int]$numAudioQueueBuffers.Minimum, [int]$settings.AudioQueueBuffers))) }
        if ($null -ne $settings.AudioQueueCapMs) { $numAudioQueueCapMs.Value = [decimal]([Math]::Min([int]$numAudioQueueCapMs.Maximum, [Math]::Max([int]$numAudioQueueCapMs.Minimum, [int]$settings.AudioQueueCapMs))) }
        if ($null -ne $settings.BufferLatenessTracer) { $chkBufferLatenessTracer.Checked = [bool]$settings.BufferLatenessTracer }
        if ($settings.GstDebugMode -and $cmbGstDebugMode.Items.Contains([string]$settings.GstDebugMode)) { $cmbGstDebugMode.SelectedItem = [string]$settings.GstDebugMode }
        if ($null -ne $settings.GstDebugSpec) { $txtGstDebugSpec.Text = [string]$settings.GstDebugSpec }
        if ($null -ne $settings.GstDebugNoColor) { $chkGstDebugNoColor.Checked = [bool]$settings.GstDebugNoColor }
        Update-GstDebugUi
        if ($null -ne $settings.SrtLatency) { $numSrtLatency.Value = [decimal]$settings.SrtLatency }
        if ($settings.RtspTransport -and $cmbRtspTransport.Items.Contains([string]$settings.RtspTransport)) { $cmbRtspTransport.SelectedItem = [string]$settings.RtspTransport }
        if ($null -ne $settings.MonitorIndex) { $numMonitor.Value = [decimal]$settings.MonitorIndex }
        if ($null -ne $settings.ShowCursor) { $chkCursor.Checked = [bool]$settings.ShowCursor }
        if ($settings.CaptureMethod -and $cmbCaptureMethod.Items.Contains([string]$settings.CaptureMethod)) {
            $cmbCaptureMethod.SelectedItem = [string]$settings.CaptureMethod
        }
        elseif ($null -ne $settings.FullscreenApp -and [bool]$settings.FullscreenApp) {
            $cmbCaptureMethod.SelectedItem = 'Fullscreen App - D3D11 / WGC'
        }
        Sync-LegacyFullscreenFlag
        Refresh-WebcamDevices
        if ($settings.ScenePreset -and $cmbScenePreset.Items.Contains([string]$settings.ScenePreset)) { $cmbScenePreset.SelectedItem = [string]$settings.ScenePreset }
        if ($settings.SceneCompositor -and $cmbSceneCompositor.Items.Contains([string]$settings.SceneCompositor)) { $cmbSceneCompositor.SelectedItem = [string]$settings.SceneCompositor }
        if ($settings.WebcamDevice -and $cmbWebcamDevice.Items.Contains([string]$settings.WebcamDevice)) { $cmbWebcamDevice.SelectedItem = [string]$settings.WebcamDevice }
        if ($settings.WebcamLayout -and $cmbWebcamLayout.Items.Contains([string]$settings.WebcamLayout)) { $cmbWebcamLayout.SelectedItem = [string]$settings.WebcamLayout }
        foreach ($sceneValue in @(
            @($settings.WebcamWidth,$numWebcamWidth), @($settings.WebcamHeight,$numWebcamHeight),
            @($settings.WebcamX,$numWebcamX), @($settings.WebcamY,$numWebcamY),
            @($settings.WebcamFps,$numWebcamFps), @($settings.WebcamOpacity,$numWebcamOpacity),
            @($settings.WebcamBorder,$numWebcamBorder),
            @($settings.SceneInputQueueBuffers,$numSceneInputQueueBuffers),
            @($settings.SceneInputQueueCapMs,$numSceneInputQueueCapMs)
        )) {
            if ($null -ne $sceneValue[0]) {
                $value = [int]$sceneValue[0]
                $sceneValue[1].Value = [decimal]([Math]::Min([int]$sceneValue[1].Maximum, [Math]::Max([int]$sceneValue[1].Minimum, $value)))
            }
        }
        if ($null -ne $settings.WebcamMirror) { $chkWebcamMirror.Checked = [bool]$settings.WebcamMirror }
        if ($null -ne $settings.WebcamAspectLock) { $chkWebcamAspectLock.Checked = [bool]$settings.WebcamAspectLock }
        Capture-WebcamAspectRatio
        if ($null -ne $settings.SceneEnabled) { $chkSceneEnabled.Checked = [bool]$settings.SceneEnabled }
        Update-SceneUi
        $loadedClockSignalingEnabled = $false
        $loadedClockSignalingKnown = $false
        if ($settings.TimingMode) {
            $loadedClockSignalingEnabled = Test-ClockSignalingValueEnabled ([string]$settings.TimingMode)
            $loadedClockSignalingKnown = $true
        }
        elseif ($settings.DirectWebRtcClockSignaling) {
            $loadedClockSignalingEnabled = Test-ClockSignalingValueEnabled ([string]$settings.DirectWebRtcClockSignaling)
            $loadedClockSignalingKnown = $true
        }
        elseif ($null -ne $settings.SendAbsoluteTimestamps) {
            $loadedClockSignalingEnabled = [bool]$settings.SendAbsoluteTimestamps
            $loadedClockSignalingKnown = $true
        }
        if ($loadedClockSignalingKnown) {
            $cmbTimingMode.SelectedItem = if ($loadedClockSignalingEnabled) { 'On / protocol clock signaling' } else { $script:DefaultTimingMode }
        }
        if ($null -ne $settings.RecordingEnabled) { $chkRecordingEnabled.Checked = [bool]$settings.RecordingEnabled }
        if ($null -ne $settings.RecordWithStream) { $chkRecordWithStream.Checked = [bool]$settings.RecordWithStream }
        if ($settings.RecordingDirectory) { $txtRecordingDirectory.Text = [string]$settings.RecordingDirectory }
        if ($settings.RecordingTemplate) { $txtRecordingTemplate.Text = [string]$settings.RecordingTemplate }
        if ($settings.RecordingEncoder -and $cmbRecordingEncoder.Items.Contains([string]$settings.RecordingEncoder)) {
            $cmbRecordingEncoder.SelectedItem = [string]$settings.RecordingEncoder
        }
        if ($settings.RecordingPreset -and $cmbRecordingPreset.Items.Contains([string]$settings.RecordingPreset)) { $cmbRecordingPreset.SelectedItem = [string]$settings.RecordingPreset }
        if ($settings.RecordingProfile -and $cmbRecordingProfile.Items.Contains([string]$settings.RecordingProfile)) { $cmbRecordingProfile.SelectedItem = [string]$settings.RecordingProfile }
        if ($settings.RecordingWidth) { $numRecordingWidth.Value = [decimal]$settings.RecordingWidth }
        if ($settings.RecordingHeight) { $numRecordingHeight.Value = [decimal]$settings.RecordingHeight }
        if ($settings.RecordingFps) { $numRecordingFps.Value = [decimal]$settings.RecordingFps }
        if ($settings.RecordingVideoBitrateKbps) { $numRecordingVideoBitrate.Value = [decimal]$settings.RecordingVideoBitrateKbps }
        if ($settings.RecordingRateControl -and $cmbRecordingRateControl.Items.Contains([string]$settings.RecordingRateControl)) { $cmbRecordingRateControl.SelectedItem = [string]$settings.RecordingRateControl }
        if ($null -ne $settings.RecordingMaxVideoBitrateKbps) { $numRecordingMaxVideoBitrate.Value = [decimal]$settings.RecordingMaxVideoBitrateKbps }
        if ($null -ne $settings.RecordingConstantQp) { $numRecordingConstantQp.Value = [decimal]$settings.RecordingConstantQp }
        if ($settings.RecordingGopSeconds) { $numRecordingGopSeconds.Value = [decimal]$settings.RecordingGopSeconds }
        if ($null -ne $settings.RecordingBFrames) { $numRecordingBFrames.Value = [decimal]$settings.RecordingBFrames }
        if ($settings.RecordingTune -and $cmbRecordingTune.Items.Contains([string]$settings.RecordingTune)) { $cmbRecordingTune.SelectedItem = [string]$settings.RecordingTune }
        if ($settings.RecordingMultipass -and $cmbRecordingMultipass.Items.Contains([string]$settings.RecordingMultipass)) { $cmbRecordingMultipass.SelectedItem = [string]$settings.RecordingMultipass }
        if ($null -ne $settings.RecordingLookAhead) { $chkRecordingLookAhead.Checked = [bool]$settings.RecordingLookAhead }
        if ($settings.RecordingLookAheadFrames) { $numRecordingLookAheadFrames.Value = [decimal]$settings.RecordingLookAheadFrames }
        if ($null -ne $settings.RecordingSpatialAq) { $chkRecordingSpatialAq.Checked = [bool]$settings.RecordingSpatialAq }
        if ($null -ne $settings.RecordingTemporalAq) { $chkRecordingTemporalAq.Checked = [bool]$settings.RecordingTemporalAq }
        if ($settings.RecordingAqStrength) { $numRecordingAqStrength.Value = [decimal]$settings.RecordingAqStrength }
        if ($null -ne $settings.RecordingVbvBufferKbits) { $numRecordingVbvBuffer.Value = [decimal]$settings.RecordingVbvBufferKbits }
        if ($null -ne $settings.RecordingCustomEncoderOptions) { $txtRecordingCustomEncoderOptions.Text = [string]$settings.RecordingCustomEncoderOptions }
        if ($null -ne $settings.RecordingDesktopAudio) { $chkRecordingDesktopAudio.Checked = [bool]$settings.RecordingDesktopAudio }
        if ($null -ne $settings.RecordingMicrophone) { $chkRecordingMic.Checked = [bool]$settings.RecordingMicrophone }
        if ($settings.RecordingAudioBitrateKbps) { $numRecordingAudioBitrate.Value = [decimal]$settings.RecordingAudioBitrateKbps }
        if ($null -ne $settings.Preview) { $chkPreview.Checked = [bool]$settings.Preview }
        if ($null -ne $settings.HidePreviewDuringStream) { $chkHidePreviewDuringStream.Checked = [bool]$settings.HidePreviewDuringStream }
        if ($null -ne $settings.DynamicScenePreviews) { $chkDynamicScenePreviews.Checked = [bool]$settings.DynamicScenePreviews }
        if ($null -ne $settings.LiveSceneEditing) { $chkLiveSceneEditing.Checked = [bool]$settings.LiveSceneEditing }
        if ($null -ne $settings.StandardPreviewOffSceneTab) { $chkStandardPreviewOffSceneTab.Checked = [bool]$settings.StandardPreviewOffSceneTab }
        if ($null -ne $settings.AutoRestart) { $chkAutoRestart.Checked = [bool]$settings.AutoRestart }
        if ($null -ne $settings.Verbose) { $chkVerbose.Checked = [bool]$settings.Verbose }
        if ($null -ne $settings.DiskProcessLogging) { $chkDiskProcessLogging.Checked = [bool]$settings.DiskProcessLogging }
        if ($null -ne $settings.MinimizeToTray) { $chkMinimizeToTray.Checked = [bool]$settings.MinimizeToTray }
        if ($null -ne $settings.StartMinimized) { $chkStartMinimized.Checked = [bool]$settings.StartMinimized }
        if ($null -ne $settings.NetworkTuningEnabled) { $chkNetworkTuningEnabled.Checked = [bool]$settings.NetworkTuningEnabled }
        if ($settings.NetworkProfile -and $cmbNetworkProfile.Items.Contains([string]$settings.NetworkProfile)) { $cmbNetworkProfile.SelectedItem = [string]$settings.NetworkProfile }
        if ($null -ne $settings.NetworkDscpEnabled) { $chkNetworkDscp.Checked = [bool]$settings.NetworkDscpEnabled }
        if ($null -ne $settings.NetworkDscpValue) { $numNetworkDscp.Value = [decimal]$settings.NetworkDscpValue }
        if ($settings.NetworkQosProtocol -and $cmbNetworkQosProtocol.Items.Contains([string]$settings.NetworkQosProtocol)) { $cmbNetworkQosProtocol.SelectedItem = [string]$settings.NetworkQosProtocol }
        if ($null -ne $settings.NetworkQosPorts) { $txtNetworkPorts.Text = [string]$settings.NetworkQosPorts }
        if ($settings.NetworkUso -and $cmbNetworkUso.Items.Contains([string]$settings.NetworkUso)) { $cmbNetworkUso.SelectedItem = [string]$settings.NetworkUso }
        if ($settings.NetworkUro -and $cmbNetworkUro.Items.Contains([string]$settings.NetworkUro)) { $cmbNetworkUro.SelectedItem = [string]$settings.NetworkUro }
        if ($null -ne $settings.NetworkDisablePowerSaving) { $chkNetworkDisablePowerSaving.Checked = [bool]$settings.NetworkDisablePowerSaving }
        if ($settings.NetworkInterruptModeration -and $cmbNetworkInterruptModeration.Items.Contains([string]$settings.NetworkInterruptModeration)) { $cmbNetworkInterruptModeration.SelectedItem = [string]$settings.NetworkInterruptModeration }
        if ($null -ne $settings.NetworkDisableEee) { $chkNetworkDisableEee.Checked = [bool]$settings.NetworkDisableEee }
        if ($null -ne $settings.NetworkRestoreOnStop) { $chkNetworkRestoreOnStop.Checked = [bool]$settings.NetworkRestoreOnStop }
        if ($null -ne $settings.NetworkRestoreOnExit) { $chkNetworkRestoreOnExit.Checked = [bool]$settings.NetworkRestoreOnExit }
        if ($null -ne $settings.NetworkRecoveryTask) { $chkNetworkRecoveryTask.Checked = [bool]$settings.NetworkRecoveryTask }
        if ($settings.NetworkAdapter) {
            for ($i = 0; $i -lt $cmbNetworkAdapter.Items.Count; $i++) {
                if ([string]$cmbNetworkAdapter.Items[$i] -like "$([string]$settings.NetworkAdapter) |*") { $cmbNetworkAdapter.SelectedIndex = $i; break }
            }
        }
        if ($settings.Width) { $numWidth.Value = [decimal]$settings.Width }
        if ($settings.Height) { $numHeight.Value = [decimal]$settings.Height }
        if ($settings.Fps) { $numFps.Value = [decimal]$settings.Fps }
        if ($settings.VideoBitrateKbps) { $numVideoBitrate.Value = [decimal]$settings.VideoBitrateKbps }
        if ($settings.RateControl -and $cmbRateControl.Items.Contains([string]$settings.RateControl)) { $cmbRateControl.SelectedItem = [string]$settings.RateControl }
        if ($null -ne $settings.MaxVideoBitrateKbps) { $numMaxVideoBitrate.Value = [decimal]$settings.MaxVideoBitrateKbps }
        if ($null -ne $settings.ConstantQp) { $numConstantQp.Value = [decimal]$settings.ConstantQp }
        if ($settings.GopSeconds) { $numGopSeconds.Value = [decimal]$settings.GopSeconds }
        if ($null -ne $settings.UnifiedBridgeKeyframeGuard) { $chkUnifiedBridgeKeyframeGuard.Checked = [bool]$settings.UnifiedBridgeKeyframeGuard }
        if ($null -ne $settings.UnifiedBridgeKeyframeIntervalMs) { $numUnifiedBridgeKeyframeIntervalMs.Value = [decimal]([Math]::Min(10000, [Math]::Max(100, [int]$settings.UnifiedBridgeKeyframeIntervalMs))) }
        if ($settings.Encoder -and $cmbEncoder.Items.Contains([string]$settings.Encoder)) {
            $cmbEncoder.SelectedItem = [string]$settings.Encoder
        }
        if ($settings.Preset -and $cmbPreset.Items.Contains([string]$settings.Preset)) { $cmbPreset.SelectedItem = [string]$settings.Preset }
        if ($settings.Profile -and $cmbProfile.Items.Contains([string]$settings.Profile)) { $cmbProfile.SelectedItem = [string]$settings.Profile }
        if ($settings.EncoderTune -and $cmbEncoderTune.Items.Contains([string]$settings.EncoderTune)) { $cmbEncoderTune.SelectedItem = [string]$settings.EncoderTune }
        if ($settings.Multipass -and $cmbMultipass.Items.Contains([string]$settings.Multipass)) { $cmbMultipass.SelectedItem = [string]$settings.Multipass }
        if ($settings.VideoPipelineClockMode -and $cmbVideoPipelineClockMode.Items.Contains([string]$settings.VideoPipelineClockMode)) { $cmbVideoPipelineClockMode.SelectedItem = [string]$settings.VideoPipelineClockMode }
        if ($settings.VideoTimestampMode -and $cmbVideoTimestampMode.Items.Contains([string]$settings.VideoTimestampMode)) { $cmbVideoTimestampMode.SelectedItem = [string]$settings.VideoTimestampMode }
        if ($settings.SplitAudioPipelineClockMode -and $cmbSplitAudioPipelineClockMode.Items.Contains([string]$settings.SplitAudioPipelineClockMode)) { $cmbSplitAudioPipelineClockMode.SelectedItem = [string]$settings.SplitAudioPipelineClockMode }
        if ($settings.VideoSyncMode -and $cmbVideoSyncMode.Items.Contains([string]$settings.VideoSyncMode)) { $cmbVideoSyncMode.SelectedItem = [string]$settings.VideoSyncMode }
        if ($null -ne $settings.VbvBufferKbits) { $numVbvBuffer.Value = [decimal]$settings.VbvBufferKbits }
        if ($null -ne $settings.BFrames) { $numBFrames.Value = [decimal]$settings.BFrames }
        if ($null -ne $settings.LookAhead) { $chkLookAhead.Checked = [bool]$settings.LookAhead }
        if ($settings.LookAheadFrames) { $numLookAheadFrames.Value = [decimal]$settings.LookAheadFrames }
        if ($null -ne $settings.SpatialAq) {
            $chkAdaptiveQuantization.Checked = [bool]$settings.SpatialAq
        }
        elseif ($null -ne $settings.AdaptiveQuantization) {
            $chkAdaptiveQuantization.Checked = [bool]$settings.AdaptiveQuantization
        }
        if ($null -ne $settings.TemporalAq) { $chkTemporalAq.Checked = [bool]$settings.TemporalAq }
        if ($settings.AqStrength) { $numAqStrength.Value = [decimal]$settings.AqStrength }
        if ($null -ne $settings.CustomEncoderOptions) { $txtCustomEncoderOptions.Text = [string]$settings.CustomEncoderOptions }

        foreach ($audioSetting in @(
            @('WhipAudioCodec', 'WHIP'),
            @('GstWebRtcAudioCodec', 'GST WebRTC'),
            @('SrtAudioCodec', 'SRT'),
            @('RtmpAudioCodec', 'RTMP'),
            @('RtspAudioCodec', 'RTSP')
        )) {
            $propertyName = $audioSetting[0]
            $protocolName = $audioSetting[1]
            $value = [string]$settings.$propertyName
            if (
                -not [string]::IsNullOrWhiteSpace($value) -and
                (Test-AudioCodecProtocolCompatibility `
                    -AudioCodecName $value `
                    -Protocol $protocolName)
            ) {
                $script:ProtocolAudioCodecs[$protocolName] = $value
            }
        }

        if ($settings.AudioTransportMode -and $cmbAudioTransportMode.Items.Contains([string]$settings.AudioTransportMode)) { $cmbAudioTransportMode.SelectedItem = [string]$settings.AudioTransportMode }
        $savedAudioClockMode = [string]$settings.AudioClockMode
        if ($savedAudioClockMode -eq 'WASAPI clock') { $savedAudioClockMode = 'Plugin default / allow WASAPI clock' }
        if ($savedAudioClockMode -and $cmbAudioClockMode.Items.Contains($savedAudioClockMode)) { $cmbAudioClockMode.SelectedItem = $savedAudioClockMode }
        $savedAudioTimingMode = [string]$settings.AudioTimingMode
        if ($savedAudioTimingMode -eq 'WASAPI normal') { $savedAudioTimingMode = 'Plugin default / WASAPI normal' }
        if ($savedAudioTimingMode -and $cmbAudioTimingMode.Items.Contains($savedAudioTimingMode)) { $cmbAudioTimingMode.SelectedItem = $savedAudioTimingMode }
        if ($settings.AudioSlaveMethod -and $cmbAudioSlaveMethod.Items.Contains([string]$settings.AudioSlaveMethod)) { $cmbAudioSlaveMethod.SelectedItem = [string]$settings.AudioSlaveMethod }
        if ($settings.AudioSyncMode -and $cmbAudioSyncMode.Items.Contains([string]$settings.AudioSyncMode)) { $cmbAudioSyncMode.SelectedItem = [string]$settings.AudioSyncMode }
        if ($null -ne $settings.WasapiLowLatencyOverride) { $chkWasapiLowLatencyOverride.Checked = [bool]$settings.WasapiLowLatencyOverride }
        if ($null -ne $settings.AudioBufferOverride) { $chkAudioBufferOverride.Checked = [bool]$settings.AudioBufferOverride }
        if ($null -ne $settings.AudioBufferMs) { $numAudioBufferMs.Value = [decimal]$settings.AudioBufferMs }
        if ($null -ne $settings.AudioLatencyOverride) { $chkAudioLatencyOverride.Checked = [bool]$settings.AudioLatencyOverride }
        if ($null -ne $settings.AudioLatencyMs) { $numAudioLatencyMs.Value = [decimal]$settings.AudioLatencyMs }
        if ($null -ne $settings.AudioSampleRateOverride) { $chkAudioSampleRateOverride.Checked = [bool]$settings.AudioSampleRateOverride }
        if ($null -ne $settings.AudioSampleRateHz) { $numAudioSampleRate.Value = [decimal]$settings.AudioSampleRateHz }
        if ($null -ne $settings.DesktopAudio) { $chkDesktopAudio.Checked = [bool]$settings.DesktopAudio }
        if ($null -ne $settings.AudioMixerMode) { $chkAudioMixerMode.Checked = [bool]$settings.AudioMixerMode }
        if ($null -ne $settings.DesktopVolume) { $numDesktopVolume.Value = [decimal]$settings.DesktopVolume }
        if ($settings.DesktopAudioDevice) { Restore-AudioDeviceSelection -Kind Output -Label ([string]$settings.DesktopAudioDevice) -DeviceId ([string]$settings.DesktopAudioDeviceId) }
        if ($null -ne $settings.Microphone) { $chkMic.Checked = [bool]$settings.Microphone }
        if ($null -ne $settings.MicrophoneVolume) { $numMicVolume.Value = [decimal]$settings.MicrophoneVolume }
        if ($settings.MicrophoneDevice) { Restore-AudioDeviceSelection -Kind Input -Label ([string]$settings.MicrophoneDevice) -DeviceId ([string]$settings.MicrophoneDeviceId) }
        if ($settings.AudioBitrateKbps) { $numAudioBitrate.Value = [decimal]$settings.AudioBitrateKbps }
        if ($settings.DirectWebRtcOpusMode -and $cmbDirectWebRtcOpusMode.Items.Contains([string]$settings.DirectWebRtcOpusMode)) { $cmbDirectWebRtcOpusMode.SelectedItem = [string]$settings.DirectWebRtcOpusMode }
        if ($settings.DirectWebRtcOpusFrameMs -and $cmbDirectWebRtcOpusFrameMs.Items.Contains([string]$settings.DirectWebRtcOpusFrameMs)) { $cmbDirectWebRtcOpusFrameMs.SelectedItem = [string]$settings.DirectWebRtcOpusFrameMs }
        if ($settings.DirectWebRtcOpusAudioType -and $cmbDirectWebRtcOpusAudioType.Items.Contains([string]$settings.DirectWebRtcOpusAudioType)) { $cmbDirectWebRtcOpusAudioType.SelectedItem = [string]$settings.DirectWebRtcOpusAudioType }
        if ($null -ne $settings.DirectWebRtcOpusFec) { $chkDirectWebRtcOpusFec.Checked = [bool]$settings.DirectWebRtcOpusFec }
        if ($null -ne $settings.DirectWebRtcOpusDtx) { $chkDirectWebRtcOpusDtx.Checked = [bool]$settings.DirectWebRtcOpusDtx }

        $protocol = if ($settings.Protocol -and $cmbProtocol.Items.Contains([string]$settings.Protocol)) { [string]$settings.Protocol } else { 'WHIP' }
        $cmbProtocol.SelectedItem = $protocol
        $script:LastProtocol = $protocol
        $txtDestination.Text = [string]$script:ProtocolDestinations[$protocol]
    }
    catch {
        Append-Log "Could not load settings: $($_.Exception.Message)"
    }
    finally {
        $script:SuppressProtocolChange = $false
        $script:LoadingSettings = $false
        # Existing f13 settings can contain a stale global TimingMode and a
        # different Direct WebRTC clock-signalling value. For Direct GST WebRTC,
        # preserve the actually emitted advanced setting and reconcile the
        # global selector to it once loading is complete.
        Sync-TransportTimingControls -Source DirectWebRtc
        Update-TransportUi
        Update-DirectWebRtcUi
        Update-EncoderUi
        Update-RecordingUi
        Update-NetworkUi
        Update-SceneUi
    }
}

function Validate-Configuration {
    $gstPath = Resolve-GstLaunchSelection -RequestedPath $txtGstPath.Text -UpdateControl
    if (-not (Test-GstLaunchPath $gstPath)) {
        [System.Windows.Forms.MessageBox]::Show(
            'Select a valid gst-launch-1.0.exe path.',
            $script:AppName,
            'OK',
            'Warning'
        ) | Out-Null
        return $false
    }

    $customGstArgumentsOverride = Test-CustomGstArgumentsOverride
    if ($customGstArgumentsOverride) {
        try {
            [void](Get-CustomGstArguments)
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
            return $false
        }
    }

    if ((-not $customGstArgumentsOverride) -and -not (Test-TransportEnabled) -and -not (Test-RecordingEnabled) -and -not $chkPreview.Checked) {
        [System.Windows.Forms.MessageBox]::Show(
            'Enable transport, recording, or preview before starting.',
            $script:AppName,
            'OK',
            'Warning'
        ) | Out-Null
        return $false
    }

    if ((Test-TransportEnabled) -and $chkStartMediaMtx.Checked -and ([string]$cmbProtocol.SelectedItem -ne $script:DirectWebRtcProtocolName)) {
        $mediaMtxPath = $txtMediaMtxPath.Text.Trim()
        if (
            [string]::IsNullOrWhiteSpace($mediaMtxPath) -or
            -not (Test-Path -LiteralPath $mediaMtxPath)
        ) {
            [System.Windows.Forms.MessageBox]::Show(
                'Select a valid mediamtx.exe path or disable MediaMTX management.',
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
            return $false
        }

        if (
            -not [System.IO.Path]::GetFileName($mediaMtxPath).Equals(
                'mediamtx.exe',
                [System.StringComparison]::OrdinalIgnoreCase
            )
        ) {
            $result = [System.Windows.Forms.MessageBox]::Show(
                "The selected MediaMTX executable is not named mediamtx.exe.`r`n`r`nContinue anyway?",
                $script:AppName,
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )

            if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
                return $false
            }
        }
    }

    if ($customGstArgumentsOverride) {
        $script:ResolvedRecordingPath = ''
        return $true
    }

    if (Test-TransportEnabled) {
        $protocol = [string]$cmbProtocol.SelectedItem
        $destination = $txtDestination.Text.Trim()
    $valid = switch ($protocol) {
        'WHIP' { $destination -match '^https?://' }
        'GST WebRTC' { $destination -match '^https?://' }
        'SRT'  { $destination -match '^srt://' }
        'RTMP' { $destination -match '^rtmps?://' }
        'RTSP' { $destination -match '^rtsps?://' }
        default { $false }
    }

    if (-not $valid) {
        [System.Windows.Forms.MessageBox]::Show(
            "The destination does not match the selected $protocol protocol.",
            $script:AppName,
            'OK',
            'Warning'
        ) | Out-Null
        return $false
    }

    $definition = Get-SelectedEncoderDefinition
    $codec = [string]$definition.Codec
    if (-not (Test-CodecProtocolCompatibility -Codec $codec -Protocol $protocol)) {
        [System.Windows.Forms.MessageBox]::Show(
            "$codec is not supported by the $protocol pipeline template.`r`n`r`nSelect another encoder or protocol.",
            $script:AppName,
            'OK',
            'Warning'
        ) | Out-Null
        return $false
    }


    if (Test-DirectWebRtcSeparateMediaStreams) {
        $videoMsid = Get-DirectWebRtcMediaStreamId -Kind video
        $audioMsid = Get-DirectWebRtcMediaStreamId -Kind audio
        $validMsidPattern = '^[A-Za-z0-9_.-]+$'
        if ($videoMsid -notmatch $validMsidPattern -or $audioMsid -notmatch $validMsidPattern) {
            [System.Windows.Forms.MessageBox]::Show(
                'Video and audio MediaStream IDs may contain only letters, numbers, underscore, period, and hyphen.',
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
            return $false
        }
        if ($videoMsid.Equals($audioMsid, [System.StringComparison]::Ordinal)) {
            [System.Windows.Forms.MessageBox]::Show(
                'Separate audio/video MediaStreams requires different Video and Audio MediaStream IDs.',
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
            return $false
        }
    }

    if (Test-DirectWebRtcUnifiedPublisher) {
        if ($protocol -ne $script:DirectWebRtcProtocolName -or -not (Test-DirectWebRtcSplitAvPipelines)) {
            [System.Windows.Forms.MessageBox]::Show(
                'Unified A/V publisher requires GST WebRTC with Split A/V pipelines selected.',
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
            return $false
        }
        if ($codec -notin @('H264','H265')) {
            [System.Windows.Forms.MessageBox]::Show(
                "Unified A/V publisher currently supports H.264 and H.265 RTP bridge payloaders only. Selected codec: $codec.",
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
            return $false
        }
        if ((Get-ComboSelectedOrDefault $cmbAudioTransportMode $script:DefaultAudioTransportMode) -ne 'Normal audio' -or -not ($chkDesktopAudio.Checked -or $chkMic.Checked)) {
            [System.Windows.Forms.MessageBox]::Show(
                'Unified A/V publisher requires Normal audio with Desktop audio or Microphone enabled.',
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
            return $false
        }
        if ((Get-ComboSelectedOrDefault $cmbDirectWebRtcOpusMode $script:DefaultDirectWebRtcOpusMode) -eq 'Raw audio to webrtcsink') {
            [System.Windows.Forms.MessageBox]::Show(
                'Unified A/V publisher requires Explicit Opus encoder mode so audio can cross the local RTP bridge as Opus.',
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
            return $false
        }
        if ((Test-RecordingEnabled) -and ($chkRecordingDesktopAudio.Checked -or $chkRecordingMic.Checked)) {
            [System.Windows.Forms.MessageBox]::Show(
                'Unified A/V publisher lab currently supports local video-only recording. Disable Recording desktop/microphone audio so a second WASAPI source is not injected into the video capture process and allowed to contaminate this timing experiment.',
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
            return $false
        }
        if ([int]$numDirectWebRtcBridgeVideoPort.Value -eq [int]$numDirectWebRtcBridgeAudioPort.Value) {
            [System.Windows.Forms.MessageBox]::Show(
                'Video and audio RTP bridge ports must be different.',
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
            return $false
        }
    }

    if ($chkDesktopAudio.Checked -or $chkMic.Checked) {
        $audioCodecName = [string]$cmbAudioCodec.SelectedItem
        if (
            -not (Test-AudioCodecProtocolCompatibility `
                -AudioCodecName $audioCodecName `
                -Protocol $protocol)
        ) {
            [System.Windows.Forms.MessageBox]::Show(
                "$audioCodecName is not compatible with $protocol.",
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
            return $false
        }
    }

    if (
        $protocol -in @('WHIP', 'GST WebRTC') -and
        $codec -eq 'H264' -and
        $numBFrames.Enabled -and
        [int]$numBFrames.Value -gt 0
    ) {
        [System.Windows.Forms.MessageBox]::Show(
            'H.264 B-frames are not compatible with normal WebRTC playback. Set B-frames to 0 for WebRTC.',
            $script:AppName,
            'OK',
            'Warning'
        ) | Out-Null
        return $false
    }

    if ($protocol -eq 'RTMP' -and $codec -in @('H265', 'AV1')) {
        $result = [System.Windows.Forms.MessageBox]::Show(
            "$codec over RTMP uses Enhanced RTMP / eflvmux. The destination server and viewers must support that extension.`r`n`r`nContinue?",
            $script:AppName,
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
            return $false
        }
    }
    }

    if (Test-RecordingEnabled) {
        try {
            $script:ResolvedRecordingPath = Resolve-RecordingFilePath -EnsureDirectory -AvoidExisting
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Recording output could not be prepared.`r`n`r`n$($_.Exception.Message)",
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
            return $false
        }
    }
    else {
        $script:ResolvedRecordingPath = ''
    }

    return $true
}

