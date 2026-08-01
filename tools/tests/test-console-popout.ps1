$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$mainWindowPath = Join-Path $repoRoot 'src\90-MainWindow.ps1'
$dashboardPath = Join-Path $repoRoot 'src\12-MainDashboardUi.ps1'
$source = Get-Content -LiteralPath $mainWindowPath -Raw
$dashboardSource = Get-Content -LiteralPath $dashboardPath -Raw

foreach ($sourcePath in @($mainWindowPath, $dashboardPath)) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $sourcePath,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        throw "$sourcePath failed to parse: $($parseErrors[0].Message)"
    }
}

$requiredFragments = @(
    '$tabLog.Text = ''Console''',
    '$trayConsoleItem.Text = ''Console''',
    '$trayConsoleItem.Add_Click({ Show-LogPopoutWindow })',
    '$popout.ShowInTaskbar = $true',
    '$form.RestoreBounds',
    '[System.Windows.Forms.Screen]::FromRectangle($mainBounds).WorkingArea',
    '$popout.Show()'
)

foreach ($fragment in $requiredFragments) {
    if (-not $source.Contains($fragment)) {
        throw "Console pop-out regression: missing expected source fragment: $fragment"
    }
}

$requiredDashboardFragments = @(
    '$script:SidebarNavButtons[''Console''] = New-SidebarButton',
    'Console" 0 { Show-LogPopoutWindow }',
    '$tabLog.Text = " $($script:Glyph.Logs)  Console "'
)

foreach ($fragment in $requiredDashboardFragments) {
    if (-not $dashboardSource.Contains($fragment)) {
        throw "Console dashboard regression: missing expected source fragment: $fragment"
    }
}

if ($source.Contains('$popout.Show($form)')) {
    throw 'Console pop-out regression: the console is still owned by the main form.'
}

foreach ($removedToolbarSymbol in @('$logTopPanel', '$logButtonRow', '$btnPopOutLog')) {
    if ($source.Contains($removedToolbarSymbol) -or $dashboardSource.Contains($removedToolbarSymbol)) {
        throw "Console layout regression: removed toolbar symbol remains: $removedToolbarSymbol"
    }
}

if ($dashboardSource.Contains('$script:SidebarNavButtons[''Logs'']')) {
    throw 'Console dashboard regression: the redundant Logs navigation action remains.'
}

if (
    -not $source.Contains('$consoleX = [Math]::Max($workingArea.Left') -or
    -not $source.Contains('$consoleY = [Math]::Max($workingArea.Top')
) {
    throw 'Console pop-out regression: its centered location is not clamped to the monitor working area.'
}

Write-Output 'Console opens independently from the sidebar or tray, stays on-screen, and leaves the tab unobscured.'
