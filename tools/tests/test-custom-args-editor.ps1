$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$sourcePaths = @(
    (Join-Path $repoRoot 'src\00-Setup.ps1'),
    (Join-Path $repoRoot 'src\10-CoreUtilities.ps1'),
    (Join-Path $repoRoot 'src\12-MainDashboardUi.ps1'),
    (Join-Path $repoRoot 'src\24-Settings.ps1'),
    (Join-Path $repoRoot 'src\29-Cleanup.ps1'),
    (Join-Path $repoRoot 'src\90-MainWindow.ps1')
)

$sources = @{}
foreach ($sourcePath in $sourcePaths) {
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
    $sources[$sourcePath] = Get-Content -LiteralPath $sourcePath -Raw
}

$setupSource = $sources[(Join-Path $repoRoot 'src\00-Setup.ps1')]
$coreSource = $sources[(Join-Path $repoRoot 'src\10-CoreUtilities.ps1')]
$dashboardSource = $sources[(Join-Path $repoRoot 'src\12-MainDashboardUi.ps1')]
$settingsSource = $sources[(Join-Path $repoRoot 'src\24-Settings.ps1')]
$cleanupSource = $sources[(Join-Path $repoRoot 'src\29-Cleanup.ps1')]
$mainSource = $sources[(Join-Path $repoRoot 'src\90-MainWindow.ps1')]
$combinedSource = ($sources.Values -join "`n")

$removedMainUiSymbols = @(
    '$tabCustomGstArgs',
    '$customArgsTopPanel',
    '$customArgsButtonRow',
    '$btnPopOutCustomGstArgs',
    '$btnUseGeneratedAsCustomGstArgs',
    '$btnClearCustomGstArgs',
    '$lblCustomGstArgumentsHelp'
)
foreach ($symbol in $removedMainUiSymbols) {
    if ($combinedSource.Contains($symbol)) {
        throw "Custom Args main-UI regression: removed symbol remains: $symbol"
    }
}

$requiredDashboardFragments = @(
    '$script:SidebarNavButtons[''Command''] = New-SidebarButton',
    'Command" 0 { Show-CustomGstArgsEditor }',
    '$tabCommand.Text = " $($script:Glyph.Command)  Command Preview "'
)
foreach ($fragment in $requiredDashboardFragments) {
    if (-not $dashboardSource.Contains($fragment)) {
        throw "Custom Args dashboard regression: missing expected source fragment: $fragment"
    }
}

$requiredMainFragments = @(
    '$chkCustomGstArgumentsEnabled = New-Object System.Windows.Forms.CheckBox',
    '$txtCustomGstArguments = New-Object System.Windows.Forms.TextBox',
    '$trayCommandItem.Text = ''Command''',
    '$trayCommandItem.Add_Click({ Show-CustomGstArgsEditor })',
    '$editor.ShowInTaskbar = $true',
    '$form.RestoreBounds',
    '[System.Windows.Forms.Screen]::FromRectangle($mainBounds).WorkingArea',
    '$editorEnabledCheckBox.Location = New-Object System.Drawing.Point(8, 14)',
    '$editorButtonRow.Padding = New-Object System.Windows.Forms.Padding(0, 8, 8, 0)',
    '$btnEditorUseGenerated.Text = ''Use Generated''',
    '$btnEditorClear.Text = ''Clear''',
    '$btnEditorApply.Text = ''Apply''',
    '$btnEditorCancel.Text = ''Cancel''',
    '$script:CustomArgsEditorTextBox.Text = Build-GstArguments',
    '$txtCustomGstArguments.Text = [string]$script:CustomArgsEditorTextBox.Text',
    '$chkCustomGstArgumentsEnabled.Checked = [bool]$script:CustomArgsEditorEnabledCheckBox.Checked',
    '$editor.Show()'
)
foreach ($fragment in $requiredMainFragments) {
    if (-not $mainSource.Contains($fragment)) {
        throw "Custom Args editor regression: missing expected source fragment: $fragment"
    }
}

if ($mainSource.Contains('$editor.ShowDialog(') -or $mainSource.Contains('$editor.Show($form)')) {
    throw 'Custom Args editor regression: the editor is still modal or owned by the main form.'
}

if (
    $mainSource.Contains('$tabCustomGstArgs.Controls.Add($chkCustomGstArgumentsEnabled)') -or
    $mainSource.Contains('$tabCustomGstArgs.Controls.Add($txtCustomGstArguments)')
) {
    throw 'Custom Args state controls were reattached to the main UI.'
}

if (
    -not $coreSource.Contains('$chkCustomGstArgumentsEnabled.Checked') -or
    -not $coreSource.Contains('$txtCustomGstArguments.Text') -or
    -not $settingsSource.Contains('CustomGstArgumentsEnabled = [bool]$chkCustomGstArgumentsEnabled.Checked') -or
    -not $settingsSource.Contains('CustomGstArguments = [string]$txtCustomGstArguments.Text')
) {
    throw 'Custom Args regression: the nonvisual state no longer feeds pipeline selection or persisted settings.'
}

foreach ($stateName in @('CustomArgsEditorForm', 'CustomArgsEditorTextBox', 'CustomArgsEditorEnabledCheckBox')) {
    if (-not $setupSource.Contains("`$script:$stateName = `$null")) {
        throw "Custom Args editor state is not initialized: $stateName"
    }
    if (-not $cleanupSource.Contains("`$script:$stateName = `$null")) {
        throw "Custom Args editor state is not cleared during shutdown: $stateName"
    }
}

Write-Output 'Custom Args lives only in an independent editor opened from the sidebar or tray, with all actions in its bottom toolbar.'
