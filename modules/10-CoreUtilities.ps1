function Get-ApplicationIcon {
    # In a compiled PS12EXE/PS2EXE build, prefer the icon embedded in the EXE.
    # While running as a .ps1, prefer Glass2Glass-Streamer.ico beside the script.
    $currentExePath = $null
    $currentExeName = $null

    try {
        $currentExePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ($currentExePath) {
            $currentExeName = [System.IO.Path]::GetFileNameWithoutExtension($currentExePath)
        }
    }
    catch {}

    $isPowerShellHost = $false
    if ($currentExeName) {
        $isPowerShellHost = $currentExeName -match '^(powershell|pwsh|powershell_ise)$'
    }

    if (
        -not $isPowerShellHost -and
        $currentExePath -and
        (Test-Path -LiteralPath $currentExePath)
    ) {
        try {
            $embeddedIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($currentExePath)
            if ($embeddedIcon) {
                try {
                    $script:AppIconSource = "embedded executable icon: $currentExePath"
                    return [System.Drawing.Icon]$embeddedIcon.Clone()
                }
                finally {
                    $embeddedIcon.Dispose()
                }
            }
        }
        catch {}
    }

    $candidateDirectories = New-Object System.Collections.Generic.List[string]

    foreach ($directory in @(
        $script:ApplicationDirectory,
        $(if ($currentExePath) { Split-Path -Parent $currentExePath }),
        $(try { (Get-Location).Path } catch { $null })
    )) {
        if (
            -not [string]::IsNullOrWhiteSpace($directory) -and
            -not $candidateDirectories.Contains($directory)
        ) {
            $candidateDirectories.Add($directory)
        }
    }

    $candidateNames = New-Object System.Collections.Generic.List[string]
    foreach ($name in @(
        'Glass2Glass-Streamer.ico',
        'GStreamer-Basic-Streamer.ico',
        $(if ($currentExeName) { "$currentExeName.ico" })
    )) {
        if (
            -not [string]::IsNullOrWhiteSpace($name) -and
            -not $candidateNames.Contains($name)
        ) {
            $candidateNames.Add($name)
        }
    }

    foreach ($directory in $candidateDirectories) {
        foreach ($name in $candidateNames) {
            $candidate = Join-Path $directory $name
            if (-not (Test-Path -LiteralPath $candidate)) {
                continue
            }

            try {
                # Clone the icon so the source file is not held open for the
                # lifetime of the GUI.
                $fileIcon = New-Object System.Drawing.Icon($candidate)
                try {
                    $script:AppIconSource = "external icon: $candidate"
                    return [System.Drawing.Icon]$fileIcon.Clone()
                }
                finally {
                    $fileIcon.Dispose()
                }
            }
            catch {}
        }
    }

    $script:AppIconSource = 'Windows default application icon'
    return [System.Drawing.Icon][System.Drawing.SystemIcons]::Application.Clone()
}

function Get-StromGstLaunchCandidates {
    $roots = New-Object System.Collections.Generic.List[string]

    foreach ($root in @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Strom'),
        (Join-Path $env:LOCALAPPDATA 'Strom'),
        (Join-Path $env:APPDATA 'Strom'),
        (Join-Path $env:ProgramFiles 'Strom'),
        (Join-Path $env:ProgramFiles 'Eyevinn\Strom'),
        (Join-Path ${env:ProgramFiles(x86)} 'Strom'),
        (Join-Path ${env:ProgramFiles(x86)} 'Eyevinn\Strom')
    )) {
        if ($root -and (Test-Path -LiteralPath $root)) {
            $roots.Add($root)
        }
    }

    try {
        foreach ($process in @(Get-Process -Name 'strom' -ErrorAction SilentlyContinue)) {
            try {
                if ($process.Path) {
                    $processDirectory = Split-Path -Parent $process.Path
                    if ($processDirectory -and -not $roots.Contains($processDirectory)) {
                        $roots.Add($processDirectory)
                    }
                }
            }
            catch {}
        }
    }
    catch {}

    $results = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    foreach ($root in $roots) {
        try {
            foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter 'gst-launch-1.0.exe' -File -Recurse -ErrorAction SilentlyContinue)) {
                $inspectPath = Join-Path $file.DirectoryName 'gst-inspect-1.0.exe'
                if (Test-Path -LiteralPath $inspectPath) {
                    $results.Add($file)
                }
            }
        }
        catch {}
    }

    return @($results | Sort-Object LastWriteTime -Descending | Select-Object -ExpandProperty FullName -Unique)
}

function Test-GstLaunchPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try {
        $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
        return (
            (Test-Path -LiteralPath $expanded -PathType Leaf) -and
            ([System.IO.Path]::GetFileName($expanded) -ieq 'gst-launch-1.0.exe')
        )
    }
    catch {
        return $false
    }
}

function Normalize-GstLaunchPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    try {
        return [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"')))
    }
    catch {
        return $Path.Trim().Trim('"')
    }
}

function Find-GstLaunch {
    param([string]$CurrentPath)

    # A user-selected/saved binary is authoritative as long as it still exists.
    # Do not silently jump back to an auto-detected runtime unless the selected
    # gst-launch-1.0.exe path is missing or invalid.
    if (Test-GstLaunchPath $CurrentPath) {
        return (Normalize-GstLaunchPath $CurrentPath)
    }

    $officialMsvc = Join-Path $env:ProgramFiles 'gstreamer\1.0\msvc_x86_64\bin\gst-launch-1.0.exe'
    if (Test-GstLaunchPath $officialMsvc) {
        return (Normalize-GstLaunchPath $officialMsvc)
    }

    if ($env:GSTREAMER_ROOT_X86_64) {
        $fromEnvironment = Join-Path $env:GSTREAMER_ROOT_X86_64 'bin\gst-launch-1.0.exe'
        if (Test-GstLaunchPath $fromEnvironment) {
            return (Normalize-GstLaunchPath $fromEnvironment)
        }
    }

    $command = Get-Command 'gst-launch-1.0.exe' -ErrorAction SilentlyContinue
    if ($command -and (Test-GstLaunchPath $command.Source)) {
        return (Normalize-GstLaunchPath $command.Source)
    }

    $candidates = @(
        (Join-Path $env:ProgramFiles 'gstreamer\1.0\mingw_x86_64\bin\gst-launch-1.0.exe'),
        (Join-Path $env:SystemDrive 'gstreamer\1.0\msvc_x86_64\bin\gst-launch-1.0.exe'),
        (Join-Path $env:SystemDrive 'gstreamer\1.0\mingw_x86_64\bin\gst-launch-1.0.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'gstreamer\1.0\msvc_x86_64\bin\gst-launch-1.0.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'gstreamer\1.0\mingw_x86_64\bin\gst-launch-1.0.exe')
    )

    foreach ($candidate in $candidates) {
        if (Test-GstLaunchPath $candidate) {
            return (Normalize-GstLaunchPath $candidate)
        }
    }

    # Strom is now only a compatibility fallback. It should never beat the
    # official Program Files\gstreamer\1.0\msvc_x86_64 install.
    $stromCandidates = @(Get-StromGstLaunchCandidates)
    if ($stromCandidates.Count -gt 0) {
        return (Normalize-GstLaunchPath ([string]$stromCandidates[0]))
    }

    return $officialMsvc
}

function Resolve-GstLaunchSelection {
    param(
        [string]$RequestedPath,
        [switch]$UpdateControl,
        [switch]$Quiet
    )

    if (Test-GstLaunchPath $RequestedPath) {
        return (Normalize-GstLaunchPath $RequestedPath)
    }

    $detected = Find-GstLaunch
    if ($UpdateControl -and -not [string]::IsNullOrWhiteSpace($detected)) {
        if ($txtGstPath.Text -ne $detected) {
            if (-not $Quiet -and -not [string]::IsNullOrWhiteSpace($RequestedPath)) {
                Append-Log "Configured GStreamer executable was not found: $RequestedPath"
                Append-Log "Using detected GStreamer executable: $detected"
            }
            $txtGstPath.Text = $detected
        }
    }

    return $detected
}

function Find-MediaMtx {
    $candidates = New-Object System.Collections.Generic.List[string]

    foreach ($candidate in @(
        $(if ($script:ApplicationDirectory) {
            Join-Path $script:ApplicationDirectory 'mediamtx.exe'
        }),
        $(try {
            Join-Path (Get-Location).Path 'mediamtx.exe'
        }
        catch {
            $null
        }),
        (Join-Path $env:SystemDrive 'mediamtx\mediamtx.exe'),
        $(if ($env:ProgramFiles) {
            Join-Path $env:ProgramFiles 'MediaMTX\mediamtx.exe'
        }),
        $(if (${env:ProgramFiles(x86)}) {
            Join-Path ${env:ProgramFiles(x86)} 'MediaMTX\mediamtx.exe'
        })
    )) {
        if (
            -not [string]::IsNullOrWhiteSpace($candidate) -and
            -not $candidates.Contains($candidate)
        ) {
            $candidates.Add($candidate)
        }
    }

    $command = Get-Command 'mediamtx.exe' -ErrorAction SilentlyContinue
    if ($command -and -not $candidates.Contains($command.Source)) {
        $candidates.Insert(0, $command.Source)
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }

    return ''
}

function Get-PathHash {
    param([Parameter(Mandatory)][string]$Value)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value.ToLowerInvariant())
        $hash = $sha.ComputeHash($bytes)
        return (-join ($hash[0..7] | ForEach-Object { $_.ToString('x2') }))
    }
    finally {
        $sha.Dispose()
    }
}

function Ensure-UnifiedPublisherHostScript {
    $helperDir = Join-Path $env:LOCALAPPDATA 'GStreamerGlass\Helpers'
    if (-not (Test-Path -LiteralPath $helperDir)) { $null = New-Item -ItemType Directory -Path $helperDir -Force }
    $helperPath = Join-Path $helperDir 'GStreamerGlass-UnifiedPublisherHost-f14.ps1'
    $bytes = [Convert]::FromBase64String(($script:UnifiedPublisherHostScriptBase64 -replace '\s',''))
    [System.IO.File]::WriteAllBytes($helperPath, $bytes)
    return $helperPath
}

function Test-DirectWebRtcUnifiedPublisherHostRequired {
    if (-not (Test-DirectWebRtcUnifiedPublisher)) { return $false }
    return (
        (Get-ComboSelectedOrDefault $cmbDirectWebRtcBundlePolicy $script:DefaultDirectWebRtcBundlePolicy) -eq 'Max bundle' -or
        [int]$numDirectWebRtcInternalRtpMtu.Value -gt 0 -or
        $chkDirectWebRtcInternalRepeatHeaders.Checked
    )
}

function Convert-GstLaunchArgumentsToPipelineDescription {
    param([Parameter(Mandatory)][string]$Arguments)
    $pipeline = $Arguments.Trim()
    while ($pipeline -match '^(?:-e|-v)\s+') { $pipeline = $pipeline -replace '^(?:-e|-v)\s+', '' }
    return $pipeline.Trim()
}

function Test-CustomGstArgumentsOverride {
    if ($script:SuppressCustomGstArgumentsOverride) { return $false }
    return [bool]($chkCustomGstArgumentsEnabled -and $chkCustomGstArgumentsEnabled.Checked)
}

function Assert-CustomGstArgumentsAreSafe {
    param([Parameter(Mandatory)][string]$Arguments)

    if ($Arguments -match '(?i)\bgst-launch-1\.0(?:\.exe)?\b') {
        throw 'Custom args expects arguments only. Remove gst-launch-1.0.exe and paste only what follows it.'
    }

    if ($Arguments -match '\$\(') {
        throw 'Custom args rejected: PowerShell command substitution "$(...)" is not allowed.'
    }

    if ($Arguments.IndexOf([string][char]96, [System.StringComparison]::Ordinal) -ge 0) {
        throw 'Custom args rejected: PowerShell backtick escapes are not allowed.'
    }

    $inSingleQuote = $false
    $inDoubleQuote = $false
    for ($i = 0; $i -lt $Arguments.Length; $i++) {
        $ch = $Arguments[$i]
        if ($ch -eq "'" -and -not $inDoubleQuote) {
            $inSingleQuote = -not $inSingleQuote
            continue
        }
        if ($ch -eq '"' -and -not $inSingleQuote) {
            $inDoubleQuote = -not $inDoubleQuote
            continue
        }
        if (-not $inSingleQuote -and -not $inDoubleQuote -and ';|&<>'.IndexOf($ch) -ge 0) {
            throw "Custom args rejected: shell operator '$ch' is not allowed outside quotes."
        }
    }

    if ($inSingleQuote -or $inDoubleQuote) {
        throw 'Custom args rejected: unmatched quote.'
    }
}

function Get-CustomGstArguments {
    $arguments = ''
    if ($txtCustomGstArguments) {
        $arguments = [string]$txtCustomGstArguments.Text
    }

    $arguments = ($arguments -replace "[`r`n`t]+", ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($arguments)) {
        throw 'Custom gst-launch args override is enabled, but no arguments were provided.'
    }

    Assert-CustomGstArgumentsAreSafe -Arguments $arguments
    return $arguments
}

function Get-PowerShellHostExecutable {
    $candidate = if ($PSVersionTable.PSEdition -eq 'Core') { Join-Path $PSHOME 'pwsh.exe' } else { Join-Path $PSHOME 'powershell.exe' }
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    return 'powershell.exe'
}

function Get-UnifiedPublisherHostLaunch {
    param([Parameter(Mandatory)][string]$GstPath, [Parameter(Mandatory)][string]$GstArguments)
    $helperPath = Ensure-UnifiedPublisherHostScript
    if (-not (Test-Path -LiteralPath $script:ConfigDirectory)) { $null = New-Item -ItemType Directory -Path $script:ConfigDirectory -Force }
    $pipelinePath = Join-Path $script:ConfigDirectory 'unified-publisher-pipeline.txt'
    $pipelineDescription = Convert-GstLaunchArgumentsToPipelineDescription -Arguments $GstArguments
    [System.IO.File]::WriteAllText($pipelinePath, $pipelineDescription, (New-Object System.Text.UTF8Encoding($false)))
    $gstBin = Split-Path -Parent $GstPath
    $bundlePolicy = Get-ComboSelectedOrDefault $cmbDirectWebRtcBundlePolicy $script:DefaultDirectWebRtcBundlePolicy
    $mtu = [int]$numDirectWebRtcInternalRtpMtu.Value
    $repeatArg = if ($chkDirectWebRtcInternalRepeatHeaders.Checked) { ' -InternalRepeatHeaders' } else { '' }
    $hostExe = Get-PowerShellHostExecutable
    $hostArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$helperPath`" -GstBin `"$gstBin`" -PipelineFile `"$pipelinePath`" -BundlePolicy `"$bundlePolicy`" -InternalRtpMtu $mtu$repeatArg"
    return [pscustomobject]@{ Executable = $hostExe; Arguments = $hostArgs; HelperPath = $helperPath; PipelinePath = $pipelinePath }
}

function Get-GStreamerRuntimeFingerprint {
    param(
        [Parameter(Mandatory)][string]$GstPath,
        [string[]]$PluginDirectories = @(),
        [string]$Scanner
    )

    $parts = New-Object System.Collections.Generic.List[string]

    foreach ($filePath in @($GstPath, $Scanner)) {
        if ([string]::IsNullOrWhiteSpace($filePath)) { continue }
        try {
            $item = Get-Item -LiteralPath $filePath -ErrorAction Stop
            $parts.Add("file=$($item.FullName.ToLowerInvariant())|len=$($item.Length)|ticks=$($item.LastWriteTimeUtc.Ticks)")
        }
        catch {
            $parts.Add("file=$filePath|missing")
        }
    }

    foreach ($directory in $PluginDirectories) {
        if ([string]::IsNullOrWhiteSpace($directory)) { continue }
        try {
            $dirItem = Get-Item -LiteralPath $directory -ErrorAction Stop
            $pluginFiles = @(Get-ChildItem -LiteralPath $directory -Filter '*.dll' -File -ErrorAction SilentlyContinue)
            $latestPluginTicks = 0L
            foreach ($pluginFile in $pluginFiles) {
                if ($pluginFile.LastWriteTimeUtc.Ticks -gt $latestPluginTicks) {
                    $latestPluginTicks = $pluginFile.LastWriteTimeUtc.Ticks
                }
            }
            $parts.Add("plugins=$($dirItem.FullName.ToLowerInvariant())|count=$($pluginFiles.Count)|dirTicks=$($dirItem.LastWriteTimeUtc.Ticks)|latestDllTicks=$latestPluginTicks")
        }
        catch {
            $parts.Add("plugins=$directory|missing")
        }
    }

    return ($parts -join '||')
}

function Set-GStreamerProcessEnvironmentValue {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][string]$Value
    )

    [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
}

function Prepare-GStreamerRuntime {
    param([Parameter(Mandatory)][string]$GstPath)

    $normalizedGstPath = Normalize-GstLaunchPath $GstPath
    $binDirectory = Split-Path -Parent $normalizedGstPath
    $runtimeRoot = Split-Path -Parent $binDirectory

    # Fully own the gst-launch child-process environment from the selected binary.
    # This prevents stale global/user variables from an old Strom or alternate
    # GStreamer install from poisoning a newly selected runtime.
    foreach ($name in @(
        'GST_PLUGIN_PATH',
        'GST_PLUGIN_PATH_1_0',
        'GST_PLUGIN_SYSTEM_PATH',
        'GST_PLUGIN_SYSTEM_PATH_1_0',
        'GST_PLUGIN_SCANNER',
        'GST_PLUGIN_SCANNER_1_0',
        'GST_REGISTRY',
        'GST_REGISTRY_1_0'
    )) {
        Set-GStreamerProcessEnvironmentValue -Name $name -Value $null
    }

    $env:PATH = "$binDirectory;$($script:BasePathEnvironment)"

    $pluginDirectories = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @(
        (Join-Path $runtimeRoot 'lib\gstreamer-1.0'),
        (Join-Path $runtimeRoot 'lib64\gstreamer-1.0'),
        (Join-Path $binDirectory 'gstreamer-1.0'),
        (Join-Path $runtimeRoot 'plugins')
    )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate) -and -not $pluginDirectories.Contains($candidate)) {
            $pluginDirectories.Add($candidate)
        }
    }

    if ($pluginDirectories.Count -eq 0 -and (Test-Path -LiteralPath $runtimeRoot)) {
        try {
            foreach ($directory in @(Get-ChildItem -LiteralPath $runtimeRoot -Directory -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'gstreamer-1.0' } | Select-Object -First 4)) {
                if (-not $pluginDirectories.Contains($directory.FullName)) {
                    $pluginDirectories.Add($directory.FullName)
                }
            }
        }
        catch {}
    }

    if ($pluginDirectories.Count -gt 0) {
        $pluginPath = $pluginDirectories -join ';'
        # Set both versioned and unversioned names. Different Windows builds and
        # helper processes have historically respected different variants.
        Set-GStreamerProcessEnvironmentValue -Name 'GST_PLUGIN_PATH_1_0' -Value $pluginPath
        Set-GStreamerProcessEnvironmentValue -Name 'GST_PLUGIN_SYSTEM_PATH_1_0' -Value $pluginPath
        Set-GStreamerProcessEnvironmentValue -Name 'GST_PLUGIN_PATH' -Value $pluginPath
        Set-GStreamerProcessEnvironmentValue -Name 'GST_PLUGIN_SYSTEM_PATH' -Value $pluginPath
    }

    $scanner = $null
    foreach ($candidate in @(
        (Join-Path $runtimeRoot 'libexec\gstreamer-1.0\gst-plugin-scanner.exe'),
        (Join-Path $binDirectory 'gst-plugin-scanner.exe')
    )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            $scanner = $candidate
            break
        }
    }

    if ($scanner) {
        Set-GStreamerProcessEnvironmentValue -Name 'GST_PLUGIN_SCANNER_1_0' -Value $scanner
        Set-GStreamerProcessEnvironmentValue -Name 'GST_PLUGIN_SCANNER' -Value $scanner
    }

    if (-not (Test-Path -LiteralPath $script:ConfigDirectory)) {
        $null = New-Item -ItemType Directory -Path $script:ConfigDirectory -Force
    }

    $fingerprint = Get-GStreamerRuntimeFingerprint -GstPath $normalizedGstPath -PluginDirectories @($pluginDirectories) -Scanner $scanner
    $runtimeHash = Get-PathHash -Value $fingerprint
    $registryPath = Join-Path $script:ConfigDirectory "gstreamer-registry-$runtimeHash.bin"

    # Set both names. The unversioned GST_REGISTRY is the important one for many
    # Windows builds; GST_REGISTRY_1_0 is kept for compatibility and clarity.
    Set-GStreamerProcessEnvironmentValue -Name 'GST_REGISTRY_1_0' -Value $registryPath
    Set-GStreamerProcessEnvironmentValue -Name 'GST_REGISTRY' -Value $registryPath

    Append-Log "GStreamer runtime: $normalizedGstPath"
    if ($pluginDirectories.Count -gt 0) {
        Append-Log "Plugin path: $($pluginDirectories -join ';')"
    }
    else {
        Append-Log "Plugin path: not found under $runtimeRoot"
    }
    if ($scanner) {
        Append-Log "Plugin scanner: $scanner"
    }
    else {
        Append-Log "Plugin scanner: not found under $runtimeRoot"
    }
    Append-Log "Isolated registry: $registryPath"
    Append-Log "Runtime registry fingerprint: $runtimeHash"
}

function Format-InvariantNumber {
    param(
        [Parameter(Mandatory)]
        [double]$Value,
        [string]$Format = '0.00'
    )

    return $Value.ToString($Format, [System.Globalization.CultureInfo]::InvariantCulture)
}

function Quote-GstValue {
    param([Parameter(Mandatory)][string]$Value)

    $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
    return '"' + $escaped + '"'
}

function Read-NewLogText {
    param(
        [string]$Path,
        [ref]$Position
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return ''
    }

    try {
        $stream = New-Object System.IO.FileStream(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )

        try {
            if ($Position.Value -gt $stream.Length) {
                $Position.Value = [int64]0
            }

            $null = $stream.Seek($Position.Value, [System.IO.SeekOrigin]::Begin)
            $reader = New-Object System.IO.StreamReader($stream)
            try {
                $text = $reader.ReadToEnd()
                $Position.Value = $stream.Position
                return $text
            }
            finally {
                $reader.Dispose()
            }
        }
        finally {
            $stream.Dispose()
        }
    }
    catch {
        return ''
    }
}

function Get-NearestAacBitrate {
    param([int]$RequestedKbps)

    $valid = @(32, 48, 64, 96, 128, 160, 192, 256, 320, 480, 512)
    $nearest = $valid | Sort-Object { [Math]::Abs($_ - $RequestedKbps) } | Select-Object -First 1
    return [int]$nearest * 1000
}

function Add-Label {
    param(
        [System.Windows.Forms.Control]$Parent,
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$Width = 120
    )

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($Width, 22)
    $label.TextAlign = 'MiddleLeft'
    $Parent.Controls.Add($label)
    return $label
}

