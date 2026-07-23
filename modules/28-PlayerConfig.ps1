# Module: 28-PlayerConfig.ps1 (auto-extracted by tools/Split-Monolith.ps1 -- edit here, then run tools/Build-Monolith.ps1)

function Update-PlayerConfigFromUi {
    try {
        Write-DirectWebRtcWebClientConfig -Quiet
    }
    catch {}
    Update-DirectWebRtcUi
    Update-CommandPreview
}

function Update-AudioTimingOptionUi {
    $timing = Get-AudioTimingMode
    $forcesNoClock = $timing -in @('WASAPI no pipeline clock','WASAPI no clock + retimestamp')
    $synthetic = ($timing -eq 'Synthetic silent audio')

    $cmbAudioClockMode.Enabled = (-not $forcesNoClock -and -not $synthetic)
    $cmbAudioSlaveMethod.Enabled = (-not $synthetic)
    $chkWasapiLowLatencyOverride.Enabled = (-not $synthetic)
    $chkAudioBufferOverride.Enabled = (-not $synthetic)
    $chkAudioLatencyOverride.Enabled = (-not $synthetic)
    $numAudioBufferMs.Enabled = (-not $synthetic -and $chkAudioBufferOverride.Checked)
    $numAudioLatencyMs.Enabled = (-not $synthetic -and $chkAudioLatencyOverride.Checked)
    $numAudioSampleRate.Enabled = $chkAudioSampleRateOverride.Checked
}

