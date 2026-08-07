# SPDX-License-Identifier: AGPL-3.0-only

# Regression coverage for a Network-tab layout bug reported multiple times:
# a collapsible section's expanded body (most visibly Dynamic DNS's
# checkbox/status/Provider/Hostname/... fields) rendering AFTER several
# unrelated LATER sections' headers (SSL/TLS Security, TLS Certificate,
# Viewer Authentication) instead of directly beneath its own header.
#
# Root cause: Add-CollapsibleSection (src/12-MainDashboardUi.ps1) added a
# section's header Label and its body FlowLayoutPanel as two SEPARATE,
# unpaired direct children of the outer scrollable pane. Nothing then
# prevented WinForms from visually separating them whenever the pane's
# layout was recomputed from a stale/partial state -- which more than one
# trigger could plausibly cause (Update-DdnsUi toggling nested provider
# sub-panels' .Visible with no PerformLayout call anywhere nearby; a -Wrap
# status label's text change crossing a line-wrap boundary; possibly
# others). The exact trigger proved impossible to force reliably in an
# isolated repro despite real effort (tried: nested sub-panel visibility
# toggles, a -Wrap label's text-length change, both before and after the
# window's first paint) -- WinForms' automatic layout propagation held up
# in a simplified harness even without the fix, so this is NOT a
# reproduce-the-exact-failure test.
#
# Instead of chasing every possible trigger, the fix makes the reported
# symptom structurally impossible: the header and body are now added to a
# dedicated wrapper FlowLayoutPanel that is itself the ONLY thing added to
# the outer pane, so they are always one atomic unit in the pane's Controls
# collection -- no other section's header or body can ever land between
# them, regardless of what triggers a stale/partial relayout. This test
# verifies that invariant directly: the source shape (wrapper added to
# $Pane; header and section added to the wrapper, never to $Pane), AND an
# executed check (build two real collapsible sections and confirm the
# header and body share one parent that is not the outer pane).
#
# Also covers Update-DdnsUi (src/32-Ddns.ps1), a concrete contributor found
# while tracing this: it toggled four nested sub-panels' .Visible with no
# PerformLayout call anywhere, unlike every other place in this codebase
# that does this correctly.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$dashboardPath = Join-Path $repoRoot 'src\12-MainDashboardUi.ps1'
$ddnsPath = Join-Path $repoRoot 'src\32-Ddns.ps1'

function Assert-CollapsibleSectionCoupling {
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

$dashboardLines = Get-Content -LiteralPath $dashboardPath
if (-not ($dashboardLines -join "`n").Contains('function Add-CollapsibleSection {')) {
    throw "Could not find Add-CollapsibleSection in $dashboardPath -- this test needs updating to match wherever that logic now lives."
}
$addCollapsibleSectionSource = Get-FunctionSource -Lines $dashboardLines -Name 'Add-CollapsibleSection'

# --- 1. Source shape: the wrapper is added to $Pane, and header/section are
#         added to the wrapper -- never directly to $Pane. ---
Assert-CollapsibleSectionCoupling ($addCollapsibleSectionSource.Contains('$Pane.Controls.Add($wrapper)')) `
    "Add-CollapsibleSection should add a wrapper to `$Pane, not the header/section directly."
Assert-CollapsibleSectionCoupling (-not $addCollapsibleSectionSource.Contains('$Pane.Controls.Add($header)')) `
    "Add-CollapsibleSection must NOT add the header directly to `$Pane -- it needs to live inside the same wrapper as its body so no other section's header/body can ever land between them."
Assert-CollapsibleSectionCoupling (-not $addCollapsibleSectionSource.Contains('$Pane.Controls.Add($section)')) `
    "Add-CollapsibleSection must NOT add the section (body) directly to `$Pane -- same reasoning as the header check above."
Assert-CollapsibleSectionCoupling ($addCollapsibleSectionSource.Contains('$wrapper.Controls.Add($header)')) `
    "Add-CollapsibleSection should add the header to the wrapper."
Assert-CollapsibleSectionCoupling ($addCollapsibleSectionSource.Contains('$wrapper.Controls.Add($section)')) `
    "Add-CollapsibleSection should add the section (body) to the wrapper."
Write-Output "Add-CollapsibleSection: header and body are added to a shared wrapper, never directly to the outer pane."

# --- 2. Executed check: build a real pane with two real collapsible
#         sections (mirroring two Network-tab sections) and confirm the
#         first section's header and body share the same immediate parent,
#         and that parent is not the outer pane itself -- the actual
#         invariant that makes the reported bug structurally impossible,
#         regardless of whatever triggers a stale/partial relayout. ---
$script:ColorAccent = [System.Drawing.Color]::Blue
$script:ColorText = [System.Drawing.Color]::Black
Invoke-Expression $addCollapsibleSectionSource

$pane = New-Object System.Windows.Forms.FlowLayoutPanel
$pane.FlowDirection = 'TopDown'
$pane.AutoScroll = $true

$firstBody = Add-CollapsibleSection -Pane $pane -Title 'First Section' -Collapsed $false
$secondBody = Add-CollapsibleSection -Pane $pane -Title 'Second Section' -Collapsed $true

$firstHeader = $pane.Controls | ForEach-Object { $_.Controls } | Where-Object { $_ -is [System.Windows.Forms.Label] -and $_.Text -match 'FIRST SECTION' } | Select-Object -First 1
Assert-CollapsibleSectionCoupling ($null -ne $firstHeader) "Could not find the first section's header control in the built pane."

Assert-CollapsibleSectionCoupling ($firstHeader.Parent -eq $firstBody.Parent) `
    "The header and body returned by Add-CollapsibleSection must share the same immediate parent (the wrapper) -- if they don't, they are direct siblings of the outer pane again and the reported bug (a body landing after unrelated later headers) is possible again."
Assert-CollapsibleSectionCoupling ($firstHeader.Parent -ne $pane) `
    "The header's parent must be a dedicated wrapper, not the outer pane directly -- otherwise the header and body are unpaired top-level pane children again."
Assert-CollapsibleSectionCoupling ($pane.Controls.Count -eq 2) `
    "The outer pane should have exactly 2 children (one wrapper per collapsible section) after adding 2 sections, found $($pane.Controls.Count) -- if this is 4, header/section are still being added directly to the pane instead of into per-section wrappers."
Write-Output "Add-CollapsibleSection (executed): header and body share one wrapper parent, distinct from the outer pane; the outer pane has exactly one child per section."

# --- 3. Update-DdnsUi explicitly reflows its FlowLayoutPanel ancestor chain
#         after toggling the nested provider sub-panels' .Visible, instead
#         of relying on WinForms' automatic (and here unreliable)
#         propagation -- a concrete contributor to the reported bug found
#         while tracing it. ---
$ddnsLines = Get-Content -LiteralPath $ddnsPath
if (-not ($ddnsLines -join "`n").Contains('function Update-DdnsUi {')) {
    throw "Could not find Update-DdnsUi in $ddnsPath -- this test needs updating to match wherever that logic now lives."
}
$updateDdnsUiSource = Get-FunctionSource -Lines $ddnsLines -Name 'Update-DdnsUi'
Assert-CollapsibleSectionCoupling ($updateDdnsUiSource.Contains('.PerformLayout()')) `
    "Update-DdnsUi should explicitly call PerformLayout() after toggling its nested provider sub-panels' .Visible, instead of relying on WinForms' automatic layout propagation through the nested AutoSize FlowLayoutPanel chain, which proved unreliable."
$lastVisibleToggleIndex = $updateDdnsUiSource.LastIndexOf('.Visible =')
$performLayoutIndex = $updateDdnsUiSource.IndexOf('.PerformLayout()')
Assert-CollapsibleSectionCoupling ($performLayoutIndex -gt $lastVisibleToggleIndex) `
    "Update-DdnsUi's PerformLayout() call should run after all the .Visible toggles, not before -- otherwise it reflows based on the pre-toggle state."
Write-Output "Update-DdnsUi: explicitly reflows its FlowLayoutPanel ancestor chain after toggling nested sub-panel visibility."

Write-Output ""
Write-Output "Collapsible-section header/body coupling checks passed."
