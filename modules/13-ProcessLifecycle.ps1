function Initialize-GstJob {
    if ($script:JobHandle -ne [IntPtr]::Zero) {
        return
    }

    try {
        $script:JobHandle = [GstProcessJob]::CreateKillOnCloseJob()
        Append-Log 'Created kill-on-close Windows job for GStreamer and MediaMTX processes.'
    }
    catch {
        $script:JobHandle = [IntPtr]::Zero
        Append-Log "WARNING: Could not create process job: $($_.Exception.Message)"
    }
}

function Save-ActiveProcessState {
    try {
        $gstRunning =
            $script:GstProcess -and
            -not $script:GstProcess.HasExited

        $videoRunning =
            $script:GstVideoProcess -and
            -not $script:GstVideoProcess.HasExited

        $audioRunning =
            $script:GstAudioProcess -and
            -not $script:GstAudioProcess.HasExited

        $mediaRunning =
            $script:MediaMtxProcess -and
            -not $script:MediaMtxProcess.HasExited

        if (-not $gstRunning -and -not $videoRunning -and -not $audioRunning -and -not $mediaRunning) {
            Remove-ActiveProcessState
            return
        }

        if (-not (Test-Path -LiteralPath $script:ConfigDirectory)) {
            $null = New-Item -ItemType Directory -Path $script:ConfigDirectory -Force
        }

        $state = [ordered]@{
            OwnerProcessId = $PID
            AppVersion     = $script:AppVersion
        }

        if ($gstRunning) {
            $state.GstProcessId      = $script:GstProcess.Id
            $state.GstExecutablePath = if ($script:ControlledLiveStreamActive) {
                [System.IO.Path]::GetFullPath($script:GstProcess.MainModule.FileName)
            }
            else {
                [System.IO.Path]::GetFullPath($txtGstPath.Text.Trim())
            }
            $state.GstStartTimeUtc   =
                $script:GstProcess.StartTime.ToUniversalTime().ToString('o')

            # Keep the older field names for backward compatibility with state
            # files written by pre-v3.4 builds.
            $state.ProcessId      = $state.GstProcessId
            $state.ExecutablePath = $state.GstExecutablePath
            $state.StartTimeUtc   = $state.GstStartTimeUtc
        }

        if ($videoRunning) {
            $state.GstVideoProcessId = $script:GstVideoProcess.Id
            $state.GstVideoStartTimeUtc = $script:GstVideoProcess.StartTime.ToUniversalTime().ToString('o')
        }

        if ($audioRunning) {
            $state.GstAudioProcessId = $script:GstAudioProcess.Id
            $state.GstAudioStartTimeUtc = $script:GstAudioProcess.StartTime.ToUniversalTime().ToString('o')
        }

        if ($mediaRunning) {
            $state.MediaMtxProcessId      = $script:MediaMtxProcess.Id
            $state.MediaMtxExecutablePath = [System.IO.Path]::GetFullPath(
                $script:MediaMtxPathInUse
            )
            $state.MediaMtxStartTimeUtc   =
                $script:MediaMtxProcess.StartTime.ToUniversalTime().ToString('o')
        }

        $state |
            ConvertTo-Json |
            Set-Content -LiteralPath $script:ProcessStatePath -Encoding UTF8
    }
    catch {
        Append-Log "WARNING: Could not save active-process state: $($_.Exception.Message)"
    }
}

function Remove-ActiveProcessState {
    try {
        Remove-Item `
            -LiteralPath $script:ProcessStatePath `
            -Force `
            -ErrorAction SilentlyContinue
    }
    catch {}
}

function Stop-ProcessTreeById {
    param([Parameter(Mandatory)][int]$ProcessId)

    if ($ProcessId -le 0) {
        return
    }

    try {
        $arguments = "/PID $ProcessId /T /F"
        $null = Start-Process `
            -FilePath 'taskkill.exe' `
            -ArgumentList $arguments `
            -WindowStyle Hidden `
            -Wait `
            -PassThru
    }
    catch {
        try {
            Stop-Process -Id $ProcessId -Force -ErrorAction Stop
        }
        catch {}
    }
}

function Stop-VerifiedStaleProcess {
    param(
        [int]$ProcessId,
        [string]$ExecutablePath,
        [string]$StartTimeUtc,
        [string]$Label
    )

    if ($ProcessId -le 0) {
        return
    }

    if (
        ($script:GstProcess -and
         -not $script:GstProcess.HasExited -and
         $script:GstProcess.Id -eq $ProcessId) -or
        ($script:MediaMtxProcess -and
         -not $script:MediaMtxProcess.HasExited -and
         $script:MediaMtxProcess.Id -eq $ProcessId)
    ) {
        return
    }

    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $process) {
        return
    }

    $pathMatches = $false
    $timeMatches = $false

    try {
        $actualPath = [System.IO.Path]::GetFullPath($process.Path)
        $expectedPath = [System.IO.Path]::GetFullPath($ExecutablePath)
        $pathMatches = $actualPath.Equals(
            $expectedPath,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    }
    catch {}

    try {
        $expectedStart = [datetime]::Parse($StartTimeUtc).ToUniversalTime()
        $actualStart = $process.StartTime.ToUniversalTime()
        $timeMatches =
            [math]::Abs(($actualStart - $expectedStart).TotalSeconds) -le 5
    }
    catch {}

    if ($pathMatches -and $timeMatches) {
        Append-Log (
            "Found orphaned $Label process PID $ProcessId from a previous " +
            'wrapper instance; terminating its process tree.'
        )
        Stop-ProcessTreeById -ProcessId $ProcessId
    }
    else {
        Append-Log (
            "Ignored stale $Label process record for PID $ProcessId because " +
            'its executable or start time no longer matches.'
        )
    }
}

function Stop-StaleManagedProcesses {
    if (-not (Test-Path -LiteralPath $script:ProcessStatePath)) {
        return
    }

    try {
        $state =
            Get-Content -LiteralPath $script:ProcessStatePath -Raw |
            ConvertFrom-Json

        $gstPid = 0
        $gstPath = ''
        $gstStart = ''

        if ($null -ne $state.GstProcessId) {
            $gstPid = [int]$state.GstProcessId
            $gstPath = [string]$state.GstExecutablePath
            $gstStart = [string]$state.GstStartTimeUtc
        }
        elseif ($null -ne $state.ProcessId) {
            $gstPid = [int]$state.ProcessId
            $gstPath = [string]$state.ExecutablePath
            $gstStart = [string]$state.StartTimeUtc
        }

        Stop-VerifiedStaleProcess `
            -ProcessId $gstPid `
            -ExecutablePath $gstPath `
            -StartTimeUtc $gstStart `
            -Label 'GStreamer publisher/main'

        Stop-VerifiedStaleProcess `
            -ProcessId ([int]$state.GstVideoProcessId) `
            -ExecutablePath $gstPath `
            -StartTimeUtc ([string]$state.GstVideoStartTimeUtc) `
            -Label 'GStreamer video bridge'

        Stop-VerifiedStaleProcess `
            -ProcessId ([int]$state.GstAudioProcessId) `
            -ExecutablePath $gstPath `
            -StartTimeUtc ([string]$state.GstAudioStartTimeUtc) `
            -Label 'GStreamer audio bridge'

        Stop-VerifiedStaleProcess `
            -ProcessId ([int]$state.MediaMtxProcessId) `
            -ExecutablePath ([string]$state.MediaMtxExecutablePath) `
            -StartTimeUtc ([string]$state.MediaMtxStartTimeUtc) `
            -Label 'MediaMTX'
    }
    catch {
        Append-Log (
            "WARNING: Could not inspect stale managed-process state: " +
            $_.Exception.Message
        )
    }
    finally {
        Remove-ActiveProcessState
    }
}

function Update-TrayMenuState {
    try {
        $running = (
            ($script:GstProcess -and -not $script:GstProcess.HasExited) -or
            [bool]$script:DynamicScenePreviewActive -or
            [bool]$script:ControlledLiveStreamActive
        )
        $waiting = [bool]$script:WaitingForFullscreen
        $previewOnly = $running -and [bool]$script:PreviewOnlyMode

        $trayStartItem.Enabled = ((-not $running) -or $previewOnly) -and -not $waiting
        # Stop is an escape hatch, not a state-dependent action. Keeping it
        # enabled lets the user cancel a pending retry/wait even between PIDs.
        $trayStopItem.Enabled = $true
        $trayRestartItem.Enabled = $running -and -not $previewOnly

        if ($previewOnly) {
            $trayStartItem.Text = 'Start Stream'
            $trayStopItem.Text = 'Stop Stream'
            $notifyIcon.Text = 'GStreamer Streamer - preview only'
        }
        elseif ($running) {
            $trayStartItem.Text = 'Start Stream'
            $trayStopItem.Text = 'Stop Stream'
            $notifyIcon.Text = "GStreamer Streamer - $([string]$cmbProtocol.SelectedItem) running"
        }
        elseif ($waiting) {
            $trayStartItem.Text = 'Start Stream'
            $trayStopItem.Text = 'Stop Stream'
            $notifyIcon.Text = 'GStreamer Streamer - waiting for fullscreen app'
        }
        else {
            $trayStartItem.Text = 'Start Stream'
            $trayStopItem.Text = 'Stop Stream'
            $notifyIcon.Text = 'GStreamer Streamer - stopped'
        }
    }
    catch {
        # Tray state is non-critical and must never affect streaming.
    }
}

function Apply-StartMinimized {
    if (-not $chkStartMinimized.Checked -or $script:ExitCleanupStarted) {
        return
    }

    try {
        # Start minimized is defined as start in tray. Keep this defensive
        # assignment even though load/UI/save also enforce the invariant.
        $chkMinimizeToTray.Checked = $true
        Hide-MainWindowToTray -SuppressBalloon
        $script:StartupTrayHidePending = $false
    }
    catch {
        try {
            $form.Opacity = 1
            $form.ShowInTaskbar = $true
        }
        catch {}
    }
}

function Enforce-StartMinimizedTrayInvariant {
    param([switch]$Persist)

    if ($script:EnforcingStartMinimizedTrayInvariant) { return }

    $script:EnforcingStartMinimizedTrayInvariant = $true
    try {
        if ($chkStartMinimized.Checked) {
            if (-not $chkMinimizeToTray.Checked) {
                $chkMinimizeToTray.Checked = $true
            }
            $chkMinimizeToTray.Enabled = $false
        }
        else {
            $chkMinimizeToTray.Enabled = $true
        }
    }
    finally {
        $script:EnforcingStartMinimizedTrayInvariant = $false
    }

    if ($Persist -and -not $script:LoadingSettings) {
        Save-Settings
    }
}

function Show-MainWindow {
    if ($script:TrayRestoreInProgress -or $script:ExitCleanupStarted) {
        return
    }

    $script:TrayRestoreInProgress = $true
    try {
        $script:StartupTrayHidePending = $false
        $form.Opacity = 1
        $form.ShowInTaskbar = $true
        $form.Show()
        if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
            $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        }
        $form.BringToFront()
        $form.Activate()

        # Finish preview restore on the next UI turn. VisibleChanged and Resize
        # both fire inside Form.Show()/WindowState changes; starting or reparenting
        # a dynamic preview from either event can race the form's native handles.
        $null = $form.BeginInvoke([Action]{
            try {
                # The form is now visible and its restore/layout events have
                # unwound, so standalone preview startup is safe again.
                $script:TrayRestoreInProgress = $false
                $script:DynamicPreviewUiReady = $true
                if ($script:ControlledLiveStreamActive) {
                    Sync-ControlledLivePreviewLayout
                }
                elseif ($script:GstProcess -and -not $script:GstProcess.HasExited) {
                    if ($script:PreviewParked) {
                        Restore-PreviewWindowFromParking
                    }
                    Try-AttachPreview
                    Set-PreviewVisibility
                }
                else {
                    Sync-StandalonePreviewState -Quiet
                }
            }
            catch {}
            finally {
                $script:TrayRestoreInProgress = $false
                Update-TrayMenuState
            }
        })
    }
    catch {
        $script:TrayRestoreInProgress = $false
    }
}

function Hide-MainWindowToTray {
    param([switch]$SuppressBalloon)

    if (-not $chkMinimizeToTray.Checked -or $script:ExitCleanupStarted) {
        return
    }

    try {
        # Dynamic source windows must never be created or reparented while the
        # main UI is entering tray-hidden state. They become eligible again only
        # after Show-MainWindow completes its deferred restore/layout turn.
        $script:DynamicPreviewUiReady = $false

        if ($script:PreviewOnlyMode) {
            Sync-StandalonePreviewState
        }
        elseif ($script:PreviewHwnd -ne [IntPtr]::Zero) {
            Park-PreviewWindow
        }

        $previewPlaceholder.Visible = $true
        $previewPlaceholder.Text = 'Preview parked while app is in tray'

        $form.ShowInTaskbar = $false
        $form.Hide()
        $form.Opacity = 1

        if (-not $SuppressBalloon -and -not $script:TrayHintShown) {
            $notifyIcon.BalloonTipTitle = $script:AppName
            $notifyIcon.BalloonTipText = 'The streamer is still running. Double-click the tray icon to restore it.'
            $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
            $notifyIcon.ShowBalloonTip(2500)
            $script:TrayHintShown = $true
        }
    }
    catch {
        # A failed tray hide should leave the normal minimized taskbar window.
        try {
            $form.Opacity = 1
            $form.ShowInTaskbar = $true
            $form.Show()
        }
        catch {}
    }
}

function Set-WaitingForFullscreenState {
    $btnStart.Enabled = $true
    $btnStart.Text = "$($script:Glyph.Stop)  Stop"
    $btnStop.Enabled = $false
    $btnStop.Visible = $false
    $btnRestart.Enabled = $false
    Update-RecordingUi
    Update-TrayMenuState
}

function Scroll-LogToBottom {
    try {
        if (-not $txtLog -or $txtLog.IsDisposed) {
            return
        }

        $txtLog.SelectionStart = $txtLog.TextLength
        $txtLog.SelectionLength = 0
        $txtLog.ScrollToCaret()

        if ($txtLog.IsHandleCreated) {
            # ScrollToCaret() can be lazy when the TextBox does not have focus or
            # when the Logs tab is not active. Force the Win32 edit control to
            # move to the bottom so live GStreamer output actually follows tail.
            [GstUiNative]::SendMessage(
                $txtLog.Handle,
                [GstUiNative]::EM_SCROLLCARET,
                [IntPtr]::Zero,
                [IntPtr]::Zero
            ) | Out-Null

            [GstUiNative]::SendMessage(
                $txtLog.Handle,
                [GstUiNative]::WM_VSCROLL,
                [IntPtr]([GstUiNative]::SB_BOTTOM),
                [IntPtr]::Zero
            ) | Out-Null
        }
    }
    catch {}
}

function Drain-ManagedProcessLogs {
    # Reads any new bytes from the GStreamer and MediaMTX stdout/stderr logs and
    # returns them as one chunk so the caller can do a single UI append.
    # Read-NewLogText already no-ops on null/blank paths, so this is cheap when
    # nothing is running.
    $parts = New-Object System.Collections.Generic.List[string]

    $chunk = Read-NewLogText -Path $script:StdOutPath -Position ([ref]$script:StdOutPosition)
    if ($chunk) { $parts.Add($chunk) }

    $chunk = Read-NewLogText -Path $script:StdErrPath -Position ([ref]$script:StdErrPosition)
    if ($chunk) { $parts.Add($chunk) }

    $chunk = Read-NewLogText -Path $script:StdOutVideoPath -Position ([ref]$script:StdOutVideoPosition)
    if ($chunk) { $parts.Add($chunk) }

    $chunk = Read-NewLogText -Path $script:StdErrVideoPath -Position ([ref]$script:StdErrVideoPosition)
    if ($chunk) { $parts.Add($chunk) }

    $chunk = Read-NewLogText -Path $script:StdOutAudioPath -Position ([ref]$script:StdOutAudioPosition)
    if ($chunk) { $parts.Add($chunk) }

    $chunk = Read-NewLogText -Path $script:StdErrAudioPath -Position ([ref]$script:StdErrAudioPosition)
    if ($chunk) { $parts.Add($chunk) }

    $chunk = Read-NewLogText -Path $script:MediaMtxStdOutPath -Position ([ref]$script:MediaMtxStdOutPosition)
    if ($chunk) { $parts.Add($chunk) }

    $chunk = Read-NewLogText -Path $script:MediaMtxStdErrPath -Position ([ref]$script:MediaMtxStdErrPosition)
    if ($chunk) { $parts.Add($chunk) }

    if ($parts.Count -eq 0) { return '' }
    return ($parts -join '')
}

function Test-LogViewLive {
    # The log textbox only needs to scroll and repaint when the user can actually
    # see it. Under heavy GST_DEBUG this is the difference between forcing a
    # scroll+repaint 2.5x/second forever and doing no UI work at all.
    try {
        if (-not $txtLog -or $txtLog.IsDisposed) { return $false }
        if (-not $form -or -not $form.Visible) { return $false }
        if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) { return $false }
        if ($lowerTabs -and $tabLog -and $lowerTabs.SelectedTab -ne $tabLog) { return $false }
        return $true
    }
    catch { return $false }
}

function Append-Log {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return
    }

    try {
        if (-not $txtLog -or $txtLog.IsDisposed) {
            return
        }

        if (-not $Text.EndsWith([Environment]::NewLine)) {
            $Text += [Environment]::NewLine
        }

        $logIsLive = Test-LogViewLive
        $needsTrim = ($txtLog.TextLength + $Text.Length) -gt 250000

        # Suspend painting only when the control is actually on screen AND we are
        # about to do the expensive full-text trim. WM_SETREDRAW on a hidden tab
        # would be wasted work, and suspending for a plain append costs more than
        # the append itself.
        $suspendRedraw = $logIsLive -and $needsTrim -and $txtLog.IsHandleCreated
        if ($suspendRedraw) {
            [void][GstUiNative]::SendMessage($txtLog.Handle, [GstUiNative]::WM_SETREDRAW, [IntPtr]::Zero, [IntPtr]::Zero)
        }

        try {
            $txtLog.AppendText($Text)

            if ($txtLog.TextLength -gt 250000) {
                $txtLog.Text = $txtLog.Text.Substring($txtLog.TextLength - 180000)
            }

            if ($logIsLive) {
                Scroll-LogToBottom
            }
        }
        finally {
            if ($suspendRedraw) {
                [void][GstUiNative]::SendMessage($txtLog.Handle, [GstUiNative]::WM_SETREDRAW, [IntPtr]1, [IntPtr]::Zero)
                $txtLog.Invalidate()
            }
        }
    }
    catch {}
}

function Test-StreamStopAvailable {
    $previewOnly = [bool]$script:PreviewOnlyMode
    return [bool](
        $script:PipelineStartInProgress -or
        $script:WaitingForFullscreen -or
        $script:RestartAt -or
        $script:ControlledLiveStreamActive -or
        $script:RecordingOnlyMode -or
        (($script:GstProcess -or $script:GstVideoProcess -or $script:GstAudioProcess -or $script:MediaMtxProcess) -and -not $previewOnly)
    )
}

function Request-StreamStop {
    $script:PendingPipelineStop = [bool]$script:PipelineStartInProgress
    $script:RestartAt = $null
    $script:AutomaticRestartPending = $false
    $script:RestartRecordingOnlyMode = $false
    $script:WaitingForFullscreen = $false
    Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Stop requested by user; cancelling pending starts/restarts and stopping all managed pipeline processes."
    Stop-GstStream
}

function Invoke-StreamToggle {
    if (Test-StreamStopAvailable) {
        Request-StreamStop
    }
    else {
        Start-GstStream
    }
}

function Set-RunState {
    param([bool]$Running)

    $previewOnly = $Running -and [bool]$script:PreviewOnlyMode
    $stopAvailable = Test-StreamStopAvailable
    # The stream action is never disabled. During start/wait/retry/error cleanup
    # it becomes a Stop request and is queued if startup has not yielded a PID yet.
    $btnStart.Enabled = $true
    $btnStop.Enabled = $false
    $btnStop.Visible = $false
    $btnRestart.Enabled = $Running -and -not $previewOnly -and -not $script:PipelineStartInProgress
    if ($stopAvailable) {
        $btnStart.Text = "$($script:Glyph.Stop)  Stop"
    }
    elseif ($previewOnly) {
        $btnStart.Text = "$($script:Glyph.Start)  Go Live"
    }
    else {
        $btnStart.Text = "$($script:Glyph.Start)  Start"
    }
    Update-RecordingUi
    Update-TrayMenuState
}

function Test-TransportEnabled {
    if ($script:ForceLocalPreviewMode) { return $false }
    return (-not $chkTransportEnabled) -or [bool]$chkTransportEnabled.Checked
}

function Test-StandalonePreviewAllowed {
    try {
        if (-not $form -or -not $form.Visible) { return $false }
        if ($script:StartupTrayHidePending) { return $false }
        if ($script:TrayRestoreInProgress) { return $false }
        if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) { return $false }
        return $true
    }
    catch {
        return $false
    }
}

function Sync-StandalonePreviewState {
    param([switch]$Quiet)

    if ($script:LoadingSettings) { return }

    $running = (
        ($script:GstProcess -and -not $script:GstProcess.HasExited) -or
        [bool]$script:DynamicScenePreviewActive -or
        [bool]$script:ControlledLiveStreamActive
    )

    if ($script:DynamicScenePreviewActive -and -not (Test-UseDynamicScenePreview)) {
        if (-not $Quiet) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Dynamic scene preview disabled by current window/scene state."
        }
        Stop-DynamicScenePreview
        return
    }

    if ($script:PreviewOnlyMode -and -not (Test-StandalonePreviewAllowed)) {
        if (-not $Quiet) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Standalone preview disabled while the app is hidden or minimized."
        }
        if ($script:DynamicScenePreviewActive) { Stop-DynamicScenePreview } else { Stop-GstStream }
        return
    }

    if (
        (-not $running) -and
        $chkPreview.Checked -and
        (Test-StandalonePreviewAllowed)
    ) {
        if (Test-UseDynamicScenePreview) {
            if (Start-DynamicScenePreview) { return }
            if (-not $Quiet) {
                Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Controlled scene preview failed; starting the normal composed preview fallback."
            }
        }

        if (-not $Quiet) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Starting standalone preview."
        }
        Start-GstStream -PreviewOnly
    }
}

function Update-MediaMtxUi {
    $transportEnabled = Test-TransportEnabled
    $isDirectWebRtc = ([string]$cmbProtocol.SelectedItem -eq $script:DirectWebRtcProtocolName)
    if ($chkStartMediaMtx) { $chkStartMediaMtx.Enabled = $transportEnabled -and -not $isDirectWebRtc }
    $enabled = $transportEnabled -and -not $isDirectWebRtc -and $chkStartMediaMtx.Checked
    $txtMediaMtxPath.Enabled = $enabled
    $btnBrowseMediaMtx.Enabled = $enabled
}

function Test-IsAdministrator {
    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

