# Module: 22-Encoding.ps1 (auto-extracted by tools/Split-Monolith.ps1 -- edit here, then run tools/Build-Monolith.ps1)

function Get-SelectedEncoderDefinition {
    $name = [string]$cmbEncoder.SelectedItem
    if (
        [string]::IsNullOrWhiteSpace($name) -or
        -not $script:EncoderCatalog.Contains($name)
    ) {
        $name = $script:DefaultEncoderName
    }

    return $script:EncoderCatalog[$name]
}

function Get-SelectedAudioCodecDefinition {
    $name = [string]$cmbAudioCodec.SelectedItem
    if (
        [string]::IsNullOrWhiteSpace($name) -or
        -not $script:AudioCodecCatalog.Contains($name)
    ) {
        $protocol = [string]$cmbProtocol.SelectedItem
        $name = [string]$script:DefaultAudioCodecByProtocol[$protocol]
    }

    return $script:AudioCodecCatalog[$name]
}

function Test-AudioCodecProtocolCompatibility {
    param(
        [Parameter(Mandatory)][string]$AudioCodecName,
        [Parameter(Mandatory)][string]$Protocol
    )

    if (-not $script:AudioCodecCatalog.Contains($AudioCodecName)) {
        return $false
    }

    return $Protocol -in @($script:AudioCodecCatalog[$AudioCodecName].Protocols)
}

function Get-CompatibleAudioCodecNames {
    param([Parameter(Mandatory)][string]$Protocol)

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($name in $script:AudioCodecCatalog.Keys) {
        if (Test-AudioCodecProtocolCompatibility -AudioCodecName $name -Protocol $Protocol) {
            $names.Add([string]$name)
        }
    }

    return @($names)
}

function Update-AudioCodecChoices {
    param([switch]$PreserveCurrent)

    $protocol = [string]$cmbProtocol.SelectedItem
    if ([string]::IsNullOrWhiteSpace($protocol)) {
        return
    }

    $current = [string]$cmbAudioCodec.SelectedItem
    if (
        $PreserveCurrent -and
        -not [string]::IsNullOrWhiteSpace($current) -and
        (Test-AudioCodecProtocolCompatibility -AudioCodecName $current -Protocol $protocol)
    ) {
        $script:ProtocolAudioCodecs[$protocol] = $current
    }

    $desired = [string]$script:ProtocolAudioCodecs[$protocol]
    $compatible = Get-CompatibleAudioCodecNames -Protocol $protocol

    if ($desired -notin $compatible) {
        $desired = [string]$script:DefaultAudioCodecByProtocol[$protocol]
    }

    $script:SuppressAudioCodecChange = $true
    try {
        $cmbAudioCodec.BeginUpdate()
        $cmbAudioCodec.Items.Clear()
        foreach ($name in $compatible) {
            $null = $cmbAudioCodec.Items.Add($name)
        }

        if ($cmbAudioCodec.Items.Contains($desired)) {
            $cmbAudioCodec.SelectedItem = $desired
        }
        elseif ($cmbAudioCodec.Items.Count -gt 0) {
            $cmbAudioCodec.SelectedIndex = 0
        }
    }
    finally {
        $cmbAudioCodec.EndUpdate()
        $script:SuppressAudioCodecChange = $false
    }

    $selected = [string]$cmbAudioCodec.SelectedItem
    if ($selected) {
        $script:ProtocolAudioCodecs[$protocol] = $selected
        $audioMode = Get-ComboSelectedOrDefault $cmbAudioTransportMode $script:DefaultAudioTransportMode
        $audioTimingMode = Get-AudioTimingMode
        if ($audioMode -eq 'Video only - no audio track') {
            $lblAudioCodecStatus.Text = "$protocol * video-only diagnostic"
            $lblAudioCodecStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        elseif ($audioTimingMode -eq 'Synthetic silent audio') {
            $lblAudioCodecStatus.Text = "$protocol * synthetic silent Opus timing diagnostic"
            $lblAudioCodecStatus.ForeColor = [System.Drawing.Color]::DarkSlateBlue
        }
        elseif ($audioMode -eq 'Muted audio clock only') {
            $lblAudioCodecStatus.Text = "$protocol * muted Opus clock diagnostic"
            $lblAudioCodecStatus.ForeColor = [System.Drawing.Color]::DarkSlateBlue
        }
        elseif (
            $protocol -in @('WHIP', 'GST WebRTC') -and
            -not $chkDesktopAudio.Checked -and
            -not $chkMic.Checked
        ) {
            $lblAudioCodecStatus.Text = "$protocol * muted Opus clock track (automatic)"
            $lblAudioCodecStatus.ForeColor = [System.Drawing.Color]::DarkSlateBlue
        }
        else {
            $lblAudioCodecStatus.Text =
                "$protocol compatible * $([string]$script:AudioCodecCatalog[$selected].Codec)"
            $lblAudioCodecStatus.ForeColor = [System.Drawing.Color]::DimGray
        }
    }

    if ($cmbDesktopAudioDevice) { $cmbDesktopAudioDevice.Enabled = $chkDesktopAudio.Checked }
    if ($chkAudioMixerMode) {
        $chkAudioMixerMode.Enabled = $chkDesktopAudio.Checked
        if ($chkDesktopAudio.Checked -and $chkMic.Checked) {
            $toolTip.SetToolTip($chkAudioMixerMode, 'Desktop + microphone requires audiomixer to combine both sources. This flag controls desktop-only mixer normalization versus the legacy direct path.')
        }
        else {
            $toolTip.SetToolTip($chkAudioMixerMode, 'Recommended timing-normalization path. When enabled, desktop-only audio is routed through audiomixer before encoding. Uncheck to restore the legacy direct WASAPI-to-encoder path.')
        }
    }
    if ($cmbMicAudioDevice) { $cmbMicAudioDevice.Enabled = $chkMic.Checked }

    Update-CommandPreview
}

function Get-EncoderControlSupport {
    $definition = Get-SelectedEncoderDefinition
    $family = [string]$definition.Family
    $codec = [string]$definition.Codec

    $supportsBFrames = $false
    $supportsLookAhead = $false
    $supportsAq = $false

    switch ($family) {
        'NVENC' {
            $supportsBFrames = $true
            $supportsLookAhead = $true
            $supportsAq = $true
        }
        'AMF' {
            $supportsBFrames = ($codec -eq 'H264')
            $supportsLookAhead = ($codec -in @('H264', 'H265'))
        }
        'QSV' {
            $supportsBFrames = ($codec -in @('H264', 'H265'))
            $supportsLookAhead = ($codec -in @('H264', 'H265'))
        }
        'MF' {
            $supportsBFrames = ($codec -in @('H264', 'H265'))
        }
        'X264' {
            $supportsBFrames = $true
            $supportsLookAhead = $true
            $supportsAq = $true
        }
        'X265' {
            $supportsBFrames = $true
            $supportsLookAhead = $true
            $supportsAq = $true
        }
        'AOM' { $supportsLookAhead = $true }
        'RAV1E' { $supportsLookAhead = $true }
        'VPX' { $supportsLookAhead = $true }
    }

    return [pscustomobject]@{
        BFrames = $supportsBFrames
        LookAhead = $supportsLookAhead
        AdaptiveQuantization = $supportsAq
    }
}

function Get-AudioEncoderChain {
    param([Parameter(Mandatory)][string]$Protocol)

    $definition = Get-SelectedAudioCodecDefinition
    $family = [string]$definition.Family
    $bitrateKbps = [int]$numAudioBitrate.Value
    $bitrateBps = $bitrateKbps * 1000

    switch ($family) {
        'OPUS' {
            return "opusenc bitrate=$bitrateBps bitrate-type=cbr frame-size=10 audio-type=restricted-lowdelay ! `"audio/x-opus`""
        }
        'AAC_MF' {
            $aacBitrate = Get-NearestAacBitrate -RequestedKbps $bitrateKbps
            $format = if ($Protocol -eq 'SRT') { 'adts' } else { 'raw' }
            return "mfaacenc bitrate=$aacBitrate ! aacparse ! `"audio/mpeg,mpegversion=4,stream-format=$format,framed=true`""
        }
        'AAC_FDK' {
            $format = if ($Protocol -eq 'SRT') { 'adts' } else { 'raw' }
            return "fdkaacenc bitrate=$bitrateBps rate-control=cbr ! aacparse ! `"audio/mpeg,mpegversion=4,stream-format=$format,framed=true`""
        }
        'AAC_LIBAV' {
            $format = if ($Protocol -eq 'SRT') { 'adts' } else { 'raw' }
            return "audioconvert ! $(Get-AudioRawCapsString -Format 'F32LE' -Channels 2) ! avenc_aac bitrate=$bitrateBps ! aacparse ! `"audio/mpeg,mpegversion=4,stream-format=$format,framed=true`""
        }
        'AAC_VO' {
            $format = if ($Protocol -eq 'SRT') { 'adts' } else { 'raw' }
            return "voaacenc bitrate=$bitrateBps ! aacparse ! `"audio/mpeg,mpegversion=4,stream-format=$format`""
        }
        'MP3' {
            $valid = @(32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320)
            $mp3Bitrate = [int](
                $valid |
                Sort-Object { [Math]::Abs($_ - $bitrateKbps) } |
                Select-Object -First 1
            )
            return "lamemp3enc target=bitrate cbr=true bitrate=$mp3Bitrate encoding-engine-quality=fast ! mpegaudioparse ! `"audio/mpeg,mpegversion=1,layer=3,parsed=true`""
        }
        'AC3' {
            return "audioconvert ! $(Get-AudioRawCapsString -Format 'F32LE' -Channels 2) ! avenc_ac3 bitrate=$bitrateBps ! ac3parse ! `"audio/x-ac3,framed=true`""
        }
        default {
            throw "Unsupported audio encoder family: $family"
        }
    }
}

function Test-CodecProtocolCompatibility {
    param(
        [Parameter(Mandatory)][string]$Codec,
        [Parameter(Mandatory)][string]$Protocol
    )

    switch ($Protocol) {
        'WHIP' { return $Codec -in @('H264', 'H265', 'AV1', 'VP8', 'VP9') }
        'GST WebRTC' { return $Codec -in @('H264', 'H265', 'AV1', 'VP8', 'VP9') }
        'SRT'  { return $Codec -in @('H264', 'H265', 'AV1', 'VP9') }
        'RTMP' { return $Codec -in @('H264', 'H265', 'AV1') }
        'RTSP' { return $Codec -in @('H264', 'H265', 'AV1', 'VP8', 'VP9') }
        default { return $false }
    }
}

function Get-CodecMediaType {
    param([Parameter(Mandatory)][string]$Codec)

    switch ($Codec) {
        'H264' { return 'video/x-h264' }
        'H265' { return 'video/x-h265' }
        'AV1'  { return 'video/x-av1' }
        'VP8'  { return 'video/x-vp8' }
        'VP9'  { return 'video/x-vp9' }
        default { throw "Unsupported codec: $Codec" }
    }
}

function Get-EncodedVideoCaps {
    param(
        [Parameter(Mandatory)][string]$Codec,
        [Parameter(Mandatory)][string]$Protocol
    )

    $profile = [string]$cmbProfile.SelectedItem

    switch ($Codec) {
        'H264' {
            $streamFormat = if ($Protocol -eq 'RTMP') { 'avc' } else { 'byte-stream' }
            if ($Protocol -eq 'WHIP') {
                # WHIP/WHEP/browser compatibility guard. A saved High profile
                # setting can make MediaMTX/WHIP sessions look like they never
                # publish or never become readable, especially after switching
                # between Direct GST WebRTC experiments and MediaMTX ingest.
                # Keep the UI profile for other protocols, but publish WHIP as
                # constrained-baseline unless/until we add a dedicated advanced
                # WHIP override.
                $profile = 'constrained-baseline'
            }
            return "video/x-h264,profile=$profile,stream-format=$streamFormat,alignment=au"
        }
        'H265' {
            $streamFormat = if ($Protocol -eq 'RTMP') { 'hvc1' } else { 'byte-stream' }
            return "video/x-h265,profile=main,stream-format=$streamFormat,alignment=au"
        }
        'AV1' {
            $alignment = if ($Protocol -eq 'SRT') { 'frame' } else { 'tu' }
            if ($Protocol -in @('GST WebRTC', 'WHIP')) {
                # Keep AV1 caps intentionally minimal for rswebrtc/webrtcsink.
                # The stricter caps pinned chroma-format and bit-depth, but the
                # GStreamer 1.28.5 rswebrtc path rejected that downstream handoff
                # with not-negotiated before out.video_0 accepted the caps.
                # profile=main avoids the earliest generic caps while still
                # allowing the WebRTC sink to negotiate the RTP payload.
                return "video/x-av1,stream-format=obu-stream,alignment=$alignment,profile=main"
            }
            return "video/x-av1,stream-format=obu-stream,alignment=$alignment"
        }
        'VP8' { return 'video/x-vp8' }
        'VP9' { return 'video/x-vp9' }
        default { throw "Unsupported codec: $Codec" }
    }
}

function Get-EncoderElementChain {
    param([Parameter(Mandatory)][string]$Protocol)

    $definition = Get-SelectedEncoderDefinition
    $element = [string]$definition.Element
    $codec = [string]$definition.Codec
    $family = [string]$definition.Family
    $inputType = [string]$definition.Input
    $parser = [string]$definition.Parser

    $width = [int]$numWidth.Value
    $height = [int]$numHeight.Value
    $fps = [int]$numFps.Value
    $videoBitrateKbps = [int]$numVideoBitrate.Value
    $videoBitrateBps = $videoBitrateKbps * 1000
    $maxVideoBitrateKbps = [int]$numMaxVideoBitrate.Value
    $constantQp = [int]$numConstantQp.Value
    $gopSize = [Math]::Max(1, $fps * [int]$numGopSeconds.Value)
    if (
        (Test-DirectWebRtcUnifiedPublisher) -and
        $codec -in @('H264','H265') -and
        $chkUnifiedBridgeKeyframeGuard.Checked
    ) {
        $bridgeKeyframeMs = [int]$numUnifiedBridgeKeyframeIntervalMs.Value
        $gopSize = [Math]::Max(1, [int][Math]::Ceiling(($fps * $bridgeKeyframeMs) / 1000.0))
    }
    $preset = [string]$cmbPreset.SelectedItem
    $rateControl = Get-ComboSelectedOrDefault $cmbRateControl 'cbr'
    $tune = Get-ComboSelectedOrDefault $cmbEncoderTune 'ultra-low-latency'
    $multipass = Get-ComboSelectedOrDefault $cmbMultipass 'disabled'
    $controlSupport = Get-EncoderControlSupport
    $bFrames = if ($controlSupport.BFrames) { [int]$numBFrames.Value } else { 0 }
    $lookAheadFrames = if (
        $controlSupport.LookAhead -and
        $chkLookAhead.Checked
    ) {
        [int]$numLookAheadFrames.Value
    }
    else {
        0
    }
    $spatialAq = $controlSupport.AdaptiveQuantization -and $chkAdaptiveQuantization.Checked
    $temporalAq = $controlSupport.AdaptiveQuantization -and $chkTemporalAq.Checked
    $aqEnabled = $spatialAq -or $temporalAq
    $aqStrength = [int]$numAqStrength.Value
    $vbvBuffer = [int]$numVbvBuffer.Value
    $aqStrengthFloat = ($aqStrength / 8.0).ToString(
        '0.###',
        [System.Globalization.CultureInfo]::InvariantCulture
    )
    $cpuWorkers = Get-CpuWorkerLimit

    if ($Protocol -eq 'WHIP') {
        # WHIP publish guard:
        # - WebRTC readers expect frequent keyframes; saved 10s GOP / 120 fps
        #   settings can make publishing appear broken or make readers wait too
        #   long for a usable IDR.
        # - B-frames/lookahead add reordering delay and have previously caused
        #   MediaMTX/WebRTC problems in this project.
        # - NVENC default/high-quality tune was observed as choppier than
        #   ultra-low-latency here, so WHIP stays on the proven ULL path.
        $gopSize = [Math]::Min($gopSize, [Math]::Max(1, $fps))
        $bFrames = 0
        $lookAheadFrames = 0
        $spatialAq = $false
        $temporalAq = $false
        $aqEnabled = $false
        if ($family -eq 'NVENC') {
            $tune = 'ultra-low-latency'
            $multipass = 'disabled'
        }
    }

    $parts = New-Object System.Collections.Generic.List[string]

    $parts.Add((Get-CaptureEncoderQueue))
    $parts.Add('!')

    if ($inputType -eq 'I420') {
        $parts.Add('d3d11download')
        $parts.Add('!')
        $parts.Add($(if ($cpuWorkers -gt 0) { "videoconvert n-threads=$cpuWorkers" } else { 'videoconvert' }))
        $parts.Add('!')
        $parts.Add(
            "`"video/x-raw,format=I420,width=$width,height=$height,framerate=$fps/1`""
        )
        $parts.Add('!')
    }

    $parts.Add($element)

    switch ($family) {
        'NVENC' {
            $zeroLatency = ($bFrames -eq 0 -and $lookAheadFrames -eq 0 -and $tune -in @('low-latency','ultra-low-latency'))
            Add-NvencRateControlOptions $parts $rateControl $videoBitrateKbps $maxVideoBitrateKbps $constantQp
            $parts.Add("preset=$preset")
            $parts.Add("tune=$tune")
            $parts.Add("multi-pass=$multipass")
            $parts.Add("zerolatency=$($zeroLatency.ToString().ToLowerInvariant())")
            $parts.Add("bframes=$bFrames")
            $parts.Add(
                "b-adapt=$((($bFrames -gt 0) -and ($lookAheadFrames -gt 0)).ToString().ToLowerInvariant())"
            )
            $parts.Add("gop-size=$gopSize")
            $parts.Add("rc-lookahead=$lookAheadFrames")
            $parts.Add("spatial-aq=$($spatialAq.ToString().ToLowerInvariant())")
            $parts.Add("temporal-aq=$($temporalAq.ToString().ToLowerInvariant())")
            if ($aqEnabled) { $parts.Add("aq-strength=$aqStrength") }
            if ($vbvBuffer -gt 0) { $parts.Add("vbv-buffer-size=$vbvBuffer") }
            if ($codec -in @('H264', 'H265')) {
                $parts.Add('repeat-sequence-header=true')
            }
        }
        'AMF' {
            $parts.Add("bitrate=$videoBitrateKbps")
            $parts.Add('rate-control=cbr')
            $parts.Add('preset=speed')
            $parts.Add(
                $(if ($codec -eq 'AV1') {
                    'usage=low-latency'
                }
                else {
                    'usage=ultra-low-latency'
                })
            )
            $parts.Add("gop-size=$gopSize")
            $parts.Add(
                "pre-analysis=$((($lookAheadFrames -gt 0)).ToString().ToLowerInvariant())"
            )
            $parts.Add('pre-encode=false')
            if ($codec -eq 'H264') {
                $parts.Add("b-frames=$bFrames")
                $parts.Add("max-b-frames=$bFrames")
                $parts.Add(
                    "adaptive-mini-gop=$((($bFrames -gt 0) -and ($lookAheadFrames -gt 0)).ToString().ToLowerInvariant())"
                )
            }
            if ($lookAheadFrames -gt 0 -and $codec -in @('H264', 'H265')) {
                $parts.Add("pa-lookahead-buffer-depth=$lookAheadFrames")
            }
        }
        'QSV' {
            Add-QsvRateControlOptions $parts $rateControl $videoBitrateKbps $maxVideoBitrateKbps $constantQp $lookAheadFrames $codec
            $parts.Add("gop-size=$gopSize")
            if ($codec -in @('H264', 'H265')) {
                $parts.Add("b-frames=$bFrames")
            }
        }
        'MF' {
            $parts.Add("bitrate=$videoBitrateKbps")
            $parts.Add('rc-mode=cbr')
            $parts.Add("gop-size=$gopSize")
            $parts.Add('low-latency=true')
            if ($controlSupport.BFrames) {
                $parts.Add("bframes=$bFrames")
            }
        }
        'X264' {
            if ($rateControl -eq 'constqp') { $parts.Add('pass=quant'); $parts.Add("quantizer=$constantQp") } else { $parts.Add("bitrate=$videoBitrateKbps") }
            $parts.Add('speed-preset=ultrafast')
            if ($tune -in @('low-latency','ultra-low-latency')) { $parts.Add('tune=zerolatency') }
            $parts.Add("key-int-max=$gopSize")
            $parts.Add("bframes=$bFrames")
            $parts.Add(
                "b-adapt=$((($bFrames -gt 0) -and ($lookAheadFrames -gt 0)).ToString().ToLowerInvariant())"
            )
            $parts.Add("rc-lookahead=$lookAheadFrames")
            $parts.Add('sync-lookahead=0')
            $parts.Add("mb-tree=$($aqEnabled.ToString().ToLowerInvariant())")
            $x264AqOptions = if ($aqEnabled) { "aq-mode=2:aq-strength=$aqStrengthFloat" } else { 'aq-mode=0' }
            $parts.Add("option-string=$x264AqOptions")
            $parts.Add('sliced-threads=true')
            if ($cpuWorkers -gt 0) { $parts.Add("threads=$cpuWorkers") }
            $parts.Add('byte-stream=true')
            $parts.Add('aud=true')
        }
        'X265' {
            if ($rateControl -ne 'constqp') { $parts.Add("bitrate=$videoBitrateKbps") }
            $parts.Add('speed-preset=ultrafast')
            if ($tune -in @('low-latency','ultra-low-latency')) { $parts.Add('tune=zerolatency') }
            $parts.Add("key-int-max=$gopSize")
            $x265Options = New-Object System.Collections.Generic.List[string]
            $x265Options.Add("bframes=$bFrames")
            $x265Options.Add("rc-lookahead=$lookAheadFrames")
            if ($cpuWorkers -gt 0) { $x265Options.Add("pools=$cpuWorkers") }
            if ($rateControl -eq 'constqp') { $x265Options.Add("qp=$constantQp") }
            if ($aqEnabled) {
                $x265Options.Add('aq-mode=2')
                $x265Options.Add("aq-strength=$aqStrengthFloat")
            }
            else {
                $x265Options.Add('aq-mode=0')
            }
            $parts.Add("option-string=$($x265Options -join ':')")
        }
        'OPENH264' {
            $parts.Add("bitrate=$videoBitrateBps")
            $parts.Add('rate-control=bitrate')
            $parts.Add('complexity=low')
            $parts.Add('usage-type=screen')
            $parts.Add("gop-size=$gopSize")
            $parts.Add('enable-frame-skip=true')
        }
        'AOM' {
            $parts.Add("target-bitrate=$videoBitrateKbps")
            $parts.Add('end-usage=cbr')
            $parts.Add('cpu-used=8')
            $parts.Add("lag-in-frames=$lookAheadFrames")
            $parts.Add("keyframe-max-dist=$gopSize")
            $parts.Add('row-mt=true')
        }
        'SVTAV1' {
            $parts.Add("target-bitrate=$videoBitrateKbps")
            $parts.Add('preset=12')
            $parts.Add("intra-period-length=$gopSize")
            $parts.Add('intra-refresh-type=IDR')
            $parts.Add('maximum-buffer-size=100')
        }
        'RAV1E' {
            $parts.Add("bitrate=$videoBitrateBps")
            $parts.Add("low-latency=$(($lookAheadFrames -eq 0).ToString().ToLowerInvariant())")
            $parts.Add('speed-preset=10')
            $parts.Add("max-key-frame-interval=$gopSize")
            $parts.Add('min-key-frame-interval=1')
            $parts.Add("rdo-lookahead-frames=$lookAheadFrames")
        }
        'VPX' {
            $parts.Add("target-bitrate=$videoBitrateBps")
            $parts.Add('deadline=1')
            $parts.Add('end-usage=cbr')
            $parts.Add("keyframe-max-dist=$gopSize")
            $parts.Add("lag-in-frames=$lookAheadFrames")
        }
        default {
            throw "Unsupported encoder family: $family"
        }
    }

    Add-CustomEncoderOptions $parts $txtCustomEncoderOptions.Text

    # Direct GST WebRTC AV1 guard:
    # GStreamer 1.28.5 av1parse emits an initial parsed AV1 caps event and then
    # immediately enriches it with chroma/bit-depth/level. rswebrtc/webrtcsink
    # treats that second caps event as unsupported renegotiation on out.video_0.
    # For Direct GST WebRTC only, feed AV1 encoder output through the minimal AV1
    # capsfilter without av1parse so the sink sees one stable caps shape. Keep
    # parsers for H.264/H.265 and non-WebRTC protocols where they are needed.
    $skipParserForDirectWebRtcAv1 = ($codec -eq 'AV1' -and $Protocol -eq 'GST WebRTC')

    if ((-not $skipParserForDirectWebRtcAv1) -and (-not [string]::IsNullOrWhiteSpace($parser))) {
        $parts.Add('!')
        $parts.Add($parser)

        if ($codec -in @('H264', 'H265')) {
            $parts.Add('config-interval=-1')
        }
    }

    $parts.Add('!')
    $parts.Add("`"$(Get-EncodedVideoCaps -Codec $codec -Protocol $Protocol)`"")

    return ($parts -join ' ')
}

function Update-EncoderUi {
    $definition = Get-SelectedEncoderDefinition
    $codec = [string]$definition.Codec
    $family = [string]$definition.Family
    $kind = [string]$definition.Kind
    $inputType = [string]$definition.Input
    $protocol = [string]$cmbProtocol.SelectedItem

    $isNvenc = ($family -eq 'NVENC')
    $rateControl = Get-ComboSelectedOrDefault $cmbRateControl 'cbr'
    $numConstantQp.Enabled = ($rateControl -eq 'constqp' -or ($isNvenc -and $rateControl -eq 'vbr'))
    $cmbPreset.Enabled = $isNvenc
    $cmbEncoderTune.Enabled = $isNvenc
    $cmbMultipass.Enabled = $isNvenc
    $numVbvBuffer.Enabled = $isNvenc
    $cmbProfile.Enabled = ($codec -eq 'H264')

    $controlSupport = Get-EncoderControlSupport
    $numBFrames.Enabled = $controlSupport.BFrames
    $chkLookAhead.Enabled = $controlSupport.LookAhead
    $numLookAheadFrames.Enabled =
        $controlSupport.LookAhead -and $chkLookAhead.Checked
    $chkAdaptiveQuantization.Enabled =
        $controlSupport.AdaptiveQuantization
    $chkTemporalAq.Enabled = $controlSupport.AdaptiveQuantization
    $numAqStrength.Enabled =
        $controlSupport.AdaptiveQuantization -and
        ($chkAdaptiveQuantization.Checked -or $chkTemporalAq.Checked)

    $memoryLabel = if ($inputType -eq 'D3D11') { 'D3D11 zero-copy path' } else { 'CPU/system-memory path' }
    $latencyFlags = New-Object System.Collections.Generic.List[string]
    $latencyFlags.Add($rateControl)
    if ($numConstantQp.Enabled) {
        $qualityLabel = if ($rateControl -eq 'vbr') { 'CQ' } else { 'QP' }
        $latencyFlags.Add("$qualityLabel=$([int]$numConstantQp.Value)")
    }
    if ($numBFrames.Enabled -and [int]$numBFrames.Value -gt 0) {
        $latencyFlags.Add("B=$([int]$numBFrames.Value)")
    }
    if ($chkLookAhead.Enabled -and $chkLookAhead.Checked) {
        $latencyFlags.Add("LA=$([int]$numLookAheadFrames.Value)")
    }
    if ($chkAdaptiveQuantization.Enabled -and ($chkAdaptiveQuantization.Checked -or $chkTemporalAq.Checked)) {
        $aqModeText = if ($chkAdaptiveQuantization.Checked -and $chkTemporalAq.Checked) { 'AQ=S/T' } elseif ($chkAdaptiveQuantization.Checked) { 'AQ=S' } else { 'AQ=T' }
        $latencyFlags.Add($aqModeText)
    }

    $flagText = if ($latencyFlags.Count -gt 0) {
        ' * ' + ($latencyFlags -join ', ')
    }
    else {
        ''
    }
    $lblEncoderStatus.Text = "$codec * $kind * $memoryLabel$flagText"

    if ($protocol) {
        $compatible = Test-CodecProtocolCompatibility -Codec $codec -Protocol $protocol
        $lblEncoderStatus.ForeColor = if ($compatible) {
            [System.Drawing.Color]::DimGray
        }
        else {
            [System.Drawing.Color]::DarkRed
        }
    }

    Update-UnifiedBridgeKeyframeUi
    Update-CommandPreview
}

