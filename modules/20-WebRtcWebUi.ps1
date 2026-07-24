function Test-DirectWebRtcProtocol {
    return (Test-TransportEnabled) -and ([string]$cmbProtocol.SelectedItem -eq $script:DirectWebRtcProtocolName)
}

function Test-WebRtcTransportProtocol {
    return (Test-TransportEnabled) -and ([string]$cmbProtocol.SelectedItem -in @('WHIP', $script:DirectWebRtcProtocolName))
}

function Normalize-DirectWebRtcWebAddress {
    param([string]$Value)

    $address = $Value
    if ([string]::IsNullOrWhiteSpace($address)) {
        $address = $script:DefaultDirectWebRtcWebAddress
    }

    $address = $address.Trim()
    if ($address -notmatch '^https?://') {
        $address = 'http://' + $address.TrimStart('/')
    }

    # web-server-host-addr is the bind/listen address. Keep the route path in
    # web-server-path so http://host:8889/live can be changed cleanly.
    try {
        $uri = [System.Uri]$address
        $scheme = $uri.Scheme
        $hostPart = $uri.Host
        $portPart = if ($uri.IsDefaultPort) { '' } else { ":$($uri.Port)" }
        $address = "${scheme}://$hostPart$portPart/"
    }
    catch {
        if ($address -notmatch '/$') { $address += '/' }
    }

    return $address
}

function Normalize-DirectWebRtcWebPath {
    param([string]$Value)

    $path = $Value
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = $script:DefaultDirectWebRtcWebPath
    }

    $path = $path.Trim()
    if ($path -eq '/') { return '/' }
    if ($path -notmatch '^/') { $path = '/' + $path }
    return $path.TrimEnd('/')
}

function Test-DirectWebRtcWebDirectory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try {
        $resolved = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"')))
        return ((Test-Path -LiteralPath (Join-Path $resolved 'index.html') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $resolved 'player.js') -PathType Leaf))
    }
    catch {
        return $false
    }
}

function Find-DirectWebRtcWebDirectory {
    param([string]$GstLaunchPath)

    $candidates = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($script:ApplicationDirectory)) {
        $candidates.Add((Join-Path $script:ApplicationDirectory 'gstwebrtc-api\dist'))
    }

    if (-not [string]::IsNullOrWhiteSpace($GstLaunchPath)) {
        try {
            $binDir = Split-Path -Parent $GstLaunchPath
            $rootDir = Split-Path -Parent $binDir
            foreach ($base in @($binDir, $rootDir, (Split-Path -Parent $rootDir))) {
                if ([string]::IsNullOrWhiteSpace($base)) { continue }
                $candidates.Add((Join-Path $base 'gstwebrtc-api\dist'))
                $candidates.Add((Join-Path $base 'share\gstwebrtc-api\dist'))
                $candidates.Add((Join-Path $base 'share\gstreamer-1.0\gstwebrtc-api\dist'))
                $candidates.Add((Join-Path $base 'share\gstreamer-1.0\webrtc\gstwebrtc-api\dist'))
                $candidates.Add((Join-Path $base 'lib\gstreamer-1.0\gstwebrtc-api\dist'))
            }
        }
        catch {}
    }

    foreach ($base in @(
        ${env:ProgramFiles},
        ${env:ProgramFiles(x86)},
        'C:\Program Files (x86)\Strom\gstreamer',
        'C:\Program Files\gstreamer\1.0\msvc_x86_64'
    )) {
        if ([string]::IsNullOrWhiteSpace($base)) { continue }
        $candidates.Add((Join-Path $base 'gstwebrtc-api\dist'))
        $candidates.Add((Join-Path $base 'share\gstwebrtc-api\dist'))
        $candidates.Add((Join-Path $base 'share\gstreamer-1.0\gstwebrtc-api\dist'))
        $candidates.Add((Join-Path $base 'share\gstreamer-1.0\webrtc\gstwebrtc-api\dist'))
        $candidates.Add((Join-Path $base 'lib\gstreamer-1.0\gstwebrtc-api\dist'))
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-DirectWebRtcWebDirectory $candidate) {
            return ([System.IO.Path]::GetFullPath($candidate))
        }
    }

    return ''
}

function Get-DefaultDirectWebRtcWorkingWebDirectory {
    return ([System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'GStreamerGlass\WebRoot\gstwebrtc-api\dist')))
}

function Test-DirectWebRtcWebDirectoryWritable {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try {
        $resolved = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"')))
        if (-not (Test-Path -LiteralPath $resolved)) {
            $null = New-Item -ItemType Directory -Path $resolved -Force
        }
        $probe = Join-Path $resolved ('.gstglass-write-test-' + [guid]::NewGuid().ToString('N') + '.tmp')
        Set-Content -LiteralPath $probe -Value 'ok' -Encoding ASCII -ErrorAction Stop
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        return $true
    }
    catch {
        return $false
    }
}

function Select-DirectWebRtcFolderPath {
    param(
        [string]$Title,
        [string]$InitialPath,
        [bool]$AllowNewFolder = $true
    )

    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = $Title
    $dlg.ShowNewFolderButton = $AllowNewFolder

    try {
        $expanded = [Environment]::ExpandEnvironmentVariables([string]$InitialPath)
        if (-not [string]::IsNullOrWhiteSpace($expanded) -and (Test-Path -LiteralPath $expanded)) {
            $dlg.SelectedPath = ([System.IO.Path]::GetFullPath($expanded))
        }
    }
    catch {}

    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dlg.SelectedPath
    }

    return $null
}

function Get-DirectWebRtcWebUiVersion {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try {
        $resolved = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"')))
        $manifest = Join-Path $resolved 'gstglass-webui-manifest.json'
        if (Test-Path -LiteralPath $manifest -PathType Leaf) {
            $json = Get-Content -LiteralPath $manifest -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($json.webUiVersion) { return [string]$json.webUiVersion }
            if ($json.version) { return [string]$json.version }
        }
    }
    catch {}
    return $null
}

function Compare-DirectWebRtcVersionString {
    param([string]$Left, [string]$Right)

    if ([string]::IsNullOrWhiteSpace($Left) -and [string]::IsNullOrWhiteSpace($Right)) { return 0 }
    if ([string]::IsNullOrWhiteSpace($Left)) { return -1 }
    if ([string]::IsNullOrWhiteSpace($Right)) { return 1 }

    try {
        # Preserve the f-build suffix used by Glass web UI releases. Comparing
        # only the dotted base made 3.7.52f18 and 3.7.52f19 look identical and
        # could leave an older working WebRoot in place after an app upgrade.
        $lm = [regex]::Match($Left, '(?i)(?<base>\d+(?:\.\d+){1,3})(?:f(?<revision>\d+))?')
        $rm = [regex]::Match($Right, '(?i)(?<base>\d+(?:\.\d+){1,3})(?:f(?<revision>\d+))?')
        if (-not $lm.Success -or -not $rm.Success) { throw 'Unrecognized version format' }

        $baseCompare = ([version]$lm.Groups['base'].Value).CompareTo([version]$rm.Groups['base'].Value)
        if ($baseCompare -ne 0) { return $baseCompare }

        $leftRevision = if ($lm.Groups['revision'].Success) { [int]$lm.Groups['revision'].Value } else { 0 }
        $rightRevision = if ($rm.Groups['revision'].Success) { [int]$rm.Groups['revision'].Value } else { 0 }
        return $leftRevision.CompareTo($rightRevision)
    }
    catch {
        return [string]::Compare($Left, $Right, $true)
    }
}

function Get-BundledDirectWebRtcWebDirectory {
    $mode = $script:DefaultDirectWebRtcBundledWebMode
    if ($cmbDirectWebRtcBundledWebMode -and $cmbDirectWebRtcBundledWebMode.SelectedItem) { $mode = [string]$cmbDirectWebRtcBundledWebMode.SelectedItem }

    if ($mode -eq 'Manual path' -and $txtDirectWebRtcBundledWebDirectory) {
        $manual = [string]$txtDirectWebRtcBundledWebDirectory.Text
        if (Test-DirectWebRtcWebDirectory $manual) {
            return ([System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($manual.Trim().Trim('"'))))
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($script:ApplicationDirectory)) {
        $bundled = Join-Path $script:ApplicationDirectory 'gstwebrtc-api\dist'
        if (Test-DirectWebRtcWebDirectory $bundled) {
            return ([System.IO.Path]::GetFullPath($bundled))
        }
    }

    return (Find-DirectWebRtcWebDirectory $txtGstPath.Text)
}

function Get-DirectWebRtcWorkingWebDirectory {
    $mode = $script:DefaultDirectWebRtcWorkingWebMode
    if ($cmbDirectWebRtcWorkingWebMode -and $cmbDirectWebRtcWorkingWebMode.SelectedItem) { $mode = [string]$cmbDirectWebRtcWorkingWebMode.SelectedItem }

    if ($mode -eq 'Manual path' -and $txtDirectWebRtcWebDirectory) {
        $manual = [string]$txtDirectWebRtcWebDirectory.Text
        if (-not [string]::IsNullOrWhiteSpace($manual)) {
            return ([System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($manual.Trim().Trim('"'))))
        }
    }

    return (Get-DefaultDirectWebRtcWorkingWebDirectory)
}

function Test-DirectWebRtcWebUiHasJbufStats {
    param([string]$Path)

    if (-not (Test-DirectWebRtcWebDirectory $Path)) { return $false }

    try {
        $playerPath = Join-Path ([System.IO.Path]::GetFullPath($Path)) 'player.js'
        if (-not (Test-Path -LiteralPath $playerPath -PathType Leaf)) { return $false }
        $playerText = Get-Content -LiteralPath $playerPath -Raw -ErrorAction Stop
        return ($playerText -match 'audio jbuf' -and $playerText -match 'video jbuf' -and $playerText -match 'GstGlassJbuf')
    }
    catch {
        return $false
    }
}

function Get-DirectWebRtcSourceWebDirectory {
    return (Get-BundledDirectWebRtcWebDirectory)
}

function Copy-DirectWebRtcStaticWebAssets {
    param(
        [Parameter(Mandatory)][string]$SourceDirectory,
        [Parameter(Mandatory)][string]$DestinationDirectory,
        [switch]$ForceRefresh
    )

    $sourceFull = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($SourceDirectory.Trim().Trim('"')))
    $destFull = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($DestinationDirectory.Trim().Trim('"')))

    if (-not (Test-DirectWebRtcWebDirectory $sourceFull)) {
        throw "Bundled Web UI source is missing index.html/player.js: $sourceFull"
    }

    if (-not (Test-Path -LiteralPath $destFull)) {
        $null = New-Item -ItemType Directory -Path $destFull -Force
    }

    if (-not (Test-DirectWebRtcWebDirectoryWritable $destFull)) {
        throw "Working Web UI directory is not writable: $destFull"
    }

    $sourceVersion = Get-DirectWebRtcWebUiVersion $sourceFull
    $destVersion = Get-DirectWebRtcWebUiVersion $destFull
    $destHasUi = Test-DirectWebRtcWebDirectory $destFull
    $needsCopy = $ForceRefresh -or (-not $destHasUi)
    if (-not $needsCopy) {
        $needsCopy = ((Compare-DirectWebRtcVersionString $sourceVersion $destVersion) -gt 0)
    }

    if (-not $needsCopy) {
        return [pscustomobject]@{ Copied = $false; Source = $sourceFull; Destination = $destFull; SourceVersion = $sourceVersion; DestinationVersion = $destVersion }
    }

    Get-ChildItem -LiteralPath $sourceFull -Force | Where-Object {
        $_.Name -notin @('gstglass-config.js') -and $_.Name -notlike '*.runtime.js' -and $_.Name -notlike '*.local.js'
    } | ForEach-Object {
        $target = Join-Path $destFull $_.Name
        if ($_.PSIsContainer) {
            Copy-Item -LiteralPath $_.FullName -Destination $target -Recurse -Force -ErrorAction Stop
        }
        else {
            Copy-Item -LiteralPath $_.FullName -Destination $target -Force -ErrorAction Stop
        }
    }

    return [pscustomobject]@{ Copied = $true; Source = $sourceFull; Destination = $destFull; SourceVersion = $sourceVersion; DestinationVersion = $destVersion }
}

function Ensure-DirectWebRtcRuntimeWebDirectory {
    param([string]$SourceDirectory, [switch]$ForceRefresh)

    if ([string]::IsNullOrWhiteSpace($SourceDirectory) -or -not (Test-DirectWebRtcWebDirectory $SourceDirectory)) {
        return ''
    }

    try {
        $runtime = Get-DirectWebRtcWorkingWebDirectory
        $script:DirectWebRtcRuntimeWebDirectory = $runtime
        $result = Copy-DirectWebRtcStaticWebAssets -SourceDirectory $SourceDirectory -DestinationDirectory $runtime -ForceRefresh:$ForceRefresh
        if ($result.Copied) {
            Append-Log "Direct WebRTC web UI updated: $($result.Source) -> $($result.Destination) [$($result.DestinationVersion) -> $($result.SourceVersion)]"
        }
        return ([System.IO.Path]::GetFullPath($runtime))
    }
    catch {
        Append-Log "Direct WebRTC runtime web UI sync failed: $($_.Exception.Message)"
        return $SourceDirectory
    }
}

function Get-DirectWebRtcWebDirectory {
    $source = Get-DirectWebRtcSourceWebDirectory
    return (Ensure-DirectWebRtcRuntimeWebDirectory $source)
}

function Get-PlayerSettingsFromUi {
    $watchdog = $script:DefaultJbufWatchdogMode
    if ($cmbJbufWatchdogMode -and $cmbJbufWatchdogMode.SelectedItem) { $watchdog = [string]$cmbJbufWatchdogMode.SelectedItem }

    return [ordered]@{
        AudioJbufMs = [int]$numDirectWebRtcPlayerJitterMs.Value
        VideoJbufMs = [int]$numDirectWebRtcVideoJitterMs.Value
        JbufMaxMs = [int]$numJbufMaxMs.Value
        JbufWatchdogMode = $watchdog
        JbufDebug = [bool]($chkPlayerJbufDebug -and $chkPlayerJbufDebug.Checked)
        StatsOverlay = [bool]($chkPlayerStatsOverlay -and $chkPlayerStatsOverlay.Checked)
        LiveEdgeGreenMs = [int]$numLiveEdgeGreenMs.Value
        LiveEdgeYellowMs = [int]$numLiveEdgeYellowMs.Value
        LiveEdgeAverageSec = [int]$numLiveEdgeAverageSec.Value
        UrlOverrides = [bool]($chkPlayerUrlOverrides -and $chkPlayerUrlOverrides.Checked)
        SeparateHtmlMediaElements = [bool]($chkPlayerSeparateHtmlMediaElements -and $chkPlayerSeparateHtmlMediaElements.Checked)
        AvRenderMode = if ($chkPlayerSeparateHtmlMediaElements -and $chkPlayerSeparateHtmlMediaElements.Checked) { 'Decoupled video/audio elements' } else { 'Synced single media element' }
        AvPipelineMode = [string](Get-DirectWebRtcAvPipelineMode)
        MediaStreamGrouping = [string](Get-DirectWebRtcMediaStreamGrouping)
        VideoMediaStreamId = [string](Get-DirectWebRtcMediaStreamId -Kind video)
        AudioMediaStreamId = [string](Get-DirectWebRtcMediaStreamId -Kind audio)
        SplitPlayerSyncMode = [string](Get-ComboSelectedOrDefault $cmbSplitPlayerSyncMode $script:DefaultSplitPlayerSyncMode)
        SplitAudioStallSeconds = [int]$numSplitAudioStallSeconds.Value
        SplitAudioWarmupSeconds = [int]$numSplitAudioWarmupSeconds.Value
        JbufWatchdogWarmupSeconds = [int]$numSplitAudioWarmupSeconds.Value
        WatchdogWarmupSeconds = [int]$numSplitAudioWarmupSeconds.Value
        SplitAvOffsetBaselineMs = [int]$numSplitAvOffsetBaselineMs.Value
        SplitAvOffsetWarnMs = [int]$numSplitAvOffsetWarnMs.Value
        WebPath = [string]$txtDirectWebRtcWebPath.Text
        BundledWebMode = [string]$cmbDirectWebRtcBundledWebMode.SelectedItem
        BundledWebDirectory = [string]$txtDirectWebRtcBundledWebDirectory.Text
        WorkingWebMode = [string]$cmbDirectWebRtcWorkingWebMode.SelectedItem
        WebDirectory = [string]$txtDirectWebRtcWebDirectory.Text
    }
}

function Update-DirectWebRtcWebUiStatus {
    if (-not $lblDirectWebRtcWebUiStatus) { return }
    try {
        $bundled = Get-BundledDirectWebRtcWebDirectory
        $working = Get-DirectWebRtcWorkingWebDirectory
        $script:DirectWebRtcRuntimeWebDirectory = $working
        $bundledOk = Test-DirectWebRtcWebDirectory $bundled
        $workingOk = Test-DirectWebRtcWebDirectory $working
        $workingStats = Test-DirectWebRtcWebUiHasJbufStats $working
        $bundledVersion = Get-DirectWebRtcWebUiVersion $bundled
        $workingVersion = Get-DirectWebRtcWebUiVersion $working
        $runtimeConfig = Join-Path $working 'gstglass-config.js'
        $configState = if (Test-Path -LiteralPath $runtimeConfig -PathType Leaf) { 'config OK' } else { 'config missing' }

        $text = "Bundled: $bundled"
        if ($bundledOk) { $text += "  [v$bundledVersion]" } else { $text += '  [missing]' }
        $text += "`r`nWorking: $working"
        if ($workingOk -and $workingStats) { $text += "  [v$workingVersion, stats OK, $configState]" }
        elseif ($workingOk) { $text += "  [v$workingVersion, missing stats markers, $configState]" }
        else { $text += "  [missing/static sync needed, $configState]" }
        $lblDirectWebRtcWebUiStatus.Text = $text
    }
    catch {
        $lblDirectWebRtcWebUiStatus.Text = "Web UI status check failed: $($_.Exception.Message)"
    }
}

function Add-DirectWebRtcViewerQuery {
    param([string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) { return $Url }

    # Normal operation is config-driven: /live/ loads gstglass-config.js with cache busting.
    # Only append the long query string when explicitly requested for debug/share testing.
    $playerSettings = Get-PlayerSettingsFromUi
    if (-not $playerSettings.UrlOverrides) { return $Url }

    $audioJitterMs = [int]$playerSettings.AudioJbufMs
    $videoJitterMs = [int]$playerSettings.VideoJbufMs
    $fallbackJitterMs = $audioJitterMs
    $maxMs = [int]$playerSettings.JbufMaxMs
    $watchdog = [System.Uri]::EscapeDataString([string]$playerSettings.JbufWatchdogMode)
    $debug = if ($playerSettings.JbufDebug) { '1' } else { '0' }
    $liveEdgeGreenMs = [int]$playerSettings.LiveEdgeGreenMs
    $liveEdgeYellowMs = [int]$playerSettings.LiveEdgeYellowMs
    $liveEdgeAverageSec = [int]$playerSettings.LiveEdgeAverageSec
    $warmupSeconds = [int]$playerSettings.WatchdogWarmupSeconds
    $avRenderMode = [System.Uri]::EscapeDataString([string]$playerSettings.AvRenderMode)
    $separateHtmlMediaElements = if ($playerSettings.SeparateHtmlMediaElements) { 1 } else { 0 }
    $effectiveAvPipelineMode = if (Test-DirectWebRtcUnifiedPublisher) { 'Unified publisher - one producer' } else { [string](Get-DirectWebRtcAvPipelineMode) }
    $avPipelineMode = [System.Uri]::EscapeDataString($effectiveAvPipelineMode)
    $effectiveMediaStreamGrouping = if (Test-DirectWebRtcSeparateMediaStreams) { [string](Get-DirectWebRtcMediaStreamGrouping) } else { $script:DefaultDirectWebRtcMediaStreamGrouping }
    $mediaStreamGrouping = [System.Uri]::EscapeDataString($effectiveMediaStreamGrouping)
    $videoMediaStreamId = [System.Uri]::EscapeDataString((Get-DirectWebRtcMediaStreamId -Kind video))
    $audioMediaStreamId = [System.Uri]::EscapeDataString((Get-DirectWebRtcMediaStreamId -Kind audio))
    $videoSignalPort = [int]$numDirectWebRtcSignalingPort.Value
    $splitAudioPort = if ((Test-DirectWebRtcSplitAvPipelines) -and -not (Test-DirectWebRtcUnifiedPublisher)) { [int](Get-DirectWebRtcSplitAudioSignalingPort) } else { 0 }
    $sharedSignaling = if (Test-DirectWebRtcSharedSignaling) { 1 } else { 0 }
    $splitAudioPart = if ($splitAudioPort -gt 0) { "&splitAudioPort=$splitAudioPort&splitAudioSignalingPort=$splitAudioPort&sharedSignaling=$sharedSignaling&splitSharedSignaling=$sharedSignaling" } else { '' }
    $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $joiner = if ($Url -match '\?') { '&' } else { '?' }

    return ($Url + $joiner + "signalPort=$videoSignalPort&videoSignalingPort=$videoSignalPort&audioJbufMs=$audioJitterMs&videoJbufMs=$videoJitterMs&jitterMs=$fallbackJitterMs&browserJitterTargetMs=$fallbackJitterMs&jbufMaxMs=$maxMs&jbufWatchdog=$watchdog&jbufDebug=$debug&liveEdgeGreenMs=$liveEdgeGreenMs&liveEdgeYellowMs=$liveEdgeYellowMs&liveEdgeAverageSec=$liveEdgeAverageSec&watchdogWarmupSeconds=$warmupSeconds&jbufWatchdogWarmupSeconds=$warmupSeconds&splitAudioWarmupSeconds=$warmupSeconds&separateHtmlMediaElements=$separateHtmlMediaElements&playerSeparateHtmlMediaElements=$separateHtmlMediaElements&avRenderMode=$avRenderMode&playerAvRenderMode=$avRenderMode&avPipelineMode=$avPipelineMode&mediaStreamGrouping=$mediaStreamGrouping&videoMsid=$videoMediaStreamId&audioMsid=$audioMediaStreamId$splitAudioPart&cb=$stamp")
}

function Get-DirectWebRtcViewerUrl {
    $address = Normalize-DirectWebRtcWebAddress $txtDestination.Text

    # 0.0.0.0 is a listen/bind address, not a URL most browsers can open.
    # Use localhost for the local Open Viewer button while preserving the
    # configured bind address in the actual GStreamer property.
    $address = $address -replace '://0\.0\.0\.0(?=[:/])', '://127.0.0.1'
    $address = $address -replace '://\*(?=[:/])', '://127.0.0.1'
    $path = Normalize-DirectWebRtcWebPath $txtDirectWebRtcWebPath.Text
    if ($path -eq '/') { return (Add-DirectWebRtcViewerQuery $address) }

    # warp's static directory handler is happier with the mounted directory URL
    # ending in a slash. Without this, /live can 404 while /live/ serves index.html.
    return (Add-DirectWebRtcViewerQuery ($address.TrimEnd('/') + $path + '/'))
}

function Update-UnifiedBridgeKeyframeUi {
    if (-not $chkUnifiedBridgeKeyframeGuard -or -not $numUnifiedBridgeKeyframeIntervalMs) { return }

    $codecSupported = $false
    try {
        $definition = Get-SelectedEncoderDefinition
        $codecSupported = ([string]$definition.Codec -in @('H264','H265'))
    }
    catch {
        $codecSupported = $false
    }

    $available = (Test-DirectWebRtcUnifiedPublisher) -and $codecSupported
    $chkUnifiedBridgeKeyframeGuard.Enabled = $available
    $numUnifiedBridgeKeyframeIntervalMs.Enabled = $available -and $chkUnifiedBridgeKeyframeGuard.Checked
}

function Update-DirectWebRtcUi {
    $directEnabled = Test-DirectWebRtcProtocol
    $webRtcTransportEnabled = Test-WebRtcTransportProtocol

    foreach ($control in @(
        $lblDirectWebRtcStatus,
        $txtDirectWebRtcSignalingHost,
        $numDirectWebRtcSignalingPort,
        $numDirectWebRtcSplitAudioSignalingPort,
        $chkDirectWebRtcSharedSignaling,
        $chkSplitClockSignalingOverrides,
        $cmbSplitVideoClockSignaling,
        $cmbSplitAudioClockSignaling,
        $cmbDirectWebRtcMediaStreamGrouping,
        $txtDirectWebRtcVideoMediaStreamId,
        $txtDirectWebRtcAudioMediaStreamId,
        $chkDirectWebRtcUnifiedPublisher,
        $numDirectWebRtcBridgeVideoPort,
        $numDirectWebRtcBridgeAudioPort,
        $numDirectWebRtcBridgeJitterMs,
        $numDirectWebRtcPublisherQueueMs,
        $chkDirectWebRtcAudioBridgePacing,
        $chkDirectWebRtcControlDataChannel,
        $cmbDirectWebRtcBundlePolicy,
        $numDirectWebRtcInternalRtpMtu,
        $chkDirectWebRtcInternalRepeatHeaders,
        $txtDirectWebRtcWebPath,
        $cmbDirectWebRtcBundledWebMode,
        $txtDirectWebRtcBundledWebDirectory,
        $btnBrowseDirectWebRtcBundledWebDirectory,
        $btnDetectDirectWebRtcBundledWebDirectory,
        $cmbDirectWebRtcWorkingWebMode,
        $txtDirectWebRtcWebDirectory,
        $btnBrowseDirectWebRtcWebDirectory,
        $btnDetectDirectWebRtcWebDirectory,
        $btnRefreshDirectWebRtcWebUi,
        $btnOpenDirectWebRtcServedDir,
        $btnOpenDirectWebRtcBundledDir,
        $lblDirectWebRtcWebUiStatus,
        $lblDirectWebRtcPlayerJitterMs,
        $numDirectWebRtcPlayerJitterMs,
        $lblDirectWebRtcVideoJitterMs,
        $numDirectWebRtcVideoJitterMs,
        $lblJbufMaxMs,
        $numJbufMaxMs,
        $lblJbufWatchdogMode,
        $cmbJbufWatchdogMode,
        $chkPlayerStatsOverlay,
        $chkPlayerJbufDebug,
        $numLiveEdgeAverageSec,
        $numLiveEdgeGreenMs,
        $numLiveEdgeYellowMs,
        $chkPlayerUrlOverrides,
        $chkPlayerSeparateHtmlMediaElements,
        $cmbSplitPlayerSyncMode,
        $numSplitAudioStallSeconds,
        $numSplitAudioWarmupSeconds,
        $numSplitAvOffsetWarnMs,
        $btnOpenDirectWebRtcViewer,
        $btnCopyDirectWebRtcViewer
    )) {
        if ($control) { $control.Enabled = $directEnabled }
    }

    if ($lblDirectWebRtcStatus) { $lblDirectWebRtcStatus.Enabled = ($directEnabled -or $webRtcTransportEnabled) }

    $splitModeEnabled = $directEnabled -and (Test-DirectWebRtcSplitAvPipelines)
    $unifiedPublisherEnabled = $splitModeEnabled -and (Test-DirectWebRtcUnifiedPublisher)
    if ($chkPlayerSeparateHtmlMediaElements) {
        # Two independent WebRTC producers cannot share the original event MediaStream;
        # unified-publisher mode returns to one PeerConnection and can use either render path.
        $chkPlayerSeparateHtmlMediaElements.Enabled = $directEnabled -and (-not $splitModeEnabled -or $unifiedPublisherEnabled)
    }
    if ($chkDirectWebRtcUnifiedPublisher) { $chkDirectWebRtcUnifiedPublisher.Enabled = $splitModeEnabled }
    if ($chkDirectWebRtcSharedSignaling) { $chkDirectWebRtcSharedSignaling.Enabled = $splitModeEnabled -and -not $unifiedPublisherEnabled }
    $singlePipelineGroupingAvailable = $webRtcTransportEnabled -and -not $splitModeEnabled
    $separateMediaStreamsEnabled = $singlePipelineGroupingAvailable -and ((Get-DirectWebRtcMediaStreamGrouping) -like 'Separate audio/video MediaStreams*')
    if ($cmbDirectWebRtcMediaStreamGrouping) { $cmbDirectWebRtcMediaStreamGrouping.Enabled = $singlePipelineGroupingAvailable }
    if ($txtDirectWebRtcVideoMediaStreamId) { $txtDirectWebRtcVideoMediaStreamId.Enabled = $separateMediaStreamsEnabled }
    if ($txtDirectWebRtcAudioMediaStreamId) { $txtDirectWebRtcAudioMediaStreamId.Enabled = $separateMediaStreamsEnabled }
    if ($numDirectWebRtcSplitAudioSignalingPort) { $numDirectWebRtcSplitAudioSignalingPort.Enabled = $splitModeEnabled -and -not $unifiedPublisherEnabled -and -not (Test-DirectWebRtcSharedSignaling) }
    if ($numDirectWebRtcBridgeVideoPort) { $numDirectWebRtcBridgeVideoPort.Enabled = $unifiedPublisherEnabled }
    if ($numDirectWebRtcBridgeAudioPort) { $numDirectWebRtcBridgeAudioPort.Enabled = $unifiedPublisherEnabled }
    if ($numDirectWebRtcBridgeJitterMs) { $numDirectWebRtcBridgeJitterMs.Enabled = $unifiedPublisherEnabled }
    if ($numDirectWebRtcPublisherQueueMs) { $numDirectWebRtcPublisherQueueMs.Enabled = $unifiedPublisherEnabled }
    if ($chkDirectWebRtcAudioBridgePacing) { $chkDirectWebRtcAudioBridgePacing.Enabled = $unifiedPublisherEnabled }
    if ($chkDirectWebRtcControlDataChannel) { $chkDirectWebRtcControlDataChannel.Enabled = $unifiedPublisherEnabled }
    if ($cmbDirectWebRtcBundlePolicy) { $cmbDirectWebRtcBundlePolicy.Enabled = $unifiedPublisherEnabled }
    if ($numDirectWebRtcInternalRtpMtu) { $numDirectWebRtcInternalRtpMtu.Enabled = $unifiedPublisherEnabled }
    if ($chkDirectWebRtcInternalRepeatHeaders) { $chkDirectWebRtcInternalRepeatHeaders.Enabled = $unifiedPublisherEnabled }
    Update-UnifiedBridgeKeyframeUi
    Update-TimestampUi

    foreach ($control in @(
        $txtDirectWebRtcStun,
        $chkDirectWebRtcTurnEnabled,
        $cmbDirectWebRtcCongestion,
        $numDirectWebRtcStartBitrateKbps,
        $numDirectWebRtcMinBitrateKbps,
        $cmbDirectWebRtcMitigation,
        $lblWebRtcRecoveryMode,
        $cmbWebRtcRecoveryMode,
        $lblWebRtcSenderQueueMode,
        $cmbWebRtcSenderQueueMode,
        $lblDirectWebRtcSmoothnessProfile,
        $cmbDirectWebRtcSmoothnessProfile,
        $lblDirectWebRtcPacingMs,
        $numDirectWebRtcPacingMs
    )) {
        if ($control) { $control.Enabled = $webRtcTransportEnabled }
    }

    if ($txtDirectWebRtcTurn) { $txtDirectWebRtcTurn.Enabled = $webRtcTransportEnabled -and $chkDirectWebRtcTurnEnabled.Checked }

    if ($directEnabled) {
        $webDir = Get-DirectWebRtcWebDirectory
        if ([string]::IsNullOrWhiteSpace($webDir)) {
            $lblDirectWebRtcStatus.Text = "Direct WebRTC viewer: $(Get-DirectWebRtcViewerUrl) - web UI dir not found; 404 likely"
            $lblDirectWebRtcStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        else {
            $groupingStatus = if (Test-DirectWebRtcSeparateMediaStreams) { "separate msid V=$(Get-DirectWebRtcMediaStreamId -Kind video) A=$(Get-DirectWebRtcMediaStreamId -Kind audio)" } else { 'combined A/V MediaStream' }
            $lblDirectWebRtcStatus.Text = "Direct WebRTC viewer: $(Get-DirectWebRtcViewerUrl) - $([string]$cmbDirectWebRtcSmoothnessProfile.SelectedItem) - $groupingStatus"
            $lblDirectWebRtcStatus.ForeColor = [System.Drawing.Color]::DarkSlateBlue
        }
    }
    elseif ($webRtcTransportEnabled) {
        $lblDirectWebRtcStatus.Text = 'WebRTC transport knobs active for WHIP/MediaMTX publish.'
        $lblDirectWebRtcStatus.ForeColor = [System.Drawing.Color]::DarkSlateBlue
    }
    else {
        $lblDirectWebRtcStatus.Text = 'WebRTC transport knobs disabled for this protocol'
        $lblDirectWebRtcStatus.ForeColor = [System.Drawing.Color]::DimGray
    }

    Update-DirectWebRtcWebUiStatus
}

