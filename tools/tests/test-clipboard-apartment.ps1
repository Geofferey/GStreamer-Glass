# SPDX-License-Identifier: AGPL-3.0-only

# Regression coverage for OLE/clipboard calls from the deliberately-MTA
# packaged WinForms host. The helper's real thread must be STA, and UI click
# handlers must never bypass it with Clipboard.SetText directly.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$setupSource = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'src\00-Setup.ps1')
$uiSource = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'src\90-MainWindow.ps1')
$buildSource = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'build.ps1')

function Assert-ClipboardApartment {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$marker = "if (-not ('GstExecutableBrowser' -as [type])) {"
$blockStart = $setupSource.IndexOf($marker)
$hereStart = $setupSource.IndexOf("@'", $blockStart) + 2
$hereEnd = $setupSource.IndexOf("'@", $hereStart)
if ($blockStart -lt 0 -or $hereStart -lt 2 -or $hereEnd -lt 0) { throw 'GstExecutableBrowser/GstClipboard C# block was not found.' }

# This C# block targets the shipped .NET Framework/Windows PowerShell host.
# PowerShell Core's reference-assembly model cannot compile the combined
# WinForms block faithfully, so its run performs the static routing checks;
# Windows PowerShell and build.ps1's compiled EXE smoke execute the real helper.
if ($PSVersionTable.PSEdition -eq 'Desktop') {
    Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition $setupSource.Substring($hereStart, $hereEnd - $hereStart) -ErrorAction Stop
    Assert-ClipboardApartment (
        [GstClipboard]::GetHelperApartmentState() -eq [System.Threading.ApartmentState]::STA
    ) 'The real clipboard helper thread was not initialized as STA.'
}
else {
    Assert-ClipboardApartment ($setupSource -match 'clipboardThread\.SetApartmentState\(ApartmentState\.STA\)') 'The clipboard helper no longer explicitly initializes its worker as STA.'
}
Assert-ClipboardApartment ($uiSource -notmatch '\[System\.Windows\.Forms\.Clipboard\]::SetText') 'A UI handler bypasses GstClipboard with a direct MTA-unsafe Clipboard.SetText call.'
Assert-ClipboardApartment (([regex]::Matches($uiSource, '\[GstClipboard\]::SetText')).Count -eq 3) 'Not every copy button is routed through the STA clipboard helper.'
Assert-ClipboardApartment ($buildSource -match "ClipboardApartmentSelfTest") 'The compiled-host clipboard apartment smoke test is missing from the build.'

Write-Output 'Clipboard STA helper and all copy-button routing checks passed.'
