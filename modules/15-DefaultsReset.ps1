function Reset-WebRtcSaneDefaults {
    $cmbDirectWebRtcCongestion.SelectedItem = 'disabled'
    $numDirectWebRtcStartBitrateKbps.Value = $script:DefaultDirectWebRtcStartBitrateKbps
    $numDirectWebRtcMinBitrateKbps.Value = $script:DefaultDirectWebRtcMinBitrateKbps
    $cmbDirectWebRtcMitigation.SelectedItem = 'none'
    if ($cmbWebRtcRecoveryMode.Items.Contains($script:DefaultWebRtcRecoveryMode)) { $cmbWebRtcRecoveryMode.SelectedItem = $script:DefaultWebRtcRecoveryMode }
    if ($cmbWebRtcSenderQueueMode.Items.Contains($script:DefaultWebRtcSenderQueueMode)) { $cmbWebRtcSenderQueueMode.SelectedItem = $script:DefaultWebRtcSenderQueueMode }
    $chkDirectWebRtcFec.Checked = $false
    $chkDirectWebRtcRetransmission.Checked = $false
    if ($cmbWebRtcRecoveryMode.Items.Contains($script:DefaultWebRtcRecoveryMode)) { Set-WebRtcRecoveryMode $script:DefaultWebRtcRecoveryMode }
    if ($cmbDirectWebRtcSmoothnessProfile.Items.Contains($script:DefaultDirectWebRtcSmoothnessProfile)) { $cmbDirectWebRtcSmoothnessProfile.SelectedItem = $script:DefaultDirectWebRtcSmoothnessProfile }
    $numDirectWebRtcPacingMs.Value = $script:DefaultDirectWebRtcPacingMs
    $numDirectWebRtcPlayerJitterMs.Value = $script:DefaultDirectWebRtcPlayerJitterMs
    $numDirectWebRtcVideoJitterMs.Value = $script:DefaultDirectWebRtcVideoJitterMs
    $numJbufMaxMs.Value = $script:DefaultJbufMaxMs
    if ($cmbJbufWatchdogMode.Items.Contains($script:DefaultJbufWatchdogMode)) { $cmbJbufWatchdogMode.SelectedItem = $script:DefaultJbufWatchdogMode }
    $chkPlayerStatsOverlay.Checked = $script:DefaultPlayerStatsOverlay
    $chkPlayerJbufDebug.Checked = $script:DefaultPlayerJbufDebug
    $numLiveEdgeAverageSec.Value = $script:DefaultLiveEdgeAverageSec
    $numLiveEdgeGreenMs.Value = $script:DefaultLiveEdgeGreenMs
    $numLiveEdgeYellowMs.Value = $script:DefaultLiveEdgeYellowMs
    $chkPlayerUrlOverrides.Checked = $script:DefaultPlayerUrlOverrides
    if ($cmbTimingMode.Items.Contains($script:DefaultTimingMode)) { $cmbTimingMode.SelectedItem = $script:DefaultTimingMode }
    $chkSplitClockSignalingOverrides.Checked = $script:DefaultSplitClockSignalingOverrides
    if ($cmbSplitVideoClockSignaling.Items.Contains($script:DefaultSplitVideoClockSignaling)) { $cmbSplitVideoClockSignaling.SelectedItem = $script:DefaultSplitVideoClockSignaling }
    if ($cmbSplitAudioClockSignaling.Items.Contains($script:DefaultSplitAudioClockSignaling)) { $cmbSplitAudioClockSignaling.SelectedItem = $script:DefaultSplitAudioClockSignaling }
    $chkDirectWebRtcControlDataChannel.Checked = $script:DefaultDirectWebRtcControlDataChannel
    if ($cmbDirectWebRtcBundlePolicy.Items.Contains($script:DefaultDirectWebRtcBundlePolicy)) { $cmbDirectWebRtcBundlePolicy.SelectedItem = $script:DefaultDirectWebRtcBundlePolicy }
    $numDirectWebRtcInternalRtpMtu.Value = $script:DefaultDirectWebRtcInternalRtpMtu
    $chkDirectWebRtcInternalRepeatHeaders.Checked = $script:DefaultDirectWebRtcInternalRepeatHeaders
    $chkPlayerSeparateHtmlMediaElements.Checked = $script:DefaultPlayerSeparateHtmlMediaElements
    if ($cmbDirectWebRtcAvPipelineMode.Items.Contains($script:DefaultDirectWebRtcAvPipelineMode)) { $cmbDirectWebRtcAvPipelineMode.SelectedItem = $script:DefaultDirectWebRtcAvPipelineMode }
    if ($cmbSplitPlayerSyncMode.Items.Contains($script:DefaultSplitPlayerSyncMode)) { $cmbSplitPlayerSyncMode.SelectedItem = $script:DefaultSplitPlayerSyncMode }
    $numSplitAudioStallSeconds.Value = $script:DefaultSplitAudioStallSeconds
    $numSplitAudioWarmupSeconds.Value = $script:DefaultSplitAudioWarmupSeconds
    $numSplitAvOffsetBaselineMs.Value = $script:DefaultSplitAvOffsetBaselineMs
    $numSplitAvOffsetWarnMs.Value = $script:DefaultSplitAvOffsetWarnMs
    Update-DirectWebRtcUi
    Update-CommandPreview
}

function Reset-TransportDefaults {
    $chkTransportEnabled.Checked = $true
    $cmbProtocol.SelectedItem = 'WHIP'
    $script:ProtocolDestinations.WHIP = 'http://10.0.0.25:8889/live/whip'
    $script:ProtocolDestinations.SRT = 'srt://10.0.0.25:8890?mode=caller&streamid=publish:live'
    $script:ProtocolDestinations.RTMP = 'rtmp://10.0.0.25/live'
    $script:ProtocolDestinations.RTSP = 'rtsp://10.0.0.25:8554/live'
    $script:ProtocolDestinations[$script:DirectWebRtcProtocolName] = $script:DefaultDirectWebRtcWebAddress
    $txtDestination.Text = $script:ProtocolDestinations.WHIP
    $txtDirectWebRtcSignalingHost.Text = $script:DefaultDirectWebRtcSignalingHost
    $numDirectWebRtcSignalingPort.Value = $script:DefaultDirectWebRtcSignalingPort
    $numDirectWebRtcSplitAudioSignalingPort.Value = $script:DefaultDirectWebRtcSplitAudioSignalingPort
    $chkDirectWebRtcSharedSignaling.Checked = $script:DefaultDirectWebRtcSharedSignaling
    if ($cmbDirectWebRtcMediaStreamGrouping.Items.Contains($script:DefaultDirectWebRtcMediaStreamGrouping)) { $cmbDirectWebRtcMediaStreamGrouping.SelectedItem = $script:DefaultDirectWebRtcMediaStreamGrouping }
    $txtDirectWebRtcVideoMediaStreamId.Text = $script:DefaultDirectWebRtcVideoMediaStreamId
    $txtDirectWebRtcAudioMediaStreamId.Text = $script:DefaultDirectWebRtcAudioMediaStreamId
    $chkDirectWebRtcUnifiedPublisher.Checked = $script:DefaultDirectWebRtcUnifiedPublisher
    $numDirectWebRtcBridgeVideoPort.Value = $script:DefaultDirectWebRtcBridgeVideoPort
    $numDirectWebRtcBridgeAudioPort.Value = $script:DefaultDirectWebRtcBridgeAudioPort
    $numDirectWebRtcBridgeJitterMs.Value = $script:DefaultDirectWebRtcBridgeJitterMs
    $numDirectWebRtcPublisherQueueMs.Value = $script:DefaultDirectWebRtcPublisherQueueMs
    $chkDirectWebRtcAudioBridgePacing.Checked = $script:DefaultDirectWebRtcAudioBridgePacing
    if ($cmbTimingMode.Items.Contains($script:DefaultTimingMode)) { $cmbTimingMode.SelectedItem = $script:DefaultTimingMode }
    $chkSplitClockSignalingOverrides.Checked = $script:DefaultSplitClockSignalingOverrides
    if ($cmbSplitVideoClockSignaling.Items.Contains($script:DefaultSplitVideoClockSignaling)) { $cmbSplitVideoClockSignaling.SelectedItem = $script:DefaultSplitVideoClockSignaling }
    if ($cmbSplitAudioClockSignaling.Items.Contains($script:DefaultSplitAudioClockSignaling)) { $cmbSplitAudioClockSignaling.SelectedItem = $script:DefaultSplitAudioClockSignaling }
    $chkDirectWebRtcControlDataChannel.Checked = $script:DefaultDirectWebRtcControlDataChannel
    if ($cmbDirectWebRtcBundlePolicy.Items.Contains($script:DefaultDirectWebRtcBundlePolicy)) { $cmbDirectWebRtcBundlePolicy.SelectedItem = $script:DefaultDirectWebRtcBundlePolicy }
    $numDirectWebRtcInternalRtpMtu.Value = $script:DefaultDirectWebRtcInternalRtpMtu
    $chkDirectWebRtcInternalRepeatHeaders.Checked = $script:DefaultDirectWebRtcInternalRepeatHeaders
    $txtDirectWebRtcStun.Text = $script:DefaultDirectWebRtcStunServer
    $chkDirectWebRtcTurnEnabled.Checked = $script:DefaultDirectWebRtcTurnEnabled
    $txtDirectWebRtcTurn.Text = $script:DefaultDirectWebRtcTurnServer
    $txtDirectWebRtcWebPath.Text = $script:DefaultDirectWebRtcWebPath
    if ($cmbDirectWebRtcBundledWebMode.Items.Contains($script:DefaultDirectWebRtcBundledWebMode)) { $cmbDirectWebRtcBundledWebMode.SelectedItem = $script:DefaultDirectWebRtcBundledWebMode }
    $txtDirectWebRtcBundledWebDirectory.Text = $script:DefaultDirectWebRtcBundledWebDirectory
    if ($cmbDirectWebRtcWorkingWebMode.Items.Contains($script:DefaultDirectWebRtcWorkingWebMode)) { $cmbDirectWebRtcWorkingWebMode.SelectedItem = $script:DefaultDirectWebRtcWorkingWebMode }
    $txtDirectWebRtcWebDirectory.Text = $script:DefaultDirectWebRtcWorkingWebDirectory
    Reset-WebRtcSaneDefaults
    $numMonitor.Value = -1
    $chkCursor.Checked = $true
    $chkSendAbsoluteTimestamps.Checked = $false
    $chkStartMediaMtx.Checked = $false
    $txtMediaMtxPath.Text = Find-MediaMtx
    $numSrtLatency.Value = 50
    $cmbRtspTransport.SelectedItem = 'TCP'
    if ($cmbTimingMode.Items.Contains($script:DefaultTimingMode)) { $cmbTimingMode.SelectedItem = $script:DefaultTimingMode }
    Update-TransportUi
    Update-DirectWebRtcUi
    Update-CaptureModeUi
}

function Reset-VideoDefaults {
    $cmbCaptureMethod.SelectedItem = $script:DefaultCaptureMethodName
    $numWidth.Value = 1920
    $numHeight.Value = 1080
    $numFps.Value = 60
    $numVideoBitrate.Value = 12000
    $numMaxVideoBitrate.Value = 0
    $numConstantQp.Value = 20
    $numGopSeconds.Value = 1
    $chkUnifiedBridgeKeyframeGuard.Checked = $script:DefaultUnifiedBridgeKeyframeGuard
    $numUnifiedBridgeKeyframeIntervalMs.Value = $script:DefaultUnifiedBridgeKeyframeIntervalMs
    $cmbEncoder.SelectedItem = $script:DefaultEncoderName
    $cmbRateControl.SelectedItem = 'cbr'
    $cmbPreset.SelectedItem = 'p1'
    $cmbProfile.SelectedItem = 'constrained-baseline'
    $cmbEncoderTune.SelectedItem = 'ultra-low-latency'
    $cmbMultipass.SelectedItem = 'disabled'
    if ($cmbVideoPipelineClockMode.Items.Contains($script:DefaultVideoPipelineClockMode)) { $cmbVideoPipelineClockMode.SelectedItem = $script:DefaultVideoPipelineClockMode }
    if ($cmbVideoTimestampMode.Items.Contains($script:DefaultVideoTimestampMode)) { $cmbVideoTimestampMode.SelectedItem = $script:DefaultVideoTimestampMode }
    if ($cmbVideoSyncMode.Items.Contains($script:DefaultVideoSyncMode)) { $cmbVideoSyncMode.SelectedItem = $script:DefaultVideoSyncMode }
    $numVbvBuffer.Value = 0
    $numBFrames.Value = 0
    $chkLookAhead.Checked = $false
    $numLookAheadFrames.Value = 20
    $chkAdaptiveQuantization.Checked = $false
    $chkTemporalAq.Checked = $false
    $numAqStrength.Value = 8
    $txtCustomEncoderOptions.Text = ''
    $numSceneInputQueueBuffers.Value = $script:DefaultSceneInputQueueBuffers
    $numSceneInputQueueCapMs.Value = $script:DefaultSceneInputQueueCapMs
    Update-CaptureModeUi
    Update-EncoderUi
}

function Reset-AudioDefaults {
    if ($cmbAudioTransportMode.Items.Contains($script:DefaultAudioTransportMode)) { $cmbAudioTransportMode.SelectedItem = $script:DefaultAudioTransportMode }
    if ($cmbSplitAudioPipelineClockMode.Items.Contains($script:DefaultSplitAudioPipelineClockMode)) { $cmbSplitAudioPipelineClockMode.SelectedItem = $script:DefaultSplitAudioPipelineClockMode }
    if ($cmbAudioClockMode.Items.Contains($script:DefaultAudioClockMode)) { $cmbAudioClockMode.SelectedItem = $script:DefaultAudioClockMode }
    if ($cmbAudioTimingMode.Items.Contains($script:DefaultAudioTimingMode)) { $cmbAudioTimingMode.SelectedItem = $script:DefaultAudioTimingMode }
    if ($cmbAudioSlaveMethod.Items.Contains($script:DefaultAudioSlaveMethod)) { $cmbAudioSlaveMethod.SelectedItem = $script:DefaultAudioSlaveMethod }
    if ($cmbAudioSyncMode.Items.Contains($script:DefaultAudioSyncMode)) { $cmbAudioSyncMode.SelectedItem = $script:DefaultAudioSyncMode }
    $chkWasapiLowLatencyOverride.Checked = $script:DefaultWasapiLowLatencyOverride
    $chkAudioBufferOverride.Checked = $script:DefaultAudioBufferOverride
    $numAudioBufferMs.Value = $script:DefaultAudioBufferMs
    $chkAudioLatencyOverride.Checked = $script:DefaultAudioLatencyOverride
    $numAudioLatencyMs.Value = $script:DefaultAudioLatencyMs
    $chkAudioSampleRateOverride.Checked = $script:DefaultAudioSampleRateOverride
    $numAudioSampleRate.Value = $script:DefaultAudioSampleRate
    $chkDesktopAudio.Checked = $true
    $chkAudioMixerMode.Checked = $script:DefaultAudioMixerMode
    $numDesktopVolume.Value = 100
    if ($cmbDesktopAudioDevice -and $cmbDesktopAudioDevice.Items.Contains($script:DefaultAudioOutputDeviceLabel)) { $cmbDesktopAudioDevice.SelectedItem = $script:DefaultAudioOutputDeviceLabel }
    $chkMic.Checked = $false
    $numMicVolume.Value = 100
    if ($cmbMicAudioDevice -and $cmbMicAudioDevice.Items.Contains($script:DefaultAudioInputDeviceLabel)) { $cmbMicAudioDevice.SelectedItem = $script:DefaultAudioInputDeviceLabel }
    $script:ProtocolAudioCodecs.WHIP = 'Opus'
    $script:ProtocolAudioCodecs.SRT = 'Opus'
    $script:ProtocolAudioCodecs.RTMP = 'AAC'
    $script:ProtocolAudioCodecs.RTSP = 'Opus'
    $cmbAudioCodec.SelectedItem = $script:ProtocolAudioCodecs[([string]$cmbProtocol.SelectedItem)]
    $numAudioBitrate.Value = 160
    if ($cmbDirectWebRtcOpusMode.Items.Contains($script:DefaultDirectWebRtcOpusMode)) { $cmbDirectWebRtcOpusMode.SelectedItem = $script:DefaultDirectWebRtcOpusMode }
    if ($cmbDirectWebRtcOpusFrameMs.Items.Contains($script:DefaultDirectWebRtcOpusFrameMs)) { $cmbDirectWebRtcOpusFrameMs.SelectedItem = $script:DefaultDirectWebRtcOpusFrameMs }
    if ($cmbDirectWebRtcOpusAudioType.Items.Contains($script:DefaultDirectWebRtcOpusAudioType)) { $cmbDirectWebRtcOpusAudioType.SelectedItem = $script:DefaultDirectWebRtcOpusAudioType }
    $chkDirectWebRtcOpusFec.Checked = $script:DefaultDirectWebRtcOpusFec
    $chkDirectWebRtcOpusDtx.Checked = $script:DefaultDirectWebRtcOpusDtx
    Update-AudioCodecChoices
}

function Reset-RecordingDefaults {
    $chkRecordingEnabled.Checked = $false
    $chkRecordWithStream.Checked = $false
    $txtRecordingDirectory.Text = Join-Path ([Environment]::GetFolderPath('MyVideos')) 'GStreamer Glass'
    $txtRecordingTemplate.Text = 'Glass-{yyyyMMdd-HHmmss}-{protocol}-{width}x{height}-{fps}fps.mkv'
    $cmbRecordingEncoder.SelectedItem = $script:DefaultEncoderName
    $cmbRecordingRateControl.SelectedItem = 'constqp'
    $numRecordingVideoBitrate.Value = 24000
    $numRecordingMaxVideoBitrate.Value = 0
    $numRecordingConstantQp.Value = 20
    $numRecordingWidth.Value = 1920
    $numRecordingHeight.Value = 1080
    $numRecordingFps.Value = 60
    $numRecordingGopSeconds.Value = 2
    $numRecordingBFrames.Value = 2
    $cmbRecordingPreset.SelectedItem = 'p5'
    $cmbRecordingProfile.SelectedItem = 'high'
    $cmbRecordingTune.SelectedItem = 'high-quality'
    $cmbRecordingMultipass.SelectedItem = 'two-pass-quarter'
    $chkRecordingLookAhead.Checked = $false
    $numRecordingLookAheadFrames.Value = 20
    $chkRecordingSpatialAq.Checked = $true
    $chkRecordingTemporalAq.Checked = $true
    $numRecordingAqStrength.Value = 8
    $numRecordingVbvBuffer.Value = 0
    $txtRecordingCustomEncoderOptions.Text = ''
    $chkRecordingDesktopAudio.Checked = $true
    $chkRecordingMic.Checked = $false
    $numRecordingAudioBitrate.Value = 192
    Update-RecordingUi
}

function Reset-NetworkDefaults {
    $chkNetworkTuningEnabled.Checked = $false
    $cmbNetworkProfile.SelectedItem = 'No changes'
    $chkNetworkDscp.Checked = $false
    $numNetworkDscp.Value = 34
    $cmbNetworkQosProtocol.SelectedItem = 'UDP'
    $txtNetworkPorts.Text = ''
    $cmbNetworkUso.SelectedItem = 'Leave unchanged'
    $cmbNetworkUro.SelectedItem = 'Leave unchanged'
    $chkNetworkDisablePowerSaving.Checked = $false
    $cmbNetworkInterruptModeration.SelectedItem = 'Leave unchanged'
    $chkNetworkDisableEee.Checked = $false
    $chkNetworkRestoreOnStop.Checked = $true
    $chkNetworkRestoreOnExit.Checked = $true
    $chkNetworkRecoveryTask.Checked = $true
    Update-NetworkUi
}

function Reset-OptionsDefaults {
    $txtGstPath.Text = Find-GstLaunch
    $chkPreview.Checked = $false
    $chkHidePreviewDuringStream.Checked = $false
    $chkAutoRestart.Checked = $true
    $chkVerbose.Checked = $false
    $chkDiskProcessLogging.Checked = $script:DefaultDiskProcessLogging
    $chkMinimizeToTray.Checked = $true
    $chkStartMinimized.Checked = $false
    if ($cmbThreadingProfile.Items.Contains($script:DefaultThreadingProfile)) { $cmbThreadingProfile.SelectedItem = $script:DefaultThreadingProfile }
    if ($cmbThreadBudget.Items.Contains($script:DefaultThreadBudget)) { $cmbThreadBudget.SelectedItem = $script:DefaultThreadBudget }
    if ($cmbGstDebugMode.Items.Contains($script:DefaultGstDebugMode)) { $cmbGstDebugMode.SelectedItem = $script:DefaultGstDebugMode }
    $txtGstDebugSpec.Text = $script:DefaultGstDebugSpec
    $chkGstDebugNoColor.Checked = $script:DefaultGstDebugNoColor
    if ($cmbJbufWatchdogMode.Items.Contains($script:DefaultJbufWatchdogMode)) { $cmbJbufWatchdogMode.SelectedItem = $script:DefaultJbufWatchdogMode }
    $numJbufMaxMs.Value = $script:DefaultJbufMaxMs
    Apply-ThreadingProfile -Force
    Apply-ThreadBudget -Force
    Update-CommandPreview
}

function Reset-AllAppDefaults {
    Reset-TransportDefaults
    Reset-VideoDefaults
    Reset-AudioDefaults
    Reset-RecordingDefaults
    Reset-NetworkDefaults
    Reset-OptionsDefaults
    Save-Settings
    Append-Log 'All GStreamer Glass app settings reset to defaults. Windows network snapshots were not touched.'
    Update-DirectWebRtcWebUiStatus
}

