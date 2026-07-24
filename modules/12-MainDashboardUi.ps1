function Apply-ModernDashboardUi {
    $script:ColorBg       = [System.Drawing.ColorTranslator]::FromHtml('#0B1220')
    $script:ColorSurface  = [System.Drawing.ColorTranslator]::FromHtml('#111827')
    $script:ColorSurface2 = [System.Drawing.ColorTranslator]::FromHtml('#172033')
    $script:ColorBorder   = [System.Drawing.ColorTranslator]::FromHtml('#334155')
    $script:ColorText     = [System.Drawing.ColorTranslator]::FromHtml('#E5E7EB')
    $script:ColorMuted    = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
    $script:ColorAccent   = [System.Drawing.ColorTranslator]::FromHtml('#2563EB')
    $script:ColorGood     = [System.Drawing.ColorTranslator]::FromHtml('#22C55E')
    $script:ColorWarn     = [System.Drawing.ColorTranslator]::FromHtml('#F59E0B')

    # UI glyphs. Built from code points via ConvertFromUtf32 so they survive any
    # source-file encoding round-trip under Windows PowerShell 5.1 (which has no
    # \u escape). IMPORTANT: WinForms buttons draw text through GDI (TextRenderer),
    # whose font-linking falls back to Segoe UI Symbol for Basic-Multilingual-Plane
    # symbols but points astral-plane emoji (U+1F###) at Segoe UI Emoji, a color
    # font GDI cannot rasterize -> those render as tofu boxes. So every glyph here
    # is a BMP symbol from a block GDI links reliably: Geometric Shapes (U+25xx),
    # Arrows (U+21xx), Latin-1 (U+00xx), plus a few individually confirmed marks.
    $script:Glyph = @{
        Transport = [char]::ConvertFromUtf32(0x2191)   # up arrow (uplink / publish)
        WebRtc    = [char]::ConvertFromUtf32(0x21C4)   # paired arrows (peer duplex)
        Video     = [char]::ConvertFromUtf32(0x25A3)   # framed square (viewport)
        Scenes    = [char]::ConvertFromUtf32(0x25F0)   # quadrant square (layout)
        Audio     = [char]::ConvertFromUtf32(0x266A)   # musical note
        Player    = [char]::ConvertFromUtf32(0x25B6)   # play triangle
        Recording = [char]::ConvertFromUtf32(0x23FA)   # record circle
        Network   = [char]::ConvertFromUtf32(0x25C9)   # fisheye (hub / node)
        Options   = [char]::ConvertFromUtf32(0x2699)   # gear
        Profiles  = [char]::ConvertFromUtf32(0x2605)   # star (presets)
        Logs      = [char]::ConvertFromUtf32(0x25A4)   # square w/ horizontal fill (lines)
        Command   = [char]::ConvertFromUtf32(0x00BB)   # >> (prompt)
        Start     = [char]::ConvertFromUtf32(0x25B6)   # play triangle
        Stop      = [char]::ConvertFromUtf32(0x25A0)   # black square
        Restart   = [char]::ConvertFromUtf32(0x21BB)   # clockwise arrow
        Copy      = [char]::ConvertFromUtf32(0x2750)   # shadowed square (duplicate)
        Clear     = [char]::ConvertFromUtf32(0x00D7)   # multiplication sign (x)
        OpenLogs  = [char]::ConvertFromUtf32(0x2197)   # up-right arrow (open external)
        Ready     = [char]::ConvertFromUtf32(0x25CF)   # filled circle
    }

    $form.Size = New-Object System.Drawing.Size(1500, 930)
    $form.MinimumSize = New-Object System.Drawing.Size(1280, 760)
    $form.BackColor = $script:ColorBg
    $form.ForeColor = $script:ColorText
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    function Style-Tree {
        param([System.Windows.Forms.Control]$Control)

        try {
            $Control.ForeColor = $script:ColorText

            if ($Control -is [System.Windows.Forms.GroupBox]) {
                $Control.BackColor = $script:ColorSurface
                $Control.ForeColor = $script:ColorText
                $Control.Padding = New-Object System.Windows.Forms.Padding(10)
            }
            elseif ($Control -is [System.Windows.Forms.Panel]) {
                if ($Control.Name -notin @('previewPanel','SceneEditorCanvas','SceneWebcamElement','SceneResizeHandle','SceneSourcePalette')) {
                    $Control.BackColor = $script:ColorSurface
                }
            }
            elseif ($Control -is [System.Windows.Forms.TextBox]) {
                $Control.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0F172A')
                $Control.ForeColor = $script:ColorText
                $Control.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
            }
            elseif ($Control -is [System.Windows.Forms.ComboBox]) {
                $Control.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0F172A')
                $Control.ForeColor = $script:ColorText
                $Control.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
            }
            elseif ($Control -is [System.Windows.Forms.NumericUpDown]) {
                $Control.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0F172A')
                $Control.ForeColor = $script:ColorText
            }
            elseif ($Control -is [System.Windows.Forms.Button]) {
                $Control.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
                $Control.FlatAppearance.BorderColor = $script:ColorBorder
                $Control.FlatAppearance.MouseOverBackColor = [System.Drawing.ColorTranslator]::FromHtml('#1D4ED8')
                $Control.FlatAppearance.MouseDownBackColor = [System.Drawing.ColorTranslator]::FromHtml('#1E40AF')
                $Control.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#1F2937')
                $Control.ForeColor = $script:ColorText
                $Control.Cursor = [System.Windows.Forms.Cursors]::Hand
            }
            elseif ($Control -is [System.Windows.Forms.CheckBox]) {
                $Control.BackColor = $script:ColorSurface
                $Control.ForeColor = $script:ColorText
                $Control.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard
                $Control.UseVisualStyleBackColor = $false
            }
            elseif ($Control -is [System.Windows.Forms.Label]) {
                $Control.BackColor = [System.Drawing.Color]::Transparent
                if ($Control.ForeColor -eq [System.Drawing.Color]::Black) {
                    $Control.ForeColor = $script:ColorMuted
                }
            }
            elseif ($Control -is [System.Windows.Forms.TabControl]) {
                $Control.BackColor = $script:ColorSurface
            }
            elseif ($Control -is [System.Windows.Forms.TabPage]) {
                $Control.BackColor = $script:ColorSurface
                $Control.ForeColor = $script:ColorText
            }
        }
        catch {}

        foreach ($child in $Control.Controls) {
            Style-Tree $child
        }
    }

    function New-SidebarButton {
        param(
            [string]$Text,
            [int]$Y,
            [scriptblock]$OnClick = $null,
            [bool]$Active = $false
        )

        # Y is accepted only for backward compatibility with older call sites.
        # The sidebar is now a FlowLayoutPanel, so button placement is declarative.
        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = $Text
        $btn.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $btn.Width = 172
        $btn.Height = 46
        $btn.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
        $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $btn.FlatAppearance.BorderSize = 0
        $btn.BackColor = if ($Active) {
            [System.Drawing.ColorTranslator]::FromHtml('#17345C')
        }
        else {
            [System.Drawing.ColorTranslator]::FromHtml('#0B1220')
        }
        $btn.ForeColor = $script:ColorText
        $btn.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
        $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
        if ($OnClick) { $btn.Add_Click($OnClick) }
        return $btn
    }

    function New-SidebarHeading {
        param([string]$Text)

        # A small muted caption that groups the buttons below it. Keeps the two
        # navigation clusters (settings panes vs. output views) visually distinct
        # so the sidebar reads as an outline rather than a flat list.
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $Text.ToUpperInvariant()
        $lbl.AutoSize = $false
        $lbl.Width = 172
        $lbl.Height = 20
        $lbl.TextAlign = 'BottomLeft'
        $lbl.Margin = New-Object System.Windows.Forms.Padding(4, 10, 0, 2)
        $lbl.ForeColor = $script:ColorMuted
        $lbl.Font = New-Object System.Drawing.Font('Segoe UI', 7.5, [System.Drawing.FontStyle]::Bold)
        return $lbl
    }

    # Shell.
    # The visible window chrome is now fully layout-panel driven:
    # Form -> root table -> sidebar + main table -> header / dashboard / lower tabs.
    # No shell card/action/log placement depends on fixed pixels anymore.
    $form.SuspendLayout()
    try {
        $form.Controls.Clear()

        $rootLayout = New-Object System.Windows.Forms.TableLayoutPanel
        $rootLayout.Name = 'ModernRootLayout'
        $rootLayout.Dock = 'Fill'
        $rootLayout.BackColor = $script:ColorBg
        $rootLayout.ColumnCount = 2
        $rootLayout.RowCount = 1
        $null = $rootLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 200)))
        $null = $rootLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        $null = $rootLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        $form.Controls.Add($rootLayout)

        $sidebar = New-Object System.Windows.Forms.FlowLayoutPanel
        $sidebar.Name = 'ModernSidebar'
        $sidebar.Dock = 'Fill'
        $sidebar.FlowDirection = 'TopDown'
        $sidebar.WrapContents = $false
        $sidebar.AutoScroll = $true
        $sidebar.Padding = New-Object System.Windows.Forms.Padding(14, 18, 14, 14)
        $sidebar.Margin = New-Object System.Windows.Forms.Padding(0)
        $sidebar.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#08111F')
        $rootLayout.Controls.Add($sidebar, 0, 0)

        $brandBox = New-Object System.Windows.Forms.TableLayoutPanel
        $brandBox.Width = 172
        $brandBox.Height = 74
        $brandBox.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
        $brandBox.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#08111F')
        $brandBox.ColumnCount = 2
        $brandBox.RowCount = 2
        $null = $brandBox.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 44)))
        $null = $brandBox.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        $null = $brandBox.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        $null = $brandBox.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 20)))
        $sidebar.Controls.Add($brandBox)

        $brandDot = New-Object System.Windows.Forms.Label
        $brandDot.Text = 'G'
        $brandDot.TextAlign = 'MiddleCenter'
        $brandDot.Dock = 'Fill'
        $brandDot.Margin = New-Object System.Windows.Forms.Padding(0, 4, 10, 8)
        $brandDot.BackColor = $script:ColorAccent
        $brandDot.ForeColor = [System.Drawing.Color]::White
        $brandDot.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
        $brandBox.Controls.Add($brandDot, 0, 0)

        $brand = New-Object System.Windows.Forms.Label
        $brand.Text = "GStreamer`r`nGlass"
        $brand.Dock = 'Fill'
        $brand.Margin = New-Object System.Windows.Forms.Padding(0)
        $brand.ForeColor = $script:ColorText
        $brand.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
        $brandBox.Controls.Add($brand, 1, 0)

        $ver = New-Object System.Windows.Forms.Label
        $ver.Text = "v$script:AppVersion"
        $ver.Dock = 'Fill'
        $ver.Margin = New-Object System.Windows.Forms.Padding(0)
        $ver.ForeColor = $script:ColorMuted
        $ver.Font = New-Object System.Drawing.Font('Segoe UI', 8)
        $brandBox.Controls.Add($ver, 0, 1)
        $brandBox.SetColumnSpan($ver, 2)

        # Sidebar navigation mirrors the settings tab strip one-to-one (same names,
        # same order) plus the two bottom output views. The leading glyph is a real
        # Unicode symbol; Segoe UI on Windows 10+ resolves these through emoji/symbol
        # fallback, so no icon font or embedded image resources are required.
        $script:SidebarNavButtons = @{}

        $sidebar.Controls.Add((New-SidebarHeading 'Settings'))
        $script:SidebarNavButtons['Transport'] = New-SidebarButton "  $($script:Glyph.Transport)   Transport" 0 { if ($script:SettingsTabs -and $script:SettingsTabTransport) { $script:SettingsTabs.SelectedTab = $script:SettingsTabTransport } } $true
        $sidebar.Controls.Add($script:SidebarNavButtons['Transport'])
        $script:SidebarNavButtons['WebRtc'] = New-SidebarButton "  $($script:Glyph.WebRtc)   WebRTC" 0 { if ($script:SettingsTabs -and $script:SettingsTabWebRtc) { $script:SettingsTabs.SelectedTab = $script:SettingsTabWebRtc } }
        $sidebar.Controls.Add($script:SidebarNavButtons['WebRtc'])
        $script:SidebarNavButtons['Video'] = New-SidebarButton "  $($script:Glyph.Video)   Video" 0 { if ($script:SettingsTabs -and $script:SettingsTabVideo) { $script:SettingsTabs.SelectedTab = $script:SettingsTabVideo } }
        $sidebar.Controls.Add($script:SidebarNavButtons['Video'])
        $script:SidebarNavButtons['Scenes'] = New-SidebarButton "  $($script:Glyph.Scenes)   Scenes" 0 { if ($script:SettingsTabs -and $script:SettingsTabScenes) { $script:SettingsTabs.SelectedTab = $script:SettingsTabScenes } }
        $sidebar.Controls.Add($script:SidebarNavButtons['Scenes'])
        $script:SidebarNavButtons['Audio'] = New-SidebarButton "  $($script:Glyph.Audio)   Audio" 0 { if ($script:SettingsTabs -and $script:SettingsTabAudio) { $script:SettingsTabs.SelectedTab = $script:SettingsTabAudio } }
        $sidebar.Controls.Add($script:SidebarNavButtons['Audio'])
        $script:SidebarNavButtons['Player'] = New-SidebarButton "  $($script:Glyph.Player)   Player" 0 { if ($script:SettingsTabs -and $script:SettingsTabPlayer) { $script:SettingsTabs.SelectedTab = $script:SettingsTabPlayer } }
        $sidebar.Controls.Add($script:SidebarNavButtons['Player'])
        $script:SidebarNavButtons['Recording'] = New-SidebarButton "  $($script:Glyph.Recording)   Recording" 0 { if ($script:SettingsTabs -and $script:SettingsTabRecording) { $script:SettingsTabs.SelectedTab = $script:SettingsTabRecording } }
        $sidebar.Controls.Add($script:SidebarNavButtons['Recording'])
        $script:SidebarNavButtons['Network'] = New-SidebarButton "  $($script:Glyph.Network)   Network" 0 { if ($script:SettingsTabs -and $script:SettingsTabNetwork) { $script:SettingsTabs.SelectedTab = $script:SettingsTabNetwork } }
        $sidebar.Controls.Add($script:SidebarNavButtons['Network'])
        $script:SidebarNavButtons['Options'] = New-SidebarButton "  $($script:Glyph.Options)   Options" 0 { if ($script:SettingsTabs -and $script:SettingsTabOptions) { $script:SettingsTabs.SelectedTab = $script:SettingsTabOptions } }
        $sidebar.Controls.Add($script:SidebarNavButtons['Options'])
        $script:SidebarNavButtons['Profiles'] = New-SidebarButton "  $($script:Glyph.Profiles)   Profiles" 0 { if ($script:SettingsTabs -and $script:SettingsTabProfiles) { $script:SettingsTabs.SelectedTab = $script:SettingsTabProfiles } }
        $sidebar.Controls.Add($script:SidebarNavButtons['Profiles'])

        $sidebar.Controls.Add((New-SidebarHeading 'Output'))
        $script:SidebarNavButtons['Logs'] = New-SidebarButton "  $($script:Glyph.Logs)   Logs" 0 { $lowerTabs.SelectedTab = $tabLog }
        $sidebar.Controls.Add($script:SidebarNavButtons['Logs'])
        $script:SidebarNavButtons['Command'] = New-SidebarButton "  $($script:Glyph.Command)   Command" 0 { $lowerTabs.SelectedTab = $tabCommand }
        $sidebar.Controls.Add($script:SidebarNavButtons['Command'])

        $sidebarStatus = New-Object System.Windows.Forms.Label
        $sidebarStatus.Text = "$($script:Glyph.Ready) Ready"
        $script:SidebarStatusLabel = $sidebarStatus
        $sidebarStatus.AutoSize = $false
        $sidebarStatus.Width = 172
        $sidebarStatus.Height = 26
        $sidebarStatus.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
        $sidebarStatus.ForeColor = $script:ColorGood
        $sidebar.Controls.Add($sidebarStatus)

        $mainLayout = New-Object System.Windows.Forms.TableLayoutPanel
        $mainLayout.Name = 'ModernMainLayout'
        $mainLayout.Dock = 'Fill'
        $mainLayout.BackColor = $script:ColorBg
        $mainLayout.Margin = New-Object System.Windows.Forms.Padding(0)
        $mainLayout.ColumnCount = 1
        $mainLayout.RowCount = 3
        $null = $mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 58)))
        $null = $mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        $null = $mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 210)))
        $rootLayout.Controls.Add($mainLayout, 1, 0)

        $header = New-Object System.Windows.Forms.TableLayoutPanel
        $header.Name = 'ModernHeader'
        $header.Dock = 'Fill'
        $header.Margin = New-Object System.Windows.Forms.Padding(0)
        $header.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0B1220')
        $header.ColumnCount = 2
        $header.RowCount = 1
        $null = $header.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 420)))
        $null = $header.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        $null = $header.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        $mainLayout.Controls.Add($header, 0, 0)

        $headerTitle = New-Object System.Windows.Forms.Label
        $headerTitle.Text = 'Low-latency desktop streaming control'
        $headerTitle.Dock = 'Fill'
        $headerTitle.TextAlign = 'MiddleLeft'
        $headerTitle.Margin = New-Object System.Windows.Forms.Padding(20, 0, 0, 0)
        $headerTitle.ForeColor = $script:ColorMuted
        $headerTitle.Font = New-Object System.Drawing.Font('Segoe UI', 10)
        $header.Controls.Add($headerTitle, 0, 0)

        $statusLabel.Parent = $header
        $statusLabel.Dock = 'Fill'
        $statusLabel.Margin = New-Object System.Windows.Forms.Padding(0, 0, 20, 0)
        $statusLabel.TextAlign = 'MiddleLeft'
        $statusLabel.ForeColor = $script:ColorGood
        $statusLabel.BackColor = [System.Drawing.Color]::Transparent
        $header.Controls.Add($statusLabel, 1, 0)

        $dashboardLayout = New-Object System.Windows.Forms.TableLayoutPanel
        $dashboardLayout.Name = 'ModernDashboardLayout'
        $dashboardLayout.Dock = 'Fill'
        $dashboardLayout.BackColor = $script:ColorBg
        $dashboardLayout.Margin = New-Object System.Windows.Forms.Padding(10, 8, 10, 8)
        $dashboardLayout.ColumnCount = 2
        $dashboardLayout.RowCount = 2
        $null = $dashboardLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
        $null = $dashboardLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
        $null = $dashboardLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        $null = $dashboardLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 58)))
        $mainLayout.Controls.Add($dashboardLayout, 0, 1)
        $script:DashboardLayout = $dashboardLayout

        $previewGroup.Text = '  LIVE PREVIEW'
        $previewGroup.Dock = 'Fill'
        $previewGroup.Margin = New-Object System.Windows.Forms.Padding(10)
        $previewPanel.Dock = 'Fill'
        $previewPanel.Margin = New-Object System.Windows.Forms.Padding(12, 24, 12, 12)
        $previewPanel.BackColor = [System.Drawing.Color]::Black
        $previewPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $previewPlaceholder.BackColor = [System.Drawing.Color]::Black
        $previewPlaceholder.ForeColor = $script:ColorMuted
        $previewPlaceholder.Font = New-Object System.Drawing.Font('Segoe UI', 12)
        $dashboardLayout.Controls.Add($previewGroup, 0, 0)

        $settingsGroup.Text = '  STREAM SETTINGS'
        $settingsGroup.Dock = 'Fill'
        $settingsGroup.Margin = New-Object System.Windows.Forms.Padding(10)
        $dashboardLayout.Controls.Add($settingsGroup, 1, 0)

        $script:ModernActionFlow = New-Object System.Windows.Forms.FlowLayoutPanel
        $script:ModernActionFlow.Name = 'ModernActionFlow'
        $script:ModernActionFlow.Dock = 'Fill'
        $script:ModernActionFlow.FlowDirection = 'RightToLeft'
        $script:ModernActionFlow.WrapContents = $true
        $script:ModernActionFlow.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 6)
        $script:ModernActionFlow.Margin = New-Object System.Windows.Forms.Padding(10, 0, 10, 0)
        $script:ModernActionFlow.BackColor = $script:ColorBg
        $dashboardLayout.Controls.Add($script:ModernActionFlow, 0, 1)
        $dashboardLayout.SetColumnSpan($script:ModernActionFlow, 2)

        $lowerTabs.Dock = 'Fill'
        $lowerTabs.Margin = New-Object System.Windows.Forms.Padding(20, 0, 20, 12)
        $mainLayout.Controls.Add($lowerTabs, 0, 2)
    }
    finally {
        $form.ResumeLayout($false)
    }

    # Tabbed settings panes to stop horizontal overflow/clutter.
    $settingsTabs = New-Object System.Windows.Forms.TabControl
    $settingsTabs.Name = 'SettingsTabs'
    $settingsTabs.Dock = 'Fill'
    $settingsTabs.Margin = New-Object System.Windows.Forms.Padding(12, 24, 12, 12)
    $settingsGroup.Controls.Add($settingsTabs)

    # Tab captions stay plain text; the leading glyphs live in the sidebar. The two
    # navigations still read as the same list because the names match one-to-one and
    # in the same order. Keeping the strip text-only avoids a crowded/wrapping tab
    # row now that there are nine panes.
    $tabTransport = New-Object System.Windows.Forms.TabPage
    $tabTransport.Text = 'Transport'
    $tabTransport.AutoScroll = $true
    $tabWebRtc = New-Object System.Windows.Forms.TabPage
    $tabWebRtc.Text = 'WebRTC'
    $tabWebRtc.AutoScroll = $true
    $tabVideo = New-Object System.Windows.Forms.TabPage
    $tabVideo.Text = 'Video'
    $tabVideo.AutoScroll = $true
    $tabScenes = New-Object System.Windows.Forms.TabPage
    $tabScenes.Text = 'Scenes'
    $tabScenes.AutoScroll = $true
    $tabAudio = New-Object System.Windows.Forms.TabPage
    $tabAudio.Text = 'Audio'
    $tabAudio.AutoScroll = $true
    # Scroll extent is computed by WinForms from the AutoSize layout panels built
    # in the declarative layout section below. No AutoScrollMinSize needed.
    $tabPlayer = New-Object System.Windows.Forms.TabPage
    $tabPlayer.Text = 'Player'
    $tabPlayer.AutoScroll = $true
    $tabRecording = New-Object System.Windows.Forms.TabPage
    $tabRecording.Text = 'Recording'
    $tabRecording.AutoScroll = $true
    $tabNetwork = New-Object System.Windows.Forms.TabPage
    $tabNetwork.Text = 'Network'
    $tabNetwork.AutoScroll = $true
    $tabOptions = New-Object System.Windows.Forms.TabPage
    $tabOptions.Text = 'Options'
    $tabOptions.AutoScroll = $true
    $tabProfiles = New-Object System.Windows.Forms.TabPage
    $tabProfiles.Text = 'Profiles'
    $tabProfiles.AutoScroll = $true

    $settingsTabs.TabPages.AddRange(@($tabTransport, $tabWebRtc, $tabVideo, $tabScenes, $tabAudio, $tabPlayer, $tabRecording, $tabNetwork, $tabOptions, $tabProfiles))
    $script:SettingsTabs = $settingsTabs
    $script:SettingsTabTransport = $tabTransport
    $script:SettingsTabWebRtc = $tabWebRtc
    $script:SettingsTabVideo = $tabVideo
    $script:SettingsTabScenes = $tabScenes
    $script:SettingsTabAudio = $tabAudio
    $script:SettingsTabPlayer = $tabPlayer
    $script:SettingsTabRecording = $tabRecording
    $script:SettingsTabNetwork = $tabNetwork
    $script:SettingsTabOptions = $tabOptions
    $script:SettingsTabProfiles = $tabProfiles

    # Keep the sidebar highlight in sync with the active settings tab so the two
    # parallel navigations never disagree about where the user is.
    $settingsTabs.Add_SelectedIndexChanged({
        if ($script:SidebarNavButtons) {
            $map = @{
                0 = 'Transport'; 1 = 'WebRtc'; 2 = 'Video'; 3 = 'Scenes'; 4 = 'Audio';
                5 = 'Player'; 6 = 'Recording'; 7 = 'Network'; 8 = 'Options'; 9 = 'Profiles'
            }
            $activeKey = $map[$script:SettingsTabs.SelectedIndex]
            foreach ($entry in $script:SidebarNavButtons.GetEnumerator()) {
                $isActive = ($entry.Key -eq $activeKey)
                $entry.Value.BackColor = if ($isActive) {
                    [System.Drawing.ColorTranslator]::FromHtml('#17345C')
                } else {
                    [System.Drawing.ColorTranslator]::FromHtml('#0B1220')
                }
            }
        }
        Update-SceneWorkspaceMode
    })

    # ------------------------------------------------------------------
    # Declarative settings layout.
    #
    # Replaces the old two-pass scheme (build a whole GroupBox UI at absolute
    # coordinates, then reparent every control into a tab and re-position it with
    # ~180 more hardcoded coordinates, hiding the 52 original labels and creating
    # 102 replacements). Controls are now placed by WinForms layout panels:
    #
    #   TabPage -> pane (FlowLayoutPanel, TopDown, AutoScroll)
    #     section header label
    #     rows (FlowLayoutPanel, LeftToRight)
    #       field cell (TableLayoutPanel: label above control)
    #
    # Everything AutoSizes, so the scrollable extent is computed by WinForms from
    # real control bounds. That is DPI-correct for free and removes the whole
    # AutoScrollMinSize / clipping class of bug rather than patching it.
    #
    # Control WIDTHS are preserved from the old layout (they were tuned and are
    # real design intent). Only X/Y positions are dropped.
    # ------------------------------------------------------------------

    function New-SettingsPane {
        param([System.Windows.Forms.TabPage]$Tab)
        $pane = New-Object System.Windows.Forms.FlowLayoutPanel
        $pane.Dock = 'Fill'
        $pane.FlowDirection = 'TopDown'
        $pane.WrapContents = $false
        $pane.AutoScroll = $true
        $pane.Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 12)
        $pane.BackColor = $script:ColorSurface
        $Tab.Controls.Add($pane)
        return $pane
    }

    function Add-Section {
        param([System.Windows.Forms.FlowLayoutPanel]$Pane, [string]$Title)
        if (-not [string]::IsNullOrWhiteSpace($Title)) {
            $header = New-Object System.Windows.Forms.Label
            $header.Text = $Title.ToUpperInvariant()
            $header.AutoSize = $true
            $header.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
            $header.ForeColor = $script:ColorAccent
            $header.Margin = New-Object System.Windows.Forms.Padding(2, 12, 0, 4)
            $Pane.Controls.Add($header)
        }
        $section = New-Object System.Windows.Forms.FlowLayoutPanel
        $section.FlowDirection = 'TopDown'
        $section.WrapContents = $false
        $section.AutoSize = $true
        $section.AutoSizeMode = 'GrowAndShrink'
        $section.Margin = New-Object System.Windows.Forms.Padding(0)
        $Pane.Controls.Add($section)
        return $section
    }

    # A section whose body collapses behind a clickable chevron header. Returns the
    # same body panel Add-Section returns, so existing Add-Row/Add-Field calls are
    # unchanged -- the only difference is the header toggles the body's visibility.
    # Because the pane is a TopDown FlowLayoutPanel, hiding the body makes the pane
    # reflow and reclaim the vertical space, so a collapsed advanced group costs one
    # header line. Starts collapsed by default (simple-first: advanced stays folded
    # until asked for). Chevrons are BMP Geometric-Shapes glyphs (U+25B6/U+25BC),
    # which GDI font-links reliably; astral emoji would render as tofu here.
    function Add-CollapsibleSection {
        param(
            [System.Windows.Forms.FlowLayoutPanel]$Pane,
            [string]$Title,
            [bool]$Collapsed = $true
        )
        $chevronCollapsed = [char]::ConvertFromUtf32(0x25B6)
        $chevronExpanded  = [char]::ConvertFromUtf32(0x25BC)

        $header = New-Object System.Windows.Forms.Label
        $header.AutoSize = $true
        $header.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
        $header.ForeColor = $script:ColorAccent
        $header.Margin = New-Object System.Windows.Forms.Padding(2, 12, 0, 4)
        $header.Cursor = [System.Windows.Forms.Cursors]::Hand
        $Pane.Controls.Add($header)

        $section = New-Object System.Windows.Forms.FlowLayoutPanel
        $section.FlowDirection = 'TopDown'
        $section.WrapContents = $false
        $section.AutoSize = $true
        $section.AutoSizeMode = 'GrowAndShrink'
        $section.Margin = New-Object System.Windows.Forms.Padding(0)
        $Pane.Controls.Add($section)

        $titleText = $Title.ToUpperInvariant()
        # All state the click handler needs lives on the header's Tag, so the
        # handler can be a plain scriptblock reading its sender -- no closures.
        $header.Tag = @{
            Section   = $section
            Collapsed = $Collapsed
            Title     = $titleText
            ChevronC  = $chevronCollapsed
            ChevronE  = $chevronExpanded
        }

        if ($Collapsed) {
            $header.Text = "$chevronCollapsed  $titleText"
            $section.Visible = $false
        }
        else {
            $header.Text = "$chevronExpanded  $titleText"
            $section.Visible = $true
        }

        $header.Add_Click({
            param($sender, $eventArgs)
            $state = $sender.Tag
            $state.Collapsed = -not $state.Collapsed
            if ($state.Collapsed) {
                $sender.Text = "$($state.ChevronC)  $($state.Title)"
                $state.Section.Visible = $false
            }
            else {
                $sender.Text = "$($state.ChevronE)  $($state.Title)"
                $state.Section.Visible = $true
            }
            if ($state.Section.Parent) { $state.Section.Parent.PerformLayout() }
        })
        $header.Add_MouseEnter({ param($sender, $eventArgs) $sender.ForeColor = $script:ColorText })
        $header.Add_MouseLeave({ param($sender, $eventArgs) $sender.ForeColor = $script:ColorAccent })

        return $section
    }

    # A muted, non-interactive label that marks the boundary between the common
    # controls above it and the collapsible advanced groups below it.
    function Add-PaneDivider {
        param([System.Windows.Forms.FlowLayoutPanel]$Pane, [string]$Text = 'Advanced')
        $divider = New-Object System.Windows.Forms.Label
        $divider.Text = $Text.ToUpperInvariant()
        $divider.AutoSize = $true
        $divider.Font = New-Object System.Drawing.Font('Segoe UI', 7.5, [System.Drawing.FontStyle]::Bold)
        $divider.ForeColor = $script:ColorMuted
        $divider.Margin = New-Object System.Windows.Forms.Padding(2, 16, 0, 2)
        $Pane.Controls.Add($divider)
        return $divider
    }

    function Add-Row {
        param([System.Windows.Forms.FlowLayoutPanel]$Section)
        $row = New-Object System.Windows.Forms.FlowLayoutPanel
        $row.FlowDirection = 'LeftToRight'
        $row.WrapContents = $false
        $row.AutoSize = $true
        $row.AutoSizeMode = 'GrowAndShrink'
        $row.Margin = New-Object System.Windows.Forms.Padding(0)
        $Section.Controls.Add($row)
        return $row
    }

    function Add-Field {
        # -Label       static caption text
        # -LabelControl an existing Label control whose .Text is updated at runtime
        # -Control     the input control
        # -Width       explicit control width (preserved from the old layout)
        param(
            [System.Windows.Forms.FlowLayoutPanel]$Row,
            [string]$Label,
            [System.Windows.Forms.Control]$LabelControl,
            [Parameter(Mandatory)][System.Windows.Forms.Control]$Control,
            [int]$Width = 0
        )
        if ($null -eq $Control) { return }

        $cell = New-Object System.Windows.Forms.TableLayoutPanel
        $cell.ColumnCount = 1
        $cell.AutoSize = $true
        $cell.AutoSizeMode = 'GrowAndShrink'
        $cell.Margin = New-Object System.Windows.Forms.Padding(0, 0, 14, 8)

        $cap = $null
        if ($LabelControl) {
            $cap = $LabelControl
            $cap.AutoSize = $true
        }
        elseif (-not [string]::IsNullOrWhiteSpace($Label)) {
            $cap = New-Object System.Windows.Forms.Label
            $cap.Text = $Label
            $cap.AutoSize = $true
            $cap.ForeColor = $script:ColorMuted
        }

        if ($cap) {
            $cap.Margin = New-Object System.Windows.Forms.Padding(2, 0, 0, 2)
            $cell.RowCount = 2
            $cell.Controls.Add($cap, 0, 0)
            $cell.Controls.Add($Control, 0, 1)
        }
        else {
            $cell.RowCount = 1
            $cell.Controls.Add($Control, 0, 0)
        }

        if ($Width -gt 0) {
            $Control.Width = $Width
        }
        $Control.Margin = New-Object System.Windows.Forms.Padding(0)
        $Control.Anchor = 'Left'
        $Control.Visible = $true
        $Control.Enabled = $true

        $Row.Controls.Add($cell)
        return $cell
    }

    # Pull each control out of the legacy GroupBox before the panes claim it.
    function Detach-FromLegacyGroup {
        param([System.Windows.Forms.Control]$Control)
        if ($null -eq $Control) { return }
        try { $settingsGroup.Controls.Remove($Control) } catch {}
    }

    foreach ($legacy in @($settingsGroup.Controls)) {
        if ($legacy -ne $settingsTabs) { $settingsGroup.Controls.Remove($legacy) }
    }

    # ---------------- Transport ----------------
    # The Transport pane answers one question: "where does the stream go, and how
    # is it timed?" Protocol-specific WebRTC internals now live on their own WebRTC
    # pane; per-monitor capture options moved to the Video pane next to the capture
    # method they belong with.
    $paneTransport = New-SettingsPane $tabTransport

    $s = Add-Section $paneTransport 'Destination'
    $r = Add-Row $s
    Add-Field $r -Control $chkTransportEnabled -Width 180 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Protocol' -Control $cmbProtocol -Width 110 | Out-Null
    Add-Field $r -LabelControl $lblDestination -Control $txtDestination -Width 410 | Out-Null

    $s = Add-Section $paneTransport 'Clock signaling / timestamps'
    $r = Add-Row $s
    Add-Field $r -LabelControl $lblTimingMode -Control $cmbTimingMode -Width 225 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $lblTimestampStatus -Width 535 | Out-Null

    $s = Add-Section $paneTransport 'MediaMTX'
    $r = Add-Row $s
    Add-Field $r -Control $chkStartMediaMtx -Width 260 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'MediaMTX executable' -Control $txtMediaMtxPath -Width 430 | Out-Null
    Add-Field $r -Control $btnBrowseMediaMtx -Width 95 | Out-Null

    $s = Add-Section $paneTransport ''
    $r = Add-Row $s
    Add-Field $r -Control $btnResetTransport -Width 180 | Out-Null

    # ---------------- WebRTC ----------------
    # Everything here only applies when Protocol = "GST WebRTC" (Direct GStreamer
    # WebRTC). Update-DirectWebRtcUi enables/disables these controls by variable
    # reference, so relocating them to their own pane changes nothing functionally
    # while unburdening the Transport pane. Sub-sections group the ~30 controls by
    # concern instead of presenting one flat wall.
    $paneWebRtc = New-SettingsPane $tabWebRtc

    $s = Add-Section $paneWebRtc 'Signaling'
    $r = Add-Row $s
    Add-Field $r -Control $lblDirectWebRtcStatus -Width 535 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Signaling host' -Control $txtDirectWebRtcSignalingHost -Width 155 | Out-Null
    Add-Field $r -Label 'Video WS port' -Control $numDirectWebRtcSignalingPort -Width 85 | Out-Null
    Add-Field $r -Label 'Audio WS port' -Control $numDirectWebRtcSplitAudioSignalingPort -Width 85 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $chkDirectWebRtcSharedSignaling -Width 260 | Out-Null

    $s = Add-Section $paneWebRtc 'ICE / connectivity'
    $r = Add-Row $s
    Add-Field $r -Label 'STUN' -Control $txtDirectWebRtcStun -Width 270 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $chkDirectWebRtcTurnEnabled -Width 165 | Out-Null
    Add-Field $r -Label 'TURN URI' -Control $txtDirectWebRtcTurn -Width 360 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Bundle policy' -Control $cmbDirectWebRtcBundlePolicy -Width 145 | Out-Null
    Add-Field $r -Label 'Internal RTP MTU (0=default)' -Control $numDirectWebRtcInternalRtpMtu -Width 85 | Out-Null
    Add-Field $r -Control $chkDirectWebRtcInternalRepeatHeaders -Width 250 | Out-Null

    $s = Add-Section $paneWebRtc 'A/V pipeline topology'
    $r = Add-Row $s
    Add-Field $r -Label 'A/V pipeline topology' -Control $cmbDirectWebRtcAvPipelineMode -Width 310 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $chkSplitClockSignalingOverrides -Width 320 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Video pipeline clock signaling' -Control $cmbSplitVideoClockSignaling -Width 220 | Out-Null
    Add-Field $r -Label 'Audio pipeline clock signaling' -Control $cmbSplitAudioClockSignaling -Width 220 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'A/V MediaStream grouping' -Control $cmbDirectWebRtcMediaStreamGrouping -Width 315 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Video MediaStream ID' -Control $txtDirectWebRtcVideoMediaStreamId -Width 180 | Out-Null
    Add-Field $r -Label 'Audio MediaStream ID' -Control $txtDirectWebRtcAudioMediaStreamId -Width 180 | Out-Null

    $s = Add-Section $paneWebRtc 'Unified publisher / RTP bridge'
    $r = Add-Row $s
    Add-Field $r -Control $chkDirectWebRtcUnifiedPublisher -Width 360 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Video RTP bridge' -Control $numDirectWebRtcBridgeVideoPort -Width 85 | Out-Null
    Add-Field $r -Label 'Audio RTP bridge' -Control $numDirectWebRtcBridgeAudioPort -Width 85 | Out-Null
    Add-Field $r -Label 'Bridge JBUF ms (0=off)' -Control $numDirectWebRtcBridgeJitterMs -Width 75 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Publisher queue ms (0=off)' -Control $numDirectWebRtcPublisherQueueMs -Width 75 | Out-Null
    Add-Field $r -Control $chkDirectWebRtcAudioBridgePacing -Width 310 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $chkDirectWebRtcControlDataChannel -Width 315 | Out-Null

    $s = Add-Section $paneWebRtc 'Congestion / recovery'
    $r = Add-Row $s
    Add-Field $r -Label 'Congestion' -Control $cmbDirectWebRtcCongestion -Width 110 | Out-Null
    Add-Field $r -Label 'Mitigation' -Control $cmbDirectWebRtcMitigation -Width 170 | Out-Null
    $r = Add-Row $s
    Add-Field $r -LabelControl $lblWebRtcRecoveryMode -Control $cmbWebRtcRecoveryMode -Width 135 | Out-Null
    Add-Field $r -LabelControl $lblDirectWebRtcSmoothnessProfile -Control $cmbDirectWebRtcSmoothnessProfile -Width 155 | Out-Null

    $s = Add-Section $paneWebRtc ''
    $r = Add-Row $s
    Add-Field $r -Control $btnResetWebRtcSane -Width 210 | Out-Null

    # Non-user-facing controls that must stay alive because other code reads them:
    #   chkDirectWebRtcFec / chkDirectWebRtcRetransmission - read by Build-GstArguments;
    #     webrtcsink owns the actual negotiation.
    #   chkFullscreenApp - legacy compatibility flag, superseded by the Capture
    #     method dropdown, kept in sync by Sync-LegacyFullscreenFlag.
    #   chkSendAbsoluteTimestamps - legacy, read by Test-SendAbsoluteTimestampsEnabled.
    # The old layout "hid" the first three by parking them at negative coordinates,
    # which kept them in the layout and in the scrolled extent. Hidden is hidden.
    foreach ($hidden in @(
        $chkDirectWebRtcFec,
        $chkDirectWebRtcRetransmission,
        $chkFullscreenApp,
        $chkSendAbsoluteTimestamps
    )) {
        if ($hidden) {
            Detach-FromLegacyGroup $hidden
            $tabTransport.Controls.Add($hidden)
            $hidden.Visible = $false
            $hidden.TabStop = $false
        }
    }

    # ---------------- Video ----------------
    $paneVideo = New-SettingsPane $tabVideo

    # Common (every-session) controls first.
    $s = Add-Section $paneVideo 'Capture'
    $r = Add-Row $s
    Add-Field $r -Label 'Capture method' -Control $cmbCaptureMethod -Width 260 | Out-Null
    Add-Field $r -Control $lblCaptureModeStatus -Width 260 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Monitor' -Control $numMonitor -Width 70 | Out-Null
    Add-Field $r -Control $chkCursor -Width 100 | Out-Null
    Add-Field $r -LabelControl $lblCaptureQueueBuffers -Control $numCaptureQueueBuffers -Width 90 | Out-Null

    $s = Add-Section $paneVideo 'Encoder'
    $r = Add-Row $s
    Add-Field $r -Label 'Encoder' -Control $cmbEncoder -Width 370 | Out-Null
    Add-Field $r -Control $lblEncoderStatus -Width 160 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Rate control' -Control $cmbRateControl -Width 105 | Out-Null
    Add-Field $r -Label 'Tune' -Control $cmbEncoderTune -Width 170 | Out-Null
    Add-Field $r -Label 'Multipass' -Control $cmbMultipass -Width 155 | Out-Null

    $s = Add-Section $paneVideo 'Format'
    $r = Add-Row $s
    Add-Field $r -Label 'Width' -Control $numWidth -Width 90 | Out-Null
    Add-Field $r -Label 'Height' -Control $numHeight -Width 90 | Out-Null
    Add-Field $r -Label 'FPS' -Control $numFps -Width 80 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Encoder bitrate kbps' -Control $numVideoBitrate -Width 110 | Out-Null
    Add-Field $r -Label 'Max kbps (WebRTC cap)' -Control $numMaxVideoBitrate -Width 100 | Out-Null
    Add-Field $r -Label 'WebRTC start kbps' -Control $numDirectWebRtcStartBitrateKbps -Width 105 | Out-Null
    Add-Field $r -Label 'WebRTC min kbps' -Control $numDirectWebRtcMinBitrateKbps -Width 105 | Out-Null
    Add-Field $r -Label 'CQ/QP' -Control $numConstantQp -Width 70 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Preset' -Control $cmbPreset -Width 120 | Out-Null
    Add-Field $r -Label 'Profile' -Control $cmbProfile -Width 170 | Out-Null

    # Advanced (set-once) controls below, folded by default.
    Add-PaneDivider $paneVideo 'Advanced' | Out-Null

    $s = Add-CollapsibleSection $paneVideo 'Encoded sender queue'
    $r = Add-Row $s
    Add-Field $r -LabelControl $lblWebRtcSenderQueueMode -Control $cmbWebRtcSenderQueueMode -Width 180 | Out-Null
    Add-Field $r -LabelControl $lblDirectWebRtcPacingMs -Control $numDirectWebRtcPacingMs -Width 90 | Out-Null

    $s = Add-CollapsibleSection $paneVideo 'Clock / timing'
    $r = Add-Row $s
    Add-Field $r -Label 'Pipeline master clock' -Control $cmbVideoPipelineClockMode -Width 235 | Out-Null
    Add-Field $r -Label 'Video timestamps' -Control $cmbVideoTimestampMode -Width 220 | Out-Null
    Add-Field $r -Label 'Video sync mode' -Control $cmbVideoSyncMode -Width 130 | Out-Null

    $s = Add-CollapsibleSection $paneVideo 'Keyframes'
    $r = Add-Row $s
    Add-Field $r -Label 'GOP sec' -Control $numGopSeconds -Width 80 | Out-Null
    Add-Field $r -Control $chkUnifiedBridgeKeyframeGuard -Width 260 | Out-Null
    Add-Field $r -Label 'Interval ms' -Control $numUnifiedBridgeKeyframeIntervalMs -Width 90 | Out-Null

    $s = Add-CollapsibleSection $paneVideo 'Quality tuning'
    $r = Add-Row $s
    Add-Field $r -Label 'B-frames' -Control $numBFrames -Width 80 | Out-Null
    Add-Field $r -Control $chkLookAhead -Width 110 | Out-Null
    Add-Field $r -Label 'Frames' -Control $numLookAheadFrames -Width 80 | Out-Null
    Add-Field $r -Control $chkAdaptiveQuantization -Width 95 | Out-Null
    Add-Field $r -Control $chkTemporalAq -Width 105 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'AQ strength' -Control $numAqStrength -Width 80 | Out-Null
    Add-Field $r -Label 'VBV kbits' -Control $numVbvBuffer -Width 100 | Out-Null
    Add-Field $r -Label 'SRT latency ms' -Control $numSrtLatency -Width 90 | Out-Null
    Add-Field $r -Label 'RTSP mode' -Control $cmbRtspTransport -Width 80 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Custom encoder options' -Control $txtCustomEncoderOptions -Width 535 | Out-Null

    $s = Add-Section $paneVideo ''
    $r = Add-Row $s
    Add-Field $r -Control $btnResetVideo -Width 160 | Out-Null

    # ---------------- Scenes ----------------
    $paneScenes = New-SettingsPane $tabScenes
    $script:SceneSettingsPane = $paneScenes
    $s = Add-Section $paneScenes 'Scene editor'
    $r = Add-Row $s
    Add-Field $r -Label 'Sources' -Control $sceneSourcePalette -Width 550 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $btnRedrawScenePreview -Width 130 | Out-Null
    Add-Field $r -Control $chkDynamicScenePreviews -Width 150 | Out-Null
    Add-Field $r -Control $chkStandardPreviewOffSceneTab -Width 190 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $chkLiveSceneEditing -Width 260 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $sceneEditorCanvas -Width 550 | Out-Null
    Save-SceneEditorCanvasHome
    $r = Add-Row $s
    Add-Field $r -Control $lblSceneEditorHint -Width 550 | Out-Null

    $s = Add-Section $paneScenes 'Experimental scene engine'
    $r = Add-Row $s
    Add-Field $r -Control $chkSceneEnabled -Width 300 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Scene preset' -Control $cmbScenePreset -Width 190 | Out-Null
    Add-Field $r -Label 'Compositor' -Control $cmbSceneCompositor -Width 190 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $lblSceneStatus -Width 540 | Out-Null

    $s = Add-Section $paneScenes 'Scene input queues'
    $r = Add-Row $s
    Add-Field $r -Label 'Input q buffers' -Control $numSceneInputQueueBuffers -Width 90 | Out-Null
    Add-Field $r -Label 'Input queue cap ms' -Control $numSceneInputQueueCapMs -Width 110 | Out-Null

    $s = Add-Section $paneScenes 'Webcam source'
    $r = Add-Row $s
    Add-Field $r -Label 'Camera' -Control $cmbWebcamDevice -Width 330 | Out-Null
    Add-Field $r -Control $btnRefreshWebcams -Width 125 | Out-Null
    Add-Field $r -Label 'Capture FPS' -Control $numWebcamFps -Width 75 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Layout' -Control $cmbWebcamLayout -Width 150 | Out-Null
    Add-Field $r -Control $chkWebcamMirror -Width 125 | Out-Null
    Add-Field $r -Label 'Opacity %' -Control $numWebcamOpacity -Width 75 | Out-Null
    Add-Field $r -Label 'Border px (concept)' -Control $numWebcamBorder -Width 75 | Out-Null

    $s = Add-Section $paneScenes 'Webcam geometry'
    $r = Add-Row $s
    Add-Field $r -Label 'Width' -Control $numWebcamWidth -Width 80 | Out-Null
    Add-Field $r -Label 'Height' -Control $numWebcamHeight -Width 80 | Out-Null
    Add-Field $r -Label 'X' -Control $numWebcamX -Width 80 | Out-Null
    Add-Field $r -Label 'Y' -Control $numWebcamY -Width 80 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $chkWebcamAspectLock -Width 140 | Out-Null

    $s = Add-Section $paneScenes 'Generated scene capture chain'
    $r = Add-Row $s
    Add-Field $r -Control $txtScenePipeline -Width 550 | Out-Null
    $paneScenes.Add_SizeChanged({ Resize-LiveSceneCanvas })
    $tabScenes.Add_Enter({ Update-SceneWorkspaceMode })

    # ---------------- Audio ----------------
    $paneAudio = New-SettingsPane $tabAudio

    # Common (every-session) controls first: what you capture and how it's coded.
    $s = Add-Section $paneAudio 'Sources'
    $r = Add-Row $s
    Add-Field $r -Control $chkDesktopAudio -Width 180 | Out-Null
    Add-Field $r -Label 'Desktop volume' -Control $numDesktopVolume -Width 90 | Out-Null
    Add-Field $r -Control $chkAudioMixerMode -Width 255 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Desktop device' -Control $cmbDesktopAudioDevice -Width 420 | Out-Null
    Add-Field $r -Control $btnRefreshAudioDevices -Width 160 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $chkMic -Width 180 | Out-Null
    Add-Field $r -Label 'Mic volume' -Control $numMicVolume -Width 90 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Mic device' -Control $cmbMicAudioDevice -Width 420 | Out-Null
    Add-Field $r -Control $lblAudioDeviceStatus -Width 260 | Out-Null

    $s = Add-Section $paneAudio 'Audio codec'
    $r = Add-Row $s
    Add-Field $r -Label 'Codec' -Control $cmbAudioCodec -Width 250 | Out-Null
    Add-Field $r -Control $lblAudioCodecStatus -Width 260 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Audio kbps' -Control $numAudioBitrate -Width 110 | Out-Null

    # Advanced (set-once) controls below, folded by default.
    Add-PaneDivider $paneAudio 'Advanced' | Out-Null

    $s = Add-CollapsibleSection $paneAudio 'Clock / timing'
    $r = Add-Row $s
    Add-Field $r -Label 'A/V test mode' -Control $cmbAudioTransportMode -Width 270 | Out-Null
    Add-Field $r -Label 'Split audio pipeline clock' -Control $cmbSplitAudioPipelineClockMode -Width 235 | Out-Null
    $r = Add-Row $s
    Add-Field $r -LabelControl $lblAudioClockMode -Control $cmbAudioClockMode -Width 230 | Out-Null
    Add-Field $r -Control $chkWasapiLowLatencyOverride -Width 190 | Out-Null
    $r = Add-Row $s
    Add-Field $r -LabelControl $lblAudioTimingMode -Control $cmbAudioTimingMode -Width 270 | Out-Null
    Add-Field $r -LabelControl $lblAudioSlaveMethod -Control $cmbAudioSlaveMethod -Width 180 | Out-Null
    Add-Field $r -Label 'Audio sync mode' -Control $cmbAudioSyncMode -Width 130 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $chkAudioBufferOverride -Width 165 | Out-Null
    Add-Field $r -LabelControl $lblAudioBufferMs -Control $numAudioBufferMs -Width 80 | Out-Null
    Add-Field $r -Control $chkAudioLatencyOverride -Width 165 | Out-Null
    Add-Field $r -LabelControl $lblAudioLatencyMs -Control $numAudioLatencyMs -Width 80 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $chkAudioSampleRateOverride -Width 175 | Out-Null
    Add-Field $r -LabelControl $lblAudioSampleRate -Control $numAudioSampleRate -Width 115 | Out-Null

    $s = Add-CollapsibleSection $paneAudio 'Audio queues'
    $r = Add-Row $s
    Add-Field $r -LabelControl $lblAudioQueueBuffers -Control $numAudioQueueBuffers -Width 90 | Out-Null
    Add-Field $r -LabelControl $lblAudioQueueCapMs -Control $numAudioQueueCapMs -Width 100 | Out-Null

    $s = Add-CollapsibleSection $paneAudio 'Direct GST WebRTC Opus'
    $r = Add-Row $s
    Add-Field $r -Label 'Opus mode' -Control $cmbDirectWebRtcOpusMode -Width 190 | Out-Null
    Add-Field $r -Label 'Frame ms' -Control $cmbDirectWebRtcOpusFrameMs -Width 80 | Out-Null
    Add-Field $r -Label 'Audio type' -Control $cmbDirectWebRtcOpusAudioType -Width 170 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $chkDirectWebRtcOpusFec -Width 110 | Out-Null
    Add-Field $r -Control $chkDirectWebRtcOpusDtx -Width 110 | Out-Null

    $s = Add-Section $paneAudio ''
    $r = Add-Row $s
    Add-Field $r -Control $btnResetAudio -Width 160 | Out-Null

    # ---------------- Player ----------------
    $panePlayer = New-SettingsPane $tabPlayer

    $s = Add-Section $panePlayer 'Browser / player jitter buffer'
    $r = Add-Row $s
    Add-Field $r -LabelControl $lblDirectWebRtcPlayerJitterMs -Control $numDirectWebRtcPlayerJitterMs -Width 90 | Out-Null
    Add-Field $r -LabelControl $lblDirectWebRtcVideoJitterMs -Control $numDirectWebRtcVideoJitterMs -Width 90 | Out-Null
    Add-Field $r -LabelControl $lblJbufMaxMs -Control $numJbufMaxMs -Width 90 | Out-Null
    Add-Field $r -LabelControl $lblJbufWatchdogMode -Control $cmbJbufWatchdogMode -Width 150 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $chkPlayerStatsOverlay -Width 150 | Out-Null
    Add-Field $r -Control $chkPlayerJbufDebug -Width 180 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Live avg sec' -Control $numLiveEdgeAverageSec -Width 90 | Out-Null
    Add-Field $r -Label 'Green <= ms' -Control $numLiveEdgeGreenMs -Width 100 | Out-Null
    Add-Field $r -Label 'Yellow <= ms' -Control $numLiveEdgeYellowMs -Width 105 | Out-Null

    $s = Add-Section $panePlayer 'Player A/V rendering'
    $r = Add-Row $s
    Add-Field $r -Control $chkPlayerSeparateHtmlMediaElements -Width 365 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Split sync mode' -Control $cmbSplitPlayerSyncMode -Width 235 | Out-Null
    Add-Field $r -Label 'Audio stall sec' -Control $numSplitAudioStallSeconds -Width 95 | Out-Null
    Add-Field $r -Label 'Watchdog warmup sec' -Control $numSplitAudioWarmupSeconds -Width 140 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Offset baseline ms' -Control $numSplitAvOffsetBaselineMs -Width 130 | Out-Null
    Add-Field $r -Label 'Offset drift warn ms' -Control $numSplitAvOffsetWarnMs -Width 140 | Out-Null

    $s = Add-Section $panePlayer 'Web player hosting'
    $r = Add-Row $s
    Add-Field $r -Label 'URL path' -Control $txtDirectWebRtcWebPath -Width 135 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Bundled source' -Control $cmbDirectWebRtcBundledWebMode -Width 180 | Out-Null
    Add-Field $r -Label 'Bundled directory' -Control $txtDirectWebRtcBundledWebDirectory -Width 245 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $btnBrowseDirectWebRtcBundledWebDirectory -Width 105 | Out-Null
    Add-Field $r -Control $btnDetectDirectWebRtcBundledWebDirectory -Width 110 | Out-Null
    Add-Field $r -Control $btnOpenDirectWebRtcBundledDir -Width 135 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Working / served mode' -Control $cmbDirectWebRtcWorkingWebMode -Width 160 | Out-Null
    Add-Field $r -Label 'Working / served dir' -Control $txtDirectWebRtcWebDirectory -Width 265 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $btnBrowseDirectWebRtcWebDirectory -Width 105 | Out-Null
    Add-Field $r -Control $btnDetectDirectWebRtcWebDirectory -Width 110 | Out-Null
    Add-Field $r -Control $btnRefreshDirectWebRtcWebUi -Width 125 | Out-Null
    Add-Field $r -Control $btnOpenDirectWebRtcServedDir -Width 130 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $lblDirectWebRtcWebUiStatus -Width 550 | Out-Null

    $s = Add-Section $panePlayer 'Viewer launch'
    $r = Add-Row $s
    Add-Field $r -Control $chkPlayerUrlOverrides -Width 240 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $btnOpenDirectWebRtcViewer -Width 130 | Out-Null
    Add-Field $r -Control $btnCopyDirectWebRtcViewer -Width 105 | Out-Null

    # ---------------- Recording ----------------
    $paneRecording = New-SettingsPane $tabRecording

    $s = Add-Section $paneRecording 'Recording'
    $r = Add-Row $s
    Add-Field $r -Control $chkRecordingEnabled -Width 170 | Out-Null
    Add-Field $r -Control $chkRecordWithStream -Width 170 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Output folder' -Control $txtRecordingDirectory -Width 425 | Out-Null
    Add-Field $r -Control $btnBrowseRecordingDirectory -Width 95 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'File name template' -Control $txtRecordingTemplate -Width 535 | Out-Null

    $s = Add-Section $paneRecording 'Recording encoder'
    $r = Add-Row $s
    Add-Field $r -Label 'Encoder' -Control $cmbRecordingEncoder -Width 360 | Out-Null
    Add-Field $r -Control $lblRecordingStatus -Width 160 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Rate control' -Control $cmbRecordingRateControl -Width 100 | Out-Null
    Add-Field $r -Label 'Video kbps' -Control $numRecordingVideoBitrate -Width 110 | Out-Null
    Add-Field $r -Label 'Max kbps' -Control $numRecordingMaxVideoBitrate -Width 105 | Out-Null
    Add-Field $r -Label 'CQ/QP' -Control $numRecordingConstantQp -Width 75 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Width' -Control $numRecordingWidth -Width 90 | Out-Null
    Add-Field $r -Label 'Height' -Control $numRecordingHeight -Width 90 | Out-Null
    Add-Field $r -Label 'FPS' -Control $numRecordingFps -Width 80 | Out-Null
    Add-Field $r -Label 'GOP sec' -Control $numRecordingGopSeconds -Width 80 | Out-Null
    Add-Field $r -Label 'B-frames' -Control $numRecordingBFrames -Width 80 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Preset' -Control $cmbRecordingPreset -Width 100 | Out-Null
    Add-Field $r -Label 'Profile' -Control $cmbRecordingProfile -Width 150 | Out-Null
    Add-Field $r -Label 'Tune' -Control $cmbRecordingTune -Width 170 | Out-Null
    Add-Field $r -Label 'Multipass' -Control $cmbRecordingMultipass -Width 150 | Out-Null

    $s = Add-Section $paneRecording 'Quality tuning'
    $r = Add-Row $s
    Add-Field $r -Control $chkRecordingLookAhead -Width 105 | Out-Null
    Add-Field $r -Label 'Frames' -Control $numRecordingLookAheadFrames -Width 70 | Out-Null
    Add-Field $r -Control $chkRecordingSpatialAq -Width 90 | Out-Null
    Add-Field $r -Control $chkRecordingTemporalAq -Width 105 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'AQ strength' -Control $numRecordingAqStrength -Width 80 | Out-Null
    Add-Field $r -Label 'VBV kbits' -Control $numRecordingVbvBuffer -Width 100 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Custom encoder options' -Control $txtRecordingCustomEncoderOptions -Width 535 | Out-Null

    $s = Add-Section $paneRecording 'Recording audio'
    $r = Add-Row $s
    Add-Field $r -Control $chkRecordingDesktopAudio -Width 170 | Out-Null
    Add-Field $r -Control $chkRecordingMic -Width 160 | Out-Null
    Add-Field $r -Label 'Audio kbps' -Control $numRecordingAudioBitrate -Width 100 | Out-Null

    $s = Add-Section $paneRecording ''
    $r = Add-Row $s
    Add-Field $r -Control $btnResetRecording -Width 170 | Out-Null

    # ---------------- Network ----------------
    $paneNetwork = New-SettingsPane $tabNetwork

    $s = Add-Section $paneNetwork 'Windows / network tuning'
    $r = Add-Row $s
    Add-Field $r -Control $chkNetworkTuningEnabled -Width 310 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Adapter' -Control $cmbNetworkAdapter -Width 405 | Out-Null
    Add-Field $r -Control $btnRefreshNetworkAdapters -Width 90 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'Profile' -Control $cmbNetworkProfile -Width 180 | Out-Null

    $s = Add-Section $paneNetwork 'QoS / DSCP'
    $r = Add-Row $s
    Add-Field $r -Control $chkNetworkDscp -Width 195 | Out-Null
    Add-Field $r -Label 'DSCP' -Control $numNetworkDscp -Width 65 | Out-Null
    Add-Field $r -Label 'Protocol' -Control $cmbNetworkQosProtocol -Width 80 | Out-Null
    Add-Field $r -Label 'Dst port/range' -Control $txtNetworkPorts -Width 120 | Out-Null

    $s = Add-Section $paneNetwork 'UDP global offloads'
    $r = Add-Row $s
    Add-Field $r -Label 'USO' -Control $cmbNetworkUso -Width 125 | Out-Null
    Add-Field $r -Label 'URO' -Control $cmbNetworkUro -Width 125 | Out-Null

    $s = Add-Section $paneNetwork 'Adapter low-latency switches'
    $r = Add-Row $s
    Add-Field $r -Control $chkNetworkDisablePowerSaving -Width 220 | Out-Null
    Add-Field $r -Label 'Interrupt moderation' -Control $cmbNetworkInterruptModeration -Width 150 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $chkNetworkDisableEee -Width 220 | Out-Null

    $s = Add-Section $paneNetwork 'Recovery'
    $r = Add-Row $s
    Add-Field $r -Control $chkNetworkRestoreOnStop -Width 240 | Out-Null
    Add-Field $r -Control $chkNetworkRestoreOnExit -Width 220 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $chkNetworkRecoveryTask -Width 300 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $lblNetworkStatus -Width 520 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $btnNetworkSnapshot -Width 90 | Out-Null
    Add-Field $r -Control $btnNetworkApply -Width 90 | Out-Null
    Add-Field $r -Control $btnNetworkRestore -Width 130 | Out-Null
    Add-Field $r -Control $btnOpenNetworkRecovery -Width 170 | Out-Null

    $s = Add-Section $paneNetwork ''
    $r = Add-Row $s
    Add-Field $r -Control $btnResetNetwork -Width 190 | Out-Null

    # ---------------- Options ----------------
    $paneOptions = New-SettingsPane $tabOptions

    $s = Add-Section $paneOptions 'GStreamer executable'
    $r = Add-Row $s
    Add-Field $r -Label 'gst-launch-1.0.exe' -Control $txtGstPath -Width 360 | Out-Null
    Add-Field $r -Control $btnBrowseGst -Width 75 | Out-Null
    Add-Field $r -Control $btnDetectGst -Width 80 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $btnCheckGst -Width 110 | Out-Null

    $s = Add-Section $paneOptions 'General'
    $r = Add-Row $s
    Add-Field $r -Control $chkPreview -Width 180 | Out-Null
    Add-Field $r -Control $chkHidePreviewDuringStream -Width 210 | Out-Null
    Add-Field $r -Control $chkAutoRestart -Width 170 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $chkVerbose -Width 145 | Out-Null
    Add-Field $r -Control $chkDiskProcessLogging -Width 210 | Out-Null
    Add-Field $r -Control $chkMinimizeToTray -Width 160 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $chkStartMinimized -Width 170 | Out-Null

    $s = Add-Section $paneOptions 'Runtime / threading'
    $r = Add-Row $s
    Add-Field $r -LabelControl $lblThreadingProfile -Control $cmbThreadingProfile -Width 165 | Out-Null
    Add-Field $r -LabelControl $lblGstProcessPriority -Control $cmbGstProcessPriority -Width 120 | Out-Null
    Add-Field $r -LabelControl $lblQueueLeakMode -Control $cmbQueueLeakMode -Width 180 | Out-Null
    $r = Add-Row $s
    Add-Field $r -LabelControl $lblThreadBudget -Control $cmbThreadBudget -Width 130 | Out-Null
    Add-Field $r -LabelControl $lblCpuWorkerLimit -Control $numCpuWorkerLimit -Width 80 | Out-Null
    Add-Field $r -Control $lblLiveGstThreads -Width 230 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $chkBudgetCaptureQueue -Width 175 | Out-Null
    Add-Field $r -Control $chkBudgetSenderQueue -Width 175 | Out-Null
    Add-Field $r -Control $chkBudgetAudioInputQueue -Width 145 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $chkBudgetAudioFinalQueue -Width 155 | Out-Null
    Add-Field $r -Control $chkBudgetSceneInputQueues -Width 155 | Out-Null
    $chkBudgetSceneInputQueues.Checked = $true
    $chkBudgetSceneInputQueues.Enabled = $false
    $r = Add-Row $s
    Add-Field $r -Control $chkBufferLatenessTracer -Width 190 | Out-Null

    $s = Add-Section $paneOptions 'GStreamer diagnostics'
    $r = Add-Row $s
    Add-Field $r -LabelControl $lblGstDebugMode -Control $cmbGstDebugMode -Width 170 | Out-Null
    Add-Field $r -LabelControl $lblGstDebugSpec -Control $txtGstDebugSpec -Width 185 | Out-Null
    Add-Field $r -Control $chkGstDebugNoColor -Width 135 | Out-Null

    $s = Add-Section $paneOptions 'Lab configuration'
    $r = Add-Row $s
    Add-Field $r -Control $btnExportLabConfig -Width 180 | Out-Null

    $s = Add-Section $paneOptions ''
    $r = Add-Row $s
    Add-Field $r -Control $btnResetOptions -Width 160 | Out-Null
    Add-Field $r -Control $btnResetAll -Width 160 | Out-Null

    $paneProfiles = New-SettingsPane $tabProfiles
    $s = Add-Section $paneProfiles 'Profile'
    $r = Add-Row $s
    Add-Field $r -Label 'Profile' -Control $cmbProfilePreset -Width 260 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $lblProfileDescription -Width 560 | Out-Null

    $s = Add-Section $paneProfiles 'Manage'
    $r = Add-Row $s
    Add-Field $r -Control $btnLoadProfile -Width 140 | Out-Null
    Add-Field $r -Control $btnSaveProfile -Width 140 | Out-Null
    Add-Field $r -Control $btnSaveProfileAs -Width 140 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Control $btnDeleteProfile -Width 140 | Out-Null
    Add-Field $r -Control $btnExportProfile -Width 140 | Out-Null
    Add-Field $r -Control $btnImportProfile -Width 140 | Out-Null

    foreach ($tp in @($tabTransport, $tabWebRtc, $tabVideo, $tabAudio, $tabPlayer, $tabRecording, $tabNetwork, $tabOptions, $tabProfiles)) {
        $tp.BackColor = $script:ColorSurface
        $tp.ForeColor = $script:ColorText
    }

    # Action row.
    # Buttons live in ModernActionFlow. The flow panel owns placement and wraps
    # if the window is narrowed, so this row no longer depends on hardcoded X/Y.
    $btnStart.Text = "$($script:Glyph.Start)  Start"
    $btnStart.Width = 145
    $btnStart.Height = 42
    $btnStart.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
    $btnStart.BackColor = $script:ColorAccent
    $btnStart.ForeColor = [System.Drawing.Color]::White
    $btnStart.FlatAppearance.BorderSize = 0

    # f78 replaces the separate Start + gated Stop pair with one always-available
    # stream toggle. Keep the legacy control allocated so old event wiring cannot
    # dereference null, but never place or display it in the action row.
    $btnStop.Visible = $false
    $btnStop.TabStop = $false

    $btnToggleRecording.Text = "$($script:Glyph.Recording)  Record"
    $btnToggleRecording.Width = 155
    $btnToggleRecording.Height = 42
    $btnToggleRecording.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)

    $btnRestart.Text = "$($script:Glyph.Restart)  Restart"
    $btnRestart.Width = 130
    $btnRestart.Height = 42
    $btnRestart.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)

    $btnCopyCommand.Text = "$($script:Glyph.Copy)  Copy"
    $btnCopyCommand.Width = 100
    $btnCopyCommand.Height = 42
    $btnCopyCommand.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)

    $btnClearLog.Text = "$($script:Glyph.Clear)  Clear"
    $btnClearLog.Width = 95
    $btnClearLog.Height = 42
    $btnClearLog.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)

    $btnOpenLogs.Text = "$($script:Glyph.OpenLogs)  Logs"
    $btnOpenLogs.Width = 90
    $btnOpenLogs.Height = 42
    $btnOpenLogs.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)

    if ($script:ModernActionFlow) {
        foreach ($btn in @($btnOpenLogs, $btnClearLog, $btnCopyCommand, $btnRestart, $btnToggleRecording, $btnStart)) {
            if ($btn -and $btn.Parent -ne $script:ModernActionFlow) {
                $script:ModernActionFlow.Controls.Add($btn)
            }
        }
        if ($btnStop.Parent -eq $script:ModernActionFlow) {
            $script:ModernActionFlow.Controls.Remove($btnStop)
        }
    }

    # Bottom output.
    $lowerTabs.Dock = 'Fill'
    $lowerTabs.SelectedTab = $tabLog

    $tabLog.Text = " $($script:Glyph.Logs)  Logs "
    $tabCommand.Text = " $($script:Glyph.Command)  Command Preview "
    $tabCustomGstArgs.Text = " $($script:Glyph.Command)  Custom Args "
    $txtLog.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#08111F')
    $txtLog.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#D1D5DB')
    $txtLog.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $txtCommand.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#08111F')
    $txtCommand.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#D1D5DB')
    $txtCommand.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $txtCustomGstArguments.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#08111F')
    $txtCustomGstArguments.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#D1D5DB')
    $txtCustomGstArguments.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $lblCustomGstArgumentsHelp.ForeColor = $script:ColorMuted
    $customArgsTopPanel.BackColor = $script:ColorSurface

    Style-Tree $form

    # Style-Tree gives ordinary text inputs a form-field treatment. The command
    # panes are code editors, so restyle them after the recursive pass.
    foreach ($editor in @($txtCommand, $txtCustomGstArguments)) {
        if ($editor) {
            $editor.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#08111F')
            $editor.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#D1D5DB')
            $editor.BorderStyle = [System.Windows.Forms.BorderStyle]::None
            $editor.Font = New-Object System.Drawing.Font('Consolas', 9)
        }
    }
    if ($customArgsTopPanel) { $customArgsTopPanel.BackColor = $script:ColorSurface }
    if ($lblCustomGstArgumentsHelp) { $lblCustomGstArgumentsHelp.ForeColor = $script:ColorMuted }

    foreach ($realControl in @(
        $chkTransportEnabled, $cmbProtocol, $lblDestination, $txtDestination,
        $cmbCaptureMethod, $lblCaptureModeStatus, $numMonitor, $chkCursor,
        $chkStartMediaMtx, $txtMediaMtxPath, $btnBrowseMediaMtx,
        $cmbDirectWebRtcBundledWebMode, $txtDirectWebRtcBundledWebDirectory, $btnBrowseDirectWebRtcBundledWebDirectory, $btnDetectDirectWebRtcBundledWebDirectory,
        $cmbDirectWebRtcWorkingWebMode, $txtDirectWebRtcWebDirectory, $btnBrowseDirectWebRtcWebDirectory, $btnDetectDirectWebRtcWebDirectory,
        $numWidth, $numHeight, $numFps, $numVideoBitrate, $numGopSeconds, $chkUnifiedBridgeKeyframeGuard, $numUnifiedBridgeKeyframeIntervalMs,
        $cmbTimingMode, $chkSplitClockSignalingOverrides, $cmbSplitVideoClockSignaling, $cmbSplitAudioClockSignaling, $chkDirectWebRtcControlDataChannel, $cmbDirectWebRtcBundlePolicy, $numDirectWebRtcInternalRtpMtu, $chkDirectWebRtcInternalRepeatHeaders,
        $cmbRateControl, $numMaxVideoBitrate, $numConstantQp,
        $cmbEncoder, $lblEncoderStatus, $cmbPreset, $cmbProfile,
        $cmbEncoderTune, $cmbMultipass, $cmbVideoPipelineClockMode, $cmbVideoTimestampMode, $cmbVideoSyncMode, $numVbvBuffer,
        $numSrtLatency, $cmbRtspTransport,
        $numBFrames, $chkLookAhead, $numLookAheadFrames,
        $chkAdaptiveQuantization, $chkTemporalAq, $numAqStrength,
        $txtCustomEncoderOptions,
        $cmbAudioTransportMode, $cmbSplitAudioPipelineClockMode, $cmbAudioClockMode, $cmbAudioTimingMode, $cmbAudioSlaveMethod, $cmbAudioSyncMode, $chkWasapiLowLatencyOverride, $chkAudioBufferOverride, $numAudioBufferMs, $chkAudioLatencyOverride, $numAudioLatencyMs, $chkAudioSampleRateOverride, $numAudioSampleRate, $chkDesktopAudio, $chkAudioMixerMode, $numDesktopVolume, $cmbDesktopAudioDevice, $btnRefreshAudioDevices, $chkMic, $numMicVolume, $cmbMicAudioDevice, $lblAudioDeviceStatus,
        $cmbAudioCodec, $lblAudioCodecStatus, $numAudioBitrate,
        $cmbDirectWebRtcOpusMode, $cmbDirectWebRtcOpusFrameMs, $cmbDirectWebRtcOpusAudioType, $chkDirectWebRtcOpusFec, $chkDirectWebRtcOpusDtx,
        $chkRecordingEnabled, $chkRecordWithStream, $btnToggleRecording, $txtRecordingDirectory, $btnBrowseRecordingDirectory,
        $txtRecordingTemplate, $cmbRecordingEncoder, $lblRecordingStatus,
        $cmbRecordingPreset, $cmbRecordingProfile, $cmbRecordingRateControl,
        $numRecordingWidth, $numRecordingHeight, $numRecordingFps,
        $numRecordingVideoBitrate, $numRecordingMaxVideoBitrate, $numRecordingConstantQp,
        $numRecordingGopSeconds, $numRecordingBFrames,
        $cmbRecordingTune, $cmbRecordingMultipass,
        $chkRecordingLookAhead, $numRecordingLookAheadFrames,
        $chkRecordingSpatialAq, $chkRecordingTemporalAq, $numRecordingAqStrength,
        $numRecordingVbvBuffer, $txtRecordingCustomEncoderOptions,
        $chkRecordingDesktopAudio, $chkRecordingMic, $numRecordingAudioBitrate,
        $chkNetworkTuningEnabled, $cmbNetworkAdapter, $btnRefreshNetworkAdapters,
        $cmbNetworkProfile, $chkNetworkDscp, $numNetworkDscp, $cmbNetworkQosProtocol,
        $txtNetworkPorts, $cmbNetworkUso, $cmbNetworkUro, $chkNetworkDisablePowerSaving,
        $cmbNetworkInterruptModeration, $chkNetworkDisableEee,
        $chkNetworkRestoreOnStop, $chkNetworkRestoreOnExit, $chkNetworkRecoveryTask,
        $btnNetworkSnapshot, $btnNetworkApply, $btnNetworkRestore, $btnOpenNetworkRecovery,
        $lblNetworkStatus, $btnResetTransport, $btnResetWebRtcSane, $btnResetVideo, $btnResetAudio,
        $btnResetRecording, $btnResetNetwork, $btnResetOptions, $btnExportLabConfig, $btnResetAll,
        $txtGstPath, $btnBrowseGst, $btnDetectGst, $btnCheckGst,
        $chkPreview, $chkHidePreviewDuringStream, $chkAutoRestart, $chkVerbose, $chkDiskProcessLogging, $chkMinimizeToTray,
        $chkCustomGstArgumentsEnabled, $txtCustomGstArguments, $btnUseGeneratedAsCustomGstArgs, $btnClearCustomGstArgs,
        $chkStartMinimized, $btnRedrawScenePreview
    )) {
        if ($realControl) {
            $realControl.Visible = $true
        }
    }

    # Static explanatory text is intentionally removed from the visible UI.
    foreach ($staticInfo in @($audioNote, $protocolNote, $latencyNote, $changesNote)) {
        if ($staticInfo) {
            $staticInfo.Visible = $false
        }
    }

    # Keep checkbox marks readable on the dark UI. Flat WinForms checkboxes can
    # render a near-white check mark on a white box, which looks unchecked.
    foreach ($checkBox in @(
        $chkTransportEnabled, $chkCursor, $chkStartMediaMtx,
        $chkPlayerStatsOverlay, $chkPlayerJbufDebug, $chkPlayerUrlOverrides,
        $cmbSplitPlayerSyncMode, $numSplitAudioStallSeconds, $numSplitAudioWarmupSeconds, $numSplitAvOffsetBaselineMs, $numSplitAvOffsetWarnMs,
        $chkDirectWebRtcOpusFec, $chkDirectWebRtcOpusDtx,
        $chkLookAhead, $chkAdaptiveQuantization, $chkTemporalAq,
        $chkDesktopAudio, $chkAudioMixerMode, $chkMic, $chkAudioSampleRateOverride,
        $chkRecordingEnabled, $chkRecordWithStream, $chkRecordingLookAhead, $chkRecordingSpatialAq,
        $chkRecordingTemporalAq, $chkRecordingDesktopAudio, $chkRecordingMic,
        $chkNetworkTuningEnabled, $chkNetworkDscp, $chkNetworkDisablePowerSaving,
        $chkNetworkDisableEee, $chkNetworkRestoreOnStop, $chkNetworkRestoreOnExit,
        $chkNetworkRecoveryTask,
        $chkPreview, $chkHidePreviewDuringStream, $chkAutoRestart, $chkVerbose, $chkDiskProcessLogging,
        $chkCustomGstArgumentsEnabled,
        $chkMinimizeToTray, $chkStartMinimized
    )) {
        # This list is hand-maintained and has occasionally picked up non-CheckBox
        # controls during UI feature patches. Guard the style calls so shutdown or
        # delayed UI refresh cannot throw repeated modal errors for controls that
        # do not expose FlatStyle / UseVisualStyleBackColor.
        if ($checkBox -and ($checkBox -is [System.Windows.Forms.CheckBox])) {
            try {
                $checkBox.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard
                $checkBox.UseVisualStyleBackColor = $false
                $checkBox.BackColor = $script:ColorSurface
                $checkBox.ForeColor = $script:ColorText
            }
            catch {}
        }
    }

    $chkFullscreenApp.Visible = $false
    $chkFullscreenApp.TabStop = $false
    $chkSendAbsoluteTimestamps.Visible = $false
    $chkSendAbsoluteTimestamps.TabStop = $false

    # Accent/color corrections after recursive styling.
    $btnStart.BackColor = $script:ColorAccent
    $btnStart.ForeColor = [System.Drawing.Color]::White
    $statusLabel.ForeColor = $script:ColorGood
    $lblEncoderStatus.ForeColor = $script:ColorMuted
    $lblAudioCodecStatus.ForeColor = $script:ColorMuted
    $lblCaptureModeStatus.ForeColor = $script:ColorMuted
    $audioNote.ForeColor = $script:ColorMuted
    $protocolNote.ForeColor = $script:ColorMuted
    $latencyNote.ForeColor = $script:ColorMuted
    $changesNote.ForeColor = $script:ColorWarn
    $previewPanel.BackColor = [System.Drawing.Color]::Black
    $previewPlaceholder.BackColor = [System.Drawing.Color]::Black
    $previewPlaceholder.ForeColor = $script:ColorMuted
    $txtLog.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#08111F')
    $txtCommand.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#08111F')
    $txtCustomGstArguments.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#08111F')
    $txtCustomGstArguments.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#D1D5DB')
    $txtCustomGstArguments.BorderStyle = [System.Windows.Forms.BorderStyle]::None
}

