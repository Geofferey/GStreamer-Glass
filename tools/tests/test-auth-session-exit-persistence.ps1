# SPDX-License-Identifier: AGPL-3.0-only

# Focused regression coverage for the opt-in "Keep auth on exit" path.
# Exercises the real C# session registry without opening a listener, then
# verifies the distinct UI setting, DPAPI protection, startup restore, and
# shutdown ordering remain wired together.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$setupPath = Join-Path $repoRoot 'src\00-Setup.ps1'
$proxyPath = Join-Path $repoRoot 'src\33-LetsEncrypt.ps1'
$settingsPath = Join-Path $repoRoot 'src\24-Settings.ps1'
$cleanupPath = Join-Path $repoRoot 'src\29-Cleanup.ps1'
$uiPath = Join-Path $repoRoot 'src\90-MainWindow.ps1'
$layoutPath = Join-Path $repoRoot 'src\12-MainDashboardUi.ps1'
$setupSource = Get-Content -Raw -LiteralPath $setupPath
$proxySource = Get-Content -Raw -LiteralPath $proxyPath
$settingsSource = Get-Content -Raw -LiteralPath $settingsPath
$cleanupSource = Get-Content -Raw -LiteralPath $cleanupPath
$uiSource = Get-Content -Raw -LiteralPath $uiPath
$layoutSource = Get-Content -Raw -LiteralPath $layoutPath

function Assert-ExitPersistence {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$marker = "if (-not ('TlsTerminatingProxy' -as [type])) {"
$blockStart = $setupSource.IndexOf($marker)
if ($blockStart -lt 0) { throw 'TlsTerminatingProxy block was not found.' }
$hereStart = $setupSource.IndexOf("@'", $blockStart) + 2
$hereEnd = $setupSource.IndexOf("'@", $hereStart)
if ($hereStart -lt 2 -or $hereEnd -lt 0) { throw 'TlsTerminatingProxy C# here-string was not found.' }
Add-Type -TypeDefinition $setupSource.Substring($hereStart, $hereEnd - $hereStart) -ErrorAction Stop

$passwordHash = [TlsTerminatingProxy]::HashAuthenticationPassword('exit-persistence-test-password')
$account = [TlsTerminatingProxy+AuthenticationAccount]::new()
$account.Username = 'viewer'
$account.PasswordHash = $passwordHash
$proxy = [TlsTerminatingProxy]::new()
$proxy.ConfigureAuthentication(
    $true,
    [TlsTerminatingProxy+AuthenticationAccount[]]@($account),
    [TlsTerminatingProxy]::CreateAuthenticationSessionKey(),
    12
)

$flags = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
$createToken = [TlsTerminatingProxy].GetMethod('CreateAuthenticationSessionToken', $flags)
$validateToken = [TlsTerminatingProxy].GetMethod('ValidateAuthenticationSessionToken', $flags)
$token = [string]$createToken.Invoke($proxy, @('viewer'))
Assert-ExitPersistence ([bool]$validateToken.Invoke($proxy, @($token))) 'Fresh session token was not valid.'

$snapshot = @($proxy.ExportActiveAuthenticationSessions())
Assert-ExitPersistence ($snapshot.Count -eq 1 -and $snapshot[0].Token -eq $token) 'Active session export did not contain the issued token.'
$proxy.RevokeAllSessions()
Assert-ExitPersistence (-not [bool]$validateToken.Invoke($proxy, @($token))) 'Revocation did not remove the exported token from the live registry.'
$proxy.RestoreActiveAuthenticationSessions([TlsTerminatingProxy+AuthenticationSessionState[]]$snapshot)
Assert-ExitPersistence ([bool]$validateToken.Invoke($proxy, @($token))) 'Restoring the session registry did not reactivate a correctly signed token.'

# A snapshot taken after logout/revocation must be empty, so persisting at
# exit can never resurrect an older pre-logout copy.
$proxy.RevokeAllSessions()
$revokedSnapshot = @($proxy.ExportActiveAuthenticationSessions())
Assert-ExitPersistence ($revokedSnapshot.Count -eq 0) 'A revoked token remained in the exported exit snapshot.'
$proxy.RestoreActiveAuthenticationSessions([TlsTerminatingProxy+AuthenticationSessionState[]]$revokedSnapshot)
Assert-ExitPersistence (-not [bool]$validateToken.Invoke($proxy, @($token))) 'An empty post-revocation snapshot unexpectedly restored a token.'

# Persisted authentication is a separate option, not an alias for the
# existing stream-restart behavior.
Assert-ExitPersistence ($uiSource -match "chkViewerAuthenticationKeepOnExit\.Text\s*=\s*'Keep auth on exit") 'The separate Keep auth on exit checkbox is missing.'
Assert-ExitPersistence ($uiSource -match "btnViewerAuthenticationSaveExitCache\.Text\s*=\s*'Save auth cache now'") 'The manual auth-cache save button is missing.'
Assert-ExitPersistence ($uiSource -match "btnViewerAuthenticationDestroyExitCache\.Text\s*=\s*'Destroy auth cache'") 'The auth-cache destroy button is missing.'
Assert-ExitPersistence ($layoutSource.IndexOf('chkViewerAuthenticationKeepOnExit') -gt $layoutSource.IndexOf('chkViewerAuthenticationKeepOnRestart')) 'Keep auth on exit is not laid out below Keep auth on restarts.'
Assert-ExitPersistence ($settingsSource -match 'ViewerAuthenticationKeepOnExit\s*=\s*\[bool\]\$chkViewerAuthenticationKeepOnExit\.Checked') 'Keep auth on exit is not saved in settings.'
Assert-ExitPersistence ($settingsSource -match '\$settings\.ViewerAuthenticationKeepOnExit') 'Keep auth on exit is not restored from settings.'

Assert-ExitPersistence ($proxySource -match '\[System\.Security\.Cryptography\.ProtectedData\]::Protect') 'Authentication exit cache is not DPAPI-protected.'
Assert-ExitPersistence ($proxySource -match '\[System\.Security\.Cryptography\.DataProtectionScope\]::CurrentUser') 'Authentication exit cache is not scoped to the current Windows user.'
Assert-ExitPersistence ($proxySource -match "Type\s*=\s*'ExportSessions'") 'The UI process does not request a live worker session snapshot.'
Assert-ExitPersistence ($proxySource -match "Type\s*=\s*'ImportSessions'") 'The UI process does not restore the worker session snapshot.'
foreach ($diagnostic in @(
    'AUTH: skipped loading the auth cache',
    'AUTH: save requested by',
    'AUTH: restoring $(@($sessions).Count) unexpired session record(s)',
    'AUTH: deleted the persisted auth cache'
)) {
    Assert-ExitPersistence ($proxySource.Contains($diagnostic)) "Auth-cache diagnostic '$diagnostic' is missing."
}

# Execute the real PowerShell cache helpers against a temporary file and a
# stub worker reply. This covers the DPAPI round trip rather than merely
# asserting the API name appears in source.
function Get-FunctionSource {
    param([string]$Source, [string]$FunctionName)
    $pattern = '(?ms)^function\s+' + [regex]::Escape($FunctionName) +
        '\s*\{(?<Body>.*?)(?=^function\s+[A-Za-z0-9_-]+\s*\{|\z)'
    $match = [regex]::Match($Source, $pattern)
    if (-not $match.Success) { throw "Could not find function '$FunctionName'." }
    return $match.Value
}

foreach ($functionName in @(
    'Test-KeepAuthenticationOnExit',
    'Get-PersistedAuthenticationStateEntropy',
    'Clear-PersistedAuthenticationState',
    'Import-PersistedAuthenticationState',
    'Save-PersistedAuthenticationState'
)) {
    Invoke-Expression (Get-FunctionSource -Source $proxySource -FunctionName $functionName)
}

# The real UI refresher is independently source-checked above. Keep the cache
# helper execution headless here.
function Update-PersistedAuthenticationStateUi {}

$cacheTestDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('gstglass-auth-cache-test-' + [Guid]::NewGuid().ToString('N'))
$script:ConfigDirectory = $cacheTestDirectory
$script:PersistedAuthenticationStatePath = Join-Path $cacheTestDirectory 'viewer-auth-state.dat'
$script:PersistedAuthenticationState = $null
$script:PersistedAuthenticationStateLoadAttempted = $false
$script:PersistedAuthenticationSessionsRestored = $false
$script:PersistedAuthenticationKeyUsed = @{ LetsEncrypt = $false; Plaintext = $false }
$script:LetsEncryptAuthenticationSessionKey = [byte[]](1..32)
$script:PlaintextAuthenticationSessionKey = [byte[]](33..64)
$script:chkViewerAuthenticationKeepOnExit = [pscustomobject]@{ Checked = $true }
$script:CapturedCacheLog = @()
$cacheToken = '2000000000.nonce.dmlld2Vy.signature'

function Test-ViewerAuthenticationEnabled { return $true }
function Test-AuthProxyWorkerRunning { return $true }
function Append-Log { param([string]$Message) $script:CapturedCacheLog += $Message }
function Send-AuthProxyWorkerCommand {
    param([hashtable]$Command, [int]$TimeoutMs)
    if ($Command.Type -ne 'ExportSessions') { throw "Unexpected cache-test command '$($Command.Type)'." }
    return [pscustomobject]@{
        Status = 'Ready'
        Sessions = @([pscustomobject]@{ Token = $cacheToken; Expires = 2000000000L })
    }
}

try {
    $null = Save-PersistedAuthenticationState
    Assert-ExitPersistence (Test-Path -LiteralPath $script:PersistedAuthenticationStatePath) 'The real cache helper did not create its DPAPI file.'
    $rawCacheText = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($script:PersistedAuthenticationStatePath))
    Assert-ExitPersistence ($rawCacheText -notmatch [regex]::Escape($cacheToken)) 'A bearer session token was written to the cache in plaintext.'

    # The second save takes the existing-file replacement branch. The shipped
    # .NET Framework host rejects File.Replace(..., $null), even though the
    # first create succeeds, so this path needs its own regression assertion.
    $secondSaveSucceeded = Save-PersistedAuthenticationState
    Assert-ExitPersistence $secondSaveSucceeded 'Replacing an existing encrypted auth cache failed.'
    Assert-ExitPersistence (Test-Path -LiteralPath $script:PersistedAuthenticationStatePath) 'The replacement save removed the auth cache.'
    Assert-ExitPersistence (-not (Test-Path -LiteralPath "$($script:PersistedAuthenticationStatePath).backup-$PID")) 'The replacement save left its encrypted backup behind.'

    $script:PersistedAuthenticationState = $null
    $script:PersistedAuthenticationStateLoadAttempted = $false
    $loadedState = Import-PersistedAuthenticationState
    Assert-ExitPersistence ([string]$loadedState.LetsEncryptSessionKeyBase64 -eq [Convert]::ToBase64String([byte[]](1..32))) 'DPAPI cache round trip changed the TLS session key.'
    Assert-ExitPersistence (@($loadedState.Sessions).Count -eq 1 -and [string]$loadedState.Sessions[0].Token -eq $cacheToken) 'DPAPI cache round trip lost its active session.'

    Clear-PersistedAuthenticationState
    Assert-ExitPersistence (-not (Test-Path -LiteralPath $script:PersistedAuthenticationStatePath)) 'Disabling Keep auth on exit did not delete the cache file.'
}
finally {
    if (Test-Path -LiteralPath $cacheTestDirectory) { Remove-Item -LiteralPath $cacheTestDirectory -Recurse -Force }
}

$saveIndex = $cleanupSource.IndexOf('Save-PersistedAuthenticationState')
$stopFamilyIndex = $cleanupSource.IndexOf('Stop-LetsEncryptTlsProxies')
$stopWorkerIndex = $cleanupSource.IndexOf('Stop-AuthProxyWorker')
Assert-ExitPersistence ($saveIndex -ge 0 -and $saveIndex -lt $stopFamilyIndex -and $saveIndex -lt $stopWorkerIndex) 'Authentication state is not saved before proxy/worker shutdown.'

Write-Output 'Active viewer sessions survive export/import, while revoked sessions stay revoked.'
Write-Output 'Keep auth on exit is a distinct saved UI option and passes a current-user DPAPI round trip.'
Write-Output 'Exit snapshots are taken before proxy-family and worker teardown.'
Write-Output ''
Write-Output 'Authentication exit-persistence checks passed.'
