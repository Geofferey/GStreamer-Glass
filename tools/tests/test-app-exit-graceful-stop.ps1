# SPDX-License-Identifier: AGPL-3.0-only

# Regression coverage for graceful-stop-on-exit: Invoke-ApplicationCleanup
# (src/29-Cleanup.ps1) previously reimplemented pieces of what the Stop
# button's Request-StreamStop/Stop-GstStream already does (an intentional-
# stop marker, forwarding suspend, connection disconnect, process kill) by
# hand -- a hand-rolled subset that drifted out of sync with the real thing
# and did not reliably reproduce the Stop button's own behavior. It now
# fires Request-StreamStop itself (with -Exiting) and only tears down the
# auth proxy listeners/worker after that call has fully completed.
#
# This is source-text verified rather than executed: these functions are
# deeply tied to live WinForms controls, real process handles, and IPC to
# the auth-proxy worker process, none of which are practical to stand up in
# an isolated test, matching this repo's established fallback for functions
# too heavy to drive end to end (see test-queue-buffer-counts.ps1).
#
# The specific trap this locks in: Stop-GstStream (and the identical gate in
# Stop-ControlledLiveStream) normally revoke every viewer session on any
# non-restart intentional stop (Revoke-ActiveAuthenticationProxySessions),
# gated only on "Keep auth on restarts" -- "Keep auth on exit" is a
# different setting and was never consulted there. Calling Request-
# StreamStop unmodified during exit would revoke every session moments
# before Invoke-ApplicationCleanup's own Save-PersistedAuthenticationState
# call tries to snapshot them, silently defeating "Keep auth on exit". The
# -Exiting switch threaded through Request-StreamStop -> Stop-GstStream ->
# Stop-ControlledLiveStream is what fixes that, and this test locks in that
# every link in that chain is still wired up.
#
# Also covers the Windows logoff/shutdown case: the OS only gives an app a
# bounded window to finish handling session-ending before force-killing it,
# and the graceful-stop sequence above (auth-proxy IPC round trips, process
# WaitForExit calls, the holding-page grace sleep) can easily exceed that on
# its own. $script:FastShutdownCleanup (set from the FormClosing event's
# CloseReason) is what shortens those specific waits -- without touching the
# settings/session save, which stays exactly as reliable either way.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$cleanupPath = Join-Path $repoRoot 'src\29-Cleanup.ps1'
$processLifecyclePath = Join-Path $repoRoot 'src\13-ProcessLifecycle.ps1'
$streamLifecyclePath = Join-Path $repoRoot 'src\27-StreamLifecycle.ps1'
$letsEncryptPath = Join-Path $repoRoot 'src\33-LetsEncrypt.ps1'
$threadingDebugPath = Join-Path $repoRoot 'src\18-ThreadingAndDebug.ps1'
$mediaMtxPath = Join-Path $repoRoot 'src\26-MediaMtx.ps1'
$mainWindowPath = Join-Path $repoRoot 'src\90-MainWindow.ps1'

function Assert-AppExitGracefulStop {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$cleanupSource = Get-Content -Raw -LiteralPath $cleanupPath
if (-not $cleanupSource.Contains('function Invoke-ApplicationCleanup {')) {
    throw "Could not find Invoke-ApplicationCleanup in $cleanupPath -- this test needs updating to match wherever that logic now lives."
}
$processLifecycleSource = Get-Content -Raw -LiteralPath $processLifecyclePath
if (-not $processLifecycleSource.Contains('function Request-StreamStop {')) {
    throw "Could not find Request-StreamStop in $processLifecyclePath -- this test needs updating to match wherever that logic now lives."
}
$streamLifecycleSource = Get-Content -Raw -LiteralPath $streamLifecyclePath
if (-not $streamLifecycleSource.Contains('function Stop-GstStream {')) {
    throw "Could not find Stop-GstStream in $streamLifecyclePath -- this test needs updating to match wherever that logic now lives."
}
if (-not $streamLifecycleSource.Contains('function Stop-ControlledLiveStream {')) {
    throw "Could not find Stop-ControlledLiveStream in $streamLifecyclePath -- this test needs updating to match wherever that logic now lives."
}
$letsEncryptSource = Get-Content -Raw -LiteralPath $letsEncryptPath
if (-not $letsEncryptSource.Contains('function Send-AuthProxyWorkerCommand {')) {
    throw "Could not find Send-AuthProxyWorkerCommand in $letsEncryptPath -- this test needs updating to match wherever that logic now lives."
}
$threadingDebugSource = Get-Content -Raw -LiteralPath $threadingDebugPath
if (-not $threadingDebugSource.Contains('function Get-ProcessExitWaitBudgetMs {')) {
    throw "Could not find Get-ProcessExitWaitBudgetMs in $threadingDebugPath -- this test needs updating to match wherever that logic now lives."
}
$mediaMtxSource = Get-Content -Raw -LiteralPath $mediaMtxPath
if (-not $mediaMtxSource.Contains('function Stop-ManagedMediaMtx {')) {
    throw "Could not find Stop-ManagedMediaMtx in $mediaMtxPath -- this test needs updating to match wherever that logic now lives."
}
$mainWindowSource = Get-Content -Raw -LiteralPath $mainWindowPath
if (-not $mainWindowSource.Contains('$form.Add_FormClosing({')) {
    throw "Could not find the FormClosing handler in $mainWindowPath -- this test needs updating to match wherever that logic now lives."
}

# --- 1. Invoke-ApplicationCleanup fires the real Request-StreamStop, with
#         -Exiting, instead of a hand-rolled subset of what it does. ---
Assert-AppExitGracefulStop ($cleanupSource.Contains('Request-StreamStop -Exiting')) `
    "Invoke-ApplicationCleanup should call Request-StreamStop -Exiting -- the exact same operation the Stop button fires, not a reimplementation of pieces of it."
Write-Output "Invoke-ApplicationCleanup: calls the real Request-StreamStop -Exiting."

# --- 2. The auth cache save is the very FIRST thing this function does,
#         before the stream/proxy is touched at all -- the exact same routine
#         "Save auth cache now" runs while streaming normally (Save-Settings
#         then Save-PersistedAuthenticationState), run here in the same
#         uncontended state that button relies on. ---
$saveSettingsIndex = $cleanupSource.IndexOf('Save-Settings')
$saveIndex = $cleanupSource.IndexOf('Save-PersistedAuthenticationState')
$requestStopIndex = $cleanupSource.IndexOf('Request-StreamStop -Exiting')
Assert-AppExitGracefulStop ($saveSettingsIndex -ge 0) `
    "Invoke-ApplicationCleanup should call Save-Settings, matching the manual 'Save auth cache now' button's routine."
Assert-AppExitGracefulStop ($saveIndex -ge 0) "Invoke-ApplicationCleanup should still call Save-PersistedAuthenticationState."
Assert-AppExitGracefulStop ($saveSettingsIndex -lt $saveIndex) `
    "Save-Settings should run before Save-PersistedAuthenticationState, matching the manual button's order."
Assert-AppExitGracefulStop ($saveIndex -lt $requestStopIndex) `
    "Save-PersistedAuthenticationState should run before Request-StreamStop -- it needs the same uncontended worker state the manual 'Save auth cache now' button relies on, not one already handling a suspended/disconnected/just-killed stream."
Write-Output "Invoke-ApplicationCleanup: auth cache save (Save-Settings + Save-PersistedAuthenticationState) runs first, before the stop."

# --- 3. A bounded wait, and the auth proxy listener/worker teardown, both
#         run strictly AFTER Request-StreamStop has completed -- giving a
#         viewer's browser a real chance to poll, notice the stop, and fetch
#         the holding-page media before the worker that serves it is gone.
#         Stopping the listeners first would already be too late regardless
#         of when the worker process itself dies. ---
Assert-AppExitGracefulStop ($cleanupSource.Contains('Start-Sleep -Milliseconds')) `
    "Invoke-ApplicationCleanup should wait briefly after Request-StreamStop completes before tearing down the auth proxy, so a viewer's browser has a real chance to poll, notice, and fetch the holding-page media first."
$sleepIndex = $cleanupSource.IndexOf('Start-Sleep -Milliseconds')
$letsEncryptStopIndex = $cleanupSource.IndexOf('Stop-LetsEncryptTlsProxies')
$plaintextStopIndex = $cleanupSource.IndexOf('Stop-PlaintextAuthProxies')
$stopWorkerIndex = $cleanupSource.IndexOf('Stop-AuthProxyWorker')
Assert-AppExitGracefulStop ($sleepIndex -gt $requestStopIndex) `
    "The post-stop wait should run after Request-StreamStop, not before -- it's specifically covering the gap between the stop completing and the proxy disappearing."
Assert-AppExitGracefulStop ($letsEncryptStopIndex -gt $requestStopIndex -and $plaintextStopIndex -gt $requestStopIndex -and $stopWorkerIndex -gt $requestStopIndex) `
    "The auth proxy listener/worker teardown must run after Request-StreamStop has completed, not before or concurrently."
Assert-AppExitGracefulStop ($sleepIndex -lt $letsEncryptStopIndex -and $sleepIndex -lt $plaintextStopIndex -and $sleepIndex -lt $stopWorkerIndex) `
    "The post-stop wait must run before the auth proxy listeners and worker are stopped -- waiting afterward is pointless, since the holding page would already be unreachable."
Write-Output "Invoke-ApplicationCleanup: waits after Request-StreamStop completes and before auth proxy teardown, so viewers have time to see the holding page."

# --- 4. Input is disabled before any IPC-waiting call can happen (the save,
#         or anything inside Request-StreamStop) -- Send-AuthProxyWorkerCommand
#         pumps Application.DoEvents() while waiting for a reply, which keeps
#         the window and tray menu clickable mid-exit; a second command
#         landing on the single IPC channel while one is already in flight
#         resets/restarts the whole worker process. ---
$formDisableIndex = $cleanupSource.IndexOf('$form.Enabled = $false')
Assert-AppExitGracefulStop ($formDisableIndex -ge 0 -and $formDisableIndex -lt $saveSettingsIndex) `
    "Invoke-ApplicationCleanup should disable the form before any auth-proxy IPC call (the save, or Request-StreamStop) can happen, so a stray click can't collide with an in-flight command on the single IPC channel."
Write-Output "Invoke-ApplicationCleanup: disables input before any IPC-waiting call can happen."

# --- 5. Request-StreamStop (src/13-ProcessLifecycle.ps1) accepts -Exiting
#         and threads it through to Stop-GstStream -Intentional. ---
Assert-AppExitGracefulStop ($processLifecycleSource.Contains('[switch]$Exiting')) `
    "Request-StreamStop should accept an -Exiting switch."
Assert-AppExitGracefulStop ($processLifecycleSource.Contains('Stop-GstStream -Intentional -Exiting:$Exiting')) `
    "Request-StreamStop should pass -Exiting through to Stop-GstStream, not silently drop it."
Write-Output "Request-StreamStop: accepts -Exiting and passes it through to Stop-GstStream."

# --- 6. Stop-GstStream and Stop-ControlledLiveStream (src/27-StreamLifecycle.ps1)
#         both accept -Exiting, Stop-GstStream passes it through to Stop-
#         ControlledLiveStream, and BOTH functions' session-revocation gates
#         now also check -Exiting + Test-KeepAuthenticationOnExit -- the
#         actual fix for "Keep auth on exit" being silently defeated. Checked
#         as an exact count (2) rather than per-function boundaries, since
#         this file holds many functions and isolating each one's body is
#         needless fragility here -- the gate text itself is distinctive
#         enough that two matches means both call sites, and this test's own
#         earlier checks already confirm both functions exist. ---
Assert-AppExitGracefulStop ($streamLifecycleSource.Contains('function Stop-GstStream {')) "Stop-GstStream should still exist."
$stopGstStreamParamsMatch = [regex]::Match($streamLifecycleSource, 'function Stop-GstStream \{\s*param\(([^)]*)\)', 'Singleline')
Assert-AppExitGracefulStop ($stopGstStreamParamsMatch.Success -and $stopGstStreamParamsMatch.Groups[1].Value.Contains('[switch]$Exiting')) `
    "Stop-GstStream should accept an -Exiting switch."
Assert-AppExitGracefulStop ($streamLifecycleSource.Contains('-Exiting:$Exiting')) `
    "Stop-GstStream should pass -Exiting through to Stop-ControlledLiveStream, not silently drop it."
$stopControlledLiveParamsMatch = [regex]::Match($streamLifecycleSource, 'function Stop-ControlledLiveStream \{\s*param\(([^)]*)\)', 'Singleline')
Assert-AppExitGracefulStop ($stopControlledLiveParamsMatch.Success -and $stopControlledLiveParamsMatch.Groups[1].Value.Contains('[switch]$Exiting')) `
    "Stop-ControlledLiveStream should accept an -Exiting switch."

$revocationGate = '-not (Test-KeepAuthenticationProxiesOnRestart) -and -not ($Exiting -and (Test-KeepAuthenticationOnExit))'
$revocationGateCount = ([regex]::Matches($streamLifecycleSource, [regex]::Escape($revocationGate))).Count
Assert-AppExitGracefulStop ($revocationGateCount -eq 2) `
    "Expected exactly 2 occurrences of the -Exiting-aware session-revocation gate (Stop-GstStream's plain-path teardown and Stop-ControlledLiveStream), found $revocationGateCount. Without this, Request-StreamStop -Exiting still revokes every viewer session on exit even when 'Keep auth on exit' is checked, silently defeating it."
Write-Output "Stop-GstStream / Stop-ControlledLiveStream: both accept -Exiting, it's threaded through, and both session-revocation gates respect 'Keep auth on exit' when exiting."

# --- 7. The FormClosing handler (src/90-MainWindow.ps1) passes its
#         CloseReason through to Invoke-ApplicationCleanup, which uses it to
#         set $script:FastShutdownCleanup only for a Windows logoff/shutdown
#         close (WindowsShutDown -- WinForms has no separate reason for
#         logoff vs. shutdown, both report the same value). ---
Assert-AppExitGracefulStop ($mainWindowSource.Contains('Invoke-ApplicationCleanup -CloseReason $e.CloseReason')) `
    "The FormClosing handler should pass its CloseReason through to Invoke-ApplicationCleanup, so it can detect a Windows logoff/shutdown close specifically."
Assert-AppExitGracefulStop ($cleanupSource.Contains('[System.Windows.Forms.CloseReason]$CloseReason')) `
    "Invoke-ApplicationCleanup should accept a CloseReason parameter."
Assert-AppExitGracefulStop ($cleanupSource.Contains('$script:FastShutdownCleanup = ($CloseReason -eq [System.Windows.Forms.CloseReason]::WindowsShutDown)')) `
    "Invoke-ApplicationCleanup should set `$script:FastShutdownCleanup exactly when CloseReason is WindowsShutDown."
Write-Output "Invoke-ApplicationCleanup: FastShutdownCleanup is derived from the FormClosing event's CloseReason."

# --- 8. During a fast shutdown, the auth-proxy IPC waits (Send-
#         AuthProxyWorkerCommand) and every process WaitForExit on the stop
#         path (Get-ProcessExitWaitBudgetMs) are both shortened, and the
#         holding-page grace sleep is skipped outright -- nobody is around to
#         see it, and the OS's patience for the whole app to finish
#         session-ending is bounded regardless. The settings/session save
#         itself is deliberately NOT gated by this anywhere -- it must stay
#         exactly as reliable during a fast shutdown as any other exit. ---
Assert-AppExitGracefulStop ($letsEncryptSource.Contains('$script:FastShutdownCleanup') -and $letsEncryptSource.Contains('$TimeoutMs = 800')) `
    "Send-AuthProxyWorkerCommand should cap its wait to a short bound when `$script:FastShutdownCleanup is set."
Assert-AppExitGracefulStop ($cleanupSource.Contains('if ($hadActiveStream -and -not $script:FastShutdownCleanup) {')) `
    "The holding-page grace sleep should be skipped outright during a fast shutdown, not just shortened -- nobody is around to see it, and every millisecond counts against the OS's bounded patience."
$saveGatedOnFastShutdown = $cleanupSource.Substring($cleanupSource.IndexOf('Save-Settings'), ($cleanupSource.IndexOf('Request-StreamStop -Exiting') - $cleanupSource.IndexOf('Save-Settings'))).Contains('FastShutdownCleanup')
Assert-AppExitGracefulStop (-not $saveGatedOnFastShutdown) `
    "The auth cache save must not be gated on `$script:FastShutdownCleanup -- it needs to stay exactly as reliable during a Windows logoff as during any other exit, unlike the purely-graceful steps that are safe to shorten."
Write-Output "Invoke-ApplicationCleanup / Send-AuthProxyWorkerCommand: fast-shutdown shortens the graceful-stop waits without touching the auth cache save."

# --- 9. Get-ProcessExitWaitBudgetMs (src/18-ThreadingAndDebug.ps1) backs
#         every WaitForExit call after Stop-ProcessTreeById reachable from
#         the exit path -- Stop-GstStream's three (main/video/audio),
#         Stop-ControlledLiveStream's one, and Stop-ManagedMediaMtx's one --
#         rather than only some of them silently keeping the old fixed
#         3-second wait and reintroducing the same force-kill risk through a
#         gap this fix otherwise closed. ---
Assert-AppExitGracefulStop ($threadingDebugSource.Contains('$script:FastShutdownCleanup')) `
    "Get-ProcessExitWaitBudgetMs should read `$script:FastShutdownCleanup to decide its budget."
$streamLifecycleBudgetUses = ([regex]::Matches($streamLifecycleSource, [regex]::Escape('WaitForExit((Get-ProcessExitWaitBudgetMs))'))).Count
Assert-AppExitGracefulStop ($streamLifecycleBudgetUses -eq 4) `
    "Expected exactly 4 WaitForExit((Get-ProcessExitWaitBudgetMs)) call sites in src/27-StreamLifecycle.ps1 (Stop-GstStream's main/video/audio processes, Stop-ControlledLiveStream's worker process), found $streamLifecycleBudgetUses. A plain WaitForExit(3000) left in place here reintroduces the same Windows-logoff force-kill risk this fix closes elsewhere."
Assert-AppExitGracefulStop ($mediaMtxSource.Contains('WaitForExit((Get-ProcessExitWaitBudgetMs))')) `
    "Stop-ManagedMediaMtx should also use Get-ProcessExitWaitBudgetMs -- it runs on the same exit path (both inside Stop-GstStream and again at the end of Invoke-ApplicationCleanup) and would otherwise keep the old fixed 3-second wait."
Write-Output "Get-ProcessExitWaitBudgetMs: backs every reachable WaitForExit on the exit path (GStreamer x3, controlled live, MediaMTX)."

Write-Output ""
Write-Output "App-exit graceful-stop checks passed."
