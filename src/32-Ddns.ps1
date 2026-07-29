# Copyright (c) 2026 Geofferey
# SPDX-License-Identifier: AGPL-3.0-only

# Best-effort Dynamic DNS updater. Keeps a hostname pointed at the current
# public IPv4 address so a remote viewer can reach the stream at a stable
# name instead of a raw address that changes whenever the ISP rotates it.
# This is the DNS-side complement to UPnP port forwarding
# (31-UpnpPortForwarding.ps1): UPnP makes the right ports reachable, this
# makes sure a name points at wherever those ports currently live. Like
# UPnP, a failure here never blocks the stream -- every call site wraps
# these functions in try/catch and just logs on failure.

$script:DdnsLastAppliedIp = $null
$script:DdnsLastAppliedKey = $null

# A handful of plain-text "what's my IP" endpoints, tried in order. No
# single one of these is authoritative or guaranteed up, so failure of any
# individual endpoint is expected and not logged -- only exhausting all of
# them is worth telling the user about (done by the caller).
function Get-DdnsPublicIPv4Address {
    $endpoints = @('https://api.ipify.org', 'https://icanhazip.com', 'https://ifconfig.me/ip')
    $ipPattern = '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$'
    foreach ($endpoint in $endpoints) {
        try {
            $response = [string](Invoke-RestMethod -Uri $endpoint -TimeoutSec 6 -ErrorAction Stop)
            $candidate = $response.Trim()
            if ($candidate -match $ipPattern) { return $candidate }
        }
        catch {}
    }
    return $null
}

function Update-DdnsRecordDuckDns {
    param([string]$Hostname, [string]$IpAddress)
    $token = [string]$txtDdnsToken.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($token)) {
        Append-Log 'DDNS (DuckDNS): no token configured; skipping update.'
        if ($lblDdnsStatus) {
            $lblDdnsStatus.Text = 'DDNS: DuckDNS token not configured'
            $lblDdnsStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        return $false
    }
    # DuckDNS domains are just the subdomain label, not the full
    # ".duckdns.org" suffix -- strip it if the user pasted the full name.
    $domain = $Hostname -replace '\.duckdns\.org$', ''
    $uri = "https://www.duckdns.org/update?domains=$([System.Uri]::EscapeDataString($domain))&token=$([System.Uri]::EscapeDataString($token))&ip=$IpAddress"
    try {
        $response = [string](Invoke-RestMethod -Uri $uri -TimeoutSec 8 -ErrorAction Stop)
        if ($response.Trim() -eq 'OK') {
            Append-Log "DDNS (DuckDNS): updated $Hostname -> $IpAddress."
            if ($lblDdnsStatus) {
                $lblDdnsStatus.Text = "DDNS: $Hostname -> $IpAddress (DuckDNS)"
                $lblDdnsStatus.ForeColor = [System.Drawing.Color]::DarkGreen
            }
            return $true
        }
        Append-Log "DDNS (DuckDNS): update rejected (response: $($response.Trim()))."
        if ($lblDdnsStatus) {
            $lblDdnsStatus.Text = 'DDNS: DuckDNS rejected the update; see log'
            $lblDdnsStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        return $false
    }
    catch {
        Append-Log "DDNS (DuckDNS): update failed: $($_.Exception.Message)"
        if ($lblDdnsStatus) {
            $lblDdnsStatus.Text = 'DDNS: DuckDNS update failed; see log'
            $lblDdnsStatus.ForeColor = [System.Drawing.Color]::DarkRed
        }
        return $false
    }
}

# Covers the shared "dyndns2" update-URL protocol used by No-IP, Dynu, and
# FreeDNS (and several other providers) -- same URL shape, HTTP Basic auth,
# only the update host differs between them.
function Update-DdnsRecordDynV2 {
    param([string]$Hostname, [string]$IpAddress)
    $updateHost = [string]$txtDdnsDynV2UpdateHost.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($updateHost)) { $updateHost = $script:DefaultDdnsDynV2UpdateHost }
    $username = [string]$txtDdnsUsername.Text
    $password = [string]$txtDdnsPassword.Text
    if ([string]::IsNullOrWhiteSpace($username) -or [string]::IsNullOrWhiteSpace($password)) {
        Append-Log 'DDNS (dyndns2): username/password not configured; skipping update.'
        if ($lblDdnsStatus) {
            $lblDdnsStatus.Text = 'DDNS: dyndns2 username/password not configured'
            $lblDdnsStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        return $false
    }
    $uri = "https://$updateHost/nic/update?hostname=$([System.Uri]::EscapeDataString($Hostname))&myip=$IpAddress"
    $basic = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${username}:${password}"))
    try {
        $response = [string](Invoke-RestMethod -Uri $uri -Headers @{ Authorization = "Basic $basic" } -TimeoutSec 8 -ErrorAction Stop)
        $trimmed = $response.Trim()
        if ($trimmed -match '^(good|nochg)\b') {
            Append-Log "DDNS (dyndns2): updated $Hostname -> $IpAddress via $updateHost ($trimmed)."
            if ($lblDdnsStatus) {
                $lblDdnsStatus.Text = "DDNS: $Hostname -> $IpAddress (dyndns2)"
                $lblDdnsStatus.ForeColor = [System.Drawing.Color]::DarkGreen
            }
            return $true
        }
        Append-Log "DDNS (dyndns2): update rejected by $updateHost (response: $trimmed)."
        if ($lblDdnsStatus) {
            $lblDdnsStatus.Text = 'DDNS: dyndns2 update rejected; see log'
            $lblDdnsStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        return $false
    }
    catch {
        Append-Log "DDNS (dyndns2): update failed: $($_.Exception.Message)"
        if ($lblDdnsStatus) {
            $lblDdnsStatus.Text = 'DDNS: dyndns2 update failed; see log'
            $lblDdnsStatus.ForeColor = [System.Drawing.Color]::DarkRed
        }
        return $false
    }
}

function Update-DdnsRecordCloudflare {
    param([string]$Hostname, [string]$IpAddress)
    $apiToken = [string]$txtDdnsCloudflareApiToken.Text.Trim()
    $zoneId = [string]$txtDdnsCloudflareZoneId.Text.Trim()
    $recordId = [string]$txtDdnsCloudflareRecordId.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($apiToken) -or [string]::IsNullOrWhiteSpace($zoneId) -or [string]::IsNullOrWhiteSpace($recordId)) {
        Append-Log 'DDNS (Cloudflare): API token, zone ID, and record ID must all be configured; skipping update.'
        if ($lblDdnsStatus) {
            $lblDdnsStatus.Text = 'DDNS: Cloudflare token/zone/record not fully configured'
            $lblDdnsStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        return $false
    }
    $proxied = [bool]($chkDdnsCloudflareProxied -and $chkDdnsCloudflareProxied.Checked)
    $uri = "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records/$recordId"
    $body = @{ type = 'A'; name = $Hostname; content = $IpAddress; ttl = 1; proxied = $proxied } | ConvertTo-Json
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Patch -Headers @{ Authorization = "Bearer $apiToken" } -ContentType 'application/json' -Body $body -TimeoutSec 8 -ErrorAction Stop
        if ($response.success) {
            Append-Log "DDNS (Cloudflare): updated $Hostname -> $IpAddress."
            if ($lblDdnsStatus) {
                $lblDdnsStatus.Text = "DDNS: $Hostname -> $IpAddress (Cloudflare)"
                $lblDdnsStatus.ForeColor = [System.Drawing.Color]::DarkGreen
            }
            return $true
        }
        $errorText = @($response.errors | ForEach-Object { $_.message }) -join '; '
        Append-Log "DDNS (Cloudflare): update rejected: $errorText"
        if ($lblDdnsStatus) {
            $lblDdnsStatus.Text = 'DDNS: Cloudflare rejected the update; see log'
            $lblDdnsStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        return $false
    }
    catch {
        Append-Log "DDNS (Cloudflare): update failed: $($_.Exception.Message)"
        if ($lblDdnsStatus) {
            $lblDdnsStatus.Text = 'DDNS: Cloudflare update failed; see log'
            $lblDdnsStatus.ForeColor = [System.Drawing.Color]::DarkRed
        }
        return $false
    }
}

# Escape hatch for any provider not explicitly covered above (or a
# self-hosted update script). {ip} and {hostname} are substituted literally
# into the user's own URL template; Basic auth is only attached when both
# username and password are set, never silently.
function Update-DdnsRecordCustom {
    param([string]$Hostname, [string]$IpAddress)
    $template = [string]$txtDdnsCustomUrlTemplate.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($template)) {
        Append-Log 'DDNS (Custom): no update URL template configured; skipping update.'
        if ($lblDdnsStatus) {
            $lblDdnsStatus.Text = 'DDNS: custom URL template not configured'
            $lblDdnsStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        return $false
    }
    $uri = $template.Replace('{ip}', $IpAddress).Replace('{hostname}', $Hostname)
    $method = [string]$cmbDdnsCustomMethod.SelectedItem
    if ([string]::IsNullOrWhiteSpace($method)) { $method = 'GET' }
    $username = [string]$txtDdnsUsername.Text
    $password = [string]$txtDdnsPassword.Text
    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($username) -and -not [string]::IsNullOrWhiteSpace($password)) {
        $basic = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${username}:${password}"))
        $headers['Authorization'] = "Basic $basic"
    }
    try {
        $null = Invoke-RestMethod -Uri $uri -Method $method -Headers $headers -TimeoutSec 8 -ErrorAction Stop
        Append-Log "DDNS (Custom): updated $Hostname -> $IpAddress."
        if ($lblDdnsStatus) {
            $lblDdnsStatus.Text = "DDNS: $Hostname -> $IpAddress (custom)"
            $lblDdnsStatus.ForeColor = [System.Drawing.Color]::DarkGreen
        }
        return $true
    }
    catch {
        Append-Log "DDNS (Custom): update failed: $($_.Exception.Message)"
        if ($lblDdnsStatus) {
            $lblDdnsStatus.Text = 'DDNS: custom update failed; see log'
            $lblDdnsStatus.ForeColor = [System.Drawing.Color]::DarkRed
        }
        return $false
    }
}

# Entry point, called from the stream-start success paths in
# 27-StreamLifecycle.ps1 (gated on transport actually being enabled, mirroring
# UPnP's own trigger discipline) and from the manual "Update Now" button (so
# credentials can be verified without going live). Skips the provider call
# entirely when the public IP hasn't changed since the last successful
# update, to avoid hitting rate-limited provider APIs on every automatic
# restart -- mirroring how Add-UpnpPortMappings' reconciliation logic avoids
# redundant Add() calls.
function Update-DdnsRecord {
    if (-not ($chkDdnsEnabled -and $chkDdnsEnabled.Checked)) { return }

    $hostname = [string]$txtDdnsHostname.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($hostname)) {
        Append-Log 'DDNS: enabled, but no hostname is configured; skipping update.'
        if ($lblDdnsStatus) {
            $lblDdnsStatus.Text = 'DDNS: enabled, but no hostname configured'
            $lblDdnsStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        return
    }

    $provider = [string]$cmbDdnsProvider.SelectedItem
    $ip = Get-DdnsPublicIPv4Address
    if ([string]::IsNullOrWhiteSpace($ip)) {
        Append-Log 'DDNS: could not determine the current public IPv4 address; skipping update.'
        if ($lblDdnsStatus) {
            $lblDdnsStatus.Text = 'DDNS: could not determine public IP; see log'
            $lblDdnsStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        return
    }

    $applyKey = "$provider|$hostname"
    if ($script:DdnsLastAppliedIp -eq $ip -and $script:DdnsLastAppliedKey -eq $applyKey) {
        Append-Log "DDNS: public IP ($ip) unchanged since last update; skipping provider call."
        if ($lblDdnsStatus) {
            $lblDdnsStatus.Text = "DDNS: $hostname already current at $ip"
            $lblDdnsStatus.ForeColor = [System.Drawing.Color]::DarkGreen
        }
        return
    }

    $updated = switch ($provider) {
        'DuckDNS' { Update-DdnsRecordDuckDns -Hostname $hostname -IpAddress $ip }
        'No-IP / Dynu / FreeDNS (dyndns2)' { Update-DdnsRecordDynV2 -Hostname $hostname -IpAddress $ip }
        'Cloudflare' { Update-DdnsRecordCloudflare -Hostname $hostname -IpAddress $ip }
        'Custom URL' { Update-DdnsRecordCustom -Hostname $hostname -IpAddress $ip }
        default {
            Append-Log "DDNS: unknown provider '$provider'."
            $false
        }
    }

    if ($updated) {
        $script:DdnsLastAppliedIp = $ip
        $script:DdnsLastAppliedKey = $applyKey
    }
}

# Master/detail UI toggling, following the same .Enabled-only convention as
# Update-MediaMtxUi -- provider-specific fields stay laid out and just gray
# out when irrelevant rather than collapsing the pane.
function Update-DdnsUi {
    $enabled = [bool]($chkDdnsEnabled -and $chkDdnsEnabled.Checked)
    $provider = if ($cmbDdnsProvider) { [string]$cmbDdnsProvider.SelectedItem } else { '' }

    foreach ($control in @($cmbDdnsProvider, $txtDdnsHostname, $btnDdnsUpdateNow)) {
        if ($control) { $control.Enabled = $enabled }
    }

    $isDuckDns    = $enabled -and $provider -eq 'DuckDNS'
    $isDynV2      = $enabled -and $provider -eq 'No-IP / Dynu / FreeDNS (dyndns2)'
    $isCloudflare = $enabled -and $provider -eq 'Cloudflare'
    $isCustom     = $enabled -and $provider -eq 'Custom URL'

    if ($txtDdnsToken) { $txtDdnsToken.Enabled = $isDuckDns }
    if ($txtDdnsDynV2UpdateHost) { $txtDdnsDynV2UpdateHost.Enabled = $isDynV2 }

    foreach ($control in @($txtDdnsUsername, $txtDdnsPassword)) {
        if ($control) { $control.Enabled = ($isDynV2 -or $isCustom) }
    }

    foreach ($control in @($txtDdnsCloudflareApiToken, $txtDdnsCloudflareZoneId, $txtDdnsCloudflareRecordId, $chkDdnsCloudflareProxied)) {
        if ($control) { $control.Enabled = $isCloudflare }
    }

    foreach ($control in @($txtDdnsCustomUrlTemplate, $cmbDdnsCustomMethod)) {
        if ($control) { $control.Enabled = $isCustom }
    }
}
