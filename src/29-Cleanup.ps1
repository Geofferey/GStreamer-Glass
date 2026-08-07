# SPDX-License-Identifier: AGPL-3.0-only

function Invoke-ApplicationCleanup {
    param(
        [System.Windows.Forms.CloseReason]$CloseReason = [System.Windows.Forms.CloseReason]::None
    )

    if ($script:ExitCleanupStarted) {
        return
    }

    $script:ExitCleanupStarted = $true

    # Windows gives an app only a bounded window to finish handling a logoff/
    # shutdown session-ending sequence before treating it as unresponsive and
    # killing it outright (there is no separate CloseReason for logoff vs.
    # shutdown -- WinForms reports WindowsShutDown for both). The GStreamer/
    # MediaMTX/worker processes are already guaranteed to be torn down
    # regardless of how this function exits (they're attached to a
    # kill-on-job-close Job Object -- see Initialize-GstJob), so the slow,
    # purely-graceful half of this sequence -- the "We'll be right back"
    # media-availability grace sleep below, the WaitForExit calls after every
    # Stop-ProcessTreeById on this path (Get-ProcessExitWaitBudgetMs,
    # src/18-ThreadingAndDebug.ps1), and the multi-second auth-proxy-worker
    # IPC round trips inside Send-AuthProxyWorkerCommand -- buys nothing a
    # logged-off user could ever observe. Only that half is shortened; the
    # settings/session save below stays exactly as it is either way.
    $script:FastShutdownCleanup = ($CloseReason -eq [System.Windows.Forms.CloseReason]::WindowsShutDown)

    # Every IPC call to the auth proxy worker below waits via
    # Wait-UiResponsiveTask, which pumps Application.DoEvents() so the window
    # doesn't look hung during an ordinary (non-exit) wait -- but that same
    # pumping keeps the window and tray menu genuinely clickable while this
    # multi-step exit sequence is still running. A click on Stop, "Save auth
    # cache now", or anything else that reaches Send-AuthProxyWorkerCommand
    # during that window lands on top of whichever call here is still
    # in-flight on the single IPC channel -- that function has its own
    # reentrancy guard, but it fails closed by resetting/restarting the
    # worker process entirely, which then leaves the rest of THIS sequence
    # (forwarding suspend, family stop, shutdown) running against a worker
    # that just came back up with different state. Disabling input here,
    # before any of those calls happen, removes the only realistic way a
    # second command gets issued during exit -- the window is going away
    # regardless, so there is no UX cost to it looking non-interactive.
    try { $form.Enabled = $false } catch {}
    try { $trayMenu.Enabled = $false } catch {}

    # Snapshot settings and the live session table before anything else
    # touches the stream, proxy, or worker process -- the exact same routine
    # "Save auth cache now" runs while streaming normally
    # (src/90-MainWindow.ps1's $btnViewerAuthenticationSaveExitCache handler:
    # Save-Settings then Save-PersistedAuthenticationState), run here in the
    # same uncontended state that button relies on. Doing this later, after
    # marking the stop, suspending forwarding, disconnecting viewers, and
    # killing GStreamer, left the worker process handling all of that plus a
    # flood of client reconnect attempts right as the session-export IPC call
    # (a 3-second-timeout round trip) came in -- a plausible reason exit's
    # save was less reliable than the manual button's, even though the
    # underlying call is identical.
    try { Save-Settings } catch {}
    Append-Log 'AUTH: beginning clean-exit authentication snapshot before anything else'
    try { $null = Save-PersistedAuthenticationState } catch { Append-Log "AUTH: unhandled snapshot failure: $($_.Exception.Message)" }

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

    # Fire off the exact same operation the Stop button does -- Request-
    # StreamStop (src/13-ProcessLifecycle.ps1), run to full completion --
    # instead of reimplementing pieces of it here. That is the only way exit
    # reliably reproduces the Stop button's own behavior (same log lines,
    # same marker/forwarding-suspend/disconnect/kill sequence, same handling
    # of whichever streaming mode -- plain pipeline, controlled live, dynamic
    # scene preview -- happens to be active), rather than a hand-rolled
    # subset that can silently drift out of sync with it.
    #
    # -Exiting is the one real difference from a manual Stop click: Stop-
    # GstStream normally revokes every viewer session on any non-restart
    # intentional stop (Revoke-ActiveAuthenticationProxySessions), gated only
    # on "Keep auth on restarts". "Keep auth on exit" is a separate setting
    # and was never consulted there, so calling this unmodified during exit
    # would revoke every session moments before they were saved above,
    # silently defeating "Keep auth on exit". -Exiting threads through to
    # both of Stop-GstStream's revocation gates (see their comments) so that
    # setting is finally respected, without changing anything about a normal
    # Stop click (which never passes -Exiting).
    $hadActiveStream = [bool](
        ($script:GstProcess -and -not $script:GstProcess.HasExited) -or
        ($script:GstVideoProcess -and -not $script:GstVideoProcess.HasExited) -or
        ($script:GstAudioProcess -and -not $script:GstAudioProcess.HasExited) -or
        $script:ControlledLiveStreamActive -or
        $script:DynamicScenePreviewActive
    )
    try { Request-StreamStop -Exiting } catch { Append-Log "Stop during exit failed: $($_.Exception.Message)" }

    # Request-StreamStop above may have just kicked off a background seek-
    # index repair for a recording that was active (Start-RecordingIndexRepair,
    # 21-Recording.ps1) -- normally drained by the 400ms poll tick, which is
    # already stopped by the time this runs (see $pollTimer.Stop() in
    # $form.Add_FormClosing). Without this wait, the repair's temp output
    # file would still get produced (it isn't tied to the kill-on-job-close
    # Job Object below, deliberately, so exiting can't cut it off mid-write)
    # but would never get swapped in, and would be left next to the original
    # forever. The remux itself is a fast repackage with no re-encode, so a
    # short bounded wait covers the common case without meaningfully delaying
    # exit; skipped on a Windows logoff/shutdown for the same reason as the
    # grace sleep below -- nobody is around to see it finish either way.
    if (-not $script:FastShutdownCleanup -and $script:PendingRecordingRepairs.Count -gt 0) {
        Append-Log 'RECORDING: waiting briefly for the in-progress seek-index repair to finish before exiting...'
        $repairDeadline = (Get-Date).AddSeconds(10)
        while ($script:PendingRecordingRepairs.Count -gt 0 -and (Get-Date) -lt $repairDeadline) {
            Start-Sleep -Milliseconds 200
            Update-PendingRecordingRepairs
        }
    }

    # After a normal Stop-button stop, the auth proxy worker keeps running
    # indefinitely with forwarding suspended, so any request a viewer's
    # browser happens to make gets the holding-page media back instantly --
    # WriteMediaMessagePageAsync answers every request itself once
    # forwardingPaused is set, without touching GStreamer at all. Exit
    # doesn't get that "keeps running indefinitely" part -- the block below,
    # which only runs AFTER Request-StreamStop above has fully completed,
    # goes on to stop the proxy listeners and kill the worker process, and if
    # that happens before the browser's next request lands, the holding page
    # (which that worker serves) is gone before the client ever gets a
    # chance to request it. Confirmed live: without this wait, the "We'll be
    # right back" media inconsistently failed to load on exit even though it
    # loads reliably after a normal Stop. Skipped on a Windows logoff/shutdown
    # close: nobody is around to see that holding page load, and the whole
    # process (worker included) is about to be torn down by the OS regardless.
    if ($hadActiveStream -and -not $script:FastShutdownCleanup) {
        Start-Sleep -Milliseconds 1500
    }

    Close-ControlledLiveWorkerPipe
    Close-WebRtcPortRangeWorkerPipe
    try { Remove-UpnpPortMappings -Quiet } catch {}
    try { Stop-LetsEncryptTlsProxies } catch {}
    try { Stop-PlaintextAuthProxies } catch {}
    # Stop-*Proxies above only tell the auth proxy worker process to stop
    # those families -- the worker process itself stays alive across
    # stream cycles (it must keep answering the login-redirect page even
    # with no stream active), so app exit needs to explicitly tear down the
    # worker process too, or it would be orphaned.
    try { Stop-AuthProxyWorker } catch {}

    try {
        Stop-ManagedMediaMtx -Quiet
    }
    catch {}

    Remove-ActiveProcessState

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

        if ($script:LogPopoutForm -and -not $script:LogPopoutForm.IsDisposed) {
            $script:LogPopoutForm.Close()
            $script:LogPopoutForm.Dispose()
        }
        $script:LogPopoutForm = $null
        $script:LogPopoutTextBox = $null

        if ($script:CustomArgsEditorForm -and -not $script:CustomArgsEditorForm.IsDisposed) {
            # FormClosed clears the script reference synchronously, so retain a
            # local reference long enough to finish deterministic disposal.
            $customArgsEditorToDispose = $script:CustomArgsEditorForm
            $customArgsEditorToDispose.Close()
            $customArgsEditorToDispose.Dispose()
        }
        $script:CustomArgsEditorForm = $null
        $script:CustomArgsEditorTextBox = $null
        $script:CustomArgsEditorEnabledCheckBox = $null

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

    Close-AppLogWriter
}
