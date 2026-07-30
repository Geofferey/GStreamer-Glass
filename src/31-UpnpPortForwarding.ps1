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

$script:UpnpNatDevice = $null

# UPnP discovery is asynchronous under the hood (SSDP + a SOAP round-trip to
# the router); StaticPortMappingCollection can transiently come back empty
# on the very first access after creating the COM object even when the
# router is fine, especially right after this is called back-to-back (once
# at stream start, again at stream stop). Cache the device once discovery
# succeeds so Add and Remove reuse the same known-good object instead of
# redoing discovery from scratch every time, and retry briefly before
# giving up on a fresh discovery.
function Get-UpnpNatDevice {
    param([switch]$Quiet)

    if ($null -ne $script:UpnpNatDevice) {
        try {
            if ($null -ne $script:UpnpNatDevice.StaticPortMappingCollection) { return $script:UpnpNatDevice }
        }
        catch {}
        try { [System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($script:UpnpNatDevice) | Out-Null } catch {}
        $script:UpnpNatDevice = $null
    }

    # Each attempt creates a genuinely fresh COM object. HNetCfg.NATUPnP
    # appears to perform its SSDP discovery once, at creation/first property
    # access, and does not re-broadcast on repeated reads of the same
    # instance -- so re-checking one already-failed object (the previous
    # approach here) was never a real retry, just re-polling a result that
    # was never going to change. SSDP over UDP multicast is inherently a bit
    # lossy on real networks (the spec has routers randomize their response
    # delay specifically to avoid response storms), so a fresh discovery
    # attempt each time is what actually gives this a real independent
    # chance to succeed -- mirroring what already happens naturally every
    # time the user clicks Start (a brand new discovery each stream start).
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $nat = $null
        try {
            $nat = New-Object -ComObject HNetCfg.NATUPnP
        }
        catch {
            if (-not $Quiet) { Append-Log "UPnP: NATUPnP COM class unavailable ($($_.Exception.Message)); skipping port forwarding." }
            return $null
        }

        try {
            if ($null -ne $nat.StaticPortMappingCollection) {
                $script:UpnpNatDevice = $nat
                return $nat
            }
        }
        catch {}

        try { [System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($nat) | Out-Null } catch {}
        if ($attempt -lt 3) { Start-Sleep -Milliseconds (700 * $attempt) }
    }

    if (-not $Quiet) { Append-Log 'UPnP: no Internet Gateway Device responded after retrying; skipping port forwarding.' }
    return $null
}

function Get-UpnpLocalIPv4Address {
    # Many routers run a UPnP "secure mode" that rejects AddPortMapping (and
    # sometimes Remove) unless the InternalClient argument matches the
    # actual source IP the SOAP request arrived from -- specifically to stop
    # one LAN device mapping/hijacking a port on another device's behalf. On
    # a system with more than one active IPv4 interface (VPN, virtual
    # switches, etc.), "first matching address found" can pick a different
    # one than the router actually sees. The interface that owns the
    # default route is provably the one any outbound call -- including the
    # UPnP SOAP request itself -- actually goes out over, so it's checked
    # first and is the most reliable match for what a secure-mode router
    # validates against.
    if (Get-Command Get-NetRoute -ErrorAction SilentlyContinue) {
        try {
            $defaultRoute = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
                Sort-Object -Property RouteMetric |
                Select-Object -First 1
            if ($defaultRoute) {
                $addr = Get-NetIPAddress -InterfaceIndex $defaultRoute.InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop |
                    Where-Object { $_.PrefixOrigin -in @('Dhcp', 'Manual') -and -not $_.IPAddress.StartsWith('169.254.') } |
                    Select-Object -First 1 -ExpandProperty IPAddress
                if ($addr) { return $addr }
            }
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

# Shared by the config generator (17-DirectWebRtcPipeline.ps1) and the debug
# query-string builder (20-WebRtcWebUi.ps1) so the player learns about an
# external signalling port exactly when one is actually configured -- based
# on the UI's configured intent, not on whether Add-UpnpPortMappings has run
# or succeeded yet, since config generation and port mapping are not ordered
# relative to each other.
function Test-UpnpSignalingMappedExternally {
    return [bool]($chkUpnpEnabled -and $chkUpnpEnabled.Checked -and
        $chkUpnpMapSignaling -and $chkUpnpMapSignaling.Checked -and
        $numUpnpSignalingExternalPort -and [int]$numUpnpSignalingExternalPort.Value -gt 0)
}

function Get-UpnpRequiredMappings {
    if ([string]$cmbProtocol.SelectedItem -ne $script:DirectWebRtcProtocolName) { return @() }

    $mappings = @()
    # Once embedded TLS termination is active, the TlsTerminatingProxy is
    # what's actually listening on this machine's LAN IP for these
    # services, not webrtcsink's original port -- that's what the router
    # needs to reach. Mapped 1:1 like RTP: the proxy already applied its
    # own external-port override when it started listening
    # (Get-LetsEncryptSignalingProxyPort etc. in 33-LetsEncrypt.ps1), so a
    # second remap here would just be a confusing second layer of the same
    # thing -- UPnP's own external-port-override fields don't apply in this
    # mode.
    $tlsActive = Test-EmbeddedTlsActive

    if ($chkUpnpMapSignaling -and $chkUpnpMapSignaling.Checked) {
        if ($tlsActive) {
            $proxyPort = Get-LetsEncryptSignalingProxyPort
            $mappings += [pscustomobject]@{
                ExternalPort = $proxyPort
                InternalPort = $proxyPort
                Protocol     = 'TCP'
                Description  = "${script:UpnpMappingTag}Video signalling (TLS)"
            }
        }
        else {
            $internalPort = [int]$numDirectWebRtcSignalingPort.Value
            $externalOverride = if ($numUpnpSignalingExternalPort) { [int]$numUpnpSignalingExternalPort.Value } else { 0 }
            $mappings += [pscustomobject]@{
                ExternalPort = if ($externalOverride -gt 0) { $externalOverride } else { $internalPort }
                InternalPort = $internalPort
                Protocol     = 'TCP'
                Description  = "${script:UpnpMappingTag}Video signalling"
            }
        }

        # Unified-publisher mode bundles audio+video into one producer/server
        # (no separate split-audio port exists then, regardless of the shared-
        # signalling toggle) -- matches the same condition
        # Write-DirectWebRtcWebClientConfig already uses for splitAudioSignalingPort.
        if ((Test-DirectWebRtcSplitAvPipelines) -and -not (Test-DirectWebRtcUnifiedPublisher) -and -not (Test-DirectWebRtcSharedSignaling)) {
            if ($tlsActive) {
                $splitProxyPort = Get-LetsEncryptSplitAudioProxyPort
                $mappings += [pscustomobject]@{
                    ExternalPort = $splitProxyPort
                    InternalPort = $splitProxyPort
                    Protocol     = 'TCP'
                    Description  = "${script:UpnpMappingTag}Audio signalling (TLS)"
                }
            }
            else {
                $splitInternalPort = [int](Get-DirectWebRtcSplitAudioSignalingPort)
                $splitExternalOverride = if ($numUpnpSplitAudioExternalPort) { [int]$numUpnpSplitAudioExternalPort.Value } else { 0 }
                $mappings += [pscustomobject]@{
                    ExternalPort = if ($splitExternalOverride -gt 0) { $splitExternalOverride } else { $splitInternalPort }
                    InternalPort = $splitInternalPort
                    Protocol     = 'TCP'
                    Description  = "${script:UpnpMappingTag}Audio signalling"
                }
            }
        }
    }

    # web-server-host-addr (default http://0.0.0.0:8889/) is webrtcsink's own
    # HTTP server that serves the viewer HTML/JS bundle -- a separate port
    # from the WS signalling port above, and the first thing a remote
    # browser has to reach before it can even open the signalling socket.
    if ($chkUpnpMapWebServer -and $chkUpnpMapWebServer.Checked) {
        try {
            $bindAddress = if ($tlsActive) { Get-DirectWebRtcWebServerBindAddress -Destination $txtDestination.Text } else { Normalize-DirectWebRtcWebAddress $txtDestination.Text }
            $webUri = [System.Uri]$bindAddress
            $webPort = $webUri.Port
            if ($tlsActive) {
                $webProxyPort = Get-LetsEncryptWebServerProxyPort -InternalPort $webPort
                if ($webPort -gt 0 -and -not ($mappings | Where-Object { $_.ExternalPort -eq $webProxyPort -and $_.Protocol -eq 'TCP' })) {
                    $mappings += [pscustomobject]@{
                        ExternalPort = $webProxyPort
                        InternalPort = $webProxyPort
                        Protocol     = 'TCP'
                        Description  = "${script:UpnpMappingTag}Web viewer (TLS)"
                    }
                }
            }
            else {
                $webExternalOverride = if ($numUpnpWebServerExternalPort) { [int]$numUpnpWebServerExternalPort.Value } else { 0 }
                $webExternalPort = if ($webExternalOverride -gt 0) { $webExternalOverride } else { $webPort }
                if ($webPort -gt 0 -and -not ($mappings | Where-Object { $_.ExternalPort -eq $webExternalPort -and $_.Protocol -eq 'TCP' })) {
                    $mappings += [pscustomobject]@{
                        ExternalPort = $webExternalPort
                        InternalPort = $webPort
                        Protocol     = 'TCP'
                        Description  = "${script:UpnpMappingTag}Web viewer"
                    }
                }
            }
        }
        catch {
            Append-Log "UPnP: could not determine the web viewer port from '$($txtDestination.Text)'; not mapped."
        }
    }

    $script:UpnpRtpRangeSkippedByCap = $false
    if (($chkUpnpMapRtp -and $chkUpnpMapRtp.Checked) -and (Test-DirectWebRtcPortRangeWorkerRequired)) {
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
    # Enumerating the router's table is one round-trip per entry on some
    # routers, so a large backlog of never-cleaned-up entries (e.g. from a
    # wide RTP range that failed to tear down repeatedly) can make this slow
    # or make the router stop responding to fresh UPnP requests entirely --
    # log clearly instead of swallowing that possibility silently.
    $currentMappingKeys = @{}
    try {
        $collection = $nat.StaticPortMappingCollection
        $stale = @()
        $seenCount = 0
        foreach ($existing in $collection) {
            $seenCount++
            if ($existing.Description -like "$($script:UpnpMappingTag)*") {
                $stillNeeded = $required | Where-Object {
                    $_.ExternalPort -eq $existing.ExternalPort -and
                    $_.Protocol -eq $existing.Protocol -and
                    $_.InternalPort -eq $existing.InternalPort -and
                    $localIp -eq [string]$existing.InternalClient
                } | Select-Object -First 1
                if ($stillNeeded) {
                    $currentMappingKeys["$($stillNeeded.Protocol)/$($stillNeeded.ExternalPort)"] = $true
                }
                else {
                    $stale += $existing
                }
            }
        }
        if ($stale.Count -gt 0) {
            $removedCount = 0
            foreach ($entry in $stale) {
                try { $collection.Remove($entry.ExternalPort, $entry.Protocol); $removedCount++ }
                catch { Append-Log "UPnP: reconciliation could not remove stale $($entry.Protocol) $($entry.ExternalPort): $($_.Exception.Message)" }
            }
            Append-Log "UPnP: reconciliation removed $removedCount of $($stale.Count) stale mapping(s) from a router table of $seenCount entries."
        }
    }
    catch {
        Append-Log "UPnP: reconciliation against the router's mapping table failed ($($_.Exception.Message)); proceeding without it. If the router table has a large backlog of stale entries, clearing them from the router's admin UI (or power-cycling the router) may be needed to restore UPnP responsiveness."
    }

    $script:ActiveUpnpMappings = @()
    $failCount = 0
    foreach ($mapping in $required) {
        $mappingKey = "$($mapping.Protocol)/$($mapping.ExternalPort)"
        if ($currentMappingKeys.ContainsKey($mappingKey)) {
            $script:ActiveUpnpMappings += $mapping
            Append-Log "UPnP: reusing existing $($mapping.Protocol) $($mapping.ExternalPort) -> $localIp`:$($mapping.InternalPort)."
            continue
        }
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
            $tcpLabels = @($script:ActiveUpnpMappings | Where-Object { $_.Protocol -eq 'TCP' } | Sort-Object ExternalPort | ForEach-Object {
                if ($_.ExternalPort -eq $_.InternalPort) { "$($_.ExternalPort)" } else { "$($_.ExternalPort)->$($_.InternalPort)" }
            })
            $udpPorts = @($script:ActiveUpnpMappings | Where-Object { $_.Protocol -eq 'UDP' } | ForEach-Object { $_.ExternalPort } | Sort-Object)
            $portParts = @()
            if ($tcpLabels.Count -gt 0) { $portParts += "TCP $($tcpLabels -join ',')" }
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

    $nat = Get-UpnpNatDevice -Quiet:$Quiet
    if (-not $nat) {
        if (-not $Quiet) {
            Append-Log "UPnP: router unavailable during cleanup; retaining $($script:ActiveUpnpMappings.Count) mapping record(s) for a later retry."
            if ($lblUpnpStatus) {
                $lblUpnpStatus.Text = "UPnP: cleanup pending for $($script:ActiveUpnpMappings.Count) mapping(s); router unavailable"
                $lblUpnpStatus.ForeColor = [System.Drawing.Color]::DarkOrange
            }
        }
        return
    }

    $remainingMappings = @()
    foreach ($mapping in $script:ActiveUpnpMappings) {
        try {
            $nat.StaticPortMappingCollection.Remove($mapping.ExternalPort, $mapping.Protocol)
            if (-not $Quiet) { Append-Log "UPnP: removed $($mapping.Protocol) $($mapping.ExternalPort)." }
        }
        catch {
            $remainingMappings += $mapping
            if (-not $Quiet) { Append-Log "UPnP: failed to remove $($mapping.Protocol) $($mapping.ExternalPort): $($_.Exception.Message)" }
        }
    }
    $script:ActiveUpnpMappings = $remainingMappings

    if (-not $Quiet -and $lblUpnpStatus) {
        if ($remainingMappings.Count -gt 0) {
            $lblUpnpStatus.Text = "UPnP: cleanup incomplete; $($remainingMappings.Count) mapping(s) pending retry"
            $lblUpnpStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        else {
            $lblUpnpStatus.Text = if ($chkUpnpEnabled -and $chkUpnpEnabled.Checked) { 'UPnP: enabled, no active mappings' } else { 'UPnP: disabled' }
            $lblUpnpStatus.ForeColor = [System.Drawing.Color]::DimGray
        }
    }
}
