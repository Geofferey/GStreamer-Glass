# Copyright (c) 2026 Geofferey
# SPDX-License-Identifier: AGPL-3.0-only

# Hand-rolled ACME v2 (RFC 8555) client, DNS-01 challenge only, for issuing
# and renewing a Let's Encrypt certificate. No external ACME library/tool
# dependency. The ACME account key (JWS-signs every request) is ECDSA P-256:
# ECDsa.SignData already emits the raw r||s format JWS ES256 requires,
# unlike RSA which would need DER-to-raw conversion. The certificate's own
# key is RSA instead, via the legacy CSP provider -- X509Certificate2's
# CopyWithPrivateKey (the modern way to pair a key with an issued cert)
# only exists on .NET Core 3.0+/.NET 5+, not .NET Framework, and this app
# can run hosted under Windows PowerShell 5.1 (.NET Framework). See
# New-LetsEncryptCertificateKey for the Framework-compatible alternative.
#
# The DNS-01 challenge publishes a TXT record at _acme-challenge.<hostname>,
# which reuses the Dynamic DNS hostname and provider credentials already
# configured in src/32-Ddns.ps1 -- no separate hostname/credential fields.
# TXT-record management is only realistic for Cloudflare (generic DNS record
# API) and DuckDNS (its txt= parameter is documented specifically for this).
#
# Like UPnP/DDNS, a failure here never blocks the stream: every call site
# wraps these functions in try/catch and just logs on failure.

# Running TlsTerminatingProxy instances (see Start-LetsEncryptTlsProxies),
# one per externally-exposed port. Empty when TLS termination isn't active.
$script:LetsEncryptTlsProxies = @()
$script:LetsEncryptTlsProxyConfigurationSignature = ''

function ConvertTo-AcmeBase64Url {
    param([byte[]]$Bytes)
    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Get-LetsEncryptCertificateDirectory {
    $dir = Join-Path $script:ConfigDirectory 'Certificates'
    if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    return $dir
}

function Set-LetsEncryptStatus {
    param([string]$Text, [string]$ColorName = 'DimGray')
    if ($lblLetsEncryptStatus) {
        $lblLetsEncryptStatus.Text = $Text
        $lblLetsEncryptStatus.ForeColor = [System.Drawing.Color]::FromName($ColorName)
    }
}

function Get-AcmeDirectoryUrl {
    if ($chkLetsEncryptStaging -and $chkLetsEncryptStaging.Checked) {
        return 'https://acme-staging-v02.api.letsencrypt.org/directory'
    }
    return 'https://acme-v02.api.letsencrypt.org/directory'
}

function Get-AcmeDirectory {
    return Invoke-RestMethod -Uri (Get-AcmeDirectoryUrl) -TimeoutSec 15 -ErrorAction Stop
}

# Normalizes response header access across Windows PowerShell 5.1
# (WebHeaderCollection-backed, string indexer) and PowerShell 7+
# (Dictionary<string, IEnumerable<string>>-backed) response objects.
function Get-AcmeHeaderValue {
    param($Response, [string]$Name)
    try {
        $value = $Response.Headers[$Name]
        if ($null -eq $value) { return $null }
        if ($value -is [string]) { return $value }
        return [string](@($value) | Select-Object -First 1)
    }
    catch { return $null }
}

# Invoke-WebRequest only decodes .Content as a string for Content-Types it
# recognizes as text (e.g. application/json). Let's Encrypt's certificate
# download uses application/pem-certificate-chain, which isn't on that
# list, so .Content comes back as a raw byte[] -- casting a byte array with
# [string] does NOT decode it as text, it joins the numeric byte values
# with spaces, which is why the PEM regex below found nothing. Decode
# explicitly instead of assuming the content is already a string.
function Get-AcmeResponseText {
    param($Response)
    $content = $Response.Content
    if ($content -is [byte[]]) { return [System.Text.Encoding]::UTF8.GetString($content) }
    return [string]$content
}

function Get-AcmeFreshNonce {
    $directory = Get-AcmeDirectory
    $response = Invoke-WebRequest -Uri $directory.newNonce -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
    return Get-AcmeHeaderValue -Response $response -Name 'Replay-Nonce'
}

# Persisted ECDSA P-256 account key, in plain JSON -- consistent with the
# plaintext credential storage already accepted for TURN/DDNS in this app
# (see 24-Settings.ps1), not a new encryption mechanism.
function Get-AcmeAccountKey {
    $keyPath = Join-Path (Get-LetsEncryptCertificateDirectory) 'acme-account-key.json'
    $curve = [System.Security.Cryptography.ECCurve]::CreateFromFriendlyName('nistP256')

    if (Test-Path -LiteralPath $keyPath) {
        $saved = Get-Content -LiteralPath $keyPath -Raw | ConvertFrom-Json
        $ecParams = New-Object System.Security.Cryptography.ECParameters
        $ecParams.Curve = $curve
        $ecParams.D = [Convert]::FromBase64String($saved.D)
        $point = New-Object System.Security.Cryptography.ECPoint
        $point.X = [Convert]::FromBase64String($saved.X)
        $point.Y = [Convert]::FromBase64String($saved.Y)
        $ecParams.Q = $point
        $ecdsa = [System.Security.Cryptography.ECDsa]::Create()
        $ecdsa.ImportParameters($ecParams)
        return $ecdsa
    }

    $ecdsa = [System.Security.Cryptography.ECDsa]::Create($curve)
    $exportParams = $ecdsa.ExportParameters($true)
    $saved = [ordered]@{
        D = [Convert]::ToBase64String($exportParams.D)
        X = [Convert]::ToBase64String($exportParams.Q.X)
        Y = [Convert]::ToBase64String($exportParams.Q.Y)
    } | ConvertTo-Json -Compress
    Set-Content -LiteralPath $keyPath -Value $saved -Encoding UTF8
    return $ecdsa
}

function Get-AcmeJwk {
    param([Parameter(Mandatory)]$AccountKey)
    $parameters = $AccountKey.ExportParameters($false)
    return [ordered]@{
        crv = 'P-256'
        kty = 'EC'
        x   = ConvertTo-AcmeBase64Url $parameters.Q.X
        y   = ConvertTo-AcmeBase64Url $parameters.Q.Y
    }
}

# RFC 7638 thumbprint: canonical JSON with lexicographically ordered members
# and no insignificant whitespace. Built by hand rather than trusting
# ConvertTo-Json's member ordering, since thumbprint correctness depends on
# this exact byte sequence.
function Get-AcmeJwkThumbprint {
    param([Parameter(Mandatory)]$AccountKey)
    $parameters = $AccountKey.ExportParameters($false)
    $x = ConvertTo-AcmeBase64Url $parameters.Q.X
    $y = ConvertTo-AcmeBase64Url $parameters.Q.Y
    $canonicalJson = '{"crv":"P-256","kty":"EC","x":"' + $x + '","y":"' + $y + '"}'
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($canonicalJson))
    return ConvertTo-AcmeBase64Url $hash
}

# Core signed-request helper -- every ACME POST (RFC 8555 SS6.2) is a
# flattened JWS: {protected, payload, signature}, all base64url. $Payload
# of $null means "POST-as-GET" (empty payload string); an empty hashtable
# @{} means a literal "{}" body (used to signal challenge readiness).
function Invoke-AcmeSignedRequest {
    param(
        [Parameter(Mandatory)][string]$Url,
        $Payload,
        [Parameter(Mandatory)]$AccountKey,
        [string]$Kid,
        [Parameter(Mandatory)][ref]$NonceRef,
        [switch]$RawResponse,
        [switch]$Retried
    )

    $protectedHeader = [ordered]@{ alg = 'ES256'; nonce = $NonceRef.Value; url = $Url }
    if ($Kid) { $protectedHeader['kid'] = $Kid } else { $protectedHeader['jwk'] = Get-AcmeJwk -AccountKey $AccountKey }

    $protectedB64 = ConvertTo-AcmeBase64Url ([System.Text.Encoding]::UTF8.GetBytes(($protectedHeader | ConvertTo-Json -Compress -Depth 6)))
    $payloadB64 = if ($null -eq $Payload) { '' } else { ConvertTo-AcmeBase64Url ([System.Text.Encoding]::UTF8.GetBytes(($Payload | ConvertTo-Json -Compress -Depth 6))) }

    $signingInput = [System.Text.Encoding]::ASCII.GetBytes("$protectedB64.$payloadB64")
    $signatureB64 = ConvertTo-AcmeBase64Url ($AccountKey.SignData($signingInput, [System.Security.Cryptography.HashAlgorithmName]::SHA256))

    $bodyJson = @{ protected = $protectedB64; payload = $payloadB64; signature = $signatureB64 } | ConvertTo-Json -Compress

    try {
        $response = Invoke-WebRequest -Uri $Url -Method Post -Body $bodyJson -ContentType 'application/jose+json' -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
        $freshNonce = Get-AcmeHeaderValue -Response $response -Name 'Replay-Nonce'
        if ($freshNonce) { $NonceRef.Value = $freshNonce }
        if ($RawResponse) { return $response }
        $responseText = Get-AcmeResponseText -Response $response
        if ([string]::IsNullOrWhiteSpace($responseText)) { return $null }
        return ($responseText | ConvertFrom-Json)
    }
    catch {
        $detail = Get-DdnsHttpErrorDetail $_
        if (-not $Retried -and $detail -match 'urn:ietf:params:acme:error:badNonce') {
            $NonceRef.Value = Get-AcmeFreshNonce
            return Invoke-AcmeSignedRequest -Url $Url -Payload $Payload -AccountKey $AccountKey -Kid $Kid -NonceRef $NonceRef -RawResponse:$RawResponse -Retried
        }
        throw $detail
    }
}

function Get-AcmeAccountStatePath { Join-Path (Get-LetsEncryptCertificateDirectory) 'acme-account-state.json' }

function Get-AcmeAccountState {
    $path = Get-AcmeAccountStatePath
    if (Test-Path -LiteralPath $path) { return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json) }
    return $null
}

function Save-AcmeAccountState {
    param([string]$Kid, [bool]$Staging)
    @{ Kid = $Kid; Staging = $Staging } | ConvertTo-Json -Compress | Set-Content -LiteralPath (Get-AcmeAccountStatePath) -Encoding UTF8
}

function Register-AcmeAccount {
    param([Parameter(Mandatory)]$AccountKey, [string]$Email, [bool]$Staging, [ref]$NonceRef)
    $directory = Get-AcmeDirectory
    $NonceRef.Value = Get-AcmeFreshNonce
    $payload = [ordered]@{ termsOfServiceAgreed = $true }
    if (-not [string]::IsNullOrWhiteSpace($Email)) { $payload['contact'] = @("mailto:$Email") }
    $response = Invoke-AcmeSignedRequest -Url $directory.newAccount -Payload $payload -AccountKey $AccountKey -NonceRef $NonceRef -RawResponse
    $kid = Get-AcmeHeaderValue -Response $response -Name 'Location'
    Save-AcmeAccountState -Kid $kid -Staging $Staging
    return $kid
}

function Get-AcmeDnsTxtValue {
    param([Parameter(Mandatory)]$AccountKey, [string]$Token)
    $thumbprint = Get-AcmeJwkThumbprint -AccountKey $AccountKey
    $keyAuthorization = "$Token.$thumbprint"
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($keyAuthorization))
    return ConvertTo-AcmeBase64Url $hash
}

function Add-AcmeDnsTxtRecordCloudflare {
    param([string]$Hostname, [string]$TxtValue)
    $apiToken = [string]$txtDdnsToken.Text.Trim()
    $zoneFieldValue = [string]$txtDdnsCloudflareZoneId.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($zoneFieldValue) -and $Hostname -match '\.') {
        $zoneFieldValue = $Hostname.Substring($Hostname.IndexOf('.') + 1)
    }
    if ([string]::IsNullOrWhiteSpace($apiToken) -or [string]::IsNullOrWhiteSpace($zoneFieldValue)) {
        Append-Log 'ACME (Cloudflare): API token and zone must be configured; cannot publish the DNS-01 challenge.'
        return $null
    }
    $headers = @{ Authorization = "Bearer $apiToken" }
    $zoneResolution = Resolve-CloudflareZoneId -ZoneFieldValue $zoneFieldValue -Headers $headers
    if (-not $zoneResolution.Success) {
        Append-Log "ACME (Cloudflare): $($zoneResolution.ErrorMessage)"
        return $null
    }
    $body = @{ type = 'TXT'; name = "_acme-challenge.$Hostname"; content = $TxtValue; ttl = 60 } | ConvertTo-Json
    try {
        $createUri = "https://api.cloudflare.com/client/v4/zones/$($zoneResolution.ZoneId)/dns_records"
        $response = Invoke-RestMethod -Uri $createUri -Method Post -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 8 -ErrorAction Stop
        if ($response.success) { return [string]$response.result.id }
        $errorText = @($response.errors | ForEach-Object { $_.message }) -join '; '
        Append-Log "ACME (Cloudflare): could not create the challenge TXT record: $errorText"
        return $null
    }
    catch {
        Append-Log "ACME (Cloudflare): could not create the challenge TXT record: $(Get-DdnsHttpErrorDetail $_)"
        return $null
    }
}

function Remove-AcmeDnsTxtRecordCloudflare {
    param([string]$Hostname, [string]$RecordId)
    if ([string]::IsNullOrWhiteSpace($RecordId)) { return }
    $apiToken = [string]$txtDdnsToken.Text.Trim()
    $zoneFieldValue = [string]$txtDdnsCloudflareZoneId.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($zoneFieldValue) -and $Hostname -match '\.') {
        $zoneFieldValue = $Hostname.Substring($Hostname.IndexOf('.') + 1)
    }
    $headers = @{ Authorization = "Bearer $apiToken" }
    $zoneResolution = Resolve-CloudflareZoneId -ZoneFieldValue $zoneFieldValue -Headers $headers
    if (-not $zoneResolution.Success) { return }
    try {
        $deleteUri = "https://api.cloudflare.com/client/v4/zones/$($zoneResolution.ZoneId)/dns_records/$RecordId"
        $null = Invoke-RestMethod -Uri $deleteUri -Method Delete -Headers $headers -TimeoutSec 8 -ErrorAction Stop
    }
    catch {
        Append-Log "ACME (Cloudflare): could not remove the challenge TXT record: $(Get-DdnsHttpErrorDetail $_)"
    }
}

# DuckDNS's txt= update parameter is documented to publish specifically at
# _acme-challenge.<name>.duckdns.org -- no arbitrary record name needed.
function Add-AcmeDnsTxtRecordDuckDns {
    param([string]$Hostname, [string]$TxtValue)
    $token = [string]$txtDdnsToken.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($token)) {
        Append-Log 'ACME (DuckDNS): no token configured; cannot publish the DNS-01 challenge.'
        return $false
    }
    $domain = $Hostname -replace '\.duckdns\.org$', ''
    $uri = "https://www.duckdns.org/update?domains=$([System.Uri]::EscapeDataString($domain))&token=$([System.Uri]::EscapeDataString($token))&txt=$([System.Uri]::EscapeDataString($TxtValue))"
    try {
        $response = [string](Invoke-RestMethod -Uri $uri -TimeoutSec 8 -ErrorAction Stop)
        if ($response.Trim().StartsWith('OK')) { return $true }
        Append-Log "ACME (DuckDNS): TXT update rejected (response: $($response.Trim()))."
        return $false
    }
    catch {
        Append-Log "ACME (DuckDNS): could not publish the challenge TXT record: $(Get-DdnsHttpErrorDetail $_)"
        return $false
    }
}

function Remove-AcmeDnsTxtRecordDuckDns {
    param([string]$Hostname)
    $token = [string]$txtDdnsToken.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($token)) { return }
    $domain = $Hostname -replace '\.duckdns\.org$', ''
    $uri = "https://www.duckdns.org/update?domains=$([System.Uri]::EscapeDataString($domain))&token=$([System.Uri]::EscapeDataString($token))&txt=remove&clear=true"
    try { $null = Invoke-RestMethod -Uri $uri -TimeoutSec 8 -ErrorAction Stop }
    catch { Append-Log "ACME (DuckDNS): could not clear the challenge TXT record: $(Get-DdnsHttpErrorDetail $_)" }
}

# Best-effort pre-check against a public resolver before telling Let's
# Encrypt the challenge is ready, to cut down on failed-validation churn
# against a real rate-limited service. Resolve-DnsName is Windows-builtin;
# if it's unavailable for some reason this just skips straight to
# submitting the challenge rather than failing issuance over a nice-to-have.
function Wait-AcmeDnsPropagation {
    param([string]$Hostname, [string]$ExpectedValue, [int]$TimeoutSeconds = 60)
    if (-not (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue)) { return $true }
    $recordName = "_acme-challenge.$Hostname"
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $records = Resolve-DnsName -Name $recordName -Type TXT -Server 8.8.8.8 -ErrorAction Stop
            $values = @($records | Where-Object { $_.Type -eq 'TXT' } | ForEach-Object { $_.Strings -join '' })
            if ($values -contains $ExpectedValue) { return $true }
        }
        catch {}
        Start-Sleep -Seconds 5
    }
    return $false
}

function Submit-AcmeChallenge {
    param([Parameter(Mandatory)]$AccountKey, [string]$Kid, [string]$ChallengeUrl, [ref]$NonceRef)
    return Invoke-AcmeSignedRequest -Url $ChallengeUrl -Payload @{} -AccountKey $AccountKey -Kid $Kid -NonceRef $NonceRef
}

function Wait-AcmeAuthorizationValid {
    param([Parameter(Mandatory)]$AccountKey, [string]$Kid, [string]$AuthorizationUrl, [ref]$NonceRef, [int]$TimeoutSeconds = 90)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $authz = Invoke-AcmeSignedRequest -Url $AuthorizationUrl -Payload $null -AccountKey $AccountKey -Kid $Kid -NonceRef $NonceRef
        if ($authz.status -eq 'valid') { return $true }
        if ($authz.status -eq 'invalid') { return $false }
        Start-Sleep -Seconds 3
    }
    return $false
}

# RSA specifically -- see Set-LetsEncryptCertificatePrivateKey (below,
# near where it's used) for why, and for which of the two key types this
# picks. The ACME account key stays ECDSA (New-Acme*Key functions above)
# since it's only ever used to sign JWS requests, never attached to a
# certificate, so none of this applies to it.
function New-LetsEncryptCertificateKey {
    if (Test-LetsEncryptModernKeyAttachment) {
        return [System.Security.Cryptography.RSA]::Create(2048)
    }
    return New-Object System.Security.Cryptography.RSACryptoServiceProvider(2048)
}

function New-AcmeCsr {
    param([string]$Hostname, [Parameter(Mandatory)]$CertificateKey)
    $subject = New-Object System.Security.Cryptography.X509Certificates.X500DistinguishedName("CN=$Hostname")
    $request = New-Object System.Security.Cryptography.X509Certificates.CertificateRequest(
        $subject, $CertificateKey, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $sanBuilder = New-Object System.Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder
    $sanBuilder.AddDnsName($Hostname)
    $request.CertificateExtensions.Add($sanBuilder.Build())
    return ConvertTo-AcmeBase64Url $request.CreateSigningRequest()
}

function Complete-AcmeOrder {
    param([Parameter(Mandatory)]$AccountKey, [string]$Kid, [string]$FinalizeUrl, [string]$OrderUrl, [string]$Csr, [ref]$NonceRef, [int]$TimeoutSeconds = 60)
    $null = Invoke-AcmeSignedRequest -Url $FinalizeUrl -Payload @{ csr = $Csr } -AccountKey $AccountKey -Kid $Kid -NonceRef $NonceRef

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $order = Invoke-AcmeSignedRequest -Url $OrderUrl -Payload $null -AccountKey $AccountKey -Kid $Kid -NonceRef $NonceRef
        if ($order.status -eq 'valid') { return $order }
        if ($order.status -eq 'invalid') { throw "Order became invalid during finalization." }
        Start-Sleep -Seconds 3
    }
    throw 'Timed out waiting for the order to finalize.'
}

function Get-AcmeCertificatePem {
    param([Parameter(Mandatory)]$AccountKey, [string]$Kid, [string]$CertificateUrl, [ref]$NonceRef)
    # The certificate download is a POST-as-GET returning PEM text directly,
    # not JSON -- ask for the raw response and decode its content explicitly.
    $response = Invoke-AcmeSignedRequest -Url $CertificateUrl -Payload $null -AccountKey $AccountKey -Kid $Kid -NonceRef $NonceRef -RawResponse
    return Get-AcmeResponseText -Response $response
}

# X509Certificate2.CopyWithPrivateKey(RSA) is a C# *extension* method,
# defined on RSACertificateExtensions rather than as an instance method on
# X509Certificate2 itself -- PowerShell cannot call extension methods via
# ordinary dot syntax ($cert.CopyWithPrivateKey(...)), so that always fails
# with "does not contain a method named ..." even where the API genuinely
# exists. It must be invoked as a static method on its declaring class
# instead. That class only exists on .NET Core 3.0+/.NET 5+ -- .NET
# Framework (this app can run hosted under Windows PowerShell 5.1) has no
# such class at all, and instead needs the legacy CSP-based PrivateKey
# property setter (which only works with RSACryptoServiceProvider-style
# keys, not the modern RSA.Create() used on the other path -- see
# New-LetsEncryptCertificateKey).
function Test-LetsEncryptModernKeyAttachment {
    return $null -ne ([System.Management.Automation.PSTypeName]'System.Security.Cryptography.X509Certificates.RSACertificateExtensions').Type
}

function Set-LetsEncryptCertificatePrivateKey {
    param([Parameter(Mandatory)]$Certificate, [Parameter(Mandatory)]$PrivateKey)
    if (Test-LetsEncryptModernKeyAttachment) {
        return [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::CopyWithPrivateKey($Certificate, $PrivateKey)
    }
    $Certificate.PrivateKey = $PrivateKey
    return $Certificate
}

function Save-LetsEncryptCertificatePfx {
    param([string]$PemChain, [Parameter(Mandatory)]$CertificateKey, [string]$Hostname)
    $blocks = [regex]::Matches($PemChain, '-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', [System.Text.RegularExpressions.RegexOptions]::Singleline) | ForEach-Object { $_.Value }
    if ($blocks.Count -eq 0) { throw "No certificates found in the ACME response." }

    # New-Object's -ArgumentList splats an array argument into one
    # constructor parameter per element (a well-known PowerShell pitfall),
    # which turns a byte[] into "one argument per byte" instead of a single
    # byte[] argument -- exactly what produced the earlier "argument count:
    # 1345" error. The ::new() static-constructor syntax passes the byte[]
    # through as-is, so it's used for these two byte[]-array constructors.
    $leaf = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new([System.Text.Encoding]::ASCII.GetBytes($blocks[0]))
    $leaf = Set-LetsEncryptCertificatePrivateKey -Certificate $leaf -PrivateKey $CertificateKey

    $collection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
    $null = $collection.Add($leaf)
    foreach ($block in ($blocks | Select-Object -Skip 1)) {
        $null = $collection.Add([System.Security.Cryptography.X509Certificates.X509Certificate2]::new([System.Text.Encoding]::ASCII.GetBytes($block)))
    }

    $pfxBytes = $collection.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx)
    $pfxPath = Join-Path (Get-LetsEncryptCertificateDirectory) "$Hostname.pfx"
    [System.IO.File]::WriteAllBytes($pfxPath, $pfxBytes)
    return $pfxPath
}

function Get-LetsEncryptCertificateStatePath { Join-Path (Get-LetsEncryptCertificateDirectory) 'certificate-state.json' }

function Get-LetsEncryptCertificateState {
    $path = Get-LetsEncryptCertificateStatePath
    if (Test-Path -LiteralPath $path) { return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json) }
    return $null
}

function Save-LetsEncryptCertificateState {
    param([string]$Hostname, [string]$PfxPath, [datetime]$NotAfter)
    @{ Hostname = $Hostname; PfxPath = $PfxPath; NotAfterUtc = $NotAfter.ToUniversalTime().ToString('o') } |
        ConvertTo-Json -Compress | Set-Content -LiteralPath (Get-LetsEncryptCertificateStatePath) -Encoding UTF8
}

# Renews inside 30 days of expiry, mirroring common ACME client practice.
function Test-LetsEncryptCertificateNeedsRenewal {
    param([string]$Hostname)
    $state = Get-LetsEncryptCertificateState
    if (-not $state -or $state.Hostname -ne $Hostname -or -not (Test-Path -LiteralPath $state.PfxPath)) { return $true }
    try {
        $notAfter = [datetime]::Parse($state.NotAfterUtc, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
        return ((Get-Date).ToUniversalTime().AddDays(30) -ge $notAfter)
    }
    catch { return $true }
}

# Whether TLS termination should actually be active right now: the feature
# is enabled, a DDNS hostname is configured, and a certificate matching
# that hostname already exists on disk (issued via "Issue/Renew Now" or a
# previous stream start -- see Update-LetsEncryptCertificate). This is the
# single source of truth src/17-DirectWebRtcPipeline.ps1,
# src/27-StreamLifecycle.ps1, and src/31-UpnpPortForwarding.ps1 all check,
# so "is TLS on" can never disagree between the pipeline, the proxy
# lifecycle, and the UPnP mapping.
function Test-LetsEncryptTlsActive {
    if (-not ($chkLetsEncryptEnabled -and $chkLetsEncryptEnabled.Checked)) { return $false }
    $hostname = [string]$txtDdnsHostname.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($hostname)) { return $false }
    $state = Get-LetsEncryptCertificateState
    return [bool]($state -and [string]$state.Hostname -eq $hostname -and (Test-Path -LiteralPath ([string]$state.PfxPath)))
}

# Loads the issued certificate (with its private key) for TlsTerminatingProxy
# instances to present. Returns $null rather than throwing if TLS isn't
# active or the file can't be loaded -- every caller treats a missing
# certificate as "skip starting the proxy," best-effort like every other
# UPnP/DDNS/ACME integration point.
function Get-LetsEncryptTlsCertificate {
    if (-not (Test-LetsEncryptTlsActive)) { return $null }
    $state = Get-LetsEncryptCertificateState
    try {
        return [System.Security.Cryptography.X509Certificates.X509Certificate2]::new([string]$state.PfxPath)
    }
    catch {
        Append-Log "ACME: could not load certificate from '$($state.PfxPath)': $($_.Exception.Message)"
        return $null
    }
}

# Top-level orchestrator, same shape as Update-DdnsRecord: gated on the
# enable checkbox, best-effort, skips work when the current cert is still
# valid and not near expiry.
function Update-LetsEncryptCertificate {
    if (-not ($chkLetsEncryptEnabled -and $chkLetsEncryptEnabled.Checked)) { return }

    $hostname = [string]$txtDdnsHostname.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($hostname)) {
        Append-Log 'ACME: enabled, but no DDNS hostname is configured; skipping.'
        Set-LetsEncryptStatus 'ACME: enabled, but no hostname configured (set one under Dynamic DNS)' 'DarkOrange'
        return
    }

    $provider = [string]$cmbDdnsProvider.SelectedItem
    if ($provider -ne 'Cloudflare' -and $provider -ne 'DuckDNS') {
        Append-Log "ACME: DNS-01 is only supported with Cloudflare or DuckDNS as the DDNS provider (current: $provider)."
        Set-LetsEncryptStatus 'ACME: needs Cloudflare or DuckDNS as the DDNS provider' 'DarkOrange'
        return
    }

    if (-not (Test-LetsEncryptCertificateNeedsRenewal -Hostname $hostname)) {
        Set-LetsEncryptStatus "ACME: certificate for $hostname is already current" 'DarkGreen'
        return
    }

    $staging = [bool]($chkLetsEncryptStaging -and $chkLetsEncryptStaging.Checked)
    $email = [string]$txtLetsEncryptEmail.Text.Trim()
    $challengeRecordId = $null
    $nonce = $null

    try {
        $accountKey = Get-AcmeAccountKey
        $savedAccount = Get-AcmeAccountState
        if ($savedAccount -and $savedAccount.Staging -eq $staging -and $savedAccount.Kid) {
            $kid = [string]$savedAccount.Kid
            $nonce = Get-AcmeFreshNonce
        }
        else {
            $kid = Register-AcmeAccount -AccountKey $accountKey -Email $email -Staging $staging -NonceRef ([ref]$nonce)
        }

        $directory = Get-AcmeDirectory
        if (-not $nonce) { $nonce = Get-AcmeFreshNonce }
        $orderResponse = Invoke-AcmeSignedRequest -Url $directory.newOrder -Payload @{ identifiers = @(@{ type = 'dns'; value = $hostname }) } -AccountKey $accountKey -Kid $kid -NonceRef ([ref]$nonce) -RawResponse
        $orderUrl = Get-AcmeHeaderValue -Response $orderResponse -Name 'Location'
        $order = Get-AcmeResponseText -Response $orderResponse | ConvertFrom-Json

        $authzUrl = @($order.authorizations) | Select-Object -First 1
        $authz = Invoke-AcmeSignedRequest -Url $authzUrl -Payload $null -AccountKey $accountKey -Kid $kid -NonceRef ([ref]$nonce)
        $challenge = @($authz.challenges) | Where-Object { $_.type -eq 'dns-01' } | Select-Object -First 1
        if (-not $challenge) { throw "Let's Encrypt did not offer a dns-01 challenge for this order." }

        $txtValue = Get-AcmeDnsTxtValue -AccountKey $accountKey -Token $challenge.token

        Set-LetsEncryptStatus "ACME: publishing DNS-01 challenge for $hostname..."
        if ($provider -eq 'Cloudflare') {
            $challengeRecordId = Add-AcmeDnsTxtRecordCloudflare -Hostname $hostname -TxtValue $txtValue
            if (-not $challengeRecordId) { throw 'Could not publish the Cloudflare challenge TXT record.' }
        }
        else {
            if (-not (Add-AcmeDnsTxtRecordDuckDns -Hostname $hostname -TxtValue $txtValue)) { throw 'Could not publish the DuckDNS challenge TXT record.' }
        }

        $null = Wait-AcmeDnsPropagation -Hostname $hostname -ExpectedValue $txtValue

        $null = Submit-AcmeChallenge -AccountKey $accountKey -Kid $kid -ChallengeUrl $challenge.url -NonceRef ([ref]$nonce)
        if (-not (Wait-AcmeAuthorizationValid -AccountKey $accountKey -Kid $kid -AuthorizationUrl $authzUrl -NonceRef ([ref]$nonce))) {
            throw 'DNS-01 challenge validation failed or timed out.'
        }

        $certificateKey = New-LetsEncryptCertificateKey
        $csr = New-AcmeCsr -Hostname $hostname -CertificateKey $certificateKey
        $finalizedOrder = Complete-AcmeOrder -AccountKey $accountKey -Kid $kid -FinalizeUrl $order.finalize -OrderUrl $orderUrl -Csr $csr -NonceRef ([ref]$nonce)

        $pem = Get-AcmeCertificatePem -AccountKey $accountKey -Kid $kid -CertificateUrl $finalizedOrder.certificate -NonceRef ([ref]$nonce)
        $pfxPath = Save-LetsEncryptCertificatePfx -PemChain $pem -CertificateKey $certificateKey -Hostname $hostname

        $leafCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($pfxPath)
        Save-LetsEncryptCertificateState -Hostname $hostname -PfxPath $pfxPath -NotAfter $leafCert.NotAfter

        $envLabel = if ($staging) { 'staging' } else { 'production' }
        Append-Log "ACME: issued a new certificate for $hostname ($envLabel), valid until $($leafCert.NotAfter)."
        Set-LetsEncryptStatus "ACME: certificate for $hostname valid until $($leafCert.NotAfter.ToString('yyyy-MM-dd')) ($envLabel)" 'DarkGreen'
    }
    catch {
        Append-Log "ACME: certificate issuance failed: $($_.Exception.Message)"
        Set-LetsEncryptStatus 'ACME: certificate issuance failed; see log' 'DarkRed'
    }
    finally {
        if ($provider -eq 'Cloudflare' -and $challengeRecordId) {
            Remove-AcmeDnsTxtRecordCloudflare -Hostname $hostname -RecordId $challengeRecordId
        }
        elseif ($provider -eq 'DuckDNS') {
            Remove-AcmeDnsTxtRecordDuckDns -Hostname $hostname
        }
    }
}

# Master/detail UI toggling, same pattern as Update-DdnsUi. Also refreshes
# the status label from on-disk certificate state -- safe to do unconditionally
# here since this is only ever called from startup/checkbox/provider-change
# events, never concurrently with an in-progress issuance's own status updates.
function Update-LetsEncryptUi {
    $enabled = [bool]($chkLetsEncryptEnabled -and $chkLetsEncryptEnabled.Checked)
    foreach ($control in @($txtLetsEncryptEmail, $chkLetsEncryptStaging, $numLetsEncryptSignalingExternalPort, $numLetsEncryptSplitAudioExternalPort, $numLetsEncryptWebServerExternalPort, $btnLetsEncryptIssueNow)) {
        if ($control) { $control.Enabled = $enabled }
    }
    Update-ViewerAuthenticationUi

    if (-not $enabled) {
        Set-LetsEncryptStatus 'ACME: disabled'
        return
    }

    $provider = [string]$cmbDdnsProvider.SelectedItem
    if ($provider -ne 'Cloudflare' -and $provider -ne 'DuckDNS') {
        Set-LetsEncryptStatus 'ACME: needs Cloudflare or DuckDNS as the DDNS provider' 'DarkOrange'
        return
    }

    $hostname = [string]$txtDdnsHostname.Text.Trim()
    $state = Get-LetsEncryptCertificateState
    if ($state -and $state.Hostname -eq $hostname -and (Test-Path -LiteralPath $state.PfxPath)) {
        Set-LetsEncryptStatus "ACME: certificate for $hostname on file (see log for validity)" 'DarkGreen'
    }
    else {
        Set-LetsEncryptStatus 'ACME: enabled - will issue a certificate when the stream starts' 'DimGray'
    }
}

function Test-ViewerAuthenticationEnabled {
    return [bool]($chkViewerAuthenticationEnabled -and $chkViewerAuthenticationEnabled.Checked)
}

function Update-ViewerAuthenticationUi {
    $tlsEnabled = [bool]($chkLetsEncryptEnabled -and $chkLetsEncryptEnabled.Checked)
    $authenticationEnabled = [bool]($tlsEnabled -and (Test-ViewerAuthenticationEnabled))
    if ($chkViewerAuthenticationEnabled) { $chkViewerAuthenticationEnabled.Enabled = $tlsEnabled }
    foreach ($control in @($txtViewerAuthenticationUsername, $txtViewerAuthenticationPassword, $numViewerAuthenticationSessionHours)) {
        if ($control) { $control.Enabled = $authenticationEnabled }
    }
}

# Starts one TlsTerminatingProxy per port that needs external HTTPS/WSS
# exposure (video signalling, split-audio signalling when it runs its own
# server, web viewer), forwarding to webrtcsink's own now-loopback-only
# servers (Get-DirectWebRtcSignalingServerBindHost/-WebServerBindAddress in
# 17-DirectWebRtcPipeline.ps1). Called from the same stream-start success
# paths as Add-UpnpPortMappings/Update-DdnsRecord (27-StreamLifecycle.ps1),
# gated the same way. A no-op if proxies are already running -- an
# automatic restart-in-place doesn't tear them down (see
# Stop-LetsEncryptTlsProxies), so this just leaves the still-live ones
# alone rather than failing on an address-already-in-use retry.
# The TLS proxy's own effective port for each of the three exposed
# services (0 = same number as webrtcsink's/the web server's real internal
# port). Shared by Start-LetsEncryptTlsProxies (what to listen on),
# Get-DirectWebRtcEffectiveExternalSignalingPort/-SplitAudio... in
# 17-DirectWebRtcPipeline.ps1 (what to tell the browser), and
# Get-UpnpRequiredMappings in 31-UpnpPortForwarding.ps1 (what the router
# should actually forward to, since webrtcsink's own port is loopback-only
# once TLS is active) -- one calculation, three consumers.
function Get-LetsEncryptSignalingProxyPort {
    $override = [int]$numLetsEncryptSignalingExternalPort.Value
    if ($override -gt 0) { return $override }
    return [int]$numDirectWebRtcSignalingPort.Value
}

function Get-LetsEncryptSplitAudioProxyPort {
    $override = [int]$numLetsEncryptSplitAudioExternalPort.Value
    if ($override -gt 0) { return $override }
    return [int](Get-DirectWebRtcSplitAudioSignalingPort)
}

function Get-LetsEncryptWebServerProxyPort {
    param([int]$InternalPort)
    $override = [int]$numLetsEncryptWebServerExternalPort.Value
    if ($override -gt 0) { return $override }
    return $InternalPort
}

function Start-LetsEncryptTlsProxies {
    if (-not (Test-LetsEncryptTlsActive)) { return }

    $certificate = Get-LetsEncryptTlsCertificate
    if (-not $certificate) { return }

    $authenticationEnabled = Test-ViewerAuthenticationEnabled
    $authenticationSessionKey = $null
    if ($authenticationEnabled) {
        if (-not [TlsTerminatingProxy]::IsAuthenticationPasswordHashValid([string]$script:ViewerAuthenticationPasswordHash)) {
            throw 'Viewer authentication is enabled but its password hash is missing or invalid.'
        }
        $authenticationSessionKey = [TlsTerminatingProxy]::CreateAuthenticationSessionKey()
    }
    $viewerMountSegment = [string](Get-DirectWebRtcWebServerPathSegment)
    $authenticationMountPath = if ([string]::IsNullOrWhiteSpace($viewerMountSegment)) { '' } else { "/$($viewerMountSegment.Trim('/'))" }

    $configurationSignature = @(
        [string]$certificate.Thumbprint,
        [string]$authenticationEnabled,
        [string]$authenticationMountPath,
        [string]$txtViewerAuthenticationUsername.Text,
        [string]$script:ViewerAuthenticationPasswordHash,
        [string]$numViewerAuthenticationSessionHours.Value,
        [string]$numDirectWebRtcSignalingPort.Value,
        [string](Get-DirectWebRtcSplitAudioSignalingPort),
        [string]$numLetsEncryptSignalingExternalPort.Value,
        [string]$numLetsEncryptSplitAudioExternalPort.Value,
        [string]$numLetsEncryptWebServerExternalPort.Value,
        [string]$txtPlayerVideoSignalingProxyPath.Text,
        [string]$txtPlayerAudioSignalingProxyPath.Text
    ) -join '|'
    if (@($script:LetsEncryptTlsProxies).Count -gt 0) {
        if ($script:LetsEncryptTlsProxyConfigurationSignature -eq $configurationSignature) { return }
        Append-Log 'ACME: TLS/authentication configuration changed; restarting the local TLS proxies and invalidating viewer sessions.'
        Stop-LetsEncryptTlsProxies
    }

    $ports = @()
    $videoInternalPort = [int]$numDirectWebRtcSignalingPort.Value
    $videoExternalPort = Get-LetsEncryptSignalingProxyPort
    $ports += [pscustomobject]@{ Label = 'video signalling'; ExternalPort = $videoExternalPort; InternalPort = $videoInternalPort; PathRoutes = @() }

    $splitAudioActive = (Test-DirectWebRtcSplitAvPipelines) -and -not (Test-DirectWebRtcUnifiedPublisher) -and -not (Test-DirectWebRtcSharedSignaling)
    $audioInternalPort = 0
    if ($splitAudioActive) {
        $audioInternalPort = [int](Get-DirectWebRtcSplitAudioSignalingPort)
        $audioExternalPort = Get-LetsEncryptSplitAudioProxyPort
        $ports += [pscustomobject]@{ Label = 'split-audio signalling'; ExternalPort = $audioExternalPort; InternalPort = $audioInternalPort; PathRoutes = @() }
    }

    try {
        $webUri = [System.Uri](Get-DirectWebRtcWebServerBindAddress -Destination $txtDestination.Text)
        $webInternalPort = $webUri.Port
        $webExternalPort = Get-LetsEncryptWebServerProxyPort -InternalPort $webInternalPort
        if ($webInternalPort -gt 0 -and -not (@($ports) | Where-Object { $_.ExternalPort -eq $webExternalPort })) {
            # The "proxy" signaling candidate in player.js requests these paths
            # on the page's own origin (same host:port as the web viewer),
            # expecting a smart reverse proxy in front to route them to the
            # actual signaling server(s) -- see tools/examples/IIS/live/web.config
            # for the pattern this mirrors. Reuse the same Video/Voice path
            # fields that already drive that client-side URL (Player tab,
            # $txtPlayerVideoSignalingProxyPath/$txtPlayerAudioSignalingProxyPath)
            # so there is exactly one place these paths are configured.
            $webPathRoutes = @([pscustomobject]@{ Path = [string]$txtPlayerVideoSignalingProxyPath.Text; Port = $videoInternalPort })
            if ($splitAudioActive) {
                $webPathRoutes += [pscustomobject]@{ Path = [string]$txtPlayerAudioSignalingProxyPath.Text; Port = $audioInternalPort }
            }
            # webrtcsink resolves the served page's own relative asset URLs
            # against the browser's current directory, which only works once
            # the address bar ends in "/" -- redirect a bare "/live" (no
            # trailing slash) to "/live/" rather than leaving that to whatever
            # (if anything) sits in front of Glass.
            $webDirectorySegment = [string](Get-DirectWebRtcWebServerPathSegment)
            $webDirectoryRedirectPath = if ([string]::IsNullOrWhiteSpace($webDirectorySegment)) { '' } else { "/$webDirectorySegment" }
            $ports += [pscustomobject]@{ Label = 'web viewer'; ExternalPort = $webExternalPort; InternalPort = $webInternalPort; PathRoutes = $webPathRoutes; DirectoryRedirectPath = $webDirectoryRedirectPath }
        }
    }
    catch {
        Append-Log "ACME: could not determine the web viewer port for TLS termination: $($_.Exception.Message)"
    }

    $started = @()
    foreach ($portInfo in $ports) {
        try {
            $proxy = New-Object TlsTerminatingProxy
            $proxy.Label = [string]$portInfo.Label
            $proxy.AuthenticationMountPath = $authenticationMountPath
            foreach ($route in @($portInfo.PathRoutes)) {
                $proxy.AddPathRoute([string]$route.Path, [int]$route.Port)
            }
            if (-not [string]::IsNullOrEmpty([string]$portInfo.DirectoryRedirectPath)) {
                $proxy.DirectoryRedirectPath = [string]$portInfo.DirectoryRedirectPath
            }
            if ($authenticationEnabled) {
                $proxy.ConfigureAuthentication(
                    $true,
                    [string]$txtViewerAuthenticationUsername.Text,
                    [string]$script:ViewerAuthenticationPasswordHash,
                    $authenticationSessionKey,
                    [int]$numViewerAuthenticationSessionHours.Value
                )
            }
            $proxy.Start($portInfo.ExternalPort, '127.0.0.1', $portInfo.InternalPort, $certificate)
            $started += $proxy
            Append-Log "ACME: TLS termination active for $($portInfo.Label): 0.0.0.0:$($portInfo.ExternalPort) -> 127.0.0.1:$($portInfo.InternalPort)."
        }
        catch {
            Append-Log "ACME: could not start TLS termination for $($portInfo.Label) on port $($portInfo.ExternalPort): $($_.Exception.Message)"
        }
    }
    $script:LetsEncryptTlsProxies = $started
    $script:LetsEncryptTlsProxyConfigurationSignature = if (@($started).Count -gt 0) { $configurationSignature } else { '' }
    if ($authenticationEnabled -and @($started).Count -gt 0) {
        Append-Log "AUTH: viewer login required on all TLS viewer/signaling endpoints; sessions expire after $([int]$numViewerAuthenticationSessionHours.Value) hour(s)."
    }
}

# Called from the UI poll timer (90-MainWindow.ps1), same cadence as the
# GstControlledScenePreview/GstWebRtcConsumerPortRange terminal-message
# poll -- proxies queue errors from ThreadPool threads that have no
# PowerShell runspace, so draining must happen from the UI thread.
function Drain-LetsEncryptTlsProxyLogs {
    foreach ($proxy in $script:LetsEncryptTlsProxies) {
        while ($true) {
            $message = $proxy.PollLogMessage()
            if (-not $message) { break }
            Append-Log "ACME: TLS proxy ($($proxy.Label)): $message"
        }
    }
}

function Stop-LetsEncryptTlsProxies {
    if (@($script:LetsEncryptTlsProxies).Count -eq 0) { return }
    foreach ($proxy in $script:LetsEncryptTlsProxies) {
        try { $proxy.Stop() } catch {}
    }
    $script:LetsEncryptTlsProxies = @()
    $script:LetsEncryptTlsProxyConfigurationSignature = ''
}
