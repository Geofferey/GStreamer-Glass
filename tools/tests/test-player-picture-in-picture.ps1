$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$distRoot = Join-Path $repoRoot 'gstwebrtc-api\dist'
$index = Get-Content -LiteralPath (Join-Path $distRoot 'index.html') -Raw
$player = Get-Content -LiteralPath (Join-Path $distRoot 'player.js') -Raw
$css = Get-Content -LiteralPath (Join-Path $distRoot 'player.css') -Raw

function Assert-PictureInPicture([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

$utilityMarkup = [regex]::Match($index, '(?s)<div id="viewerUtilityBar".*?</div>')
Assert-PictureInPicture $utilityMarkup.Success 'The viewer utility bar is missing.'
$pipPosition = $utilityMarkup.Value.IndexOf('id="viewerPipButton"', [System.StringComparison]::Ordinal)
$settingsPosition = $utilityMarkup.Value.IndexOf('id="viewerSettingsButton"', [System.StringComparison]::Ordinal)
Assert-PictureInPicture ($pipPosition -ge 0 -and $settingsPosition -gt $pipPosition) 'The PiP button is not immediately left of the settings gear.'

Assert-PictureInPicture ($index.Contains('id="viewerSettingPip"')) 'The settings panel cannot control PiP shortcut visibility.'
Assert-PictureInPicture ($index.Contains('> Background audio</label>')) 'The media notification anchor was not renamed to Background audio.'
Assert-PictureInPicture (-not $index.Contains('Android status-bar controls')) 'The obsolete Android status-bar label is still visible.'
Assert-PictureInPicture ($player.Contains('document.pictureInPictureEnabled === true')) 'The player does not feature-detect standard Picture-in-Picture.'
Assert-PictureInPicture ($player.Contains('await video.requestPictureInPicture()')) 'The PiP shortcut does not enter Picture-in-Picture.'
Assert-PictureInPicture ($player.Contains('await document.exitPictureInPicture()')) 'The PiP shortcut does not exit Picture-in-Picture.'
Assert-PictureInPicture ($player.Contains("video.addEventListener('enterpictureinpicture'")) 'The PiP button does not observe entry state.'
Assert-PictureInPicture ($player.Contains("video.addEventListener('leavepictureinpicture'")) 'The PiP button does not observe exit state.'
Assert-PictureInPicture ($player.Contains("viewerDisplaySetting('pictureInPictureShortcut', true)")) 'PiP shortcut visibility is not persistent or enabled by default.'
Assert-PictureInPicture ($css -match '\.viewerPipButton\.isActive') 'Active PiP state has no visible styling.'

Write-Host 'PASS: Picture-in-Picture is available beside settings and persistently configurable.'
