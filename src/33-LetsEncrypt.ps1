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
# The exact session-signing key currently live on $script:LetsEncryptTlsProxies
# -- retained so Sync-ViewerAuthenticationAccountsToLiveProxies can push an
# updated account list into already-running proxies via ConfigureAuthentication
# without generating a new key (which would silently log out every viewer,
# not just whichever account actually changed). Empty whenever those
# proxies aren't running authentication.
$script:LetsEncryptAuthenticationSessionKey = $null

# Plaintext-mode (certificate = null) TlsTerminatingProxy instances for
# "Allow plaintext auth" -- see Start-PlaintextAuthProxies. Kept separate
# from $script:LetsEncryptTlsProxies since these can run independently of
# embedded TLS (or alongside it, for the plain ports it deliberately
# leaves open).
$script:PlaintextAuthProxies = @()
$script:PlaintextAuthProxyConfigurationSignature = ''
$script:PlaintextAuthenticationSessionKey = $null

function ConvertTo-AcmeBase64Url {
    param([byte[]]$Bytes)
    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

# Hand-rolled PEM/DER RSA private key parsing, for a user-supplied custom
# certificate's private key file (SSL/TLS Security section). Written by
# hand rather than using RSA.ImportRSAPrivateKey/ImportPkcs8PrivateKey --
# those are .NET Core 3.0+/.NET 5+ only and do not exist on .NET Framework
# 4.8, which this app can run hosted under (Windows PowerShell 5.1). Same
# reasoning as CopyWithPrivateKey above. Verified against real
# openssl-generated PKCS#1 and PKCS#8 keys, including a full sign/verify
# round-trip against a paired certificate, under both runtimes.
function ConvertFrom-PemBody {
    param([Parameter(Mandatory)][string]$PemText, [Parameter(Mandatory)][string]$Label)
    $pattern = "-----BEGIN $Label-----(.*?)-----END $Label-----"
    $m = [regex]::Match($PemText, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $m.Success) { return $null }
    $base64 = ($m.Groups[1].Value -replace '\s', '')
    return [Convert]::FromBase64String($base64)
}

# Minimal definite-length DER TLV reader -- sufficient for the SEQUENCE/
# INTEGER/OCTET STRING structures a PKCS#1/PKCS#8 RSA private key uses.
# Indefinite-length DER (BER) is not handled; standard key export tooling
# (openssl, etc.) always emits definite lengths for these structures.
function Read-DerTlv {
    param([byte[]]$Bytes, [int]$Offset)
    $tag = $Bytes[$Offset]
    $lengthByte = $Bytes[$Offset + 1]
    $lengthStart = $Offset + 2
    $length = 0
    if ($lengthByte -lt 0x80) {
        $length = $lengthByte
    }
    else {
        $numLengthBytes = $lengthByte -band 0x7F
        for ($i = 0; $i -lt $numLengthBytes; $i++) { $length = ($length -shl 8) -bor $Bytes[$lengthStart + $i] }
        $lengthStart += $numLengthBytes
    }
    $content = New-Object byte[] $length
    [Array]::Copy($Bytes, $lengthStart, $content, 0, $length)
    return [pscustomobject]@{ Tag = $tag; Content = $content; NextOffset = ($lengthStart + $length) }
}

# DER INTEGER content carries a leading 0x00 sign-padding byte whenever the
# true value's high bit would otherwise read as negative -- RSAParameters
# wants the raw unsigned magnitude, so strip exactly one leading zero byte
# when present (and more bytes remain).
function ConvertFrom-DerInteger {
    param([byte[]]$Content)
    if ($Content.Length -gt 1 -and $Content[0] -eq 0) { return $Content[1..($Content.Length - 1)] }
    return $Content
}

# PKCS#1 RSAPrivateKey ::= SEQUENCE { version, n, e, d, p, q, dp, dq, qInv }
function ConvertFrom-Pkcs1RsaPrivateKeyDer {
    param([byte[]]$Der)
    $outer = Read-DerTlv -Bytes $Der -Offset 0
    if ($outer.Tag -ne 0x30) { throw 'Expected a SEQUENCE at the start of the PKCS#1 RSA private key.' }
    $sequence = $outer.Content
    $offset = 0
    $fields = @()
    for ($i = 0; $i -lt 9; $i++) {
        $tlv = Read-DerTlv -Bytes $sequence -Offset $offset
        $fields += , (ConvertFrom-DerInteger $tlv.Content)
        $offset = $tlv.NextOffset
    }
    $rsaParameters = New-Object System.Security.Cryptography.RSAParameters
    $rsaParameters.Modulus = $fields[1]
    $rsaParameters.Exponent = $fields[2]
    $rsaParameters.D = $fields[3]
    $rsaParameters.P = $fields[4]
    $rsaParameters.Q = $fields[5]
    $rsaParameters.DP = $fields[6]
    $rsaParameters.DQ = $fields[7]
    $rsaParameters.InverseQ = $fields[8]
    return $rsaParameters
}

# PKCS#8 PrivateKeyInfo ::= SEQUENCE { version, AlgorithmIdentifier, OCTET STRING (the PKCS#1 key) }
function ConvertFrom-Pkcs8PrivateKeyInfoDer {
    param([byte[]]$Der)
    $outer = Read-DerTlv -Bytes $Der -Offset 0
    if ($outer.Tag -ne 0x30) { throw 'Expected a SEQUENCE at the start of the PKCS#8 PrivateKeyInfo.' }
    $sequence = $outer.Content
    $offset = 0
    $versionTlv = Read-DerTlv -Bytes $sequence -Offset $offset
    $offset = $versionTlv.NextOffset
    $algorithmIdTlv = Read-DerTlv -Bytes $sequence -Offset $offset
    $offset = $algorithmIdTlv.NextOffset
    $keyOctetTlv = Read-DerTlv -Bytes $sequence -Offset $offset
    if ($keyOctetTlv.Tag -ne 0x04) { throw 'Expected an OCTET STRING containing the PKCS#1 key.' }
    return ConvertFrom-Pkcs1RsaPrivateKeyDer -Der $keyOctetTlv.Content
}

# Loads a user-supplied RSA private key file (PEM, PKCS#1 "RSA PRIVATE KEY"
# or PKCS#8 "PRIVATE KEY"). Encrypted private keys ("ENCRYPTED PRIVATE
# KEY", or the legacy "Proc-Type: 4,ENCRYPTED" header) are not supported --
# there's no password field for this, by design; supply a decrypted key or
# use the Let's Encrypt-managed certificate instead. Returns an RSA key
# object matching whatever this runtime's private-key-attachment path
# expects (see Test-LetsEncryptModernKeyAttachment / New-LetsEncryptCertificateKey).
function Import-TlsPrivateKeyFile {
    param([Parameter(Mandatory)][string]$Path)
    $pemText = Get-Content -LiteralPath $Path -Raw
    if ($pemText -match 'ENCRYPTED PRIVATE KEY' -or $pemText -match 'Proc-Type:\s*4,ENCRYPTED') {
        throw 'This private key file is password-encrypted. Supply a decrypted PEM private key.'
    }

    $rsaParameters = $null
    $pkcs1Der = ConvertFrom-PemBody -PemText $pemText -Label 'RSA PRIVATE KEY'
    if ($pkcs1Der) {
        $rsaParameters = ConvertFrom-Pkcs1RsaPrivateKeyDer -Der $pkcs1Der
    }
    else {
        $pkcs8Der = ConvertFrom-PemBody -PemText $pemText -Label 'PRIVATE KEY'
        if (-not $pkcs8Der) { throw 'Not a recognized PEM RSA private key (expected "RSA PRIVATE KEY" or "PRIVATE KEY").' }
        $rsaParameters = ConvertFrom-Pkcs8PrivateKeyInfoDer -Der $pkcs8Der
    }

    if (Test-LetsEncryptModernKeyAttachment) {
        $rsa = [System.Security.Cryptography.RSA]::Create()
        $rsa.ImportParameters($rsaParameters)
        return $rsa
    }
    $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
    $rsa.ImportParameters($rsaParameters)
    return $rsa
}

# Defaults to a Certificates folder under AppData, but overridable from the
# SSL/TLS Security section so issued certs/keys can live somewhere the user
# chooses (e.g. alongside other cert material they already manage).
function Get-LetsEncryptCertificateDirectory {
    $override = if ($txtLetsEncryptCertificateDirectory) { [string]$txtLetsEncryptCertificateDirectory.Text.Trim() } else { '' }
    $dir = if ([string]::IsNullOrWhiteSpace($override)) { Join-Path $script:ConfigDirectory 'Certificates' } else { $override }
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

# Which certificate file "Use embedded TLS" would actually present right
# now, before any of it is loaded: a custom cert path if the broadcaster
# set one in SSL/TLS Security (overridable, per that section's design),
# otherwise whatever Let's Encrypt has issued to disk for the current DDNS
# hostname. Returns $null if neither source has a usable file yet. Kept
# cheap (Test-Path only, no X509Certificate2 loading) since Test-EmbeddedTlsActive
# calls this on every gating check throughout the pipeline/proxy/UPnP code.
function Resolve-EmbeddedTlsCertificatePath {
    $customCertPath = if ($txtTlsCertificatePath) { [string]$txtTlsCertificatePath.Text.Trim() } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($customCertPath)) {
        if (Test-Path -LiteralPath $customCertPath) { return $customCertPath }
        return $null
    }
    if (-not ($chkLetsEncryptEnabled -and $chkLetsEncryptEnabled.Checked)) { return $null }
    $hostname = [string]$txtDdnsHostname.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($hostname)) { return $null }
    $state = Get-LetsEncryptCertificateState
    if ($state -and [string]$state.Hostname -eq $hostname -and (Test-Path -LiteralPath ([string]$state.PfxPath))) { return [string]$state.PfxPath }
    return $null
}

# Whether embedded TLS termination should actually be active right now:
# the "Use embedded TLS" master switch is on, and a certificate is
# resolvable (custom cert/key path, or a Let's Encrypt-issued certificate
# on disk -- see Resolve-EmbeddedTlsCertificatePath). This is the single
# source of truth src/17-DirectWebRtcPipeline.ps1, src/27-StreamLifecycle.ps1,
# and src/31-UpnpPortForwarding.ps1 all check, so "is TLS on" can never
# disagree between the pipeline, the proxy lifecycle, and the UPnP mapping.
# Deliberately independent of the Let's Encrypt checkbox: that checkbox
# only controls whether a certificate gets *issued*, not whether the
# embedded TLS proxies run -- a custom cert/key pair works with Let's
# Encrypt turned off entirely.
function Test-EmbeddedTlsActive {
    if (-not ($chkEmbeddedTlsEnabled -and $chkEmbeddedTlsEnabled.Checked)) { return $false }
    return [bool](Resolve-EmbeddedTlsCertificatePath)
}

# Whether the plain-HTTP/WS listeners (webrtcsink's own web/signalling
# servers) should be restricted to loopback-only right now. Has no effect
# at all -- always returns false -- when none of embedded TLS, TLS-enforced
# viewer auth, or plaintext auth are active: with nothing else fronting
# them, the plain servers just listen on whatever the UI configures
# (0.0.0.0 by default, or a specific address) regardless of this checkbox.
# When one of those IS active:
#  - Plaintext auth (Test-PlaintextAuthActive) always forces loopback,
#    unconditionally -- structurally required, not a preference: its
#    auth-gating relay transparently takes over the exact same port number
#    webrtcsink would otherwise use (Start-PlaintextAuthProxies), and two
#    listeners can't both bind 0.0.0.0 on that same port.
#  - Embedded TLS / TLS-enforced viewer auth only forces loopback when
#    "Allow insecure listeners" is UNCHECKED. Checking it lets the plain
#    servers keep listening on 0.0.0.0 (or whatever's configured) even
#    while the TLS proxy also runs, e.g. because the broadcaster still
#    wants that plain path reachable/proxied some other way -- the TLS
#    proxy's own external port just needs to differ from the internal one
#    in that case (see Get-EmbeddedTlsPortConflicts), since a
#    0.0.0.0-bound proxy and a 127.0.0.1-bound internal server coexist
#    fine on the same port number, but two 0.0.0.0 binds do not.
function Test-EmbeddedTlsInsecurePortsRestricted {
    if (Test-PlaintextAuthActive) { return $true }
    if (-not (Test-EmbeddedTlsActive)) { return $false }
    return -not [bool]($chkTlsAllowInsecurePorts -and $chkTlsAllowInsecurePorts.Checked)
}

# Loads the certificate (with its private key) for TlsTerminatingProxy
# instances to present -- either the broadcaster's custom cert/key files,
# or the Let's Encrypt-issued PFX, per Resolve-EmbeddedTlsCertificatePath.
# Returns $null rather than throwing if TLS isn't active or the file can't
# be loaded -- every caller treats a missing certificate as "skip starting
# the proxy," best-effort like every other UPnP/DDNS/ACME integration point.
function Get-EmbeddedTlsCertificate {
    $certPath = Resolve-EmbeddedTlsCertificatePath
    if (-not $certPath) { return $null }
    $customCertPath = if ($txtTlsCertificatePath) { [string]$txtTlsCertificatePath.Text.Trim() } else { '' }
    $isCustomCertificate = -not [string]::IsNullOrWhiteSpace($customCertPath)
    try {
        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certPath)
        if (-not $isCustomCertificate) { return $certificate }

        $keyPath = if ($txtTlsPrivateKeyPath) { [string]$txtTlsPrivateKeyPath.Text.Trim() } else { '' }
        if ([string]::IsNullOrWhiteSpace($keyPath)) { return $certificate }
        if (-not (Test-Path -LiteralPath $keyPath)) {
            Append-Log "TLS: private key path '$keyPath' does not exist; using '$certPath' as-is."
            return $certificate
        }
        $privateKey = Import-TlsPrivateKeyFile -Path $keyPath
        return Set-LetsEncryptCertificatePrivateKey -Certificate $certificate -PrivateKey $privateKey
    }
    catch {
        Append-Log "TLS: could not load certificate from '$certPath': $($_.Exception.Message)"
        return $null
    }
}

# Top-level orchestrator, same shape as Update-DdnsRecord: gated on the
# enable checkbox, best-effort, skips work when the current cert is still
# valid and not near expiry (unless -Force, used by the "Force Renew"
# button -- staging or production, whichever the checkbox has selected, so
# repeated manual testing can still go through staging on demand).
function Update-LetsEncryptCertificate {
    param([switch]$Force)
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

    if (-not $Force -and -not (Test-LetsEncryptCertificateNeedsRenewal -Hostname $hostname)) {
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

# Deletes the on-disk issued certificate (and its state record) for the
# current DDNS hostname, after warning about Let's Encrypt's production
# rate limits (5 duplicate certs/week for the same hostname) -- deleting
# the local file doesn't reset anything server-side, so a broadcaster who
# deletes and immediately re-issues against production repeatedly can
# still burn into that limit. Staging has no such limit and remains
# available for repeated testing regardless of this warning.
function Remove-LetsEncryptCertificate {
    $state = Get-LetsEncryptCertificateState
    if (-not $state -or -not (Test-Path -LiteralPath ([string]$state.PfxPath))) {
        [System.Windows.Forms.MessageBox]::Show("There is no certificate on file to delete.", $script:AppName, 'OK', 'Information') | Out-Null
        return
    }

    $staging = [bool]($chkLetsEncryptStaging -and $chkLetsEncryptStaging.Checked)
    $rateLimitNote = if ($staging) {
        "The current environment is staging, which has no meaningful rate limit -- safe to delete and re-issue as often as needed."
    }
    else {
        "The current environment is production. Let's Encrypt limits duplicate certificates for the same hostname to 5 per week -- deleting this file does not reset that count server-side. If you plan to re-issue repeatedly, switch to staging first."
    }
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Delete the certificate on file for '$($state.Hostname)'?`n`n$rateLimitNote",
        $script:AppName,
        'YesNo',
        'Warning'
    )
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    try { Remove-Item -LiteralPath ([string]$state.PfxPath) -Force -ErrorAction SilentlyContinue } catch {}
    try { Remove-Item -LiteralPath (Get-LetsEncryptCertificateStatePath) -Force -ErrorAction SilentlyContinue } catch {}
    Append-Log "ACME: deleted the certificate on file for '$($state.Hostname)'."
    Update-LetsEncryptUi
}

# Master/detail UI toggling, same pattern as Update-DdnsUi. Also refreshes
# the status label from on-disk certificate state -- safe to do unconditionally
# here since this is only ever called from startup/checkbox/provider-change
# events, never concurrently with an in-progress issuance's own status updates.
# Only the ACME-specific controls live here now -- the master "Use embedded
# TLS" switch, cert/key path overrides, port fields, and insecure-port
# lockdown are their own SSL/TLS Security section, see Update-EmbeddedTlsUi.
function Update-LetsEncryptUi {
    $enabled = [bool]($chkLetsEncryptEnabled -and $chkLetsEncryptEnabled.Checked)
    foreach ($control in @($txtLetsEncryptEmail, $chkLetsEncryptStaging, $txtLetsEncryptCertificateDirectory, $btnBrowseLetsEncryptCertificateDirectory, $btnLetsEncryptIssueNow, $btnLetsEncryptForceRenew, $btnLetsEncryptDeleteCertificate)) {
        if ($control) { $control.Enabled = $enabled }
    }
    Update-EmbeddedTlsUi
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

# Master/detail UI toggling for the SSL/TLS Security section -- the "Use
# embedded TLS" master switch gates the custom cert/key path overrides and
# the three proxy port fields, independent of whether Let's Encrypt is
# also enabled. "Allow insecure listeners" is deliberately NOT gated here
# (see below) -- it also matters for "Allow plaintext auth", which is
# independent of embedded TLS. Also surfaces whether a certificate
# actually resolves right now, so a broadcaster who checked the box
# without pointing it at a real cert/key or turning on Let's Encrypt sees
# why nothing started, rather than a silent no-op.
function Update-EmbeddedTlsUi {
    $enabled = [bool]($chkEmbeddedTlsEnabled -and $chkEmbeddedTlsEnabled.Checked)
    foreach ($control in @(
        $txtTlsCertificatePath, $btnBrowseTlsCertificatePath, $txtTlsPrivateKeyPath, $btnBrowseTlsPrivateKeyPath,
        $numLetsEncryptSignalingExternalPort, $numLetsEncryptSplitAudioExternalPort, $numLetsEncryptWebServerExternalPort
    )) {
        if ($control) { $control.Enabled = $enabled }
    }
    # Not gated by "Use embedded TLS" -- this also matters for "Allow
    # plaintext auth" (Test-PlaintextAuthActive), which is independent of
    # embedded TLS being on, so it must stay interactive even while
    # embedded TLS is off.
    if ($chkTlsAllowInsecurePorts) { $chkTlsAllowInsecurePorts.Enabled = $true }

    if (-not $lblEmbeddedTlsStatus) { return }
    if (-not $enabled) {
        $lblEmbeddedTlsStatus.Text = 'Embedded TLS: disabled'
        $lblEmbeddedTlsStatus.ForeColor = [System.Drawing.Color]::DimGray
        return
    }

    $certPath = Resolve-EmbeddedTlsCertificatePath
    if ($certPath) {
        $lblEmbeddedTlsStatus.Text = "Embedded TLS: active, presenting $certPath"
        $lblEmbeddedTlsStatus.ForeColor = [System.Drawing.Color]::DarkGreen
    }
    else {
        $lblEmbeddedTlsStatus.Text = 'Embedded TLS: enabled, but no certificate found -- set a custom cert/key path or enable Let''s Encrypt below'
        $lblEmbeddedTlsStatus.ForeColor = [System.Drawing.Color]::DarkOrange
    }
}

function Test-ViewerAuthenticationEnabled {
    return [bool]($chkViewerAuthenticationEnabled -and $chkViewerAuthenticationEnabled.Checked)
}

# Whether viewer login should be enforced directly on the plain HTTP/WS
# ports (video signalling, split-audio signalling, web viewer) via a
# plaintext-mode TlsTerminatingProxy (certificate = null -- see
# Start-PlaintextAuthProxies). Off by default: the session cookie travels
# in cleartext on this path, so this is only meant for setups where
# something else already terminates TLS in front of Glass, or the
# broadcaster has otherwise accepted that risk.
function Test-PlaintextAuthActive {
    return [bool]($chkViewerAuthenticationAllowPlaintext -and $chkViewerAuthenticationAllowPlaintext.Checked -and (Test-ViewerAuthenticationEnabled))
}

# Whether the embedded-TLS/plaintext-auth proxies should stay running
# across a stream Start/Stop/Restart cycle, instead of being torn down and
# rebuilt with a fresh session-signing key each time (which logs every
# viewer out, forcing a fresh login the next time the stream comes back
# up). Checked at every Stop-GstStream call site that would otherwise
# call Stop-LetsEncryptTlsProxies/Stop-PlaintextAuthProxies
# (27-StreamLifecycle.ps1). Only meaningful while "Require viewer login"
# is also checked -- without it there's no session to preserve.
function Test-KeepAuthenticationProxiesOnRestart {
    return [bool]($chkViewerAuthenticationKeepOnRestart -and $chkViewerAuthenticationKeepOnRestart.Checked -and (Test-ViewerAuthenticationEnabled))
}

function Update-ViewerAuthenticationUi {
    # The "Require viewer login" checkbox itself is never grayed out by TLS
    # state -- a broadcaster can check it and set up accounts at any time.
    # It only actually takes effect once something enforces it (embedded
    # TLS, or plaintext auth being allowed); otherwise it's simply
    # disregarded (see Validate-Configuration in 24-Settings.ps1).
    $authenticationEnabled = Test-ViewerAuthenticationEnabled
    foreach ($control in @(
        $lstViewerAuthenticationAccounts, $txtViewerAuthenticationNewUsername, $txtViewerAuthenticationNewPassword,
        $btnViewerAuthenticationAddAccount, $btnViewerAuthenticationRemoveAccount,
        $btnViewerAuthenticationEnableTotp, $btnViewerAuthenticationDisableTotp,
        $numViewerAuthenticationSessionHours, $chkViewerAuthenticationAllowPlaintext,
        $chkViewerAuthenticationKeepOnRestart
    )) {
        if ($control) { $control.Enabled = $authenticationEnabled }
    }
}

# Each named account can log in independently -- see AuthenticationAccount /
# ConfigureAuthentication in the TlsTerminatingProxy C# class. Only the
# salted PBKDF2-HMAC-SHA256 hash is ever kept; the plaintext password field
# is cleared immediately after hashing.
function Sync-ViewerAuthenticationAccountsListBox {
    if (-not $lstViewerAuthenticationAccounts) { return }
    $selectedUsername = Get-SelectedViewerAuthenticationUsername
    $lstViewerAuthenticationAccounts.BeginUpdate()
    try {
        $lstViewerAuthenticationAccounts.Items.Clear()
        $selectedLabel = $null
        foreach ($account in @($script:ViewerAuthenticationAccounts)) {
            $label = Get-ViewerAuthenticationAccountLabel $account
            [void]$lstViewerAuthenticationAccounts.Items.Add($label)
            if ($selectedUsername -and [string]$account.Username -eq $selectedUsername) { $selectedLabel = $label }
        }
        if ($selectedLabel) { $lstViewerAuthenticationAccounts.SelectedItem = $selectedLabel }
    }
    finally {
        $lstViewerAuthenticationAccounts.EndUpdate()
    }
}

# The list box shows "username (2FA)" for accounts with a TOTP secret so
# the broadcaster can see enrollment status at a glance -- these two
# helpers keep that display label and the underlying raw username in sync
# in exactly one place, since every handler below needs the raw username.
function Get-ViewerAuthenticationAccountLabel {
    param($Account)
    $label = [string]$Account.Username
    if (-not [string]::IsNullOrWhiteSpace([string]$Account.TotpSecret)) { $label += ' (2FA)' }
    return $label
}

function Get-SelectedViewerAuthenticationUsername {
    $selected = [string]$lstViewerAuthenticationAccounts.SelectedItem
    if ([string]::IsNullOrWhiteSpace($selected)) { return $null }
    return ($selected -replace '\s*\(2FA\)$', '')
}

function Add-ViewerAuthenticationAccount {
    $username = [string]$txtViewerAuthenticationNewUsername.Text.Trim()
    $password = [string]$txtViewerAuthenticationNewPassword.Text
    if ([string]::IsNullOrWhiteSpace($username) -or $username.Length -gt 64 -or $username -match '[\r\n]') {
        [System.Windows.Forms.MessageBox]::Show('Enter a username between 1 and 64 characters with no line breaks.', $script:AppName, 'OK', 'Warning') | Out-Null
        return
    }
    if ($password.Length -lt 10 -or $password.Length -gt 256) {
        [System.Windows.Forms.MessageBox]::Show('Password must be between 10 and 256 characters.', $script:AppName, 'OK', 'Warning') | Out-Null
        return
    }
    $passwordHash = [TlsTerminatingProxy]::HashAuthenticationPassword($password)
    $existing = @($script:ViewerAuthenticationAccounts) | Where-Object { $_.Username -eq $username }
    if ($existing) {
        # A password change never touches an existing 2FA enrollment --
        # TotpSecret is simply not part of this update.
        $existing[0].PasswordHash = $passwordHash
        Append-Log "AUTH: updated the password for viewer account '$username'."
    }
    else {
        $script:ViewerAuthenticationAccounts = @(@($script:ViewerAuthenticationAccounts) + [pscustomobject]@{ Username = $username; PasswordHash = $passwordHash; TotpSecret = '' })
        Append-Log "AUTH: added viewer account '$username'."
    }
    $txtViewerAuthenticationNewUsername.Clear()
    $txtViewerAuthenticationNewPassword.Clear()
    Sync-ViewerAuthenticationAccountsListBox
    Sync-ViewerAuthenticationAccountsToLiveProxies
    Save-Settings
}

function Remove-ViewerAuthenticationAccount {
    $selected = Get-SelectedViewerAuthenticationUsername
    if ([string]::IsNullOrWhiteSpace($selected)) { return }
    $script:ViewerAuthenticationAccounts = @(@($script:ViewerAuthenticationAccounts) | Where-Object { $_.Username -ne $selected })
    Sync-ViewerAuthenticationAccountsToLiveProxies
    Append-Log "AUTH: removed viewer account '$selected'; its active sessions are now revoked."
    Sync-ViewerAuthenticationAccountsListBox
    Save-Settings
}

# Generates a fresh secret and requires the broadcaster to enter the CURRENT
# code from their authenticator app before it's actually saved -- confirming
# the app scanned/entered it correctly, so enabling 2FA can never lock the
# account out from a typo or a misconfigured app.
function Enable-ViewerAuthenticationTotp {
    $selected = Get-SelectedViewerAuthenticationUsername
    if ([string]::IsNullOrWhiteSpace($selected)) {
        [System.Windows.Forms.MessageBox]::Show('Select an account first.', $script:AppName, 'OK', 'Warning') | Out-Null
        return
    }
    $account = @($script:ViewerAuthenticationAccounts) | Where-Object { $_.Username -eq $selected } | Select-Object -First 1
    if (-not $account) { return }

    $secret = [TlsTerminatingProxy]::GenerateTotpSecret()
    $issuer = 'GStreamer Glass'
    $otpauthUri = "otpauth://totp/$([System.Uri]::EscapeDataString($issuer)):$([System.Uri]::EscapeDataString($selected))?secret=$secret&issuer=$([System.Uri]::EscapeDataString($issuer))"
    [System.Windows.Forms.MessageBox]::Show(
        "Add this to an authenticator app (Google Authenticator, Authy, 1Password, etc.) for '$selected':`n`nSecret key (manual entry): $secret`n`nOr paste this URI if your app supports it:`n$otpauthUri`n`nAfter adding it, click OK and enter the 6-digit code it shows to confirm.",
        $script:AppName,
        'OK',
        'Information'
    ) | Out-Null

    Add-Type -AssemblyName Microsoft.VisualBasic
    $confirmCode = [Microsoft.VisualBasic.Interaction]::InputBox("Enter the current 6-digit code for '$selected' to confirm 2FA setup:", 'Confirm 2FA Setup', '')
    if ([string]::IsNullOrWhiteSpace($confirmCode)) {
        Append-Log "AUTH: 2FA setup for '$selected' was cancelled before confirmation; not enabled."
        return
    }
    if (-not [TlsTerminatingProxy]::VerifyTotpCode($secret, $confirmCode.Trim())) {
        [System.Windows.Forms.MessageBox]::Show("That code did not match. 2FA was not enabled for '$selected' -- try again.", $script:AppName, 'OK', 'Warning') | Out-Null
        return
    }

    $account.TotpSecret = $secret
    Append-Log "AUTH: 2FA enabled for viewer account '$selected'."
    Sync-ViewerAuthenticationAccountsListBox
    Sync-ViewerAuthenticationAccountsToLiveProxies
    Save-Settings
}

function Disable-ViewerAuthenticationTotp {
    $selected = Get-SelectedViewerAuthenticationUsername
    if ([string]::IsNullOrWhiteSpace($selected)) {
        [System.Windows.Forms.MessageBox]::Show('Select an account first.', $script:AppName, 'OK', 'Warning') | Out-Null
        return
    }
    $account = @($script:ViewerAuthenticationAccounts) | Where-Object { $_.Username -eq $selected } | Select-Object -First 1
    if (-not $account -or [string]::IsNullOrWhiteSpace([string]$account.TotpSecret)) { return }
    $account.TotpSecret = ''
    Append-Log "AUTH: 2FA disabled for viewer account '$selected'."
    Sync-ViewerAuthenticationAccountsListBox
    Sync-ViewerAuthenticationAccountsToLiveProxies
    Save-Settings
}

# Pre-flight check for Validate-Configuration (24-Settings.ps1). Only
# relevant when the plain servers are NOT restricted to loopback
# (Test-EmbeddedTlsInsecurePortsRestricted returns false -- i.e. "Allow
# insecure ports" is checked): webrtcsink's own server then stays on
# 0.0.0.0 (global) same as the TlsTerminatingProxy's external listener,
# and two 0.0.0.0 binds can never share one port number -- that's a
# guaranteed address-in-use failure, not a policy preference. When the
# plain servers ARE restricted to loopback, a 0.0.0.0 proxy + 127.0.0.1
# internal server coexist fine on the same port number (verified directly
# against real TcpListener binds), so no restriction applies there at
# all. Uses the exact same per-service port sources
# (Get-LetsEncryptSignalingProxyPort etc.) Start-LetsEncryptTlsProxies
# itself uses, so this can never disagree with what actually gets started.
function Get-EmbeddedTlsPortConflicts {
    if (Test-EmbeddedTlsInsecurePortsRestricted) { return @() }
    $conflicts = @()

    $videoInternalPort = [int]$numDirectWebRtcSignalingPort.Value
    if ((Get-LetsEncryptSignalingProxyPort) -eq $videoInternalPort) {
        $conflicts += "Video signalling: external TLS port must differ from the internal port ($videoInternalPort) while insecure ports stay on 0.0.0.0."
    }

    $splitAudioActive = (Test-DirectWebRtcSplitAvPipelines) -and -not (Test-DirectWebRtcUnifiedPublisher) -and -not (Test-DirectWebRtcSharedSignaling)
    if ($splitAudioActive) {
        $audioInternalPort = [int](Get-DirectWebRtcSplitAudioSignalingPort)
        if ((Get-LetsEncryptSplitAudioProxyPort) -eq $audioInternalPort) {
            $conflicts += "Split-audio signalling: external TLS port must differ from the internal port ($audioInternalPort) while insecure ports stay on 0.0.0.0."
        }
    }

    try {
        $webUri = [System.Uri](Get-DirectWebRtcWebServerBindAddress -Destination $txtDestination.Text)
        $webInternalPort = $webUri.Port
        if ($webInternalPort -gt 0 -and (Get-LetsEncryptWebServerProxyPort -InternalPort $webInternalPort) -eq $webInternalPort) {
            $conflicts += "Web viewer: external TLS port must differ from the internal port ($webInternalPort) while insecure ports stay on 0.0.0.0."
        }
    }
    catch {}

    return $conflicts
}

# Starts one TlsTerminatingProxy per port that needs external HTTPS/WSS
# exposure (video signalling, split-audio signalling when it runs its own
# server, web viewer), forwarding to webrtcsink's own servers -- loopback-only
# or still on 0.0.0.0 depending on "Disable insecure ports"
# (Get-DirectWebRtcSignalingServerBindHost/-WebServerBindAddress in
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

# Builds the [TlsTerminatingProxy+AuthenticationAccount[]] array a proxy's
# ConfigureAuthentication expects, from $script:ViewerAuthenticationAccounts
# -- shared by Start-LetsEncryptTlsProxies and Start-PlaintextAuthProxies so
# the two proxy families can never end up with divergent account data.
function Get-ViewerAuthenticationAccountObjects {
    param($Accounts)
    return [TlsTerminatingProxy+AuthenticationAccount[]]@(
        @($Accounts) | ForEach-Object {
            $account = [TlsTerminatingProxy+AuthenticationAccount]::new()
            $account.Username = [string]$_.Username
            $account.PasswordHash = [string]$_.PasswordHash
            $account.TotpSecret = [string]$_.TotpSecret
            $account
        }
    )
}

# Pushes the current $script:ViewerAuthenticationAccounts into any
# already-running proxies immediately, without a listener restart --
# ConfigureAuthentication just swaps the proxy's in-memory account list,
# and ValidateAuthenticationSessionToken re-checks every session against
# that CURRENT list on every request. So a removed account's sessions stop
# validating right away (FindAuthenticationAccount no longer finds it),
# while every other viewer's session stays untouched -- unlike restarting
# the proxies (which regenerates the session-signing key and would log
# everyone out). Reuses the session key each proxy family is already
# running with (see $script:LetsEncryptAuthenticationSessionKey /
# $script:PlaintextAuthenticationSessionKey) rather than generating a new
# one, for exactly that reason. A no-op wherever a proxy family isn't
# currently running authentication (nothing to push to yet -- the next
# Start-*Proxies call will pick up current accounts on its own).
function Sync-ViewerAuthenticationAccountsToLiveProxies {
    $validAccounts = @($script:ViewerAuthenticationAccounts) | Where-Object {
        $_.Username -and [TlsTerminatingProxy]::IsAuthenticationPasswordHashValid([string]$_.PasswordHash)
    }
    $accountObjects = Get-ViewerAuthenticationAccountObjects -Accounts $validAccounts
    $sessionHours = [int]$numViewerAuthenticationSessionHours.Value

    if ($script:LetsEncryptAuthenticationSessionKey -and @($script:LetsEncryptTlsProxies).Count -gt 0) {
        foreach ($proxy in $script:LetsEncryptTlsProxies) {
            try { $proxy.ConfigureAuthentication($true, $accountObjects, $script:LetsEncryptAuthenticationSessionKey, $sessionHours) } catch {}
        }
    }
    if ($script:PlaintextAuthenticationSessionKey -and @($script:PlaintextAuthProxies).Count -gt 0) {
        foreach ($proxy in $script:PlaintextAuthProxies) {
            try { $proxy.ConfigureAuthentication($true, $accountObjects, $script:PlaintextAuthenticationSessionKey, $sessionHours) } catch {}
        }
    }
}

function Start-LetsEncryptTlsProxies {
    if (-not (Test-EmbeddedTlsActive)) { return }

    $certificate = Get-EmbeddedTlsCertificate
    if (-not $certificate) { return }

    $authenticationEnabled = Test-ViewerAuthenticationEnabled
    $authenticationAccounts = @($script:ViewerAuthenticationAccounts) | Where-Object {
        $_.Username -and [TlsTerminatingProxy]::IsAuthenticationPasswordHashValid([string]$_.PasswordHash)
    }
    $authenticationSessionKey = $null
    if ($authenticationEnabled) {
        if (@($authenticationAccounts).Count -eq 0) {
            throw 'Viewer authentication is enabled but no account has a valid password hash.'
        }
        $authenticationSessionKey = [TlsTerminatingProxy]::CreateAuthenticationSessionKey()
    }
    $viewerMountSegment = [string](Get-DirectWebRtcWebServerPathSegment)
    $authenticationMountPath = if ([string]::IsNullOrWhiteSpace($viewerMountSegment)) { '' } else { "/$($viewerMountSegment.Trim('/'))" }

    # Account data is deliberately NOT part of this signature -- adding,
    # removing, or editing viewer accounts is handled live via
    # Sync-ViewerAuthenticationAccountsToLiveProxies (ConfigureAuthentication
    # on the already-running proxies, no restart), specifically so it never
    # regenerates the session-signing key and logs every other viewer out
    # just because one account changed.
    $configurationSignature = @(
        [string]$certificate.Thumbprint,
        [string]$authenticationEnabled,
        [string]$authenticationMountPath,
        [string]$numViewerAuthenticationSessionHours.Value,
        [string]$numDirectWebRtcSignalingPort.Value,
        [string](Get-DirectWebRtcSplitAudioSignalingPort),
        [string]$numLetsEncryptSignalingExternalPort.Value,
        [string]$numLetsEncryptSplitAudioExternalPort.Value,
        [string]$numLetsEncryptWebServerExternalPort.Value,
        [string]$txtPlayerVideoSignalingProxyPath.Text,
        [string]$txtPlayerAudioSignalingProxyPath.Text,
        [string]$txtTlsCertificatePath.Text,
        [string]$txtTlsPrivateKeyPath.Text,
        [string]((Test-EmbeddedTlsInsecurePortsRestricted))
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
                    (Get-ViewerAuthenticationAccountObjects -Accounts $authenticationAccounts),
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
    $script:LetsEncryptAuthenticationSessionKey = if (@($started).Count -gt 0 -and $authenticationEnabled) { $authenticationSessionKey } else { $null }
    if ($authenticationEnabled -and @($started).Count -gt 0) {
        Append-Log "AUTH: viewer login required on all TLS viewer/signaling endpoints; sessions expire after $([int]$numViewerAuthenticationSessionHours.Value) hour(s)."
    }
}

# "Allow plaintext auth" counterpart to Start-LetsEncryptTlsProxies: runs
# the exact same login/session/routing gate (TlsTerminatingProxy) directly
# on the plain HTTP/WS ports, with certificate = null so it never attempts
# a TLS handshake. Transparently takes over each service's normal port
# number (external == internal -- there's no separate override field for
# this, since the whole point is standing in for webrtcsink's own server
# on the port a client already expects), and correspondingly forces that
# service's real server to loopback-only via
# Get-DirectWebRtcSignalingServerBindHost/-WebServerBindAddress
# (Test-EmbeddedTlsInsecurePortsRestricted always returns true whenever
# Test-PlaintextAuthActive is true).
# Runs independently of embedded TLS -- either, both, or neither can be
# active depending on configuration.
function Start-PlaintextAuthProxies {
    if (-not (Test-PlaintextAuthActive)) { return }

    $authenticationAccounts = @($script:ViewerAuthenticationAccounts) | Where-Object {
        $_.Username -and [TlsTerminatingProxy]::IsAuthenticationPasswordHashValid([string]$_.PasswordHash)
    }
    if (@($authenticationAccounts).Count -eq 0) {
        throw 'Plaintext auth is enabled but no account has a valid password hash.'
    }
    $authenticationSessionKey = [TlsTerminatingProxy]::CreateAuthenticationSessionKey()

    $viewerMountSegment = [string](Get-DirectWebRtcWebServerPathSegment)
    $authenticationMountPath = if ([string]::IsNullOrWhiteSpace($viewerMountSegment)) { '' } else { "/$($viewerMountSegment.Trim('/'))" }

    # Account data deliberately excluded -- see the matching comment in
    # Start-LetsEncryptTlsProxies.
    $configurationSignature = @(
        [string]$authenticationMountPath,
        [string]$numViewerAuthenticationSessionHours.Value,
        [string]$numDirectWebRtcSignalingPort.Value,
        [string](Get-DirectWebRtcSplitAudioSignalingPort),
        [string]$txtPlayerVideoSignalingProxyPath.Text,
        [string]$txtPlayerAudioSignalingProxyPath.Text
    ) -join '|'
    if (@($script:PlaintextAuthProxies).Count -gt 0) {
        if ($script:PlaintextAuthProxyConfigurationSignature -eq $configurationSignature) { return }
        Append-Log 'AUTH: plaintext-auth configuration changed; restarting the plaintext auth proxies and invalidating viewer sessions.'
        Stop-PlaintextAuthProxies
    }

    $ports = @()
    $videoPort = [int]$numDirectWebRtcSignalingPort.Value
    $ports += [pscustomobject]@{ Label = 'video signalling (plaintext auth)'; Port = $videoPort; PathRoutes = @() }

    $splitAudioActive = (Test-DirectWebRtcSplitAvPipelines) -and -not (Test-DirectWebRtcUnifiedPublisher) -and -not (Test-DirectWebRtcSharedSignaling)
    $audioPort = 0
    if ($splitAudioActive) {
        $audioPort = [int](Get-DirectWebRtcSplitAudioSignalingPort)
        $ports += [pscustomobject]@{ Label = 'split-audio signalling (plaintext auth)'; Port = $audioPort; PathRoutes = @() }
    }

    try {
        $webUri = [System.Uri](Get-DirectWebRtcWebServerBindAddress -Destination $txtDestination.Text)
        $webPort = $webUri.Port
        if ($webPort -gt 0 -and -not (@($ports) | Where-Object { $_.Port -eq $webPort })) {
            $webPathRoutes = @([pscustomobject]@{ Path = [string]$txtPlayerVideoSignalingProxyPath.Text; Port = $videoPort })
            if ($splitAudioActive) {
                $webPathRoutes += [pscustomobject]@{ Path = [string]$txtPlayerAudioSignalingProxyPath.Text; Port = $audioPort }
            }
            $webDirectorySegment = [string](Get-DirectWebRtcWebServerPathSegment)
            $webDirectoryRedirectPath = if ([string]::IsNullOrWhiteSpace($webDirectorySegment)) { '' } else { "/$webDirectorySegment" }
            $ports += [pscustomobject]@{ Label = 'web viewer (plaintext auth)'; Port = $webPort; PathRoutes = $webPathRoutes; DirectoryRedirectPath = $webDirectoryRedirectPath }
        }
    }
    catch {
        Append-Log "AUTH: could not determine the web viewer port for plaintext auth: $($_.Exception.Message)"
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
            $proxy.ConfigureAuthentication(
                $true,
                (Get-ViewerAuthenticationAccountObjects -Accounts $authenticationAccounts),
                $authenticationSessionKey,
                [int]$numViewerAuthenticationSessionHours.Value
            )
            $proxy.Start([int]$portInfo.Port, '127.0.0.1', [int]$portInfo.Port, $null)
            $started += $proxy
            Append-Log "AUTH: plaintext auth active for $($portInfo.Label): 0.0.0.0:$($portInfo.Port) -> 127.0.0.1:$($portInfo.Port)."
        }
        catch {
            Append-Log "AUTH: could not start plaintext auth for $($portInfo.Label) on port $($portInfo.Port): $($_.Exception.Message)"
        }
    }
    $script:PlaintextAuthProxies = $started
    $script:PlaintextAuthProxyConfigurationSignature = if (@($started).Count -gt 0) { $configurationSignature } else { '' }
    $script:PlaintextAuthenticationSessionKey = if (@($started).Count -gt 0) { $authenticationSessionKey } else { $null }
}

# Called from the UI poll timer (90-MainWindow.ps1), same cadence as the
# GstControlledScenePreview/GstWebRtcConsumerPortRange terminal-message
# poll -- proxies queue errors from ThreadPool threads that have no
# PowerShell runspace, so draining must happen from the UI thread.
function Drain-LetsEncryptTlsProxyLogs {
    foreach ($proxy in @($script:LetsEncryptTlsProxies) + @($script:PlaintextAuthProxies)) {
        while ($true) {
            $message = $proxy.PollLogMessage()
            if (-not $message) { break }
            Append-Log "ACME: TLS proxy ($($proxy.Label)): $message"
        }
    }
}

# Proactively disconnects every currently-pumping viewer connection on
# every live proxy (both families), WITHOUT stopping the proxies
# themselves -- for "Keep auth on restarts", where the proxies keep
# accepting connections across a stream restart but the GST process behind
# them is about to be killed. Call this immediately before killing GST so
# already-connected viewers get a clean, immediate disconnect (their
# browser's own reconnect logic fires right away) instead of leaving that
# connection to eventually notice the upstream died on its own -- which is
# what could leave the UI looking hung waiting on it. Safe to call even
# when no proxies are running, or when they're about to be fully stopped
# anyway (Keep-auth off) -- it's a no-op past that point either way.
function Disconnect-ActiveAuthenticationProxyConnections {
    foreach ($proxy in @($script:LetsEncryptTlsProxies) + @($script:PlaintextAuthProxies)) {
        try { $proxy.DisconnectActiveConnections() } catch {}
    }
}

# Call immediately before killing the upstream GST process for a restart
# (alongside Disconnect-ActiveAuthenticationProxyConnections, and for the
# same "Keep auth on restarts" reason: these proxies keep running and
# accepting NEW connections through the whole restart). Without this, a
# plaintext-auth relay -- external and internal port are the SAME number
# by design, unlike the TLS proxy -- can end up connecting to its own
# listener instead of failing when it tries to reach upstream while GST
# is briefly down, and recurse into itself without bound, pegging a CPU
# core and making the whole process look hung. See PauseForwarding's
# comment on the C# side for the verified mechanism.
function Suspend-ActiveAuthenticationProxyForwarding {
    foreach ($proxy in @($script:LetsEncryptTlsProxies) + @($script:PlaintextAuthProxies)) {
        try { $proxy.PauseForwarding() } catch {}
    }
}

# Call once the new GST process has been (re)started -- see
# Suspend-ActiveAuthenticationProxyForwarding.
function Resume-ActiveAuthenticationProxyForwarding {
    foreach ($proxy in @($script:LetsEncryptTlsProxies) + @($script:PlaintextAuthProxies)) {
        try { $proxy.ResumeForwarding() } catch {}
    }
}

# Invalidates every currently-issued viewer session, used in place of
# Stop-LetsEncryptTlsProxies/Stop-PlaintextAuthProxies at every
# Test-KeepAuthenticationProxiesOnRestart-gated Stop/Restart call site
# (27-StreamLifecycle.ps1). Deliberately does NOT stop the proxies --
# activeAuthenticationSessions is static/shared across every instance, so
# clearing it via any one of them signs every viewer out everywhere, and
# the auth gate's existing ordinary-request handling already turns that
# into a 303 to /auth/login on each viewer's very next request, all on its
# own (see RevokeAllSessions's C# comment). Leaving the listener running is
# the whole point: a stopped listener answers nothing at all, so a client
# sitting on a stale cached page would just see every request refused
# forever instead of ever being bounced to login. Player.js also polls
# /auth/status directly on its own schedule as a dedicated heartbeat,
# rather than only noticing this as a side effect of some other fetch.
function Revoke-ActiveAuthenticationProxySessions {
    foreach ($proxy in @($script:LetsEncryptTlsProxies) + @($script:PlaintextAuthProxies)) {
        try { $proxy.RevokeAllSessions() } catch {}
    }
}

function Stop-PlaintextAuthProxies {
    if (@($script:PlaintextAuthProxies).Count -eq 0) { return }
    foreach ($proxy in $script:PlaintextAuthProxies) {
        try { $proxy.Stop() } catch {}
    }
    $script:PlaintextAuthProxies = @()
    $script:PlaintextAuthProxyConfigurationSignature = ''
    $script:PlaintextAuthenticationSessionKey = $null
}

function Stop-LetsEncryptTlsProxies {
    if (@($script:LetsEncryptTlsProxies).Count -eq 0) { return }
    foreach ($proxy in $script:LetsEncryptTlsProxies) {
        try { $proxy.Stop() } catch {}
    }
    $script:LetsEncryptTlsProxies = @()
    $script:LetsEncryptTlsProxyConfigurationSignature = ''
    $script:LetsEncryptAuthenticationSessionKey = $null
}
