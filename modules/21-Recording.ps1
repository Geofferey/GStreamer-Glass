# Module: 21-Recording.ps1 (auto-extracted by tools/Split-Monolith.ps1 -- edit here, then run tools/Build-Monolith.ps1)

function Test-RecordingEnabled {
    return (
        $chkRecordingEnabled -and
        $chkRecordingEnabled.Checked -and
        [bool]$script:RecordingPipelineRequested
    )
}

function Get-SelectedRecordingEncoderDefinition {
    $name = [string]$cmbRecordingEncoder.SelectedItem
    if (
        [string]::IsNullOrWhiteSpace($name) -or
        -not $script:EncoderCatalog.Contains($name)
    ) {
        $name = $script:DefaultEncoderName
    }

    return $script:EncoderCatalog[$name]
}

function Get-RecordingEncoderControlSupport {
    $definition = Get-SelectedRecordingEncoderDefinition
    $family = [string]$definition.Family
    $codec = [string]$definition.Codec

    $supportsBFrames = $false
    switch ($family) {
        'NVENC' { $supportsBFrames = ($codec -in @('H264', 'H265')) }
        'AMF'   { $supportsBFrames = ($codec -eq 'H264') }
        'QSV'   { $supportsBFrames = ($codec -in @('H264', 'H265')) }
        'MF'    { $supportsBFrames = ($codec -in @('H264', 'H265')) }
        'X264'  { $supportsBFrames = $true }
        'X265'  { $supportsBFrames = $true }
    }

    return [pscustomobject]@{ BFrames = $supportsBFrames }
}

function Get-SafeRecordingToken {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return 'unknown' }

    $safe = $Value -replace '[^A-Za-z0-9._-]+', '-'
    $safe = $safe.Trim('-')
    if ([string]::IsNullOrWhiteSpace($safe)) { return 'unknown' }
    return $safe
}

function Resolve-RecordingFilePath {
    param([switch]$EnsureDirectory, [switch]$AvoidExisting)

    $folder = [Environment]::ExpandEnvironmentVariables($txtRecordingDirectory.Text.Trim())
    if ([string]::IsNullOrWhiteSpace($folder)) { throw 'Select a recording output folder.' }

    if ($EnsureDirectory -and -not (Test-Path -LiteralPath $folder)) {
        $null = New-Item -ItemType Directory -Path $folder -Force
    }

    if (-not (Test-Path -LiteralPath $folder)) { throw "Recording folder does not exist: $folder" }

    $now = Get-Date
    $template = $txtRecordingTemplate.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($template)) {
        $template = 'Glass-{yyyyMMdd-HHmmss}-{protocol}-{width}x{height}-{fps}fps.mkv'
    }

    $tokenMap = [ordered]@{
        '{date}'     = $now.ToString('yyyyMMdd')
        '{time}'     = $now.ToString('HHmmss')
        '{datetime}' = $now.ToString('yyyyMMdd-HHmmss')
        '{protocol}' = Get-SafeRecordingToken ([string]$cmbProtocol.SelectedItem)
        '{encoder}'  = Get-SafeRecordingToken ([string]$cmbRecordingEncoder.SelectedItem)
        '{width}'    = [string][int]$numRecordingWidth.Value
        '{height}'   = [string][int]$numRecordingHeight.Value
        '{fps}'      = [string][int]$numRecordingFps.Value
    }

    $fileName = $template
    foreach ($key in $tokenMap.Keys) { $fileName = $fileName.Replace($key, [string]$tokenMap[$key]) }

    $fileName = [regex]::Replace(
        $fileName,
        '\{([yMdHhmsfF_. -]+)\}',
        { param($match) $now.ToString($match.Groups[1].Value) }
    )

    foreach ($invalid in [System.IO.Path]::GetInvalidFileNameChars()) {
        $fileName = $fileName.Replace([string]$invalid, '_')
    }

    if ([string]::IsNullOrWhiteSpace([System.IO.Path]::GetExtension($fileName))) { $fileName += '.mkv' }

    $path = Join-Path $folder $fileName
    if ($AvoidExisting) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($path)
        $ext = [System.IO.Path]::GetExtension($path)
        $dir = [System.IO.Path]::GetDirectoryName($path)
        $index = 1
        while (Test-Path -LiteralPath $path) {
            $path = Join-Path $dir ("{0}-{1:000}{2}" -f $base, $index, $ext)
            $index++
        }
    }
    return $path
}

function Get-RecordingEncodedVideoCaps {
    param([Parameter(Mandatory)][string]$Codec)
    $profile = [string]$cmbRecordingProfile.SelectedItem

    # Matroska does not accept Annex-B/byte-stream H.264 or H.265 on its video pad.
    # Force the parser to negotiate muxer-friendly length-prefixed caps instead.
    switch ($Codec) {
        'H264' { return "video/x-h264,profile=$profile,stream-format=avc,alignment=au" }
        'H265' { return 'video/x-h265,profile=main,stream-format=hvc1,alignment=au' }
        'AV1'  { return 'video/x-av1,stream-format=obu-stream,alignment=tu,profile=main,chroma-format=(string)4:2:0,bit-depth-luma=(uint)8,bit-depth-chroma=(uint)8' }
        'VP8'  { return 'video/x-vp8' }
        'VP9'  { return 'video/x-vp9' }
        default { throw "Unsupported recording codec: $Codec" }
    }
}

function Add-CustomEncoderOptions {
    param(
        [Parameter(Mandatory)]$Parts,
        [AllowNull()][string]$Options
    )

    $text = ([string]$Options).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return }

    foreach ($chunk in ($text -split '\s+')) {
        if (-not [string]::IsNullOrWhiteSpace($chunk)) {
            $Parts.Add($chunk)
        }
    }
}

function Get-ComboSelectedOrDefault {
    param(
        [Parameter(Mandatory)]$ComboBox,
        [Parameter(Mandatory)][string]$Default
    )

    $value = [string]$ComboBox.SelectedItem
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value
}

function Add-NvencRateControlOptions {
    param(
        [Parameter(Mandatory)]$Parts,
        [Parameter(Mandatory)][string]$RateControl,
        [Parameter(Mandatory)][int]$BitrateKbps,
        [Parameter(Mandatory)][int]$MaxBitrateKbps,
        [Parameter(Mandatory)][int]$ConstantQp
    )

    switch ($RateControl) {
        'constqp' {
            $Parts.Add('rc-mode=constqp')
            $Parts.Add("qp-const=$ConstantQp")
            $Parts.Add("qp-const-i=$ConstantQp")
            $Parts.Add("qp-const-p=$ConstantQp")
            $Parts.Add("qp-const-b=$ConstantQp")
        }
        'vbr' {
            $Parts.Add("bitrate=$BitrateKbps")
            $Parts.Add('rc-mode=vbr')
            if ($MaxBitrateKbps -gt 0) { $Parts.Add("max-bitrate=$MaxBitrateKbps") }
            $Parts.Add("const-quality=$ConstantQp")
        }
        default {
            $Parts.Add("bitrate=$BitrateKbps")
            $Parts.Add('rc-mode=cbr')
        }
    }
}

function Add-QsvRateControlOptions {
    param(
        [Parameter(Mandatory)]$Parts,
        [Parameter(Mandatory)][string]$RateControl,
        [Parameter(Mandatory)][int]$BitrateKbps,
        [Parameter(Mandatory)][int]$MaxBitrateKbps,
        [Parameter(Mandatory)][int]$ConstantQp,
        [Parameter(Mandatory)][int]$LookAheadFrames,
        [Parameter(Mandatory)][string]$Codec
    )

    switch ($RateControl) {
        'constqp' {
            $Parts.Add('rate-control=cqp')
            if ($Codec -in @('H264','H265')) {
                $Parts.Add("qp-i=$ConstantQp")
                $Parts.Add("qp-p=$ConstantQp")
                $Parts.Add("qp-b=$ConstantQp")
            }
        }
        'vbr' {
            if ($LookAheadFrames -gt 0 -and $Codec -in @('H264','H265')) {
                $Parts.Add('rate-control=la-vbr')
                $Parts.Add("rc-lookahead=$LookAheadFrames")
            }
            else {
                $Parts.Add('rate-control=vbr')
            }
            $Parts.Add("bitrate=$BitrateKbps")
            if ($MaxBitrateKbps -gt 0) { $Parts.Add("max-bitrate=$MaxBitrateKbps") }
        }
        default {
            if ($LookAheadFrames -gt 0 -and $Codec -in @('H264','H265')) {
                $Parts.Add('rate-control=la-hrd')
                $Parts.Add("rc-lookahead=$LookAheadFrames")
            }
            else {
                $Parts.Add('rate-control=cbr')
                if ($Codec -in @('H264','H265')) { $Parts.Add('rc-lookahead=0') }
            }
            $Parts.Add("bitrate=$BitrateKbps")
        }
    }
}

function Get-RecordingEncoderElementChain {
    $definition = Get-SelectedRecordingEncoderDefinition
    $element = [string]$definition.Element
    $codec = [string]$definition.Codec
    $family = [string]$definition.Family
    $inputType = [string]$definition.Input
    $parser = [string]$definition.Parser
    $width = [int]$numRecordingWidth.Value
    $height = [int]$numRecordingHeight.Value
    $fps = [int]$numRecordingFps.Value
    $videoBitrateKbps = [int]$numRecordingVideoBitrate.Value
    $videoBitrateBps = $videoBitrateKbps * 1000
    $maxVideoBitrateKbps = [int]$numRecordingMaxVideoBitrate.Value
    $constantQp = [int]$numRecordingConstantQp.Value
    $gopSize = [Math]::Max(1, $fps * [int]$numRecordingGopSeconds.Value)
    $preset = [string]$cmbRecordingPreset.SelectedItem
    $rateControl = Get-ComboSelectedOrDefault $cmbRecordingRateControl 'constqp'
    $tune = Get-ComboSelectedOrDefault $cmbRecordingTune 'high-quality'
    $multipass = Get-ComboSelectedOrDefault $cmbRecordingMultipass 'two-pass-quarter'
    $support = Get-RecordingEncoderControlSupport
    $bFrames = if ($support.BFrames) { [int]$numRecordingBFrames.Value } else { 0 }
    $lookAheadFrames = if ($support.LookAhead -and $chkRecordingLookAhead.Checked) { [int]$numRecordingLookAheadFrames.Value } else { 0 }
    $spatialAq = $support.AdaptiveQuantization -and $chkRecordingSpatialAq.Checked
    $temporalAq = $support.AdaptiveQuantization -and $chkRecordingTemporalAq.Checked
    $aqStrength = [int]$numRecordingAqStrength.Value
    $aqStrengthFloat = ($aqStrength / 8.0).ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture)
    $vbvBuffer = [int]$numRecordingVbvBuffer.Value
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($x in @('queue','max-size-buffers=12','max-size-bytes=0','max-size-time=0','leaky=downstream','!','d3d11convert','!')) { $parts.Add($x) }
    $parts.Add("`"video/x-raw(memory:D3D11Memory),format=NV12,width=$width,height=$height,framerate=$fps/1`"")
    $parts.Add('!')
    if ($inputType -eq 'I420') {
        foreach ($x in @('d3d11download','!','videoconvert','!')) { $parts.Add($x) }
        $parts.Add("`"video/x-raw,format=I420,width=$width,height=$height,framerate=$fps/1`"")
        $parts.Add('!')
    }
    $parts.Add($element)
    switch ($family) {
        'NVENC' {
            $zeroLatency = ($bFrames -eq 0 -and $lookAheadFrames -eq 0 -and $tune -in @('low-latency','ultra-low-latency'))
            Add-NvencRateControlOptions $parts $rateControl $videoBitrateKbps $maxVideoBitrateKbps $constantQp
            foreach ($x in @("preset=$preset","tune=$tune","multi-pass=$multipass","zerolatency=$($zeroLatency.ToString().ToLowerInvariant())","bframes=$bFrames","b-adapt=$((($bFrames -gt 0) -and ($lookAheadFrames -gt 0)).ToString().ToLowerInvariant())","gop-size=$gopSize","rc-lookahead=$lookAheadFrames","spatial-aq=$($spatialAq.ToString().ToLowerInvariant())","temporal-aq=$($temporalAq.ToString().ToLowerInvariant())")) { $parts.Add($x) }
            if ($spatialAq -or $temporalAq) { $parts.Add("aq-strength=$aqStrength") }
            if ($vbvBuffer -gt 0) { $parts.Add("vbv-buffer-size=$vbvBuffer") }
            if ($codec -in @('H264','H265')) { $parts.Add('repeat-sequence-header=true') }
        }
        'AMF' {
            foreach ($x in @("bitrate=$videoBitrateKbps",'rate-control=cbr','preset=quality','usage=transcoding',"gop-size=$gopSize",'pre-encode=false')) { $parts.Add($x) }
            if ($codec -eq 'H264') { $parts.Add("b-frames=$bFrames"); $parts.Add("max-b-frames=$bFrames") }
        }
        'QSV' {
            Add-QsvRateControlOptions $parts $rateControl $videoBitrateKbps $maxVideoBitrateKbps $constantQp $lookAheadFrames $codec
            $parts.Add("gop-size=$gopSize")
            if ($codec -in @('H264','H265')) { $parts.Add("b-frames=$bFrames") }
        }
        'MF' {
            foreach ($x in @("bitrate=$videoBitrateKbps",'rc-mode=cbr',"gop-size=$gopSize",'low-latency=false')) { $parts.Add($x) }
            if ($support.BFrames) { $parts.Add("bframes=$bFrames") }
        }
        'X264' {
            if ($rateControl -eq 'constqp') { $parts.Add('pass=quant'); $parts.Add("quantizer=$constantQp") } else { $parts.Add("bitrate=$videoBitrateKbps") }
            $parts.Add('speed-preset=veryfast')
            if ($tune -in @('low-latency','ultra-low-latency')) { $parts.Add('tune=zerolatency') }
            foreach ($x in @("key-int-max=$gopSize","bframes=$bFrames","rc-lookahead=$lookAheadFrames",'byte-stream=true','aud=true')) { $parts.Add($x) }
        }
        'X265' {
            if ($rateControl -ne 'constqp') { $parts.Add("bitrate=$videoBitrateKbps") }
            $parts.Add('speed-preset=veryfast')
            if ($tune -in @('low-latency','ultra-low-latency')) { $parts.Add('tune=zerolatency') }
            $parts.Add("key-int-max=$gopSize")
            $x265Options = New-Object System.Collections.Generic.List[string]
            $x265Options.Add("bframes=$bFrames")
            $x265Options.Add("rc-lookahead=$lookAheadFrames")
            if ($rateControl -eq 'constqp') { $x265Options.Add("qp=$constantQp") }
            if ($spatialAq -or $temporalAq) { $x265Options.Add('aq-mode=2'); $x265Options.Add("aq-strength=$aqStrengthFloat") } else { $x265Options.Add('aq-mode=0') }
            $parts.Add("option-string=$($x265Options -join ':')")
        }
        'OPENH264' { foreach ($x in @("bitrate=$videoBitrateBps",'rate-control=bitrate','complexity=medium','usage-type=screen',"gop-size=$gopSize")) { $parts.Add($x) } }
        'AOM' { foreach ($x in @("target-bitrate=$videoBitrateKbps",'end-usage=cbr','cpu-used=6','lag-in-frames=0',"keyframe-max-dist=$gopSize",'row-mt=true')) { $parts.Add($x) } }
        'SVTAV1' { foreach ($x in @("target-bitrate=$videoBitrateKbps",'preset=8',"intra-period-length=$gopSize",'intra-refresh-type=IDR')) { $parts.Add($x) } }
        'RAV1E' { foreach ($x in @("bitrate=$videoBitrateBps",'low-latency=true','speed-preset=8',"max-key-frame-interval=$gopSize",'min-key-frame-interval=1','rdo-lookahead-frames=0')) { $parts.Add($x) } }
        'VPX' { foreach ($x in @("target-bitrate=$videoBitrateBps",'deadline=1','end-usage=cbr',"keyframe-max-dist=$gopSize",'lag-in-frames=0')) { $parts.Add($x) } }
        default { throw "Unsupported recording encoder family: $family" }
    }
    Add-CustomEncoderOptions $parts $txtRecordingCustomEncoderOptions.Text
    if (-not [string]::IsNullOrWhiteSpace($parser)) {
        $parts.Add('!'); $parts.Add($parser)
        if ($codec -in @('H264','H265')) { $parts.Add('config-interval=-1') }
    }
    $parts.Add('!')
    $parts.Add("`"$(Get-RecordingEncodedVideoCaps -Codec $codec)`"")
    return ($parts -join ' ')
}

function Build-RecordingRawAudioChain {
    $desktopEnabled = $chkRecordingDesktopAudio.Checked
    $micEnabled = $chkRecordingMic.Checked
    if (-not $desktopEnabled -and -not $micEnabled) { return '' }

    # Recording audio shares the same pipeline clock. Reuse the Audio-tab WASAPI
    # source builder so recording cannot silently inject low-latency/buffer/clock
    # properties that are disabled in the timing lab.
    $desktopSource = Get-WasapiSourceString -Loopback
    $micSource = Get-WasapiSourceString

    if ($desktopEnabled -and -not $micEnabled) {
        return @($desktopSource,'!','queue','max-size-buffers=16','max-size-bytes=0','max-size-time=0','leaky=downstream','!','audioconvert','!','audioresample','!',(Get-AudioRawCapsString -Format 'S16LE' -Channels 2)) -join ' '
    }
    if (-not $desktopEnabled -and $micEnabled) {
        return @($micSource,'!','queue','max-size-buffers=16','max-size-bytes=0','max-size-time=0','leaky=downstream','!','audioconvert','!','audioresample','!',(Get-AudioRawCapsString -Format 'S16LE' -Channels 2)) -join ' '
    }
    $desktopMixBranch = @($desktopSource,'!','queue','max-size-buffers=16','max-size-bytes=0','max-size-time=0','leaky=downstream','!','audioconvert','!','audioresample','!',(Get-AudioRawCapsString -Format 'F32LE' -Channels 2),'!','recordaudiomix.') -join ' '
    $micMixBranch = @($micSource,'!','queue','max-size-buffers=16','max-size-bytes=0','max-size-time=0','leaky=downstream','!','audioconvert','!','audioresample','!',(Get-AudioRawCapsString -Format 'F32LE' -Channels 2),'!','recordaudiomix.') -join ' '
    $mixOutput = @('recordaudiomix.','!','queue','max-size-buffers=16','max-size-bytes=0','max-size-time=0','leaky=downstream','!','audioconvert','!',(Get-AudioRawCapsString -Format 'S16LE' -Channels 2)) -join ' '
    return "audiomixer name=recordaudiomix $desktopMixBranch $micMixBranch $mixOutput"
}

function Build-RecordingAudioBranch {
    if (-not (Test-RecordingEnabled)) { return '' }
    $raw = Build-RecordingRawAudioChain
    if ([string]::IsNullOrWhiteSpace($raw)) { return '' }
    $bitrate = [int]$numRecordingAudioBitrate.Value * 1000
    return "$raw ! opusenc bitrate=$bitrate bitrate-type=cbr frame-size=10 audio-type=restricted-lowdelay ! `"audio/x-opus`" ! recordmux."
}

function Get-RecordingBranchQueue {
    # A tee branch without a queue is pushed synchronously on the tee's streaming
    # thread - which here is the capture thread. Without this, the recording
    # encoder + matroskamux + filesink write all run inline on capture, and
    # because tee pushes to its src pads in link order (recording is linked
    # first), the live/transport branch does not even receive a buffer until the
    # recording write returns. Any disk hitch therefore lands directly on the
    # live encode path.
    #
    # Kept shallow deliberately: these are D3D11Memory buffers from a fixed-size
    # capture pool. A deep queue here would hold GPU textures, starve the pool,
    # and stall d3d11screencapturesrc - worse than the problem being fixed.
    #
    # leaky=no preserves recording integrity: sustained disk overrun will still
    # backpressure rather than silently punch frame gaps into the file. To favour
    # the live stream over the recording instead, change this to leaky=downstream
    # and accept dropped frames in the recorded file.
    return 'queue name=recordq max-size-buffers=4 max-size-bytes=0 max-size-time=0 leaky=no'
}

function Build-RecordingMuxPrefixAndVideoBranch {
    if (-not (Test-RecordingEnabled)) { return '' }
    $recordingPath = if (-not [string]::IsNullOrWhiteSpace($script:ResolvedRecordingPath)) { $script:ResolvedRecordingPath } else { Resolve-RecordingFilePath }
    $quotedRecordingPath = Quote-GstValue $recordingPath
    $encoder = Get-RecordingEncoderElementChain
    $recordQueue = Get-RecordingBranchQueue
    return "matroskamux name=recordmux writing-app=`"GStreamer Glass`" ! filesink location=$quotedRecordingPath async=false rawtee. ! $recordQueue ! $encoder ! recordmux."
}

function Update-RecordingUi {
    if (-not $chkRecordingEnabled) { return }
    $enabled = [bool]$chkRecordingEnabled.Checked
    $definition = Get-SelectedRecordingEncoderDefinition
    $codec = [string]$definition.Codec
    $family = [string]$definition.Family
    $kind = [string]$definition.Kind
    foreach ($control in @($txtRecordingDirectory,$btnBrowseRecordingDirectory,$txtRecordingTemplate,$cmbRecordingEncoder,$cmbRecordingRateControl,$numRecordingWidth,$numRecordingHeight,$numRecordingFps,$numRecordingVideoBitrate,$numRecordingMaxVideoBitrate,$numRecordingConstantQp,$numRecordingGopSeconds,$chkRecordingDesktopAudio,$chkRecordingMic,$numRecordingAudioBitrate,$txtRecordingCustomEncoderOptions)) {
        if ($control) { $control.Enabled = $enabled }
    }
    if ($chkRecordWithStream) { $chkRecordWithStream.Enabled = $enabled }
    if ($btnToggleRecording) {
        $btnToggleRecording.Enabled = $script:RecordingPipelineActive -or ($enabled -and -not $script:WaitingForFullscreen)
        $btnToggleRecording.Text = if ($script:RecordingPipelineActive) {
            "$($script:Glyph.Stop)  Stop Recording"
        }
        else {
            "$($script:Glyph.Recording)  Record"
        }
    }
    $isNvenc = ($family -eq 'NVENC')
    $recordingRateControl = Get-ComboSelectedOrDefault $cmbRecordingRateControl 'constqp'
    $numRecordingConstantQp.Enabled = $enabled -and ($recordingRateControl -eq 'constqp' -or ($isNvenc -and $recordingRateControl -eq 'vbr'))
    $cmbRecordingPreset.Enabled = $enabled -and $isNvenc
    $cmbRecordingTune.Enabled = $enabled -and $isNvenc
    $cmbRecordingMultipass.Enabled = $enabled -and $isNvenc
    $numRecordingVbvBuffer.Enabled = $enabled -and $isNvenc
    $cmbRecordingProfile.Enabled = $enabled -and ($codec -eq 'H264')
    $support = Get-RecordingEncoderControlSupport
    $numRecordingBFrames.Enabled = $enabled -and $support.BFrames
    $chkRecordingLookAhead.Enabled = $enabled -and $support.LookAhead
    $numRecordingLookAheadFrames.Enabled = $enabled -and $support.LookAhead -and $chkRecordingLookAhead.Checked
    $chkRecordingSpatialAq.Enabled = $enabled -and $support.AdaptiveQuantization
    $chkRecordingTemporalAq.Enabled = $enabled -and $support.AdaptiveQuantization
    $numRecordingAqStrength.Enabled = $enabled -and $support.AdaptiveQuantization -and ($chkRecordingSpatialAq.Checked -or $chkRecordingTemporalAq.Checked)
    if ($script:RecordingPipelineActive) {
        $lblRecordingStatus.Text = "RECORDING * $codec * $kind * MKV"
        $lblRecordingStatus.ForeColor = [System.Drawing.Color]::DarkGreen
    }
    elseif ($enabled) {
        $audioSummary = if ($chkRecordingDesktopAudio.Checked -or $chkRecordingMic.Checked) { 'Opus audio' } else { 'video only' }
        $rcSummary = Get-ComboSelectedOrDefault $cmbRecordingRateControl 'constqp'
        $lblRecordingStatus.Text = "Ready * $codec * $kind * $rcSummary * MKV * $audioSummary"
        $lblRecordingStatus.ForeColor = [System.Drawing.Color]::DarkSlateBlue
    }
    else {
        $lblRecordingStatus.Text = 'Recording disabled'
        $lblRecordingStatus.ForeColor = [System.Drawing.Color]::DimGray
    }
    Update-CommandPreview
}

function Invoke-ToggleRecording {
    if (-not $chkRecordingEnabled.Checked) {
        [System.Windows.Forms.MessageBox]::Show(
            'Enable recording first, then use Record.',
            $script:AppName,
            'OK',
            'Information'
        ) | Out-Null
        return
    }

    $pipelineRunning = $script:GstProcess -and -not $script:GstProcess.HasExited

    if ($script:RecordingPipelineActive) {
        if ($script:RecordingOnlyMode) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Stop Recording requested; stopping the local recording pipeline."
            Stop-GstStream
        }
        else {
            # Removing a tee/mux branch safely requires rebuilding the gst-launch
            # graph. Clear the persistent policy too, otherwise the scheduled
            # stream restart would immediately add recording again.
            $chkRecordWithStream.Checked = $false
            Save-Settings
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Stop Recording requested; restarting the live stream without its recording branch."
            Stop-GstStream -Restart
        }
        return
    }

    if ($pipelineRunning -and -not $script:PreviewOnlyMode -and (Test-TransportEnabled)) {
        $chkRecordWithStream.Checked = $true
        Save-Settings
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Start Recording requested; restarting the live stream with its recording branch."
        Stop-GstStream -Restart
        return
    }

    if ($pipelineRunning -or $script:DynamicScenePreviewActive) {
        $script:RestartRecordingOnlyMode = $true
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Start Recording requested; replacing the preview-only pipeline with a local recording pipeline."
        Stop-GstStream -Restart
        return
    }

    Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Starting local recording."
    Start-GstStream -RecordingOnly
}

function Test-RecordingFrameRateCompatible {
    if (-not (Test-RecordingEnabled)) { return $true }
    if (-not (Test-TransportEnabled)) { return $true }

    # With transport enabled, capture is driven by the Video tab FPS. The recording branch
    # currently stays on the zero-copy D3D11 path, where d3d11convert cannot change FPS.
    # Allow independent recording bitrate/size/encoder, but require matching FPS unless
    # we later add a dedicated videorate download/upload path.
    return ([int]$numRecordingFps.Value -eq [int]$numFps.Value)
}

function Assert-RecordingFrameRateCompatible {
    if (Test-RecordingFrameRateCompatible) { return }

    throw ("Recording FPS must match Video FPS while transport is enabled. " +
        "Set Video FPS to $([int]$numRecordingFps.Value), set Recording FPS to $([int]$numFps.Value), " +
        "or disable transport for recording-only capture. The D3D11 branch cannot convert frame rate with d3d11convert.")
}

