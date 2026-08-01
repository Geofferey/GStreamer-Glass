$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$mainWindowPath = Join-Path $repoRoot 'src\90-MainWindow.ps1'
$source = Get-Content -LiteralPath $mainWindowPath -Raw

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $mainWindowPath,
    [ref]$tokens,
    [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
    throw "Main window source failed to parse: $($parseErrors[0].Message)"
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

if ($source.Contains('$popout.Show($form)')) {
    throw 'Console pop-out regression: the console is still owned by the main form.'
}

if (
    -not $source.Contains('$consoleX = [Math]::Max($workingArea.Left') -or
    -not $source.Contains('$consoleY = [Math]::Max($workingArea.Top')
) {
    throw 'Console pop-out regression: its centered location is not clamped to the monitor working area.'
}

Write-Output 'Console pop-out stays independent, opens on-screen, and is available from the tray.'
