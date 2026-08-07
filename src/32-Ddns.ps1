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

# Tracks whether the Cloudflare Zone field holds a value the user typed
# themselves, as opposed to one this app auto-filled from the Hostname
# field. Starts (or resets) false so auto-fill is active until the user
# actually types into Zone directly, or until a saved settings load finds
# a non-blank Zone already on disk (see Load-Settings in 24-Settings.ps1).
$script:DdnsCloudflareZoneManuallySet = $false
# Set around a programmatic write to the Zone field so its own TextChanged
# handler can tell that write apart from the user actually typing into it.
$script:DdnsSuppressZoneAutoFill = $false

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

# Invoke-RestMethod's own exception message for a non-2xx response is just
# the bare HTTP status line (e.g. "The remote server returned an error:
# (404) Not Found"), which throws away the part that actually explains why
# (a provider's JSON error body, e.g. Cloudflare's "Invalid zone identifier").
# Pull the real response body out of the exception instead, across both
# Windows PowerShell 5.1 (System.Net.WebException) and PowerShell 7+
# (Microsoft.PowerShell.Commands.HttpResponseException), falling back to the
# plain exception message if no body is available.
function Get-DdnsHttpErrorDetail {
    param($ErrorRecord)
    try {
        if ($ErrorRecord.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($ErrorRecord.ErrorDetails.Message)) {
            return $ErrorRecord.ErrorDetails.Message
        }
    }
    catch {}
    try {
        $webResponse = $ErrorRecord.Exception.Response
        if ($webResponse) {
            $stream = $webResponse.GetResponseStream()
            if ($stream) {
                $reader = New-Object System.IO.StreamReader($stream)
                $body = $reader.ReadToEnd()
                if (-not [string]::IsNullOrWhiteSpace($body)) { return $body }
            }
        }
    }
    catch {}
    return $ErrorRecord.Exception.Message
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
        Append-Log "DDNS (DuckDNS): update failed: $(Get-DdnsHttpErrorDetail $_)"
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
        Append-Log "DDNS (dyndns2): update failed: $(Get-DdnsHttpErrorDetail $_)"
        if ($lblDdnsStatus) {
            $lblDdnsStatus.Text = 'DDNS: dyndns2 update failed; see log'
            $lblDdnsStatus.ForeColor = [System.Drawing.Color]::DarkRed
        }
        return $false
    }
}

# Resolves the Cloudflare Zone field (either a real Zone ID or a domain
# name -- see the tolerance note in Update-DdnsRecordCloudflare below) to
# both the Zone ID every zone-scoped API call needs, and the zone's domain
# name for callers that build a record name from a bare hostname label.
# Shared by the DDNS A-record updater and the Let's Encrypt DNS-01 TXT
# challenge (src/33-LetsEncrypt.ps1) so this lookup/tolerance logic exists
# in exactly one place.
function Resolve-CloudflareZoneId {
    param(
        [string]$ZoneFieldValue,
        [hashtable]$Headers,
        [switch]$NeedZoneName
    )
    $result = [pscustomobject]@{ Success = $false; ZoneId = $null; ZoneName = $null; ErrorMessage = $null }
    try {
        if ($ZoneFieldValue -match '^[0-9a-fA-F]{32}$') {
            $result.ZoneId = $ZoneFieldValue
            if ($NeedZoneName) {
                $zoneLookupUri = "https://api.cloudflare.com/client/v4/zones/$($result.ZoneId)"
                $zoneLookupResponse = Invoke-RestMethod -Uri $zoneLookupUri -Headers $Headers -TimeoutSec 8 -ErrorAction Stop
                if (-not $zoneLookupResponse.success -or -not $zoneLookupResponse.result) {
                    $result.ErrorMessage = "could not look up zone '$ZoneFieldValue'; check the Zone field."
                    return $result
                }
                $result.ZoneName = [string]$zoneLookupResponse.result.name
            }
        }
        else {
            $result.ZoneName = $ZoneFieldValue
            $zoneLookupUri = "https://api.cloudflare.com/client/v4/zones?name=$([System.Uri]::EscapeDataString($ZoneFieldValue))"
            $zoneLookupResponse = Invoke-RestMethod -Uri $zoneLookupUri -Headers $Headers -TimeoutSec 8 -ErrorAction Stop
            $matchedZone = @($zoneLookupResponse.result) | Select-Object -First 1
            if (-not $zoneLookupResponse.success -or -not $matchedZone) {
                $result.ErrorMessage = "could not resolve '$ZoneFieldValue' to a zone on this account; check the Zone field (paste the Zone ID from the dashboard, or the exact registered domain name)."
                return $result
            }
            $result.ZoneId = [string]$matchedZone.id
        }
        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = Get-DdnsHttpErrorDetail $_
    }
    return $result
}

function Update-DdnsRecordCloudflare {
    param([string]$Hostname, [string]$IpAddress)
    $apiToken = [string]$txtDdnsToken.Text.Trim()
    $zoneFieldValue = [string]$txtDdnsCloudflareZoneId.Text.Trim()

    # A blank Zone is inferred from everything after the Hostname's first
    # dot (e.g. Hostname "live.netlabwork.net" -> zone "netlabwork.net"). A
    # bare Hostname with no dot (e.g. just "live") is combined with the
    # zone's own domain name instead, once that's resolved below.
    if ([string]::IsNullOrWhiteSpace($zoneFieldValue) -and $Hostname -match '\.') {
        $zoneFieldValue = $Hostname.Substring($Hostname.IndexOf('.') + 1)
    }

    if ([string]::IsNullOrWhiteSpace($apiToken) -or [string]::IsNullOrWhiteSpace($zoneFieldValue)) {
        Append-Log 'DDNS (Cloudflare): API token, and a zone (or a fully-qualified Hostname to derive one from), must be configured; skipping update.'
        if ($lblDdnsStatus) {
            $lblDdnsStatus.Text = 'DDNS: Cloudflare token/zone not fully configured'
            $lblDdnsStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        return $false
    }

    $proxied = [bool]($chkDdnsCloudflareProxied -and $chkDdnsCloudflareProxied.Checked)
    $headers = @{ Authorization = "Bearer $apiToken" }
    # The Zone field accepts either the real Zone ID (a 32-character hex
    # string) or the plain registered domain name -- Cloudflare's own
    # dashboard shows the Zone ID right next to the unrelated Account ID,
    # and typing the domain there instead is an easy, common mixup.
    $needZoneName = ($Hostname -notmatch '\.')

    $zoneResolution = Resolve-CloudflareZoneId -ZoneFieldValue $zoneFieldValue -Headers $headers -NeedZoneName:$needZoneName
    if (-not $zoneResolution.Success) {
        Append-Log "DDNS (Cloudflare): $($zoneResolution.ErrorMessage)"
        if ($lblDdnsStatus) {
            $lblDdnsStatus.Text = 'DDNS: Cloudflare zone not found; see log'
            $lblDdnsStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        return $false
    }
    $zoneId = $zoneResolution.ZoneId
    $zoneName = $zoneResolution.ZoneName

    try {
        # A bare Hostname label (no dot) is the record's subdomain within the
        # zone above, e.g. Hostname "live" + Zone "netlabwork.net" -> update
        # "live.netlabwork.net".
        $recordHostname = if ($needZoneName) { "$Hostname.$zoneName" } else { $Hostname }
        $body = @{ type = 'A'; name = $recordHostname; content = $IpAddress; ttl = 1; proxied = $proxied } | ConvertTo-Json

        # No record ID is asked of the user -- look the existing A record up
        # by name within the zone, and fall back to creating it if this is
        # the first update for a hostname that doesn't have one yet.
        $listUri = "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records?type=A&name=$([System.Uri]::EscapeDataString($recordHostname))"
        $listResponse = Invoke-RestMethod -Uri $listUri -Headers $headers -TimeoutSec 8 -ErrorAction Stop
        if (-not $listResponse.success) {
            $errorText = @($listResponse.errors | ForEach-Object { $_.message }) -join '; '
            Append-Log "DDNS (Cloudflare): could not look up the existing record: $errorText"
            if ($lblDdnsStatus) {
                $lblDdnsStatus.Text = 'DDNS: Cloudflare record lookup failed; see log'
                $lblDdnsStatus.ForeColor = [System.Drawing.Color]::DarkOrange
            }
            return $false
        }

        $existing = @($listResponse.result) | Select-Object -First 1
        if ($existing) {
            $updateUri = "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records/$($existing.id)"
            $response = Invoke-RestMethod -Uri $updateUri -Method Patch -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 8 -ErrorAction Stop
        }
        else {
            $createUri = "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records"
            $response = Invoke-RestMethod -Uri $createUri -Method Post -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 8 -ErrorAction Stop
        }

        if ($response.success) {
            Append-Log "DDNS (Cloudflare): updated $recordHostname -> $IpAddress."
            if ($lblDdnsStatus) {
                $lblDdnsStatus.Text = "DDNS: $recordHostname -> $IpAddress (Cloudflare)"
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
        Append-Log "DDNS (Cloudflare): update failed: $(Get-DdnsHttpErrorDetail $_)"
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
        Append-Log "DDNS (Custom): update failed: $(Get-DdnsHttpErrorDetail $_)"
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

# Master/detail UI toggling. The provider dropdown already tells the user
# which service is selected, so there is no need to list every provider's
# fields at once -- only the group(s) relevant to the selected provider are
# shown at all (their containing section's .Visible is toggled, which also
# collapses the FlowLayoutPanel space they would otherwise take up), and a
# field is reused across providers whenever it is the same kind of value
# (one shared Token/API Token field for DuckDNS + Cloudflare, one shared
# Username/Password pair for dyndns2 + Custom URL basic auth).
function Update-DdnsUi {
    $enabled = [bool]($chkDdnsEnabled -and $chkDdnsEnabled.Checked)
    $provider = if ($cmbDdnsProvider) { [string]$cmbDdnsProvider.SelectedItem } else { '' }

    foreach ($control in @($cmbDdnsProvider, $txtDdnsHostname, $btnDdnsUpdateNow)) {
        if ($control) { $control.Enabled = $enabled }
    }

    $isDuckDns    = $provider -eq 'DuckDNS'
    $isDynV2      = $provider -eq 'No-IP / Dynu / FreeDNS (dyndns2)'
    $isCloudflare = $provider -eq 'Cloudflare'
    $isCustom     = $provider -eq 'Custom URL'

    if ($lblDdnsTokenCaption) { $lblDdnsTokenCaption.Text = if ($isCloudflare) { 'API Token' } else { 'Token' } }

    if ($script:paneDdnsToken) {
        $script:paneDdnsToken.Visible = ($isDuckDns -or $isCloudflare)
        $script:paneDdnsToken.Enabled = $enabled
    }
    if ($script:paneDdnsDynV2) {
        $script:paneDdnsDynV2.Visible = $isDynV2
        $script:paneDdnsDynV2.Enabled = $enabled
    }
    if ($script:paneDdnsCloudflareExtra) {
        $script:paneDdnsCloudflareExtra.Visible = $isCloudflare
        $script:paneDdnsCloudflareExtra.Enabled = $enabled
    }
    if ($script:paneDdnsCustom) {
        $script:paneDdnsCustom.Visible = $isCustom
        $script:paneDdnsCustom.Enabled = $enabled
    }
    if ($script:paneDdnsAccount) {
        $script:paneDdnsAccount.Visible = ($isDynV2 -or $isCustom)
        $script:paneDdnsAccount.Enabled = $enabled
    }

    # Toggling .Visible on the sub-panels above doesn't reliably propagate
    # through this app's nested AutoSize/GrowAndShrink FlowLayoutPanel
    # cascade (sub-panel -> this section's body -> its header/body wrapper
    # -> the outer scrollable pane) via WinForms' own automatic layout
    # invalidation -- confirmed live, and what let this section's body
    # intermittently render in the wrong stacking position relative to
    # other sections (see Add-CollapsibleSection's wrapper comment,
    # src/12-MainDashboardUi.ps1). Walk up and reflow every FlowLayoutPanel
    # ancestor explicitly instead of relying on that automatic propagation.
    $ancestor = $script:paneDdnsToken
    while ($ancestor -is [System.Windows.Forms.FlowLayoutPanel]) {
        $ancestor.PerformLayout()
        $ancestor = $ancestor.Parent
    }
}
