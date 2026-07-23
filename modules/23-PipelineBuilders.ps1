function Get-EffectiveCaptureSettings {
    param([switch]$LocalOnly)

    $width = [int]$numWidth.Value
    $height = [int]$numHeight.Value
    $fps = [int]$numFps.Value

    # The source capture FPS is the only FPS d3d11convert can preserve. It can scale/format,
    # but it does not manufacture a new frame cadence. For recording-only local pipelines,
    # make the recording settings the capture settings so 120 FPS recording does not try to
    # link a 60 FPS raw tee into a 120 FPS encoder caps filter.
    if ($LocalOnly -and (Test-RecordingEnabled)) {
        $width = [int]$numRecordingWidth.Value
        $height = [int]$numRecordingHeight.Value
        $fps = [int]$numRecordingFps.Value
    }

    return [pscustomobject]@{
        Width  = [Math]::Max(1, $width)
        Height = [Math]::Max(1, $height)
        Fps    = [Math]::Max(1, $fps)
    }
}

function Build-DesktopCaptureChain {
    param([switch]$LocalOnly)

    $captureSettings = Get-EffectiveCaptureSettings -LocalOnly:$LocalOnly
    $monitor = [int]$numMonitor.Value
    $cursor = if ($chkCursor.Checked) { 'true' } else { 'false' }
    $gdiCursor = if ($chkCursor.Checked) { 'true' } else { 'false' }
    $width = [int]$captureSettings.Width
    $height = [int]$captureSettings.Height
    $fps = [int]$captureSettings.Fps
    $method = Get-SelectedCaptureMethod
    $gdiMonitor = if ($monitor -lt 0) { 0 } else { $monitor }
    $d3d11Source = Add-VideoSourceTimestampOption 'd3d11screencapturesrc'
    $gdiSource = Add-VideoSourceTimestampOption 'gdiscreencapsrc'

    switch ([string]$method.Method) {
        'FullscreenAppD3D11Wgc' {
            $windowHandle = if ($script:CaptureWindowHwnd -ne [IntPtr]::Zero) { [uint64]$script:CaptureWindowHwnd.ToInt64() } else { [uint64]0 }
            return @($d3d11Source,'capture-api=wgc',"window-handle=$windowHandle",'window-capture-mode=default','show-border=false',"show-cursor=$cursor",'!',"`"video/x-raw(memory:D3D11Memory),framerate=$fps/1`"",'!','d3d11convert','!',"`"video/x-raw(memory:D3D11Memory),format=NV12,width=$width,height=$height,framerate=$fps/1`"") -join ' '
        }
        'MonitorD3D11Wgc' {
            return @($d3d11Source,'capture-api=wgc',"monitor-index=$monitor", "show-cursor=$cursor",'!',"`"video/x-raw(memory:D3D11Memory),framerate=$fps/1`"",'!','d3d11convert','!',"`"video/x-raw(memory:D3D11Memory),format=NV12,width=$width,height=$height,framerate=$fps/1`"") -join ' '
        }
        'MonitorGdi' {
            return @($gdiSource,"monitor=$gdiMonitor", "cursor=$gdiCursor",'!',"`"video/x-raw,framerate=$fps/1`"",'!','videoconvert','!','videoscale','!',"`"video/x-raw,format=BGRA,width=$width,height=$height,framerate=$fps/1`"",'!','d3d11upload','!','d3d11convert','!',"`"video/x-raw(memory:D3D11Memory),format=NV12,width=$width,height=$height,framerate=$fps/1`"") -join ' '
        }
        default {
            return @($d3d11Source,'capture-api=dxgi',"monitor-index=$monitor", "show-cursor=$cursor",'!',"`"video/x-raw(memory:D3D11Memory),framerate=$fps/1`"",'!','d3d11convert','!',"`"video/x-raw(memory:D3D11Memory),format=NV12,width=$width,height=$height,framerate=$fps/1`"") -join ' '
        }
    }
}

function Build-SceneCaptureChain {
    param([switch]$LocalOnly)

    $captureSettings = Get-EffectiveCaptureSettings -LocalOnly:$LocalOnly
    $canvasWidth = [int]$captureSettings.Width
    $canvasHeight = [int]$captureSettings.Height
    $canvasFps = [int]$captureSettings.Fps
    $cameraWidth = [int]$numWebcamWidth.Value
    $cameraHeight = [int]$numWebcamHeight.Value
    $cameraX = [int]$numWebcamX.Value
    $cameraY = [int]$numWebcamY.Value
    $cameraFps = [int]$numWebcamFps.Value
    $cameraIndex = Get-SelectedWebcamIndex
    $alpha = ([double]$numWebcamOpacity.Value / 100.0).ToString('0.00', [Globalization.CultureInfo]::InvariantCulture)
    $sizingPolicy = if ($chkWebcamAspectLock.Checked) { 'keep-aspect-ratio' } else { 'none' }
    $mirror = if ($chkWebcamMirror.Checked) { ' ! videoflip method=horizontal-flip' } else { '' }
    $webcamSource = Add-VideoSourceTimestampOption "mfvideosrc device-index=$cameraIndex"
    $preset = [string]$cmbScenePreset.SelectedItem
    $cpuWorkers = Get-CpuWorkerLimit
    $cpuConvert = if ($cpuWorkers -gt 0) { "videoconvert n-threads=$cpuWorkers" } else { 'videoconvert' }
    $cpuCompositorWorkers = if ($cpuWorkers -gt 0) { " max-threads=$cpuWorkers" } else { '' }
    # A compositor combines independent live inputs. Each input keeps its own
    # queue boundary because removing the queues can produce GstAggregator
    # "max latency < min latency" failures. Depth and time cap are now explicit
    # Scene-tab settings; 0 ms is emitted literally and has no hidden fallback.
    $sceneInputBoundary = ' ! ' + (New-LiveQueueString -Buffers ([int]$numSceneInputQueueBuffers.Value) -MaxTimeMs ([int]$numSceneInputQueueCapMs.Value) -Leak 'downstream')

    if ($preset -eq 'Desktop only') { return (Build-DesktopCaptureChain -LocalOnly:$LocalOnly) }

    if ($preset -eq 'Webcam only') {
        return "$webcamSource ! video/x-raw,framerate=$cameraFps/1 ! $cpuConvert$mirror ! videoscale ! video/x-raw,format=BGRA,width=$canvasWidth,height=$canvasHeight ! videorate ! video/x-raw,format=BGRA,width=$canvasWidth,height=$canvasHeight,framerate=$canvasFps/1 ! d3d11upload ! d3d11convert ! `"video/x-raw(memory:D3D11Memory),format=NV12,width=$canvasWidth,height=$canvasHeight,framerate=$canvasFps/1`""
    }

    $desktop = Build-DesktopCaptureChain -LocalOnly:$LocalOnly
    if ([string]$cmbSceneCompositor.SelectedItem -eq 'CPU compatibility') {
        return "$desktop ! d3d11download ! $cpuConvert$sceneInputBoundary ! scene.sink_0 $webcamSource ! video/x-raw,framerate=$cameraFps/1 ! $cpuConvert$mirror ! videoscale ! video/x-raw,format=BGRA,width=$cameraWidth,height=$cameraHeight$sceneInputBoundary ! scene.sink_1 compositor name=scene background=black$cpuCompositorWorkers sink_0::xpos=0 sink_0::ypos=0 sink_0::width=$canvasWidth sink_0::height=$canvasHeight sink_0::zorder=0 sink_1::xpos=$cameraX sink_1::ypos=$cameraY sink_1::width=$cameraWidth sink_1::height=$cameraHeight sink_1::alpha=$alpha sink_1::zorder=1 sink_1::sizing-policy=$sizingPolicy ! $cpuConvert ! video/x-raw,format=BGRA,width=$canvasWidth,height=$canvasHeight,framerate=$canvasFps/1 ! d3d11upload ! d3d11convert ! `"video/x-raw(memory:D3D11Memory),format=NV12,width=$canvasWidth,height=$canvasHeight,framerate=$canvasFps/1`""
    }

    return "$desktop$sceneInputBoundary ! scene.sink_0 $webcamSource ! video/x-raw,framerate=$cameraFps/1 ! $cpuConvert$mirror ! videoscale ! video/x-raw,format=BGRA,width=$cameraWidth,height=$cameraHeight ! d3d11upload ! d3d11convert ! `"video/x-raw(memory:D3D11Memory),format=BGRA,width=$cameraWidth,height=$cameraHeight`"$sceneInputBoundary ! scene.sink_1 d3d11compositor name=scene background=black ignore-inactive-pads=true sink_0::xpos=0 sink_0::ypos=0 sink_0::width=$canvasWidth sink_0::height=$canvasHeight sink_0::zorder=0 sink_1::xpos=$cameraX sink_1::ypos=$cameraY sink_1::width=$cameraWidth sink_1::height=$cameraHeight sink_1::alpha=$alpha sink_1::zorder=1 sink_1::sizing-policy=$sizingPolicy ! d3d11convert ! `"video/x-raw(memory:D3D11Memory),format=NV12,width=$canvasWidth,height=$canvasHeight,framerate=$canvasFps/1`""
}

function Build-CaptureChain {
    param([switch]$LocalOnly)
    if ($chkSceneEnabled -and $chkSceneEnabled.Checked) {
        return (Build-SceneCaptureChain -LocalOnly:$LocalOnly)
    }
    return (Build-DesktopCaptureChain -LocalOnly:$LocalOnly)
}

function Test-PreviewEnabledForCurrentPipeline {
    if (-not $chkPreview.Checked) { return $false }
    if ($script:ForceLocalPreviewMode) { return $true }
    if ($script:ForceLiveScenePreviewBranch) { return $true }
    if ((Test-TransportEnabled) -and $chkHidePreviewDuringStream -and $chkHidePreviewDuringStream.Checked) { return $false }
    return $true
}

function Test-PreviewVisibleNow {
    if (-not $chkPreview.Checked) { return $false }
    if ($script:PreviewOnlyMode) { return $true }
    if ($script:ControlledLiveStreamActive) {
        if ((Test-TransportEnabled) -and $chkHidePreviewDuringStream -and $chkHidePreviewDuringStream.Checked) { return $false }
        return $true
    }
    if (($script:GstProcess -and -not $script:GstProcess.HasExited) -and (Test-TransportEnabled) -and $chkHidePreviewDuringStream -and $chkHidePreviewDuringStream.Checked) { return $false }
    return $true
}

function Build-VideoBranch {
    param([Parameter(Mandatory)][string]$Protocol)

    Assert-RecordingFrameRateCompatible
    $capture = Build-CaptureChain
    $encoder = Get-EncoderElementChain -Protocol $Protocol
    $hasPreview = Test-PreviewEnabledForCurrentPipeline
    $hasRecording = Test-RecordingEnabled

    if ($hasPreview -or $hasRecording) {
        $parts = New-Object System.Collections.Generic.List[string]
        $parts.Add($capture)
        $parts.Add('!')
        $parts.Add('tee')
        $parts.Add('name=rawtee')

        if ($hasRecording) {
            $recordingBranch = Build-RecordingMuxPrefixAndVideoBranch
            if (-not [string]::IsNullOrWhiteSpace($recordingBranch)) { $parts.Add($recordingBranch) }
        }

        if ($hasPreview) {
            $parts.Add((@('rawtee.','!',(New-LiveQueueString -Buffers 1 -Leak 'downstream'),'!','d3d11videosink','name=localpreview',(Get-VideoPreviewSinkSyncOption),'force-aspect-ratio=true') -join ' '))
        }

        $parts.Add("rawtee. ! $encoder")
        return ($parts -join ' ')
    }

    return "$capture ! $encoder"
}

function Build-LocalOnlyVideoPipeline {
    $capture = Build-CaptureChain -LocalOnly
    $hasPreview = Test-PreviewEnabledForCurrentPipeline
    $hasRecording = Test-RecordingEnabled

    if (-not $hasPreview -and -not $hasRecording) {
        throw 'Enable transport, recording, or preview before starting.'
    }

    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add($capture)
    $parts.Add('!')
    $parts.Add('tee')
    $parts.Add('name=rawtee')

    if ($hasRecording) {
        $recordingBranch = Build-RecordingMuxPrefixAndVideoBranch
        if (-not [string]::IsNullOrWhiteSpace($recordingBranch)) { $parts.Add($recordingBranch) }
    }

    if ($hasPreview) {
        $parts.Add((@('rawtee.','!',(New-LiveQueueString -Buffers 1 -Leak 'downstream'),'!','d3d11videosink','name=localpreview',(Get-VideoPreviewSinkSyncOption),'force-aspect-ratio=true') -join ' '))
    }

    return ($parts -join ' ')
}

function Build-GstArguments {
    $protocol = [string]$cmbProtocol.SelectedItem
    $destination = $txtDestination.Text.Trim()
    $quotedDestination = Quote-GstValue $destination

    if ($protocol -eq $script:DirectWebRtcProtocolName -and (Test-DirectWebRtcUnifiedPublisher)) {
        return (Build-DirectWebRtcUnifiedPublisherArguments)
    }

    if (-not (Test-TransportEnabled)) {
        $pipeline = Build-LocalOnlyVideoPipeline

        if (Test-RecordingEnabled) {
            $recordingAudioBranch = Build-RecordingAudioBranch
            if (-not [string]::IsNullOrWhiteSpace($recordingAudioBranch)) {
                $pipeline += " $recordingAudioBranch"
            }
        }

        $flags = '-e'
        if ($chkVerbose.Checked) {
            $flags += ' -v'
        }

        $pipeline = Wrap-GstPipelineWithClockSelect -Pipeline $pipeline -ClockMode (Get-VideoPipelineClockMode)
        return "$flags $pipeline"
    }

    $definition = Get-SelectedEncoderDefinition
    $codec = [string]$definition.Codec
    $mediaType = Get-CodecMediaType -Codec $codec
    $audioTransportMode = Get-ComboSelectedOrDefault $cmbAudioTransportMode $script:DefaultAudioTransportMode
    $userAudioEnabled =
        $audioTransportMode -eq 'Normal audio' -and
        ($chkDesktopAudio.Checked -or $chkMic.Checked)

    $audioRaw = $null
    $usingWhipSilentClockAudio = $false

    $audioTimingMode = Get-AudioTimingMode

    switch ($audioTransportMode) {
        'Video only - no audio track' {
            $audioRaw = $null
        }
        'Muted audio clock only' {
            $audioRaw = Build-WhipSilentClockAudioChain
            $usingWhipSilentClockAudio = $true
        }
        default {
            if ($audioTimingMode -eq 'Synthetic silent audio') {
                $audioRaw = Build-SyntheticSilentAudioChain
                $usingWhipSilentClockAudio = $true
            }
            else {
                $audioRaw = Build-RawAudioChain
                if (
                    $protocol -in @('WHIP', 'GST WebRTC') -and
                    [string]::IsNullOrWhiteSpace($audioRaw)
                ) {
                    $audioRaw = Build-WhipSilentClockAudioChain
                    $usingWhipSilentClockAudio = $true
                }
            }
        }
    }

    $hasAudio = -not [string]::IsNullOrWhiteSpace($audioRaw)

    $audioCodecName = if ($usingWhipSilentClockAudio) {
        'Opus'
    }
    else {
        [string]$cmbAudioCodec.SelectedItem
    }

    $audioDefinition = if ($usingWhipSilentClockAudio) {
        $script:AudioCodecCatalog['Opus']
    }
    else {
        Get-SelectedAudioCodecDefinition
    }

    $audioMediaType = switch ([string]$audioDefinition.Codec) {
        'OPUS' { 'audio/x-opus' }
        'AAC'  { 'audio/mpeg' }
        'MP3'  { 'audio/mpeg' }
        'AC3'  { 'audio/x-ac3' }
        default {
            throw "Unsupported audio codec: $([string]$audioDefinition.Codec)"
        }
    }

    $audioEncoded = if ($usingWhipSilentClockAudio) {
        $silentBitrate = [int]$numAudioBitrate.Value * 1000
        "opusenc bitrate=$silentBitrate bitrate-type=cbr frame-size=10 audio-type=restricted-lowdelay ! `"audio/x-opus`""
    }
    elseif ($hasAudio) {
        Get-AudioEncoderChain -Protocol $protocol
    }
    else {
        ''
    }
    $video = if ($protocol -eq $script:DirectWebRtcProtocolName) { '' } else { Build-VideoBranch -Protocol $protocol }
    $videoSyncSuffix = if ($protocol -eq $script:DirectWebRtcProtocolName) { '' } else { Get-VideoBranchSyncSuffix }
    $audioSyncSuffix = Get-AudioBranchSyncSuffix

    if (-not (Test-CodecProtocolCompatibility -Codec $codec -Protocol $protocol)) {
        throw "$codec is not supported by the $protocol pipeline template."
    }

    if (
        $hasAudio -and
        -not (Test-AudioCodecProtocolCompatibility `
            -AudioCodecName $audioCodecName `
            -Protocol $protocol)
    ) {
        throw "$audioCodecName is not supported by the $protocol pipeline template."
    }

    switch ($protocol) {
        'WHIP' {
            $timestampOption = Get-AbsoluteTimestampTransportOption -Protocol $protocol
            $timestampOption = if ([string]::IsNullOrWhiteSpace($timestampOption)) { '' } else { " $timestampOption" }
            $recoveryFlags = Get-WebRtcRecoveryFlags
            $congestion = Get-ComboSelectedOrDefault $cmbDirectWebRtcCongestion 'gcc'
            $mitigation = Get-ComboSelectedOrDefault $cmbDirectWebRtcMitigation 'none'
            $stunServer = $txtDirectWebRtcStun.Text.Trim()
            $stunOption = if ([string]::IsNullOrWhiteSpace($stunServer)) { '' } else { ' stun-server=' + (Quote-GstValue $stunServer) }
    $turnOption = Get-DirectWebRtcTurnOption
            $bitrateEnvelope = Get-DirectWebRtcVideoBitrateEnvelope
            $minBitrate = [int64]$bitrateEnvelope.MinBitrate
            $startBitrate = [int64]$bitrateEnvelope.StartBitrate
            $maxBitrate = [int64]$bitrateEnvelope.MaxBitrate
            $webRtcSinkOptions = " do-fec=$([string]$recoveryFlags.Fec) do-retransmission=$([string]$recoveryFlags.Retransmission) congestion-control=$congestion enable-mitigation-modes=$mitigation min-bitrate=$minBitrate start-bitrate=$startBitrate max-bitrate=$maxBitrate"
            $mediaStreamPadOptions = Get-WebRtcMediaStreamPadOptions -HasAudio $hasAudio
            $webRtcMediaStreamOptions = if ($mediaStreamPadOptions.Count -gt 0) { ' ' + ($mediaStreamPadOptions -join ' ') } else { '' }
            $webRtcVideoQueue = Get-DirectWebRtcPacingQueue

            if ($hasAudio) {
                $pipeline = "whipclientsink name=out video-caps=`"$mediaType`" audio-caps=`"$audioMediaType`"$webRtcMediaStreamOptions$timestampOption$webRtcSinkOptions$stunOption$turnOption signaller::whip-endpoint=$quotedDestination $video$videoSyncSuffix ! $webRtcVideoQueue ! out.video_0 $audioRaw ! $audioEncoded ! $(Get-AudioFinalQueue)$audioSyncSuffix ! out.audio_0"
            }
            else {
                $pipeline = "$video$videoSyncSuffix ! $webRtcVideoQueue ! whipclientsink video-caps=`"$mediaType`"$webRtcMediaStreamOptions$timestampOption$webRtcSinkOptions$stunOption$turnOption signaller::whip-endpoint=$quotedDestination"
            }
        }

        'GST WebRTC' {
            $timestampOption = Get-AbsoluteTimestampTransportOption -Protocol $protocol -SinkRole Video
            $timestampOption = if ([string]::IsNullOrWhiteSpace($timestampOption)) { '' } else { " $timestampOption" }

            $webAddress = Quote-GstValue (Normalize-DirectWebRtcWebAddress $destination)
            $webPathSegment = Get-DirectWebRtcWebServerPathSegment
            $webPathOption = if ([string]::IsNullOrWhiteSpace($webPathSegment)) { '' } else { ' web-server-path=' + (Quote-GstValue $webPathSegment) }
            $webDirectory = Get-DirectWebRtcWebDirectory
            $webDirectoryOption = if ([string]::IsNullOrWhiteSpace($webDirectory)) { '' } else { ' web-server-directory=' + (Quote-GstValue $webDirectory) }
            $signalHost = $txtDirectWebRtcSignalingHost.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($signalHost)) {
                $signalHost = $script:DefaultDirectWebRtcSignalingHost
            }
            $signalHost = Quote-GstValue $signalHost
            $signalPort = [int]$numDirectWebRtcSignalingPort.Value
            $stunServer = $txtDirectWebRtcStun.Text.Trim()
            $stunOption = if ([string]::IsNullOrWhiteSpace($stunServer)) { '' } else { ' stun-server=' + (Quote-GstValue $stunServer) }
    $turnOption = Get-DirectWebRtcTurnOption
            $congestion = Get-ComboSelectedOrDefault $cmbDirectWebRtcCongestion 'gcc'
            $mitigation = Get-ComboSelectedOrDefault $cmbDirectWebRtcMitigation 'none'
            $recoveryFlags = Get-WebRtcRecoveryFlags
            $fec = [string]$recoveryFlags.Fec
            $retx = [string]$recoveryFlags.Retransmission
            $bitrateEnvelope = Get-DirectWebRtcVideoBitrateEnvelope
            $startBitrate = [int64]$bitrateEnvelope.StartBitrate
            $maxBitrate = [int64]$bitrateEnvelope.MaxBitrate
            $minBitrate = [int64]$bitrateEnvelope.MinBitrate

            # Feed our explicit encoded branch into webrtcsink. The raw D3D11
            # experiment could start the web/signalling server, but this package
            # failed stream discovery with "No codec present" for video_0. The
            # encoded path keeps our tested NVENC/QSV/software encoder controls
            # while still bypassing MediaMTX for WebRTC signalling/delivery.
            $directVideo = Build-DirectWebRtcEncodedVideoBranch

            $sinkProps = @(
                'webrtcsink',
                'name=out',
                "video-caps=`"$mediaType`"",
                "audio-caps=`"audio/x-opus`"",
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
                "max-bitrate=$maxBitrate"
            )
            $sinkProps += Get-WebRtcMediaStreamPadOptions -HasAudio $hasAudio
            if ((Test-DirectWebRtcSplitAvPipelines) -and (Test-DirectWebRtcSharedSignaling)) {
                $sinkProps += 'meta="meta,name=gstglass-video,kind=video"'
            }

            $pipeline = (($sinkProps -join ' ') + $timestampOption + $stunOption + $turnOption + $webPathOption + $webDirectoryOption + " $directVideo")
            if ($hasAudio -and (Test-DirectWebRtcSplitAvPipelines)) {
                # Split A/V diagnostic: keep this gst-launch instance video-only.
                # Start-GstStream launches a second audio-only webrtcsink. It either
                # owns the configured audio signalling port or joins the video server.
            }
            elseif ($hasAudio) {
                $directOpusMode = Get-ComboSelectedOrDefault $cmbDirectWebRtcOpusMode $script:DefaultDirectWebRtcOpusMode
                if ($directOpusMode -eq 'Raw audio to webrtcsink') {
                    # Diagnostic escape hatch: hand raw S16LE to webrtcsink and let
                    # its internal child encoder do whatever this GStreamer build defaults to.
                    $pipeline += " $audioRaw ! $(Get-AudioFinalQueue)$audioSyncSuffix ! out.audio_0"
                }
                else {
                    # Explicit Direct GST WebRTC Opus branch. This keeps opusenc
                    # frame-size/audio-type/FEC/DTX visible in the command preview
                    # instead of hiding defaults inside webrtcsink.
                    $directOpusBitrate = [int]$numAudioBitrate.Value * 1000
                    $directOpusFrameMs = Get-ComboSelectedOrDefault $cmbDirectWebRtcOpusFrameMs $script:DefaultDirectWebRtcOpusFrameMs
                    $directOpusAudioType = Get-ComboSelectedOrDefault $cmbDirectWebRtcOpusAudioType $script:DefaultDirectWebRtcOpusAudioType
                    $directOpusFec = if ($chkDirectWebRtcOpusFec.Checked) { 'true' } else { 'false' }
                    $directOpusDtx = if ($chkDirectWebRtcOpusDtx.Checked) { 'true' } else { 'false' }
                    $directOpus = "opusenc bitrate=$directOpusBitrate bitrate-type=cbr frame-size=$directOpusFrameMs audio-type=$directOpusAudioType inband-fec=$directOpusFec dtx=$directOpusDtx ! opusparse ! `"audio/x-opus`""
                    $pipeline += " $audioRaw ! $directOpus ! $(Get-AudioFinalQueue)$audioSyncSuffix ! out.audio_0"
                }
            }
        }

        'SRT' {
            # Known-good MediaMTX SRT -> WebRTC shape:
            # - Opus survives SRT ingest and WebRTC egress.
            # - AAC is valid in MPEG-TS, but MediaMTX WebRTC readers skip
            #   MPEG-4 Audio.
            # - 2.9 ms aggregator latency avoids the one-track PMT race
            #   without adding the huge delay of the diagnostic 1s value.
            # - srtsink latency is intentionally omitted.
            $programMap = if ($hasAudio) {
                'prog-map="program_map,sink_256=1,sink_257=1"'
            }
            else {
                'prog-map="program_map,sink_256=1"'
            }

            $destination = $quotedDestination
            if ($destination -notmatch 'pkt_size=') {
                $joiner = if ($destination -match '\?') { '&' } else { '?' }
                $destination =
                    $destination.TrimEnd('"') +
                    "$joiner" +
                    'pkt_size=1316"'
            }

            $pipeline =
                "mpegtsmux name=mux alignment=7 " +
                "latency=2900000 " +
                "min-upstream-latency=2900000 " +
                "pat-interval=600 pmt-interval=600 " +
                "$programMap " +
                "! srtsink uri=$destination " +
                "wait-for-connection=true auto-reconnect=true " +
                "$video$videoSyncSuffix ! mux.sink_256"

            if ($hasAudio) {
                $pipeline +=
                    " $audioRaw ! $audioEncoded$audioSyncSuffix ! mux.sink_257"
            }
        }

        'RTMP' {
            if ($codec -eq 'H264') {
                $pipeline = "flvmux name=mux streamable=true ! rtmp2sink location=$quotedDestination async-connect=true $video$videoSyncSuffix ! mux."
                if ($hasAudio) {
                    $pipeline += " $audioRaw ! $audioEncoded$audioSyncSuffix ! mux."
                }
            }
            else {
                $pipeline = "eflvmux name=mux streamable=true ! rtmp2sink location=$quotedDestination async-connect=true $video$videoSyncSuffix ! mux.video"
                if ($hasAudio) {
                    $pipeline += " $audioRaw ! $audioEncoded$audioSyncSuffix ! mux.audio"
                }
            }
        }

        'RTSP' {
            $transport = if ([string]$cmbRtspTransport.SelectedItem -eq 'UDP') {
                'udp'
            }
            else {
                'tcp'
            }
            $timestampOption = Get-AbsoluteTimestampTransportOption -Protocol $protocol
            $timestampOption = if ([string]::IsNullOrWhiteSpace($timestampOption)) { '' } else { " $timestampOption" }
            $pipeline = "rtspclientsink name=out location=$quotedDestination protocols=$transport latency=0 rtx-time=0$timestampOption $video$videoSyncSuffix ! out.sink_0"
            if ($hasAudio) {
                $pipeline += " $audioRaw ! $audioEncoded$audioSyncSuffix ! out.sink_1"
            }
        }

        default {
            throw "Unsupported protocol: $protocol"
        }
    }

    if (Test-RecordingEnabled) {
        $recordingAudioBranch = Build-RecordingAudioBranch
        if (-not [string]::IsNullOrWhiteSpace($recordingAudioBranch)) {
            $pipeline += " $recordingAudioBranch"
        }
    }

    $pipeline = Wrap-GstPipelineWithClockSelect -Pipeline $pipeline -ClockMode (Get-VideoPipelineClockMode)

    $flags = '-e'
    if ($chkVerbose.Checked) {
        $flags += ' -v'
    }

    return "$flags $pipeline"
}

function Convert-GstArgumentsToPowerShellPreview {
    param([Parameter(Mandatory)][string]$Arguments)

    # Start-Process passes clockselect parentheses directly to gst-launch. In the
    # copyable PowerShell preview, quote only the outer wrapper parentheses so
    # PowerShell does not treat them as expression syntax. Do not touch caps such
    # as video/x-raw(memory:D3D11Memory).
    if ($Arguments -notmatch 'clockselect\.\s+\(') { return $Arguments }

    $preview = [regex]::Replace($Arguments, 'clockselect\.\s+\(', 'clockselect. "("', 1)
    $lastClose = $preview.LastIndexOf(')')
    if ($lastClose -ge 0) {
        $preview = $preview.Substring(0, $lastClose) + '")"' + $preview.Substring($lastClose + 1)
    }
    return $preview
}

function Update-CommandPreview {
    $originalRecordingRequest = [bool]$script:RecordingPipelineRequested
    try {
        $pipelineRunning = $script:GstProcess -and -not $script:GstProcess.HasExited
        if (-not $pipelineRunning) {
            # The command pane describes the normal Start/Go Live action. Manual
            # recording-only runs are launched by the dedicated button.
            $script:RecordingPipelineRequested = [bool](
                $chkRecordingEnabled -and
                $chkRecordingEnabled.Checked -and
                $chkRecordWithStream -and
                $chkRecordWithStream.Checked -and
                ((-not $chkTransportEnabled) -or $chkTransportEnabled.Checked)
            )
        }

        $gstPath = $txtGstPath.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($gstPath)) {
            $gstPath = 'gst-launch-1.0.exe'
        }

        $customGstArgumentsEnabled = Test-CustomGstArgumentsOverride
        $mainArguments = if ($customGstArgumentsEnabled) { Get-CustomGstArguments } else { Build-GstArguments }
        $previewMainArguments = Convert-GstArgumentsToPowerShellPreview -Arguments $mainArguments
        $previewText = '& ' + (Quote-GstValue $gstPath) + ' ' + $previewMainArguments

        if ($customGstArgumentsEnabled) {
            $previewText = "# CUSTOM GST-LAUNCH ARGS OVERRIDE ACTIVE`r`n# Start/Go Live will bypass the UI pipeline builder and run only these args.`r`n" + $previewText
        }

        if ((-not $customGstArgumentsEnabled) -and (Test-TransportEnabled) -and [string]$cmbProtocol.SelectedItem -eq $script:DirectWebRtcProtocolName -and (Test-DirectWebRtcSplitAvPipelines)) {
            if (Test-DirectWebRtcUnifiedPublisher) {
                $videoArguments = Build-DirectWebRtcUnifiedVideoBridgeArguments
                $audioArguments = Build-DirectWebRtcAudioOnlyArguments
                $previewText = "# Unified WebRTC publisher - one producer / video_0 + audio_0`r`n" + $previewText
                $previewText += "`r`n`r`n# Split video capture -> localhost RTP bridge port $([int]$numDirectWebRtcBridgeVideoPort.Value)"
                $previewVideoArguments = Convert-GstArgumentsToPowerShellPreview -Arguments $videoArguments
                $previewText += "`r`n" + '& ' + (Quote-GstValue $gstPath) + ' ' + $previewVideoArguments
                $previewText += "`r`n`r`n# Split audio capture -> localhost RTP bridge port $([int]$numDirectWebRtcBridgeAudioPort.Value)"
                if ([string]::IsNullOrWhiteSpace($audioArguments)) {
                    $previewText += "`r`n# Unified audio bridge unavailable: enable Normal audio, Desktop/Mic audio, and Explicit Opus encoder mode."
                }
                else {
                    $previewAudioArguments = Convert-GstArgumentsToPowerShellPreview -Arguments $audioArguments
                    $previewText += "`r`n" + '& ' + (Quote-GstValue $gstPath) + ' ' + $previewAudioArguments
                }
            }
            else {
                $audioArguments = Build-DirectWebRtcAudioOnlyArguments
                $previewText += "`r`n`r`n# Split audio pipeline - separate gst-launch / $(if (Test-DirectWebRtcSharedSignaling) { 'shared signalling server' } else { 'signalling port ' + (Get-DirectWebRtcSplitAudioSignalingPort) })"
                if ([string]::IsNullOrWhiteSpace($audioArguments)) {
                    $previewText += "`r`n# Split audio command unavailable: enable Normal audio and Desktop/Mic audio."
                }
                else {
                    $previewAudioArguments = Convert-GstArgumentsToPowerShellPreview -Arguments $audioArguments
                    $previewText += "`r`n" + '& ' + (Quote-GstValue $gstPath) + ' ' + $previewAudioArguments
                }
            }
        }

        $txtCommand.Text = $previewText
        $script:RecordingPipelineRequested = $originalRecordingRequest
    }
    catch {
        $script:RecordingPipelineRequested = $originalRecordingRequest
        $txtCommand.Text = "Unable to build command: $($_.Exception.Message)"
    }
}

function Update-ProtocolUi {
    $protocol = [string]$cmbProtocol.SelectedItem
    if ([string]::IsNullOrWhiteSpace($protocol)) {
        return
    }

    if (-not $script:SuppressProtocolChange) {
        if ($script:LastProtocol -and -not [string]::IsNullOrWhiteSpace($txtDestination.Text)) {
            $script:ProtocolDestinations[$script:LastProtocol] = $txtDestination.Text.Trim()
        }

        $currentAudioCodec = [string]$cmbAudioCodec.SelectedItem
        if (
            $script:LastProtocol -and
            -not [string]::IsNullOrWhiteSpace($currentAudioCodec) -and
            (Test-AudioCodecProtocolCompatibility `
                -AudioCodecName $currentAudioCodec `
                -Protocol $script:LastProtocol)
        ) {
            $script:ProtocolAudioCodecs[$script:LastProtocol] = $currentAudioCodec
        }

        $txtDestination.Text = [string]$script:ProtocolDestinations[$protocol]
    }

    $script:LastProtocol = $protocol
    $transportEnabled = Test-TransportEnabled
    $cmbProtocol.Enabled = $transportEnabled
    $txtDestination.Enabled = $transportEnabled
    $lblDestination.Enabled = $transportEnabled
    $lblDestination.Text = if ($protocol -eq $script:DirectWebRtcProtocolName) { 'Web viewer bind URL' } else { "$protocol destination" }
    $numSrtLatency.Enabled = $transportEnabled -and ($protocol -eq 'SRT')
    $cmbRtspTransport.Enabled = $transportEnabled -and ($protocol -eq 'RTSP')
    Update-TimestampUi
    Update-MediaMtxUi
    Update-DirectWebRtcUi

    switch ($protocol) {
        'WHIP' { $toolTip.SetToolTip($txtDestination, 'Example: http://server:8889/live/whip') }
        'GST WebRTC' { $toolTip.SetToolTip($txtDestination, 'GStreamer webrtcsink web server bind address. Default mirrors MediaMTX WebRTC HTTP: http://0.0.0.0:8889/') }
        'SRT'  { $toolTip.SetToolTip($txtDestination, 'Example: srt://server:8890?mode=caller&streamid=publish:live') }
        'RTMP' { $toolTip.SetToolTip($txtDestination, 'Example: rtmp://server/live') }
        'RTSP' { $toolTip.SetToolTip($txtDestination, 'Example: rtsp://server:8554/live') }
    }

    Update-AudioCodecChoices
    Update-AudioTimingOptionUi
    Update-EncoderUi
}

