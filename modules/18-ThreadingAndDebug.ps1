# Module: 18-ThreadingAndDebug.ps1 (auto-extracted by tools/Split-Monolith.ps1 -- edit here, then run tools/Build-Monolith.ps1)

function Get-CpuWorkerLimit {
    if (-not $numCpuWorkerLimit) { return 0 }
    return [Math]::Max(0, [int]$numCpuWorkerLimit.Value)
}

function Get-CpuWorkerProperty {
    param([Parameter(Mandatory)][string]$Name)
    $workers = Get-CpuWorkerLimit
    if ($workers -le 0) { return '' }
    return "$Name=$workers"
}

function Apply-ThreadBudget {
    param([switch]$Force)
    if ($script:ApplyingThreadBudget) { return }
    $script:ApplyingThreadBudget = $true
    try {
        $budget = Get-ComboSelectedOrDefault $cmbThreadBudget $script:DefaultThreadBudget
        if ($budget -eq 'Custom' -and -not $Force) { return }
        switch ($budget) {
            'Lean' {
                $numCpuWorkerLimit.Value = 1
                $chkBudgetCaptureQueue.Checked = $false
                $chkBudgetSenderQueue.Checked = $false
                $chkBudgetAudioInputQueue.Checked = $false
                $chkBudgetAudioFinalQueue.Checked = $true
                $chkBudgetSceneInputQueues.Checked = $true
            }
            'Balanced' {
                $numCpuWorkerLimit.Value = 2
                $chkBudgetCaptureQueue.Checked = $true
                $chkBudgetSenderQueue.Checked = $true
                $chkBudgetAudioInputQueue.Checked = $true
                $chkBudgetAudioFinalQueue.Checked = $true
                $chkBudgetSceneInputQueues.Checked = $true
            }
            'Isolated' {
                $numCpuWorkerLimit.Value = 0
                $chkBudgetCaptureQueue.Checked = $true
                $chkBudgetSenderQueue.Checked = $true
                $chkBudgetAudioInputQueue.Checked = $true
                $chkBudgetAudioFinalQueue.Checked = $true
                $chkBudgetSceneInputQueues.Checked = $true
            }
            default {
                $numCpuWorkerLimit.Value = 0
                $chkBudgetCaptureQueue.Checked = $true
                $chkBudgetSenderQueue.Checked = $true
                $chkBudgetAudioInputQueue.Checked = $true
                $chkBudgetAudioFinalQueue.Checked = $true
                $chkBudgetSceneInputQueues.Checked = $true
            }
        }
    }
    finally { $script:ApplyingThreadBudget = $false }
    Update-CommandPreview
}

function Update-GstThreadCountStatus {
    if (-not $lblLiveGstThreads) { return }
    if (-not $script:GstProcess -or $script:GstProcess.HasExited) {
        $lblLiveGstThreads.Text = if (($script:DynamicScenePreviewActive -or $script:ControlledLiveStreamActive) -and [GstControlledScenePreview]::IsRunning) {
            if ($script:ControlledLiveStreamActive) { 'Live GST threads: controlled broadcast worker' } else { 'Live GST threads: controlled scene preview runs in-process' }
        }
        else {
            'Live GST threads: stopped'
        }
        return
    }
    try {
        $parts = New-Object System.Collections.Generic.List[string]
        $total = 0
        foreach ($entry in @(
            [pscustomobject]@{ Label = $(if (Test-DirectWebRtcUnifiedPublisher) { 'publisher' } else { 'main' }); Process = $script:GstProcess },
            [pscustomobject]@{ Label = 'video'; Process = $script:GstVideoProcess },
            [pscustomobject]@{ Label = 'audio'; Process = $script:GstAudioProcess }
        )) {
            $process = $entry.Process
            if ($process -and -not $process.HasExited) {
                $process.Refresh()
                $count = [int]$process.Threads.Count
                $total += $count
                $parts.Add("$($entry.Label)=$count/PID$($process.Id)")
            }
        }
        $lblLiveGstThreads.Text = "Live GST threads: $total  ($($parts -join ', '))"
    }
    catch { $lblLiveGstThreads.Text = 'Live GST threads: unavailable' }
}

function Get-CaptureEncoderQueue {
    if ($chkBudgetCaptureQueue -and -not $chkBudgetCaptureQueue.Checked) { return 'identity' }
    $buffers = [int]$numCaptureQueueBuffers.Value
    return (New-LiveQueueString -Buffers $buffers -MaxTimeMs 0)
}

function Get-EffectiveAudioQueueCapMs {
    # GStreamer basesink latency negotiation fails if a nonzero queue time cap is
    # lower than the live audio source's reported minimum latency plus the sink
    # processing deadline. The old 20 ms cap could produce:
    #   Impossible to configure latency: max 20ms < min ~21ms
    # Keep 0 as uncapped, but clamp small nonzero caps to a safe low-latency floor.
    $requestedMs = [int]$numAudioQueueCapMs.Value
    if ($requestedMs -le 0) { return 0 }

    $requestedBufferMs = if ($chkAudioBufferOverride -and $chkAudioBufferOverride.Checked) { [Math]::Max(1, [int]$numAudioBufferMs.Value) } else { 0 }
    $requestedLatencyMs = if ($chkAudioLatencyOverride -and $chkAudioLatencyOverride.Checked) { [Math]::Max(1, [int]$numAudioLatencyMs.Value) } else { 0 }
    $safeFloorMs = [Math]::Max(30, ($requestedBufferMs + $requestedLatencyMs + 10))
    return [Math]::Max($requestedMs, [int]$safeFloorMs)
}

function Get-AudioInputQueue {
    param([int]$Multiplier = 1)
    if ($chkBudgetAudioInputQueue -and -not $chkBudgetAudioInputQueue.Checked) { return 'identity' }
    $buffers = [Math]::Max(1, [int]$numAudioQueueBuffers.Value * [Math]::Max(1, $Multiplier))
    $ms = Get-EffectiveAudioQueueCapMs
    return (New-LiveQueueString -Buffers $buffers -MaxTimeMs $ms)
}

function Get-AudioFinalQueue {
    if ($chkBudgetAudioFinalQueue -and -not $chkBudgetAudioFinalQueue.Checked) { return 'identity' }
    $buffers = [Math]::Max(1, [int]$numAudioQueueBuffers.Value * 2)
    $ms = Get-EffectiveAudioQueueCapMs
    return (New-LiveQueueString -Buffers $buffers -MaxTimeMs $ms)
}

function Apply-ThreadingProfile {
    param([switch]$Force)

    if ($script:ApplyingThreadingProfile) { return }
    $script:ApplyingThreadingProfile = $true
    try {
        $profile = Get-ComboSelectedOrDefault $cmbThreadingProfile $script:DefaultThreadingProfile
        if ($profile -eq 'Custom' -and -not $Force) { return }

        switch ($profile) {
            'Live strict' {
                $cmbGstProcessPriority.SelectedItem = 'High'
                $cmbQueueLeakMode.SelectedItem = 'Downstream - drop old'
                $numCaptureQueueBuffers.Value = 2
                $numAudioQueueBuffers.Value = 4
                $numAudioQueueCapMs.Value = 0
                $chkBufferLatenessTracer.Checked = $false
            }
            'Balanced' {
                $cmbGstProcessPriority.SelectedItem = 'Above normal'
                $cmbQueueLeakMode.SelectedItem = 'Downstream - drop old'
                $numCaptureQueueBuffers.Value = 4
                $numAudioQueueBuffers.Value = 6
                $numAudioQueueCapMs.Value = 40
                $chkBufferLatenessTracer.Checked = $false
            }
            'Non-blocking brutal' {
                $cmbGstProcessPriority.SelectedItem = 'High'
                $cmbQueueLeakMode.SelectedItem = 'Downstream - drop old'
                $numCaptureQueueBuffers.Value = 1
                $numAudioQueueBuffers.Value = 2
                $numAudioQueueCapMs.Value = 0
                $chkBufferLatenessTracer.Checked = $false
            }
            'Blocking diagnostic' {
                $cmbGstProcessPriority.SelectedItem = 'Normal'
                $cmbQueueLeakMode.SelectedItem = 'No leak - block'
                $numCaptureQueueBuffers.Value = 2
                $numAudioQueueBuffers.Value = 4
                $numAudioQueueCapMs.Value = 80
                $chkBufferLatenessTracer.Checked = $true
            }
        }
    }
    finally {
        $script:ApplyingThreadingProfile = $false
    }

    Update-CommandPreview
}

function Set-GstProcessPriority {
    param([System.Diagnostics.Process]$Process)

    if (-not $Process) { return }
    $priorityText = Get-ComboSelectedOrDefault $cmbGstProcessPriority $script:DefaultGstProcessPriority
    $priority = switch ($priorityText) {
        'Above normal' { 'AboveNormal' }
        'High' { 'High' }
        default { 'Normal' }
    }

    try {
        $Process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::$priority
        Append-Log "GStreamer process priority: $priorityText"
    }
    catch {
        Append-Log "WARNING: could not set GStreamer process priority to ${priorityText}: $($_.Exception.Message)"
    }
}

function Get-GstDebugSpec {
    $mode = Get-ComboSelectedOrDefault $cmbGstDebugMode $script:DefaultGstDebugMode

    switch ($mode) {
        'ERROR (*:1)' { return '*:1' }
        'WARNING (*:2)' { return '*:2' }
        'INFO (*:3)' { return '*:3' }
        'DEBUG (*:4)' { return '*:4' }
        'LOG (*:5)' { return '*:5' }
        'TRACE (*:6)' { return '*:6' }
        'FULL/MEMDUMP (*:9)' { return '*:9' }
        'Custom' {
            $custom = $txtGstDebugSpec.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($custom)) { return $script:DefaultGstDebugSpec }
            return $custom
        }
        default { return '' }
    }
}

function Test-ProcessDiskLoggingEnabled {
    # Keep the default run path disk-quiet. Diagnostic output is captured only
    # when explicitly requested by the disk-log checkbox or by an explicit
    # diagnostic mode that would otherwise emit useful stdout/stderr.
    try {
        if ($chkDiskProcessLogging -and $chkDiskProcessLogging.Checked) { return $true }
        if ($chkVerbose -and $chkVerbose.Checked) { return $true }
        if ($chkBufferLatenessTracer -and $chkBufferLatenessTracer.Checked) { return $true }
        $debugSpec = Get-GstDebugSpec
        if (-not [string]::IsNullOrWhiteSpace($debugSpec)) { return $true }
    }
    catch {}

    return $false
}

function Reset-ProcessLogPaths {
    $script:StdOutPath = $null
    $script:StdErrPath = $null
    $script:StdOutVideoPath = $null
    $script:StdErrVideoPath = $null
    $script:StdOutAudioPath = $null
    $script:StdErrAudioPath = $null
    $script:MediaMtxStdOutPath = $null
    $script:MediaMtxStdErrPath = $null
    $script:StdOutPosition = [int64]0
    $script:StdErrPosition = [int64]0
    $script:StdOutVideoPosition = [int64]0
    $script:StdErrVideoPosition = [int64]0
    $script:StdOutAudioPosition = [int64]0
    $script:StdErrAudioPosition = [int64]0
    $script:MediaMtxStdOutPosition = [int64]0
    $script:MediaMtxStdErrPosition = [int64]0
}

function Ensure-ProcessLogDirectory {
    if (-not (Test-Path -LiteralPath $script:LogDirectory)) {
        $null = New-Item -ItemType Directory -Path $script:LogDirectory -Force
    }
}

function Update-GstDebugUi {
    $mode = Get-ComboSelectedOrDefault $cmbGstDebugMode $script:DefaultGstDebugMode
    $custom = ($mode -eq 'Custom')
    $txtGstDebugSpec.Enabled = $custom

    if (-not $custom) {
        $spec = Get-GstDebugSpec
        if ([string]::IsNullOrWhiteSpace($spec)) {
            $txtGstDebugSpec.Text = $script:DefaultGstDebugSpec
        }
        else {
            $txtGstDebugSpec.Text = $spec
        }
    }
}

function Set-GstTracerEnvironment {
    param(
        [switch]$Enable,
        [string]$DebugSpec = '',
        [switch]$NoColor
    )

    $state = [ordered]@{
        GST_TRACERS = $env:GST_TRACERS
        GST_DEBUG = $env:GST_DEBUG
        GST_DEBUG_NO_COLOR = $env:GST_DEBUG_NO_COLOR
    }

    $debugParts = @()

    if ($Enable) {
        $env:GST_TRACERS = 'buffer-lateness'
        $debugParts += 'GST_TRACER:7'
    }

    if (-not [string]::IsNullOrWhiteSpace($DebugSpec)) {
        $debugParts += $DebugSpec.Trim()
    }

    if ($debugParts.Count -gt 0) {
        $env:GST_DEBUG = ($debugParts -join ',')
        if ($NoColor) {
            $env:GST_DEBUG_NO_COLOR = '1'
        }
    }

    return $state
}

function Restore-GstTracerEnvironment {
    param($State)
    if ($null -eq $State) { return }
    if ($null -eq $State.GST_TRACERS) { Remove-Item Env:\GST_TRACERS -ErrorAction SilentlyContinue } else { $env:GST_TRACERS = $State.GST_TRACERS }
    if ($null -eq $State.GST_DEBUG) { Remove-Item Env:\GST_DEBUG -ErrorAction SilentlyContinue } else { $env:GST_DEBUG = $State.GST_DEBUG }
    if ($null -eq $State.GST_DEBUG_NO_COLOR) { Remove-Item Env:\GST_DEBUG_NO_COLOR -ErrorAction SilentlyContinue } else { $env:GST_DEBUG_NO_COLOR = $State.GST_DEBUG_NO_COLOR }
}

