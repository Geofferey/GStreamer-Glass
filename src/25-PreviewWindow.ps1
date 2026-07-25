function Ensure-PreviewParkingWindow {
    if ($script:PreviewParkForm -and -not $script:PreviewParkForm.IsDisposed) {
        return $script:PreviewParkForm
    }

    $park = New-Object System.Windows.Forms.Form
    $park.Text = 'GStreamer Glass Preview Parking'
    $park.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $park.ShowInTaskbar = $false
    $park.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $park.Location = New-Object System.Drawing.Point(-32000, -32000)
    $park.Size = New-Object System.Drawing.Size(16, 16)
    $park.Opacity = 0.01
    $park.TopMost = $false

    # Keep this window visible. Hiding/minimizing the parent is what makes the
    # d3d11videosink preview come back black on some Windows systems.
    $park.Show()
    $script:PreviewParkForm = $park
    return $script:PreviewParkForm
}

function Park-PreviewWindow {
    if ($script:PreviewHwnd -eq [IntPtr]::Zero) {
        return
    }

    try {
        $park = Ensure-PreviewParkingWindow
        [void][GstPreviewNative]::ReparentEmbeddedWindow(
            $script:PreviewHwnd,
            $park.Handle,
            16,
            16,
            $true
        )
        $script:PreviewParked = $true
        Reset-PreviewAppliedState
    }
    catch {}
}

function Restore-PreviewWindowFromParking {
    if ($script:PreviewHwnd -eq [IntPtr]::Zero) {
        return
    }

    try {
        [void][GstPreviewNative]::ReparentEmbeddedWindow(
            $script:PreviewHwnd,
            $previewPanel.Handle,
            $previewPanel.ClientSize.Width,
            $previewPanel.ClientSize.Height,
            (Test-PreviewVisibleNow)
        )
        $script:PreviewParked = $false
        Reset-PreviewAppliedState
    }
    catch {}
}

function Reset-PreviewAppliedState {
    # Anything that reparents, hides, or replaces the embedded renderer window
    # invalidates what we believe we last pushed to it, so force the next
    # Set-PreviewVisibility to re-apply geometry and visibility.
    $script:PreviewAppliedSize = [System.Drawing.Size]::Empty
    $script:PreviewAppliedVisible = $null
}

function Set-PreviewVisibility {
    $formIsHiddenForTray =
        (-not $form.Visible) -or
        ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized)
    $previewVisibleNow = [bool](Test-PreviewVisibleNow)

    if ($script:PreviewHwnd -eq [IntPtr]::Zero) {
        $previewPlaceholder.Visible = $true
        $previewPlaceholder.Text = if ($formIsHiddenForTray) {
            'Preview parked while app is in tray'
        }
        elseif ($previewVisibleNow) {
            'Preview starting...'
        }
        else {
            'Preview hidden - stream still running'
        }
        return
    }

    if ($formIsHiddenForTray) {
        Park-PreviewWindow
        $previewPlaceholder.Visible = $true
        $previewPlaceholder.Text = 'Preview parked while app is in tray'
        return
    }

    if (-not $previewVisibleNow) {
        # Reparent the foreign renderer into the hidden parking form instead of
        # merely hiding its HWND. Controlled-live layout polling and D3D11 sink
        # repaint events can otherwise make it flash back over the Scene editor.
        if (-not $script:PreviewParked) { Park-PreviewWindow }
        if (-not $script:PreviewParked -and $script:PreviewAppliedVisible -ne $false) {
            [GstPreviewNative]::SetWindowVisible($script:PreviewHwnd, $false)
            $script:PreviewAppliedVisible = $false
        }
        $previewPlaceholder.Visible = $true
        $previewPlaceholder.Text = if ($chkHidePreviewDuringStream -and $chkHidePreviewDuringStream.Checked -and (Test-TransportEnabled)) {
            'Preview hidden during stream'
        }
        else {
            'Preview hidden - stream still running'
        }
        return
    }

    if ($script:PreviewParked) { Restore-PreviewWindowFromParking }

    if ($previewVisibleNow) {
        # Only touch the renderer window when something actually changed. This runs
        # every poll tick; unconditional resize/show on a live d3d11videosink is a
        # stutter source.
        $clientSize = $previewPanel.ClientSize
        if (
            $clientSize.Width -ne $script:PreviewAppliedSize.Width -or
            $clientSize.Height -ne $script:PreviewAppliedSize.Height
        ) {
            [GstPreviewNative]::ResizeEmbeddedWindow(
                $script:PreviewHwnd,
                $clientSize.Width,
                $clientSize.Height
            )
            $script:PreviewAppliedSize = $clientSize
        }

        if ($script:PreviewAppliedVisible -ne $true) {
            [GstPreviewNative]::SetWindowVisible($script:PreviewHwnd, $true)
            $script:PreviewAppliedVisible = $true
        }
        $previewPlaceholder.Visible = $false
    }
}

function Try-AttachPreview {
    if ($script:ControlledLiveStreamActive) {
        Sync-ControlledLivePreviewLayout
        return
    }

    if ($script:DynamicScenePreviewActive) {
        Try-AttachDynamicScenePreview
        return
    }

    $previewProcess = if ((Test-DirectWebRtcUnifiedPublisher) -and $script:GstVideoProcess) { $script:GstVideoProcess } else { $script:GstProcess }
    if (-not $script:PipelineHasPreview -or -not $previewProcess -or $previewProcess.HasExited) {
        return
    }

    if ($script:PreviewHwnd -eq [IntPtr]::Zero) {
        $candidate = [GstPreviewNative]::FindPreviewWindow($previewProcess.Id)
        if ($candidate -ne [IntPtr]::Zero) {
            if ([GstPreviewNative]::EmbedWindow($candidate, $previewPanel.Handle, $previewPanel.ClientSize.Width, $previewPanel.ClientSize.Height)) {
                $script:PreviewHwnd = $candidate
                $script:PreviewParked = $false
                Reset-PreviewAppliedState
                Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Preview window embedded for runtime toggle."
            }
        }
    }

    Set-PreviewVisibility
}

function Test-UseDynamicScenePreview {
    try {
        if (-not (Test-DynamicScenePreviewWanted)) { return $false }
        return (
            -not $script:ControlledLiveStreamActive -and
            -not ($script:GstProcess -and -not $script:GstProcess.HasExited)
        )
    }
    catch {
        return $false
    }
}

function Test-DynamicScenePreviewWanted {
    try {
        $dynamicPreviewContextAllowed = (
            $script:SceneWorkspaceActive -or
            ($chkStandardPreviewOffSceneTab -and -not $chkStandardPreviewOffSceneTab.Checked)
        )

        return (
            $dynamicPreviewContextAllowed -and
            $script:DynamicPreviewUiReady -and
            -not $script:SuppressDynamicScenePreview -and
            $chkDynamicScenePreviews -and $chkDynamicScenePreviews.Checked -and
            $chkSceneEnabled -and $chkSceneEnabled.Checked -and
            $chkPreview -and $chkPreview.Checked -and
            (Test-StandalonePreviewAllowed)
        )
    }
    catch {
        return $false
    }
}

function ConvertTo-InProcessGstLaunchDescription {
    param([Parameter(Mandatory)][string]$Description)

    # -e/-v are gst-launch executable switches, not pipeline grammar.
    $pipeline = [regex]::Replace(
        $Description,
        '^\s*(?:(?:-e|-v)\s+)+',
        ''
    )
    # Build-* emits quoted caps so Windows command-line parsing passes each caps
    # expression to gst-launch as one argument. gst_parse_launch receives the
    # description directly, so those shell-only quote characters must not be
    # present. Preserve quotes on paths/string properties and unwrap caps only.
    return [regex]::Replace(
        $pipeline,
        '"((?:audio|video|application)/[^"]+)"',
        '$1'
    )
}

function Build-ControlledScenePreviewPipeline {
    $sceneChain = Build-SceneCaptureChain -LocalOnly
    $pipeline = "$sceneChain ! queue max-size-buffers=1 max-size-bytes=0 max-size-time=0 leaky=downstream ! d3d11videosink name=controlledpreview sync=false force-aspect-ratio=true"
    return (ConvertTo-InProcessGstLaunchDescription -Description $pipeline)
}

function Close-ControlledLiveWorkerPipe {
    try { if ($script:ControlledLiveWorkerWriter) { $script:ControlledLiveWorkerWriter.Dispose() } } catch {}
    try { if ($script:ControlledLiveWorkerReader) { $script:ControlledLiveWorkerReader.Dispose() } } catch {}
    try { if ($script:ControlledLiveWorkerPipe) { $script:ControlledLiveWorkerPipe.Dispose() } } catch {}
    $script:ControlledLiveWorkerWriter = $null
    $script:ControlledLiveWorkerReader = $null
    $script:ControlledLiveWorkerPipe = $null
}

function Send-ControlledLiveWorkerCommand {
    param([Parameter(Mandatory)][hashtable]$Command)

    if (-not (Test-ControlledLiveWorkerRunning)) { return $false }
    try {
        $script:ControlledLiveWorkerWriter.WriteLine(($Command | ConvertTo-Json -Compress))
        return $true
    }
    catch {
        Append-Log "Controlled live worker command failed: $($_.Exception.Message)"
        return $false
    }
}

function Wait-UiResponsiveTask {
    param(
        [Parameter(Mandatory)][System.Threading.Tasks.Task]$Task,
        [Parameter(Mandatory)][int]$TimeoutMs
    )

    $deadline = [DateTime]::UtcNow.AddMilliseconds([Math]::Max(1, $TimeoutMs))
    while (-not $Task.IsCompleted -and [DateTime]::UtcNow -lt $deadline) {
        [System.Windows.Forms.Application]::DoEvents()
        if ($script:PendingPipelineStop) { return $false }
        [System.Threading.Thread]::Sleep(20)
    }
    if (-not $Task.IsCompleted) { return $false }
    if ($Task.IsFaulted) { throw ($Task.Exception.GetBaseException()) }
    if ($Task.IsCanceled) { throw 'The controlled worker operation was cancelled.' }
    return $true
}

function Start-ControlledLiveWorker {
    param(
        [Parameter(Mandatory)][string]$Pipeline,
        [Parameter(Mandatory)][IntPtr]$WindowHandle,
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height
    )

    Close-ControlledLiveWorkerPipe
    $pipeName = "gstglass-live-$PID-$([Guid]::NewGuid().ToString('N'))"
    $process = $null
    $pipe = $null
    $reader = $null
    $writer = $null

    try {
        $currentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
        $currentExe = $currentProcess.MainModule.FileName
        $currentName = [System.IO.Path]::GetFileNameWithoutExtension($currentExe)
        if ($currentName -match '^(powershell|pwsh|powershell_ise)$') {
            if ([string]::IsNullOrWhiteSpace($PSCommandPath) -or -not (Test-Path -LiteralPath $PSCommandPath)) {
                throw 'The current script path is unavailable; the controlled worker cannot be launched.'
            }
            $escapedScript = $PSCommandPath.Replace('"', '\"')
            $arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$escapedScript`" -ControlledLiveWorker -ControlledLiveWorkerPipe `"$pipeName`""
        }
        else {
            # PS2EXE/PS12EXE builds can relaunch their own executable and use
            # the same hidden worker switch handled near the top of this file.
            $arguments = "-ControlledLiveWorker -ControlledLiveWorkerPipe `"$pipeName`""
        }

        $startParams = @{
            FilePath    = $currentExe
            ArgumentList = $arguments
            WindowStyle = 'Hidden'
            PassThru    = $true
        }
        if (Test-ProcessDiskLoggingEnabled) {
            $startParams.RedirectStandardOutput = $script:StdOutPath
            $startParams.RedirectStandardError = $script:StdErrPath
        }
        $process = Start-Process @startParams
        Set-GstProcessPriority -Process $process
        if ($script:JobHandle -ne [IntPtr]::Zero) {
            try { [GstProcessJob]::AssignProcess($script:JobHandle, $process.Handle) }
            catch { Append-Log "WARNING: Controlled live worker could not be assigned to the kill-on-close job: $($_.Exception.Message)" }
        }

        $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(
            '.',
            $pipeName,
            [System.IO.Pipes.PipeDirection]::InOut,
            [System.IO.Pipes.PipeOptions]::None
        )
        $connectTask = $pipe.ConnectAsync(12000)
        if (-not (Wait-UiResponsiveTask -Task $connectTask -TimeoutMs 12500)) {
            if ($script:PendingPipelineStop) { throw 'Controlled worker startup cancelled by Stop.' }
            throw 'The controlled live worker pipe did not connect within 12 seconds.'
        }
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $reader = New-Object System.IO.StreamReader($pipe, $utf8, $false, 4096, $true)
        $writer = New-Object System.IO.StreamWriter($pipe, $utf8, 4096, $true)
        $writer.AutoFlush = $true
        $writer.WriteLine((@{
            Type         = 'Start'
            Pipeline     = $Pipeline
            # Let d3d11videosink create a worker-owned window, then embed that
            # HWND with the same Win32 path as every external gst-launch preview.
            WindowHandle = [int64]0
            Width        = [Math]::Max(1, $Width)
            Height       = [Math]::Max(1, $Height)
            DesktopPad   = 'sink_0'
            WebcamPad    = 'sink_1'
        } | ConvertTo-Json -Compress))

        $replyTask = $reader.ReadLineAsync()
        if (-not (Wait-UiResponsiveTask -Task $replyTask -TimeoutMs 15000)) {
            if ($script:PendingPipelineStop) { throw 'Controlled worker startup cancelled by Stop.' }
            throw 'The controlled live worker did not acknowledge startup within 15 seconds.'
        }
        $replyLine = $replyTask.Result
        if ([string]::IsNullOrWhiteSpace($replyLine)) { throw 'The controlled live worker exited before acknowledging startup.' }
        $reply = $replyLine | ConvertFrom-Json
        if ([string]$reply.Status -ne 'Ready') { throw "Controlled live worker start failed: $([string]$reply.Error)" }

        $script:ControlledLiveWorkerPipe = $pipe
        $script:ControlledLiveWorkerReader = $reader
        $script:ControlledLiveWorkerWriter = $writer
        $script:GstProcess = $process
        return $true
    }
    catch {
        try { if ($process -and -not $process.HasExited) { Stop-ProcessTreeById -ProcessId $process.Id } } catch {}
        try { if ($writer) { $writer.Dispose() } } catch {}
        try { if ($reader) { $reader.Dispose() } } catch {}
        try { if ($pipe) { $pipe.Dispose() } } catch {}
        try { if ($process) { $process.Dispose() } } catch {}
        throw
    }
}

function Test-ControlledLiveStreamRequested {
    param([switch]$PreviewOnly)

    try {
        if ($PreviewOnly) { return $false }
        if ($script:SuppressControlledLiveStream) { return $false }
        if (-not $script:DynamicPreviewUiReady) { return $false }
        if (-not $chkLiveSceneEditing -or -not $chkLiveSceneEditing.Checked) { return $false }
        if (-not $chkDynamicScenePreviews -or -not $chkDynamicScenePreviews.Checked) { return $false }
        if (-not $chkSceneEnabled -or -not $chkSceneEnabled.Checked) { return $false }
        if ([string]$cmbScenePreset.SelectedItem -ne 'Desktop + webcam') { return $false }
        if (-not $chkPreview -or -not $chkPreview.Checked) { return $false }
        if (Test-FullscreenCaptureMode) { return $false }

        # Unified-publisher and split-A/V modes have the scene capture in a
        # different process from the primary pipeline. Keep their proven process
        # topology until each bridge is migrated deliberately.
        if (Test-DirectWebRtcUnifiedPublisher) { return $false }
        if (Test-DirectWebRtcSplitAvPipelines) { return $false }
        return $true
    }
    catch {
        return $false
    }
}

function Start-DynamicScenePreview {
    if ($script:DynamicScenePreviewActive -or $script:DynamicScenePreviewStarting) { return $true }
    if (-not (Test-UseDynamicScenePreview)) { return $false }

    $script:DynamicScenePreviewStarting = $true
    try {
        Reset-DynamicScenePreviewFallback
        Stop-GstStream
        $script:DynamicScenePreviewActive = $true
        $script:DynamicScenePreviewStartedAt = Get-Date
        $script:PreviewOnlyMode = $true
        $script:RecordingPipelineRequested = $false
        $script:RecordingPipelineActive = $false
        $script:RecordingOnlyMode = $false
        $script:PipelineHasPreview = $false
        $script:PreviewHwnd = [IntPtr]::Zero
        Reset-PreviewAppliedState

        # The old implementation launched one sink window per source and stacked
        # those HWNDs. f70 renders the actual scene compositor into one canvas.
        $sceneDesktopPreviewPanel.Visible = $true
        $sceneWebcamPreviewPanel.Visible = $false
        $lblSceneDesktop.Visible = $false
        $script:SceneDesktopPreviewHwnd = [IntPtr]::Zero
        $script:SceneWebcamPreviewHwnd = [IntPtr]::Zero
        $script:SceneDesktopPreviewProcess = $null
        $script:SceneWebcamPreviewProcess = $null

        if (-not $script:SceneWorkspaceActive -and $chkStandardPreviewOffSceneTab -and -not $chkStandardPreviewOffSceneTab.Checked) {
            Show-DynamicScenePreviewInPreviewCard
        }

        Update-SceneCanvasFromValues
        Update-SceneSelectionChrome

        $gstPath = Resolve-GstLaunchSelection -RequestedPath $txtGstPath.Text -UpdateControl
        Prepare-GStreamerRuntime -GstPath $gstPath
        $binDirectory = Split-Path -Parent (Normalize-GstLaunchPath $gstPath)
        $nativeRuntime = Join-Path $binDirectory 'gstreamer-1.0-0.dll'
        if (-not (Test-Path -LiteralPath $nativeRuntime)) {
            throw "The selected GStreamer runtime does not contain gstreamer-1.0-0.dll: $binDirectory"
        }

        $pipeline = Build-ControlledScenePreviewPipeline
        $preset = [string]$cmbScenePreset.SelectedItem
        $desktopPadName = if ($preset -eq 'Desktop + webcam') { 'sink_0' } else { '' }
        $webcamPadName = if ($preset -eq 'Desktop + webcam') { 'sink_1' } else { '' }
        $null = $sceneDesktopPreviewPanel.Handle
        Append-Log "Controlled scene preview pipeline: $pipeline"
        [GstControlledScenePreview]::Start(
            $pipeline,
            $sceneDesktopPreviewPanel.Handle.ToInt64(),
            $sceneDesktopPreviewPanel.ClientSize.Width,
            $sceneDesktopPreviewPanel.ClientSize.Height,
            $desktopPadName,
            $webcamPadName
        )
        $script:ControlledScenePreviewSurfaceHwnd = $sceneDesktopPreviewPanel.Handle
        $script:ControlledScenePreviewAppliedSize = $sceneDesktopPreviewPanel.ClientSize
        Sync-ControlledScenePreviewProperties

        $statusLabel.Text = 'Controlled scene preview'
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkGreen
        Set-RunState $true
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Controlled scene compositor started; geometry and opacity are live."
        return $true
    }
    catch {
        Append-Log "Controlled scene preview start error: $($_.Exception.Message)"
        $script:SuppressDynamicScenePreview = $true
        Stop-DynamicScenePreview -Quiet

        # A failed parse can still construct and then tear down a partial graph.
        # Give Windows capture backends a bounded release window before the
        # external normal-preview fallback opens the same desktop/camera again.
        [System.Threading.Thread]::Sleep(750)
        return $false
    }
    finally {
        $script:DynamicScenePreviewStarting = $false
    }
}

function Stop-DynamicScenePreview {
    param([switch]$Quiet)

    $hadDynamic = [bool]$script:DynamicScenePreviewActive

    if ([GstControlledScenePreview]::IsRunning) {
        if (-not $Quiet) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Stopping controlled scene compositor..."
        }
        try { [GstControlledScenePreview]::Stop() } catch {
            Append-Log "Controlled scene preview stop warning: $($_.Exception.Message)"
        }
    }

    $script:SceneDesktopPreviewProcess = $null
    $script:SceneWebcamPreviewProcess = $null
    $script:SceneDesktopPreviewHwnd = [IntPtr]::Zero
    $script:SceneWebcamPreviewHwnd = [IntPtr]::Zero
    $script:DynamicScenePreviewActive = $false
    $script:DynamicScenePreviewStarting = $false
    $script:DynamicScenePreviewStartedAt = $null
    $script:PreviewOnlyMode = $false
    $script:RecordingPipelineRequested = $false
    $script:RecordingPipelineActive = $false
    $script:RecordingOnlyMode = $false
    $script:ControlledScenePreviewSurfaceHwnd = [IntPtr]::Zero
    $script:ControlledScenePreviewAppliedSize = [System.Drawing.Size]::Empty

    if ($sceneDesktopPreviewPanel) { $sceneDesktopPreviewPanel.Visible = $false }
    if ($sceneWebcamPreviewPanel) { $sceneWebcamPreviewPanel.Visible = $false }
    if ($lblSceneDesktop) { $lblSceneDesktop.Visible = $true }
    if ($script:SceneEditorCanvasHostedInPreview) { Restore-SceneEditorCanvasHome }
    Update-SceneSelectionChrome

    if ($hadDynamic -and -not $Quiet) {
        $statusLabel.Text = 'Stopped'
        $statusLabel.ForeColor = [System.Drawing.Color]::Black
        Set-RunState $false
    }
}

function Try-AttachDynamicScenePreview {
    if (-not $script:DynamicScenePreviewActive) { return }
    Sync-DynamicScenePreviewLayout
}

function Test-DynamicScenePreviewAttached {
    return ($script:DynamicScenePreviewActive -and [GstControlledScenePreview]::IsRunning)
}

function Invoke-DynamicScenePreviewFallback {
    param([string]$Reason = 'reported a pipeline error')

    if (-not $script:DynamicScenePreviewActive) { return }
    if ($script:DynamicScenePreviewFallbackTriggered) { return }

    $script:DynamicScenePreviewFallbackTriggered = $true
    $script:SuppressDynamicScenePreview = $true

    Append-Log (
        "[$(Get-Date -Format 'HH:mm:ss')] Dynamic scene preview $Reason; " +
        'falling back to the normal composed preview in the scene editor. ' +
        'Scene objects will not redraw dynamically until Dynamic previews is retried.'
    )

    Stop-DynamicScenePreview -Quiet
    $script:PreviewOnlyMode = $false
    $script:PreviewHwnd = [IntPtr]::Zero
    Reset-PreviewAppliedState

    if ($previewPlaceholder) {
        $previewPlaceholder.Text = 'Dynamic preview fallback: normal composed preview'
        $previewPlaceholder.Visible = $true
    }

    if ($sceneDesktopPreviewPanel) { $sceneDesktopPreviewPanel.Visible = $false }
    if ($sceneWebcamPreviewPanel) { $sceneWebcamPreviewPanel.Visible = $false }
    Update-SceneCanvasFromValues

    if ($chkPreview -and $chkPreview.Checked -and (Test-StandalonePreviewAllowed)) {
        Sync-StandalonePreviewState -Quiet
    }
}

function Sync-DynamicScenePreviewLayout {
    if (-not $script:DynamicScenePreviewActive) { return }

    try {
        if ([GstControlledScenePreview]::IsRunning -and $sceneDesktopPreviewPanel -and $sceneDesktopPreviewPanel.IsHandleCreated) {
            $surfaceHandle = $sceneDesktopPreviewPanel.Handle
            $surfaceSize = $sceneDesktopPreviewPanel.ClientSize
            if (
                $surfaceHandle -ne $script:ControlledScenePreviewSurfaceHwnd -or
                $surfaceSize.Width -ne $script:ControlledScenePreviewAppliedSize.Width -or
                $surfaceSize.Height -ne $script:ControlledScenePreviewAppliedSize.Height
            ) {
                [GstControlledScenePreview]::SetWindowHandle(
                    $surfaceHandle.ToInt64(),
                    $surfaceSize.Width,
                    $surfaceSize.Height
                )
                $script:ControlledScenePreviewSurfaceHwnd = $surfaceHandle
                $script:ControlledScenePreviewAppliedSize = $surfaceSize
            }
        }
    }
    catch {}
}

function Sync-ControlledLivePreviewLayout {
    if (-not $script:ControlledLiveStreamActive) { return }
    if (-not (Test-ControlledLiveWorkerRunning)) { return }

    try {
        if ($script:PreviewHwnd -eq [IntPtr]::Zero) {
            $candidate = [GstPreviewNative]::FindPreviewWindow($script:GstProcess.Id)
            if ($candidate -ne [IntPtr]::Zero) {
                $attachVisible = (
                    $form.Visible -and
                    $form.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized -and
                    (Test-PreviewVisibleNow)
                )
                $attachTarget = if ($attachVisible) { $previewPanel } else { Ensure-PreviewParkingWindow }
                $attachSize = if ($attachVisible) { $previewPanel.ClientSize } else { New-Object System.Drawing.Size(16, 16) }
                $null = $attachTarget.Handle
                if ([GstPreviewNative]::EmbedWindow(
                    $candidate,
                    $attachTarget.Handle,
                    $attachSize.Width,
                    $attachSize.Height
                )) {
                    $script:PreviewHwnd = $candidate
                    $script:PreviewParked = -not $attachVisible
                    Reset-PreviewAppliedState
                    Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Controlled worker preview window $(if ($attachVisible) { 'embedded' } else { 'parked while hidden' })."
                }
            }
        }

        # From this point forward use the proven external-preview reparent,
        # parking, visibility, and resize path rather than cross-process overlay
        # handle mutation.
        Set-PreviewVisibility
    }
    catch {}
}

function Restart-DynamicScenePreviewIfActive {
    if ($script:ControlledLiveStreamActive) {
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] A scene source setting changed; restarting the live pipeline to rebuild its capture graph."
        Stop-GstStream -Restart
        return
    }
    if (-not $script:DynamicScenePreviewActive) { return }
    Stop-DynamicScenePreview -Quiet
    Sync-StandalonePreviewState -Quiet
}

