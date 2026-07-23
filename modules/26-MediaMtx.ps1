function Read-MediaMtxStartupLogs {
    $stdoutText = Read-NewLogText `
        -Path $script:MediaMtxStdOutPath `
        -Position ([ref]$script:MediaMtxStdOutPosition)

    if ($stdoutText) {
        Append-Log $stdoutText
    }

    $stderrText = Read-NewLogText `
        -Path $script:MediaMtxStdErrPath `
        -Position ([ref]$script:MediaMtxStdErrPosition)

    if ($stderrText) {
        Append-Log $stderrText
    }
}

function Start-ManagedMediaMtx {
    if ((-not (Test-TransportEnabled)) -or -not $chkStartMediaMtx.Checked -or ([string]$cmbProtocol.SelectedItem -eq $script:DirectWebRtcProtocolName)) {
        return $true
    }

    if ($script:MediaMtxProcess -and -not $script:MediaMtxProcess.HasExited) {
        return $true
    }

    $mediaMtxPath = $txtMediaMtxPath.Text.Trim()
    $script:MediaMtxPathInUse = [System.IO.Path]::GetFullPath($mediaMtxPath)

    $processDiskLogging = Test-ProcessDiskLoggingEnabled
    $script:MediaMtxStdOutPath = $null
    $script:MediaMtxStdErrPath = $null
    $script:MediaMtxStdOutPosition = [int64]0
    $script:MediaMtxStdErrPosition = [int64]0

    if ($processDiskLogging) {
        Ensure-ProcessLogDirectory
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
        $script:MediaMtxStdOutPath = Join-Path $script:LogDirectory "mediamtx-$stamp-out.log"
        $script:MediaMtxStdErrPath = Join-Path $script:LogDirectory "mediamtx-$stamp-err.log"
    }

    $workingDirectory = Split-Path -Parent $script:MediaMtxPathInUse

    Append-Log (
        "[$(Get-Date -Format 'HH:mm:ss')] Starting managed MediaMTX..."
    )
    Append-Log "MediaMTX executable: $($script:MediaMtxPathInUse)"
    Append-Log "MediaMTX working directory: $workingDirectory"

    try {
        if ($processDiskLogging) {
            $script:MediaMtxProcess = Start-Process `
                -FilePath $script:MediaMtxPathInUse `
                -WorkingDirectory $workingDirectory `
                -RedirectStandardOutput $script:MediaMtxStdOutPath `
                -RedirectStandardError $script:MediaMtxStdErrPath `
                -WindowStyle Hidden `
                -PassThru
        }
        else {
            $script:MediaMtxProcess = Start-Process `
                -FilePath $script:MediaMtxPathInUse `
                -WorkingDirectory $workingDirectory `
                -WindowStyle Hidden `
                -PassThru
        }

        if ($script:JobHandle -ne [IntPtr]::Zero) {
            try {
                [GstProcessJob]::AssignProcess(
                    $script:JobHandle,
                    $script:MediaMtxProcess.Handle
                )
            }
            catch {
                Append-Log (
                    'WARNING: MediaMTX could not be assigned to the ' +
                    "kill-on-close job: $($_.Exception.Message)"
                )
            }
        }

        Save-ActiveProcessState

        # Give MediaMTX enough time to bind listeners and fail visibly if its
        # configuration or ports are invalid. Keep the WinForms UI responsive.
        $deadline = (Get-Date).AddMilliseconds(900)
        while ((Get-Date) -lt $deadline) {
            [System.Windows.Forms.Application]::DoEvents()
            if ($script:PendingPipelineStop) {
                Append-Log 'MediaMTX startup cancelled by the queued Stop request.'
                return $false
            }
            Start-Sleep -Milliseconds 50
            if (-not $script:MediaMtxProcess) { return $false }
            $script:MediaMtxProcess.Refresh()

            if ($script:MediaMtxProcess.HasExited) {
                break
            }
        }

        if ($processDiskLogging) {
            Read-MediaMtxStartupLogs
        }

        if ($script:MediaMtxProcess.HasExited) {
            $exitCode = $script:MediaMtxProcess.ExitCode
            Append-Log "MediaMTX exited during startup with code $exitCode."
            try { $script:MediaMtxProcess.Dispose() } catch {}
            $script:MediaMtxProcess = $null
            $script:MediaMtxPathInUse = ''
            Remove-ActiveProcessState
            return $false
        }

        Append-Log (
            "MediaMTX is running - PID $($script:MediaMtxProcess.Id)."
        )
        return $true
    }
    catch {
        Append-Log "MEDIAMTX START ERROR: $($_.Exception.Message)"
        try {
            if (
                $script:MediaMtxProcess -and
                -not $script:MediaMtxProcess.HasExited
            ) {
                Stop-ProcessTreeById -ProcessId $script:MediaMtxProcess.Id
            }
        }
        catch {}

        try { $script:MediaMtxProcess.Dispose() } catch {}
        $script:MediaMtxProcess = $null
        $script:MediaMtxPathInUse = ''
        Remove-ActiveProcessState
        return $false
    }
}

function Stop-ManagedMediaMtx {
    param([switch]$Quiet)

    if ($script:MediaMtxProcess -and -not $script:MediaMtxProcess.HasExited) {
        if (-not $Quiet) {
            Append-Log (
                "[$(Get-Date -Format 'HH:mm:ss')] Stopping managed MediaMTX " +
                "process tree - PID $($script:MediaMtxProcess.Id)..."
            )
        }

        Stop-ProcessTreeById -ProcessId $script:MediaMtxProcess.Id
        try {
            $script:MediaMtxProcess.WaitForExit(3000) | Out-Null
        }
        catch {}
    }

    try {
        if ($script:MediaMtxProcess) {
            $script:MediaMtxProcess.Dispose()
        }
    }
    catch {}

    $script:MediaMtxProcess = $null
    $script:MediaMtxPathInUse = ''
}

