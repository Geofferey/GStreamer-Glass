function Invoke-ApplicationCleanup {
    if ($script:ExitCleanupStarted) {
        return
    }

    $script:ExitCleanupStarted = $true
    # Closing the UI is also an unconditional cancellation request. If the form
    # is closed while a controlled worker or MediaMTX is still handshaking, the
    # responsive startup waits will unwind instead of launching after cleanup.
    $script:PendingPipelineStop = $true
    $script:AutomaticRestartPending = $false
    $script:WaitingForFullscreen = $false
    $script:RestartAt = $null

    try {
        $chkAutoRestart.Checked = $false
    }
    catch {}

    try {
        if ($script:ControlledLiveStreamActive) {
            $script:ControlledLiveStreamActive = $false
        }
        Stop-DynamicScenePreview -Quiet
    }
    catch {}

    try {
        if ($script:GstVideoProcess -and -not $script:GstVideoProcess.HasExited) {
            Stop-ProcessTreeById -ProcessId $script:GstVideoProcess.Id
            try { $script:GstVideoProcess.WaitForExit(3000) | Out-Null } catch {}
        }
        if ($script:GstAudioProcess -and -not $script:GstAudioProcess.HasExited) {
            Stop-ProcessTreeById -ProcessId $script:GstAudioProcess.Id
            try { $script:GstAudioProcess.WaitForExit(3000) | Out-Null } catch {}
        }
        if ($script:GstProcess -and -not $script:GstProcess.HasExited) {
            Stop-ProcessTreeById -ProcessId $script:GstProcess.Id
            try { $script:GstProcess.WaitForExit(3000) | Out-Null } catch {}
        }
    }
    catch {}

    Close-ControlledLiveWorkerPipe

    try {
        Stop-ManagedMediaMtx -Quiet
    }
    catch {}

    Remove-ActiveProcessState

    try {
        if ($chkNetworkRestoreOnExit -and $chkNetworkRestoreOnExit.Checked) {
            Restore-NetworkTuning -Quiet | Out-Null
        }
    }
    catch {}

    if ($script:JobHandle -ne [IntPtr]::Zero) {
        try {
            # Closing this handle forcibly terminates every process assigned to the job.
            [GstProcessJob]::CloseJob($script:JobHandle)
        }
        catch {}
        $script:JobHandle = [IntPtr]::Zero
    }

    try {
        $notifyIcon.Visible = $false
        $notifyIcon.Dispose()
    }
    catch {}

    try {
        if ($script:PreviewParkForm -and -not $script:PreviewParkForm.IsDisposed) {
            $script:PreviewParkForm.Close()
            $script:PreviewParkForm.Dispose()
        }

        $trayMenu.Dispose()
    }
    catch {}

    try {
        $form.Icon = $null
        if ($script:AppIcon) {
            $script:AppIcon.Dispose()
            $script:AppIcon = $null
        }
    }
    catch {}
}

