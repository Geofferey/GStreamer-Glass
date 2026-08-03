#requires -Version 5.1
# SPDX-License-Identifier: AGPL-3.0-only

<#
.SYNOPSIS
    Basic Windows GUI wrapper for low-latency GStreamer desktop streaming.

.DESCRIPTION
    Captures a Windows desktop through selectable GStreamer capture backends,
    encodes through a selectable hardware or software encoder, and publishes
    through WHIP, SRT, RTMP, or RTSP. Desktop loopback audio and the default
    microphone can be enabled independently. Optional fullscreen-app capture
    targets a topmost fullscreen HWND through Windows Graphics Capture.

    The optional preview uses a leaky GPU-side tee and d3d11videosink. The GUI
    attempts to re-parent the GStreamer preview window into the form. This is an
    experimental convenience layer; streaming does not depend on preview.

    Designed to run as a PS2EXE/PS12EXE no-console application. All GStreamer
    output is shown in the in-memory app log. Per-run process log files are opt-in.
#>

param(
    [switch]$ControlledLiveWorker,
    [string]$ControlledLiveWorkerPipe,
    [switch]$WebRtcPortRangeWorker,
    [string]$WebRtcPortRangeWorkerPipe,
    [switch]$AuthProxyWorker,
    [string]$AuthProxyWorkerPipe,
    [switch]$AuthCacheCryptoSelfTest,
    [switch]$ClipboardApartmentSelfTest
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
# ProtectedData lives in System.Security.dll on Windows PowerShell/.NET
# Framework. An interactive console often has that assembly loaded already,
# but a PS12EXE no-console host does not; without this explicit load, merely
# resolving [System.Security.Cryptography.ProtectedData] throws from the UI
# button handler before our cache-level try/catch can run.
Add-Type -AssemblyName System.Security
[System.Windows.Forms.Application]::EnableVisualStyles()

# Hidden build-smoke-test entry point. Running the compiled EXE with this
# switch proves the exact PS12EXE host can load System.Security and complete a
# current-user DPAPI round trip, instead of trusting a console PowerShell test
# whose assembly set differs from the shipped executable.
if ($AuthCacheCryptoSelfTest) {
    try {
        $sample = [System.Text.Encoding]::UTF8.GetBytes('gstglass-auth-cache-self-test')
        $entropy = [System.Text.Encoding]::UTF8.GetBytes('gstglass-auth-cache-self-test-entropy')
        $encrypted = [System.Security.Cryptography.ProtectedData]::Protect(
            $sample,
            $entropy,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        $roundTrip = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $encrypted,
            $entropy,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        if ([Convert]::ToBase64String($sample) -ne [Convert]::ToBase64String($roundTrip)) { exit 72 }
        exit 0
    }
    catch {
        exit 71
    }
}


if (-not ('GstExecutableBrowser' -as [type])) {
    Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.IO;
using System.Threading;
using System.Windows.Forms;

public static class GstExecutableBrowser
{
    public static string SelectGstLaunch(string currentPath)
    {
        return SelectExecutable(
            currentPath,
            "Select gst-launch-1.0.exe",
            "gst-launch-1.0.exe",
            "GStreamer launcher (gst-launch-1.0.exe)|gst-launch-1.0.exe|" +
            "Executable files (*.exe)|*.exe|All files (*.*)|*.*",
            "GStreamer executable browser");
    }

    public static string SelectMediaMtx(string currentPath)
    {
        return SelectExecutable(
            currentPath,
            "Select mediamtx.exe",
            "mediamtx.exe",
            "MediaMTX server (mediamtx.exe)|mediamtx.exe|" +
            "Executable files (*.exe)|*.exe|All files (*.*)|*.*",
            "MediaMTX executable browser");
    }

    public static string SelectFile(string currentPath, string title, string preferredFileName, string filter)
    {
        return SelectExecutable(currentPath, title, preferredFileName, filter, "File browser");
    }

    public static string SelectSaveFile(string currentPath, string preferredFileName, string title, string filter, string defaultExt)
    {
        string selectedPath = String.Empty;
        Exception dialogError = null;

        Thread dialogThread = new Thread(() =>
        {
            try
            {
                using (SaveFileDialog dialog = new SaveFileDialog())
                {
                    dialog.Title = title;
                    dialog.Filter = filter;
                    dialog.DefaultExt = defaultExt;
                    dialog.AddExtension = true;
                    dialog.OverwritePrompt = true;
                    dialog.RestoreDirectory = true;
                    dialog.FileName = preferredFileName;

                    if (!String.IsNullOrWhiteSpace(currentPath))
                    {
                        try
                        {
                            string expanded =
                                Environment.ExpandEnvironmentVariables(currentPath.Trim());

                            if (Directory.Exists(expanded))
                                dialog.InitialDirectory = expanded;
                        }
                        catch
                        {
                            // A stale saved path must not prevent the picker opening.
                        }
                    }

                    if (dialog.ShowDialog() == DialogResult.OK)
                        selectedPath = dialog.FileName ?? String.Empty;
                }
            }
            catch (Exception ex)
            {
                dialogError = ex;
            }
        });

        dialogThread.Name = "Save file browser";
        dialogThread.IsBackground = true;
        dialogThread.SetApartmentState(ApartmentState.STA);
        dialogThread.Start();
        dialogThread.Join();

        if (dialogError != null)
            throw new InvalidOperationException(
                "The save dialog could not be opened.",
                dialogError);

        return selectedPath;
    }

    public static string SelectFolder(string currentPath, string description)
    {
        return SelectFolder(currentPath, description, true);
    }

    public static string SelectFolder(string currentPath, string description, bool showNewFolderButton)
    {
        string selectedPath = String.Empty;
        Exception dialogError = null;

        Thread dialogThread = new Thread(() =>
        {
            try
            {
                using (FolderBrowserDialog dialog = new FolderBrowserDialog())
                {
                    dialog.Description = String.IsNullOrWhiteSpace(description)
                        ? "Select folder"
                        : description;
                    dialog.ShowNewFolderButton = showNewFolderButton;

                    if (!String.IsNullOrWhiteSpace(currentPath))
                    {
                        try
                        {
                            string expanded =
                                Environment.ExpandEnvironmentVariables(currentPath.Trim());

                            if (Directory.Exists(expanded))
                                dialog.SelectedPath = expanded;
                            else
                            {
                                string parent = Path.GetDirectoryName(expanded);
                                if (!String.IsNullOrWhiteSpace(parent) &&
                                    Directory.Exists(parent))
                                    dialog.SelectedPath = parent;
                            }
                        }
                        catch
                        {
                            // A stale saved path must not prevent the picker opening.
                        }
                    }

                    if (dialog.ShowDialog() == DialogResult.OK)
                        selectedPath = dialog.SelectedPath ?? String.Empty;
                }
            }
            catch (Exception ex)
            {
                dialogError = ex;
            }
        });

        dialogThread.Name = "Recording folder browser";
        dialogThread.IsBackground = true;
        dialogThread.SetApartmentState(ApartmentState.STA);
        dialogThread.Start();
        dialogThread.Join();

        if (dialogError != null)
            throw new InvalidOperationException(
                "The folder browser could not be opened.",
                dialogError);

        return selectedPath;
    }

    private static string SelectExecutable(
        string currentPath,
        string title,
        string preferredFileName,
        string filter,
        string threadName)
    {
        string selectedPath = String.Empty;
        Exception dialogError = null;

        Thread dialogThread = new Thread(() =>
        {
            try
            {
                using (OpenFileDialog dialog = new OpenFileDialog())
                {
                    dialog.Title = title;
                    dialog.Filter = filter;
                    dialog.CheckFileExists = true;
                    dialog.CheckPathExists = true;
                    dialog.Multiselect = false;
                    dialog.RestoreDirectory = true;
                    dialog.DereferenceLinks = true;
                    dialog.ValidateNames = true;
                    dialog.FileName = preferredFileName;

                    if (!String.IsNullOrWhiteSpace(currentPath))
                    {
                        try
                        {
                            string expanded =
                                Environment.ExpandEnvironmentVariables(currentPath.Trim());

                            if (File.Exists(expanded))
                            {
                                dialog.InitialDirectory = Path.GetDirectoryName(expanded);
                                dialog.FileName = Path.GetFileName(expanded);
                            }
                            else if (Directory.Exists(expanded))
                            {
                                dialog.InitialDirectory = expanded;
                            }
                            else
                            {
                                string parent = Path.GetDirectoryName(expanded);
                                if (!String.IsNullOrWhiteSpace(parent) &&
                                    Directory.Exists(parent))
                                {
                                    dialog.InitialDirectory = parent;
                                }
                            }
                        }
                        catch
                        {
                            // A stale saved path must not prevent the picker opening.
                        }
                    }

                    if (dialog.ShowDialog() == DialogResult.OK)
                        selectedPath = dialog.FileName ?? String.Empty;
                }
            }
            catch (Exception ex)
            {
                dialogError = ex;
            }
        });

        dialogThread.Name = threadName;
        dialogThread.IsBackground = true;
        dialogThread.SetApartmentState(ApartmentState.STA);
        dialogThread.Start();
        dialogThread.Join();

        if (dialogError != null)
            throw new InvalidOperationException(
                "The executable browser could not be opened.",
                dialogError);

        return selectedPath;
    }
}

// The packaged UI deliberately runs MTA, while the Windows clipboard is an
// OLE API and therefore requires STA. Keep every clipboard call behind this
// helper, matching the dedicated STA-thread pattern used by the dialogs above.
public static class GstClipboard
{
    public static void SetText(string text)
    {
        if (String.IsNullOrEmpty(text))
            throw new ArgumentException("Clipboard text cannot be empty.", "text");

        Exception clipboardError = null;
        Thread clipboardThread = new Thread(() =>
        {
            try { Clipboard.SetText(text); }
            catch (Exception ex) { clipboardError = ex; }
        });
        clipboardThread.Name = "Clipboard writer";
        clipboardThread.IsBackground = true;
        clipboardThread.SetApartmentState(ApartmentState.STA);
        clipboardThread.Start();
        clipboardThread.Join();

        if (clipboardError != null)
            throw new InvalidOperationException("Text could not be copied to the clipboard.", clipboardError);
    }

    public static ApartmentState GetHelperApartmentState()
    {
        ApartmentState state = ApartmentState.Unknown;
        Thread clipboardThread = new Thread(() => { state = Thread.CurrentThread.GetApartmentState(); });
        clipboardThread.Name = "Clipboard apartment self-test";
        clipboardThread.IsBackground = true;
        clipboardThread.SetApartmentState(ApartmentState.STA);
        clipboardThread.Start();
        clipboardThread.Join();
        return state;
    }
}
'@
}

if ($ClipboardApartmentSelfTest) {
    if ([GstClipboard]::GetHelperApartmentState() -eq [System.Threading.ApartmentState]::STA) { exit 0 }
    exit 73
}


if (-not ('GstUiNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class GstUiNative
{
    public const int WM_VSCROLL = 0x0115;
    public const int SB_BOTTOM = 7;
    public const int EM_SCROLLCARET = 0x00B7;
    public const int WM_SETREDRAW = 0x000B;

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
}
'@
}

if (-not ('GstPreviewNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class GstPreviewNative
{
    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct MONITORINFO
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr hWnd, StringBuilder className, int maxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder windowText, int maxCount);

    [DllImport("user32.dll")]
    private static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint flags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO monitorInfo);

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(IntPtr hWnd, int attribute, out int value, int size);

    [DllImport("user32.dll")]
    private static extern IntPtr SetParent(IntPtr child, IntPtr newParent);

    [DllImport("user32.dll")]
    private static extern int GetWindowLong(IntPtr hWnd, int index);

    [DllImport("user32.dll")]
    private static extern int SetWindowLong(IntPtr hWnd, int index, int value);

    [DllImport("user32.dll")]
    private static extern bool MoveWindow(IntPtr hWnd, int x, int y, int width, int height, bool repaint);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int command);

    private const int GWL_STYLE = -16;
    private const int WS_CHILD = 0x40000000;
    private const int WS_VISIBLE = 0x10000000;
    private const int WS_POPUP = unchecked((int)0x80000000);
    private const int WS_CAPTION = 0x00C00000;
    private const int WS_THICKFRAME = 0x00040000;
    private const int WS_SYSMENU = 0x00080000;
    private const int WS_MINIMIZEBOX = 0x00020000;
    private const int WS_MAXIMIZEBOX = 0x00010000;
    private const int SW_HIDE = 0;
    private const int SW_SHOW = 5;
    private const uint MONITOR_DEFAULTTONEAREST = 2;
    private const int DWMWA_CLOAKED = 14;

    private static bool IsShellWindowClass(string className)
    {
        return string.Equals(className, "Progman", StringComparison.OrdinalIgnoreCase) ||
               string.Equals(className, "WorkerW", StringComparison.OrdinalIgnoreCase) ||
               string.Equals(className, "Shell_TrayWnd", StringComparison.OrdinalIgnoreCase) ||
               string.Equals(className, "Shell_SecondaryTrayWnd", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsFullscreenCandidate(IntPtr hWnd, int excludedProcessId, int secondExcludedProcessId)
    {
        if (hWnd == IntPtr.Zero || !IsWindow(hWnd) || !IsWindowVisible(hWnd) || IsIconic(hWnd))
            return false;

        uint pid;
        GetWindowThreadProcessId(hWnd, out pid);
        if (pid == 0 || pid == (uint)excludedProcessId ||
            (secondExcludedProcessId > 0 && pid == (uint)secondExcludedProcessId))
            return false;

        var classNameBuilder = new StringBuilder(256);
        GetClassName(hWnd, classNameBuilder, classNameBuilder.Capacity);
        if (IsShellWindowClass(classNameBuilder.ToString()))
            return false;

        try
        {
            int cloaked;
            if (DwmGetWindowAttribute(hWnd, DWMWA_CLOAKED, out cloaked, sizeof(int)) == 0 && cloaked != 0)
                return false;
        }
        catch
        {
            // DWM query is best-effort only.
        }

        RECT rect;
        if (!GetWindowRect(hWnd, out rect))
            return false;

        int width = rect.Right - rect.Left;
        int height = rect.Bottom - rect.Top;
        if (width < 640 || height < 360)
            return false;

        IntPtr monitor = MonitorFromWindow(hWnd, MONITOR_DEFAULTTONEAREST);
        if (monitor == IntPtr.Zero)
            return false;

        MONITORINFO info = new MONITORINFO();
        info.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
        if (!GetMonitorInfo(monitor, ref info))
            return false;

        const int tolerance = 12;
        bool coversMonitor =
            rect.Left <= info.rcMonitor.Left + tolerance &&
            rect.Top <= info.rcMonitor.Top + tolerance &&
            rect.Right >= info.rcMonitor.Right - tolerance &&
            rect.Bottom >= info.rcMonitor.Bottom - tolerance;

        bool notWildlyOversized =
            rect.Left >= info.rcMonitor.Left - 64 &&
            rect.Top >= info.rcMonitor.Top - 64 &&
            rect.Right <= info.rcMonitor.Right + 64 &&
            rect.Bottom <= info.rcMonitor.Bottom + 64;

        return coversMonitor && notWildlyOversized;
    }

    public static IntPtr FindTopmostFullscreenWindow(int excludedProcessId, int secondExcludedProcessId)
    {
        IntPtr result = IntPtr.Zero;

        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam)
        {
            if (IsFullscreenCandidate(hWnd, excludedProcessId, secondExcludedProcessId))
            {
                result = hWnd;
                return false;
            }

            return true;
        }, IntPtr.Zero);

        return result;
    }

    public static string GetWindowTitleSafe(IntPtr hWnd)
    {
        if (hWnd == IntPtr.Zero || !IsWindow(hWnd))
            return string.Empty;

        int length = Math.Max(0, GetWindowTextLength(hWnd));
        var title = new StringBuilder(Math.Max(256, length + 1));
        GetWindowText(hWnd, title, title.Capacity);
        if (title.Length > 0)
            return title.ToString();

        var className = new StringBuilder(256);
        GetClassName(hWnd, className, className.Capacity);
        return className.ToString();
    }

    public static bool WindowExists(IntPtr hWnd)
    {
        return hWnd != IntPtr.Zero && IsWindow(hWnd);
    }

    public static IntPtr FindPreviewWindow(int processId)
    {
        IntPtr best = IntPtr.Zero;
        long bestArea = 0;

        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam)
        {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);

            // gst-launch is intentionally started hidden for PS12EXE/no-console use.
            // d3d11videosink can therefore create a valid preview window that is
            // initially hidden. Do not require visibility here; EmbedWindow()
            // reparents and explicitly shows the selected renderer window.
            if (pid != (uint)processId || !IsWindow(hWnd))
                return true;

            var classNameBuilder = new StringBuilder(256);
            GetClassName(hWnd, classNameBuilder, classNameBuilder.Capacity);
            string className = classNameBuilder.ToString();

            if (className.IndexOf("Console", StringComparison.OrdinalIgnoreCase) >= 0 ||
                className.IndexOf("CASCADIA", StringComparison.OrdinalIgnoreCase) >= 0 ||
                className.IndexOf("PseudoConsole", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                ShowWindow(hWnd, SW_HIDE);
                return true;
            }

            RECT rect;
            if (!GetWindowRect(hWnd, out rect))
                return true;

            long width = Math.Max(0, rect.Right - rect.Left);
            long height = Math.Max(0, rect.Bottom - rect.Top);
            long area = width * height;
            if (area > bestArea)
            {
                bestArea = area;
                best = hWnd;
            }

            return true;
        }, IntPtr.Zero);

        return best;
    }

    public static bool EmbedWindow(IntPtr child, IntPtr parent, int width, int height)
    {
        if (child == IntPtr.Zero || parent == IntPtr.Zero)
            return false;

        SetParent(child, parent);
        int style = GetWindowLong(child, GWL_STYLE);
        style &= ~(WS_POPUP | WS_CAPTION | WS_THICKFRAME | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX);
        style |= WS_CHILD | WS_VISIBLE;
        SetWindowLong(child, GWL_STYLE, style);
        MoveWindow(child, 0, 0, Math.Max(1, width), Math.Max(1, height), true);
        ShowWindow(child, SW_SHOW);
        return true;
    }

    public static void ResizeEmbeddedWindow(IntPtr child, int width, int height)
    {
        if (child != IntPtr.Zero)
            MoveWindow(child, 0, 0, Math.Max(1, width), Math.Max(1, height), true);
    }

    public static void SetWindowVisible(IntPtr child, bool visible)
    {
        if (child != IntPtr.Zero && IsWindow(child))
            ShowWindow(child, visible ? SW_SHOW : SW_HIDE);
    }

    public static bool ReparentEmbeddedWindow(IntPtr child, IntPtr parent, int width, int height, bool visible)
    {
        if (child == IntPtr.Zero || parent == IntPtr.Zero || !IsWindow(child))
            return false;

        SetParent(child, parent);
        int style = GetWindowLong(child, GWL_STYLE);
        style &= ~(WS_POPUP | WS_CAPTION | WS_THICKFRAME | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX);
        style |= WS_CHILD;
        if (visible)
            style |= WS_VISIBLE;
        else
            style &= ~WS_VISIBLE;

        SetWindowLong(child, GWL_STYLE, style);
        MoveWindow(child, 0, 0, Math.Max(1, width), Math.Max(1, height), true);
        ShowWindow(child, visible ? SW_SHOW : SW_HIDE);
        return true;
    }
}
'@
}

if (-not ('GstControlledScenePreview' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class GstControlledScenePreview
{
    private const string Gst = "gstreamer-1.0-0.dll";
    private const string GstVideo = "gstvideo-1.0-0.dll";
    private const string GObject = "gobject-2.0-0.dll";
    private const string GLib = "glib-2.0-0.dll";

    private const int GST_STATE_NULL = 1;
    private const int GST_STATE_PLAYING = 4;
    private const int GST_STATE_CHANGE_FAILURE = 0;
    private const uint GST_MESSAGE_EOS = 1u << 0;
    private const uint GST_MESSAGE_ERROR = 1u << 1;
    private static readonly UIntPtr G_TYPE_INT = new UIntPtr(6u << 2);
    private static readonly UIntPtr G_TYPE_UINT = new UIntPtr(7u << 2);
    private static readonly UIntPtr G_TYPE_DOUBLE = new UIntPtr(15u << 2);
    private static readonly UIntPtr G_TYPE_ENUM = new UIntPtr(12u << 2);

    [StructLayout(LayoutKind.Sequential)]
    private struct GValue
    {
        public UIntPtr g_type;
        public UIntPtr data0;
        public UIntPtr data1;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct GError
    {
        public uint domain;
        public int code;
        public IntPtr message;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct GParamSpecPrefix
    {
        public IntPtr g_class;
        public IntPtr name;
        public uint flags;
        public UIntPtr value_type;
        public UIntPtr owner_type;
    }

    [DllImport(Gst, CallingConvention = CallingConvention.Cdecl)]
    private static extern void gst_init(IntPtr argc, IntPtr argv);

    [DllImport(Gst, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern IntPtr gst_parse_launch(string pipeline_description, out IntPtr error);

    [DllImport(Gst, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern IntPtr gst_bin_get_by_name(IntPtr bin, string name);

    [DllImport(Gst, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern IntPtr gst_element_get_static_pad(IntPtr element, string name);

    [DllImport(Gst, CallingConvention = CallingConvention.Cdecl)]
    private static extern int gst_element_set_state(IntPtr element, int state);

    [DllImport(Gst, CallingConvention = CallingConvention.Cdecl)]
    private static extern int gst_element_get_state(IntPtr element, out int state, out int pending, ulong timeout);

    [DllImport(Gst, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr gst_element_get_bus(IntPtr element);

    [DllImport(Gst, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr gst_bus_timed_pop_filtered(IntPtr bus, ulong timeout, uint types);

    [DllImport(Gst, CallingConvention = CallingConvention.Cdecl)]
    private static extern void gst_message_parse_error(IntPtr message, out IntPtr error, out IntPtr debug);

    [DllImport(Gst, CallingConvention = CallingConvention.Cdecl)]
    private static extern void gst_mini_object_unref(IntPtr mini_object);

    [DllImport(Gst, CallingConvention = CallingConvention.Cdecl)]
    private static extern void gst_object_unref(IntPtr obj);

    [DllImport(GstVideo, CallingConvention = CallingConvention.Cdecl)]
    private static extern void gst_video_overlay_set_window_handle(IntPtr overlay, UIntPtr handle);

    [DllImport(GstVideo, CallingConvention = CallingConvention.Cdecl)]
    private static extern int gst_video_overlay_set_render_rectangle(IntPtr overlay, int x, int y, int width, int height);

    [DllImport(GstVideo, CallingConvention = CallingConvention.Cdecl)]
    private static extern void gst_video_overlay_expose(IntPtr overlay);

    [DllImport(GstVideo, CallingConvention = CallingConvention.Cdecl)]
    private static extern void gst_video_overlay_handle_events(IntPtr overlay, int handle_events);

    [DllImport(GObject, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr g_value_init(ref GValue value, UIntPtr g_type);

    [DllImport(GObject, CallingConvention = CallingConvention.Cdecl)]
    private static extern void g_value_unset(ref GValue value);

    [DllImport(GObject, CallingConvention = CallingConvention.Cdecl)]
    private static extern void g_value_set_int(ref GValue value, int number);

    [DllImport(GObject, CallingConvention = CallingConvention.Cdecl)]
    private static extern void g_value_set_uint(ref GValue value, uint number);

    [DllImport(GObject, CallingConvention = CallingConvention.Cdecl)]
    private static extern void g_value_set_double(ref GValue value, double number);

    [DllImport(GObject, CallingConvention = CallingConvention.Cdecl)]
    private static extern void g_value_set_enum(ref GValue value, int number);

    [DllImport(GObject, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern void g_object_set_property(IntPtr obj, string property_name, ref GValue value);

    [DllImport(GObject, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern IntPtr g_object_class_find_property(IntPtr oclass, string property_name);

    [DllImport(GObject, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern void g_object_get(IntPtr obj, string first_property_name, out IntPtr value, IntPtr terminator);

    [DllImport(GObject, EntryPoint = "g_object_get", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern void g_object_get_uint(IntPtr obj, string first_property_name, out uint value, IntPtr terminator);

    [DllImport(GObject, CallingConvention = CallingConvention.Cdecl)]
    private static extern void g_object_unref(IntPtr obj);

    private delegate void ConsumerAddedDelegate(IntPtr webrtcsink, IntPtr peerId, IntPtr consumerElement, IntPtr userData);

    [DllImport(GObject, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern ulong g_signal_connect_data(IntPtr instance, string detailed_signal, ConsumerAddedDelegate c_handler, IntPtr data, IntPtr destroy_data, int connect_flags);

    [DllImport(GLib, CallingConvention = CallingConvention.Cdecl)]
    private static extern void g_error_free(IntPtr error);

    [DllImport(GLib, CallingConvention = CallingConvention.Cdecl)]
    private static extern void g_free(IntPtr memory);

    [DllImport(GLib, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr g_main_context_default();

    // No explicit MarshalAs needed: glib's gboolean is a 4-byte gint, which is
    // exactly what .NET's default (unannotated) bool marshaling already uses
    // for P/Invoke (the Win32 BOOL convention) -- MarshalAs(I1) would be wrong
    // here (that's a 1-byte bool, for a different ABI).
    [DllImport(GLib, CallingConvention = CallingConvention.Cdecl)]
    private static extern bool g_main_context_iteration(IntPtr context, bool mayBlock);

    private static readonly object Gate = new object();
    private static bool initialized;
    private static IntPtr pipeline;
    private static IntPtr scene;
    private static IntPtr sink;
    private static IntPtr bus;
    private static IntPtr desktopPad;
    private static IntPtr webcamPad;
    // Only resolved/hooked when StartLive is given a nonzero Min/Max RTP
    // port range -- the "out" webrtcsink element that Start-GstStream's
    // plain gst-launch path also uses. Mirrors GstWebRtcConsumerPortRange's
    // own consumer-added hook exactly, so Live Scene Editing can pin the ICE
    // port range on its own hosted webrtcsink instead of that being
    // mutually exclusive with the separate port-range worker process.
    private static IntPtr webrtcSinkForPortRange;
    private static uint minRtpPort;
    private static uint maxRtpPort;
    private static int consumersConfigured;
    private static string consumerError;
    private static ConsumerAddedDelegate consumerAddedCallback;

    public static bool IsRunning
    {
        get { lock (Gate) { return pipeline != IntPtr.Zero; } }
    }

    public static bool HasWebcamPad
    {
        get { lock (Gate) { return webcamPad != IntPtr.Zero; } }
    }

    private static string ReadGError(IntPtr error)
    {
        if (error == IntPtr.Zero) return "Unknown GStreamer error";
        GError value = (GError)Marshal.PtrToStructure(error, typeof(GError));
        return value.message == IntPtr.Zero ? "Unknown GStreamer error" : Marshal.PtrToStringAnsi(value.message);
    }

    // Identical in spirit to GstWebRtcConsumerPortRange.OnConsumerAdded --
    // duplicated rather than shared because these are two independently
    // Add-Type-compiled classes with no shared native-interop assembly.
    private static void OnConsumerAdded(IntPtr webrtcsink, IntPtr peerId, IntPtr consumerElement, IntPtr userData)
    {
        try
        {
            if (consumerElement == IntPtr.Zero)
                throw new InvalidOperationException("The WebRTC consumer element was not provided.");
            IntPtr iceAgent;
            g_object_get(consumerElement, "ice-agent", out iceAgent, IntPtr.Zero);
            if (iceAgent == IntPtr.Zero)
                throw new InvalidOperationException("The WebRTC consumer has no ICE agent.");
            try
            {
                SetUInt(iceAgent, "min-rtp-port", minRtpPort);
                SetUInt(iceAgent, "max-rtp-port", maxRtpPort);
                uint actualMin;
                uint actualMax;
                g_object_get_uint(iceAgent, "min-rtp-port", out actualMin, IntPtr.Zero);
                g_object_get_uint(iceAgent, "max-rtp-port", out actualMax, IntPtr.Zero);
                if (actualMin != minRtpPort || actualMax != maxRtpPort)
                    throw new InvalidOperationException("The ICE agent rejected the requested RTP port range.");
                System.Threading.Interlocked.Increment(ref consumersConfigured);
            }
            finally
            {
                g_object_unref(iceAgent);
            }
        }
        catch (Exception ex)
        {
            System.Threading.Interlocked.CompareExchange(
                ref consumerError, "Failed to apply WebRTC ICE port range: " + ex.Message, null);
        }
    }

    // See GstWebRtcConsumerPortRange.PumpMainContextOnce for why this exists:
    // this class also hosts webrtcsink directly via gst_parse_launch +
    // gst_element_set_state instead of gst-launch-1.0.exe's own
    // g_main_loop_run(), so nothing services the default GMainContext
    // (RTCP timers, congestion-control ticks, the embedded signalling/web
    // server's async I/O, clock-sync notifications) without this.
    public static bool PumpMainContextOnce()
    {
        return g_main_context_iteration(g_main_context_default(), false);
    }

    public static void Start(
        string description,
        long windowHandle,
        int width,
        int height,
        string desktopPadName,
        string webcamPadName)
    {
        StartCore(
            description,
            windowHandle,
            width,
            height,
            "controlledpreview",
            desktopPadName,
            webcamPadName,
            0,
            0);
    }

    public static void StartLive(
        string description,
        long windowHandle,
        int width,
        int height,
        string desktopPadName,
        string webcamPadName,
        uint minRtpPortValue,
        uint maxRtpPortValue)
    {
        StartCore(
            description,
            windowHandle,
            width,
            height,
            "localpreview",
            desktopPadName,
            webcamPadName,
            minRtpPortValue,
            maxRtpPortValue);
    }

    private static void StartCore(
        string description,
        long windowHandle,
        int width,
        int height,
        string sinkName,
        string desktopPadName,
        string webcamPadName,
        uint minRtpPortValue,
        uint maxRtpPortValue)
    {
        lock (Gate)
        {
            StopUnsafe();
            if (!initialized)
            {
                gst_init(IntPtr.Zero, IntPtr.Zero);
                initialized = true;
            }

            minRtpPort = minRtpPortValue;
            maxRtpPort = maxRtpPortValue;
            consumersConfigured = 0;
            System.Threading.Interlocked.Exchange(ref consumerError, null);

            IntPtr parseError;
            pipeline = gst_parse_launch(description, out parseError);
            if (parseError != IntPtr.Zero)
            {
                string message = ReadGError(parseError);
                g_error_free(parseError);
                StopUnsafe();
                throw new InvalidOperationException("Pipeline parse failed: " + message);
            }
            if (pipeline == IntPtr.Zero)
                throw new InvalidOperationException("gst_parse_launch returned no pipeline.");

            sink = gst_bin_get_by_name(pipeline, sinkName);
            bus = gst_element_get_bus(pipeline);
            if (sink == IntPtr.Zero || bus == IntPtr.Zero)
            {
                StopUnsafe();
                throw new InvalidOperationException(
                    "The controlled sink '" + sinkName + "' or pipeline bus was not found.");
            }

            bool needsScene = !String.IsNullOrEmpty(desktopPadName) || !String.IsNullOrEmpty(webcamPadName);
            if (needsScene)
            {
                scene = gst_bin_get_by_name(pipeline, "scene");
                if (scene == IntPtr.Zero)
                {
                    StopUnsafe();
                    throw new InvalidOperationException("The controlled scene compositor was not found.");
                }

                if (!String.IsNullOrEmpty(desktopPadName))
                    desktopPad = gst_element_get_static_pad(scene, desktopPadName);
                if (!String.IsNullOrEmpty(webcamPadName))
                    webcamPad = gst_element_get_static_pad(scene, webcamPadName);

                if ((!String.IsNullOrEmpty(desktopPadName) && desktopPad == IntPtr.Zero) ||
                    (!String.IsNullOrEmpty(webcamPadName) && webcamPad == IntPtr.Zero))
                {
                    StopUnsafe();
                    throw new InvalidOperationException("A required controlled compositor pad was not found.");
                }
            }

            if (minRtpPort > 0 && maxRtpPort > 0)
            {
                webrtcSinkForPortRange = gst_bin_get_by_name(pipeline, "out");
                if (webrtcSinkForPortRange == IntPtr.Zero)
                {
                    StopUnsafe();
                    throw new InvalidOperationException("The webrtcsink element 'out' was not found for RTP port range enforcement.");
                }
                consumerAddedCallback = new ConsumerAddedDelegate(OnConsumerAdded);
                g_signal_connect_data(webrtcSinkForPortRange, "consumer-added", consumerAddedCallback, IntPtr.Zero, IntPtr.Zero, 0);
            }

            if (windowHandle != 0)
            {
                gst_video_overlay_set_window_handle(sink, new UIntPtr(unchecked((ulong)windowHandle)));
                gst_video_overlay_handle_events(sink, 1);
                gst_video_overlay_set_render_rectangle(sink, 0, 0, Math.Max(1, width), Math.Max(1, height));
            }

            int result = gst_element_set_state(pipeline, GST_STATE_PLAYING);
            if (result == GST_STATE_CHANGE_FAILURE)
            {
                StopUnsafe();
                throw new InvalidOperationException("GStreamer rejected the controlled preview PLAYING transition.");
            }
        }
    }

    private static void SetInt(IntPtr obj, string name, int number)
    {
        GValue value = new GValue();
        g_value_init(ref value, G_TYPE_INT);
        try { g_value_set_int(ref value, number); g_object_set_property(obj, name, ref value); }
        finally { g_value_unset(ref value); }
    }

    private static void SetUInt(IntPtr obj, string name, uint number)
    {
        GValue value = new GValue();
        g_value_init(ref value, G_TYPE_UINT);
        try { g_value_set_uint(ref value, number); g_object_set_property(obj, name, ref value); }
        finally { g_value_unset(ref value); }
    }

    private static void SetDouble(IntPtr obj, string name, double number)
    {
        GValue value = new GValue();
        g_value_init(ref value, G_TYPE_DOUBLE);
        try { g_value_set_double(ref value, number); g_object_set_property(obj, name, ref value); }
        finally { g_value_unset(ref value); }
    }

    private static void SetEnum(IntPtr obj, string name, int number)
    {
        GValue value = new GValue();
        UIntPtr enumType = G_TYPE_ENUM;
        try
        {
            IntPtr objectClass = Marshal.ReadIntPtr(obj);
            IntPtr paramSpec = objectClass == IntPtr.Zero
                ? IntPtr.Zero
                : g_object_class_find_property(objectClass, name);
            if (paramSpec != IntPtr.Zero)
            {
                GParamSpecPrefix prefix = (GParamSpecPrefix)Marshal.PtrToStructure(paramSpec, typeof(GParamSpecPrefix));
                if (prefix.value_type != UIntPtr.Zero) enumType = prefix.value_type;
            }
        }
        catch { }
        g_value_init(ref value, enumType);
        try { g_value_set_enum(ref value, number); g_object_set_property(obj, name, ref value); }
        finally { g_value_unset(ref value); }
    }

    public static void UpdateWebcam(int x, int y, int width, int height, double alpha, uint zorder, bool keepAspect)
    {
        lock (Gate)
        {
            if (webcamPad == IntPtr.Zero) return;
            SetInt(webcamPad, "xpos", x);
            SetInt(webcamPad, "ypos", y);
            SetInt(webcamPad, "width", Math.Max(1, width));
            SetInt(webcamPad, "height", Math.Max(1, height));
            SetDouble(webcamPad, "alpha", Math.Max(0.0, Math.Min(1.0, alpha)));
            SetUInt(webcamPad, "zorder", zorder);
            SetEnum(webcamPad, "sizing-policy", keepAspect ? 1 : 0);
        }
    }

    public static void Resize(int width, int height)
    {
        lock (Gate)
        {
            if (sink == IntPtr.Zero) return;
            gst_video_overlay_set_render_rectangle(sink, 0, 0, Math.Max(1, width), Math.Max(1, height));
            gst_video_overlay_expose(sink);
        }
    }

    public static void SetWindowHandle(long windowHandle, int width, int height)
    {
        lock (Gate)
        {
            if (sink == IntPtr.Zero) return;
            gst_video_overlay_set_window_handle(sink, new UIntPtr(unchecked((ulong)windowHandle)));
            gst_video_overlay_set_render_rectangle(sink, 0, 0, Math.Max(1, width), Math.Max(1, height));
            gst_video_overlay_expose(sink);
        }
    }

    public static string PollTerminalMessage()
    {
        lock (Gate)
        {
            string callbackError = System.Threading.Interlocked.Exchange(ref consumerError, null);
            if (!String.IsNullOrEmpty(callbackError)) return callbackError;
            if (bus == IntPtr.Zero) return null;
            IntPtr errorMessage = gst_bus_timed_pop_filtered(bus, 0, GST_MESSAGE_ERROR);
            if (errorMessage != IntPtr.Zero)
            {
                try
                {
                    IntPtr error;
                    IntPtr debug;
                    gst_message_parse_error(errorMessage, out error, out debug);
                    try
                    {
                        string text = ReadGError(error);
                        string detail = debug == IntPtr.Zero ? null : Marshal.PtrToStringAnsi(debug);
                        return String.IsNullOrEmpty(detail) ? text : text + Environment.NewLine + detail;
                    }
                    finally
                    {
                        if (error != IntPtr.Zero) g_error_free(error);
                        if (debug != IntPtr.Zero) g_free(debug);
                    }
                }
                finally { gst_mini_object_unref(errorMessage); }
            }

            IntPtr eosMessage = gst_bus_timed_pop_filtered(bus, 0, GST_MESSAGE_EOS);
            if (eosMessage == IntPtr.Zero) return null;
            gst_mini_object_unref(eosMessage);
            return "Pipeline reached end of stream.";
        }
    }

    public static void Stop()
    {
        lock (Gate) { StopUnsafe(); }
    }

    private static void StopUnsafe()
    {
        if (pipeline != IntPtr.Zero)
        {
            gst_element_set_state(pipeline, GST_STATE_NULL);
            try
            {
                int current;
                int pending;
                gst_element_get_state(pipeline, out current, out pending, 2000000000UL);
            }
            catch { }
        }
        if (webcamPad != IntPtr.Zero) gst_object_unref(webcamPad);
        if (desktopPad != IntPtr.Zero) gst_object_unref(desktopPad);
        if (bus != IntPtr.Zero) gst_object_unref(bus);
        if (sink != IntPtr.Zero) gst_object_unref(sink);
        if (scene != IntPtr.Zero) gst_object_unref(scene);
        if (webrtcSinkForPortRange != IntPtr.Zero) gst_object_unref(webrtcSinkForPortRange);
        if (pipeline != IntPtr.Zero) gst_object_unref(pipeline);
        webcamPad = desktopPad = bus = sink = scene = webrtcSinkForPortRange = pipeline = IntPtr.Zero;
        consumerAddedCallback = null;
    }
}
'@
}

if (-not ('GstWebRtcConsumerPortRange' -as [type])) {
    # Constrains webrtcsink's ICE candidate UDP port range to a known, fixed
    # span so it can actually be port-forwarded/hairpinned on a router -- a
    # random ephemeral port every session can't be. webrtcsink itself has no
    # such property (verified via gst-inspect and a full plugin registry
    # search), but the per-consumer webrtcbin it creates internally does, via
    # its "ice-agent" object's min-rtp-port/max-rtp-port properties (verified
    # via runtime g_object_class_list_properties introspection, since that
    # object isn't a registered element type gst-inspect can see statically).
    # Reaching that per-consumer object requires hooking webrtcsink's real
    # "consumer-added" signal (NOT a "webrtcbin-ready" signal -- that one does
    # not exist on this element) and setting the properties there, before
    # that consumer's own ICE gathering begins. This can only be done from
    # inside the same process that owns the pipeline, so it runs in the
    # disposable -WebRtcPortRangeWorker process, mirroring exactly how the
    # controlled live scene worker already hosts GStreamer out-of-process.
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class GstWebRtcConsumerPortRange
{
    private const string Gst = "gstreamer-1.0-0.dll";
    private const string GObject = "gobject-2.0-0.dll";
    private const string GLib = "glib-2.0-0.dll";

    private const int GST_STATE_NULL = 1;
    private const int GST_STATE_PLAYING = 4;
    private const int GST_STATE_CHANGE_FAILURE = 0;
    private const uint GST_MESSAGE_EOS = 1u << 0;
    private const uint GST_MESSAGE_ERROR = 1u << 1;
    private static readonly UIntPtr G_TYPE_UINT = new UIntPtr(7u << 2);

    [StructLayout(LayoutKind.Sequential)]
    private struct GValue
    {
        public UIntPtr g_type;
        public UIntPtr data0;
        public UIntPtr data1;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct GError
    {
        public uint domain;
        public int code;
        public IntPtr message;
    }

    [DllImport(Gst, CallingConvention = CallingConvention.Cdecl)]
    private static extern void gst_init(IntPtr argc, IntPtr argv);

    [DllImport(Gst, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern IntPtr gst_parse_launch(string pipeline_description, out IntPtr error);

    [DllImport(Gst, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern IntPtr gst_bin_get_by_name(IntPtr bin, string name);

    [DllImport(Gst, CallingConvention = CallingConvention.Cdecl)]
    private static extern int gst_element_set_state(IntPtr element, int state);

    [DllImport(Gst, CallingConvention = CallingConvention.Cdecl)]
    private static extern int gst_element_get_state(IntPtr element, out int state, out int pending, ulong timeout);

    [DllImport(Gst, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr gst_element_get_bus(IntPtr element);

    [DllImport(Gst, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr gst_bus_timed_pop_filtered(IntPtr bus, ulong timeout, uint types);

    [DllImport(Gst, CallingConvention = CallingConvention.Cdecl)]
    private static extern void gst_message_parse_error(IntPtr message, out IntPtr error, out IntPtr debug);

    [DllImport(Gst, CallingConvention = CallingConvention.Cdecl)]
    private static extern void gst_mini_object_unref(IntPtr mini_object);

    [DllImport(Gst, CallingConvention = CallingConvention.Cdecl)]
    private static extern void gst_object_unref(IntPtr obj);

    [DllImport(GObject, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern void g_object_get(IntPtr obj, string first_property_name, out IntPtr value, IntPtr terminator);

    [DllImport(GObject, EntryPoint = "g_object_get", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern void g_object_get_uint(IntPtr obj, string first_property_name, out uint value, IntPtr terminator);

    [DllImport(GObject, CallingConvention = CallingConvention.Cdecl)]
    private static extern void g_object_unref(IntPtr obj);

    [DllImport(GObject, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr g_value_init(ref GValue value, UIntPtr g_type);

    [DllImport(GObject, CallingConvention = CallingConvention.Cdecl)]
    private static extern void g_value_unset(ref GValue value);

    [DllImport(GObject, CallingConvention = CallingConvention.Cdecl)]
    private static extern void g_value_set_uint(ref GValue value, uint number);

    [DllImport(GObject, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern void g_object_set_property(IntPtr obj, string property_name, ref GValue value);

    private delegate void ConsumerAddedDelegate(IntPtr webrtcsink, IntPtr peerId, IntPtr consumerElement, IntPtr userData);

    [DllImport(GObject, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern ulong g_signal_connect_data(IntPtr instance, string detailed_signal, ConsumerAddedDelegate c_handler, IntPtr data, IntPtr destroy_data, int connect_flags);

    [DllImport(GLib, CallingConvention = CallingConvention.Cdecl)]
    private static extern void g_error_free(IntPtr error);

    [DllImport(GLib, CallingConvention = CallingConvention.Cdecl)]
    private static extern void g_free(IntPtr memory);

    [DllImport(GLib, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr g_main_context_default();

    // No explicit MarshalAs needed: glib's gboolean is a 4-byte gint, which is
    // exactly what .NET's default (unannotated) bool marshaling already uses
    // for P/Invoke (the Win32 BOOL convention) -- MarshalAs(I1) would be wrong
    // here (that's a 1-byte bool, for a different ABI).
    [DllImport(GLib, CallingConvention = CallingConvention.Cdecl)]
    private static extern bool g_main_context_iteration(IntPtr context, bool mayBlock);

    private static readonly object Gate = new object();
    private static bool initialized;
    private static IntPtr pipeline;
    private static IntPtr bus;
    private static IntPtr sink;
    private static uint minPort;
    private static uint maxPort;
    private static int consumersConfigured;
    private static string consumerError;
    // A live reference to the delegate must be kept for as long as native code
    // might call back through it -- otherwise the GC can collect it while
    // g_signal_connect_data's stored function pointer still points at it, and
    // the next signal emission calls freed/reused memory.
    private static ConsumerAddedDelegate consumerAddedCallback;

    public static bool IsRunning
    {
        get { lock (Gate) { return pipeline != IntPtr.Zero; } }
    }

    public static int ConsumersConfigured
    {
        get { lock (Gate) { return consumersConfigured; } }
    }

    private static string ReadGError(IntPtr error)
    {
        if (error == IntPtr.Zero) return "Unknown GStreamer error";
        GError value = (GError)Marshal.PtrToStructure(error, typeof(GError));
        return value.message == IntPtr.Zero ? "Unknown GStreamer error" : Marshal.PtrToStringAnsi(value.message);
    }

    private static void SetUintProperty(IntPtr obj, string name, uint number)
    {
        GValue value = new GValue();
        g_value_init(ref value, G_TYPE_UINT);
        try { g_value_set_uint(ref value, number); g_object_set_property(obj, name, ref value); }
        finally { g_value_unset(ref value); }
    }

    private static void OnConsumerAdded(IntPtr webrtcsink, IntPtr peerId, IntPtr consumerElement, IntPtr userData)
    {
        try
        {
            if (consumerElement == IntPtr.Zero)
                throw new InvalidOperationException("The WebRTC consumer element was not provided.");
            IntPtr iceAgent;
            g_object_get(consumerElement, "ice-agent", out iceAgent, IntPtr.Zero);
            if (iceAgent == IntPtr.Zero)
                throw new InvalidOperationException("The WebRTC consumer has no ICE agent.");
            try
            {
                SetUintProperty(iceAgent, "min-rtp-port", minPort);
                SetUintProperty(iceAgent, "max-rtp-port", maxPort);
                uint actualMin;
                uint actualMax;
                g_object_get_uint(iceAgent, "min-rtp-port", out actualMin, IntPtr.Zero);
                g_object_get_uint(iceAgent, "max-rtp-port", out actualMax, IntPtr.Zero);
                if (actualMin != minPort || actualMax != maxPort)
                    throw new InvalidOperationException("The ICE agent rejected the requested RTP port range.");
                System.Threading.Interlocked.Increment(ref consumersConfigured);
            }
            finally
            {
                g_object_unref(iceAgent);
            }
        }
        catch (Exception ex)
        {
            System.Threading.Interlocked.CompareExchange(
                ref consumerError, "Failed to apply WebRTC ICE port range: " + ex.Message, null);
        }
    }

    public static void Start(string pipelineDescription, uint minRtpPort, uint maxRtpPort, string sinkName)
    {
        lock (Gate)
        {
            StopUnsafe();
            if (!initialized) { gst_init(IntPtr.Zero, IntPtr.Zero); initialized = true; }
            minPort = minRtpPort;
            maxPort = maxRtpPort;
            consumersConfigured = 0;
            System.Threading.Interlocked.Exchange(ref consumerError, null);

            IntPtr parseError;
            pipeline = gst_parse_launch(pipelineDescription, out parseError);
            if (parseError != IntPtr.Zero)
            {
                string message = ReadGError(parseError);
                g_error_free(parseError);
                StopUnsafe();
                throw new InvalidOperationException("Pipeline parse failed: " + message);
            }
            if (pipeline == IntPtr.Zero)
                throw new InvalidOperationException("gst_parse_launch returned no pipeline.");

            sink = gst_bin_get_by_name(pipeline, sinkName);
            bus = gst_element_get_bus(pipeline);
            if (sink == IntPtr.Zero || bus == IntPtr.Zero)
            {
                StopUnsafe();
                throw new InvalidOperationException(
                    "The webrtcsink element '" + sinkName + "' or pipeline bus was not found.");
            }

            consumerAddedCallback = new ConsumerAddedDelegate(OnConsumerAdded);
            g_signal_connect_data(sink, "consumer-added", consumerAddedCallback, IntPtr.Zero, IntPtr.Zero, 0);

            int result = gst_element_set_state(pipeline, GST_STATE_PLAYING);
            if (result == GST_STATE_CHANGE_FAILURE)
            {
                StopUnsafe();
                throw new InvalidOperationException("Failed to set the pipeline to PLAYING.");
            }
        }
    }

    // The worker hosts the pipeline via gst_parse_launch + gst_element_set_state
    // directly instead of the real gst-launch-1.0.exe binary, which normally
    // runs g_main_loop_run() for the whole pipeline lifetime. Without that,
    // nothing ever services the default GMainContext -- so anything scheduled
    // on it via g_idle_add/g_timeout_add (RTCP timers, congestion-control
    // bandwidth estimation ticks, async I/O completions for the embedded
    // signalling/web server, clock-sync notifications) silently never fires.
    // Called from the worker's outer command-pipe loop in a tight sub-loop
    // (drain until no more pending sources) at a much finer cadence than that
    // loop's own ~200ms pipe-wait, so this behaves like a real main loop
    // instead of introducing its own scheduling jitter.
    public static bool PumpMainContextOnce()
    {
        return g_main_context_iteration(g_main_context_default(), false);
    }

    public static string PollTerminalMessage()
    {
        lock (Gate)
        {
            string callbackError = System.Threading.Interlocked.Exchange(ref consumerError, null);
            if (!String.IsNullOrEmpty(callbackError)) return callbackError;
            if (bus == IntPtr.Zero) return null;
            IntPtr errorMessage = gst_bus_timed_pop_filtered(bus, 0, GST_MESSAGE_ERROR);
            if (errorMessage != IntPtr.Zero)
            {
                try
                {
                    IntPtr error;
                    IntPtr debug;
                    gst_message_parse_error(errorMessage, out error, out debug);
                    try
                    {
                        string text = ReadGError(error);
                        string detail = debug == IntPtr.Zero ? null : Marshal.PtrToStringAnsi(debug);
                        return String.IsNullOrEmpty(detail) ? text : text + Environment.NewLine + detail;
                    }
                    finally
                    {
                        if (error != IntPtr.Zero) g_error_free(error);
                        if (debug != IntPtr.Zero) g_free(debug);
                    }
                }
                finally { gst_mini_object_unref(errorMessage); }
            }

            IntPtr eosMessage = gst_bus_timed_pop_filtered(bus, 0, GST_MESSAGE_EOS);
            if (eosMessage == IntPtr.Zero) return null;
            gst_mini_object_unref(eosMessage);
            return "Pipeline reached end of stream.";
        }
    }

    public static void Stop()
    {
        lock (Gate) { StopUnsafe(); }
    }

    private static void StopUnsafe()
    {
        if (pipeline != IntPtr.Zero)
        {
            gst_element_set_state(pipeline, GST_STATE_NULL);
            try
            {
                int current;
                int pending;
                gst_element_get_state(pipeline, out current, out pending, 2000000000UL);
            }
            catch { }
        }
        if (bus != IntPtr.Zero) gst_object_unref(bus);
        if (sink != IntPtr.Zero) gst_object_unref(sink);
        if (pipeline != IntPtr.Zero) gst_object_unref(pipeline);
        bus = sink = pipeline = IntPtr.Zero;
        consumerAddedCallback = null;
    }
}
'@
}

if ($ControlledLiveWorker) {
    # The live-edit broadcast deliberately lives in a disposable process. The
    # GUI sends compositor mutations over this pipe, while Stop/Restart kills
    # this complete process tree exactly like the legacy gst-launch path. That
    # hard process boundary is what closes every signalling socket reliably.
    if ([string]::IsNullOrWhiteSpace($ControlledLiveWorkerPipe)) { exit 64 }

    $pipeServer = $null
    $pipeReader = $null
    $pipeWriter = $null
    try {
        $pipeServer = New-Object System.IO.Pipes.NamedPipeServerStream(
            $ControlledLiveWorkerPipe,
            [System.IO.Pipes.PipeDirection]::InOut,
            1,
            [System.IO.Pipes.PipeTransmissionMode]::Byte,
            [System.IO.Pipes.PipeOptions]::None
        )
        $pipeServer.WaitForConnection()
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $pipeReader = New-Object System.IO.StreamReader($pipeServer, $utf8, $false, 4096, $true)
        $pipeWriter = New-Object System.IO.StreamWriter($pipeServer, $utf8, 4096, $true)
        $pipeWriter.AutoFlush = $true

        $startLine = $pipeReader.ReadLine()
        if ([string]::IsNullOrWhiteSpace($startLine)) { throw 'No start command was received.' }
        $start = $startLine | ConvertFrom-Json
        if ([string]$start.Type -ne 'Start') { throw 'The first worker command was not Start.' }

        # NOT [uint32](if (...) {...} else {...}) -- an if-statement wrapped
        # in bare parens with a type-cast prefix is not a valid PowerShell
        # expression (PowerShell tries to invoke "if" itself as a command,
        # failing with "The term 'if' is not recognized..."), regardless of
        # which branch would have been taken. This is exactly why going live
        # with the controlled worker always failed here while plain preview
        # (which never reaches this pipe-command handler at all -- see
        # GstControlledScenePreview::Start) never did. Precomputing into
        # plain variables first matches the already-working `$x = if (...)
        # {...} else {...}` (no wrapping parens) pattern used elsewhere in
        # this codebase, e.g. 27-StreamLifecycle.ps1's $workerMinRtpPort.
        $workerMinRtpPort = if ($start.MinRtpPort) { [uint32]$start.MinRtpPort } else { [uint32]0 }
        $workerMaxRtpPort = if ($start.MaxRtpPort) { [uint32]$start.MaxRtpPort } else { [uint32]0 }
        [GstControlledScenePreview]::StartLive(
            [string]$start.Pipeline,
            [int64]$start.WindowHandle,
            [int]$start.Width,
            [int]$start.Height,
            [string]$start.DesktopPad,
            [string]$start.WebcamPad,
            $workerMinRtpPort,
            $workerMaxRtpPort
        )
        $pipeWriter.WriteLine((@{ Status = 'Ready'; Error = '' } | ConvertTo-Json -Compress))

        $readTask = $pipeReader.ReadLineAsync()
        while ($true) {
            # This worker hosts webrtcsink directly via gst_parse_launch +
            # gst_element_set_state rather than gst-launch-1.0.exe's own
            # g_main_loop_run(), so nothing services the default GMainContext
            # (RTCP timers, congestion-control ticks, the embedded
            # signalling/web server's async I/O, clock-sync notifications)
            # without this -- see GstWebRtcConsumerPortRange's identical fix.
            while ([GstControlledScenePreview]::PumpMainContextOnce()) {}

            if ($readTask.Wait(5)) {
                $line = $readTask.Result
                if ($null -eq $line) { break }
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    $command = $line | ConvertFrom-Json
                    switch ([string]$command.Type) {
                        'Webcam' {
                            [GstControlledScenePreview]::UpdateWebcam(
                                [int]$command.X,
                                [int]$command.Y,
                                [int]$command.Width,
                                [int]$command.Height,
                                [double]$command.Alpha,
                                [uint32]$command.ZOrder,
                                [bool]$command.KeepAspect
                            )
                        }
                        'Window' {
                            [GstControlledScenePreview]::SetWindowHandle(
                                [int64]$command.WindowHandle,
                                [int]$command.Width,
                                [int]$command.Height
                            )
                        }
                    }
                }
                $readTask = $pipeReader.ReadLineAsync()
            }

            $terminal = [GstControlledScenePreview]::PollTerminalMessage()
            if ($terminal) { throw $terminal }
        }
    }
    catch {
        try {
            if ($pipeWriter -and $pipeServer -and $pipeServer.IsConnected) {
                $pipeWriter.WriteLine((@{ Status = 'Error'; Error = $_.Exception.Message } | ConvertTo-Json -Compress))
            }
        }
        catch {}
        [Console]::Error.WriteLine("Controlled live worker error: $($_.Exception)")
        exit 70
    }
    finally {
        try { [GstControlledScenePreview]::Stop() } catch {}
        try { if ($pipeWriter) { $pipeWriter.Dispose() } } catch {}
        try { if ($pipeReader) { $pipeReader.Dispose() } } catch {}
        try { if ($pipeServer) { $pipeServer.Dispose() } } catch {}
    }
    exit 0
}

if ($WebRtcPortRangeWorker) {
    # Disposable process, same reasoning as the controlled live worker above:
    # a hard process boundary is what reliably closes every signalling socket
    # and frees the pipeline, and Stop-GstStream already tree-kills whatever
    # process is assigned to $script:GstProcess -- reusing that exact same
    # mechanism here means no changes were needed to the stop path at all.
    if ([string]::IsNullOrWhiteSpace($WebRtcPortRangeWorkerPipe)) { exit 64 }

    $pipeServer = $null
    $pipeReader = $null
    $pipeWriter = $null
    try {
        $pipeServer = New-Object System.IO.Pipes.NamedPipeServerStream(
            $WebRtcPortRangeWorkerPipe,
            [System.IO.Pipes.PipeDirection]::InOut,
            1,
            [System.IO.Pipes.PipeTransmissionMode]::Byte,
            [System.IO.Pipes.PipeOptions]::None
        )
        $pipeServer.WaitForConnection()
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $pipeReader = New-Object System.IO.StreamReader($pipeServer, $utf8, $false, 4096, $true)
        $pipeWriter = New-Object System.IO.StreamWriter($pipeServer, $utf8, 4096, $true)
        $pipeWriter.AutoFlush = $true

        $startLine = $pipeReader.ReadLine()
        if ([string]::IsNullOrWhiteSpace($startLine)) { throw 'No start command was received.' }
        $start = $startLine | ConvertFrom-Json
        if ([string]$start.Type -ne 'Start') { throw 'The first worker command was not Start.' }

        [GstWebRtcConsumerPortRange]::Start(
            [string]$start.Pipeline,
            [uint32]$start.MinRtpPort,
            [uint32]$start.MaxRtpPort,
            'out'
        )
        $pipeWriter.WriteLine((@{ Status = 'Ready'; Error = '' } | ConvertTo-Json -Compress))

        $readTask = $pipeReader.ReadLineAsync()
        while ($true) {
            # This worker runs the pipeline via gst_parse_launch + gst_element_set_state
            # directly rather than the real gst-launch-1.0.exe binary, which normally
            # keeps a GMainLoop running for the pipeline's whole lifetime. Drain the
            # default GMainContext every tick so anything scheduled on it (RTCP
            # timers, congestion-control bandwidth estimation, async I/O for the
            # embedded signalling/web server, clock-sync notifications) actually
            # gets serviced -- previously nothing pumped this at all.
            while ([GstWebRtcConsumerPortRange]::PumpMainContextOnce()) {}

            if ($readTask.Wait(5)) {
                $line = $readTask.Result
                if ($null -eq $line) { break }
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    $command = $line | ConvertFrom-Json
                    if ([string]$command.Type -eq 'Stop') { break }
                }
                $readTask = $pipeReader.ReadLineAsync()
            }

            $terminal = [GstWebRtcConsumerPortRange]::PollTerminalMessage()
            if ($terminal) { throw $terminal }
        }
    }
    catch {
        try {
            if ($pipeWriter -and $pipeServer -and $pipeServer.IsConnected) {
                $pipeWriter.WriteLine((@{ Status = 'Error'; Error = $_.Exception.Message } | ConvertTo-Json -Compress))
            }
        }
        catch {}
        [Console]::Error.WriteLine("WebRTC port range worker error: $($_.Exception)")
        exit 70
    }
    finally {
        try { [GstWebRtcConsumerPortRange]::Stop() } catch {}
        try { if ($pipeWriter) { $pipeWriter.Dispose() } } catch {}
        try { if ($pipeReader) { $pipeReader.Dispose() } } catch {}
        try { if ($pipeServer) { $pipeServer.Dispose() } } catch {}
    }
    exit 0
}

if (-not ('GstProcessJob' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class GstProcessJob
{
    [StructLayout(LayoutKind.Sequential)]
    private struct IO_COUNTERS
    {
        public UInt64 ReadOperationCount;
        public UInt64 WriteOperationCount;
        public UInt64 OtherOperationCount;
        public UInt64 ReadTransferCount;
        public UInt64 WriteTransferCount;
        public UInt64 OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct JOBOBJECT_BASIC_LIMIT_INFORMATION
    {
        public Int64 PerProcessUserTimeLimit;
        public Int64 PerJobUserTimeLimit;
        public UInt32 LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public UInt32 ActiveProcessLimit;
        public UIntPtr Affinity;
        public UInt32 PriorityClass;
        public UInt32 SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateJobObject(IntPtr jobAttributes, string name);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetInformationJobObject(
        IntPtr job,
        int jobObjectInformationClass,
        IntPtr jobObjectInformation,
        UInt32 jobObjectInformationLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    private const UInt32 JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000;
    private const int JobObjectExtendedLimitInformation = 9;

    public static IntPtr CreateKillOnCloseJob()
    {
        IntPtr job = CreateJobObject(IntPtr.Zero, null);
        if (job == IntPtr.Zero)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateJobObject failed");

        JOBOBJECT_EXTENDED_LIMIT_INFORMATION info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
        info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;

        int length = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
        IntPtr buffer = Marshal.AllocHGlobal(length);
        try
        {
            Marshal.StructureToPtr(info, buffer, false);
            if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, buffer, (UInt32)length))
            {
                int error = Marshal.GetLastWin32Error();
                CloseHandle(job);
                throw new Win32Exception(error, "SetInformationJobObject failed");
            }
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }

        return job;
    }

    public static void AssignProcess(IntPtr job, IntPtr process)
    {
        if (job == IntPtr.Zero || process == IntPtr.Zero)
            throw new ArgumentException("A valid job and process handle are required.");

        if (!AssignProcessToJobObject(job, process))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "AssignProcessToJobObject failed");
    }

    public static void CloseJob(IntPtr job)
    {
        if (job != IntPtr.Zero)
            CloseHandle(job);
    }
}
'@
}

# A protocol-agnostic TLS-terminating TCP relay: accepts a TLS connection on
# an external port and blind-relays the decrypted byte stream to a plain TCP
# target -- webrtcsink's own HTTP/WS server, bound to loopback-only once this
# sits in front of it (see 17-DirectWebRtcPipeline.ps1). After TLS decryption
# a plain HTTPS GET and a WS upgrade handshake are just bytes indistinguishable
# from the unencrypted wire format, so one relay implementation covers both
# the web viewer and signalling sockets -- no HTTP-aware parsing needed. Not
# static like the classes above: multiple independent instances run at once
# (video signalling, split-audio signalling, web viewer), one per exposed
# port -- see src/27-StreamLifecycle.ps1 for where instances are started/
# stopped.
if (-not ('TlsTerminatingProxy' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

public class TlsTerminatingProxy
{
    // Diagnostic label set by the caller (e.g. "web viewer") -- purely
    // cosmetic, used only when formatting drained log messages.
    public string Label;

    // Canonical and legacy-alias authentication route paths, shared between
    // IsAuthenticationEndpointPath (classification) and
    // HandleAuthenticationAsync (dispatch) so the two can never drift apart.
    private const string CanonicalLoginPath = "/auth/login";
    private const string CanonicalLogoutPath = "/auth/logout";
    private const string CanonicalVerifyPath = "/auth/verify";
    private const string CanonicalStatusPath = "/auth/status";
    private const string CanonicalStreamStatusPath = "/auth/stream-status";
    private const string CanonicalTemporarySessionPath = "/auth/session";
    private const string CanonicalAccountSetupPath = "/auth/setup";
    private const string CanonicalRobotsPath = "/robots.txt";
    private const string TemporaryLinkUnavailableImageAssetPath = "/auth/assets/temporary-link-unavailable.png";
    private const string TemporaryLinkUnavailableMp4AssetPath = "/auth/assets/temporary-link-unavailable.mp4";
    private const string TemporaryLinkUnavailableWebmAssetPath = "/auth/assets/temporary-link-unavailable.webm";
    private const string RestartImageAssetPath = "/auth/assets/well-be-right-back.png";
    private const string RestartMp4AssetPath = "/auth/assets/well-be-right-back.mp4";
    private const string RestartWebmAssetPath = "/auth/assets/well-be-right-back.webm";
    private const string RestartPortraitImageAssetPath = "/auth/assets/well-be-right-back-portrait.png";
    private const string RestartPortraitMp4AssetPath = "/auth/assets/well-be-right-back-portrait.mp4";
    private const string RestartPortraitWebmAssetPath = "/auth/assets/well-be-right-back-portrait.webm";
    private const string LegacyLoginPath = "/__gstglass/auth/login";
    private const string LegacyLogoutPath = "/__gstglass/auth/logout";
    private const string LegacySimpleLogoutPath = "/logout";

    // One named account per viewer -- distinct from a single shared
    // credential, each account's own username is what gets embedded in and
    // checked against its issued session tokens (see CreateAuthenticationSessionToken
    // / ValidateAuthenticationSessionToken), so removing an account from the
    // configured list immediately invalidates any session still using it.
    public sealed class AuthenticationAccount
    {
        public string Username;
        public string PasswordHash;
        // Base32-encoded TOTP secret (RFC 6238/4226). Null/empty means this
        // account has no second factor and authenticates on password alone.
        public string TotpSecret;
    }

    private TcpListener listener;
    private X509Certificate2 certificate;
    // The "Secure" cookie attribute tells the browser to never send this
    // cookie back over a plain (non-HTTPS) connection -- correct and
    // necessary for the normal TLS-terminating proxy, but fatal for a
    // plaintext-auth relay (certificate == null): the browser would accept
    // the cookie on login, then silently withhold it on every later
    // request, making every session look logged-out immediately.
    private string CookieSecureAttribute { get { return certificate != null ? "; Secure" : ""; } }
    private string targetHost;
    private int targetPort;
    private volatile bool running;
    // Every currently-open upstream (proxy -> webrtcsink) connection this
    // instance is actively pumping, so a restart can proactively and
    // cleanly disconnect them -- see DisconnectActiveConnections. Without
    // this, a killed upstream process only gets noticed once the OS
    // eventually surfaces the dead socket to the pump's next read/write,
    // which is not bounded and is exactly what could leave a "Keep auth on
    // restarts" viewer connection in limbo instead of failing fast.
    private readonly System.Collections.Concurrent.ConcurrentDictionary<TcpClient, byte> activeUpstreamConnections = new System.Collections.Concurrent.ConcurrentDictionary<TcpClient, byte>();
    // Set right before the upstream (GST) process is killed for a restart,
    // cleared once it's back up -- see PauseForwarding/ResumeForwarding.
    // Exists specifically because a plaintext-auth relay's external and
    // internal ports are the SAME number by design (transparent same-port
    // takeover -- there's no override field for this, unlike the TLS
    // proxy, which normally uses a different external port and doesn't
    // hit this). This external listener binds IPAddress.Any (0.0.0.0),
    // which on Windows also answers loopback connects for that port when
    // nothing is bound to 127.0.0.1 specifically -- so while GST is down,
    // this proxy's own attempt to reach "127.0.0.1:samePort" can be
    // accepted by ITS OWN listener instead of failing, forwarding the
    // request back into itself and recursing without bound, pegging a CPU
    // core and making the whole host process (including Glass's own UI
    // thread) look hung. Verified directly: a TcpListener on
    // IPAddress.Any accepts a same-process connect to 127.0.0.1 on that
    // port when nothing else is bound to it. Refusing new forwards while
    // paused avoids ever attempting that connection in the first place.
    private volatile bool forwardingPaused;
    // Defense in depth for the same-port plaintext relay: every forwarded
    // first request carries an instance-unique hop marker. If the upstream
    // connect was actually accepted by THIS listener because GStreamer was
    // absent, the recursively-arriving request is rejected locally instead
    // of being forwarded into the listener again without bound. A random
    // per-instance value prevents an ordinary external client from guessing
    // the marker and manufacturing this internal-loop response.
    private readonly string proxyLoopToken = Guid.NewGuid().ToString("N");
    private bool authenticationEnabled;
    private List<AuthenticationAccount> authenticationAccounts = new List<AuthenticationAccount>();
    private byte[] authenticationSessionKey = new byte[0];
    private int authenticationSessionHours = 12;
    // X-Forwarded-For is attacker-controlled unless the TCP peer that supplied
    // it is explicitly trusted. Keep exact normalized proxy addresses here;
    // an empty set preserves socket-address behavior and is the safe default.
    private readonly HashSet<string> trustedForwardingProxyAddresses = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
    private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, AuthenticationFailureState> authenticationFailures = new System.Collections.Concurrent.ConcurrentDictionary<string, AuthenticationFailureState>();
    private static readonly SemaphoreSlim authenticationHashSlots = new SemaphoreSlim(2, 2);
    private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, long> activeAuthenticationSessions = new System.Collections.Concurrent.ConcurrentDictionary<string, long>();
    private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, string> authenticationSessionBoundAddresses = new System.Collections.Concurrent.ConcurrentDictionary<string, string>();
    private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, TemporaryAuthenticationLinkState> temporaryAuthenticationLinks = new System.Collections.Concurrent.ConcurrentDictionary<string, TemporaryAuthenticationLinkState>();
    // Password setup happens inside the isolated auth worker, but the UI owns
    // the durable account settings. Only the newly-derived password hash (and
    // optional TOTP secret), never plaintext, crosses back over the worker IPC
    // channel. PollLog drains this queue and applies each update to every live
    // proxy before returning it to the UI for persistence.
    private static readonly System.Collections.Concurrent.ConcurrentQueue<AuthenticationAccountUpdateState> pendingAuthenticationAccountUpdates = new System.Collections.Concurrent.ConcurrentQueue<AuthenticationAccountUpdateState>();
    // Shared by every proxy instance in this worker so the message artwork
    // and video loops are loaded only once even when video, audio, and viewer
    // ports are all gated.
    private static readonly object temporaryLinkUnavailableImageLock = new object();
    private static byte[] temporaryLinkUnavailableImageBytes = new byte[0];
    private static string temporaryLinkUnavailableImagePath = "";
    private static byte[] temporaryLinkUnavailableMp4Bytes = new byte[0];
    private static byte[] temporaryLinkUnavailableWebmBytes = new byte[0];
    private static string temporaryLinkUnavailableMp4Path = "";
    private static string temporaryLinkUnavailableWebmPath = "";
    private static readonly object restartImageLock = new object();
    private static byte[] restartImageBytes = new byte[0];
    private static string restartImagePath = "";
    private static byte[] restartMp4Bytes = new byte[0];
    private static byte[] restartWebmBytes = new byte[0];
    private static string restartMp4Path = "";
    private static string restartWebmPath = "";
    private static byte[] restartPortraitImageBytes = new byte[0];
    private static string restartPortraitImagePath = "";
    private static byte[] restartPortraitMp4Bytes = new byte[0];
    private static byte[] restartPortraitWebmBytes = new byte[0];
    private static string restartPortraitMp4Path = "";
    private static string restartPortraitWebmPath = "";

    // The five auth-proxy page templates (gstwebrtc-api/dist/auth-proxy/*.html)
    // -- read once per configured path and cached as text, same shape as the
    // restart image/video caching above, just ReadAllText instead of
    // ReadAllBytes since these get per-request placeholder substitution
    // rather than being streamed as-is. Shared lock: these are configured
    // together (one StartFamily command) and read far more often than
    // written, so one lock for all five is simpler than five separate ones
    // and never a real contention point.
    private static readonly object authTemplateLock = new object();
    // Defaults to the built-in fallback constant (defined below), not "" --
    // an instance that never gets its Configure*Template method called at
    // all (e.g. a test constructing this class directly) must serve the
    // same safe minimal page a failed-to-load template falls back to, not a
    // blank body.
    private static string loginTemplatePath = "";
    private static string loginTemplateText = FallbackLoginHtml;
    private static string linkConfirmTemplatePath = "";
    private static string linkConfirmTemplateText = FallbackLinkConfirmHtml;
    private static string accountSetupTemplatePath = "";
    private static string accountSetupTemplateText = FallbackAccountSetupHtml;
    private static string totpChallengeTemplatePath = "";
    private static string totpChallengeTemplateText = FallbackTotpChallengeHtml;
    private static string mediaMessageTemplatePath = "";
    private static string mediaMessageTemplateText = FallbackMediaMessageHtml;

    // Async continuations resume on arbitrary ThreadPool threads with no
    // PowerShell runspace bound to them, so failures here cannot invoke a
    // PowerShell callback directly (that throws "no Runspace available"
    // and, since this all runs under async void, crashes the process).
    // Queue messages instead and let the UI-thread poll timer drain them
    // via PollLogMessage(), the same pattern PollTerminalMessage() uses
    // for GstControlledScenePreview/GstWebRtcConsumerPortRange.
    private readonly System.Collections.Concurrent.ConcurrentQueue<string> pendingLog = new System.Collections.Concurrent.ConcurrentQueue<string>();

    public void ConfigureTemporaryLinkUnavailableImage(string imagePath)
    {
        string normalizedPath = imagePath ?? "";
        try
        {
            if (!string.IsNullOrWhiteSpace(normalizedPath)) normalizedPath = Path.GetFullPath(normalizedPath);
        }
        catch
        {
            normalizedPath = "";
        }

        lock (temporaryLinkUnavailableImageLock)
        {
            if (string.Equals(temporaryLinkUnavailableImagePath, normalizedPath, StringComparison.OrdinalIgnoreCase) && temporaryLinkUnavailableImageBytes.Length > 0) return;
            temporaryLinkUnavailableImagePath = normalizedPath;
            temporaryLinkUnavailableImageBytes = new byte[0];
            if (string.IsNullOrEmpty(normalizedPath)) return;

            try
            {
                byte[] imageBytes = File.ReadAllBytes(normalizedPath);
                bool isPng = imageBytes.Length >= 8 &&
                    imageBytes[0] == 0x89 && imageBytes[1] == 0x50 && imageBytes[2] == 0x4E && imageBytes[3] == 0x47 &&
                    imageBytes[4] == 0x0D && imageBytes[5] == 0x0A && imageBytes[6] == 0x1A && imageBytes[7] == 0x0A;
                if (!isPng) throw new InvalidDataException("The configured file is not a PNG image.");
                temporaryLinkUnavailableImageBytes = imageBytes;
                pendingLog.Enqueue("loaded temporary-link rejection image from " + normalizedPath);
            }
            catch (Exception ex)
            {
                pendingLog.Enqueue("could not load temporary-link rejection image; using the text fallback: " + ex.Message);
            }
        }
    }

    public void ConfigureRestartImage(string imagePath)
    {
        string normalizedPath = imagePath ?? "";
        try
        {
            if (!string.IsNullOrWhiteSpace(normalizedPath)) normalizedPath = Path.GetFullPath(normalizedPath);
        }
        catch
        {
            normalizedPath = "";
        }

        lock (restartImageLock)
        {
            if (string.Equals(restartImagePath, normalizedPath, StringComparison.OrdinalIgnoreCase) && restartImageBytes.Length > 0) return;
            restartImagePath = normalizedPath;
            restartImageBytes = new byte[0];
            if (string.IsNullOrEmpty(normalizedPath)) return;

            try
            {
                byte[] imageBytes = File.ReadAllBytes(normalizedPath);
                bool isPng = imageBytes.Length >= 8 &&
                    imageBytes[0] == 0x89 && imageBytes[1] == 0x50 && imageBytes[2] == 0x4E && imageBytes[3] == 0x47 &&
                    imageBytes[4] == 0x0D && imageBytes[5] == 0x0A && imageBytes[6] == 0x1A && imageBytes[7] == 0x0A;
                if (!isPng) throw new InvalidDataException("The configured file is not a PNG image.");
                restartImageBytes = imageBytes;
                pendingLog.Enqueue("loaded stream-restart image from " + normalizedPath);
            }
            catch (Exception ex)
            {
                pendingLog.Enqueue("could not load stream-restart image; using the text fallback: " + ex.Message);
            }
        }
    }

    public void ConfigureRestartPortraitImage(string imagePath)
    {
        string normalizedPath = NormalizeMessageAssetPath(imagePath);
        lock (restartImageLock)
        {
            if (string.Equals(restartPortraitImagePath, normalizedPath, StringComparison.OrdinalIgnoreCase) && restartPortraitImageBytes.Length > 0) return;
            restartPortraitImagePath = normalizedPath;
            restartPortraitImageBytes = new byte[0];
            if (string.IsNullOrEmpty(normalizedPath)) return;

            try
            {
                byte[] imageBytes = File.ReadAllBytes(normalizedPath);
                bool isPng = imageBytes.Length >= 8 &&
                    imageBytes[0] == 0x89 && imageBytes[1] == 0x50 && imageBytes[2] == 0x4E && imageBytes[3] == 0x47 &&
                    imageBytes[4] == 0x0D && imageBytes[5] == 0x0A && imageBytes[6] == 0x1A && imageBytes[7] == 0x0A;
                if (!isPng) throw new InvalidDataException("The configured file is not a PNG image.");
                restartPortraitImageBytes = imageBytes;
                pendingLog.Enqueue("loaded portrait stream-restart image from " + normalizedPath);
            }
            catch (Exception ex)
            {
                pendingLog.Enqueue("could not load portrait stream-restart image; using the landscape fallback: " + ex.Message);
            }
        }
    }

    private byte[] LoadMessageVideo(string videoPath, bool webm, string description)
    {
        if (string.IsNullOrWhiteSpace(videoPath)) return new byte[0];
        try
        {
            string normalizedPath = Path.GetFullPath(videoPath);
            byte[] videoBytes = File.ReadAllBytes(normalizedPath);
            bool valid = webm
                ? videoBytes.Length >= 4 && videoBytes[0] == 0x1A && videoBytes[1] == 0x45 && videoBytes[2] == 0xDF && videoBytes[3] == 0xA3
                : videoBytes.Length >= 12 && videoBytes[4] == 0x66 && videoBytes[5] == 0x74 && videoBytes[6] == 0x79 && videoBytes[7] == 0x70;
            if (!valid) throw new InvalidDataException("The configured file is not a valid " + (webm ? "WebM" : "MP4") + " video.");
            pendingLog.Enqueue("loaded " + description + " video from " + normalizedPath);
            return videoBytes;
        }
        catch (Exception ex)
        {
            pendingLog.Enqueue("could not load " + description + " video: " + ex.Message);
            return new byte[0];
        }
    }

    public void ConfigureTemporaryLinkUnavailableVideos(string mp4Path, string webmPath)
    {
        string normalizedMp4Path = NormalizeMessageAssetPath(mp4Path);
        string normalizedWebmPath = NormalizeMessageAssetPath(webmPath);
        lock (temporaryLinkUnavailableImageLock)
        {
            if (string.Equals(temporaryLinkUnavailableMp4Path, normalizedMp4Path, StringComparison.OrdinalIgnoreCase) &&
                string.Equals(temporaryLinkUnavailableWebmPath, normalizedWebmPath, StringComparison.OrdinalIgnoreCase)) return;
            temporaryLinkUnavailableMp4Path = normalizedMp4Path;
            temporaryLinkUnavailableWebmPath = normalizedWebmPath;
            temporaryLinkUnavailableMp4Bytes = LoadMessageVideo(normalizedMp4Path, false, "temporary-link rejection MP4");
            temporaryLinkUnavailableWebmBytes = LoadMessageVideo(normalizedWebmPath, true, "temporary-link rejection WebM");
        }
    }

    public void ConfigureRestartVideos(string mp4Path, string webmPath)
    {
        string normalizedMp4Path = NormalizeMessageAssetPath(mp4Path);
        string normalizedWebmPath = NormalizeMessageAssetPath(webmPath);
        lock (restartImageLock)
        {
            if (string.Equals(restartMp4Path, normalizedMp4Path, StringComparison.OrdinalIgnoreCase) &&
                string.Equals(restartWebmPath, normalizedWebmPath, StringComparison.OrdinalIgnoreCase)) return;
            restartMp4Path = normalizedMp4Path;
            restartWebmPath = normalizedWebmPath;
            restartMp4Bytes = LoadMessageVideo(normalizedMp4Path, false, "stream-restart MP4");
            restartWebmBytes = LoadMessageVideo(normalizedWebmPath, true, "stream-restart WebM");
        }
    }

    public void ConfigureRestartPortraitVideos(string mp4Path, string webmPath)
    {
        string normalizedMp4Path = NormalizeMessageAssetPath(mp4Path);
        string normalizedWebmPath = NormalizeMessageAssetPath(webmPath);
        lock (restartImageLock)
        {
            if (string.Equals(restartPortraitMp4Path, normalizedMp4Path, StringComparison.OrdinalIgnoreCase) &&
                string.Equals(restartPortraitWebmPath, normalizedWebmPath, StringComparison.OrdinalIgnoreCase)) return;
            restartPortraitMp4Path = normalizedMp4Path;
            restartPortraitWebmPath = normalizedWebmPath;
            restartPortraitMp4Bytes = LoadMessageVideo(normalizedMp4Path, false, "portrait stream-restart MP4");
            restartPortraitWebmBytes = LoadMessageVideo(normalizedWebmPath, true, "portrait stream-restart WebM");
        }
    }

    private static string NormalizeMessageAssetPath(string assetPath)
    {
        if (string.IsNullOrWhiteSpace(assetPath)) return "";
        try { return Path.GetFullPath(assetPath); }
        catch { return ""; }
    }

    // Minimal, unstyled fallback markup for each auth-proxy page -- used
    // only if its real template file (gstwebrtc-api/dist/auth-proxy/*.html)
    // is missing or fails to load. A missing restart-page image just means
    // no picture shows; a missing LOGIN template must not mean nobody can
    // authenticate at all, so every page keeps a working (if plain) form
    // here rather than failing the request outright.
    private const string FallbackLoginHtml =
        "<!doctype html><html><head><meta charset=\"utf-8\"><title>GStreamer Glass - Viewer Login</title></head><body>" +
        "<h1>GStreamer Glass</h1><p>This broadcast requires viewer authentication.</p>{{ERROR_BLOCK}}" +
        "<form method=\"post\" action=\"./login\"><input type=\"hidden\" name=\"return\" value=\"{{RETURN_TARGET}}\">" +
        "<label>Username <input name=\"username\" autocomplete=\"username\" required autofocus></label><br>" +
        "<label>Password <input name=\"password\" type=\"password\" autocomplete=\"current-password\" required></label><br>" +
        "<button type=\"submit\">Watch broadcast</button></form></body></html>";
    private const string FallbackLinkConfirmHtml =
        "<!doctype html><html><head><meta charset=\"utf-8\"><title>GStreamer Glass - Open Broadcast</title></head><body>" +
        "<h1>Open broadcast?</h1><p>{{LINK_DESCRIPTION}}</p>" +
        "<form method=\"post\" action=\"/auth/session\"><input type=\"hidden\" name=\"token\" value=\"{{TOKEN}}\">" +
        "<input type=\"hidden\" name=\"return\" value=\"{{RETURN_TARGET}}\"><button type=\"submit\">Continue to broadcast</button></form></body></html>";
    private const string FallbackAccountSetupHtml =
        "<!doctype html><html><head><meta charset=\"utf-8\"><title>GStreamer Glass - Account Setup</title></head><body>" +
        "<h1>Set up {{USERNAME}}</h1><p>Choose a new password for this viewer account.</p>{{ERROR_BLOCK}}" +
        "<form method=\"post\" action=\"/auth/setup\"><input type=\"hidden\" name=\"token\" value=\"{{TOKEN}}\">" +
        "<input type=\"hidden\" name=\"return\" value=\"{{RETURN_TARGET}}\">" +
        "<label>New password <input name=\"password\" type=\"password\" minlength=\"10\" maxlength=\"256\" autocomplete=\"new-password\" required autofocus></label><br>" +
        "<label>Confirm password <input name=\"confirm\" type=\"password\" minlength=\"10\" maxlength=\"256\" autocomplete=\"new-password\" required></label><br>" +
        "{{TOTP_FIELDS}}<button type=\"submit\">Save account and continue</button></form></body></html>";
    private const string FallbackTotpChallengeHtml =
        "<!doctype html><html><head><meta charset=\"utf-8\"><title>GStreamer Glass - Verification Code</title></head><body>" +
        "<h1>Verification code</h1><p>Enter the 6-digit code from your authenticator app.</p>{{ERROR_BLOCK}}" +
        "<form method=\"post\" action=\"./verify\"><input type=\"hidden\" name=\"pending\" value=\"{{PENDING_TOKEN}}\">" +
        "<input type=\"hidden\" name=\"return\" value=\"{{RETURN_TARGET}}\">" +
        "<label>Code <input name=\"code\" inputmode=\"numeric\" pattern=\"[0-9]{6}\" maxlength=\"6\" autocomplete=\"one-time-code\" required autofocus></label><br>" +
        "<label><input type=\"checkbox\" name=\"remember\" value=\"1\"> Remember this device for {{TRUSTED_DEVICE_DAYS}} days</label><br>" +
        "<button type=\"submit\">Verify</button></form></body></html>";
    private const string FallbackMediaMessageHtml =
        "<!doctype html><html><head><meta charset=\"utf-8\"><title>{{TITLE}}</title></head><body>{{MEDIA_MARKUP}}{{SCRIPT_BLOCK}}</body></html>";

    // Shared by every Configure*Template method: normalize path, skip if
    // unchanged and already cached (matches ConfigureRestartImage's shape),
    // File.ReadAllText once, sanity-check it looks like an HTML document (a
    // deliberately loose check -- these are trusted, locally-authored files,
    // not untrusted input; this only guards against pointing the path at
    // something obviously wrong, not against malformed markup within an
    // otherwise-real template), cache or fall back to the built-in minimal
    // page on any failure.
    private string LoadTemplateText(string templatePath, string description, string fallback)
    {
        if (string.IsNullOrWhiteSpace(templatePath)) return fallback;
        try
        {
            string text = File.ReadAllText(templatePath);
            if (text.IndexOf("<!doctype html>", StringComparison.OrdinalIgnoreCase) < 0)
            {
                throw new InvalidDataException("The configured file does not look like an HTML document.");
            }
            pendingLog.Enqueue("loaded " + description + " template from " + templatePath);
            return text;
        }
        catch (Exception ex)
        {
            pendingLog.Enqueue("could not load " + description + " template; using the built-in fallback page: " + ex.Message);
            return fallback;
        }
    }

    public void ConfigureLoginTemplate(string templatePath)
    {
        string normalizedPath = NormalizeMessageAssetPath(templatePath);
        lock (authTemplateLock)
        {
            if (string.Equals(loginTemplatePath, normalizedPath, StringComparison.OrdinalIgnoreCase) && loginTemplateText.Length > 0) return;
            loginTemplatePath = normalizedPath;
            loginTemplateText = LoadTemplateText(normalizedPath, "login page", FallbackLoginHtml);
        }
    }

    public void ConfigureLinkConfirmTemplate(string templatePath)
    {
        string normalizedPath = NormalizeMessageAssetPath(templatePath);
        lock (authTemplateLock)
        {
            if (string.Equals(linkConfirmTemplatePath, normalizedPath, StringComparison.OrdinalIgnoreCase) && linkConfirmTemplateText.Length > 0) return;
            linkConfirmTemplatePath = normalizedPath;
            linkConfirmTemplateText = LoadTemplateText(normalizedPath, "temporary-link confirmation page", FallbackLinkConfirmHtml);
        }
    }

    public void ConfigureAccountSetupTemplate(string templatePath)
    {
        string normalizedPath = NormalizeMessageAssetPath(templatePath);
        lock (authTemplateLock)
        {
            if (string.Equals(accountSetupTemplatePath, normalizedPath, StringComparison.OrdinalIgnoreCase) && accountSetupTemplateText.Length > 0) return;
            accountSetupTemplatePath = normalizedPath;
            accountSetupTemplateText = LoadTemplateText(normalizedPath, "account setup page", FallbackAccountSetupHtml);
        }
    }

    public void ConfigureTotpChallengeTemplate(string templatePath)
    {
        string normalizedPath = NormalizeMessageAssetPath(templatePath);
        lock (authTemplateLock)
        {
            if (string.Equals(totpChallengeTemplatePath, normalizedPath, StringComparison.OrdinalIgnoreCase) && totpChallengeTemplateText.Length > 0) return;
            totpChallengeTemplatePath = normalizedPath;
            totpChallengeTemplateText = LoadTemplateText(normalizedPath, "TOTP challenge page", FallbackTotpChallengeHtml);
        }
    }

    public void ConfigureMediaMessageTemplate(string templatePath)
    {
        string normalizedPath = NormalizeMessageAssetPath(templatePath);
        lock (authTemplateLock)
        {
            if (string.Equals(mediaMessageTemplatePath, normalizedPath, StringComparison.OrdinalIgnoreCase) && mediaMessageTemplateText.Length > 0) return;
            mediaMessageTemplatePath = normalizedPath;
            mediaMessageTemplateText = LoadTemplateText(normalizedPath, "restart/holding page", FallbackMediaMessageHtml);
        }
    }

    // Optional path -> internal-port overrides, checked against the decrypted
    // HTTP request's path before falling back to the default target. Lets one
    // external port also serve path-routed WebSocket signaling endpoints (the
    // "Video path"/"Voice path" fields), mirroring what an external IIS/HAProxy
    // URL-rewrite rule does in front of Glass -- see tools/examples/IIS/live/web.config.
    private readonly System.Collections.Generic.List<Tuple<string, int>> pathRoutes = new System.Collections.Generic.List<Tuple<string, int>>();

    // When set (e.g. "/live"), a bare GET for exactly this path (no trailing
    // slash) gets a 301 to path + "/" instead of being forwarded as-is.
    // webrtcsink's static file serving resolves the page's own relative
    // asset URLs (script/style tags with no leading slash) against the
    // current directory, which only works once the browser's address bar
    // actually ends in "/" -- without this, loading the bare path serves
    // the HTML but every relative asset 404s.
    public string DirectoryRedirectPath;

    // Viewer mount used for proxy-owned authentication endpoints. This is
    // deliberately independent of DirectoryRedirectPath: when viewer HTTP
    // and signaling share one external port, the signaling proxy is reused
    // and does not need the directory redirect, but it still owns auth URLs
    // at the permanent origin-level /auth/ gate. The viewer mount is retained
    // only for protected-content redirects and legacy compatibility aliases.
    public string AuthenticationMountPath;

    private sealed class AuthenticationFailureState
    {
        public int Count;
        public DateTime WindowStartedUtc;
        public DateTime LockedUntilUtc;
    }

    public sealed class AuthenticationSessionState
    {
        public string Token;
        public long Expires;
        public string BoundAddress;
    }

    public sealed class TemporaryAuthenticationLinkState
    {
        public string Token;
        public string Username;
        public long Expires;
        public bool SingleUse;
        public string BoundAddress;
        // "session" grants temporary viewer access. "setup" is always
        // single-use and lets the named account replace its password.
        public string Purpose;
        public bool RequireTotp;
        // Present only for setup links that require enrolling a fresh second
        // factor. Setup links are bearer secrets already and the worker's
        // persisted cache is DPAPI-protected.
        public string TotpSecret;
    }

    public sealed class AuthenticationAccountUpdateState
    {
        public string Username;
        public string PasswordHash;
        public string TotpSecret;
        public int SessionsRevoked;
    }

    public sealed class TemporaryAuthenticationLinkRevocationState
    {
        public bool LinkRemoved;
        public string Username;
        public int SessionsRevoked;
    }

    public void ConfigureAuthentication(bool enabled, AuthenticationAccount[] accounts, byte[] sessionKey, int sessionHours)
    {
        authenticationEnabled = enabled;
        List<AuthenticationAccount> normalized = new List<AuthenticationAccount>();
        if (accounts != null)
        {
            foreach (AuthenticationAccount account in accounts)
            {
                if (account == null || string.IsNullOrWhiteSpace(account.Username) || string.IsNullOrWhiteSpace(account.PasswordHash)) continue;
                normalized.Add(new AuthenticationAccount { Username = account.Username.Trim(), PasswordHash = account.PasswordHash, TotpSecret = account.TotpSecret });
            }
        }
        authenticationAccounts = normalized;
        authenticationSessionKey = sessionKey == null ? new byte[0] : (byte[])sessionKey.Clone();
        authenticationSessionHours = Math.Max(1, Math.Min(168, sessionHours));
    }

    public void ConfigureTrustedForwardingProxies(string[] addresses)
    {
        trustedForwardingProxyAddresses.Clear();
        if (addresses == null) return;
        foreach (string value in addresses)
        {
            IPAddress address;
            if (!IPAddress.TryParse((value ?? "").Trim(), out address)) continue;
            trustedForwardingProxyAddresses.Add(NormalizeIpAddress(address));
        }
    }

    private AuthenticationAccount FindAuthenticationAccount(string username)
    {
        if (string.IsNullOrEmpty(username)) return null;
        foreach (AuthenticationAccount account in authenticationAccounts)
        {
            if (string.Equals(account.Username, username, StringComparison.Ordinal)) return account;
        }
        return null;
    }

    public static byte[] CreateAuthenticationSessionKey()
    {
        byte[] key = new byte[32];
        using (RandomNumberGenerator random = RandomNumberGenerator.Create())
        {
            random.GetBytes(key);
        }
        return key;
    }

    public static string HashAuthenticationPassword(string password)
    {
        if (password == null) throw new ArgumentNullException("password");
        byte[] salt = new byte[16];
        using (RandomNumberGenerator random = RandomNumberGenerator.Create())
        {
            random.GetBytes(salt);
        }
        const int iterations = 600000;
        byte[] hash = Pbkdf2Sha256(password, salt, iterations, 32);
        return "pbkdf2-sha256$" + iterations.ToString() + "$" + Convert.ToBase64String(salt) + "$" + Convert.ToBase64String(hash);
    }

    public static bool IsAuthenticationPasswordHashValid(string encodedHash)
    {
        try
        {
            string[] parts = (encodedHash ?? "").Split('$');
            if (parts.Length != 4 || parts[0] != "pbkdf2-sha256") return false;
            int iterations;
            if (!int.TryParse(parts[1], out iterations) || iterations < 100000 || iterations > 2000000) return false;
            return Convert.FromBase64String(parts[2]).Length >= 16 && Convert.FromBase64String(parts[3]).Length == 32;
        }
        catch { return false; }
    }

    // TOTP (RFC 6238, built on the HOTP counter algorithm from RFC 4226):
    // a 20-byte (160-bit) secret, SHA-1 HMAC, 30-second time steps, 6-digit
    // codes -- the same parameters every mainstream authenticator app
    // (Google Authenticator, Authy, 1Password, etc.) assumes by default, so
    // no per-account configuration of algorithm/digits/period is exposed.
    private const string Base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

    public static string GenerateTotpSecret()
    {
        byte[] secretBytes = new byte[20];
        using (RandomNumberGenerator random = RandomNumberGenerator.Create())
        {
            random.GetBytes(secretBytes);
        }
        return Base32Encode(secretBytes);
    }

    private static string Base32Encode(byte[] data)
    {
        if (data == null || data.Length == 0) return "";
        StringBuilder result = new StringBuilder();
        int bitBuffer = 0;
        int bitCount = 0;
        foreach (byte b in data)
        {
            bitBuffer = (bitBuffer << 8) | b;
            bitCount += 8;
            while (bitCount >= 5)
            {
                bitCount -= 5;
                result.Append(Base32Alphabet[(bitBuffer >> bitCount) & 0x1F]);
            }
        }
        if (bitCount > 0)
        {
            result.Append(Base32Alphabet[(bitBuffer << (5 - bitCount)) & 0x1F]);
        }
        return result.ToString();
    }

    private static byte[] Base32Decode(string input)
    {
        string clean = (input ?? "").Trim().ToUpperInvariant().Replace("-", "").Replace(" ", "").TrimEnd('=');
        if (clean.Length == 0) return new byte[0];
        List<byte> output = new List<byte>();
        int bitBuffer = 0;
        int bitCount = 0;
        foreach (char c in clean)
        {
            int value = Base32Alphabet.IndexOf(c);
            if (value < 0) throw new FormatException("Invalid Base32 character.");
            bitBuffer = (bitBuffer << 5) | value;
            bitCount += 5;
            if (bitCount >= 8)
            {
                bitCount -= 8;
                output.Add((byte)((bitBuffer >> bitCount) & 0xFF));
            }
        }
        return output.ToArray();
    }

    // RFC 4226 SS5.3 dynamic truncation, fixed at 6 digits (10^6).
    private static string ComputeTotpCode(byte[] secretBytes, long timeStep)
    {
        byte[] counter = BitConverter.GetBytes(timeStep);
        if (BitConverter.IsLittleEndian) Array.Reverse(counter);
        byte[] hash;
        using (HMACSHA1 hmac = new HMACSHA1(secretBytes))
        {
            hash = hmac.ComputeHash(counter);
        }
        int offset = hash[hash.Length - 1] & 0x0F;
        int binaryCode =
            ((hash[offset] & 0x7F) << 24) |
            ((hash[offset + 1] & 0xFF) << 16) |
            ((hash[offset + 2] & 0xFF) << 8) |
            (hash[offset + 3] & 0xFF);
        return (binaryCode % 1000000).ToString("D6", System.Globalization.CultureInfo.InvariantCulture);
    }

    // Accepts the current 30s window plus one step on either side (a total
    // 90s span) to tolerate ordinary clock drift between the viewer's phone
    // and this machine without meaningfully widening the guessable window.
    public static bool VerifyTotpCode(string base32Secret, string submittedCode)
    {
        if (string.IsNullOrWhiteSpace(base32Secret) || string.IsNullOrWhiteSpace(submittedCode)) return false;
        string normalizedCode = submittedCode.Trim();
        if (normalizedCode.Length != 6) return false;
        foreach (char c in normalizedCode) { if (c < '0' || c > '9') return false; }
        byte[] secretBytes;
        try { secretBytes = Base32Decode(base32Secret); }
        catch { return false; }
        if (secretBytes.Length == 0) return false;
        long currentStep = ToUnixTimeSeconds(DateTime.UtcNow) / 30;
        byte[] suppliedBytes = Encoding.ASCII.GetBytes(normalizedCode);
        for (long stepOffset = -1; stepOffset <= 1; stepOffset++)
        {
            string expected = ComputeTotpCode(secretBytes, currentStep + stepOffset);
            if (FixedTimeEquals(Encoding.ASCII.GetBytes(expected), suppliedBytes)) return true;
        }
        return false;
    }

    // certificate == null runs this relay in plaintext mode: no TLS
    // handshake at all, used for "Allow plaintext auth" (the same login
    // gate/session-cookie/path-routing logic, just over an unencrypted
    // connection -- session cookies then travel in cleartext, acceptable
    // only when something else already terminates TLS in front of Glass,
    // or the operator has otherwise accepted that risk).
    public void Start(int externalPort, string targetHost, int targetPort, X509Certificate2 certificate)
    {
        this.targetHost = targetHost;
        this.targetPort = targetPort;
        this.certificate = certificate;
        this.listener = new TcpListener(IPAddress.Any, externalPort);
        this.listener.Start();
        this.running = true;
        AcceptLoop();
    }

    public void AddPathRoute(string path, int internalPort)
    {
        if (string.IsNullOrWhiteSpace(path) || internalPort <= 0) return;
        pathRoutes.Add(Tuple.Create(path.TrimEnd('/'), internalPort));
    }

    public void Stop()
    {
        running = false;
        try { if (listener != null) listener.Stop(); } catch { }
    }

    // Proactively and immediately severs every connection this instance is
    // currently pumping to its upstream (webrtcsink), without stopping the
    // listener itself -- for "Keep auth on restarts", where the proxy
    // keeps accepting new connections across a stream restart but the
    // upstream process is about to be killed. Called from PowerShell right
    // before that kill, so already-connected viewers get a clean,
    // immediate disconnect (their browser's reconnect logic kicks in
    // right away) instead of waiting on the OS to eventually notice the
    // killed process's socket died.
    //
    // Uses an abortive close (LingerState with a zero timeout, which sends
    // an immediate RST) rather than the default graceful close/FIN --
    // graceful close can block waiting for an ACK that will never come
    // once the upstream process is gone, which is exactly the kind of
    // indefinite wait this exists to avoid.
    public void DisconnectActiveConnections()
    {
        foreach (TcpClient upstream in activeUpstreamConnections.Keys)
        {
            try
            {
                upstream.LingerState = new LingerOption(true, 0);
                upstream.Close();
            }
            catch { }
        }
    }

    // Call right before killing the upstream (GST) process for a restart.
    // While paused, new requests get an immediate 503 instead of this
    // instance attempting to reach upstream at all -- see the comment on
    // forwardingPaused for why that connection attempt itself is unsafe
    // during this window. Does not affect already-open pumped connections
    // (see DisconnectActiveConnections for those) or the listener itself
    // -- new connections are still accepted, just answered locally.
    public void PauseForwarding()
    {
        forwardingPaused = true;
    }

    // Call once the upstream process is confirmed back up (or at least
    // has been given a moment to start listening again).
    public void ResumeForwarding()
    {
        forwardingPaused = false;
    }

    // Invalidates every currently-issued session token immediately (across
    // ALL proxy instances -- activeAuthenticationSessions is static/shared
    // by design, same as the rate limiter). Deliberately does NOT touch the
    // listener: HasValidAuthenticationCookie starts failing for everyone on
    // their very next request, which the existing ordinary-request path in
    // HandleAuthenticationAsync already turns into a 303 to /auth/login --
    // no new redirect logic needed. Stopping the listener instead (as this
    // used to do) meant that redirect could never actually reach a client:
    // once torn down, every subsequent request just gets a hard connection
    // refusal, forever, which is indistinguishable from the server being
    // gone and leaves a stale tab stuck rather than bounced to login.
    public void RevokeAllSessions()
    {
        activeAuthenticationSessions.Clear();
        authenticationSessionBoundAddresses.Clear();
    }

    // The UI process uses these two methods only for the opt-in
    // "Keep auth on exit" cache. Session tokens are still useless without
    // the per-family HMAC key and are additionally protected at rest with
    // Windows DPAPI; keeping the registry is necessary because validation
    // deliberately requires both a sound signature and live membership.
    public AuthenticationSessionState[] ExportActiveAuthenticationSessions()
    {
        RemoveExpiredAuthenticationSessions();
        List<AuthenticationSessionState> result = new List<AuthenticationSessionState>();
        foreach (KeyValuePair<string, long> session in activeAuthenticationSessions)
        {
            string boundAddress;
            authenticationSessionBoundAddresses.TryGetValue(session.Key, out boundAddress);
            result.Add(new AuthenticationSessionState { Token = session.Key, Expires = session.Value, BoundAddress = boundAddress ?? "" });
        }
        return result.ToArray();
    }

    public void RestoreActiveAuthenticationSessions(AuthenticationSessionState[] sessions)
    {
        activeAuthenticationSessions.Clear();
        authenticationSessionBoundAddresses.Clear();
        if (sessions == null) return;
        long now = ToUnixTimeSeconds(DateTime.UtcNow);
        int restored = 0;
        foreach (AuthenticationSessionState session in sessions)
        {
            if (session == null || string.IsNullOrWhiteSpace(session.Token) || session.Expires < now) continue;
            string[] tokenParts = session.Token.Split('.');
            long tokenExpiry;
            if (tokenParts.Length != 4 || !long.TryParse(tokenParts[0], out tokenExpiry) || tokenExpiry != session.Expires) continue;
            activeAuthenticationSessions[session.Token] = session.Expires;
            IPAddress boundAddress;
            if (!string.IsNullOrWhiteSpace(session.BoundAddress) && IPAddress.TryParse(session.BoundAddress, out boundAddress))
                authenticationSessionBoundAddresses[session.Token] = NormalizeIpAddress(boundAddress);
            restored++;
            if (restored >= 4096) break;
        }
    }

    public TemporaryAuthenticationLinkState CreateTemporaryAuthenticationLink(string username, int durationMinutes, bool singleUse, string boundAddress)
    {
        AuthenticationAccount account = FindAuthenticationAccount((username ?? "").Trim());
        if (account == null) throw new InvalidOperationException("The selected viewer account no longer exists.");
        return CreateTemporaryAuthenticationLinkState(account.Username, durationMinutes, singleUse, boundAddress, "session", false, "");
    }

    public TemporaryAuthenticationLinkState CreateAuthenticationSetupLink(string username, int durationMinutes, bool requireTotp, string boundAddress)
    {
        AuthenticationAccount account = FindAuthenticationAccount((username ?? "").Trim());
        if (account == null) throw new InvalidOperationException("The selected viewer account no longer exists.");
        string totpSecret = requireTotp ? GenerateTotpSecret() : "";
        return CreateTemporaryAuthenticationLinkState(account.Username, durationMinutes, true, boundAddress, "setup", requireTotp, totpSecret);
    }

    private TemporaryAuthenticationLinkState CreateTemporaryAuthenticationLinkState(string username, int durationMinutes, bool singleUse, string boundAddress, string purpose, bool requireTotp, string totpSecret)
    {
        string normalizedBoundAddress = NormalizeTemporaryLinkBoundAddress(boundAddress);
        RemoveExpiredTemporaryAuthenticationLinks();
        if (temporaryAuthenticationLinks.Count >= 4096) throw new InvalidOperationException("The temporary-link limit has been reached.");
        byte[] randomBytes = new byte[32];
        using (RandomNumberGenerator random = RandomNumberGenerator.Create()) { random.GetBytes(randomBytes); }
        TemporaryAuthenticationLinkState state = new TemporaryAuthenticationLinkState {
            Token = Base64UrlEncode(randomBytes),
            Username = username,
            Expires = ToUnixTimeSeconds(DateTime.UtcNow.AddMinutes(Math.Max(1, Math.Min(43200, durationMinutes)))),
            SingleUse = singleUse,
            BoundAddress = normalizedBoundAddress,
            Purpose = NormalizeTemporaryLinkPurpose(purpose),
            RequireTotp = requireTotp,
            TotpSecret = totpSecret ?? ""
        };
        temporaryAuthenticationLinks[state.Token] = state;
        return CloneTemporaryAuthenticationLink(state);
    }

    private static string NormalizeTemporaryLinkBoundAddress(string boundAddress)
    {
        if (string.IsNullOrWhiteSpace(boundAddress)) return "";
        IPAddress parsed;
        if (!IPAddress.TryParse(boundAddress.Trim(), out parsed)) throw new ArgumentException("The restricted client IP address is invalid.");
        return NormalizeIpAddress(parsed);
    }

    private static string NormalizeTemporaryLinkPurpose(string purpose)
    {
        return string.Equals(purpose, "setup", StringComparison.OrdinalIgnoreCase) ? "setup" : "session";
    }

    public TemporaryAuthenticationLinkState[] ExportTemporaryAuthenticationLinks()
    {
        RemoveExpiredTemporaryAuthenticationLinks();
        List<TemporaryAuthenticationLinkState> result = new List<TemporaryAuthenticationLinkState>();
        foreach (TemporaryAuthenticationLinkState state in temporaryAuthenticationLinks.Values)
            result.Add(CloneTemporaryAuthenticationLink(state));
        return result.ToArray();
    }

    public void RestoreTemporaryAuthenticationLinks(TemporaryAuthenticationLinkState[] links)
    {
        temporaryAuthenticationLinks.Clear();
        if (links == null) return;
        long now = ToUnixTimeSeconds(DateTime.UtcNow);
        int restored = 0;
        foreach (TemporaryAuthenticationLinkState link in links)
        {
            if (link == null || string.IsNullOrWhiteSpace(link.Token) || string.IsNullOrWhiteSpace(link.Username) || link.Expires < now) continue;
            string normalizedBoundAddress = "";
            if (!string.IsNullOrWhiteSpace(link.BoundAddress))
            {
                IPAddress parsed;
                if (!IPAddress.TryParse(link.BoundAddress, out parsed)) continue;
                normalizedBoundAddress = NormalizeIpAddress(parsed);
            }
            temporaryAuthenticationLinks[link.Token] = new TemporaryAuthenticationLinkState {
                Token = link.Token,
                Username = link.Username,
                Expires = link.Expires,
                SingleUse = NormalizeTemporaryLinkPurpose(link.Purpose) == "setup" ? true : link.SingleUse,
                BoundAddress = normalizedBoundAddress,
                Purpose = NormalizeTemporaryLinkPurpose(link.Purpose),
                RequireTotp = NormalizeTemporaryLinkPurpose(link.Purpose) == "setup" && link.RequireTotp,
                TotpSecret = NormalizeTemporaryLinkPurpose(link.Purpose) == "setup" && link.RequireTotp ? (link.TotpSecret ?? "") : ""
            };
            restored++;
            if (restored >= 4096) break;
        }
    }

    public bool RevokeTemporaryAuthenticationLink(string token)
    {
        TemporaryAuthenticationLinkState removed;
        return !string.IsNullOrWhiteSpace(token) && temporaryAuthenticationLinks.TryRemove(token, out removed);
    }

    public TemporaryAuthenticationLinkRevocationState RevokeTemporaryAuthenticationLinkAndSessions(string token)
    {
        TemporaryAuthenticationLinkState removed;
        if (string.IsNullOrWhiteSpace(token) || !temporaryAuthenticationLinks.TryRemove(token, out removed) || removed == null)
            return new TemporaryAuthenticationLinkRevocationState { LinkRemoved = false, Username = "", SessionsRevoked = 0 };

        return new TemporaryAuthenticationLinkRevocationState {
            LinkRemoved = true,
            Username = removed.Username ?? "",
            SessionsRevoked = RevokeAuthenticationSessionsForUsername(removed.Username)
        };
    }

    public int RevokeAuthenticationSessionsForUsername(string username)
    {
        if (string.IsNullOrWhiteSpace(username)) return 0;
        int revoked = 0;
        foreach (KeyValuePair<string, long> session in activeAuthenticationSessions)
        {
            if (!string.Equals(GetTokenUsernameForLogging(session.Key), username, StringComparison.Ordinal)) continue;
            long removedExpiry;
            if (!activeAuthenticationSessions.TryRemove(session.Key, out removedExpiry)) continue;
            string removedBoundAddress;
            authenticationSessionBoundAddresses.TryRemove(session.Key, out removedBoundAddress);
            revoked++;
        }
        return revoked;
    }

    private static TemporaryAuthenticationLinkState CloneTemporaryAuthenticationLink(TemporaryAuthenticationLinkState state)
    {
        return new TemporaryAuthenticationLinkState {
            Token = state.Token,
            Username = state.Username,
            Expires = state.Expires,
            SingleUse = state.SingleUse,
            BoundAddress = state.BoundAddress ?? "",
            Purpose = NormalizeTemporaryLinkPurpose(state.Purpose),
            RequireTotp = state.RequireTotp,
            TotpSecret = state.TotpSecret ?? ""
        };
    }

    private static void RemoveExpiredTemporaryAuthenticationLinks()
    {
        long now = ToUnixTimeSeconds(DateTime.UtcNow);
        foreach (KeyValuePair<string, TemporaryAuthenticationLinkState> entry in temporaryAuthenticationLinks)
        {
            if (entry.Value != null && entry.Value.Expires >= now) continue;
            TemporaryAuthenticationLinkState removed;
            temporaryAuthenticationLinks.TryRemove(entry.Key, out removed);
        }
    }

    public bool ApplyAuthenticationAccountUpdate(string username, string passwordHash, string totpSecret)
    {
        if (string.IsNullOrWhiteSpace(username) || !IsAuthenticationPasswordHashValid(passwordHash)) return false;
        AuthenticationAccount account = FindAuthenticationAccount(username);
        if (account == null) return false;
        account.PasswordHash = passwordHash;
        account.TotpSecret = totpSecret ?? "";
        return true;
    }

    public AuthenticationAccountUpdateState PollAuthenticationAccountUpdate()
    {
        AuthenticationAccountUpdateState update;
        return pendingAuthenticationAccountUpdates.TryDequeue(out update) ? update : null;
    }

    public string PollLogMessage()
    {
        string message;
        return pendingLog.TryDequeue(out message) ? message : null;
    }

    private async void AcceptLoop()
    {
        while (running)
        {
            TcpClient client;
            try
            {
                client = await listener.AcceptTcpClientAsync();
            }
            catch (Exception ex)
            {
                if (running) pendingLog.Enqueue("listener stopped accepting: " + ex.Message);
                break;
            }
            HandleClient(client);
        }
    }

    private async void HandleClient(TcpClient client)
    {
        try
        {
            client.NoDelay = true;
            using (client)
            {
                // certificate == null (plaintext-auth mode) skips the TLS
                // handshake entirely and runs everything below directly over
                // the raw NetworkStream -- see Start(). SslStream derives
                // from Stream, so every helper below (ReadHttpHeaderBlockAsync,
                // HandleAuthenticationAsync, PumpAsync, etc.) already takes the
                // generic Stream type and needs no changes for this.
                Stream stream = client.GetStream();
                SslStream sslStream = null;
                if (certificate != null)
                {
                    sslStream = new SslStream(stream, false);
                    try
                    {
                        // Explicit protocols rather than SslProtocols.None (meant to mean
                        // "let the OS pick") -- on at least one Windows 11 Enterprise host
                        // in the field, None threw ArgumentException("...SslProtocolType
                        // enumeration...") out of AuthenticateAsServerAsync, likely due to
                        // local SChannel/TLS policy restricting the OS-default protocol
                        // set. Naming the protocols explicitly sidesteps that.
                        await sslStream.AuthenticateAsServerAsync(certificate, false, SslProtocols.Tls12 | SslProtocols.Tls13, false);
                    }
                    catch (Exception ex)
                    {
                        // "Unexpected packet format" and similar almost always mean
                        // non-TLS bytes hit this port (a stale plain ws:// URL, a
                        // browser prefetch, or internet scanner noise once the port
                        // is DDNS-reachable) rather than a bug in this relay -- the
                        // remote address at least tells us whether it's the same
                        // source repeating or many different ones.
                        string remote = "unknown";
                        try
                        {
                            IPEndPoint endpoint = client.Client.RemoteEndPoint as IPEndPoint;
                            if (endpoint != null) remote = endpoint.Address.ToString();
                        }
                        catch { }
                        pendingLog.Enqueue("TLS handshake failed from " + remote + ": " + ex.Message);
                        sslStream.Dispose();
                        return;
                    }
                    stream = sslStream;
                }

                try
                {
                    int effectivePort = targetPort;
                    byte[] headerBytes = new byte[0];
                    bool suppressDocumentCaching = false;
                    bool rewriteHttpResponseHeaders = false;
                    if (pathRoutes.Count > 0 ||
                        authenticationEnabled ||
                        !string.IsNullOrEmpty(DirectoryRedirectPath) ||
                        !string.IsNullOrEmpty(AuthenticationMountPath))
                    {
                        headerBytes = await ReadHttpHeaderBlockAsync(stream);
                        if (headerBytes.Length == 0) return;
                        if (HasOwnProxyLoopMarker(headerBytes))
                        {
                            pendingLog.Enqueue("blocked a recursive same-port proxy request because the configured upstream resolved back to this listener");
                            await WriteHttpResponseAsync(
                                stream,
                                502,
                                "Bad Gateway",
                                "text/plain; charset=utf-8",
                                "The stream backend is unavailable.",
                                null
                            );
                            return;
                        }
                        if (!string.IsNullOrEmpty(DirectoryRedirectPath) && await RedirectMissingTrailingSlashAsync(stream, headerBytes))
                        {
                            return;
                        }
                        string requestPath = ExtractHttpRequestPath(headerBytes);
                        bool isAuthenticationEndpoint = IsAuthenticationEndpointPath(requestPath);
                        if (isAuthenticationEndpoint)
                        {
                            // Authentication routes are permanently owned by this
                            // gate. A valid viewer session must never cause
                            // login/logout to fall through to GStreamer's static
                            // or signaling servers.
                            bool endpointHandled = await HandleAuthenticationAsync(stream, client, headerBytes);
                            if (!endpointHandled)
                            {
                                pendingLog.Enqueue("authentication endpoint was not handled locally: " + requestPath);
                                await WriteHttpResponseAsync(
                                    stream,
                                    500,
                                    "Internal Server Error",
                                    "text/plain; charset=utf-8",
                                    "Authentication gate error.",
                                    null
                                );
                            }
                            return;
                        }
                        if (authenticationEnabled && !IsPublicPwaAssetPath(requestPath) &&
                            await HandleAuthenticationAsync(stream, client, headerBytes))
                        {
                            return;
                        }
                        if (requestPath != null)
                        {
                            foreach (Tuple<string, int> route in pathRoutes)
                            {
                                if (string.Equals(route.Item1, requestPath, StringComparison.OrdinalIgnoreCase))
                                {
                                    effectivePort = route.Item2;
                                    break;
                                }
                            }
                        }

                        // This proxy only inspects the FIRST request on each TCP
                        // connection -- forwarding below becomes a blind byte pump
                        // for the rest of that connection's life (required for
                        // WebSocket upgrades, which must stay a raw pipe). If the
                        // browser keeps this same connection alive and reuses it
                        // for a LATER, unrelated request (e.g. navigating to
                        // /auth/logout after the page already loaded), that later
                        // request would never be re-inspected and would silently
                        // ride the upstream target chosen for the first request --
                        // this is what made /auth/* start 404ing after the first
                        // request on a connection, recovering only when the whole
                        // process restarted and forced every connection fresh.
                        // Forcing the upstream to close after any non-upgrade
                        // response makes the browser open a new connection for
                        // its next request, which runs this same header-peek /
                        // auth / routing gate again from scratch.
                        bool isWebSocketUpgrade = IsWebSocketUpgradeRequest(headerBytes);
                        if (!isWebSocketUpgrade)
                        {
                            rewriteHttpResponseHeaders = true;
                            headerBytes = ForceConnectionCloseHeader(headerBytes);
                            // See InjectResponsePolicyHeaders' comment -- a
                            // stale cached copy of the viewer document served
                            // straight from disk cache after a real logout is
                            // exactly what let a logged-out browser keep showing
                            // the player without ever re-hitting this gate. Only
                            // relevant while auth is actually enforced; otherwise
                            // there is no session to protect and no reason to
                            // change existing caching behavior.
                            suppressDocumentCaching = authenticationEnabled && IsDocumentEntryPath(requestPath);
                        }
                    }

                    // Refuse to forward at all while paused (see PauseForwarding) --
                    // upstream is about to be/is being killed for a restart, and for
                    // a same-port relay (plaintext auth), even attempting this
                    // connection right now risks looping back into this instance's
                    // own listener instead of failing cleanly.
                    if (forwardingPaused)
                    {
                        string restartReturnPath = string.IsNullOrWhiteSpace(DirectoryRedirectPath)
                            ? "/live/"
                            : DirectoryRedirectPath.TrimEnd('/') + "/";
                        restartReturnPath = GetSafeReturnTarget(restartReturnPath);
                        Dictionary<string, string> restartHeaders = new Dictionary<string, string>
                        {
                            { "Retry-After", "2" },
                            // Stable machine-readable contract for player.js.
                            // Do not restore the old Refresh header: refreshing
                            // the holding document resets its looping video.
                            { "X-GStreamer-Glass-Forwarding-Paused", "1" }
                        };
                        byte[] restartImage = restartImageBytes;
                        byte[] restartMp4 = restartMp4Bytes;
                        byte[] restartWebm = restartWebmBytes;
                        byte[] restartPortraitImage = restartPortraitImageBytes;
                        byte[] restartPortraitMp4 = restartPortraitMp4Bytes;
                        byte[] restartPortraitWebm = restartPortraitWebmBytes;
                        if (restartImage.Length > 0 || restartMp4.Length > 0 || restartWebm.Length > 0)
                        {
                            await WriteMediaMessagePageAsync(
                                stream, 503, "Service Unavailable",
                                restartImage, restartMp4, restartWebm,
                                RestartImageAssetPath, RestartMp4AssetPath, RestartWebmAssetPath,
                                restartPortraitImage, restartPortraitMp4, restartPortraitWebm,
                                RestartPortraitImageAssetPath, RestartPortraitMp4AssetPath, RestartPortraitWebmAssetPath,
                                "We'll Be Right Back!", restartHeaders, restartReturnPath
                            );
                        }
                        else
                        {
                            await WriteHttpResponseAsync(stream, 503, "Service Unavailable", "text/plain; charset=utf-8", "Stream is restarting.", restartHeaders);
                        }
                        return;
                    }

                    // Mark the request only after all local auth/routing work
                    // has completed. The real upstream ignores this private
                    // extension header; if the same-port connect loops back to
                    // this listener, HasOwnProxyLoopMarker above terminates it
                    // on the first recursion with a bounded 502 response.
                    if (headerBytes.Length > 0)
                    {
                        headerBytes = InjectOwnProxyLoopMarker(headerBytes);
                    }

                    using (TcpClient upstream = new TcpClient())
                    {
                        upstream.NoDelay = true;
                        try
                        {
                            await upstream.ConnectAsync(targetHost, effectivePort);
                        }
                        catch (Exception ex)
                        {
                            pendingLog.Enqueue("could not reach upstream " + targetHost + ":" + effectivePort + ": " + ex.Message);
                            return;
                        }
                        activeUpstreamConnections.TryAdd(upstream, 0);
                        try
                        {
                            using (NetworkStream upstreamStream = upstream.GetStream())
                            {
                                if (headerBytes.Length > 0) await upstreamStream.WriteAsync(headerBytes, 0, headerBytes.Length);
                                Task toUpstream = PumpAsync(stream, upstreamStream);
                                Task toClient = rewriteHttpResponseHeaders
                                    ? PumpResponseWithPolicyHeadersAsync(upstreamStream, stream, suppressDocumentCaching)
                                    : PumpAsync(upstreamStream, stream);
                                await Task.WhenAny(toUpstream, toClient);
                            }
                        }
                        finally
                        {
                            byte removedMarker;
                            activeUpstreamConnections.TryRemove(upstream, out removedMarker);
                        }
                    }
                }
                finally
                {
                    if (sslStream != null) sslStream.Dispose();
                }
            }
        }
        catch (Exception ex)
        {
            // Best-effort relay: a single connection failing (client
            // disconnect, reset mid-stream) must never affect the listener
            // or other connections -- but still surface why for diagnosis.
            pendingLog.Enqueue("relay error: " + ex.Message);
        }
    }

    // Returns true when this request was answered locally or rejected. A false
    // return authorizes only this ordinary request for forwarding; it does not
    // disable or remove the gate. The next HTTPS/WSS request is validated
    // independently. Authentication endpoints are dispatched separately above
    // and are never eligible for upstream forwarding.
    private async Task<bool> HandleAuthenticationAsync(Stream stream, TcpClient client, byte[] headerBytes)
    {
        string headerText = null;
        try { headerText = Encoding.ASCII.GetString(headerBytes); }
        catch { }
        if (headerText == null)
        {
            await WriteHttpResponseAsync(stream, 400, "Bad Request", "text/plain; charset=utf-8", "Malformed HTTP request.", null);
            return true;
        }

        string[] lines = headerText.Split(new string[] { "\r\n" }, StringSplitOptions.None);
        string[] requestParts = lines.Length > 0 ? lines[0].Split(' ') : new string[0];
        if (requestParts.Length < 2)
        {
            await WriteHttpResponseAsync(stream, 400, "Bad Request", "text/plain; charset=utf-8", "Malformed HTTP request.", null);
            return true;
        }

        string method = requestParts[0].ToUpperInvariant();
        string rawTarget = requestParts[1];
        string path = ExtractHttpRequestPath(headerBytes) ?? "/";
        Dictionary<string, string> headers = ParseHttpHeaders(lines);
        string socketRemoteAddress = "unknown";
        try
        {
            IPEndPoint endpoint = client.Client.RemoteEndPoint as IPEndPoint;
            if (endpoint != null) socketRemoteAddress = NormalizeIpAddress(endpoint.Address);
        }
        catch { }
        // This one effective identity deliberately feeds BOTH audit logs and
        // authenticationFailures. Otherwise a reverse proxy makes every viewer
        // share one lockout bucket even if the log happens to show distinct IPs.
        string remoteAddress = ResolveForwardedClientAddress(headers, socketRemoteAddress);

        string mountedLegacyLoginPath = GetMountedAuthenticationPath(LegacyLoginPath);
        string mountedLegacyLogoutPath = GetMountedAuthenticationPath(LegacyLogoutPath);
        string mountedSimpleLogoutPath = GetMountedAuthenticationPath(LegacySimpleLogoutPath);

        bool isLogoutEndpoint =
            string.Equals(path, CanonicalLogoutPath, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(path, LegacyLogoutPath, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(path, LegacySimpleLogoutPath, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(path, mountedLegacyLogoutPath, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(path, mountedSimpleLogoutPath, StringComparison.OrdinalIgnoreCase);
        bool isLoginEndpoint =
            string.Equals(path, CanonicalLoginPath, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(path, LegacyLoginPath, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(path, mountedLegacyLoginPath, StringComparison.OrdinalIgnoreCase);
        bool isVerifyEndpoint = string.Equals(path, CanonicalVerifyPath, StringComparison.OrdinalIgnoreCase);
        bool isStatusEndpoint = string.Equals(path, CanonicalStatusPath, StringComparison.OrdinalIgnoreCase);
        bool isStreamStatusEndpoint = string.Equals(path, CanonicalStreamStatusPath, StringComparison.OrdinalIgnoreCase);
        bool isTemporarySessionEndpoint = string.Equals(path, CanonicalTemporarySessionPath, StringComparison.OrdinalIgnoreCase);
        bool isAccountSetupEndpoint = string.Equals(path, CanonicalAccountSetupPath, StringComparison.OrdinalIgnoreCase);
        bool isRobotsEndpoint = string.Equals(path, CanonicalRobotsPath, StringComparison.OrdinalIgnoreCase);
        bool isAuthenticationRoot =
            string.Equals(path, "/auth", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(path, "/auth/", StringComparison.OrdinalIgnoreCase);
        bool isCanonicalAuthenticationPath =
            string.Equals(path, "/auth", StringComparison.OrdinalIgnoreCase) ||
            path.StartsWith("/auth/", StringComparison.OrdinalIgnoreCase);

        byte[] messageAssetBytes;
        string messageAssetContentType;
        if (TryGetMessageAsset(path, out messageAssetBytes, out messageAssetContentType))
        {
            bool isAssetGet = string.Equals(method, "GET", StringComparison.OrdinalIgnoreCase);
            bool isAssetHead = string.Equals(method, "HEAD", StringComparison.OrdinalIgnoreCase);
            if (!isAssetGet && !isAssetHead)
            {
                Dictionary<string, string> assetMethodHeaders = new Dictionary<string, string>();
                assetMethodHeaders["Allow"] = "GET, HEAD";
                await WriteHttpResponseAsync(stream, 405, "Method Not Allowed", "text/plain; charset=utf-8", "Method not allowed.", assetMethodHeaders);
                return true;
            }
            await WriteHttpResponseBytesAsync(
                stream,
                200,
                "OK",
                messageAssetContentType,
                isAssetHead ? new byte[0] : messageAssetBytes,
                null
            );
            return true;
        }

        if (isRobotsEndpoint)
        {
            if (!string.Equals(method, "GET", StringComparison.OrdinalIgnoreCase) && !string.Equals(method, "HEAD", StringComparison.OrdinalIgnoreCase))
            {
                Dictionary<string, string> methodHeaders = new Dictionary<string, string>();
                methodHeaders["Allow"] = "GET, HEAD";
                await WriteHttpResponseAsync(stream, 405, "Method Not Allowed", "text/plain; charset=utf-8", "Method not allowed.", methodHeaders);
                return true;
            }
            string robotsBody = string.Equals(method, "HEAD", StringComparison.OrdinalIgnoreCase) ? "" : "User-agent: *\r\nDisallow: /\r\n";
            await WriteHttpResponseAsync(stream, 200, "OK", "text/plain; charset=utf-8", robotsBody, null);
            return true;
        }

        if (isLogoutEndpoint)
        {
            if (!string.Equals(method, "GET", StringComparison.OrdinalIgnoreCase))
            {
                Dictionary<string, string> methodHeaders = new Dictionary<string, string>();
                methodHeaders["Allow"] = "GET";
                await WriteHttpResponseAsync(stream, 405, "Method Not Allowed", "text/plain; charset=utf-8", "Method not allowed.", methodHeaders);
                return true;
            }
            // Multiple viewers can be signed in at once under this one shared
            // account (there is no per-user login). Logout must only revoke
            // THIS browser's own session token -- removing it from the
            // dictionary already makes that exact token fail validation
            // everywhere it's presented (any alias host/port, any concurrent
            // signaling connection, since they all key off the same token
            // value) without touching anyone else's independently issued
            // token. Clearing the whole session table here would sign out
            // every other viewer just because one person clicked logout.
            string logoutToken = GetAuthenticationCookie(headers);
            string logoutUsername = GetTokenUsernameForLogging(logoutToken);
            long removedSessionExpiry;
            bool removedCurrentSession =
                !string.IsNullOrWhiteSpace(logoutToken) &&
                activeAuthenticationSessions.TryRemove(logoutToken, out removedSessionExpiry);
            string removedBoundAddress;
            if (!string.IsNullOrWhiteSpace(logoutToken)) authenticationSessionBoundAddresses.TryRemove(logoutToken, out removedBoundAddress);
            Dictionary<string, string> logoutHeaders = new Dictionary<string, string>();
            logoutHeaders["Set-Cookie"] = "GstGlassAuth=; Path=/; HttpOnly" + CookieSecureAttribute + "; SameSite=Lax; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT";
            logoutHeaders["Clear-Site-Data"] = "\"cookies\", \"storage\"";
            // Straight to the login page, not the viewer -- redirecting to the
            // viewer here just means that request immediately gets challenged
            // and redirected to login again anyway, a wasted extra round trip.
            // The return target is still the actual viewer mount (e.g.
            // "/live/"), not bare "/" -- nothing is served at the site root,
            // so a bare "/" return would strand a re-logged-in viewer on a
            // blank/404 page instead of back at the broadcast.
            logoutHeaders["Location"] = CanonicalLoginPath + "?return=" + Uri.EscapeDataString(GetMountedViewerPath());
            pendingLog.Enqueue(
                "viewer" + (logoutUsername != null ? " '" + logoutUsername + "'" : "") + " logout from " + remoteAddress +
                "; current session " + (removedCurrentSession ? "removed" : "not found"));
            await WriteHttpResponseAsync(stream, 303, "See Other", "text/plain; charset=utf-8", "Signed out.", logoutHeaders);
            return true;
        }

        if (isTemporarySessionEndpoint)
        {
            bool isTemporaryGet = string.Equals(method, "GET", StringComparison.OrdinalIgnoreCase);
            bool isTemporaryHead = string.Equals(method, "HEAD", StringComparison.OrdinalIgnoreCase);
            bool isTemporaryPost = string.Equals(method, "POST", StringComparison.OrdinalIgnoreCase);
            if (!isTemporaryGet && !isTemporaryHead && !isTemporaryPost)
            {
                Dictionary<string, string> methodHeaders = new Dictionary<string, string>();
                methodHeaders["Allow"] = "GET, HEAD, POST";
                await WriteHttpResponseAsync(stream, 405, "Method Not Allowed", "text/plain; charset=utf-8", "Method not allowed.", methodHeaders);
                return true;
            }
            if (!authenticationEnabled)
            {
                await WriteHttpResponseAsync(stream, 404, "Not Found", "text/plain; charset=utf-8", "Authentication endpoint not found.", null);
                return true;
            }

            // HEAD is useful to note-taking apps and link scanners, but it
            // must never validate or consume a bearer token. A bodyless 204
            // plus the response-wide robots directives gives them nothing to
            // index while leaving the real browser GET untouched.
            if (isTemporaryHead)
            {
                await WriteHttpResponseAsync(stream, 204, "No Content", "text/plain; charset=utf-8", "", null);
                return true;
            }

            string temporaryToken;
            string temporaryReturnTarget;
            if (isTemporaryPost)
            {
                int temporaryContentLength;
                if (!TryGetContentLength(headers, out temporaryContentLength) || temporaryContentLength < 0 || temporaryContentLength > 8192)
                {
                    await WriteHttpResponseAsync(stream, 413, "Payload Too Large", "text/plain; charset=utf-8", "Invalid temporary-link request.", null);
                    return true;
                }
                byte[] temporaryBodyBytes = await ReadExactAsync(stream, temporaryContentLength);
                if (temporaryBodyBytes.Length != temporaryContentLength)
                {
                    await WriteHttpResponseAsync(stream, 400, "Bad Request", "text/plain; charset=utf-8", "Incomplete temporary-link request.", null);
                    return true;
                }
                Dictionary<string, string> temporaryForm = ParseUrlEncoded(Encoding.UTF8.GetString(temporaryBodyBytes));
                temporaryToken = temporaryForm.ContainsKey("token") ? temporaryForm["token"] : "";
                temporaryReturnTarget = temporaryForm.ContainsKey("return") ? temporaryForm["return"] : "";
            }
            else
            {
                temporaryToken = GetQueryValue(rawTarget, "token");
                temporaryReturnTarget = GetQueryValue(rawTarget, "return");
            }
            if (string.IsNullOrWhiteSpace(temporaryReturnTarget)) temporaryReturnTarget = GetMountedViewerPath();
            if (HasValidAuthenticationCookie(headers, remoteAddress))
            {
                await WriteRedirectAsync(stream, temporaryReturnTarget);
                return true;
            }
            TemporaryAuthenticationLinkState temporaryLink;
            string rejectionReason;
            int rejectionStatus;
            if (!TryValidateTemporaryAuthenticationLink(temporaryToken, remoteAddress, "session", out temporaryLink, out rejectionReason, out rejectionStatus))
            {
                pendingLog.Enqueue("temporary viewer link rejected from " + remoteAddress + ": " + rejectionReason);
                await WriteTemporaryLinkRejectedAsync(stream, rejectionStatus);
                return true;
            }

            // GET is intentionally safe and idempotent. Link-preview bots can
            // fetch this confirmation page without creating a viewer session
            // or burning a single-use token; only the explicit form POST below
            // performs redemption.
            if (isTemporaryGet)
            {
                await WriteTemporaryLinkConfirmationPageAsync(stream, temporaryToken, temporaryReturnTarget, temporaryLink);
                return true;
            }

            if (!TryRedeemTemporaryAuthenticationLink(temporaryToken, remoteAddress, "session", out temporaryLink, out rejectionReason, out rejectionStatus))
            {
                pendingLog.Enqueue("temporary viewer link redemption rejected from " + remoteAddress + ": " + rejectionReason);
                await WriteTemporaryLinkRejectedAsync(stream, rejectionStatus);
                return true;
            }
            await IssueAuthenticationSessionResponseAsync(
                stream,
                temporaryLink.Username,
                temporaryReturnTarget,
                remoteAddress,
                " (temporary link" + (temporaryLink.SingleUse ? ", single-use" : ", reusable") + (!string.IsNullOrEmpty(temporaryLink.BoundAddress) ? ", IP-bound" : "") + ")",
                null,
                temporaryLink.Expires,
                temporaryLink.BoundAddress
            );
            return true;
        }

        if (isAccountSetupEndpoint)
        {
            bool isSetupGet = string.Equals(method, "GET", StringComparison.OrdinalIgnoreCase);
            bool isSetupHead = string.Equals(method, "HEAD", StringComparison.OrdinalIgnoreCase);
            bool isSetupPost = string.Equals(method, "POST", StringComparison.OrdinalIgnoreCase);
            if (!isSetupGet && !isSetupHead && !isSetupPost)
            {
                Dictionary<string, string> methodHeaders = new Dictionary<string, string>();
                methodHeaders["Allow"] = "GET, HEAD, POST";
                await WriteHttpResponseAsync(stream, 405, "Method Not Allowed", "text/plain; charset=utf-8", "Method not allowed.", methodHeaders);
                return true;
            }
            if (!authenticationEnabled)
            {
                await WriteHttpResponseAsync(stream, 404, "Not Found", "text/plain; charset=utf-8", "Authentication endpoint not found.", null);
                return true;
            }
            // Preview probes get no token oracle and can never consume a link.
            if (isSetupHead)
            {
                await WriteHttpResponseAsync(stream, 204, "No Content", "text/plain; charset=utf-8", "", null);
                return true;
            }

            string setupToken;
            string setupReturnTarget;
            Dictionary<string, string> setupForm = null;
            if (isSetupPost)
            {
                int setupContentLength;
                if (!TryGetContentLength(headers, out setupContentLength) || setupContentLength < 0 || setupContentLength > 8192)
                {
                    await WriteHttpResponseAsync(stream, 413, "Payload Too Large", "text/plain; charset=utf-8", "Invalid account-setup request.", null);
                    return true;
                }
                byte[] setupBodyBytes = await ReadExactAsync(stream, setupContentLength);
                if (setupBodyBytes.Length != setupContentLength)
                {
                    await WriteHttpResponseAsync(stream, 400, "Bad Request", "text/plain; charset=utf-8", "Incomplete account-setup request.", null);
                    return true;
                }
                setupForm = ParseUrlEncoded(Encoding.UTF8.GetString(setupBodyBytes));
                setupToken = setupForm.ContainsKey("token") ? setupForm["token"] : "";
                setupReturnTarget = setupForm.ContainsKey("return") ? setupForm["return"] : "";
            }
            else
            {
                setupToken = GetQueryValue(rawTarget, "token");
                setupReturnTarget = GetQueryValue(rawTarget, "return");
            }
            if (string.IsNullOrWhiteSpace(setupReturnTarget)) setupReturnTarget = GetMountedViewerPath();

            TemporaryAuthenticationLinkState setupLink;
            string setupRejectionReason;
            int setupRejectionStatus;
            if (!TryValidateTemporaryAuthenticationLink(setupToken, remoteAddress, "setup", out setupLink, out setupRejectionReason, out setupRejectionStatus))
            {
                pendingLog.Enqueue("account setup link rejected from " + remoteAddress + ": " + setupRejectionReason);
                await WriteTemporaryLinkRejectedAsync(stream, setupRejectionStatus);
                return true;
            }
            AuthenticationAccount setupAccount = FindAuthenticationAccount(setupLink.Username);
            if (setupAccount == null || (setupLink.RequireTotp && string.IsNullOrWhiteSpace(setupLink.TotpSecret)))
            {
                RevokeTemporaryAuthenticationLink(setupToken);
                pendingLog.Enqueue("account setup link rejected from " + remoteAddress + ": account or 2FA enrollment state unavailable");
                await WriteTemporaryLinkRejectedAsync(stream, 410);
                return true;
            }

            if (isSetupGet)
            {
                await WriteAccountSetupPageAsync(stream, setupToken, setupReturnTarget, setupLink, setupAccount, "", 200, "OK", null);
                return true;
            }

            string setupPassword = setupForm.ContainsKey("password") ? setupForm["password"] : "";
            string setupPasswordConfirmation = setupForm.ContainsKey("confirm") ? setupForm["confirm"] : "";
            string setupCode = setupForm.ContainsKey("code") ? setupForm["code"] : "";
            if (setupPassword.Length < 10 || setupPassword.Length > 256 || !string.Equals(setupPassword, setupPasswordConfirmation, StringComparison.Ordinal))
            {
                await WriteAccountSetupPageAsync(stream, setupToken, setupReturnTarget, setupLink, setupAccount,
                    "Passwords must match and contain between 10 and 256 characters.", 400, "Bad Request", null);
                return true;
            }

            string totpSecretToKeep = setupLink.RequireTotp ? setupLink.TotpSecret : (setupAccount.TotpSecret ?? "");
            string verifiedTotpSecret = totpSecretToKeep;
            bool codeRequired = !string.IsNullOrWhiteSpace(totpSecretToKeep);
            if (codeRequired)
            {
                int setupRetryAfter = GetAuthenticationRetryAfterSeconds(remoteAddress);
                if (setupRetryAfter > 0)
                {
                    Dictionary<string, string> limitedHeaders = new Dictionary<string, string>();
                    limitedHeaders["Retry-After"] = setupRetryAfter.ToString();
                    await WriteAccountSetupPageAsync(stream, setupToken, setupReturnTarget, setupLink, setupAccount,
                        "Too many attempts. Wait a moment and try again.", 429, "Too Many Requests", limitedHeaders);
                    return true;
                }
                if (!VerifyTotpCode(totpSecretToKeep, setupCode))
                {
                    RecordAuthenticationFailure(remoteAddress);
                    pendingLog.Enqueue("account setup 2FA code rejected from " + remoteAddress);
                    await WriteAccountSetupPageAsync(stream, setupToken, setupReturnTarget, setupLink, setupAccount,
                        "That authenticator code was not accepted.", 401, "Unauthorized", null);
                    return true;
                }
            }

            bool setupHashSlot = await authenticationHashSlots.WaitAsync(5000);
            if (!setupHashSlot)
            {
                Dictionary<string, string> busyHeaders = new Dictionary<string, string>();
                busyHeaders["Retry-After"] = "5";
                await WriteAccountSetupPageAsync(stream, setupToken, setupReturnTarget, setupLink, setupAccount,
                    "Password setup is busy. Try again in a few seconds.", 503, "Service Unavailable", busyHeaders);
                return true;
            }
            string newPasswordHash;
            try { newPasswordHash = HashAuthenticationPassword(setupPassword); }
            finally { authenticationHashSlots.Release(); }

            // Consume only after every validation and the expensive password
            // derivation succeeds. Concurrent submissions race here, so only
            // one can ever change credentials or receive a session.
            if (!TryRedeemTemporaryAuthenticationLink(setupToken, remoteAddress, "setup", out setupLink, out setupRejectionReason, out setupRejectionStatus))
            {
                pendingLog.Enqueue("account setup link redemption rejected from " + remoteAddress + ": " + setupRejectionReason);
                await WriteTemporaryLinkRejectedAsync(stream, setupRejectionStatus);
                return true;
            }
            setupAccount = FindAuthenticationAccount(setupLink.Username);
            if (setupAccount == null)
            {
                await WriteTemporaryLinkRejectedAsync(stream, 410);
                return true;
            }
            totpSecretToKeep = setupLink.RequireTotp ? setupLink.TotpSecret : (setupAccount.TotpSecret ?? "");
            // An administrator can change 2FA while this request is hashing
            // the new password. Never issue a session against a secret that
            // was not the one actually verified above (including a change
            // from no 2FA to 2FA during the request).
            if (!string.Equals(totpSecretToKeep, verifiedTotpSecret, StringComparison.Ordinal))
            {
                pendingLog.Enqueue("account setup link consumed without changing credentials because 2FA changed during redemption for '" + setupLink.Username + "'");
                await WriteTemporaryLinkRejectedAsync(stream, 410);
                return true;
            }
            if (!ApplyAuthenticationAccountUpdate(setupLink.Username, newPasswordHash, totpSecretToKeep))
            {
                await WriteTemporaryLinkRejectedAsync(stream, 410);
                return true;
            }
            int setupSessionsRevoked = RevokeAuthenticationSessionsForUsername(setupLink.Username);
            pendingAuthenticationAccountUpdates.Enqueue(new AuthenticationAccountUpdateState {
                Username = setupLink.Username,
                PasswordHash = newPasswordHash,
                TotpSecret = totpSecretToKeep,
                SessionsRevoked = setupSessionsRevoked
            });
            AuthenticationFailureState removedSetupFailureState;
            authenticationFailures.TryRemove(remoteAddress, out removedSetupFailureState);
            await IssueAuthenticationSessionResponseAsync(
                stream,
                setupLink.Username,
                setupReturnTarget,
                remoteAddress,
                " (account setup link" + (codeRequired ? ", 2FA verified" : "") + ")",
                null,
                long.MaxValue,
                setupLink.BoundAddress
            );
            return true;
        }

        if (isVerifyEndpoint)
        {
            if (!string.Equals(method, "POST", StringComparison.OrdinalIgnoreCase))
            {
                Dictionary<string, string> methodHeaders = new Dictionary<string, string>();
                methodHeaders["Allow"] = "POST";
                await WriteHttpResponseAsync(stream, 405, "Method Not Allowed", "text/plain; charset=utf-8", "Method not allowed.", methodHeaders);
                return true;
            }

            int verifyContentLength;
            if (!TryGetContentLength(headers, out verifyContentLength) || verifyContentLength < 0 || verifyContentLength > 8192)
            {
                await WriteHttpResponseAsync(stream, 413, "Payload Too Large", "text/plain; charset=utf-8", "Invalid verification request.", null);
                return true;
            }
            byte[] verifyBodyBytes = await ReadExactAsync(stream, verifyContentLength);
            if (verifyBodyBytes.Length != verifyContentLength)
            {
                await WriteHttpResponseAsync(stream, 400, "Bad Request", "text/plain; charset=utf-8", "Incomplete verification request.", null);
                return true;
            }

            Dictionary<string, string> verifyForm = ParseUrlEncoded(Encoding.UTF8.GetString(verifyBodyBytes));
            string pendingToken = verifyForm.ContainsKey("pending") ? verifyForm["pending"] : "";
            string code = verifyForm.ContainsKey("code") ? verifyForm["code"] : "";
            string verifyReturnTarget = verifyForm.ContainsKey("return") ? verifyForm["return"] : GetMountedViewerPath();
            bool rememberDevice = verifyForm.ContainsKey("remember") && verifyForm["remember"] == "1";

            // The same per-IP lockout that guards password attempts also
            // covers the code step, so the second factor can't be brute
            // forced by hammering only /auth/verify.
            int verifyRetryAfter = GetAuthenticationRetryAfterSeconds(remoteAddress);
            if (verifyRetryAfter > 0)
            {
                Dictionary<string, string> limitedHeaders = new Dictionary<string, string>();
                limitedHeaders["Retry-After"] = verifyRetryAfter.ToString();
                await WriteTotpChallengePageAsync(stream, pendingToken, verifyReturnTarget, true, 429, "Too Many Requests", limitedHeaders);
                return true;
            }

            string pendingUsername = ValidatePendingTotpToken(pendingToken);
            AuthenticationAccount verifyAccount = pendingUsername != null ? FindAuthenticationAccount(pendingUsername) : null;
            bool codeValid = verifyAccount != null && !string.IsNullOrEmpty(verifyAccount.TotpSecret) && VerifyTotpCode(verifyAccount.TotpSecret, code);
            if (!codeValid)
            {
                RecordAuthenticationFailure(remoteAddress);
                pendingLog.Enqueue("2FA code rejected from " + remoteAddress);
                if (verifyAccount == null)
                {
                    // The pending token expired, was tampered with, or its
                    // account was removed mid-challenge -- send back to the
                    // start of login rather than re-showing a challenge tied
                    // to a token that can never validate.
                    await WriteRedirectAsync(stream, CanonicalLoginPath + "?return=" + Uri.EscapeDataString(GetSafeReturnTarget(verifyReturnTarget)));
                    return true;
                }
                await WriteTotpChallengePageAsync(stream, pendingToken, verifyReturnTarget, true, 401, "Unauthorized");
                return true;
            }

            AuthenticationFailureState verifyRemovedFailureState;
            authenticationFailures.TryRemove(remoteAddress, out verifyRemovedFailureState);
            List<string> verifyExtraCookies = null;
            if (rememberDevice)
            {
                string trustToken = CreateTrustedDeviceToken(verifyAccount.Username);
                verifyExtraCookies = new List<string> {
                    TrustedDeviceCookieName + "=" + trustToken + "; Path=/; HttpOnly" + CookieSecureAttribute +
                    "; SameSite=Lax; Max-Age=" + (TrustedDeviceDays * 86400).ToString()
                };
            }
            await IssueAuthenticationSessionResponseAsync(stream, verifyAccount.Username, verifyReturnTarget, remoteAddress, " (2FA)" + (rememberDevice ? ", device remembered" : ""), verifyExtraCookies);
            return true;
        }

        if (isStatusEndpoint)
        {
            // A dedicated, lightweight session heartbeat -- unlike the
            // ordinary viewer/signalling paths (which only redirect a
            // *specific request that happened to come in* once a session is
            // gone), this exists so the player can poll the auth mechanism
            // itself directly, on its own schedule, and act the moment a
            // session is revoked rather than waiting on some other fetch to
            // incidentally notice. Always answered locally, same as every
            // other /auth/* path -- never forwarded, never affected by
            // whether GST/webrtcsink is even running. Must run before the
            // "unknown /auth/* child" 404 catch-all below, and works
            // regardless of authenticationEnabled (an unauthenticated proxy
            // has nothing to be revoked, so it always reports true).
            if (!string.Equals(method, "GET", StringComparison.OrdinalIgnoreCase))
            {
                Dictionary<string, string> statusMethodHeaders = new Dictionary<string, string>();
                statusMethodHeaders["Allow"] = "GET";
                await WriteHttpResponseAsync(stream, 405, "Method Not Allowed", "text/plain; charset=utf-8", "Method not allowed.", statusMethodHeaders);
                return true;
            }
            bool authenticated = !authenticationEnabled || HasValidAuthenticationCookie(headers, remoteAddress);
            await WriteHttpResponseAsync(
                stream,
                200,
                "OK",
                "application/json; charset=utf-8",
                "{\"authenticated\":" + (authenticated ? "true" : "false") + "}",
                null
            );
            return true;
        }

        if (isStreamStatusEndpoint)
        {
            if (!string.Equals(method, "GET", StringComparison.OrdinalIgnoreCase))
            {
                Dictionary<string, string> streamStatusMethodHeaders = new Dictionary<string, string>();
                streamStatusMethodHeaders["Allow"] = "GET";
                await WriteHttpResponseAsync(stream, 405, "Method Not Allowed", "text/plain; charset=utf-8", "Method not allowed.", streamStatusMethodHeaders);
                return true;
            }
            bool authenticated = !authenticationEnabled || HasValidAuthenticationCookie(headers, remoteAddress);
            await WriteHttpResponseAsync(
                stream,
                200,
                "OK",
                "application/json; charset=utf-8",
                "{\"authenticated\":" + (authenticated ? "true" : "false") + ",\"forwardingPaused\":" + (forwardingPaused ? "true" : "false") + "}",
                null
            );
            return true;
        }

        if (isAuthenticationRoot)
        {
            if (authenticationEnabled && !HasValidAuthenticationCookie(headers, remoteAddress))
            {
                await WriteRedirectAsync(
                    stream,
                    CanonicalLoginPath + "?return=" + Uri.EscapeDataString(GetMountedViewerPath())
                );
            }
            else
            {
                await WriteRedirectAsync(stream, GetMountedViewerPath());
            }
            return true;
        }

        // /auth/ is a permanently reserved gate namespace. Unknown children
        // are answered locally and are never eligible for authenticated
        // forwarding to the viewer or signaling upstreams.
        if (isCanonicalAuthenticationPath && !isLoginEndpoint && !isVerifyEndpoint && !isStatusEndpoint && !isStreamStatusEndpoint && !isTemporarySessionEndpoint && !isAccountSetupEndpoint)
        {
            await WriteHttpResponseAsync(
                stream,
                404,
                "Not Found",
                "text/plain; charset=utf-8",
                "Authentication endpoint not found.",
                null
            );
            return true;
        }

        // Auth endpoints belong to the TLS edge even while authentication is
        // being enabled, disabled, or restarted. Logout above must always be
        // consumable so a stale HttpOnly cookie can be expired. A login route
        // reached while enforcement is off simply returns to the viewer.
        if (!authenticationEnabled)
        {
            if (isLoginEndpoint)
            {
                await WriteRedirectAsync(stream, GetMountedViewerPath());
                return true;
            }
            return false;
        }

        if (isLoginEndpoint)
        {
            string returnTarget = GetQueryValue(rawTarget, "return");
            if (string.IsNullOrWhiteSpace(returnTarget)) returnTarget = GetMountedViewerPath();
            if (method == "GET")
            {
                if (HasValidAuthenticationCookie(headers, remoteAddress))
                {
                    await WriteRedirectAsync(stream, GetSafeReturnTarget(returnTarget));
                }
                else
                {
                    await WriteLoginPageAsync(stream, returnTarget, false, 200, "OK");
                }
                return true;
            }

            if (method != "POST")
            {
                Dictionary<string, string> methodHeaders = new Dictionary<string, string>();
                methodHeaders["Allow"] = "GET, POST";
                await WriteHttpResponseAsync(stream, 405, "Method Not Allowed", "text/plain; charset=utf-8", "Method not allowed.", methodHeaders);
                return true;
            }

            int contentLength;
            if (!TryGetContentLength(headers, out contentLength) || contentLength < 0 || contentLength > 8192)
            {
                await WriteHttpResponseAsync(stream, 413, "Payload Too Large", "text/plain; charset=utf-8", "Invalid login request.", null);
                return true;
            }

            byte[] bodyBytes = await ReadExactAsync(stream, contentLength);
            if (bodyBytes.Length != contentLength)
            {
                await WriteHttpResponseAsync(stream, 400, "Bad Request", "text/plain; charset=utf-8", "Incomplete login request.", null);
                return true;
            }

            Dictionary<string, string> form = ParseUrlEncoded(Encoding.UTF8.GetString(bodyBytes));
            string username = form.ContainsKey("username") ? form["username"] : "";
            string password = form.ContainsKey("password") ? form["password"] : "";
            returnTarget = form.ContainsKey("return") ? form["return"] : returnTarget;

            int retryAfter = GetAuthenticationRetryAfterSeconds(remoteAddress);
            if (retryAfter > 0)
            {
                Dictionary<string, string> limitedHeaders = new Dictionary<string, string>();
                limitedHeaders["Retry-After"] = retryAfter.ToString();
                await WriteLoginPageAsync(stream, returnTarget, true, 429, "Too Many Requests", limitedHeaders);
                return true;
            }

            // Run the expensive password verification even when the username
            // matches no configured account (against an empty/invalid hash,
            // which VerifyAuthenticationPassword still spends a full PBKDF2
            // round on before reporting "invalid format") -- this keeps a
            // request for an unknown username from completing observably
            // faster than one for a real account, preventing a username
            // enumeration oracle. Password length is capped before hashing
            // to bound abuse.
            AuthenticationAccount matchedAccount = FindAuthenticationAccount(username);
            bool acquiredHashSlot = await authenticationHashSlots.WaitAsync(5000);
            if (!acquiredHashSlot)
            {
                Dictionary<string, string> busyHeaders = new Dictionary<string, string>();
                busyHeaders["Retry-After"] = "5";
                await WriteLoginPageAsync(stream, returnTarget, true, 503, "Service Unavailable", busyHeaders);
                return true;
            }
            bool passwordValid;
            try
            {
                string hashToVerify = matchedAccount != null ? matchedAccount.PasswordHash : "";
                passwordValid = password.Length <= 256 && VerifyAuthenticationPassword(password, hashToVerify);
            }
            finally
            {
                authenticationHashSlots.Release();
            }
            if (!passwordValid || matchedAccount == null)
            {
                RecordAuthenticationFailure(remoteAddress);
                pendingLog.Enqueue("authentication rejected from " + remoteAddress);
                await WriteLoginPageAsync(stream, returnTarget, true, 401, "Unauthorized");
                return true;
            }

            if (!string.IsNullOrEmpty(matchedAccount.TotpSecret))
            {
                // A device that already completed 2FA for this exact
                // account recently gets to skip straight to a real session,
                // same as an account with no TOTP secret at all -- the
                // password above was still required either way, this only
                // ever skips the second factor.
                if (ValidateTrustedDeviceToken(GetCookieValue(headers, TrustedDeviceCookieName), matchedAccount.Username))
                {
                    AuthenticationFailureState trustedFailureState;
                    authenticationFailures.TryRemove(remoteAddress, out trustedFailureState);
                    await IssueAuthenticationSessionResponseAsync(stream, matchedAccount.Username, returnTarget, remoteAddress, " (2FA skipped, trusted device)", null);
                    return true;
                }

                // Password alone was correct but is not sufficient for this
                // account -- do not clear the failure counter or issue a
                // session yet. A wrong code on the next step is tracked by
                // the SAME per-IP lockout as a wrong password (see
                // isVerifyEndpoint above), so the second factor can't be
                // brute-forced by skipping straight to /auth/verify either.
                string pendingToken = CreatePendingTotpToken(matchedAccount.Username);
                await WriteTotpChallengePageAsync(stream, pendingToken, returnTarget, false, 200, "OK");
                return true;
            }

            AuthenticationFailureState removedFailureState;
            authenticationFailures.TryRemove(remoteAddress, out removedFailureState);
            await IssueAuthenticationSessionResponseAsync(stream, matchedAccount.Username, returnTarget, remoteAddress, "", null);
            return true;
        }

        if (HasValidAuthenticationCookie(headers, remoteAddress)) return false;

        bool isWebSocket = headers.ContainsKey("Upgrade") && headers["Upgrade"].IndexOf("websocket", StringComparison.OrdinalIgnoreCase) >= 0;
        if (isWebSocket)
        {
            Dictionary<string, string> deniedHeaders = new Dictionary<string, string>();
            deniedHeaders["WWW-Authenticate"] = "GstGlassSession";
            await WriteHttpResponseAsync(stream, 401, "Unauthorized", "text/plain; charset=utf-8", "Authentication required.", deniedHeaders);
            return true;
        }

        string loginTarget = CanonicalLoginPath + "?return=" + Uri.EscapeDataString(GetSafeReturnTarget(rawTarget));
        await WriteRedirectAsync(stream, loginTarget);
        return true;
    }

    private string GetMountedAuthenticationPath(string rootPath)
    {
        string mount = (AuthenticationMountPath ?? "").TrimEnd('/');
        if (string.IsNullOrEmpty(mount)) mount = (DirectoryRedirectPath ?? "").TrimEnd('/');
        if (string.IsNullOrEmpty(mount)) return rootPath;
        return mount + rootPath;
    }

    private bool IsAuthenticationEndpointPath(string path)
    {
        if (string.IsNullOrEmpty(path)) return false;
        if (string.Equals(path, CanonicalRobotsPath, StringComparison.OrdinalIgnoreCase)) return true;
        // Every canonical path (login, logout, and any other /auth/* child)
        // already starts with "/auth" or "/auth/", so only the legacy,
        // non-canonical alias paths need their own explicit comparisons below.
        if (string.Equals(path, "/auth", StringComparison.OrdinalIgnoreCase) ||
            path.StartsWith("/auth/", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }
        return
            string.Equals(path, LegacyLoginPath, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(path, LegacyLogoutPath, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(path, LegacySimpleLogoutPath, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(path, GetMountedAuthenticationPath(LegacyLoginPath), StringComparison.OrdinalIgnoreCase) ||
            string.Equals(path, GetMountedAuthenticationPath(LegacyLogoutPath), StringComparison.OrdinalIgnoreCase) ||
            string.Equals(path, GetMountedAuthenticationPath(LegacySimpleLogoutPath), StringComparison.OrdinalIgnoreCase);
    }

    private string GetMountedViewerPath()
    {
        string mount = (AuthenticationMountPath ?? "").TrimEnd('/');
        if (string.IsNullOrEmpty(mount)) mount = (DirectoryRedirectPath ?? "").TrimEnd('/');
        return string.IsNullOrEmpty(mount) ? "/live/" : mount + "/";
    }

    // Returns true when a redirect was sent (caller must not forward the
    // request). Only fires for an exact, case-insensitive match on a plain
    // GET -- WebSocket upgrades and any other path pass through untouched.
    private async Task<bool> RedirectMissingTrailingSlashAsync(Stream stream, byte[] headerBytes)
    {
        string text;
        try { text = Encoding.ASCII.GetString(headerBytes); }
        catch { return false; }
        int lineEnd = text.IndexOf("\r\n");
        string requestLine = lineEnd >= 0 ? text.Substring(0, lineEnd) : text;
        string[] parts = requestLine.Split(' ');
        if (parts.Length < 2 || !string.Equals(parts[0], "GET", StringComparison.OrdinalIgnoreCase)) return false;

        string rawTarget = parts[1];
        int query = rawTarget.IndexOf('?');
        string rawPath = query >= 0 ? rawTarget.Substring(0, query) : rawTarget;
        string queryString = query >= 0 ? rawTarget.Substring(query) : "";
        if (!string.Equals(rawPath, DirectoryRedirectPath, StringComparison.OrdinalIgnoreCase)) return false;

        Dictionary<string, string> headers = new Dictionary<string, string>();
        headers["Location"] = DirectoryRedirectPath + "/" + queryString;
        await WriteHttpResponseAsync(stream, 301, "Moved Permanently", "text/plain; charset=utf-8", "Redirecting.", headers);
        return true;
    }

    private static Dictionary<string, string> ParseHttpHeaders(string[] lines)
    {
        Dictionary<string, string> headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        for (int i = 1; i < lines.Length; i++)
        {
            int separator = lines[i].IndexOf(':');
            if (separator <= 0) continue;
            string name = lines[i].Substring(0, separator).Trim();
            string value = lines[i].Substring(separator + 1).Trim();
            if (!headers.ContainsKey(name)) headers[name] = value;
            else if (string.Equals(name, "X-Forwarded-For", StringComparison.OrdinalIgnoreCase))
            {
                // Multiple XFF fields are equivalent to one comma-separated
                // chain. Combining them is also important when a trusted proxy
                // appends the real peer after a client-supplied field.
                headers[name] = headers[name] + "," + value;
            }
        }
        return headers;
    }

    private static string NormalizeIpAddress(IPAddress address)
    {
        if (address == null) return "unknown";
        if (address.IsIPv4MappedToIPv6) address = address.MapToIPv4();
        return address.ToString();
    }

    // Walk X-Forwarded-For from the proxy nearest Glass toward the original
    // client. A hop is accepted only while the current sender is in the exact
    // trusted-proxy list. The first untrusted address is the client identity;
    // anything farther left is client-controlled and ignored. A malformed
    // chain fails closed to the actual socket peer.
    private string ResolveForwardedClientAddress(Dictionary<string, string> headers, string socketRemoteAddress)
    {
        if (string.IsNullOrWhiteSpace(socketRemoteAddress) ||
            !trustedForwardingProxyAddresses.Contains(socketRemoteAddress)) return socketRemoteAddress;

        string forwardedFor;
        if (headers == null || !headers.TryGetValue("X-Forwarded-For", out forwardedFor) || string.IsNullOrWhiteSpace(forwardedFor))
            return socketRemoteAddress;

        string currentAddress = socketRemoteAddress;
        string[] hops = forwardedFor.Split(',');
        for (int i = hops.Length - 1; i >= 0; i--)
        {
            string token = (hops[i] ?? "").Trim().Trim('"');
            IPAddress parsed;
            if (token.Length == 0 || !IPAddress.TryParse(token, out parsed)) return socketRemoteAddress;
            currentAddress = NormalizeIpAddress(parsed);
            if (!trustedForwardingProxyAddresses.Contains(currentAddress)) return currentAddress;
        }
        return currentAddress;
    }

    private static bool TryGetContentLength(Dictionary<string, string> headers, out int length)
    {
        length = 0;
        string value;
        return headers.TryGetValue("Content-Length", out value) && int.TryParse(value, out length);
    }

    private static async Task<byte[]> ReadExactAsync(Stream stream, int length)
    {
        byte[] result = new byte[length];
        int offset = 0;
        while (offset < length)
        {
            int read = await stream.ReadAsync(result, offset, length - offset);
            if (read <= 0) break;
            offset += read;
        }
        if (offset == length) return result;
        byte[] partial = new byte[offset];
        Buffer.BlockCopy(result, 0, partial, 0, offset);
        return partial;
    }

    private async Task WriteLoginPageAsync(Stream stream, string returnTarget, bool invalid, int statusCode, string reason)
    {
        await WriteLoginPageAsync(stream, returnTarget, invalid, statusCode, reason, null);
    }

    private async Task WriteLoginPageAsync(Stream stream, string returnTarget, bool invalid, int statusCode, string reason, Dictionary<string, string> additionalHeaders)
    {
        string safeReturn = GetSafeReturnTarget(returnTarget);
        string error = invalid ? "<p class=\"error\">That login was not accepted. Check the credentials or wait a moment and try again.</p>" : "";
        // A tab/PWA can end up sitting on this page while already holding a
        // valid session -- logged in from elsewhere with the same shared
        // account, or a still-valid cookie the platform just didn't route a
        // fresh navigation through (observed specifically on installed
        // Android PWAs). The template's heartbeat script polls the
        // always-locally-answered /auth/status heartbeat (same endpoint
        // player.js's checkAuthStatus polls) and bounces to the return
        // target the moment it reports authenticated. CSP blocks scripts by
        // default (see WriteHttpResponseAsync); this nonce is what allows
        // that one inline script through for this response.
        byte[] scriptNonceBytes = new byte[16];
        using (RandomNumberGenerator random = RandomNumberGenerator.Create())
        {
            random.GetBytes(scriptNonceBytes);
        }
        string scriptNonce = Base64UrlEncode(scriptNonceBytes);
        // Installable from here too, not just the player -- the whole point
        // being that an installed PWA always reopens to wherever it was
        // installed FROM (confirmed platform behavior, not something either
        // page can override), so an install anchored on /auth/login is
        // self-correcting on every relaunch: a still-valid session already
        // 303s straight through to the viewer (see the GET branch of the
        // /auth/login handler above), an invalid one just shows this same
        // form again. No manifest URL is mount-relative here the way
        // index.html's is -- this page lives at the origin root, not under
        // the viewer mount, so GetMountedViewerPath() builds an absolute
        // reference to the same manifest/icons index.html uses.
        string pwaMountPath = GetMountedViewerPath();
        // This must remain byte-for-byte identical to index.html's manifest
        // href. Chromium associates installed-app metadata updates with the
        // manifest URL, so changing it (including only its query string) can
        // strand an existing WebAPK on an older display mode.
        string manifestUrl = pwaMountPath + "manifest.webmanifest?v=3.8.40";
        string iconUrl = pwaMountPath + "icons/gstreamer-glass-192.png";
        string html = loginTemplateText
            .Replace("{{MANIFEST_URL}}", WebUtility.HtmlEncode(manifestUrl))
            .Replace("{{ICON_URL}}", WebUtility.HtmlEncode(iconUrl))
            .Replace("{{ERROR_BLOCK}}", error)
            .Replace("{{RETURN_TARGET}}", WebUtility.HtmlEncode(safeReturn))
            .Replace("{{NONCE}}", scriptNonce);
        await WriteHttpResponseAsync(stream, statusCode, reason, "text/html; charset=utf-8", html, additionalHeaders, scriptNonce);
    }

    private async Task WriteTemporaryLinkConfirmationPageAsync(Stream stream, string token, string returnTarget, TemporaryAuthenticationLinkState link)
    {
        string safeReturn = GetSafeReturnTarget(returnTarget);
        string linkDescription = link != null && link.SingleUse
            ? "This single-use link will only be consumed after you continue."
            : "This temporary link remains reusable until it expires or is revoked.";
        string html = linkConfirmTemplateText
            .Replace("{{LINK_DESCRIPTION}}", WebUtility.HtmlEncode(linkDescription))
            .Replace("{{TOKEN}}", WebUtility.HtmlEncode(token ?? ""))
            .Replace("{{RETURN_TARGET}}", WebUtility.HtmlEncode(safeReturn));
        await WriteHttpResponseAsync(stream, 200, "OK", "text/html; charset=utf-8", html, null);
    }

    private async Task WriteAccountSetupPageAsync(Stream stream, string token, string returnTarget, TemporaryAuthenticationLinkState link, AuthenticationAccount account, string errorMessage, int statusCode, string reason, Dictionary<string, string> additionalHeaders)
    {
        string safeReturn = GetSafeReturnTarget(returnTarget);
        string username = account != null ? account.Username : (link != null ? link.Username : "");
        bool enrollTotp = link != null && link.RequireTotp;
        bool verifyExistingTotp = !enrollTotp && account != null && !string.IsNullOrWhiteSpace(account.TotpSecret);
        string error = string.IsNullOrWhiteSpace(errorMessage) ? "" : "<p class=\"error\">" + WebUtility.HtmlEncode(errorMessage) + "</p>";
        string totpFields = "";
        if (enrollTotp)
        {
            string issuer = "GStreamer Glass";
            string secret = link.TotpSecret ?? "";
            string otpauthUri = "otpauth://totp/" + Uri.EscapeDataString(issuer) + ":" + Uri.EscapeDataString(username) +
                "?secret=" + Uri.EscapeDataString(secret) + "&issuer=" + Uri.EscapeDataString(issuer);
            totpFields =
                "<section><h2>Set up two-factor authentication</h2><p>Add this account to your authenticator app using the secret or URI below, then enter its current code.</p>" +
                "<label>Secret key</label><code>" + WebUtility.HtmlEncode(secret) + "</code>" +
                "<label>Authenticator URI</label><code class=\"uri\"><a href=\"" + WebUtility.HtmlEncode(otpauthUri) + "\">" + WebUtility.HtmlEncode(otpauthUri) + "</a></code></section>" +
                "<label for=\"code\">Authenticator code</label><input id=\"code\" name=\"code\" inputmode=\"numeric\" pattern=\"[0-9]{6}\" maxlength=\"6\" autocomplete=\"one-time-code\" required>";
        }
        else if (verifyExistingTotp)
        {
            totpFields =
                "<p>Your existing two-factor enrollment will be preserved. Enter its current code to complete the password change.</p>" +
                "<label for=\"code\">Authenticator code</label><input id=\"code\" name=\"code\" inputmode=\"numeric\" pattern=\"[0-9]{6}\" maxlength=\"6\" autocomplete=\"one-time-code\" required>";
        }
        string html = accountSetupTemplateText
            .Replace("{{USERNAME}}", WebUtility.HtmlEncode(username))
            .Replace("{{ERROR_BLOCK}}", error)
            .Replace("{{TOTP_FIELDS}}", totpFields)
            .Replace("{{TOKEN}}", WebUtility.HtmlEncode(token ?? ""))
            .Replace("{{RETURN_TARGET}}", WebUtility.HtmlEncode(safeReturn));
        await WriteHttpResponseAsync(stream, statusCode, reason, "text/html; charset=utf-8", html, additionalHeaders);
    }

    private async Task WriteTemporaryLinkRejectedAsync(Stream stream, int rejectionStatus)
    {
        byte[] rejectionImage = temporaryLinkUnavailableImageBytes;
        byte[] rejectionMp4 = temporaryLinkUnavailableMp4Bytes;
        byte[] rejectionWebm = temporaryLinkUnavailableWebmBytes;
        if (rejectionImage.Length > 0 || rejectionMp4.Length > 0 || rejectionWebm.Length > 0)
        {
            await WriteMediaMessagePageAsync(
                stream, rejectionStatus, rejectionStatus == 403 ? "Forbidden" : "Gone",
                rejectionImage, rejectionMp4, rejectionWebm,
                TemporaryLinkUnavailableImageAssetPath, TemporaryLinkUnavailableMp4AssetPath, TemporaryLinkUnavailableWebmAssetPath,
                new byte[0], new byte[0], new byte[0], "", "", "",
                "Temporary viewer link unavailable", null, null
            );
            return;
        }
        await WriteHttpResponseAsync(stream, rejectionStatus, rejectionStatus == 403 ? "Forbidden" : "Gone", "text/plain; charset=utf-8", "This temporary viewer link is invalid, expired, already used, or unavailable from this client.", null);
    }

    private async Task WriteTotpChallengePageAsync(Stream stream, string pendingToken, string returnTarget, bool invalid, int statusCode, string reason)
    {
        await WriteTotpChallengePageAsync(stream, pendingToken, returnTarget, invalid, statusCode, reason, null);
    }

    // Same visual shell as WriteLoginPageAsync (kept in sync by hand -- this
    // is simple enough that factoring out the shared chrome would cost more
    // clarity than it saves) so the two steps of a 2FA login read as one
    // continuous flow rather than a jarring page-style change partway
    // through.
    private async Task WriteTotpChallengePageAsync(Stream stream, string pendingToken, string returnTarget, bool invalid, int statusCode, string reason, Dictionary<string, string> additionalHeaders)
    {
        string safeReturn = GetSafeReturnTarget(returnTarget);
        string error = invalid ? "<p class=\"error\">That code was not accepted. Check your authenticator app and try again.</p>" : "";
        string html = totpChallengeTemplateText
            .Replace("{{ERROR_BLOCK}}", error)
            .Replace("{{PENDING_TOKEN}}", WebUtility.HtmlEncode(pendingToken ?? ""))
            .Replace("{{RETURN_TARGET}}", WebUtility.HtmlEncode(safeReturn))
            .Replace("{{TRUSTED_DEVICE_DAYS}}", TrustedDeviceDays.ToString());
        await WriteHttpResponseAsync(stream, statusCode, reason, "text/html; charset=utf-8", html, additionalHeaders);
    }

    private static async Task WriteRedirectAsync(Stream stream, string location)
    {
        Dictionary<string, string> headers = new Dictionary<string, string>();
        headers["Location"] = GetSafeReturnTarget(location);
        await WriteHttpResponseAsync(stream, 303, "See Other", "text/plain; charset=utf-8", "Redirecting.", headers);
    }

    private static async Task WriteHttpResponseAsync(Stream stream, int statusCode, string reason, string contentType, string body, Dictionary<string, string> additionalHeaders, string scriptNonce = null, IEnumerable<string> extraSetCookieHeaders = null)
    {
        byte[] bodyBytes = Encoding.UTF8.GetBytes(body ?? "");
        await WriteHttpResponseBytesAsync(stream, statusCode, reason, contentType, bodyBytes, additionalHeaders, scriptNonce, extraSetCookieHeaders);
    }

    private static bool TryGetMessageAsset(string path, out byte[] assetBytes, out string contentType)
    {
        assetBytes = new byte[0];
        contentType = "application/octet-stream";
        if (string.Equals(path, TemporaryLinkUnavailableImageAssetPath, StringComparison.OrdinalIgnoreCase)) { assetBytes = temporaryLinkUnavailableImageBytes; contentType = "image/png"; }
        else if (string.Equals(path, TemporaryLinkUnavailableMp4AssetPath, StringComparison.OrdinalIgnoreCase)) { assetBytes = temporaryLinkUnavailableMp4Bytes; contentType = "video/mp4"; }
        else if (string.Equals(path, TemporaryLinkUnavailableWebmAssetPath, StringComparison.OrdinalIgnoreCase)) { assetBytes = temporaryLinkUnavailableWebmBytes; contentType = "video/webm"; }
        else if (string.Equals(path, RestartImageAssetPath, StringComparison.OrdinalIgnoreCase)) { assetBytes = restartImageBytes; contentType = "image/png"; }
        else if (string.Equals(path, RestartMp4AssetPath, StringComparison.OrdinalIgnoreCase)) { assetBytes = restartMp4Bytes; contentType = "video/mp4"; }
        else if (string.Equals(path, RestartWebmAssetPath, StringComparison.OrdinalIgnoreCase)) { assetBytes = restartWebmBytes; contentType = "video/webm"; }
        else if (string.Equals(path, RestartPortraitImageAssetPath, StringComparison.OrdinalIgnoreCase)) { assetBytes = restartPortraitImageBytes; contentType = "image/png"; }
        else if (string.Equals(path, RestartPortraitMp4AssetPath, StringComparison.OrdinalIgnoreCase)) { assetBytes = restartPortraitMp4Bytes; contentType = "video/mp4"; }
        else if (string.Equals(path, RestartPortraitWebmAssetPath, StringComparison.OrdinalIgnoreCase)) { assetBytes = restartPortraitWebmBytes; contentType = "video/webm"; }
        return assetBytes != null && assetBytes.Length > 0;
    }

    private static async Task WriteMediaMessagePageAsync(
        Stream stream, int statusCode, string reason,
        byte[] imageBytes, byte[] mp4Bytes, byte[] webmBytes,
        string imageAssetPath, string mp4AssetPath, string webmAssetPath,
        byte[] portraitImageBytes, byte[] portraitMp4Bytes, byte[] portraitWebmBytes,
        string portraitImageAssetPath, string portraitMp4AssetPath, string portraitWebmAssetPath,
        string alternativeText, Dictionary<string, string> additionalHeaders, string refreshTarget)
    {
        string safeAlternativeText = WebUtility.HtmlEncode(alternativeText ?? "GStreamer Glass message");
        bool hasImage = imageBytes != null && imageBytes.Length > 0;
        bool hasMp4 = mp4Bytes != null && mp4Bytes.Length > 0;
        bool hasWebm = webmBytes != null && webmBytes.Length > 0;
        bool hasPortraitImage = portraitImageBytes != null && portraitImageBytes.Length > 0;
        bool hasPortraitMp4 = portraitMp4Bytes != null && portraitMp4Bytes.Length > 0;
        bool hasPortraitWebm = portraitWebmBytes != null && portraitWebmBytes.Length > 0;
        bool hasPortraitMedia = hasPortraitImage || hasPortraitMp4 || hasPortraitWebm;
        string poster = hasImage ? " poster=\"" + WebUtility.HtmlEncode(imageAssetPath) + "\"" : "";
        string mediaMarkup;
        if (hasMp4 || hasWebm)
        {
            string sources =
                (hasWebm ? "<source src=\"" + WebUtility.HtmlEncode(webmAssetPath) + "\" type=\"video/webm\">" : "") +
                (hasMp4 ? "<source src=\"" + WebUtility.HtmlEncode(mp4AssetPath) + "\" type=\"video/mp4\">" : "");
            string orientationData = hasPortraitMedia
                ? " data-landscape-poster=\"" + WebUtility.HtmlEncode(hasImage ? imageAssetPath : "") + "\"" +
                  " data-landscape-webm=\"" + WebUtility.HtmlEncode(hasWebm ? webmAssetPath : "") + "\"" +
                  " data-landscape-mp4=\"" + WebUtility.HtmlEncode(hasMp4 ? mp4AssetPath : "") + "\"" +
                  " data-portrait-poster=\"" + WebUtility.HtmlEncode(hasPortraitImage ? portraitImageAssetPath : "") + "\"" +
                  " data-portrait-webm=\"" + WebUtility.HtmlEncode(hasPortraitWebm ? portraitWebmAssetPath : "") + "\"" +
                  " data-portrait-mp4=\"" + WebUtility.HtmlEncode(hasPortraitMp4 ? portraitMp4AssetPath : "") + "\""
                : "";
            mediaMarkup = "<video autoplay muted loop playsinline preload=\"auto\"" + poster + orientationData + " aria-label=\"" + safeAlternativeText + "\">" + sources + "</video>";
        }
        else
        {
            mediaMarkup = hasPortraitImage
                ? "<picture><source media=\"(orientation: portrait)\" srcset=\"" + WebUtility.HtmlEncode(portraitImageAssetPath) + "\"><img src=\"" + WebUtility.HtmlEncode(imageAssetPath) + "\" alt=\"" + safeAlternativeText + "\"></picture>"
                : "<img src=\"" + WebUtility.HtmlEncode(imageAssetPath) + "\" alt=\"" + safeAlternativeText + "\">";
        }

        string scriptNonce = null;
        string script = "";
        if (!string.IsNullOrWhiteSpace(refreshTarget))
        {
            byte[] nonceBytes = new byte[16];
            using (RandomNumberGenerator random = RandomNumberGenerator.Create()) { random.GetBytes(nonceBytes); }
            scriptNonce = Base64UrlEncode(nonceBytes);
            string safeReturn = GetSafeReturnTarget(refreshTarget);
            script = "<script nonce=\"" + scriptNonce + "\" data-return=\"" + WebUtility.HtmlEncode(safeReturn) + "\" data-title=\"" + safeAlternativeText + "\">" +
                "(function(){var s=document.currentScript,t=s.dataset.return,title=s.dataset.title||'GStreamer Glass',v=document.querySelector('video'),w=null,q=window.matchMedia?matchMedia('(orientation: portrait)'):null,layout='';" +
                "function play(){if(v){v.muted=true;v.defaultMuted=true;var p=v.play();if(p&&p.catch)p.catch(function(){});}}" +
                "function media(){if(!v||(!v.dataset.portraitPoster&&!v.dataset.portraitWebm&&!v.dataset.portraitMp4))return;var portrait=!!(q&&q.matches),next=portrait?'portrait':'landscape';if(layout===next)return;layout=next;var poster=v.dataset[next+'Poster'],webm=v.dataset[next+'Webm'],mp4=v.dataset[next+'Mp4'];if(poster)v.poster=poster;while(v.firstChild)v.removeChild(v.firstChild);function add(src,type){if(!src)return;var x=document.createElement('source');x.src=src;x.type=type;v.appendChild(x);}add(webm,'video/webm');add(mp4,'video/mp4');v.load();play();}" +
                "function wake(){if(!('wakeLock' in navigator)||document.visibilityState!=='visible')return;navigator.wakeLock.request('screen').then(function(x){w=x;}).catch(function(){});}" +
                "function check(){fetch('/auth/stream-status?reload='+Date.now(),{cache:'no-store',credentials:'same-origin'}).then(function(r){return r.ok?r.json():null;}).then(function(x){if(!x)return;if(x.authenticated===false){var u=new URL('/auth/login',location.href);u.searchParams.set('return',t);location.replace(u.href);return;}if(x.forwardingPaused===false)location.replace(t);}).catch(function(){});}" +
                "function activate(){media();play();wake();}" +
                "if('mediaSession' in navigator){try{navigator.mediaSession.metadata=new MediaMetadata({title:title,artist:'GStreamer Glass',album:'Live broadcast'});navigator.mediaSession.playbackState='playing';navigator.mediaSession.setActionHandler('play',play);}catch(e){}}" +
                "if(q){var rotate=media;if(q.addEventListener)q.addEventListener('change',rotate);else if(q.addListener)q.addListener(rotate);}" +
                "document.addEventListener('visibilitychange',function(){if(document.visibilityState==='visible')activate();});" +
                "document.addEventListener('pointerdown',activate,{passive:true});media();play();wake();check();setInterval(check,2000);})();</script>";
        }
        string html = mediaMessageTemplateText
            .Replace("{{TITLE}}", safeAlternativeText)
            .Replace("{{MEDIA_MARKUP}}", mediaMarkup)
            .Replace("{{SCRIPT_BLOCK}}", script);
        await WriteHttpResponseAsync(stream, statusCode, reason, "text/html; charset=utf-8", html, additionalHeaders, scriptNonce);
    }

    private static async Task WriteHttpResponseBytesAsync(Stream stream, int statusCode, string reason, string contentType, byte[] bodyBytes, Dictionary<string, string> additionalHeaders, string scriptNonce = null, IEnumerable<string> extraSetCookieHeaders = null)
    {
        if (bodyBytes == null) bodyBytes = new byte[0];
        StringBuilder response = new StringBuilder();
        response.Append("HTTP/1.1 ").Append(statusCode).Append(' ').Append(reason).Append("\r\n");
        response.Append("Content-Type: ").Append(contentType).Append("\r\n");
        response.Append("Content-Length: ").Append(bodyBytes.Length).Append("\r\n");
        // no-store alone is the strongest, spec-correct directive (and the
        // one actually verified fixing the auth-gate-bypass-via-cache bug),
        // but the full belt-and-suspenders set costs nothing and covers
        // older/nonstandard caches that only honor Pragma/Expires.
        response.Append("Cache-Control: no-store, no-cache, must-revalidate, max-age=0\r\n");
        response.Append("Pragma: no-cache\r\n");
        response.Append("Expires: 0\r\n");
        // Authentication pages, bearer-link responses, status JSON, and
        // rejection artwork are never public discovery surfaces. This is a
        // crawler hint rather than an authorization control; the gate remains
        // the actual security boundary.
        response.Append("X-Robots-Tag: noindex, nofollow, noarchive, nosnippet, noimageindex\r\n");
        // script-src is omitted (falling back to default-src 'none', blocking
        // all script execution) unless a caller explicitly opts a specific
        // response into running one nonce-tagged inline script -- see
        // WriteLoginPageAsync's session-heartbeat script for the only current
        // user of this. manifest-src/img-src are both explicit (rather than
        // also inheriting default-src 'none') because WriteLoginPageAsync
        // links the PWA manifest and icons so the login page is installable
        // too -- without these, the <link> tags are present in the HTML but
        // the browser silently refuses to actually fetch either one, so
        // Chrome never sees a valid manifest and never offers to install
        // the page at all, regardless of how correct the markup is.
        string contentSecurityPolicy = "default-src 'none'; style-src 'unsafe-inline'; manifest-src 'self'; img-src 'self' data:; media-src 'self' data:; connect-src 'self'; form-action 'self'; frame-ancestors 'none'";
        if (!string.IsNullOrEmpty(scriptNonce))
        {
            contentSecurityPolicy += "; script-src 'nonce-" + scriptNonce + "'";
        }
        response.Append("Content-Security-Policy: ").Append(contentSecurityPolicy).Append("\r\n");
        response.Append("Referrer-Policy: no-referrer\r\n");
        response.Append("X-Content-Type-Options: nosniff\r\n");
        response.Append("X-Frame-Options: DENY\r\n");
        if (additionalHeaders != null)
        {
            foreach (KeyValuePair<string, string> header in additionalHeaders)
            {
                response.Append(header.Key).Append(": ").Append(header.Value).Append("\r\n");
            }
        }
        // A Dictionary<string,string> additionalHeaders can only ever carry
        // one Set-Cookie -- the trusted-device cookie needs to ride alongside
        // the ordinary session cookie on the same response, so it comes
        // through this separate list instead of fighting the dictionary for
        // the same key.
        if (extraSetCookieHeaders != null)
        {
            foreach (string cookieHeader in extraSetCookieHeaders)
            {
                response.Append("Set-Cookie: ").Append(cookieHeader).Append("\r\n");
            }
        }
        response.Append("Connection: close\r\n\r\n");
        byte[] headerBytes = Encoding.ASCII.GetBytes(response.ToString());
        await stream.WriteAsync(headerBytes, 0, headerBytes.Length);
        if (bodyBytes.Length > 0) await stream.WriteAsync(bodyBytes, 0, bodyBytes.Length);
        await stream.FlushAsync();
    }

    private static string GetCookieValue(Dictionary<string, string> headers, string cookieName)
    {
        string cookieHeader;
        if (!headers.TryGetValue("Cookie", out cookieHeader)) return "";
        string[] cookies = cookieHeader.Split(';');
        foreach (string cookie in cookies)
        {
            int separator = cookie.IndexOf('=');
            if (separator <= 0) continue;
            if (!string.Equals(cookie.Substring(0, separator).Trim(), cookieName, StringComparison.Ordinal)) continue;
            return cookie.Substring(separator + 1).Trim();
        }
        return "";
    }

    private static string GetAuthenticationCookie(Dictionary<string, string> headers)
    {
        return GetCookieValue(headers, "GstGlassAuth");
    }

    private bool HasValidAuthenticationCookie(Dictionary<string, string> headers)
    {
        return ValidateAuthenticationSessionToken(GetAuthenticationCookie(headers));
    }

    private bool HasValidAuthenticationCookie(Dictionary<string, string> headers, string remoteAddress)
    {
        return ValidateAuthenticationSessionTokenForAddress(GetAuthenticationCookie(headers), remoteAddress);
    }

    private string CreateAuthenticationSessionToken(string username)
    {
        return CreateBoundedAuthenticationSessionToken(username, long.MaxValue, "");
    }

    private string CreateBoundedAuthenticationSessionToken(string username, long maximumExpires, string boundAddress)
    {
        long expires = ToUnixTimeSeconds(DateTime.UtcNow.AddHours(authenticationSessionHours));
        if (maximumExpires > 0 && maximumExpires < expires) expires = maximumExpires;
        byte[] nonce = new byte[24];
        using (RandomNumberGenerator random = RandomNumberGenerator.Create())
        {
            random.GetBytes(nonce);
        }
        string payload = expires.ToString() + "." + Base64UrlEncode(nonce) + "." + Base64UrlEncode(Encoding.UTF8.GetBytes(username));
        byte[] signature;
        using (HMACSHA256 hmac = new HMACSHA256(authenticationSessionKey))
        {
            signature = hmac.ComputeHash(Encoding.UTF8.GetBytes(payload));
        }
        string token = payload + "." + Base64UrlEncode(signature);
        activeAuthenticationSessions[token] = expires;
        if (!string.IsNullOrWhiteSpace(boundAddress)) authenticationSessionBoundAddresses[token] = boundAddress;
        if (activeAuthenticationSessions.Count > 4096) RemoveExpiredAuthenticationSessions();
        return token;
    }

    private const string TrustedDeviceCookieName = "GstGlassTrustedDevice";
    private const int TrustedDeviceDays = 30;

    // Derived from authenticationSessionKey rather than reusing it directly,
    // so a trusted-device token can never be replayed as (or forged from) a
    // real session token even though both are HMAC-signed payloads of the
    // same shape -- domain separation via HKDF-style key derivation, not
    // format differences that would need careful parsing to enforce.
    private byte[] GetTrustedDeviceSigningKey()
    {
        using (HMACSHA256 hmac = new HMACSHA256(authenticationSessionKey))
        {
            return hmac.ComputeHash(Encoding.UTF8.GetBytes("gstglass-trusted-device-v1"));
        }
    }

    // "Remember this device" for 2FA: only ever skips the SECOND factor --
    // the password is still verified on every single login regardless, so a
    // stolen/expired trust cookie alone grants nothing. Deliberately
    // stateless (no activeAuthenticationSessions entry, unlike a real
    // session token) so it survives RevokeAllSessions clearing that table
    // on a stream stop/restart -- the whole point is that remembered 2FA
    // outlives those events even though regular viewer sessions do not.
    private string CreateTrustedDeviceToken(string username)
    {
        long expires = ToUnixTimeSeconds(DateTime.UtcNow.AddDays(TrustedDeviceDays));
        byte[] nonce = new byte[24];
        using (RandomNumberGenerator random = RandomNumberGenerator.Create())
        {
            random.GetBytes(nonce);
        }
        string payload = expires.ToString() + "." + Base64UrlEncode(nonce) + "." + Base64UrlEncode(Encoding.UTF8.GetBytes(username));
        byte[] signature;
        using (HMACSHA256 hmac = new HMACSHA256(GetTrustedDeviceSigningKey()))
        {
            signature = hmac.ComputeHash(Encoding.UTF8.GetBytes(payload));
        }
        return payload + "." + Base64UrlEncode(signature);
    }

    private bool ValidateTrustedDeviceToken(string token, string expectedUsername)
    {
        if (authenticationSessionKey == null || authenticationSessionKey.Length < 32 || string.IsNullOrWhiteSpace(token)) return false;
        string[] parts = token.Split('.');
        if (parts.Length != 4) return false;
        long expires;
        if (!long.TryParse(parts[0], out expires) || expires < ToUnixTimeSeconds(DateTime.UtcNow)) return false;
        string payload = parts[0] + "." + parts[1] + "." + parts[2];
        byte[] expected;
        using (HMACSHA256 hmac = new HMACSHA256(GetTrustedDeviceSigningKey()))
        {
            expected = hmac.ComputeHash(Encoding.UTF8.GetBytes(payload));
        }
        byte[] supplied;
        try { supplied = Base64UrlDecode(parts[3]); }
        catch { return false; }
        if (!FixedTimeEquals(expected, supplied)) return false;
        try
        {
            string username = Encoding.UTF8.GetString(Base64UrlDecode(parts[2]));
            // Checked against the CURRENT account list, same reasoning as
            // ValidateAuthenticationSessionToken -- removing the account
            // revokes trust immediately too.
            return string.Equals(username, expectedUsername, StringComparison.Ordinal) && FindAuthenticationAccount(username) != null;
        }
        catch { return false; }
    }

    // Shared by every path that lands a viewer in a full, real session --
    // no-2FA login, a trusted-device 2FA skip, and a successful /auth/verify
    // -- so the cookie attributes and success log line can never drift
    // between them.
    //
    // SameSite=Lax, not Strict: an installed Android PWA relaunched from its
    // home-screen icon (no live browser tab, cold WebAPK start) is treated
    // by Chrome as enough of a boundary that a Strict cookie doesn't survive
    // it -- this is a well-documented, widely-reported class of bug across
    // unrelated PWA projects (e.g. github.com/pocketbase/pocketbase
    // discussions/2972, github.com/miniflux/v2 issues/3614), not something
    // specific to this app, and switching to Lax is the confirmed fix in
    // both. Lax still withholds the cookie from cross-site POSTs/iframes/
    // subresource requests -- the actual state-changing actions here
    // (login, verify) are POST-only, so this does not meaningfully change
    // the CSRF surface, only permits the cookie to survive a same-site
    // top-level GET/app-launch navigation the way Strict was never able to.
    private async Task IssueAuthenticationSessionResponseAsync(Stream stream, string username, string returnTarget, string remoteAddress, string logSuffix, List<string> extraSetCookieHeaders)
    {
        await IssueAuthenticationSessionResponseAsync(stream, username, returnTarget, remoteAddress, logSuffix, extraSetCookieHeaders, long.MaxValue, "");
    }

    private async Task IssueAuthenticationSessionResponseAsync(Stream stream, string username, string returnTarget, string remoteAddress, string logSuffix, List<string> extraSetCookieHeaders, long maximumExpires, string boundAddress)
    {
        long now = ToUnixTimeSeconds(DateTime.UtcNow);
        long effectiveExpires = Math.Min(ToUnixTimeSeconds(DateTime.UtcNow.AddHours(authenticationSessionHours)), maximumExpires > 0 ? maximumExpires : long.MaxValue);
        int maxAge = (int)Math.Max(1, Math.Min(int.MaxValue, effectiveExpires - now));
        string token = CreateBoundedAuthenticationSessionToken(username, effectiveExpires, boundAddress);
        Dictionary<string, string> headers = new Dictionary<string, string>();
        headers["Set-Cookie"] = "GstGlassAuth=" + token + "; Path=/; HttpOnly" + CookieSecureAttribute + "; SameSite=Lax; Max-Age=" + maxAge.ToString();
        headers["Location"] = GetSafeReturnTarget(returnTarget);
        pendingLog.Enqueue("viewer '" + username + "' authenticated from " + remoteAddress + logSuffix);
        await WriteHttpResponseAsync(stream, 303, "See Other", "text/plain; charset=utf-8", "Authenticated.", headers, null, extraSetCookieHeaders);
    }

    // Carries "password already verified for this username" across the
    // login -> code-entry round trip without a session cookie. Signed with
    // the same key as real session tokens but in a structurally distinct,
    // shorter-lived shape (5 leading "totp." segments vs. a session token's
    // 4) -- ValidateAuthenticationSessionToken's 4-part check alone already
    // rejects this shape, and this method is never consulted by the normal
    // cookie-gate path, so a pending token can never be replayed as a
    // session credential.
    private string CreatePendingTotpToken(string username)
    {
        long expires = ToUnixTimeSeconds(DateTime.UtcNow.AddMinutes(5));
        byte[] nonce = new byte[24];
        using (RandomNumberGenerator random = RandomNumberGenerator.Create())
        {
            random.GetBytes(nonce);
        }
        string payload = "totp." + expires.ToString() + "." + Base64UrlEncode(nonce) + "." + Base64UrlEncode(Encoding.UTF8.GetBytes(username));
        byte[] signature;
        using (HMACSHA256 hmac = new HMACSHA256(authenticationSessionKey))
        {
            signature = hmac.ComputeHash(Encoding.UTF8.GetBytes(payload));
        }
        return payload + "." + Base64UrlEncode(signature);
    }

    // Returns the embedded username when the token is a validly signed,
    // unexpired pending-2FA challenge; null otherwise. Deliberately stops
    // short of checking anything about the account itself (existence, TOTP
    // secret) -- callers combine this with FindAuthenticationAccount so a
    // removed-mid-challenge account is treated the same as any other
    // invalid token.
    private string ValidatePendingTotpToken(string token)
    {
        if (authenticationSessionKey == null || authenticationSessionKey.Length < 32 || string.IsNullOrWhiteSpace(token)) return null;
        string[] parts = token.Split('.');
        if (parts.Length != 5 || parts[0] != "totp") return null;
        long expires;
        if (!long.TryParse(parts[1], out expires) || expires < ToUnixTimeSeconds(DateTime.UtcNow)) return null;
        string payload = parts[0] + "." + parts[1] + "." + parts[2] + "." + parts[3];
        byte[] expected;
        using (HMACSHA256 hmac = new HMACSHA256(authenticationSessionKey))
        {
            expected = hmac.ComputeHash(Encoding.UTF8.GetBytes(payload));
        }
        byte[] supplied;
        try { supplied = Base64UrlDecode(parts[4]); }
        catch { return null; }
        if (!FixedTimeEquals(expected, supplied)) return null;
        try { return Encoding.UTF8.GetString(Base64UrlDecode(parts[3])); }
        catch { return null; }
    }

    // Best-effort, unvalidated extraction of a token's embedded username for
    // a nicer log line -- never used for an authorization decision (that's
    // ValidateAuthenticationSessionToken, which also checks the HMAC
    // signature and session-table membership).
    private static string GetTokenUsernameForLogging(string token)
    {
        if (string.IsNullOrWhiteSpace(token)) return null;
        string[] parts = token.Split('.');
        if (parts.Length != 4) return null;
        try { return Encoding.UTF8.GetString(Base64UrlDecode(parts[2])); }
        catch { return null; }
    }

    private bool ValidateAuthenticationSessionToken(string token)
    {
        return ValidateAuthenticationSessionTokenForAddress(token, null);
    }

    private bool ValidateAuthenticationSessionTokenForAddress(string token, string remoteAddress)
    {
        if (authenticationSessionKey == null || authenticationSessionKey.Length < 32 || string.IsNullOrWhiteSpace(token)) return false;
        string[] parts = token.Split('.');
        if (parts.Length != 4) return false;
        long expires;
        if (!long.TryParse(parts[0], out expires) || expires < ToUnixTimeSeconds(DateTime.UtcNow)) return false;
        string payload = parts[0] + "." + parts[1] + "." + parts[2];
        byte[] expected;
        using (HMACSHA256 hmac = new HMACSHA256(authenticationSessionKey))
        {
            expected = hmac.ComputeHash(Encoding.UTF8.GetBytes(payload));
        }
        byte[] supplied;
        try { supplied = Base64UrlDecode(parts[3]); }
        catch { return false; }
        if (!FixedTimeEquals(expected, supplied)) return false;
        try
        {
            // Checked against the CURRENT account list, not a snapshot taken
            // at login time -- removing an account revokes every session it
            // already issued immediately, without needing a proxy restart.
            string username = Encoding.UTF8.GetString(Base64UrlDecode(parts[2]));
            if (FindAuthenticationAccount(username) == null) return false;
            long registeredExpiry;
            if (!activeAuthenticationSessions.TryGetValue(token, out registeredExpiry) || registeredExpiry != expires) return false;
            string boundAddress;
            if (authenticationSessionBoundAddresses.TryGetValue(token, out boundAddress) && !string.IsNullOrWhiteSpace(boundAddress))
                return !string.IsNullOrWhiteSpace(remoteAddress) && string.Equals(boundAddress, remoteAddress, StringComparison.OrdinalIgnoreCase);
            return true;
        }
        catch { return false; }
    }

    private static void RemoveExpiredAuthenticationSessions()
    {
        long now = ToUnixTimeSeconds(DateTime.UtcNow);
        foreach (KeyValuePair<string, long> session in activeAuthenticationSessions)
        {
            if (session.Value >= now) continue;
            long removedExpiry;
            activeAuthenticationSessions.TryRemove(session.Key, out removedExpiry);
            string removedBoundAddress;
            authenticationSessionBoundAddresses.TryRemove(session.Key, out removedBoundAddress);
        }
    }

    private bool TryValidateTemporaryAuthenticationLink(string token, string remoteAddress, string expectedPurpose, out TemporaryAuthenticationLinkState validated, out string reason, out int statusCode)
    {
        validated = null;
        reason = "not found";
        statusCode = 410;
        if (string.IsNullOrWhiteSpace(token)) return false;
        TemporaryAuthenticationLinkState current;
        if (!temporaryAuthenticationLinks.TryGetValue(token, out current) || current == null) return false;
        if (!string.Equals(NormalizeTemporaryLinkPurpose(current.Purpose), NormalizeTemporaryLinkPurpose(expectedPurpose), StringComparison.Ordinal))
        {
            reason = "wrong link purpose";
            return false;
        }
        long now = ToUnixTimeSeconds(DateTime.UtcNow);
        if (current.Expires < now)
        {
            TemporaryAuthenticationLinkState expired;
            temporaryAuthenticationLinks.TryRemove(token, out expired);
            reason = "expired";
            return false;
        }
        if (FindAuthenticationAccount(current.Username) == null)
        {
            TemporaryAuthenticationLinkState orphaned;
            temporaryAuthenticationLinks.TryRemove(token, out orphaned);
            reason = "account removed";
            return false;
        }
        if (!string.IsNullOrWhiteSpace(current.BoundAddress) && !string.Equals(current.BoundAddress, remoteAddress, StringComparison.OrdinalIgnoreCase))
        {
            reason = "client IP does not match restriction";
            statusCode = 403;
            return false;
        }
        validated = CloneTemporaryAuthenticationLink(current);
        reason = "accepted";
        statusCode = 200;
        return true;
    }

    private bool TryRedeemTemporaryAuthenticationLink(string token, string remoteAddress, string expectedPurpose, out TemporaryAuthenticationLinkState redeemed, out string reason, out int statusCode)
    {
        redeemed = null;
        TemporaryAuthenticationLinkState current;
        if (!TryValidateTemporaryAuthenticationLink(token, remoteAddress, expectedPurpose, out current, out reason, out statusCode))
        {
            return false;
        }
        if (current.SingleUse || string.Equals(NormalizeTemporaryLinkPurpose(expectedPurpose), "setup", StringComparison.Ordinal))
        {
            TemporaryAuthenticationLinkState consumed;
            if (!temporaryAuthenticationLinks.TryRemove(token, out consumed))
            {
                reason = "already used";
                return false;
            }
            current = consumed;
        }
        redeemed = CloneTemporaryAuthenticationLink(current);
        reason = "accepted";
        statusCode = 200;
        return true;
    }

    private int GetAuthenticationRetryAfterSeconds(string remoteAddress)
    {
        AuthenticationFailureState state;
        if (!authenticationFailures.TryGetValue(remoteAddress, out state)) return 0;
        lock (state)
        {
            DateTime now = DateTime.UtcNow;
            if (state.LockedUntilUtc <= now) return 0;
            return Math.Max(1, (int)Math.Ceiling((state.LockedUntilUtc - now).TotalSeconds));
        }
    }

    private void RecordAuthenticationFailure(string remoteAddress)
    {
        if (authenticationFailures.Count > 4096 && !authenticationFailures.ContainsKey(remoteAddress))
        {
            authenticationFailures.Clear();
        }
        AuthenticationFailureState state = authenticationFailures.GetOrAdd(remoteAddress, delegate(string _)
        {
            return new AuthenticationFailureState { Count = 0, WindowStartedUtc = DateTime.UtcNow, LockedUntilUtc = DateTime.MinValue };
        });
        lock (state)
        {
            DateTime now = DateTime.UtcNow;
            if ((now - state.WindowStartedUtc).TotalMinutes >= 5)
            {
                state.Count = 0;
                state.WindowStartedUtc = now;
                state.LockedUntilUtc = DateTime.MinValue;
            }
            state.Count++;
            if (state.Count >= 5) state.LockedUntilUtc = now.AddSeconds(60);
        }
    }

    private static bool VerifyAuthenticationPassword(string password, string encodedHash)
    {
        byte[] salt = new byte[16];
        int iterations = 600000;
        byte[] expected = new byte[32];
        bool formatValid = false;
        try
        {
            string[] parts = (encodedHash ?? "").Split('$');
            if (parts.Length == 4 && parts[0] == "pbkdf2-sha256")
            {
                iterations = int.Parse(parts[1]);
                salt = Convert.FromBase64String(parts[2]);
                expected = Convert.FromBase64String(parts[3]);
                formatValid = iterations >= 100000 && iterations <= 2000000 && salt.Length >= 16 && expected.Length == 32;
            }
        }
        catch { formatValid = false; }
        if (!formatValid)
        {
            salt = new byte[16];
            expected = new byte[32];
            iterations = 600000;
        }
        byte[] actual = Pbkdf2Sha256(password ?? "", salt, iterations, expected.Length);
        return formatValid && FixedTimeEquals(actual, expected);
    }

    private static byte[] Pbkdf2Sha256(string password, byte[] salt, int iterations, int outputLength)
    {
        byte[] passwordBytes = Encoding.UTF8.GetBytes(password ?? "");
        try
        {
            using (HMACSHA256 hmac = new HMACSHA256(passwordBytes))
            {
                const int hashLength = 32;
                int blockCount = (int)Math.Ceiling((double)outputLength / hashLength);
                byte[] output = new byte[outputLength];
                int outputOffset = 0;
                for (int block = 1; block <= blockCount; block++)
                {
                    byte[] blockInput = new byte[salt.Length + 4];
                    Buffer.BlockCopy(salt, 0, blockInput, 0, salt.Length);
                    blockInput[salt.Length] = (byte)(block >> 24);
                    blockInput[salt.Length + 1] = (byte)(block >> 16);
                    blockInput[salt.Length + 2] = (byte)(block >> 8);
                    blockInput[salt.Length + 3] = (byte)block;
                    byte[] u = hmac.ComputeHash(blockInput);
                    byte[] accumulator = (byte[])u.Clone();
                    for (int iteration = 1; iteration < iterations; iteration++)
                    {
                        u = hmac.ComputeHash(u);
                        for (int i = 0; i < accumulator.Length; i++) accumulator[i] ^= u[i];
                    }
                    int copyLength = Math.Min(hashLength, outputLength - outputOffset);
                    Buffer.BlockCopy(accumulator, 0, output, outputOffset, copyLength);
                    outputOffset += copyLength;
                }
                return output;
            }
        }
        finally
        {
            Array.Clear(passwordBytes, 0, passwordBytes.Length);
        }
    }

    private static bool FixedTimeEquals(byte[] left, byte[] right)
    {
        if (left == null || right == null) return false;
        int difference = left.Length ^ right.Length;
        int length = Math.Max(left.Length, right.Length);
        for (int i = 0; i < length; i++)
        {
            byte a = i < left.Length ? left[i] : (byte)0;
            byte b = i < right.Length ? right[i] : (byte)0;
            difference |= a ^ b;
        }
        return difference == 0;
    }

    private static Dictionary<string, string> ParseUrlEncoded(string encoded)
    {
        Dictionary<string, string> values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (string pair in (encoded ?? "").Split('&'))
        {
            int separator = pair.IndexOf('=');
            string name = separator >= 0 ? pair.Substring(0, separator) : pair;
            string value = separator >= 0 ? pair.Substring(separator + 1) : "";
            values[UrlDecode(name)] = UrlDecode(value);
        }
        return values;
    }

    private static string GetQueryValue(string target, string name)
    {
        int query = (target ?? "").IndexOf('?');
        if (query < 0 || query == target.Length - 1) return "";
        Dictionary<string, string> values = ParseUrlEncoded(target.Substring(query + 1));
        string value;
        return values.TryGetValue(name, out value) ? value : "";
    }

    private static string UrlDecode(string value)
    {
        try { return Uri.UnescapeDataString((value ?? "").Replace("+", " ")); }
        catch { return ""; }
    }

    private static string GetSafeReturnTarget(string target)
    {
        string value = string.IsNullOrWhiteSpace(target) ? "/live/" : target.Trim();
        string decoded = value;
        try { decoded = Uri.UnescapeDataString(value); } catch { }
        if (!value.StartsWith("/", StringComparison.Ordinal) ||
            value.StartsWith("//", StringComparison.Ordinal) ||
            value.StartsWith("/\\", StringComparison.Ordinal) ||
            decoded.StartsWith("//", StringComparison.Ordinal) ||
            decoded.StartsWith("/\\", StringComparison.Ordinal) ||
            value.IndexOf('\r') >= 0 ||
            value.IndexOf('\n') >= 0)
        {
            return "/live/";
        }
        return value;
    }

    private static string Base64UrlEncode(byte[] value)
    {
        return Convert.ToBase64String(value).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    }

    private static byte[] Base64UrlDecode(string value)
    {
        string padded = (value ?? "").Replace('-', '+').Replace('_', '/');
        switch (padded.Length % 4)
        {
            case 2: padded += "=="; break;
            case 3: padded += "="; break;
        }
        return Convert.FromBase64String(padded);
    }

    private static long ToUnixTimeSeconds(DateTime utc)
    {
        return (long)(utc.ToUniversalTime() - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalSeconds;
    }

    private static async Task PumpAsync(Stream source, Stream destination)
    {
        try
        {
            await source.CopyToAsync(destination);
        }
        catch
        {
        }
    }

    // Same as PumpAsync, but peeks at a normal HTTP response header so every
    // viewer resource can receive the site-wide robots policy. The navigable
    // document additionally receives no-store while auth is enabled. The
    // body is still copied as a transparent stream, so arbitrarily large
    // assets remain safe and WebSocket upgrades never enter this path.
    private static async Task PumpResponseWithPolicyHeadersAsync(Stream source, Stream destination, bool suppressDocumentCaching)
    {
        try
        {
            byte[] responseHeader = await ReadHttpHeaderBlockAsync(source);
            if (responseHeader.Length > 0)
            {
                byte[] rewritten = InjectResponsePolicyHeaders(responseHeader, suppressDocumentCaching);
                await destination.WriteAsync(rewritten, 0, rewritten.Length);
            }
            await source.CopyToAsync(destination);
        }
        catch
        {
        }
    }

    // Reads exactly up through the blank line that ends an HTTP message's
    // headers, one byte at a time -- generic over direction (a request's
    // headers and a response's headers both end in the same "\r\n\r\n", and
    // this makes no assumptions about which side of the connection it's
    // reading), used both for the client's initial request (this runs once
    // per connection at setup, not on the media data path, so simplicity
    // wins over throughput here) and, in PumpResponseWithPolicyHeadersAsync, for
    // peeking the upstream's response headers on the way back out. Whatever
    // is read is later replayed verbatim so no bytes are lost to the peek.
    // Bails out (returning what it has) past a generous cap so a non-HTTP or
    // malformed peer can't buffer unbounded data.
    private static async Task<byte[]> ReadHttpHeaderBlockAsync(Stream stream)
    {
        List<byte> buffer = new List<byte>();
        byte[] one = new byte[1];
        int matched = 0;
        byte[] terminator = new byte[] { (byte)'\r', (byte)'\n', (byte)'\r', (byte)'\n' };
        while (buffer.Count < 16384)
        {
            int read;
            try { read = await stream.ReadAsync(one, 0, 1); }
            catch { break; }
            if (read <= 0) break;
            buffer.Add(one[0]);
            matched = (one[0] == terminator[matched]) ? matched + 1 : (one[0] == terminator[0] ? 1 : 0);
            if (matched == terminator.Length) break;
        }
        return buffer.ToArray();
    }

    private static string ExtractHttpRequestPath(byte[] header)
    {
        if (header == null || header.Length == 0) return null;
        string text;
        try { text = System.Text.Encoding.ASCII.GetString(header); }
        catch { return null; }
        int lineEnd = text.IndexOf("\r\n");
        string requestLine = lineEnd >= 0 ? text.Substring(0, lineEnd) : text;
        string[] parts = requestLine.Split(' ');
        if (parts.Length < 2) return null;
        string path = parts[1];
        int query = path.IndexOf('?');
        if (query >= 0) path = path.Substring(0, query);
        return path.TrimEnd('/');
    }

    // True for the actual navigable document (the viewer mount root, e.g.
    // "/live", and its index.html) as opposed to sub-resources fetched by
    // that page (player.js, config.js, images, ...). Matters specifically
    // for cache suppression: the document itself must always be refetched
    // so an invalidated session gets caught by the auth gate on every
    // navigation, but blanket no-store on every forwarded response would
    // needlessly defeat legitimate, harmless caching of static assets that
    // already use their own cache-busted URLs (player.js's ?v=...&t=...).
    private bool IsDocumentEntryPath(string path)
    {
        if (string.IsNullOrEmpty(DirectoryRedirectPath) || string.IsNullOrEmpty(path)) return false;
        string mount = DirectoryRedirectPath.TrimEnd('/');
        string trimmed = path.TrimEnd('/');
        return string.Equals(trimmed, mount, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(trimmed, mount + "/index.html", StringComparison.OrdinalIgnoreCase);
    }

    // The PWA manifest and its icons must be reachable without a valid
    // session -- WriteLoginPageAsync links them too (so the login page
    // itself is installable, not just the player), and if fetching the
    // manifest got redirected to /auth/login like any other gated
    // sub-resource, the browser would try to parse that HTML as JSON and
    // never consider the page installable in the first place. Neither file
    // is sensitive: a manifest and some branding icons, not viewer content.
    private static bool IsPublicPwaAssetPath(string path)
    {
        if (string.IsNullOrEmpty(path)) return false;
        return path.EndsWith("/manifest.webmanifest", StringComparison.OrdinalIgnoreCase) ||
            path.IndexOf("/icons/", StringComparison.OrdinalIgnoreCase) >= 0;
    }

    private static bool IsWebSocketUpgradeRequest(byte[] header)
    {
        if (header == null || header.Length == 0) return false;
        string text;
        try { text = Encoding.ASCII.GetString(header); }
        catch { return false; }
        string[] lines = text.Split(new string[] { "\r\n" }, StringSplitOptions.None);
        Dictionary<string, string> headers = ParseHttpHeaders(lines);
        string upgrade;
        return headers.TryGetValue("Upgrade", out upgrade) && upgrade.IndexOf("websocket", StringComparison.OrdinalIgnoreCase) >= 0;
    }

    private bool HasOwnProxyLoopMarker(byte[] header)
    {
        if (header == null || header.Length == 0) return false;
        string text;
        try { text = Encoding.ASCII.GetString(header); }
        catch { return false; }
        string[] lines = text.Split(new string[] { "\r\n" }, StringSplitOptions.None);
        Dictionary<string, string> headers = ParseHttpHeaders(lines);
        string marker;
        return headers.TryGetValue("X-GstGlass-Proxy-Hop", out marker) &&
            string.Equals(marker.Trim(), proxyLoopToken, StringComparison.Ordinal);
    }

    private byte[] InjectOwnProxyLoopMarker(byte[] header)
    {
        string text;
        try { text = Encoding.ASCII.GetString(header); }
        catch { return header; }
        string[] lines = text.Split(new string[] { "\r\n" }, StringSplitOptions.None);
        List<string> rebuilt = new List<string>();
        foreach (string line in lines)
        {
            int separator = line.IndexOf(':');
            if (separator > 0 && string.Equals(line.Substring(0, separator).Trim(), "X-GstGlass-Proxy-Hop", StringComparison.OrdinalIgnoreCase))
            {
                // Strip any client-supplied value. Only this instance's fresh
                // token is allowed to travel toward its configured upstream.
                continue;
            }
            rebuilt.Add(line);
        }
        int insertAt = rebuilt.Count >= 2 ? rebuilt.Count - 2 : rebuilt.Count;
        rebuilt.Insert(Math.Max(0, insertAt), "X-GstGlass-Proxy-Hop: " + proxyLoopToken);
        try { return Encoding.ASCII.GetBytes(string.Join("\r\n", rebuilt)); }
        catch { return header; }
    }

    // Rewrites (or adds) a Connection header on a raw HTTP request so the
    // header always reads "Connection: close", forcing a compliant upstream
    // HTTP/1.1 server to close after answering rather than keeping the
    // connection alive for a request it never actually said. Operates on the
    // exact header-line split produced by "\r\n", so re-joining always
    // reproduces byte-for-byte valid CRLF-terminated request text.
    private static byte[] ForceConnectionCloseHeader(byte[] header)
    {
        string text;
        try { text = Encoding.ASCII.GetString(header); }
        catch { return header; }
        string[] lines = text.Split(new string[] { "\r\n" }, StringSplitOptions.None);
        List<string> rebuilt = new List<string>();
        bool sawConnection = false;
        foreach (string line in lines)
        {
            int separator = line.IndexOf(':');
            if (separator > 0 && string.Equals(line.Substring(0, separator).Trim(), "Connection", StringComparison.OrdinalIgnoreCase))
            {
                rebuilt.Add("Connection: close");
                sawConnection = true;
            }
            else
            {
                rebuilt.Add(line);
            }
        }
        if (!sawConnection)
        {
            // The split of a well-formed "...\r\n\r\n" request always ends in
            // two empty strings (the blank line, then after the final CRLF);
            // insert just before those so the blank-line terminator survives.
            int insertAt = rebuilt.Count >= 2 ? rebuilt.Count - 2 : rebuilt.Count;
            rebuilt.Insert(Math.Max(0, insertAt), "Connection: close");
        }
        try { return Encoding.ASCII.GetBytes(string.Join("\r\n", rebuilt)); }
        catch { return header; }
    }

    // There is no way to reach into a browser's cache and purge a specific
    // already-cached response after the fact -- the only lever a server has
    // is what Cache-Control it sends on each response going forward. So
    // "invalidate the viewer document on logout" has to mean "never let it
    // become cacheable while auth is in play at all": a stale cached copy
    // of /live/ served straight from disk cache after a real logout is
    // exactly what let a logged-out browser keep showing the player instead
    // of ever re-hitting this gate. Cache suppression remains limited to
    // authenticated document responses; the site-wide X-Robots-Tag is
    // independently applied to every ordinary proxied HTTP response.
    private static byte[] InjectResponsePolicyHeaders(byte[] header, bool suppressDocumentCaching)
    {
        Dictionary<string, string> replacements = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            { "X-Robots-Tag", "X-Robots-Tag: noindex, nofollow, noarchive, nosnippet, noimageindex" }
        };
        if (suppressDocumentCaching)
        {
            // no-store alone is the strongest, spec-correct directive, but
            // these matching legacy headers cover nonstandard caches too.
            replacements["Cache-Control"] = "Cache-Control: no-store, no-cache, must-revalidate, max-age=0";
            replacements["Pragma"] = "Pragma: no-cache";
            replacements["Expires"] = "Expires: 0";
        }
        string text;
        try { text = Encoding.ASCII.GetString(header); }
        catch { return header; }
        string[] lines = text.Split(new string[] { "\r\n" }, StringSplitOptions.None);
        List<string> rebuilt = new List<string>();
        HashSet<string> seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (string line in lines)
        {
            int separator = line.IndexOf(':');
            string name = separator > 0 ? line.Substring(0, separator).Trim() : null;
            string replacement;
            if (name != null && replacements.TryGetValue(name, out replacement))
            {
                rebuilt.Add(replacement);
                seen.Add(name);
            }
            else
            {
                rebuilt.Add(line);
            }
        }
        int insertAt = rebuilt.Count >= 2 ? rebuilt.Count - 2 : rebuilt.Count;
        foreach (KeyValuePair<string, string> entry in replacements)
        {
            if (seen.Contains(entry.Key)) continue;
            rebuilt.Insert(Math.Max(0, insertAt), entry.Value);
        }
        try { return Encoding.ASCII.GetBytes(string.Join("\r\n", rebuilt)); }
        catch { return header; }
    }
}
'@
}

if ($AuthProxyWorker) {
    # Hosts every TlsTerminatingProxy instance (both auth families:
    # embedded TLS + plaintext auth) in a disposable process, so a
    # misbehaving proxy -- e.g. a runaway reconnect loop pegging CPU and
    # exhausting the shared .NET thread pool, the exact mechanism behind an
    # earlier whole-app UI freeze -- can never starve the UI process's own
    # threads/message pump. See 33-LetsEncrypt.ps1's Start-AuthProxyWorker
    # for the UI-side half of this. Placed after the TlsTerminatingProxy
    # Add-Type block above (unlike the two worker blocks earlier in this
    # file) because it needs that class to already be defined -- this
    # script executes top-to-bottom, and a function/type is only callable
    # once its own definition has actually run.
    #
    # Unlike the scene-preview/port-range workers above, this is a
    # persistent request/response server -- many commands over its whole
    # lifetime, not one Start plus incremental updates -- and needs no
    # GMainContext pump, since TlsTerminatingProxy is plain .NET
    # (TcpListener/SslStream), not glib-driven. A simple synchronous
    # ReadLine loop is enough.
    if ([string]::IsNullOrWhiteSpace($AuthProxyWorkerPipe)) { exit 64 }

    $proxiesByFamily = @{ LetsEncrypt = @(); Plaintext = @() }

    function New-AuthProxyAccountObjects {
        param($Accounts)
        return [TlsTerminatingProxy+AuthenticationAccount[]]@(
            @($Accounts) | ForEach-Object {
                $account = [TlsTerminatingProxy+AuthenticationAccount]::new()
                $account.Username = [string]$_.Username
                $account.PasswordHash = [string]$_.PasswordHash
                $account.TotpSecret = [string]$_.TotpSecret
                $account
            }
        )
    }

    # Do not send dynamically-compiled CLR objects directly across the JSON
    # boundary. Windows PowerShell's adapter inside the packaged PS2EXE host
    # can expose their public fields differently than console PowerShell,
    # producing records with no Token/Username/Expires values. Materializing
    # an ordinary PowerShell object keeps the IPC contract host-independent.
    function ConvertTo-AuthProxyTemporaryLinkRecord {
        param($Link)
        if (-not $Link) { return $null }
        return [pscustomobject][ordered]@{
            Token = [string]$Link.Token
            Username = [string]$Link.Username
            Expires = [long]$Link.Expires
            SingleUse = [bool]$Link.SingleUse
            BoundAddress = [string]$Link.BoundAddress
            Purpose = [string]$Link.Purpose
            RequireTotp = [bool]$Link.RequireTotp
            TotpSecret = [string]$Link.TotpSecret
        }
    }

    function ConvertTo-AuthProxyAccountUpdateRecord {
        param($Update)
        if (-not $Update) { return $null }
        return [pscustomobject][ordered]@{
            Username = [string]$Update.Username
            PasswordHash = [string]$Update.PasswordHash
            TotpSecret = [string]$Update.TotpSecret
            SessionsRevoked = [int]$Update.SessionsRevoked
        }
    }

    function Stop-AuthProxyFamily {
        param([string]$Family)
        foreach ($proxy in @($proxiesByFamily[$Family])) {
            try { $proxy.Stop() } catch {}
        }
        $proxiesByFamily[$Family] = @()
    }

    function Invoke-AuthProxyWorkerCommand {
        param($Command)
        switch ([string]$Command.Type) {
            'StartFamily' {
                $family = [string]$Command.Family
                Stop-AuthProxyFamily -Family $family
                $certificate = $null
                if (-not [string]::IsNullOrEmpty([string]$Command.CertificatePfxBase64)) {
                    $certBytes = [Convert]::FromBase64String([string]$Command.CertificatePfxBase64)
                    $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certBytes, '')
                }
                $accountObjects = New-AuthProxyAccountObjects -Accounts $Command.Accounts
                $errors = New-Object System.Collections.Generic.List[string]
                $started = New-Object System.Collections.Generic.List[object]
                foreach ($portInfo in @($Command.Ports)) {
                    try {
                        $proxy = New-Object TlsTerminatingProxy
                        $proxy.Label = [string]$portInfo.Label
                        $proxy.AuthenticationMountPath = [string]$Command.AuthenticationMountPath
                        $proxy.ConfigureTemporaryLinkUnavailableImage([string]$Command.TemporaryLinkUnavailableImagePath)
                        $proxy.ConfigureTemporaryLinkUnavailableVideos(
                            [string]$Command.TemporaryLinkUnavailableVideoMp4Path,
                            [string]$Command.TemporaryLinkUnavailableVideoWebmPath
                        )
                        $proxy.ConfigureRestartImage([string]$Command.RestartImagePath)
                        $proxy.ConfigureRestartVideos(
                            [string]$Command.RestartVideoMp4Path,
                            [string]$Command.RestartVideoWebmPath
                        )
                        $proxy.ConfigureRestartPortraitImage([string]$Command.RestartPortraitImagePath)
                        $proxy.ConfigureRestartPortraitVideos(
                            [string]$Command.RestartPortraitVideoMp4Path,
                            [string]$Command.RestartPortraitVideoWebmPath
                        )
                        $proxy.ConfigureLoginTemplate([string]$Command.LoginTemplatePath)
                        $proxy.ConfigureLinkConfirmTemplate([string]$Command.LinkConfirmTemplatePath)
                        $proxy.ConfigureAccountSetupTemplate([string]$Command.AccountSetupTemplatePath)
                        $proxy.ConfigureTotpChallengeTemplate([string]$Command.TotpChallengeTemplatePath)
                        $proxy.ConfigureMediaMessageTemplate([string]$Command.MediaMessageTemplatePath)
                        $proxy.ConfigureTrustedForwardingProxies([string[]]@($Command.TrustedForwardingProxyAddresses))
                        foreach ($route in @($portInfo.PathRoutes)) {
                            $proxy.AddPathRoute([string]$route.Path, [int]$route.Port)
                        }
                        if (-not [string]::IsNullOrEmpty([string]$portInfo.DirectoryRedirectPath)) {
                            $proxy.DirectoryRedirectPath = [string]$portInfo.DirectoryRedirectPath
                        }
                        if ([bool]$Command.AuthenticationEnabled) {
                            $proxy.ConfigureAuthentication($true, $accountObjects, [Convert]::FromBase64String([string]$Command.SessionKeyBase64), [int]$Command.SessionHours)
                        }
                        $proxy.Start([int]$portInfo.ExternalPort, '127.0.0.1', [int]$portInfo.InternalPort, $certificate)
                        $started.Add($proxy)
                    }
                    catch {
                        $errors.Add("$($portInfo.Label): $($_.Exception.Message)")
                    }
                }
                $proxiesByFamily[$family] = $started.ToArray()
                if ($started.Count -gt 0) {
                    return @{ Status = 'Ready'; Error = ($errors -join '; ') }
                }
                return @{ Status = 'Error'; Error = $(if ($errors.Count -gt 0) { $errors -join '; ' } else { 'no ports were configured' }) }
            }
            'StopFamily' {
                Stop-AuthProxyFamily -Family ([string]$Command.Family)
                return @{ Status = 'Ready'; Error = '' }
            }
            'ConfigureAuthentication' {
                $family = [string]$Command.Family
                $accountObjects = New-AuthProxyAccountObjects -Accounts $Command.Accounts
                foreach ($proxy in @($proxiesByFamily[$family])) {
                    try { $proxy.ConfigureAuthentication($true, $accountObjects, [Convert]::FromBase64String([string]$Command.SessionKeyBase64), [int]$Command.SessionHours) } catch {}
                }
                return @{ Status = 'Ready'; Error = '' }
            }
            'SuspendForwarding' {
                foreach ($proxy in (@($proxiesByFamily['LetsEncrypt']) + @($proxiesByFamily['Plaintext']))) {
                    try { $proxy.PauseForwarding() } catch {}
                }
                return @{ Status = 'Ready'; Error = '' }
            }
            'ResumeForwarding' {
                foreach ($proxy in (@($proxiesByFamily['LetsEncrypt']) + @($proxiesByFamily['Plaintext']))) {
                    try { $proxy.ResumeForwarding() } catch {}
                }
                return @{ Status = 'Ready'; Error = '' }
            }
            'DisconnectConnections' {
                foreach ($proxy in (@($proxiesByFamily['LetsEncrypt']) + @($proxiesByFamily['Plaintext']))) {
                    try { $proxy.DisconnectActiveConnections() } catch {}
                }
                return @{ Status = 'Ready'; Error = '' }
            }
            'RevokeSessions' {
                $any = (@($proxiesByFamily['LetsEncrypt']) + @($proxiesByFamily['Plaintext'])) | Select-Object -First 1
                if ($any) { try { $any.RevokeAllSessions() } catch {} }
                return @{ Status = 'Ready'; Error = '' }
            }
            'ExportSessions' {
                $any = (@($proxiesByFamily['LetsEncrypt']) + @($proxiesByFamily['Plaintext'])) | Select-Object -First 1
                $sessions = if ($any) { @($any.ExportActiveAuthenticationSessions()) } else { @() }
                [object[]]$temporaryLinks = @()
                if ($any) { $temporaryLinks = [object[]]@($any.ExportTemporaryAuthenticationLinks() | ForEach-Object { ConvertTo-AuthProxyTemporaryLinkRecord $_ }) }
                return @{ Status = 'Ready'; Error = ''; SessionCount = @($sessions).Count; Sessions = $sessions; TemporaryLinks = $temporaryLinks }
            }
            'ImportSessions' {
                $any = (@($proxiesByFamily['LetsEncrypt']) + @($proxiesByFamily['Plaintext'])) | Select-Object -First 1
                if ($any) {
                    $sessions = [TlsTerminatingProxy+AuthenticationSessionState[]]@(
                        @($Command.Sessions) | ForEach-Object {
                            $state = New-Object TlsTerminatingProxy+AuthenticationSessionState
                            $state.Token = [string]$_.Token
                            $state.Expires = [long]$_.Expires
                            $state.BoundAddress = [string]$_.BoundAddress
                            $state
                        }
                    )
                    $any.RestoreActiveAuthenticationSessions($sessions)
                    $temporaryLinks = [TlsTerminatingProxy+TemporaryAuthenticationLinkState[]]@(
                        @($Command.TemporaryLinks) | ForEach-Object {
                            $state = New-Object TlsTerminatingProxy+TemporaryAuthenticationLinkState
                            $state.Token = [string]$_.Token
                            $state.Username = [string]$_.Username
                            $state.Expires = [long]$_.Expires
                            $state.SingleUse = [bool]$_.SingleUse
                            $state.BoundAddress = [string]$_.BoundAddress
                            $state.Purpose = [string]$_.Purpose
                            $state.RequireTotp = [bool]$_.RequireTotp
                            $state.TotpSecret = [string]$_.TotpSecret
                            $state
                        }
                    )
                    $any.RestoreTemporaryAuthenticationLinks($temporaryLinks)
                }
                return @{ Status = 'Ready'; Error = ''; SessionCount = @($Command.Sessions).Count; TemporaryLinkCount = @($Command.TemporaryLinks).Count }
            }
            'CreateTemporaryLink' {
                $any = (@($proxiesByFamily['LetsEncrypt']) + @($proxiesByFamily['Plaintext'])) | Select-Object -First 1
                if (-not $any) { return @{ Status = 'Error'; Error = 'no authentication proxy is running' } }
                try {
                    $link = $any.CreateTemporaryAuthenticationLink([string]$Command.Username, [int]$Command.DurationMinutes, [bool]$Command.SingleUse, [string]$Command.BoundAddress)
                    return @{ Status = 'Ready'; Error = ''; Link = (ConvertTo-AuthProxyTemporaryLinkRecord $link) }
                }
                catch { return @{ Status = 'Error'; Error = $_.Exception.Message } }
            }
            'CreateAccountSetupLink' {
                $any = (@($proxiesByFamily['LetsEncrypt']) + @($proxiesByFamily['Plaintext'])) | Select-Object -First 1
                if (-not $any) { return @{ Status = 'Error'; Error = 'no authentication proxy is running' } }
                try {
                    $link = $any.CreateAuthenticationSetupLink([string]$Command.Username, [int]$Command.DurationMinutes, [bool]$Command.RequireTotp, [string]$Command.BoundAddress)
                    return @{ Status = 'Ready'; Error = ''; Link = (ConvertTo-AuthProxyTemporaryLinkRecord $link) }
                }
                catch { return @{ Status = 'Error'; Error = $_.Exception.Message } }
            }
            'ListTemporaryLinks' {
                $any = (@($proxiesByFamily['LetsEncrypt']) + @($proxiesByFamily['Plaintext'])) | Select-Object -First 1
                [object[]]$links = @()
                if ($any) { $links = [object[]]@($any.ExportTemporaryAuthenticationLinks() | ForEach-Object { ConvertTo-AuthProxyTemporaryLinkRecord $_ }) }
                return @{ Status = 'Ready'; Error = ''; TemporaryLinks = $links }
            }
            'RevokeTemporaryLink' {
                $any = (@($proxiesByFamily['LetsEncrypt']) + @($proxiesByFamily['Plaintext'])) | Select-Object -First 1
                if (-not $any) { return @{ Status = 'Error'; Error = 'no authentication proxy is running'; Removed = $false; Username = ''; SessionsRevoked = 0 } }
                $revocation = $any.RevokeTemporaryAuthenticationLinkAndSessions([string]$Command.Token)
                return @{
                    Status = 'Ready'
                    Error = ''
                    Removed = [bool]$revocation.LinkRemoved
                    Username = [string]$revocation.Username
                    SessionsRevoked = [int]$revocation.SessionsRevoked
                }
            }
            'PollLog' {
                $messages = New-Object System.Collections.Generic.List[string]
                $allProxies = @($proxiesByFamily['LetsEncrypt']) + @($proxiesByFamily['Plaintext'])
                foreach ($proxy in $allProxies) {
                    while ($true) {
                        $message = $proxy.PollLogMessage()
                        if (-not $message) { break }
                        $messages.Add("$($proxy.Label): $message")
                    }
                }
                $accountUpdates = New-Object System.Collections.Generic.List[object]
                $any = $allProxies | Select-Object -First 1
                if ($any) {
                    while ($true) {
                        $update = $any.PollAuthenticationAccountUpdate()
                        if (-not $update) { break }
                        foreach ($proxy in $allProxies) {
                            try { $null = $proxy.ApplyAuthenticationAccountUpdate([string]$update.Username, [string]$update.PasswordHash, [string]$update.TotpSecret) } catch {}
                        }
                        $accountUpdates.Add((ConvertTo-AuthProxyAccountUpdateRecord $update))
                    }
                }
                return @{ Status = 'Ready'; Error = ''; Messages = $messages.ToArray(); AccountUpdates = $accountUpdates.ToArray() }
            }
            default {
                return @{ Status = 'Error'; Error = "Unknown auth proxy worker command: $($Command.Type)" }
            }
        }
    }

    $pipeServer = $null
    $pipeReader = $null
    $pipeWriter = $null
    try {
        $pipeServer = New-Object System.IO.Pipes.NamedPipeServerStream(
            $AuthProxyWorkerPipe,
            [System.IO.Pipes.PipeDirection]::InOut,
            1,
            [System.IO.Pipes.PipeTransmissionMode]::Byte,
            [System.IO.Pipes.PipeOptions]::None
        )
        $pipeServer.WaitForConnection()
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $pipeReader = New-Object System.IO.StreamReader($pipeServer, $utf8, $false, 4096, $true)
        $pipeWriter = New-Object System.IO.StreamWriter($pipeServer, $utf8, 4096, $true)
        $pipeWriter.AutoFlush = $true

        while ($true) {
            $line = $pipeReader.ReadLine()
            if ($null -eq $line) { break }
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $command = $line | ConvertFrom-Json
            if ([string]$command.Type -eq 'Shutdown') {
                $pipeWriter.WriteLine((@{ Status = 'Ready'; Error = '' } | ConvertTo-Json -Compress))
                break
            }
            try {
                $result = Invoke-AuthProxyWorkerCommand -Command $command
            }
            catch {
                $result = @{ Status = 'Error'; Error = $_.Exception.Message }
            }
            $pipeWriter.WriteLine(($result | ConvertTo-Json -Compress -Depth 6))
        }
    }
    catch {
        [Console]::Error.WriteLine("Auth proxy worker error: $($_.Exception)")
        exit 70
    }
    finally {
        foreach ($family in @('LetsEncrypt', 'Plaintext')) {
            foreach ($proxy in @($proxiesByFamily[$family])) {
                try { $proxy.Stop() } catch {}
            }
        }
        try { if ($pipeWriter) { $pipeWriter.Dispose() } } catch {}
        try { if ($pipeReader) { $pipeReader.Dispose() } } catch {}
        try { if ($pipeServer) { $pipeServer.Dispose() } } catch {}
    }
    exit 0
}

$script:AppVersion = '3.8.3a'
$script:AppName = "GStreamer Glass v$($script:AppVersion)"
$script:ConfigDirectory = Join-Path $env:APPDATA 'GStreamerBasicWhipStreamer'
$script:ConfigPath = Join-Path $script:ConfigDirectory 'settings.json'
$script:LogDirectory = Join-Path $env:LOCALAPPDATA 'GStreamerBasicWhipStreamer\Logs'
$script:ProcessStatePath = Join-Path $script:ConfigDirectory 'active-gstreamer-process.json'
$script:ProfilesDirectory = Join-Path $script:ConfigDirectory 'Profiles'
$script:ApplyingDirectWebRtcSmoothnessProfile = $false
$script:ApplyingThreadingProfile = $false
$script:ApplyingThreadBudget = $false
$script:LoadingSettings = $false
$script:DefaultAudioOutputDeviceLabel = 'Default output device (loopback)'
$script:DefaultAudioInputDeviceLabel = 'Default input device / microphone'
$script:AudioOutputDeviceMap = @{}
$script:AudioInputDeviceMap = @{}

# Resolve the directory beside the script during development and beside the
# compiled executable when packaged by PS12EXE/PS2EXE.
$script:ApplicationDirectory = $null
try {
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $script:ApplicationDirectory = $PSScriptRoot
    }
}
catch {}

if ([string]::IsNullOrWhiteSpace($script:ApplicationDirectory)) {
    try {
        $script:ApplicationDirectory = [System.AppDomain]::CurrentDomain.BaseDirectory.TrimEnd('\')
    }
    catch {
        $script:ApplicationDirectory = (Get-Location).Path
    }
}

$script:AppIcon = $null
$script:AppIconSource = 'Windows default application icon'

$script:BasePathEnvironment = $env:PATH
$script:GstProcess = $null
$script:GstVideoProcess = $null
$script:GstAudioProcess = $null
$script:MediaMtxProcess = $null
$script:MediaMtxPathInUse = ''
$script:StopRequested = $false
$script:RestartAt = $null
$script:AutomaticRestartPending = $false
$script:PipelineStartInProgress = $false
$script:PendingPipelineStop = $false
$script:StdOutPath = $null
$script:StdErrPath = $null
$script:StdOutPosition = [int64]0
$script:StdErrPosition = [int64]0
$script:StdOutVideoPath = $null
$script:StdErrVideoPath = $null
$script:StdOutVideoPosition = [int64]0
$script:StdErrVideoPosition = [int64]0
$script:StdOutAudioPath = $null
$script:StdErrAudioPath = $null
$script:StdOutAudioPosition = [int64]0
$script:StdErrAudioPosition = [int64]0
$script:MediaMtxStdOutPath = $null
$script:MediaMtxStdErrPath = $null
$script:PsDebugLogPath = $null
$script:MediaMtxStdOutPosition = [int64]0
$script:MediaMtxStdErrPosition = [int64]0
$script:PreviewHwnd = [IntPtr]::Zero
$script:PreviewParkForm = $null
$script:CustomArgsEditorForm = $null
$script:CustomArgsEditorTextBox = $null
$script:CustomArgsEditorEnabledCheckBox = $null
$script:PreviewParked = $false
$script:PipelineHasPreview = $false
# Cache of the last preview geometry/visibility actually pushed to the embedded
# renderer window. Set-PreviewVisibility runs on every 400 ms poll tick; without
# this it re-issues SetWindowPos/ShowWindow on the live d3d11videosink window
# 2.5x/second forever, which can force needless swapchain work and visible hitching.
$script:PreviewAppliedSize = [System.Drawing.Size]::Empty
$script:PreviewAppliedVisible = $null
$script:PreviewOnlyMode = $false
$script:ForceLocalPreviewMode = $false
$script:RecordingPipelineRequested = $false
$script:RecordingPipelineActive = $false
$script:RecordingOnlyMode = $false
$script:RestartRecordingOnlyMode = $false
$script:DynamicScenePreviewActive = $false
$script:DynamicScenePreviewStarting = $false
$script:DynamicScenePreviewStartedAt = $null
$script:DynamicScenePreviewFallbackTriggered = $false
$script:SuppressDynamicScenePreview = $false
$script:ControlledLiveStreamActive = $false
$script:SuppressControlledLiveStream = $false
$script:ForceLiveScenePreviewBranch = $false
$script:ControlledLiveWorkerPipe = $null
$script:ControlledLiveWorkerReader = $null
$script:ControlledLiveWorkerWriter = $null
$script:ControlledScenePreviewSurfaceHwnd = [IntPtr]::Zero
$script:ControlledScenePreviewAppliedSize = [System.Drawing.Size]::Empty
$script:ControlledLivePreviewSurfaceHwnd = [IntPtr]::Zero
$script:ControlledLivePreviewAppliedSize = [System.Drawing.Size]::Empty
$script:SceneDesktopPreviewProcess = $null
$script:SceneWebcamPreviewProcess = $null
$script:SceneDesktopPreviewHwnd = [IntPtr]::Zero
$script:SceneWebcamPreviewHwnd = [IntPtr]::Zero
$script:DashboardLayout = $null
$script:SceneSettingsPane = $null
$script:SceneWorkspaceActive = $false
$script:ResizingSceneWorkspace = $false
$script:SettingsTabs = $null
$script:SettingsTabTransport = $null
$script:SettingsTabVideo = $null
$script:SettingsTabScenes = $null
$script:SettingsTabAudio = $null
$script:SettingsTabPlayer = $null
$script:SettingsTabRecording = $null
$script:SettingsTabNetwork = $null
$script:SettingsTabOptions = $null
$script:SceneEditorCanvasHomeParent = $null
$script:SceneEditorCanvasHomeDock = $null
$script:SceneEditorCanvasHomeMargin = $null
$script:SceneEditorCanvasHomeAnchor = $null
$script:SceneEditorCanvasHomeBorderStyle = $null
$script:SceneEditorCanvasHostedInPreview = $false
$script:ResolvedRecordingPath = ''
$script:CaptureWindowHwnd = [IntPtr]::Zero
$script:CaptureWindowTitle = ''
$script:NextFullscreenProbe = [datetime]::MinValue
$script:WaitingForFullscreen = $false
$script:JobHandle = [IntPtr]::Zero
$script:ExitCleanupStarted = $false
$script:SuppressProtocolChange = $false
$script:TrayHintShown = $false
$script:StartupTrayHidePending = $false
$script:TrayRestoreInProgress = $false
$script:DynamicPreviewUiReady = $false
$script:EnforcingStartMinimizedTrayInvariant = $false
$script:LastProtocol = 'WHIP'
$script:ProtocolDestinations = [ordered]@{
    WHIP = 'http://10.0.0.25:8889/live/whip'
    SRT  = 'srt://10.0.0.25:8890?mode=caller&streamid=publish:live'
    RTMP = 'rtmp://10.0.0.25/live'
    RTSP = 'rtsp://10.0.0.25:8554/live'
    'GST WebRTC' = 'http://0.0.0.0:8889/'
}

# Direct GStreamer WebRTC defaults:
#   8889 = HTTP viewer, matching MediaMTX WebRTC HTTP delivery.
#   8189 = TCP/WebSocket signalling for this gst-launch/webrtcsink mode.
# Note: in MediaMTX 8189 is UDP media/ICE. GStreamer webrtcsink's exposed
# signalling-server-port is TCP/WebSocket signalling; the actual WebRTC media
# still negotiates separately through ICE/UDP. Pinning media itself to UDP 8189
# requires a helper using the GStreamer API to set the ICE min/max RTP port on
# each created webrtcbin/ICE agent.
$script:DefaultDirectWebRtcWebAddress = 'http://0.0.0.0:8889/'
$script:DefaultDirectWebRtcWebPath = '/live'
$script:DefaultDirectWebRtcBundledWebMode = 'Auto-detect beside EXE'
$script:DefaultDirectWebRtcBundledWebDirectory = ''
$script:DefaultDirectWebRtcWorkingWebMode = 'Auto: LocalAppData'
$script:DefaultDirectWebRtcWorkingWebDirectory = Join-Path $env:LOCALAPPDATA 'GStreamerGlass\WebRoot\gstwebrtc-api\dist'
$script:DirectWebRtcRuntimeWebDirectory = $script:DefaultDirectWebRtcWorkingWebDirectory
$script:DefaultTimingMode = 'Off / plugin default'
$script:DefaultAudioTransportMode = 'Normal audio'
$script:DefaultAudioClockMode = 'Plugin default / allow WASAPI clock'
$script:DefaultAudioTimingMode = 'Plugin default / WASAPI normal'
$script:DefaultAudioSlaveMethod = 'Auto'
$script:DefaultAudioBufferMs = 20
$script:DefaultAudioLatencyMs = 10
$script:DefaultWasapiLowLatencyOverride = $false
$script:DefaultAudioBufferOverride = $false
$script:DefaultAudioLatencyOverride = $false
$script:DefaultAudioSampleRateOverride = $false
$script:DefaultAudioSampleRate = 48000
$script:DefaultAudioMixerMode = $true
$script:DefaultDirectWebRtcSignalingHost = '0.0.0.0'
$script:DefaultDirectWebRtcSignalingPort = 8189
$script:DefaultDirectWebRtcSplitAudioSignalingPort = 8190
$script:DefaultDirectWebRtcSharedSignaling = $false
$script:DefaultDirectWebRtcMediaStreamGrouping = 'Combined A/V MediaStream (default)'
$script:DefaultDirectWebRtcVideoMediaStreamId = 'gstglass-video'
$script:DefaultDirectWebRtcAudioMediaStreamId = 'gstglass-audio'
$script:DefaultDirectWebRtcUnifiedPublisher = $false
$script:DefaultDirectWebRtcBridgeVideoPort = 5004
$script:DefaultDirectWebRtcBridgeAudioPort = 5006
$script:DefaultDirectWebRtcBridgeJitterMs = 0
$script:DefaultDirectWebRtcPublisherQueueMs = 50
$script:DefaultDirectWebRtcAudioBridgePacing = $true
$script:DefaultSplitClockSignalingOverrides = $false
$script:DefaultSplitVideoClockSignaling = 'Off / plugin default'
$script:DefaultSplitAudioClockSignaling = 'Off / plugin default'
$script:DefaultDirectWebRtcControlDataChannel = $false
$script:DefaultDirectWebRtcBundlePolicy = 'Default'
$script:DefaultDirectWebRtcInternalRtpMtu = 0
$script:DefaultDirectWebRtcInternalRepeatHeaders = $false
$script:DefaultUnifiedBridgeKeyframeGuard = $false
$script:DefaultUnifiedBridgeKeyframeIntervalMs = 500
$script:DefaultDirectWebRtcStunServer = 'stun://stun.l.google.com:19302'
$script:DefaultDirectWebRtcTurnEnabled = $false
$script:DefaultDirectWebRtcTurnServer = 'turn://openrelay.metered.ca:80'
$script:DefaultDirectWebRtcMinRtpPort = 0
$script:DefaultDirectWebRtcMaxRtpPort = 0
$script:DefaultDirectWebRtcAdditionalIceHost = ''
$script:DefaultUpnpEnabled = $false
$script:DefaultUpnpMapSignaling = $true
$script:DefaultUpnpMapRtp = $true
$script:DefaultUpnpMapWebServer = $true
$script:DefaultUpnpSignalingExternalPort = 0
$script:DefaultUpnpSplitAudioExternalPort = 0
$script:DefaultUpnpWebServerExternalPort = 0
$script:DefaultDdnsEnabled = $false
$script:DefaultDdnsProvider = 'DuckDNS'
$script:DefaultDdnsHostname = ''
$script:DefaultDdnsToken = ''
$script:DefaultDdnsDynV2UpdateHost = 'dynupdate.no-ip.com'
$script:DefaultDdnsUsername = ''
$script:DefaultDdnsPassword = ''
$script:DefaultDdnsCloudflareZoneId = ''
$script:DefaultDdnsCloudflareProxied = $false
$script:DefaultDdnsCustomUrlTemplate = ''
$script:DefaultDdnsCustomMethod = 'GET'
$script:DefaultLetsEncryptEnabled = $false
$script:DefaultLetsEncryptEmail = ''
$script:DefaultLetsEncryptStaging = $true
$script:DefaultLetsEncryptCertificateDirectory = ''
$script:DefaultLetsEncryptSignalingExternalPort = 0
$script:DefaultLetsEncryptSplitAudioExternalPort = 0
$script:DefaultLetsEncryptWebServerExternalPort = 0
$script:DefaultEmbeddedTlsEnabled = $false
$script:DefaultTlsCertificatePath = ''
$script:DefaultTlsPrivateKeyPath = ''
$script:DefaultTlsAllowInsecurePorts = $false
$script:DefaultViewerAuthenticationEnabled = $false
$script:DefaultViewerAuthenticationSessionHours = 12
$script:DefaultViewerAuthenticationAllowPlaintext = $false
$script:DefaultViewerAuthenticationKeepOnRestart = $false
$script:DefaultViewerAuthenticationKeepOnExit = $false
$script:DefaultViewerAuthenticationStartOnLaunch = $false
$script:DefaultViewerAuthenticationTemporaryLinkProxyDomain = ''
$script:DefaultViewerAuthenticationTemporaryLinkMinutes = 60
$script:DefaultViewerAuthenticationTemporaryLinkSingleUse = $false
$script:DefaultViewerAuthenticationTemporaryLinkRestrictedIp = ''
$script:DefaultViewerAuthenticationSetupLinkRequireTotp = $false
$script:DefaultViewerAuthenticationTrustedProxies = ''
# Named accounts, each @{ Username; PasswordHash }. Only the salted
# PBKDF2-HMAC-SHA256 hash is ever persisted -- see Add-ViewerAuthenticationAccount
# in src/33-LetsEncrypt.ps1.
$script:ViewerAuthenticationAccounts = @()
$script:DefaultDirectWebRtcSmoothnessProfile = 'Sane defaults'
$script:DefaultDirectWebRtcStartBitrateKbps = 0
$script:DefaultDirectWebRtcMinBitrateKbps = 0
$script:DefaultWebRtcRecoveryMode = 'None'
$script:DefaultWebRtcSenderQueueMode = 'Leaky live'
$script:DefaultDirectWebRtcPacingMs = 0
# Buffer depth for the sender/pacing (output) queue, independent of sender
# queue mode. Preserves today's mode-tied literals (2 for Leaky live, 4 for
# Small cushion/Non-leaky experimental) as the starting value for the
# default mode; Apply-DirectWebRtcSmoothnessProfile sets it per preset.
$script:DefaultDirectWebRtcSenderQueueBuffers = 2
$script:DefaultDirectWebRtcPlayerJitterMs = 20
$script:DefaultDirectWebRtcVideoJitterMs = 10
$script:DefaultDirectWebRtcOpusMode = 'Explicit Opus encoder'
$script:DefaultDirectWebRtcOpusFrameMs = '10'
$script:DefaultDirectWebRtcOpusAudioType = 'restricted-lowdelay'
$script:DefaultDirectWebRtcOpusFec = $false
$script:DefaultDirectWebRtcOpusDtx = $false
$script:DefaultJbufWatchdogMode = 'Warn only'
$script:DefaultJbufMaxMs = 30
$script:DefaultPlayerStatsOverlay = $true
$script:DefaultPlayerJbufDebug = $false
$script:DefaultPlayerUrlOverrides = $false
$script:DefaultPlayerVideoSignalingProxyPath = '/live/GstSignal/video'
$script:DefaultPlayerAudioSignalingProxyPath = '/live/GstSignal/voice'
$script:DefaultSendEosOnStop = $false
$script:DefaultLiveEdgeGreenMs = 50
$script:DefaultLiveEdgeYellowMs = 120
$script:DefaultLiveEdgeAverageSec = 5
$script:DefaultPlayerSeparateHtmlMediaElements = $false
$script:DefaultDirectWebRtcAvPipelineMode = 'Single pipeline'
$script:DefaultSplitPlayerSyncMode = 'Off / free-run'
$script:DefaultSplitAudioStallSeconds = 3
$script:DefaultSplitAudioWarmupSeconds = 8
$script:DefaultSplitAvOffsetWarnMs = 140
$script:DefaultSplitAvOffsetBaselineMs = 0
$script:DefaultDirectWebRtcSplitAudioPortOffset = 1
$script:DefaultVideoPipelineClockMode = 'Automatic / element elected'
$script:DefaultVideoTimestampMode = 'Plugin default'
$script:DefaultSplitAudioPipelineClockMode = 'Follow video/master'
$script:DefaultVideoSyncMode = 'Default'
$script:DefaultAudioSyncMode = 'Default'

# Runtime/threading defaults. These are queue/process knobs exposed for diagnosing
# scheduler/backpressure issues where a live stream glitches despite plenty of CPU/GPU headroom.
$script:DefaultThreadingProfile = 'Live strict'
$script:DefaultGstProcessPriority = 'High'
# One control per live queue (video input/output, audio input/output).
# 'Default' is an explicit, visible item -- not just nothing selected --
# meaning omit the leaky= property entirely (GStreamer's own queue
# default). This app is a transparent pipeline constructor: a parameter's
# "don't set this" state should be a real, self-documenting choice, not an
# ambiguous blank control. Only actually reachable via the 'Custom'
# threading profile; every other profile (Apply-ThreadingProfile,
# src/18-ThreadingAndDebug.ps1) explicitly sets all four to a safe value as
# part of its preset.
$script:DefaultVideoInputQueueLeakMode = 'Default'
$script:DefaultVideoOutputQueueLeakMode = 'Default'
$script:DefaultAudioInputQueueLeakMode = 'Default'
$script:DefaultAudioOutputQueueLeakMode = 'Default'
$script:DefaultCaptureQueueBuffers = 2
$script:DefaultAudioQueueBuffers = 4
# Buffer depth for the final audio queue (output side), independent of the
# input-side queue above. Preserves today's hardcoded 2x-of-input value
# (4 * 2) as the default; Apply-ThreadingProfile sets it per preset.
$script:DefaultAudioOutputQueueBuffers = 8
$script:DefaultAudioQueueCapMs = 0
$script:DefaultSceneInputQueueBuffers = 3
$script:DefaultSceneInputQueueCapMs = 0
$script:DefaultBufferLatenessTracer = $false
$script:DefaultThreadBudget = 'Automatic'
$script:DefaultCpuWorkerLimit = 0

# GStreamer diagnostic logging defaults. Verbose output only adds gst-launch -v;
# GST_DEBUG is much deeper and can be extremely noisy, so it is opt-in.
$script:DefaultGstDebugMode = 'Off'
$script:DefaultGstDebugSpec = '*:4'
$script:DefaultGstDebugNoColor = $true
$script:DefaultDiskProcessLogging = $false
$script:DefaultPsDebugEnabled = $false

$script:DirectWebRtcProtocolName = 'GST WebRTC'

# Capture method definitions. The display text is persisted so settings remain
# human-readable, while the Method/Element values drive pipeline generation.
$script:DefaultCaptureMethodName = 'Monitor - D3D11 / DXGI'
$script:CaptureMethodCatalog = [ordered]@{
    'Monitor - D3D11 / DXGI' = [ordered]@{
        Method = 'MonitorD3D11Dxgi'
        Element = 'd3d11screencapturesrc'
        CaptureApi = 'dxgi'
        SourceMemory = 'D3D11'
        RequiresFullscreenWindow = $false
        Description = 'Default Desktop Duplication path. Fastest monitor capture, but it can conflict with Sunshine/Moonlight.'
    }
    'Monitor - D3D11 / WGC' = [ordered]@{
        Method = 'MonitorD3D11Wgc'
        Element = 'd3d11screencapturesrc'
        CaptureApi = 'wgc'
        SourceMemory = 'D3D11'
        RequiresFullscreenWindow = $false
        Description = 'Windows Graphics Capture monitor path. Best first test when Moonlight/Sunshine breaks whole-display capture.'
    }
    'Fullscreen App - D3D11 / WGC' = [ordered]@{
        Method = 'FullscreenAppD3D11Wgc'
        Element = 'd3d11screencapturesrc'
        CaptureApi = 'wgc'
        SourceMemory = 'D3D11'
        RequiresFullscreenWindow = $true
        Description = 'Captures the topmost fullscreen application window using Windows Graphics Capture.'
    }
    'GDI fallback - CPU capture' = [ordered]@{
        Method = 'MonitorGdi'
        Element = 'gdiscreencapsrc'
        CaptureApi = 'gdi'
        SourceMemory = 'System'
        RequiresFullscreenWindow = $false
        Description = 'Emergency compatibility capture through GDI. Slower, but useful when GPU capture backends fight each other.'
    }
}

# Encoder definitions stay deliberately opinionated: every template favors
# minimum buffering, fixed GOP cadence, and no B-frame reordering when the
# underlying encoder exposes such controls.
$script:EncoderCatalog = [ordered]@{
    'NVIDIA NVENC H.264 (D3D11)' = [ordered]@{
        Element = 'nvd3d11h264enc'; Codec = 'H264'; Family = 'NVENC'
        Input = 'D3D11'; Parser = 'h264parse'; Kind = 'Hardware'
    }
    'NVIDIA NVENC H.265 (D3D11)' = [ordered]@{
        Element = 'nvd3d11h265enc'; Codec = 'H265'; Family = 'NVENC'
        Input = 'D3D11'; Parser = 'h265parse'; Kind = 'Hardware'
    }
    'NVIDIA NVENC AV1 (D3D11)' = [ordered]@{
        Element = 'nvd3d11av1enc'; Codec = 'AV1'; Family = 'NVENC'
        Input = 'D3D11'; Parser = 'av1parse'; Kind = 'Hardware'
    }
    'AMD AMF H.264' = [ordered]@{
        Element = 'amfh264enc'; Codec = 'H264'; Family = 'AMF'
        Input = 'D3D11'; Parser = 'h264parse'; Kind = 'Hardware'
    }
    'AMD AMF H.265' = [ordered]@{
        Element = 'amfh265enc'; Codec = 'H265'; Family = 'AMF'
        Input = 'D3D11'; Parser = 'h265parse'; Kind = 'Hardware'
    }
    'AMD AMF AV1' = [ordered]@{
        Element = 'amfav1enc'; Codec = 'AV1'; Family = 'AMF'
        Input = 'D3D11'; Parser = 'av1parse'; Kind = 'Hardware'
    }
    'Intel Quick Sync H.264' = [ordered]@{
        Element = 'qsvh264enc'; Codec = 'H264'; Family = 'QSV'
        Input = 'D3D11'; Parser = 'h264parse'; Kind = 'Hardware'
    }
    'Intel Quick Sync H.265' = [ordered]@{
        Element = 'qsvh265enc'; Codec = 'H265'; Family = 'QSV'
        Input = 'D3D11'; Parser = 'h265parse'; Kind = 'Hardware'
    }
    'Intel Quick Sync AV1' = [ordered]@{
        Element = 'qsvav1enc'; Codec = 'AV1'; Family = 'QSV'
        Input = 'D3D11'; Parser = 'av1parse'; Kind = 'Hardware'
    }
    'Intel Quick Sync VP9' = [ordered]@{
        Element = 'qsvvp9enc'; Codec = 'VP9'; Family = 'QSV'
        Input = 'D3D11'; Parser = 'vp9parse'; Kind = 'Hardware'
    }
    'Microsoft Media Foundation H.264' = [ordered]@{
        Element = 'mfh264enc'; Codec = 'H264'; Family = 'MF'
        Input = 'D3D11'; Parser = 'h264parse'; Kind = 'Hardware'
    }
    'Microsoft Media Foundation H.265' = [ordered]@{
        Element = 'mfh265enc'; Codec = 'H265'; Family = 'MF'
        Input = 'D3D11'; Parser = 'h265parse'; Kind = 'Hardware'
    }
    'x264 Software H.264' = [ordered]@{
        Element = 'x264enc'; Codec = 'H264'; Family = 'X264'
        Input = 'I420'; Parser = 'h264parse'; Kind = 'Software'
    }
    'x265 Software H.265' = [ordered]@{
        Element = 'x265enc'; Codec = 'H265'; Family = 'X265'
        Input = 'I420'; Parser = 'h265parse'; Kind = 'Software'
    }
    'OpenH264 Software H.264' = [ordered]@{
        Element = 'openh264enc'; Codec = 'H264'; Family = 'OPENH264'
        Input = 'I420'; Parser = 'h264parse'; Kind = 'Software'
    }
    'AOM Software AV1' = [ordered]@{
        Element = 'av1enc'; Codec = 'AV1'; Family = 'AOM'
        Input = 'I420'; Parser = 'av1parse'; Kind = 'Software'
    }
    'SVT-AV1 Software AV1' = [ordered]@{
        Element = 'svtav1enc'; Codec = 'AV1'; Family = 'SVTAV1'
        Input = 'I420'; Parser = 'av1parse'; Kind = 'Software'
    }
    'rav1e Software AV1' = [ordered]@{
        Element = 'rav1enc'; Codec = 'AV1'; Family = 'RAV1E'
        Input = 'I420'; Parser = 'av1parse'; Kind = 'Software'
    }
    'libvpx Software VP8' = [ordered]@{
        Element = 'vp8enc'; Codec = 'VP8'; Family = 'VPX'
        Input = 'I420'; Parser = ''; Kind = 'Software'
    }
    'libvpx Software VP9' = [ordered]@{
        Element = 'vp9enc'; Codec = 'VP9'; Family = 'VPX'
        Input = 'I420'; Parser = 'vp9parse'; Kind = 'Software'
    }
}
$script:DefaultEncoderName = 'NVIDIA NVENC H.264 (D3D11)'


$script:RateControlModes = @('cbr', 'vbr', 'constqp')
$script:NvencTuneModes = @('default', 'high-quality', 'low-latency', 'ultra-low-latency', 'lossless')
$script:NvencMultipassModes = @('default', 'disabled', 'two-pass-quarter', 'two-pass')

$script:AudioCodecCatalog = [ordered]@{
    'Opus' = [ordered]@{
        Codec = 'OPUS'; Element = 'opusenc'; Parser = ''; Family = 'OPUS'
        Protocols = @('WHIP', 'GST WebRTC', 'SRT', 'RTSP')
    }
    'AAC (Media Foundation)' = [ordered]@{
        Codec = 'AAC'; Element = 'mfaacenc'; Parser = 'aacparse'; Family = 'AAC_MF'
        Protocols = @('SRT', 'RTMP', 'RTSP')
    }
    'AAC (FDK)' = [ordered]@{
        Codec = 'AAC'; Element = 'fdkaacenc'; Parser = 'aacparse'; Family = 'AAC_FDK'
        Protocols = @('SRT', 'RTMP', 'RTSP')
    }
    'AAC (libav)' = [ordered]@{
        Codec = 'AAC'; Element = 'avenc_aac'; Parser = 'aacparse'; Family = 'AAC_LIBAV'
        Protocols = @('SRT', 'RTMP', 'RTSP')
    }
    'AAC (VisualOn)' = [ordered]@{
        Codec = 'AAC'; Element = 'voaacenc'; Parser = 'aacparse'; Family = 'AAC_VO'
        Protocols = @('SRT', 'RTMP', 'RTSP')
    }
    'MP3 (LAME)' = [ordered]@{
        Codec = 'MP3'; Element = 'lamemp3enc'; Parser = 'mpegaudioparse'; Family = 'MP3'
        Protocols = @('SRT', 'RTMP', 'RTSP')
    }
    'AC-3 (libav)' = [ordered]@{
        Codec = 'AC3'; Element = 'avenc_ac3'; Parser = 'ac3parse'; Family = 'AC3'
        Protocols = @('SRT', 'RTSP')
    }
}

$script:DefaultAudioCodecByProtocol = [ordered]@{
    WHIP = 'Opus'
    'GST WebRTC' = 'Opus'
    SRT  = 'Opus'
    RTMP = 'AAC (Media Foundation)'
    RTSP = 'Opus'
}

$script:ProtocolAudioCodecs = [ordered]@{
    WHIP = 'Opus'
    'GST WebRTC' = 'Opus'
    SRT  = 'Opus'
    RTMP = 'AAC (Media Foundation)'
    RTSP = 'Opus'
}

$script:SuppressAudioCodecChange = $false
