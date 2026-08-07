# SPDX-License-Identifier: AGPL-3.0-only

# Regression coverage for the recording seek-index repair mechanism
# (Start-RecordingIndexRepair / Update-PendingRecordingRepairs, src/21-
# Recording.ps1). Background: every stop of a recording pipeline in this app
# hard-kills gst-launch (taskkill /T /F, Stop-ProcessTreeById) rather than
# sending a clean EOS -- the right call for every other pipeline (killing the
# process IS the signalling boundary a WebRTC/RTMP viewer expects), but it
# means matroskamux never gets to write its Cues seek-index, which only
# happens at finalization. Recordings played fine start-to-finish but could
# not be seeked. A prior attempt to fix this by sending a graceful Ctrl+Break
# to gst-launch instead was abandoned: confirmed live (not just in theory)
# that broadcasting CTRL_BREAK_EVENT to the target's console killed the
# CALLING process too, even with a correctly-implemented real console-ctrl
# handler installed to suppress it -- a mechanism that could take down the
# whole app was not shipped. The approach here instead lets the hard kill
# happen exactly as before, then repairs the seek index after the fact with
# a short matroskademux/matroskamux remux pass (repackage only, no
# re-encode), swapped in only once proven to have succeeded.
#
# This does not spawn a real gst-launch process (no test in this repo depends
# on the GStreamer runtime being installed -- see the other tools/tests/
# files) and does not re-derive the actual byte-level Matroska Cues proof;
# that was validated live against real recordings during development. What
# this DOES cover, because it is the part most likely to silently regress and
# the part with real data-loss consequences if it does:
#
#   1. Source shape: the remux pipeline always links video_0, and only links
#      audio_0 when the ORIGINAL recording actually had an audio track --
#      confirmed live during development that referencing an audio_0 pad
#      that will never exist hangs the pipeline forever (gst-launch's
#      delayed-linking waits indefinitely for a pad that is never coming),
#      instead of failing fast.
#   2. Start-RecordingIndexRepair never touches the original file directly,
#      and safely no-ops (no queued job) when the recording path is missing
#      or empty.
#   3. Update-PendingRecordingRepairs' swap-in is a rename-rename-cleanup
#      sequence, executed for real against real files with a real (trivial,
#      non-GStreamer) spawned process standing in for the remux job: a
#      successful repair replaces the original's content, and a FAILED
#      repair (nonzero exit or missing output) leaves the original completely
#      untouched.
#   4. The wiring: both Stop-GstStream and Stop-ControlledLiveStream trigger
#      the repair after their kill, the existing 400ms poll tick drains
#      pending repairs, and app exit waits briefly for one to finish instead
#      of silently abandoning it once the poll timer stops.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$recordingPath = Join-Path $repoRoot 'src\21-Recording.ps1'
$streamLifecyclePath = Join-Path $repoRoot 'src\27-StreamLifecycle.ps1'
$mainWindowPath = Join-Path $repoRoot 'src\90-MainWindow.ps1'
$cleanupPath = Join-Path $repoRoot 'src\29-Cleanup.ps1'

function Assert-RecordingRepair {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-FunctionSource {
    param([string[]]$Lines, [string]$Name)
    $startIdx = ($Lines | Select-String -Pattern "^\s*function $Name \{" | Select-Object -First 1).LineNumber - 1
    if ($null -eq $startIdx) { throw "Could not find function $Name" }
    $depth = 0
    $endIdx = -1
    for ($i = $startIdx; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        $depth += ([regex]::Matches($line, '\{')).Count
        $depth -= ([regex]::Matches($line, '\}')).Count
        if ($depth -eq 0 -and $i -gt $startIdx) { $endIdx = $i; break }
    }
    if ($endIdx -lt 0) { throw "Could not find the end of function $Name" }
    return ($Lines[$startIdx..$endIdx]) -join "`n"
}

$recordingLines = Get-Content -LiteralPath $recordingPath
$startRepairSource = Get-FunctionSource -Lines $recordingLines -Name 'Start-RecordingIndexRepair'
$updateRepairsSource = Get-FunctionSource -Lines $recordingLines -Name 'Update-PendingRecordingRepairs'

# --- 1. Source shape: video_0 is always linked; audio_0 is only linked
#         conditionally on HasAudioTrack. ---
Assert-RecordingRepair ($startRepairSource.Contains('demux.video_0 ! queue ! mux.video_0')) `
    "Start-RecordingIndexRepair should always link the video_0 pad on both ends."
Assert-RecordingRepair ($startRepairSource.Contains('if ($HasAudioTrack)') -and $startRepairSource.Contains('demux.audio_0 ! queue ! mux.audio_0')) `
    "Start-RecordingIndexRepair should only link demux.audio_0/mux.audio_0 when HasAudioTrack is true -- referencing an audio pad that will never exist hangs gst-launch's delayed linking forever instead of failing fast (confirmed live during development)."
Write-Output "Start-RecordingIndexRepair: video_0 always linked, audio_0 linked only when the recording actually had an audio track."

# --- 2. Executed check: a missing/empty recording path must not queue a
#         repair job or touch anything. ---
Invoke-Expression $startRepairSource
$script:PendingRecordingRepairs = New-Object System.Collections.Generic.List[object]
$missingPath = Join-Path $env:TEMP "gstglass-repair-test-missing-$([Guid]::NewGuid().ToString('N')).mkv"
Start-RecordingIndexRepair -RecordingPath $missingPath -HasAudioTrack $true
Assert-RecordingRepair ($script:PendingRecordingRepairs.Count -eq 0) `
    "Start-RecordingIndexRepair must not queue a repair job for a recording path that does not exist."
Write-Output "Start-RecordingIndexRepair (executed): a missing recording path is safely ignored, no job queued."

# --- 3. Executed check: Update-PendingRecordingRepairs' swap-in, against
#         real files and a real (trivial) spawned process standing in for
#         the remux job -- no GStreamer dependency, but real file-system
#         behavior for the part that can actually lose data if it regresses. ---
function Append-Log { param([string]$Message) } # no-op stand-in for the real UI-bound logger
function Stop-ProcessTreeById { param([int]$ProcessId) taskkill.exe /PID $ProcessId /T /F 2>&1 | Out-Null }
Invoke-Expression $updateRepairsSource

$testDir = Join-Path $env:TEMP "gstglass-repair-test-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $testDir -Force | Out-Null
try {
    function New-StandinProcess {
        param([int]$ExitCode)
        Start-Process -FilePath $env:ComSpec -ArgumentList "/c exit $ExitCode" -WindowStyle Hidden -PassThru
    }

    # 3a. Successful repair: temp output exists and the process exits 0 --
    #     the original's content must be replaced by the repaired content.
    $originalOk = Join-Path $testDir 'ok-original.mkv'
    $tempOk = "$originalOk.repair-test.mkv"
    Set-Content -LiteralPath $originalOk -Value 'ORIGINAL-BROKEN-DATA' -NoNewline
    Set-Content -LiteralPath $tempOk -Value 'REPAIRED-DATA' -NoNewline
    $procOk = New-StandinProcess -ExitCode 0
    $procOk.WaitForExit()

    $script:PendingRecordingRepairs = New-Object System.Collections.Generic.List[object]
    $script:PendingRecordingRepairs.Add([pscustomobject]@{
        Process      = $procOk
        OriginalPath = $originalOk
        TempPath     = $tempOk
        StartedAt    = Get-Date
    })
    Update-PendingRecordingRepairs

    Assert-RecordingRepair ((Get-Content -LiteralPath $originalOk -Raw) -eq 'REPAIRED-DATA') `
        "A successful repair (exit 0, valid temp output) must swap the repaired content into the original path."
    Assert-RecordingRepair (-not (Test-Path -LiteralPath $tempOk)) `
        "The temp repair file should be gone after a successful swap-in."
    Assert-RecordingRepair (@(Get-ChildItem -LiteralPath $testDir -Filter '*.prerepair-*.bak').Count -eq 0) `
        "No backup file should remain after a successful swap-in."
    Assert-RecordingRepair ($script:PendingRecordingRepairs.Count -eq 0) `
        "A finished repair job must be removed from the pending list."
    Write-Output "Update-PendingRecordingRepairs (executed): a successful repair swaps the repaired content into place and cleans up."

    # 3b. Failed repair: nonzero exit, no temp output produced -- the
    #     original must be left completely untouched.
    $originalFail = Join-Path $testDir 'fail-original.mkv'
    $tempFail = "$originalFail.repair-test.mkv"
    Set-Content -LiteralPath $originalFail -Value 'ORIGINAL-SAFE-DATA' -NoNewline
    $procFail = New-StandinProcess -ExitCode 1
    $procFail.WaitForExit()

    $script:PendingRecordingRepairs = New-Object System.Collections.Generic.List[object]
    $script:PendingRecordingRepairs.Add([pscustomobject]@{
        Process      = $procFail
        OriginalPath = $originalFail
        TempPath     = $tempFail
        StartedAt    = Get-Date
    })
    Update-PendingRecordingRepairs

    Assert-RecordingRepair ((Get-Content -LiteralPath $originalFail -Raw) -eq 'ORIGINAL-SAFE-DATA') `
        "A failed repair (nonzero exit / missing temp output) must leave the original recording completely untouched -- this is the core data-safety guarantee of the whole mechanism."
    Assert-RecordingRepair ($script:PendingRecordingRepairs.Count -eq 0) `
        "A finished (even failed) repair job must be removed from the pending list."
    Write-Output "Update-PendingRecordingRepairs (executed): a failed repair leaves the original recording completely untouched."

    # 3c. Failed repair where a temp output DOES exist (a partial/corrupt
    #     write despite the process reporting failure) -- distinct from 3b
    #     because if the exit-code check were removed, Move-Item would
    #     happily swap this garbage in (the file exists, so the swap
    #     mechanics alone would not catch it the way a missing file does
    #     via its own catch-block recovery).
    $originalFail2 = Join-Path $testDir 'fail2-original.mkv'
    $tempFail2 = "$originalFail2.repair-test.mkv"
    Set-Content -LiteralPath $originalFail2 -Value 'ORIGINAL-SAFE-DATA-2' -NoNewline
    Set-Content -LiteralPath $tempFail2 -Value 'PARTIAL-GARBAGE-OUTPUT' -NoNewline
    $procFail2 = New-StandinProcess -ExitCode 1
    $procFail2.WaitForExit()

    $script:PendingRecordingRepairs = New-Object System.Collections.Generic.List[object]
    $script:PendingRecordingRepairs.Add([pscustomobject]@{
        Process      = $procFail2
        OriginalPath = $originalFail2
        TempPath     = $tempFail2
        StartedAt    = Get-Date
    })
    Update-PendingRecordingRepairs

    Assert-RecordingRepair ((Get-Content -LiteralPath $originalFail2 -Raw) -eq 'ORIGINAL-SAFE-DATA-2') `
        "A nonzero exit code must block the swap-in even when a temp output file exists -- otherwise a partial/corrupt write from a failed remux could still get swapped into place."
    Write-Output "Update-PendingRecordingRepairs (executed): a nonzero exit code blocks the swap-in even when a temp output file exists."
}
finally {
    Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
}

# --- 4. Wiring: both stop paths trigger the repair, the poll tick drains
#         it, and exit waits briefly instead of abandoning an in-flight job. ---
$streamLifecycleText = (Get-Content -LiteralPath $streamLifecyclePath) -join "`n"
$repairCallCount = ([regex]::Matches($streamLifecycleText, 'Start-RecordingIndexRepair -RecordingPath')).Count
Assert-RecordingRepair ($repairCallCount -eq 2) `
    "Expected Start-RecordingIndexRepair to be called from exactly the two stop paths (Stop-ControlledLiveStream and Stop-GstStream), found $repairCallCount call(s)."
Write-Output "Stop-ControlledLiveStream and Stop-GstStream both trigger Start-RecordingIndexRepair after their kill."

$mainWindowText = (Get-Content -LiteralPath $mainWindowPath) -join "`n"
Assert-RecordingRepair ($mainWindowText.Contains('Update-PendingRecordingRepairs')) `
    "The main poll tick should call Update-PendingRecordingRepairs to drain background repair jobs."
Write-Output "The 400ms poll tick drains pending recording repairs."

$cleanupText = (Get-Content -LiteralPath $cleanupPath) -join "`n"
Assert-RecordingRepair ($cleanupText.Contains('PendingRecordingRepairs.Count -gt 0') -and $cleanupText.Contains('Update-PendingRecordingRepairs')) `
    "Invoke-ApplicationCleanup should wait briefly and drain any in-flight recording repair before exiting -- otherwise the poll timer stopping first (it stops before cleanup runs) would abandon it: a produced-but-never-swapped-in repair, forever."
Write-Output "App exit waits briefly for an in-flight recording repair instead of abandoning it."

Write-Output ""
Write-Output "Recording index repair checks passed."
