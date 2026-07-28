# Copyright (c) 2026 Geofferey
# SPDX-License-Identifier: AGPL-3.0-only

# Best-effort UPnP IGD port forwarding for the Direct GST WebRTC protocol,
# using the Windows-builtin NATUPnP COM API (no external dependency). Mirrors
# exactly the ports the web viewer/signalling settings and Min/Max RTP port
# range already require (see GstWebRtcConsumerPortRange in 00-Setup.ps1) --
# it never invents new ports, and a mapping failure never blocks or fails the
# stream, since STUN/TURN-based ICE already works without it.

$script:UpnpMappingTag = 'GStreamer Glass: '
$script:ActiveUpnpMappings = @()

# The Windows NATUPnP COM API maps one port per call; a UDP RTP range has to
# be expanded into that many individual Add() calls. Cap it so an
# unreasonably wide range (e.g. a fat-fingered full ephemeral range) can't
# stall stream start for minutes -- if it's over the cap we skip the RTP
# range mappings entirely (a partial mapping would silently under-cover the
# range) and surface why in both the log and the status label. 256 covers
# realistic single-streamer ranges (a handful of ports per consumer) with
# room to spare while still catching genuine mistakes.
$script:MaxUpnpRtpRangePorts = 256
$script:UpnpRtpRangeSkippedByCap = $false

function Get-UpnpNatDevice {
    try {
        $nat = New-Object -ComObject HNetCfg.NATUPnP
    }
    catch {
        Append-Log "UPnP: NATUPnP COM class unavailable ($($_.Exception.Message)); skipping port forwarding."
        return $null
    }
    try {
        if (-not $nat.StaticPortMappingCollection) {
            Append-Log 'UPnP: no Internet Gateway Device responded; skipping port forwarding.'
            return $null
        }
    }
    catch {
        Append-Log "UPnP: could not reach the router's UPnP mapping table ($($_.Exception.Message)); skipping port forwarding."
        return $null
    }
    return $nat
}

function Get-UpnpLocalIPv4Address {
    $adapterName = $null
    try { $adapterName = Get-SelectedNetworkAdapterName } catch {}

    if (-not [string]::IsNullOrWhiteSpace($adapterName) -and (Get-Command Get-NetIPAddress -ErrorAction SilentlyContinue)) {
        try {
            $addr = Get-NetIPAddress -InterfaceAlias $adapterName -AddressFamily IPv4 -ErrorAction Stop |
                Where-Object { $_.PrefixOrigin -in @('Dhcp', 'Manual') -and -not $_.IPAddress.StartsWith('169.254.') } |
                Select-Object -First 1 -ExpandProperty IPAddress
            if ($addr) { return $addr }
        }
        catch {}
    }

    if (Get-Command Get-NetIPAddress -ErrorAction SilentlyContinue) {
        try {
            $addr = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
                Where-Object { $_.PrefixOrigin -in @('Dhcp', 'Manual') -and $_.IPAddress -ne '127.0.0.1' -and -not $_.IPAddress.StartsWith('169.254.') } |
                Select-Object -First 1 -ExpandProperty IPAddress
            if ($addr) { return $addr }
        }
        catch {}
    }

    return $null
}

function Get-UpnpRequiredMappings {
    if ([string]$cmbProtocol.SelectedItem -ne $script:DirectWebRtcProtocolName) { return @() }

    $mappings = @()

    $mappings += [pscustomobject]@{
        ExternalPort = [int]$numDirectWebRtcSignalingPort.Value
        InternalPort = [int]$numDirectWebRtcSignalingPort.Value
        Protocol     = 'TCP'
        Description  = "${script:UpnpMappingTag}Video signalling"
    }

    # web-server-host-addr (default http://0.0.0.0:8889/) is webrtcsink's own
    # HTTP server that serves the viewer HTML/JS bundle -- a separate port
    # from the WS signalling port above, and the first thing a remote
    # browser has to reach before it can even open the signalling socket.
    try {
        $webUri = [System.Uri](Normalize-DirectWebRtcWebAddress $txtDestination.Text)
        $webPort = $webUri.Port
        if ($webPort -gt 0 -and -not ($mappings | Where-Object { $_.ExternalPort -eq $webPort -and $_.Protocol -eq 'TCP' })) {
            $mappings += [pscustomobject]@{
                ExternalPort = $webPort
                InternalPort = $webPort
                Protocol     = 'TCP'
                Description  = "${script:UpnpMappingTag}Web viewer"
            }
        }
    }
    catch {
        Append-Log "UPnP: could not determine the web viewer port from '$($txtDestination.Text)'; not mapped."
    }

    if ((Test-DirectWebRtcSplitAvPipelines) -and -not (Test-DirectWebRtcSharedSignaling)) {
        $splitPort = [int](Get-DirectWebRtcSplitAudioSignalingPort)
        $mappings += [pscustomobject]@{
            ExternalPort = $splitPort
            InternalPort = $splitPort
            Protocol     = 'TCP'
            Description  = "${script:UpnpMappingTag}Audio signalling"
        }
    }

    $script:UpnpRtpRangeSkippedByCap = $false
    if (Test-DirectWebRtcPortRangeWorkerRequired) {
        $minPort = [int]$numDirectWebRtcMinRtpPort.Value
        $maxPort = [int]$numDirectWebRtcMaxRtpPort.Value
        $rangeSize = $maxPort - $minPort + 1
        if ($rangeSize -gt $script:MaxUpnpRtpRangePorts) {
            $script:UpnpRtpRangeSkippedByCap = $true
            Append-Log "UPnP: RTP port range $minPort-$maxPort is $rangeSize ports, over the $($script:MaxUpnpRtpRangePorts)-port UPnP mapping cap; skipping RTP range forwarding (signalling ports are still mapped)."
        }
        else {
            for ($port = $minPort; $port -le $maxPort; $port++) {
                $mappings += [pscustomobject]@{
                    ExternalPort = $port
                    InternalPort = $port
                    Protocol     = 'UDP'
                    Description  = "${script:UpnpMappingTag}RTP $port"
                }
            }
        }
    }

    return $mappings
}

function Add-UpnpPortMappings {
    $required = @(Get-UpnpRequiredMappings)
    if ($required.Count -eq 0) { return }

    $nat = Get-UpnpNatDevice
    if (-not $nat) { return }

    $localIp = Get-UpnpLocalIPv4Address
    if ([string]::IsNullOrWhiteSpace($localIp)) {
        Append-Log 'UPnP: could not resolve a local IPv4 address; skipping port forwarding.'
        return
    }

    # Reconciliation: drop any of our own previously-tagged mappings that a
    # crash left behind or that no longer match the current requirement set,
    # before adding the current ones. Never touches mappings we didn't tag.
    try {
        $collection = $nat.StaticPortMappingCollection
        $stale = @()
        foreach ($existing in $collection) {
            if ($existing.Description -like "$($script:UpnpMappingTag)*") {
                $stillNeeded = $required | Where-Object {
                    $_.ExternalPort -eq $existing.ExternalPort -and $_.Protocol -eq $existing.Protocol
                }
                if (-not $stillNeeded) { $stale += $existing }
            }
        }
        foreach ($entry in $stale) {
            try { $collection.Remove($entry.ExternalPort, $entry.Protocol) } catch {}
        }
    }
    catch {}

    $script:ActiveUpnpMappings = @()
    $failCount = 0
    foreach ($mapping in $required) {
        try {
            $nat.StaticPortMappingCollection.Add(
                $mapping.ExternalPort, $mapping.Protocol, $mapping.InternalPort,
                $localIp, $true, $mapping.Description) | Out-Null
            $script:ActiveUpnpMappings += $mapping
            Append-Log "UPnP: mapped $($mapping.Protocol) $($mapping.ExternalPort) -> $localIp`:$($mapping.InternalPort)."
        }
        catch {
            $failCount++
            Append-Log "UPnP: failed to map $($mapping.Protocol) $($mapping.ExternalPort): $($_.Exception.Message)"
        }
    }

    if ($lblUpnpStatus) {
        $capSuffix = if ($script:UpnpRtpRangeSkippedByCap) { " (RTP range too wide for UPnP, over $($script:MaxUpnpRtpRangePorts) ports; skipped)" } else { '' }
        if ($script:ActiveUpnpMappings.Count -eq 0) {
            $lblUpnpStatus.Text = "UPnP: enabled, but no ports could be mapped; see log$capSuffix"
            $lblUpnpStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        else {
            $tcpPorts = @($script:ActiveUpnpMappings | Where-Object { $_.Protocol -eq 'TCP' } | ForEach-Object { $_.ExternalPort } | Sort-Object)
            $udpPorts = @($script:ActiveUpnpMappings | Where-Object { $_.Protocol -eq 'UDP' } | ForEach-Object { $_.ExternalPort } | Sort-Object)
            $portParts = @()
            if ($tcpPorts.Count -gt 0) { $portParts += "TCP $($tcpPorts -join ',')" }
            if ($udpPorts.Count -gt 1) { $portParts += "UDP $($udpPorts[0])-$($udpPorts[-1]) ($($udpPorts.Count) ports)" }
            elseif ($udpPorts.Count -eq 1) { $portParts += "UDP $($udpPorts[0])" }
            $ports = $portParts -join '; '
            $failSuffix = if ($failCount -gt 0) { " ($failCount failed; see log)" } else { '' }
            $lblUpnpStatus.Text = "UPnP: mapped $ports on $localIp$failSuffix$capSuffix"
            $lblUpnpStatus.ForeColor = if ($failCount -gt 0 -or $script:UpnpRtpRangeSkippedByCap) { [System.Drawing.Color]::DarkOrange } else { [System.Drawing.Color]::DarkGreen }
        }
    }
}

function Remove-UpnpPortMappings {
    param([switch]$Quiet)

    if ($script:ActiveUpnpMappings.Count -eq 0) { return }

    $nat = $null
    try { $nat = New-Object -ComObject HNetCfg.NATUPnP } catch {}

    foreach ($mapping in $script:ActiveUpnpMappings) {
        try {
            if ($nat) {
                $nat.StaticPortMappingCollection.Remove($mapping.ExternalPort, $mapping.Protocol)
                if (-not $Quiet) { Append-Log "UPnP: removed $($mapping.Protocol) $($mapping.ExternalPort)." }
            }
        }
        catch {
            if (-not $Quiet) { Append-Log "UPnP: failed to remove $($mapping.Protocol) $($mapping.ExternalPort): $($_.Exception.Message)" }
        }
    }
    $script:ActiveUpnpMappings = @()

    if (-not $Quiet -and $lblUpnpStatus) {
        $lblUpnpStatus.Text = if ($chkUpnpEnabled -and $chkUpnpEnabled.Checked) { 'UPnP: enabled, no active mappings' } else { 'UPnP: disabled' }
        $lblUpnpStatus.ForeColor = [System.Drawing.Color]::DimGray
    }
}
