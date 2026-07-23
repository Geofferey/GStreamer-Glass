# Module: 11-SceneEditor.ps1 (auto-extracted by tools/Split-Monolith.ps1 -- edit here, then run tools/Build-Monolith.ps1)

function New-SceneNumeric {
    param([int]$Minimum, [int]$Maximum, [int]$Value, [int]$Increment = 1)
    $control = New-Object System.Windows.Forms.NumericUpDown
    $control.Minimum = $Minimum
    $control.Maximum = $Maximum
    $control.Value = $Value
    $control.Increment = $Increment
    return $control
}

function Update-SceneSelectionChrome {
    # The live scene preview already contains the composed webcam image. Keep the
    # editor control as a header, outline, and resize handle so it remains fully
    # interactive without painting an opaque rectangle over the video beneath it.
    if (-not $sceneWebcamElement -or $sceneWebcamElement.Width -le 0 -or $sceneWebcamElement.Height -le 0) { return }

    $oldRegion = $sceneWebcamElement.Region
    $outer = New-Object System.Drawing.Rectangle(0, 0, $sceneWebcamElement.Width, $sceneWebcamElement.Height)
    $region = New-Object System.Drawing.Region($outer)

    if ($sceneWebcamElement.Width -gt 6 -and $sceneWebcamElement.Height -gt 30) {
        # Windows PowerShell treats arithmetic placed directly after commas in a
        # New-Object TypeName(...) constructor as an operation on the accumulated
        # Object[] argument list. Calculate dimensions first so the constructor
        # receives four scalar values.
        $holeWidth = [int]$sceneWebcamElement.Width - 4
        $holeHeight = [int]$sceneWebcamElement.Height - 27
        $hole = New-Object System.Drawing.Rectangle(2, 24, $holeWidth, $holeHeight)
        $region.Exclude($hole)
    }

    $sceneWebcamElement.Region = $region
    if ($oldRegion) { try { $oldRegion.Dispose() } catch {} }
    $lblSceneWebcam.Height = [Math]::Min(24, [Math]::Max(1, $sceneWebcamElement.Height))
    $handleX = [Math]::Max(0, [int]$sceneWebcamElement.Width - [int]$sceneResizeHandle.Width - 1)
    $handleY = [Math]::Max(0, [int]$sceneWebcamElement.Height - [int]$sceneResizeHandle.Height - 1)
    $sceneResizeHandle.Location = New-Object System.Drawing.Point($handleX, $handleY)
    if ($sceneWebcamPreviewPanel) {
        # f70 renders the already-composed scene into the canvas itself. The old
        # per-source child sink panel must stay hidden or it covers that output.
        $sceneWebcamPreviewPanel.Visible = $false
        $sceneWebcamPreviewPanel.SendToBack()
    }
    $lblSceneWebcam.BringToFront()
    $sceneResizeHandle.BringToFront()
}

function Set-SceneEditorChromeVisible {
    param([bool]$Visible)

    if ($lblSceneWebcam) { $lblSceneWebcam.Visible = $Visible }
    if ($sceneResizeHandle) { $sceneResizeHandle.Visible = $Visible }
    if ($sceneWebcamElement) {
        $sceneWebcamElement.Visible = ($Visible -and [string]$cmbScenePreset.SelectedItem -ne 'Desktop only')
        $sceneWebcamElement.BorderStyle = if ($Visible) { [System.Windows.Forms.BorderStyle]::FixedSingle } else { [System.Windows.Forms.BorderStyle]::None }
        $sceneWebcamElement.Cursor = if ($Visible) { [System.Windows.Forms.Cursors]::SizeAll } else { [System.Windows.Forms.Cursors]::Default }
    }
    if ($sceneEditorCanvas) {
        $sceneEditorCanvas.BorderStyle = if ($Visible) { [System.Windows.Forms.BorderStyle]::FixedSingle } else { [System.Windows.Forms.BorderStyle]::None }
    }
}

function Save-SceneEditorCanvasHome {
    if (-not $sceneEditorCanvas) { return }
    if ($script:SceneEditorCanvasHomeParent) { return }
    if ($previewPanel -and $sceneEditorCanvas.Parent -eq $previewPanel) { return }

    $script:SceneEditorCanvasHomeParent = $sceneEditorCanvas.Parent
    $script:SceneEditorCanvasHomeDock = $sceneEditorCanvas.Dock
    $script:SceneEditorCanvasHomeMargin = $sceneEditorCanvas.Margin
    $script:SceneEditorCanvasHomeAnchor = $sceneEditorCanvas.Anchor
    $script:SceneEditorCanvasHomeBorderStyle = $sceneEditorCanvas.BorderStyle
}

function Restore-SceneEditorCanvasHome {
    if (-not $sceneEditorCanvas) { return }
    if (-not $script:SceneEditorCanvasHomeParent) { return }
    if ($sceneEditorCanvas.Parent -eq $script:SceneEditorCanvasHomeParent -and -not $script:SceneEditorCanvasHostedInPreview) { return }

    $sceneEditorCanvas.SuspendLayout()
    try {
        $sceneEditorCanvas.Parent = $script:SceneEditorCanvasHomeParent
        if ($null -ne $script:SceneEditorCanvasHomeDock) { $sceneEditorCanvas.Dock = $script:SceneEditorCanvasHomeDock }
        if ($null -ne $script:SceneEditorCanvasHomeMargin) { $sceneEditorCanvas.Margin = $script:SceneEditorCanvasHomeMargin }
        if ($null -ne $script:SceneEditorCanvasHomeAnchor) { $sceneEditorCanvas.Anchor = $script:SceneEditorCanvasHomeAnchor }
        if ($null -ne $script:SceneEditorCanvasHomeBorderStyle) { $sceneEditorCanvas.BorderStyle = $script:SceneEditorCanvasHomeBorderStyle }
        $sceneEditorCanvas.Location = New-Object System.Drawing.Point(0, 0)
        $sceneEditorCanvas.Visible = $true
        $script:SceneEditorCanvasHostedInPreview = $false
        Set-SceneEditorChromeVisible $true
    }
    finally {
        $sceneEditorCanvas.ResumeLayout($true)
    }
}

function Resize-DynamicScenePreviewCardCanvas {
    if (-not $script:SceneEditorCanvasHostedInPreview) { return }
    if (-not $previewPanel -or -not $sceneEditorCanvas) { return }
    if ($previewPanel.ClientSize.Width -le 0 -or $previewPanel.ClientSize.Height -le 0) { return }

    $outputWidth = [Math]::Max(1, [int]$numWidth.Value)
    $outputHeight = [Math]::Max(1, [int]$numHeight.Value)
    $aspect = [double]$outputWidth / [double]$outputHeight

    $availableWidth = [Math]::Max(1, [int]$previewPanel.ClientSize.Width)
    $availableHeight = [Math]::Max(1, [int]$previewPanel.ClientSize.Height)

    $fitWidth = $availableWidth
    $fitHeight = [int][Math]::Round($fitWidth / $aspect)
    if ($fitHeight -gt $availableHeight) {
        $fitHeight = $availableHeight
        $fitWidth = [int][Math]::Round($fitHeight * $aspect)
    }

    $fitWidth = [Math]::Max(1, $fitWidth)
    $fitHeight = [Math]::Max(1, $fitHeight)
    $left = [int][Math]::Max(0, [Math]::Round(($availableWidth - $fitWidth) / 2))
    $top = [int][Math]::Max(0, [Math]::Round(($availableHeight - $fitHeight) / 2))

    $sceneEditorCanvas.SuspendLayout()
    try {
        $sceneEditorCanvas.Dock = 'None'
        $sceneEditorCanvas.Anchor = 'None'
        $sceneEditorCanvas.Location = New-Object System.Drawing.Point($left, $top)
        $sceneEditorCanvas.Size = New-Object System.Drawing.Size($fitWidth, $fitHeight)
        $sceneEditorCanvas.BringToFront()
        Update-SceneCanvasFromValues
    }
    finally {
        $sceneEditorCanvas.ResumeLayout($true)
    }

    Sync-DynamicScenePreviewLayout
}

function Show-DynamicScenePreviewInPreviewCard {
    if (-not $script:DynamicScenePreviewActive) { return }
    if (-not $previewPanel -or -not $sceneEditorCanvas) { return }
    if ($chkStandardPreviewOffSceneTab -and $chkStandardPreviewOffSceneTab.Checked) { return }

    Save-SceneEditorCanvasHome

    $previewPlaceholder.Visible = $false
    $sceneEditorCanvas.SuspendLayout()
    try {
        $sceneEditorCanvas.Parent = $previewPanel
        $sceneEditorCanvas.Dock = 'None'
        $sceneEditorCanvas.Margin = New-Object System.Windows.Forms.Padding(0)
        $sceneEditorCanvas.Anchor = 'None'
        $sceneEditorCanvas.BorderStyle = [System.Windows.Forms.BorderStyle]::None
        $sceneEditorCanvas.Visible = $true
        $script:SceneEditorCanvasHostedInPreview = $true
        Set-SceneEditorChromeVisible $false
        $sceneEditorCanvas.BringToFront()
    }
    finally {
        $sceneEditorCanvas.ResumeLayout($true)
    }

    Resize-DynamicScenePreviewCardCanvas
}

function Update-SceneCanvasFromValues {
    if (-not $sceneEditorCanvas -or $sceneEditorCanvas.ClientSize.Width -le 0 -or $sceneEditorCanvas.ClientSize.Height -le 0) { return }
    $script:UpdatingSceneEditor = $true
    try {
        $outputWidth = [Math]::Max(1, [int]$numWidth.Value)
        $outputHeight = [Math]::Max(1, [int]$numHeight.Value)
        $scaleX = [double]$sceneEditorCanvas.ClientSize.Width / $outputWidth
        $scaleY = [double]$sceneEditorCanvas.ClientSize.Height / $outputHeight
        $left = [int]([Math]::Round([int]$numWebcamX.Value * $scaleX))
        $top = [int]([Math]::Round([int]$numWebcamY.Value * $scaleY))
        $width = [Math]::Max(24, [int]([Math]::Round([int]$numWebcamWidth.Value * $scaleX)))
        $height = [Math]::Max(18, [int]([Math]::Round([int]$numWebcamHeight.Value * $scaleY)))
        $left = [Math]::Max(0, [Math]::Min($sceneEditorCanvas.ClientSize.Width - $width, $left))
        $top = [Math]::Max(0, [Math]::Min($sceneEditorCanvas.ClientSize.Height - $height, $top))
        $sceneWebcamElement.Bounds = New-Object System.Drawing.Rectangle($left, $top, $width, $height)
        Update-SceneSelectionChrome
        $sceneWebcamElement.Visible = (
            [string]$cmbScenePreset.SelectedItem -ne 'Desktop only' -and
            -not $script:SceneEditorCanvasHostedInPreview
        )
        $sceneWebcamElement.Enabled = $chkSceneEnabled.Checked
        $lblSceneDesktop.Text = "DESKTOP BACKGROUND`r`n$outputWidth x $outputHeight"
        $lblSceneWebcam.Text = "WEBCAM  $([int]$numWebcamWidth.Value) x $([int]$numWebcamHeight.Value)"
        if ($sceneDesktopPreviewPanel) {
            # The former desktop-only sink panel is now the one composed-output
            # surface. It fills the canvas beneath the hollow editor chrome.
            $sceneDesktopPreviewPanel.Visible = [bool]$script:DynamicScenePreviewActive
            if ($script:DynamicScenePreviewActive) { $sceneDesktopPreviewPanel.BringToFront() }
        }
        $usingLegacyScenePreview = (
            $script:SceneWorkspaceActive -and
            (-not $script:DynamicScenePreviewActive) -and
            $chkPreview -and $chkPreview.Checked -and
            $previewPanel -and
            $previewPanel.Parent -eq $sceneEditorCanvas
        )
        $lblSceneDesktop.Visible = ((-not $script:DynamicScenePreviewActive) -and (-not $usingLegacyScenePreview))
        if ($usingLegacyScenePreview) {
            $previewPanel.Visible = $true
            $previewPanel.BringToFront()
        }
        $sceneWebcamElement.BringToFront()
        if (Get-Command Sync-DynamicScenePreviewLayout -ErrorAction SilentlyContinue) {
            Sync-DynamicScenePreviewLayout
        }
        if (Get-Command Sync-ControlledScenePreviewProperties -ErrorAction SilentlyContinue) {
            Sync-ControlledScenePreviewProperties
        }
    }
    finally { $script:UpdatingSceneEditor = $false }
}

function Test-ControlledLiveWorkerRunning {
    return (
        $script:ControlledLiveStreamActive -and
        $script:GstProcess -and
        -not $script:GstProcess.HasExited -and
        $script:ControlledLiveWorkerWriter
    )
}

function Sync-ControlledScenePreviewProperties {
    $mutationActive = if ($script:ControlledLiveStreamActive) {
        [bool](Test-ControlledLiveWorkerRunning)
    }
    else {
        ($script:DynamicScenePreviewActive -and [GstControlledScenePreview]::IsRunning)
    }
    if (-not $mutationActive) { return }

    try {
        if ($script:ControlledLiveStreamActive) {
            $null = Send-ControlledLiveWorkerCommand -Command @{
                Type       = 'Webcam'
                X          = [int]$numWebcamX.Value
                Y          = [int]$numWebcamY.Value
                Width      = [int]$numWebcamWidth.Value
                Height     = [int]$numWebcamHeight.Value
                Alpha      = ([double]$numWebcamOpacity.Value / 100.0)
                ZOrder     = [uint32]1
                KeepAspect = [bool]$chkWebcamAspectLock.Checked
            }
            return
        }
        if (-not [GstControlledScenePreview]::IsRunning -or -not [GstControlledScenePreview]::HasWebcamPad) { return }
        [GstControlledScenePreview]::UpdateWebcam(
            [int]$numWebcamX.Value,
            [int]$numWebcamY.Value,
            [int]$numWebcamWidth.Value,
            [int]$numWebcamHeight.Value,
            ([double]$numWebcamOpacity.Value / 100.0),
            [uint32]1,
            [bool]$chkWebcamAspectLock.Checked
        )
    }
    catch {
        Append-Log "Controlled scene property update failed: $($_.Exception.Message)"
    }
}

function Push-ControlledSceneGeometryFromElement {
    # Dragging occurs in scaled canvas coordinates. Convert directly to encoded
    # scene coordinates and mutate the live compositor pad without touching the
    # numeric controls or rebuilding command previews on every mouse-move event.
    $mutationActive = if ($script:ControlledLiveStreamActive) {
        [bool](Test-ControlledLiveWorkerRunning)
    }
    else {
        ($script:DynamicScenePreviewActive -and [GstControlledScenePreview]::IsRunning)
    }
    if (-not $mutationActive) { return }

    $outputWidth = [Math]::Max(1, [int]$numWidth.Value)
    $outputHeight = [Math]::Max(1, [int]$numHeight.Value)
    $scaleX = [double]$outputWidth / [Math]::Max(1, $sceneEditorCanvas.ClientSize.Width)
    $scaleY = [double]$outputHeight / [Math]::Max(1, $sceneEditorCanvas.ClientSize.Height)

    $x = [Math]::Max(0, [int][Math]::Round($sceneWebcamElement.Left * $scaleX))
    $y = [Math]::Max(0, [int][Math]::Round($sceneWebcamElement.Top * $scaleY))
    $width = [Math]::Max(1, [int][Math]::Round($sceneWebcamElement.Width * $scaleX))
    $height = [Math]::Max(1, [int][Math]::Round($sceneWebcamElement.Height * $scaleY))

    try {
        if ($script:ControlledLiveStreamActive) {
            $null = Send-ControlledLiveWorkerCommand -Command @{
                Type       = 'Webcam'
                X          = $x
                Y          = $y
                Width      = $width
                Height     = $height
                Alpha      = ([double]$numWebcamOpacity.Value / 100.0)
                ZOrder     = [uint32]1
                KeepAspect = [bool]$chkWebcamAspectLock.Checked
            }
            return
        }
        if (-not [GstControlledScenePreview]::IsRunning -or -not [GstControlledScenePreview]::HasWebcamPad) { return }
        [GstControlledScenePreview]::UpdateWebcam(
            $x,
            $y,
            $width,
            $height,
            ([double]$numWebcamOpacity.Value / 100.0),
            [uint32]1,
            [bool]$chkWebcamAspectLock.Checked
        )
    }
    catch {
        Append-Log "Controlled scene drag update failed: $($_.Exception.Message)"
    }
}

function Capture-WebcamAspectRatio {
    if ([int]$numWebcamHeight.Value -gt 0) {
        $script:WebcamAspectRatio = [double]$numWebcamWidth.Value / [double]$numWebcamHeight.Value
    }
    if ($script:WebcamAspectRatio -le 0) { $script:WebcamAspectRatio = 16.0 / 9.0 }
}

function Set-SceneValuesFromElement {
    if ($script:UpdatingSceneEditor) { return }
    $outputWidth = [Math]::Max(1, [int]$numWidth.Value)
    $outputHeight = [Math]::Max(1, [int]$numHeight.Value)
    $scaleX = [double]$outputWidth / [Math]::Max(1, $sceneEditorCanvas.ClientSize.Width)
    $scaleY = [double]$outputHeight / [Math]::Max(1, $sceneEditorCanvas.ClientSize.Height)
    $script:UpdatingSceneEditor = $true
    try {
        $cmbWebcamLayout.SelectedItem = 'Custom'
        $numWebcamX.Value = [decimal]([Math]::Min([int]$numWebcamX.Maximum, [Math]::Max(0, [int]([Math]::Round($sceneWebcamElement.Left * $scaleX)))))
        $numWebcamY.Value = [decimal]([Math]::Min([int]$numWebcamY.Maximum, [Math]::Max(0, [int]([Math]::Round($sceneWebcamElement.Top * $scaleY)))))
        $numWebcamWidth.Value = [decimal]([Math]::Min([int]$numWebcamWidth.Maximum, [Math]::Max([int]$numWebcamWidth.Minimum, [int]([Math]::Round($sceneWebcamElement.Width * $scaleX)))))
        $numWebcamHeight.Value = [decimal]([Math]::Min([int]$numWebcamHeight.Maximum, [Math]::Max([int]$numWebcamHeight.Minimum, [int]([Math]::Round($sceneWebcamElement.Height * $scaleY)))))
    }
    finally { $script:UpdatingSceneEditor = $false }
    Update-SceneUi
}

function Place-WebcamOnSceneCanvas {
    param([System.Drawing.Point]$ScreenPoint)
    $canvasBounds = $sceneEditorCanvas.RectangleToScreen($sceneEditorCanvas.ClientRectangle)
    if (-not $canvasBounds.Contains($ScreenPoint)) { return }
    $chkSceneEnabled.Checked = $true
    $cmbScenePreset.SelectedItem = 'Desktop + webcam'
    $point = $sceneEditorCanvas.PointToClient($ScreenPoint)
    Update-SceneCanvasFromValues
    $left = [Math]::Max(0, [Math]::Min($sceneEditorCanvas.ClientSize.Width - $sceneWebcamElement.Width, $point.X - [int]($sceneWebcamElement.Width / 2)))
    $top = [Math]::Max(0, [Math]::Min($sceneEditorCanvas.ClientSize.Height - $sceneWebcamElement.Height, $point.Y - [int]($sceneWebcamElement.Height / 2)))
    $sceneWebcamElement.Location = New-Object System.Drawing.Point($left, $top)
    Set-SceneValuesFromElement
}

function Get-SelectedWebcamIndex {
    $selected = [string]$cmbWebcamDevice.SelectedItem
    if ($selected -match '^\s*(\d+)\s*:') { return [int]$Matches[1] }
    return 0
}

function Refresh-WebcamDevices {
    $previous = [string]$cmbWebcamDevice.SelectedItem
    $cmbWebcamDevice.Items.Clear()
    try {
        $cameras = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object {
            $_.Status -eq 'OK' -and ($_.PNPClass -in @('Camera', 'Image'))
        } | Sort-Object Name -Unique)
        $index = 0
        foreach ($camera in $cameras) {
            $null = $cmbWebcamDevice.Items.Add(("{0}: {1}" -f $index, [string]$camera.Name))
            $index++
        }
    }
    catch {}
    if ($cmbWebcamDevice.Items.Count -eq 0) { $null = $cmbWebcamDevice.Items.Add('0: Default camera') }
    if ($previous -and $cmbWebcamDevice.Items.Contains($previous)) { $cmbWebcamDevice.SelectedItem = $previous }
    else { $cmbWebcamDevice.SelectedIndex = 0 }
}

function Set-WebcamLayoutPreset {
    if ([string]$cmbWebcamLayout.SelectedItem -eq 'Custom') { return }
    $canvasWidth = [int]$numWidth.Value
    $canvasHeight = [int]$numHeight.Value
    $cameraWidth = [int]$numWebcamWidth.Value
    $cameraHeight = [int]$numWebcamHeight.Value
    $margin = 20
    switch ([string]$cmbWebcamLayout.SelectedItem) {
        'Bottom left' { $numWebcamX.Value = $margin; $numWebcamY.Value = [Math]::Max(0, $canvasHeight - $cameraHeight - $margin) }
        'Top right'   { $numWebcamX.Value = [Math]::Max(0, $canvasWidth - $cameraWidth - $margin); $numWebcamY.Value = $margin }
        'Top left'    { $numWebcamX.Value = $margin; $numWebcamY.Value = $margin }
        default       { $numWebcamX.Value = [Math]::Max(0, $canvasWidth - $cameraWidth - $margin); $numWebcamY.Value = [Math]::Max(0, $canvasHeight - $cameraHeight - $margin) }
    }
}

function Update-LiveSceneEditingGate {
    if (-not $chkLiveSceneEditing) { return }

    # This is deliberately based on configuration state, not preview runtime
    # state. The user must be able to opt in before either preview or stream is
    # started, and an editor-layout synchronization must never leave it stale.
    $chkLiveSceneEditing.Enabled = (
        $chkDynamicScenePreviews -and $chkDynamicScenePreviews.Checked -and
        $chkSceneEnabled -and $chkSceneEnabled.Checked -and
        [string]$cmbScenePreset.SelectedItem -eq 'Desktop + webcam'
    )
}

function Update-SceneUi {
    Update-LiveSceneEditingGate
    if ($script:UpdatingSceneEditor) { return }
    $enabled = $chkSceneEnabled.Checked
    foreach ($control in @($cmbScenePreset,$cmbSceneCompositor,$cmbWebcamDevice,$btnRefreshWebcams,$cmbWebcamLayout,$numWebcamWidth,$numWebcamHeight,$numWebcamX,$numWebcamY,$numWebcamFps,$numWebcamOpacity,$numWebcamBorder,$chkWebcamMirror,$chkWebcamAspectLock)) {
        $control.Enabled = $enabled
    }
    $usesCompositor = ($enabled -and [string]$cmbScenePreset.SelectedItem -eq 'Desktop + webcam')
    $numSceneInputQueueBuffers.Enabled = $usesCompositor
    $numSceneInputQueueCapMs.Enabled = $usesCompositor
    $lblSceneStatus.Text = if ($enabled) { 'Scene composition enabled. Dynamic previews and compatible live streams use the real controlled compositor.' } else { 'Scene composition is disabled; the existing capture pipeline is unchanged.' }
    Update-SceneCanvasFromValues
    try { $txtScenePipeline.Text = Build-SceneCaptureChain -LocalOnly } catch { $txtScenePipeline.Text = $_.Exception.Message }
    if (Get-Command Update-CommandPreview -ErrorAction SilentlyContinue) { Update-CommandPreview }
}

function Invoke-ScenePreviewRedraw {
    param([switch]$Quiet)

    try {
        if ($script:SceneWorkspaceActive) {
            Resize-LiveSceneCanvas
        }

        Update-SceneCanvasFromValues

        if ($previewPanel) {
            $previewPanel.PerformLayout()
            $previewPanel.Invalidate()
        }
        if ($sceneEditorCanvas) {
            $sceneEditorCanvas.PerformLayout()
            $sceneEditorCanvas.Invalidate()
        }

        if (Get-Command Reset-PreviewAppliedState -ErrorAction SilentlyContinue) {
            Reset-PreviewAppliedState
        }
        if (Get-Command Try-AttachPreview -ErrorAction SilentlyContinue) {
            Try-AttachPreview
        }
        elseif (Get-Command Set-PreviewVisibility -ErrorAction SilentlyContinue) {
            Set-PreviewVisibility
        }

        if (Get-Command Sync-DynamicScenePreviewLayout -ErrorAction SilentlyContinue) {
            Sync-DynamicScenePreviewLayout
        }

        if (-not $Quiet) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Scene preview redraw requested."
        }
    }
    catch {
        if (-not $Quiet) {
            Append-Log "Scene preview redraw error: $($_.Exception.Message)"
        }
    }
}

function Reset-DynamicScenePreviewFallback {
    $script:SuppressDynamicScenePreview = $false
    $script:DynamicScenePreviewFallbackTriggered = $false
}

function Resize-LiveSceneCanvas {
    if (-not $script:SceneWorkspaceActive -or -not $script:SceneSettingsPane -or $script:ResizingSceneWorkspace) { return }
    if ($script:SceneSettingsPane.ClientSize.Width -le 0) { return }

    $script:ResizingSceneWorkspace = $true
    try {
        $availableWidth = [Math]::Max(550, $script:SceneSettingsPane.ClientSize.Width - 52)
        $outputWidth = [Math]::Max(1, [int]$numWidth.Value)
        $outputHeight = [Math]::Max(1, [int]$numHeight.Value)
        $aspect = [double]$outputWidth / $outputHeight

        # Use the reclaimed dashboard width while keeping very large windows from
        # producing a needlessly gigantic editor surface.
        $canvasWidth = [Math]::Min(1280, $availableWidth)
        $canvasHeight = [int][Math]::Round($canvasWidth / $aspect)
        if ($canvasHeight -gt 720) {
            $canvasHeight = 720
            $canvasWidth = [int][Math]::Round($canvasHeight * $aspect)
        }

        $sceneSourcePalette.Width = $canvasWidth
        $sceneEditorCanvas.Size = New-Object System.Drawing.Size($canvasWidth, $canvasHeight)
        $lblSceneEditorHint.MaximumSize = New-Object System.Drawing.Size($canvasWidth, 0)
        $txtScenePipeline.Width = $canvasWidth
        Update-SceneCanvasFromValues
    }
    finally {
        $script:ResizingSceneWorkspace = $false
    }
}

function Update-SceneWorkspaceMode {
    if (-not $script:DashboardLayout -or -not $script:SettingsTabs -or -not $script:SettingsTabScenes) { return }

    $sceneSelected = ($script:SettingsTabs.SelectedTab -eq $script:SettingsTabScenes)
    if ($sceneSelected) {
        Restore-SceneEditorCanvasHome
    }

    if ($sceneSelected -eq $script:SceneWorkspaceActive) {
        if ($sceneSelected) { Resize-LiveSceneCanvas }
        elseif ($script:DynamicScenePreviewActive -and $chkStandardPreviewOffSceneTab -and -not $chkStandardPreviewOffSceneTab.Checked) {
            Show-DynamicScenePreviewInPreviewCard
        }
        return
    }

    $script:SceneWorkspaceActive = $sceneSelected
    $script:DashboardLayout.SuspendLayout()
    $sceneEditorCanvas.SuspendLayout()
    try {
        if ($sceneSelected) {
            # The normal preview card is redundant on the scene page. Reuse its
            # exact live renderer surface as the editor background and let the
            # settings card occupy the entire dashboard width.
            $previewPanel.Parent = $sceneEditorCanvas
            $previewPanel.Dock = 'Fill'
            $previewPanel.Margin = New-Object System.Windows.Forms.Padding(0)
            $previewPanel.SendToBack()
            $lblSceneDesktop.Visible = $false
            $sceneWebcamElement.BringToFront()

            $previewGroup.Visible = $false
            $script:DashboardLayout.SetColumn($settingsGroup, 0)
            $script:DashboardLayout.SetRow($settingsGroup, 0)
            $script:DashboardLayout.SetColumnSpan($settingsGroup, 2)
            $settingsGroup.Text = '  SCENE WORKSPACE'
        }
        else {
            $previewPanel.Parent = $previewGroup
            $previewPanel.Dock = 'Fill'
            $previewPanel.Margin = New-Object System.Windows.Forms.Padding(12, 24, 12, 12)
            $previewPanel.SendToBack()
            $lblSceneDesktop.Visible = $true

            $script:DashboardLayout.SetColumnSpan($settingsGroup, 1)
            $script:DashboardLayout.SetColumn($settingsGroup, 1)
            $script:DashboardLayout.SetRow($settingsGroup, 0)
            $previewGroup.Visible = $true
            $settingsGroup.Text = '  STREAM SETTINGS'
        }
    }
    finally {
        $sceneEditorCanvas.ResumeLayout($true)
        $script:DashboardLayout.ResumeLayout($true)
    }

    $script:DashboardLayout.PerformLayout()
    if ($sceneSelected) { Resize-LiveSceneCanvas }
    Invoke-ScenePreviewRedraw -Quiet
    if ($sceneSelected) {
        if ($script:PreviewOnlyMode -and $script:GstProcess -and -not $script:GstProcess.HasExited -and (Test-DynamicScenePreviewWanted)) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Scenes tab selected with Dynamic previews enabled; restarting local preview as dynamic scene previews."
            Stop-GstStream
        }
        Sync-StandalonePreviewState -Quiet
    }
    elseif ($script:DynamicScenePreviewActive -and $chkStandardPreviewOffSceneTab -and $chkStandardPreviewOffSceneTab.Checked) {
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Leaving Scenes tab; switching dynamic scene previews back to the normal composed preview."
        Stop-DynamicScenePreview -Quiet
        Sync-StandalonePreviewState -Quiet
    }
    elseif ($script:DynamicScenePreviewActive -and $chkStandardPreviewOffSceneTab -and -not $chkStandardPreviewOffSceneTab.Checked) {
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Leaving Scenes tab; sharing dynamic scene previews in the normal Preview card."
        Show-DynamicScenePreviewInPreviewCard
    }
}

