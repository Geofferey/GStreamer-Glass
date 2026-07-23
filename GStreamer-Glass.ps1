#requires -Version 5.1
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
    [string]$ControlledLiveWorkerPipe
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()


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

    public static string SelectFolder(string currentPath, string description)
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
                    dialog.ShowNewFolderButton = true;

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
'@
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

    [DllImport(GLib, CallingConvention = CallingConvention.Cdecl)]
    private static extern void g_error_free(IntPtr error);

    [DllImport(GLib, CallingConvention = CallingConvention.Cdecl)]
    private static extern void g_free(IntPtr memory);

    private static readonly object Gate = new object();
    private static bool initialized;
    private static IntPtr pipeline;
    private static IntPtr scene;
    private static IntPtr sink;
    private static IntPtr bus;
    private static IntPtr desktopPad;
    private static IntPtr webcamPad;

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
            webcamPadName);
    }

    public static void StartLive(
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
            "localpreview",
            desktopPadName,
            webcamPadName);
    }

    private static void StartCore(
        string description,
        long windowHandle,
        int width,
        int height,
        string sinkName,
        string desktopPadName,
        string webcamPadName)
    {
        lock (Gate)
        {
            StopUnsafe();
            if (!initialized)
            {
                gst_init(IntPtr.Zero, IntPtr.Zero);
                initialized = true;
            }

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
        if (pipeline != IntPtr.Zero) gst_object_unref(pipeline);
        webcamPad = desktopPad = bus = sink = scene = pipeline = IntPtr.Zero;
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

        [GstControlledScenePreview]::StartLive(
            [string]$start.Pipeline,
            [int64]$start.WindowHandle,
            [int]$start.Width,
            [int]$start.Height,
            [string]$start.DesktopPad,
            [string]$start.WebcamPad
        )
        $pipeWriter.WriteLine((@{ Status = 'Ready'; Error = '' } | ConvertTo-Json -Compress))

        $readTask = $pipeReader.ReadLineAsync()
        while ($true) {
            if ($readTask.Wait(100)) {
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

$script:AppVersion = '3.7.52f74'
$script:AppName = "GStreamer Glass v$($script:AppVersion)"
$script:ConfigDirectory = Join-Path $env:APPDATA 'GStreamerBasicWhipStreamer'
$script:ConfigPath = Join-Path $script:ConfigDirectory 'settings.json'
$script:LogDirectory = Join-Path $env:LOCALAPPDATA 'GStreamerBasicWhipStreamer\Logs'
$script:ProcessStatePath = Join-Path $script:ConfigDirectory 'active-gstreamer-process.json'
$script:NetworkRecoveryDirectory = Join-Path $env:ProgramData 'GStreamerGlass\Recovery'
$script:NetworkSnapshotPath = Join-Path $script:NetworkRecoveryDirectory 'network-snapshot-latest.json'
$script:NetworkAppliedStatePath = Join-Path $script:NetworkRecoveryDirectory 'applied-state.json'
$script:NetworkRecoveryScriptPath = Join-Path $script:NetworkRecoveryDirectory 'Restore-GStreamerGlassNetwork.ps1'
$script:NetworkRecoveryTaskName = 'GStreamerGlass-NetworkRecovery'
$script:NetworkTuningApplied = $false
$script:ApplyingDirectWebRtcSmoothnessProfile = $false
$script:ApplyingThreadingProfile = $false
$script:ApplyingThreadBudget = $false
$script:LoadingSettings = $false
$script:SynchronizingTimingControls = $false
$script:DefaultAudioOutputDeviceLabel = 'Default output device (loopback)'
$script:DefaultAudioInputDeviceLabel = 'Default input device / microphone'
$script:AudioOutputDeviceMap = @{}
$script:AudioInputDeviceMap = @{}
$script:PendingAudioOutputDeviceLabel = ''
$script:PendingAudioInputDeviceLabel = ''

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
$script:MediaMtxStdOutPosition = [int64]0
$script:MediaMtxStdErrPosition = [int64]0
$script:PreviewHwnd = [IntPtr]::Zero
$script:PreviewParkForm = $null
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
$script:DefaultDirectWebRtcWebDirectory = ''
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
$script:DefaultDirectWebRtcSmoothnessProfile = 'Sane defaults'
$script:DefaultWebRtcRecoveryMode = 'None'
$script:DefaultWebRtcSenderQueueMode = 'Leaky live'
$script:DefaultDirectWebRtcPacingMs = 0
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
$script:DefaultLiveEdgeGreenMs = 50
$script:DefaultLiveEdgeYellowMs = 120
$script:DefaultLiveEdgeAverageSec = 5
$script:DefaultPlayerAvRenderMode = 'Synced single media element' # legacy config compatibility
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
$script:DefaultQueueLeakMode = 'Downstream - drop old'
$script:DefaultCaptureQueueBuffers = 2
$script:DefaultAudioQueueBuffers = 4
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
$script:QueueProfiles = @('Lowest latency', 'Balanced', 'Stable / recording')

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

$script:UnifiedPublisherHostScriptBase64 = @'
W0NtZGxldEJpbmRpbmcoKV0KcGFyYW0oCiAgICBbUGFyYW1ldGVyKE1hbmRhdG9yeSA9ICR0cnVlKV1bc3RyaW5nXSRHc3RCaW4sCiAgICBbUGFyYW1ldGVy
KE1hbmRhdG9yeSA9ICR0cnVlKV1bc3RyaW5nXSRQaXBlbGluZUZpbGUsCiAgICBbVmFsaWRhdGVTZXQoJ0RlZmF1bHQnLCdNYXggYnVuZGxlJyldW3N0cmlu
Z10kQnVuZGxlUG9saWN5ID0gJ0RlZmF1bHQnLAogICAgW1ZhbGlkYXRlUmFuZ2UoMCw2NTUzNSldW2ludF0kSW50ZXJuYWxSdHBNdHUgPSAwLAogICAgW3N3
aXRjaF0kSW50ZXJuYWxSZXBlYXRIZWFkZXJzCikKCiRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAnU3RvcCcKCmlmICgtbm90IChUZXN0LVBhdGggLUxpdGVy
YWxQYXRoICRQaXBlbGluZUZpbGUgLVBhdGhUeXBlIExlYWYpKSB7CiAgICB0aHJvdyAiVW5pZmllZCBwdWJsaXNoZXIgcGlwZWxpbmUgZmlsZSB3YXMgbm90
IGZvdW5kOiAkUGlwZWxpbmVGaWxlIgp9CmlmICgtbm90IChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRHc3RCaW4gLVBhdGhUeXBlIENvbnRhaW5lcikpIHsK
ICAgIHRocm93ICJHU3RyZWFtZXIgYmluIGRpcmVjdG9yeSB3YXMgbm90IGZvdW5kOiAkR3N0QmluIgp9CgojIEN1cnJlbnQgR1N0cmVhbWVyIFdpbmRvd3Mg
cGFja2FnZXMgaGF2ZSB1c2VkIGJvdGggbGliLXByZWZpeGVkIGFuZAojIHVucHJlZml4ZWQgY29yZSBETEwgbmFtZXMuICBUaGUgbmF0aXZlIGhvc3QgaW1w
b3J0cyB0aGUgdHJhZGl0aW9uYWwKIyBsaWItcHJlZml4ZWQgbmFtZXMsIHNvIG1hdGVyaWFsaXplIHByaXZhdGUgYWxpYXNlcyB3aGVuIGEgbmV3ZXIgcnVu
dGltZSBvbmx5CiMgc2hpcHMgZ3N0cmVhbWVyLTEuMC0wLmRsbCAvIGdvYmplY3QtMi4wLTAuZGxsIC8gZ2xpYi0yLjAtMC5kbGwuCiRuYXRpdmVBbGlhc0Rp
ciA9IEpvaW4tUGF0aCAkZW52OkxPQ0FMQVBQREFUQSAnR1N0cmVhbWVyR2xhc3NcSGVscGVyc1xuYXRpdmUtYWxpYXNlcycKaWYgKC1ub3QgKFRlc3QtUGF0
aCAtTGl0ZXJhbFBhdGggJG5hdGl2ZUFsaWFzRGlyKSkgewogICAgJG51bGwgPSBOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICRuYXRpdmVB
bGlhc0RpciAtRm9yY2UKfQoKZnVuY3Rpb24gRW5zdXJlLU5hdGl2ZURsbEFsaWFzIHsKICAgIHBhcmFtKAogICAgICAgIFtQYXJhbWV0ZXIoTWFuZGF0b3J5
ID0gJHRydWUpXVtzdHJpbmddJEltcG9ydE5hbWUsCiAgICAgICAgW1BhcmFtZXRlcihNYW5kYXRvcnkgPSAkdHJ1ZSldW3N0cmluZ1tdXSRDYW5kaWRhdGVz
CiAgICApCgogICAgJGRpcmVjdCA9IEpvaW4tUGF0aCAkR3N0QmluICRJbXBvcnROYW1lCiAgICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkZGlyZWN0
IC1QYXRoVHlwZSBMZWFmKSB7IHJldHVybiB9CgogICAgZm9yZWFjaCAoJGNhbmRpZGF0ZU5hbWUgaW4gJENhbmRpZGF0ZXMpIHsKICAgICAgICAkY2FuZGlk
YXRlID0gSm9pbi1QYXRoICRHc3RCaW4gJGNhbmRpZGF0ZU5hbWUKICAgICAgICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkY2FuZGlkYXRlIC1QYXRo
VHlwZSBMZWFmKSB7CiAgICAgICAgICAgIENvcHktSXRlbSAtTGl0ZXJhbFBhdGggJGNhbmRpZGF0ZSAtRGVzdGluYXRpb24gKEpvaW4tUGF0aCAkbmF0aXZl
QWxpYXNEaXIgJEltcG9ydE5hbWUpIC1Gb3JjZQogICAgICAgICAgICByZXR1cm4KICAgICAgICB9CiAgICB9CgogICAgdGhyb3cgIlJlcXVpcmVkIEdTdHJl
YW1lciBuYXRpdmUgRExMIHdhcyBub3QgZm91bmQuIEltcG9ydD0kSW1wb3J0TmFtZTsgc2VhcmNoZWQ9JCgkQ2FuZGlkYXRlcyAtam9pbiAnLCAnKSIKfQoK
RW5zdXJlLU5hdGl2ZURsbEFsaWFzIC1JbXBvcnROYW1lICdsaWJnc3RyZWFtZXItMS4wLTAuZGxsJyAtQ2FuZGlkYXRlcyBAKCdsaWJnc3RyZWFtZXItMS4w
LTAuZGxsJywnZ3N0cmVhbWVyLTEuMC0wLmRsbCcpCkVuc3VyZS1OYXRpdmVEbGxBbGlhcyAtSW1wb3J0TmFtZSAnbGliZ29iamVjdC0yLjAtMC5kbGwnIC1D
YW5kaWRhdGVzIEAoJ2xpYmdvYmplY3QtMi4wLTAuZGxsJywnZ29iamVjdC0yLjAtMC5kbGwnKQpFbnN1cmUtTmF0aXZlRGxsQWxpYXMgLUltcG9ydE5hbWUg
J2xpYmdsaWItMi4wLTAuZGxsJyAtQ2FuZGlkYXRlcyBAKCdsaWJnbGliLTIuMC0wLmRsbCcsJ2dsaWItMi4wLTAuZGxsJykKCiRlbnY6UEFUSCA9ICIkbmF0
aXZlQWxpYXNEaXI7JEdzdEJpbjskZW52OlBBVEgiCiRwaXBlbGluZURlc2NyaXB0aW9uID0gR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRQaXBlbGluZUZp
bGUgLVJhdwppZiAoW3N0cmluZ106OklzTnVsbE9yV2hpdGVTcGFjZSgkcGlwZWxpbmVEZXNjcmlwdGlvbikpIHsKICAgIHRocm93ICdVbmlmaWVkIHB1Ymxp
c2hlciBwaXBlbGluZSBkZXNjcmlwdGlvbiBpcyBlbXB0eS4nCn0KCiRuYXRpdmVTb3VyY2UgPSBAJwp1c2luZyBTeXN0ZW07CnVzaW5nIFN5c3RlbS5SdW50
aW1lLkludGVyb3BTZXJ2aWNlczsKdXNpbmcgU3lzdGVtLlRleHQ7CnVzaW5nIFN5c3RlbS5UaHJlYWRpbmc7CgpwdWJsaWMgc3RhdGljIGNsYXNzIEdTdHJl
YW1lckdsYXNzVW5pZmllZFB1Ymxpc2hlckhvc3QKewogICAgcHJpdmF0ZSBjb25zdCBpbnQgR1NUX1NUQVRFX05VTEwgPSAxOwogICAgcHJpdmF0ZSBjb25z
dCBpbnQgR1NUX1NUQVRFX1BMQVlJTkcgPSA0OwogICAgcHJpdmF0ZSBjb25zdCBpbnQgR1NUX1NUQVRFX0NIQU5HRV9GQUlMVVJFID0gMDsKICAgIHByaXZh
dGUgY29uc3QgdWludCBHU1RfTUVTU0FHRV9FUlJPUiA9IDF1IDw8IDE7CiAgICBwcml2YXRlIGNvbnN0IGludCBHX0NPTk5FQ1RfQUZURVIgPSAxOwoKICAg
IHByaXZhdGUgc3RhdGljIGJvb2wgX21heEJ1bmRsZTsKICAgIHByaXZhdGUgc3RhdGljIGludCBfaW50ZXJuYWxSdHBNdHU7CiAgICBwcml2YXRlIHN0YXRp
YyBib29sIF9yZXBlYXRIZWFkZXJzOwoKICAgIFtVbm1hbmFnZWRGdW5jdGlvblBvaW50ZXIoQ2FsbGluZ0NvbnZlbnRpb24uQ2RlY2wpXQogICAgcHJpdmF0
ZSBkZWxlZ2F0ZSB2b2lkIFdlYlJ0Y0JpblJlYWR5RGVsZWdhdGUoSW50UHRyIHNlbGYsIEludFB0ciBwZWVySWQsIEludFB0ciB3ZWJydGNiaW4sIEludFB0
ciB1c2VyRGF0YSk7CgogICAgW1VubWFuYWdlZEZ1bmN0aW9uUG9pbnRlcihDYWxsaW5nQ29udmVudGlvbi5DZGVjbCldCiAgICBwcml2YXRlIGRlbGVnYXRl
IGludCBQYXlsb2FkZXJTZXR1cERlbGVnYXRlKEludFB0ciBzZWxmLCBJbnRQdHIgY29uc3VtZXJJZCwgSW50UHRyIHBhZE5hbWUsIEludFB0ciBwYXlsb2Fk
ZXIsIEludFB0ciB1c2VyRGF0YSk7CgogICAgcHJpdmF0ZSBzdGF0aWMgV2ViUnRjQmluUmVhZHlEZWxlZ2F0ZSBfd2VicnRjYmluUmVhZHlEZWxlZ2F0ZSA9
IE9uV2ViUnRjQmluUmVhZHk7CiAgICBwcml2YXRlIHN0YXRpYyBQYXlsb2FkZXJTZXR1cERlbGVnYXRlIF9wYXlsb2FkZXJTZXR1cERlbGVnYXRlID0gT25Q
YXlsb2FkZXJTZXR1cDsKCiAgICBbU3RydWN0TGF5b3V0KExheW91dEtpbmQuU2VxdWVudGlhbCldCiAgICBwcml2YXRlIHN0cnVjdCBHRXJyb3JOYXRpdmUK
ICAgIHsKICAgICAgICBwdWJsaWMgdWludCBkb21haW47CiAgICAgICAgcHVibGljIGludCBjb2RlOwogICAgICAgIHB1YmxpYyBJbnRQdHIgbWVzc2FnZTsK
ICAgIH0KCiAgICBbRGxsSW1wb3J0KCJsaWJnc3RyZWFtZXItMS4wLTAuZGxsIiwgQ2FsbGluZ0NvbnZlbnRpb24gPSBDYWxsaW5nQ29udmVudGlvbi5DZGVj
bCldCiAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gdm9pZCBnc3RfaW5pdChJbnRQdHIgYXJnYywgSW50UHRyIGFyZ3YpOwoKICAgIFtEbGxJbXBvcnQoImxp
YmdzdHJlYW1lci0xLjAtMC5kbGwiLCBDYWxsaW5nQ29udmVudGlvbiA9IENhbGxpbmdDb252ZW50aW9uLkNkZWNsKV0KICAgIHByaXZhdGUgc3RhdGljIGV4
dGVybiBJbnRQdHIgZ3N0X3BhcnNlX2xhdW5jaChbTWFyc2hhbEFzKFVubWFuYWdlZFR5cGUuTFBVVEY4U3RyKV0gc3RyaW5nIHBpcGVsaW5lRGVzY3JpcHRp
b24sIG91dCBJbnRQdHIgZXJyb3IpOwoKICAgIFtEbGxJbXBvcnQoImxpYmdzdHJlYW1lci0xLjAtMC5kbGwiLCBDYWxsaW5nQ29udmVudGlvbiA9IENhbGxp
bmdDb252ZW50aW9uLkNkZWNsKV0KICAgIHByaXZhdGUgc3RhdGljIGV4dGVybiBJbnRQdHIgZ3N0X2Jpbl9nZXRfYnlfbmFtZShJbnRQdHIgYmluLCBbTWFy
c2hhbEFzKFVubWFuYWdlZFR5cGUuTFBVVEY4U3RyKV0gc3RyaW5nIG5hbWUpOwoKICAgIFtEbGxJbXBvcnQoImxpYmdzdHJlYW1lci0xLjAtMC5kbGwiLCBD
YWxsaW5nQ29udmVudGlvbiA9IENhbGxpbmdDb252ZW50aW9uLkNkZWNsKV0KICAgIHByaXZhdGUgc3RhdGljIGV4dGVybiBpbnQgZ3N0X2VsZW1lbnRfc2V0
X3N0YXRlKEludFB0ciBlbGVtZW50LCBpbnQgc3RhdGUpOwoKICAgIFtEbGxJbXBvcnQoImxpYmdzdHJlYW1lci0xLjAtMC5kbGwiLCBDYWxsaW5nQ29udmVu
dGlvbiA9IENhbGxpbmdDb252ZW50aW9uLkNkZWNsKV0KICAgIHByaXZhdGUgc3RhdGljIGV4dGVybiBJbnRQdHIgZ3N0X2VsZW1lbnRfZ2V0X2J1cyhJbnRQ
dHIgZWxlbWVudCk7CgogICAgW0RsbEltcG9ydCgibGliZ3N0cmVhbWVyLTEuMC0wLmRsbCIsIENhbGxpbmdDb252ZW50aW9uID0gQ2FsbGluZ0NvbnZlbnRp
b24uQ2RlY2wpXQogICAgcHJpdmF0ZSBzdGF0aWMgZXh0ZXJuIEludFB0ciBnc3RfYnVzX3RpbWVkX3BvcF9maWx0ZXJlZChJbnRQdHIgYnVzLCB1bG9uZyB0
aW1lb3V0LCB1aW50IHR5cGVzKTsKCiAgICBbRGxsSW1wb3J0KCJsaWJnc3RyZWFtZXItMS4wLTAuZGxsIiwgQ2FsbGluZ0NvbnZlbnRpb24gPSBDYWxsaW5n
Q29udmVudGlvbi5DZGVjbCldCiAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gdm9pZCBnc3RfbWVzc2FnZV9wYXJzZV9lcnJvcihJbnRQdHIgbWVzc2FnZSwg
b3V0IEludFB0ciBlcnJvciwgb3V0IEludFB0ciBkZWJ1Zyk7CgogICAgW0RsbEltcG9ydCgibGliZ3N0cmVhbWVyLTEuMC0wLmRsbCIsIENhbGxpbmdDb252
ZW50aW9uID0gQ2FsbGluZ0NvbnZlbnRpb24uQ2RlY2wpXQogICAgcHJpdmF0ZSBzdGF0aWMgZXh0ZXJuIHZvaWQgZ3N0X21pbmlfb2JqZWN0X3VucmVmKElu
dFB0ciBtaW5pT2JqZWN0KTsKCiAgICBbRGxsSW1wb3J0KCJsaWJnc3RyZWFtZXItMS4wLTAuZGxsIiwgQ2FsbGluZ0NvbnZlbnRpb24gPSBDYWxsaW5nQ29u
dmVudGlvbi5DZGVjbCldCiAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gdm9pZCBnc3Rfb2JqZWN0X3VucmVmKEludFB0ciBvYmopOwoKICAgIFtEbGxJbXBv
cnQoImxpYmdzdHJlYW1lci0xLjAtMC5kbGwiLCBDYWxsaW5nQ29udmVudGlvbiA9IENhbGxpbmdDb252ZW50aW9uLkNkZWNsKV0KICAgIHByaXZhdGUgc3Rh
dGljIGV4dGVybiB2b2lkIGdzdF91dGlsX3NldF9vYmplY3RfYXJnKEludFB0ciBvYmosIFtNYXJzaGFsQXMoVW5tYW5hZ2VkVHlwZS5MUFVURjhTdHIpXSBz
dHJpbmcgbmFtZSwgW01hcnNoYWxBcyhVbm1hbmFnZWRUeXBlLkxQVVRGOFN0cildIHN0cmluZyB2YWx1ZSk7CgogICAgW0RsbEltcG9ydCgibGliZ29iamVj
dC0yLjAtMC5kbGwiLCBDYWxsaW5nQ29udmVudGlvbiA9IENhbGxpbmdDb252ZW50aW9uLkNkZWNsKV0KICAgIHByaXZhdGUgc3RhdGljIGV4dGVybiB1aW50
IGdfc2lnbmFsX2Nvbm5lY3RfZGF0YSgKICAgICAgICBJbnRQdHIgaW5zdGFuY2UsCiAgICAgICAgW01hcnNoYWxBcyhVbm1hbmFnZWRUeXBlLkxQVVRGOFN0
cildIHN0cmluZyBkZXRhaWxlZFNpZ25hbCwKICAgICAgICBJbnRQdHIgY2FsbGJhY2ssCiAgICAgICAgSW50UHRyIGRhdGEsCiAgICAgICAgSW50UHRyIGRl
c3Ryb3lEYXRhLAogICAgICAgIGludCBjb25uZWN0RmxhZ3MpOwoKICAgIFtEbGxJbXBvcnQoImxpYmdsaWItMi4wLTAuZGxsIiwgQ2FsbGluZ0NvbnZlbnRp
b24gPSBDYWxsaW5nQ29udmVudGlvbi5DZGVjbCldCiAgICBwcml2YXRlIHN0YXRpYyBleHRlcm4gdm9pZCBnX2Vycm9yX2ZyZWUoSW50UHRyIGVycm9yKTsK
CiAgICBbRGxsSW1wb3J0KCJsaWJnbGliLTIuMC0wLmRsbCIsIENhbGxpbmdDb252ZW50aW9uID0gQ2FsbGluZ0NvbnZlbnRpb24uQ2RlY2wpXQogICAgcHJp
dmF0ZSBzdGF0aWMgZXh0ZXJuIHZvaWQgZ19mcmVlKEludFB0ciBtZW1vcnkpOwoKICAgIHByaXZhdGUgc3RhdGljIHN0cmluZyBQdHJUb1V0ZjgoSW50UHRy
IHB0cikKICAgIHsKICAgICAgICBpZiAocHRyID09IEludFB0ci5aZXJvKSByZXR1cm4gU3RyaW5nLkVtcHR5OwogICAgICAgIGludCBsZW5ndGggPSAwOwog
ICAgICAgIHdoaWxlIChNYXJzaGFsLlJlYWRCeXRlKHB0ciwgbGVuZ3RoKSAhPSAwKSBsZW5ndGgrKzsKICAgICAgICBpZiAobGVuZ3RoID09IDApIHJldHVy
biBTdHJpbmcuRW1wdHk7CiAgICAgICAgYnl0ZVtdIGJ5dGVzID0gbmV3IGJ5dGVbbGVuZ3RoXTsKICAgICAgICBNYXJzaGFsLkNvcHkocHRyLCBieXRlcywg
MCwgbGVuZ3RoKTsKICAgICAgICByZXR1cm4gRW5jb2RpbmcuVVRGOC5HZXRTdHJpbmcoYnl0ZXMpOwogICAgfQoKICAgIHByaXZhdGUgc3RhdGljIHN0cmlu
ZyBSZWFkR0Vycm9yKEludFB0ciBlcnJvcikKICAgIHsKICAgICAgICBpZiAoZXJyb3IgPT0gSW50UHRyLlplcm8pIHJldHVybiBTdHJpbmcuRW1wdHk7CiAg
ICAgICAgR0Vycm9yTmF0aXZlIG5hdGl2ZSA9IChHRXJyb3JOYXRpdmUpTWFyc2hhbC5QdHJUb1N0cnVjdHVyZShlcnJvciwgdHlwZW9mKEdFcnJvck5hdGl2
ZSkpOwogICAgICAgIHJldHVybiBQdHJUb1V0ZjgobmF0aXZlLm1lc3NhZ2UpOwogICAgfQoKICAgIHByaXZhdGUgc3RhdGljIHZvaWQgT25XZWJSdGNCaW5S
ZWFkeShJbnRQdHIgc2VsZiwgSW50UHRyIHBlZXJJZCwgSW50UHRyIHdlYnJ0Y2JpbiwgSW50UHRyIHVzZXJEYXRhKQogICAgewogICAgICAgIGlmICghX21h
eEJ1bmRsZSB8fCB3ZWJydGNiaW4gPT0gSW50UHRyLlplcm8pIHJldHVybjsKICAgICAgICBzdHJpbmcgcGVlciA9IFB0clRvVXRmOChwZWVySWQpOwogICAg
ICAgIGdzdF91dGlsX3NldF9vYmplY3RfYXJnKHdlYnJ0Y2JpbiwgImJ1bmRsZS1wb2xpY3kiLCAibWF4LWJ1bmRsZSIpOwogICAgICAgIENvbnNvbGUuV3Jp
dGVMaW5lKCJbdW5pZmllZC1ob3N0XSB3ZWJydGNiaW4tcmVhZHkgcGVlcj0iICsgcGVlciArICIgYnVuZGxlLXBvbGljeT1tYXgtYnVuZGxlIik7CiAgICB9
CgogICAgcHJpdmF0ZSBzdGF0aWMgaW50IE9uUGF5bG9hZGVyU2V0dXAoSW50UHRyIHNlbGYsIEludFB0ciBjb25zdW1lcklkLCBJbnRQdHIgcGFkTmFtZSwg
SW50UHRyIHBheWxvYWRlciwgSW50UHRyIHVzZXJEYXRhKQogICAgewogICAgICAgIGlmIChwYXlsb2FkZXIgPT0gSW50UHRyLlplcm8pIHJldHVybiAwOwog
ICAgICAgIHN0cmluZyBjb25zdW1lciA9IFB0clRvVXRmOChjb25zdW1lcklkKTsKICAgICAgICBzdHJpbmcgcGFkID0gUHRyVG9VdGY4KHBhZE5hbWUpOwoK
ICAgICAgICBpZiAoX2ludGVybmFsUnRwTXR1ID4gMCkKICAgICAgICB7CiAgICAgICAgICAgIGdzdF91dGlsX3NldF9vYmplY3RfYXJnKHBheWxvYWRlciwg
Im10dSIsIF9pbnRlcm5hbFJ0cE10dS5Ub1N0cmluZygpKTsKICAgICAgICAgICAgQ29uc29sZS5Xcml0ZUxpbmUoIlt1bmlmaWVkLWhvc3RdIHBheWxvYWRl
ci1zZXR1cCBjb25zdW1lcj0iICsgY29uc3VtZXIgKyAiIHBhZD0iICsgcGFkICsgIiBtdHU9IiArIF9pbnRlcm5hbFJ0cE10dSk7CiAgICAgICAgfQoKICAg
ICAgICBpZiAoX3JlcGVhdEhlYWRlcnMgJiYgcGFkLlN0YXJ0c1dpdGgoInZpZGVvXyIsIFN0cmluZ0NvbXBhcmlzb24uT3JkaW5hbElnbm9yZUNhc2UpKQog
ICAgICAgIHsKICAgICAgICAgICAgZ3N0X3V0aWxfc2V0X29iamVjdF9hcmcocGF5bG9hZGVyLCAiY29uZmlnLWludGVydmFsIiwgIi0xIik7CiAgICAgICAg
ICAgIENvbnNvbGUuV3JpdGVMaW5lKCJbdW5pZmllZC1ob3N0XSBwYXlsb2FkZXItc2V0dXAgY29uc3VtZXI9IiArIGNvbnN1bWVyICsgIiBwYWQ9IiArIHBh
ZCArICIgY29uZmlnLWludGVydmFsPS0xIik7CiAgICAgICAgfQoKICAgICAgICByZXR1cm4gMTsKICAgIH0KCiAgICBwcml2YXRlIHN0YXRpYyB1aW50IENv
bm5lY3RTaWduYWwoSW50UHRyIGluc3RhbmNlLCBzdHJpbmcgc2lnbmFsLCBEZWxlZ2F0ZSBjYWxsYmFjaywgaW50IGZsYWdzKQogICAgewogICAgICAgIElu
dFB0ciBmdW5jdGlvblBvaW50ZXIgPSBNYXJzaGFsLkdldEZ1bmN0aW9uUG9pbnRlckZvckRlbGVnYXRlKGNhbGxiYWNrKTsKICAgICAgICByZXR1cm4gZ19z
aWduYWxfY29ubmVjdF9kYXRhKGluc3RhbmNlLCBzaWduYWwsIGZ1bmN0aW9uUG9pbnRlciwgSW50UHRyLlplcm8sIEludFB0ci5aZXJvLCBmbGFncyk7CiAg
ICB9CgogICAgcHVibGljIHN0YXRpYyBpbnQgUnVuKHN0cmluZyBwaXBlbGluZURlc2NyaXB0aW9uLCBib29sIG1heEJ1bmRsZSwgaW50IGludGVybmFsUnRw
TXR1LCBib29sIHJlcGVhdEhlYWRlcnMpCiAgICB7CiAgICAgICAgX21heEJ1bmRsZSA9IG1heEJ1bmRsZTsKICAgICAgICBfaW50ZXJuYWxSdHBNdHUgPSBp
bnRlcm5hbFJ0cE10dTsKICAgICAgICBfcmVwZWF0SGVhZGVycyA9IHJlcGVhdEhlYWRlcnM7CgogICAgICAgIEludFB0ciBwaXBlbGluZSA9IEludFB0ci5a
ZXJvOwogICAgICAgIEludFB0ciBzaW5rID0gSW50UHRyLlplcm87CiAgICAgICAgSW50UHRyIGJ1cyA9IEludFB0ci5aZXJvOwogICAgICAgIEludFB0ciBw
YXJzZUVycm9yID0gSW50UHRyLlplcm87CgogICAgICAgIHRyeQogICAgICAgIHsKICAgICAgICAgICAgZ3N0X2luaXQoSW50UHRyLlplcm8sIEludFB0ci5a
ZXJvKTsKICAgICAgICAgICAgcGlwZWxpbmUgPSBnc3RfcGFyc2VfbGF1bmNoKHBpcGVsaW5lRGVzY3JpcHRpb24sIG91dCBwYXJzZUVycm9yKTsKICAgICAg
ICAgICAgaWYgKHBpcGVsaW5lID09IEludFB0ci5aZXJvKQogICAgICAgICAgICB7CiAgICAgICAgICAgICAgICBzdHJpbmcgcGFyc2VNZXNzYWdlID0gUmVh
ZEdFcnJvcihwYXJzZUVycm9yKTsKICAgICAgICAgICAgICAgIENvbnNvbGUuRXJyb3IuV3JpdGVMaW5lKCJbdW5pZmllZC1ob3N0XSBnc3RfcGFyc2VfbGF1
bmNoIGZhaWxlZDogIiArIHBhcnNlTWVzc2FnZSk7CiAgICAgICAgICAgICAgICByZXR1cm4gMTsKICAgICAgICAgICAgfQoKICAgICAgICAgICAgc2luayA9
IGdzdF9iaW5fZ2V0X2J5X25hbWUocGlwZWxpbmUsICJvdXQiKTsKICAgICAgICAgICAgaWYgKHNpbmsgPT0gSW50UHRyLlplcm8pCiAgICAgICAgICAgIHsK
ICAgICAgICAgICAgICAgIENvbnNvbGUuRXJyb3IuV3JpdGVMaW5lKCJbdW5pZmllZC1ob3N0XSB3ZWJydGNzaW5rIG5hbWVkICdvdXQnIHdhcyBub3QgZm91
bmQuIik7CiAgICAgICAgICAgICAgICByZXR1cm4gMTsKICAgICAgICAgICAgfQoKICAgICAgICAgICAgaWYgKF9tYXhCdW5kbGUpCiAgICAgICAgICAgIHsK
ICAgICAgICAgICAgICAgIENvbm5lY3RTaWduYWwoc2luaywgIndlYnJ0Y2Jpbi1yZWFkeSIsIF93ZWJydGNiaW5SZWFkeURlbGVnYXRlLCAwKTsKICAgICAg
ICAgICAgfQogICAgICAgICAgICBpZiAoX2ludGVybmFsUnRwTXR1ID4gMCB8fCBfcmVwZWF0SGVhZGVycykKICAgICAgICAgICAgewogICAgICAgICAgICAg
ICAgQ29ubmVjdFNpZ25hbChzaW5rLCAicGF5bG9hZGVyLXNldHVwIiwgX3BheWxvYWRlclNldHVwRGVsZWdhdGUsIEdfQ09OTkVDVF9BRlRFUik7CiAgICAg
ICAgICAgIH0KCiAgICAgICAgICAgIENvbnNvbGUuV3JpdGVMaW5lKCJbdW5pZmllZC1ob3N0XSBwaXBlbGluZSBzdGFydGluZzsgbWF4LWJ1bmRsZT0iICsg
X21heEJ1bmRsZSArICI7IGludGVybmFsLW10dT0iICsgX2ludGVybmFsUnRwTXR1ICsgIjsgcmVwZWF0LWhlYWRlcnM9IiArIF9yZXBlYXRIZWFkZXJzKTsK
ICAgICAgICAgICAgaW50IHN0YXRlUmVzdWx0ID0gZ3N0X2VsZW1lbnRfc2V0X3N0YXRlKHBpcGVsaW5lLCBHU1RfU1RBVEVfUExBWUlORyk7CiAgICAgICAg
ICAgIGlmIChzdGF0ZVJlc3VsdCA9PSBHU1RfU1RBVEVfQ0hBTkdFX0ZBSUxVUkUpCiAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgIENvbnNvbGUuRXJy
b3IuV3JpdGVMaW5lKCJbdW5pZmllZC1ob3N0XSBmYWlsZWQgdG8gc2V0IHBpcGVsaW5lIHRvIFBMQVlJTkcuIik7CiAgICAgICAgICAgICAgICByZXR1cm4g
MTsKICAgICAgICAgICAgfQoKICAgICAgICAgICAgYnVzID0gZ3N0X2VsZW1lbnRfZ2V0X2J1cyhwaXBlbGluZSk7CiAgICAgICAgICAgIHdoaWxlICh0cnVl
KQogICAgICAgICAgICB7CiAgICAgICAgICAgICAgICBJbnRQdHIgbWVzc2FnZSA9IGdzdF9idXNfdGltZWRfcG9wX2ZpbHRlcmVkKGJ1cywgMjUwMDAwMDAw
VUwsIEdTVF9NRVNTQUdFX0VSUk9SKTsKICAgICAgICAgICAgICAgIGlmIChtZXNzYWdlICE9IEludFB0ci5aZXJvKQogICAgICAgICAgICAgICAgewogICAg
ICAgICAgICAgICAgICAgIEludFB0ciBlcnJvciA9IEludFB0ci5aZXJvOwogICAgICAgICAgICAgICAgICAgIEludFB0ciBkZWJ1ZyA9IEludFB0ci5aZXJv
OwogICAgICAgICAgICAgICAgICAgIHRyeQogICAgICAgICAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgICAgICAgICAgZ3N0X21lc3NhZ2VfcGFyc2Vf
ZXJyb3IobWVzc2FnZSwgb3V0IGVycm9yLCBvdXQgZGVidWcpOwogICAgICAgICAgICAgICAgICAgICAgICBDb25zb2xlLkVycm9yLldyaXRlTGluZSgiW3Vu
aWZpZWQtaG9zdF0gR1N0cmVhbWVyIGVycm9yOiAiICsgUmVhZEdFcnJvcihlcnJvcikpOwogICAgICAgICAgICAgICAgICAgICAgICBzdHJpbmcgZGVidWdU
ZXh0ID0gUHRyVG9VdGY4KGRlYnVnKTsKICAgICAgICAgICAgICAgICAgICAgICAgaWYgKCFTdHJpbmcuSXNOdWxsT3JXaGl0ZVNwYWNlKGRlYnVnVGV4dCkp
IENvbnNvbGUuRXJyb3IuV3JpdGVMaW5lKCJbdW5pZmllZC1ob3N0XSAiICsgZGVidWdUZXh0KTsKICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAg
ICAgICAgICAgZmluYWxseQogICAgICAgICAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgICAgICAgICAgaWYgKGVycm9yICE9IEludFB0ci5aZXJvKSBn
X2Vycm9yX2ZyZWUoZXJyb3IpOwogICAgICAgICAgICAgICAgICAgICAgICBpZiAoZGVidWcgIT0gSW50UHRyLlplcm8pIGdfZnJlZShkZWJ1Zyk7CiAgICAg
ICAgICAgICAgICAgICAgICAgIGdzdF9taW5pX29iamVjdF91bnJlZihtZXNzYWdlKTsKICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAg
ICAgcmV0dXJuIDE7CiAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICBUaHJlYWQuU2xlZXAoMTApOwogICAgICAgICAgICB9CiAgICAgICAgfQog
ICAgICAgIGNhdGNoIChFeGNlcHRpb24gZXgpCiAgICAgICAgewogICAgICAgICAgICBDb25zb2xlLkVycm9yLldyaXRlTGluZSgiW3VuaWZpZWQtaG9zdF0g
ZmF0YWw6ICIgKyBleCk7CiAgICAgICAgICAgIHJldHVybiAxOwogICAgICAgIH0KICAgICAgICBmaW5hbGx5CiAgICAgICAgewogICAgICAgICAgICBpZiAo
cGlwZWxpbmUgIT0gSW50UHRyLlplcm8pIGdzdF9lbGVtZW50X3NldF9zdGF0ZShwaXBlbGluZSwgR1NUX1NUQVRFX05VTEwpOwogICAgICAgICAgICBpZiAo
YnVzICE9IEludFB0ci5aZXJvKSBnc3Rfb2JqZWN0X3VucmVmKGJ1cyk7CiAgICAgICAgICAgIGlmIChzaW5rICE9IEludFB0ci5aZXJvKSBnc3Rfb2JqZWN0
X3VucmVmKHNpbmspOwogICAgICAgICAgICBpZiAocGlwZWxpbmUgIT0gSW50UHRyLlplcm8pIGdzdF9vYmplY3RfdW5yZWYocGlwZWxpbmUpOwogICAgICAg
ICAgICBpZiAocGFyc2VFcnJvciAhPSBJbnRQdHIuWmVybykgZ19lcnJvcl9mcmVlKHBhcnNlRXJyb3IpOwogICAgICAgIH0KICAgIH0KfQonQAoKQWRkLVR5
cGUgLVR5cGVEZWZpbml0aW9uICRuYXRpdmVTb3VyY2UgLUxhbmd1YWdlIENTaGFycApleGl0IFtHU3RyZWFtZXJHbGFzc1VuaWZpZWRQdWJsaXNoZXJIb3N0
XTo6UnVuKAogICAgJHBpcGVsaW5lRGVzY3JpcHRpb24sCiAgICAoJEJ1bmRsZVBvbGljeSAtZXEgJ01heCBidW5kbGUnKSwKICAgICRJbnRlcm5hbFJ0cE10
dSwKICAgIFtib29sXSRJbnRlcm5hbFJlcGVhdEhlYWRlcnMKKQo=
'@

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

$script:AppIcon = Get-ApplicationIcon

$form = New-Object System.Windows.Forms.Form
$form.Text = $script:AppName
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(1640, 960)
$form.MinimumSize = New-Object System.Drawing.Size(1280, 760)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.Icon = $script:AppIcon

$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 15000
$toolTip.InitialDelay = 350
$toolTip.ReshowDelay = 100

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

$settingsGroup = New-Object System.Windows.Forms.GroupBox
$settingsGroup.Text = 'Stream Settings'
$settingsGroup.Location = New-Object System.Drawing.Point(10, 10)
$settingsGroup.Size = New-Object System.Drawing.Size(735, 586)
$form.Controls.Add($settingsGroup)

$null = Add-Label $settingsGroup 'GStreamer executable' 15 25 130
$txtGstPath = New-Object System.Windows.Forms.TextBox
$txtGstPath.Location = New-Object System.Drawing.Point(150, 25)
$txtGstPath.Size = New-Object System.Drawing.Size(370, 23)
$txtGstPath.Text = Find-GstLaunch
$settingsGroup.Controls.Add($txtGstPath)
$toolTip.SetToolTip($txtGstPath, 'Fresh installs prefer C:\Program Files\gstreamer\1.0\msvc_x86_64\bin\gst-launch-1.0.exe. A valid user-selected binary is preserved and gets its own plugin/scanner/registry environment; Strom is fallback only.')

$btnBrowseGst = New-Object System.Windows.Forms.Button
$btnBrowseGst.Text = 'Browse...'
$btnBrowseGst.Location = New-Object System.Drawing.Point(530, 23)
$btnBrowseGst.Size = New-Object System.Drawing.Size(60, 27)
$settingsGroup.Controls.Add($btnBrowseGst)

$btnDetectGst = New-Object System.Windows.Forms.Button
$btnDetectGst.Text = 'Detect'
$btnDetectGst.Location = New-Object System.Drawing.Point(595, 23)
$btnDetectGst.Size = New-Object System.Drawing.Size(60, 27)
$settingsGroup.Controls.Add($btnDetectGst)
$toolTip.SetToolTip($btnDetectGst, 'Finds Strom bundled GStreamer first, then the official/default installations.')

$btnCheckGst = New-Object System.Windows.Forms.Button
$btnCheckGst.Text = 'Check'
$btnCheckGst.Location = New-Object System.Drawing.Point(660, 23)
$btnCheckGst.Size = New-Object System.Drawing.Size(58, 27)
$settingsGroup.Controls.Add($btnCheckGst)
$toolTip.SetToolTip($btnCheckGst, 'Checks every GStreamer element required by the selected encoder, protocol, preview, and audio configuration.')

$null = Add-Label $settingsGroup 'Protocol' 15 60 70
$cmbProtocol = New-Object System.Windows.Forms.ComboBox
$cmbProtocol.Location = New-Object System.Drawing.Point(85, 60)
$cmbProtocol.Size = New-Object System.Drawing.Size(100, 23)
$cmbProtocol.DropDownStyle = 'DropDownList'
$null = $cmbProtocol.Items.AddRange(@('WHIP', 'GST WebRTC', 'SRT', 'RTMP', 'RTSP'))
$cmbProtocol.SelectedItem = 'WHIP'
$settingsGroup.Controls.Add($cmbProtocol)

$chkTransportEnabled = New-Object System.Windows.Forms.CheckBox
$chkTransportEnabled.Text = 'Enable transport'
$chkTransportEnabled.Location = New-Object System.Drawing.Point(15, 32)
$chkTransportEnabled.Size = New-Object System.Drawing.Size(160, 24)
$chkTransportEnabled.Checked = $true
$settingsGroup.Controls.Add($chkTransportEnabled)
$toolTip.SetToolTip($chkTransportEnabled, 'Enables the network transport sink (WHIP/SRT/RTMP/RTSP). Disable this for local recording/preview only.')

$lblDestination = Add-Label $settingsGroup 'WHIP endpoint' 200 60 100
$txtDestination = New-Object System.Windows.Forms.TextBox
$txtDestination.Location = New-Object System.Drawing.Point(300, 60)
$txtDestination.Size = New-Object System.Drawing.Size(418, 23)
$txtDestination.Text = $script:ProtocolDestinations.WHIP
$settingsGroup.Controls.Add($txtDestination)

$cmbCaptureMethod = New-Object System.Windows.Forms.ComboBox
$cmbCaptureMethod.Location = New-Object System.Drawing.Point(15, 96)
$cmbCaptureMethod.Size = New-Object System.Drawing.Size(245, 23)
$cmbCaptureMethod.DropDownStyle = 'DropDownList'
$null = $cmbCaptureMethod.Items.AddRange(@($script:CaptureMethodCatalog.Keys))
$cmbCaptureMethod.SelectedItem = $script:DefaultCaptureMethodName
$settingsGroup.Controls.Add($cmbCaptureMethod)
$toolTip.SetToolTip($cmbCaptureMethod, 'Choose the GStreamer capture backend. Try Monitor - D3D11 / WGC when Sunshine/Moonlight breaks whole-display DXGI capture.')

# Legacy compatibility flag for older settings and event paths. Hidden now that
# capture is controlled by the Capture Method dropdown.
$chkFullscreenApp = New-Object System.Windows.Forms.CheckBox
$chkFullscreenApp.Text = 'Only capture fullscreen app (WGC)'
$chkFullscreenApp.Location = New-Object System.Drawing.Point(15, 96)
$chkFullscreenApp.Size = New-Object System.Drawing.Size(245, 25)
$chkFullscreenApp.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$chkFullscreenApp.Checked = $false
$settingsGroup.Controls.Add($chkFullscreenApp)
$toolTip.SetToolTip($chkFullscreenApp, 'Legacy compatibility flag. Use the Capture Method dropdown instead.')
$chkFullscreenApp.Visible = $false
$chkFullscreenApp.TabStop = $false

$lblCaptureModeStatus = New-Object System.Windows.Forms.Label
$lblCaptureModeStatus.Text = 'Monitor capture active'
$lblCaptureModeStatus.Location = New-Object System.Drawing.Point(275, 96)
$lblCaptureModeStatus.Size = New-Object System.Drawing.Size(300, 25)
$lblCaptureModeStatus.TextAlign = 'MiddleLeft'
$lblCaptureModeStatus.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($lblCaptureModeStatus)

$chkStartMinimized = New-Object System.Windows.Forms.CheckBox
$chkStartMinimized.Text = 'Start minimized'
$chkStartMinimized.Location = New-Object System.Drawing.Point(600, 96)
$chkStartMinimized.Size = New-Object System.Drawing.Size(125, 25)
$chkStartMinimized.Checked = $false
$settingsGroup.Controls.Add($chkStartMinimized)
$toolTip.SetToolTip($chkStartMinimized, 'Starts the app directly in the notification area. Enabling this requires and automatically enables Minimize to tray.')

$null = Add-Label $settingsGroup 'Monitor' 15 130 60
$numMonitor = New-Object System.Windows.Forms.NumericUpDown
$numMonitor.Location = New-Object System.Drawing.Point(75, 130)
$numMonitor.Size = New-Object System.Drawing.Size(60, 23)
$numMonitor.Minimum = -1
$numMonitor.Maximum = 32
$numMonitor.Value = -1
$settingsGroup.Controls.Add($numMonitor)
$toolTip.SetToolTip($numMonitor, '-1 uses the primary monitor. Other values select a GStreamer monitor index.')

$chkCursor = New-Object System.Windows.Forms.CheckBox
$chkCursor.Text = 'Cursor'
$chkCursor.Location = New-Object System.Drawing.Point(150, 130)
$chkCursor.Size = New-Object System.Drawing.Size(75, 23)
$chkCursor.Checked = $true
$settingsGroup.Controls.Add($chkCursor)

# Legacy compatibility flag for older settings. The live UI now uses the protocol-aware clock signaling selector.
$chkSendAbsoluteTimestamps = New-Object System.Windows.Forms.CheckBox
$chkSendAbsoluteTimestamps.Text = 'Legacy absolute timestamps'
$chkSendAbsoluteTimestamps.Location = New-Object System.Drawing.Point(235, 130)
$chkSendAbsoluteTimestamps.Size = New-Object System.Drawing.Size(220, 23)
$chkSendAbsoluteTimestamps.Checked = $false
$chkSendAbsoluteTimestamps.Visible = $false
$chkSendAbsoluteTimestamps.TabStop = $false
$settingsGroup.Controls.Add($chkSendAbsoluteTimestamps)

$lblTimingMode = Add-Label $settingsGroup 'WHIP clock signaling' 235 130 175
$cmbTimingMode = New-Object System.Windows.Forms.ComboBox
$cmbTimingMode.Location = New-Object System.Drawing.Point(415, 130)
$cmbTimingMode.Size = New-Object System.Drawing.Size(215, 23)
$cmbTimingMode.DropDownStyle = 'DropDownList'
$null = $cmbTimingMode.Items.AddRange([string[]]@(
    'Off / plugin default',
    'On / protocol clock signaling'
))
$cmbTimingMode.SelectedItem = $script:DefaultTimingMode
$settingsGroup.Controls.Add($cmbTimingMode)
$toolTip.SetToolTip($cmbTimingMode, 'One protocol-aware sink setting. WHIP and GST WebRTC emit do-clock-signalling=true when On; RTSP emits ntp-time-source=ntp. It does not alter upstream source, encoder, queue, or pipeline-clock properties.')

$chkSplitClockSignalingOverrides = New-Object System.Windows.Forms.CheckBox
$chkSplitClockSignalingOverrides.Text = 'Separate clock signaling per split pipeline'
$chkSplitClockSignalingOverrides.Location = New-Object System.Drawing.Point(15, 548)
$chkSplitClockSignalingOverrides.Size = New-Object System.Drawing.Size(300, 24)
$chkSplitClockSignalingOverrides.Checked = $script:DefaultSplitClockSignalingOverrides
$settingsGroup.Controls.Add($chkSplitClockSignalingOverrides)
$toolTip.SetToolTip($chkSplitClockSignalingOverrides, 'Physical split GST WebRTC only. Off makes both webrtcsink instances inherit the main WebRTC clock signaling setting. On exposes independent video-sink and audio-sink RFC7273 state.')

$cmbSplitVideoClockSignaling = New-Object System.Windows.Forms.ComboBox
$cmbSplitVideoClockSignaling.Location = New-Object System.Drawing.Point(15, 548)
$cmbSplitVideoClockSignaling.Size = New-Object System.Drawing.Size(215, 23)
$cmbSplitVideoClockSignaling.DropDownStyle = 'DropDownList'
$null = $cmbSplitVideoClockSignaling.Items.AddRange([string[]]@('Off / plugin default','RFC7273 NTP/PTP signaling'))
$cmbSplitVideoClockSignaling.SelectedItem = $script:DefaultSplitVideoClockSignaling
$settingsGroup.Controls.Add($cmbSplitVideoClockSignaling)
$toolTip.SetToolTip($cmbSplitVideoClockSignaling, 'Physical split mode video webrtcsink only. On emits do-clock-signalling=true on the video pipeline sink.')

$cmbSplitAudioClockSignaling = New-Object System.Windows.Forms.ComboBox
$cmbSplitAudioClockSignaling.Location = New-Object System.Drawing.Point(15, 548)
$cmbSplitAudioClockSignaling.Size = New-Object System.Drawing.Size(215, 23)
$cmbSplitAudioClockSignaling.DropDownStyle = 'DropDownList'
$null = $cmbSplitAudioClockSignaling.Items.AddRange([string[]]@('Off / plugin default','RFC7273 NTP/PTP signaling'))
$cmbSplitAudioClockSignaling.SelectedItem = $script:DefaultSplitAudioClockSignaling
$settingsGroup.Controls.Add($cmbSplitAudioClockSignaling)
$toolTip.SetToolTip($cmbSplitAudioClockSignaling, 'Physical split mode audio webrtcsink only. On emits do-clock-signalling=true on the audio pipeline sink.')

$lblTimestampStatus = New-Object System.Windows.Forms.Label
$lblTimestampStatus.Text = 'Timing: receiver/server timestamps'
$lblTimestampStatus.Location = New-Object System.Drawing.Point(580, 130)
$lblTimestampStatus.Size = New-Object System.Drawing.Size(215, 23)
$lblTimestampStatus.TextAlign = 'MiddleLeft'
$lblTimestampStatus.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($lblTimestampStatus)

$lblDirectWebRtcStatus = New-Object System.Windows.Forms.Label
$lblDirectWebRtcStatus.Text = 'Direct WebRTC disabled'
$lblDirectWebRtcStatus.Location = New-Object System.Drawing.Point(15, 548)
$lblDirectWebRtcStatus.Size = New-Object System.Drawing.Size(535, 23)
$lblDirectWebRtcStatus.TextAlign = 'MiddleLeft'
$lblDirectWebRtcStatus.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($lblDirectWebRtcStatus)

$txtDirectWebRtcSignalingHost = New-Object System.Windows.Forms.TextBox
$txtDirectWebRtcSignalingHost.Location = New-Object System.Drawing.Point(15, 548)
$txtDirectWebRtcSignalingHost.Size = New-Object System.Drawing.Size(155, 23)
$txtDirectWebRtcSignalingHost.Text = $script:DefaultDirectWebRtcSignalingHost
$settingsGroup.Controls.Add($txtDirectWebRtcSignalingHost)
$toolTip.SetToolTip($txtDirectWebRtcSignalingHost, 'Address used by GStreamer webrtcsink for its built-in signalling server. 0.0.0.0 listens on all local interfaces.')

$numDirectWebRtcSignalingPort = New-Object System.Windows.Forms.NumericUpDown
$numDirectWebRtcSignalingPort.Location = New-Object System.Drawing.Point(15, 548)
$numDirectWebRtcSignalingPort.Size = New-Object System.Drawing.Size(85, 23)
$numDirectWebRtcSignalingPort.Minimum = 1
$numDirectWebRtcSignalingPort.Maximum = 65535
$numDirectWebRtcSignalingPort.Value = $script:DefaultDirectWebRtcSignalingPort
$settingsGroup.Controls.Add($numDirectWebRtcSignalingPort)
$toolTip.SetToolTip($numDirectWebRtcSignalingPort, 'TCP/WebSocket signalling port for webrtcsink. TCP/WebSocket signalling port. Default 8189 for proxy compatibility; media still negotiates separately through WebRTC ICE/UDP.')

$numDirectWebRtcSplitAudioSignalingPort = New-Object System.Windows.Forms.NumericUpDown
$numDirectWebRtcSplitAudioSignalingPort.Location = New-Object System.Drawing.Point(15, 548)
$numDirectWebRtcSplitAudioSignalingPort.Size = New-Object System.Drawing.Size(85, 23)
$numDirectWebRtcSplitAudioSignalingPort.Minimum = 1
$numDirectWebRtcSplitAudioSignalingPort.Maximum = 65535
$numDirectWebRtcSplitAudioSignalingPort.Value = $script:DefaultDirectWebRtcSplitAudioSignalingPort
$settingsGroup.Controls.Add($numDirectWebRtcSplitAudioSignalingPort)
$toolTip.SetToolTip($numDirectWebRtcSplitAudioSignalingPort, 'TCP/WebSocket signalling port for the separate split-audio producer when shared signalling is off. Default 8190.')

$chkDirectWebRtcSharedSignaling = New-Object System.Windows.Forms.CheckBox
$chkDirectWebRtcSharedSignaling.Text = 'Shared signalling for split A/V'
$chkDirectWebRtcSharedSignaling.Location = New-Object System.Drawing.Point(15, 548)
$chkDirectWebRtcSharedSignaling.Size = New-Object System.Drawing.Size(245, 24)
$chkDirectWebRtcSharedSignaling.Checked = $script:DefaultDirectWebRtcSharedSignaling
$settingsGroup.Controls.Add($chkDirectWebRtcSharedSignaling)
$toolTip.SetToolTip($chkDirectWebRtcSharedSignaling, 'Split mode only. Video owns the configured signalling server and the audio producer joins that same server through signaller::uri. Off preserves the existing separate-port method.')

$cmbDirectWebRtcMediaStreamGrouping = New-Object System.Windows.Forms.ComboBox
$cmbDirectWebRtcMediaStreamGrouping.Location = New-Object System.Drawing.Point(15, 548)
$cmbDirectWebRtcMediaStreamGrouping.Size = New-Object System.Drawing.Size(315, 23)
$cmbDirectWebRtcMediaStreamGrouping.DropDownStyle = 'DropDownList'
$null = $cmbDirectWebRtcMediaStreamGrouping.Items.AddRange([string[]]@('Combined A/V MediaStream (default)','Separate audio/video MediaStreams (experimental)'))
$cmbDirectWebRtcMediaStreamGrouping.SelectedItem = $script:DefaultDirectWebRtcMediaStreamGrouping
$settingsGroup.Controls.Add($cmbDirectWebRtcMediaStreamGrouping)
$toolTip.SetToolTip($cmbDirectWebRtcMediaStreamGrouping, 'Direct GST WebRTC single-pipeline experiment. Separate mode rewrites the incoming SDP in the bundled player so Chromium receives video and audio under different MediaStream IDs. It preserves one producer, PeerConnection, ICE session, and gst-launch pipeline. Combined mode changes nothing.')

$txtDirectWebRtcVideoMediaStreamId = New-Object System.Windows.Forms.TextBox
$txtDirectWebRtcVideoMediaStreamId.Location = New-Object System.Drawing.Point(15, 548)
$txtDirectWebRtcVideoMediaStreamId.Size = New-Object System.Drawing.Size(180, 23)
$txtDirectWebRtcVideoMediaStreamId.Text = $script:DefaultDirectWebRtcVideoMediaStreamId
$settingsGroup.Controls.Add($txtDirectWebRtcVideoMediaStreamId)
$toolTip.SetToolTip($txtDirectWebRtcVideoMediaStreamId, 'MediaStream ID written into video a=msid SDP attributes when separate MediaStreams is enabled. The existing MediaStreamTrack ID is preserved.')

$txtDirectWebRtcAudioMediaStreamId = New-Object System.Windows.Forms.TextBox
$txtDirectWebRtcAudioMediaStreamId.Location = New-Object System.Drawing.Point(15, 548)
$txtDirectWebRtcAudioMediaStreamId.Size = New-Object System.Drawing.Size(180, 23)
$txtDirectWebRtcAudioMediaStreamId.Text = $script:DefaultDirectWebRtcAudioMediaStreamId
$settingsGroup.Controls.Add($txtDirectWebRtcAudioMediaStreamId)
$toolTip.SetToolTip($txtDirectWebRtcAudioMediaStreamId, 'MediaStream ID written into audio a=msid SDP attributes when separate MediaStreams is enabled. The existing MediaStreamTrack ID is preserved.')

$chkDirectWebRtcUnifiedPublisher = New-Object System.Windows.Forms.CheckBox
$chkDirectWebRtcUnifiedPublisher.Text = 'Unified A/V producer via RTP bridge (experimental)'
$chkDirectWebRtcUnifiedPublisher.Location = New-Object System.Drawing.Point(15, 548)
$chkDirectWebRtcUnifiedPublisher.Size = New-Object System.Drawing.Size(355, 24)
$chkDirectWebRtcUnifiedPublisher.Checked = $script:DefaultDirectWebRtcUnifiedPublisher
$settingsGroup.Controls.Add($chkDirectWebRtcUnifiedPublisher)
$toolTip.SetToolTip($chkDirectWebRtcUnifiedPublisher, 'Split capture mode only. Launches independent video and audio capture pipelines into localhost RTP, then a third publisher pipeline exposes one WebRTC producer with video_0 and audio_0. Off preserves all existing split methods.')

$numDirectWebRtcBridgeVideoPort = New-Object System.Windows.Forms.NumericUpDown
$numDirectWebRtcBridgeVideoPort.Location = New-Object System.Drawing.Point(15, 548)
$numDirectWebRtcBridgeVideoPort.Size = New-Object System.Drawing.Size(85, 23)
$numDirectWebRtcBridgeVideoPort.Minimum = 1
$numDirectWebRtcBridgeVideoPort.Maximum = 65535
$numDirectWebRtcBridgeVideoPort.Value = $script:DefaultDirectWebRtcBridgeVideoPort
$settingsGroup.Controls.Add($numDirectWebRtcBridgeVideoPort)
$toolTip.SetToolTip($numDirectWebRtcBridgeVideoPort, 'Localhost RTP bridge port carrying encoded video from the split video capture process to the unified WebRTC publisher.')

$numDirectWebRtcBridgeAudioPort = New-Object System.Windows.Forms.NumericUpDown
$numDirectWebRtcBridgeAudioPort.Location = New-Object System.Drawing.Point(15, 548)
$numDirectWebRtcBridgeAudioPort.Size = New-Object System.Drawing.Size(85, 23)
$numDirectWebRtcBridgeAudioPort.Minimum = 1
$numDirectWebRtcBridgeAudioPort.Maximum = 65535
$numDirectWebRtcBridgeAudioPort.Value = $script:DefaultDirectWebRtcBridgeAudioPort
$settingsGroup.Controls.Add($numDirectWebRtcBridgeAudioPort)
$toolTip.SetToolTip($numDirectWebRtcBridgeAudioPort, 'Localhost RTP bridge port carrying Opus audio from the split audio capture process to the unified WebRTC publisher.')

$numDirectWebRtcBridgeJitterMs = New-Object System.Windows.Forms.NumericUpDown
$numDirectWebRtcBridgeJitterMs.Location = New-Object System.Drawing.Point(15, 548)
$numDirectWebRtcBridgeJitterMs.Size = New-Object System.Drawing.Size(75, 23)
$numDirectWebRtcBridgeJitterMs.Minimum = 0
$numDirectWebRtcBridgeJitterMs.Maximum = 2000
$numDirectWebRtcBridgeJitterMs.Value = $script:DefaultDirectWebRtcBridgeJitterMs
$settingsGroup.Controls.Add($numDirectWebRtcBridgeJitterMs)
$toolTip.SetToolTip($numDirectWebRtcBridgeJitterMs, 'Optional RTP cadence reconstruction latency in the unified publisher for both localhost RTP legs. 0 disables and omits rtpjitterbuffer. Enabled buffers do not drop on latency.')

$numDirectWebRtcPublisherQueueMs = New-Object System.Windows.Forms.NumericUpDown
$numDirectWebRtcPublisherQueueMs.Location = New-Object System.Drawing.Point(15, 548)
$numDirectWebRtcPublisherQueueMs.Size = New-Object System.Drawing.Size(75, 23)
$numDirectWebRtcPublisherQueueMs.Minimum = 0
$numDirectWebRtcPublisherQueueMs.Maximum = 2000
$numDirectWebRtcPublisherQueueMs.Value = $script:DefaultDirectWebRtcPublisherQueueMs
$settingsGroup.Controls.Add($numDirectWebRtcPublisherQueueMs)
$toolTip.SetToolTip($numDirectWebRtcPublisherQueueMs, 'Non-leaky time queue before each unified-publisher webrtcsink track. Satisfies the sink processing deadline and absorbs cross-process scheduling bursts. 0 disables and omits the queue.')

$chkDirectWebRtcAudioBridgePacing = New-Object System.Windows.Forms.CheckBox
$chkDirectWebRtcAudioBridgePacing.Text = 'Pace localhost audio RTP from timestamps'
$chkDirectWebRtcAudioBridgePacing.Location = New-Object System.Drawing.Point(15, 548)
$chkDirectWebRtcAudioBridgePacing.Size = New-Object System.Drawing.Size(300, 24)
$chkDirectWebRtcAudioBridgePacing.Checked = $script:DefaultDirectWebRtcAudioBridgePacing
$settingsGroup.Controls.Add($chkDirectWebRtcAudioBridgePacing)
$toolTip.SetToolTip($chkDirectWebRtcAudioBridgePacing, 'Unified publisher only. sync=true on the audio bridge udpsink paces Opus RTP using the isolated audio pipeline clock instead of dumping packets immediately when its thread runs.')

$chkDirectWebRtcControlDataChannel = New-Object System.Windows.Forms.CheckBox
$chkDirectWebRtcControlDataChannel.Text = 'Control data channel for upstream events'
$chkDirectWebRtcControlDataChannel.Location = New-Object System.Drawing.Point(15, 548)
$chkDirectWebRtcControlDataChannel.Size = New-Object System.Drawing.Size(310, 24)
$chkDirectWebRtcControlDataChannel.Checked = $script:DefaultDirectWebRtcControlDataChannel
$settingsGroup.Controls.Add($chkDirectWebRtcControlDataChannel)
$toolTip.SetToolTip($chkDirectWebRtcControlDataChannel, 'Unified publisher only. Emits enable-control-data-channel=true so arbitrary upstream events can be received through the WebRTC control channel. The localhost keyframe bridge still needs an explicit event relay.')

$cmbDirectWebRtcBundlePolicy = New-Object System.Windows.Forms.ComboBox
$cmbDirectWebRtcBundlePolicy.Location = New-Object System.Drawing.Point(15, 548)
$cmbDirectWebRtcBundlePolicy.Size = New-Object System.Drawing.Size(145, 23)
$cmbDirectWebRtcBundlePolicy.DropDownStyle = 'DropDownList'
$null = $cmbDirectWebRtcBundlePolicy.Items.AddRange([string[]]@('Default','Max bundle'))
$cmbDirectWebRtcBundlePolicy.SelectedItem = $script:DefaultDirectWebRtcBundlePolicy
$settingsGroup.Controls.Add($cmbDirectWebRtcBundlePolicy)
$toolTip.SetToolTip($cmbDirectWebRtcBundlePolicy, 'Unified publisher only. Max bundle configures both the browser RTCPeerConnection and the dynamically created internal webrtcbin for one bundled transport. Selecting it activates the embedded unified-publisher host.')

$numDirectWebRtcInternalRtpMtu = New-Object System.Windows.Forms.NumericUpDown
$numDirectWebRtcInternalRtpMtu.Location = New-Object System.Drawing.Point(15, 548)
$numDirectWebRtcInternalRtpMtu.Size = New-Object System.Drawing.Size(85, 23)
$numDirectWebRtcInternalRtpMtu.Minimum = 0
$numDirectWebRtcInternalRtpMtu.Maximum = 65535
$numDirectWebRtcInternalRtpMtu.Value = $script:DefaultDirectWebRtcInternalRtpMtu
$settingsGroup.Controls.Add($numDirectWebRtcInternalRtpMtu)
$toolTip.SetToolTip($numDirectWebRtcInternalRtpMtu, 'Unified publisher only. 0 leaves the final WebRTC RTP payloaders at plugin defaults. A nonzero value sets mtu on every dynamically created internal payloader through payloader-setup.')

$chkDirectWebRtcInternalRepeatHeaders = New-Object System.Windows.Forms.CheckBox
$chkDirectWebRtcInternalRepeatHeaders.Text = 'Internal payloader repeat headers'
$chkDirectWebRtcInternalRepeatHeaders.Location = New-Object System.Drawing.Point(15, 548)
$chkDirectWebRtcInternalRepeatHeaders.Size = New-Object System.Drawing.Size(245, 24)
$chkDirectWebRtcInternalRepeatHeaders.Checked = $script:DefaultDirectWebRtcInternalRepeatHeaders
$settingsGroup.Controls.Add($chkDirectWebRtcInternalRepeatHeaders)
$toolTip.SetToolTip($chkDirectWebRtcInternalRepeatHeaders, 'Unified H.264/H.265 publisher only. Sets config-interval=-1 on the dynamically created final WebRTC video payloader so parameter sets repeat with each IDR. Off emits no internal override.')

$txtDirectWebRtcStun = New-Object System.Windows.Forms.TextBox
$txtDirectWebRtcStun.Location = New-Object System.Drawing.Point(15, 548)
$txtDirectWebRtcStun.Size = New-Object System.Drawing.Size(250, 23)
$txtDirectWebRtcStun.Text = $script:DefaultDirectWebRtcStunServer
$settingsGroup.Controls.Add($txtDirectWebRtcStun)
$toolTip.SetToolTip($txtDirectWebRtcStun, 'STUN server for Direct GStreamer WebRTC. Leave blank for no STUN.')

$chkDirectWebRtcTurnEnabled = New-Object System.Windows.Forms.CheckBox
$chkDirectWebRtcTurnEnabled.Text = 'Enable TURN relay'
$chkDirectWebRtcTurnEnabled.Location = New-Object System.Drawing.Point(15, 548)
$chkDirectWebRtcTurnEnabled.Size = New-Object System.Drawing.Size(145, 24)
$chkDirectWebRtcTurnEnabled.Checked = $script:DefaultDirectWebRtcTurnEnabled
$settingsGroup.Controls.Add($chkDirectWebRtcTurnEnabled)
$toolTip.SetToolTip($chkDirectWebRtcTurnEnabled, 'Adds the TURN URI as a one-entry turn-servers array on rswebrtc sinks. TURN is opt-in because relayed media consumes third-party bandwidth and can add latency.')

$txtDirectWebRtcTurn = New-Object System.Windows.Forms.TextBox
$txtDirectWebRtcTurn.Location = New-Object System.Drawing.Point(15, 548)
$txtDirectWebRtcTurn.Size = New-Object System.Drawing.Size(330, 23)
$txtDirectWebRtcTurn.Text = $script:DefaultDirectWebRtcTurnServer
$settingsGroup.Controls.Add($txtDirectWebRtcTurn)
$toolTip.SetToolTip($txtDirectWebRtcTurn, 'TURN URI for Direct GST WebRTC and WHIP, for example turn://username:password@host:3478 or turns://username:password@host:5349. The public default address still requires valid credentials before it can relay media.')

$txtDirectWebRtcWebPath = New-Object System.Windows.Forms.TextBox
$txtDirectWebRtcWebPath.Location = New-Object System.Drawing.Point(15, 548)
$txtDirectWebRtcWebPath.Size = New-Object System.Drawing.Size(120, 23)
$txtDirectWebRtcWebPath.Text = $script:DefaultDirectWebRtcWebPath
$settingsGroup.Controls.Add($txtDirectWebRtcWebPath)
$toolTip.SetToolTip($txtDirectWebRtcWebPath, 'Path where GStreamer should serve the WebRTC viewer. Example: /live makes the viewer URL http://127.0.0.1:8889/live/')

$txtDirectWebRtcWebDirectory = New-Object System.Windows.Forms.TextBox
$txtDirectWebRtcWebDirectory.Location = New-Object System.Drawing.Point(15, 548)
$txtDirectWebRtcWebDirectory.Size = New-Object System.Drawing.Size(260, 23)
$txtDirectWebRtcWebDirectory.Text = $script:DefaultDirectWebRtcWorkingWebDirectory
$settingsGroup.Controls.Add($txtDirectWebRtcWebDirectory)
$toolTip.SetToolTip($txtDirectWebRtcWebDirectory, 'Optional gstwebrtc-api/dist directory for the built-in webrtcsink web UI. If blank, GStreamer Glass searches common install paths. Missing assets usually means the web port answers but returns 404.')

$btnBrowseDirectWebRtcWebDirectory = New-Object System.Windows.Forms.Button
$btnBrowseDirectWebRtcWebDirectory.Text = 'Browse working'
$btnBrowseDirectWebRtcWebDirectory.Location = New-Object System.Drawing.Point(15, 548)
$btnBrowseDirectWebRtcWebDirectory.Size = New-Object System.Drawing.Size(80, 27)
$settingsGroup.Controls.Add($btnBrowseDirectWebRtcWebDirectory)
$toolTip.SetToolTip($btnBrowseDirectWebRtcWebDirectory, 'Select the gstwebrtc-api/dist folder used by webrtcsink run-web-server.')

$btnDetectDirectWebRtcWebDirectory = New-Object System.Windows.Forms.Button
$btnDetectDirectWebRtcWebDirectory.Text = 'Detect working'
$btnDetectDirectWebRtcWebDirectory.Location = New-Object System.Drawing.Point(15, 548)
$btnDetectDirectWebRtcWebDirectory.Size = New-Object System.Drawing.Size(80, 27)
$settingsGroup.Controls.Add($btnDetectDirectWebRtcWebDirectory)
$toolTip.SetToolTip($btnDetectDirectWebRtcWebDirectory, 'Detect/create the writable working web UI folder. This is the folder actually served by webrtcsink.')

$cmbDirectWebRtcBundledWebMode = New-Object System.Windows.Forms.ComboBox
$cmbDirectWebRtcBundledWebMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbDirectWebRtcBundledWebMode.Size = New-Object System.Drawing.Size(180, 23)
$cmbDirectWebRtcBundledWebMode.DropDownStyle = 'DropDownList'
$null = $cmbDirectWebRtcBundledWebMode.Items.AddRange([string[]]@('Auto-detect beside EXE','Manual path'))
$cmbDirectWebRtcBundledWebMode.SelectedItem = $script:DefaultDirectWebRtcBundledWebMode
$settingsGroup.Controls.Add($cmbDirectWebRtcBundledWebMode)
$toolTip.SetToolTip($cmbDirectWebRtcBundledWebMode, 'Bundled static web UI source. Auto finds gstwebrtc-api\dist beside GStreamer Glass.exe / the source script. Manual is for dev or custom installs.')

$txtDirectWebRtcBundledWebDirectory = New-Object System.Windows.Forms.TextBox
$txtDirectWebRtcBundledWebDirectory.Location = New-Object System.Drawing.Point(15, 548)
$txtDirectWebRtcBundledWebDirectory.Size = New-Object System.Drawing.Size(300, 23)
$txtDirectWebRtcBundledWebDirectory.Text = $script:DefaultDirectWebRtcBundledWebDirectory
$settingsGroup.Controls.Add($txtDirectWebRtcBundledWebDirectory)
$toolTip.SetToolTip($txtDirectWebRtcBundledWebDirectory, 'Bundled gstwebrtc-api\dist folder. Usually beside the EXE. Must contain index.html and player.js.')

$btnBrowseDirectWebRtcBundledWebDirectory = New-Object System.Windows.Forms.Button
$btnBrowseDirectWebRtcBundledWebDirectory.Text = 'Browse source'
$btnBrowseDirectWebRtcBundledWebDirectory.Location = New-Object System.Drawing.Point(15, 548)
$btnBrowseDirectWebRtcBundledWebDirectory.Size = New-Object System.Drawing.Size(100, 27)
$settingsGroup.Controls.Add($btnBrowseDirectWebRtcBundledWebDirectory)
$toolTip.SetToolTip($btnBrowseDirectWebRtcBundledWebDirectory, 'Select the bundled/static gstwebrtc-api\dist source folder.')

$btnDetectDirectWebRtcBundledWebDirectory = New-Object System.Windows.Forms.Button
$btnDetectDirectWebRtcBundledWebDirectory.Text = 'Detect source'
$btnDetectDirectWebRtcBundledWebDirectory.Location = New-Object System.Drawing.Point(15, 548)
$btnDetectDirectWebRtcBundledWebDirectory.Size = New-Object System.Drawing.Size(100, 27)
$settingsGroup.Controls.Add($btnDetectDirectWebRtcBundledWebDirectory)
$toolTip.SetToolTip($btnDetectDirectWebRtcBundledWebDirectory, 'Detect the bundled/static web UI source folder beside the app/script.')

$cmbDirectWebRtcWorkingWebMode = New-Object System.Windows.Forms.ComboBox
$cmbDirectWebRtcWorkingWebMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbDirectWebRtcWorkingWebMode.Size = New-Object System.Drawing.Size(160, 23)
$cmbDirectWebRtcWorkingWebMode.DropDownStyle = 'DropDownList'
$null = $cmbDirectWebRtcWorkingWebMode.Items.AddRange([string[]]@('Auto: LocalAppData','Manual path'))
$cmbDirectWebRtcWorkingWebMode.SelectedItem = $script:DefaultDirectWebRtcWorkingWebMode
$settingsGroup.Controls.Add($cmbDirectWebRtcWorkingWebMode)
$toolTip.SetToolTip($cmbDirectWebRtcWorkingWebMode, 'Working/served web UI directory. Auto uses %%LOCALAPPDATA%%\GStreamerGlass so no admin rights are needed.')


$cmbDirectWebRtcCongestion = New-Object System.Windows.Forms.ComboBox
$cmbDirectWebRtcCongestion.Location = New-Object System.Drawing.Point(15, 548)
$cmbDirectWebRtcCongestion.Size = New-Object System.Drawing.Size(110, 23)
$cmbDirectWebRtcCongestion.DropDownStyle = 'DropDownList'
$null = $cmbDirectWebRtcCongestion.Items.AddRange([string[]]@('gcc','homegrown','disabled'))
$cmbDirectWebRtcCongestion.SelectedItem = 'disabled'
$settingsGroup.Controls.Add($cmbDirectWebRtcCongestion)
$toolTip.SetToolTip($cmbDirectWebRtcCongestion, 'WebRTC bitrate adaptation for WHIP/GST WebRTC. Disabled/fixed bitrate is the sane debug default; gcc can create rubber-band behavior while adapting.')

$cmbDirectWebRtcMitigation = New-Object System.Windows.Forms.ComboBox
$cmbDirectWebRtcMitigation.Location = New-Object System.Drawing.Point(15, 548)
$cmbDirectWebRtcMitigation.Size = New-Object System.Drawing.Size(150, 23)
$cmbDirectWebRtcMitigation.DropDownStyle = 'DropDownList'
$null = $cmbDirectWebRtcMitigation.Items.AddRange([string[]]@('none','downscaled','downsampled','downsampled+downscaled'))
$cmbDirectWebRtcMitigation.SelectedItem = 'none'
$settingsGroup.Controls.Add($cmbDirectWebRtcMitigation)
$toolTip.SetToolTip($cmbDirectWebRtcMitigation, 'Allows webrtcsink to lower resolution and/or framerate under congestion. Use none for deterministic low-latency LAN tests.')

$chkDirectWebRtcFec = New-Object System.Windows.Forms.CheckBox
$chkDirectWebRtcFec.Text = 'FEC'
$chkDirectWebRtcFec.Location = New-Object System.Drawing.Point(15, 548)
$chkDirectWebRtcFec.Size = New-Object System.Drawing.Size(70, 24)
$chkDirectWebRtcFec.Checked = $false
$settingsGroup.Controls.Add($chkDirectWebRtcFec)
$toolTip.SetToolTip($chkDirectWebRtcFec, 'Forward error correction. Can help loss, but may add overhead.')

$chkDirectWebRtcRetransmission = New-Object System.Windows.Forms.CheckBox
$chkDirectWebRtcRetransmission.Text = 'Retransmit'
$chkDirectWebRtcRetransmission.Location = New-Object System.Drawing.Point(15, 548)
$chkDirectWebRtcRetransmission.Size = New-Object System.Drawing.Size(110, 24)
$chkDirectWebRtcRetransmission.Checked = $false
$settingsGroup.Controls.Add($chkDirectWebRtcRetransmission)
$toolTip.SetToolTip($chkDirectWebRtcRetransmission, 'Allow WebRTC retransmission requests. Disable only for brutal LAN latency experiments.')

$chkDirectWebRtcFec.Visible = $false
$chkDirectWebRtcRetransmission.Visible = $false

$lblWebRtcRecoveryMode = Add-Label $settingsGroup 'Recovery' 15 548 80

$cmbWebRtcRecoveryMode = New-Object System.Windows.Forms.ComboBox
$cmbWebRtcRecoveryMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbWebRtcRecoveryMode.Size = New-Object System.Drawing.Size(135, 23)
$cmbWebRtcRecoveryMode.DropDownStyle = 'DropDownList'
$null = $cmbWebRtcRecoveryMode.Items.AddRange([string[]]@('None','RTX only','FEC only','FEC + RTX'))
$cmbWebRtcRecoveryMode.SelectedItem = $script:DefaultWebRtcRecoveryMode
$settingsGroup.Controls.Add($cmbWebRtcRecoveryMode)
$toolTip.SetToolTip($cmbWebRtcRecoveryMode, 'WebRTC recovery mode for WHIP and GST WebRTC. None is the cleanest sane default. RTX can help loss but can add bursts; FEC can add overhead and visible stutter on low-latency desktop streams.')

$lblWebRtcSenderQueueMode = Add-Label $settingsGroup 'Encoded sender queue' 15 548 125

$cmbWebRtcSenderQueueMode = New-Object System.Windows.Forms.ComboBox
$cmbWebRtcSenderQueueMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbWebRtcSenderQueueMode.Size = New-Object System.Drawing.Size(165, 23)
$cmbWebRtcSenderQueueMode.DropDownStyle = 'DropDownList'
$null = $cmbWebRtcSenderQueueMode.Items.AddRange([string[]]@('Leaky live','Small cushion','Non-leaky experimental'))
$cmbWebRtcSenderQueueMode.SelectedItem = $script:DefaultWebRtcSenderQueueMode
$settingsGroup.Controls.Add($cmbWebRtcSenderQueueMode)
$toolTip.SetToolTip($cmbWebRtcSenderQueueMode, 'Encoded-video queue behavior for WHIP and GST WebRTC. Leaky live drops late frames instead of rubber-banding. Non-leaky is diagnostic only.')

$lblDirectWebRtcSmoothnessProfile = Add-Label $settingsGroup 'Smooth profile' 15 548 100

$cmbDirectWebRtcSmoothnessProfile = New-Object System.Windows.Forms.ComboBox
$cmbDirectWebRtcSmoothnessProfile.Location = New-Object System.Drawing.Point(15, 548)
$cmbDirectWebRtcSmoothnessProfile.Size = New-Object System.Drawing.Size(150, 23)
$cmbDirectWebRtcSmoothnessProfile.DropDownStyle = 'DropDownList'
$null = $cmbDirectWebRtcSmoothnessProfile.Items.AddRange([string[]]@('Sane defaults','Lowest latency','Balanced smooth','WAN smooth','Adaptive viewer','Custom'))
$cmbDirectWebRtcSmoothnessProfile.SelectedItem = $script:DefaultDirectWebRtcSmoothnessProfile
$settingsGroup.Controls.Add($cmbDirectWebRtcSmoothnessProfile)
$toolTip.SetToolTip($cmbDirectWebRtcSmoothnessProfile, 'Direct GST WebRTC smoothing preset. Balanced smooth adds a tiny sender pacing queue and receiver jitter target. WAN smooth adds more cushion. Adaptive viewer lets the bundled browser player raise/lower jitter target from WebRTC stats.')

$lblDirectWebRtcPacingMs = Add-Label $settingsGroup 'Queue cap ms (0=off)' 15 548 140

$numDirectWebRtcPacingMs = New-Object System.Windows.Forms.NumericUpDown
$numDirectWebRtcPacingMs.Location = New-Object System.Drawing.Point(15, 548)
$numDirectWebRtcPacingMs.Size = New-Object System.Drawing.Size(70, 23)
$numDirectWebRtcPacingMs.Minimum = 0
$numDirectWebRtcPacingMs.Maximum = 500
$numDirectWebRtcPacingMs.Increment = 10
$numDirectWebRtcPacingMs.Value = $script:DefaultDirectWebRtcPacingMs
$settingsGroup.Controls.Add($numDirectWebRtcPacingMs)
$toolTip.SetToolTip($numDirectWebRtcPacingMs, 'Encoded-video sender queue max-size-time for WHIP/GST WebRTC. 0 always emits max-size-time=0 with no hidden fallback. This is not the browser JBUF target; high values can accumulate latency.')

$lblDirectWebRtcPlayerJitterMs = Add-Label $settingsGroup 'Audio JBUF ms' 15 548 130

$numDirectWebRtcPlayerJitterMs = New-Object System.Windows.Forms.NumericUpDown
$numDirectWebRtcPlayerJitterMs.Location = New-Object System.Drawing.Point(15, 548)
$numDirectWebRtcPlayerJitterMs.Size = New-Object System.Drawing.Size(70, 23)
$numDirectWebRtcPlayerJitterMs.Minimum = 0
$numDirectWebRtcPlayerJitterMs.Maximum = 500
$numDirectWebRtcPlayerJitterMs.Increment = 10
$numDirectWebRtcPlayerJitterMs.Value = $script:DefaultDirectWebRtcPlayerJitterMs
$settingsGroup.Controls.Add($numDirectWebRtcPlayerJitterMs)
$toolTip.SetToolTip($numDirectWebRtcPlayerJitterMs, 'Chrome receiver jitterBufferTarget for the bundled GST WebRTC audio receiver, in milliseconds. 0 disables the override.')

$lblDirectWebRtcVideoJitterMs = Add-Label $settingsGroup 'Video JBUF ms' 15 548 130

$numDirectWebRtcVideoJitterMs = New-Object System.Windows.Forms.NumericUpDown
$numDirectWebRtcVideoJitterMs.Location = New-Object System.Drawing.Point(15, 548)
$numDirectWebRtcVideoJitterMs.Size = New-Object System.Drawing.Size(70, 23)
$numDirectWebRtcVideoJitterMs.Minimum = 0
$numDirectWebRtcVideoJitterMs.Maximum = 500
$numDirectWebRtcVideoJitterMs.Increment = 5
$numDirectWebRtcVideoJitterMs.Value = $script:DefaultDirectWebRtcVideoJitterMs
$settingsGroup.Controls.Add($numDirectWebRtcVideoJitterMs)
$toolTip.SetToolTip($numDirectWebRtcVideoJitterMs, 'Chrome receiver jitterBufferTarget for the bundled GST WebRTC video receiver, in milliseconds. 0 disables the override.')

$btnOpenDirectWebRtcViewer = New-Object System.Windows.Forms.Button
$btnOpenDirectWebRtcViewer.Text = 'Open viewer'
$btnOpenDirectWebRtcViewer.Location = New-Object System.Drawing.Point(15, 548)
$btnOpenDirectWebRtcViewer.Size = New-Object System.Drawing.Size(100, 28)
$settingsGroup.Controls.Add($btnOpenDirectWebRtcViewer)
$toolTip.SetToolTip($btnOpenDirectWebRtcViewer, 'Open the Direct GStreamer WebRTC web viewer URL in your default browser.')

$btnCopyDirectWebRtcViewer = New-Object System.Windows.Forms.Button
$btnCopyDirectWebRtcViewer.Text = 'Copy URL'
$btnCopyDirectWebRtcViewer.Location = New-Object System.Drawing.Point(15, 548)
$btnCopyDirectWebRtcViewer.Size = New-Object System.Drawing.Size(90, 28)
$settingsGroup.Controls.Add($btnCopyDirectWebRtcViewer)
$toolTip.SetToolTip($btnCopyDirectWebRtcViewer, 'Copy the Direct GStreamer WebRTC local viewer URL.')

$btnRefreshDirectWebRtcWebUi = New-Object System.Windows.Forms.Button
$btnRefreshDirectWebRtcWebUi.Text = 'Force refresh UI'
$btnRefreshDirectWebRtcWebUi.Location = New-Object System.Drawing.Point(15, 548)
$btnRefreshDirectWebRtcWebUi.Size = New-Object System.Drawing.Size(120, 28)
$settingsGroup.Controls.Add($btnRefreshDirectWebRtcWebUi)
$toolTip.SetToolTip($btnRefreshDirectWebRtcWebUi, 'Force-copy versioned static web player assets from bundled source to the writable working dir, excluding runtime gstglass-config.js, then rewrite config from Player tab values.')

$btnOpenDirectWebRtcServedDir = New-Object System.Windows.Forms.Button
$btnOpenDirectWebRtcServedDir.Text = 'Open served dir'
$btnOpenDirectWebRtcServedDir.Location = New-Object System.Drawing.Point(15, 548)
$btnOpenDirectWebRtcServedDir.Size = New-Object System.Drawing.Size(120, 28)
$settingsGroup.Controls.Add($btnOpenDirectWebRtcServedDir)
$toolTip.SetToolTip($btnOpenDirectWebRtcServedDir, 'Open the writable working/served web UI folder under LocalAppData or your manual path.')

$btnOpenDirectWebRtcBundledDir = New-Object System.Windows.Forms.Button
$btnOpenDirectWebRtcBundledDir.Text = 'Open bundled dir'
$btnOpenDirectWebRtcBundledDir.Location = New-Object System.Drawing.Point(15, 548)
$btnOpenDirectWebRtcBundledDir.Size = New-Object System.Drawing.Size(120, 28)
$settingsGroup.Controls.Add($btnOpenDirectWebRtcBundledDir)
$toolTip.SetToolTip($btnOpenDirectWebRtcBundledDir, 'Open the bundled gstwebrtc-api/dist folder shipped beside this script/app.')

$lblDirectWebRtcWebUiStatus = Add-Label $settingsGroup 'Web UI status: not checked' 15 548 520

$chkPreview = New-Object System.Windows.Forms.CheckBox
$chkPreview.Text = 'Show Preview'
$chkPreview.Location = New-Object System.Drawing.Point(235, 130)
$chkPreview.Size = New-Object System.Drawing.Size(80, 23)
$chkPreview.Checked = $false
$settingsGroup.Controls.Add($chkPreview)
$toolTip.SetToolTip($chkPreview, 'Enables standalone preview while stopped and, unless Hide preview during stream is enabled, includes a local preview branch when the stream starts.')

$chkHidePreviewDuringStream = New-Object System.Windows.Forms.CheckBox
$chkHidePreviewDuringStream.Text = 'Hide preview during stream'
$chkHidePreviewDuringStream.AutoSize = $true
$chkHidePreviewDuringStream.Checked = $false
$settingsGroup.Controls.Add($chkHidePreviewDuringStream)
$toolTip.SetToolTip($chkHidePreviewDuringStream, 'When enabled, Show Preview is used for standalone preview while stopped, but the live transport pipeline omits/hides the local preview branch.')

$chkAutoRestart = New-Object System.Windows.Forms.CheckBox
$chkAutoRestart.Text = 'Auto-restart on exit'
$chkAutoRestart.Location = New-Object System.Drawing.Point(325, 130)
$chkAutoRestart.Size = New-Object System.Drawing.Size(145, 23)
$chkAutoRestart.Checked = $true
$settingsGroup.Controls.Add($chkAutoRestart)

$chkVerbose = New-Object System.Windows.Forms.CheckBox
$chkVerbose.Text = 'Verbose output'
$chkVerbose.Location = New-Object System.Drawing.Point(480, 130)
$chkVerbose.Size = New-Object System.Drawing.Size(120, 23)
$chkVerbose.Checked = $false
$settingsGroup.Controls.Add($chkVerbose)
$toolTip.SetToolTip($chkVerbose, 'Adds gst-launch -v. This is element/caps verbosity, not full GST_DEBUG logging. Use GST debug below for deep logs.')

$chkDiskProcessLogging = New-Object System.Windows.Forms.CheckBox
$chkDiskProcessLogging.Text = 'Write process logs to disk'
$chkDiskProcessLogging.Location = New-Object System.Drawing.Point(480, 158)
$chkDiskProcessLogging.Size = New-Object System.Drawing.Size(190, 23)
$chkDiskProcessLogging.Checked = $script:DefaultDiskProcessLogging
$settingsGroup.Controls.Add($chkDiskProcessLogging)
$toolTip.SetToolTip($chkDiskProcessLogging, 'Off by default. When off, gst-launch/MediaMTX stdout/stderr are not redirected to per-run log files. Verbose output, GST debug, or tracer options still explicitly enable diagnostic process logs for that run.')

$chkMinimizeToTray = New-Object System.Windows.Forms.CheckBox
$chkMinimizeToTray.Text = 'Minimize to tray'
$chkMinimizeToTray.Location = New-Object System.Drawing.Point(600, 130)
$chkMinimizeToTray.Size = New-Object System.Drawing.Size(120, 23)
$chkMinimizeToTray.Checked = $true
$settingsGroup.Controls.Add($chkMinimizeToTray)
$toolTip.SetToolTip($chkMinimizeToTray, 'Hides the main window in the notification area when minimized. Closing the window still exits and terminates GStreamer.')

# Windows/network tuning controls. These are intentionally opt-in because they can touch global or adapter-level OS settings.
$chkNetworkTuningEnabled = New-Object System.Windows.Forms.CheckBox
$chkNetworkTuningEnabled.Text = 'Enable Windows network tuning while active'
$chkNetworkTuningEnabled.Location = New-Object System.Drawing.Point(15, 548)
$chkNetworkTuningEnabled.Size = New-Object System.Drawing.Size(300, 24)
$chkNetworkTuningEnabled.Checked = $false
$settingsGroup.Controls.Add($chkNetworkTuningEnabled)
$toolTip.SetToolTip($chkNetworkTuningEnabled, 'Opt-in. GStreamer Glass snapshots current adapter/global settings before applying OS-level network tuning.')

$cmbNetworkAdapter = New-Object System.Windows.Forms.ComboBox
$cmbNetworkAdapter.Location = New-Object System.Drawing.Point(15, 548)
$cmbNetworkAdapter.Size = New-Object System.Drawing.Size(360, 23)
$cmbNetworkAdapter.DropDownStyle = 'DropDownList'
$settingsGroup.Controls.Add($cmbNetworkAdapter)
$toolTip.SetToolTip($cmbNetworkAdapter, 'Adapter to tune. Refresh picks the first Up adapter if possible.')

$btnRefreshNetworkAdapters = New-Object System.Windows.Forms.Button
$btnRefreshNetworkAdapters.Text = 'Refresh'
$btnRefreshNetworkAdapters.Location = New-Object System.Drawing.Point(15, 548)
$btnRefreshNetworkAdapters.Size = New-Object System.Drawing.Size(80, 28)
$settingsGroup.Controls.Add($btnRefreshNetworkAdapters)

$cmbNetworkProfile = New-Object System.Windows.Forms.ComboBox
$cmbNetworkProfile.Location = New-Object System.Drawing.Point(15, 548)
$cmbNetworkProfile.Size = New-Object System.Drawing.Size(180, 23)
$cmbNetworkProfile.DropDownStyle = 'DropDownList'
$null = $cmbNetworkProfile.Items.AddRange([string[]]@('No changes','Low latency LAN','Stable WAN','Custom'))
$cmbNetworkProfile.SelectedItem = 'No changes'
$settingsGroup.Controls.Add($cmbNetworkProfile)
$toolTip.SetToolTip($cmbNetworkProfile, 'Profile helper. No changes leaves tuning off; Low latency LAN and Stable WAN prefill conservative defaults.')

$chkNetworkDscp = New-Object System.Windows.Forms.CheckBox
$chkNetworkDscp.Text = 'DSCP / QoS mark transport'
$chkNetworkDscp.Location = New-Object System.Drawing.Point(15, 548)
$chkNetworkDscp.Size = New-Object System.Drawing.Size(210, 24)
$chkNetworkDscp.Checked = $false
$settingsGroup.Controls.Add($chkNetworkDscp)
$toolTip.SetToolTip($chkNetworkDscp, 'Creates a Windows QoS policy for gst-launch-1.0.exe. Useful only when your LAN/VPN/router honors DSCP.')

$numNetworkDscp = New-Object System.Windows.Forms.NumericUpDown
$numNetworkDscp.Location = New-Object System.Drawing.Point(15, 548)
$numNetworkDscp.Size = New-Object System.Drawing.Size(70, 23)
$numNetworkDscp.Minimum = 0
$numNetworkDscp.Maximum = 63
$numNetworkDscp.Value = 34
$settingsGroup.Controls.Add($numNetworkDscp)
$toolTip.SetToolTip($numNetworkDscp, 'DSCP value. 34 is AF41/video-ish; 46 is EF/voice-like and more aggressive.')

$cmbNetworkQosProtocol = New-Object System.Windows.Forms.ComboBox
$cmbNetworkQosProtocol.Location = New-Object System.Drawing.Point(15, 548)
$cmbNetworkQosProtocol.Size = New-Object System.Drawing.Size(80, 23)
$cmbNetworkQosProtocol.DropDownStyle = 'DropDownList'
$null = $cmbNetworkQosProtocol.Items.AddRange([string[]]@('UDP','TCP','Any'))
$cmbNetworkQosProtocol.SelectedItem = 'UDP'
$settingsGroup.Controls.Add($cmbNetworkQosProtocol)

$txtNetworkPorts = New-Object System.Windows.Forms.TextBox
$txtNetworkPorts.Location = New-Object System.Drawing.Point(15, 548)
$txtNetworkPorts.Size = New-Object System.Drawing.Size(160, 23)
$txtNetworkPorts.Text = ''
$settingsGroup.Controls.Add($txtNetworkPorts)
$toolTip.SetToolTip($txtNetworkPorts, 'Optional destination port or range for QoS policy, e.g. 8890 or 8889-8890. Leave blank to match all gst-launch traffic for the protocol.')

$cmbNetworkUso = New-Object System.Windows.Forms.ComboBox
$cmbNetworkUso.Location = New-Object System.Drawing.Point(15, 548)
$cmbNetworkUso.Size = New-Object System.Drawing.Size(130, 23)
$cmbNetworkUso.DropDownStyle = 'DropDownList'
$null = $cmbNetworkUso.Items.AddRange([string[]]@('Leave unchanged','Enable','Disable'))
$cmbNetworkUso.SelectedItem = 'Leave unchanged'
$settingsGroup.Controls.Add($cmbNetworkUso)
$toolTip.SetToolTip($cmbNetworkUso, 'Global UDP Segmentation Offload. Leave unchanged unless testing CPU/latency behavior.')

$cmbNetworkUro = New-Object System.Windows.Forms.ComboBox
$cmbNetworkUro.Location = New-Object System.Drawing.Point(15, 548)
$cmbNetworkUro.Size = New-Object System.Drawing.Size(130, 23)
$cmbNetworkUro.DropDownStyle = 'DropDownList'
$null = $cmbNetworkUro.Items.AddRange([string[]]@('Leave unchanged','Enable','Disable'))
$cmbNetworkUro.SelectedItem = 'Leave unchanged'
$settingsGroup.Controls.Add($cmbNetworkUro)
$toolTip.SetToolTip($cmbNetworkUro, 'Global UDP Receive Offload. Disable can be worth testing for receive-side latency; Enable can help throughput.')

$chkNetworkDisablePowerSaving = New-Object System.Windows.Forms.CheckBox
$chkNetworkDisablePowerSaving.Text = 'Disable adapter power saving'
$chkNetworkDisablePowerSaving.Location = New-Object System.Drawing.Point(15, 548)
$chkNetworkDisablePowerSaving.Size = New-Object System.Drawing.Size(210, 24)
$chkNetworkDisablePowerSaving.Checked = $false
$settingsGroup.Controls.Add($chkNetworkDisablePowerSaving)

$cmbNetworkInterruptModeration = New-Object System.Windows.Forms.ComboBox
$cmbNetworkInterruptModeration.Location = New-Object System.Drawing.Point(15, 548)
$cmbNetworkInterruptModeration.Size = New-Object System.Drawing.Size(150, 23)
$cmbNetworkInterruptModeration.DropDownStyle = 'DropDownList'
$null = $cmbNetworkInterruptModeration.Items.AddRange([string[]]@('Leave unchanged','Disable','Enable / Adaptive'))
$cmbNetworkInterruptModeration.SelectedItem = 'Leave unchanged'
$settingsGroup.Controls.Add($cmbNetworkInterruptModeration)
$toolTip.SetToolTip($cmbNetworkInterruptModeration, 'Driver advanced property when present. Disable can reduce latency but increases CPU/interrupt load.')

$chkNetworkDisableEee = New-Object System.Windows.Forms.CheckBox
$chkNetworkDisableEee.Text = 'Disable EEE / Green Ethernet'
$chkNetworkDisableEee.Location = New-Object System.Drawing.Point(15, 548)
$chkNetworkDisableEee.Size = New-Object System.Drawing.Size(220, 24)
$chkNetworkDisableEee.Checked = $false
$settingsGroup.Controls.Add($chkNetworkDisableEee)

$chkNetworkRestoreOnStop = New-Object System.Windows.Forms.CheckBox
$chkNetworkRestoreOnStop.Text = 'Restore tuning when stream stops'
$chkNetworkRestoreOnStop.Location = New-Object System.Drawing.Point(15, 548)
$chkNetworkRestoreOnStop.Size = New-Object System.Drawing.Size(240, 24)
$chkNetworkRestoreOnStop.Checked = $true
$settingsGroup.Controls.Add($chkNetworkRestoreOnStop)

$chkNetworkRestoreOnExit = New-Object System.Windows.Forms.CheckBox
$chkNetworkRestoreOnExit.Text = 'Restore tuning on app exit'
$chkNetworkRestoreOnExit.Location = New-Object System.Drawing.Point(15, 548)
$chkNetworkRestoreOnExit.Size = New-Object System.Drawing.Size(220, 24)
$chkNetworkRestoreOnExit.Checked = $true
$settingsGroup.Controls.Add($chkNetworkRestoreOnExit)

$chkNetworkRecoveryTask = New-Object System.Windows.Forms.CheckBox
$chkNetworkRecoveryTask.Text = 'Create recovery task/script before applying'
$chkNetworkRecoveryTask.Location = New-Object System.Drawing.Point(15, 548)
$chkNetworkRecoveryTask.Size = New-Object System.Drawing.Size(280, 24)
$chkNetworkRecoveryTask.Checked = $true
$settingsGroup.Controls.Add($chkNetworkRecoveryTask)
$toolTip.SetToolTip($chkNetworkRecoveryTask, 'Writes a restore script and attempts to register a logon recovery task. The script remains in ProgramData even if task registration fails.')

$btnNetworkSnapshot = New-Object System.Windows.Forms.Button
$btnNetworkSnapshot.Text = 'Snapshot'
$btnNetworkSnapshot.Location = New-Object System.Drawing.Point(15, 548)
$btnNetworkSnapshot.Size = New-Object System.Drawing.Size(90, 30)
$settingsGroup.Controls.Add($btnNetworkSnapshot)

$btnNetworkApply = New-Object System.Windows.Forms.Button
$btnNetworkApply.Text = 'Apply Now'
$btnNetworkApply.Location = New-Object System.Drawing.Point(15, 548)
$btnNetworkApply.Size = New-Object System.Drawing.Size(90, 30)
$settingsGroup.Controls.Add($btnNetworkApply)

$btnNetworkRestore = New-Object System.Windows.Forms.Button
$btnNetworkRestore.Text = 'Restore Previous'
$btnNetworkRestore.Location = New-Object System.Drawing.Point(15, 548)
$btnNetworkRestore.Size = New-Object System.Drawing.Size(120, 30)
$settingsGroup.Controls.Add($btnNetworkRestore)

$btnOpenNetworkRecovery = New-Object System.Windows.Forms.Button
$btnOpenNetworkRecovery.Text = 'Open Recovery Folder'
$btnOpenNetworkRecovery.Location = New-Object System.Drawing.Point(15, 548)
$btnOpenNetworkRecovery.Size = New-Object System.Drawing.Size(150, 30)
$settingsGroup.Controls.Add($btnOpenNetworkRecovery)

$lblNetworkStatus = New-Object System.Windows.Forms.Label
$lblNetworkStatus.Text = 'Network tuning disabled'
$lblNetworkStatus.Location = New-Object System.Drawing.Point(15, 548)
$lblNetworkStatus.Size = New-Object System.Drawing.Size(520, 40)
$lblNetworkStatus.TextAlign = 'MiddleLeft'
$lblNetworkStatus.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($lblNetworkStatus)

# Per-tab reset buttons. These restore GStreamer Glass app defaults only; they do not overwrite Windows network snapshots.
$btnResetTransport = New-Object System.Windows.Forms.Button
$btnResetTransport.Text = 'Reset Transport Defaults'
$btnResetTransport.Location = New-Object System.Drawing.Point(15, 548)
$btnResetTransport.Size = New-Object System.Drawing.Size(170, 30)
$settingsGroup.Controls.Add($btnResetTransport)

$btnResetWebRtcSane = New-Object System.Windows.Forms.Button
$btnResetWebRtcSane.Text = 'Reset WebRTC Sane Defaults'
$btnResetWebRtcSane.Location = New-Object System.Drawing.Point(15, 548)
$btnResetWebRtcSane.Size = New-Object System.Drawing.Size(190, 30)
$settingsGroup.Controls.Add($btnResetWebRtcSane)

$btnResetVideo = New-Object System.Windows.Forms.Button
$btnResetVideo.Text = 'Reset Video Defaults'
$btnResetVideo.Location = New-Object System.Drawing.Point(15, 548)
$btnResetVideo.Size = New-Object System.Drawing.Size(150, 30)
$settingsGroup.Controls.Add($btnResetVideo)

$btnResetAudio = New-Object System.Windows.Forms.Button
$btnResetAudio.Text = 'Reset Audio Defaults'
$btnResetAudio.Location = New-Object System.Drawing.Point(15, 548)
$btnResetAudio.Size = New-Object System.Drawing.Size(150, 30)
$settingsGroup.Controls.Add($btnResetAudio)

$btnResetRecording = New-Object System.Windows.Forms.Button
$btnResetRecording.Text = 'Reset Recording Defaults'
$btnResetRecording.Location = New-Object System.Drawing.Point(15, 548)
$btnResetRecording.Size = New-Object System.Drawing.Size(170, 30)
$settingsGroup.Controls.Add($btnResetRecording)

$btnResetNetwork = New-Object System.Windows.Forms.Button
$btnResetNetwork.Text = 'Reset Network Tab Defaults'
$btnResetNetwork.Location = New-Object System.Drawing.Point(15, 548)
$btnResetNetwork.Size = New-Object System.Drawing.Size(180, 30)
$settingsGroup.Controls.Add($btnResetNetwork)

$btnResetOptions = New-Object System.Windows.Forms.Button
$btnResetOptions.Text = 'Reset Options Defaults'
$btnResetOptions.Location = New-Object System.Drawing.Point(15, 548)
$btnResetOptions.Size = New-Object System.Drawing.Size(160, 30)
$settingsGroup.Controls.Add($btnResetOptions)

$btnExportLabConfig = New-Object System.Windows.Forms.Button
$btnExportLabConfig.Text = 'Export Lab Config'
$btnExportLabConfig.Location = New-Object System.Drawing.Point(15, 548)
$btnExportLabConfig.Size = New-Object System.Drawing.Size(160, 30)
$settingsGroup.Controls.Add($btnExportLabConfig)
$toolTip.SetToolTip($btnExportLabConfig, 'Export the complete current settings snapshot plus the exact generated gst-launch command to a portable JSON file.')

$lblThreadingProfile = Add-Label $settingsGroup 'Threading profile' 15 548 120

$cmbThreadingProfile = New-Object System.Windows.Forms.ComboBox
$cmbThreadingProfile.Location = New-Object System.Drawing.Point(15, 548)
$cmbThreadingProfile.Size = New-Object System.Drawing.Size(165, 23)
$cmbThreadingProfile.DropDownStyle = 'DropDownList'
$null = $cmbThreadingProfile.Items.AddRange([string[]]@('Live strict','Balanced','Non-blocking brutal','Blocking diagnostic','Custom'))
$cmbThreadingProfile.SelectedItem = $script:DefaultThreadingProfile
$settingsGroup.Controls.Add($cmbThreadingProfile)
$toolTip.SetToolTip($cmbThreadingProfile, 'Runtime queue/threading profile. Live strict keeps queues tiny and leaky. Blocking diagnostic intentionally allows backpressure to prove where stalls start.')

$lblGstProcessPriority = Add-Label $settingsGroup 'GST priority' 15 548 90

$cmbGstProcessPriority = New-Object System.Windows.Forms.ComboBox
$cmbGstProcessPriority.Location = New-Object System.Drawing.Point(15, 548)
$cmbGstProcessPriority.Size = New-Object System.Drawing.Size(120, 23)
$cmbGstProcessPriority.DropDownStyle = 'DropDownList'
$null = $cmbGstProcessPriority.Items.AddRange([string[]]@('Normal','Above normal','High'))
$cmbGstProcessPriority.SelectedItem = $script:DefaultGstProcessPriority
$settingsGroup.Controls.Add($cmbGstProcessPriority)
$toolTip.SetToolTip($cmbGstProcessPriority, 'Windows process priority for gst-launch after start. High can help capture/encode threads get scheduled under game load.')

$lblThreadBudget = Add-Label $settingsGroup 'Thread budget' 15 548 100
$cmbThreadBudget = New-Object System.Windows.Forms.ComboBox
$cmbThreadBudget.DropDownStyle = 'DropDownList'
$null = $cmbThreadBudget.Items.AddRange([string[]]@('Automatic','Lean','Balanced','Isolated','Custom'))
$cmbThreadBudget.SelectedItem = $script:DefaultThreadBudget
$settingsGroup.Controls.Add($cmbThreadBudget)
$toolTip.SetToolTip($cmbThreadBudget, 'Controls optional GStreamer queue thread boundaries and supported CPU worker limits. This cannot cap driver, WASAPI, or WebRTC internal threads.')

$lblCpuWorkerLimit = Add-Label $settingsGroup 'CPU workers' 15 548 90
$numCpuWorkerLimit = New-Object System.Windows.Forms.NumericUpDown
$numCpuWorkerLimit.Minimum = 0
$numCpuWorkerLimit.Maximum = 32
$numCpuWorkerLimit.Value = $script:DefaultCpuWorkerLimit
$settingsGroup.Controls.Add($numCpuWorkerLimit)
$toolTip.SetToolTip($numCpuWorkerLimit, 'Worker cap for supported CPU elements such as compositor, videoconvert, and x264enc. 0 leaves the element on automatic. It does not cap total process threads.')

$chkBudgetCaptureQueue = New-Object System.Windows.Forms.CheckBox
$chkBudgetCaptureQueue.Text = 'Capture -> encoder thread'
$chkBudgetCaptureQueue.AutoSize = $true
$chkBudgetCaptureQueue.Checked = $true
$settingsGroup.Controls.Add($chkBudgetCaptureQueue)

$chkBudgetSenderQueue = New-Object System.Windows.Forms.CheckBox
$chkBudgetSenderQueue.Text = 'Encoder -> sender thread'
$chkBudgetSenderQueue.AutoSize = $true
$chkBudgetSenderQueue.Checked = $true
$settingsGroup.Controls.Add($chkBudgetSenderQueue)

$chkBudgetAudioInputQueue = New-Object System.Windows.Forms.CheckBox
$chkBudgetAudioInputQueue.Text = 'Audio input thread'
$chkBudgetAudioInputQueue.AutoSize = $true
$chkBudgetAudioInputQueue.Checked = $true
$settingsGroup.Controls.Add($chkBudgetAudioInputQueue)

$chkBudgetAudioFinalQueue = New-Object System.Windows.Forms.CheckBox
$chkBudgetAudioFinalQueue.Text = 'Audio sender thread'
$chkBudgetAudioFinalQueue.AutoSize = $true
$chkBudgetAudioFinalQueue.Checked = $true
$settingsGroup.Controls.Add($chkBudgetAudioFinalQueue)

$chkBudgetSceneInputQueues = New-Object System.Windows.Forms.CheckBox
$chkBudgetSceneInputQueues.Text = 'Scene input threads (required)'
$chkBudgetSceneInputQueues.AutoSize = $true
$chkBudgetSceneInputQueues.Checked = $true
$settingsGroup.Controls.Add($chkBudgetSceneInputQueues)

$lblLiveGstThreads = New-Object System.Windows.Forms.Label
$lblLiveGstThreads.Text = 'Live GST threads: stopped'
$lblLiveGstThreads.AutoSize = $true
$settingsGroup.Controls.Add($lblLiveGstThreads)
$toolTip.SetToolTip($lblLiveGstThreads, 'Observed Windows thread count for gst-launch-1.0.exe. Includes GStreamer, plugin, driver, audio, GPU, networking, and housekeeping threads.')

$lblQueueLeakMode = Add-Label $settingsGroup 'Queue leak' 15 548 90

$cmbQueueLeakMode = New-Object System.Windows.Forms.ComboBox
$cmbQueueLeakMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbQueueLeakMode.Size = New-Object System.Drawing.Size(170, 23)
$cmbQueueLeakMode.DropDownStyle = 'DropDownList'
$null = $cmbQueueLeakMode.Items.AddRange([string[]]@('Downstream - drop old','Upstream - drop new','No leak - block'))
$cmbQueueLeakMode.SelectedItem = $script:DefaultQueueLeakMode
$settingsGroup.Controls.Add($cmbQueueLeakMode)
$toolTip.SetToolTip($cmbQueueLeakMode, 'How live queues behave when full. Downstream drops old frames and is usually right for live desktop. No leak blocks upstream and can rubber-band.')

$lblCaptureQueueBuffers = Add-Label $settingsGroup 'Capture q buffers' 15 548 120

$numCaptureQueueBuffers = New-Object System.Windows.Forms.NumericUpDown
$numCaptureQueueBuffers.Location = New-Object System.Drawing.Point(15, 548)
$numCaptureQueueBuffers.Size = New-Object System.Drawing.Size(70, 23)
$numCaptureQueueBuffers.Minimum = 1
$numCaptureQueueBuffers.Maximum = 16
$numCaptureQueueBuffers.Increment = 1
$numCaptureQueueBuffers.Value = $script:DefaultCaptureQueueBuffers
$settingsGroup.Controls.Add($numCaptureQueueBuffers)
$toolTip.SetToolTip($numCaptureQueueBuffers, 'Queue depth immediately before the encoder. Lower = lower latency; higher = more cushion when compositor/GPU scheduling hiccups.')

$lblAudioQueueBuffers = Add-Label $settingsGroup 'Audio q buffers' 15 548 110

$numAudioQueueBuffers = New-Object System.Windows.Forms.NumericUpDown
$numAudioQueueBuffers.Location = New-Object System.Drawing.Point(15, 548)
$numAudioQueueBuffers.Size = New-Object System.Drawing.Size(70, 23)
$numAudioQueueBuffers.Minimum = 1
$numAudioQueueBuffers.Maximum = 32
$numAudioQueueBuffers.Increment = 1
$numAudioQueueBuffers.Value = $script:DefaultAudioQueueBuffers
$settingsGroup.Controls.Add($numAudioQueueBuffers)
$toolTip.SetToolTip($numAudioQueueBuffers, 'Audio queue buffer depth. If audio clock is dragging video, smaller/leaky audio queues help reveal it.')

$lblAudioQueueCapMs = Add-Label $settingsGroup 'Audio queue cap ms' 15 548 130

$numAudioQueueCapMs = New-Object System.Windows.Forms.NumericUpDown
$numAudioQueueCapMs.Location = New-Object System.Drawing.Point(15, 548)
$numAudioQueueCapMs.Size = New-Object System.Drawing.Size(80, 23)
$numAudioQueueCapMs.Minimum = 0
$numAudioQueueCapMs.Maximum = 500
$numAudioQueueCapMs.Increment = 10
$numAudioQueueCapMs.Value = $script:DefaultAudioQueueCapMs
$settingsGroup.Controls.Add($numAudioQueueCapMs)
$toolTip.SetToolTip($numAudioQueueCapMs, 'Optional audio queue time cap. 0 disables time cap. Nonzero caps below the safe live-audio floor are clamped at runtime to avoid GStreamer latency errors.')

$chkBufferLatenessTracer = New-Object System.Windows.Forms.CheckBox
$chkBufferLatenessTracer.Text = 'Buffer lateness tracer'
$chkBufferLatenessTracer.Location = New-Object System.Drawing.Point(15, 548)
$chkBufferLatenessTracer.Size = New-Object System.Drawing.Size(190, 24)
$chkBufferLatenessTracer.Checked = $script:DefaultBufferLatenessTracer
$settingsGroup.Controls.Add($chkBufferLatenessTracer)
$toolTip.SetToolTip($chkBufferLatenessTracer, 'Enables GST_TRACERS=buffer-lateness and GST_DEBUG=GST_TRACER:7 for gst-launch. Use only while diagnosing; logs get noisy.')

$lblGstDebugMode = Add-Label $settingsGroup 'GST debug' 15 548 90

$cmbGstDebugMode = New-Object System.Windows.Forms.ComboBox
$cmbGstDebugMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbGstDebugMode.Size = New-Object System.Drawing.Size(170, 23)
$cmbGstDebugMode.DropDownStyle = 'DropDownList'
$null = $cmbGstDebugMode.Items.AddRange([string[]]@('Off','ERROR (*:1)','WARNING (*:2)','INFO (*:3)','DEBUG (*:4)','LOG (*:5)','TRACE (*:6)','FULL/MEMDUMP (*:9)','Custom'))
$cmbGstDebugMode.SelectedItem = $script:DefaultGstDebugMode
$settingsGroup.Controls.Add($cmbGstDebugMode)
$toolTip.SetToolTip($cmbGstDebugMode, 'Sets GST_DEBUG for the gst-launch process only. DEBUG/TRACE/FULL are very noisy but useful for latency/desync diagnosis.')

$lblGstDebugSpec = Add-Label $settingsGroup 'GST_DEBUG spec' 15 548 120

$txtGstDebugSpec = New-Object System.Windows.Forms.TextBox
$txtGstDebugSpec.Location = New-Object System.Drawing.Point(15, 548)
$txtGstDebugSpec.Size = New-Object System.Drawing.Size(185, 23)
$txtGstDebugSpec.Text = $script:DefaultGstDebugSpec
$settingsGroup.Controls.Add($txtGstDebugSpec)
$toolTip.SetToolTip($txtGstDebugSpec, 'Custom GST_DEBUG value, for example *:4,webrtc*:6,rtp*:6,rtpjitterbuffer:6,wasapi*:6. Used only when mode is Custom; presets show their generated spec here.')

$chkGstDebugNoColor = New-Object System.Windows.Forms.CheckBox
$chkGstDebugNoColor.Text = 'No debug color'
$chkGstDebugNoColor.Location = New-Object System.Drawing.Point(15, 548)
$chkGstDebugNoColor.Size = New-Object System.Drawing.Size(135, 24)
$chkGstDebugNoColor.Checked = $script:DefaultGstDebugNoColor
$settingsGroup.Controls.Add($chkGstDebugNoColor)
$toolTip.SetToolTip($chkGstDebugNoColor, 'Sets GST_DEBUG_NO_COLOR=1 so redirected logs are readable in the app/log files.')

$lblJbufWatchdogMode = Add-Label $settingsGroup 'JBUF watchdog' 15 548 115

$cmbJbufWatchdogMode = New-Object System.Windows.Forms.ComboBox
$cmbJbufWatchdogMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbJbufWatchdogMode.Size = New-Object System.Drawing.Size(170, 23)
$cmbJbufWatchdogMode.DropDownStyle = 'DropDownList'
$null = $cmbJbufWatchdogMode.Items.AddRange([string[]]@('Off','Warn only','Auto-reconnect viewer'))
$cmbJbufWatchdogMode.SelectedItem = $script:DefaultJbufWatchdogMode
$settingsGroup.Controls.Add($cmbJbufWatchdogMode)
$toolTip.SetToolTip($cmbJbufWatchdogMode, 'Browser-side guard for growing WebRTC jitter buffer. Warn only paints status; Auto-reconnect viewer tears down the browser PeerConnection when JBUF keeps exceeding the threshold.')

$lblJbufMaxMs = Add-Label $settingsGroup 'JBUF max ms' 15 548 100

$numJbufMaxMs = New-Object System.Windows.Forms.NumericUpDown
$numJbufMaxMs.Location = New-Object System.Drawing.Point(15, 548)
$numJbufMaxMs.Size = New-Object System.Drawing.Size(80, 23)
$numJbufMaxMs.Minimum = 5
$numJbufMaxMs.Maximum = 500
$numJbufMaxMs.Increment = 5
$numJbufMaxMs.Value = $script:DefaultJbufMaxMs
$settingsGroup.Controls.Add($numJbufMaxMs)
$toolTip.SetToolTip($numJbufMaxMs, 'Browser-side JBUF warning/reconnect threshold. This is a watchdog threshold, not a guaranteed hard browser limit.')

$chkPlayerStatsOverlay = New-Object System.Windows.Forms.CheckBox
$chkPlayerStatsOverlay.Text = 'Stats overlay'
$chkPlayerStatsOverlay.Location = New-Object System.Drawing.Point(15, 548)
$chkPlayerStatsOverlay.Size = New-Object System.Drawing.Size(130, 24)
$chkPlayerStatsOverlay.Checked = $script:DefaultPlayerStatsOverlay
$settingsGroup.Controls.Add($chkPlayerStatsOverlay)
$toolTip.SetToolTip($chkPlayerStatsOverlay, 'Show the browser player stats overlay. Written to gstglass-config.js as statsOverlay.')

$chkPlayerJbufDebug = New-Object System.Windows.Forms.CheckBox
$chkPlayerJbufDebug.Text = 'JBUF debug logging'
$chkPlayerJbufDebug.Location = New-Object System.Drawing.Point(15, 548)
$chkPlayerJbufDebug.Size = New-Object System.Drawing.Size(155, 24)
$chkPlayerJbufDebug.Checked = $script:DefaultPlayerJbufDebug
$settingsGroup.Controls.Add($chkPlayerJbufDebug)
$toolTip.SetToolTip($chkPlayerJbufDebug, 'Enable browser console logging for player.js JBUF target/config resolution.')

$numLiveEdgeAverageSec = New-Object System.Windows.Forms.NumericUpDown
$numLiveEdgeAverageSec.Location = New-Object System.Drawing.Point(15, 548)
$numLiveEdgeAverageSec.Size = New-Object System.Drawing.Size(70, 23)
$numLiveEdgeAverageSec.Minimum = 1
$numLiveEdgeAverageSec.Maximum = 30
$numLiveEdgeAverageSec.Increment = 1
$numLiveEdgeAverageSec.Value = $script:DefaultLiveEdgeAverageSec
$settingsGroup.Controls.Add($numLiveEdgeAverageSec)
$toolTip.SetToolTip($numLiveEdgeAverageSec, 'Rolling average window for Live Edge excess latency. Shorter reacts faster; longer is steadier. Range 1-30 seconds.')

$numLiveEdgeGreenMs = New-Object System.Windows.Forms.NumericUpDown
$numLiveEdgeGreenMs.Location = New-Object System.Drawing.Point(15, 548)
$numLiveEdgeGreenMs.Size = New-Object System.Drawing.Size(80, 23)
$numLiveEdgeGreenMs.Minimum = 1
$numLiveEdgeGreenMs.Maximum = 4999
$numLiveEdgeGreenMs.Increment = 1
$numLiveEdgeGreenMs.Value = $script:DefaultLiveEdgeGreenMs
$settingsGroup.Controls.Add($numLiveEdgeGreenMs)
$toolTip.SetToolTip($numLiveEdgeGreenMs, 'Maximum rolling excess-latency average shown as green / Live.')

$numLiveEdgeYellowMs = New-Object System.Windows.Forms.NumericUpDown
$numLiveEdgeYellowMs.Location = New-Object System.Drawing.Point(15, 548)
$numLiveEdgeYellowMs.Size = New-Object System.Drawing.Size(80, 23)
$numLiveEdgeYellowMs.Minimum = 2
$numLiveEdgeYellowMs.Maximum = 5000
$numLiveEdgeYellowMs.Increment = 1
$numLiveEdgeYellowMs.Value = $script:DefaultLiveEdgeYellowMs
$settingsGroup.Controls.Add($numLiveEdgeYellowMs)
$toolTip.SetToolTip($numLiveEdgeYellowMs, 'Maximum rolling excess-latency average shown as yellow / Delayed. Values above this are red.')

$chkPlayerUrlOverrides = New-Object System.Windows.Forms.CheckBox
$chkPlayerUrlOverrides.Text = 'Open/copy with URL overrides'
$chkPlayerUrlOverrides.Location = New-Object System.Drawing.Point(15, 548)
$chkPlayerUrlOverrides.Size = New-Object System.Drawing.Size(220, 24)
$chkPlayerUrlOverrides.Checked = $script:DefaultPlayerUrlOverrides
$settingsGroup.Controls.Add($chkPlayerUrlOverrides)
$toolTip.SetToolTip($chkPlayerUrlOverrides, 'Debug escape hatch. Off = clean /live/ URL uses gstglass-config.js. On = append current Player tab values as query overrides.')

$chkPlayerSeparateHtmlMediaElements = New-Object System.Windows.Forms.CheckBox
$chkPlayerSeparateHtmlMediaElements.Text = 'Separate video and audio HTML media elements'
$chkPlayerSeparateHtmlMediaElements.Location = New-Object System.Drawing.Point(15, 548)
$chkPlayerSeparateHtmlMediaElements.Size = New-Object System.Drawing.Size(340, 24)
$chkPlayerSeparateHtmlMediaElements.Checked = $script:DefaultPlayerSeparateHtmlMediaElements
$settingsGroup.Controls.Add($chkPlayerSeparateHtmlMediaElements)
$toolTip.SetToolTip($chkPlayerSeparateHtmlMediaElements, 'Player rendering only. On attaches the video track to the video element and the audio track to a separate audio element. Off recombines both tracks into one MediaStream on the video element. Independent of A/V MediaStream grouping. Physical split WebRTC producers necessarily use separate elements.')

$cmbDirectWebRtcAvPipelineMode = New-Object System.Windows.Forms.ComboBox
$cmbDirectWebRtcAvPipelineMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbDirectWebRtcAvPipelineMode.Size = New-Object System.Drawing.Size(310, 23)
$cmbDirectWebRtcAvPipelineMode.DropDownStyle = 'DropDownList'
$null = $cmbDirectWebRtcAvPipelineMode.Items.AddRange([string[]]@('Single pipeline','Split A/V pipelines - separate gst-launch'))
$cmbDirectWebRtcAvPipelineMode.SelectedItem = $script:DefaultDirectWebRtcAvPipelineMode
$settingsGroup.Controls.Add($cmbDirectWebRtcAvPipelineMode)
$toolTip.SetToolTip($cmbDirectWebRtcAvPipelineMode, 'Direct GST WebRTC topology. Single pipeline keeps audio and video in one gst-launch pipeline. Split mode launches a second audio-only gst-launch/webrtcsink. Transport-tab controls choose separate signalling ports or one shared signalling server.')

$cmbSplitPlayerSyncMode = New-Object System.Windows.Forms.ComboBox
$cmbSplitPlayerSyncMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbSplitPlayerSyncMode.Size = New-Object System.Drawing.Size(220, 23)
$cmbSplitPlayerSyncMode.DropDownStyle = 'DropDownList'
$null = $cmbSplitPlayerSyncMode.Items.AddRange([string[]]@('Off / free-run','Audio watchdog only','Soft sync experimental'))
$cmbSplitPlayerSyncMode.SelectedItem = $script:DefaultSplitPlayerSyncMode
$settingsGroup.Controls.Add($cmbSplitPlayerSyncMode)
$toolTip.SetToolTip($cmbSplitPlayerSyncMode, 'Split A/V browser/player behavior. Default Off leaves the proven split path free-running. Audio watchdog and soft sync are opt-in experiments that only recover/reconnect the split audio side; they do not delay video.')

$numSplitAudioStallSeconds = New-Object System.Windows.Forms.NumericUpDown
$numSplitAudioStallSeconds.Location = New-Object System.Drawing.Point(15, 548)
$numSplitAudioStallSeconds.Size = New-Object System.Drawing.Size(70, 23)
$numSplitAudioStallSeconds.Minimum = 1
$numSplitAudioStallSeconds.Maximum = 30
$numSplitAudioStallSeconds.Increment = 1
$numSplitAudioStallSeconds.Value = $script:DefaultSplitAudioStallSeconds
$settingsGroup.Controls.Add($numSplitAudioStallSeconds)
$toolTip.SetToolTip($numSplitAudioStallSeconds, 'Opt-in split audio watchdog timeout. If enabled and audio stats/element look stalled this many seconds, the player recovers only the split audio path after the startup warmup window.')

$numSplitAudioWarmupSeconds = New-Object System.Windows.Forms.NumericUpDown
$numSplitAudioWarmupSeconds.Location = New-Object System.Drawing.Point(15, 548)
$numSplitAudioWarmupSeconds.Size = New-Object System.Drawing.Size(70, 23)
$numSplitAudioWarmupSeconds.Minimum = 0
$numSplitAudioWarmupSeconds.Maximum = 600
$numSplitAudioWarmupSeconds.Increment = 1
$numSplitAudioWarmupSeconds.Value = $script:DefaultSplitAudioWarmupSeconds
$settingsGroup.Controls.Add($numSplitAudioWarmupSeconds)
$toolTip.SetToolTip($numSplitAudioWarmupSeconds, 'Opt-in startup/equalization grace period for both browser JBUF watchdog and split audio watchdog/soft-sync recovery. Recovery/reconnect is blocked until this many seconds after primary or split audio connects/receives media. Range 0-600 seconds.')

$numSplitAvOffsetWarnMs = New-Object System.Windows.Forms.NumericUpDown
$numSplitAvOffsetWarnMs.Location = New-Object System.Drawing.Point(15, 548)
$numSplitAvOffsetWarnMs.Size = New-Object System.Drawing.Size(80, 23)
$numSplitAvOffsetWarnMs.Minimum = 20
$numSplitAvOffsetWarnMs.Maximum = 1000
$numSplitAvOffsetWarnMs.Increment = 10
$numSplitAvOffsetWarnMs.Value = $script:DefaultSplitAvOffsetWarnMs
$settingsGroup.Controls.Add($numSplitAvOffsetWarnMs)
$toolTip.SetToolTip($numSplitAvOffsetWarnMs, 'Opt-in split A/V soft-sync drift threshold. This compares current estimated A/V offset against the learned/configured baseline, not against zero. Video is never delayed by this feature.')

$numSplitAvOffsetBaselineMs = New-Object System.Windows.Forms.NumericUpDown
$numSplitAvOffsetBaselineMs.Location = New-Object System.Drawing.Point(15, 548)
$numSplitAvOffsetBaselineMs.Size = New-Object System.Drawing.Size(80, 23)
$numSplitAvOffsetBaselineMs.Minimum = 0
$numSplitAvOffsetBaselineMs.Maximum = 1000
$numSplitAvOffsetBaselineMs.Increment = 1
$numSplitAvOffsetBaselineMs.Value = $script:DefaultSplitAvOffsetBaselineMs
$settingsGroup.Controls.Add($numSplitAvOffsetBaselineMs)
$toolTip.SetToolTip($numSplitAvOffsetBaselineMs, 'Opt-in split A/V healthy offset baseline in ms. 0 = auto-learn after watchdog warmup. Example: audio 59ms - video 16ms = baseline 43ms, and only drift above that is considered bad.')

$btnResetAll = New-Object System.Windows.Forms.Button
$btnResetAll.Text = 'Reset All App Defaults'
$btnResetAll.Location = New-Object System.Drawing.Point(15, 548)
$btnResetAll.Size = New-Object System.Drawing.Size(170, 30)
$settingsGroup.Controls.Add($btnResetAll)


$null = Add-Label $settingsGroup 'Width' 15 166 45
$numWidth = New-Object System.Windows.Forms.NumericUpDown
$numWidth.Location = New-Object System.Drawing.Point(60, 166)
$numWidth.Size = New-Object System.Drawing.Size(80, 23)
$numWidth.Minimum = 320
$numWidth.Maximum = 7680
$numWidth.Increment = 16
$numWidth.Value = 1920
$settingsGroup.Controls.Add($numWidth)

$null = Add-Label $settingsGroup 'Height' 150 166 48
$numHeight = New-Object System.Windows.Forms.NumericUpDown
$numHeight.Location = New-Object System.Drawing.Point(198, 166)
$numHeight.Size = New-Object System.Drawing.Size(80, 23)
$numHeight.Minimum = 240
$numHeight.Maximum = 4320
$numHeight.Increment = 16
$numHeight.Value = 1080
$settingsGroup.Controls.Add($numHeight)

$null = Add-Label $settingsGroup 'FPS' 290 166 35
$numFps = New-Object System.Windows.Forms.NumericUpDown
$numFps.Location = New-Object System.Drawing.Point(325, 166)
$numFps.Size = New-Object System.Drawing.Size(60, 23)
$numFps.Minimum = 1
$numFps.Maximum = 240
$numFps.Value = 60
$settingsGroup.Controls.Add($numFps)

$null = Add-Label $settingsGroup 'Video kbps' 400 166 75
$numVideoBitrate = New-Object System.Windows.Forms.NumericUpDown
$numVideoBitrate.Location = New-Object System.Drawing.Point(475, 166)
$numVideoBitrate.Size = New-Object System.Drawing.Size(90, 23)
$numVideoBitrate.Minimum = 250
$numVideoBitrate.Maximum = 100000
$numVideoBitrate.Increment = 500
$numVideoBitrate.Value = 12000
$settingsGroup.Controls.Add($numVideoBitrate)

$null = Add-Label $settingsGroup 'GOP sec' 580 166 60
$numGopSeconds = New-Object System.Windows.Forms.NumericUpDown
$numGopSeconds.Location = New-Object System.Drawing.Point(640, 166)
$numGopSeconds.Size = New-Object System.Drawing.Size(60, 23)
$numGopSeconds.Minimum = 1
$numGopSeconds.Maximum = 10
$numGopSeconds.Value = 1
$settingsGroup.Controls.Add($numGopSeconds)

$chkUnifiedBridgeKeyframeGuard = New-Object System.Windows.Forms.CheckBox
$chkUnifiedBridgeKeyframeGuard.Text = 'Unified bridge periodic keyframes'
$chkUnifiedBridgeKeyframeGuard.Location = New-Object System.Drawing.Point(15, 548)
$chkUnifiedBridgeKeyframeGuard.Size = New-Object System.Drawing.Size(250, 24)
$chkUnifiedBridgeKeyframeGuard.Checked = $script:DefaultUnifiedBridgeKeyframeGuard
$settingsGroup.Controls.Add($chkUnifiedBridgeKeyframeGuard)
$toolTip.SetToolTip($chkUnifiedBridgeKeyframeGuard, 'Unified publisher only. Overrides GOP seconds with a short periodic IDR interval because browser PLI/FIR keyframe requests cannot cross the localhost RTP/process boundary. Off emits no override and uses GOP sec.')

$numUnifiedBridgeKeyframeIntervalMs = New-Object System.Windows.Forms.NumericUpDown
$numUnifiedBridgeKeyframeIntervalMs.Location = New-Object System.Drawing.Point(15, 548)
$numUnifiedBridgeKeyframeIntervalMs.Size = New-Object System.Drawing.Size(85, 23)
$numUnifiedBridgeKeyframeIntervalMs.Minimum = 100
$numUnifiedBridgeKeyframeIntervalMs.Maximum = 10000
$numUnifiedBridgeKeyframeIntervalMs.Increment = 100
$numUnifiedBridgeKeyframeIntervalMs.Value = $script:DefaultUnifiedBridgeKeyframeIntervalMs
$settingsGroup.Controls.Add($numUnifiedBridgeKeyframeIntervalMs)
$toolTip.SetToolTip($numUnifiedBridgeKeyframeIntervalMs, 'Periodic IDR/keyframe interval in milliseconds for the unified publisher video bridge. The value is converted to encoder GOP frames using the current FPS. Smaller values recover joins/reconnects faster but increase bitrate and encoder work.')


$null = Add-Label $settingsGroup 'Rate control' 15 520 90
$cmbRateControl = New-Object System.Windows.Forms.ComboBox
$cmbRateControl.Location = New-Object System.Drawing.Point(15, 548)
$cmbRateControl.Size = New-Object System.Drawing.Size(95, 23)
$cmbRateControl.DropDownStyle = 'DropDownList'
$null = $cmbRateControl.Items.AddRange([string[]]$script:RateControlModes)
$cmbRateControl.SelectedItem = 'cbr'
$settingsGroup.Controls.Add($cmbRateControl)
$toolTip.SetToolTip($cmbRateControl, 'Stream encoder rate control. CBR is safest for live transport; VBR/CQP are mostly for quality testing or recording-style workflows.')

$null = Add-Label $settingsGroup 'Max kbps' 15 520 70
$numMaxVideoBitrate = New-Object System.Windows.Forms.NumericUpDown
$numMaxVideoBitrate.Location = New-Object System.Drawing.Point(15, 548)
$numMaxVideoBitrate.Size = New-Object System.Drawing.Size(100, 23)
$numMaxVideoBitrate.Minimum = 0
$numMaxVideoBitrate.Maximum = 300000
$numMaxVideoBitrate.Increment = 500
$numMaxVideoBitrate.Value = 0
$settingsGroup.Controls.Add($numMaxVideoBitrate)
$toolTip.SetToolTip($numMaxVideoBitrate, 'Maximum bitrate for VBR where the selected encoder supports it. 0 uses the encoder default; CBR usually ignores this.')

$null = Add-Label $settingsGroup 'CQ/QP' 15 520 60
$numConstantQp = New-Object System.Windows.Forms.NumericUpDown
$numConstantQp.Location = New-Object System.Drawing.Point(15, 548)
$numConstantQp.Size = New-Object System.Drawing.Size(70, 23)
$numConstantQp.Minimum = 0
$numConstantQp.Maximum = 51
$numConstantQp.Value = 20
$settingsGroup.Controls.Add($numConstantQp)
$toolTip.SetToolTip($numConstantQp, 'Constant QP for constqp/CQP, or constant-quality target for NVENC VBR. Lower means higher quality and bigger files/bitrate spikes.')

$null = Add-Label $settingsGroup 'Tune' 15 520 60
$cmbEncoderTune = New-Object System.Windows.Forms.ComboBox
$cmbEncoderTune.Location = New-Object System.Drawing.Point(15, 548)
$cmbEncoderTune.Size = New-Object System.Drawing.Size(165, 23)
$cmbEncoderTune.DropDownStyle = 'DropDownList'
$null = $cmbEncoderTune.Items.AddRange([string[]]$script:NvencTuneModes)
$cmbEncoderTune.SelectedItem = 'ultra-low-latency'
$settingsGroup.Controls.Add($cmbEncoderTune)
$toolTip.SetToolTip($cmbEncoderTune, 'NVENC tune. Other encoder families keep their closest low-latency/quality mapping or use Custom encoder options.')

$null = Add-Label $settingsGroup 'Multipass' 15 520 90
$cmbMultipass = New-Object System.Windows.Forms.ComboBox
$cmbMultipass.Location = New-Object System.Drawing.Point(15, 548)
$cmbMultipass.Size = New-Object System.Drawing.Size(150, 23)
$cmbMultipass.DropDownStyle = 'DropDownList'
$null = $cmbMultipass.Items.AddRange([string[]]$script:NvencMultipassModes)
$cmbMultipass.SelectedItem = 'disabled'
$settingsGroup.Controls.Add($cmbMultipass)
$toolTip.SetToolTip($cmbMultipass, 'NVENC multipass mode. Disabled is best for live ultra-low-latency; two-pass modes can improve quality but add work/latency.')

$cmbVideoPipelineClockMode = New-Object System.Windows.Forms.ComboBox
$cmbVideoPipelineClockMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbVideoPipelineClockMode.Size = New-Object System.Drawing.Size(225, 23)
$cmbVideoPipelineClockMode.DropDownStyle = 'DropDownList'
$null = $cmbVideoPipelineClockMode.Items.AddRange([string[]]@(
    'Automatic / element elected',
    'System monotonic',
    'System realtime'
))
$cmbVideoPipelineClockMode.SelectedItem = $script:DefaultVideoPipelineClockMode
$settingsGroup.Controls.Add($cmbVideoPipelineClockMode)
$toolTip.SetToolTip($cmbVideoPipelineClockMode, 'Shared pipeline master clock. Automatic preserves GStreamer clock election. System monotonic/realtime wrap the complete gst-launch graph in clockselect, so a single A/V pipeline cannot switch to the WASAPI device clock.')

$cmbVideoTimestampMode = New-Object System.Windows.Forms.ComboBox
$cmbVideoTimestampMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbVideoTimestampMode.Size = New-Object System.Drawing.Size(210, 23)
$cmbVideoTimestampMode.DropDownStyle = 'DropDownList'
$null = $cmbVideoTimestampMode.Items.AddRange([string[]]@(
    'Plugin default',
    'Pipeline running-time',
    'Source timestamps'
))
$cmbVideoTimestampMode.SelectedItem = $script:DefaultVideoTimestampMode
$settingsGroup.Controls.Add($cmbVideoTimestampMode)
$toolTip.SetToolTip($cmbVideoTimestampMode, 'Video source timestamp policy. Pipeline running-time adds do-timestamp=true to screen/webcam sources. Source timestamps adds do-timestamp=false. Plugin default leaves the capture source unchanged.')

$cmbVideoSyncMode = New-Object System.Windows.Forms.ComboBox
$cmbVideoSyncMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbVideoSyncMode.Size = New-Object System.Drawing.Size(120, 23)
$cmbVideoSyncMode.DropDownStyle = 'DropDownList'
$null = $cmbVideoSyncMode.Items.AddRange([string[]]@('Default','sync=true','sync=false'))
$cmbVideoSyncMode.SelectedItem = $script:DefaultVideoSyncMode
$settingsGroup.Controls.Add($cmbVideoSyncMode)
$toolTip.SetToolTip($cmbVideoSyncMode, 'Video branch sync lab. Default leaves transport branches unchanged and preserves existing local preview behavior. sync=true/sync=false inserts a clocksync element before compatible send/mux sinks, and applies the value to the local preview sink.')

$null = Add-Label $settingsGroup 'VBV kbits' 15 520 80
$numVbvBuffer = New-Object System.Windows.Forms.NumericUpDown
$numVbvBuffer.Location = New-Object System.Drawing.Point(15, 548)
$numVbvBuffer.Size = New-Object System.Drawing.Size(95, 23)
$numVbvBuffer.Minimum = 0
$numVbvBuffer.Maximum = 1000000
$numVbvBuffer.Increment = 500
$numVbvBuffer.Value = 0
$settingsGroup.Controls.Add($numVbvBuffer)
$toolTip.SetToolTip($numVbvBuffer, 'NVENC VBV/HRD buffer size in kbits. 0 uses the encoder default. Small buffers can reduce latency but may hurt quality.')

$chkTemporalAq = New-Object System.Windows.Forms.CheckBox
$chkTemporalAq.Text = 'Temporal AQ'
$chkTemporalAq.Location = New-Object System.Drawing.Point(15, 548)
$chkTemporalAq.Size = New-Object System.Drawing.Size(105, 23)
$chkTemporalAq.Checked = $false
$settingsGroup.Controls.Add($chkTemporalAq)
$toolTip.SetToolTip($chkTemporalAq, 'NVENC temporal adaptive quantization. Can improve motion quality; may increase encoder work and is not always ideal for latency testing.')

$null = Add-Label $settingsGroup 'Custom encoder options' 15 520 160
$txtCustomEncoderOptions = New-Object System.Windows.Forms.TextBox
$txtCustomEncoderOptions.Location = New-Object System.Drawing.Point(15, 548)
$txtCustomEncoderOptions.Size = New-Object System.Drawing.Size(520, 23)
$txtCustomEncoderOptions.Text = ''
$settingsGroup.Controls.Add($txtCustomEncoderOptions)
$toolTip.SetToolTip($txtCustomEncoderOptions, 'Raw options appended directly after the selected stream encoder element, e.g. weighted-pred=true strict-gop=true. Use for untested AMD/Intel/MF/software knobs.')

$null = Add-Label $settingsGroup 'Encoder' 15 202 60
$cmbEncoder = New-Object System.Windows.Forms.ComboBox
$cmbEncoder.Location = New-Object System.Drawing.Point(75, 202)
$cmbEncoder.Size = New-Object System.Drawing.Size(330, 23)
$cmbEncoder.DropDownStyle = 'DropDownList'
$null = $cmbEncoder.Items.AddRange([string[]]($script:EncoderCatalog.Keys))
$cmbEncoder.SelectedItem = $script:DefaultEncoderName
$settingsGroup.Controls.Add($cmbEncoder)
$toolTip.SetToolTip(
    $cmbEncoder,
    'Select a hardware or software encoder. Use Check to verify that the selected GStreamer runtime contains the required element and parser.'
)

$lblEncoderStatus = New-Object System.Windows.Forms.Label
$lblEncoderStatus.Text = 'H.264 * Hardware * D3D11'
$lblEncoderStatus.Location = New-Object System.Drawing.Point(415, 202)
$lblEncoderStatus.Size = New-Object System.Drawing.Size(303, 23)
$lblEncoderStatus.TextAlign = 'MiddleLeft'
$lblEncoderStatus.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($lblEncoderStatus)

$null = Add-Label $settingsGroup 'NVENC preset' 15 238 90
$cmbPreset = New-Object System.Windows.Forms.ComboBox
$cmbPreset.Location = New-Object System.Drawing.Point(105, 238)
$cmbPreset.Size = New-Object System.Drawing.Size(80, 23)
$cmbPreset.DropDownStyle = 'DropDownList'
$null = $cmbPreset.Items.AddRange(@('p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7'))
$cmbPreset.SelectedItem = 'p1'
$settingsGroup.Controls.Add($cmbPreset)

$null = Add-Label $settingsGroup 'H.264 profile' 200 238 90
$cmbProfile = New-Object System.Windows.Forms.ComboBox
$cmbProfile.Location = New-Object System.Drawing.Point(290, 238)
$cmbProfile.Size = New-Object System.Drawing.Size(145, 23)
$cmbProfile.DropDownStyle = 'DropDownList'
$null = $cmbProfile.Items.AddRange(@('constrained-baseline', 'baseline', 'main', 'high'))
$cmbProfile.SelectedItem = 'constrained-baseline'
$settingsGroup.Controls.Add($cmbProfile)

$null = Add-Label $settingsGroup 'SRT latency ms' 450 238 95
$numSrtLatency = New-Object System.Windows.Forms.NumericUpDown
$numSrtLatency.Location = New-Object System.Drawing.Point(545, 238)
$numSrtLatency.Size = New-Object System.Drawing.Size(70, 23)
$numSrtLatency.Minimum = 0
$numSrtLatency.Maximum = 10000
$numSrtLatency.Increment = 10
$numSrtLatency.Value = 50
$numSrtLatency.Enabled = $false
$settingsGroup.Controls.Add($numSrtLatency)

$null = Add-Label $settingsGroup 'RTSP' 625 238 40
$cmbRtspTransport = New-Object System.Windows.Forms.ComboBox
$cmbRtspTransport.Location = New-Object System.Drawing.Point(665, 238)
$cmbRtspTransport.Size = New-Object System.Drawing.Size(55, 23)
$cmbRtspTransport.DropDownStyle = 'DropDownList'
$null = $cmbRtspTransport.Items.AddRange(@('TCP', 'UDP'))
$cmbRtspTransport.SelectedItem = 'TCP'
$cmbRtspTransport.Enabled = $false
$settingsGroup.Controls.Add($cmbRtspTransport)

$null = Add-Label $settingsGroup 'B-frames' 15 278 60
$numBFrames = New-Object System.Windows.Forms.NumericUpDown
$numBFrames.Location = New-Object System.Drawing.Point(75, 278)
$numBFrames.Size = New-Object System.Drawing.Size(55, 23)
$numBFrames.Minimum = 0
$numBFrames.Maximum = 4
$numBFrames.Value = 0
$settingsGroup.Controls.Add($numBFrames)
$toolTip.SetToolTip($numBFrames, 'Leave at 0 for lowest latency and WebRTC-compatible H.264.')

$chkLookAhead = New-Object System.Windows.Forms.CheckBox
$chkLookAhead.Text = 'Look-ahead'
$chkLookAhead.Location = New-Object System.Drawing.Point(150, 278)
$chkLookAhead.Size = New-Object System.Drawing.Size(90, 23)
$chkLookAhead.Checked = $false
$settingsGroup.Controls.Add($chkLookAhead)
$toolTip.SetToolTip($chkLookAhead, 'Enables encoder look-ahead where supported; this adds frame latency.')

$null = Add-Label $settingsGroup 'Frames' 240 278 48
$numLookAheadFrames = New-Object System.Windows.Forms.NumericUpDown
$numLookAheadFrames.Location = New-Object System.Drawing.Point(288, 278)
$numLookAheadFrames.Size = New-Object System.Drawing.Size(55, 23)
$numLookAheadFrames.Minimum = 1
$numLookAheadFrames.Maximum = 64
$numLookAheadFrames.Value = 20
$numLookAheadFrames.Enabled = $false
$settingsGroup.Controls.Add($numLookAheadFrames)

$chkAdaptiveQuantization = New-Object System.Windows.Forms.CheckBox
$chkAdaptiveQuantization.Text = 'Spatial AQ'
$chkAdaptiveQuantization.Location = New-Object System.Drawing.Point(365, 278)
$chkAdaptiveQuantization.Size = New-Object System.Drawing.Size(150, 23)
$chkAdaptiveQuantization.Checked = $false
$settingsGroup.Controls.Add($chkAdaptiveQuantization)

$null = Add-Label $settingsGroup 'AQ strength' 525 278 75
$numAqStrength = New-Object System.Windows.Forms.NumericUpDown
$numAqStrength.Location = New-Object System.Drawing.Point(600, 278)
$numAqStrength.Size = New-Object System.Drawing.Size(55, 23)
$numAqStrength.Minimum = 1
$numAqStrength.Maximum = 15
$numAqStrength.Value = 8
$numAqStrength.Enabled = $false
$settingsGroup.Controls.Add($numAqStrength)

$chkDesktopAudio = New-Object System.Windows.Forms.CheckBox
$chkDesktopAudio.Text = 'Desktop audio'
$chkDesktopAudio.Location = New-Object System.Drawing.Point(15, 316)
$chkDesktopAudio.Size = New-Object System.Drawing.Size(115, 23)
$chkDesktopAudio.Checked = $true
$settingsGroup.Controls.Add($chkDesktopAudio)

$chkAudioMixerMode = New-Object System.Windows.Forms.CheckBox
$chkAudioMixerMode.Text = 'Route desktop through audiomixer'
$chkAudioMixerMode.Location = New-Object System.Drawing.Point(565, 316)
$chkAudioMixerMode.Size = New-Object System.Drawing.Size(245, 23)
$chkAudioMixerMode.Checked = $script:DefaultAudioMixerMode
$settingsGroup.Controls.Add($chkAudioMixerMode)
$toolTip.SetToolTip($chkAudioMixerMode, 'Recommended timing-normalization path. When enabled, desktop-only audio is routed through audiomixer before encoding. Uncheck to restore the legacy direct WASAPI-to-encoder path. Desktop + microphone always requires audiomixer to combine both sources.')

$null = Add-Label $settingsGroup 'Volume %' 130 316 65
$numDesktopVolume = New-Object System.Windows.Forms.NumericUpDown
$numDesktopVolume.Location = New-Object System.Drawing.Point(195, 316)
$numDesktopVolume.Size = New-Object System.Drawing.Size(65, 23)
$numDesktopVolume.Minimum = 0
$numDesktopVolume.Maximum = 200
$numDesktopVolume.Value = 100
$settingsGroup.Controls.Add($numDesktopVolume)

$chkMic = New-Object System.Windows.Forms.CheckBox
$chkMic.Text = 'Default microphone'
$chkMic.Location = New-Object System.Drawing.Point(280, 316)
$chkMic.Size = New-Object System.Drawing.Size(140, 23)
$chkMic.Checked = $false
$settingsGroup.Controls.Add($chkMic)

$null = Add-Label $settingsGroup 'Volume %' 420 316 65
$numMicVolume = New-Object System.Windows.Forms.NumericUpDown
$numMicVolume.Location = New-Object System.Drawing.Point(485, 316)
$numMicVolume.Size = New-Object System.Drawing.Size(65, 23)
$numMicVolume.Minimum = 0
$numMicVolume.Maximum = 200
$numMicVolume.Value = 100
$settingsGroup.Controls.Add($numMicVolume)

$null = Add-Label $settingsGroup 'Desktop device' 15 354 95
$cmbDesktopAudioDevice = New-Object System.Windows.Forms.ComboBox
$cmbDesktopAudioDevice.Location = New-Object System.Drawing.Point(115, 354)
$cmbDesktopAudioDevice.Size = New-Object System.Drawing.Size(420, 23)
$cmbDesktopAudioDevice.DropDownStyle = 'DropDownList'
$null = $cmbDesktopAudioDevice.Items.Add($script:DefaultAudioOutputDeviceLabel)
$cmbDesktopAudioDevice.SelectedIndex = 0
$settingsGroup.Controls.Add($cmbDesktopAudioDevice)
$toolTip.SetToolTip($cmbDesktopAudioDevice, 'WASAPI output endpoint used when Desktop audio is enabled. Loopback captures what that selected output device plays.')

$btnRefreshAudioDevices = New-Object System.Windows.Forms.Button
$btnRefreshAudioDevices.Text = 'Refresh audio devices'
$btnRefreshAudioDevices.Location = New-Object System.Drawing.Point(550, 354)
$btnRefreshAudioDevices.Size = New-Object System.Drawing.Size(150, 24)
$settingsGroup.Controls.Add($btnRefreshAudioDevices)
$toolTip.SetToolTip($btnRefreshAudioDevices, 'Runs gst-device-monitor and populates WASAPI input/output endpoints.')

$null = Add-Label $settingsGroup 'Mic device' 15 392 95
$cmbMicAudioDevice = New-Object System.Windows.Forms.ComboBox
$cmbMicAudioDevice.Location = New-Object System.Drawing.Point(115, 392)
$cmbMicAudioDevice.Size = New-Object System.Drawing.Size(420, 23)
$cmbMicAudioDevice.DropDownStyle = 'DropDownList'
$null = $cmbMicAudioDevice.Items.Add($script:DefaultAudioInputDeviceLabel)
$cmbMicAudioDevice.SelectedIndex = 0
$settingsGroup.Controls.Add($cmbMicAudioDevice)
$toolTip.SetToolTip($cmbMicAudioDevice, 'WASAPI capture endpoint used when Default microphone/Mic audio is enabled.')

$lblAudioDeviceStatus = New-Object System.Windows.Forms.Label
$lblAudioDeviceStatus.Text = 'Audio devices: defaults until refreshed'
$lblAudioDeviceStatus.Location = New-Object System.Drawing.Point(550, 392)
$lblAudioDeviceStatus.Size = New-Object System.Drawing.Size(260, 23)
$lblAudioDeviceStatus.TextAlign = 'MiddleLeft'
$lblAudioDeviceStatus.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($lblAudioDeviceStatus)

$null = Add-Label $settingsGroup 'A/V test mode' 15 430 95
$cmbAudioTransportMode = New-Object System.Windows.Forms.ComboBox
$cmbAudioTransportMode.Location = New-Object System.Drawing.Point(115, 354)
$cmbAudioTransportMode.Size = New-Object System.Drawing.Size(245, 23)
$cmbAudioTransportMode.DropDownStyle = 'DropDownList'
$null = $cmbAudioTransportMode.Items.AddRange([string[]]@(
    'Normal audio',
    'Video only - no audio track',
    'Muted audio clock only'
))
$cmbAudioTransportMode.SelectedItem = $script:DefaultAudioTransportMode
$settingsGroup.Controls.Add($cmbAudioTransportMode)
$toolTip.SetToolTip($cmbAudioTransportMode, 'A/V sync diagnostic. Normal uses the checkboxes below. Video only removes the audio track. Muted audio clock keeps an audio clock but emits silence.')

$cmbSplitAudioPipelineClockMode = New-Object System.Windows.Forms.ComboBox
$cmbSplitAudioPipelineClockMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbSplitAudioPipelineClockMode.Size = New-Object System.Drawing.Size(225, 23)
$cmbSplitAudioPipelineClockMode.DropDownStyle = 'DropDownList'
$null = $cmbSplitAudioPipelineClockMode.Items.AddRange([string[]]@(
    'Follow video/master',
    'Automatic / element elected',
    'System monotonic',
    'System realtime'
))
$cmbSplitAudioPipelineClockMode.SelectedItem = $script:DefaultSplitAudioPipelineClockMode
$settingsGroup.Controls.Add($cmbSplitAudioPipelineClockMode)
$toolTip.SetToolTip($cmbSplitAudioPipelineClockMode, 'Clock for the separate split-audio gst-launch process. Single-pipeline A/V always uses the master clock selected on the Video tab. Follow video/master applies the same selection to split audio.')

$lblAudioClockMode = Add-Label $settingsGroup 'WASAPI provider' 15 548 110

$cmbAudioClockMode = New-Object System.Windows.Forms.ComboBox
$cmbAudioClockMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbAudioClockMode.Size = New-Object System.Drawing.Size(230, 23)
$cmbAudioClockMode.DropDownStyle = 'DropDownList'
$null = $cmbAudioClockMode.Items.AddRange([string[]]@('Plugin default / allow WASAPI clock','System clock / no WASAPI clock'))
$cmbAudioClockMode.SelectedItem = $script:DefaultAudioClockMode
$settingsGroup.Controls.Add($cmbAudioClockMode)
$toolTip.SetToolTip($cmbAudioClockMode, 'Plugin default emits no provide-clock property. System clock / no WASAPI clock explicitly appends provide-clock=false. For a monotonic-master test, also select System monotonic on the Video tab and Resample as the slave method.')

$lblAudioTimingMode = Add-Label $settingsGroup 'Audio timing' 15 602 95
$cmbAudioTimingMode = New-Object System.Windows.Forms.ComboBox
$cmbAudioTimingMode.Location = New-Object System.Drawing.Point(115, 602)
$cmbAudioTimingMode.Size = New-Object System.Drawing.Size(260, 23)
$cmbAudioTimingMode.DropDownStyle = 'DropDownList'
$null = $cmbAudioTimingMode.Items.AddRange([string[]]@(
    'Plugin default / WASAPI normal',
    'WASAPI no pipeline clock',
    'WASAPI retimestamp',
    'WASAPI no clock + retimestamp',
    'Synthetic silent audio'
))
$cmbAudioTimingMode.SelectedItem = $script:DefaultAudioTimingMode
$settingsGroup.Controls.Add($cmbAudioTimingMode)
$toolTip.SetToolTip($cmbAudioTimingMode, 'Plugin default emits no do-timestamp or clock override. Synthetic silent audio bypasses WASAPI; the other entries explicitly add the named timing behavior.')

$lblAudioSlaveMethod = Add-Label $settingsGroup 'Slave method' 395 602 95
$cmbAudioSlaveMethod = New-Object System.Windows.Forms.ComboBox
$cmbAudioSlaveMethod.Location = New-Object System.Drawing.Point(495, 602)
$cmbAudioSlaveMethod.Size = New-Object System.Drawing.Size(135, 23)
$cmbAudioSlaveMethod.DropDownStyle = 'DropDownList'
$null = $cmbAudioSlaveMethod.Items.AddRange([string[]]@('Auto','None','Skew','Resample','Retimestamp'))
$cmbAudioSlaveMethod.SelectedItem = $script:DefaultAudioSlaveMethod
$settingsGroup.Controls.Add($cmbAudioSlaveMethod)
$toolTip.SetToolTip($cmbAudioSlaveMethod, 'Experimental wasapi2src/audiobasesrc slave-method. Leave Auto unless testing clock drift.')

$cmbAudioSyncMode = New-Object System.Windows.Forms.ComboBox
$cmbAudioSyncMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbAudioSyncMode.Size = New-Object System.Drawing.Size(120, 23)
$cmbAudioSyncMode.DropDownStyle = 'DropDownList'
$null = $cmbAudioSyncMode.Items.AddRange([string[]]@('Default','sync=true','sync=false'))
$cmbAudioSyncMode.SelectedItem = $script:DefaultAudioSyncMode
$settingsGroup.Controls.Add($cmbAudioSyncMode)
$toolTip.SetToolTip($cmbAudioSyncMode, 'Audio branch sync lab. Default leaves audio send branches unchanged. sync=true/sync=false inserts a clocksync element before compatible send/mux sinks so we can test whether sender-side timestamp scheduling is coupling A/V latency.')

$chkWasapiLowLatencyOverride = New-Object System.Windows.Forms.CheckBox
$chkWasapiLowLatencyOverride.Text = 'Force low-latency=true'
$chkWasapiLowLatencyOverride.Location = New-Object System.Drawing.Point(650, 602)
$chkWasapiLowLatencyOverride.Size = New-Object System.Drawing.Size(175, 23)
$chkWasapiLowLatencyOverride.Checked = $script:DefaultWasapiLowLatencyOverride
$settingsGroup.Controls.Add($chkWasapiLowLatencyOverride)
$toolTip.SetToolTip($chkWasapiLowLatencyOverride, 'Unchecked emits no low-latency property and leaves the WASAPI source at its plugin default. Checked explicitly appends low-latency=true.')

$chkAudioBufferOverride = New-Object System.Windows.Forms.CheckBox
$chkAudioBufferOverride.Text = 'Override buffer-time'
$chkAudioBufferOverride.Location = New-Object System.Drawing.Point(365, 648)
$chkAudioBufferOverride.Size = New-Object System.Drawing.Size(155, 23)
$chkAudioBufferOverride.Checked = $script:DefaultAudioBufferOverride
$settingsGroup.Controls.Add($chkAudioBufferOverride)
$toolTip.SetToolTip($chkAudioBufferOverride, 'Unchecked emits no buffer-time property. Checked explicitly appends buffer-time using the Buffer ms value.')

$chkAudioLatencyOverride = New-Object System.Windows.Forms.CheckBox
$chkAudioLatencyOverride.Text = 'Override latency-time'
$chkAudioLatencyOverride.Location = New-Object System.Drawing.Point(525, 648)
$chkAudioLatencyOverride.Size = New-Object System.Drawing.Size(155, 23)
$chkAudioLatencyOverride.Checked = $script:DefaultAudioLatencyOverride
$settingsGroup.Controls.Add($chkAudioLatencyOverride)
$toolTip.SetToolTip($chkAudioLatencyOverride, 'Unchecked emits no latency-time property. Checked explicitly appends latency-time using the Latency ms value.')

$lblAudioBufferMs = Add-Label $settingsGroup 'Buffer ms' 15 648 80
$numAudioBufferMs = New-Object System.Windows.Forms.NumericUpDown
$numAudioBufferMs.Location = New-Object System.Drawing.Point(95, 648)
$numAudioBufferMs.Size = New-Object System.Drawing.Size(75, 23)
$numAudioBufferMs.Minimum = 1
$numAudioBufferMs.Maximum = 1000
$numAudioBufferMs.Value = $script:DefaultAudioBufferMs
$settingsGroup.Controls.Add($numAudioBufferMs)
$toolTip.SetToolTip($numAudioBufferMs, 'WASAPI buffer-time in milliseconds. This value is emitted only while Override buffer-time is checked.')

$lblAudioLatencyMs = Add-Label $settingsGroup 'Latency ms' 195 648 80
$numAudioLatencyMs = New-Object System.Windows.Forms.NumericUpDown
$numAudioLatencyMs.Location = New-Object System.Drawing.Point(275, 648)
$numAudioLatencyMs.Size = New-Object System.Drawing.Size(75, 23)
$numAudioLatencyMs.Minimum = 1
$numAudioLatencyMs.Maximum = 1000
$numAudioLatencyMs.Value = $script:DefaultAudioLatencyMs
$settingsGroup.Controls.Add($numAudioLatencyMs)

$chkAudioSampleRateOverride = New-Object System.Windows.Forms.CheckBox
$chkAudioSampleRateOverride.Text = 'Override sample rate'
$chkAudioSampleRateOverride.Location = New-Object System.Drawing.Point(15, 694)
$chkAudioSampleRateOverride.Size = New-Object System.Drawing.Size(170, 23)
$chkAudioSampleRateOverride.Checked = $script:DefaultAudioSampleRateOverride
$settingsGroup.Controls.Add($chkAudioSampleRateOverride)
$toolTip.SetToolTip($chkAudioSampleRateOverride, 'Unchecked emits no rate field in raw-audio caps and leaves sample-rate negotiation to GStreamer. Checked forces the selected processing rate on desktop, microphone, audiomixer output, split audio, and recording audio paths.')

$lblAudioSampleRate = Add-Label $settingsGroup 'Rate Hz' 190 694 60
$numAudioSampleRate = New-Object System.Windows.Forms.NumericUpDown
$numAudioSampleRate.Location = New-Object System.Drawing.Point(250, 694)
$numAudioSampleRate.Size = New-Object System.Drawing.Size(100, 23)
$numAudioSampleRate.Minimum = 8000
$numAudioSampleRate.Maximum = 192000
$numAudioSampleRate.Increment = 100
$numAudioSampleRate.Value = $script:DefaultAudioSampleRate
$numAudioSampleRate.Enabled = $script:DefaultAudioSampleRateOverride
$settingsGroup.Controls.Add($numAudioSampleRate)
$toolTip.SetToolTip($numAudioSampleRate, 'Raw-audio processing rate in Hz. Opus accepts 8000, 12000, 16000, 24000, or 48000 Hz; other explicit values may be useful for non-Opus codec experiments and may intentionally fail with Opus.')
$toolTip.SetToolTip($numAudioLatencyMs, 'WASAPI latency-time in milliseconds. This value is emitted only while Override latency-time is checked.')

$null = Add-Label $settingsGroup 'Audio codec' 15 354 80
$cmbAudioCodec = New-Object System.Windows.Forms.ComboBox
$cmbAudioCodec.Location = New-Object System.Drawing.Point(95, 354)
$cmbAudioCodec.Size = New-Object System.Drawing.Size(210, 23)
$cmbAudioCodec.DropDownStyle = 'DropDownList'
$settingsGroup.Controls.Add($cmbAudioCodec)
$toolTip.SetToolTip($cmbAudioCodec, 'A compatible selection is remembered independently for each protocol.')

$lblAudioCodecStatus = New-Object System.Windows.Forms.Label
$lblAudioCodecStatus.Text = 'Protocol default'
$lblAudioCodecStatus.Location = New-Object System.Drawing.Point(315, 354)
$lblAudioCodecStatus.Size = New-Object System.Drawing.Size(245, 23)
$lblAudioCodecStatus.TextAlign = 'MiddleLeft'
$lblAudioCodecStatus.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($lblAudioCodecStatus)

$null = Add-Label $settingsGroup 'Audio kbps' 570 354 75
$numAudioBitrate = New-Object System.Windows.Forms.NumericUpDown
$numAudioBitrate.Location = New-Object System.Drawing.Point(645, 354)
$numAudioBitrate.Size = New-Object System.Drawing.Size(70, 23)
$numAudioBitrate.Minimum = 32
$numAudioBitrate.Maximum = 512
$numAudioBitrate.Increment = 16
$numAudioBitrate.Value = 128
$settingsGroup.Controls.Add($numAudioBitrate)

$cmbDirectWebRtcOpusMode = New-Object System.Windows.Forms.ComboBox
$cmbDirectWebRtcOpusMode.Location = New-Object System.Drawing.Point(15, 548)
$cmbDirectWebRtcOpusMode.Size = New-Object System.Drawing.Size(190, 23)
$cmbDirectWebRtcOpusMode.DropDownStyle = 'DropDownList'
$null = $cmbDirectWebRtcOpusMode.Items.AddRange([string[]]@('Explicit Opus encoder','Raw audio to webrtcsink'))
$cmbDirectWebRtcOpusMode.SelectedItem = $script:DefaultDirectWebRtcOpusMode
$settingsGroup.Controls.Add($cmbDirectWebRtcOpusMode)
$toolTip.SetToolTip($cmbDirectWebRtcOpusMode, 'Direct GST WebRTC audio path. Explicit Opus exposes frame-size/type/FEC/DTX. Raw audio hands S16LE to webrtcsink and lets it spawn its own internal encoder.')

$cmbDirectWebRtcOpusFrameMs = New-Object System.Windows.Forms.ComboBox
$cmbDirectWebRtcOpusFrameMs.Location = New-Object System.Drawing.Point(15, 548)
$cmbDirectWebRtcOpusFrameMs.Size = New-Object System.Drawing.Size(85, 23)
$cmbDirectWebRtcOpusFrameMs.DropDownStyle = 'DropDownList'
$null = $cmbDirectWebRtcOpusFrameMs.Items.AddRange([string[]]@('2.5','5','10','20','40','60'))
$cmbDirectWebRtcOpusFrameMs.SelectedItem = $script:DefaultDirectWebRtcOpusFrameMs
$settingsGroup.Controls.Add($cmbDirectWebRtcOpusFrameMs)
$toolTip.SetToolTip($cmbDirectWebRtcOpusFrameMs, 'opusenc frame-size for Direct GST WebRTC when Explicit Opus encoder is selected. Smaller frames reduce fixed audio encode delay but increase packet rate.')

$cmbDirectWebRtcOpusAudioType = New-Object System.Windows.Forms.ComboBox
$cmbDirectWebRtcOpusAudioType.Location = New-Object System.Drawing.Point(15, 548)
$cmbDirectWebRtcOpusAudioType.Size = New-Object System.Drawing.Size(170, 23)
$cmbDirectWebRtcOpusAudioType.DropDownStyle = 'DropDownList'
$null = $cmbDirectWebRtcOpusAudioType.Items.AddRange([string[]]@('restricted-lowdelay','voice','generic'))
$cmbDirectWebRtcOpusAudioType.SelectedItem = $script:DefaultDirectWebRtcOpusAudioType
$settingsGroup.Controls.Add($cmbDirectWebRtcOpusAudioType)
$toolTip.SetToolTip($cmbDirectWebRtcOpusAudioType, 'opusenc audio-type for Direct GST WebRTC explicit Opus encoding.')

$chkDirectWebRtcOpusFec = New-Object System.Windows.Forms.CheckBox
$chkDirectWebRtcOpusFec.Text = 'Opus FEC'
$chkDirectWebRtcOpusFec.Location = New-Object System.Drawing.Point(15, 548)
$chkDirectWebRtcOpusFec.Size = New-Object System.Drawing.Size(95, 23)
$chkDirectWebRtcOpusFec.Checked = $script:DefaultDirectWebRtcOpusFec
$settingsGroup.Controls.Add($chkDirectWebRtcOpusFec)
$toolTip.SetToolTip($chkDirectWebRtcOpusFec, 'opusenc inband-fec for Direct GST WebRTC. Keep off for lowest LAN latency unless testing packet loss recovery.')

$chkDirectWebRtcOpusDtx = New-Object System.Windows.Forms.CheckBox
$chkDirectWebRtcOpusDtx.Text = 'Opus DTX'
$chkDirectWebRtcOpusDtx.Location = New-Object System.Drawing.Point(15, 548)
$chkDirectWebRtcOpusDtx.Size = New-Object System.Drawing.Size(95, 23)
$chkDirectWebRtcOpusDtx.Checked = $script:DefaultDirectWebRtcOpusDtx
$settingsGroup.Controls.Add($chkDirectWebRtcOpusDtx)
$toolTip.SetToolTip($chkDirectWebRtcOpusDtx, 'opusenc dtx for Direct GST WebRTC. Usually off for desktop/game streaming so silence does not change receiver timing behavior.')

$audioNote = New-Object System.Windows.Forms.Label
$audioNote.Text = 'A/V test mode isolates desync: Video only removes audio; Muted audio clock keeps GstAudioSrcClock but sends silence. Normal uses WASAPI loopback/mic.'
$audioNote.Location = New-Object System.Drawing.Point(15, 392)
$audioNote.Size = New-Object System.Drawing.Size(700, 22)
$audioNote.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($audioNote)

$protocolNote = New-Object System.Windows.Forms.Label
$protocolNote.Text = 'Audio defaults: WHIP/SRT/RTSP use Opus; RTMP uses AAC. SRT uses PID 256/257, program 1, 2.9 ms mux sync.'
$protocolNote.Location = New-Object System.Drawing.Point(15, 418)
$protocolNote.Size = New-Object System.Drawing.Size(700, 22)
$protocolNote.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($protocolNote)

$latencyNote = New-Object System.Windows.Forms.Label
$latencyNote.Text = 'Low-latency defaults: B-frames 0, look-ahead off, AQ off, 1-second GOP, and leaky queues. Controls enable only where supported.'
$latencyNote.Location = New-Object System.Drawing.Point(15, 446)
$latencyNote.Size = New-Object System.Drawing.Size(700, 38)
$latencyNote.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($latencyNote)

$changesNote = New-Object System.Windows.Forms.Label
$changesNote.Text = 'Changes apply on the next Start or Restart Pipeline.'
$changesNote.Location = New-Object System.Drawing.Point(15, 492)
$changesNote.Size = New-Object System.Drawing.Size(700, 22)
$changesNote.ForeColor = [System.Drawing.Color]::DarkSlateBlue
$settingsGroup.Controls.Add($changesNote)

$chkStartMediaMtx = New-Object System.Windows.Forms.CheckBox
$chkStartMediaMtx.Text = 'Start/stop MediaMTX with stream'
$chkStartMediaMtx.Location = New-Object System.Drawing.Point(15, 546)
$chkStartMediaMtx.Size = New-Object System.Drawing.Size(220, 25)
$chkStartMediaMtx.Checked = $false
$settingsGroup.Controls.Add($chkStartMediaMtx)
$toolTip.SetToolTip(
    $chkStartMediaMtx,
    'Starts MediaMTX before GStreamer and stops it whenever the stream stops or restarts. Only the MediaMTX process started by this application is terminated.'
)

$txtMediaMtxPath = New-Object System.Windows.Forms.TextBox
$txtMediaMtxPath.Location = New-Object System.Drawing.Point(240, 546)
$txtMediaMtxPath.Size = New-Object System.Drawing.Size(400, 23)
$txtMediaMtxPath.Text = Find-MediaMtx
$settingsGroup.Controls.Add($txtMediaMtxPath)
$toolTip.SetToolTip(
    $txtMediaMtxPath,
    'Path to mediamtx.exe. It is launched hidden with its working directory set to the executable folder so mediamtx.yml beside it is discovered normally.'
)

$btnBrowseMediaMtx = New-Object System.Windows.Forms.Button
$btnBrowseMediaMtx.Text = 'Browse...'
$btnBrowseMediaMtx.Location = New-Object System.Drawing.Point(650, 544)
$btnBrowseMediaMtx.Size = New-Object System.Drawing.Size(68, 27)
$settingsGroup.Controls.Add($btnBrowseMediaMtx)


$defaultRecordingRoot = [Environment]::GetFolderPath('MyVideos')
if ([string]::IsNullOrWhiteSpace($defaultRecordingRoot)) {
    $defaultRecordingRoot = [Environment]::GetFolderPath('Desktop')
}
if ([string]::IsNullOrWhiteSpace($defaultRecordingRoot)) {
    $defaultRecordingRoot = $env:USERPROFILE
}
$defaultRecordingDirectory = Join-Path $defaultRecordingRoot 'GStreamer Glass'

$chkRecordingEnabled = New-Object System.Windows.Forms.CheckBox
$chkRecordingEnabled.Text = 'Enable recording'
$chkRecordingEnabled.Location = New-Object System.Drawing.Point(15, 520)
$chkRecordingEnabled.Size = New-Object System.Drawing.Size(160, 23)
$chkRecordingEnabled.Checked = $false
$settingsGroup.Controls.Add($chkRecordingEnabled)
$toolTip.SetToolTip($chkRecordingEnabled, 'Records a local file from the same capture source while the selected transport keeps streaming.')

$txtRecordingDirectory = New-Object System.Windows.Forms.TextBox
$txtRecordingDirectory.Location = New-Object System.Drawing.Point(15, 548)
$txtRecordingDirectory.Size = New-Object System.Drawing.Size(500, 23)
$txtRecordingDirectory.Text = $defaultRecordingDirectory
$settingsGroup.Controls.Add($txtRecordingDirectory)
$toolTip.SetToolTip($txtRecordingDirectory, 'Folder where recording files are written. The folder is created on Start if needed.')

$btnBrowseRecordingDirectory = New-Object System.Windows.Forms.Button
$btnBrowseRecordingDirectory.Text = 'Browse...'
$btnBrowseRecordingDirectory.Location = New-Object System.Drawing.Point(525, 546)
$btnBrowseRecordingDirectory.Size = New-Object System.Drawing.Size(90, 27)
$settingsGroup.Controls.Add($btnBrowseRecordingDirectory)

$txtRecordingTemplate = New-Object System.Windows.Forms.TextBox
$txtRecordingTemplate.Location = New-Object System.Drawing.Point(15, 548)
$txtRecordingTemplate.Size = New-Object System.Drawing.Size(500, 23)
$txtRecordingTemplate.Text = 'Glass-{yyyyMMdd-HHmmss}-{protocol}-{width}x{height}-{fps}fps.mkv'
$settingsGroup.Controls.Add($txtRecordingTemplate)
$toolTip.SetToolTip($txtRecordingTemplate, 'File name template. Supports {yyyyMMdd-HHmmss}, {date}, {time}, {protocol}, {encoder}, {width}, {height}, and {fps}.')

$cmbRecordingEncoder = New-Object System.Windows.Forms.ComboBox
$cmbRecordingEncoder.Location = New-Object System.Drawing.Point(15, 548)
$cmbRecordingEncoder.Size = New-Object System.Drawing.Size(360, 23)
$cmbRecordingEncoder.DropDownStyle = 'DropDownList'
$null = $cmbRecordingEncoder.Items.AddRange([string[]]($script:EncoderCatalog.Keys))
$cmbRecordingEncoder.SelectedItem = $script:DefaultEncoderName
$settingsGroup.Controls.Add($cmbRecordingEncoder)
$toolTip.SetToolTip($cmbRecordingEncoder, 'Recording uses its own encoder and bitrate so the stream can stay low-latency while the file gets a different quality target.')

$lblRecordingStatus = New-Object System.Windows.Forms.Label
$lblRecordingStatus.Text = 'Recording disabled'
$lblRecordingStatus.Location = New-Object System.Drawing.Point(390, 548)
$lblRecordingStatus.Size = New-Object System.Drawing.Size(325, 23)
$lblRecordingStatus.TextAlign = 'MiddleLeft'
$lblRecordingStatus.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($lblRecordingStatus)

$cmbRecordingPreset = New-Object System.Windows.Forms.ComboBox
$cmbRecordingPreset.Location = New-Object System.Drawing.Point(15, 548)
$cmbRecordingPreset.Size = New-Object System.Drawing.Size(100, 23)
$cmbRecordingPreset.DropDownStyle = 'DropDownList'
$null = $cmbRecordingPreset.Items.AddRange(@('p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7'))
$cmbRecordingPreset.SelectedItem = 'p5'
$settingsGroup.Controls.Add($cmbRecordingPreset)

$cmbRecordingProfile = New-Object System.Windows.Forms.ComboBox
$cmbRecordingProfile.Location = New-Object System.Drawing.Point(15, 548)
$cmbRecordingProfile.Size = New-Object System.Drawing.Size(150, 23)
$cmbRecordingProfile.DropDownStyle = 'DropDownList'
$null = $cmbRecordingProfile.Items.AddRange(@('constrained-baseline', 'baseline', 'main', 'high'))
$cmbRecordingProfile.SelectedItem = 'high'
$settingsGroup.Controls.Add($cmbRecordingProfile)

$numRecordingWidth = New-Object System.Windows.Forms.NumericUpDown
$numRecordingWidth.Location = New-Object System.Drawing.Point(15, 548)
$numRecordingWidth.Size = New-Object System.Drawing.Size(90, 23)
$numRecordingWidth.Minimum = 320
$numRecordingWidth.Maximum = 7680
$numRecordingWidth.Increment = 16
$numRecordingWidth.Value = 1920
$settingsGroup.Controls.Add($numRecordingWidth)

$numRecordingHeight = New-Object System.Windows.Forms.NumericUpDown
$numRecordingHeight.Location = New-Object System.Drawing.Point(15, 548)
$numRecordingHeight.Size = New-Object System.Drawing.Size(90, 23)
$numRecordingHeight.Minimum = 240
$numRecordingHeight.Maximum = 4320
$numRecordingHeight.Increment = 16
$numRecordingHeight.Value = 1080
$settingsGroup.Controls.Add($numRecordingHeight)

$numRecordingFps = New-Object System.Windows.Forms.NumericUpDown
$numRecordingFps.Location = New-Object System.Drawing.Point(15, 548)
$numRecordingFps.Size = New-Object System.Drawing.Size(80, 23)
$numRecordingFps.Minimum = 1
$numRecordingFps.Maximum = 240
$numRecordingFps.Value = 60
$settingsGroup.Controls.Add($numRecordingFps)

$numRecordingVideoBitrate = New-Object System.Windows.Forms.NumericUpDown
$numRecordingVideoBitrate.Location = New-Object System.Drawing.Point(15, 548)
$numRecordingVideoBitrate.Size = New-Object System.Drawing.Size(110, 23)
$numRecordingVideoBitrate.Minimum = 250
$numRecordingVideoBitrate.Maximum = 200000
$numRecordingVideoBitrate.Increment = 500
$numRecordingVideoBitrate.Value = 25000
$settingsGroup.Controls.Add($numRecordingVideoBitrate)


$cmbRecordingRateControl = New-Object System.Windows.Forms.ComboBox
$cmbRecordingRateControl.Location = New-Object System.Drawing.Point(15, 548)
$cmbRecordingRateControl.Size = New-Object System.Drawing.Size(95, 23)
$cmbRecordingRateControl.DropDownStyle = 'DropDownList'
$null = $cmbRecordingRateControl.Items.AddRange([string[]]$script:RateControlModes)
$cmbRecordingRateControl.SelectedItem = 'constqp'
$settingsGroup.Controls.Add($cmbRecordingRateControl)
$toolTip.SetToolTip($cmbRecordingRateControl, 'Recording rate control. constqp is the OBS-style quality-first default; CBR/VBR remain available.')

$numRecordingMaxVideoBitrate = New-Object System.Windows.Forms.NumericUpDown
$numRecordingMaxVideoBitrate.Location = New-Object System.Drawing.Point(15, 548)
$numRecordingMaxVideoBitrate.Size = New-Object System.Drawing.Size(100, 23)
$numRecordingMaxVideoBitrate.Minimum = 0
$numRecordingMaxVideoBitrate.Maximum = 500000
$numRecordingMaxVideoBitrate.Increment = 500
$numRecordingMaxVideoBitrate.Value = 0
$settingsGroup.Controls.Add($numRecordingMaxVideoBitrate)
$toolTip.SetToolTip($numRecordingMaxVideoBitrate, 'Recording maximum bitrate for VBR where supported. 0 uses encoder default.')

$numRecordingConstantQp = New-Object System.Windows.Forms.NumericUpDown
$numRecordingConstantQp.Location = New-Object System.Drawing.Point(15, 548)
$numRecordingConstantQp.Size = New-Object System.Drawing.Size(70, 23)
$numRecordingConstantQp.Minimum = 0
$numRecordingConstantQp.Maximum = 51
$numRecordingConstantQp.Value = 20
$settingsGroup.Controls.Add($numRecordingConstantQp)
$toolTip.SetToolTip($numRecordingConstantQp, 'Recording CQ/QP. Lower means higher quality and larger files. 18-23 is usually the useful range for H.264/H.265 testing.')

$numRecordingGopSeconds = New-Object System.Windows.Forms.NumericUpDown
$numRecordingGopSeconds.Location = New-Object System.Drawing.Point(15, 548)
$numRecordingGopSeconds.Size = New-Object System.Drawing.Size(80, 23)
$numRecordingGopSeconds.Minimum = 1
$numRecordingGopSeconds.Maximum = 10
$numRecordingGopSeconds.Value = 2
$settingsGroup.Controls.Add($numRecordingGopSeconds)

$numRecordingBFrames = New-Object System.Windows.Forms.NumericUpDown
$numRecordingBFrames.Location = New-Object System.Drawing.Point(15, 548)
$numRecordingBFrames.Size = New-Object System.Drawing.Size(80, 23)
$numRecordingBFrames.Minimum = 0
$numRecordingBFrames.Maximum = 4
$numRecordingBFrames.Value = 2
$settingsGroup.Controls.Add($numRecordingBFrames)
$toolTip.SetToolTip($numRecordingBFrames, 'Recording can use B-frames for quality because this branch is not the live WebRTC path.')


$cmbRecordingTune = New-Object System.Windows.Forms.ComboBox
$cmbRecordingTune.Location = New-Object System.Drawing.Point(15, 548)
$cmbRecordingTune.Size = New-Object System.Drawing.Size(165, 23)
$cmbRecordingTune.DropDownStyle = 'DropDownList'
$null = $cmbRecordingTune.Items.AddRange([string[]]$script:NvencTuneModes)
$cmbRecordingTune.SelectedItem = 'high-quality'
$settingsGroup.Controls.Add($cmbRecordingTune)
$toolTip.SetToolTip($cmbRecordingTune, 'NVENC tune for recording. high-quality is the default; use low-latency/ultra-low-latency only when recording must stay realtime above quality.')

$cmbRecordingMultipass = New-Object System.Windows.Forms.ComboBox
$cmbRecordingMultipass.Location = New-Object System.Drawing.Point(15, 548)
$cmbRecordingMultipass.Size = New-Object System.Drawing.Size(150, 23)
$cmbRecordingMultipass.DropDownStyle = 'DropDownList'
$null = $cmbRecordingMultipass.Items.AddRange([string[]]$script:NvencMultipassModes)
$cmbRecordingMultipass.SelectedItem = 'two-pass-quarter'
$settingsGroup.Controls.Add($cmbRecordingMultipass)
$toolTip.SetToolTip($cmbRecordingMultipass, 'NVENC multipass for recording. two-pass-quarter mirrors OBS-style quality without full two-pass cost.')

$chkRecordingLookAhead = New-Object System.Windows.Forms.CheckBox
$chkRecordingLookAhead.Text = 'Look-ahead'
$chkRecordingLookAhead.Location = New-Object System.Drawing.Point(15, 548)
$chkRecordingLookAhead.Size = New-Object System.Drawing.Size(105, 23)
$chkRecordingLookAhead.Checked = $false
$settingsGroup.Controls.Add($chkRecordingLookAhead)
$toolTip.SetToolTip($chkRecordingLookAhead, 'Recording look-ahead where supported. Adds frame buffering but can improve B-frame decisions/quality.')

$numRecordingLookAheadFrames = New-Object System.Windows.Forms.NumericUpDown
$numRecordingLookAheadFrames.Location = New-Object System.Drawing.Point(15, 548)
$numRecordingLookAheadFrames.Size = New-Object System.Drawing.Size(70, 23)
$numRecordingLookAheadFrames.Minimum = 1
$numRecordingLookAheadFrames.Maximum = 64
$numRecordingLookAheadFrames.Value = 20
$numRecordingLookAheadFrames.Enabled = $false
$settingsGroup.Controls.Add($numRecordingLookAheadFrames)

$chkRecordingSpatialAq = New-Object System.Windows.Forms.CheckBox
$chkRecordingSpatialAq.Text = 'Spatial AQ'
$chkRecordingSpatialAq.Location = New-Object System.Drawing.Point(15, 548)
$chkRecordingSpatialAq.Size = New-Object System.Drawing.Size(90, 23)
$chkRecordingSpatialAq.Checked = $true
$settingsGroup.Controls.Add($chkRecordingSpatialAq)

$chkRecordingTemporalAq = New-Object System.Windows.Forms.CheckBox
$chkRecordingTemporalAq.Text = 'Temporal AQ'
$chkRecordingTemporalAq.Location = New-Object System.Drawing.Point(15, 548)
$chkRecordingTemporalAq.Size = New-Object System.Drawing.Size(105, 23)
$chkRecordingTemporalAq.Checked = $true
$settingsGroup.Controls.Add($chkRecordingTemporalAq)

$numRecordingAqStrength = New-Object System.Windows.Forms.NumericUpDown
$numRecordingAqStrength.Location = New-Object System.Drawing.Point(15, 548)
$numRecordingAqStrength.Size = New-Object System.Drawing.Size(70, 23)
$numRecordingAqStrength.Minimum = 1
$numRecordingAqStrength.Maximum = 15
$numRecordingAqStrength.Value = 8
$settingsGroup.Controls.Add($numRecordingAqStrength)

$numRecordingVbvBuffer = New-Object System.Windows.Forms.NumericUpDown
$numRecordingVbvBuffer.Location = New-Object System.Drawing.Point(15, 548)
$numRecordingVbvBuffer.Size = New-Object System.Drawing.Size(100, 23)
$numRecordingVbvBuffer.Minimum = 0
$numRecordingVbvBuffer.Maximum = 1000000
$numRecordingVbvBuffer.Increment = 500
$numRecordingVbvBuffer.Value = 0
$settingsGroup.Controls.Add($numRecordingVbvBuffer)
$toolTip.SetToolTip($numRecordingVbvBuffer, 'NVENC VBV/HRD buffer size in kbits. 0 uses encoder default.')

$txtRecordingCustomEncoderOptions = New-Object System.Windows.Forms.TextBox
$txtRecordingCustomEncoderOptions.Location = New-Object System.Drawing.Point(15, 548)
$txtRecordingCustomEncoderOptions.Size = New-Object System.Drawing.Size(520, 23)
$txtRecordingCustomEncoderOptions.Text = ''
$settingsGroup.Controls.Add($txtRecordingCustomEncoderOptions)
$toolTip.SetToolTip($txtRecordingCustomEncoderOptions, 'Raw options appended directly after the selected recording encoder element. Useful for AMD/Intel/MF/software knobs while we validate mappings.')

$chkRecordingDesktopAudio = New-Object System.Windows.Forms.CheckBox
$chkRecordingDesktopAudio.Text = 'Record desktop audio'
$chkRecordingDesktopAudio.Location = New-Object System.Drawing.Point(15, 548)
$chkRecordingDesktopAudio.Size = New-Object System.Drawing.Size(170, 23)
$chkRecordingDesktopAudio.Checked = $true
$settingsGroup.Controls.Add($chkRecordingDesktopAudio)

$chkRecordingMic = New-Object System.Windows.Forms.CheckBox
$chkRecordingMic.Text = 'Record microphone'
$chkRecordingMic.Location = New-Object System.Drawing.Point(15, 548)
$chkRecordingMic.Size = New-Object System.Drawing.Size(170, 23)
$chkRecordingMic.Checked = $false
$settingsGroup.Controls.Add($chkRecordingMic)

$numRecordingAudioBitrate = New-Object System.Windows.Forms.NumericUpDown
$numRecordingAudioBitrate.Location = New-Object System.Drawing.Point(15, 548)
$numRecordingAudioBitrate.Size = New-Object System.Drawing.Size(100, 23)
$numRecordingAudioBitrate.Minimum = 32
$numRecordingAudioBitrate.Maximum = 512
$numRecordingAudioBitrate.Increment = 16
$numRecordingAudioBitrate.Value = 192
$settingsGroup.Controls.Add($numRecordingAudioBitrate)

$previewGroup = New-Object System.Windows.Forms.GroupBox
$previewGroup.Text = 'Local Preview (experimental)'
$previewGroup.Location = New-Object System.Drawing.Point(755, 10)
$previewGroup.Size = New-Object System.Drawing.Size(440, 586)
$previewGroup.Anchor = 'Top,Right'
$form.Controls.Add($previewGroup)

$previewPanel = New-Object System.Windows.Forms.Panel
$previewPanel.Location = New-Object System.Drawing.Point(12, 24)
$previewPanel.Size = New-Object System.Drawing.Size(416, 544)
$previewPanel.BackColor = [System.Drawing.Color]::Black
$previewPanel.Anchor = 'Top,Bottom,Left,Right'
$previewGroup.Controls.Add($previewPanel)

$previewPlaceholder = New-Object System.Windows.Forms.Label
$previewPlaceholder.Text = 'Preview disabled for this pipeline'
$previewPlaceholder.ForeColor = [System.Drawing.Color]::LightGray
$previewPlaceholder.BackColor = [System.Drawing.Color]::Black
$previewPlaceholder.TextAlign = 'MiddleCenter'
$previewPlaceholder.Dock = 'Fill'
$previewPanel.Controls.Add($previewPlaceholder)

$lowerTabs = New-Object System.Windows.Forms.TabControl
$lowerTabs.Location = New-Object System.Drawing.Point(10, 650)
$lowerTabs.Size = New-Object System.Drawing.Size(1185, 396)
$lowerTabs.Anchor = 'Top,Bottom,Left,Right'
$form.Controls.Add($lowerTabs)

$tabLog = New-Object System.Windows.Forms.TabPage
$tabLog.Text = 'Output Log'
$tabLog.Padding = New-Object System.Windows.Forms.Padding(6)
$null = $lowerTabs.TabPages.Add($tabLog)

$tabCommand = New-Object System.Windows.Forms.TabPage
$tabCommand.Text = 'Generated Command'
$tabCommand.Padding = New-Object System.Windows.Forms.Padding(6)
$null = $lowerTabs.TabPages.Add($tabCommand)

# Appends no longer force a scroll while the log tab is hidden, so catch the
# tail up whenever the log becomes visible again.
$lowerTabs.Add_SelectedIndexChanged({
    if ($lowerTabs.SelectedTab -eq $tabLog) {
        Scroll-LogToBottom
    }
})

$txtCommand = New-Object System.Windows.Forms.TextBox
$txtCommand.Multiline = $true
$txtCommand.ScrollBars = 'Vertical'
$txtCommand.WordWrap = $true
$txtCommand.ReadOnly = $true
$txtCommand.HideSelection = $false
$txtCommand.AcceptsReturn = $false
$txtCommand.AcceptsTab = $false
$txtCommand.Font = New-Object System.Drawing.Font('Consolas', 9)
$txtCommand.Dock = 'Fill'
$tabCommand.Controls.Add($txtCommand)

$lowerTabs.SelectedTab = $tabLog

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = 'Start Stream'
$btnStart.Location = New-Object System.Drawing.Point(10, 606)
$btnStart.Size = New-Object System.Drawing.Size(120, 34)
$btnStart.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnStart)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = 'Stop'
$btnStop.Location = New-Object System.Drawing.Point(140, 606)
$btnStop.Size = New-Object System.Drawing.Size(90, 34)
$btnStop.Enabled = $false
$form.Controls.Add($btnStop)

$btnRestart = New-Object System.Windows.Forms.Button
$btnRestart.Text = 'Restart Pipeline'
$btnRestart.Location = New-Object System.Drawing.Point(240, 606)
$btnRestart.Size = New-Object System.Drawing.Size(125, 34)
$btnRestart.Enabled = $false
$form.Controls.Add($btnRestart)

$btnCopyCommand = New-Object System.Windows.Forms.Button
$btnCopyCommand.Text = 'Copy Command'
$btnCopyCommand.Location = New-Object System.Drawing.Point(375, 606)
$btnCopyCommand.Size = New-Object System.Drawing.Size(115, 34)
$form.Controls.Add($btnCopyCommand)

$btnClearLog = New-Object System.Windows.Forms.Button
$btnClearLog.Text = 'Clear Log'
$btnClearLog.Location = New-Object System.Drawing.Point(500, 606)
$btnClearLog.Size = New-Object System.Drawing.Size(90, 34)
$form.Controls.Add($btnClearLog)

$btnOpenLogs = New-Object System.Windows.Forms.Button
$btnOpenLogs.Text = 'Open Logs'
$btnOpenLogs.Location = New-Object System.Drawing.Point(600, 606)
$btnOpenLogs.Size = New-Object System.Drawing.Size(105, 34)
$form.Controls.Add($btnOpenLogs)
$toolTip.SetToolTip(
    $btnOpenLogs,
    "Opens the optional per-run process log folder. Disk process logs are disabled by default."
)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = 'Stopped'
$statusLabel.Location = New-Object System.Drawing.Point(720, 611)
$statusLabel.Size = New-Object System.Drawing.Size(475, 25)
$statusLabel.TextAlign = 'MiddleRight'
$statusLabel.Anchor = 'Top,Right'
$statusLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($statusLabel)

$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip

$trayShowItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trayShowItem.Text = 'Show GStreamer Glass'
$trayShowItem.Font = New-Object System.Drawing.Font($trayShowItem.Font, [System.Drawing.FontStyle]::Bold)
$null = $trayMenu.Items.Add($trayShowItem)

$null = $trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$trayStartItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trayStartItem.Text = 'Start Stream'
$null = $trayMenu.Items.Add($trayStartItem)

$trayStopItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trayStopItem.Text = 'Stop Stream'
$null = $trayMenu.Items.Add($trayStopItem)

$trayRestartItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trayRestartItem.Text = 'Restart Pipeline'
$null = $trayMenu.Items.Add($trayRestartItem)

$null = $trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$trayExitItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trayExitItem.Text = 'Exit'
$null = $trayMenu.Items.Add($trayExitItem)

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = $script:AppIcon
$notifyIcon.Text = $script:AppName
$notifyIcon.ContextMenuStrip = $trayMenu
$notifyIcon.Visible = $true

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ScrollBars = 'Both'
$txtLog.WordWrap = $false
$txtLog.ReadOnly = $true
$txtLog.HideSelection = $false
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$txtLog.Dock = 'Fill'
$tabLog.Controls.Add($txtLog)

# Experimental scene controls. Scenes remain off by default, preserving the
# original single-source capture path byte-for-byte until explicitly enabled.
$chkSceneEnabled = New-Object System.Windows.Forms.CheckBox
$chkSceneEnabled.Text = 'Enable experimental scene composition'
$chkSceneEnabled.AutoSize = $true

$cmbScenePreset = New-Object System.Windows.Forms.ComboBox
$cmbScenePreset.DropDownStyle = 'DropDownList'
$null = $cmbScenePreset.Items.AddRange(@('Desktop + webcam', 'Desktop only', 'Webcam only'))
$cmbScenePreset.SelectedItem = 'Desktop + webcam'

$cmbSceneCompositor = New-Object System.Windows.Forms.ComboBox
$cmbSceneCompositor.DropDownStyle = 'DropDownList'
$null = $cmbSceneCompositor.Items.AddRange(@('D3D11 GPU (recommended)', 'CPU compatibility'))
$cmbSceneCompositor.SelectedIndex = 0

$cmbWebcamDevice = New-Object System.Windows.Forms.ComboBox
$cmbWebcamDevice.DropDownStyle = 'DropDownList'
$null = $cmbWebcamDevice.Items.Add('0: Default camera')
$cmbWebcamDevice.SelectedIndex = 0

$btnRefreshWebcams = New-Object System.Windows.Forms.Button
$btnRefreshWebcams.Text = 'Refresh cameras'

$btnRedrawScenePreview = New-Object System.Windows.Forms.Button
$btnRedrawScenePreview.Text = 'Redraw preview'
$toolTip.SetToolTip($btnRedrawScenePreview, 'Refreshes the embedded scene preview surface without restarting the GStreamer pipeline.')

$chkDynamicScenePreviews = New-Object System.Windows.Forms.CheckBox
$chkDynamicScenePreviews.Text = 'Dynamic previews'
$chkDynamicScenePreviews.AutoSize = $true
$chkDynamicScenePreviews.Checked = $false
$toolTip.SetToolTip($chkDynamicScenePreviews, 'Runs the real scene compositor in-process so placement, size, opacity, and z-order update live without restarting.')

$chkLiveSceneEditing = New-Object System.Windows.Forms.CheckBox
$chkLiveSceneEditing.Text = 'Edit scene while live (experimental)'
$chkLiveSceneEditing.AutoSize = $true
$chkLiveSceneEditing.Checked = $false
$toolTip.SetToolTip($chkLiveSceneEditing, 'Explicit opt-in. Available only with Dynamic previews. Runs compatible single-pipeline streams in a controlled worker process so placement, size, and opacity change on the actual broadcast without restarting. Stop/Restart terminates that worker exactly like the legacy launcher.')

$chkStandardPreviewOffSceneTab = New-Object System.Windows.Forms.CheckBox
$chkStandardPreviewOffSceneTab.Text = 'Standard preview off Scenes'
$chkStandardPreviewOffSceneTab.AutoSize = $true
$chkStandardPreviewOffSceneTab.Checked = $true
$toolTip.SetToolTip($chkStandardPreviewOffSceneTab, 'When Dynamic previews is enabled, switch back to the normal composed preview when leaving the Scenes tab.')

$cmbWebcamLayout = New-Object System.Windows.Forms.ComboBox
$cmbWebcamLayout.DropDownStyle = 'DropDownList'
$null = $cmbWebcamLayout.Items.AddRange(@('Bottom right', 'Bottom left', 'Top right', 'Top left', 'Custom'))
$cmbWebcamLayout.SelectedItem = 'Bottom right'

function New-SceneNumeric {
    param([int]$Minimum, [int]$Maximum, [int]$Value, [int]$Increment = 1)
    $control = New-Object System.Windows.Forms.NumericUpDown
    $control.Minimum = $Minimum
    $control.Maximum = $Maximum
    $control.Value = $Value
    $control.Increment = $Increment
    return $control
}

$numWebcamWidth = New-SceneNumeric 64 3840 480 16
$numWebcamHeight = New-SceneNumeric 64 2160 270 16
$numWebcamX = New-SceneNumeric 0 7680 1420 10
$numWebcamY = New-SceneNumeric 0 4320 790 10
$numWebcamFps = New-SceneNumeric 1 240 30 1
$numWebcamOpacity = New-SceneNumeric 0 100 100 5
$numWebcamBorder = New-SceneNumeric 0 64 0 1

# Scene input queue controls. These replace the old hidden fixed scene queue
# values. 0 ms is honest: it emits max-size-time=0 and disables the time limit.
$numSceneInputQueueBuffers = New-SceneNumeric 1 64 $script:DefaultSceneInputQueueBuffers 1
$numSceneInputQueueCapMs = New-SceneNumeric 0 5000 $script:DefaultSceneInputQueueCapMs 5
$toolTip.SetToolTip($numSceneInputQueueBuffers, 'Queue depth applied independently to the desktop and webcam inputs immediately before the compositor.')
$toolTip.SetToolTip($numSceneInputQueueCapMs, 'Scene input queue time cap in milliseconds. 0 emits max-size-time=0; no hidden fallback is substituted.')

$chkWebcamMirror = New-Object System.Windows.Forms.CheckBox
$chkWebcamMirror.Text = 'Mirror webcam'
$chkWebcamMirror.AutoSize = $true

$chkWebcamAspectLock = New-Object System.Windows.Forms.CheckBox
$chkWebcamAspectLock.Text = 'Lock aspect ratio'
$chkWebcamAspectLock.AutoSize = $true
$chkWebcamAspectLock.Checked = $true
$toolTip.SetToolTip($chkWebcamAspectLock, 'Keeps webcam width and height coupled while resizing in the scene editor or changing geometry values.')

$lblSceneStatus = New-Object System.Windows.Forms.Label
$lblSceneStatus.Text = 'Scene composition is disabled; the existing capture pipeline is unchanged.'
$lblSceneStatus.AutoSize = $true

$txtScenePipeline = New-Object System.Windows.Forms.TextBox
$txtScenePipeline.Multiline = $true
$txtScenePipeline.ReadOnly = $true
$txtScenePipeline.ScrollBars = 'Both'
$txtScenePipeline.WordWrap = $false
$txtScenePipeline.Height = 110

# Visual scene editor. The canvas is a scaled representation of the encoded
# output; moving/resizing the webcam layer writes directly to the compositor
# X/Y/width/height controls used by Build-SceneCaptureChain.
$script:UpdatingSceneEditor = $false
$script:ScenePointerActive = $false
$script:ScenePointerMode = 'Move'
$script:ScenePointerStart = [System.Drawing.Point]::Empty
$script:SceneElementStartBounds = [System.Drawing.Rectangle]::Empty
$script:SceneSourceDragActive = $false
$script:WebcamAspectRatio = [double]$numWebcamWidth.Value / [double]$numWebcamHeight.Value

$sceneSourcePalette = New-Object System.Windows.Forms.FlowLayoutPanel
$sceneSourcePalette.Name = 'SceneSourcePalette'
$sceneSourcePalette.FlowDirection = 'LeftToRight'
$sceneSourcePalette.WrapContents = $false
$sceneSourcePalette.AutoSize = $false
$sceneSourcePalette.Height = 42
$sceneSourcePalette.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0F172A')
$sceneSourcePalette.Padding = New-Object System.Windows.Forms.Padding(6)

$lblDesktopSource = New-Object System.Windows.Forms.Label
$lblDesktopSource.Text = '[box] Desktop (background)'
$lblDesktopSource.AutoSize = $false
$lblDesktopSource.Size = New-Object System.Drawing.Size(190, 28)
$lblDesktopSource.TextAlign = 'MiddleCenter'
$lblDesktopSource.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#1E293B')
$lblDesktopSource.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$sceneSourcePalette.Controls.Add($lblDesktopSource)

$lblWebcamSource = New-Object System.Windows.Forms.Label
$lblWebcamSource.Text = '[box] Webcam - drag to canvas'
$lblWebcamSource.AutoSize = $false
$lblWebcamSource.Size = New-Object System.Drawing.Size(210, 28)
$lblWebcamSource.TextAlign = 'MiddleCenter'
$lblWebcamSource.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#17345C')
$lblWebcamSource.ForeColor = [System.Drawing.Color]::White
$lblWebcamSource.Cursor = [System.Windows.Forms.Cursors]::Hand
$sceneSourcePalette.Controls.Add($lblWebcamSource)

$sceneEditorCanvas = New-Object System.Windows.Forms.Panel
$sceneEditorCanvas.Name = 'SceneEditorCanvas'
$sceneEditorCanvas.Size = New-Object System.Drawing.Size(550, 309)
$sceneEditorCanvas.MinimumSize = New-Object System.Drawing.Size(420, 236)
$sceneEditorCanvas.BackColor = [System.Drawing.Color]::Black
$sceneEditorCanvas.BorderStyle = 'FixedSingle'
# Do not use WinForms AllowDrop/DoDragDrop here. Those APIs invoke OLE and throw
# when the PS2EXE/PowerShell host runs MTA. The editor uses control capture and
# screen-coordinate hit testing below, which works in both STA and MTA hosts.

$lblSceneDesktop = New-Object System.Windows.Forms.Label
$lblSceneDesktop.Dock = 'Fill'
$lblSceneDesktop.Text = "DESKTOP BACKGROUND`r`n1920 x 1080"
$lblSceneDesktop.TextAlign = 'MiddleCenter'
$lblSceneDesktop.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
$lblSceneDesktop.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#050A12')
$sceneEditorCanvas.Controls.Add($lblSceneDesktop)

$sceneDesktopPreviewPanel = New-Object System.Windows.Forms.Panel
$sceneDesktopPreviewPanel.Name = 'SceneDesktopPreviewPanel'
$sceneDesktopPreviewPanel.Dock = 'Fill'
$sceneDesktopPreviewPanel.BackColor = [System.Drawing.Color]::Black
$sceneDesktopPreviewPanel.Visible = $false
$sceneEditorCanvas.Controls.Add($sceneDesktopPreviewPanel)

$sceneWebcamElement = New-Object System.Windows.Forms.Panel
$sceneWebcamElement.Name = 'SceneWebcamElement'
$sceneWebcamElement.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#17345C')
$sceneWebcamElement.BorderStyle = 'FixedSingle'
$sceneWebcamElement.Cursor = [System.Windows.Forms.Cursors]::SizeAll
$sceneEditorCanvas.Controls.Add($sceneWebcamElement)

$lblSceneWebcam = New-Object System.Windows.Forms.Label
$lblSceneWebcam.Dock = 'Top'
$lblSceneWebcam.Height = 24
$lblSceneWebcam.Text = 'WEBCAM - drag to move'
$lblSceneWebcam.TextAlign = 'MiddleCenter'
$lblSceneWebcam.ForeColor = [System.Drawing.Color]::White
$lblSceneWebcam.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#17345C')
$lblSceneWebcam.Cursor = [System.Windows.Forms.Cursors]::SizeAll
$sceneWebcamElement.Controls.Add($lblSceneWebcam)

$sceneWebcamPreviewPanel = New-Object System.Windows.Forms.Panel
$sceneWebcamPreviewPanel.Name = 'SceneWebcamPreviewPanel'
$sceneWebcamPreviewPanel.Dock = 'Fill'
$sceneWebcamPreviewPanel.BackColor = [System.Drawing.Color]::Black
$sceneWebcamPreviewPanel.Visible = $false
$sceneWebcamElement.Controls.Add($sceneWebcamPreviewPanel)

$sceneResizeHandle = New-Object System.Windows.Forms.Panel
$sceneResizeHandle.Name = 'SceneResizeHandle'
$sceneResizeHandle.Size = New-Object System.Drawing.Size(14, 14)
$sceneResizeHandle.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#60A5FA')
$sceneResizeHandle.Cursor = [System.Windows.Forms.Cursors]::SizeNWSE
$sceneWebcamElement.Controls.Add($sceneResizeHandle)

$lblSceneEditorHint = New-Object System.Windows.Forms.Label
$lblSceneEditorHint.Text = 'Drag Webcam from Sources onto the canvas. Drag the webcam header to move; drag its blue corner to resize.'
$lblSceneEditorHint.AutoSize = $true

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

function Sync-ControlledScenePreviewProperties {
    if (-not (Test-ControlledSceneMutationActive)) { return }

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
    if (-not (Test-ControlledSceneMutationActive)) { return }

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

$scenePointerDown = {
    param($sender, $e)
    if (-not $script:SceneWorkspaceActive) { return }
    if (-not $chkSceneEnabled.Checked -or $e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $script:ScenePointerActive = $true
    $script:ScenePointerStart = [System.Windows.Forms.Cursor]::Position
    $script:SceneElementStartBounds = $sceneWebcamElement.Bounds
    $local = $sceneWebcamElement.PointToClient([System.Windows.Forms.Cursor]::Position)
    $script:ScenePointerMode = if ($local.X -ge ($sceneWebcamElement.Width - 18) -and $local.Y -ge ($sceneWebcamElement.Height - 18)) { 'Resize' } else { 'Move' }
    $sceneWebcamElement.Capture = $true
}

$scenePointerMove = {
    param($sender, $e)
    if (-not $script:ScenePointerActive) { return }
    $cursor = [System.Windows.Forms.Cursor]::Position
    $dx = $cursor.X - $script:ScenePointerStart.X
    $dy = $cursor.Y - $script:ScenePointerStart.Y
    $start = $script:SceneElementStartBounds
    if ($script:ScenePointerMode -eq 'Resize') {
        $maxWidth = [Math]::Max(24, $sceneEditorCanvas.ClientSize.Width - $start.Left)
        $maxHeight = [Math]::Max(18, $sceneEditorCanvas.ClientSize.Height - $start.Top)
        $newWidth = [Math]::Max(24, [Math]::Min($maxWidth, $start.Width + $dx))
        $newHeight = [Math]::Max(18, [Math]::Min($maxHeight, $start.Height + $dy))

        if ($chkWebcamAspectLock.Checked) {
            $displayAspect = if ($start.Height -gt 0) { [double]$start.Width / [double]$start.Height } else { $script:WebcamAspectRatio }
            if ($displayAspect -le 0) { $displayAspect = 16.0 / 9.0 }

            if ([Math]::Abs($dx) -ge [Math]::Abs($dy * $displayAspect)) {
                $newHeight = [Math]::Max(18, [int][Math]::Round($newWidth / $displayAspect))
            }
            else {
                $newWidth = [Math]::Max(24, [int][Math]::Round($newHeight * $displayAspect))
            }

            if ($newWidth -gt $maxWidth) {
                $newWidth = $maxWidth
                $newHeight = [Math]::Max(18, [int][Math]::Round($newWidth / $displayAspect))
            }
            if ($newHeight -gt $maxHeight) {
                $newHeight = $maxHeight
                $newWidth = [Math]::Max(24, [int][Math]::Round($newHeight * $displayAspect))
            }
        }

        $sceneWebcamElement.Size = New-Object System.Drawing.Size($newWidth, $newHeight)
        Update-SceneSelectionChrome
    }
    else {
        $newLeft = [Math]::Max(0, [Math]::Min($sceneEditorCanvas.ClientSize.Width - $start.Width, $start.Left + $dx))
        $newTop = [Math]::Max(0, [Math]::Min($sceneEditorCanvas.ClientSize.Height - $start.Height, $start.Top + $dy))
        $sceneWebcamElement.Location = New-Object System.Drawing.Point($newLeft, $newTop)
    }
    Push-ControlledSceneGeometryFromElement
}

$scenePointerUp = {
    param($sender, $e)
    if (-not $script:ScenePointerActive) { return }
    $script:ScenePointerActive = $false
    $sceneWebcamElement.Capture = $false
    Set-SceneValuesFromElement
    if (-not $chkWebcamAspectLock.Checked) { Capture-WebcamAspectRatio }
}

foreach ($dragControl in @($sceneWebcamElement, $lblSceneWebcam, $sceneResizeHandle)) {
    $dragControl.Add_MouseDown($scenePointerDown)
    $dragControl.Add_MouseMove($scenePointerMove)
    $dragControl.Add_MouseUp($scenePointerUp)
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

$lblWebcamSource.Add_MouseDown({
    param($sender, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $script:SceneSourceDragActive = $true
    $lblWebcamSource.Capture = $true
    $lblWebcamSource.Text = '[box] Webcam - release on canvas'
})
$lblWebcamSource.Add_MouseMove({
    if (-not $script:SceneSourceDragActive) { return }
    $bounds = $sceneEditorCanvas.RectangleToScreen($sceneEditorCanvas.ClientRectangle)
    $lblWebcamSource.Cursor = if ($bounds.Contains([System.Windows.Forms.Cursor]::Position)) { [System.Windows.Forms.Cursors]::Cross } else { [System.Windows.Forms.Cursors]::Hand }
})
$lblWebcamSource.Add_MouseUp({
    param($sender, $e)
    if (-not $script:SceneSourceDragActive) { return }
    $script:SceneSourceDragActive = $false
    $lblWebcamSource.Capture = $false
    $lblWebcamSource.Text = '[box] Webcam - drag to canvas'
    $lblWebcamSource.Cursor = [System.Windows.Forms.Cursors]::Hand
    Place-WebcamOnSceneCanvas -ScreenPoint ([System.Windows.Forms.Cursor]::Position)
})
$sceneEditorCanvas.Add_SizeChanged({ Update-SceneCanvasFromValues })
$sceneDesktopPreviewPanel.Add_Resize({
    if (Get-Command Sync-DynamicScenePreviewLayout -ErrorAction SilentlyContinue) {
        Sync-DynamicScenePreviewLayout
    }
})
$sceneWebcamPreviewPanel.Add_Resize({
    if (Get-Command Sync-DynamicScenePreviewLayout -ErrorAction SilentlyContinue) {
        Sync-DynamicScenePreviewLayout
    }
})

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

$btnRefreshWebcams.Add_Click({ Reset-DynamicScenePreviewFallback; Refresh-WebcamDevices; Update-SceneUi; Restart-DynamicScenePreviewIfActive })
$btnRedrawScenePreview.Add_Click({ Invoke-ScenePreviewRedraw })
$chkSceneEnabled.Add_CheckedChanged({ Reset-DynamicScenePreviewFallback; Update-SceneUi; Restart-DynamicScenePreviewIfActive; Sync-StandalonePreviewState -Quiet })
$chkDynamicScenePreviews.Add_CheckedChanged({
    Reset-DynamicScenePreviewFallback
    $script:SuppressControlledLiveStream = $false

    # Re-evaluate the opt-in gate immediately from checkbox state. It must not
    # depend on the controlled preview having finished its asynchronous handoff.
    Update-LiveSceneEditingGate

    if ($script:LoadingSettings) {
        Update-SceneUi
        Update-CommandPreview
        return
    }
    if (-not $chkDynamicScenePreviews.Checked -and $script:ControlledLiveStreamActive) {
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Dynamic scene control disabled; restarting the stream with the legacy launcher."
        Stop-GstStream -Restart
        Update-SceneUi
        Update-CommandPreview
        return
    }
    if (-not $chkDynamicScenePreviews.Checked -and $script:DynamicScenePreviewActive) {
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Dynamic scene previews disabled; falling back to the normal composed preview."
        Stop-DynamicScenePreview -Quiet
    }
    elseif ($chkDynamicScenePreviews.Checked -and $script:PreviewOnlyMode -and $script:GstProcess -and -not $script:GstProcess.HasExited -and (Test-DynamicScenePreviewWanted)) {
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Dynamic scene previews enabled; restarting local preview with the controlled compositor."
        Stop-GstStream
    }
    Update-SceneUi
    Update-SceneCanvasFromValues
    Sync-StandalonePreviewState -Quiet
    Update-CommandPreview
})
$chkLiveSceneEditing.Add_CheckedChanged({
    $script:SuppressControlledLiveStream = $false
    if ($script:LoadingSettings) {
        Update-SceneUi
        Update-CommandPreview
        return
    }

    $externalStreamRunning = (
        $script:GstProcess -and
        -not $script:GstProcess.HasExited -and
        -not $script:PreviewOnlyMode
    )
    if ($script:ControlledLiveStreamActive -or ($chkLiveSceneEditing.Checked -and $externalStreamRunning)) {
        $mode = if ($chkLiveSceneEditing.Checked) { 'controlled live editing' } else { 'the legacy launcher' }
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Live scene editing changed; restarting the stream with $mode."
        Stop-GstStream -Restart
    }
    Update-SceneUi
    Update-CommandPreview
})
$chkStandardPreviewOffSceneTab.Add_CheckedChanged({
    if ($chkStandardPreviewOffSceneTab.Checked -and (-not $script:SceneWorkspaceActive) -and $script:DynamicScenePreviewActive) {
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Standard preview off Scenes enabled; switching dynamic scene previews back to the normal composed preview."
        Stop-DynamicScenePreview -Quiet
        Restore-SceneEditorCanvasHome
        Sync-StandalonePreviewState -Quiet
    }
    elseif ((-not $chkStandardPreviewOffSceneTab.Checked) -and (-not $script:SceneWorkspaceActive) -and $script:DynamicScenePreviewActive) {
        Show-DynamicScenePreviewInPreviewCard
    }
    elseif ((-not $chkStandardPreviewOffSceneTab.Checked) -and $script:PreviewOnlyMode -and $script:GstProcess -and -not $script:GstProcess.HasExited -and (Test-DynamicScenePreviewWanted)) {
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Dynamic preview sharing enabled off Scenes; switching the local preview to the controlled compositor."
        Stop-GstStream
        Sync-StandalonePreviewState -Quiet
    }
    Update-CommandPreview
})
$cmbScenePreset.Add_SelectedIndexChanged({ Reset-DynamicScenePreviewFallback; Update-SceneUi; Restart-DynamicScenePreviewIfActive })
$cmbSceneCompositor.Add_SelectedIndexChanged({ Reset-DynamicScenePreviewFallback; Update-SceneUi; Restart-DynamicScenePreviewIfActive })
$cmbWebcamDevice.Add_SelectedIndexChanged({ Reset-DynamicScenePreviewFallback; Update-SceneUi; Restart-DynamicScenePreviewIfActive })
$cmbWebcamLayout.Add_SelectedIndexChanged({ Set-WebcamLayoutPreset; Update-SceneUi })
$numWebcamWidth.Add_ValueChanged({
    if ($script:UpdatingSceneEditor -or $script:LoadingSettings) { return }
    if ($chkWebcamAspectLock.Checked) {
        $script:UpdatingSceneEditor = $true
        try {
            $ratio = [Math]::Max(0.0001, $script:WebcamAspectRatio)
            $height = [Math]::Min([int]$numWebcamHeight.Maximum, [Math]::Max([int]$numWebcamHeight.Minimum, [int][Math]::Round([double]$numWebcamWidth.Value / $ratio)))
            $width = [Math]::Min([int]$numWebcamWidth.Maximum, [Math]::Max([int]$numWebcamWidth.Minimum, [int][Math]::Round($height * $ratio)))
            $numWebcamWidth.Value = [decimal]$width
            $numWebcamHeight.Value = [decimal]$height
        }
        finally { $script:UpdatingSceneEditor = $false }
    }
    else { Capture-WebcamAspectRatio }
    Update-SceneUi
})
$numWebcamHeight.Add_ValueChanged({
    if ($script:UpdatingSceneEditor -or $script:LoadingSettings) { return }
    if ($chkWebcamAspectLock.Checked) {
        $script:UpdatingSceneEditor = $true
        try {
            $ratio = [Math]::Max(0.0001, $script:WebcamAspectRatio)
            $width = [Math]::Min([int]$numWebcamWidth.Maximum, [Math]::Max([int]$numWebcamWidth.Minimum, [int][Math]::Round([double]$numWebcamHeight.Value * $ratio)))
            $height = [Math]::Min([int]$numWebcamHeight.Maximum, [Math]::Max([int]$numWebcamHeight.Minimum, [int][Math]::Round($width / $ratio)))
            $numWebcamWidth.Value = [decimal]$width
            $numWebcamHeight.Value = [decimal]$height
        }
        finally { $script:UpdatingSceneEditor = $false }
    }
    else { Capture-WebcamAspectRatio }
    Update-SceneUi
})
$chkWebcamAspectLock.Add_CheckedChanged({
    if ($chkWebcamAspectLock.Checked) { Capture-WebcamAspectRatio }
    Update-SceneUi
})
foreach ($control in @($numWebcamX,$numWebcamY,$numWebcamFps,$numWebcamOpacity,$numWebcamBorder,$numSceneInputQueueBuffers,$numSceneInputQueueCapMs)) { $control.Add_ValueChanged({ Update-SceneUi }) }
$numWebcamFps.Add_ValueChanged({ Reset-DynamicScenePreviewFallback; Restart-DynamicScenePreviewIfActive })
$numSceneInputQueueBuffers.Add_ValueChanged({ Reset-DynamicScenePreviewFallback; Restart-DynamicScenePreviewIfActive })
$numSceneInputQueueCapMs.Add_ValueChanged({ Reset-DynamicScenePreviewFallback; Restart-DynamicScenePreviewIfActive })
$numWidth.Add_ValueChanged({ Resize-LiveSceneCanvas; Resize-DynamicScenePreviewCardCanvas; Update-SceneCanvasFromValues })
$numHeight.Add_ValueChanged({ Resize-LiveSceneCanvas; Resize-DynamicScenePreviewCardCanvas; Update-SceneCanvasFromValues })
$chkWebcamMirror.Add_CheckedChanged({ Reset-DynamicScenePreviewFallback; Update-SceneUi; Restart-DynamicScenePreviewIfActive })

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

    $settingsTabs.TabPages.AddRange(@($tabTransport, $tabWebRtc, $tabVideo, $tabScenes, $tabAudio, $tabPlayer, $tabRecording, $tabNetwork, $tabOptions))
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

    # Keep the sidebar highlight in sync with the active settings tab so the two
    # parallel navigations never disagree about where the user is.
    $settingsTabs.Add_SelectedIndexChanged({
        if ($script:SidebarNavButtons) {
            $map = @{
                0 = 'Transport'; 1 = 'WebRtc'; 2 = 'Video'; 3 = 'Scenes'; 4 = 'Audio';
                5 = 'Player'; 6 = 'Recording'; 7 = 'Network'; 8 = 'Options'
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

    $s = Add-Section $paneVideo 'Encoded sender queue'
    $r = Add-Row $s
    Add-Field $r -LabelControl $lblWebRtcSenderQueueMode -Control $cmbWebRtcSenderQueueMode -Width 180 | Out-Null
    Add-Field $r -LabelControl $lblDirectWebRtcPacingMs -Control $numDirectWebRtcPacingMs -Width 90 | Out-Null

    $s = Add-Section $paneVideo 'Clock / timing'
    $r = Add-Row $s
    Add-Field $r -Label 'Pipeline master clock' -Control $cmbVideoPipelineClockMode -Width 235 | Out-Null
    Add-Field $r -Label 'Video timestamps' -Control $cmbVideoTimestampMode -Width 220 | Out-Null
    Add-Field $r -Label 'Video sync mode' -Control $cmbVideoSyncMode -Width 130 | Out-Null

    $s = Add-Section $paneVideo 'Format'
    $r = Add-Row $s
    Add-Field $r -Label 'Width' -Control $numWidth -Width 90 | Out-Null
    Add-Field $r -Label 'Height' -Control $numHeight -Width 90 | Out-Null
    Add-Field $r -Label 'FPS' -Control $numFps -Width 80 | Out-Null
    Add-Field $r -Label 'Video kbps' -Control $numVideoBitrate -Width 110 | Out-Null
    Add-Field $r -Label 'Max kbps' -Control $numMaxVideoBitrate -Width 100 | Out-Null
    $r = Add-Row $s
    Add-Field $r -Label 'CQ/QP' -Control $numConstantQp -Width 70 | Out-Null
    Add-Field $r -Label 'Preset' -Control $cmbPreset -Width 120 | Out-Null
    Add-Field $r -Label 'Profile' -Control $cmbProfile -Width 170 | Out-Null

    $s = Add-Section $paneVideo 'Keyframes'
    $r = Add-Row $s
    Add-Field $r -Label 'GOP sec' -Control $numGopSeconds -Width 80 | Out-Null
    Add-Field $r -Control $chkUnifiedBridgeKeyframeGuard -Width 260 | Out-Null
    Add-Field $r -Label 'Interval ms' -Control $numUnifiedBridgeKeyframeIntervalMs -Width 90 | Out-Null

    $s = Add-Section $paneVideo 'Quality tuning'
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

    $s = Add-Section $paneAudio 'Clock / timing'
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

    $s = Add-Section $paneAudio 'Audio queues'
    $r = Add-Row $s
    Add-Field $r -LabelControl $lblAudioQueueBuffers -Control $numAudioQueueBuffers -Width 90 | Out-Null
    Add-Field $r -LabelControl $lblAudioQueueCapMs -Control $numAudioQueueCapMs -Width 100 | Out-Null

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

    $s = Add-Section $paneAudio 'Direct GST WebRTC Opus'
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

    foreach ($tp in @($tabTransport, $tabWebRtc, $tabVideo, $tabAudio, $tabPlayer, $tabRecording, $tabNetwork, $tabOptions)) {
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

    $btnStop.Text = "$($script:Glyph.Stop)  Stop"
    $btnStop.Width = 110
    $btnStop.Height = 42
    $btnStop.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)

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
        foreach ($btn in @($btnOpenLogs, $btnClearLog, $btnCopyCommand, $btnRestart, $btnStop, $btnStart)) {
            if ($btn -and $btn.Parent -ne $script:ModernActionFlow) {
                $script:ModernActionFlow.Controls.Add($btn)
            }
        }
    }

    # Bottom output.
    $lowerTabs.Dock = 'Fill'
    $lowerTabs.SelectedTab = $tabLog

    $tabLog.Text = " $($script:Glyph.Logs)  Logs "
    $tabCommand.Text = " $($script:Glyph.Command)  Command Preview "
    $txtLog.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#08111F')
    $txtLog.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#D1D5DB')
    $txtLog.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $txtCommand.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#08111F')
    $txtCommand.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#D1D5DB')
    $txtCommand.BorderStyle = [System.Windows.Forms.BorderStyle]::None

    Style-Tree $form

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
        $chkRecordingEnabled, $txtRecordingDirectory, $btnBrowseRecordingDirectory,
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
        $chkRecordingEnabled, $chkRecordingLookAhead, $chkRecordingSpatialAq,
        $chkRecordingTemporalAq, $chkRecordingDesktopAudio, $chkRecordingMic,
        $chkNetworkTuningEnabled, $chkNetworkDscp, $chkNetworkDisablePowerSaving,
        $chkNetworkDisableEee, $chkNetworkRestoreOnStop, $chkNetworkRestoreOnExit,
        $chkNetworkRecoveryTask,
        $chkPreview, $chkHidePreviewDuringStream, $chkAutoRestart, $chkVerbose, $chkDiskProcessLogging,
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
}

Apply-ModernDashboardUi



function Initialize-GstJob {
    if ($script:JobHandle -ne [IntPtr]::Zero) {
        return
    }

    try {
        $script:JobHandle = [GstProcessJob]::CreateKillOnCloseJob()
        Append-Log 'Created kill-on-close Windows job for GStreamer and MediaMTX processes.'
    }
    catch {
        $script:JobHandle = [IntPtr]::Zero
        Append-Log "WARNING: Could not create process job: $($_.Exception.Message)"
    }
}

function Save-ActiveProcessState {
    try {
        $gstRunning =
            $script:GstProcess -and
            -not $script:GstProcess.HasExited

        $videoRunning =
            $script:GstVideoProcess -and
            -not $script:GstVideoProcess.HasExited

        $audioRunning =
            $script:GstAudioProcess -and
            -not $script:GstAudioProcess.HasExited

        $mediaRunning =
            $script:MediaMtxProcess -and
            -not $script:MediaMtxProcess.HasExited

        if (-not $gstRunning -and -not $videoRunning -and -not $audioRunning -and -not $mediaRunning) {
            Remove-ActiveProcessState
            return
        }

        if (-not (Test-Path -LiteralPath $script:ConfigDirectory)) {
            $null = New-Item -ItemType Directory -Path $script:ConfigDirectory -Force
        }

        $state = [ordered]@{
            OwnerProcessId = $PID
            AppVersion     = $script:AppVersion
        }

        if ($gstRunning) {
            $state.GstProcessId      = $script:GstProcess.Id
            $state.GstExecutablePath = if ($script:ControlledLiveStreamActive) {
                [System.IO.Path]::GetFullPath($script:GstProcess.MainModule.FileName)
            }
            else {
                [System.IO.Path]::GetFullPath($txtGstPath.Text.Trim())
            }
            $state.GstStartTimeUtc   =
                $script:GstProcess.StartTime.ToUniversalTime().ToString('o')

            # Keep the older field names for backward compatibility with state
            # files written by pre-v3.4 builds.
            $state.ProcessId      = $state.GstProcessId
            $state.ExecutablePath = $state.GstExecutablePath
            $state.StartTimeUtc   = $state.GstStartTimeUtc
        }

        if ($videoRunning) {
            $state.GstVideoProcessId = $script:GstVideoProcess.Id
            $state.GstVideoStartTimeUtc = $script:GstVideoProcess.StartTime.ToUniversalTime().ToString('o')
        }

        if ($audioRunning) {
            $state.GstAudioProcessId = $script:GstAudioProcess.Id
            $state.GstAudioStartTimeUtc = $script:GstAudioProcess.StartTime.ToUniversalTime().ToString('o')
        }

        if ($mediaRunning) {
            $state.MediaMtxProcessId      = $script:MediaMtxProcess.Id
            $state.MediaMtxExecutablePath = [System.IO.Path]::GetFullPath(
                $script:MediaMtxPathInUse
            )
            $state.MediaMtxStartTimeUtc   =
                $script:MediaMtxProcess.StartTime.ToUniversalTime().ToString('o')
        }

        $state |
            ConvertTo-Json |
            Set-Content -LiteralPath $script:ProcessStatePath -Encoding UTF8
    }
    catch {
        Append-Log "WARNING: Could not save active-process state: $($_.Exception.Message)"
    }
}

function Remove-ActiveProcessState {
    try {
        Remove-Item `
            -LiteralPath $script:ProcessStatePath `
            -Force `
            -ErrorAction SilentlyContinue
    }
    catch {}
}

function Stop-ProcessTreeById {
    param([Parameter(Mandatory)][int]$ProcessId)

    if ($ProcessId -le 0) {
        return
    }

    try {
        $arguments = "/PID $ProcessId /T /F"
        $null = Start-Process `
            -FilePath 'taskkill.exe' `
            -ArgumentList $arguments `
            -WindowStyle Hidden `
            -Wait `
            -PassThru
    }
    catch {
        try {
            Stop-Process -Id $ProcessId -Force -ErrorAction Stop
        }
        catch {}
    }
}

function Stop-VerifiedStaleProcess {
    param(
        [int]$ProcessId,
        [string]$ExecutablePath,
        [string]$StartTimeUtc,
        [string]$Label
    )

    if ($ProcessId -le 0) {
        return
    }

    if (
        ($script:GstProcess -and
         -not $script:GstProcess.HasExited -and
         $script:GstProcess.Id -eq $ProcessId) -or
        ($script:MediaMtxProcess -and
         -not $script:MediaMtxProcess.HasExited -and
         $script:MediaMtxProcess.Id -eq $ProcessId)
    ) {
        return
    }

    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $process) {
        return
    }

    $pathMatches = $false
    $timeMatches = $false

    try {
        $actualPath = [System.IO.Path]::GetFullPath($process.Path)
        $expectedPath = [System.IO.Path]::GetFullPath($ExecutablePath)
        $pathMatches = $actualPath.Equals(
            $expectedPath,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    }
    catch {}

    try {
        $expectedStart = [datetime]::Parse($StartTimeUtc).ToUniversalTime()
        $actualStart = $process.StartTime.ToUniversalTime()
        $timeMatches =
            [math]::Abs(($actualStart - $expectedStart).TotalSeconds) -le 5
    }
    catch {}

    if ($pathMatches -and $timeMatches) {
        Append-Log (
            "Found orphaned $Label process PID $ProcessId from a previous " +
            'wrapper instance; terminating its process tree.'
        )
        Stop-ProcessTreeById -ProcessId $ProcessId
    }
    else {
        Append-Log (
            "Ignored stale $Label process record for PID $ProcessId because " +
            'its executable or start time no longer matches.'
        )
    }
}

function Stop-StaleManagedProcesses {
    if (-not (Test-Path -LiteralPath $script:ProcessStatePath)) {
        return
    }

    try {
        $state =
            Get-Content -LiteralPath $script:ProcessStatePath -Raw |
            ConvertFrom-Json

        $gstPid = 0
        $gstPath = ''
        $gstStart = ''

        if ($null -ne $state.GstProcessId) {
            $gstPid = [int]$state.GstProcessId
            $gstPath = [string]$state.GstExecutablePath
            $gstStart = [string]$state.GstStartTimeUtc
        }
        elseif ($null -ne $state.ProcessId) {
            $gstPid = [int]$state.ProcessId
            $gstPath = [string]$state.ExecutablePath
            $gstStart = [string]$state.StartTimeUtc
        }

        Stop-VerifiedStaleProcess `
            -ProcessId $gstPid `
            -ExecutablePath $gstPath `
            -StartTimeUtc $gstStart `
            -Label 'GStreamer publisher/main'

        Stop-VerifiedStaleProcess `
            -ProcessId ([int]$state.GstVideoProcessId) `
            -ExecutablePath $gstPath `
            -StartTimeUtc ([string]$state.GstVideoStartTimeUtc) `
            -Label 'GStreamer video bridge'

        Stop-VerifiedStaleProcess `
            -ProcessId ([int]$state.GstAudioProcessId) `
            -ExecutablePath $gstPath `
            -StartTimeUtc ([string]$state.GstAudioStartTimeUtc) `
            -Label 'GStreamer audio bridge'

        Stop-VerifiedStaleProcess `
            -ProcessId ([int]$state.MediaMtxProcessId) `
            -ExecutablePath ([string]$state.MediaMtxExecutablePath) `
            -StartTimeUtc ([string]$state.MediaMtxStartTimeUtc) `
            -Label 'MediaMTX'
    }
    catch {
        Append-Log (
            "WARNING: Could not inspect stale managed-process state: " +
            $_.Exception.Message
        )
    }
    finally {
        Remove-ActiveProcessState
    }
}

function Update-TrayMenuState {
    try {
        $running = (
            ($script:GstProcess -and -not $script:GstProcess.HasExited) -or
            [bool]$script:DynamicScenePreviewActive -or
            [bool]$script:ControlledLiveStreamActive
        )
        $waiting = [bool]$script:WaitingForFullscreen
        $previewOnly = $running -and [bool]$script:PreviewOnlyMode

        $trayStartItem.Enabled = ((-not $running) -or $previewOnly) -and -not $waiting
        $trayStopItem.Enabled = ($running -and -not $previewOnly) -or $waiting
        $trayRestartItem.Enabled = $running -and -not $previewOnly

        if ($previewOnly) {
            $trayStartItem.Text = 'Start Stream'
            $trayStopItem.Text = 'Stop Stream'
            $notifyIcon.Text = 'GStreamer Streamer - preview only'
        }
        elseif ($running) {
            $trayStartItem.Text = 'Start Stream'
            $trayStopItem.Text = 'Stop Stream'
            $notifyIcon.Text = "GStreamer Streamer - $([string]$cmbProtocol.SelectedItem) running"
        }
        elseif ($waiting) {
            $trayStartItem.Text = 'Start Stream'
            $trayStopItem.Text = 'Stop Stream'
            $notifyIcon.Text = 'GStreamer Streamer - waiting for fullscreen app'
        }
        else {
            $trayStartItem.Text = 'Start Stream'
            $trayStopItem.Text = 'Stop Stream'
            $notifyIcon.Text = 'GStreamer Streamer - stopped'
        }
    }
    catch {
        # Tray state is non-critical and must never affect streaming.
    }
}

function Apply-StartMinimized {
    if (-not $chkStartMinimized.Checked -or $script:ExitCleanupStarted) {
        return
    }

    try {
        # Start minimized is defined as start in tray. Keep this defensive
        # assignment even though load/UI/save also enforce the invariant.
        $chkMinimizeToTray.Checked = $true
        Hide-MainWindowToTray -SuppressBalloon
        $script:StartupTrayHidePending = $false
    }
    catch {
        try {
            $form.Opacity = 1
            $form.ShowInTaskbar = $true
        }
        catch {}
    }
}

function Enforce-StartMinimizedTrayInvariant {
    param([switch]$Persist)

    if ($script:EnforcingStartMinimizedTrayInvariant) { return }

    $script:EnforcingStartMinimizedTrayInvariant = $true
    try {
        if ($chkStartMinimized.Checked) {
            if (-not $chkMinimizeToTray.Checked) {
                $chkMinimizeToTray.Checked = $true
            }
            $chkMinimizeToTray.Enabled = $false
        }
        else {
            $chkMinimizeToTray.Enabled = $true
        }
    }
    finally {
        $script:EnforcingStartMinimizedTrayInvariant = $false
    }

    if ($Persist -and -not $script:LoadingSettings) {
        Save-Settings
    }
}

$chkStartMinimized.Add_CheckedChanged({
    Enforce-StartMinimizedTrayInvariant -Persist
})
$chkMinimizeToTray.Add_CheckedChanged({
    Enforce-StartMinimizedTrayInvariant -Persist
})

function Show-MainWindow {
    if ($script:TrayRestoreInProgress -or $script:ExitCleanupStarted) {
        return
    }

    $script:TrayRestoreInProgress = $true
    try {
        $script:StartupTrayHidePending = $false
        $form.Opacity = 1
        $form.ShowInTaskbar = $true
        $form.Show()
        if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
            $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        }
        $form.BringToFront()
        $form.Activate()

        # Finish preview restore on the next UI turn. VisibleChanged and Resize
        # both fire inside Form.Show()/WindowState changes; starting or reparenting
        # a dynamic preview from either event can race the form's native handles.
        $null = $form.BeginInvoke([Action]{
            try {
                # The form is now visible and its restore/layout events have
                # unwound, so standalone preview startup is safe again.
                $script:TrayRestoreInProgress = $false
                $script:DynamicPreviewUiReady = $true
                if ($script:ControlledLiveStreamActive) {
                    Sync-ControlledLivePreviewLayout
                }
                elseif ($script:GstProcess -and -not $script:GstProcess.HasExited) {
                    if ($script:PreviewParked) {
                        Restore-PreviewWindowFromParking
                    }
                    Try-AttachPreview
                    Set-PreviewVisibility
                }
                else {
                    Sync-StandalonePreviewState -Quiet
                }
            }
            catch {}
            finally {
                $script:TrayRestoreInProgress = $false
                Update-TrayMenuState
            }
        })
    }
    catch {
        $script:TrayRestoreInProgress = $false
    }
}

function Hide-MainWindowToTray {
    param([switch]$SuppressBalloon)

    if (-not $chkMinimizeToTray.Checked -or $script:ExitCleanupStarted) {
        return
    }

    try {
        # Dynamic source windows must never be created or reparented while the
        # main UI is entering tray-hidden state. They become eligible again only
        # after Show-MainWindow completes its deferred restore/layout turn.
        $script:DynamicPreviewUiReady = $false

        if ($script:PreviewOnlyMode) {
            Sync-StandalonePreviewState
        }
        elseif ($script:PreviewHwnd -ne [IntPtr]::Zero) {
            Park-PreviewWindow
        }

        $previewPlaceholder.Visible = $true
        $previewPlaceholder.Text = 'Preview parked while app is in tray'

        $form.ShowInTaskbar = $false
        $form.Hide()
        $form.Opacity = 1

        if (-not $SuppressBalloon -and -not $script:TrayHintShown) {
            $notifyIcon.BalloonTipTitle = $script:AppName
            $notifyIcon.BalloonTipText = 'The streamer is still running. Double-click the tray icon to restore it.'
            $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
            $notifyIcon.ShowBalloonTip(2500)
            $script:TrayHintShown = $true
        }
    }
    catch {
        # A failed tray hide should leave the normal minimized taskbar window.
        try {
            $form.Opacity = 1
            $form.ShowInTaskbar = $true
            $form.Show()
        }
        catch {}
    }
}

function Set-WaitingForFullscreenState {
    $btnStart.Enabled = $false
    $btnStop.Enabled = $true
    $btnRestart.Enabled = $false
    Update-TrayMenuState
}

function Scroll-LogToBottom {
    try {
        if (-not $txtLog -or $txtLog.IsDisposed) {
            return
        }

        $txtLog.SelectionStart = $txtLog.TextLength
        $txtLog.SelectionLength = 0
        $txtLog.ScrollToCaret()

        if ($txtLog.IsHandleCreated) {
            # ScrollToCaret() can be lazy when the TextBox does not have focus or
            # when the Logs tab is not active. Force the Win32 edit control to
            # move to the bottom so live GStreamer output actually follows tail.
            [GstUiNative]::SendMessage(
                $txtLog.Handle,
                [GstUiNative]::EM_SCROLLCARET,
                [IntPtr]::Zero,
                [IntPtr]::Zero
            ) | Out-Null

            [GstUiNative]::SendMessage(
                $txtLog.Handle,
                [GstUiNative]::WM_VSCROLL,
                [IntPtr]([GstUiNative]::SB_BOTTOM),
                [IntPtr]::Zero
            ) | Out-Null
        }
    }
    catch {}
}

function Drain-ManagedProcessLogs {
    # Reads any new bytes from the GStreamer and MediaMTX stdout/stderr logs and
    # returns them as one chunk so the caller can do a single UI append.
    # Read-NewLogText already no-ops on null/blank paths, so this is cheap when
    # nothing is running.
    $parts = New-Object System.Collections.Generic.List[string]

    $chunk = Read-NewLogText -Path $script:StdOutPath -Position ([ref]$script:StdOutPosition)
    if ($chunk) { $parts.Add($chunk) }

    $chunk = Read-NewLogText -Path $script:StdErrPath -Position ([ref]$script:StdErrPosition)
    if ($chunk) { $parts.Add($chunk) }

    $chunk = Read-NewLogText -Path $script:StdOutVideoPath -Position ([ref]$script:StdOutVideoPosition)
    if ($chunk) { $parts.Add($chunk) }

    $chunk = Read-NewLogText -Path $script:StdErrVideoPath -Position ([ref]$script:StdErrVideoPosition)
    if ($chunk) { $parts.Add($chunk) }

    $chunk = Read-NewLogText -Path $script:StdOutAudioPath -Position ([ref]$script:StdOutAudioPosition)
    if ($chunk) { $parts.Add($chunk) }

    $chunk = Read-NewLogText -Path $script:StdErrAudioPath -Position ([ref]$script:StdErrAudioPosition)
    if ($chunk) { $parts.Add($chunk) }

    $chunk = Read-NewLogText -Path $script:MediaMtxStdOutPath -Position ([ref]$script:MediaMtxStdOutPosition)
    if ($chunk) { $parts.Add($chunk) }

    $chunk = Read-NewLogText -Path $script:MediaMtxStdErrPath -Position ([ref]$script:MediaMtxStdErrPosition)
    if ($chunk) { $parts.Add($chunk) }

    if ($parts.Count -eq 0) { return '' }
    return ($parts -join '')
}

function Test-LogViewLive {
    # The log textbox only needs to scroll and repaint when the user can actually
    # see it. Under heavy GST_DEBUG this is the difference between forcing a
    # scroll+repaint 2.5x/second forever and doing no UI work at all.
    try {
        if (-not $txtLog -or $txtLog.IsDisposed) { return $false }
        if (-not $form -or -not $form.Visible) { return $false }
        if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) { return $false }
        if ($lowerTabs -and $tabLog -and $lowerTabs.SelectedTab -ne $tabLog) { return $false }
        return $true
    }
    catch { return $false }
}

function Append-Log {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return
    }

    try {
        if (-not $txtLog -or $txtLog.IsDisposed) {
            return
        }

        if (-not $Text.EndsWith([Environment]::NewLine)) {
            $Text += [Environment]::NewLine
        }

        $logIsLive = Test-LogViewLive
        $needsTrim = ($txtLog.TextLength + $Text.Length) -gt 250000

        # Suspend painting only when the control is actually on screen AND we are
        # about to do the expensive full-text trim. WM_SETREDRAW on a hidden tab
        # would be wasted work, and suspending for a plain append costs more than
        # the append itself.
        $suspendRedraw = $logIsLive -and $needsTrim -and $txtLog.IsHandleCreated
        if ($suspendRedraw) {
            [void][GstUiNative]::SendMessage($txtLog.Handle, [GstUiNative]::WM_SETREDRAW, [IntPtr]::Zero, [IntPtr]::Zero)
        }

        try {
            $txtLog.AppendText($Text)

            if ($txtLog.TextLength -gt 250000) {
                $txtLog.Text = $txtLog.Text.Substring($txtLog.TextLength - 180000)
            }

            if ($logIsLive) {
                Scroll-LogToBottom
            }
        }
        finally {
            if ($suspendRedraw) {
                [void][GstUiNative]::SendMessage($txtLog.Handle, [GstUiNative]::WM_SETREDRAW, [IntPtr]1, [IntPtr]::Zero)
                $txtLog.Invalidate()
            }
        }
    }
    catch {}
}

function Set-RunState {
    param([bool]$Running)

    $previewOnly = $Running -and [bool]$script:PreviewOnlyMode
    $btnStart.Enabled = (-not $Running) -or $previewOnly
    $btnStop.Enabled = $Running -and -not $previewOnly
    $btnRestart.Enabled = $Running -and -not $previewOnly
    if ($previewOnly) {
        $btnStart.Text = "$($script:Glyph.Start)  Go Live"
        $btnStop.Text = "$($script:Glyph.Stop)  Stop"
    }
    else {
        $btnStart.Text = "$($script:Glyph.Start)  Start"
        $btnStop.Text = "$($script:Glyph.Stop)  Stop"
    }
    Update-TrayMenuState
}

function Test-TransportEnabled {
    if ($script:ForceLocalPreviewMode) { return $false }
    return (-not $chkTransportEnabled) -or [bool]$chkTransportEnabled.Checked
}

function Test-StandalonePreviewAllowed {
    try {
        if (-not $form -or -not $form.Visible) { return $false }
        if ($script:StartupTrayHidePending) { return $false }
        if ($script:TrayRestoreInProgress) { return $false }
        if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) { return $false }
        return $true
    }
    catch {
        return $false
    }
}

function Sync-StandalonePreviewState {
    param([switch]$Quiet)

    if ($script:LoadingSettings) { return }

    $running = (
        ($script:GstProcess -and -not $script:GstProcess.HasExited) -or
        [bool]$script:DynamicScenePreviewActive -or
        [bool]$script:ControlledLiveStreamActive
    )

    if ($script:DynamicScenePreviewActive -and -not (Test-UseDynamicScenePreview)) {
        if (-not $Quiet) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Dynamic scene preview disabled by current window/scene state."
        }
        Stop-DynamicScenePreview
        return
    }

    if ($script:PreviewOnlyMode -and -not (Test-StandalonePreviewAllowed)) {
        if (-not $Quiet) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Standalone preview disabled while the app is hidden or minimized."
        }
        if ($script:DynamicScenePreviewActive) { Stop-DynamicScenePreview } else { Stop-GstStream }
        return
    }

    if (
        (-not $running) -and
        $chkPreview.Checked -and
        (Test-StandalonePreviewAllowed)
    ) {
        if (Test-UseDynamicScenePreview) {
            if (Start-DynamicScenePreview) { return }
            if (-not $Quiet) {
                Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Controlled scene preview failed; starting the normal composed preview fallback."
            }
        }

        if (-not $Quiet) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Starting standalone preview."
        }
        Start-GstStream -PreviewOnly
    }
}

function Update-MediaMtxUi {
    $transportEnabled = Test-TransportEnabled
    $isDirectWebRtc = ([string]$cmbProtocol.SelectedItem -eq $script:DirectWebRtcProtocolName)
    if ($chkStartMediaMtx) { $chkStartMediaMtx.Enabled = $transportEnabled -and -not $isDirectWebRtc }
    $enabled = $transportEnabled -and -not $isDirectWebRtc -and $chkStartMediaMtx.Checked
    $txtMediaMtxPath.Enabled = $enabled
    $btnBrowseMediaMtx.Enabled = $enabled
}

function Test-IsAdministrator {
    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Ensure-NetworkRecoveryDirectory {
    if (-not (Test-Path -LiteralPath $script:NetworkRecoveryDirectory)) {
        $null = New-Item -ItemType Directory -Path $script:NetworkRecoveryDirectory -Force
    }
}

function Get-SelectedNetworkAdapterName {
    $item = [string]$cmbNetworkAdapter.SelectedItem
    if ([string]::IsNullOrWhiteSpace($item)) { return '' }
    return ($item -split '\s+\|\s+', 2)[0].Trim()
}

function Refresh-NetworkAdapters {
    try {
        $previous = Get-SelectedNetworkAdapterName
        $cmbNetworkAdapter.Items.Clear()
        if (-not (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue)) {
            $lblNetworkStatus.Text = 'Get-NetAdapter unavailable on this system.'
            $lblNetworkStatus.ForeColor = [System.Drawing.Color]::DarkRed
            return
        }

        $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Sort-Object @{Expression={ if ($_.Status -eq 'Up') { 0 } else { 1 } }}, Name)
        foreach ($adapter in $adapters) {
            $display = "$($adapter.Name) | $($adapter.InterfaceDescription) [$($adapter.Status)]"
            $null = $cmbNetworkAdapter.Items.Add($display)
        }

        if ($cmbNetworkAdapter.Items.Count -gt 0) {
            $matchIndex = -1
            if (-not [string]::IsNullOrWhiteSpace($previous)) {
                for ($i = 0; $i -lt $cmbNetworkAdapter.Items.Count; $i++) {
                    if ([string]$cmbNetworkAdapter.Items[$i] -like "$previous |*") { $matchIndex = $i; break }
                }
            }
            if ($matchIndex -lt 0) { $matchIndex = 0 }
            $cmbNetworkAdapter.SelectedIndex = $matchIndex
            $lblNetworkStatus.Text = "Adapter ready: $(Get-SelectedNetworkAdapterName)"
            $lblNetworkStatus.ForeColor = [System.Drawing.Color]::DimGray
        }
        else {
            $lblNetworkStatus.Text = 'No network adapters detected.'
            $lblNetworkStatus.ForeColor = [System.Drawing.Color]::DarkRed
        }
    }
    catch {
        $lblNetworkStatus.Text = "Adapter refresh failed: $($_.Exception.Message)"
        $lblNetworkStatus.ForeColor = [System.Drawing.Color]::DarkRed
    }
}

function Normalize-UdpOffloadState {
    param([AllowNull()][object]$State)

    $value = ([string]$State).Trim().ToLowerInvariant()
    switch ($value) {
        'enabled' { return 'enabled' }
        'disabled' { return 'disabled' }
        default { return '' }
    }
}

function Get-UdpGlobalState {
    $state = [ordered]@{ Uso = ''; Uro = ''; Raw = '' }
    try {
        $raw = (& netsh interface udp show global 2>&1 | Out-String).Trim()
        $state.Raw = $raw
        foreach ($line in ($raw -split "`r?`n")) {
            if ($line -match '(?i)\buso\b.*:\s*(?<value>enabled|disabled)') { $state.Uso = $matches['value'].ToLowerInvariant(); continue }
            if ($line -match '(?i)segmentation.*:\s*(?<value>enabled|disabled)') { $state.Uso = $matches['value'].ToLowerInvariant(); continue }
            if ($line -match '(?i)\buro\b.*:\s*(?<value>enabled|disabled)') { $state.Uro = $matches['value'].ToLowerInvariant(); continue }
            if ($line -match '(?i)receive.*(?:offload|coalescing).*:\s*(?<value>enabled|disabled)') { $state.Uro = $matches['value'].ToLowerInvariant(); continue }
        }
    }
    catch {}
    return $state
}

function Get-SnapshotUdpOffloadState {
    param(
        [AllowNull()][object]$UdpGlobal,
        [ValidateSet('uso','uro')][string]$Name
    )

    if (-not $UdpGlobal) { return '' }

    $direct = ''
    try {
        if ($Name -eq 'uso') { $direct = Normalize-UdpOffloadState $UdpGlobal.Uso }
        else { $direct = Normalize-UdpOffloadState $UdpGlobal.Uro }
    }
    catch {}
    if ($direct) { return $direct }

    try {
        $raw = [string]$UdpGlobal.Raw
        foreach ($line in ($raw -split "`r?`n")) {
            if ($Name -eq 'uso') {
                if ($line -match '(?i)\buso\b.*:\s*(?<value>enabled|disabled)') { return $matches['value'].ToLowerInvariant() }
                if ($line -match '(?i)segmentation.*:\s*(?<value>enabled|disabled)') { return $matches['value'].ToLowerInvariant() }
            }
            else {
                if ($line -match '(?i)\buro\b.*:\s*(?<value>enabled|disabled)') { return $matches['value'].ToLowerInvariant() }
                if ($line -match '(?i)receive.*(?:offload|coalescing).*:\s*(?<value>enabled|disabled)') { return $matches['value'].ToLowerInvariant() }
            }
        }
    }
    catch {}

    return ''
}

function Set-UdpGlobalOffload {
    param(
        [ValidateSet('uso','uro')][string]$Name,
        [ValidateSet('enabled','disabled')][string]$State
    )

    try {
        $result = (& netsh interface udp set global ("$Name=$State") 2>&1 | Out-String).Trim()
        Append-Log "Network tuning: netsh interface udp set global $Name=$State - $result"
        return $true
    }
    catch {
        Append-Log "Network tuning warning: could not set UDP $Name to $State - $($_.Exception.Message)"
        return $false
    }
}

function Get-NetworkSnapshotObject {
    param([Parameter(Mandatory)][string]$AdapterName)

    $advanced = @()
    if (Get-Command Get-NetAdapterAdvancedProperty -ErrorAction SilentlyContinue) {
        try {
            $advanced = @(Get-NetAdapterAdvancedProperty -Name $AdapterName -ErrorAction SilentlyContinue | ForEach-Object {
                [ordered]@{
                    DisplayName = [string]$_.DisplayName
                    DisplayValue = [string]$_.DisplayValue
                    RegistryKeyword = [string]$_.RegistryKeyword
                    RegistryValue = @($_.RegistryValue)
                }
            })
        }
        catch {}
    }

    $power = [ordered]@{}
    if (Get-Command Get-NetAdapterPowerManagement -ErrorAction SilentlyContinue) {
        try {
            $pm = Get-NetAdapterPowerManagement -Name $AdapterName -ErrorAction SilentlyContinue
            foreach ($propName in @('AllowComputerToTurnOffDevice','WakeOnMagicPacket','WakeOnPattern','DeviceSleepOnDisconnect','ArpOffload','NSOffload','RsnRekeyOffload','D0PacketCoalescing')) {
                if ($pm.PSObject.Properties.Name -contains $propName) {
                    $power[$propName] = [string]$pm.$propName
                }
            }
        }
        catch {}
    }

    return [ordered]@{
        Version = $script:AppVersion
        Timestamp = (Get-Date).ToString('o')
        ComputerName = $env:COMPUTERNAME
        AdapterName = $AdapterName
        UdpGlobal = Get-UdpGlobalState
        AdvancedProperties = $advanced
        PowerManagement = $power
        QosPolicyName = 'GStreamerGlass-Transport'
    }
}

function Write-NetworkRecoveryScript {
    Ensure-NetworkRecoveryDirectory
    $template = @'
param([string]$SnapshotPath = '__SNAPSHOT_PATH__')

function Normalize-UdpOffloadState {
    param([string]$State)
    $value = ([string]$State).Trim().ToLowerInvariant()
    if ($value -eq 'enabled' -or $value -eq 'disabled') { return $value }
    return ''
}

function Get-SnapshotUdpOffloadState {
    param($UdpGlobal, [string]$Name)
    if (-not $UdpGlobal) { return '' }
    $direct = ''
    try {
        if ($Name -eq 'uso') { $direct = Normalize-UdpOffloadState ([string]$UdpGlobal.Uso) }
        else { $direct = Normalize-UdpOffloadState ([string]$UdpGlobal.Uro) }
    } catch {}
    if ($direct) { return $direct }

    try {
        $raw = [string]$UdpGlobal.Raw
        foreach ($line in ($raw -split "`r?`n")) {
            if ($Name -eq 'uso') {
                if ($line -match '(?i)\buso\b.*:\s*(?<value>enabled|disabled)') { return $matches['value'].ToLowerInvariant() }
                if ($line -match '(?i)segmentation.*:\s*(?<value>enabled|disabled)') { return $matches['value'].ToLowerInvariant() }
            }
            else {
                if ($line -match '(?i)\buro\b.*:\s*(?<value>enabled|disabled)') { return $matches['value'].ToLowerInvariant() }
                if ($line -match '(?i)receive.*(?:offload|coalescing).*:\s*(?<value>enabled|disabled)') { return $matches['value'].ToLowerInvariant() }
            }
        }
    } catch {}
    return ''
}

function Set-UdpGlobalSafe {
    param([string]$Name, [string]$State)
    $safeState = Normalize-UdpOffloadState $State
    if ([string]::IsNullOrWhiteSpace($safeState)) { return }
    try { & netsh interface udp set global "$Name=$safeState" | Out-Null } catch { Write-Warning $_.Exception.Message }
}

if (-not (Test-Path -LiteralPath $SnapshotPath)) {
    Write-Error "Snapshot not found: $SnapshotPath"
    exit 1
}

$snapshot = Get-Content -LiteralPath $SnapshotPath -Raw | ConvertFrom-Json
$adapterName = [string]$snapshot.AdapterName

try {
    if (Get-Command Remove-NetQosPolicy -ErrorAction SilentlyContinue) {
        Remove-NetQosPolicy -Name ([string]$snapshot.QosPolicyName) -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    }
} catch { Write-Warning $_.Exception.Message }

try {
    if ($snapshot.UdpGlobal) {
        Set-UdpGlobalSafe -Name 'uso' -State (Get-SnapshotUdpOffloadState -UdpGlobal $snapshot.UdpGlobal -Name 'uso')
        Set-UdpGlobalSafe -Name 'uro' -State (Get-SnapshotUdpOffloadState -UdpGlobal $snapshot.UdpGlobal -Name 'uro')
    }
} catch { Write-Warning $_.Exception.Message }

try {
    if ((Get-Command Set-NetAdapterAdvancedProperty -ErrorAction SilentlyContinue) -and $snapshot.AdvancedProperties) {
        foreach ($prop in $snapshot.AdvancedProperties) {
            if (-not [string]::IsNullOrWhiteSpace([string]$prop.DisplayName)) {
                Set-NetAdapterAdvancedProperty -Name $adapterName -DisplayName ([string]$prop.DisplayName) -DisplayValue ([string]$prop.DisplayValue) -NoRestart -ErrorAction SilentlyContinue | Out-Null
            }
        }
    }
} catch { Write-Warning $_.Exception.Message }

try {
    if ((Get-Command Set-NetAdapterPowerManagement -ErrorAction SilentlyContinue) -and $snapshot.PowerManagement) {
        $params = @{ Name = $adapterName; ErrorAction = 'SilentlyContinue' }
        foreach ($p in $snapshot.PowerManagement.PSObject.Properties) {
            if (-not [string]::IsNullOrWhiteSpace([string]$p.Value)) { $params[$p.Name] = [string]$p.Value }
        }
        if ($params.Count -gt 2) { Set-NetAdapterPowerManagement @params | Out-Null }
    }
} catch { Write-Warning $_.Exception.Message }

Write-Host "GStreamer Glass network settings restored from $SnapshotPath"
'@
    $scriptText = $template.Replace('__SNAPSHOT_PATH__', $script:NetworkSnapshotPath.Replace("'", "''"))
    Set-Content -LiteralPath $script:NetworkRecoveryScriptPath -Value $scriptText -Encoding UTF8
}

function Save-NetworkSnapshot {
    param([switch]$Quiet)

    Ensure-NetworkRecoveryDirectory
    $adapterName = Get-SelectedNetworkAdapterName
    if ([string]::IsNullOrWhiteSpace($adapterName)) {
        throw 'Select a network adapter first.'
    }

    $snapshot = Get-NetworkSnapshotObject -AdapterName $adapterName
    $json = $snapshot | ConvertTo-Json -Depth 12
    $json | Set-Content -LiteralPath $script:NetworkSnapshotPath -Encoding UTF8
    $timestampPath = Join-Path $script:NetworkRecoveryDirectory ("network-snapshot-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $json | Set-Content -LiteralPath $timestampPath -Encoding UTF8
    Write-NetworkRecoveryScript

    if (-not $Quiet) {
        Append-Log "Network tuning snapshot saved: $script:NetworkSnapshotPath"
        $lblNetworkStatus.Text = "Snapshot saved for $adapterName"
        $lblNetworkStatus.ForeColor = [System.Drawing.Color]::DarkGreen
    }

    return $snapshot
}

function Set-NetworkAppliedState {
    param([bool]$Active)
    Ensure-NetworkRecoveryDirectory
    $script:NetworkTuningApplied = $Active
    [ordered]@{
        Active = $Active
        Timestamp = (Get-Date).ToString('o')
        SnapshotPath = $script:NetworkSnapshotPath
        AdapterName = Get-SelectedNetworkAdapterName
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:NetworkAppliedStatePath -Encoding UTF8
}

function Get-NetworkAppliedState {
    try {
        if (Test-Path -LiteralPath $script:NetworkAppliedStatePath) {
            return Get-Content -LiteralPath $script:NetworkAppliedStatePath -Raw | ConvertFrom-Json
        }
    }
    catch {}
    return $null
}

function Register-NetworkRecoveryTask {
    if (-not $chkNetworkRecoveryTask.Checked) { return }
    try {
        Write-NetworkRecoveryScript
        $tr = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$script:NetworkRecoveryScriptPath`""
        & schtasks.exe /Create /TN $script:NetworkRecoveryTaskName /SC ONLOGON /TR $tr /F 2>&1 | Out-Null
        Append-Log "Network recovery task registered: $script:NetworkRecoveryTaskName"
    }
    catch {
        Append-Log "Network tuning warning: recovery task registration failed - $($_.Exception.Message)"
    }
}

function Unregister-NetworkRecoveryTask {
    try {
        & schtasks.exe /Delete /TN $script:NetworkRecoveryTaskName /F 2>&1 | Out-Null
    }
    catch {}
}

function Set-AdapterAdvancedPropertyByCandidates {
    param(
        [Parameter(Mandatory)][string]$AdapterName,
        [Parameter(Mandatory)][string[]]$DisplayNames,
        [Parameter(Mandatory)][string[]]$DesiredValues
    )

    if (-not (Get-Command Get-NetAdapterAdvancedProperty -ErrorAction SilentlyContinue) -or -not (Get-Command Set-NetAdapterAdvancedProperty -ErrorAction SilentlyContinue)) {
        return $false
    }

    foreach ($displayName in $DisplayNames) {
        $prop = $null
        try { $prop = Get-NetAdapterAdvancedProperty -Name $AdapterName -DisplayName $displayName -ErrorAction SilentlyContinue | Select-Object -First 1 } catch {}
        if (-not $prop) {
            try { $prop = Get-NetAdapterAdvancedProperty -Name $AdapterName -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*$displayName*" } | Select-Object -First 1 } catch {}
        }
        if (-not $prop) { continue }

        foreach ($desired in $DesiredValues) {
            try {
                Set-NetAdapterAdvancedProperty -Name $AdapterName -DisplayName $prop.DisplayName -DisplayValue $desired -NoRestart -ErrorAction Stop | Out-Null
                Append-Log "Network tuning: $($prop.DisplayName) -> $desired"
                return $true
            }
            catch {}
        }
    }

    return $false
}

function Set-NetworkPowerSavingDisabled {
    param([Parameter(Mandatory)][string]$AdapterName)
    if (-not (Get-Command Set-NetAdapterPowerManagement -ErrorAction SilentlyContinue)) { return $false }
    try {
        Set-NetAdapterPowerManagement -Name $AdapterName -AllowComputerToTurnOffDevice Disabled -ErrorAction Stop | Out-Null
        Append-Log 'Network tuning: adapter power saving disabled.'
        return $true
    }
    catch {
        Append-Log "Network tuning warning: adapter power saving was not changed - $($_.Exception.Message)"
        return $false
    }
}

function Apply-NetworkProfileToUi {
    $profile = [string]$cmbNetworkProfile.SelectedItem
    switch ($profile) {
        'No changes' {
            $chkNetworkTuningEnabled.Checked = $false
            $chkNetworkDscp.Checked = $false
            $cmbNetworkUso.SelectedItem = 'Leave unchanged'
            $cmbNetworkUro.SelectedItem = 'Leave unchanged'
            $chkNetworkDisablePowerSaving.Checked = $false
            $cmbNetworkInterruptModeration.SelectedItem = 'Leave unchanged'
            $chkNetworkDisableEee.Checked = $false
        }
        'Low latency LAN' {
            $chkNetworkTuningEnabled.Checked = $true
            $chkNetworkDscp.Checked = $true
            $numNetworkDscp.Value = 34
            $cmbNetworkQosProtocol.SelectedItem = 'UDP'
            $cmbNetworkUso.SelectedItem = 'Leave unchanged'
            $cmbNetworkUro.SelectedItem = 'Disable'
            $chkNetworkDisablePowerSaving.Checked = $true
            $cmbNetworkInterruptModeration.SelectedItem = 'Disable'
            $chkNetworkDisableEee.Checked = $true
            $chkNetworkRestoreOnStop.Checked = $true
            $chkNetworkRestoreOnExit.Checked = $true
            $chkNetworkRecoveryTask.Checked = $true
        }
        'Stable WAN' {
            $chkNetworkTuningEnabled.Checked = $true
            $chkNetworkDscp.Checked = $true
            $numNetworkDscp.Value = 34
            $cmbNetworkQosProtocol.SelectedItem = 'UDP'
            $cmbNetworkUso.SelectedItem = 'Enable'
            $cmbNetworkUro.SelectedItem = 'Enable'
            $chkNetworkDisablePowerSaving.Checked = $true
            $cmbNetworkInterruptModeration.SelectedItem = 'Enable / Adaptive'
            $chkNetworkDisableEee.Checked = $true
            $chkNetworkRestoreOnStop.Checked = $true
            $chkNetworkRestoreOnExit.Checked = $true
            $chkNetworkRecoveryTask.Checked = $true
        }
    }
    Update-NetworkUi
}

function Update-NetworkUi {
    $enabled = [bool]$chkNetworkTuningEnabled.Checked
    foreach ($control in @($cmbNetworkAdapter,$btnRefreshNetworkAdapters,$cmbNetworkProfile,$chkNetworkRestoreOnStop,$chkNetworkRestoreOnExit,$chkNetworkRecoveryTask,$btnNetworkSnapshot,$btnNetworkRestore,$btnOpenNetworkRecovery,$btnResetNetwork)) {
        if ($control) { $control.Enabled = $true }
    }
    foreach ($control in @($chkNetworkDscp,$numNetworkDscp,$cmbNetworkQosProtocol,$txtNetworkPorts,$cmbNetworkUso,$cmbNetworkUro,$chkNetworkDisablePowerSaving,$cmbNetworkInterruptModeration,$chkNetworkDisableEee,$btnNetworkApply)) {
        if ($control) { $control.Enabled = $enabled }
    }
    $numNetworkDscp.Enabled = $enabled -and $chkNetworkDscp.Checked
    $cmbNetworkQosProtocol.Enabled = $enabled -and $chkNetworkDscp.Checked
    $txtNetworkPorts.Enabled = $enabled -and $chkNetworkDscp.Checked

    if ($enabled) {
        $lblNetworkStatus.Text = 'Network tuning armed - snapshot required before apply.'
        $lblNetworkStatus.ForeColor = [System.Drawing.Color]::DarkOrange
    }
    else {
        $lblNetworkStatus.Text = 'Network tuning disabled'
        $lblNetworkStatus.ForeColor = [System.Drawing.Color]::DimGray
    }
}

function New-QosPolicyForGStreamer {
    param([Parameter(Mandatory)][int]$DscpValue)

    if (-not (Get-Command New-NetQosPolicy -ErrorAction SilentlyContinue)) {
        Append-Log 'Network tuning warning: New-NetQosPolicy is unavailable.'
        return
    }

    $policyName = 'GStreamerGlass-Transport'
    try { Remove-NetQosPolicy -Name $policyName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}

    $params = @{
        Name = $policyName
        AppPathNameMatchCondition = 'gst-launch-1.0.exe'
        DSCPAction = $DscpValue
        ErrorAction = 'Stop'
    }

    $proto = [string]$cmbNetworkQosProtocol.SelectedItem
    if ($proto -in @('UDP','TCP')) { $params.IPProtocolMatchCondition = $proto }

    $ports = $txtNetworkPorts.Text.Trim()
    if (-not [string]::IsNullOrWhiteSpace($ports)) {
        $params.IPDstPortMatchCondition = $ports
    }

    try {
        New-NetQosPolicy @params | Out-Null
        Append-Log "Network tuning: QoS DSCP policy created for gst-launch-1.0.exe DSCP=$DscpValue protocol=$proto ports=$(if ($ports) { $ports } else { 'any' })."
    }
    catch {
        Append-Log "Network tuning warning: QoS policy failed - $($_.Exception.Message)"
    }
}

function Apply-NetworkTuningForSession {
    if (-not $chkNetworkTuningEnabled.Checked) { return $true }

    if (-not (Test-IsAdministrator)) {
        [System.Windows.Forms.MessageBox]::Show(
            'Windows network tuning requires running GStreamer Glass as Administrator. No OS tuning was applied.',
            $script:AppName,
            'OK',
            'Warning'
        ) | Out-Null
        return $false
    }

    try {
        $snapshot = Save-NetworkSnapshot -Quiet
        Register-NetworkRecoveryTask
        $adapterName = [string]$snapshot.AdapterName

        Append-Log "Network tuning: applying profile '$([string]$cmbNetworkProfile.SelectedItem)' to adapter '$adapterName'."

        if ($chkNetworkDscp.Checked) {
            New-QosPolicyForGStreamer -DscpValue ([int]$numNetworkDscp.Value)
        }

        switch ([string]$cmbNetworkUso.SelectedItem) {
            'Enable' { Set-UdpGlobalOffload -Name uso -State enabled | Out-Null }
            'Disable' { Set-UdpGlobalOffload -Name uso -State disabled | Out-Null }
        }
        switch ([string]$cmbNetworkUro.SelectedItem) {
            'Enable' { Set-UdpGlobalOffload -Name uro -State enabled | Out-Null }
            'Disable' { Set-UdpGlobalOffload -Name uro -State disabled | Out-Null }
        }

        if ($chkNetworkDisablePowerSaving.Checked) {
            Set-NetworkPowerSavingDisabled -AdapterName $adapterName | Out-Null
        }

        switch ([string]$cmbNetworkInterruptModeration.SelectedItem) {
            'Disable' {
                Set-AdapterAdvancedPropertyByCandidates -AdapterName $adapterName -DisplayNames @('Interrupt Moderation','Interrupt Moderation Rate') -DesiredValues @('Disabled','Off') | Out-Null
            }
            'Enable / Adaptive' {
                Set-AdapterAdvancedPropertyByCandidates -AdapterName $adapterName -DisplayNames @('Interrupt Moderation','Interrupt Moderation Rate') -DesiredValues @('Adaptive','Enabled','On') | Out-Null
            }
        }

        if ($chkNetworkDisableEee.Checked) {
            Set-AdapterAdvancedPropertyByCandidates -AdapterName $adapterName -DisplayNames @('Energy Efficient Ethernet','EEE','Green Ethernet','Advanced EEE') -DesiredValues @('Disabled','Off') | Out-Null
        }

        Set-NetworkAppliedState -Active $true
        $lblNetworkStatus.Text = 'Network tuning applied. Recovery snapshot saved.'
        $lblNetworkStatus.ForeColor = [System.Drawing.Color]::DarkGreen
        return $true
    }
    catch {
        Append-Log "Network tuning failed before stream start: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            "Network tuning failed before stream start.`r`n`r`n$($_.Exception.Message)",
            $script:AppName,
            'OK',
            'Warning'
        ) | Out-Null
        return $false
    }
}

function Restore-NetworkTuning {
    param([switch]$Quiet)

    if (-not (Test-Path -LiteralPath $script:NetworkSnapshotPath)) {
        if (-not $Quiet) { Append-Log 'Network restore: no snapshot found.' }
        return $false
    }

    if (-not (Test-IsAdministrator)) {
        if (-not $Quiet) {
            [System.Windows.Forms.MessageBox]::Show(
                'Restoring Windows network tuning requires running as Administrator.',
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
        }
        return $false
    }

    try {
        $snapshot = Get-Content -LiteralPath $script:NetworkSnapshotPath -Raw | ConvertFrom-Json
        $adapterName = [string]$snapshot.AdapterName
        Append-Log "Network restore: restoring adapter '$adapterName' from $script:NetworkSnapshotPath"

        try {
            if (Get-Command Remove-NetQosPolicy -ErrorAction SilentlyContinue) {
                Remove-NetQosPolicy -Name ([string]$snapshot.QosPolicyName) -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                Append-Log 'Network restore: removed GStreamer Glass QoS policy.'
            }
        }
        catch {}

        if ($snapshot.UdpGlobal) {
            $usoRestoreState = Get-SnapshotUdpOffloadState -UdpGlobal $snapshot.UdpGlobal -Name uso
            $uroRestoreState = Get-SnapshotUdpOffloadState -UdpGlobal $snapshot.UdpGlobal -Name uro
            if ($usoRestoreState) {
                Set-UdpGlobalOffload -Name uso -State $usoRestoreState | Out-Null
            }
            elseif ($snapshot.UdpGlobal.Uso) {
                Append-Log "Network restore: skipped invalid saved UDP USO state '$($snapshot.UdpGlobal.Uso)'."
            }
            if ($uroRestoreState) {
                Set-UdpGlobalOffload -Name uro -State $uroRestoreState | Out-Null
            }
            elseif ($snapshot.UdpGlobal.Uro) {
                Append-Log "Network restore: skipped invalid saved UDP URO state '$($snapshot.UdpGlobal.Uro)'."
            }
        }

        if ((Get-Command Set-NetAdapterAdvancedProperty -ErrorAction SilentlyContinue) -and $snapshot.AdvancedProperties) {
            foreach ($prop in $snapshot.AdvancedProperties) {
                if (-not [string]::IsNullOrWhiteSpace([string]$prop.DisplayName)) {
                    try {
                        Set-NetAdapterAdvancedProperty -Name $adapterName -DisplayName ([string]$prop.DisplayName) -DisplayValue ([string]$prop.DisplayValue) -NoRestart -ErrorAction SilentlyContinue | Out-Null
                    }
                    catch {}
                }
            }
            Append-Log 'Network restore: adapter advanced properties restored where supported.'
        }

        if ((Get-Command Set-NetAdapterPowerManagement -ErrorAction SilentlyContinue) -and $snapshot.PowerManagement) {
            try {
                $params = @{ Name = $adapterName; ErrorAction = 'SilentlyContinue' }
                foreach ($p in $snapshot.PowerManagement.PSObject.Properties) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$p.Value)) { $params[$p.Name] = [string]$p.Value }
                }
                if ($params.Count -gt 2) { Set-NetAdapterPowerManagement @params | Out-Null }
                Append-Log 'Network restore: adapter power management restored where supported.'
            }
            catch {}
        }

        Unregister-NetworkRecoveryTask
        Set-NetworkAppliedState -Active $false
        $lblNetworkStatus.Text = 'Network settings restored from snapshot.'
        $lblNetworkStatus.ForeColor = [System.Drawing.Color]::DarkGreen
        return $true
    }
    catch {
        Append-Log "Network restore failed: $($_.Exception.Message)"
        if (-not $Quiet) {
            [System.Windows.Forms.MessageBox]::Show(
                "Network restore failed.`r`n`r`n$($_.Exception.Message)",
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
        }
        return $false
    }
}

function Check-PendingNetworkRecovery {
    $state = Get-NetworkAppliedState
    if ($state -and $state.Active -eq $true) {
        $result = [System.Windows.Forms.MessageBox]::Show(
            "GStreamer Glass detected Windows network tuning from a previous session.`r`n`r`nRestore the saved network snapshot now?",
            $script:AppName,
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            Restore-NetworkTuning | Out-Null
        }
        else {
            $lblNetworkStatus.Text = 'Previous network tuning is still marked active.'
            $lblNetworkStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
    }
}

function Reset-WebRtcSaneDefaults {
    $cmbDirectWebRtcCongestion.SelectedItem = 'disabled'
    $cmbDirectWebRtcMitigation.SelectedItem = 'none'
    if ($cmbWebRtcRecoveryMode.Items.Contains($script:DefaultWebRtcRecoveryMode)) { $cmbWebRtcRecoveryMode.SelectedItem = $script:DefaultWebRtcRecoveryMode }
    if ($cmbWebRtcSenderQueueMode.Items.Contains($script:DefaultWebRtcSenderQueueMode)) { $cmbWebRtcSenderQueueMode.SelectedItem = $script:DefaultWebRtcSenderQueueMode }
    $chkDirectWebRtcFec.Checked = $false
    $chkDirectWebRtcRetransmission.Checked = $false
    if ($cmbWebRtcRecoveryMode.Items.Contains($script:DefaultWebRtcRecoveryMode)) { Set-WebRtcRecoveryMode $script:DefaultWebRtcRecoveryMode }
    if ($cmbDirectWebRtcSmoothnessProfile.Items.Contains($script:DefaultDirectWebRtcSmoothnessProfile)) { $cmbDirectWebRtcSmoothnessProfile.SelectedItem = $script:DefaultDirectWebRtcSmoothnessProfile }
    $numDirectWebRtcPacingMs.Value = $script:DefaultDirectWebRtcPacingMs
    $numDirectWebRtcPlayerJitterMs.Value = $script:DefaultDirectWebRtcPlayerJitterMs
    $numDirectWebRtcVideoJitterMs.Value = $script:DefaultDirectWebRtcVideoJitterMs
    $numJbufMaxMs.Value = $script:DefaultJbufMaxMs
    if ($cmbJbufWatchdogMode.Items.Contains($script:DefaultJbufWatchdogMode)) { $cmbJbufWatchdogMode.SelectedItem = $script:DefaultJbufWatchdogMode }
    $chkPlayerStatsOverlay.Checked = $script:DefaultPlayerStatsOverlay
    $chkPlayerJbufDebug.Checked = $script:DefaultPlayerJbufDebug
    $numLiveEdgeAverageSec.Value = $script:DefaultLiveEdgeAverageSec
    $numLiveEdgeGreenMs.Value = $script:DefaultLiveEdgeGreenMs
    $numLiveEdgeYellowMs.Value = $script:DefaultLiveEdgeYellowMs
    $chkPlayerUrlOverrides.Checked = $script:DefaultPlayerUrlOverrides
    if ($cmbTimingMode.Items.Contains($script:DefaultTimingMode)) { $cmbTimingMode.SelectedItem = $script:DefaultTimingMode }
    $chkSplitClockSignalingOverrides.Checked = $script:DefaultSplitClockSignalingOverrides
    if ($cmbSplitVideoClockSignaling.Items.Contains($script:DefaultSplitVideoClockSignaling)) { $cmbSplitVideoClockSignaling.SelectedItem = $script:DefaultSplitVideoClockSignaling }
    if ($cmbSplitAudioClockSignaling.Items.Contains($script:DefaultSplitAudioClockSignaling)) { $cmbSplitAudioClockSignaling.SelectedItem = $script:DefaultSplitAudioClockSignaling }
    $chkDirectWebRtcControlDataChannel.Checked = $script:DefaultDirectWebRtcControlDataChannel
    if ($cmbDirectWebRtcBundlePolicy.Items.Contains($script:DefaultDirectWebRtcBundlePolicy)) { $cmbDirectWebRtcBundlePolicy.SelectedItem = $script:DefaultDirectWebRtcBundlePolicy }
    $numDirectWebRtcInternalRtpMtu.Value = $script:DefaultDirectWebRtcInternalRtpMtu
    $chkDirectWebRtcInternalRepeatHeaders.Checked = $script:DefaultDirectWebRtcInternalRepeatHeaders
    $chkPlayerSeparateHtmlMediaElements.Checked = $script:DefaultPlayerSeparateHtmlMediaElements
    if ($cmbDirectWebRtcAvPipelineMode.Items.Contains($script:DefaultDirectWebRtcAvPipelineMode)) { $cmbDirectWebRtcAvPipelineMode.SelectedItem = $script:DefaultDirectWebRtcAvPipelineMode }
    if ($cmbSplitPlayerSyncMode.Items.Contains($script:DefaultSplitPlayerSyncMode)) { $cmbSplitPlayerSyncMode.SelectedItem = $script:DefaultSplitPlayerSyncMode }
    $numSplitAudioStallSeconds.Value = $script:DefaultSplitAudioStallSeconds
    $numSplitAudioWarmupSeconds.Value = $script:DefaultSplitAudioWarmupSeconds
    $numSplitAvOffsetBaselineMs.Value = $script:DefaultSplitAvOffsetBaselineMs
    $numSplitAvOffsetWarnMs.Value = $script:DefaultSplitAvOffsetWarnMs
    Update-DirectWebRtcUi
    Update-CommandPreview
}

function Reset-TransportDefaults {
    $chkTransportEnabled.Checked = $true
    $cmbProtocol.SelectedItem = 'WHIP'
    $script:ProtocolDestinations.WHIP = 'http://10.0.0.25:8889/live/whip'
    $script:ProtocolDestinations.SRT = 'srt://10.0.0.25:8890?mode=caller&streamid=publish:live'
    $script:ProtocolDestinations.RTMP = 'rtmp://10.0.0.25/live'
    $script:ProtocolDestinations.RTSP = 'rtsp://10.0.0.25:8554/live'
    $script:ProtocolDestinations[$script:DirectWebRtcProtocolName] = $script:DefaultDirectWebRtcWebAddress
    $txtDestination.Text = $script:ProtocolDestinations.WHIP
    $txtDirectWebRtcSignalingHost.Text = $script:DefaultDirectWebRtcSignalingHost
    $numDirectWebRtcSignalingPort.Value = $script:DefaultDirectWebRtcSignalingPort
    $numDirectWebRtcSplitAudioSignalingPort.Value = $script:DefaultDirectWebRtcSplitAudioSignalingPort
    $chkDirectWebRtcSharedSignaling.Checked = $script:DefaultDirectWebRtcSharedSignaling
    if ($cmbDirectWebRtcMediaStreamGrouping.Items.Contains($script:DefaultDirectWebRtcMediaStreamGrouping)) { $cmbDirectWebRtcMediaStreamGrouping.SelectedItem = $script:DefaultDirectWebRtcMediaStreamGrouping }
    $txtDirectWebRtcVideoMediaStreamId.Text = $script:DefaultDirectWebRtcVideoMediaStreamId
    $txtDirectWebRtcAudioMediaStreamId.Text = $script:DefaultDirectWebRtcAudioMediaStreamId
    $chkDirectWebRtcUnifiedPublisher.Checked = $script:DefaultDirectWebRtcUnifiedPublisher
    $numDirectWebRtcBridgeVideoPort.Value = $script:DefaultDirectWebRtcBridgeVideoPort
    $numDirectWebRtcBridgeAudioPort.Value = $script:DefaultDirectWebRtcBridgeAudioPort
    $numDirectWebRtcBridgeJitterMs.Value = $script:DefaultDirectWebRtcBridgeJitterMs
    $numDirectWebRtcPublisherQueueMs.Value = $script:DefaultDirectWebRtcPublisherQueueMs
    $chkDirectWebRtcAudioBridgePacing.Checked = $script:DefaultDirectWebRtcAudioBridgePacing
    if ($cmbTimingMode.Items.Contains($script:DefaultTimingMode)) { $cmbTimingMode.SelectedItem = $script:DefaultTimingMode }
    $chkSplitClockSignalingOverrides.Checked = $script:DefaultSplitClockSignalingOverrides
    if ($cmbSplitVideoClockSignaling.Items.Contains($script:DefaultSplitVideoClockSignaling)) { $cmbSplitVideoClockSignaling.SelectedItem = $script:DefaultSplitVideoClockSignaling }
    if ($cmbSplitAudioClockSignaling.Items.Contains($script:DefaultSplitAudioClockSignaling)) { $cmbSplitAudioClockSignaling.SelectedItem = $script:DefaultSplitAudioClockSignaling }
    $chkDirectWebRtcControlDataChannel.Checked = $script:DefaultDirectWebRtcControlDataChannel
    if ($cmbDirectWebRtcBundlePolicy.Items.Contains($script:DefaultDirectWebRtcBundlePolicy)) { $cmbDirectWebRtcBundlePolicy.SelectedItem = $script:DefaultDirectWebRtcBundlePolicy }
    $numDirectWebRtcInternalRtpMtu.Value = $script:DefaultDirectWebRtcInternalRtpMtu
    $chkDirectWebRtcInternalRepeatHeaders.Checked = $script:DefaultDirectWebRtcInternalRepeatHeaders
    $txtDirectWebRtcStun.Text = $script:DefaultDirectWebRtcStunServer
    $chkDirectWebRtcTurnEnabled.Checked = $script:DefaultDirectWebRtcTurnEnabled
    $txtDirectWebRtcTurn.Text = $script:DefaultDirectWebRtcTurnServer
    $txtDirectWebRtcWebPath.Text = $script:DefaultDirectWebRtcWebPath
    if ($cmbDirectWebRtcBundledWebMode.Items.Contains($script:DefaultDirectWebRtcBundledWebMode)) { $cmbDirectWebRtcBundledWebMode.SelectedItem = $script:DefaultDirectWebRtcBundledWebMode }
    $txtDirectWebRtcBundledWebDirectory.Text = $script:DefaultDirectWebRtcBundledWebDirectory
    if ($cmbDirectWebRtcWorkingWebMode.Items.Contains($script:DefaultDirectWebRtcWorkingWebMode)) { $cmbDirectWebRtcWorkingWebMode.SelectedItem = $script:DefaultDirectWebRtcWorkingWebMode }
    $txtDirectWebRtcWebDirectory.Text = $script:DefaultDirectWebRtcWorkingWebDirectory
    Reset-WebRtcSaneDefaults
    $numMonitor.Value = -1
    $chkCursor.Checked = $true
    $chkSendAbsoluteTimestamps.Checked = $false
    $chkStartMediaMtx.Checked = $false
    $txtMediaMtxPath.Text = Find-MediaMtx
    $numSrtLatency.Value = 50
    $cmbRtspTransport.SelectedItem = 'TCP'
    if ($cmbTimingMode.Items.Contains($script:DefaultTimingMode)) { $cmbTimingMode.SelectedItem = $script:DefaultTimingMode }
    Update-TransportUi
    Update-DirectWebRtcUi
    Update-CaptureModeUi
}

function Reset-VideoDefaults {
    $cmbCaptureMethod.SelectedItem = $script:DefaultCaptureMethodName
    $numWidth.Value = 1920
    $numHeight.Value = 1080
    $numFps.Value = 60
    $numVideoBitrate.Value = 12000
    $numMaxVideoBitrate.Value = 0
    $numConstantQp.Value = 20
    $numGopSeconds.Value = 1
    $chkUnifiedBridgeKeyframeGuard.Checked = $script:DefaultUnifiedBridgeKeyframeGuard
    $numUnifiedBridgeKeyframeIntervalMs.Value = $script:DefaultUnifiedBridgeKeyframeIntervalMs
    $cmbEncoder.SelectedItem = $script:DefaultEncoderName
    $cmbRateControl.SelectedItem = 'cbr'
    $cmbPreset.SelectedItem = 'p1'
    $cmbProfile.SelectedItem = 'constrained-baseline'
    $cmbEncoderTune.SelectedItem = 'ultra-low-latency'
    $cmbMultipass.SelectedItem = 'disabled'
    if ($cmbVideoPipelineClockMode.Items.Contains($script:DefaultVideoPipelineClockMode)) { $cmbVideoPipelineClockMode.SelectedItem = $script:DefaultVideoPipelineClockMode }
    if ($cmbVideoTimestampMode.Items.Contains($script:DefaultVideoTimestampMode)) { $cmbVideoTimestampMode.SelectedItem = $script:DefaultVideoTimestampMode }
    if ($cmbVideoSyncMode.Items.Contains($script:DefaultVideoSyncMode)) { $cmbVideoSyncMode.SelectedItem = $script:DefaultVideoSyncMode }
    $numVbvBuffer.Value = 0
    $numBFrames.Value = 0
    $chkLookAhead.Checked = $false
    $numLookAheadFrames.Value = 20
    $chkAdaptiveQuantization.Checked = $false
    $chkTemporalAq.Checked = $false
    $numAqStrength.Value = 8
    $txtCustomEncoderOptions.Text = ''
    $numSceneInputQueueBuffers.Value = $script:DefaultSceneInputQueueBuffers
    $numSceneInputQueueCapMs.Value = $script:DefaultSceneInputQueueCapMs
    Update-CaptureModeUi
    Update-EncoderUi
}

function Reset-AudioDefaults {
    if ($cmbAudioTransportMode.Items.Contains($script:DefaultAudioTransportMode)) { $cmbAudioTransportMode.SelectedItem = $script:DefaultAudioTransportMode }
    if ($cmbSplitAudioPipelineClockMode.Items.Contains($script:DefaultSplitAudioPipelineClockMode)) { $cmbSplitAudioPipelineClockMode.SelectedItem = $script:DefaultSplitAudioPipelineClockMode }
    if ($cmbAudioClockMode.Items.Contains($script:DefaultAudioClockMode)) { $cmbAudioClockMode.SelectedItem = $script:DefaultAudioClockMode }
    if ($cmbAudioTimingMode.Items.Contains($script:DefaultAudioTimingMode)) { $cmbAudioTimingMode.SelectedItem = $script:DefaultAudioTimingMode }
    if ($cmbAudioSlaveMethod.Items.Contains($script:DefaultAudioSlaveMethod)) { $cmbAudioSlaveMethod.SelectedItem = $script:DefaultAudioSlaveMethod }
    if ($cmbAudioSyncMode.Items.Contains($script:DefaultAudioSyncMode)) { $cmbAudioSyncMode.SelectedItem = $script:DefaultAudioSyncMode }
    $chkWasapiLowLatencyOverride.Checked = $script:DefaultWasapiLowLatencyOverride
    $chkAudioBufferOverride.Checked = $script:DefaultAudioBufferOverride
    $numAudioBufferMs.Value = $script:DefaultAudioBufferMs
    $chkAudioLatencyOverride.Checked = $script:DefaultAudioLatencyOverride
    $numAudioLatencyMs.Value = $script:DefaultAudioLatencyMs
    $chkAudioSampleRateOverride.Checked = $script:DefaultAudioSampleRateOverride
    $numAudioSampleRate.Value = $script:DefaultAudioSampleRate
    $chkDesktopAudio.Checked = $true
    $chkAudioMixerMode.Checked = $script:DefaultAudioMixerMode
    $numDesktopVolume.Value = 100
    if ($cmbDesktopAudioDevice -and $cmbDesktopAudioDevice.Items.Contains($script:DefaultAudioOutputDeviceLabel)) { $cmbDesktopAudioDevice.SelectedItem = $script:DefaultAudioOutputDeviceLabel }
    $chkMic.Checked = $false
    $numMicVolume.Value = 100
    if ($cmbMicAudioDevice -and $cmbMicAudioDevice.Items.Contains($script:DefaultAudioInputDeviceLabel)) { $cmbMicAudioDevice.SelectedItem = $script:DefaultAudioInputDeviceLabel }
    $script:ProtocolAudioCodecs.WHIP = 'Opus'
    $script:ProtocolAudioCodecs.SRT = 'Opus'
    $script:ProtocolAudioCodecs.RTMP = 'AAC'
    $script:ProtocolAudioCodecs.RTSP = 'Opus'
    $cmbAudioCodec.SelectedItem = $script:ProtocolAudioCodecs[([string]$cmbProtocol.SelectedItem)]
    $numAudioBitrate.Value = 160
    if ($cmbDirectWebRtcOpusMode.Items.Contains($script:DefaultDirectWebRtcOpusMode)) { $cmbDirectWebRtcOpusMode.SelectedItem = $script:DefaultDirectWebRtcOpusMode }
    if ($cmbDirectWebRtcOpusFrameMs.Items.Contains($script:DefaultDirectWebRtcOpusFrameMs)) { $cmbDirectWebRtcOpusFrameMs.SelectedItem = $script:DefaultDirectWebRtcOpusFrameMs }
    if ($cmbDirectWebRtcOpusAudioType.Items.Contains($script:DefaultDirectWebRtcOpusAudioType)) { $cmbDirectWebRtcOpusAudioType.SelectedItem = $script:DefaultDirectWebRtcOpusAudioType }
    $chkDirectWebRtcOpusFec.Checked = $script:DefaultDirectWebRtcOpusFec
    $chkDirectWebRtcOpusDtx.Checked = $script:DefaultDirectWebRtcOpusDtx
    Update-AudioCodecChoices
}

function Reset-RecordingDefaults {
    $chkRecordingEnabled.Checked = $false
    $txtRecordingDirectory.Text = Join-Path ([Environment]::GetFolderPath('MyVideos')) 'GStreamer Glass'
    $txtRecordingTemplate.Text = 'Glass-{yyyyMMdd-HHmmss}-{protocol}-{width}x{height}-{fps}fps.mkv'
    $cmbRecordingEncoder.SelectedItem = $script:DefaultEncoderName
    $cmbRecordingRateControl.SelectedItem = 'constqp'
    $numRecordingVideoBitrate.Value = 24000
    $numRecordingMaxVideoBitrate.Value = 0
    $numRecordingConstantQp.Value = 20
    $numRecordingWidth.Value = 1920
    $numRecordingHeight.Value = 1080
    $numRecordingFps.Value = 60
    $numRecordingGopSeconds.Value = 2
    $numRecordingBFrames.Value = 2
    $cmbRecordingPreset.SelectedItem = 'p5'
    $cmbRecordingProfile.SelectedItem = 'high'
    $cmbRecordingTune.SelectedItem = 'high-quality'
    $cmbRecordingMultipass.SelectedItem = 'two-pass-quarter'
    $chkRecordingLookAhead.Checked = $false
    $numRecordingLookAheadFrames.Value = 20
    $chkRecordingSpatialAq.Checked = $true
    $chkRecordingTemporalAq.Checked = $true
    $numRecordingAqStrength.Value = 8
    $numRecordingVbvBuffer.Value = 0
    $txtRecordingCustomEncoderOptions.Text = ''
    $chkRecordingDesktopAudio.Checked = $true
    $chkRecordingMic.Checked = $false
    $numRecordingAudioBitrate.Value = 192
    Update-RecordingUi
}

function Reset-NetworkDefaults {
    $chkNetworkTuningEnabled.Checked = $false
    $cmbNetworkProfile.SelectedItem = 'No changes'
    $chkNetworkDscp.Checked = $false
    $numNetworkDscp.Value = 34
    $cmbNetworkQosProtocol.SelectedItem = 'UDP'
    $txtNetworkPorts.Text = ''
    $cmbNetworkUso.SelectedItem = 'Leave unchanged'
    $cmbNetworkUro.SelectedItem = 'Leave unchanged'
    $chkNetworkDisablePowerSaving.Checked = $false
    $cmbNetworkInterruptModeration.SelectedItem = 'Leave unchanged'
    $chkNetworkDisableEee.Checked = $false
    $chkNetworkRestoreOnStop.Checked = $true
    $chkNetworkRestoreOnExit.Checked = $true
    $chkNetworkRecoveryTask.Checked = $true
    Update-NetworkUi
}

function Reset-OptionsDefaults {
    $txtGstPath.Text = Find-GstLaunch
    $chkPreview.Checked = $false
    $chkHidePreviewDuringStream.Checked = $false
    $chkAutoRestart.Checked = $true
    $chkVerbose.Checked = $false
    $chkDiskProcessLogging.Checked = $script:DefaultDiskProcessLogging
    $chkMinimizeToTray.Checked = $true
    $chkStartMinimized.Checked = $false
    if ($cmbThreadingProfile.Items.Contains($script:DefaultThreadingProfile)) { $cmbThreadingProfile.SelectedItem = $script:DefaultThreadingProfile }
    if ($cmbThreadBudget.Items.Contains($script:DefaultThreadBudget)) { $cmbThreadBudget.SelectedItem = $script:DefaultThreadBudget }
    if ($cmbGstDebugMode.Items.Contains($script:DefaultGstDebugMode)) { $cmbGstDebugMode.SelectedItem = $script:DefaultGstDebugMode }
    $txtGstDebugSpec.Text = $script:DefaultGstDebugSpec
    $chkGstDebugNoColor.Checked = $script:DefaultGstDebugNoColor
    if ($cmbJbufWatchdogMode.Items.Contains($script:DefaultJbufWatchdogMode)) { $cmbJbufWatchdogMode.SelectedItem = $script:DefaultJbufWatchdogMode }
    $numJbufMaxMs.Value = $script:DefaultJbufMaxMs
    Apply-ThreadingProfile -Force
    Apply-ThreadBudget -Force
    Update-CommandPreview
}

function Reset-AllAppDefaults {
    Reset-TransportDefaults
    Reset-VideoDefaults
    Reset-AudioDefaults
    Reset-RecordingDefaults
    Reset-NetworkDefaults
    Reset-OptionsDefaults
    Save-Settings
    Append-Log 'All GStreamer Glass app settings reset to defaults. Windows network snapshots were not touched.'
    Update-DirectWebRtcWebUiStatus
}

function Update-TransportUi {
    $enabled = Test-TransportEnabled
    foreach ($control in @($cmbProtocol, $txtDestination, $lblDestination, $cmbTimingMode, $chkStartMediaMtx)) {
        if ($control) { $control.Enabled = $enabled }
    }

    Update-MediaMtxUi
    Update-DirectWebRtcUi
    Update-ProtocolUi
    Update-CommandPreview
}

function Get-SelectedCaptureMethodName {
    $name = [string]$cmbCaptureMethod.SelectedItem
    if (-not [string]::IsNullOrWhiteSpace($name) -and $script:CaptureMethodCatalog.Contains($name)) {
        return $name
    }

    if ($chkFullscreenApp.Checked) {
        return 'Fullscreen App - D3D11 / WGC'
    }

    return $script:DefaultCaptureMethodName
}

function Get-SelectedCaptureMethod {
    $name = Get-SelectedCaptureMethodName
    return $script:CaptureMethodCatalog[$name]
}

function Test-FullscreenCaptureMode {
    $method = Get-SelectedCaptureMethod
    return [bool]$method.RequiresFullscreenWindow
}

function Sync-LegacyFullscreenFlag {
    $isFullscreenMode = Test-FullscreenCaptureMode
    if ($chkFullscreenApp.Checked -ne $isFullscreenMode) {
        $chkFullscreenApp.Checked = $isFullscreenMode
    }
}

function Update-CaptureModeUi {
    $methodName = Get-SelectedCaptureMethodName
    $method = Get-SelectedCaptureMethod
    $isFullscreenMode = [bool]$method.RequiresFullscreenWindow

    if ($cmbCaptureMethod.SelectedItem -ne $methodName -and $cmbCaptureMethod.Items.Contains($methodName)) {
        $cmbCaptureMethod.SelectedItem = $methodName
    }

    if ($chkFullscreenApp.Checked -ne $isFullscreenMode) {
        $chkFullscreenApp.Checked = $isFullscreenMode
    }

    $numMonitor.Enabled = -not $isFullscreenMode

    if ($isFullscreenMode) {
        if ($script:CaptureWindowHwnd -ne [IntPtr]::Zero -and $script:CaptureWindowTitle) {
            $lblCaptureModeStatus.Text = "Fullscreen target: $($script:CaptureWindowTitle)"
            $lblCaptureModeStatus.ForeColor = [System.Drawing.Color]::DarkGreen
        }
        else {
            $lblCaptureModeStatus.Text = 'Fullscreen WGC - waiting starts automatically'
            $lblCaptureModeStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
    }
    else {
        $hint = switch ([string]$method.Method) {
            'MonitorD3D11Dxgi' { 'DXGI monitor capture' }
            'MonitorD3D11Wgc'  { 'WGC monitor capture' }
            'MonitorGdi'       { 'GDI fallback capture' }
            default            { 'Monitor capture' }
        }
        $lblCaptureModeStatus.Text = "$hint (index $([int]$numMonitor.Value))"
        $lblCaptureModeStatus.ForeColor = [System.Drawing.Color]::DimGray
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$method.Description)) {
        $toolTip.SetToolTip($cmbCaptureMethod, [string]$method.Description)
    }
}

function Resolve-FullscreenCaptureTarget {
    param([switch]$Quiet)

    if (-not (Test-FullscreenCaptureMode)) {
        $script:CaptureWindowHwnd = [IntPtr]::Zero
        $script:CaptureWindowTitle = ''
        Update-CaptureModeUi
        return $true
    }

    $gstPid = 0
    if ((Test-DirectWebRtcUnifiedPublisher) -and $script:GstVideoProcess -and -not $script:GstVideoProcess.HasExited) {
        $gstPid = $script:GstVideoProcess.Id
    }
    elseif ($script:GstProcess -and -not $script:GstProcess.HasExited) {
        $gstPid = $script:GstProcess.Id
    }

    $candidate = [GstPreviewNative]::FindTopmostFullscreenWindow($PID, $gstPid)
    if ($candidate -eq [IntPtr]::Zero) {
        $script:CaptureWindowHwnd = [IntPtr]::Zero
        $script:CaptureWindowTitle = ''
        Update-CaptureModeUi

        return $false
    }

    $script:CaptureWindowHwnd = $candidate
    $script:CaptureWindowTitle = [GstPreviewNative]::GetWindowTitleSafe($candidate)
    Update-CaptureModeUi
    return $true
}


function Get-QueueLeakValue {
    $mode = Get-ComboSelectedOrDefault $cmbQueueLeakMode $script:DefaultQueueLeakMode
    switch ($mode) {
        'Upstream - drop new' { return 'upstream' }
        'No leak - block' { return 'no' }
        default { return 'downstream' }
    }
}

function Get-EffectiveLiveQueueLeakValue {
    # Live streaming should not silently preserve old frames. Blocking queues are
    # allowed only in the explicit Blocking diagnostic profile; otherwise a stale
    # saved setting of 'No leak - block' is coerced to downstream/drop-old.
    $leak = Get-QueueLeakValue
    $profile = Get-ComboSelectedOrDefault $cmbThreadingProfile $script:DefaultThreadingProfile
    if ($leak -eq 'no' -and $profile -ne 'Blocking diagnostic') { return 'downstream' }
    return $leak
}

function Get-AudioTimingMode {
    return (Get-ComboSelectedOrDefault $cmbAudioTimingMode $script:DefaultAudioTimingMode)
}

function Get-WasapiClockOption {
    $clockMode = Get-ComboSelectedOrDefault $cmbAudioClockMode $script:DefaultAudioClockMode
    $timingMode = Get-AudioTimingMode
    if ($clockMode -eq 'System clock / no WASAPI clock' -or $timingMode -in @('WASAPI no pipeline clock','WASAPI no clock + retimestamp')) {
        return 'provide-clock=false'
    }
    return ''
}

function Get-WasapiTimestampOption {
    $timingMode = Get-AudioTimingMode
    if ($timingMode -in @('WASAPI retimestamp','WASAPI no clock + retimestamp')) { return 'do-timestamp=true' }
    return ''
}

function Get-WasapiSlaveMethodOption {
    $mode = Get-ComboSelectedOrDefault $cmbAudioSlaveMethod $script:DefaultAudioSlaveMethod
    switch ($mode) {
        'None' { return 'slave-method=none' }
        'Skew' { return 'slave-method=skew' }
        'Resample' { return 'slave-method=resample' }
        'Retimestamp' { return 'slave-method=re-timestamp' }
        default { return '' }
    }
}

function Get-WasapiLowLatencyOption {
    if ($chkWasapiLowLatencyOverride -and $chkWasapiLowLatencyOverride.Checked) { return 'low-latency=true' }
    return ''
}

function Get-WasapiBufferTimeOption {
    if (-not $chkAudioBufferOverride -or -not $chkAudioBufferOverride.Checked) { return '' }
    $ms = [int]$numAudioBufferMs.Value
    if ($ms -le 0) { return '' }
    return ('buffer-time=' + ([int64]$ms * 1000))
}

function Get-WasapiLatencyTimeOption {
    if (-not $chkAudioLatencyOverride -or -not $chkAudioLatencyOverride.Checked) { return '' }
    $ms = [int]$numAudioLatencyMs.Value
    if ($ms -le 0) { return '' }
    return ('latency-time=' + ([int64]$ms * 1000))
}

function Get-AudioSampleRateOverrideValue {
    if (-not $chkAudioSampleRateOverride -or -not $chkAudioSampleRateOverride.Checked) { return 0 }
    $rate = [int]$numAudioSampleRate.Value
    if ($rate -le 0) { return 0 }
    return $rate
}

function Get-AudioRawCapsString {
    param(
        [ValidateSet('S16LE','F32LE')][string]$Format = 'S16LE',
        [int]$Channels = 2
    )

    $fields = New-Object System.Collections.Generic.List[string]
    $fields.Add('audio/x-raw')
    $fields.Add("format=$Format")
    $rate = Get-AudioSampleRateOverrideValue
    if ($rate -gt 0) { $fields.Add("rate=$rate") }
    if ($Channels -gt 0) { $fields.Add("channels=$Channels") }
    return ('"' + ($fields -join ',') + '"')
}

function Clean-GstDevicePropertyValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $v = $Value.Trim()
    $v = $v -replace '^\([^)]+\)\s*', ''
    $v = $v.Trim()
    if ($v.Length -ge 2 -and $v.StartsWith('"') -and $v.EndsWith('"')) {
        $v = $v.Substring(1, $v.Length - 2)
    }
    return $v.Trim()
}

function Get-GstDeviceMonitorPath {
    $gstPath = $txtGstPath.Text.Trim()
    if (-not [string]::IsNullOrWhiteSpace($gstPath) -and (Test-Path -LiteralPath $gstPath)) {
        # Windows PowerShell can throw a ParameterBindingException for Split-Path -LiteralPath ... -Parent.
        # Use .NET path handling here so the Refresh audio devices button is ps2exe/WinPS safe.
        $dir = [System.IO.Path]::GetDirectoryName($gstPath)
        if (-not [string]::IsNullOrWhiteSpace($dir)) {
            $candidate = Join-Path -Path $dir -ChildPath 'gst-device-monitor-1.0.exe'
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
    }
    return 'gst-device-monitor-1.0.exe'
}

function Set-AudioDeviceComboDefaults {
    if ($cmbDesktopAudioDevice) {
        $cmbDesktopAudioDevice.BeginUpdate()
        try {
            $cmbDesktopAudioDevice.Items.Clear()
            [void]$cmbDesktopAudioDevice.Items.Add($script:DefaultAudioOutputDeviceLabel)
            $cmbDesktopAudioDevice.SelectedIndex = 0
        }
        finally { $cmbDesktopAudioDevice.EndUpdate() }
    }
    if ($cmbMicAudioDevice) {
        $cmbMicAudioDevice.BeginUpdate()
        try {
            $cmbMicAudioDevice.Items.Clear()
            [void]$cmbMicAudioDevice.Items.Add($script:DefaultAudioInputDeviceLabel)
            $cmbMicAudioDevice.SelectedIndex = 0
        }
        finally { $cmbMicAudioDevice.EndUpdate() }
    }
    $script:AudioOutputDeviceMap = @{}
    $script:AudioInputDeviceMap = @{}
}

function Add-AudioDeviceComboItem {
    param(
        [ValidateSet('Output','Input')][string]$Kind,
        [string]$Name,
        [string]$DeviceId
    )

    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $cleanName = $Name.Trim()
    $cleanId = (Clean-GstDevicePropertyValue $DeviceId)
    if ([string]::IsNullOrWhiteSpace($cleanId)) { $cleanId = $cleanName }

    $shortId = $cleanId
    if ($shortId.Length -gt 28) { $shortId = $shortId.Substring($shortId.Length - 28) }
    $label = "$cleanName  [$shortId]"

    if ($Kind -eq 'Output') {
        if (-not $cmbDesktopAudioDevice.Items.Contains($label)) { [void]$cmbDesktopAudioDevice.Items.Add($label) }
        $script:AudioOutputDeviceMap[$label] = $cleanId
    }
    else {
        if (-not $cmbMicAudioDevice.Items.Contains($label)) { [void]$cmbMicAudioDevice.Items.Add($label) }
        $script:AudioInputDeviceMap[$label] = $cleanId
    }
}

function Restore-AudioDeviceSelection {
    param(
        [ValidateSet('Output','Input')][string]$Kind,
        [string]$Label,
        [string]$DeviceId
    )

    if ([string]::IsNullOrWhiteSpace($Label)) { return }
    $combo = if ($Kind -eq 'Output') { $cmbDesktopAudioDevice } else { $cmbMicAudioDevice }
    $mapName = if ($Kind -eq 'Output') { 'AudioOutputDeviceMap' } else { 'AudioInputDeviceMap' }
    if (-not $combo) { return }

    if (-not $combo.Items.Contains($Label)) {
        [void]$combo.Items.Add($Label)
        if (-not [string]::IsNullOrWhiteSpace($DeviceId)) {
            (Get-Variable -Name $mapName -Scope Script).Value[$Label] = [string]$DeviceId
        }
    }
    if ($combo.Items.Contains($Label)) { $combo.SelectedItem = $Label }
}

function Refresh-AudioDevices {
    param([switch]$Quiet)

    $previousOutput = if ($cmbDesktopAudioDevice -and $cmbDesktopAudioDevice.SelectedItem) { [string]$cmbDesktopAudioDevice.SelectedItem } else { $script:DefaultAudioOutputDeviceLabel }
    $previousInput = if ($cmbMicAudioDevice -and $cmbMicAudioDevice.SelectedItem) { [string]$cmbMicAudioDevice.SelectedItem } else { $script:DefaultAudioInputDeviceLabel }

    Set-AudioDeviceComboDefaults

    $monitor = Get-GstDeviceMonitorPath
    try {
        $raw = & $monitor Audio/Source Audio/Sink 2>&1 | Out-String
        $lines = $raw -split "`r?`n"
        $device = $null
        $outputCount = 0
        $inputCount = 0

        function Flush-ParsedAudioDevice {
            param($Parsed)
            if ($null -eq $Parsed) { return }
            $name = [string]$Parsed.Name
            $class = [string]$Parsed.Class
            $devId = [string]$Parsed.DeviceId
            if ([string]::IsNullOrWhiteSpace($name)) { return }
            if ($class -match 'Audio/Sink') {
                Add-AudioDeviceComboItem -Kind Output -Name $name -DeviceId $devId
                $script:__AudioDeviceOutputCount++
            }
            elseif ($class -match 'Audio/Source') {
                Add-AudioDeviceComboItem -Kind Input -Name $name -DeviceId $devId
                $script:__AudioDeviceInputCount++
            }
        }

        $script:__AudioDeviceOutputCount = 0
        $script:__AudioDeviceInputCount = 0
        foreach ($line in $lines) {
            if ($line -match '^\s*Device found:') {
                Flush-ParsedAudioDevice $device
                $device = [ordered]@{ Name = ''; Class = ''; DeviceId = '' }
                continue
            }
            if ($null -eq $device) { continue }
            if ($line -match '^\s*name\s*:\s*(.+)$') {
                $device.Name = (Clean-GstDevicePropertyValue $Matches[1])
                continue
            }
            if ($line -match '^\s*class\s*:\s*(.+)$') {
                $device.Class = (Clean-GstDevicePropertyValue $Matches[1])
                continue
            }
            if ($line -match '^\s*(device\.strid|device\.id|device\.path|wasapi\.[^=]*strid|wasapi\.[^=]*id)\s*=\s*(.+)$') {
                if ([string]::IsNullOrWhiteSpace([string]$device.DeviceId)) {
                    $device.DeviceId = (Clean-GstDevicePropertyValue $Matches[2])
                }
                continue
            }
            if ($line -match '^\s*(device\.name|wasapi\.device\.description)\s*=\s*(.+)$') {
                if ([string]::IsNullOrWhiteSpace([string]$device.Name)) {
                    $device.Name = (Clean-GstDevicePropertyValue $Matches[2])
                }
                continue
            }
        }
        Flush-ParsedAudioDevice $device
        $outputCount = [int]$script:__AudioDeviceOutputCount
        $inputCount = [int]$script:__AudioDeviceInputCount
        Remove-Variable -Name __AudioDeviceOutputCount -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name __AudioDeviceInputCount -Scope Script -ErrorAction SilentlyContinue

        if ($cmbDesktopAudioDevice.Items.Contains($previousOutput)) { $cmbDesktopAudioDevice.SelectedItem = $previousOutput }
        if ($cmbMicAudioDevice.Items.Contains($previousInput)) { $cmbMicAudioDevice.SelectedItem = $previousInput }
        if ($lblAudioDeviceStatus) {
            $lblAudioDeviceStatus.Text = "Audio devices: $outputCount output / $inputCount input"
            $lblAudioDeviceStatus.ForeColor = if ($outputCount -gt 0 -or $inputCount -gt 0) { [System.Drawing.Color]::DarkGreen } else { [System.Drawing.Color]::DarkOrange }
        }
        if (-not $Quiet) { Append-Log "Audio device refresh: $outputCount output loopback device(s), $inputCount input capture device(s)." }
    }
    catch {
        if ($lblAudioDeviceStatus) {
            $lblAudioDeviceStatus.Text = 'Audio device refresh failed; using defaults'
            $lblAudioDeviceStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        if (-not $Quiet) { Append-Log "Audio device refresh failed: $($_.Exception.Message)" }
    }

    try {
        Update-CommandPreview
    }
    catch {
        if (-not $Quiet) { Append-Log "Audio device refresh preview update failed: $($_.Exception.Message)" }
    }
}

function Get-SelectedWasapiDeviceOption {
    param([ValidateSet('Output','Input')][string]$Kind)

    if ($Kind -eq 'Output') {
        if (-not $cmbDesktopAudioDevice -or -not $cmbDesktopAudioDevice.SelectedItem) { return '' }
        $label = [string]$cmbDesktopAudioDevice.SelectedItem
        if ($label -eq $script:DefaultAudioOutputDeviceLabel) { return '' }
        $id = [string]$script:AudioOutputDeviceMap[$label]
    }
    else {
        if (-not $cmbMicAudioDevice -or -not $cmbMicAudioDevice.SelectedItem) { return '' }
        $label = [string]$cmbMicAudioDevice.SelectedItem
        if ($label -eq $script:DefaultAudioInputDeviceLabel) { return '' }
        $id = [string]$script:AudioInputDeviceMap[$label]
    }

    if ([string]::IsNullOrWhiteSpace($id)) { return '' }
    return ('device=' + (Quote-GstValue $id))
}

function Get-SelectedAudioDeviceId {
    param([ValidateSet('Output','Input')][string]$Kind)
    if ($Kind -eq 'Output') {
        $label = if ($cmbDesktopAudioDevice -and $cmbDesktopAudioDevice.SelectedItem) { [string]$cmbDesktopAudioDevice.SelectedItem } else { '' }
        return [string]$script:AudioOutputDeviceMap[$label]
    }
    $label = if ($cmbMicAudioDevice -and $cmbMicAudioDevice.SelectedItem) { [string]$cmbMicAudioDevice.SelectedItem } else { '' }
    return [string]$script:AudioInputDeviceMap[$label]
}

function Get-AudioSourceSelectionSummary {
    $parts = New-Object System.Collections.Generic.List[string]
    if ($chkDesktopAudio.Checked) {
        $label = if ($cmbDesktopAudioDevice -and $cmbDesktopAudioDevice.SelectedItem) { [string]$cmbDesktopAudioDevice.SelectedItem } else { $script:DefaultAudioOutputDeviceLabel }
        $parts.Add("desktop loopback=$label")
    }
    if ($chkMic.Checked) {
        $label = if ($cmbMicAudioDevice -and $cmbMicAudioDevice.SelectedItem) { [string]$cmbMicAudioDevice.SelectedItem } else { $script:DefaultAudioInputDeviceLabel }
        $parts.Add("mic/input=$label")
    }
    if ($parts.Count -eq 0) { return 'none' }
    return ($parts -join '; ')
}

function Get-WasapiSourceString {
    param([switch]$Loopback)

    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add('wasapi2src')
    $deviceOpt = if ($Loopback) { Get-SelectedWasapiDeviceOption -Kind Output } else { Get-SelectedWasapiDeviceOption -Kind Input }
    if (-not [string]::IsNullOrWhiteSpace($deviceOpt)) { $parts.Add($deviceOpt) }
    foreach ($opt in @(
        (Get-WasapiClockOption),
        (Get-WasapiTimestampOption),
        (Get-WasapiSlaveMethodOption),
        (Get-WasapiLowLatencyOption),
        (Get-WasapiBufferTimeOption),
        (Get-WasapiLatencyTimeOption)
    )) {
        if (-not [string]::IsNullOrWhiteSpace($opt)) { $parts.Add($opt) }
    }

    if ($Loopback) { $parts.Add('loopback=true') }
    return ($parts -join ' ')
}



function Get-VideoPipelineClockMode {
    return (Get-ComboSelectedOrDefault $cmbVideoPipelineClockMode $script:DefaultVideoPipelineClockMode)
}

function Get-SplitAudioPipelineClockMode {
    $mode = Get-ComboSelectedOrDefault $cmbSplitAudioPipelineClockMode $script:DefaultSplitAudioPipelineClockMode
    if ($mode -eq 'Follow video/master') { return (Get-VideoPipelineClockMode) }
    return $mode
}

function Get-ClockSelectIdForMode {
    param([Parameter(Mandatory)][string]$Mode)

    switch ($Mode) {
        'System monotonic' { return 'monotonic' }
        'System realtime'  { return 'realtime' }
        default            { return '' }
    }
}

function Wrap-GstPipelineWithClockSelect {
    param(
        [Parameter(Mandatory)][string]$Pipeline,
        [Parameter(Mandatory)][string]$ClockMode
    )

    $clockId = Get-ClockSelectIdForMode -Mode $ClockMode
    if ([string]::IsNullOrWhiteSpace($clockId)) { return $Pipeline }

    # clockselect is a GstPipeline subclass exposed specifically so gst-launch can
    # force a pipeline clock. Parentheses contain the complete graph; shell escape
    # backslashes shown in Unix documentation are not part of Windows ArgumentList.
    return "clockselect. ( clock-id=$clockId $Pipeline )"
}

function Get-VideoTimestampMode {
    return (Get-ComboSelectedOrDefault $cmbVideoTimestampMode $script:DefaultVideoTimestampMode)
}

function Get-VideoSourceTimestampOption {
    switch (Get-VideoTimestampMode) {
        'Pipeline running-time' { return 'do-timestamp=true' }
        'Source timestamps'     { return 'do-timestamp=false' }
        default                 { return '' }
    }
}

function Add-VideoSourceTimestampOption {
    param([Parameter(Mandatory)][string]$SourceText)

    $option = Get-VideoSourceTimestampOption
    if ([string]::IsNullOrWhiteSpace($option)) { return $SourceText }
    return "$SourceText $option"
}

function Get-VideoSyncMode {
    return (Get-ComboSelectedOrDefault $cmbVideoSyncMode $script:DefaultVideoSyncMode)
}

function Get-AudioSyncMode {
    return (Get-ComboSelectedOrDefault $cmbAudioSyncMode $script:DefaultAudioSyncMode)
}


function Get-DirectWebRtcAvPipelineMode {
    if ($null -eq $cmbDirectWebRtcAvPipelineMode) { return $script:DefaultDirectWebRtcAvPipelineMode }
    return (Get-ComboSelectedOrDefault $cmbDirectWebRtcAvPipelineMode $script:DefaultDirectWebRtcAvPipelineMode)
}

function Test-DirectWebRtcSplitAvPipelines {
    return ((Get-DirectWebRtcAvPipelineMode) -like 'Split A/V pipelines*')
}


function Get-DirectWebRtcMediaStreamGrouping {
    if ($null -eq $cmbDirectWebRtcMediaStreamGrouping) { return $script:DefaultDirectWebRtcMediaStreamGrouping }
    return (Get-ComboSelectedOrDefault $cmbDirectWebRtcMediaStreamGrouping $script:DefaultDirectWebRtcMediaStreamGrouping)
}

function Test-DirectWebRtcSeparateMediaStreams {
    return ((Test-DirectWebRtcProtocol) -and -not (Test-DirectWebRtcSplitAvPipelines) -and ((Get-DirectWebRtcMediaStreamGrouping) -like 'Separate audio/video MediaStreams*'))
}

function Get-DirectWebRtcMediaStreamId {
    param([ValidateSet('video','audio')][string]$Kind)

    $fallback = if ($Kind -eq 'audio') { $script:DefaultDirectWebRtcAudioMediaStreamId } else { $script:DefaultDirectWebRtcVideoMediaStreamId }
    $control = if ($Kind -eq 'audio') { $txtDirectWebRtcAudioMediaStreamId } else { $txtDirectWebRtcVideoMediaStreamId }
    if ($null -eq $control) { return $fallback }
    $value = [string]$control.Text
    if ([string]::IsNullOrWhiteSpace($value)) { return $fallback }
    return $value.Trim()
}

function Test-DirectWebRtcUnifiedPublisher {
    return ((Test-DirectWebRtcSplitAvPipelines) -and $chkDirectWebRtcUnifiedPublisher -and $chkDirectWebRtcUnifiedPublisher.Checked)
}

function Test-DirectWebRtcSharedSignaling {
    return ((Test-DirectWebRtcSplitAvPipelines) -and -not (Test-DirectWebRtcUnifiedPublisher) -and $chkDirectWebRtcSharedSignaling -and $chkDirectWebRtcSharedSignaling.Checked)
}

function Get-DirectWebRtcSplitAudioSignalingPort {
    if (Test-DirectWebRtcSharedSignaling) { return [int]$numDirectWebRtcSignalingPort.Value }
    return [int]$numDirectWebRtcSplitAudioSignalingPort.Value
}

function Get-DirectWebRtcSignalingClientHost {
    $hostText = $txtDirectWebRtcSignalingHost.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($hostText) -or $hostText -in @('0.0.0.0','*','::','[::]')) { return '127.0.0.1' }
    $hostText = $hostText.Trim('[',']')
    if ($hostText -match ':') { return "[$hostText]" }
    return $hostText
}

function Get-DirectWebRtcSharedSignallerUri {
    $clientHost = Get-DirectWebRtcSignalingClientHost
    return "ws://${clientHost}:$([int]$numDirectWebRtcSignalingPort.Value)"
}

function Get-DirectWebRtcSplitAudioWebAddress {
    $base = Normalize-DirectWebRtcWebAddress $txtDestination.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($base)) { $base = $script:DefaultDirectWebRtcWebAddress }
    try {
        $u = [Uri]$base
        $b = New-Object System.UriBuilder($u)
        if ($b.Port -le 0) { $b.Port = 8889 }
        $b.Port = $b.Port + 1
        return $b.Uri.AbsoluteUri
    }
    catch {
        return 'http://0.0.0.0:8890/'
    }
}

function Get-DirectWebRtcSplitAudioWsUrlForPlayer {
    # Proxy-aware default: do NOT hardcode 127.0.0.1 into gstglass-config.js.
    # player.js derives ws/wss + host from the actual primary viewer socket.
    # Separate mode uses splitAudioSignalingPort; shared mode reuses the exact
    # primary signalling WebSocket and selects the audio producer by metadata.
    return ''
}

function Get-DirectWebRtcSplitAudioWsUrlDescriptionForLog {
    if (Test-DirectWebRtcSharedSignaling) { return 'same primary signalling WebSocket/server' }
    return "auto/proxy-aware from viewer page host on port $(Get-DirectWebRtcSplitAudioSignalingPort)"
}

function Get-BranchClockSyncElement {
    param([Parameter(Mandatory)][string]$Mode)

    switch ($Mode) {
        'sync=true'  { return 'clocksync sync=true' }
        'sync=false' { return 'clocksync sync=false' }
        default      { return '' }
    }
}

function Get-VideoBranchSyncSuffix {
    $sync = Get-BranchClockSyncElement -Mode (Get-VideoSyncMode)
    if ([string]::IsNullOrWhiteSpace($sync)) { return '' }
    return " ! $sync"
}

function Get-AudioBranchSyncSuffix {
    $sync = Get-BranchClockSyncElement -Mode (Get-AudioSyncMode)
    if ([string]::IsNullOrWhiteSpace($sync)) { return '' }
    return " ! $sync"
}

function Get-VideoPreviewSinkSyncOption {
    # Preserve historical GStreamer Glass behavior: local preview used d3d11videosink sync=false.
    # The explicit Video sync mode overrides that only when the user selects sync=true/sync=false.
    $mode = Get-VideoSyncMode
    switch ($mode) {
        'sync=true'  { return 'sync=true' }
        'sync=false' { return 'sync=false' }
        default      { return 'sync=false' }
    }
}

function Get-EffectiveAudioTimingSummary {
    $timing = Get-AudioTimingMode
    $clockMode = Get-ComboSelectedOrDefault $cmbAudioClockMode $script:DefaultAudioClockMode
    $clockOpt = Get-WasapiClockOption

    if ($timing -eq 'Synthetic silent audio') {
        return 'synthetic source; WASAPI timing controls bypassed'
    }

    $items = New-Object System.Collections.Generic.List[string]
    foreach ($opt in @(
        $clockOpt,
        (Get-WasapiTimestampOption),
        (Get-WasapiSlaveMethodOption),
        (Get-WasapiLowLatencyOption),
        (Get-WasapiBufferTimeOption),
        (Get-WasapiLatencyTimeOption)
    )) {
        if (-not [string]::IsNullOrWhiteSpace($opt)) { $items.Add($opt) }
    }

    $sampleRate = Get-AudioSampleRateOverrideValue
    if ($sampleRate -gt 0) { $items.Add("raw-rate=$sampleRate") }

    if ($items.Count -eq 0) {
        $items.Add('plugin defaults; no WASAPI timing overrides emitted')
    }

    $note = ''
    if ($clockMode -eq 'Plugin default / allow WASAPI clock' -and $clockOpt -eq 'provide-clock=false') {
        $note = ' UI note: the selected Audio timing mode explicitly disables the WASAPI clock.'
    }

    return (($items -join ' ') + $note)
}

function New-LiveQueueString {
    param(
        [int]$Buffers = 2,
        [int]$MaxTimeMs = 0,
        [string]$Leak = ''
    )

    if ([string]::IsNullOrWhiteSpace($Leak)) { $Leak = Get-EffectiveLiveQueueLeakValue }
    $Buffers = [Math]::Max(1, $Buffers)
    $ns = [int64]([Math]::Max(0, $MaxTimeMs)) * 1000000
    return "queue max-size-buffers=$Buffers max-size-bytes=0 max-size-time=$ns leaky=$Leak"
}

function Get-CpuWorkerLimit {
    if (-not $numCpuWorkerLimit) { return 0 }
    return [Math]::Max(0, [int]$numCpuWorkerLimit.Value)
}

function Get-CpuWorkerProperty {
    param([Parameter(Mandatory)][string]$Name)
    $workers = Get-CpuWorkerLimit
    if ($workers -le 0) { return '' }
    return "$Name=$workers"
}

function Apply-ThreadBudget {
    param([switch]$Force)
    if ($script:ApplyingThreadBudget) { return }
    $script:ApplyingThreadBudget = $true
    try {
        $budget = Get-ComboSelectedOrDefault $cmbThreadBudget $script:DefaultThreadBudget
        if ($budget -eq 'Custom' -and -not $Force) { return }
        switch ($budget) {
            'Lean' {
                $numCpuWorkerLimit.Value = 1
                $chkBudgetCaptureQueue.Checked = $false
                $chkBudgetSenderQueue.Checked = $false
                $chkBudgetAudioInputQueue.Checked = $false
                $chkBudgetAudioFinalQueue.Checked = $true
                $chkBudgetSceneInputQueues.Checked = $true
            }
            'Balanced' {
                $numCpuWorkerLimit.Value = 2
                $chkBudgetCaptureQueue.Checked = $true
                $chkBudgetSenderQueue.Checked = $true
                $chkBudgetAudioInputQueue.Checked = $true
                $chkBudgetAudioFinalQueue.Checked = $true
                $chkBudgetSceneInputQueues.Checked = $true
            }
            'Isolated' {
                $numCpuWorkerLimit.Value = 0
                $chkBudgetCaptureQueue.Checked = $true
                $chkBudgetSenderQueue.Checked = $true
                $chkBudgetAudioInputQueue.Checked = $true
                $chkBudgetAudioFinalQueue.Checked = $true
                $chkBudgetSceneInputQueues.Checked = $true
            }
            default {
                $numCpuWorkerLimit.Value = 0
                $chkBudgetCaptureQueue.Checked = $true
                $chkBudgetSenderQueue.Checked = $true
                $chkBudgetAudioInputQueue.Checked = $true
                $chkBudgetAudioFinalQueue.Checked = $true
                $chkBudgetSceneInputQueues.Checked = $true
            }
        }
    }
    finally { $script:ApplyingThreadBudget = $false }
    Update-CommandPreview
}

function Update-GstThreadCountStatus {
    if (-not $lblLiveGstThreads) { return }
    if (-not $script:GstProcess -or $script:GstProcess.HasExited) {
        $lblLiveGstThreads.Text = if (($script:DynamicScenePreviewActive -or $script:ControlledLiveStreamActive) -and [GstControlledScenePreview]::IsRunning) {
            if ($script:ControlledLiveStreamActive) { 'Live GST threads: controlled broadcast worker' } else { 'Live GST threads: controlled scene preview runs in-process' }
        }
        else {
            'Live GST threads: stopped'
        }
        return
    }
    try {
        $parts = New-Object System.Collections.Generic.List[string]
        $total = 0
        foreach ($entry in @(
            [pscustomobject]@{ Label = $(if (Test-DirectWebRtcUnifiedPublisher) { 'publisher' } else { 'main' }); Process = $script:GstProcess },
            [pscustomobject]@{ Label = 'video'; Process = $script:GstVideoProcess },
            [pscustomobject]@{ Label = 'audio'; Process = $script:GstAudioProcess }
        )) {
            $process = $entry.Process
            if ($process -and -not $process.HasExited) {
                $process.Refresh()
                $count = [int]$process.Threads.Count
                $total += $count
                $parts.Add("$($entry.Label)=$count/PID$($process.Id)")
            }
        }
        $lblLiveGstThreads.Text = "Live GST threads: $total  ($($parts -join ', '))"
    }
    catch { $lblLiveGstThreads.Text = 'Live GST threads: unavailable' }
}

function Get-CaptureEncoderQueue {
    if ($chkBudgetCaptureQueue -and -not $chkBudgetCaptureQueue.Checked) { return 'identity' }
    $buffers = [int]$numCaptureQueueBuffers.Value
    return (New-LiveQueueString -Buffers $buffers -MaxTimeMs 0)
}

function Get-EffectiveAudioQueueCapMs {
    # GStreamer basesink latency negotiation fails if a nonzero queue time cap is
    # lower than the live audio source's reported minimum latency plus the sink
    # processing deadline. The old 20 ms cap could produce:
    #   Impossible to configure latency: max 20ms < min ~21ms
    # Keep 0 as uncapped, but clamp small nonzero caps to a safe low-latency floor.
    $requestedMs = [int]$numAudioQueueCapMs.Value
    if ($requestedMs -le 0) { return 0 }

    $requestedBufferMs = if ($chkAudioBufferOverride -and $chkAudioBufferOverride.Checked) { [Math]::Max(1, [int]$numAudioBufferMs.Value) } else { 0 }
    $requestedLatencyMs = if ($chkAudioLatencyOverride -and $chkAudioLatencyOverride.Checked) { [Math]::Max(1, [int]$numAudioLatencyMs.Value) } else { 0 }
    $safeFloorMs = [Math]::Max(30, ($requestedBufferMs + $requestedLatencyMs + 10))
    return [Math]::Max($requestedMs, [int]$safeFloorMs)
}

function Get-AudioInputQueue {
    param([int]$Multiplier = 1)
    if ($chkBudgetAudioInputQueue -and -not $chkBudgetAudioInputQueue.Checked) { return 'identity' }
    $buffers = [Math]::Max(1, [int]$numAudioQueueBuffers.Value * [Math]::Max(1, $Multiplier))
    $ms = Get-EffectiveAudioQueueCapMs
    return (New-LiveQueueString -Buffers $buffers -MaxTimeMs $ms)
}

function Get-AudioFinalQueue {
    if ($chkBudgetAudioFinalQueue -and -not $chkBudgetAudioFinalQueue.Checked) { return 'identity' }
    $buffers = [Math]::Max(1, [int]$numAudioQueueBuffers.Value * 2)
    $ms = Get-EffectiveAudioQueueCapMs
    return (New-LiveQueueString -Buffers $buffers -MaxTimeMs $ms)
}

function Apply-ThreadingProfile {
    param([switch]$Force)

    if ($script:ApplyingThreadingProfile) { return }
    $script:ApplyingThreadingProfile = $true
    try {
        $profile = Get-ComboSelectedOrDefault $cmbThreadingProfile $script:DefaultThreadingProfile
        if ($profile -eq 'Custom' -and -not $Force) { return }

        switch ($profile) {
            'Live strict' {
                $cmbGstProcessPriority.SelectedItem = 'High'
                $cmbQueueLeakMode.SelectedItem = 'Downstream - drop old'
                $numCaptureQueueBuffers.Value = 2
                $numAudioQueueBuffers.Value = 4
                $numAudioQueueCapMs.Value = 0
                $chkBufferLatenessTracer.Checked = $false
            }
            'Balanced' {
                $cmbGstProcessPriority.SelectedItem = 'Above normal'
                $cmbQueueLeakMode.SelectedItem = 'Downstream - drop old'
                $numCaptureQueueBuffers.Value = 4
                $numAudioQueueBuffers.Value = 6
                $numAudioQueueCapMs.Value = 40
                $chkBufferLatenessTracer.Checked = $false
            }
            'Non-blocking brutal' {
                $cmbGstProcessPriority.SelectedItem = 'High'
                $cmbQueueLeakMode.SelectedItem = 'Downstream - drop old'
                $numCaptureQueueBuffers.Value = 1
                $numAudioQueueBuffers.Value = 2
                $numAudioQueueCapMs.Value = 0
                $chkBufferLatenessTracer.Checked = $false
            }
            'Blocking diagnostic' {
                $cmbGstProcessPriority.SelectedItem = 'Normal'
                $cmbQueueLeakMode.SelectedItem = 'No leak - block'
                $numCaptureQueueBuffers.Value = 2
                $numAudioQueueBuffers.Value = 4
                $numAudioQueueCapMs.Value = 80
                $chkBufferLatenessTracer.Checked = $true
            }
        }
    }
    finally {
        $script:ApplyingThreadingProfile = $false
    }

    Update-CommandPreview
}

function Set-GstProcessPriority {
    param([System.Diagnostics.Process]$Process)

    if (-not $Process) { return }
    $priorityText = Get-ComboSelectedOrDefault $cmbGstProcessPriority $script:DefaultGstProcessPriority
    $priority = switch ($priorityText) {
        'Above normal' { 'AboveNormal' }
        'High' { 'High' }
        default { 'Normal' }
    }

    try {
        $Process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::$priority
        Append-Log "GStreamer process priority: $priorityText"
    }
    catch {
        Append-Log "WARNING: could not set GStreamer process priority to ${priorityText}: $($_.Exception.Message)"
    }
}

function Get-GstDebugSpec {
    $mode = Get-ComboSelectedOrDefault $cmbGstDebugMode $script:DefaultGstDebugMode

    switch ($mode) {
        'ERROR (*:1)' { return '*:1' }
        'WARNING (*:2)' { return '*:2' }
        'INFO (*:3)' { return '*:3' }
        'DEBUG (*:4)' { return '*:4' }
        'LOG (*:5)' { return '*:5' }
        'TRACE (*:6)' { return '*:6' }
        'FULL/MEMDUMP (*:9)' { return '*:9' }
        'Custom' {
            $custom = $txtGstDebugSpec.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($custom)) { return $script:DefaultGstDebugSpec }
            return $custom
        }
        default { return '' }
    }
}

function Test-ProcessDiskLoggingEnabled {
    # Keep the default run path disk-quiet. Diagnostic output is captured only
    # when explicitly requested by the disk-log checkbox or by an explicit
    # diagnostic mode that would otherwise emit useful stdout/stderr.
    try {
        if ($chkDiskProcessLogging -and $chkDiskProcessLogging.Checked) { return $true }
        if ($chkVerbose -and $chkVerbose.Checked) { return $true }
        if ($chkBufferLatenessTracer -and $chkBufferLatenessTracer.Checked) { return $true }
        $debugSpec = Get-GstDebugSpec
        if (-not [string]::IsNullOrWhiteSpace($debugSpec)) { return $true }
    }
    catch {}

    return $false
}

function Reset-ProcessLogPaths {
    $script:StdOutPath = $null
    $script:StdErrPath = $null
    $script:StdOutVideoPath = $null
    $script:StdErrVideoPath = $null
    $script:StdOutAudioPath = $null
    $script:StdErrAudioPath = $null
    $script:MediaMtxStdOutPath = $null
    $script:MediaMtxStdErrPath = $null
    $script:StdOutPosition = [int64]0
    $script:StdErrPosition = [int64]0
    $script:StdOutVideoPosition = [int64]0
    $script:StdErrVideoPosition = [int64]0
    $script:StdOutAudioPosition = [int64]0
    $script:StdErrAudioPosition = [int64]0
    $script:MediaMtxStdOutPosition = [int64]0
    $script:MediaMtxStdErrPosition = [int64]0
}

function Ensure-ProcessLogDirectory {
    if (-not (Test-Path -LiteralPath $script:LogDirectory)) {
        $null = New-Item -ItemType Directory -Path $script:LogDirectory -Force
    }
}

function Update-GstDebugUi {
    $mode = Get-ComboSelectedOrDefault $cmbGstDebugMode $script:DefaultGstDebugMode
    $custom = ($mode -eq 'Custom')
    $txtGstDebugSpec.Enabled = $custom

    if (-not $custom) {
        $spec = Get-GstDebugSpec
        if ([string]::IsNullOrWhiteSpace($spec)) {
            $txtGstDebugSpec.Text = $script:DefaultGstDebugSpec
        }
        else {
            $txtGstDebugSpec.Text = $spec
        }
    }
}

function Set-GstTracerEnvironment {
    param(
        [switch]$Enable,
        [string]$DebugSpec = '',
        [switch]$NoColor
    )

    $state = [ordered]@{
        GST_TRACERS = $env:GST_TRACERS
        GST_DEBUG = $env:GST_DEBUG
        GST_DEBUG_NO_COLOR = $env:GST_DEBUG_NO_COLOR
    }

    $debugParts = @()

    if ($Enable) {
        $env:GST_TRACERS = 'buffer-lateness'
        $debugParts += 'GST_TRACER:7'
    }

    if (-not [string]::IsNullOrWhiteSpace($DebugSpec)) {
        $debugParts += $DebugSpec.Trim()
    }

    if ($debugParts.Count -gt 0) {
        $env:GST_DEBUG = ($debugParts -join ',')
        if ($NoColor) {
            $env:GST_DEBUG_NO_COLOR = '1'
        }
    }

    return $state
}

function Restore-GstTracerEnvironment {
    param($State)
    if ($null -eq $State) { return }
    if ($null -eq $State.GST_TRACERS) { Remove-Item Env:\GST_TRACERS -ErrorAction SilentlyContinue } else { $env:GST_TRACERS = $State.GST_TRACERS }
    if ($null -eq $State.GST_DEBUG) { Remove-Item Env:\GST_DEBUG -ErrorAction SilentlyContinue } else { $env:GST_DEBUG = $State.GST_DEBUG }
    if ($null -eq $State.GST_DEBUG_NO_COLOR) { Remove-Item Env:\GST_DEBUG_NO_COLOR -ErrorAction SilentlyContinue } else { $env:GST_DEBUG_NO_COLOR = $State.GST_DEBUG_NO_COLOR }
}

function Build-RawAudioChain {
    $desktopEnabled = $chkDesktopAudio.Checked
    $micEnabled = $chkMic.Checked

    if (-not $desktopEnabled -and -not $micEnabled) {
        return $null
    }

    $desktopVolume = Format-InvariantNumber ([double]$numDesktopVolume.Value / 100.0)
    $micVolume = Format-InvariantNumber ([double]$numMicVolume.Value / 100.0)

    # Mixer mode is deliberately forced whenever both sources are active because
    # a single downstream encoder needs one combined raw-audio stream. The flag
    # controls the important diagnostic case: desktop-only through audiomixer
    # versus the legacy direct WASAPI -> encoder path.
    $useMixer = $desktopEnabled -and ($micEnabled -or $chkAudioMixerMode.Checked)

    if (-not $useMixer) {
        if ($desktopEnabled) {
            return @(
                (Get-WasapiSourceString -Loopback)
                '!'
                (Get-AudioInputQueue)
                '!'
                'audioconvert'
                '!'
                'audioresample'
                '!'
                (Get-AudioRawCapsString -Format 'S16LE' -Channels 2)
                '!'
                'volume'
                "volume=$desktopVolume"
            ) -join ' '
        }

        return @(
            (Get-WasapiSourceString)
            '!'
            (Get-AudioInputQueue)
            '!'
            'audioconvert'
            '!'
            'audioresample'
            '!'
            (Get-AudioRawCapsString -Format 'S16LE' -Channels 2)
            '!'
            'volume'
            "volume=$micVolume"
        ) -join ' '
    }

    $mixBranches = @()

    if ($desktopEnabled) {
        $mixBranches += @(
            (Get-WasapiSourceString -Loopback)
            '!'
            (Get-AudioInputQueue -Multiplier 2)
            '!'
            'audioconvert'
            '!'
            'audioresample'
            '!'
            (Get-AudioRawCapsString -Format 'F32LE' -Channels 2)
            '!'
            'volume'
            "volume=$desktopVolume"
            '!'
            'mix.'
        ) -join ' '
    }

    if ($micEnabled) {
        $mixBranches += @(
            (Get-WasapiSourceString)
            '!'
            (Get-AudioInputQueue -Multiplier 2)
            '!'
            'audioconvert'
            '!'
            'audioresample'
            '!'
            (Get-AudioRawCapsString -Format 'F32LE' -Channels 2)
            '!'
            'volume'
            "volume=$micVolume"
            '!'
            'mix.'
        ) -join ' '
    }

    $mixOutput = @(
        'mix.'
        '!'
        (Get-AudioInputQueue -Multiplier 2)
        '!'
        'audioconvert'
        '!'
        (Get-AudioRawCapsString -Format 'S16LE' -Channels 2)
    ) -join ' '

    return "audiomixer name=mix $($mixBranches -join ' ') $mixOutput"
}

function Build-WhipSilentClockAudioChain {
    # MediaMTX/GStreamer testing showed that video-only WHIP selects
    # GstSystemClock and eventually develops a small backward DTS step. A muted
    # WASAPI loopback source makes the pipeline use GstAudioSrcClock, matching
    # the stable desktop-audio path while emitting no audible sound.
    return @(
        (Get-WasapiSourceString -Loopback)
        '!'
        (Get-AudioInputQueue)
        '!'
        'audioconvert'
        '!'
        'audioresample'
        '!'
        (Get-AudioRawCapsString -Format 'S16LE' -Channels 2)
        '!'
        'volume'
        'volume=0.0'
    ) -join ' '
}


function Build-SyntheticSilentAudioChain {
    # Completely bypasses WASAPI. Use this to prove whether the browser/WebRTC
    # audio track is fine when Windows audio driver timing is removed.
    $explicitRate = Get-AudioSampleRateOverrideValue
    $samplesPerBuffer = if ($explicitRate -gt 0) { [Math]::Max(1, [int][Math]::Round($explicitRate / 100.0)) } else { 480 }
    return @(
        'audiotestsrc'
        'is-live=true'
        'do-timestamp=true'
        'wave=silence'
        "samplesperbuffer=$samplesPerBuffer"
        '!'
        (Get-AudioInputQueue)
        '!'
        'audioconvert'
        '!'
        'audioresample'
        '!'
        (Get-AudioRawCapsString -Format 'S16LE' -Channels 2)
        '!'
        'volume'
        'volume=0.0'
    ) -join ' '
}

function Get-TimingMode {
    if ($null -ne $cmbTimingMode -and $cmbTimingMode.SelectedItem) {
        return [string]$cmbTimingMode.SelectedItem
    }
    if ($chkSendAbsoluteTimestamps.Checked) {
        return 'On / protocol clock signaling'
    }
    return $script:DefaultTimingMode
}

function Test-ClockSignalingValueEnabled {
    param([AllowNull()][string]$Value)

    return ([string]$Value -in @(
        'On / protocol clock signaling',
        'Send absolute timestamps / clock signalling',
        'RFC7273 NTP/PTP signalling',
        'RFC7273 NTP/PTP signaling',
        'On',
        'Enabled'
    ))
}

function Test-SendAbsoluteTimestampsEnabled {
    return (Test-ClockSignalingValueEnabled (Get-TimingMode))
}

function Test-SplitClockSignalingOverridesActive {
    return (
        ([string]$cmbProtocol.SelectedItem -eq $script:DirectWebRtcProtocolName) -and
        (Test-TransportEnabled) -and
        (Test-DirectWebRtcSplitAvPipelines) -and
        -not (Test-DirectWebRtcUnifiedPublisher) -and
        $chkSplitClockSignalingOverrides -and
        $chkSplitClockSignalingOverrides.Checked
    )
}

function Test-WebRtcClockSignalingForSink {
    param(
        [ValidateSet('Global','Video','Audio')]
        [string]$SinkRole = 'Global'
    )

    if ((Test-SplitClockSignalingOverridesActive) -and $SinkRole -ne 'Global') {
        if ($SinkRole -eq 'Video') {
            return (Test-ClockSignalingValueEnabled ([string]$cmbSplitVideoClockSignaling.SelectedItem))
        }
        return (Test-ClockSignalingValueEnabled ([string]$cmbSplitAudioClockSignaling.SelectedItem))
    }

    return (Test-SendAbsoluteTimestampsEnabled)
}

function Sync-TransportTimingControls {
    param(
        [ValidateSet('Protocol','TimingMode','DirectWebRtc')]
        [string]$Source = 'Protocol'
    )

    # Compatibility no-op. Older builds had a second GST-WebRTC-only selector;
    # f42 keeps one protocol-aware setting and only maps old values during load.
}

function Get-AbsoluteTimestampTransportOption {
    param(
        [Parameter(Mandatory)][string]$Protocol,
        [ValidateSet('Global','Video','Audio')][string]$SinkRole = 'Global'
    )

    switch ($Protocol) {
        'GST WebRTC' {
            if (Test-WebRtcClockSignalingForSink -SinkRole $SinkRole) { return 'do-clock-signalling=true' }
            return ''
        }
        'WHIP' {
            if (Test-SendAbsoluteTimestampsEnabled) { return 'do-clock-signalling=true' }
            return ''
        }
        'RTSP' {
            if (Test-SendAbsoluteTimestampsEnabled) { return 'ntp-time-source=ntp' }
            return ''
        }
        default { return '' }
    }
}

function Get-AbsoluteTimestampStatusText {
    $protocol = [string]$cmbProtocol.SelectedItem

    if (-not (Test-TransportEnabled)) { return 'Transport disabled' }

    switch ($protocol) {
        'GST WebRTC' {
            if (Test-SplitClockSignalingOverridesActive) {
                $videoState = if (Test-WebRtcClockSignalingForSink -SinkRole Video) { 'on' } else { 'off' }
                $audioState = if (Test-WebRtcClockSignalingForSink -SinkRole Audio) { 'on' } else { 'off' }
                return "GST WebRTC split sinks: video RFC7273 $videoState; audio RFC7273 $audioState"
            }
            if (Test-SendAbsoluteTimestampsEnabled) { return 'GST WebRTC sink: RFC7273 do-clock-signalling=true' }
            return 'GST WebRTC sink: clock signaling off / property omitted'
        }
        'WHIP' {
            if (Test-SendAbsoluteTimestampsEnabled) { return 'WHIP sink: RFC7273 do-clock-signalling=true' }
            return 'WHIP sink: clock signaling off / property omitted'
        }
        'RTSP' {
            if (Test-SendAbsoluteTimestampsEnabled) { return 'RTSP sink: ntp-time-source=ntp' }
            return 'RTSP sink: NTP timestamp override off / property omitted'
        }
        default { return ($protocol + ': no applicable clock-signaling sink property') }
    }
}

function Update-TimestampUi {
    $protocol = [string]$cmbProtocol.SelectedItem
    $transportEnabled = Test-TransportEnabled
    $applicable = $protocol -in @('WHIP','GST WebRTC','RTSP')

    $physicalSplit = $transportEnabled -and $protocol -eq 'GST WebRTC' -and (Test-DirectWebRtcSplitAvPipelines) -and -not (Test-DirectWebRtcUnifiedPublisher)
    $splitOverrides = $physicalSplit -and $chkSplitClockSignalingOverrides.Checked

    if ($lblTimingMode) {
        $lblTimingMode.Text = switch ($protocol) {
            'WHIP' { 'WHIP clock signaling' }
            'GST WebRTC' {
                if ($splitOverrides) { 'WebRTC clock signaling (overridden)' }
                elseif ($physicalSplit) { 'WebRTC clock signaling (both sinks)' }
                else { 'WebRTC clock signaling' }
            }
            'RTSP' { 'RTSP NTP timestamps' }
            default { 'Clock signaling' }
        }
    }

    if ($cmbTimingMode) { $cmbTimingMode.Enabled = $transportEnabled -and $applicable -and -not $splitOverrides }
    $chkSendAbsoluteTimestamps.Checked = Test-SendAbsoluteTimestampsEnabled

    if ($chkSplitClockSignalingOverrides) { $chkSplitClockSignalingOverrides.Enabled = $physicalSplit }
    if ($cmbSplitVideoClockSignaling) { $cmbSplitVideoClockSignaling.Enabled = $splitOverrides }
    if ($cmbSplitAudioClockSignaling) { $cmbSplitAudioClockSignaling.Enabled = $splitOverrides }

    $lblTimestampStatus.Text = Get-AbsoluteTimestampStatusText
    $active = if ($protocol -eq 'GST WebRTC' -and (Test-SplitClockSignalingOverridesActive)) {
        (Test-WebRtcClockSignalingForSink -SinkRole Video) -or (Test-WebRtcClockSignalingForSink -SinkRole Audio)
    }
    else {
        $applicable -and (Test-SendAbsoluteTimestampsEnabled)
    }
    $lblTimestampStatus.ForeColor = if ($active) { [System.Drawing.Color]::DarkSlateBlue } else { [System.Drawing.Color]::DimGray }
}

function Test-DirectWebRtcProtocol {
    return (Test-TransportEnabled) -and ([string]$cmbProtocol.SelectedItem -eq $script:DirectWebRtcProtocolName)
}

function Test-WebRtcTransportProtocol {
    return (Test-TransportEnabled) -and ([string]$cmbProtocol.SelectedItem -in @('WHIP', $script:DirectWebRtcProtocolName))
}

function Normalize-DirectWebRtcWebAddress {
    param([string]$Value)

    $address = $Value
    if ([string]::IsNullOrWhiteSpace($address)) {
        $address = $script:DefaultDirectWebRtcWebAddress
    }

    $address = $address.Trim()
    if ($address -notmatch '^https?://') {
        $address = 'http://' + $address.TrimStart('/')
    }

    # web-server-host-addr is the bind/listen address. Keep the route path in
    # web-server-path so http://host:8889/live can be changed cleanly.
    try {
        $uri = [System.Uri]$address
        $scheme = $uri.Scheme
        $hostPart = $uri.Host
        $portPart = if ($uri.IsDefaultPort) { '' } else { ":$($uri.Port)" }
        $address = "${scheme}://$hostPart$portPart/"
    }
    catch {
        if ($address -notmatch '/$') { $address += '/' }
    }

    return $address
}

function Normalize-DirectWebRtcWebPath {
    param([string]$Value)

    $path = $Value
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = $script:DefaultDirectWebRtcWebPath
    }

    $path = $path.Trim()
    if ($path -eq '/') { return '/' }
    if ($path -notmatch '^/') { $path = '/' + $path }
    return $path.TrimEnd('/')
}

function Test-DirectWebRtcWebDirectory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try {
        $resolved = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"')))
        return ((Test-Path -LiteralPath (Join-Path $resolved 'index.html') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $resolved 'player.js') -PathType Leaf))
    }
    catch {
        return $false
    }
}

function Find-DirectWebRtcWebDirectory {
    param([string]$GstLaunchPath)

    $candidates = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($script:ApplicationDirectory)) {
        $candidates.Add((Join-Path $script:ApplicationDirectory 'gstwebrtc-api\dist'))
    }

    if (-not [string]::IsNullOrWhiteSpace($GstLaunchPath)) {
        try {
            $binDir = Split-Path -Parent $GstLaunchPath
            $rootDir = Split-Path -Parent $binDir
            foreach ($base in @($binDir, $rootDir, (Split-Path -Parent $rootDir))) {
                if ([string]::IsNullOrWhiteSpace($base)) { continue }
                $candidates.Add((Join-Path $base 'gstwebrtc-api\dist'))
                $candidates.Add((Join-Path $base 'share\gstwebrtc-api\dist'))
                $candidates.Add((Join-Path $base 'share\gstreamer-1.0\gstwebrtc-api\dist'))
                $candidates.Add((Join-Path $base 'share\gstreamer-1.0\webrtc\gstwebrtc-api\dist'))
                $candidates.Add((Join-Path $base 'lib\gstreamer-1.0\gstwebrtc-api\dist'))
            }
        }
        catch {}
    }

    foreach ($base in @(
        ${env:ProgramFiles},
        ${env:ProgramFiles(x86)},
        'C:\Program Files (x86)\Strom\gstreamer',
        'C:\Program Files\gstreamer\1.0\msvc_x86_64'
    )) {
        if ([string]::IsNullOrWhiteSpace($base)) { continue }
        $candidates.Add((Join-Path $base 'gstwebrtc-api\dist'))
        $candidates.Add((Join-Path $base 'share\gstwebrtc-api\dist'))
        $candidates.Add((Join-Path $base 'share\gstreamer-1.0\gstwebrtc-api\dist'))
        $candidates.Add((Join-Path $base 'share\gstreamer-1.0\webrtc\gstwebrtc-api\dist'))
        $candidates.Add((Join-Path $base 'lib\gstreamer-1.0\gstwebrtc-api\dist'))
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-DirectWebRtcWebDirectory $candidate) {
            return ([System.IO.Path]::GetFullPath($candidate))
        }
    }

    return ''
}


function Get-DefaultDirectWebRtcWorkingWebDirectory {
    return ([System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'GStreamerGlass\WebRoot\gstwebrtc-api\dist')))
}

function Test-DirectWebRtcWebDirectoryWritable {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try {
        $resolved = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"')))
        if (-not (Test-Path -LiteralPath $resolved)) {
            $null = New-Item -ItemType Directory -Path $resolved -Force
        }
        $probe = Join-Path $resolved ('.gstglass-write-test-' + [guid]::NewGuid().ToString('N') + '.tmp')
        Set-Content -LiteralPath $probe -Value 'ok' -Encoding ASCII -ErrorAction Stop
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        return $true
    }
    catch {
        return $false
    }
}

function Select-DirectWebRtcFolderPath {
    param(
        [string]$Title,
        [string]$InitialPath,
        [bool]$AllowNewFolder = $true
    )

    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = $Title
    $dlg.ShowNewFolderButton = $AllowNewFolder

    try {
        $expanded = [Environment]::ExpandEnvironmentVariables([string]$InitialPath)
        if (-not [string]::IsNullOrWhiteSpace($expanded) -and (Test-Path -LiteralPath $expanded)) {
            $dlg.SelectedPath = ([System.IO.Path]::GetFullPath($expanded))
        }
    }
    catch {}

    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dlg.SelectedPath
    }

    return $null
}

function Get-DirectWebRtcWebUiVersion {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try {
        $resolved = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"')))
        $manifest = Join-Path $resolved 'gstglass-webui-manifest.json'
        if (Test-Path -LiteralPath $manifest -PathType Leaf) {
            $json = Get-Content -LiteralPath $manifest -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($json.webUiVersion) { return [string]$json.webUiVersion }
            if ($json.version) { return [string]$json.version }
        }
    }
    catch {}
    return $null
}

function Compare-DirectWebRtcVersionString {
    param([string]$Left, [string]$Right)

    if ([string]::IsNullOrWhiteSpace($Left) -and [string]::IsNullOrWhiteSpace($Right)) { return 0 }
    if ([string]::IsNullOrWhiteSpace($Left)) { return -1 }
    if ([string]::IsNullOrWhiteSpace($Right)) { return 1 }

    try {
        # Preserve the f-build suffix used by Glass web UI releases. Comparing
        # only the dotted base made 3.7.52f18 and 3.7.52f19 look identical and
        # could leave an older working WebRoot in place after an app upgrade.
        $lm = [regex]::Match($Left, '(?i)(?<base>\d+(?:\.\d+){1,3})(?:f(?<revision>\d+))?')
        $rm = [regex]::Match($Right, '(?i)(?<base>\d+(?:\.\d+){1,3})(?:f(?<revision>\d+))?')
        if (-not $lm.Success -or -not $rm.Success) { throw 'Unrecognized version format' }

        $baseCompare = ([version]$lm.Groups['base'].Value).CompareTo([version]$rm.Groups['base'].Value)
        if ($baseCompare -ne 0) { return $baseCompare }

        $leftRevision = if ($lm.Groups['revision'].Success) { [int]$lm.Groups['revision'].Value } else { 0 }
        $rightRevision = if ($rm.Groups['revision'].Success) { [int]$rm.Groups['revision'].Value } else { 0 }
        return $leftRevision.CompareTo($rightRevision)
    }
    catch {
        return [string]::Compare($Left, $Right, $true)
    }
}

function Get-BundledDirectWebRtcWebDirectory {
    $mode = $script:DefaultDirectWebRtcBundledWebMode
    if ($cmbDirectWebRtcBundledWebMode -and $cmbDirectWebRtcBundledWebMode.SelectedItem) { $mode = [string]$cmbDirectWebRtcBundledWebMode.SelectedItem }

    if ($mode -eq 'Manual path' -and $txtDirectWebRtcBundledWebDirectory) {
        $manual = [string]$txtDirectWebRtcBundledWebDirectory.Text
        if (Test-DirectWebRtcWebDirectory $manual) {
            return ([System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($manual.Trim().Trim('"'))))
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($script:ApplicationDirectory)) {
        $bundled = Join-Path $script:ApplicationDirectory 'gstwebrtc-api\dist'
        if (Test-DirectWebRtcWebDirectory $bundled) {
            return ([System.IO.Path]::GetFullPath($bundled))
        }
    }

    return (Find-DirectWebRtcWebDirectory $txtGstPath.Text)
}

function Get-DirectWebRtcWorkingWebDirectory {
    $mode = $script:DefaultDirectWebRtcWorkingWebMode
    if ($cmbDirectWebRtcWorkingWebMode -and $cmbDirectWebRtcWorkingWebMode.SelectedItem) { $mode = [string]$cmbDirectWebRtcWorkingWebMode.SelectedItem }

    if ($mode -eq 'Manual path' -and $txtDirectWebRtcWebDirectory) {
        $manual = [string]$txtDirectWebRtcWebDirectory.Text
        if (-not [string]::IsNullOrWhiteSpace($manual)) {
            return ([System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($manual.Trim().Trim('"'))))
        }
    }

    return (Get-DefaultDirectWebRtcWorkingWebDirectory)
}

function Test-DirectWebRtcWebUiHasJbufStats {
    param([string]$Path)

    if (-not (Test-DirectWebRtcWebDirectory $Path)) { return $false }

    try {
        $playerPath = Join-Path ([System.IO.Path]::GetFullPath($Path)) 'player.js'
        if (-not (Test-Path -LiteralPath $playerPath -PathType Leaf)) { return $false }
        $playerText = Get-Content -LiteralPath $playerPath -Raw -ErrorAction Stop
        return ($playerText -match 'audio jbuf' -and $playerText -match 'video jbuf' -and $playerText -match 'GstGlassJbuf')
    }
    catch {
        return $false
    }
}

function Get-DirectWebRtcSourceWebDirectory {
    return (Get-BundledDirectWebRtcWebDirectory)
}

function Copy-DirectWebRtcStaticWebAssets {
    param(
        [Parameter(Mandatory)][string]$SourceDirectory,
        [Parameter(Mandatory)][string]$DestinationDirectory,
        [switch]$ForceRefresh
    )

    $sourceFull = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($SourceDirectory.Trim().Trim('"')))
    $destFull = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($DestinationDirectory.Trim().Trim('"')))

    if (-not (Test-DirectWebRtcWebDirectory $sourceFull)) {
        throw "Bundled Web UI source is missing index.html/player.js: $sourceFull"
    }

    if (-not (Test-Path -LiteralPath $destFull)) {
        $null = New-Item -ItemType Directory -Path $destFull -Force
    }

    if (-not (Test-DirectWebRtcWebDirectoryWritable $destFull)) {
        throw "Working Web UI directory is not writable: $destFull"
    }

    $sourceVersion = Get-DirectWebRtcWebUiVersion $sourceFull
    $destVersion = Get-DirectWebRtcWebUiVersion $destFull
    $destHasUi = Test-DirectWebRtcWebDirectory $destFull
    $needsCopy = $ForceRefresh -or (-not $destHasUi)
    if (-not $needsCopy) {
        $needsCopy = ((Compare-DirectWebRtcVersionString $sourceVersion $destVersion) -gt 0)
    }

    if (-not $needsCopy) {
        return [pscustomobject]@{ Copied = $false; Source = $sourceFull; Destination = $destFull; SourceVersion = $sourceVersion; DestinationVersion = $destVersion }
    }

    Get-ChildItem -LiteralPath $sourceFull -Force | Where-Object {
        $_.Name -notin @('gstglass-config.js') -and $_.Name -notlike '*.runtime.js' -and $_.Name -notlike '*.local.js'
    } | ForEach-Object {
        $target = Join-Path $destFull $_.Name
        if ($_.PSIsContainer) {
            Copy-Item -LiteralPath $_.FullName -Destination $target -Recurse -Force -ErrorAction Stop
        }
        else {
            Copy-Item -LiteralPath $_.FullName -Destination $target -Force -ErrorAction Stop
        }
    }

    return [pscustomobject]@{ Copied = $true; Source = $sourceFull; Destination = $destFull; SourceVersion = $sourceVersion; DestinationVersion = $destVersion }
}

function Ensure-DirectWebRtcRuntimeWebDirectory {
    param([string]$SourceDirectory, [switch]$ForceRefresh)

    if ([string]::IsNullOrWhiteSpace($SourceDirectory) -or -not (Test-DirectWebRtcWebDirectory $SourceDirectory)) {
        return ''
    }

    try {
        $runtime = Get-DirectWebRtcWorkingWebDirectory
        $script:DirectWebRtcRuntimeWebDirectory = $runtime
        $result = Copy-DirectWebRtcStaticWebAssets -SourceDirectory $SourceDirectory -DestinationDirectory $runtime -ForceRefresh:$ForceRefresh
        if ($result.Copied) {
            Append-Log "Direct WebRTC web UI updated: $($result.Source) -> $($result.Destination) [$($result.DestinationVersion) -> $($result.SourceVersion)]"
        }
        return ([System.IO.Path]::GetFullPath($runtime))
    }
    catch {
        Append-Log "Direct WebRTC runtime web UI sync failed: $($_.Exception.Message)"
        return $SourceDirectory
    }
}

function Get-DirectWebRtcWebDirectory {
    $source = Get-DirectWebRtcSourceWebDirectory
    return (Ensure-DirectWebRtcRuntimeWebDirectory $source)
}


function Get-PlayerSettingsFromUi {
    $watchdog = $script:DefaultJbufWatchdogMode
    if ($cmbJbufWatchdogMode -and $cmbJbufWatchdogMode.SelectedItem) { $watchdog = [string]$cmbJbufWatchdogMode.SelectedItem }

    return [ordered]@{
        AudioJbufMs = [int]$numDirectWebRtcPlayerJitterMs.Value
        VideoJbufMs = [int]$numDirectWebRtcVideoJitterMs.Value
        JbufMaxMs = [int]$numJbufMaxMs.Value
        JbufWatchdogMode = $watchdog
        JbufDebug = [bool]($chkPlayerJbufDebug -and $chkPlayerJbufDebug.Checked)
        StatsOverlay = [bool]($chkPlayerStatsOverlay -and $chkPlayerStatsOverlay.Checked)
        LiveEdgeGreenMs = [int]$numLiveEdgeGreenMs.Value
        LiveEdgeYellowMs = [int]$numLiveEdgeYellowMs.Value
        LiveEdgeAverageSec = [int]$numLiveEdgeAverageSec.Value
        UrlOverrides = [bool]($chkPlayerUrlOverrides -and $chkPlayerUrlOverrides.Checked)
        SeparateHtmlMediaElements = [bool]($chkPlayerSeparateHtmlMediaElements -and $chkPlayerSeparateHtmlMediaElements.Checked)
        AvRenderMode = if ($chkPlayerSeparateHtmlMediaElements -and $chkPlayerSeparateHtmlMediaElements.Checked) { 'Decoupled video/audio elements' } else { 'Synced single media element' }
        AvPipelineMode = [string](Get-DirectWebRtcAvPipelineMode)
        MediaStreamGrouping = [string](Get-DirectWebRtcMediaStreamGrouping)
        VideoMediaStreamId = [string](Get-DirectWebRtcMediaStreamId -Kind video)
        AudioMediaStreamId = [string](Get-DirectWebRtcMediaStreamId -Kind audio)
        SplitPlayerSyncMode = [string](Get-ComboSelectedOrDefault $cmbSplitPlayerSyncMode $script:DefaultSplitPlayerSyncMode)
        SplitAudioStallSeconds = [int]$numSplitAudioStallSeconds.Value
        SplitAudioWarmupSeconds = [int]$numSplitAudioWarmupSeconds.Value
        JbufWatchdogWarmupSeconds = [int]$numSplitAudioWarmupSeconds.Value
        WatchdogWarmupSeconds = [int]$numSplitAudioWarmupSeconds.Value
        SplitAvOffsetBaselineMs = [int]$numSplitAvOffsetBaselineMs.Value
        SplitAvOffsetWarnMs = [int]$numSplitAvOffsetWarnMs.Value
        WebPath = [string]$txtDirectWebRtcWebPath.Text
        BundledWebMode = [string]$cmbDirectWebRtcBundledWebMode.SelectedItem
        BundledWebDirectory = [string]$txtDirectWebRtcBundledWebDirectory.Text
        WorkingWebMode = [string]$cmbDirectWebRtcWorkingWebMode.SelectedItem
        WebDirectory = [string]$txtDirectWebRtcWebDirectory.Text
    }
}


function Update-DirectWebRtcWebUiStatus {
    if (-not $lblDirectWebRtcWebUiStatus) { return }
    try {
        $bundled = Get-BundledDirectWebRtcWebDirectory
        $working = Get-DirectWebRtcWorkingWebDirectory
        $script:DirectWebRtcRuntimeWebDirectory = $working
        $bundledOk = Test-DirectWebRtcWebDirectory $bundled
        $workingOk = Test-DirectWebRtcWebDirectory $working
        $workingStats = Test-DirectWebRtcWebUiHasJbufStats $working
        $bundledVersion = Get-DirectWebRtcWebUiVersion $bundled
        $workingVersion = Get-DirectWebRtcWebUiVersion $working
        $runtimeConfig = Join-Path $working 'gstglass-config.js'
        $configState = if (Test-Path -LiteralPath $runtimeConfig -PathType Leaf) { 'config OK' } else { 'config missing' }

        $text = "Bundled: $bundled"
        if ($bundledOk) { $text += "  [v$bundledVersion]" } else { $text += '  [missing]' }
        $text += "`r`nWorking: $working"
        if ($workingOk -and $workingStats) { $text += "  [v$workingVersion, stats OK, $configState]" }
        elseif ($workingOk) { $text += "  [v$workingVersion, missing stats markers, $configState]" }
        else { $text += "  [missing/static sync needed, $configState]" }
        $lblDirectWebRtcWebUiStatus.Text = $text
    }
    catch {
        $lblDirectWebRtcWebUiStatus.Text = "Web UI status check failed: $($_.Exception.Message)"
    }
}


function Add-DirectWebRtcViewerQuery {
    param([string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) { return $Url }

    # Normal operation is config-driven: /live/ loads gstglass-config.js with cache busting.
    # Only append the long query string when explicitly requested for debug/share testing.
    $playerSettings = Get-PlayerSettingsFromUi
    if (-not $playerSettings.UrlOverrides) { return $Url }

    $audioJitterMs = [int]$playerSettings.AudioJbufMs
    $videoJitterMs = [int]$playerSettings.VideoJbufMs
    $fallbackJitterMs = $audioJitterMs
    $maxMs = [int]$playerSettings.JbufMaxMs
    $watchdog = [System.Uri]::EscapeDataString([string]$playerSettings.JbufWatchdogMode)
    $debug = if ($playerSettings.JbufDebug) { '1' } else { '0' }
    $liveEdgeGreenMs = [int]$playerSettings.LiveEdgeGreenMs
    $liveEdgeYellowMs = [int]$playerSettings.LiveEdgeYellowMs
    $liveEdgeAverageSec = [int]$playerSettings.LiveEdgeAverageSec
    $warmupSeconds = [int]$playerSettings.WatchdogWarmupSeconds
    $avRenderMode = [System.Uri]::EscapeDataString([string]$playerSettings.AvRenderMode)
    $separateHtmlMediaElements = if ($playerSettings.SeparateHtmlMediaElements) { 1 } else { 0 }
    $effectiveAvPipelineMode = if (Test-DirectWebRtcUnifiedPublisher) { 'Unified publisher - one producer' } else { [string](Get-DirectWebRtcAvPipelineMode) }
    $avPipelineMode = [System.Uri]::EscapeDataString($effectiveAvPipelineMode)
    $effectiveMediaStreamGrouping = if (Test-DirectWebRtcSeparateMediaStreams) { [string](Get-DirectWebRtcMediaStreamGrouping) } else { $script:DefaultDirectWebRtcMediaStreamGrouping }
    $mediaStreamGrouping = [System.Uri]::EscapeDataString($effectiveMediaStreamGrouping)
    $videoMediaStreamId = [System.Uri]::EscapeDataString((Get-DirectWebRtcMediaStreamId -Kind video))
    $audioMediaStreamId = [System.Uri]::EscapeDataString((Get-DirectWebRtcMediaStreamId -Kind audio))
    $videoSignalPort = [int]$numDirectWebRtcSignalingPort.Value
    $splitAudioPort = if ((Test-DirectWebRtcSplitAvPipelines) -and -not (Test-DirectWebRtcUnifiedPublisher)) { [int](Get-DirectWebRtcSplitAudioSignalingPort) } else { 0 }
    $sharedSignaling = if (Test-DirectWebRtcSharedSignaling) { 1 } else { 0 }
    $splitAudioPart = if ($splitAudioPort -gt 0) { "&splitAudioPort=$splitAudioPort&splitAudioSignalingPort=$splitAudioPort&sharedSignaling=$sharedSignaling&splitSharedSignaling=$sharedSignaling" } else { '' }
    $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $joiner = if ($Url -match '\?') { '&' } else { '?' }

    return ($Url + $joiner + "signalPort=$videoSignalPort&videoSignalingPort=$videoSignalPort&audioJbufMs=$audioJitterMs&videoJbufMs=$videoJitterMs&jitterMs=$fallbackJitterMs&browserJitterTargetMs=$fallbackJitterMs&jbufMaxMs=$maxMs&jbufWatchdog=$watchdog&jbufDebug=$debug&liveEdgeGreenMs=$liveEdgeGreenMs&liveEdgeYellowMs=$liveEdgeYellowMs&liveEdgeAverageSec=$liveEdgeAverageSec&watchdogWarmupSeconds=$warmupSeconds&jbufWatchdogWarmupSeconds=$warmupSeconds&splitAudioWarmupSeconds=$warmupSeconds&separateHtmlMediaElements=$separateHtmlMediaElements&playerSeparateHtmlMediaElements=$separateHtmlMediaElements&avRenderMode=$avRenderMode&playerAvRenderMode=$avRenderMode&avPipelineMode=$avPipelineMode&mediaStreamGrouping=$mediaStreamGrouping&videoMsid=$videoMediaStreamId&audioMsid=$audioMediaStreamId$splitAudioPart&cb=$stamp")
}

function Get-DirectWebRtcViewerUrl {
    $address = Normalize-DirectWebRtcWebAddress $txtDestination.Text

    # 0.0.0.0 is a listen/bind address, not a URL most browsers can open.
    # Use localhost for the local Open Viewer button while preserving the
    # configured bind address in the actual GStreamer property.
    $address = $address -replace '://0\.0\.0\.0(?=[:/])', '://127.0.0.1'
    $address = $address -replace '://\*(?=[:/])', '://127.0.0.1'
    $path = Normalize-DirectWebRtcWebPath $txtDirectWebRtcWebPath.Text
    if ($path -eq '/') { return (Add-DirectWebRtcViewerQuery $address) }

    # warp's static directory handler is happier with the mounted directory URL
    # ending in a slash. Without this, /live can 404 while /live/ serves index.html.
    return (Add-DirectWebRtcViewerQuery ($address.TrimEnd('/') + $path + '/'))
}

function Update-UnifiedBridgeKeyframeUi {
    if (-not $chkUnifiedBridgeKeyframeGuard -or -not $numUnifiedBridgeKeyframeIntervalMs) { return }

    $codecSupported = $false
    try {
        $definition = Get-SelectedEncoderDefinition
        $codecSupported = ([string]$definition.Codec -in @('H264','H265'))
    }
    catch {
        $codecSupported = $false
    }

    $available = (Test-DirectWebRtcUnifiedPublisher) -and $codecSupported
    $chkUnifiedBridgeKeyframeGuard.Enabled = $available
    $numUnifiedBridgeKeyframeIntervalMs.Enabled = $available -and $chkUnifiedBridgeKeyframeGuard.Checked
}

function Update-DirectWebRtcUi {
    $directEnabled = Test-DirectWebRtcProtocol
    $webRtcTransportEnabled = Test-WebRtcTransportProtocol

    foreach ($control in @(
        $lblDirectWebRtcStatus,
        $txtDirectWebRtcSignalingHost,
        $numDirectWebRtcSignalingPort,
        $numDirectWebRtcSplitAudioSignalingPort,
        $chkDirectWebRtcSharedSignaling,
        $chkSplitClockSignalingOverrides,
        $cmbSplitVideoClockSignaling,
        $cmbSplitAudioClockSignaling,
        $cmbDirectWebRtcMediaStreamGrouping,
        $txtDirectWebRtcVideoMediaStreamId,
        $txtDirectWebRtcAudioMediaStreamId,
        $chkDirectWebRtcUnifiedPublisher,
        $numDirectWebRtcBridgeVideoPort,
        $numDirectWebRtcBridgeAudioPort,
        $numDirectWebRtcBridgeJitterMs,
        $numDirectWebRtcPublisherQueueMs,
        $chkDirectWebRtcAudioBridgePacing,
        $chkDirectWebRtcControlDataChannel,
        $cmbDirectWebRtcBundlePolicy,
        $numDirectWebRtcInternalRtpMtu,
        $chkDirectWebRtcInternalRepeatHeaders,
        $txtDirectWebRtcWebPath,
        $cmbDirectWebRtcBundledWebMode,
        $txtDirectWebRtcBundledWebDirectory,
        $btnBrowseDirectWebRtcBundledWebDirectory,
        $btnDetectDirectWebRtcBundledWebDirectory,
        $cmbDirectWebRtcWorkingWebMode,
        $txtDirectWebRtcWebDirectory,
        $btnBrowseDirectWebRtcWebDirectory,
        $btnDetectDirectWebRtcWebDirectory,
        $btnRefreshDirectWebRtcWebUi,
        $btnOpenDirectWebRtcServedDir,
        $btnOpenDirectWebRtcBundledDir,
        $lblDirectWebRtcWebUiStatus,
        $lblDirectWebRtcPlayerJitterMs,
        $numDirectWebRtcPlayerJitterMs,
        $lblDirectWebRtcVideoJitterMs,
        $numDirectWebRtcVideoJitterMs,
        $lblJbufMaxMs,
        $numJbufMaxMs,
        $lblJbufWatchdogMode,
        $cmbJbufWatchdogMode,
        $chkPlayerStatsOverlay,
        $chkPlayerJbufDebug,
        $numLiveEdgeAverageSec,
        $numLiveEdgeGreenMs,
        $numLiveEdgeYellowMs,
        $chkPlayerUrlOverrides,
        $chkPlayerSeparateHtmlMediaElements,
        $cmbSplitPlayerSyncMode,
        $numSplitAudioStallSeconds,
        $numSplitAudioWarmupSeconds,
        $numSplitAvOffsetWarnMs,
        $btnOpenDirectWebRtcViewer,
        $btnCopyDirectWebRtcViewer
    )) {
        if ($control) { $control.Enabled = $directEnabled }
    }

    if ($lblDirectWebRtcStatus) { $lblDirectWebRtcStatus.Enabled = ($directEnabled -or $webRtcTransportEnabled) }

    $splitModeEnabled = $directEnabled -and (Test-DirectWebRtcSplitAvPipelines)
    $unifiedPublisherEnabled = $splitModeEnabled -and (Test-DirectWebRtcUnifiedPublisher)
    if ($chkPlayerSeparateHtmlMediaElements) {
        # Two independent WebRTC producers cannot share the original event MediaStream;
        # unified-publisher mode returns to one PeerConnection and can use either render path.
        $chkPlayerSeparateHtmlMediaElements.Enabled = $directEnabled -and (-not $splitModeEnabled -or $unifiedPublisherEnabled)
    }
    if ($chkDirectWebRtcUnifiedPublisher) { $chkDirectWebRtcUnifiedPublisher.Enabled = $splitModeEnabled }
    if ($chkDirectWebRtcSharedSignaling) { $chkDirectWebRtcSharedSignaling.Enabled = $splitModeEnabled -and -not $unifiedPublisherEnabled }
    $singlePipelineGroupingAvailable = $directEnabled -and -not $splitModeEnabled
    $separateMediaStreamsEnabled = $singlePipelineGroupingAvailable -and ((Get-DirectWebRtcMediaStreamGrouping) -like 'Separate audio/video MediaStreams*')
    if ($cmbDirectWebRtcMediaStreamGrouping) { $cmbDirectWebRtcMediaStreamGrouping.Enabled = $singlePipelineGroupingAvailable }
    if ($txtDirectWebRtcVideoMediaStreamId) { $txtDirectWebRtcVideoMediaStreamId.Enabled = $separateMediaStreamsEnabled }
    if ($txtDirectWebRtcAudioMediaStreamId) { $txtDirectWebRtcAudioMediaStreamId.Enabled = $separateMediaStreamsEnabled }
    if ($numDirectWebRtcSplitAudioSignalingPort) { $numDirectWebRtcSplitAudioSignalingPort.Enabled = $splitModeEnabled -and -not $unifiedPublisherEnabled -and -not (Test-DirectWebRtcSharedSignaling) }
    if ($numDirectWebRtcBridgeVideoPort) { $numDirectWebRtcBridgeVideoPort.Enabled = $unifiedPublisherEnabled }
    if ($numDirectWebRtcBridgeAudioPort) { $numDirectWebRtcBridgeAudioPort.Enabled = $unifiedPublisherEnabled }
    if ($numDirectWebRtcBridgeJitterMs) { $numDirectWebRtcBridgeJitterMs.Enabled = $unifiedPublisherEnabled }
    if ($numDirectWebRtcPublisherQueueMs) { $numDirectWebRtcPublisherQueueMs.Enabled = $unifiedPublisherEnabled }
    if ($chkDirectWebRtcAudioBridgePacing) { $chkDirectWebRtcAudioBridgePacing.Enabled = $unifiedPublisherEnabled }
    if ($chkDirectWebRtcControlDataChannel) { $chkDirectWebRtcControlDataChannel.Enabled = $unifiedPublisherEnabled }
    if ($cmbDirectWebRtcBundlePolicy) { $cmbDirectWebRtcBundlePolicy.Enabled = $unifiedPublisherEnabled }
    if ($numDirectWebRtcInternalRtpMtu) { $numDirectWebRtcInternalRtpMtu.Enabled = $unifiedPublisherEnabled }
    if ($chkDirectWebRtcInternalRepeatHeaders) { $chkDirectWebRtcInternalRepeatHeaders.Enabled = $unifiedPublisherEnabled }
    Update-UnifiedBridgeKeyframeUi
    Update-TimestampUi

    foreach ($control in @(
        $txtDirectWebRtcStun,
        $chkDirectWebRtcTurnEnabled,
        $cmbDirectWebRtcCongestion,
        $cmbDirectWebRtcMitigation,
        $lblWebRtcRecoveryMode,
        $cmbWebRtcRecoveryMode,
        $lblWebRtcSenderQueueMode,
        $cmbWebRtcSenderQueueMode,
        $lblDirectWebRtcSmoothnessProfile,
        $cmbDirectWebRtcSmoothnessProfile,
        $lblDirectWebRtcPacingMs,
        $numDirectWebRtcPacingMs
    )) {
        if ($control) { $control.Enabled = $webRtcTransportEnabled }
    }

    if ($txtDirectWebRtcTurn) { $txtDirectWebRtcTurn.Enabled = $webRtcTransportEnabled -and $chkDirectWebRtcTurnEnabled.Checked }

    if ($directEnabled) {
        $webDir = Get-DirectWebRtcWebDirectory
        if ([string]::IsNullOrWhiteSpace($webDir)) {
            $lblDirectWebRtcStatus.Text = "Direct WebRTC viewer: $(Get-DirectWebRtcViewerUrl) - web UI dir not found; 404 likely"
            $lblDirectWebRtcStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        else {
            $groupingStatus = if (Test-DirectWebRtcSeparateMediaStreams) { "separate msid V=$(Get-DirectWebRtcMediaStreamId -Kind video) A=$(Get-DirectWebRtcMediaStreamId -Kind audio)" } else { 'combined A/V MediaStream' }
            $lblDirectWebRtcStatus.Text = "Direct WebRTC viewer: $(Get-DirectWebRtcViewerUrl) - $([string]$cmbDirectWebRtcSmoothnessProfile.SelectedItem) - $groupingStatus"
            $lblDirectWebRtcStatus.ForeColor = [System.Drawing.Color]::DarkSlateBlue
        }
    }
    elseif ($webRtcTransportEnabled) {
        $lblDirectWebRtcStatus.Text = 'WebRTC transport knobs active for WHIP/MediaMTX publish.'
        $lblDirectWebRtcStatus.ForeColor = [System.Drawing.Color]::DarkSlateBlue
    }
    else {
        $lblDirectWebRtcStatus.Text = 'WebRTC transport knobs disabled for this protocol'
        $lblDirectWebRtcStatus.ForeColor = [System.Drawing.Color]::DimGray
    }

    Update-DirectWebRtcWebUiStatus
}


function Test-RecordingEnabled {
    return ($chkRecordingEnabled -and $chkRecordingEnabled.Checked)
}

function Get-SelectedRecordingEncoderDefinition {
    $name = [string]$cmbRecordingEncoder.SelectedItem
    if (
        [string]::IsNullOrWhiteSpace($name) -or
        -not $script:EncoderCatalog.Contains($name)
    ) {
        $name = $script:DefaultEncoderName
    }

    return $script:EncoderCatalog[$name]
}

function Get-RecordingEncoderControlSupport {
    $definition = Get-SelectedRecordingEncoderDefinition
    $family = [string]$definition.Family
    $codec = [string]$definition.Codec

    $supportsBFrames = $false
    switch ($family) {
        'NVENC' { $supportsBFrames = ($codec -in @('H264', 'H265')) }
        'AMF'   { $supportsBFrames = ($codec -eq 'H264') }
        'QSV'   { $supportsBFrames = ($codec -in @('H264', 'H265')) }
        'MF'    { $supportsBFrames = ($codec -in @('H264', 'H265')) }
        'X264'  { $supportsBFrames = $true }
        'X265'  { $supportsBFrames = $true }
    }

    return [pscustomobject]@{ BFrames = $supportsBFrames }
}

function Get-SafeRecordingToken {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return 'unknown' }

    $safe = $Value -replace '[^A-Za-z0-9._-]+', '-'
    $safe = $safe.Trim('-')
    if ([string]::IsNullOrWhiteSpace($safe)) { return 'unknown' }
    return $safe
}

function Resolve-RecordingFilePath {
    param([switch]$EnsureDirectory, [switch]$AvoidExisting)

    $folder = [Environment]::ExpandEnvironmentVariables($txtRecordingDirectory.Text.Trim())
    if ([string]::IsNullOrWhiteSpace($folder)) { throw 'Select a recording output folder.' }

    if ($EnsureDirectory -and -not (Test-Path -LiteralPath $folder)) {
        $null = New-Item -ItemType Directory -Path $folder -Force
    }

    if (-not (Test-Path -LiteralPath $folder)) { throw "Recording folder does not exist: $folder" }

    $now = Get-Date
    $template = $txtRecordingTemplate.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($template)) {
        $template = 'Glass-{yyyyMMdd-HHmmss}-{protocol}-{width}x{height}-{fps}fps.mkv'
    }

    $tokenMap = [ordered]@{
        '{date}'     = $now.ToString('yyyyMMdd')
        '{time}'     = $now.ToString('HHmmss')
        '{datetime}' = $now.ToString('yyyyMMdd-HHmmss')
        '{protocol}' = Get-SafeRecordingToken ([string]$cmbProtocol.SelectedItem)
        '{encoder}'  = Get-SafeRecordingToken ([string]$cmbRecordingEncoder.SelectedItem)
        '{width}'    = [string][int]$numRecordingWidth.Value
        '{height}'   = [string][int]$numRecordingHeight.Value
        '{fps}'      = [string][int]$numRecordingFps.Value
    }

    $fileName = $template
    foreach ($key in $tokenMap.Keys) { $fileName = $fileName.Replace($key, [string]$tokenMap[$key]) }

    $fileName = [regex]::Replace(
        $fileName,
        '\{([yMdHhmsfF_. -]+)\}',
        { param($match) $now.ToString($match.Groups[1].Value) }
    )

    foreach ($invalid in [System.IO.Path]::GetInvalidFileNameChars()) {
        $fileName = $fileName.Replace([string]$invalid, '_')
    }

    if ([string]::IsNullOrWhiteSpace([System.IO.Path]::GetExtension($fileName))) { $fileName += '.mkv' }

    $path = Join-Path $folder $fileName
    if ($AvoidExisting) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($path)
        $ext = [System.IO.Path]::GetExtension($path)
        $dir = [System.IO.Path]::GetDirectoryName($path)
        $index = 1
        while (Test-Path -LiteralPath $path) {
            $path = Join-Path $dir ("{0}-{1:000}{2}" -f $base, $index, $ext)
            $index++
        }
    }
    return $path
}

function Get-RecordingEncodedVideoCaps {
    param([Parameter(Mandatory)][string]$Codec)
    $profile = [string]$cmbRecordingProfile.SelectedItem

    # Matroska does not accept Annex-B/byte-stream H.264 or H.265 on its video pad.
    # Force the parser to negotiate muxer-friendly length-prefixed caps instead.
    switch ($Codec) {
        'H264' { return "video/x-h264,profile=$profile,stream-format=avc,alignment=au" }
        'H265' { return 'video/x-h265,profile=main,stream-format=hvc1,alignment=au' }
        'AV1'  { return 'video/x-av1,stream-format=obu-stream,alignment=tu,profile=main,chroma-format=(string)4:2:0,bit-depth-luma=(uint)8,bit-depth-chroma=(uint)8' }
        'VP8'  { return 'video/x-vp8' }
        'VP9'  { return 'video/x-vp9' }
        default { throw "Unsupported recording codec: $Codec" }
    }
}


function Add-CustomEncoderOptions {
    param(
        [Parameter(Mandatory)]$Parts,
        [AllowNull()][string]$Options
    )

    $text = ([string]$Options).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return }

    foreach ($chunk in ($text -split '\s+')) {
        if (-not [string]::IsNullOrWhiteSpace($chunk)) {
            $Parts.Add($chunk)
        }
    }
}

function Get-ComboSelectedOrDefault {
    param(
        [Parameter(Mandatory)]$ComboBox,
        [Parameter(Mandatory)][string]$Default
    )

    $value = [string]$ComboBox.SelectedItem
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value
}

function Add-NvencRateControlOptions {
    param(
        [Parameter(Mandatory)]$Parts,
        [Parameter(Mandatory)][string]$RateControl,
        [Parameter(Mandatory)][int]$BitrateKbps,
        [Parameter(Mandatory)][int]$MaxBitrateKbps,
        [Parameter(Mandatory)][int]$ConstantQp
    )

    switch ($RateControl) {
        'constqp' {
            $Parts.Add('rc-mode=constqp')
            $Parts.Add("qp-const=$ConstantQp")
            $Parts.Add("qp-const-i=$ConstantQp")
            $Parts.Add("qp-const-p=$ConstantQp")
            $Parts.Add("qp-const-b=$ConstantQp")
        }
        'vbr' {
            # Plain NVENC VBR. Do not append const-quality here.
            # const-quality is a VBR quality target, not the same as normal VBR,
            # and using the Constant QP UI value here made H.264/H.265/AV1 VBR
            # behave like CQ-VBR. Users can still add const-quality explicitly
            # through Custom encoder options when intentionally testing CQ-VBR.
            $Parts.Add("bitrate=$BitrateKbps")
            $Parts.Add('rc-mode=vbr')
            if ($MaxBitrateKbps -gt 0) { $Parts.Add("max-bitrate=$MaxBitrateKbps") }
        }
        default {
            $Parts.Add("bitrate=$BitrateKbps")
            $Parts.Add('rc-mode=cbr')
        }
    }
}

function Add-QsvRateControlOptions {
    param(
        [Parameter(Mandatory)]$Parts,
        [Parameter(Mandatory)][string]$RateControl,
        [Parameter(Mandatory)][int]$BitrateKbps,
        [Parameter(Mandatory)][int]$MaxBitrateKbps,
        [Parameter(Mandatory)][int]$ConstantQp,
        [Parameter(Mandatory)][int]$LookAheadFrames,
        [Parameter(Mandatory)][string]$Codec
    )

    switch ($RateControl) {
        'constqp' {
            $Parts.Add('rate-control=cqp')
            if ($Codec -in @('H264','H265')) {
                $Parts.Add("qp-i=$ConstantQp")
                $Parts.Add("qp-p=$ConstantQp")
                $Parts.Add("qp-b=$ConstantQp")
            }
        }
        'vbr' {
            if ($LookAheadFrames -gt 0 -and $Codec -in @('H264','H265')) {
                $Parts.Add('rate-control=la-vbr')
                $Parts.Add("rc-lookahead=$LookAheadFrames")
            }
            else {
                $Parts.Add('rate-control=vbr')
            }
            $Parts.Add("bitrate=$BitrateKbps")
            if ($MaxBitrateKbps -gt 0) { $Parts.Add("max-bitrate=$MaxBitrateKbps") }
        }
        default {
            if ($LookAheadFrames -gt 0 -and $Codec -in @('H264','H265')) {
                $Parts.Add('rate-control=la-hrd')
                $Parts.Add("rc-lookahead=$LookAheadFrames")
            }
            else {
                $Parts.Add('rate-control=cbr')
                if ($Codec -in @('H264','H265')) { $Parts.Add('rc-lookahead=0') }
            }
            $Parts.Add("bitrate=$BitrateKbps")
        }
    }
}

function Get-RecordingEncoderElementChain {
    $definition = Get-SelectedRecordingEncoderDefinition
    $element = [string]$definition.Element
    $codec = [string]$definition.Codec
    $family = [string]$definition.Family
    $inputType = [string]$definition.Input
    $parser = [string]$definition.Parser
    $width = [int]$numRecordingWidth.Value
    $height = [int]$numRecordingHeight.Value
    $fps = [int]$numRecordingFps.Value
    $videoBitrateKbps = [int]$numRecordingVideoBitrate.Value
    $videoBitrateBps = $videoBitrateKbps * 1000
    $maxVideoBitrateKbps = [int]$numRecordingMaxVideoBitrate.Value
    $constantQp = [int]$numRecordingConstantQp.Value
    $gopSize = [Math]::Max(1, $fps * [int]$numRecordingGopSeconds.Value)
    $preset = [string]$cmbRecordingPreset.SelectedItem
    $rateControl = Get-ComboSelectedOrDefault $cmbRecordingRateControl 'constqp'
    $tune = Get-ComboSelectedOrDefault $cmbRecordingTune 'high-quality'
    $multipass = Get-ComboSelectedOrDefault $cmbRecordingMultipass 'two-pass-quarter'
    $support = Get-RecordingEncoderControlSupport
    $bFrames = if ($support.BFrames) { [int]$numRecordingBFrames.Value } else { 0 }
    $lookAheadFrames = if ($support.LookAhead -and $chkRecordingLookAhead.Checked) { [int]$numRecordingLookAheadFrames.Value } else { 0 }
    $spatialAq = $support.AdaptiveQuantization -and $chkRecordingSpatialAq.Checked
    $temporalAq = $support.AdaptiveQuantization -and $chkRecordingTemporalAq.Checked
    $aqStrength = [int]$numRecordingAqStrength.Value
    $aqStrengthFloat = ($aqStrength / 8.0).ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture)
    $vbvBuffer = [int]$numRecordingVbvBuffer.Value
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($x in @('queue','max-size-buffers=12','max-size-bytes=0','max-size-time=0','leaky=downstream','!','d3d11convert','!')) { $parts.Add($x) }
    $parts.Add("`"video/x-raw(memory:D3D11Memory),format=NV12,width=$width,height=$height,framerate=$fps/1`"")
    $parts.Add('!')
    if ($inputType -eq 'I420') {
        foreach ($x in @('d3d11download','!','videoconvert','!')) { $parts.Add($x) }
        $parts.Add("`"video/x-raw,format=I420,width=$width,height=$height,framerate=$fps/1`"")
        $parts.Add('!')
    }
    $parts.Add($element)
    switch ($family) {
        'NVENC' {
            $zeroLatency = ($bFrames -eq 0 -and $lookAheadFrames -eq 0 -and $tune -in @('low-latency','ultra-low-latency'))
            Add-NvencRateControlOptions $parts $rateControl $videoBitrateKbps $maxVideoBitrateKbps $constantQp
            foreach ($x in @("preset=$preset","tune=$tune","multi-pass=$multipass","zerolatency=$($zeroLatency.ToString().ToLowerInvariant())","bframes=$bFrames","b-adapt=$((($bFrames -gt 0) -and ($lookAheadFrames -gt 0)).ToString().ToLowerInvariant())","gop-size=$gopSize","rc-lookahead=$lookAheadFrames","spatial-aq=$($spatialAq.ToString().ToLowerInvariant())","temporal-aq=$($temporalAq.ToString().ToLowerInvariant())")) { $parts.Add($x) }
            if ($spatialAq -or $temporalAq) { $parts.Add("aq-strength=$aqStrength") }
            if ($vbvBuffer -gt 0) { $parts.Add("vbv-buffer-size=$vbvBuffer") }
            if ($codec -in @('H264','H265')) { $parts.Add('repeat-sequence-header=true') }
        }
        'AMF' {
            foreach ($x in @("bitrate=$videoBitrateKbps",'rate-control=cbr','preset=quality','usage=transcoding',"gop-size=$gopSize",'pre-encode=false')) { $parts.Add($x) }
            if ($codec -eq 'H264') { $parts.Add("b-frames=$bFrames"); $parts.Add("max-b-frames=$bFrames") }
        }
        'QSV' {
            Add-QsvRateControlOptions $parts $rateControl $videoBitrateKbps $maxVideoBitrateKbps $constantQp $lookAheadFrames $codec
            $parts.Add("gop-size=$gopSize")
            if ($codec -in @('H264','H265')) { $parts.Add("b-frames=$bFrames") }
        }
        'MF' {
            foreach ($x in @("bitrate=$videoBitrateKbps",'rc-mode=cbr',"gop-size=$gopSize",'low-latency=false')) { $parts.Add($x) }
            if ($support.BFrames) { $parts.Add("bframes=$bFrames") }
        }
        'X264' {
            if ($rateControl -eq 'constqp') { $parts.Add('pass=quant'); $parts.Add("quantizer=$constantQp") } else { $parts.Add("bitrate=$videoBitrateKbps") }
            $parts.Add('speed-preset=veryfast')
            if ($tune -in @('low-latency','ultra-low-latency')) { $parts.Add('tune=zerolatency') }
            foreach ($x in @("key-int-max=$gopSize","bframes=$bFrames","rc-lookahead=$lookAheadFrames",'byte-stream=true','aud=true')) { $parts.Add($x) }
        }
        'X265' {
            if ($rateControl -ne 'constqp') { $parts.Add("bitrate=$videoBitrateKbps") }
            $parts.Add('speed-preset=veryfast')
            if ($tune -in @('low-latency','ultra-low-latency')) { $parts.Add('tune=zerolatency') }
            $parts.Add("key-int-max=$gopSize")
            $x265Options = New-Object System.Collections.Generic.List[string]
            $x265Options.Add("bframes=$bFrames")
            $x265Options.Add("rc-lookahead=$lookAheadFrames")
            if ($rateControl -eq 'constqp') { $x265Options.Add("qp=$constantQp") }
            if ($spatialAq -or $temporalAq) { $x265Options.Add('aq-mode=2'); $x265Options.Add("aq-strength=$aqStrengthFloat") } else { $x265Options.Add('aq-mode=0') }
            $parts.Add("option-string=$($x265Options -join ':')")
        }
        'OPENH264' { foreach ($x in @("bitrate=$videoBitrateBps",'rate-control=bitrate','complexity=medium','usage-type=screen',"gop-size=$gopSize")) { $parts.Add($x) } }
        'AOM' { foreach ($x in @("target-bitrate=$videoBitrateKbps",'end-usage=cbr','cpu-used=6','lag-in-frames=0',"keyframe-max-dist=$gopSize",'row-mt=true')) { $parts.Add($x) } }
        'SVTAV1' { foreach ($x in @("target-bitrate=$videoBitrateKbps",'preset=8',"intra-period-length=$gopSize",'intra-refresh-type=IDR')) { $parts.Add($x) } }
        'RAV1E' { foreach ($x in @("bitrate=$videoBitrateBps",'low-latency=true','speed-preset=8',"max-key-frame-interval=$gopSize",'min-key-frame-interval=1','rdo-lookahead-frames=0')) { $parts.Add($x) } }
        'VPX' { foreach ($x in @("target-bitrate=$videoBitrateBps",'deadline=1','end-usage=cbr',"keyframe-max-dist=$gopSize",'lag-in-frames=0')) { $parts.Add($x) } }
        default { throw "Unsupported recording encoder family: $family" }
    }
    Add-CustomEncoderOptions $parts $txtRecordingCustomEncoderOptions.Text
    if (-not [string]::IsNullOrWhiteSpace($parser)) {
        $parts.Add('!'); $parts.Add($parser)
        if ($codec -in @('H264','H265')) { $parts.Add('config-interval=-1') }
    }
    $parts.Add('!')
    $parts.Add("`"$(Get-RecordingEncodedVideoCaps -Codec $codec)`"")
    return ($parts -join ' ')
}

function Build-RecordingRawAudioChain {
    $desktopEnabled = $chkRecordingDesktopAudio.Checked
    $micEnabled = $chkRecordingMic.Checked
    if (-not $desktopEnabled -and -not $micEnabled) { return '' }

    # Recording audio shares the same pipeline clock. Reuse the Audio-tab WASAPI
    # source builder so recording cannot silently inject low-latency/buffer/clock
    # properties that are disabled in the timing lab.
    $desktopSource = Get-WasapiSourceString -Loopback
    $micSource = Get-WasapiSourceString

    if ($desktopEnabled -and -not $micEnabled) {
        return @($desktopSource,'!','queue','max-size-buffers=16','max-size-bytes=0','max-size-time=0','leaky=downstream','!','audioconvert','!','audioresample','!',(Get-AudioRawCapsString -Format 'S16LE' -Channels 2)) -join ' '
    }
    if (-not $desktopEnabled -and $micEnabled) {
        return @($micSource,'!','queue','max-size-buffers=16','max-size-bytes=0','max-size-time=0','leaky=downstream','!','audioconvert','!','audioresample','!',(Get-AudioRawCapsString -Format 'S16LE' -Channels 2)) -join ' '
    }
    $desktopMixBranch = @($desktopSource,'!','queue','max-size-buffers=16','max-size-bytes=0','max-size-time=0','leaky=downstream','!','audioconvert','!','audioresample','!',(Get-AudioRawCapsString -Format 'F32LE' -Channels 2),'!','recordaudiomix.') -join ' '
    $micMixBranch = @($micSource,'!','queue','max-size-buffers=16','max-size-bytes=0','max-size-time=0','leaky=downstream','!','audioconvert','!','audioresample','!',(Get-AudioRawCapsString -Format 'F32LE' -Channels 2),'!','recordaudiomix.') -join ' '
    $mixOutput = @('recordaudiomix.','!','queue','max-size-buffers=16','max-size-bytes=0','max-size-time=0','leaky=downstream','!','audioconvert','!',(Get-AudioRawCapsString -Format 'S16LE' -Channels 2)) -join ' '
    return "audiomixer name=recordaudiomix $desktopMixBranch $micMixBranch $mixOutput"
}

function Build-RecordingAudioBranch {
    if (-not (Test-RecordingEnabled)) { return '' }
    $raw = Build-RecordingRawAudioChain
    if ([string]::IsNullOrWhiteSpace($raw)) { return '' }
    $bitrate = [int]$numRecordingAudioBitrate.Value * 1000
    return "$raw ! opusenc bitrate=$bitrate bitrate-type=cbr frame-size=10 audio-type=restricted-lowdelay ! `"audio/x-opus`" ! recordmux."
}

function Get-RecordingBranchQueue {
    # A tee branch without a queue is pushed synchronously on the tee's streaming
    # thread - which here is the capture thread. Without this, the recording
    # encoder + matroskamux + filesink write all run inline on capture, and
    # because tee pushes to its src pads in link order (recording is linked
    # first), the live/transport branch does not even receive a buffer until the
    # recording write returns. Any disk hitch therefore lands directly on the
    # live encode path.
    #
    # Kept shallow deliberately: these are D3D11Memory buffers from a fixed-size
    # capture pool. A deep queue here would hold GPU textures, starve the pool,
    # and stall d3d11screencapturesrc - worse than the problem being fixed.
    #
    # leaky=no preserves recording integrity: sustained disk overrun will still
    # backpressure rather than silently punch frame gaps into the file. To favour
    # the live stream over the recording instead, change this to leaky=downstream
    # and accept dropped frames in the recorded file.
    return 'queue name=recordq max-size-buffers=4 max-size-bytes=0 max-size-time=0 leaky=no'
}

function Build-RecordingMuxPrefixAndVideoBranch {
    if (-not (Test-RecordingEnabled)) { return '' }
    $recordingPath = if (-not [string]::IsNullOrWhiteSpace($script:ResolvedRecordingPath)) { $script:ResolvedRecordingPath } else { Resolve-RecordingFilePath }
    $quotedRecordingPath = Quote-GstValue $recordingPath
    $encoder = Get-RecordingEncoderElementChain
    $recordQueue = Get-RecordingBranchQueue
    return "matroskamux name=recordmux writing-app=`"GStreamer Glass`" ! filesink location=$quotedRecordingPath async=false rawtee. ! $recordQueue ! $encoder ! recordmux."
}

function Update-RecordingUi {
    if (-not $chkRecordingEnabled) { return }
    $enabled = [bool]$chkRecordingEnabled.Checked
    $definition = Get-SelectedRecordingEncoderDefinition
    $codec = [string]$definition.Codec
    $family = [string]$definition.Family
    $kind = [string]$definition.Kind
    foreach ($control in @($txtRecordingDirectory,$btnBrowseRecordingDirectory,$txtRecordingTemplate,$cmbRecordingEncoder,$cmbRecordingRateControl,$numRecordingWidth,$numRecordingHeight,$numRecordingFps,$numRecordingVideoBitrate,$numRecordingMaxVideoBitrate,$numRecordingConstantQp,$numRecordingGopSeconds,$chkRecordingDesktopAudio,$chkRecordingMic,$numRecordingAudioBitrate,$txtRecordingCustomEncoderOptions)) {
        if ($control) { $control.Enabled = $enabled }
    }
    $isNvenc = ($family -eq 'NVENC')
    $cmbRecordingPreset.Enabled = $enabled -and $isNvenc
    $cmbRecordingTune.Enabled = $enabled -and $isNvenc
    $cmbRecordingMultipass.Enabled = $enabled -and $isNvenc
    $numRecordingVbvBuffer.Enabled = $enabled -and $isNvenc
    $cmbRecordingProfile.Enabled = $enabled -and ($codec -eq 'H264')
    $support = Get-RecordingEncoderControlSupport
    $numRecordingBFrames.Enabled = $enabled -and $support.BFrames
    $chkRecordingLookAhead.Enabled = $enabled -and $support.LookAhead
    $numRecordingLookAheadFrames.Enabled = $enabled -and $support.LookAhead -and $chkRecordingLookAhead.Checked
    $chkRecordingSpatialAq.Enabled = $enabled -and $support.AdaptiveQuantization
    $chkRecordingTemporalAq.Enabled = $enabled -and $support.AdaptiveQuantization
    $numRecordingAqStrength.Enabled = $enabled -and $support.AdaptiveQuantization -and ($chkRecordingSpatialAq.Checked -or $chkRecordingTemporalAq.Checked)
    if ($enabled) {
        $audioSummary = if ($chkRecordingDesktopAudio.Checked -or $chkRecordingMic.Checked) { 'Opus audio' } else { 'video only' }
        $rcSummary = Get-ComboSelectedOrDefault $cmbRecordingRateControl 'constqp'
        $lblRecordingStatus.Text = "$codec * $kind * $rcSummary * MKV * $audioSummary"
        $lblRecordingStatus.ForeColor = [System.Drawing.Color]::DarkSlateBlue
    }
    else {
        $lblRecordingStatus.Text = 'Recording disabled'
        $lblRecordingStatus.ForeColor = [System.Drawing.Color]::DimGray
    }
    Update-CommandPreview
}

function Get-SelectedEncoderDefinition {
    $name = [string]$cmbEncoder.SelectedItem
    if (
        [string]::IsNullOrWhiteSpace($name) -or
        -not $script:EncoderCatalog.Contains($name)
    ) {
        $name = $script:DefaultEncoderName
    }

    return $script:EncoderCatalog[$name]
}

function Get-SelectedAudioCodecDefinition {
    $name = [string]$cmbAudioCodec.SelectedItem
    if (
        [string]::IsNullOrWhiteSpace($name) -or
        -not $script:AudioCodecCatalog.Contains($name)
    ) {
        $protocol = [string]$cmbProtocol.SelectedItem
        $name = [string]$script:DefaultAudioCodecByProtocol[$protocol]
    }

    return $script:AudioCodecCatalog[$name]
}

function Test-AudioCodecProtocolCompatibility {
    param(
        [Parameter(Mandatory)][string]$AudioCodecName,
        [Parameter(Mandatory)][string]$Protocol
    )

    if (-not $script:AudioCodecCatalog.Contains($AudioCodecName)) {
        return $false
    }

    return $Protocol -in @($script:AudioCodecCatalog[$AudioCodecName].Protocols)
}

function Get-CompatibleAudioCodecNames {
    param([Parameter(Mandatory)][string]$Protocol)

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($name in $script:AudioCodecCatalog.Keys) {
        if (Test-AudioCodecProtocolCompatibility -AudioCodecName $name -Protocol $Protocol) {
            $names.Add([string]$name)
        }
    }

    return @($names)
}

function Update-AudioCodecChoices {
    param([switch]$PreserveCurrent)

    $protocol = [string]$cmbProtocol.SelectedItem
    if ([string]::IsNullOrWhiteSpace($protocol)) {
        return
    }

    $current = [string]$cmbAudioCodec.SelectedItem
    if (
        $PreserveCurrent -and
        -not [string]::IsNullOrWhiteSpace($current) -and
        (Test-AudioCodecProtocolCompatibility -AudioCodecName $current -Protocol $protocol)
    ) {
        $script:ProtocolAudioCodecs[$protocol] = $current
    }

    $desired = [string]$script:ProtocolAudioCodecs[$protocol]
    $compatible = Get-CompatibleAudioCodecNames -Protocol $protocol

    if ($desired -notin $compatible) {
        $desired = [string]$script:DefaultAudioCodecByProtocol[$protocol]
    }

    $script:SuppressAudioCodecChange = $true
    try {
        $cmbAudioCodec.BeginUpdate()
        $cmbAudioCodec.Items.Clear()
        foreach ($name in $compatible) {
            $null = $cmbAudioCodec.Items.Add($name)
        }

        if ($cmbAudioCodec.Items.Contains($desired)) {
            $cmbAudioCodec.SelectedItem = $desired
        }
        elseif ($cmbAudioCodec.Items.Count -gt 0) {
            $cmbAudioCodec.SelectedIndex = 0
        }
    }
    finally {
        $cmbAudioCodec.EndUpdate()
        $script:SuppressAudioCodecChange = $false
    }

    $selected = [string]$cmbAudioCodec.SelectedItem
    if ($selected) {
        $script:ProtocolAudioCodecs[$protocol] = $selected
        $audioMode = Get-ComboSelectedOrDefault $cmbAudioTransportMode $script:DefaultAudioTransportMode
        $audioTimingMode = Get-AudioTimingMode
        if ($audioMode -eq 'Video only - no audio track') {
            $lblAudioCodecStatus.Text = "$protocol * video-only diagnostic"
            $lblAudioCodecStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        elseif ($audioTimingMode -eq 'Synthetic silent audio') {
            $lblAudioCodecStatus.Text = "$protocol * synthetic silent Opus timing diagnostic"
            $lblAudioCodecStatus.ForeColor = [System.Drawing.Color]::DarkSlateBlue
        }
        elseif ($audioMode -eq 'Muted audio clock only') {
            $lblAudioCodecStatus.Text = "$protocol * muted Opus clock diagnostic"
            $lblAudioCodecStatus.ForeColor = [System.Drawing.Color]::DarkSlateBlue
        }
        elseif (
            $protocol -in @('WHIP', 'GST WebRTC') -and
            -not $chkDesktopAudio.Checked -and
            -not $chkMic.Checked
        ) {
            $lblAudioCodecStatus.Text = "$protocol * muted Opus clock track (automatic)"
            $lblAudioCodecStatus.ForeColor = [System.Drawing.Color]::DarkSlateBlue
        }
        else {
            $lblAudioCodecStatus.Text =
                "$protocol compatible * $([string]$script:AudioCodecCatalog[$selected].Codec)"
            $lblAudioCodecStatus.ForeColor = [System.Drawing.Color]::DimGray
        }
    }

    if ($cmbDesktopAudioDevice) { $cmbDesktopAudioDevice.Enabled = $chkDesktopAudio.Checked }
    if ($chkAudioMixerMode) {
        $chkAudioMixerMode.Enabled = $chkDesktopAudio.Checked
        if ($chkDesktopAudio.Checked -and $chkMic.Checked) {
            $toolTip.SetToolTip($chkAudioMixerMode, 'Desktop + microphone requires audiomixer to combine both sources. This flag controls desktop-only mixer normalization versus the legacy direct path.')
        }
        else {
            $toolTip.SetToolTip($chkAudioMixerMode, 'Recommended timing-normalization path. When enabled, desktop-only audio is routed through audiomixer before encoding. Uncheck to restore the legacy direct WASAPI-to-encoder path.')
        }
    }
    if ($cmbMicAudioDevice) { $cmbMicAudioDevice.Enabled = $chkMic.Checked }

    Update-CommandPreview
}

function Get-EncoderControlSupport {
    $definition = Get-SelectedEncoderDefinition
    $family = [string]$definition.Family
    $codec = [string]$definition.Codec

    $supportsBFrames = $false
    $supportsLookAhead = $false
    $supportsAq = $false

    switch ($family) {
        'NVENC' {
            $supportsBFrames = $true
            $supportsLookAhead = $true
            $supportsAq = $true
        }
        'AMF' {
            $supportsBFrames = ($codec -eq 'H264')
            $supportsLookAhead = ($codec -in @('H264', 'H265'))
        }
        'QSV' {
            $supportsBFrames = ($codec -in @('H264', 'H265'))
            $supportsLookAhead = ($codec -in @('H264', 'H265'))
        }
        'MF' {
            $supportsBFrames = ($codec -in @('H264', 'H265'))
        }
        'X264' {
            $supportsBFrames = $true
            $supportsLookAhead = $true
            $supportsAq = $true
        }
        'X265' {
            $supportsBFrames = $true
            $supportsLookAhead = $true
            $supportsAq = $true
        }
        'AOM' { $supportsLookAhead = $true }
        'RAV1E' { $supportsLookAhead = $true }
        'VPX' { $supportsLookAhead = $true }
    }

    return [pscustomobject]@{
        BFrames = $supportsBFrames
        LookAhead = $supportsLookAhead
        AdaptiveQuantization = $supportsAq
    }
}

function Get-AudioEncoderChain {
    param([Parameter(Mandatory)][string]$Protocol)

    $definition = Get-SelectedAudioCodecDefinition
    $family = [string]$definition.Family
    $bitrateKbps = [int]$numAudioBitrate.Value
    $bitrateBps = $bitrateKbps * 1000

    switch ($family) {
        'OPUS' {
            return "opusenc bitrate=$bitrateBps bitrate-type=cbr frame-size=10 audio-type=restricted-lowdelay ! `"audio/x-opus`""
        }
        'AAC_MF' {
            $aacBitrate = Get-NearestAacBitrate -RequestedKbps $bitrateKbps
            $format = if ($Protocol -eq 'SRT') { 'adts' } else { 'raw' }
            return "mfaacenc bitrate=$aacBitrate ! aacparse ! `"audio/mpeg,mpegversion=4,stream-format=$format,framed=true`""
        }
        'AAC_FDK' {
            $format = if ($Protocol -eq 'SRT') { 'adts' } else { 'raw' }
            return "fdkaacenc bitrate=$bitrateBps rate-control=cbr ! aacparse ! `"audio/mpeg,mpegversion=4,stream-format=$format,framed=true`""
        }
        'AAC_LIBAV' {
            $format = if ($Protocol -eq 'SRT') { 'adts' } else { 'raw' }
            return "audioconvert ! $(Get-AudioRawCapsString -Format 'F32LE' -Channels 2) ! avenc_aac bitrate=$bitrateBps ! aacparse ! `"audio/mpeg,mpegversion=4,stream-format=$format,framed=true`""
        }
        'AAC_VO' {
            $format = if ($Protocol -eq 'SRT') { 'adts' } else { 'raw' }
            return "voaacenc bitrate=$bitrateBps ! aacparse ! `"audio/mpeg,mpegversion=4,stream-format=$format`""
        }
        'MP3' {
            $valid = @(32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320)
            $mp3Bitrate = [int](
                $valid |
                Sort-Object { [Math]::Abs($_ - $bitrateKbps) } |
                Select-Object -First 1
            )
            return "lamemp3enc target=bitrate cbr=true bitrate=$mp3Bitrate encoding-engine-quality=fast ! mpegaudioparse ! `"audio/mpeg,mpegversion=1,layer=3,parsed=true`""
        }
        'AC3' {
            return "audioconvert ! $(Get-AudioRawCapsString -Format 'F32LE' -Channels 2) ! avenc_ac3 bitrate=$bitrateBps ! ac3parse ! `"audio/x-ac3,framed=true`""
        }
        default {
            throw "Unsupported audio encoder family: $family"
        }
    }
}

function Test-CodecProtocolCompatibility {
    param(
        [Parameter(Mandatory)][string]$Codec,
        [Parameter(Mandatory)][string]$Protocol
    )

    switch ($Protocol) {
        'WHIP' { return $Codec -in @('H264', 'H265', 'AV1', 'VP8', 'VP9') }
        'GST WebRTC' { return $Codec -in @('H264', 'H265', 'AV1', 'VP8', 'VP9') }
        'SRT'  { return $Codec -in @('H264', 'H265', 'AV1', 'VP9') }
        'RTMP' { return $Codec -in @('H264', 'H265', 'AV1') }
        'RTSP' { return $Codec -in @('H264', 'H265', 'AV1', 'VP8', 'VP9') }
        default { return $false }
    }
}

function Get-CodecMediaType {
    param([Parameter(Mandatory)][string]$Codec)

    switch ($Codec) {
        'H264' { return 'video/x-h264' }
        'H265' { return 'video/x-h265' }
        'AV1'  { return 'video/x-av1' }
        'VP8'  { return 'video/x-vp8' }
        'VP9'  { return 'video/x-vp9' }
        default { throw "Unsupported codec: $Codec" }
    }
}

function Get-EncodedVideoCaps {
    param(
        [Parameter(Mandatory)][string]$Codec,
        [Parameter(Mandatory)][string]$Protocol
    )

    $profile = [string]$cmbProfile.SelectedItem

    switch ($Codec) {
        'H264' {
            $streamFormat = if ($Protocol -eq 'RTMP') { 'avc' } else { 'byte-stream' }
            if ($Protocol -eq 'WHIP') {
                # WHIP/WHEP/browser compatibility guard. A saved High profile
                # setting can make MediaMTX/WHIP sessions look like they never
                # publish or never become readable, especially after switching
                # between Direct GST WebRTC experiments and MediaMTX ingest.
                # Keep the UI profile for other protocols, but publish WHIP as
                # constrained-baseline unless/until we add a dedicated advanced
                # WHIP override.
                $profile = 'constrained-baseline'
            }
            return "video/x-h264,profile=$profile,stream-format=$streamFormat,alignment=au"
        }
        'H265' {
            $streamFormat = if ($Protocol -eq 'RTMP') { 'hvc1' } else { 'byte-stream' }
            return "video/x-h265,profile=main,stream-format=$streamFormat,alignment=au"
        }
        'AV1' {
            $alignment = if ($Protocol -eq 'SRT') { 'frame' } else { 'tu' }
            if ($Protocol -in @('GST WebRTC', 'WHIP')) {
                # Keep AV1 caps intentionally minimal for rswebrtc/webrtcsink.
                # The stricter caps pinned chroma-format and bit-depth, but the
                # GStreamer 1.28.5 rswebrtc path rejected that downstream handoff
                # with not-negotiated before out.video_0 accepted the caps.
                # profile=main avoids the earliest generic caps while still
                # allowing the WebRTC sink to negotiate the RTP payload.
                return "video/x-av1,stream-format=obu-stream,alignment=$alignment,profile=main"
            }
            return "video/x-av1,stream-format=obu-stream,alignment=$alignment"
        }
        'VP8' { return 'video/x-vp8' }
        'VP9' { return 'video/x-vp9' }
        default { throw "Unsupported codec: $Codec" }
    }
}

function Get-EncoderElementChain {
    param([Parameter(Mandatory)][string]$Protocol)

    $definition = Get-SelectedEncoderDefinition
    $element = [string]$definition.Element
    $codec = [string]$definition.Codec
    $family = [string]$definition.Family
    $inputType = [string]$definition.Input
    $parser = [string]$definition.Parser

    $width = [int]$numWidth.Value
    $height = [int]$numHeight.Value
    $fps = [int]$numFps.Value
    $videoBitrateKbps = [int]$numVideoBitrate.Value
    $videoBitrateBps = $videoBitrateKbps * 1000
    $maxVideoBitrateKbps = [int]$numMaxVideoBitrate.Value
    $constantQp = [int]$numConstantQp.Value
    $gopSize = [Math]::Max(1, $fps * [int]$numGopSeconds.Value)
    if (
        (Test-DirectWebRtcUnifiedPublisher) -and
        $codec -in @('H264','H265') -and
        $chkUnifiedBridgeKeyframeGuard.Checked
    ) {
        $bridgeKeyframeMs = [int]$numUnifiedBridgeKeyframeIntervalMs.Value
        $gopSize = [Math]::Max(1, [int][Math]::Ceiling(($fps * $bridgeKeyframeMs) / 1000.0))
    }
    $preset = [string]$cmbPreset.SelectedItem
    $rateControl = Get-ComboSelectedOrDefault $cmbRateControl 'cbr'
    $tune = Get-ComboSelectedOrDefault $cmbEncoderTune 'ultra-low-latency'
    $multipass = Get-ComboSelectedOrDefault $cmbMultipass 'disabled'
    $controlSupport = Get-EncoderControlSupport
    $bFrames = if ($controlSupport.BFrames) { [int]$numBFrames.Value } else { 0 }
    $lookAheadFrames = if (
        $controlSupport.LookAhead -and
        $chkLookAhead.Checked
    ) {
        [int]$numLookAheadFrames.Value
    }
    else {
        0
    }
    $spatialAq = $controlSupport.AdaptiveQuantization -and $chkAdaptiveQuantization.Checked
    $temporalAq = $controlSupport.AdaptiveQuantization -and $chkTemporalAq.Checked
    $aqEnabled = $spatialAq -or $temporalAq
    $aqStrength = [int]$numAqStrength.Value
    $vbvBuffer = [int]$numVbvBuffer.Value
    $aqStrengthFloat = ($aqStrength / 8.0).ToString(
        '0.###',
        [System.Globalization.CultureInfo]::InvariantCulture
    )
    $cpuWorkers = Get-CpuWorkerLimit

    if ($Protocol -eq 'WHIP') {
        # WHIP publish guard:
        # - WebRTC readers expect frequent keyframes; saved 10s GOP / 120 fps
        #   settings can make publishing appear broken or make readers wait too
        #   long for a usable IDR.
        # - B-frames/lookahead add reordering delay and have previously caused
        #   MediaMTX/WebRTC problems in this project.
        # - NVENC default/high-quality tune was observed as choppier than
        #   ultra-low-latency here, so WHIP stays on the proven ULL path.
        $gopSize = [Math]::Min($gopSize, [Math]::Max(1, $fps))
        $bFrames = 0
        $lookAheadFrames = 0
        $spatialAq = $false
        $temporalAq = $false
        $aqEnabled = $false
        if ($family -eq 'NVENC') {
            $tune = 'ultra-low-latency'
            $multipass = 'disabled'
        }
    }

    $parts = New-Object System.Collections.Generic.List[string]

    $parts.Add((Get-CaptureEncoderQueue))
    $parts.Add('!')

    if ($inputType -eq 'I420') {
        $parts.Add('d3d11download')
        $parts.Add('!')
        $parts.Add($(if ($cpuWorkers -gt 0) { "videoconvert n-threads=$cpuWorkers" } else { 'videoconvert' }))
        $parts.Add('!')
        $parts.Add(
            "`"video/x-raw,format=I420,width=$width,height=$height,framerate=$fps/1`""
        )
        $parts.Add('!')
    }

    $parts.Add($element)

    switch ($family) {
        'NVENC' {
            $zeroLatency = ($bFrames -eq 0 -and $lookAheadFrames -eq 0 -and $tune -in @('low-latency','ultra-low-latency'))
            Add-NvencRateControlOptions $parts $rateControl $videoBitrateKbps $maxVideoBitrateKbps $constantQp
            $parts.Add("preset=$preset")
            $parts.Add("tune=$tune")
            $parts.Add("multi-pass=$multipass")
            $parts.Add("zerolatency=$($zeroLatency.ToString().ToLowerInvariant())")
            $parts.Add("bframes=$bFrames")
            $parts.Add(
                "b-adapt=$((($bFrames -gt 0) -and ($lookAheadFrames -gt 0)).ToString().ToLowerInvariant())"
            )
            $parts.Add("gop-size=$gopSize")
            $parts.Add("rc-lookahead=$lookAheadFrames")
            $parts.Add("spatial-aq=$($spatialAq.ToString().ToLowerInvariant())")
            $parts.Add("temporal-aq=$($temporalAq.ToString().ToLowerInvariant())")
            if ($aqEnabled) { $parts.Add("aq-strength=$aqStrength") }
            if ($vbvBuffer -gt 0) { $parts.Add("vbv-buffer-size=$vbvBuffer") }
            if ($codec -in @('H264', 'H265')) {
                $parts.Add('repeat-sequence-header=true')
            }
        }
        'AMF' {
            $parts.Add("bitrate=$videoBitrateKbps")
            $parts.Add('rate-control=cbr')
            $parts.Add('preset=speed')
            $parts.Add(
                $(if ($codec -eq 'AV1') {
                    'usage=low-latency'
                }
                else {
                    'usage=ultra-low-latency'
                })
            )
            $parts.Add("gop-size=$gopSize")
            $parts.Add(
                "pre-analysis=$((($lookAheadFrames -gt 0)).ToString().ToLowerInvariant())"
            )
            $parts.Add('pre-encode=false')
            if ($codec -eq 'H264') {
                $parts.Add("b-frames=$bFrames")
                $parts.Add("max-b-frames=$bFrames")
                $parts.Add(
                    "adaptive-mini-gop=$((($bFrames -gt 0) -and ($lookAheadFrames -gt 0)).ToString().ToLowerInvariant())"
                )
            }
            if ($lookAheadFrames -gt 0 -and $codec -in @('H264', 'H265')) {
                $parts.Add("pa-lookahead-buffer-depth=$lookAheadFrames")
            }
        }
        'QSV' {
            Add-QsvRateControlOptions $parts $rateControl $videoBitrateKbps $maxVideoBitrateKbps $constantQp $lookAheadFrames $codec
            $parts.Add("gop-size=$gopSize")
            if ($codec -in @('H264', 'H265')) {
                $parts.Add("b-frames=$bFrames")
            }
        }
        'MF' {
            $parts.Add("bitrate=$videoBitrateKbps")
            $parts.Add('rc-mode=cbr')
            $parts.Add("gop-size=$gopSize")
            $parts.Add('low-latency=true')
            if ($controlSupport.BFrames) {
                $parts.Add("bframes=$bFrames")
            }
        }
        'X264' {
            if ($rateControl -eq 'constqp') { $parts.Add('pass=quant'); $parts.Add("quantizer=$constantQp") } else { $parts.Add("bitrate=$videoBitrateKbps") }
            $parts.Add('speed-preset=ultrafast')
            if ($tune -in @('low-latency','ultra-low-latency')) { $parts.Add('tune=zerolatency') }
            $parts.Add("key-int-max=$gopSize")
            $parts.Add("bframes=$bFrames")
            $parts.Add(
                "b-adapt=$((($bFrames -gt 0) -and ($lookAheadFrames -gt 0)).ToString().ToLowerInvariant())"
            )
            $parts.Add("rc-lookahead=$lookAheadFrames")
            $parts.Add('sync-lookahead=0')
            $parts.Add("mb-tree=$($aqEnabled.ToString().ToLowerInvariant())")
            $x264AqOptions = if ($aqEnabled) { "aq-mode=2:aq-strength=$aqStrengthFloat" } else { 'aq-mode=0' }
            $parts.Add("option-string=$x264AqOptions")
            $parts.Add('sliced-threads=true')
            if ($cpuWorkers -gt 0) { $parts.Add("threads=$cpuWorkers") }
            $parts.Add('byte-stream=true')
            $parts.Add('aud=true')
        }
        'X265' {
            if ($rateControl -ne 'constqp') { $parts.Add("bitrate=$videoBitrateKbps") }
            $parts.Add('speed-preset=ultrafast')
            if ($tune -in @('low-latency','ultra-low-latency')) { $parts.Add('tune=zerolatency') }
            $parts.Add("key-int-max=$gopSize")
            $x265Options = New-Object System.Collections.Generic.List[string]
            $x265Options.Add("bframes=$bFrames")
            $x265Options.Add("rc-lookahead=$lookAheadFrames")
            if ($cpuWorkers -gt 0) { $x265Options.Add("pools=$cpuWorkers") }
            if ($rateControl -eq 'constqp') { $x265Options.Add("qp=$constantQp") }
            if ($aqEnabled) {
                $x265Options.Add('aq-mode=2')
                $x265Options.Add("aq-strength=$aqStrengthFloat")
            }
            else {
                $x265Options.Add('aq-mode=0')
            }
            $parts.Add("option-string=$($x265Options -join ':')")
        }
        'OPENH264' {
            $parts.Add("bitrate=$videoBitrateBps")
            $parts.Add('rate-control=bitrate')
            $parts.Add('complexity=low')
            $parts.Add('usage-type=screen')
            $parts.Add("gop-size=$gopSize")
            $parts.Add('enable-frame-skip=true')
        }
        'AOM' {
            $parts.Add("target-bitrate=$videoBitrateKbps")
            $parts.Add('end-usage=cbr')
            $parts.Add('cpu-used=8')
            $parts.Add("lag-in-frames=$lookAheadFrames")
            $parts.Add("keyframe-max-dist=$gopSize")
            $parts.Add('row-mt=true')
        }
        'SVTAV1' {
            $parts.Add("target-bitrate=$videoBitrateKbps")
            $parts.Add('preset=12')
            $parts.Add("intra-period-length=$gopSize")
            $parts.Add('intra-refresh-type=IDR')
            $parts.Add('maximum-buffer-size=100')
        }
        'RAV1E' {
            $parts.Add("bitrate=$videoBitrateBps")
            $parts.Add("low-latency=$(($lookAheadFrames -eq 0).ToString().ToLowerInvariant())")
            $parts.Add('speed-preset=10')
            $parts.Add("max-key-frame-interval=$gopSize")
            $parts.Add('min-key-frame-interval=1')
            $parts.Add("rdo-lookahead-frames=$lookAheadFrames")
        }
        'VPX' {
            $parts.Add("target-bitrate=$videoBitrateBps")
            $parts.Add('deadline=1')
            $parts.Add('end-usage=cbr')
            $parts.Add("keyframe-max-dist=$gopSize")
            $parts.Add("lag-in-frames=$lookAheadFrames")
        }
        default {
            throw "Unsupported encoder family: $family"
        }
    }

    Add-CustomEncoderOptions $parts $txtCustomEncoderOptions.Text

    # Direct GST WebRTC AV1 guard:
    # GStreamer 1.28.5 av1parse emits an initial parsed AV1 caps event and then
    # immediately enriches it with chroma/bit-depth/level. rswebrtc/webrtcsink
    # treats that second caps event as unsupported renegotiation on out.video_0.
    # For Direct GST WebRTC only, feed AV1 encoder output through the minimal AV1
    # capsfilter without av1parse so the sink sees one stable caps shape. Keep
    # parsers for H.264/H.265 and non-WebRTC protocols where they are needed.
    $skipParserForDirectWebRtcAv1 = ($codec -eq 'AV1' -and $Protocol -eq 'GST WebRTC')

    if ((-not $skipParserForDirectWebRtcAv1) -and (-not [string]::IsNullOrWhiteSpace($parser))) {
        $parts.Add('!')
        $parts.Add($parser)

        if ($codec -in @('H264', 'H265')) {
            $parts.Add('config-interval=-1')
        }
    }

    $parts.Add('!')
    $parts.Add("`"$(Get-EncodedVideoCaps -Codec $codec -Protocol $Protocol)`"")

    return ($parts -join ' ')
}

function Update-EncoderUi {
    $definition = Get-SelectedEncoderDefinition
    $codec = [string]$definition.Codec
    $family = [string]$definition.Family
    $kind = [string]$definition.Kind
    $inputType = [string]$definition.Input
    $protocol = [string]$cmbProtocol.SelectedItem

    $isNvenc = ($family -eq 'NVENC')
    $cmbPreset.Enabled = $isNvenc
    $cmbEncoderTune.Enabled = $isNvenc
    $cmbMultipass.Enabled = $isNvenc
    $numVbvBuffer.Enabled = $isNvenc
    $cmbProfile.Enabled = ($codec -eq 'H264')

    $controlSupport = Get-EncoderControlSupport
    $numBFrames.Enabled = $controlSupport.BFrames
    $chkLookAhead.Enabled = $controlSupport.LookAhead
    $numLookAheadFrames.Enabled =
        $controlSupport.LookAhead -and $chkLookAhead.Checked
    $chkAdaptiveQuantization.Enabled =
        $controlSupport.AdaptiveQuantization
    $chkTemporalAq.Enabled = $controlSupport.AdaptiveQuantization
    $numAqStrength.Enabled =
        $controlSupport.AdaptiveQuantization -and
        ($chkAdaptiveQuantization.Checked -or $chkTemporalAq.Checked)

    $memoryLabel = if ($inputType -eq 'D3D11') { 'D3D11 zero-copy path' } else { 'CPU/system-memory path' }
    $latencyFlags = New-Object System.Collections.Generic.List[string]
    $latencyFlags.Add((Get-ComboSelectedOrDefault $cmbRateControl 'cbr'))
    if ($numBFrames.Enabled -and [int]$numBFrames.Value -gt 0) {
        $latencyFlags.Add("B=$([int]$numBFrames.Value)")
    }
    if ($chkLookAhead.Enabled -and $chkLookAhead.Checked) {
        $latencyFlags.Add("LA=$([int]$numLookAheadFrames.Value)")
    }
    if ($chkAdaptiveQuantization.Enabled -and ($chkAdaptiveQuantization.Checked -or $chkTemporalAq.Checked)) {
        $aqModeText = if ($chkAdaptiveQuantization.Checked -and $chkTemporalAq.Checked) { 'AQ=S/T' } elseif ($chkAdaptiveQuantization.Checked) { 'AQ=S' } else { 'AQ=T' }
        $latencyFlags.Add($aqModeText)
    }

    $flagText = if ($latencyFlags.Count -gt 0) {
        ' * ' + ($latencyFlags -join ', ')
    }
    else {
        ''
    }
    $lblEncoderStatus.Text = "$codec * $kind * $memoryLabel$flagText"

    if ($protocol) {
        $compatible = Test-CodecProtocolCompatibility -Codec $codec -Protocol $protocol
        $lblEncoderStatus.ForeColor = if ($compatible) {
            [System.Drawing.Color]::DimGray
        }
        else {
            [System.Drawing.Color]::DarkRed
        }
    }

    Update-UnifiedBridgeKeyframeUi
    Update-CommandPreview
}

function Get-EffectiveCaptureSettings {
    param([switch]$LocalOnly)

    $width = [int]$numWidth.Value
    $height = [int]$numHeight.Value
    $fps = [int]$numFps.Value

    # The source capture FPS is the only FPS d3d11convert can preserve. It can scale/format,
    # but it does not manufacture a new frame cadence. For recording-only local pipelines,
    # make the recording settings the capture settings so 120 FPS recording does not try to
    # link a 60 FPS raw tee into a 120 FPS encoder caps filter.
    if ($LocalOnly -and (Test-RecordingEnabled)) {
        $width = [int]$numRecordingWidth.Value
        $height = [int]$numRecordingHeight.Value
        $fps = [int]$numRecordingFps.Value
    }

    return [pscustomobject]@{
        Width  = [Math]::Max(1, $width)
        Height = [Math]::Max(1, $height)
        Fps    = [Math]::Max(1, $fps)
    }
}

function Test-RecordingFrameRateCompatible {
    if (-not (Test-RecordingEnabled)) { return $true }
    if (-not (Test-TransportEnabled)) { return $true }

    # With transport enabled, capture is driven by the Video tab FPS. The recording branch
    # currently stays on the zero-copy D3D11 path, where d3d11convert cannot change FPS.
    # Allow independent recording bitrate/size/encoder, but require matching FPS unless
    # we later add a dedicated videorate download/upload path.
    return ([int]$numRecordingFps.Value -eq [int]$numFps.Value)
}

function Assert-RecordingFrameRateCompatible {
    if (Test-RecordingFrameRateCompatible) { return }

    throw ("Recording FPS must match Video FPS while transport is enabled. " +
        "Set Video FPS to $([int]$numRecordingFps.Value), set Recording FPS to $([int]$numFps.Value), " +
        "or disable transport for recording-only capture. The D3D11 branch cannot convert frame rate with d3d11convert.")
}

function Build-DesktopCaptureChain {
    param([switch]$LocalOnly)

    $captureSettings = Get-EffectiveCaptureSettings -LocalOnly:$LocalOnly
    $monitor = [int]$numMonitor.Value
    $cursor = if ($chkCursor.Checked) { 'true' } else { 'false' }
    $gdiCursor = if ($chkCursor.Checked) { 'true' } else { 'false' }
    $width = [int]$captureSettings.Width
    $height = [int]$captureSettings.Height
    $fps = [int]$captureSettings.Fps
    $method = Get-SelectedCaptureMethod
    $gdiMonitor = if ($monitor -lt 0) { 0 } else { $monitor }
    $d3d11Source = Add-VideoSourceTimestampOption 'd3d11screencapturesrc'
    $gdiSource = Add-VideoSourceTimestampOption 'gdiscreencapsrc'

    switch ([string]$method.Method) {
        'FullscreenAppD3D11Wgc' {
            $windowHandle = if ($script:CaptureWindowHwnd -ne [IntPtr]::Zero) { [uint64]$script:CaptureWindowHwnd.ToInt64() } else { [uint64]0 }
            return @($d3d11Source,'capture-api=wgc',"window-handle=$windowHandle",'window-capture-mode=default','show-border=false',"show-cursor=$cursor",'!',"`"video/x-raw(memory:D3D11Memory),framerate=$fps/1`"",'!','d3d11convert','!',"`"video/x-raw(memory:D3D11Memory),format=NV12,width=$width,height=$height,framerate=$fps/1`"") -join ' '
        }
        'MonitorD3D11Wgc' {
            return @($d3d11Source,'capture-api=wgc',"monitor-index=$monitor", "show-cursor=$cursor",'!',"`"video/x-raw(memory:D3D11Memory),framerate=$fps/1`"",'!','d3d11convert','!',"`"video/x-raw(memory:D3D11Memory),format=NV12,width=$width,height=$height,framerate=$fps/1`"") -join ' '
        }
        'MonitorGdi' {
            return @($gdiSource,"monitor=$gdiMonitor", "cursor=$gdiCursor",'!',"`"video/x-raw,framerate=$fps/1`"",'!','videoconvert','!','videoscale','!',"`"video/x-raw,format=BGRA,width=$width,height=$height,framerate=$fps/1`"",'!','d3d11upload','!','d3d11convert','!',"`"video/x-raw(memory:D3D11Memory),format=NV12,width=$width,height=$height,framerate=$fps/1`"") -join ' '
        }
        default {
            return @($d3d11Source,'capture-api=dxgi',"monitor-index=$monitor", "show-cursor=$cursor",'!',"`"video/x-raw(memory:D3D11Memory),framerate=$fps/1`"",'!','d3d11convert','!',"`"video/x-raw(memory:D3D11Memory),format=NV12,width=$width,height=$height,framerate=$fps/1`"") -join ' '
        }
    }
}

function Build-SceneCaptureChain {
    param([switch]$LocalOnly)

    $captureSettings = Get-EffectiveCaptureSettings -LocalOnly:$LocalOnly
    $canvasWidth = [int]$captureSettings.Width
    $canvasHeight = [int]$captureSettings.Height
    $canvasFps = [int]$captureSettings.Fps
    $cameraWidth = [int]$numWebcamWidth.Value
    $cameraHeight = [int]$numWebcamHeight.Value
    $cameraX = [int]$numWebcamX.Value
    $cameraY = [int]$numWebcamY.Value
    $cameraFps = [int]$numWebcamFps.Value
    $cameraIndex = Get-SelectedWebcamIndex
    $alpha = ([double]$numWebcamOpacity.Value / 100.0).ToString('0.00', [Globalization.CultureInfo]::InvariantCulture)
    $sizingPolicy = if ($chkWebcamAspectLock.Checked) { 'keep-aspect-ratio' } else { 'none' }
    $mirror = if ($chkWebcamMirror.Checked) { ' ! videoflip method=horizontal-flip' } else { '' }
    $webcamSource = Add-VideoSourceTimestampOption "mfvideosrc device-index=$cameraIndex"
    $preset = [string]$cmbScenePreset.SelectedItem
    $cpuWorkers = Get-CpuWorkerLimit
    $cpuConvert = if ($cpuWorkers -gt 0) { "videoconvert n-threads=$cpuWorkers" } else { 'videoconvert' }
    $cpuCompositorWorkers = if ($cpuWorkers -gt 0) { " max-threads=$cpuWorkers" } else { '' }
    # A compositor combines independent live inputs. Each input keeps its own
    # queue boundary because removing the queues can produce GstAggregator
    # "max latency < min latency" failures. Depth and time cap are now explicit
    # Scene-tab settings; 0 ms is emitted literally and has no hidden fallback.
    $sceneInputBoundary = ' ! ' + (New-LiveQueueString -Buffers ([int]$numSceneInputQueueBuffers.Value) -MaxTimeMs ([int]$numSceneInputQueueCapMs.Value) -Leak 'downstream')

    if ($preset -eq 'Desktop only') { return (Build-DesktopCaptureChain -LocalOnly:$LocalOnly) }

    if ($preset -eq 'Webcam only') {
        return "$webcamSource ! video/x-raw,framerate=$cameraFps/1 ! $cpuConvert$mirror ! videoscale ! video/x-raw,format=BGRA,width=$canvasWidth,height=$canvasHeight ! videorate ! video/x-raw,format=BGRA,width=$canvasWidth,height=$canvasHeight,framerate=$canvasFps/1 ! d3d11upload ! d3d11convert ! `"video/x-raw(memory:D3D11Memory),format=NV12,width=$canvasWidth,height=$canvasHeight,framerate=$canvasFps/1`""
    }

    $desktop = Build-DesktopCaptureChain -LocalOnly:$LocalOnly
    if ([string]$cmbSceneCompositor.SelectedItem -eq 'CPU compatibility') {
        return "$desktop ! d3d11download ! $cpuConvert$sceneInputBoundary ! scene.sink_0 $webcamSource ! video/x-raw,framerate=$cameraFps/1 ! $cpuConvert$mirror ! videoscale ! video/x-raw,format=BGRA,width=$cameraWidth,height=$cameraHeight$sceneInputBoundary ! scene.sink_1 compositor name=scene background=black$cpuCompositorWorkers sink_0::xpos=0 sink_0::ypos=0 sink_0::width=$canvasWidth sink_0::height=$canvasHeight sink_0::zorder=0 sink_1::xpos=$cameraX sink_1::ypos=$cameraY sink_1::width=$cameraWidth sink_1::height=$cameraHeight sink_1::alpha=$alpha sink_1::zorder=1 sink_1::sizing-policy=$sizingPolicy ! $cpuConvert ! video/x-raw,format=BGRA,width=$canvasWidth,height=$canvasHeight,framerate=$canvasFps/1 ! d3d11upload ! d3d11convert ! `"video/x-raw(memory:D3D11Memory),format=NV12,width=$canvasWidth,height=$canvasHeight,framerate=$canvasFps/1`""
    }

    return "$desktop$sceneInputBoundary ! scene.sink_0 $webcamSource ! video/x-raw,framerate=$cameraFps/1 ! $cpuConvert$mirror ! videoscale ! video/x-raw,format=BGRA,width=$cameraWidth,height=$cameraHeight ! d3d11upload ! d3d11convert ! `"video/x-raw(memory:D3D11Memory),format=BGRA,width=$cameraWidth,height=$cameraHeight`"$sceneInputBoundary ! scene.sink_1 d3d11compositor name=scene background=black ignore-inactive-pads=true sink_0::xpos=0 sink_0::ypos=0 sink_0::width=$canvasWidth sink_0::height=$canvasHeight sink_0::zorder=0 sink_1::xpos=$cameraX sink_1::ypos=$cameraY sink_1::width=$cameraWidth sink_1::height=$cameraHeight sink_1::alpha=$alpha sink_1::zorder=1 sink_1::sizing-policy=$sizingPolicy ! d3d11convert ! `"video/x-raw(memory:D3D11Memory),format=NV12,width=$canvasWidth,height=$canvasHeight,framerate=$canvasFps/1`""
}

function Build-CaptureChain {
    param([switch]$LocalOnly)
    if ($chkSceneEnabled -and $chkSceneEnabled.Checked) {
        return (Build-SceneCaptureChain -LocalOnly:$LocalOnly)
    }
    return (Build-DesktopCaptureChain -LocalOnly:$LocalOnly)
}

function Test-PreviewEnabledForCurrentPipeline {
    if (-not $chkPreview.Checked) { return $false }
    if ($script:ForceLocalPreviewMode) { return $true }
    if ($script:ForceLiveScenePreviewBranch) { return $true }
    if ((Test-TransportEnabled) -and $chkHidePreviewDuringStream -and $chkHidePreviewDuringStream.Checked) { return $false }
    return $true
}

function Test-PreviewVisibleNow {
    if (-not $chkPreview.Checked) { return $false }
    if ($script:PreviewOnlyMode) { return $true }
    if ($script:ControlledLiveStreamActive) {
        if ($script:SceneWorkspaceActive) { return $true }
        if ((Test-TransportEnabled) -and $chkHidePreviewDuringStream -and $chkHidePreviewDuringStream.Checked) { return $false }
        return $true
    }
    if (($script:GstProcess -and -not $script:GstProcess.HasExited) -and (Test-TransportEnabled) -and $chkHidePreviewDuringStream -and $chkHidePreviewDuringStream.Checked) { return $false }
    return $true
}

function Build-VideoBranch {
    param([Parameter(Mandatory)][string]$Protocol)

    Assert-RecordingFrameRateCompatible
    $capture = Build-CaptureChain
    $encoder = Get-EncoderElementChain -Protocol $Protocol
    $hasPreview = Test-PreviewEnabledForCurrentPipeline
    $hasRecording = Test-RecordingEnabled

    if ($hasPreview -or $hasRecording) {
        $parts = New-Object System.Collections.Generic.List[string]
        $parts.Add($capture)
        $parts.Add('!')
        $parts.Add('tee')
        $parts.Add('name=rawtee')

        if ($hasRecording) {
            $recordingBranch = Build-RecordingMuxPrefixAndVideoBranch
            if (-not [string]::IsNullOrWhiteSpace($recordingBranch)) { $parts.Add($recordingBranch) }
        }

        if ($hasPreview) {
            $parts.Add((@('rawtee.','!','queue','max-size-buffers=1','max-size-bytes=0','max-size-time=0','leaky=downstream','!','d3d11videosink','name=localpreview',(Get-VideoPreviewSinkSyncOption),'force-aspect-ratio=true') -join ' '))
        }

        $parts.Add("rawtee. ! $encoder")
        return ($parts -join ' ')
    }

    return "$capture ! $encoder"
}

function Build-LocalOnlyVideoPipeline {
    $capture = Build-CaptureChain -LocalOnly
    $hasPreview = Test-PreviewEnabledForCurrentPipeline
    $hasRecording = Test-RecordingEnabled

    if (-not $hasPreview -and -not $hasRecording) {
        throw 'Enable transport, recording, or preview before starting.'
    }

    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add($capture)
    $parts.Add('!')
    $parts.Add('tee')
    $parts.Add('name=rawtee')

    if ($hasRecording) {
        $recordingBranch = Build-RecordingMuxPrefixAndVideoBranch
        if (-not [string]::IsNullOrWhiteSpace($recordingBranch)) { $parts.Add($recordingBranch) }
    }

    if ($hasPreview) {
        $parts.Add((@('rawtee.','!','queue','max-size-buffers=1','max-size-bytes=0','max-size-time=0','leaky=downstream','!','d3d11videosink','name=localpreview',(Get-VideoPreviewSinkSyncOption),'force-aspect-ratio=true') -join ' '))
    }

    return ($parts -join ' ')
}

function Build-DirectWebRtcRawVideoBranch {
    # NOTE: currently unreachable. Build-DirectWebRtcEncodedVideoBranch is the only
    # path Build-GstArguments uses for Direct GST WebRTC (see its comment: the raw
    # D3D11 feed experiment could not find a usable encoder on this Windows
    # package). Kept for that experiment. The rawtee line below was single-quoted
    # and would have emitted a literal $(Get-CaptureEncoderQueue) into the
    # pipeline, so this function could never have parsed if it were called; fixed
    # so reviving the experiment does not start from a broken pipeline.
    # webrtcsink is a high-level WebRTC sender and works best when it owns the
    # per-consumer encoder/payloader. Feed raw D3D11 frames and use video-caps
    # to tell it which WebRTC codec to negotiate.
    Assert-RecordingFrameRateCompatible
    $capture = Build-CaptureChain
    $hasPreview = Test-PreviewEnabledForCurrentPipeline
    $hasRecording = Test-RecordingEnabled

    if ($hasPreview -or $hasRecording) {
        $parts = New-Object System.Collections.Generic.List[string]
        $parts.Add($capture)
        $parts.Add('!')
        $parts.Add('tee')
        $parts.Add('name=rawtee')

        if ($hasRecording) {
            $recordingBranch = Build-RecordingMuxPrefixAndVideoBranch
            if (-not [string]::IsNullOrWhiteSpace($recordingBranch)) { $parts.Add($recordingBranch) }
        }

        if ($hasPreview) {
            $parts.Add((@('rawtee.','!','queue','max-size-buffers=1','max-size-bytes=0','max-size-time=0','leaky=downstream','!','d3d11videosink','name=localpreview',(Get-VideoPreviewSinkSyncOption),'force-aspect-ratio=true') -join ' '))
        }

        $parts.Add("rawtee. ! $(Get-CaptureEncoderQueue) ! out.video_0")
        return ($parts -join ' ')
    }

    return "$capture ! $(Get-CaptureEncoderQueue) ! out.video_0"
}



function Set-WebRtcRecoveryMode {
    param([string]$Mode)
    if ([string]::IsNullOrWhiteSpace($Mode) -or -not $cmbWebRtcRecoveryMode.Items.Contains($Mode)) {
        $Mode = $script:DefaultWebRtcRecoveryMode
    }
    $cmbWebRtcRecoveryMode.SelectedItem = $Mode
    switch ($Mode) {
        'None' {
            $chkDirectWebRtcFec.Checked = $false
            $chkDirectWebRtcRetransmission.Checked = $false
        }
        'FEC only' {
            $chkDirectWebRtcFec.Checked = $true
            $chkDirectWebRtcRetransmission.Checked = $false
        }
        'FEC + RTX' {
            $chkDirectWebRtcFec.Checked = $true
            $chkDirectWebRtcRetransmission.Checked = $true
        }
        default {
            $chkDirectWebRtcFec.Checked = $false
            $chkDirectWebRtcRetransmission.Checked = $true
        }
    }
}

function Get-WebRtcRecoveryFlags {
    $mode = Get-ComboSelectedOrDefault $cmbWebRtcRecoveryMode $script:DefaultWebRtcRecoveryMode
    switch ($mode) {
        'None' { return [ordered]@{ Fec = 'false'; Retransmission = 'false'; Mode = 'None' } }
        'FEC only' { return [ordered]@{ Fec = 'true'; Retransmission = 'false'; Mode = 'FEC only' } }
        'FEC + RTX' { return [ordered]@{ Fec = 'true'; Retransmission = 'true'; Mode = 'FEC + RTX' } }
        default { return [ordered]@{ Fec = 'false'; Retransmission = 'true'; Mode = 'RTX only' } }
    }
}

function Apply-DirectWebRtcSmoothnessProfile {
    param([switch]$Force)

    if ($script:ApplyingDirectWebRtcSmoothnessProfile) { return }
    $script:ApplyingDirectWebRtcSmoothnessProfile = $true
    try {
        $profile = Get-ComboSelectedOrDefault $cmbDirectWebRtcSmoothnessProfile $script:DefaultDirectWebRtcSmoothnessProfile
        if ($profile -eq 'Custom' -and -not $Force) { return }

        switch ($profile) {
            'Sane defaults' {
                $cmbWebRtcSenderQueueMode.SelectedItem = 'Leaky live'
                $numDirectWebRtcPacingMs.Value = 0
                $numDirectWebRtcPlayerJitterMs.Value = $script:DefaultDirectWebRtcPlayerJitterMs
                $numDirectWebRtcVideoJitterMs.Value = $script:DefaultDirectWebRtcVideoJitterMs
                $cmbDirectWebRtcCongestion.SelectedItem = 'disabled'
                $cmbDirectWebRtcMitigation.SelectedItem = 'none'
                Set-WebRtcRecoveryMode 'None'
            }
            'Lowest latency' {
                $cmbWebRtcSenderQueueMode.SelectedItem = 'Leaky live'
                $numDirectWebRtcPacingMs.Value = 0
                $numDirectWebRtcPlayerJitterMs.Value = 0
                $numDirectWebRtcVideoJitterMs.Value = 0
                $cmbDirectWebRtcCongestion.SelectedItem = 'disabled'
                $cmbDirectWebRtcMitigation.SelectedItem = 'none'
                Set-WebRtcRecoveryMode 'None'
            }
            'Balanced smooth' {
                $cmbWebRtcSenderQueueMode.SelectedItem = 'Small cushion'
                $numDirectWebRtcPacingMs.Value = 40
                $numDirectWebRtcPlayerJitterMs.Value = 60
                $numDirectWebRtcVideoJitterMs.Value = 40
                $cmbDirectWebRtcCongestion.SelectedItem = 'gcc'
                $cmbDirectWebRtcMitigation.SelectedItem = 'none'
                Set-WebRtcRecoveryMode 'RTX only'
            }
            'WAN smooth' {
                $cmbWebRtcSenderQueueMode.SelectedItem = 'Small cushion'
                $numDirectWebRtcPacingMs.Value = 80
                $numDirectWebRtcPlayerJitterMs.Value = 100
                $numDirectWebRtcVideoJitterMs.Value = 80
                $cmbDirectWebRtcCongestion.SelectedItem = 'gcc'
                $cmbDirectWebRtcMitigation.SelectedItem = 'none'
                Set-WebRtcRecoveryMode 'RTX only'
            }
            'Adaptive viewer' {
                $cmbWebRtcSenderQueueMode.SelectedItem = 'Small cushion'
                $numDirectWebRtcPacingMs.Value = 60
                $numDirectWebRtcPlayerJitterMs.Value = 80
                $numDirectWebRtcVideoJitterMs.Value = 60
                $cmbDirectWebRtcCongestion.SelectedItem = 'gcc'
                $cmbDirectWebRtcMitigation.SelectedItem = 'none'
                Set-WebRtcRecoveryMode 'RTX only'
            }
        }
    }
    finally {
        $script:ApplyingDirectWebRtcSmoothnessProfile = $false
    }
}

function Get-DirectWebRtcPacingQueue {
    if ($chkBudgetSenderQueue -and -not $chkBudgetSenderQueue.Checked) { return 'identity' }
    $mode = Get-ComboSelectedOrDefault $cmbWebRtcSenderQueueMode $script:DefaultWebRtcSenderQueueMode
    # Structurally honest: the visible cap is the emitted cap. Zero means no
    # max-size-time limit in every mode; presets may set a nonzero value explicitly.
    $ms = [Math]::Max(0, [int]$numDirectWebRtcPacingMs.Value)
    $leak = Get-EffectiveLiveQueueLeakValue

    if ($mode -eq 'Leaky live') {
        # Leaky live means newest-frame-wins. Do not let a global stale 'No leak'
        # setting override this and create rubber-band latency.
        if ($leak -eq 'no') { $leak = 'downstream' }
        return (New-LiveQueueString -Buffers 2 -MaxTimeMs $ms -Leak $leak)
    }

    if ($mode -eq 'Small cushion') {
        return (New-LiveQueueString -Buffers 4 -MaxTimeMs $ms -Leak $leak)
    }

    return (New-LiveQueueString -Buffers 4 -MaxTimeMs $ms -Leak 'no')
}

function Write-DirectWebRtcWebClientConfig {
    param([switch]$Quiet)

    # Always resolve through the Player tab working-dir logic. Quiet callers still
    # need manual working-dir selections and versioned AppData sync to apply.
    $webDir = Get-DirectWebRtcWebDirectory
    if ([string]::IsNullOrWhiteSpace($webDir)) { return }

    try {
        $configPath = Join-Path $webDir 'gstglass-config.js'
        $smoothnessProfile = [string]$cmbDirectWebRtcSmoothnessProfile.SelectedItem
        $playerSettings = Get-PlayerSettingsFromUi
        $audioTarget = [int]$playerSettings.AudioJbufMs
        $videoTarget = [int]$playerSettings.VideoJbufMs
        $jbufMax = [int]$playerSettings.JbufMaxMs
        $watchdog = [string]$playerSettings.JbufWatchdogMode
        $statsOverlayEnabled = [bool]$playerSettings.StatsOverlay
        $jbufDebugEnabled = [bool]$playerSettings.JbufDebug
        $videoSignalingPort = [int]$numDirectWebRtcSignalingPort.Value

        $effectiveAvPipelineMode = if (Test-DirectWebRtcUnifiedPublisher) { 'Unified publisher - one producer' } else { [string](Get-DirectWebRtcAvPipelineMode) }
        $effectiveSharedSignaling = [bool](Test-DirectWebRtcSharedSignaling)
        $effectiveMediaStreamGrouping = if (Test-DirectWebRtcSeparateMediaStreams) { [string](Get-DirectWebRtcMediaStreamGrouping) } else { $script:DefaultDirectWebRtcMediaStreamGrouping }
        $videoMediaStreamId = [string](Get-DirectWebRtcMediaStreamId -Kind video)
        $audioMediaStreamId = [string](Get-DirectWebRtcMediaStreamId -Kind audio)

        $data = [ordered]@{
            version = $script:AppVersion
            source = 'gstglass-config.js'
            writtenUtc = [DateTime]::UtcNow.ToString('o')
            smoothnessProfile = $smoothnessProfile
            recoveryMode = [string]$cmbWebRtcRecoveryMode.SelectedItem
            senderQueueMode = [string]$cmbWebRtcSenderQueueMode.SelectedItem
            senderQueueCapMs = [int]$numDirectWebRtcPacingMs.Value
            pacingMs = [int]$numDirectWebRtcPacingMs.Value
            playerJitterMs = $audioTarget
            browserJitterTargetMs = $audioTarget
            browserJitterHintMs = $audioTarget
            jitterBufferTargetMs = $audioTarget
            jbufTargetMs = $audioTarget
            audioJbufMs = $audioTarget
            videoJbufMs = $videoTarget
            directWebRtcOpusMode = [string]$cmbDirectWebRtcOpusMode.SelectedItem
            directWebRtcOpusFrameMs = [string]$cmbDirectWebRtcOpusFrameMs.SelectedItem
            directWebRtcOpusAudioType = [string]$cmbDirectWebRtcOpusAudioType.SelectedItem
            directWebRtcOpusInbandFec = [bool]$chkDirectWebRtcOpusFec.Checked
            directWebRtcOpusDtx = [bool]$chkDirectWebRtcOpusDtx.Checked
            jbufWatchdogMode = $watchdog
            jbufWatchdog = $watchdog
            jbufMaxMs = $jbufMax
            jbufTrendWindowSec = 3
            jbufDebug = $jbufDebugEnabled
            adaptiveJitter = ($smoothnessProfile -eq 'Adaptive viewer')
            adaptiveJitterMinMs = [int]([Math]::Min($audioTarget, $videoTarget))
            adaptiveJitterMaxMs = [int]([Math]::Max([Math]::Max($audioTarget, $videoTarget), 500))
            keepAliveSeconds = 15
            statsOverlay = $statsOverlayEnabled
            liveEdgeGreenMs = [int]$playerSettings.LiveEdgeGreenMs
            liveEdgeYellowMs = [int]$playerSettings.LiveEdgeYellowMs
            liveEdgeAverageSec = [int]$playerSettings.LiveEdgeAverageSec
            screenWakeLock = $true
            connectionMode = 'auto'
            playerSeparateHtmlMediaElements = [bool]$playerSettings.SeparateHtmlMediaElements
            separateHtmlMediaElements = [bool]$playerSettings.SeparateHtmlMediaElements
            playerAvRenderMode = [string]$playerSettings.AvRenderMode
            avRenderMode = [string]$playerSettings.AvRenderMode
            avPipelineMode = $effectiveAvPipelineMode
            directWebRtcAvPipelineMode = $effectiveAvPipelineMode
            mediaStreamGrouping = $effectiveMediaStreamGrouping
            avMediaStreamGrouping = $effectiveMediaStreamGrouping
            separateMediaStreams = [bool](Test-DirectWebRtcSeparateMediaStreams)
            videoMediaStreamId = $videoMediaStreamId
            audioMediaStreamId = $audioMediaStreamId
            videoMsid = $videoMediaStreamId
            audioMsid = $audioMediaStreamId
            unifiedPublisher = [bool](Test-DirectWebRtcUnifiedPublisher)
            transportClockSignaling = [string](Get-TimingMode)
            splitClockSignalingOverrides = [bool](Test-SplitClockSignalingOverridesActive)
            splitVideoClockSignaling = if (Test-WebRtcClockSignalingForSink -SinkRole Video) { 'RFC7273 NTP/PTP signaling' } else { 'Off / plugin default' }
            splitAudioClockSignaling = if (Test-WebRtcClockSignalingForSink -SinkRole Audio) { 'RFC7273 NTP/PTP signaling' } else { 'Off / plugin default' }
            controlDataChannel = [bool]$chkDirectWebRtcControlDataChannel.Checked
            bundlePolicy = if ((Get-ComboSelectedOrDefault $cmbDirectWebRtcBundlePolicy $script:DefaultDirectWebRtcBundlePolicy) -eq 'Max bundle') { 'max-bundle' } else { 'default' }
            internalRtpMtu = [int]$numDirectWebRtcInternalRtpMtu.Value
            internalRepeatHeaders = [bool]$chkDirectWebRtcInternalRepeatHeaders.Checked
            splitPlayerSyncMode = [string]$playerSettings.SplitPlayerSyncMode
            splitAudioWatchdogMode = [string]$playerSettings.SplitPlayerSyncMode
            splitAudioStallSeconds = [int]$playerSettings.SplitAudioStallSeconds
            splitAudioWarmupSeconds = [int]$playerSettings.SplitAudioWarmupSeconds
            splitAudioEqualizeSeconds = [int]$playerSettings.SplitAudioWarmupSeconds
            jbufWatchdogWarmupSeconds = [int]$playerSettings.JbufWatchdogWarmupSeconds
            watchdogWarmupSeconds = [int]$playerSettings.WatchdogWarmupSeconds
            splitAvOffsetWarnMs = [int]$playerSettings.SplitAvOffsetWarnMs
            splitAvOffsetBaselineMs = [int]$playerSettings.SplitAvOffsetBaselineMs
            splitAvBaselineMs = [int]$playerSettings.SplitAvOffsetBaselineMs
            splitAvBaselineLearnTicks = 5
            signalingPort = $videoSignalingPort
            videoSignalingPort = $videoSignalingPort
            splitAudioWsUrl = if ((Test-DirectWebRtcSplitAvPipelines) -and -not (Test-DirectWebRtcUnifiedPublisher)) { [string](Get-DirectWebRtcSplitAudioWsUrlForPlayer) } else { '' }
            splitAudioSignalingPort = if ((Test-DirectWebRtcSplitAvPipelines) -and -not (Test-DirectWebRtcUnifiedPublisher)) { [int](Get-DirectWebRtcSplitAudioSignalingPort) } else { 0 }
            sharedSignaling = $effectiveSharedSignaling
            splitSharedSignaling = $effectiveSharedSignaling
            videoProducerName = 'gstglass-video'
            splitAudioProducerName = 'gstglass-audio'
            webPath = [string]$playerSettings.WebPath
            bundledWebMode = [string]$playerSettings.BundledWebMode
            bundledWebDirectory = [string]$playerSettings.BundledWebDirectory
            workingWebMode = [string]$playerSettings.WorkingWebMode
            webDirectory = [string]$playerSettings.WebDirectory
            servedWebDirectory = [string]$webDir
            runtimeConfigPath = [string](Join-Path $webDir 'gstglass-config.js')
            timingMode = [string]$cmbTimingMode.SelectedItem
            videoPipelineClockMode = [string](Get-VideoPipelineClockMode)
            videoTimestampMode = [string](Get-VideoTimestampMode)
            splitAudioPipelineClockMode = [string](Get-SplitAudioPipelineClockMode)
            audioTransportMode = [string]$cmbAudioTransportMode.SelectedItem
            audioClockMode = [string]$cmbAudioClockMode.SelectedItem
            congestionControl = [string]$cmbDirectWebRtcCongestion.SelectedItem
            threadingProfile = [string]$cmbThreadingProfile.SelectedItem
            queueLeakMode = [string]$cmbQueueLeakMode.SelectedItem
        }
        $json = $data | ConvertTo-Json -Compress
        Set-Content -LiteralPath $configPath -Value "window.GST_GLASS_CONFIG = $json;" -Encoding UTF8
        Update-DirectWebRtcWebUiStatus
        if (-not $Quiet) {
            Append-Log "Direct WebRTC client config written from UI: audio/video target $audioTarget/$videoTarget ms, max $jbufMax ms, watchdog $watchdog, separateHtmlElements=$($playerSettings.SeparateHtmlMediaElements), MediaStream grouping=$effectiveMediaStreamGrouping (V=$videoMediaStreamId A=$audioMediaStreamId), statsOverlay=$statsOverlayEnabled, jbufDebug=$jbufDebugEnabled, served=$webDir."
        }
    }
    catch {
        Append-Log "Direct WebRTC client config could not be written: $($_.Exception.Message)"
    }
}

function Build-DirectWebRtcEncodedVideoBranch {
    # webrtcsink accepts encoded video/x-h264/h265/av1 on its video pad. The
    # raw-feed experiment could not discover a usable encoder for D3D11 frames
    # on this Windows package, so use our known-good explicit encoder branch and
    # let webrtcsink own signalling, SDP, RTP/WebRTC transport, and browser fanout.
    $encoded = Build-VideoBranch -Protocol $script:DirectWebRtcProtocolName
    $pacingQueue = Get-DirectWebRtcPacingQueue
    $videoSync = Get-VideoBranchSyncSuffix
    return "$encoded$videoSync ! $pacingQueue ! out.video_0"
}

function Get-DirectWebRtcWebServerPathSegment {
    # gst-plugin-webrtc's warp route expects an exact path segment without a
    # leading slash. The UI/viewer URL stays browser-friendly as /live, but the
    # GStreamer property must be live or warp panics: exact path segments should
    # not contain a slash.
    $path = Normalize-DirectWebRtcWebPath $txtDirectWebRtcWebPath.Text
    if ($path -eq '/') { return '' }
    return $path.Trim('/').Trim()
}



function Get-DirectWebRtcUnifiedRtpVideoDefinition {
    $definition = Get-SelectedEncoderDefinition
    $codec = [string]$definition.Codec

    switch ($codec) {
        'H264' {
            return [pscustomobject]@{
                Codec = 'H264'
                PayloadType = 96
                RtpCaps = 'application/x-rtp,media=(string)video,encoding-name=(string)H264,payload=(int)96,clock-rate=(int)90000'
                Payloader = 'rtph264pay pt=96 config-interval=-1 aggregate-mode=zero-latency'
                Receiver = 'rtph264depay ! h264parse config-interval=-1 ! "video/x-h264,stream-format=byte-stream,alignment=au"'
            }
        }
        'H265' {
            return [pscustomobject]@{
                Codec = 'H265'
                PayloadType = 96
                RtpCaps = 'application/x-rtp,media=(string)video,encoding-name=(string)H265,payload=(int)96,clock-rate=(int)90000'
                Payloader = 'rtph265pay pt=96 config-interval=-1 aggregate-mode=zero-latency'
                Receiver = 'rtph265depay ! h265parse config-interval=-1 ! "video/x-h265,stream-format=byte-stream,alignment=au"'
            }
        }
        default {
            throw "Unified A/V publisher bridge currently supports H264 and H265 only; selected codec is $codec."
        }
    }
}

function Build-DirectWebRtcUnifiedVideoBridgeArguments {
    if (-not (Test-DirectWebRtcUnifiedPublisher)) { return '' }

    $rtp = Get-DirectWebRtcUnifiedRtpVideoDefinition
    $videoPort = [int]$numDirectWebRtcBridgeVideoPort.Value
    $encodedVideo = Build-VideoBranch -Protocol $script:DirectWebRtcProtocolName
    $videoSyncSuffix = Get-VideoBranchSyncSuffix
    $bridgeQueue = Get-DirectWebRtcPacingQueue
    $pipeline = "$encodedVideo$videoSyncSuffix ! $bridgeQueue ! $($rtp.Payloader) ! udpsink host=127.0.0.1 port=$videoPort sync=false async=false"
    $pipeline = Wrap-GstPipelineWithClockSelect -Pipeline $pipeline -ClockMode (Get-VideoPipelineClockMode)

    $flags = '-e'
    if ($chkVerbose.Checked) { $flags += ' -v' }
    return "$flags $pipeline"
}

function Build-DirectWebRtcUnifiedAudioBridgeArguments {
    if (-not (Test-DirectWebRtcUnifiedPublisher)) { return '' }

    $audioTransportMode = Get-ComboSelectedOrDefault $cmbAudioTransportMode $script:DefaultAudioTransportMode
    if ($audioTransportMode -ne 'Normal audio' -or (-not ($chkDesktopAudio.Checked -or $chkMic.Checked))) { return '' }

    $audioRaw = Build-RawAudioChain
    if ([string]::IsNullOrWhiteSpace($audioRaw)) { return '' }

    $directOpusMode = Get-ComboSelectedOrDefault $cmbDirectWebRtcOpusMode $script:DefaultDirectWebRtcOpusMode
    if ($directOpusMode -eq 'Raw audio to webrtcsink') {
        throw 'Unified A/V publisher bridge requires Explicit Opus encoder mode so the split audio process can cross the RTP bridge as encoded Opus.'
    }

    $directOpusBitrate = [int]$numAudioBitrate.Value * 1000
    $directOpusFrameMs = Get-ComboSelectedOrDefault $cmbDirectWebRtcOpusFrameMs $script:DefaultDirectWebRtcOpusFrameMs
    $directOpusAudioType = Get-ComboSelectedOrDefault $cmbDirectWebRtcOpusAudioType $script:DefaultDirectWebRtcOpusAudioType
    $directOpusFec = if ($chkDirectWebRtcOpusFec.Checked) { 'true' } else { 'false' }
    $directOpusDtx = if ($chkDirectWebRtcOpusDtx.Checked) { 'true' } else { 'false' }
    $directOpus = "opusenc bitrate=$directOpusBitrate bitrate-type=cbr frame-size=$directOpusFrameMs audio-type=$directOpusAudioType inband-fec=$directOpusFec dtx=$directOpusDtx ! opusparse ! `"audio/x-opus`""
    $audioPort = [int]$numDirectWebRtcBridgeAudioPort.Value
    $audioSyncSuffix = Get-AudioBranchSyncSuffix
    $audioBridgeSync = if ($chkDirectWebRtcAudioBridgePacing.Checked) { 'true' } else { 'false' }
    $pipeline = "$audioRaw ! $directOpus ! $(Get-AudioFinalQueue)$audioSyncSuffix ! rtpopuspay pt=97 dtx=$directOpusDtx ! udpsink host=127.0.0.1 port=$audioPort sync=$audioBridgeSync async=false"
    $pipeline = Wrap-GstPipelineWithClockSelect -Pipeline $pipeline -ClockMode (Get-SplitAudioPipelineClockMode)

    $flags = '-e'
    if ($chkVerbose.Checked) { $flags += ' -v' }
    return "$flags $pipeline"
}

function Get-DirectWebRtcTurnOption {
    if (-not $chkDirectWebRtcTurnEnabled.Checked) { return '' }

    $turnServer = $txtDirectWebRtcTurn.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($turnServer)) { return '' }

    # webrtcsink and whipclientsink inherit GstBaseWebRTCSink.  That base
    # element exposes TURN as a GstValueArray named turn-servers, not the
    # singular webrtcbin convenience property turn-server.  Build a one-item
    # array value and let Quote-GstValue preserve the embedded URI quotes for
    # gst-launch on Windows: turn-servers=<"turn://user:pass@host:port">.
    $turnArray = '<"' + $turnServer.Replace('"', '\"') + '">' 
    return ' turn-servers=' + (Quote-GstValue $turnArray)
}

function Build-DirectWebRtcUnifiedPublisherArguments {
    if (-not (Test-DirectWebRtcUnifiedPublisher)) { return '' }

    $destination = $txtDestination.Text.Trim()
    $webAddress = Quote-GstValue (Normalize-DirectWebRtcWebAddress $destination)
    $webPathSegment = Get-DirectWebRtcWebServerPathSegment
    $webPathOption = if ([string]::IsNullOrWhiteSpace($webPathSegment)) { '' } else { ' web-server-path=' + (Quote-GstValue $webPathSegment) }
    $webDirectory = Get-DirectWebRtcWebDirectory
    $webDirectoryOption = if ([string]::IsNullOrWhiteSpace($webDirectory)) { '' } else { ' web-server-directory=' + (Quote-GstValue $webDirectory) }
    $signalHostText = $txtDirectWebRtcSignalingHost.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($signalHostText)) { $signalHostText = $script:DefaultDirectWebRtcSignalingHost }
    $signalHost = Quote-GstValue $signalHostText
    $signalPort = [int]$numDirectWebRtcSignalingPort.Value
    $stunServer = $txtDirectWebRtcStun.Text.Trim()
    $stunOption = if ([string]::IsNullOrWhiteSpace($stunServer)) { '' } else { ' stun-server=' + (Quote-GstValue $stunServer) }
    $turnOption = Get-DirectWebRtcTurnOption
    $timestampOption = Get-AbsoluteTimestampTransportOption -Protocol $script:DirectWebRtcProtocolName -SinkRole Global
    $timestampOption = if ([string]::IsNullOrWhiteSpace($timestampOption)) { '' } else { " $timestampOption" }
    $congestion = Get-ComboSelectedOrDefault $cmbDirectWebRtcCongestion 'gcc'
    $mitigation = Get-ComboSelectedOrDefault $cmbDirectWebRtcMitigation 'none'
    $recoveryFlags = Get-WebRtcRecoveryFlags
    $fec = [string]$recoveryFlags.Fec
    $retx = [string]$recoveryFlags.Retransmission
    $startBitrate = [Math]::Max(1000, ([int]$numVideoBitrate.Value * 1000))
    $maxKbps = [int]$numMaxVideoBitrate.Value
    $maxBitrate = if ($maxKbps -gt 0) { [Math]::Max($startBitrate, $maxKbps * 1000) } else { $startBitrate }
    $smoothProfile = Get-ComboSelectedOrDefault $cmbDirectWebRtcSmoothnessProfile $script:DefaultDirectWebRtcSmoothnessProfile
    $minBitrate = switch ($smoothProfile) {
        'Lowest latency' { [Math]::Max(1000, [int]($startBitrate / 2)) }
        'Balanced smooth' { [Math]::Max(1000, [int]($startBitrate * 0.75)) }
        'WAN smooth' { [Math]::Max(1000, [int]($startBitrate * 0.60)) }
        default { [Math]::Min(1000000, [Math]::Max(1000, [int]($startBitrate / 4))) }
    }

    $videoRtp = Get-DirectWebRtcUnifiedRtpVideoDefinition
    $mediaType = Get-CodecMediaType -Codec ([string]$videoRtp.Codec)
    $videoPort = [int]$numDirectWebRtcBridgeVideoPort.Value
    $audioPort = [int]$numDirectWebRtcBridgeAudioPort.Value
    $jitterMs = [int]$numDirectWebRtcBridgeJitterMs.Value
    $publisherQueueMs = [int]$numDirectWebRtcPublisherQueueMs.Value
    $videoCaps = Quote-GstValue ([string]$videoRtp.RtpCaps)
    $audioCaps = Quote-GstValue 'application/x-rtp,media=(string)audio,encoding-name=(string)OPUS,payload=(int)97,clock-rate=(int)48000,encoding-params=(string)2'

    $sinkProps = @(
        'webrtcsink',
        'name=out',
        "video-caps=`"$mediaType`"",
        'audio-caps="audio/x-opus"',
        'run-signalling-server=true',
        'run-web-server=true',
        "signalling-server-host=$signalHost",
        "signalling-server-port=$signalPort",
        "web-server-host-addr=$webAddress",
        "congestion-control=$congestion",
        "do-fec=$fec",
        "do-retransmission=$retx",
        "enable-mitigation-modes=$mitigation",
        "min-bitrate=$minBitrate",
        "start-bitrate=$startBitrate",
        "max-bitrate=$maxBitrate",
        'meta="meta,name=gstglass-av"'
    )
    if ($chkDirectWebRtcControlDataChannel.Checked) { $sinkProps += 'enable-control-data-channel=true' }

    # Preserve RTP-derived cadence across the process boundary.  The f10 graph
    # forced udpsrc arrival timestamps and then fed webrtcsink with no buffering,
    # which converted Windows scheduling bursts into choppy audio and triggered
    # the internal appsink 20 ms processing-deadline warnings.
    $bridgeJitter = if ($jitterMs -gt 0) { "rtpjitterbuffer latency=$jitterMs drop-on-latency=false do-lost=true ! " } else { '' }
    $publisherQueueNs = [int64]$publisherQueueMs * 1000000
    $publisherQueue = if ($publisherQueueMs -gt 0) { "queue max-size-buffers=0 max-size-bytes=0 max-size-time=$publisherQueueNs leaky=no ! " } else { '' }
    $videoInput = "udpsrc port=$videoPort caps=$videoCaps ! $bridgeJitter$($videoRtp.Receiver) ! $publisherQueue" + 'out.video_0'
    $audioInput = "udpsrc port=$audioPort caps=$audioCaps ! $bridgeJitter" + 'rtpopusdepay ! opusparse ! "audio/x-opus" ! ' + $publisherQueue + 'out.audio_0'
    $pipeline = (($sinkProps -join ' ') + $timestampOption + $stunOption + $turnOption + $webPathOption + $webDirectoryOption + " $videoInput $audioInput")
    $pipeline = Wrap-GstPipelineWithClockSelect -Pipeline $pipeline -ClockMode (Get-VideoPipelineClockMode)

    $flags = '-e'
    if ($chkVerbose.Checked) { $flags += ' -v' }
    return "$flags $pipeline"
}

function Build-DirectWebRtcAudioOnlyArguments {
    if (Test-DirectWebRtcUnifiedPublisher) { return (Build-DirectWebRtcUnifiedAudioBridgeArguments) }

    $audioTransportMode = Get-ComboSelectedOrDefault $cmbAudioTransportMode $script:DefaultAudioTransportMode
    if ($audioTransportMode -ne 'Normal audio' -or (-not ($chkDesktopAudio.Checked -or $chkMic.Checked))) {
        return ''
    }

    $audioRaw = Build-RawAudioChain
    if ([string]::IsNullOrWhiteSpace($audioRaw)) { return '' }

    $signalHostText = $txtDirectWebRtcSignalingHost.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($signalHostText)) { $signalHostText = $script:DefaultDirectWebRtcSignalingHost }
    $signalHost = Quote-GstValue $signalHostText
    $signalPort = Get-DirectWebRtcSplitAudioSignalingPort
    $sharedSignaling = Test-DirectWebRtcSharedSignaling
    $stunServer = $txtDirectWebRtcStun.Text.Trim()
    $stunOption = if ([string]::IsNullOrWhiteSpace($stunServer)) { '' } else { ' stun-server=' + (Quote-GstValue $stunServer) }
    $turnOption = Get-DirectWebRtcTurnOption
    $timestampOption = Get-AbsoluteTimestampTransportOption -Protocol $script:DirectWebRtcProtocolName -SinkRole Audio
    $timestampOption = if ([string]::IsNullOrWhiteSpace($timestampOption)) { '' } else { " $timestampOption" }
    $congestion = Get-ComboSelectedOrDefault $cmbDirectWebRtcCongestion 'gcc'
    $mitigation = Get-ComboSelectedOrDefault $cmbDirectWebRtcMitigation 'none'
    $recoveryFlags = Get-WebRtcRecoveryFlags
    $fec = [string]$recoveryFlags.Fec
    $retx = [string]$recoveryFlags.Retransmission
    $startBitrate = [Math]::Max(1000, ([int]$numAudioBitrate.Value * 1000))
    $maxBitrate = $startBitrate
    $minBitrate = [Math]::Max(1000, [int]($startBitrate / 2))

    $sinkProps = @(
        'webrtcsink',
        'name=aout',
        'audio-caps="audio/x-opus"'
    )
    if ($sharedSignaling) {
        $sharedUri = Quote-GstValue (Get-DirectWebRtcSharedSignallerUri)
        $sinkProps += "signaller::uri=$sharedUri"
        $sinkProps += 'meta="meta,name=gstglass-audio,kind=audio"'
    }
    else {
        $sinkProps += 'run-signalling-server=true'
        $sinkProps += 'run-web-server=false'
        $sinkProps += "signalling-server-host=$signalHost"
        $sinkProps += "signalling-server-port=$signalPort"
    }
    $sinkProps += @(
        "congestion-control=$congestion",
        "do-fec=$fec",
        "do-retransmission=$retx",
        "enable-mitigation-modes=$mitigation",
        "min-bitrate=$minBitrate",
        "start-bitrate=$startBitrate",
        "max-bitrate=$maxBitrate"
    )

    $directOpusMode = Get-ComboSelectedOrDefault $cmbDirectWebRtcOpusMode $script:DefaultDirectWebRtcOpusMode
    $audioSyncSuffix = Get-AudioBranchSyncSuffix
    if ($directOpusMode -eq 'Raw audio to webrtcsink') {
        $audioBranch = "$audioRaw ! $(Get-AudioFinalQueue)$audioSyncSuffix ! aout.audio_0"
    }
    else {
        $directOpusBitrate = [int]$numAudioBitrate.Value * 1000
        $directOpusFrameMs = Get-ComboSelectedOrDefault $cmbDirectWebRtcOpusFrameMs $script:DefaultDirectWebRtcOpusFrameMs
        $directOpusAudioType = Get-ComboSelectedOrDefault $cmbDirectWebRtcOpusAudioType $script:DefaultDirectWebRtcOpusAudioType
        $directOpusFec = if ($chkDirectWebRtcOpusFec.Checked) { 'true' } else { 'false' }
        $directOpusDtx = if ($chkDirectWebRtcOpusDtx.Checked) { 'true' } else { 'false' }
        $directOpus = "opusenc bitrate=$directOpusBitrate bitrate-type=cbr frame-size=$directOpusFrameMs audio-type=$directOpusAudioType inband-fec=$directOpusFec dtx=$directOpusDtx ! opusparse ! `"audio/x-opus`""
        $audioBranch = "$audioRaw ! $directOpus ! $(Get-AudioFinalQueue)$audioSyncSuffix ! aout.audio_0"
    }

    $pipeline = "$(($sinkProps -join ' '))$timestampOption$stunOption$turnOption $audioBranch"
    $pipeline = Wrap-GstPipelineWithClockSelect -Pipeline $pipeline -ClockMode (Get-SplitAudioPipelineClockMode)

    $flags = '-e'
    if ($chkVerbose.Checked) { $flags += ' -v' }
    return "$flags $pipeline"
}

function Build-GstArguments {
    $protocol = [string]$cmbProtocol.SelectedItem
    $destination = $txtDestination.Text.Trim()
    $quotedDestination = Quote-GstValue $destination

    if ($protocol -eq $script:DirectWebRtcProtocolName -and (Test-DirectWebRtcUnifiedPublisher)) {
        return (Build-DirectWebRtcUnifiedPublisherArguments)
    }

    if (-not (Test-TransportEnabled)) {
        $pipeline = Build-LocalOnlyVideoPipeline

        if (Test-RecordingEnabled) {
            $recordingAudioBranch = Build-RecordingAudioBranch
            if (-not [string]::IsNullOrWhiteSpace($recordingAudioBranch)) {
                $pipeline += " $recordingAudioBranch"
            }
        }

        $flags = '-e'
        if ($chkVerbose.Checked) {
            $flags += ' -v'
        }

        $pipeline = Wrap-GstPipelineWithClockSelect -Pipeline $pipeline -ClockMode (Get-VideoPipelineClockMode)
        return "$flags $pipeline"
    }

    $definition = Get-SelectedEncoderDefinition
    $codec = [string]$definition.Codec
    $mediaType = Get-CodecMediaType -Codec $codec
    $audioTransportMode = Get-ComboSelectedOrDefault $cmbAudioTransportMode $script:DefaultAudioTransportMode
    $userAudioEnabled =
        $audioTransportMode -eq 'Normal audio' -and
        ($chkDesktopAudio.Checked -or $chkMic.Checked)

    $audioRaw = $null
    $usingWhipSilentClockAudio = $false

    $audioTimingMode = Get-AudioTimingMode

    switch ($audioTransportMode) {
        'Video only - no audio track' {
            $audioRaw = $null
        }
        'Muted audio clock only' {
            $audioRaw = Build-WhipSilentClockAudioChain
            $usingWhipSilentClockAudio = $true
        }
        default {
            if ($audioTimingMode -eq 'Synthetic silent audio') {
                $audioRaw = Build-SyntheticSilentAudioChain
                $usingWhipSilentClockAudio = $true
            }
            else {
                $audioRaw = Build-RawAudioChain
                if (
                    $protocol -in @('WHIP', 'GST WebRTC') -and
                    [string]::IsNullOrWhiteSpace($audioRaw)
                ) {
                    $audioRaw = Build-WhipSilentClockAudioChain
                    $usingWhipSilentClockAudio = $true
                }
            }
        }
    }

    $hasAudio = -not [string]::IsNullOrWhiteSpace($audioRaw)

    $audioCodecName = if ($usingWhipSilentClockAudio) {
        'Opus'
    }
    else {
        [string]$cmbAudioCodec.SelectedItem
    }

    $audioDefinition = if ($usingWhipSilentClockAudio) {
        $script:AudioCodecCatalog['Opus']
    }
    else {
        Get-SelectedAudioCodecDefinition
    }

    $audioMediaType = switch ([string]$audioDefinition.Codec) {
        'OPUS' { 'audio/x-opus' }
        'AAC'  { 'audio/mpeg' }
        'MP3'  { 'audio/mpeg' }
        'AC3'  { 'audio/x-ac3' }
        default {
            throw "Unsupported audio codec: $([string]$audioDefinition.Codec)"
        }
    }

    $audioEncoded = if ($usingWhipSilentClockAudio) {
        $silentBitrate = [int]$numAudioBitrate.Value * 1000
        "opusenc bitrate=$silentBitrate bitrate-type=cbr frame-size=10 audio-type=restricted-lowdelay ! `"audio/x-opus`""
    }
    elseif ($hasAudio) {
        Get-AudioEncoderChain -Protocol $protocol
    }
    else {
        ''
    }
    $video = if ($protocol -eq $script:DirectWebRtcProtocolName) { '' } else { Build-VideoBranch -Protocol $protocol }
    $videoSyncSuffix = if ($protocol -eq $script:DirectWebRtcProtocolName) { '' } else { Get-VideoBranchSyncSuffix }
    $audioSyncSuffix = Get-AudioBranchSyncSuffix

    if (-not (Test-CodecProtocolCompatibility -Codec $codec -Protocol $protocol)) {
        throw "$codec is not supported by the $protocol pipeline template."
    }

    if (
        $hasAudio -and
        -not (Test-AudioCodecProtocolCompatibility `
            -AudioCodecName $audioCodecName `
            -Protocol $protocol)
    ) {
        throw "$audioCodecName is not supported by the $protocol pipeline template."
    }

    switch ($protocol) {
        'WHIP' {
            $timestampOption = Get-AbsoluteTimestampTransportOption -Protocol $protocol
            $timestampOption = if ([string]::IsNullOrWhiteSpace($timestampOption)) { '' } else { " $timestampOption" }
            $recoveryFlags = Get-WebRtcRecoveryFlags
            $congestion = Get-ComboSelectedOrDefault $cmbDirectWebRtcCongestion 'gcc'
            $mitigation = Get-ComboSelectedOrDefault $cmbDirectWebRtcMitigation 'none'
            $stunServer = $txtDirectWebRtcStun.Text.Trim()
            $stunOption = if ([string]::IsNullOrWhiteSpace($stunServer)) { '' } else { ' stun-server=' + (Quote-GstValue $stunServer) }
    $turnOption = Get-DirectWebRtcTurnOption
            $startBitrate = [Math]::Max(1000, ([int]$numVideoBitrate.Value * 1000))
            $maxKbps = [int]$numMaxVideoBitrate.Value
            $maxBitrate = if ($maxKbps -gt 0) { [Math]::Max($startBitrate, $maxKbps * 1000) } else { $startBitrate }
            $webRtcSinkOptions = " do-fec=$([string]$recoveryFlags.Fec) do-retransmission=$([string]$recoveryFlags.Retransmission) congestion-control=$congestion enable-mitigation-modes=$mitigation start-bitrate=$startBitrate max-bitrate=$maxBitrate"
            $webRtcVideoQueue = Get-DirectWebRtcPacingQueue

            if ($hasAudio) {
                $pipeline = "whipclientsink name=out video-caps=`"$mediaType`" audio-caps=`"$audioMediaType`"$timestampOption$webRtcSinkOptions$stunOption$turnOption signaller::whip-endpoint=$quotedDestination $video$videoSyncSuffix ! $webRtcVideoQueue ! out.video_0 $audioRaw ! $audioEncoded ! $(Get-AudioFinalQueue)$audioSyncSuffix ! out.audio_0"
            }
            else {
                $pipeline = "$video$videoSyncSuffix ! $webRtcVideoQueue ! whipclientsink video-caps=`"$mediaType`"$timestampOption$webRtcSinkOptions$stunOption$turnOption signaller::whip-endpoint=$quotedDestination"
            }
        }

        'GST WebRTC' {
            $timestampOption = Get-AbsoluteTimestampTransportOption -Protocol $protocol -SinkRole Video
            $timestampOption = if ([string]::IsNullOrWhiteSpace($timestampOption)) { '' } else { " $timestampOption" }

            $webAddress = Quote-GstValue (Normalize-DirectWebRtcWebAddress $destination)
            $webPathSegment = Get-DirectWebRtcWebServerPathSegment
            $webPathOption = if ([string]::IsNullOrWhiteSpace($webPathSegment)) { '' } else { ' web-server-path=' + (Quote-GstValue $webPathSegment) }
            $webDirectory = Get-DirectWebRtcWebDirectory
            $webDirectoryOption = if ([string]::IsNullOrWhiteSpace($webDirectory)) { '' } else { ' web-server-directory=' + (Quote-GstValue $webDirectory) }
            $signalHost = $txtDirectWebRtcSignalingHost.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($signalHost)) {
                $signalHost = $script:DefaultDirectWebRtcSignalingHost
            }
            $signalHost = Quote-GstValue $signalHost
            $signalPort = [int]$numDirectWebRtcSignalingPort.Value
            $stunServer = $txtDirectWebRtcStun.Text.Trim()
            $stunOption = if ([string]::IsNullOrWhiteSpace($stunServer)) { '' } else { ' stun-server=' + (Quote-GstValue $stunServer) }
    $turnOption = Get-DirectWebRtcTurnOption
            $congestion = Get-ComboSelectedOrDefault $cmbDirectWebRtcCongestion 'gcc'
            $mitigation = Get-ComboSelectedOrDefault $cmbDirectWebRtcMitigation 'none'
            $recoveryFlags = Get-WebRtcRecoveryFlags
            $fec = [string]$recoveryFlags.Fec
            $retx = [string]$recoveryFlags.Retransmission
            $startBitrate = [Math]::Max(1000, ([int]$numVideoBitrate.Value * 1000))
            $maxKbps = [int]$numMaxVideoBitrate.Value
            $maxBitrate = if ($maxKbps -gt 0) { [Math]::Max($startBitrate, $maxKbps * 1000) } else { $startBitrate }
            $smoothProfile = Get-ComboSelectedOrDefault $cmbDirectWebRtcSmoothnessProfile $script:DefaultDirectWebRtcSmoothnessProfile
            $minBitrate = switch ($smoothProfile) {
                'Lowest latency' { [Math]::Max(1000, [int]($startBitrate / 2)) }
                'Balanced smooth' { [Math]::Max(1000, [int]($startBitrate * 0.75)) }
                'WAN smooth' { [Math]::Max(1000, [int]($startBitrate * 0.60)) }
                default { [Math]::Min(1000000, [Math]::Max(1000, [int]($startBitrate / 4))) }
            }

            # Feed our explicit encoded branch into webrtcsink. The raw D3D11
            # experiment could start the web/signalling server, but this package
            # failed stream discovery with "No codec present" for video_0. The
            # encoded path keeps our tested NVENC/QSV/software encoder controls
            # while still bypassing MediaMTX for WebRTC signalling/delivery.
            $directVideo = Build-DirectWebRtcEncodedVideoBranch

            $sinkProps = @(
                'webrtcsink',
                'name=out',
                "video-caps=`"$mediaType`"",
                "audio-caps=`"audio/x-opus`"",
                'run-signalling-server=true',
                'run-web-server=true',
                "signalling-server-host=$signalHost",
                "signalling-server-port=$signalPort",
                "web-server-host-addr=$webAddress",
                "congestion-control=$congestion",
                "do-fec=$fec",
                "do-retransmission=$retx",
                "enable-mitigation-modes=$mitigation",
                "min-bitrate=$minBitrate",
                "start-bitrate=$startBitrate",
                "max-bitrate=$maxBitrate"
            )
            if ((Test-DirectWebRtcSplitAvPipelines) -and (Test-DirectWebRtcSharedSignaling)) {
                $sinkProps += 'meta="meta,name=gstglass-video,kind=video"'
            }

            $pipeline = (($sinkProps -join ' ') + $timestampOption + $stunOption + $turnOption + $webPathOption + $webDirectoryOption + " $directVideo")
            if ($hasAudio -and (Test-DirectWebRtcSplitAvPipelines)) {
                # Split A/V diagnostic: keep this gst-launch instance video-only.
                # Start-GstStream launches a second audio-only webrtcsink. It either
                # owns the configured audio signalling port or joins the video server.
            }
            elseif ($hasAudio) {
                $directOpusMode = Get-ComboSelectedOrDefault $cmbDirectWebRtcOpusMode $script:DefaultDirectWebRtcOpusMode
                if ($directOpusMode -eq 'Raw audio to webrtcsink') {
                    # Diagnostic escape hatch: hand raw S16LE to webrtcsink and let
                    # its internal child encoder do whatever this GStreamer build defaults to.
                    $pipeline += " $audioRaw ! $(Get-AudioFinalQueue)$audioSyncSuffix ! out.audio_0"
                }
                else {
                    # Explicit Direct GST WebRTC Opus branch. This keeps opusenc
                    # frame-size/audio-type/FEC/DTX visible in the command preview
                    # instead of hiding defaults inside webrtcsink.
                    $directOpusBitrate = [int]$numAudioBitrate.Value * 1000
                    $directOpusFrameMs = Get-ComboSelectedOrDefault $cmbDirectWebRtcOpusFrameMs $script:DefaultDirectWebRtcOpusFrameMs
                    $directOpusAudioType = Get-ComboSelectedOrDefault $cmbDirectWebRtcOpusAudioType $script:DefaultDirectWebRtcOpusAudioType
                    $directOpusFec = if ($chkDirectWebRtcOpusFec.Checked) { 'true' } else { 'false' }
                    $directOpusDtx = if ($chkDirectWebRtcOpusDtx.Checked) { 'true' } else { 'false' }
                    $directOpus = "opusenc bitrate=$directOpusBitrate bitrate-type=cbr frame-size=$directOpusFrameMs audio-type=$directOpusAudioType inband-fec=$directOpusFec dtx=$directOpusDtx ! opusparse ! `"audio/x-opus`""
                    $pipeline += " $audioRaw ! $directOpus ! $(Get-AudioFinalQueue)$audioSyncSuffix ! out.audio_0"
                }
            }
        }

        'SRT' {
            # Known-good MediaMTX SRT -> WebRTC shape:
            # - Opus survives SRT ingest and WebRTC egress.
            # - AAC is valid in MPEG-TS, but MediaMTX WebRTC readers skip
            #   MPEG-4 Audio.
            # - 2.9 ms aggregator latency avoids the one-track PMT race
            #   without adding the huge delay of the diagnostic 1s value.
            # - srtsink latency is intentionally omitted.
            $programMap = if ($hasAudio) {
                'prog-map="program_map,sink_256=1,sink_257=1"'
            }
            else {
                'prog-map="program_map,sink_256=1"'
            }

            $destination = $quotedDestination
            if ($destination -notmatch 'pkt_size=') {
                $joiner = if ($destination -match '\?') { '&' } else { '?' }
                $destination =
                    $destination.TrimEnd('"') +
                    "$joiner" +
                    'pkt_size=1316"'
            }

            $pipeline =
                "mpegtsmux name=mux alignment=7 " +
                "latency=2900000 " +
                "min-upstream-latency=2900000 " +
                "pat-interval=600 pmt-interval=600 " +
                "$programMap " +
                "! srtsink uri=$destination " +
                "wait-for-connection=true auto-reconnect=true " +
                "$video$videoSyncSuffix ! mux.sink_256"

            if ($hasAudio) {
                $pipeline +=
                    " $audioRaw ! $audioEncoded$audioSyncSuffix ! mux.sink_257"
            }
        }

        'RTMP' {
            if ($codec -eq 'H264') {
                $pipeline = "flvmux name=mux streamable=true ! rtmp2sink location=$quotedDestination async-connect=true $video$videoSyncSuffix ! mux."
                if ($hasAudio) {
                    $pipeline += " $audioRaw ! $audioEncoded$audioSyncSuffix ! mux."
                }
            }
            else {
                $pipeline = "eflvmux name=mux streamable=true ! rtmp2sink location=$quotedDestination async-connect=true $video$videoSyncSuffix ! mux.video"
                if ($hasAudio) {
                    $pipeline += " $audioRaw ! $audioEncoded$audioSyncSuffix ! mux.audio"
                }
            }
        }

        'RTSP' {
            $transport = if ([string]$cmbRtspTransport.SelectedItem -eq 'UDP') {
                'udp'
            }
            else {
                'tcp'
            }
            $timestampOption = Get-AbsoluteTimestampTransportOption -Protocol $protocol
            $timestampOption = if ([string]::IsNullOrWhiteSpace($timestampOption)) { '' } else { " $timestampOption" }
            $pipeline = "rtspclientsink name=out location=$quotedDestination protocols=$transport latency=0 rtx-time=0$timestampOption $video$videoSyncSuffix ! out.sink_0"
            if ($hasAudio) {
                $pipeline += " $audioRaw ! $audioEncoded$audioSyncSuffix ! out.sink_1"
            }
        }

        default {
            throw "Unsupported protocol: $protocol"
        }
    }

    if (Test-RecordingEnabled) {
        $recordingAudioBranch = Build-RecordingAudioBranch
        if (-not [string]::IsNullOrWhiteSpace($recordingAudioBranch)) {
            $pipeline += " $recordingAudioBranch"
        }
    }

    $pipeline = Wrap-GstPipelineWithClockSelect -Pipeline $pipeline -ClockMode (Get-VideoPipelineClockMode)

    $flags = '-e'
    if ($chkVerbose.Checked) {
        $flags += ' -v'
    }

    return "$flags $pipeline"
}

function Convert-GstArgumentsToPowerShellPreview {
    param([Parameter(Mandatory)][string]$Arguments)

    # Start-Process passes clockselect parentheses directly to gst-launch. In the
    # copyable PowerShell preview, quote only the outer wrapper parentheses so
    # PowerShell does not treat them as expression syntax. Do not touch caps such
    # as video/x-raw(memory:D3D11Memory).
    if ($Arguments -notmatch 'clockselect\.\s+\(') { return $Arguments }

    $preview = [regex]::Replace($Arguments, 'clockselect\.\s+\(', 'clockselect. "("', 1)
    $lastClose = $preview.LastIndexOf(')')
    if ($lastClose -ge 0) {
        $preview = $preview.Substring(0, $lastClose) + '")"' + $preview.Substring($lastClose + 1)
    }
    return $preview
}

function Update-CommandPreview {
    try {
        $gstPath = $txtGstPath.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($gstPath)) {
            $gstPath = 'gst-launch-1.0.exe'
        }

        $mainArguments = Build-GstArguments
        $previewMainArguments = Convert-GstArgumentsToPowerShellPreview -Arguments $mainArguments
        $previewText = '& ' + (Quote-GstValue $gstPath) + ' ' + $previewMainArguments

        if ((Test-TransportEnabled) -and [string]$cmbProtocol.SelectedItem -eq $script:DirectWebRtcProtocolName -and (Test-DirectWebRtcSplitAvPipelines)) {
            if (Test-DirectWebRtcUnifiedPublisher) {
                $videoArguments = Build-DirectWebRtcUnifiedVideoBridgeArguments
                $audioArguments = Build-DirectWebRtcAudioOnlyArguments
                $previewText = "# Unified WebRTC publisher - one producer / video_0 + audio_0`r`n" + $previewText
                $previewText += "`r`n`r`n# Split video capture -> localhost RTP bridge port $([int]$numDirectWebRtcBridgeVideoPort.Value)"
                $previewVideoArguments = Convert-GstArgumentsToPowerShellPreview -Arguments $videoArguments
                $previewText += "`r`n" + '& ' + (Quote-GstValue $gstPath) + ' ' + $previewVideoArguments
                $previewText += "`r`n`r`n# Split audio capture -> localhost RTP bridge port $([int]$numDirectWebRtcBridgeAudioPort.Value)"
                if ([string]::IsNullOrWhiteSpace($audioArguments)) {
                    $previewText += "`r`n# Unified audio bridge unavailable: enable Normal audio, Desktop/Mic audio, and Explicit Opus encoder mode."
                }
                else {
                    $previewAudioArguments = Convert-GstArgumentsToPowerShellPreview -Arguments $audioArguments
                    $previewText += "`r`n" + '& ' + (Quote-GstValue $gstPath) + ' ' + $previewAudioArguments
                }
            }
            else {
                $audioArguments = Build-DirectWebRtcAudioOnlyArguments
                $previewText += "`r`n`r`n# Split audio pipeline - separate gst-launch / $(if (Test-DirectWebRtcSharedSignaling) { 'shared signalling server' } else { 'signalling port ' + (Get-DirectWebRtcSplitAudioSignalingPort) })"
                if ([string]::IsNullOrWhiteSpace($audioArguments)) {
                    $previewText += "`r`n# Split audio command unavailable: enable Normal audio and Desktop/Mic audio."
                }
                else {
                    $previewAudioArguments = Convert-GstArgumentsToPowerShellPreview -Arguments $audioArguments
                    $previewText += "`r`n" + '& ' + (Quote-GstValue $gstPath) + ' ' + $previewAudioArguments
                }
            }
        }

        $txtCommand.Text = $previewText
    }
    catch {
        $txtCommand.Text = "Unable to build command: $($_.Exception.Message)"
    }
}

function Update-ProtocolUi {
    $protocol = [string]$cmbProtocol.SelectedItem
    if ([string]::IsNullOrWhiteSpace($protocol)) {
        return
    }

    if (-not $script:SuppressProtocolChange) {
        if ($script:LastProtocol -and -not [string]::IsNullOrWhiteSpace($txtDestination.Text)) {
            $script:ProtocolDestinations[$script:LastProtocol] = $txtDestination.Text.Trim()
        }

        $currentAudioCodec = [string]$cmbAudioCodec.SelectedItem
        if (
            $script:LastProtocol -and
            -not [string]::IsNullOrWhiteSpace($currentAudioCodec) -and
            (Test-AudioCodecProtocolCompatibility `
                -AudioCodecName $currentAudioCodec `
                -Protocol $script:LastProtocol)
        ) {
            $script:ProtocolAudioCodecs[$script:LastProtocol] = $currentAudioCodec
        }

        $txtDestination.Text = [string]$script:ProtocolDestinations[$protocol]
    }

    $script:LastProtocol = $protocol
    $transportEnabled = Test-TransportEnabled
    $cmbProtocol.Enabled = $transportEnabled
    $txtDestination.Enabled = $transportEnabled
    $lblDestination.Enabled = $transportEnabled
    $lblDestination.Text = if ($protocol -eq $script:DirectWebRtcProtocolName) { 'Web viewer bind URL' } else { "$protocol destination" }
    $numSrtLatency.Enabled = $transportEnabled -and ($protocol -eq 'SRT')
    $cmbRtspTransport.Enabled = $transportEnabled -and ($protocol -eq 'RTSP')
    Update-TimestampUi
    Update-MediaMtxUi
    Update-DirectWebRtcUi

    switch ($protocol) {
        'WHIP' { $toolTip.SetToolTip($txtDestination, 'Example: http://server:8889/live/whip') }
        'GST WebRTC' { $toolTip.SetToolTip($txtDestination, 'GStreamer webrtcsink web server bind address. Default mirrors MediaMTX WebRTC HTTP: http://0.0.0.0:8889/') }
        'SRT'  { $toolTip.SetToolTip($txtDestination, 'Example: srt://server:8890?mode=caller&streamid=publish:live') }
        'RTMP' { $toolTip.SetToolTip($txtDestination, 'Example: rtmp://server/live') }
        'RTSP' { $toolTip.SetToolTip($txtDestination, 'Example: rtsp://server:8554/live') }
    }

    Update-AudioCodecChoices
    Update-AudioTimingOptionUi
    Update-EncoderUi
}

function Save-Settings {
    # UI events fire while Load-Settings assigns controls. Never persist that
    # partially restored state back over the complete settings file.
    if ($script:LoadingSettings) { return }

    try {
        if (-not (Test-Path -LiteralPath $script:ConfigDirectory)) {
            $null = New-Item -ItemType Directory -Path $script:ConfigDirectory -Force
        }

        $protocol = [string]$cmbProtocol.SelectedItem
        if ($protocol -and -not [string]::IsNullOrWhiteSpace($txtDestination.Text)) {
            $script:ProtocolDestinations[$protocol] = $txtDestination.Text.Trim()
        }

        $settings = [ordered]@{
            GstPath           = $txtGstPath.Text
            StartMediaMtx     = $chkStartMediaMtx.Checked
            MediaMtxPath      = $txtMediaMtxPath.Text
            TransportEnabled  = $chkTransportEnabled.Checked
            Protocol          = $protocol
            WhipUrl           = $script:ProtocolDestinations.WHIP
            SrtUrl            = $script:ProtocolDestinations.SRT
            RtmpUrl           = $script:ProtocolDestinations.RTMP
            RtspUrl           = $script:ProtocolDestinations.RTSP
            GstWebRtcUrl      = $script:ProtocolDestinations[$script:DirectWebRtcProtocolName]
            DirectWebRtcSignalingHost = $txtDirectWebRtcSignalingHost.Text
            DirectWebRtcSignalingPort = [int]$numDirectWebRtcSignalingPort.Value
            DirectWebRtcSplitAudioSignalingPort = [int]$numDirectWebRtcSplitAudioSignalingPort.Value
            DirectWebRtcSharedSignaling = [bool]$chkDirectWebRtcSharedSignaling.Checked
            SplitClockSignalingOverrides = [bool]$chkSplitClockSignalingOverrides.Checked
            SplitVideoClockSignaling = [string]$cmbSplitVideoClockSignaling.SelectedItem
            SplitAudioClockSignaling = [string]$cmbSplitAudioClockSignaling.SelectedItem
            DirectWebRtcMediaStreamGrouping = [string](Get-DirectWebRtcMediaStreamGrouping)
            DirectWebRtcVideoMediaStreamId = [string](Get-DirectWebRtcMediaStreamId -Kind video)
            DirectWebRtcAudioMediaStreamId = [string](Get-DirectWebRtcMediaStreamId -Kind audio)
            DirectWebRtcUnifiedPublisher = [bool]$chkDirectWebRtcUnifiedPublisher.Checked
            DirectWebRtcBridgeVideoPort = [int]$numDirectWebRtcBridgeVideoPort.Value
            DirectWebRtcBridgeAudioPort = [int]$numDirectWebRtcBridgeAudioPort.Value
            DirectWebRtcBridgeJitterMs = [int]$numDirectWebRtcBridgeJitterMs.Value
            DirectWebRtcPublisherQueueMs = [int]$numDirectWebRtcPublisherQueueMs.Value
            DirectWebRtcAudioBridgePacing = [bool]$chkDirectWebRtcAudioBridgePacing.Checked
            DirectWebRtcControlDataChannel = [bool]$chkDirectWebRtcControlDataChannel.Checked
            DirectWebRtcBundlePolicy = [string]$cmbDirectWebRtcBundlePolicy.SelectedItem
            DirectWebRtcInternalRtpMtu = [int]$numDirectWebRtcInternalRtpMtu.Value
            DirectWebRtcInternalRepeatHeaders = [bool]$chkDirectWebRtcInternalRepeatHeaders.Checked
            DirectWebRtcStunServer = $txtDirectWebRtcStun.Text
            DirectWebRtcTurnEnabled = [bool]$chkDirectWebRtcTurnEnabled.Checked
            DirectWebRtcTurnServer = $txtDirectWebRtcTurn.Text
            DirectWebRtcWebPath = $txtDirectWebRtcWebPath.Text
            DirectWebRtcBundledWebMode = [string]$cmbDirectWebRtcBundledWebMode.SelectedItem
            DirectWebRtcBundledWebDirectory = $txtDirectWebRtcBundledWebDirectory.Text
            DirectWebRtcWorkingWebMode = [string]$cmbDirectWebRtcWorkingWebMode.SelectedItem
            DirectWebRtcWorkingWebDirectory = $txtDirectWebRtcWebDirectory.Text
            DirectWebRtcWebDirectory = $txtDirectWebRtcWebDirectory.Text
            DirectWebRtcCongestion = [string]$cmbDirectWebRtcCongestion.SelectedItem
            DirectWebRtcMitigation = [string]$cmbDirectWebRtcMitigation.SelectedItem
            WebRtcRecoveryMode = [string]$cmbWebRtcRecoveryMode.SelectedItem
            WebRtcSenderQueueMode = [string]$cmbWebRtcSenderQueueMode.SelectedItem
            DirectWebRtcFec = $chkDirectWebRtcFec.Checked
            DirectWebRtcRetransmission = $chkDirectWebRtcRetransmission.Checked
            DirectWebRtcSmoothnessProfile = [string]$cmbDirectWebRtcSmoothnessProfile.SelectedItem
            DirectWebRtcPacingMs = [int]$numDirectWebRtcPacingMs.Value
            WebRtcSenderQueueCapMs = [int]$numDirectWebRtcPacingMs.Value
            DirectWebRtcPlayerJitterMs = [int]$numDirectWebRtcPlayerJitterMs.Value
            DirectWebRtcAudioJitterMs = [int]$numDirectWebRtcPlayerJitterMs.Value
            DirectWebRtcVideoJitterMs = [int]$numDirectWebRtcVideoJitterMs.Value
            DirectWebRtcOpusMode = [string]$cmbDirectWebRtcOpusMode.SelectedItem
            DirectWebRtcOpusFrameMs = [string]$cmbDirectWebRtcOpusFrameMs.SelectedItem
            DirectWebRtcOpusAudioType = [string]$cmbDirectWebRtcOpusAudioType.SelectedItem
            DirectWebRtcOpusFec = [bool]$chkDirectWebRtcOpusFec.Checked
            DirectWebRtcOpusDtx = [bool]$chkDirectWebRtcOpusDtx.Checked
            JbufWatchdogMode = [string]$cmbJbufWatchdogMode.SelectedItem
            JbufMaxMs = [int]$numJbufMaxMs.Value
            PlayerStatsOverlay = [bool]$chkPlayerStatsOverlay.Checked
            PlayerJbufDebug = [bool]$chkPlayerJbufDebug.Checked
            LiveEdgeGreenMs = [int]$numLiveEdgeGreenMs.Value
            LiveEdgeYellowMs = [int]$numLiveEdgeYellowMs.Value
            LiveEdgeAverageSec = [int]$numLiveEdgeAverageSec.Value
            PlayerUrlOverrides = [bool]$chkPlayerUrlOverrides.Checked
            PlayerSeparateHtmlMediaElements = [bool]$chkPlayerSeparateHtmlMediaElements.Checked
            SeparateHtmlMediaElements = [bool]$chkPlayerSeparateHtmlMediaElements.Checked
            PlayerAvRenderMode = if ($chkPlayerSeparateHtmlMediaElements.Checked) { 'Decoupled video/audio elements' } else { 'Synced single media element' }
            DirectWebRtcAvPipelineMode = [string](Get-DirectWebRtcAvPipelineMode)
            SplitPlayerSyncMode = [string](Get-ComboSelectedOrDefault $cmbSplitPlayerSyncMode $script:DefaultSplitPlayerSyncMode)
            SplitAudioStallSeconds = [int]$numSplitAudioStallSeconds.Value
            SplitAudioWarmupSeconds = [int]$numSplitAudioWarmupSeconds.Value
            JbufWatchdogWarmupSeconds = [int]$numSplitAudioWarmupSeconds.Value
            WatchdogWarmupSeconds = [int]$numSplitAudioWarmupSeconds.Value
            SplitAvOffsetBaselineMs = [int]$numSplitAvOffsetBaselineMs.Value
            SplitAvOffsetWarnMs = [int]$numSplitAvOffsetWarnMs.Value
            VideoPipelineClockMode = [string]$cmbVideoPipelineClockMode.SelectedItem
            VideoTimestampMode = [string]$cmbVideoTimestampMode.SelectedItem
            SplitAudioPipelineClockMode = [string]$cmbSplitAudioPipelineClockMode.SelectedItem
            VideoSyncMode = [string]$cmbVideoSyncMode.SelectedItem
            AudioSyncMode = [string]$cmbAudioSyncMode.SelectedItem
            ThreadingProfile = [string]$cmbThreadingProfile.SelectedItem
            GstProcessPriority = [string]$cmbGstProcessPriority.SelectedItem
            ThreadBudget = [string]$cmbThreadBudget.SelectedItem
            CpuWorkerLimit = [int]$numCpuWorkerLimit.Value
            BudgetCaptureQueue = $chkBudgetCaptureQueue.Checked
            BudgetSenderQueue = $chkBudgetSenderQueue.Checked
            BudgetAudioInputQueue = $chkBudgetAudioInputQueue.Checked
            BudgetAudioFinalQueue = $chkBudgetAudioFinalQueue.Checked
            BudgetSceneInputQueues = $chkBudgetSceneInputQueues.Checked
            QueueLeakMode = [string]$cmbQueueLeakMode.SelectedItem
            CaptureQueueBuffers = [int]$numCaptureQueueBuffers.Value
            AudioQueueBuffers = [int]$numAudioQueueBuffers.Value
            AudioQueueCapMs = [int]$numAudioQueueCapMs.Value
            BufferLatenessTracer = $chkBufferLatenessTracer.Checked
            GstDebugMode     = [string]$cmbGstDebugMode.SelectedItem
            GstDebugSpec     = $txtGstDebugSpec.Text
            GstDebugNoColor  = $chkGstDebugNoColor.Checked
            SrtLatency        = [int]$numSrtLatency.Value
            RtspTransport     = [string]$cmbRtspTransport.SelectedItem
            MonitorIndex      = [int]$numMonitor.Value
            ShowCursor        = $chkCursor.Checked
            CaptureMethod     = Get-SelectedCaptureMethodName
            SceneEnabled      = $chkSceneEnabled.Checked
            ScenePreset       = [string]$cmbScenePreset.SelectedItem
            SceneCompositor   = [string]$cmbSceneCompositor.SelectedItem
            SceneInputQueueBuffers = [int]$numSceneInputQueueBuffers.Value
            SceneInputQueueCapMs = [int]$numSceneInputQueueCapMs.Value
            WebcamDevice      = [string]$cmbWebcamDevice.SelectedItem
            WebcamLayout      = [string]$cmbWebcamLayout.SelectedItem
            WebcamWidth       = [int]$numWebcamWidth.Value
            WebcamHeight      = [int]$numWebcamHeight.Value
            WebcamX           = [int]$numWebcamX.Value
            WebcamY           = [int]$numWebcamY.Value
            WebcamFps         = [int]$numWebcamFps.Value
            WebcamOpacity     = [int]$numWebcamOpacity.Value
            WebcamBorder      = [int]$numWebcamBorder.Value
            WebcamMirror      = $chkWebcamMirror.Checked
            WebcamAspectLock  = $chkWebcamAspectLock.Checked
            FullscreenApp     = Test-FullscreenCaptureMode
            SendAbsoluteTimestamps = (Test-SendAbsoluteTimestampsEnabled)
            TimingMode             = [string]$cmbTimingMode.SelectedItem
            RecordingEnabled  = $chkRecordingEnabled.Checked
            RecordingDirectory = $txtRecordingDirectory.Text
            RecordingTemplate = $txtRecordingTemplate.Text
            RecordingEncoder  = [string]$cmbRecordingEncoder.SelectedItem
            RecordingPreset   = [string]$cmbRecordingPreset.SelectedItem
            RecordingProfile  = [string]$cmbRecordingProfile.SelectedItem
            RecordingWidth    = [int]$numRecordingWidth.Value
            RecordingHeight   = [int]$numRecordingHeight.Value
            RecordingFps      = [int]$numRecordingFps.Value
            RecordingVideoBitrateKbps = [int]$numRecordingVideoBitrate.Value
            RecordingRateControl = [string]$cmbRecordingRateControl.SelectedItem
            RecordingMaxVideoBitrateKbps = [int]$numRecordingMaxVideoBitrate.Value
            RecordingConstantQp = [int]$numRecordingConstantQp.Value
            RecordingGopSeconds = [int]$numRecordingGopSeconds.Value
            RecordingBFrames  = [int]$numRecordingBFrames.Value
            RecordingTune     = [string]$cmbRecordingTune.SelectedItem
            RecordingMultipass = [string]$cmbRecordingMultipass.SelectedItem
            RecordingLookAhead = $chkRecordingLookAhead.Checked
            RecordingLookAheadFrames = [int]$numRecordingLookAheadFrames.Value
            RecordingSpatialAq = $chkRecordingSpatialAq.Checked
            RecordingTemporalAq = $chkRecordingTemporalAq.Checked
            RecordingAqStrength = [int]$numRecordingAqStrength.Value
            RecordingVbvBufferKbits = [int]$numRecordingVbvBuffer.Value
            RecordingCustomEncoderOptions = $txtRecordingCustomEncoderOptions.Text
            RecordingDesktopAudio = $chkRecordingDesktopAudio.Checked
            RecordingMicrophone = $chkRecordingMic.Checked
            RecordingAudioBitrateKbps = [int]$numRecordingAudioBitrate.Value
            Preview           = $chkPreview.Checked
            HidePreviewDuringStream = $chkHidePreviewDuringStream.Checked
            DynamicScenePreviews = $chkDynamicScenePreviews.Checked
            LiveSceneEditing   = $chkLiveSceneEditing.Checked
            StandardPreviewOffSceneTab = $chkStandardPreviewOffSceneTab.Checked
            AutoRestart       = $chkAutoRestart.Checked
            Verbose           = $chkVerbose.Checked
            DiskProcessLogging = $chkDiskProcessLogging.Checked
            MinimizeToTray    = [bool]($chkMinimizeToTray.Checked -or $chkStartMinimized.Checked)
            StartMinimized    = $chkStartMinimized.Checked
            NetworkTuningEnabled = $chkNetworkTuningEnabled.Checked
            NetworkAdapter    = Get-SelectedNetworkAdapterName
            NetworkProfile    = [string]$cmbNetworkProfile.SelectedItem
            NetworkDscpEnabled = $chkNetworkDscp.Checked
            NetworkDscpValue  = [int]$numNetworkDscp.Value
            NetworkQosProtocol = [string]$cmbNetworkQosProtocol.SelectedItem
            NetworkQosPorts   = $txtNetworkPorts.Text
            NetworkUso        = [string]$cmbNetworkUso.SelectedItem
            NetworkUro        = [string]$cmbNetworkUro.SelectedItem
            NetworkDisablePowerSaving = $chkNetworkDisablePowerSaving.Checked
            NetworkInterruptModeration = [string]$cmbNetworkInterruptModeration.SelectedItem
            NetworkDisableEee = $chkNetworkDisableEee.Checked
            NetworkRestoreOnStop = $chkNetworkRestoreOnStop.Checked
            NetworkRestoreOnExit = $chkNetworkRestoreOnExit.Checked
            NetworkRecoveryTask = $chkNetworkRecoveryTask.Checked
            Width             = [int]$numWidth.Value
            Height            = [int]$numHeight.Value
            Fps               = [int]$numFps.Value
            VideoBitrateKbps  = [int]$numVideoBitrate.Value
            RateControl       = [string]$cmbRateControl.SelectedItem
            MaxVideoBitrateKbps = [int]$numMaxVideoBitrate.Value
            ConstantQp        = [int]$numConstantQp.Value
            GopSeconds        = [int]$numGopSeconds.Value
            UnifiedBridgeKeyframeGuard = [bool]$chkUnifiedBridgeKeyframeGuard.Checked
            UnifiedBridgeKeyframeIntervalMs = [int]$numUnifiedBridgeKeyframeIntervalMs.Value
            Encoder           = [string]$cmbEncoder.SelectedItem
            Preset            = [string]$cmbPreset.SelectedItem
            Profile           = [string]$cmbProfile.SelectedItem
            EncoderTune       = [string]$cmbEncoderTune.SelectedItem
            Multipass         = [string]$cmbMultipass.SelectedItem
            VbvBufferKbits    = [int]$numVbvBuffer.Value
            BFrames           = [int]$numBFrames.Value
            LookAhead         = $chkLookAhead.Checked
            LookAheadFrames   = [int]$numLookAheadFrames.Value
            AdaptiveQuantization = $chkAdaptiveQuantization.Checked
            SpatialAq         = $chkAdaptiveQuantization.Checked
            TemporalAq        = $chkTemporalAq.Checked
            AqStrength        = [int]$numAqStrength.Value
            CustomEncoderOptions = $txtCustomEncoderOptions.Text
            WhipAudioCodec    = [string]$script:ProtocolAudioCodecs.WHIP
            GstWebRtcAudioCodec = [string]$script:ProtocolAudioCodecs[$script:DirectWebRtcProtocolName]
            SrtAudioCodec     = [string]$script:ProtocolAudioCodecs.SRT
            RtmpAudioCodec    = [string]$script:ProtocolAudioCodecs.RTMP
            RtspAudioCodec    = [string]$script:ProtocolAudioCodecs.RTSP
            AudioTransportMode = [string]$cmbAudioTransportMode.SelectedItem
            AudioClockMode = [string]$cmbAudioClockMode.SelectedItem
            AudioTimingMode = [string]$cmbAudioTimingMode.SelectedItem
            AudioSlaveMethod = [string]$cmbAudioSlaveMethod.SelectedItem
            WasapiLowLatencyOverride = [bool]$chkWasapiLowLatencyOverride.Checked
            AudioBufferOverride = [bool]$chkAudioBufferOverride.Checked
            AudioBufferMs = [int]$numAudioBufferMs.Value
            AudioLatencyOverride = [bool]$chkAudioLatencyOverride.Checked
            AudioLatencyMs = [int]$numAudioLatencyMs.Value
            AudioSampleRateOverride = [bool]$chkAudioSampleRateOverride.Checked
            AudioSampleRateHz = [int]$numAudioSampleRate.Value
            DesktopAudio      = $chkDesktopAudio.Checked
            AudioMixerMode    = $chkAudioMixerMode.Checked
            DesktopVolume     = [int]$numDesktopVolume.Value
            DesktopAudioDevice = if ($cmbDesktopAudioDevice.SelectedItem) { [string]$cmbDesktopAudioDevice.SelectedItem } else { $script:DefaultAudioOutputDeviceLabel }
            DesktopAudioDeviceId = Get-SelectedAudioDeviceId -Kind Output
            Microphone        = $chkMic.Checked
            MicrophoneVolume  = [int]$numMicVolume.Value
            MicrophoneDevice  = if ($cmbMicAudioDevice.SelectedItem) { [string]$cmbMicAudioDevice.SelectedItem } else { $script:DefaultAudioInputDeviceLabel }
            MicrophoneDeviceId = Get-SelectedAudioDeviceId -Kind Input
            AudioBitrateKbps  = [int]$numAudioBitrate.Value
        }

        $settings | ConvertTo-Json | Set-Content -LiteralPath $script:ConfigPath -Encoding UTF8
    }
    catch {
        Append-Log "Could not save settings: $($_.Exception.Message)"
    }
}

function Export-LabConfiguration {
    try {
        # Save first so the export is based on the exact current UI state.
        Save-Settings
        Update-CommandPreview

        if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
            throw "The live settings file was not created: $script:ConfigPath"
        }

        $savedSettings =
            Get-Content -LiteralPath $script:ConfigPath -Raw |
            ConvertFrom-Json

        # Keep the settings flat so this file can later be imported directly or
        # used as settings.json. Metadata keys are prefixed and ignored by older
        # builds that do not know about them.
        $export = [ordered]@{
            _Schema           = 'GStreamerGlassLabConfig'
            _SchemaVersion    = 1
            _AppVersion       = $script:AppVersion
            _ExportedUtc      = [DateTime]::UtcNow.ToString('o')
            _GeneratedCommand = [string]$txtCommand.Text
        }

        foreach ($property in $savedSettings.PSObject.Properties) {
            $export[$property.Name] = $property.Value
        }

        $dialog = New-Object System.Windows.Forms.SaveFileDialog
        try {
            $dialog.Title = 'Export GStreamer Glass lab configuration'
            $dialog.Filter = 'GStreamer Glass lab config (*.gstglass.json)|*.gstglass.json|JSON files (*.json)|*.json|All files (*.*)|*.*'
            $dialog.DefaultExt = 'gstglass.json'
            $dialog.AddExtension = $true
            $dialog.OverwritePrompt = $true
            $dialog.RestoreDirectory = $true
            $dialog.FileName = 'GStreamer-Glass-' + $script:AppVersion + '-LabConfig-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.gstglass.json'

            if ($dialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) {
                return
            }

            $export |
                ConvertTo-Json -Depth 12 |
                Set-Content -LiteralPath $dialog.FileName -Encoding UTF8

            Append-Log "Lab configuration exported: $($dialog.FileName)"
            $statusLabel.Text = 'Lab config exported'
            $statusLabel.ForeColor = [System.Drawing.Color]::DarkGreen

            [System.Windows.Forms.MessageBox]::Show(
                "Exported the complete UI configuration and exact generated command.`r`n`r`n$($dialog.FileName)",
                $script:AppName,
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
        finally {
            $dialog.Dispose()
        }
    }
    catch {
        Append-Log "Could not export lab configuration: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            "Could not export the lab configuration.`r`n`r`n$($_.Exception.Message)",
            $script:AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

function Load-Settings {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
        return
    }

    $script:LoadingSettings = $true
    try {
        $settings = Get-Content -LiteralPath $script:ConfigPath -Raw | ConvertFrom-Json
        $script:SuppressProtocolChange = $true

        if ($settings.GstPath) {
            $loadedGstPath = [string]$settings.GstPath
            if (Test-GstLaunchPath $loadedGstPath) {
                $txtGstPath.Text = Normalize-GstLaunchPath $loadedGstPath
            }
            else {
                $txtGstPath.Text = Find-GstLaunch
                Append-Log "Saved GStreamer executable was not found: $loadedGstPath"
                Append-Log "Using detected GStreamer executable: $($txtGstPath.Text)"
            }
        }
        if ($settings.MediaMtxPath) {
            $txtMediaMtxPath.Text = [string]$settings.MediaMtxPath
        }
        if ($null -ne $settings.StartMediaMtx) {
            $chkStartMediaMtx.Checked = [bool]$settings.StartMediaMtx
        }
        if ($null -ne $settings.TransportEnabled) {
            $chkTransportEnabled.Checked = [bool]$settings.TransportEnabled
        }
        if ($settings.WhipUrl) { $script:ProtocolDestinations.WHIP = [string]$settings.WhipUrl }
        if ($settings.SrtUrl) { $script:ProtocolDestinations.SRT = [string]$settings.SrtUrl }
        if ($settings.RtmpUrl) { $script:ProtocolDestinations.RTMP = [string]$settings.RtmpUrl }
        if ($settings.RtspUrl) { $script:ProtocolDestinations.RTSP = [string]$settings.RtspUrl }
        if ($settings.GstWebRtcUrl) { $script:ProtocolDestinations[$script:DirectWebRtcProtocolName] = [string]$settings.GstWebRtcUrl }
        if ($settings.DirectWebRtcSignalingHost) { $txtDirectWebRtcSignalingHost.Text = [string]$settings.DirectWebRtcSignalingHost }
        if ($null -ne $settings.DirectWebRtcSignalingPort) {
            $loadedDirectWebRtcSignalPort = [int]$settings.DirectWebRtcSignalingPort
            if ($loadedDirectWebRtcSignalPort -eq 8443) {
                # v3.7.21 used 8443. The user's proxy layout expects the WebSocket
                # signalling listener on 8189, so migrate the stale saved value.
                $loadedDirectWebRtcSignalPort = $script:DefaultDirectWebRtcSignalingPort
                Append-Log 'Migrated legacy Direct WebRTC signalling port 8443 to 8189.'
            }
            $numDirectWebRtcSignalingPort.Value = [decimal]$loadedDirectWebRtcSignalPort
        }
        if ($null -ne $settings.DirectWebRtcSplitAudioSignalingPort) {
            $loadedAudioSignalPort = [int]$settings.DirectWebRtcSplitAudioSignalingPort
            $numDirectWebRtcSplitAudioSignalingPort.Value = [decimal]([Math]::Min(65535, [Math]::Max(1, $loadedAudioSignalPort)))
        }
        elseif ($null -ne $settings.DirectWebRtcSignalingPort) {
            $legacyAudioPort = [Math]::Min(65535, ([int]$numDirectWebRtcSignalingPort.Value + [int]$script:DefaultDirectWebRtcSplitAudioPortOffset))
            $numDirectWebRtcSplitAudioSignalingPort.Value = [decimal]$legacyAudioPort
        }
        if ($null -ne $settings.DirectWebRtcSharedSignaling) { $chkDirectWebRtcSharedSignaling.Checked = [bool]$settings.DirectWebRtcSharedSignaling }
        if ($settings.DirectWebRtcMediaStreamGrouping -and $cmbDirectWebRtcMediaStreamGrouping.Items.Contains([string]$settings.DirectWebRtcMediaStreamGrouping)) { $cmbDirectWebRtcMediaStreamGrouping.SelectedItem = [string]$settings.DirectWebRtcMediaStreamGrouping }
        if ($null -ne $settings.DirectWebRtcVideoMediaStreamId) { $txtDirectWebRtcVideoMediaStreamId.Text = [string]$settings.DirectWebRtcVideoMediaStreamId }
        if ($null -ne $settings.DirectWebRtcAudioMediaStreamId) { $txtDirectWebRtcAudioMediaStreamId.Text = [string]$settings.DirectWebRtcAudioMediaStreamId }
        if ($null -ne $settings.DirectWebRtcUnifiedPublisher) { $chkDirectWebRtcUnifiedPublisher.Checked = [bool]$settings.DirectWebRtcUnifiedPublisher }
        if ($null -ne $settings.DirectWebRtcBridgeVideoPort) { $numDirectWebRtcBridgeVideoPort.Value = [decimal]([Math]::Min(65535, [Math]::Max(1, [int]$settings.DirectWebRtcBridgeVideoPort))) }
        if ($null -ne $settings.DirectWebRtcBridgeAudioPort) { $numDirectWebRtcBridgeAudioPort.Value = [decimal]([Math]::Min(65535, [Math]::Max(1, [int]$settings.DirectWebRtcBridgeAudioPort))) }
        if ($null -ne $settings.DirectWebRtcBridgeJitterMs) { $numDirectWebRtcBridgeJitterMs.Value = [decimal]([Math]::Min(2000, [Math]::Max(0, [int]$settings.DirectWebRtcBridgeJitterMs))) }
        if ($null -ne $settings.DirectWebRtcPublisherQueueMs) { $numDirectWebRtcPublisherQueueMs.Value = [decimal]([Math]::Min(2000, [Math]::Max(0, [int]$settings.DirectWebRtcPublisherQueueMs))) }
        if ($null -ne $settings.DirectWebRtcAudioBridgePacing) { $chkDirectWebRtcAudioBridgePacing.Checked = [bool]$settings.DirectWebRtcAudioBridgePacing }
        if ($null -ne $settings.SplitClockSignalingOverrides) { $chkSplitClockSignalingOverrides.Checked = [bool]$settings.SplitClockSignalingOverrides }
        if ($settings.SplitVideoClockSignaling -and $cmbSplitVideoClockSignaling.Items.Contains([string]$settings.SplitVideoClockSignaling)) { $cmbSplitVideoClockSignaling.SelectedItem = [string]$settings.SplitVideoClockSignaling }
        if ($settings.SplitAudioClockSignaling -and $cmbSplitAudioClockSignaling.Items.Contains([string]$settings.SplitAudioClockSignaling)) { $cmbSplitAudioClockSignaling.SelectedItem = [string]$settings.SplitAudioClockSignaling }
        if ($null -ne $settings.DirectWebRtcControlDataChannel) { $chkDirectWebRtcControlDataChannel.Checked = [bool]$settings.DirectWebRtcControlDataChannel }
        if ($settings.DirectWebRtcBundlePolicy -and $cmbDirectWebRtcBundlePolicy.Items.Contains([string]$settings.DirectWebRtcBundlePolicy)) { $cmbDirectWebRtcBundlePolicy.SelectedItem = [string]$settings.DirectWebRtcBundlePolicy }
        if ($null -ne $settings.DirectWebRtcInternalRtpMtu) { $numDirectWebRtcInternalRtpMtu.Value = [decimal]([Math]::Min(65535, [Math]::Max(0, [int]$settings.DirectWebRtcInternalRtpMtu))) }
        if ($null -ne $settings.DirectWebRtcInternalRepeatHeaders) { $chkDirectWebRtcInternalRepeatHeaders.Checked = [bool]$settings.DirectWebRtcInternalRepeatHeaders }
        if ($null -ne $settings.DirectWebRtcStunServer) { $txtDirectWebRtcStun.Text = [string]$settings.DirectWebRtcStunServer }
        if ($null -ne $settings.DirectWebRtcTurnEnabled) { $chkDirectWebRtcTurnEnabled.Checked = [bool]$settings.DirectWebRtcTurnEnabled }
        if ($null -ne $settings.DirectWebRtcTurnServer) { $txtDirectWebRtcTurn.Text = [string]$settings.DirectWebRtcTurnServer }
        if ($null -ne $settings.DirectWebRtcWebPath) { $txtDirectWebRtcWebPath.Text = [string]$settings.DirectWebRtcWebPath }
        if ($settings.DirectWebRtcBundledWebMode -and $cmbDirectWebRtcBundledWebMode.Items.Contains([string]$settings.DirectWebRtcBundledWebMode)) { $cmbDirectWebRtcBundledWebMode.SelectedItem = [string]$settings.DirectWebRtcBundledWebMode }
        if ($null -ne $settings.DirectWebRtcBundledWebDirectory) { $txtDirectWebRtcBundledWebDirectory.Text = [string]$settings.DirectWebRtcBundledWebDirectory }
        if ($settings.DirectWebRtcWorkingWebMode -and $cmbDirectWebRtcWorkingWebMode.Items.Contains([string]$settings.DirectWebRtcWorkingWebMode)) { $cmbDirectWebRtcWorkingWebMode.SelectedItem = [string]$settings.DirectWebRtcWorkingWebMode }
        if ($null -ne $settings.DirectWebRtcWorkingWebDirectory) { $txtDirectWebRtcWebDirectory.Text = [string]$settings.DirectWebRtcWorkingWebDirectory }
        elseif ($null -ne $settings.DirectWebRtcWebDirectory) { $txtDirectWebRtcWebDirectory.Text = [string]$settings.DirectWebRtcWebDirectory }
        if ($settings.DirectWebRtcCongestion -and $cmbDirectWebRtcCongestion.Items.Contains([string]$settings.DirectWebRtcCongestion)) { $cmbDirectWebRtcCongestion.SelectedItem = [string]$settings.DirectWebRtcCongestion }
        if ($settings.DirectWebRtcMitigation -and $cmbDirectWebRtcMitigation.Items.Contains([string]$settings.DirectWebRtcMitigation)) { $cmbDirectWebRtcMitigation.SelectedItem = [string]$settings.DirectWebRtcMitigation }
        if ($settings.WebRtcRecoveryMode -and $cmbWebRtcRecoveryMode.Items.Contains([string]$settings.WebRtcRecoveryMode)) {
            Set-WebRtcRecoveryMode ([string]$settings.WebRtcRecoveryMode)
        }
        elseif ($null -ne $settings.DirectWebRtcFec -or $null -ne $settings.DirectWebRtcRetransmission) {
            $legacyFec = if ($null -ne $settings.DirectWebRtcFec) { [bool]$settings.DirectWebRtcFec } else { $false }
            $legacyRtx = if ($null -ne $settings.DirectWebRtcRetransmission) { [bool]$settings.DirectWebRtcRetransmission } else { $true }
            if ($legacyFec -and $legacyRtx) { Set-WebRtcRecoveryMode 'FEC + RTX' }
            elseif ($legacyFec) { Set-WebRtcRecoveryMode 'FEC only' }
            elseif ($legacyRtx) { Set-WebRtcRecoveryMode 'RTX only' }
            else { Set-WebRtcRecoveryMode 'None' }
        }
        if ($settings.WebRtcSenderQueueMode -and $cmbWebRtcSenderQueueMode.Items.Contains([string]$settings.WebRtcSenderQueueMode)) { $cmbWebRtcSenderQueueMode.SelectedItem = [string]$settings.WebRtcSenderQueueMode }
        if ($settings.DirectWebRtcSmoothnessProfile -and $cmbDirectWebRtcSmoothnessProfile.Items.Contains([string]$settings.DirectWebRtcSmoothnessProfile)) { $cmbDirectWebRtcSmoothnessProfile.SelectedItem = [string]$settings.DirectWebRtcSmoothnessProfile }
        if ($null -ne $settings.DirectWebRtcPacingMs) { $numDirectWebRtcPacingMs.Value = [decimal]([Math]::Min([int]$numDirectWebRtcPacingMs.Maximum, [Math]::Max([int]$numDirectWebRtcPacingMs.Minimum, [int]$settings.DirectWebRtcPacingMs))) }
        if ($null -ne $settings.DirectWebRtcAudioJitterMs) { $numDirectWebRtcPlayerJitterMs.Value = [decimal]([Math]::Min([int]$numDirectWebRtcPlayerJitterMs.Maximum, [Math]::Max([int]$numDirectWebRtcPlayerJitterMs.Minimum, [int]$settings.DirectWebRtcAudioJitterMs))) }
        elseif ($null -ne $settings.DirectWebRtcPlayerJitterMs) { $numDirectWebRtcPlayerJitterMs.Value = [decimal]([Math]::Min([int]$numDirectWebRtcPlayerJitterMs.Maximum, [Math]::Max([int]$numDirectWebRtcPlayerJitterMs.Minimum, [int]$settings.DirectWebRtcPlayerJitterMs))) }
        if ($null -ne $settings.DirectWebRtcVideoJitterMs) { $numDirectWebRtcVideoJitterMs.Value = [decimal]([Math]::Min([int]$numDirectWebRtcVideoJitterMs.Maximum, [Math]::Max([int]$numDirectWebRtcVideoJitterMs.Minimum, [int]$settings.DirectWebRtcVideoJitterMs))) }
        if ($settings.DirectWebRtcOpusMode -and $cmbDirectWebRtcOpusMode.Items.Contains([string]$settings.DirectWebRtcOpusMode)) { $cmbDirectWebRtcOpusMode.SelectedItem = [string]$settings.DirectWebRtcOpusMode }
        if ($settings.DirectWebRtcOpusFrameMs -and $cmbDirectWebRtcOpusFrameMs.Items.Contains([string]$settings.DirectWebRtcOpusFrameMs)) { $cmbDirectWebRtcOpusFrameMs.SelectedItem = [string]$settings.DirectWebRtcOpusFrameMs }
        if ($settings.DirectWebRtcOpusAudioType -and $cmbDirectWebRtcOpusAudioType.Items.Contains([string]$settings.DirectWebRtcOpusAudioType)) { $cmbDirectWebRtcOpusAudioType.SelectedItem = [string]$settings.DirectWebRtcOpusAudioType }
        if ($null -ne $settings.DirectWebRtcOpusFec) { $chkDirectWebRtcOpusFec.Checked = [bool]$settings.DirectWebRtcOpusFec }
        if ($null -ne $settings.DirectWebRtcOpusDtx) { $chkDirectWebRtcOpusDtx.Checked = [bool]$settings.DirectWebRtcOpusDtx }
        if ($settings.JbufWatchdogMode -and $cmbJbufWatchdogMode.Items.Contains([string]$settings.JbufWatchdogMode)) { $cmbJbufWatchdogMode.SelectedItem = [string]$settings.JbufWatchdogMode }
        if ($null -ne $settings.JbufMaxMs) { $numJbufMaxMs.Value = [decimal]([Math]::Min([int]$numJbufMaxMs.Maximum, [Math]::Max([int]$numJbufMaxMs.Minimum, [int]$settings.JbufMaxMs))) }
        if ($null -ne $settings.PlayerStatsOverlay) { $chkPlayerStatsOverlay.Checked = [bool]$settings.PlayerStatsOverlay }
        if ($null -ne $settings.PlayerJbufDebug) { $chkPlayerJbufDebug.Checked = [bool]$settings.PlayerJbufDebug }
        if ($null -ne $settings.LiveEdgeGreenMs) { $numLiveEdgeGreenMs.Value = [decimal]([Math]::Min([int]$numLiveEdgeGreenMs.Maximum, [Math]::Max([int]$numLiveEdgeGreenMs.Minimum, [int]$settings.LiveEdgeGreenMs))) }
        if ($null -ne $settings.LiveEdgeYellowMs) { $numLiveEdgeYellowMs.Value = [decimal]([Math]::Min([int]$numLiveEdgeYellowMs.Maximum, [Math]::Max([int]$numLiveEdgeYellowMs.Minimum, [int]$settings.LiveEdgeYellowMs))) }
        if ($null -ne $settings.LiveEdgeAverageSec) { $numLiveEdgeAverageSec.Value = [decimal]([Math]::Min([int]$numLiveEdgeAverageSec.Maximum, [Math]::Max([int]$numLiveEdgeAverageSec.Minimum, [int]$settings.LiveEdgeAverageSec))) }
        if ($numLiveEdgeYellowMs.Value -le $numLiveEdgeGreenMs.Value) { $numLiveEdgeYellowMs.Value = [decimal]([Math]::Min([int]$numLiveEdgeYellowMs.Maximum, [int]$numLiveEdgeGreenMs.Value + 1)) }
        if ($null -ne $settings.PlayerUrlOverrides) { $chkPlayerUrlOverrides.Checked = [bool]$settings.PlayerUrlOverrides }
        if ($null -ne $settings.PlayerSeparateHtmlMediaElements) {
            $chkPlayerSeparateHtmlMediaElements.Checked = [bool]$settings.PlayerSeparateHtmlMediaElements
        }
        elseif ($null -ne $settings.SeparateHtmlMediaElements) {
            $chkPlayerSeparateHtmlMediaElements.Checked = [bool]$settings.SeparateHtmlMediaElements
        }
        elseif ($settings.DirectWebRtcMediaStreamGrouping -and ([string]$settings.DirectWebRtcMediaStreamGrouping -like 'Separate audio/video MediaStreams*')) {
            # f40-f42 forced separate HTML elements whenever MSIDs were split. Preserve
            # that effective behavior once while migrating to the explicit Player toggle.
            $chkPlayerSeparateHtmlMediaElements.Checked = $true
        }
        elseif ($settings.PlayerAvRenderMode) {
            $chkPlayerSeparateHtmlMediaElements.Checked = ([string]$settings.PlayerAvRenderMode -like 'Decoupled*')
        }
        if ($settings.DirectWebRtcAvPipelineMode -and $cmbDirectWebRtcAvPipelineMode.Items.Contains([string]$settings.DirectWebRtcAvPipelineMode)) { $cmbDirectWebRtcAvPipelineMode.SelectedItem = [string]$settings.DirectWebRtcAvPipelineMode }
        if ($settings.SplitPlayerSyncMode -and $cmbSplitPlayerSyncMode.Items.Contains([string]$settings.SplitPlayerSyncMode)) { $cmbSplitPlayerSyncMode.SelectedItem = [string]$settings.SplitPlayerSyncMode }
        if ($null -ne $settings.SplitAudioStallSeconds) { $numSplitAudioStallSeconds.Value = [decimal]([Math]::Min([int]$numSplitAudioStallSeconds.Maximum, [Math]::Max([int]$numSplitAudioStallSeconds.Minimum, [int]$settings.SplitAudioStallSeconds))) }
        if ($null -ne $settings.JbufWatchdogWarmupSeconds) { $numSplitAudioWarmupSeconds.Value = [decimal]([Math]::Min([int]$numSplitAudioWarmupSeconds.Maximum, [Math]::Max([int]$numSplitAudioWarmupSeconds.Minimum, [int]$settings.JbufWatchdogWarmupSeconds))) } elseif ($null -ne $settings.WatchdogWarmupSeconds) { $numSplitAudioWarmupSeconds.Value = [decimal]([Math]::Min([int]$numSplitAudioWarmupSeconds.Maximum, [Math]::Max([int]$numSplitAudioWarmupSeconds.Minimum, [int]$settings.WatchdogWarmupSeconds))) } elseif ($null -ne $settings.SplitAudioWarmupSeconds) { $numSplitAudioWarmupSeconds.Value = [decimal]([Math]::Min([int]$numSplitAudioWarmupSeconds.Maximum, [Math]::Max([int]$numSplitAudioWarmupSeconds.Minimum, [int]$settings.SplitAudioWarmupSeconds))) }
        if ($null -ne $settings.SplitAvOffsetBaselineMs) { $numSplitAvOffsetBaselineMs.Value = [decimal]([Math]::Min([int]$numSplitAvOffsetBaselineMs.Maximum, [Math]::Max([int]$numSplitAvOffsetBaselineMs.Minimum, [int]$settings.SplitAvOffsetBaselineMs))) }
        if ($null -ne $settings.SplitAvOffsetWarnMs) { $numSplitAvOffsetWarnMs.Value = [decimal]([Math]::Min([int]$numSplitAvOffsetWarnMs.Maximum, [Math]::Max([int]$numSplitAvOffsetWarnMs.Minimum, [int]$settings.SplitAvOffsetWarnMs))) }
        if ($settings.ThreadingProfile -and $cmbThreadingProfile.Items.Contains([string]$settings.ThreadingProfile)) { $cmbThreadingProfile.SelectedItem = [string]$settings.ThreadingProfile }
        if ($settings.GstProcessPriority -and $cmbGstProcessPriority.Items.Contains([string]$settings.GstProcessPriority)) { $cmbGstProcessPriority.SelectedItem = [string]$settings.GstProcessPriority }
        if ($settings.ThreadBudget -and $cmbThreadBudget.Items.Contains([string]$settings.ThreadBudget)) { $cmbThreadBudget.SelectedItem = [string]$settings.ThreadBudget }
        if ($null -ne $settings.CpuWorkerLimit) { $numCpuWorkerLimit.Value = [decimal]([Math]::Min([int]$numCpuWorkerLimit.Maximum, [Math]::Max(0, [int]$settings.CpuWorkerLimit))) }
        if ($null -ne $settings.BudgetCaptureQueue) { $chkBudgetCaptureQueue.Checked = [bool]$settings.BudgetCaptureQueue }
        if ($null -ne $settings.BudgetSenderQueue) { $chkBudgetSenderQueue.Checked = [bool]$settings.BudgetSenderQueue }
        if ($null -ne $settings.BudgetAudioInputQueue) { $chkBudgetAudioInputQueue.Checked = [bool]$settings.BudgetAudioInputQueue }
        if ($null -ne $settings.BudgetAudioFinalQueue) { $chkBudgetAudioFinalQueue.Checked = [bool]$settings.BudgetAudioFinalQueue }
        $chkBudgetSceneInputQueues.Checked = $true
        $chkBudgetSceneInputQueues.Enabled = $false
        if ($settings.QueueLeakMode -and $cmbQueueLeakMode.Items.Contains([string]$settings.QueueLeakMode)) { $cmbQueueLeakMode.SelectedItem = [string]$settings.QueueLeakMode }
        if ($null -ne $settings.CaptureQueueBuffers) { $numCaptureQueueBuffers.Value = [decimal]([Math]::Min([int]$numCaptureQueueBuffers.Maximum, [Math]::Max([int]$numCaptureQueueBuffers.Minimum, [int]$settings.CaptureQueueBuffers))) }
        if ($null -ne $settings.AudioQueueBuffers) { $numAudioQueueBuffers.Value = [decimal]([Math]::Min([int]$numAudioQueueBuffers.Maximum, [Math]::Max([int]$numAudioQueueBuffers.Minimum, [int]$settings.AudioQueueBuffers))) }
        if ($null -ne $settings.AudioQueueCapMs) { $numAudioQueueCapMs.Value = [decimal]([Math]::Min([int]$numAudioQueueCapMs.Maximum, [Math]::Max([int]$numAudioQueueCapMs.Minimum, [int]$settings.AudioQueueCapMs))) }
        if ($null -ne $settings.BufferLatenessTracer) { $chkBufferLatenessTracer.Checked = [bool]$settings.BufferLatenessTracer }
        if ($settings.GstDebugMode -and $cmbGstDebugMode.Items.Contains([string]$settings.GstDebugMode)) { $cmbGstDebugMode.SelectedItem = [string]$settings.GstDebugMode }
        if ($null -ne $settings.GstDebugSpec) { $txtGstDebugSpec.Text = [string]$settings.GstDebugSpec }
        if ($null -ne $settings.GstDebugNoColor) { $chkGstDebugNoColor.Checked = [bool]$settings.GstDebugNoColor }
        Update-GstDebugUi
        if ($null -ne $settings.SrtLatency) { $numSrtLatency.Value = [decimal]$settings.SrtLatency }
        if ($settings.RtspTransport -and $cmbRtspTransport.Items.Contains([string]$settings.RtspTransport)) { $cmbRtspTransport.SelectedItem = [string]$settings.RtspTransport }
        if ($null -ne $settings.MonitorIndex) { $numMonitor.Value = [decimal]$settings.MonitorIndex }
        if ($null -ne $settings.ShowCursor) { $chkCursor.Checked = [bool]$settings.ShowCursor }
        if ($settings.CaptureMethod -and $cmbCaptureMethod.Items.Contains([string]$settings.CaptureMethod)) {
            $cmbCaptureMethod.SelectedItem = [string]$settings.CaptureMethod
        }
        elseif ($null -ne $settings.FullscreenApp -and [bool]$settings.FullscreenApp) {
            $cmbCaptureMethod.SelectedItem = 'Fullscreen App - D3D11 / WGC'
        }
        Sync-LegacyFullscreenFlag
        Refresh-WebcamDevices
        if ($settings.ScenePreset -and $cmbScenePreset.Items.Contains([string]$settings.ScenePreset)) { $cmbScenePreset.SelectedItem = [string]$settings.ScenePreset }
        if ($settings.SceneCompositor -and $cmbSceneCompositor.Items.Contains([string]$settings.SceneCompositor)) { $cmbSceneCompositor.SelectedItem = [string]$settings.SceneCompositor }
        if ($settings.WebcamDevice -and $cmbWebcamDevice.Items.Contains([string]$settings.WebcamDevice)) { $cmbWebcamDevice.SelectedItem = [string]$settings.WebcamDevice }
        if ($settings.WebcamLayout -and $cmbWebcamLayout.Items.Contains([string]$settings.WebcamLayout)) { $cmbWebcamLayout.SelectedItem = [string]$settings.WebcamLayout }
        foreach ($sceneValue in @(
            @($settings.WebcamWidth,$numWebcamWidth), @($settings.WebcamHeight,$numWebcamHeight),
            @($settings.WebcamX,$numWebcamX), @($settings.WebcamY,$numWebcamY),
            @($settings.WebcamFps,$numWebcamFps), @($settings.WebcamOpacity,$numWebcamOpacity),
            @($settings.WebcamBorder,$numWebcamBorder),
            @($settings.SceneInputQueueBuffers,$numSceneInputQueueBuffers),
            @($settings.SceneInputQueueCapMs,$numSceneInputQueueCapMs)
        )) {
            if ($null -ne $sceneValue[0]) {
                $value = [int]$sceneValue[0]
                $sceneValue[1].Value = [decimal]([Math]::Min([int]$sceneValue[1].Maximum, [Math]::Max([int]$sceneValue[1].Minimum, $value)))
            }
        }
        if ($null -ne $settings.WebcamMirror) { $chkWebcamMirror.Checked = [bool]$settings.WebcamMirror }
        if ($null -ne $settings.WebcamAspectLock) { $chkWebcamAspectLock.Checked = [bool]$settings.WebcamAspectLock }
        Capture-WebcamAspectRatio
        if ($null -ne $settings.SceneEnabled) { $chkSceneEnabled.Checked = [bool]$settings.SceneEnabled }
        Update-SceneUi
        $loadedClockSignalingEnabled = $false
        $loadedClockSignalingKnown = $false
        if ($settings.TimingMode) {
            $loadedClockSignalingEnabled = Test-ClockSignalingValueEnabled ([string]$settings.TimingMode)
            $loadedClockSignalingKnown = $true
        }
        elseif ($settings.DirectWebRtcClockSignaling) {
            $loadedClockSignalingEnabled = Test-ClockSignalingValueEnabled ([string]$settings.DirectWebRtcClockSignaling)
            $loadedClockSignalingKnown = $true
        }
        elseif ($null -ne $settings.SendAbsoluteTimestamps) {
            $loadedClockSignalingEnabled = [bool]$settings.SendAbsoluteTimestamps
            $loadedClockSignalingKnown = $true
        }
        if ($loadedClockSignalingKnown) {
            $cmbTimingMode.SelectedItem = if ($loadedClockSignalingEnabled) { 'On / protocol clock signaling' } else { $script:DefaultTimingMode }
        }
        if ($null -ne $settings.RecordingEnabled) { $chkRecordingEnabled.Checked = [bool]$settings.RecordingEnabled }
        if ($settings.RecordingDirectory) { $txtRecordingDirectory.Text = [string]$settings.RecordingDirectory }
        if ($settings.RecordingTemplate) { $txtRecordingTemplate.Text = [string]$settings.RecordingTemplate }
        if ($settings.RecordingEncoder -and $cmbRecordingEncoder.Items.Contains([string]$settings.RecordingEncoder)) {
            $cmbRecordingEncoder.SelectedItem = [string]$settings.RecordingEncoder
        }
        if ($settings.RecordingPreset -and $cmbRecordingPreset.Items.Contains([string]$settings.RecordingPreset)) { $cmbRecordingPreset.SelectedItem = [string]$settings.RecordingPreset }
        if ($settings.RecordingProfile -and $cmbRecordingProfile.Items.Contains([string]$settings.RecordingProfile)) { $cmbRecordingProfile.SelectedItem = [string]$settings.RecordingProfile }
        if ($settings.RecordingWidth) { $numRecordingWidth.Value = [decimal]$settings.RecordingWidth }
        if ($settings.RecordingHeight) { $numRecordingHeight.Value = [decimal]$settings.RecordingHeight }
        if ($settings.RecordingFps) { $numRecordingFps.Value = [decimal]$settings.RecordingFps }
        if ($settings.RecordingVideoBitrateKbps) { $numRecordingVideoBitrate.Value = [decimal]$settings.RecordingVideoBitrateKbps }
        if ($settings.RecordingRateControl -and $cmbRecordingRateControl.Items.Contains([string]$settings.RecordingRateControl)) { $cmbRecordingRateControl.SelectedItem = [string]$settings.RecordingRateControl }
        if ($null -ne $settings.RecordingMaxVideoBitrateKbps) { $numRecordingMaxVideoBitrate.Value = [decimal]$settings.RecordingMaxVideoBitrateKbps }
        if ($null -ne $settings.RecordingConstantQp) { $numRecordingConstantQp.Value = [decimal]$settings.RecordingConstantQp }
        if ($settings.RecordingGopSeconds) { $numRecordingGopSeconds.Value = [decimal]$settings.RecordingGopSeconds }
        if ($null -ne $settings.RecordingBFrames) { $numRecordingBFrames.Value = [decimal]$settings.RecordingBFrames }
        if ($settings.RecordingTune -and $cmbRecordingTune.Items.Contains([string]$settings.RecordingTune)) { $cmbRecordingTune.SelectedItem = [string]$settings.RecordingTune }
        if ($settings.RecordingMultipass -and $cmbRecordingMultipass.Items.Contains([string]$settings.RecordingMultipass)) { $cmbRecordingMultipass.SelectedItem = [string]$settings.RecordingMultipass }
        if ($null -ne $settings.RecordingLookAhead) { $chkRecordingLookAhead.Checked = [bool]$settings.RecordingLookAhead }
        if ($settings.RecordingLookAheadFrames) { $numRecordingLookAheadFrames.Value = [decimal]$settings.RecordingLookAheadFrames }
        if ($null -ne $settings.RecordingSpatialAq) { $chkRecordingSpatialAq.Checked = [bool]$settings.RecordingSpatialAq }
        if ($null -ne $settings.RecordingTemporalAq) { $chkRecordingTemporalAq.Checked = [bool]$settings.RecordingTemporalAq }
        if ($settings.RecordingAqStrength) { $numRecordingAqStrength.Value = [decimal]$settings.RecordingAqStrength }
        if ($null -ne $settings.RecordingVbvBufferKbits) { $numRecordingVbvBuffer.Value = [decimal]$settings.RecordingVbvBufferKbits }
        if ($null -ne $settings.RecordingCustomEncoderOptions) { $txtRecordingCustomEncoderOptions.Text = [string]$settings.RecordingCustomEncoderOptions }
        if ($null -ne $settings.RecordingDesktopAudio) { $chkRecordingDesktopAudio.Checked = [bool]$settings.RecordingDesktopAudio }
        if ($null -ne $settings.RecordingMicrophone) { $chkRecordingMic.Checked = [bool]$settings.RecordingMicrophone }
        if ($settings.RecordingAudioBitrateKbps) { $numRecordingAudioBitrate.Value = [decimal]$settings.RecordingAudioBitrateKbps }
        if ($null -ne $settings.Preview) { $chkPreview.Checked = [bool]$settings.Preview }
        if ($null -ne $settings.HidePreviewDuringStream) { $chkHidePreviewDuringStream.Checked = [bool]$settings.HidePreviewDuringStream }
        if ($null -ne $settings.DynamicScenePreviews) { $chkDynamicScenePreviews.Checked = [bool]$settings.DynamicScenePreviews }
        if ($null -ne $settings.LiveSceneEditing) { $chkLiveSceneEditing.Checked = [bool]$settings.LiveSceneEditing }
        if ($null -ne $settings.StandardPreviewOffSceneTab) { $chkStandardPreviewOffSceneTab.Checked = [bool]$settings.StandardPreviewOffSceneTab }
        if ($null -ne $settings.AutoRestart) { $chkAutoRestart.Checked = [bool]$settings.AutoRestart }
        if ($null -ne $settings.Verbose) { $chkVerbose.Checked = [bool]$settings.Verbose }
        if ($null -ne $settings.DiskProcessLogging) { $chkDiskProcessLogging.Checked = [bool]$settings.DiskProcessLogging }
        if ($null -ne $settings.MinimizeToTray) { $chkMinimizeToTray.Checked = [bool]$settings.MinimizeToTray }
        if ($null -ne $settings.StartMinimized) { $chkStartMinimized.Checked = [bool]$settings.StartMinimized }
        if ($null -ne $settings.NetworkTuningEnabled) { $chkNetworkTuningEnabled.Checked = [bool]$settings.NetworkTuningEnabled }
        if ($settings.NetworkProfile -and $cmbNetworkProfile.Items.Contains([string]$settings.NetworkProfile)) { $cmbNetworkProfile.SelectedItem = [string]$settings.NetworkProfile }
        if ($null -ne $settings.NetworkDscpEnabled) { $chkNetworkDscp.Checked = [bool]$settings.NetworkDscpEnabled }
        if ($null -ne $settings.NetworkDscpValue) { $numNetworkDscp.Value = [decimal]$settings.NetworkDscpValue }
        if ($settings.NetworkQosProtocol -and $cmbNetworkQosProtocol.Items.Contains([string]$settings.NetworkQosProtocol)) { $cmbNetworkQosProtocol.SelectedItem = [string]$settings.NetworkQosProtocol }
        if ($null -ne $settings.NetworkQosPorts) { $txtNetworkPorts.Text = [string]$settings.NetworkQosPorts }
        if ($settings.NetworkUso -and $cmbNetworkUso.Items.Contains([string]$settings.NetworkUso)) { $cmbNetworkUso.SelectedItem = [string]$settings.NetworkUso }
        if ($settings.NetworkUro -and $cmbNetworkUro.Items.Contains([string]$settings.NetworkUro)) { $cmbNetworkUro.SelectedItem = [string]$settings.NetworkUro }
        if ($null -ne $settings.NetworkDisablePowerSaving) { $chkNetworkDisablePowerSaving.Checked = [bool]$settings.NetworkDisablePowerSaving }
        if ($settings.NetworkInterruptModeration -and $cmbNetworkInterruptModeration.Items.Contains([string]$settings.NetworkInterruptModeration)) { $cmbNetworkInterruptModeration.SelectedItem = [string]$settings.NetworkInterruptModeration }
        if ($null -ne $settings.NetworkDisableEee) { $chkNetworkDisableEee.Checked = [bool]$settings.NetworkDisableEee }
        if ($null -ne $settings.NetworkRestoreOnStop) { $chkNetworkRestoreOnStop.Checked = [bool]$settings.NetworkRestoreOnStop }
        if ($null -ne $settings.NetworkRestoreOnExit) { $chkNetworkRestoreOnExit.Checked = [bool]$settings.NetworkRestoreOnExit }
        if ($null -ne $settings.NetworkRecoveryTask) { $chkNetworkRecoveryTask.Checked = [bool]$settings.NetworkRecoveryTask }
        if ($settings.NetworkAdapter) {
            for ($i = 0; $i -lt $cmbNetworkAdapter.Items.Count; $i++) {
                if ([string]$cmbNetworkAdapter.Items[$i] -like "$([string]$settings.NetworkAdapter) |*") { $cmbNetworkAdapter.SelectedIndex = $i; break }
            }
        }
        if ($settings.Width) { $numWidth.Value = [decimal]$settings.Width }
        if ($settings.Height) { $numHeight.Value = [decimal]$settings.Height }
        if ($settings.Fps) { $numFps.Value = [decimal]$settings.Fps }
        if ($settings.VideoBitrateKbps) { $numVideoBitrate.Value = [decimal]$settings.VideoBitrateKbps }
        if ($settings.RateControl -and $cmbRateControl.Items.Contains([string]$settings.RateControl)) { $cmbRateControl.SelectedItem = [string]$settings.RateControl }
        if ($null -ne $settings.MaxVideoBitrateKbps) { $numMaxVideoBitrate.Value = [decimal]$settings.MaxVideoBitrateKbps }
        if ($null -ne $settings.ConstantQp) { $numConstantQp.Value = [decimal]$settings.ConstantQp }
        if ($settings.GopSeconds) { $numGopSeconds.Value = [decimal]$settings.GopSeconds }
        if ($null -ne $settings.UnifiedBridgeKeyframeGuard) { $chkUnifiedBridgeKeyframeGuard.Checked = [bool]$settings.UnifiedBridgeKeyframeGuard }
        if ($null -ne $settings.UnifiedBridgeKeyframeIntervalMs) { $numUnifiedBridgeKeyframeIntervalMs.Value = [decimal]([Math]::Min(10000, [Math]::Max(100, [int]$settings.UnifiedBridgeKeyframeIntervalMs))) }
        if ($settings.Encoder -and $cmbEncoder.Items.Contains([string]$settings.Encoder)) {
            $cmbEncoder.SelectedItem = [string]$settings.Encoder
        }
        if ($settings.Preset -and $cmbPreset.Items.Contains([string]$settings.Preset)) { $cmbPreset.SelectedItem = [string]$settings.Preset }
        if ($settings.Profile -and $cmbProfile.Items.Contains([string]$settings.Profile)) { $cmbProfile.SelectedItem = [string]$settings.Profile }
        if ($settings.EncoderTune -and $cmbEncoderTune.Items.Contains([string]$settings.EncoderTune)) { $cmbEncoderTune.SelectedItem = [string]$settings.EncoderTune }
        if ($settings.Multipass -and $cmbMultipass.Items.Contains([string]$settings.Multipass)) { $cmbMultipass.SelectedItem = [string]$settings.Multipass }
        if ($settings.VideoPipelineClockMode -and $cmbVideoPipelineClockMode.Items.Contains([string]$settings.VideoPipelineClockMode)) { $cmbVideoPipelineClockMode.SelectedItem = [string]$settings.VideoPipelineClockMode }
        if ($settings.VideoTimestampMode -and $cmbVideoTimestampMode.Items.Contains([string]$settings.VideoTimestampMode)) { $cmbVideoTimestampMode.SelectedItem = [string]$settings.VideoTimestampMode }
        if ($settings.SplitAudioPipelineClockMode -and $cmbSplitAudioPipelineClockMode.Items.Contains([string]$settings.SplitAudioPipelineClockMode)) { $cmbSplitAudioPipelineClockMode.SelectedItem = [string]$settings.SplitAudioPipelineClockMode }
        if ($settings.VideoSyncMode -and $cmbVideoSyncMode.Items.Contains([string]$settings.VideoSyncMode)) { $cmbVideoSyncMode.SelectedItem = [string]$settings.VideoSyncMode }
        if ($null -ne $settings.VbvBufferKbits) { $numVbvBuffer.Value = [decimal]$settings.VbvBufferKbits }
        if ($null -ne $settings.BFrames) { $numBFrames.Value = [decimal]$settings.BFrames }
        if ($null -ne $settings.LookAhead) { $chkLookAhead.Checked = [bool]$settings.LookAhead }
        if ($settings.LookAheadFrames) { $numLookAheadFrames.Value = [decimal]$settings.LookAheadFrames }
        if ($null -ne $settings.SpatialAq) {
            $chkAdaptiveQuantization.Checked = [bool]$settings.SpatialAq
        }
        elseif ($null -ne $settings.AdaptiveQuantization) {
            $chkAdaptiveQuantization.Checked = [bool]$settings.AdaptiveQuantization
        }
        if ($null -ne $settings.TemporalAq) { $chkTemporalAq.Checked = [bool]$settings.TemporalAq }
        if ($settings.AqStrength) { $numAqStrength.Value = [decimal]$settings.AqStrength }
        if ($null -ne $settings.CustomEncoderOptions) { $txtCustomEncoderOptions.Text = [string]$settings.CustomEncoderOptions }

        foreach ($audioSetting in @(
            @('WhipAudioCodec', 'WHIP'),
            @('GstWebRtcAudioCodec', 'GST WebRTC'),
            @('SrtAudioCodec', 'SRT'),
            @('RtmpAudioCodec', 'RTMP'),
            @('RtspAudioCodec', 'RTSP')
        )) {
            $propertyName = $audioSetting[0]
            $protocolName = $audioSetting[1]
            $value = [string]$settings.$propertyName
            if (
                -not [string]::IsNullOrWhiteSpace($value) -and
                (Test-AudioCodecProtocolCompatibility `
                    -AudioCodecName $value `
                    -Protocol $protocolName)
            ) {
                $script:ProtocolAudioCodecs[$protocolName] = $value
            }
        }

        if ($settings.AudioTransportMode -and $cmbAudioTransportMode.Items.Contains([string]$settings.AudioTransportMode)) { $cmbAudioTransportMode.SelectedItem = [string]$settings.AudioTransportMode }
        $savedAudioClockMode = [string]$settings.AudioClockMode
        if ($savedAudioClockMode -eq 'WASAPI clock') { $savedAudioClockMode = 'Plugin default / allow WASAPI clock' }
        if ($savedAudioClockMode -and $cmbAudioClockMode.Items.Contains($savedAudioClockMode)) { $cmbAudioClockMode.SelectedItem = $savedAudioClockMode }
        $savedAudioTimingMode = [string]$settings.AudioTimingMode
        if ($savedAudioTimingMode -eq 'WASAPI normal') { $savedAudioTimingMode = 'Plugin default / WASAPI normal' }
        if ($savedAudioTimingMode -and $cmbAudioTimingMode.Items.Contains($savedAudioTimingMode)) { $cmbAudioTimingMode.SelectedItem = $savedAudioTimingMode }
        if ($settings.AudioSlaveMethod -and $cmbAudioSlaveMethod.Items.Contains([string]$settings.AudioSlaveMethod)) { $cmbAudioSlaveMethod.SelectedItem = [string]$settings.AudioSlaveMethod }
        if ($settings.AudioSyncMode -and $cmbAudioSyncMode.Items.Contains([string]$settings.AudioSyncMode)) { $cmbAudioSyncMode.SelectedItem = [string]$settings.AudioSyncMode }
        if ($null -ne $settings.WasapiLowLatencyOverride) { $chkWasapiLowLatencyOverride.Checked = [bool]$settings.WasapiLowLatencyOverride }
        if ($null -ne $settings.AudioBufferOverride) { $chkAudioBufferOverride.Checked = [bool]$settings.AudioBufferOverride }
        if ($null -ne $settings.AudioBufferMs) { $numAudioBufferMs.Value = [decimal]$settings.AudioBufferMs }
        if ($null -ne $settings.AudioLatencyOverride) { $chkAudioLatencyOverride.Checked = [bool]$settings.AudioLatencyOverride }
        if ($null -ne $settings.AudioLatencyMs) { $numAudioLatencyMs.Value = [decimal]$settings.AudioLatencyMs }
        if ($null -ne $settings.AudioSampleRateOverride) { $chkAudioSampleRateOverride.Checked = [bool]$settings.AudioSampleRateOverride }
        if ($null -ne $settings.AudioSampleRateHz) { $numAudioSampleRate.Value = [decimal]$settings.AudioSampleRateHz }
        if ($null -ne $settings.DesktopAudio) { $chkDesktopAudio.Checked = [bool]$settings.DesktopAudio }
        if ($null -ne $settings.AudioMixerMode) { $chkAudioMixerMode.Checked = [bool]$settings.AudioMixerMode }
        if ($null -ne $settings.DesktopVolume) { $numDesktopVolume.Value = [decimal]$settings.DesktopVolume }
        if ($settings.DesktopAudioDevice) { Restore-AudioDeviceSelection -Kind Output -Label ([string]$settings.DesktopAudioDevice) -DeviceId ([string]$settings.DesktopAudioDeviceId) }
        if ($null -ne $settings.Microphone) { $chkMic.Checked = [bool]$settings.Microphone }
        if ($null -ne $settings.MicrophoneVolume) { $numMicVolume.Value = [decimal]$settings.MicrophoneVolume }
        if ($settings.MicrophoneDevice) { Restore-AudioDeviceSelection -Kind Input -Label ([string]$settings.MicrophoneDevice) -DeviceId ([string]$settings.MicrophoneDeviceId) }
        if ($settings.AudioBitrateKbps) { $numAudioBitrate.Value = [decimal]$settings.AudioBitrateKbps }
        if ($settings.DirectWebRtcOpusMode -and $cmbDirectWebRtcOpusMode.Items.Contains([string]$settings.DirectWebRtcOpusMode)) { $cmbDirectWebRtcOpusMode.SelectedItem = [string]$settings.DirectWebRtcOpusMode }
        if ($settings.DirectWebRtcOpusFrameMs -and $cmbDirectWebRtcOpusFrameMs.Items.Contains([string]$settings.DirectWebRtcOpusFrameMs)) { $cmbDirectWebRtcOpusFrameMs.SelectedItem = [string]$settings.DirectWebRtcOpusFrameMs }
        if ($settings.DirectWebRtcOpusAudioType -and $cmbDirectWebRtcOpusAudioType.Items.Contains([string]$settings.DirectWebRtcOpusAudioType)) { $cmbDirectWebRtcOpusAudioType.SelectedItem = [string]$settings.DirectWebRtcOpusAudioType }
        if ($null -ne $settings.DirectWebRtcOpusFec) { $chkDirectWebRtcOpusFec.Checked = [bool]$settings.DirectWebRtcOpusFec }
        if ($null -ne $settings.DirectWebRtcOpusDtx) { $chkDirectWebRtcOpusDtx.Checked = [bool]$settings.DirectWebRtcOpusDtx }

        $protocol = if ($settings.Protocol -and $cmbProtocol.Items.Contains([string]$settings.Protocol)) { [string]$settings.Protocol } else { 'WHIP' }
        $cmbProtocol.SelectedItem = $protocol
        $script:LastProtocol = $protocol
        $txtDestination.Text = [string]$script:ProtocolDestinations[$protocol]
    }
    catch {
        Append-Log "Could not load settings: $($_.Exception.Message)"
    }
    finally {
        $script:SuppressProtocolChange = $false
        $script:LoadingSettings = $false
        # Existing f13 settings can contain a stale global TimingMode and a
        # different Direct WebRTC clock-signalling value. For Direct GST WebRTC,
        # preserve the actually emitted advanced setting and reconcile the
        # global selector to it once loading is complete.
        Sync-TransportTimingControls -Source DirectWebRtc
        Update-TransportUi
        Update-DirectWebRtcUi
        Update-EncoderUi
        Update-RecordingUi
        Update-NetworkUi
        Update-SceneUi
    }
}

function Validate-Configuration {
    $gstPath = Resolve-GstLaunchSelection -RequestedPath $txtGstPath.Text -UpdateControl
    if (-not (Test-GstLaunchPath $gstPath)) {
        [System.Windows.Forms.MessageBox]::Show(
            'Select a valid gst-launch-1.0.exe path.',
            $script:AppName,
            'OK',
            'Warning'
        ) | Out-Null
        return $false
    }

    if (-not (Test-TransportEnabled) -and -not $chkRecordingEnabled.Checked -and -not $chkPreview.Checked) {
        [System.Windows.Forms.MessageBox]::Show(
            'Enable transport, recording, or preview before starting.',
            $script:AppName,
            'OK',
            'Warning'
        ) | Out-Null
        return $false
    }

    if ((Test-TransportEnabled) -and $chkStartMediaMtx.Checked -and ([string]$cmbProtocol.SelectedItem -ne $script:DirectWebRtcProtocolName)) {
        $mediaMtxPath = $txtMediaMtxPath.Text.Trim()
        if (
            [string]::IsNullOrWhiteSpace($mediaMtxPath) -or
            -not (Test-Path -LiteralPath $mediaMtxPath)
        ) {
            [System.Windows.Forms.MessageBox]::Show(
                'Select a valid mediamtx.exe path or disable MediaMTX management.',
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
            return $false
        }

        if (
            -not [System.IO.Path]::GetFileName($mediaMtxPath).Equals(
                'mediamtx.exe',
                [System.StringComparison]::OrdinalIgnoreCase
            )
        ) {
            $result = [System.Windows.Forms.MessageBox]::Show(
                "The selected MediaMTX executable is not named mediamtx.exe.`r`n`r`nContinue anyway?",
                $script:AppName,
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )

            if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
                return $false
            }
        }
    }

    if (Test-TransportEnabled) {
        $protocol = [string]$cmbProtocol.SelectedItem
        $destination = $txtDestination.Text.Trim()
    $valid = switch ($protocol) {
        'WHIP' { $destination -match '^https?://' }
        'GST WebRTC' { $destination -match '^https?://' }
        'SRT'  { $destination -match '^srt://' }
        'RTMP' { $destination -match '^rtmps?://' }
        'RTSP' { $destination -match '^rtsps?://' }
        default { $false }
    }

    if (-not $valid) {
        [System.Windows.Forms.MessageBox]::Show(
            "The destination does not match the selected $protocol protocol.",
            $script:AppName,
            'OK',
            'Warning'
        ) | Out-Null
        return $false
    }

    $definition = Get-SelectedEncoderDefinition
    $codec = [string]$definition.Codec
    if (-not (Test-CodecProtocolCompatibility -Codec $codec -Protocol $protocol)) {
        [System.Windows.Forms.MessageBox]::Show(
            "$codec is not supported by the $protocol pipeline template.`r`n`r`nSelect another encoder or protocol.",
            $script:AppName,
            'OK',
            'Warning'
        ) | Out-Null
        return $false
    }


    if (Test-DirectWebRtcSeparateMediaStreams) {
        $videoMsid = Get-DirectWebRtcMediaStreamId -Kind video
        $audioMsid = Get-DirectWebRtcMediaStreamId -Kind audio
        $validMsidPattern = '^[A-Za-z0-9_.-]+$'
        if ($videoMsid -notmatch $validMsidPattern -or $audioMsid -notmatch $validMsidPattern) {
            [System.Windows.Forms.MessageBox]::Show(
                'Video and audio MediaStream IDs may contain only letters, numbers, underscore, period, and hyphen.',
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
            return $false
        }
        if ($videoMsid.Equals($audioMsid, [System.StringComparison]::Ordinal)) {
            [System.Windows.Forms.MessageBox]::Show(
                'Separate audio/video MediaStreams requires different Video and Audio MediaStream IDs.',
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
            return $false
        }
    }

    if (Test-DirectWebRtcUnifiedPublisher) {
        if ($protocol -ne $script:DirectWebRtcProtocolName -or -not (Test-DirectWebRtcSplitAvPipelines)) {
            [System.Windows.Forms.MessageBox]::Show(
                'Unified A/V publisher requires GST WebRTC with Split A/V pipelines selected.',
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
            return $false
        }
        if ($codec -notin @('H264','H265')) {
            [System.Windows.Forms.MessageBox]::Show(
                "Unified A/V publisher currently supports H.264 and H.265 RTP bridge payloaders only. Selected codec: $codec.",
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
            return $false
        }
        if ((Get-ComboSelectedOrDefault $cmbAudioTransportMode $script:DefaultAudioTransportMode) -ne 'Normal audio' -or -not ($chkDesktopAudio.Checked -or $chkMic.Checked)) {
            [System.Windows.Forms.MessageBox]::Show(
                'Unified A/V publisher requires Normal audio with Desktop audio or Microphone enabled.',
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
            return $false
        }
        if ((Get-ComboSelectedOrDefault $cmbDirectWebRtcOpusMode $script:DefaultDirectWebRtcOpusMode) -eq 'Raw audio to webrtcsink') {
            [System.Windows.Forms.MessageBox]::Show(
                'Unified A/V publisher requires Explicit Opus encoder mode so audio can cross the local RTP bridge as Opus.',
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
            return $false
        }
        if ($chkRecordingEnabled.Checked -and ($chkRecordingDesktopAudio.Checked -or $chkRecordingMic.Checked)) {
            [System.Windows.Forms.MessageBox]::Show(
                'Unified A/V publisher lab currently supports local video-only recording. Disable Recording desktop/microphone audio so a second WASAPI source is not injected into the video capture process and allowed to contaminate this timing experiment.',
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
            return $false
        }
        if ([int]$numDirectWebRtcBridgeVideoPort.Value -eq [int]$numDirectWebRtcBridgeAudioPort.Value) {
            [System.Windows.Forms.MessageBox]::Show(
                'Video and audio RTP bridge ports must be different.',
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
            return $false
        }
    }

    if ($chkDesktopAudio.Checked -or $chkMic.Checked) {
        $audioCodecName = [string]$cmbAudioCodec.SelectedItem
        if (
            -not (Test-AudioCodecProtocolCompatibility `
                -AudioCodecName $audioCodecName `
                -Protocol $protocol)
        ) {
            [System.Windows.Forms.MessageBox]::Show(
                "$audioCodecName is not compatible with $protocol.",
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
            return $false
        }
    }

    if (
        $protocol -in @('WHIP', 'GST WebRTC') -and
        $codec -eq 'H264' -and
        $numBFrames.Enabled -and
        [int]$numBFrames.Value -gt 0
    ) {
        [System.Windows.Forms.MessageBox]::Show(
            'H.264 B-frames are not compatible with normal WebRTC playback. Set B-frames to 0 for WebRTC.',
            $script:AppName,
            'OK',
            'Warning'
        ) | Out-Null
        return $false
    }

    if ($protocol -eq 'RTMP' -and $codec -in @('H265', 'AV1')) {
        $result = [System.Windows.Forms.MessageBox]::Show(
            "$codec over RTMP uses Enhanced RTMP / eflvmux. The destination server and viewers must support that extension.`r`n`r`nContinue?",
            $script:AppName,
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
            return $false
        }
    }
    }

    if ($chkRecordingEnabled.Checked) {
        try {
            $script:ResolvedRecordingPath = Resolve-RecordingFilePath -EnsureDirectory -AvoidExisting
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Recording output could not be prepared.`r`n`r`n$($_.Exception.Message)",
                $script:AppName,
                'OK',
                'Warning'
            ) | Out-Null
            return $false
        }
    }
    else {
        $script:ResolvedRecordingPath = ''
    }

    return $true
}


function Ensure-PreviewParkingWindow {
    if ($script:PreviewParkForm -and -not $script:PreviewParkForm.IsDisposed) {
        return $script:PreviewParkForm
    }

    $park = New-Object System.Windows.Forms.Form
    $park.Text = 'GStreamer Glass Preview Parking'
    $park.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $park.ShowInTaskbar = $false
    $park.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $park.Location = New-Object System.Drawing.Point(-32000, -32000)
    $park.Size = New-Object System.Drawing.Size(16, 16)
    $park.Opacity = 0.01
    $park.TopMost = $false

    # Keep this window visible. Hiding/minimizing the parent is what makes the
    # d3d11videosink preview come back black on some Windows systems.
    $park.Show()
    $script:PreviewParkForm = $park
    return $script:PreviewParkForm
}

function Park-PreviewWindow {
    if ($script:PreviewHwnd -eq [IntPtr]::Zero) {
        return
    }

    try {
        $park = Ensure-PreviewParkingWindow
        [void][GstPreviewNative]::ReparentEmbeddedWindow(
            $script:PreviewHwnd,
            $park.Handle,
            16,
            16,
            $true
        )
        $script:PreviewParked = $true
        Reset-PreviewAppliedState
    }
    catch {}
}

function Restore-PreviewWindowFromParking {
    if ($script:PreviewHwnd -eq [IntPtr]::Zero) {
        return
    }

    try {
        [void][GstPreviewNative]::ReparentEmbeddedWindow(
            $script:PreviewHwnd,
            $previewPanel.Handle,
            $previewPanel.ClientSize.Width,
            $previewPanel.ClientSize.Height,
            (Test-PreviewVisibleNow)
        )
        $script:PreviewParked = $false
        Reset-PreviewAppliedState
    }
    catch {}
}

function Reset-PreviewAppliedState {
    # Anything that reparents, hides, or replaces the embedded renderer window
    # invalidates what we believe we last pushed to it, so force the next
    # Set-PreviewVisibility to re-apply geometry and visibility.
    $script:PreviewAppliedSize = [System.Drawing.Size]::Empty
    $script:PreviewAppliedVisible = $null
}

function Set-PreviewVisibility {
    $formIsHiddenForTray =
        (-not $form.Visible) -or
        ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized)

    if ($script:PreviewHwnd -eq [IntPtr]::Zero) {
        $previewPlaceholder.Visible = $true
        $previewPlaceholder.Text = if ($formIsHiddenForTray) {
            'Preview parked while app is in tray'
        }
        elseif (Test-PreviewVisibleNow) {
            'Preview starting...'
        }
        else {
            'Preview hidden - stream still running'
        }
        return
    }

    if ($formIsHiddenForTray) {
        Park-PreviewWindow
        $previewPlaceholder.Visible = $true
        $previewPlaceholder.Text = 'Preview parked while app is in tray'
        return
    }

    if ($script:PreviewParked) {
        Restore-PreviewWindowFromParking
    }

    if (Test-PreviewVisibleNow) {
        # Only touch the renderer window when something actually changed. This runs
        # every poll tick; unconditional resize/show on a live d3d11videosink is a
        # stutter source.
        $clientSize = $previewPanel.ClientSize
        if (
            $clientSize.Width -ne $script:PreviewAppliedSize.Width -or
            $clientSize.Height -ne $script:PreviewAppliedSize.Height
        ) {
            [GstPreviewNative]::ResizeEmbeddedWindow(
                $script:PreviewHwnd,
                $clientSize.Width,
                $clientSize.Height
            )
            $script:PreviewAppliedSize = $clientSize
        }

        if ($script:PreviewAppliedVisible -ne $true) {
            [GstPreviewNative]::SetWindowVisible($script:PreviewHwnd, $true)
            $script:PreviewAppliedVisible = $true
        }

        $previewPlaceholder.Visible = $false
    }
    else {
        if ($script:PreviewAppliedVisible -ne $false) {
            [GstPreviewNative]::SetWindowVisible($script:PreviewHwnd, $false)
            $script:PreviewAppliedVisible = $false
        }

        $previewPlaceholder.Visible = $true
        $previewPlaceholder.Text = if ($chkHidePreviewDuringStream -and $chkHidePreviewDuringStream.Checked -and (Test-TransportEnabled)) {
            'Preview hidden during stream'
        }
        else {
            'Preview hidden - stream still running'
        }
    }
}

function Try-AttachPreview {
    if ($script:ControlledLiveStreamActive) {
        Sync-ControlledLivePreviewLayout
        return
    }

    if ($script:DynamicScenePreviewActive) {
        Try-AttachDynamicScenePreview
        return
    }

    $previewProcess = if ((Test-DirectWebRtcUnifiedPublisher) -and $script:GstVideoProcess) { $script:GstVideoProcess } else { $script:GstProcess }
    if (-not $script:PipelineHasPreview -or -not $previewProcess -or $previewProcess.HasExited) {
        return
    }

    if ($script:PreviewHwnd -eq [IntPtr]::Zero) {
        $candidate = [GstPreviewNative]::FindPreviewWindow($previewProcess.Id)
        if ($candidate -ne [IntPtr]::Zero) {
            if ([GstPreviewNative]::EmbedWindow($candidate, $previewPanel.Handle, $previewPanel.ClientSize.Width, $previewPanel.ClientSize.Height)) {
                $script:PreviewHwnd = $candidate
                $script:PreviewParked = $false
                Reset-PreviewAppliedState
                Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Preview window embedded for runtime toggle."
            }
        }
    }

    Set-PreviewVisibility
}

function Test-UseDynamicScenePreview {
    try {
        if (-not (Test-DynamicScenePreviewWanted)) { return $false }
        return (
            -not $script:ControlledLiveStreamActive -and
            -not ($script:GstProcess -and -not $script:GstProcess.HasExited)
        )
    }
    catch {
        return $false
    }
}

function Test-DynamicScenePreviewWanted {
    try {
        $dynamicPreviewContextAllowed = (
            $script:SceneWorkspaceActive -or
            ($chkStandardPreviewOffSceneTab -and -not $chkStandardPreviewOffSceneTab.Checked)
        )

        return (
            $dynamicPreviewContextAllowed -and
            $script:DynamicPreviewUiReady -and
            -not $script:SuppressDynamicScenePreview -and
            $chkDynamicScenePreviews -and $chkDynamicScenePreviews.Checked -and
            $chkSceneEnabled -and $chkSceneEnabled.Checked -and
            $chkPreview -and $chkPreview.Checked -and
            (Test-StandalonePreviewAllowed)
        )
    }
    catch {
        return $false
    }
}

function ConvertTo-InProcessGstLaunchDescription {
    param([Parameter(Mandatory)][string]$Description)

    # -e/-v are gst-launch executable switches, not pipeline grammar.
    $pipeline = [regex]::Replace(
        $Description,
        '^\s*(?:(?:-e|-v)\s+)+',
        ''
    )
    # Build-* emits quoted caps so Windows command-line parsing passes each caps
    # expression to gst-launch as one argument. gst_parse_launch receives the
    # description directly, so those shell-only quote characters must not be
    # present. Preserve quotes on paths/string properties and unwrap caps only.
    return [regex]::Replace(
        $pipeline,
        '"((?:audio|video|application)/[^"]+)"',
        '$1'
    )
}

function Build-ControlledScenePreviewPipeline {
    $sceneChain = Build-SceneCaptureChain -LocalOnly
    $pipeline = "$sceneChain ! queue max-size-buffers=1 max-size-bytes=0 max-size-time=0 leaky=downstream ! d3d11videosink name=controlledpreview sync=false force-aspect-ratio=true"
    return (ConvertTo-InProcessGstLaunchDescription -Description $pipeline)
}

function Test-ControlledLiveWorkerRunning {
    return (
        $script:ControlledLiveStreamActive -and
        $script:GstProcess -and
        -not $script:GstProcess.HasExited -and
        $script:ControlledLiveWorkerWriter
    )
}

function Close-ControlledLiveWorkerPipe {
    try { if ($script:ControlledLiveWorkerWriter) { $script:ControlledLiveWorkerWriter.Dispose() } } catch {}
    try { if ($script:ControlledLiveWorkerReader) { $script:ControlledLiveWorkerReader.Dispose() } } catch {}
    try { if ($script:ControlledLiveWorkerPipe) { $script:ControlledLiveWorkerPipe.Dispose() } } catch {}
    $script:ControlledLiveWorkerWriter = $null
    $script:ControlledLiveWorkerReader = $null
    $script:ControlledLiveWorkerPipe = $null
}

function Send-ControlledLiveWorkerCommand {
    param([Parameter(Mandatory)][hashtable]$Command)

    if (-not (Test-ControlledLiveWorkerRunning)) { return $false }
    try {
        $script:ControlledLiveWorkerWriter.WriteLine(($Command | ConvertTo-Json -Compress))
        return $true
    }
    catch {
        Append-Log "Controlled live worker command failed: $($_.Exception.Message)"
        return $false
    }
}

function Start-ControlledLiveWorker {
    param(
        [Parameter(Mandatory)][string]$Pipeline,
        [Parameter(Mandatory)][IntPtr]$WindowHandle,
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height
    )

    Close-ControlledLiveWorkerPipe
    $pipeName = "gstglass-live-$PID-$([Guid]::NewGuid().ToString('N'))"
    $process = $null
    $pipe = $null
    $reader = $null
    $writer = $null

    try {
        $currentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
        $currentExe = $currentProcess.MainModule.FileName
        $currentName = [System.IO.Path]::GetFileNameWithoutExtension($currentExe)
        if ($currentName -match '^(powershell|pwsh|powershell_ise)$') {
            if ([string]::IsNullOrWhiteSpace($PSCommandPath) -or -not (Test-Path -LiteralPath $PSCommandPath)) {
                throw 'The current script path is unavailable; the controlled worker cannot be launched.'
            }
            $escapedScript = $PSCommandPath.Replace('"', '\"')
            $arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$escapedScript`" -ControlledLiveWorker -ControlledLiveWorkerPipe `"$pipeName`""
        }
        else {
            # PS2EXE/PS12EXE builds can relaunch their own executable and use
            # the same hidden worker switch handled near the top of this file.
            $arguments = "-ControlledLiveWorker -ControlledLiveWorkerPipe `"$pipeName`""
        }

        $startParams = @{
            FilePath    = $currentExe
            ArgumentList = $arguments
            WindowStyle = 'Hidden'
            PassThru    = $true
        }
        if (Test-ProcessDiskLoggingEnabled) {
            $startParams.RedirectStandardOutput = $script:StdOutPath
            $startParams.RedirectStandardError = $script:StdErrPath
        }
        $process = Start-Process @startParams
        Set-GstProcessPriority -Process $process
        if ($script:JobHandle -ne [IntPtr]::Zero) {
            try { [GstProcessJob]::AssignProcess($script:JobHandle, $process.Handle) }
            catch { Append-Log "WARNING: Controlled live worker could not be assigned to the kill-on-close job: $($_.Exception.Message)" }
        }

        $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(
            '.',
            $pipeName,
            [System.IO.Pipes.PipeDirection]::InOut,
            [System.IO.Pipes.PipeOptions]::None
        )
        $pipe.Connect(12000)
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $reader = New-Object System.IO.StreamReader($pipe, $utf8, $false, 4096, $true)
        $writer = New-Object System.IO.StreamWriter($pipe, $utf8, 4096, $true)
        $writer.AutoFlush = $true
        $writer.WriteLine((@{
            Type         = 'Start'
            Pipeline     = $Pipeline
            # Let d3d11videosink create a worker-owned window, then embed that
            # HWND with the same Win32 path as every external gst-launch preview.
            WindowHandle = [int64]0
            Width        = [Math]::Max(1, $Width)
            Height       = [Math]::Max(1, $Height)
            DesktopPad   = 'sink_0'
            WebcamPad    = 'sink_1'
        } | ConvertTo-Json -Compress))

        $replyTask = $reader.ReadLineAsync()
        if (-not $replyTask.Wait(15000)) { throw 'The controlled live worker did not acknowledge startup within 15 seconds.' }
        $replyLine = $replyTask.Result
        if ([string]::IsNullOrWhiteSpace($replyLine)) { throw 'The controlled live worker exited before acknowledging startup.' }
        $reply = $replyLine | ConvertFrom-Json
        if ([string]$reply.Status -ne 'Ready') { throw "Controlled live worker start failed: $([string]$reply.Error)" }

        $script:ControlledLiveWorkerPipe = $pipe
        $script:ControlledLiveWorkerReader = $reader
        $script:ControlledLiveWorkerWriter = $writer
        $script:GstProcess = $process
        return $true
    }
    catch {
        try { if ($process -and -not $process.HasExited) { Stop-ProcessTreeById -ProcessId $process.Id } } catch {}
        try { if ($writer) { $writer.Dispose() } } catch {}
        try { if ($reader) { $reader.Dispose() } } catch {}
        try { if ($pipe) { $pipe.Dispose() } } catch {}
        try { if ($process) { $process.Dispose() } } catch {}
        throw
    }
}

function Test-ControlledSceneMutationActive {
    if ($script:ControlledLiveStreamActive) { return [bool](Test-ControlledLiveWorkerRunning) }
    return ($script:DynamicScenePreviewActive -and [GstControlledScenePreview]::IsRunning)
}

function Test-ControlledLiveStreamRequested {
    param([switch]$PreviewOnly)

    try {
        if ($PreviewOnly) { return $false }
        if ($script:SuppressControlledLiveStream) { return $false }
        if (-not $script:DynamicPreviewUiReady) { return $false }
        if (-not $chkLiveSceneEditing -or -not $chkLiveSceneEditing.Checked) { return $false }
        if (-not $chkDynamicScenePreviews -or -not $chkDynamicScenePreviews.Checked) { return $false }
        if (-not $chkSceneEnabled -or -not $chkSceneEnabled.Checked) { return $false }
        if ([string]$cmbScenePreset.SelectedItem -ne 'Desktop + webcam') { return $false }
        if (-not $chkPreview -or -not $chkPreview.Checked) { return $false }
        if (Test-FullscreenCaptureMode) { return $false }

        # Unified-publisher and split-A/V modes have the scene capture in a
        # different process from the primary pipeline. Keep their proven process
        # topology until each bridge is migrated deliberately.
        if (Test-DirectWebRtcUnifiedPublisher) { return $false }
        if (Test-DirectWebRtcSplitAvPipelines) { return $false }
        return $true
    }
    catch {
        return $false
    }
}

function Start-DynamicScenePreview {
    if ($script:DynamicScenePreviewActive -or $script:DynamicScenePreviewStarting) { return $true }
    if (-not (Test-UseDynamicScenePreview)) { return $false }

    $script:DynamicScenePreviewStarting = $true
    try {
        Reset-DynamicScenePreviewFallback
        Stop-GstStream
        $script:DynamicScenePreviewActive = $true
        $script:DynamicScenePreviewStartedAt = Get-Date
        $script:PreviewOnlyMode = $true
        $script:PipelineHasPreview = $false
        $script:PreviewHwnd = [IntPtr]::Zero
        Reset-PreviewAppliedState

        # The old implementation launched one sink window per source and stacked
        # those HWNDs. f70 renders the actual scene compositor into one canvas.
        $sceneDesktopPreviewPanel.Visible = $true
        $sceneWebcamPreviewPanel.Visible = $false
        $lblSceneDesktop.Visible = $false
        $script:SceneDesktopPreviewHwnd = [IntPtr]::Zero
        $script:SceneWebcamPreviewHwnd = [IntPtr]::Zero
        $script:SceneDesktopPreviewProcess = $null
        $script:SceneWebcamPreviewProcess = $null

        if (-not $script:SceneWorkspaceActive -and $chkStandardPreviewOffSceneTab -and -not $chkStandardPreviewOffSceneTab.Checked) {
            Show-DynamicScenePreviewInPreviewCard
        }

        Update-SceneCanvasFromValues
        Update-SceneSelectionChrome

        $gstPath = Resolve-GstLaunchSelection -RequestedPath $txtGstPath.Text -UpdateControl
        Prepare-GStreamerRuntime -GstPath $gstPath
        $binDirectory = Split-Path -Parent (Normalize-GstLaunchPath $gstPath)
        $nativeRuntime = Join-Path $binDirectory 'gstreamer-1.0-0.dll'
        if (-not (Test-Path -LiteralPath $nativeRuntime)) {
            throw "The selected GStreamer runtime does not contain gstreamer-1.0-0.dll: $binDirectory"
        }

        $pipeline = Build-ControlledScenePreviewPipeline
        $preset = [string]$cmbScenePreset.SelectedItem
        $desktopPadName = if ($preset -eq 'Desktop + webcam') { 'sink_0' } else { '' }
        $webcamPadName = if ($preset -eq 'Desktop + webcam') { 'sink_1' } else { '' }
        $null = $sceneDesktopPreviewPanel.Handle
        Append-Log "Controlled scene preview pipeline: $pipeline"
        [GstControlledScenePreview]::Start(
            $pipeline,
            $sceneDesktopPreviewPanel.Handle.ToInt64(),
            $sceneDesktopPreviewPanel.ClientSize.Width,
            $sceneDesktopPreviewPanel.ClientSize.Height,
            $desktopPadName,
            $webcamPadName
        )
        $script:ControlledScenePreviewSurfaceHwnd = $sceneDesktopPreviewPanel.Handle
        $script:ControlledScenePreviewAppliedSize = $sceneDesktopPreviewPanel.ClientSize
        Sync-ControlledScenePreviewProperties

        $statusLabel.Text = 'Controlled scene preview'
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkGreen
        Set-RunState $true
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Controlled scene compositor started; geometry and opacity are live."
        return $true
    }
    catch {
        Append-Log "Controlled scene preview start error: $($_.Exception.Message)"
        $script:SuppressDynamicScenePreview = $true
        Stop-DynamicScenePreview -Quiet

        # A failed parse can still construct and then tear down a partial graph.
        # Give Windows capture backends a bounded release window before the
        # external normal-preview fallback opens the same desktop/camera again.
        [System.Threading.Thread]::Sleep(750)
        return $false
    }
    finally {
        $script:DynamicScenePreviewStarting = $false
    }
}

function Stop-DynamicScenePreview {
    param([switch]$Quiet)

    $hadDynamic = [bool]$script:DynamicScenePreviewActive

    if ([GstControlledScenePreview]::IsRunning) {
        if (-not $Quiet) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Stopping controlled scene compositor..."
        }
        try { [GstControlledScenePreview]::Stop() } catch {
            Append-Log "Controlled scene preview stop warning: $($_.Exception.Message)"
        }
    }

    $script:SceneDesktopPreviewProcess = $null
    $script:SceneWebcamPreviewProcess = $null
    $script:SceneDesktopPreviewHwnd = [IntPtr]::Zero
    $script:SceneWebcamPreviewHwnd = [IntPtr]::Zero
    $script:DynamicScenePreviewActive = $false
    $script:DynamicScenePreviewStarting = $false
    $script:DynamicScenePreviewStartedAt = $null
    $script:PreviewOnlyMode = $false
    $script:ControlledScenePreviewSurfaceHwnd = [IntPtr]::Zero
    $script:ControlledScenePreviewAppliedSize = [System.Drawing.Size]::Empty

    if ($sceneDesktopPreviewPanel) { $sceneDesktopPreviewPanel.Visible = $false }
    if ($sceneWebcamPreviewPanel) { $sceneWebcamPreviewPanel.Visible = $false }
    if ($lblSceneDesktop) { $lblSceneDesktop.Visible = $true }
    if ($script:SceneEditorCanvasHostedInPreview) { Restore-SceneEditorCanvasHome }
    Update-SceneSelectionChrome

    if ($hadDynamic -and -not $Quiet) {
        $statusLabel.Text = 'Stopped'
        $statusLabel.ForeColor = [System.Drawing.Color]::Black
        Set-RunState $false
    }
}

function Try-AttachDynamicScenePreview {
    if (-not $script:DynamicScenePreviewActive) { return }
    Sync-DynamicScenePreviewLayout
}

function Test-DynamicScenePreviewAttached {
    return ($script:DynamicScenePreviewActive -and [GstControlledScenePreview]::IsRunning)
}

function Invoke-DynamicScenePreviewFallback {
    param([string]$Reason = 'reported a pipeline error')

    if (-not $script:DynamicScenePreviewActive) { return }
    if ($script:DynamicScenePreviewFallbackTriggered) { return }

    $script:DynamicScenePreviewFallbackTriggered = $true
    $script:SuppressDynamicScenePreview = $true

    Append-Log (
        "[$(Get-Date -Format 'HH:mm:ss')] Dynamic scene preview $Reason; " +
        'falling back to the normal composed preview in the scene editor. ' +
        'Scene objects will not redraw dynamically until Dynamic previews is retried.'
    )

    Stop-DynamicScenePreview -Quiet
    $script:PreviewOnlyMode = $false
    $script:PreviewHwnd = [IntPtr]::Zero
    Reset-PreviewAppliedState

    if ($previewPlaceholder) {
        $previewPlaceholder.Text = 'Dynamic preview fallback: normal composed preview'
        $previewPlaceholder.Visible = $true
    }

    if ($sceneDesktopPreviewPanel) { $sceneDesktopPreviewPanel.Visible = $false }
    if ($sceneWebcamPreviewPanel) { $sceneWebcamPreviewPanel.Visible = $false }
    Update-SceneCanvasFromValues

    if ($chkPreview -and $chkPreview.Checked -and (Test-StandalonePreviewAllowed)) {
        Sync-StandalonePreviewState -Quiet
    }
}

function Sync-DynamicScenePreviewLayout {
    if (-not $script:DynamicScenePreviewActive) { return }

    try {
        if ([GstControlledScenePreview]::IsRunning -and $sceneDesktopPreviewPanel -and $sceneDesktopPreviewPanel.IsHandleCreated) {
            $surfaceHandle = $sceneDesktopPreviewPanel.Handle
            $surfaceSize = $sceneDesktopPreviewPanel.ClientSize
            if (
                $surfaceHandle -ne $script:ControlledScenePreviewSurfaceHwnd -or
                $surfaceSize.Width -ne $script:ControlledScenePreviewAppliedSize.Width -or
                $surfaceSize.Height -ne $script:ControlledScenePreviewAppliedSize.Height
            ) {
                [GstControlledScenePreview]::SetWindowHandle(
                    $surfaceHandle.ToInt64(),
                    $surfaceSize.Width,
                    $surfaceSize.Height
                )
                $script:ControlledScenePreviewSurfaceHwnd = $surfaceHandle
                $script:ControlledScenePreviewAppliedSize = $surfaceSize
            }
        }
    }
    catch {}
}

function Sync-ControlledLivePreviewLayout {
    if (-not $script:ControlledLiveStreamActive) { return }
    if (-not (Test-ControlledLiveWorkerRunning)) { return }

    try {
        if ($script:PreviewHwnd -eq [IntPtr]::Zero) {
            $candidate = [GstPreviewNative]::FindPreviewWindow($script:GstProcess.Id)
            if ($candidate -ne [IntPtr]::Zero) {
                if ([GstPreviewNative]::EmbedWindow(
                    $candidate,
                    $previewPanel.Handle,
                    $previewPanel.ClientSize.Width,
                    $previewPanel.ClientSize.Height
                )) {
                    $script:PreviewHwnd = $candidate
                    $script:PreviewParked = $false
                    Reset-PreviewAppliedState
                    Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Controlled worker preview window embedded."
                }
            }
        }

        # From this point forward use the proven external-preview reparent,
        # parking, visibility, and resize path rather than cross-process overlay
        # handle mutation.
        Set-PreviewVisibility
    }
    catch {}
}

function Restart-DynamicScenePreviewIfActive {
    if ($script:ControlledLiveStreamActive) {
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] A scene source setting changed; restarting the live pipeline to rebuild its capture graph."
        Stop-GstStream -Restart
        return
    }
    if (-not $script:DynamicScenePreviewActive) { return }
    Stop-DynamicScenePreview -Quiet
    Sync-StandalonePreviewState -Quiet
}

function Read-MediaMtxStartupLogs {
    $stdoutText = Read-NewLogText `
        -Path $script:MediaMtxStdOutPath `
        -Position ([ref]$script:MediaMtxStdOutPosition)

    if ($stdoutText) {
        Append-Log $stdoutText
    }

    $stderrText = Read-NewLogText `
        -Path $script:MediaMtxStdErrPath `
        -Position ([ref]$script:MediaMtxStdErrPosition)

    if ($stderrText) {
        Append-Log $stderrText
    }
}

function Start-ManagedMediaMtx {
    if ((-not (Test-TransportEnabled)) -or -not $chkStartMediaMtx.Checked -or ([string]$cmbProtocol.SelectedItem -eq $script:DirectWebRtcProtocolName)) {
        return $true
    }

    if ($script:MediaMtxProcess -and -not $script:MediaMtxProcess.HasExited) {
        return $true
    }

    $mediaMtxPath = $txtMediaMtxPath.Text.Trim()
    $script:MediaMtxPathInUse = [System.IO.Path]::GetFullPath($mediaMtxPath)

    $processDiskLogging = Test-ProcessDiskLoggingEnabled
    $script:MediaMtxStdOutPath = $null
    $script:MediaMtxStdErrPath = $null
    $script:MediaMtxStdOutPosition = [int64]0
    $script:MediaMtxStdErrPosition = [int64]0

    if ($processDiskLogging) {
        Ensure-ProcessLogDirectory
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
        $script:MediaMtxStdOutPath = Join-Path $script:LogDirectory "mediamtx-$stamp-out.log"
        $script:MediaMtxStdErrPath = Join-Path $script:LogDirectory "mediamtx-$stamp-err.log"
    }

    $workingDirectory = Split-Path -Parent $script:MediaMtxPathInUse

    Append-Log (
        "[$(Get-Date -Format 'HH:mm:ss')] Starting managed MediaMTX..."
    )
    Append-Log "MediaMTX executable: $($script:MediaMtxPathInUse)"
    Append-Log "MediaMTX working directory: $workingDirectory"

    try {
        if ($processDiskLogging) {
            $script:MediaMtxProcess = Start-Process `
                -FilePath $script:MediaMtxPathInUse `
                -WorkingDirectory $workingDirectory `
                -RedirectStandardOutput $script:MediaMtxStdOutPath `
                -RedirectStandardError $script:MediaMtxStdErrPath `
                -WindowStyle Hidden `
                -PassThru
        }
        else {
            $script:MediaMtxProcess = Start-Process `
                -FilePath $script:MediaMtxPathInUse `
                -WorkingDirectory $workingDirectory `
                -WindowStyle Hidden `
                -PassThru
        }

        if ($script:JobHandle -ne [IntPtr]::Zero) {
            try {
                [GstProcessJob]::AssignProcess(
                    $script:JobHandle,
                    $script:MediaMtxProcess.Handle
                )
            }
            catch {
                Append-Log (
                    'WARNING: MediaMTX could not be assigned to the ' +
                    "kill-on-close job: $($_.Exception.Message)"
                )
            }
        }

        Save-ActiveProcessState

        # Give MediaMTX enough time to bind listeners and fail visibly if its
        # configuration or ports are invalid. Keep the WinForms UI responsive.
        $deadline = (Get-Date).AddMilliseconds(900)
        while ((Get-Date) -lt $deadline) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 50
            $script:MediaMtxProcess.Refresh()

            if ($script:MediaMtxProcess.HasExited) {
                break
            }
        }

        if ($processDiskLogging) {
            Read-MediaMtxStartupLogs
        }

        if ($script:MediaMtxProcess.HasExited) {
            $exitCode = $script:MediaMtxProcess.ExitCode
            Append-Log "MediaMTX exited during startup with code $exitCode."
            try { $script:MediaMtxProcess.Dispose() } catch {}
            $script:MediaMtxProcess = $null
            $script:MediaMtxPathInUse = ''
            Remove-ActiveProcessState
            return $false
        }

        Append-Log (
            "MediaMTX is running - PID $($script:MediaMtxProcess.Id)."
        )
        return $true
    }
    catch {
        Append-Log "MEDIAMTX START ERROR: $($_.Exception.Message)"
        try {
            if (
                $script:MediaMtxProcess -and
                -not $script:MediaMtxProcess.HasExited
            ) {
                Stop-ProcessTreeById -ProcessId $script:MediaMtxProcess.Id
            }
        }
        catch {}

        try { $script:MediaMtxProcess.Dispose() } catch {}
        $script:MediaMtxProcess = $null
        $script:MediaMtxPathInUse = ''
        Remove-ActiveProcessState
        return $false
    }
}

function Stop-ManagedMediaMtx {
    param([switch]$Quiet)

    if ($script:MediaMtxProcess -and -not $script:MediaMtxProcess.HasExited) {
        if (-not $Quiet) {
            Append-Log (
                "[$(Get-Date -Format 'HH:mm:ss')] Stopping managed MediaMTX " +
                "process tree - PID $($script:MediaMtxProcess.Id)..."
            )
        }

        Stop-ProcessTreeById -ProcessId $script:MediaMtxProcess.Id
        try {
            $script:MediaMtxProcess.WaitForExit(3000) | Out-Null
        }
        catch {}
    }

    try {
        if ($script:MediaMtxProcess) {
            $script:MediaMtxProcess.Dispose()
        }
    }
    catch {}

    $script:MediaMtxProcess = $null
    $script:MediaMtxPathInUse = ''
}

function Start-GstStream {
    param(
        [switch]$Automatic,
        [switch]$PreviewOnly
    )

    if ($script:ControlledLiveStreamActive) { return }

    if ($script:DynamicScenePreviewActive) {
        if ($PreviewOnly) { return }
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Going live: stopping dynamic scene preview and starting the configured stream."
        Stop-DynamicScenePreview -Quiet
    }

    if ($PreviewOnly -and (Test-UseDynamicScenePreview)) {
        if (Start-DynamicScenePreview) { return }
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Controlled scene preview failed; continuing with the normal composed preview fallback."
    }

    if ($script:GstProcess -and -not $script:GstProcess.HasExited) {
        if ($script:PreviewOnlyMode -and -not $PreviewOnly) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Going live: stopping local preview and starting the configured stream."
            Stop-GstStream -Restart
        }
        return
    }

    $script:ForceLocalPreviewMode = [bool]$PreviewOnly

    if (-not (Validate-Configuration)) {
        $script:WaitingForFullscreen = $false
        $script:RestartAt = $null
        $script:PreviewOnlyMode = $false
        $script:ForceLocalPreviewMode = $false
        Set-RunState $false
        return
    }

    Stop-StaleManagedProcesses

    if (-not (Resolve-FullscreenCaptureTarget -Quiet)) {
        $firstWait = -not $script:WaitingForFullscreen
        $script:WaitingForFullscreen = $true
        $script:StopRequested = $false
        $script:RestartAt = (Get-Date).AddSeconds(2)
        $statusLabel.Text = 'Waiting for a fullscreen application'
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
        Set-WaitingForFullscreenState
        if ($firstWait) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] No fullscreen application is active; waiting and retrying every 2 seconds."
        }
        $script:PreviewOnlyMode = $false
        $script:ForceLocalPreviewMode = $false
        return
    }

    if ($script:WaitingForFullscreen) {
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Fullscreen application detected: '$($script:CaptureWindowTitle)'."
    }
    $script:WaitingForFullscreen = $false

    Save-Settings

    Reset-ProcessLogPaths
    $processDiskLogging = Test-ProcessDiskLoggingEnabled
    if ($processDiskLogging) {
        Ensure-ProcessLogDirectory
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
        $script:StdOutPath = Join-Path $script:LogDirectory "gst-$stamp-out.log"
        $script:StdErrPath = Join-Path $script:LogDirectory "gst-$stamp-err.log"
        $script:StdOutVideoPath = Join-Path $script:LogDirectory "gst-video-$stamp-out.log"
        $script:StdErrVideoPath = Join-Path $script:LogDirectory "gst-video-$stamp-err.log"
        $script:StdOutAudioPath = Join-Path $script:LogDirectory "gst-audio-$stamp-out.log"
        $script:StdErrAudioPath = Join-Path $script:LogDirectory "gst-audio-$stamp-err.log"
    }
    $script:StopRequested = $false
    $script:RestartAt = $null
    $script:PreviewHwnd = [IntPtr]::Zero
    $script:PreviewParked = $false
    Reset-PreviewAppliedState
    $controlledLiveRequested = [bool](Test-ControlledLiveStreamRequested -PreviewOnly:$PreviewOnly)
    $script:ForceLiveScenePreviewBranch = $controlledLiveRequested
    try { $script:PipelineHasPreview = Test-PreviewEnabledForCurrentPipeline }
    finally { $script:ForceLiveScenePreviewBranch = $false }
    $script:PreviewOnlyMode = [bool]$PreviewOnly
    $previewPlaceholder.Visible = $true
    $previewPlaceholder.Text = if ($script:PipelineHasPreview) { 'Starting preview...' } else { 'Preview disabled for this pipeline' }

    if (-not (Apply-NetworkTuningForSession)) {
        $statusLabel.Text = 'Network tuning failed'
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkRed
        $script:PreviewOnlyMode = $false
        $script:ForceLocalPreviewMode = $false
        Set-RunState $false
        return
    }

    $gstPath = Resolve-GstLaunchSelection -RequestedPath $txtGstPath.Text -UpdateControl
    Prepare-GStreamerRuntime -GstPath $gstPath
    Initialize-GstJob

    if (-not (Start-ManagedMediaMtx)) {
        if ($chkNetworkRestoreOnStop.Checked) { Restore-NetworkTuning -Quiet | Out-Null }
        $statusLabel.Text = 'MediaMTX start failed'
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkRed
        $script:PreviewOnlyMode = $false
        $script:ForceLocalPreviewMode = $false
        Set-RunState $false
        return
    }

    Write-DirectWebRtcWebClientConfig

    try {
        $script:ForceLiveScenePreviewBranch = $controlledLiveRequested
        $arguments = Build-GstArguments
        $videoArguments = ''
        $audioArguments = ''
        if ((Test-TransportEnabled) -and [string]$cmbProtocol.SelectedItem -eq $script:DirectWebRtcProtocolName -and (Test-DirectWebRtcSplitAvPipelines)) {
            if (Test-DirectWebRtcUnifiedPublisher) {
                $videoArguments = Build-DirectWebRtcUnifiedVideoBridgeArguments
            }
            $audioArguments = Build-DirectWebRtcAudioOnlyArguments
        }
    }
    catch {
        $script:PreviewOnlyMode = $false
        $script:ForceLocalPreviewMode = $false
        $statusLabel.Text = 'Start failed'
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkRed
        Set-RunState $false
        Append-Log "START ERROR: $($_.Exception.Message)"
        return
    }
    finally {
        $script:ForceLiveScenePreviewBranch = $false
    }

    $transportEnabled = Test-TransportEnabled
    $runIsPreviewOnly = [bool]$PreviewOnly
    $runNeedsUnifiedPublisherHost = $transportEnabled -and (Test-DirectWebRtcUnifiedPublisherHostRequired)
    $useControlledLiveStream = (
        $controlledLiveRequested -and
        -not $runNeedsUnifiedPublisherHost -and
        [string]::IsNullOrWhiteSpace($videoArguments) -and
        [string]::IsNullOrWhiteSpace($audioArguments)
    )
    $script:ForceLocalPreviewMode = $false
    Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Starting full GStreamer pipeline..."
    Append-Log "Process disk logging: $(if ($processDiskLogging) { 'enabled' } else { 'disabled - UI log only' })"
    Append-Log "Transport: $(if ($transportEnabled) { 'Enabled' } elseif ($runIsPreviewOnly) { 'Disabled - local preview only' } else { 'Disabled - local recording/preview only' })"
    if ($transportEnabled) {
        Append-Log "Protocol: $([string]$cmbProtocol.SelectedItem)"
        Append-Log "Absolute timestamps: $(Get-AbsoluteTimestampStatusText)"
        if ([string]$cmbProtocol.SelectedItem -eq 'WHIP') {
            Append-Log 'WHIP publish guard: constrained-baseline H.264 caps, GOP capped to 1s, B-frames/lookahead off, NVENC ultra-low-latency.'
            if (Test-SendAbsoluteTimestampsEnabled) {
                Append-Log 'WHIP timing: do-clock-signalling=true. Use with MediaMTX pathDefaults/useAbsoluteTimestamp=true.'
            }
            else {
                Append-Log 'WHIP timing: receiver/server timestamps. Use with MediaMTX pathDefaults/useAbsoluteTimestamp=false.'
            }
        }
        if ([string]$cmbProtocol.SelectedItem -eq $script:DirectWebRtcProtocolName) {
            Append-Log "Direct WebRTC viewer: $(Get-DirectWebRtcViewerUrl)"
            Append-Log "Direct WebRTC video signalling WebSocket/TCP: $($txtDirectWebRtcSignalingHost.Text):$([int]$numDirectWebRtcSignalingPort.Value)"
            Append-Log "Direct WebRTC smoothing: $([string]$cmbDirectWebRtcSmoothnessProfile.SelectedItem), recovery $([string]$cmbWebRtcRecoveryMode.SelectedItem), sender queue $([string]$cmbWebRtcSenderQueueMode.SelectedItem) / $([int]$numDirectWebRtcPacingMs.Value) ms cap, browser audio/video JBUF $([int]$numDirectWebRtcPlayerJitterMs.Value)/$([int]$numDirectWebRtcVideoJitterMs.Value) ms, clock signaling $([string](Get-TimingMode)), audio mode $([string]$cmbAudioTransportMode.SelectedItem)"
            Append-Log "Audio source selection: $(Get-AudioSourceSelectionSummary)"
            Append-Log "Direct WebRTC A/V pipeline topology: $([string](Get-DirectWebRtcAvPipelineMode))"
            if (Test-SplitClockSignalingOverridesActive) {
                $splitVideoClockText = if (Test-WebRtcClockSignalingForSink -SinkRole Video) { 'RFC7273 on' } else { 'off / property omitted' }
                $splitAudioClockText = if (Test-WebRtcClockSignalingForSink -SinkRole Audio) { 'RFC7273 on' } else { 'off / property omitted' }
                Append-Log "Split WebRTC sink clock signaling: video=$splitVideoClockText; audio=$splitAudioClockText."
            }
            else {
                $webRtcClockText = if (Test-WebRtcClockSignalingForSink -SinkRole Global) { 'RFC7273 on' } else { 'off / property omitted' }
                Append-Log "WebRTC sink clock signaling: $webRtcClockText."
            }
            if (Test-DirectWebRtcUnifiedPublisher) {
                Append-Log "Direct WebRTC unified-publisher lab: independent video/audio capture processes feed localhost RTP ports $([int]$numDirectWebRtcBridgeVideoPort.Value)/$([int]$numDirectWebRtcBridgeAudioPort.Value); one publisher exposes producer gstglass-av with video_0 + audio_0 on signalling port $([int]$numDirectWebRtcSignalingPort.Value)."
                $bridgeJitterText = if ([int]$numDirectWebRtcBridgeJitterMs.Value -gt 0) { [string]([int]$numDirectWebRtcBridgeJitterMs.Value) + ' ms, non-dropping' } else { 'disabled / element omitted' }
                $publisherQueueText = if ([int]$numDirectWebRtcPublisherQueueMs.Value -gt 0) { [string]([int]$numDirectWebRtcPublisherQueueMs.Value) + ' ms non-leaky per track' } else { 'disabled / element omitted' }
                $audioBridgePacingText = if ($chkDirectWebRtcAudioBridgePacing.Checked) { 'enabled (sync=true)' } else { 'disabled (sync=false)' }
                Append-Log "Unified publisher RTP timing repair: receive JBUF $bridgeJitterText; publisher queue $publisherQueueText; audio RTP pacing $audioBridgePacingText; udpsrc do-timestamp override omitted. Player uses one PeerConnection and does not open the split-audio WebSocket."
                $internalMtuText = if ([int]$numDirectWebRtcInternalRtpMtu.Value -gt 0) { [string]([int]$numDirectWebRtcInternalRtpMtu.Value) } else { 'plugin default' }
                Append-Log "Unified producer advanced: clock-signaling=$([bool](Test-WebRtcClockSignalingForSink -SinkRole Global)); control-data-channel=$($chkDirectWebRtcControlDataChannel.Checked); bundle=$([string]$cmbDirectWebRtcBundlePolicy.SelectedItem); internal RTP MTU=$internalMtuText; internal repeat headers=$($chkDirectWebRtcInternalRepeatHeaders.Checked)."
                if ($chkUnifiedBridgeKeyframeGuard.Checked) {
                    $effectiveKeyframeFrames = [Math]::Max(1, [int][Math]::Ceiling(([int]$numFps.Value * [int]$numUnifiedBridgeKeyframeIntervalMs.Value) / 1000.0))
                    Append-Log "Unified publisher keyframe guard: periodic IDR every $([int]$numUnifiedBridgeKeyframeIntervalMs.Value) ms -> encoder GOP $effectiveKeyframeFrames frames at $([int]$numFps.Value) FPS. This is the fallback for PLI/FIR requests that cannot cross the RTP process boundary."
                }
                else {
                    Append-Log "Unified publisher keyframe guard: off; encoder uses Video-tab GOP $([int]$numGopSeconds.Value) sec."
                }
            }
            elseif (Test-DirectWebRtcSplitAvPipelines) {
                if (Test-DirectWebRtcSharedSignaling) {
                    Append-Log "Direct WebRTC split signalling: SHARED on video port $([int]$numDirectWebRtcSignalingPort.Value); audio producer joins $(Get-DirectWebRtcSharedSignallerUri)."
                }
                else {
                    Append-Log "Direct WebRTC split audio signalling WebSocket/TCP: $($txtDirectWebRtcSignalingHost.Text):$(Get-DirectWebRtcSplitAudioSignalingPort)"
                }
                Append-Log "Direct WebRTC split audio player WS URL: $(Get-DirectWebRtcSplitAudioWsUrlDescriptionForLog)"
            }
            Append-Log 'Direct WebRTC media: UDP through ICE. Signalling is TCP/WebSocket on the configured port; the unified-publisher lab additionally uses localhost RTP/UDP between its three processes.'
        }
    }
    Append-Log "Capture method: $(Get-SelectedCaptureMethodName)"
    if ($chkSceneEnabled.Checked -and [string]$cmbScenePreset.SelectedItem -eq 'Desktop + webcam') {
        Append-Log "Scene input queues: $([int]$numSceneInputQueueBuffers.Value) buffers / $([int]$numSceneInputQueueCapMs.Value) ms per input, leaky=downstream. 0 ms is emitted literally with no hidden fallback."
    }
    if ($chkRecordingEnabled.Checked) {
        Append-Log "Recording file: $script:ResolvedRecordingPath"
        Append-Log "Recording encoder: $([string]$cmbRecordingEncoder.SelectedItem), $([int]$numRecordingVideoBitrate.Value) kbps, $([int]$numRecordingWidth.Value)x$([int]$numRecordingHeight.Value)@$([int]$numRecordingFps.Value)"
        Append-Log 'Recording branch guard: decoupled from the capture thread by a shallow non-leaky queue (recordq). Sustained disk/encoder overrun will backpressure capture rather than drop recorded frames; a software recording encoder can therefore throttle the live branch.'
    }

    if ($transportEnabled -and [string]$cmbProtocol.SelectedItem -eq 'SRT') {
        $srtTracks = if ($chkDesktopAudio.Checked -or $chkMic.Checked) {
            'video PID 256 + audio PID 257, both in program 1'
        }
        else {
            'video PID 256 in program 1'
        }

        Append-Log "SRT MPEG-TS mapping: $srtTracks"
        Append-Log 'SRT low-latency mux profile: mux latency 2.9 ms, PAT/PMT 600, pkt_size 1316, Opus preferred'
    }
    if (Test-FullscreenCaptureMode) {
        Append-Log "Fullscreen capture target: $($script:CaptureWindowTitle) (HWND $([uint64]$script:CaptureWindowHwnd.ToInt64()))"
    }
    $gstDebugSpec = Get-GstDebugSpec
    $requestedAudioQueueCapMs = [int]$numAudioQueueCapMs.Value
    $effectiveAudioQueueCapMs = Get-EffectiveAudioQueueCapMs
    $audioQueueCapText = if ($requestedAudioQueueCapMs -ne $effectiveAudioQueueCapMs) {
        "$requestedAudioQueueCapMs ms -> effective $effectiveAudioQueueCapMs ms"
    }
    else {
        "$requestedAudioQueueCapMs ms"
    }
    Append-Log "Threading: profile $([string]$cmbThreadingProfile.SelectedItem), priority $([string]$cmbGstProcessPriority.SelectedItem), capture queue $([int]$numCaptureQueueBuffers.Value) buffers, sender queue $([string]$cmbWebRtcSenderQueueMode.SelectedItem) / $([int]$numDirectWebRtcPacingMs.Value) ms, audio queue $([int]$numAudioQueueBuffers.Value) buffers / $audioQueueCapText, leak $([string]$cmbQueueLeakMode.SelectedItem), effective leak $(Get-EffectiveLiveQueueLeakValue), lateness tracer $($chkBufferLatenessTracer.Checked)."
    $cpuWorkerText = if ([int]$numCpuWorkerLimit.Value -eq 0) { 'auto' } else { [string]([int]$numCpuWorkerLimit.Value) }
    Append-Log "Thread budget: $([string]$cmbThreadBudget.SelectedItem), CPU workers $cpuWorkerText, boundaries capture=$($chkBudgetCaptureQueue.Checked) sender=$($chkBudgetSenderQueue.Checked) audio-input=$($chkBudgetAudioInputQueue.Checked) audio-sender=$($chkBudgetAudioFinalQueue.Checked) scene-inputs=$($chkBudgetSceneInputQueues.Checked). Total process threads are observed, not hard-capped."
    if ((Get-QueueLeakValue) -eq 'no' -and (Get-EffectiveLiveQueueLeakValue) -ne 'no') { Append-Log 'Threading guard: No leak/block was selected but coerced to downstream/drop-old outside Blocking diagnostic profile.' }
    if ($requestedAudioQueueCapMs -gt 0 -and $effectiveAudioQueueCapMs -gt $requestedAudioQueueCapMs) { Append-Log "Audio queue guard: raised nonzero audio queue cap from $requestedAudioQueueCapMs ms to $effectiveAudioQueueCapMs ms so GStreamer latency negotiation has enough headroom." }
    Append-Log "Browser JBUF guard: audio/video target $([int]$numDirectWebRtcPlayerJitterMs.Value)/$([int]$numDirectWebRtcVideoJitterMs.Value) ms, watchdog $([string]$cmbJbufWatchdogMode.SelectedItem), max $([int]$numJbufMaxMs.Value) ms, URL/config bridged."
    Append-Log "Split player sync: $([string]$cmbSplitPlayerSyncMode.SelectedItem), watchdog warmup $([int]$numSplitAudioWarmupSeconds.Value) sec applies to both JBUF and split-audio watchdogs, audio stall $([int]$numSplitAudioStallSeconds.Value) sec, offset baseline $([int]$numSplitAvOffsetBaselineMs.Value) ms (0 auto), drift warn $([int]$numSplitAvOffsetWarnMs.Value) ms. Default free-run never delays video."
    Append-Log "Direct GST WebRTC Opus: $([string]$cmbDirectWebRtcOpusMode.SelectedItem), frame $([string]$cmbDirectWebRtcOpusFrameMs.SelectedItem) ms, type $([string]$cmbDirectWebRtcOpusAudioType.SelectedItem), FEC $($chkDirectWebRtcOpusFec.Checked), DTX $($chkDirectWebRtcOpusDtx.Checked)."
    Append-Log "Pipeline clock: $([string](Get-VideoPipelineClockMode)); video timestamps $([string](Get-VideoTimestampMode)). Explicit system modes wrap the complete main graph in clockselect."
    Append-Log "Split audio process clock: $([string](Get-SplitAudioPipelineClockMode)) (UI selection $([string]$cmbSplitAudioPipelineClockMode.SelectedItem))."
    if ((Test-DirectWebRtcSplitAvPipelines) -and -not (Test-DirectWebRtcSharedSignaling) -and ([int]$numDirectWebRtcSignalingPort.Value -eq [int]$numDirectWebRtcSplitAudioSignalingPort.Value)) {
        Append-Log 'WARNING: Separate split signalling is selected but video and audio ports are identical; the second server cannot bind the same TCP port.'
    }
    $mixerSummary = if ($chkDesktopAudio.Checked -and ($chkMic.Checked -or $chkAudioMixerMode.Checked)) { 'audiomixer' } elseif ($chkDesktopAudio.Checked) { 'legacy direct desktop path' } else { 'not applicable' }
    Append-Log "Desktop audio path: $mixerSummary (mixer flag=$($chkAudioMixerMode.Checked); microphone=$($chkMic.Checked))."
    Append-Log "Video sync mode: $([string]$cmbVideoSyncMode.SelectedItem); Audio sync mode: $([string]$cmbAudioSyncMode.SelectedItem). Explicit modes insert clocksync before compatible send/mux sinks; local preview also honors Video sync mode."
    Append-Log "Audio timing UI: clock=$([string]$cmbAudioClockMode.SelectedItem); mode=$([string]$cmbAudioTimingMode.SelectedItem); slave=$([string]$cmbAudioSlaveMethod.SelectedItem); low-latency override=$($chkWasapiLowLatencyOverride.Checked); buffer override=$($chkAudioBufferOverride.Checked) [$([int]$numAudioBufferMs.Value) ms]; latency override=$($chkAudioLatencyOverride.Checked) [$([int]$numAudioLatencyMs.Value) ms]; sample-rate override=$($chkAudioSampleRateOverride.Checked) [$([int]$numAudioSampleRate.Value) Hz]."
    Append-Log "Effective WASAPI source: $(Get-EffectiveAudioTimingSummary)"
    if (-not [string]::IsNullOrWhiteSpace($gstDebugSpec)) {
        Append-Log "GStreamer debug: GST_DEBUG=$gstDebugSpec, no color=$($chkGstDebugNoColor.Checked)."
    }
    else {
        Append-Log 'GStreamer debug: off.'
    }
    $mainLaunchExecutable = $gstPath
    $mainLaunchArguments = $arguments
    if ($useControlledLiveStream) {
        Append-Log 'Live scene editing: enabled on the actual broadcast compositor (single controlled worker pipeline).'
        Append-Log ('In-process pipeline: ' + (ConvertTo-InProcessGstLaunchDescription -Description $arguments))
        if ($processDiskLogging) {
            Append-Log 'Process disk logging: controlled worker stdout/stderr uses the normal per-run log files.'
        }
    }
    elseif ($runNeedsUnifiedPublisherHost) {
        $hostLaunch = Get-UnifiedPublisherHostLaunch -GstPath $gstPath -GstArguments $arguments
        $mainLaunchExecutable = [string]$hostLaunch.Executable
        $mainLaunchArguments = [string]$hostLaunch.Arguments
        Append-Log "Unified publisher host: $mainLaunchExecutable"
        Append-Log "Unified publisher host arguments: $mainLaunchArguments"
        Append-Log "Equivalent gst-launch arguments: $arguments"
    }
    else {
        Append-Log "Executable: $gstPath"
        Append-Log "Arguments: $arguments"
    }
    if (-not [string]::IsNullOrWhiteSpace($videoArguments)) {
        Append-Log "Video bridge executable: $gstPath"
        Append-Log "Video bridge arguments: $videoArguments"
    }
    if (-not [string]::IsNullOrWhiteSpace($audioArguments)) {
        Append-Log "Audio executable: $gstPath"
        Append-Log "Audio arguments: $audioArguments"
    }

    if ($useControlledLiveStream) {
        try {
            $pipelineDescription = ConvertTo-InProcessGstLaunchDescription -Description $arguments
            $showLivePreviewAtStart = (
                $form.Visible -and
                $form.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized -and
                (
                    $script:SceneWorkspaceActive -or
                    -not ($transportEnabled -and $chkHidePreviewDuringStream.Checked)
                )
            )
            $renderTarget = if ($showLivePreviewAtStart) { $previewPanel } else { Ensure-PreviewParkingWindow }
            $renderSize = if ($showLivePreviewAtStart) { $previewPanel.ClientSize } else { New-Object System.Drawing.Size(16, 16) }
            $null = $renderTarget.Handle

            $tracerEnvState = $null
            try {
                $tracerEnvState = Set-GstTracerEnvironment -Enable:([bool]$chkBufferLatenessTracer.Checked) -DebugSpec $gstDebugSpec -NoColor:([bool]$chkGstDebugNoColor.Checked)
                $workerStarted = Start-ControlledLiveWorker `
                    -Pipeline $pipelineDescription `
                    -WindowHandle $renderTarget.Handle `
                    -Width ([Math]::Max(1, $renderSize.Width)) `
                    -Height ([Math]::Max(1, $renderSize.Height))
                if (-not $workerStarted) { throw 'The controlled live worker did not start.' }
            }
            finally {
                Restore-GstTracerEnvironment $tracerEnvState
            }

            $script:ControlledLiveStreamActive = $true
            $script:ControlledLivePreviewSurfaceHwnd = $renderTarget.Handle
            $script:ControlledLivePreviewAppliedSize = $renderSize
            $script:PreviewHwnd = [IntPtr]::Zero
            $script:PreviewParked = -not $showLivePreviewAtStart
            Sync-ControlledScenePreviewProperties
            Sync-ControlledLivePreviewLayout
            Save-ActiveProcessState

            $mediaSuffix = if ($script:MediaMtxProcess -and -not $script:MediaMtxProcess.HasExited) { " + MediaMTX PID $($script:MediaMtxProcess.Id)" } else { '' }
            if ($transportEnabled) {
                $statusLabel.Text = "$([string]$cmbProtocol.SelectedItem) streaming - controlled worker PID $($script:GstProcess.Id)$mediaSuffix"
            }
            elseif ($chkRecordingEnabled.Checked) {
                $statusLabel.Text = "Recording locally - controlled worker PID $($script:GstProcess.Id)"
            }
            else {
                $statusLabel.Text = "Controlled live scene pipeline - worker PID $($script:GstProcess.Id)"
            }
            $statusLabel.ForeColor = [System.Drawing.Color]::DarkGreen
            Set-RunState $true
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] LIVE SCENE CONTROL ACTIVE: worker PID $($script:GstProcess.Id); editor geometry and opacity mutate its broadcast compositor over IPC."
            return
        }
        catch {
            Append-Log "Controlled live stream start error: $($_.Exception.Message)"
            Append-Log 'Falling back to the unchanged external gst-launch stream for this run.'
            $script:SuppressControlledLiveStream = $true
            $script:ControlledLiveStreamActive = $false
            try {
                if ($script:GstProcess -and -not $script:GstProcess.HasExited) {
                    Stop-ProcessTreeById -ProcessId $script:GstProcess.Id
                }
            }
            catch {}
            Close-ControlledLiveWorkerPipe
            try { if ($script:GstProcess) { $script:GstProcess.Dispose() } } catch {}
            $script:GstProcess = $null
            $script:ControlledLivePreviewSurfaceHwnd = [IntPtr]::Zero
            $script:ControlledLivePreviewAppliedSize = [System.Drawing.Size]::Empty
            [System.Threading.Thread]::Sleep(750)
        }
    }

    try {
        $tracerEnvState = $null
        try {
            $tracerEnvState = Set-GstTracerEnvironment -Enable:([bool]$chkBufferLatenessTracer.Checked) -DebugSpec $gstDebugSpec -NoColor:([bool]$chkGstDebugNoColor.Checked)
            if ($chkBufferLatenessTracer.Checked) { Append-Log 'GStreamer buffer-lateness tracer enabled for this run.' }
            if ($processDiskLogging) {
                $script:GstProcess = Start-Process -FilePath $mainLaunchExecutable -ArgumentList $mainLaunchArguments -RedirectStandardOutput $script:StdOutPath -RedirectStandardError $script:StdErrPath -WindowStyle Hidden -PassThru
            }
            else {
                $script:GstProcess = Start-Process -FilePath $mainLaunchExecutable -ArgumentList $mainLaunchArguments -WindowStyle Hidden -PassThru
            }
        }
        finally {
            Restore-GstTracerEnvironment $tracerEnvState
        }

        Set-GstProcessPriority -Process $script:GstProcess

        if ($script:JobHandle -ne [IntPtr]::Zero) {
            try {
                [GstProcessJob]::AssignProcess($script:JobHandle, $script:GstProcess.Handle)
            }
            catch {
                Append-Log "WARNING: GStreamer could not be assigned to the kill-on-close job: $($_.Exception.Message)"
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($videoArguments)) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Starting split video capture / RTP bridge pipeline..."
            # Let the unified publisher bind its UDP receivers and signalling/web listeners first.
            Start-Sleep -Milliseconds 250
            $videoTracerEnvState = $null
            try {
                $videoTracerEnvState = Set-GstTracerEnvironment -Enable:([bool]$chkBufferLatenessTracer.Checked) -DebugSpec $gstDebugSpec -NoColor:([bool]$chkGstDebugNoColor.Checked)
                if ($processDiskLogging) {
                    $script:GstVideoProcess = Start-Process -FilePath $gstPath -ArgumentList $videoArguments -RedirectStandardOutput $script:StdOutVideoPath -RedirectStandardError $script:StdErrVideoPath -WindowStyle Hidden -PassThru
                }
                else {
                    $script:GstVideoProcess = Start-Process -FilePath $gstPath -ArgumentList $videoArguments -WindowStyle Hidden -PassThru
                }
            }
            finally {
                Restore-GstTracerEnvironment $videoTracerEnvState
            }
            Set-GstProcessPriority -Process $script:GstVideoProcess
            if ($script:JobHandle -ne [IntPtr]::Zero) {
                try { [GstProcessJob]::AssignProcess($script:JobHandle, $script:GstVideoProcess.Handle) }
                catch { Append-Log "WARNING: Split video bridge GStreamer could not be assigned to the kill-on-close job: $($_.Exception.Message)" }
            }
            Append-Log "Split video bridge GST PID: $($script:GstVideoProcess.Id)"
        }

        if (-not [string]::IsNullOrWhiteSpace($audioArguments)) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Starting split audio-only GStreamer pipeline..."
            $audioTracerEnvState = $null
            try {
                $audioTracerEnvState = Set-GstTracerEnvironment -Enable:([bool]$chkBufferLatenessTracer.Checked) -DebugSpec $gstDebugSpec -NoColor:([bool]$chkGstDebugNoColor.Checked)
                if ($processDiskLogging) {
                    $script:GstAudioProcess = Start-Process -FilePath $gstPath -ArgumentList $audioArguments -RedirectStandardOutput $script:StdOutAudioPath -RedirectStandardError $script:StdErrAudioPath -WindowStyle Hidden -PassThru
                }
                else {
                    $script:GstAudioProcess = Start-Process -FilePath $gstPath -ArgumentList $audioArguments -WindowStyle Hidden -PassThru
                }
            }
            finally {
                Restore-GstTracerEnvironment $audioTracerEnvState
            }
            Set-GstProcessPriority -Process $script:GstAudioProcess
            if ($script:JobHandle -ne [IntPtr]::Zero) {
                try { [GstProcessJob]::AssignProcess($script:JobHandle, $script:GstAudioProcess.Handle) }
                catch { Append-Log "WARNING: Split audio GStreamer could not be assigned to the kill-on-close job: $($_.Exception.Message)" }
            }
            Append-Log "Split audio GST PID: $($script:GstAudioProcess.Id)"
        }

        Save-ActiveProcessState

        $targetSuffix = if ((Test-FullscreenCaptureMode) -and $script:CaptureWindowTitle) { " - $($script:CaptureWindowTitle)" } else { '' }
        $mediaSuffix = if (
            $script:MediaMtxProcess -and
            -not $script:MediaMtxProcess.HasExited
        ) {
            " + MediaMTX PID $($script:MediaMtxProcess.Id)"
        }
        else {
            ''
        }
        if ($transportEnabled) {
            $videoSuffix = if ($script:GstVideoProcess -and -not $script:GstVideoProcess.HasExited) { " + Video PID $($script:GstVideoProcess.Id)" } else { '' }
            $audioSuffix = if ($script:GstAudioProcess -and -not $script:GstAudioProcess.HasExited) { " + Audio PID $($script:GstAudioProcess.Id)" } else { '' }
            $statusLabel.Text = "$([string]$cmbProtocol.SelectedItem) streaming - GST PID $($script:GstProcess.Id)$videoSuffix$audioSuffix$mediaSuffix$targetSuffix"
        }
        elseif ($chkRecordingEnabled.Checked) {
            $statusLabel.Text = "Recording locally - GST PID $($script:GstProcess.Id)$targetSuffix"
        }
        else {
            $statusLabel.Text = "Preview only - GST PID $($script:GstProcess.Id)$targetSuffix"
        }
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkGreen
        Set-RunState $true
    }
    catch {
        $script:GstProcess = $null
        if ($script:GstVideoProcess -and -not $script:GstVideoProcess.HasExited) { try { Stop-ProcessTreeById -ProcessId $script:GstVideoProcess.Id } catch {} }
        if ($script:GstAudioProcess -and -not $script:GstAudioProcess.HasExited) { try { Stop-ProcessTreeById -ProcessId $script:GstAudioProcess.Id } catch {} }
        $script:GstVideoProcess = $null
        $script:GstAudioProcess = $null
        $script:PreviewOnlyMode = $false
        $script:ForceLocalPreviewMode = $false
        Stop-ManagedMediaMtx -Quiet
        if ($chkNetworkRestoreOnStop.Checked) { Restore-NetworkTuning -Quiet | Out-Null }
        Remove-ActiveProcessState
        $statusLabel.Text = 'Start failed'
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkRed
        Set-RunState $false
        Append-Log "START ERROR: $($_.Exception.Message)"
    }
}

function Stop-ControlledLiveStream {
    param([switch]$Restart)

    if (-not $script:ControlledLiveStreamActive) { return $false }

    $script:StopRequested = $true
    $script:WaitingForFullscreen = $false
    $script:RestartAt = if ($Restart) { (Get-Date).AddMilliseconds(800) } else { $null }
    $workerProcess = $script:GstProcess
    if ($workerProcess -and -not $workerProcess.HasExited) {
        Append-Log (
            "[$(Get-Date -Format 'HH:mm:ss')] Stopping complete controlled live " +
            "process tree - PID $($workerProcess.Id)..."
        )
        # Intentionally identical to every legacy publisher stop. Do not send a
        # pipe Stop command or transition the graph to NULL first: terminating
        # this process is the signalling/socket boundary the web player expects.
        Stop-ProcessTreeById -ProcessId $workerProcess.Id
        try { $workerProcess.WaitForExit(3000) | Out-Null } catch {}
    }
    Close-ControlledLiveWorkerPipe
    try { if ($workerProcess) { $workerProcess.Dispose() } } catch {}
    $script:GstProcess = $null

    $script:ControlledLiveStreamActive = $false
    $script:ControlledLivePreviewSurfaceHwnd = [IntPtr]::Zero
    $script:ControlledLivePreviewAppliedSize = [System.Drawing.Size]::Empty
    $script:PreviewHwnd = [IntPtr]::Zero
    $script:PreviewParked = $false
    $script:PipelineHasPreview = $false
    $script:PreviewOnlyMode = $false
    $script:ForceLocalPreviewMode = $false
    $script:ForceLiveScenePreviewBranch = $false
    Reset-PreviewAppliedState

    $previewPlaceholder.Visible = $true
    $previewPlaceholder.Text = if ($Restart) { 'Restarting stream...' } else { 'Preview stopped' }

    Stop-ManagedMediaMtx
    # MediaMTX may emit final diagnostics while it is being stopped. Drain that
    # tail before discarding the paths so a failed relay shutdown remains visible.
    $finalText = Drain-ManagedProcessLogs
    if ($finalText) { Append-Log $finalText }
    Reset-ProcessLogPaths
    Remove-ActiveProcessState
    if ((-not $Restart) -and $chkNetworkRestoreOnStop.Checked) {
        Restore-NetworkTuning -Quiet | Out-Null
    }

    Set-RunState $false
    if ($Restart) {
        $statusLabel.Text = 'Restarting...'
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
    }
    else {
        $statusLabel.Text = 'Stopped'
        $statusLabel.ForeColor = [System.Drawing.Color]::Black
        $script:StopRequested = $false
        $null = $form.BeginInvoke([Action]{
            try { Sync-StandalonePreviewState -Quiet } catch {}
        })
    }
    return $true
}

function Stop-GstStream {
    param([switch]$Restart)

    if (Stop-ControlledLiveStream -Restart:$Restart) { return }

    if ($script:DynamicScenePreviewActive) {
        Stop-DynamicScenePreview
        if (-not $Restart) { return }
    }

    $script:StopRequested = $true
    $script:WaitingForFullscreen = $false
    $wasPreviewOnly = [bool]$script:PreviewOnlyMode

    if ($Restart) {
        $script:RestartAt = (Get-Date).AddMilliseconds(800)
    }
    else {
        $script:RestartAt = $null
    }

    $script:PreviewHwnd = [IntPtr]::Zero
    $script:PreviewParked = $false
    $script:PipelineHasPreview = $false
    $script:PreviewOnlyMode = $false
    $script:ForceLocalPreviewMode = $false
    Reset-PreviewAppliedState
    $previewPlaceholder.Visible = $true
    $previewPlaceholder.Text = if ($wasPreviewOnly) { 'Preview stopped' } else { 'Preview stopped' }

    $hadGst =
        $script:GstProcess -and
        -not $script:GstProcess.HasExited

    $hadVideoGst =
        $script:GstVideoProcess -and
        -not $script:GstVideoProcess.HasExited

    $hadAudioGst =
        $script:GstAudioProcess -and
        -not $script:GstAudioProcess.HasExited

    $hadMedia =
        $script:MediaMtxProcess -and
        -not $script:MediaMtxProcess.HasExited

    if ($hadGst -or $hadVideoGst -or $hadAudioGst -or $hadMedia) {
        $statusLabel.Text = 'Stopping...'
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
    }

    # Stop the publisher first so MediaMTX sees a clean publisher disconnect,
    # then stop the managed server itself.
    if ($hadGst) {
        Append-Log (
            "[$(Get-Date -Format 'HH:mm:ss')] Stopping complete GStreamer " +
            "process tree - PID $($script:GstProcess.Id)..."
        )
        Stop-ProcessTreeById -ProcessId $script:GstProcess.Id

        try {
            $script:GstProcess.WaitForExit(3000) | Out-Null
        }
        catch {}
    }

    if ($hadVideoGst) {
        Append-Log (
            "[$(Get-Date -Format 'HH:mm:ss')] Stopping split video bridge GStreamer " +
            "process tree - PID $($script:GstVideoProcess.Id)..."
        )
        Stop-ProcessTreeById -ProcessId $script:GstVideoProcess.Id
        try { $script:GstVideoProcess.WaitForExit(3000) | Out-Null } catch {}
    }

    if ($hadAudioGst) {
        Append-Log (
            "[$(Get-Date -Format 'HH:mm:ss')] Stopping split audio GStreamer " +
            "process tree - PID $($script:GstAudioProcess.Id)..."
        )
        Stop-ProcessTreeById -ProcessId $script:GstAudioProcess.Id
        try { $script:GstAudioProcess.WaitForExit(3000) | Out-Null } catch {}
    }

    try {
        if ($script:GstProcess) {
            $script:GstProcess.Dispose()
        }
        if ($script:GstVideoProcess) {
            $script:GstVideoProcess.Dispose()
        }
        if ($script:GstAudioProcess) {
            $script:GstAudioProcess.Dispose()
        }
    }
    catch {}
    $script:GstProcess = $null
    $script:GstVideoProcess = $null
    $script:GstAudioProcess = $null

    Stop-ManagedMediaMtx

    Remove-ActiveProcessState

    if ((-not $Restart) -and $chkNetworkRestoreOnStop.Checked) {
        Restore-NetworkTuning -Quiet | Out-Null
    }

    if (-not $Restart) {
        $statusLabel.Text = 'Stopped'
        $statusLabel.ForeColor = [System.Drawing.Color]::Black
        Set-RunState $false
        $script:StopRequested = $false
        if (-not $wasPreviewOnly) {
            $null = $form.BeginInvoke([Action]{
                try { Sync-StandalonePreviewState -Quiet } catch {}
            })
        }
    }
    else {
        Set-RunState $false
    }
}

function Test-GStreamerElements {
    $gstPath = Resolve-GstLaunchSelection -RequestedPath $txtGstPath.Text -UpdateControl
    if (-not (Test-GstLaunchPath $gstPath)) {
        [System.Windows.Forms.MessageBox]::Show('Select a valid gst-launch-1.0.exe first.', $script:AppName, 'OK', 'Warning') | Out-Null
        return
    }

    Prepare-GStreamerRuntime -GstPath $gstPath
    $inspectPath = Join-Path (Split-Path -Parent $gstPath) 'gst-inspect-1.0.exe'
    if (-not (Test-Path -LiteralPath $inspectPath)) {
        [System.Windows.Forms.MessageBox]::Show('gst-inspect-1.0.exe was not found beside gst-launch-1.0.exe.', $script:AppName, 'OK', 'Warning') | Out-Null
        return
    }

    $transportEnabled = Test-TransportEnabled
    $definition = Get-SelectedEncoderDefinition
    $codec = [string]$definition.Codec
    $protocol = [string]$cmbProtocol.SelectedItem

    $captureMethod = Get-SelectedCaptureMethod
    $elements = New-Object System.Collections.Generic.List[string]
    $baseElements = @([string]$captureMethod.Element, 'd3d11convert')
    if ($transportEnabled) { $baseElements += [string]$definition.Element }
    foreach ($element in $baseElements) {
        if (-not [string]::IsNullOrWhiteSpace($element)) {
            $elements.Add($element)
        }
    }

    if ([string]$captureMethod.Method -eq 'MonitorGdi') {
        foreach ($element in @('videoconvert', 'videoscale', 'd3d11upload')) {
            $elements.Add($element)
        }
    }

    if ($transportEnabled -and [string]$definition.Input -eq 'I420') {
        $elements.Add('d3d11download')
        $elements.Add('videoconvert')
    }

    if ($transportEnabled -and -not [string]::IsNullOrWhiteSpace([string]$definition.Parser)) {
        $elements.Add([string]$definition.Parser)
    }

    if ($chkPreview.Checked -or $chkRecordingEnabled.Checked) {
        $elements.Add('tee')
    }

    if ($chkPreview.Checked) {
        $elements.Add('d3d11videosink')
    }

    if ($chkRecordingEnabled.Checked) {
        $recordDefinition = Get-SelectedRecordingEncoderDefinition
        foreach ($element in @(
            'matroskamux',
            'filesink',
            'd3d11convert',
            [string]$recordDefinition.Element
        )) {
            if (-not [string]::IsNullOrWhiteSpace($element)) {
                $elements.Add($element)
            }
        }

        if ([string]$recordDefinition.Input -eq 'I420') {
            $elements.Add('d3d11download')
            $elements.Add('videoconvert')
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$recordDefinition.Parser)) {
            $elements.Add([string]$recordDefinition.Parser)
        }

        if ($chkRecordingDesktopAudio.Checked -or $chkRecordingMic.Checked) {
            foreach ($element in @(
                'wasapi2src',
                'audioconvert',
                'audioresample',
                'opusenc'
            )) {
                $elements.Add($element)
            }

            if ($chkRecordingDesktopAudio.Checked -and $chkRecordingMic.Checked) {
                $elements.Add('audiomixer')
            }
        }
    }

    $userAudioEnabled =
        $transportEnabled -and
        (
            $chkDesktopAudio.Checked -or
            $chkMic.Checked
        )

    $usingWhipSilentClockAudio =
        $transportEnabled -and
        $protocol -in @('WHIP', 'GST WebRTC') -and
        -not $userAudioEnabled

    $hasAudio =
        $userAudioEnabled -or
        $usingWhipSilentClockAudio

    if ($hasAudio) {
        foreach (
            $element in @(
                'wasapi2src',
                'audioconvert',
                'audioresample',
                'volume'
            )
        ) {
            $elements.Add($element)
        }

        if ($chkDesktopAudio.Checked -and $chkMic.Checked) {
            $elements.Add('audiomixer')
        }
    }

    $audioDefinition = if ($usingWhipSilentClockAudio) {
        $script:AudioCodecCatalog['Opus']
    }
    elseif ($hasAudio) {
        Get-SelectedAudioCodecDefinition
    }
    else {
        $null
    }

    if ($transportEnabled) {
        switch ($protocol) {
        'WHIP' {
            $elements.Add('whipclientsink')

            $videoPayloader = switch ($codec) {
                'H264' { 'rtph264pay' }
                'H265' { 'rtph265pay' }
                'AV1'  { 'rtpav1pay' }
                'VP8'  { 'rtpvp8pay' }
                'VP9'  { 'rtpvp9pay' }
            }

            if ($videoPayloader) {
                $elements.Add($videoPayloader)
            }

            if ($hasAudio) {
                $elements.Add([string]$audioDefinition.Element)
                if (-not [string]::IsNullOrWhiteSpace([string]$audioDefinition.Parser)) {
                    $elements.Add([string]$audioDefinition.Parser)
                }
                if ([string]$audioDefinition.Codec -eq 'OPUS') {
                    $elements.Add('rtpopuspay')
                }
            }
        }

        'GST WebRTC' {
            $elements.Add('webrtcsink')
            if (Test-DirectWebRtcUnifiedPublisher) {
                foreach ($element in @(
                    'udpsrc',
                    'udpsink',
                    'rtpopuspay',
                    'rtpopusdepay',
                    'opusenc',
                    'opusparse'
                )) {
                    $elements.Add($element)
                }

                if ([int]$numDirectWebRtcBridgeJitterMs.Value -gt 0) {
                    $elements.Add('rtpjitterbuffer')
                }

                switch ($codec) {
                    'H264' {
                        $elements.Add('rtph264pay')
                        $elements.Add('rtph264depay')
                        $elements.Add('h264parse')
                    }
                    'H265' {
                        $elements.Add('rtph265pay')
                        $elements.Add('rtph265depay')
                        $elements.Add('h265parse')
                    }
                }
            }
            elseif ($hasAudio) {
                $elements.Add([string]$audioDefinition.Element)
                if (-not [string]::IsNullOrWhiteSpace([string]$audioDefinition.Parser)) {
                    $elements.Add([string]$audioDefinition.Parser)
                }
            }
        }

        'SRT' {
            $elements.Add('mpegtsmux')
            $elements.Add('srtsink')
            if ($hasAudio) {
                $elements.Add([string]$audioDefinition.Element)
                if (-not [string]::IsNullOrWhiteSpace([string]$audioDefinition.Parser)) {
                    $elements.Add([string]$audioDefinition.Parser)
                }
            }
        }

        'RTMP' {
            $elements.Add($(if ($codec -eq 'H264') { 'flvmux' } else { 'eflvmux' }))
            $elements.Add('rtmp2sink')
            if ($hasAudio) {
                $elements.Add([string]$audioDefinition.Element)
                if (-not [string]::IsNullOrWhiteSpace([string]$audioDefinition.Parser)) {
                    $elements.Add([string]$audioDefinition.Parser)
                }
            }
        }

        'RTSP' {
            $elements.Add('rtspclientsink')
            if ($hasAudio) {
                $elements.Add([string]$audioDefinition.Element)
                if (-not [string]::IsNullOrWhiteSpace([string]$audioDefinition.Parser)) {
                    $elements.Add([string]$audioDefinition.Parser)
                }

                $audioPayloader = switch ([string]$audioDefinition.Codec) {
                    'OPUS' { 'rtpopuspay' }
                    'AAC'  { 'rtpmp4apay' }
                    'MP3'  { 'rtpmpapay' }
                    'AC3'  { 'rtpac3pay' }
                }
                if ($audioPayloader) {
                    $elements.Add($audioPayloader)
                }
            }
        }
        }
    }

    $missing = New-Object System.Collections.Generic.List[string]
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        foreach ($element in ($elements | Select-Object -Unique)) {
            & $inspectPath $element *> $null
            if ($LASTEXITCODE -ne 0) {
                $missing.Add($element)
            }
        }
    }
    finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }

    $compatibilityWarning = $null
    if ($transportEnabled -and (Test-DirectWebRtcUnifiedPublisher) -and $codec -notin @('H264','H265')) {
        $compatibilityWarning = "Unified A/V publisher bridge currently supports H264 and H265 only; selected codec is $codec."
    }
    elseif ($transportEnabled -and (Test-DirectWebRtcUnifiedPublisher) -and (Get-ComboSelectedOrDefault $cmbDirectWebRtcOpusMode $script:DefaultDirectWebRtcOpusMode) -eq 'Raw audio to webrtcsink') {
        $compatibilityWarning = 'Unified A/V publisher bridge requires Explicit Opus encoder mode.'
    }
    elseif ($transportEnabled -and -not (Test-CodecProtocolCompatibility -Codec $codec -Protocol $protocol)) {
        $compatibilityWarning = "$codec is not supported by the $protocol pipeline template."
    }
    elseif (
        $transportEnabled -and
        $hasAudio -and
        -not $usingWhipSilentClockAudio -and
        -not (Test-AudioCodecProtocolCompatibility `
            -AudioCodecName ([string]$cmbAudioCodec.SelectedItem) `
            -Protocol $protocol)
    ) {
        $compatibilityWarning =
            "$([string]$cmbAudioCodec.SelectedItem) is not supported by $protocol."
    }

    if ($missing.Count -eq 0 -and -not $compatibilityWarning) {
        $audioSummary = if ($usingWhipSilentClockAudio) {
            'Muted Opus/WASAPI clock track (automatic)'
        }
        elseif ($hasAudio) {
            [string]$cmbAudioCodec.SelectedItem
        }
        else {
            'Disabled'
        }

        [System.Windows.Forms.MessageBox]::Show(
            (
                "All elements required by the current configuration were found." +
                "`r`n`r`nTransport: $(if ($transportEnabled) { 'Enabled - ' + $protocol } else { 'Disabled' })" +
                "`r`nCapture: $(Get-SelectedCaptureMethodName)" +
                "`r`nVideo: $(if ($transportEnabled) { [string]$definition.Element + ' (' + $codec + ')' } else { 'No network encoder branch' })" +
                "`r`nAudio: $audioSummary" +
                "`r`nRecording: $(if ($chkRecordingEnabled.Checked) { 'Enabled - ' + [string]$cmbRecordingEncoder.SelectedItem } else { 'Disabled' })"
            ),
            $script:AppName,
            'OK',
            'Information'
        ) | Out-Null
    }
    else {
        $messages = New-Object System.Collections.Generic.List[string]
        if ($missing.Count -gt 0) {
            $messages.Add("Missing GStreamer elements:`r`n$($missing -join "`r`n")")
        }
        if ($compatibilityWarning) {
            $messages.Add($compatibilityWarning)
        }

        [System.Windows.Forms.MessageBox]::Show(
            ($messages -join "`r`n`r`n"),
            $script:AppName,
            'OK',
            'Error'
        ) | Out-Null
    }
}

$previewHandler = { Update-CommandPreview }

function Update-PlayerConfigFromUi {
    try {
        Write-DirectWebRtcWebClientConfig -Quiet
    }
    catch {}
    Update-DirectWebRtcUi
    Update-CommandPreview
}

$txtGstPath.Add_TextChanged($previewHandler)
$txtDestination.Add_TextChanged({
    $protocol = [string]$cmbProtocol.SelectedItem
    if ($protocol -and -not $script:SuppressProtocolChange) {
        $script:ProtocolDestinations[$protocol] = $txtDestination.Text
    }
    Update-DirectWebRtcUi
    Update-CommandPreview
})
$cmbProtocol.Add_SelectedIndexChanged({
    Update-ProtocolUi
    Sync-TransportTimingControls -Source TimingMode
    Update-TimestampUi
    Update-CommandPreview
})
$chkTransportEnabled.Add_CheckedChanged({ Update-TransportUi })
$chkSendAbsoluteTimestamps.Add_CheckedChanged({ Update-TimestampUi; Update-CommandPreview })
$cmbTimingMode.Add_SelectedIndexChanged({
    Sync-TransportTimingControls -Source TimingMode
    Update-TransportUi
})
$chkSplitClockSignalingOverrides.Add_CheckedChanged({ Update-TimestampUi; Update-CommandPreview })
$cmbSplitVideoClockSignaling.Add_SelectedIndexChanged({ Update-TimestampUi; Update-CommandPreview })
$cmbSplitAudioClockSignaling.Add_SelectedIndexChanged({ Update-TimestampUi; Update-CommandPreview })
$cmbEncoder.Add_SelectedIndexChanged({ Update-EncoderUi })
$cmbAudioTransportMode.Add_SelectedIndexChanged({ Update-AudioCodecChoices; Update-CommandPreview })
$cmbSplitAudioPipelineClockMode.Add_SelectedIndexChanged($previewHandler)
$cmbAudioClockMode.Add_SelectedIndexChanged($previewHandler)
$cmbAudioTimingMode.Add_SelectedIndexChanged({ Update-AudioTimingOptionUi; Update-AudioCodecChoices; Update-CommandPreview })
$cmbAudioSlaveMethod.Add_SelectedIndexChanged($previewHandler)
$cmbAudioSyncMode.Add_SelectedIndexChanged($previewHandler)
$chkWasapiLowLatencyOverride.Add_CheckedChanged({ Update-AudioTimingOptionUi; Update-CommandPreview })
$chkAudioBufferOverride.Add_CheckedChanged({ Update-AudioTimingOptionUi; Update-CommandPreview })
$chkAudioLatencyOverride.Add_CheckedChanged({ Update-AudioTimingOptionUi; Update-CommandPreview })
$chkAudioSampleRateOverride.Add_CheckedChanged({ Update-AudioTimingOptionUi; Update-CommandPreview })

function Update-AudioTimingOptionUi {
    $timing = Get-AudioTimingMode
    $forcesNoClock = $timing -in @('WASAPI no pipeline clock','WASAPI no clock + retimestamp')
    $synthetic = ($timing -eq 'Synthetic silent audio')

    $cmbAudioClockMode.Enabled = (-not $forcesNoClock -and -not $synthetic)
    $cmbAudioSlaveMethod.Enabled = (-not $synthetic)
    $chkWasapiLowLatencyOverride.Enabled = (-not $synthetic)
    $chkAudioBufferOverride.Enabled = (-not $synthetic)
    $chkAudioLatencyOverride.Enabled = (-not $synthetic)
    $numAudioBufferMs.Enabled = (-not $synthetic -and $chkAudioBufferOverride.Checked)
    $numAudioLatencyMs.Enabled = (-not $synthetic -and $chkAudioLatencyOverride.Checked)
    $numAudioSampleRate.Enabled = $chkAudioSampleRateOverride.Checked
}

$numAudioBufferMs.Add_ValueChanged($previewHandler)
$numAudioLatencyMs.Add_ValueChanged($previewHandler)
$numAudioSampleRate.Add_ValueChanged($previewHandler)
$cmbDirectWebRtcOpusMode.Add_SelectedIndexChanged($previewHandler)
$cmbDirectWebRtcOpusFrameMs.Add_SelectedIndexChanged($previewHandler)
$cmbDirectWebRtcOpusAudioType.Add_SelectedIndexChanged($previewHandler)
$chkDirectWebRtcOpusFec.Add_CheckedChanged($previewHandler)
$chkDirectWebRtcOpusDtx.Add_CheckedChanged($previewHandler)

$cmbAudioCodec.Add_SelectedIndexChanged({
    if (-not $script:SuppressAudioCodecChange) {
        $protocol = [string]$cmbProtocol.SelectedItem
        $selected = [string]$cmbAudioCodec.SelectedItem
        if (
            -not [string]::IsNullOrWhiteSpace($protocol) -and
            -not [string]::IsNullOrWhiteSpace($selected) -and
            (Test-AudioCodecProtocolCompatibility `
                -AudioCodecName $selected `
                -Protocol $protocol)
        ) {
            $script:ProtocolAudioCodecs[$protocol] = $selected
        }
        Update-AudioCodecChoices -PreserveCurrent
    }
})
$numMonitor.Add_ValueChanged({ Update-CaptureModeUi; Update-CommandPreview })
$chkCursor.Add_CheckedChanged($previewHandler)
$cmbCaptureMethod.Add_SelectedIndexChanged({
    Sync-LegacyFullscreenFlag
    if (Test-FullscreenCaptureMode) {
        $null = Resolve-FullscreenCaptureTarget -Quiet
    }
    else {
        $script:CaptureWindowHwnd = [IntPtr]::Zero
        $script:CaptureWindowTitle = ''
        Update-CaptureModeUi
    }
    Update-CommandPreview
})
$chkFullscreenApp.Add_CheckedChanged({
    if ($chkFullscreenApp.Checked -and $cmbCaptureMethod.SelectedItem -ne 'Fullscreen App - D3D11 / WGC') {
        $cmbCaptureMethod.SelectedItem = 'Fullscreen App - D3D11 / WGC'
    }
    elseif (-not $chkFullscreenApp.Checked -and (Test-FullscreenCaptureMode)) {
        $cmbCaptureMethod.SelectedItem = $script:DefaultCaptureMethodName
    }
})
$chkPreview.Add_CheckedChanged({
    if ($script:LoadingSettings) {
        Update-CommandPreview
        return
    }

    if ($chkPreview.Checked) {
        Reset-DynamicScenePreviewFallback
    }

    if ($script:ControlledLiveStreamActive -and -not $chkPreview.Checked) {
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Preview disabled; restarting the live stream without controlled live scene editing."
        Stop-GstStream -Restart
        Update-CommandPreview
        return
    }

    if ($script:DynamicScenePreviewActive -and -not $chkPreview.Checked) {
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Preview disabled; stopping dynamic scene preview."
        Stop-DynamicScenePreview
        Update-CommandPreview
        return
    }

    if ($script:GstProcess -and -not $script:GstProcess.HasExited) {
        if ($script:PreviewOnlyMode -and -not $chkPreview.Checked) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Preview disabled; stopping local preview."
            Stop-GstStream
        }
        elseif ($script:PipelineHasPreview) {
            Set-PreviewVisibility
            $previewState = if ($chkPreview.Checked) { 'shown' } else { 'hidden' }
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Preview $previewState without restarting stream."
        }
        elseif ($chkPreview.Checked -and $chkHidePreviewDuringStream.Checked -and (Test-TransportEnabled)) {
            $previewPlaceholder.Visible = $true
            $previewPlaceholder.Text = 'Preview hidden during stream'
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Preview remains hidden because Hide preview during stream is enabled."
        }
        elseif ($chkPreview.Checked) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Preview enabled; restarting stream to add preview pipeline branch."
            $lowerTabs.SelectedTab = $tabLog
            Stop-GstStream -Restart
        }
        else {
            $previewPlaceholder.Visible = $true
            $previewPlaceholder.Text = 'Preview disabled for this pipeline'
        }
    }
    else {
        if ($chkPreview.Checked) {
            $previewPlaceholder.Text = 'Starting local preview...'
            $lowerTabs.SelectedTab = $tabLog
            Sync-StandalonePreviewState
        }
        else {
            $previewPlaceholder.Text = 'Preview disabled for this pipeline'
        }
    }

    Update-CommandPreview
})
$chkHidePreviewDuringStream.Add_CheckedChanged({
    if ($script:LoadingSettings) {
        Update-CommandPreview
        return
    }

    if ($script:ControlledLiveStreamActive) {
        Sync-ControlledLivePreviewLayout
        $previewState = if ($chkHidePreviewDuringStream.Checked) { 'shown only in the live Scene editor' } else { 'shown throughout the UI' }
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Controlled live preview $previewState without restarting the stream."
        Update-CommandPreview
        return
    }

    if ($script:GstProcess -and -not $script:GstProcess.HasExited -and -not $script:PreviewOnlyMode) {
        if ($script:PipelineHasPreview) {
            Set-PreviewVisibility
            $previewState = if ($chkHidePreviewDuringStream.Checked) { 'hidden during stream' } else { 'shown during stream' }
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Preview $previewState without restarting stream."
        }
        elseif ((-not $chkHidePreviewDuringStream.Checked) -and $chkPreview.Checked) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Hide preview during stream disabled; restarting stream to add preview pipeline branch."
            $lowerTabs.SelectedTab = $tabLog
            Stop-GstStream -Restart
        }
    }

    Update-CommandPreview
})
$chkAutoRestart.Add_CheckedChanged($previewHandler)
$chkVerbose.Add_CheckedChanged($previewHandler)
$chkDiskProcessLogging.Add_CheckedChanged($previewHandler)
$numWidth.Add_ValueChanged($previewHandler)
$numHeight.Add_ValueChanged($previewHandler)
$numFps.Add_ValueChanged($previewHandler)
$numVideoBitrate.Add_ValueChanged($previewHandler)
$cmbRateControl.Add_SelectedIndexChanged({ Update-EncoderUi })
$numMaxVideoBitrate.Add_ValueChanged($previewHandler)
$numConstantQp.Add_ValueChanged($previewHandler)
$numGopSeconds.Add_ValueChanged($previewHandler)
$chkUnifiedBridgeKeyframeGuard.Add_CheckedChanged({ Update-UnifiedBridgeKeyframeUi; Update-CommandPreview })
$numUnifiedBridgeKeyframeIntervalMs.Add_ValueChanged($previewHandler)
$cmbPreset.Add_SelectedIndexChanged($previewHandler)
$cmbProfile.Add_SelectedIndexChanged($previewHandler)
$cmbEncoderTune.Add_SelectedIndexChanged({ Update-EncoderUi })
$cmbMultipass.Add_SelectedIndexChanged($previewHandler)
$cmbVideoPipelineClockMode.Add_SelectedIndexChanged($previewHandler)
$cmbVideoTimestampMode.Add_SelectedIndexChanged($previewHandler)
$cmbVideoSyncMode.Add_SelectedIndexChanged($previewHandler)
$numVbvBuffer.Add_ValueChanged($previewHandler)
$numBFrames.Add_ValueChanged({ Update-EncoderUi })
$chkLookAhead.Add_CheckedChanged({ Update-EncoderUi })
$numLookAheadFrames.Add_ValueChanged({ Update-EncoderUi })
$chkAdaptiveQuantization.Add_CheckedChanged({ Update-EncoderUi })
$chkTemporalAq.Add_CheckedChanged({ Update-EncoderUi })
$numAqStrength.Add_ValueChanged({ Update-EncoderUi })
$txtCustomEncoderOptions.Add_TextChanged($previewHandler)
$numSrtLatency.Add_ValueChanged($previewHandler)
$cmbRtspTransport.Add_SelectedIndexChanged($previewHandler)
$chkDesktopAudio.Add_CheckedChanged({
    Update-AudioCodecChoices -PreserveCurrent
})
$chkAudioMixerMode.Add_CheckedChanged($previewHandler)
$numDesktopVolume.Add_ValueChanged($previewHandler)
$chkMic.Add_CheckedChanged({
    Update-AudioCodecChoices -PreserveCurrent
})
$numMicVolume.Add_ValueChanged($previewHandler)
$cmbDesktopAudioDevice.Add_SelectedIndexChanged($previewHandler)
$cmbMicAudioDevice.Add_SelectedIndexChanged($previewHandler)
$btnRefreshAudioDevices.Add_Click({
    try {
        Refresh-AudioDevices
        Save-Settings
    }
    catch {
        Append-Log "Audio device refresh button failed: $($_.Exception.Message)"
        if ($lblAudioDeviceStatus) {
            $lblAudioDeviceStatus.Text = 'Audio device refresh failed; see log'
            $lblAudioDeviceStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
    }
})
$numAudioBitrate.Add_ValueChanged($previewHandler)
$chkStartMediaMtx.Add_CheckedChanged({
    Update-MediaMtxUi
    Update-CommandPreview
})

foreach ($control in @(
    $txtDirectWebRtcSignalingHost,
    $numDirectWebRtcSignalingPort,
    $numDirectWebRtcSplitAudioSignalingPort,
    $chkDirectWebRtcSharedSignaling,
    $chkSplitClockSignalingOverrides,
    $cmbSplitVideoClockSignaling,
    $cmbSplitAudioClockSignaling,
    $cmbDirectWebRtcMediaStreamGrouping,
    $txtDirectWebRtcVideoMediaStreamId,
    $txtDirectWebRtcAudioMediaStreamId,
    $chkDirectWebRtcUnifiedPublisher,
    $numDirectWebRtcBridgeVideoPort,
    $numDirectWebRtcBridgeAudioPort,
    $numDirectWebRtcBridgeJitterMs,
    $numDirectWebRtcPublisherQueueMs,
    $chkDirectWebRtcAudioBridgePacing,
    $chkDirectWebRtcControlDataChannel,
    $cmbDirectWebRtcBundlePolicy,
    $numDirectWebRtcInternalRtpMtu,
    $chkDirectWebRtcInternalRepeatHeaders,
    $txtDirectWebRtcStun,
    $chkDirectWebRtcTurnEnabled,
    $txtDirectWebRtcTurn,
    $txtDirectWebRtcWebPath,
    $cmbDirectWebRtcBundledWebMode,
    $txtDirectWebRtcBundledWebDirectory,
    $cmbDirectWebRtcWorkingWebMode,
    $txtDirectWebRtcWebDirectory,
    $cmbDirectWebRtcCongestion,
    $cmbDirectWebRtcMitigation,
    $cmbWebRtcRecoveryMode,
    $cmbWebRtcSenderQueueMode,
    $cmbThreadingProfile,
    $cmbGstProcessPriority,
    $cmbQueueLeakMode,
    $chkDirectWebRtcFec,
    $chkDirectWebRtcRetransmission,
    $cmbJbufWatchdogMode,
    $numJbufMaxMs,
    $numDirectWebRtcPlayerJitterMs,
    $numDirectWebRtcVideoJitterMs,
    $chkPlayerStatsOverlay,
    $chkPlayerJbufDebug,
    $numLiveEdgeAverageSec,
    $numLiveEdgeGreenMs,
    $numLiveEdgeYellowMs,
    $chkPlayerUrlOverrides,
    $cmbDirectWebRtcOpusMode,
    $cmbDirectWebRtcOpusFrameMs,
    $cmbDirectWebRtcOpusAudioType,
    $chkDirectWebRtcOpusFec,
    $chkDirectWebRtcOpusDtx
)) {
    if ($control -is [System.Windows.Forms.TextBox]) {
        $control.Add_TextChanged({ Update-PlayerConfigFromUi })
    }
    elseif ($control -is [System.Windows.Forms.NumericUpDown]) {
        $control.Add_ValueChanged({ Update-PlayerConfigFromUi })
    }
    elseif ($control -is [System.Windows.Forms.ComboBox]) {
        $control.Add_SelectedIndexChanged({ Update-PlayerConfigFromUi })
    }
    elseif ($control -is [System.Windows.Forms.CheckBox]) {
        $control.Add_CheckedChanged({ Update-PlayerConfigFromUi })
    }
}

$btnBrowseDirectWebRtcBundledWebDirectory.Add_Click({
    try {
        $initial = $txtDirectWebRtcBundledWebDirectory.Text
        if ([string]::IsNullOrWhiteSpace($initial)) { $initial = Get-BundledDirectWebRtcWebDirectory }
        $picked = Select-DirectWebRtcFolderPath -Title 'Select bundled/static gstwebrtc-api\dist source folder' -InitialPath $initial -AllowNewFolder:$false
        if ([string]::IsNullOrWhiteSpace($picked)) { return }
        $txtDirectWebRtcBundledWebDirectory.Text = $picked
        $cmbDirectWebRtcBundledWebMode.SelectedItem = 'Manual path'
        if (Test-DirectWebRtcWebDirectory $picked) {
            Append-Log "Bundled Web UI source selected: $picked"
        }
        else {
            Append-Log "Bundled Web UI source selected, but index.html/player.js were not found: $picked"
            [System.Windows.Forms.MessageBox]::Show('Selected bundled source must contain index.html and player.js.', $script:AppName, 'OK', 'Warning') | Out-Null
        }
        Save-Settings
        Update-PlayerConfigFromUi
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not select bundled Web UI source: $($_.Exception.Message)", $script:AppName, 'OK', 'Warning') | Out-Null
    }
})

$btnDetectDirectWebRtcBundledWebDirectory.Add_Click({
    try {
        $found = ''
        if (-not [string]::IsNullOrWhiteSpace($script:ApplicationDirectory)) {
            $candidate = Join-Path $script:ApplicationDirectory 'gstwebrtc-api\dist'
            if (Test-DirectWebRtcWebDirectory $candidate) { $found = [System.IO.Path]::GetFullPath($candidate) }
        }
        if ([string]::IsNullOrWhiteSpace($found)) { $found = Find-DirectWebRtcWebDirectory $txtGstPath.Text }
        if ([string]::IsNullOrWhiteSpace($found)) {
            Append-Log 'Bundled Web UI source was not found. Need gstwebrtc-api\dist beside the app/script or select it manually.'
            [System.Windows.Forms.MessageBox]::Show('Could not find bundled gstwebrtc-api\dist automatically. Select the bundled source folder manually.', $script:AppName, 'OK', 'Warning') | Out-Null
        }
        else {
            $txtDirectWebRtcBundledWebDirectory.Text = $found
            $cmbDirectWebRtcBundledWebMode.SelectedItem = 'Manual path'
            Append-Log "Bundled Web UI source detected: $found"
        }
        Save-Settings
        Update-PlayerConfigFromUi
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not detect bundled Web UI source: $($_.Exception.Message)", $script:AppName, 'OK', 'Warning') | Out-Null
    }
})

$btnBrowseDirectWebRtcWebDirectory.Add_Click({
    try {
        $initial = $txtDirectWebRtcWebDirectory.Text
        if ([string]::IsNullOrWhiteSpace($initial)) { $initial = Get-DefaultDirectWebRtcWorkingWebDirectory }
        $picked = Select-DirectWebRtcFolderPath -Title 'Select writable working/served Web UI directory' -InitialPath $initial -AllowNewFolder:$true
        if ([string]::IsNullOrWhiteSpace($picked)) { return }
        $txtDirectWebRtcWebDirectory.Text = $picked
        $cmbDirectWebRtcWorkingWebMode.SelectedItem = 'Manual path'
        if (-not (Test-DirectWebRtcWebDirectoryWritable $picked)) {
            Append-Log "Working Web UI directory selected, but it is not writable: $picked"
            [System.Windows.Forms.MessageBox]::Show('Selected working Web UI directory is not writable.', $script:AppName, 'OK', 'Warning') | Out-Null
            return
        }
        Save-Settings
        $source = Get-DirectWebRtcSourceWebDirectory
        $served = Ensure-DirectWebRtcRuntimeWebDirectory $source
        Write-DirectWebRtcWebClientConfig
        Append-Log "Working Web UI directory selected: $picked; serving from $served"
        Update-DirectWebRtcUi
        Update-CommandPreview
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not select working Web UI directory: $($_.Exception.Message)", $script:AppName, 'OK', 'Warning') | Out-Null
    }
})

$btnDetectDirectWebRtcWebDirectory.Add_Click({
    try {
        $working = Get-DefaultDirectWebRtcWorkingWebDirectory
        $txtDirectWebRtcWebDirectory.Text = $working
        $cmbDirectWebRtcWorkingWebMode.SelectedItem = 'Auto: LocalAppData'
        if (-not (Test-DirectWebRtcWebDirectoryWritable $working)) { throw "Working directory is not writable: $working" }
        $source = Get-DirectWebRtcSourceWebDirectory
        $served = Ensure-DirectWebRtcRuntimeWebDirectory $source
        Write-DirectWebRtcWebClientConfig
        Save-Settings
        Append-Log "Working Web UI directory detected/created: $served"
        Update-DirectWebRtcUi
        Update-CommandPreview
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not detect/create working Web UI directory: $($_.Exception.Message)", $script:AppName, 'OK', 'Warning') | Out-Null
    }
})


$btnRefreshDirectWebRtcWebUi.Add_Click({
    try {
        $source = Get-DirectWebRtcSourceWebDirectory
        $served = Ensure-DirectWebRtcRuntimeWebDirectory -SourceDirectory $source -ForceRefresh
        Write-DirectWebRtcWebClientConfig
        Update-DirectWebRtcWebUiStatus
        Append-Log "Direct WebRTC web UI force refresh requested from Player tab: $source -> $served"
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not refresh Direct WebRTC web UI: $($_.Exception.Message)", $script:AppName, 'OK', 'Warning') | Out-Null
    }
})

$btnOpenDirectWebRtcServedDir.Add_Click({
    try {
        $served = Get-DirectWebRtcWorkingWebDirectory
        if (-not (Test-Path -LiteralPath $served)) { $null = New-Item -ItemType Directory -Path $served -Force }
        Start-Process explorer.exe $served | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not open working/served web UI directory: $($_.Exception.Message)", $script:AppName, 'OK', 'Warning') | Out-Null
    }
})

$btnOpenDirectWebRtcBundledDir.Add_Click({
    try {
        $bundled = Get-BundledDirectWebRtcWebDirectory
        if ([string]::IsNullOrWhiteSpace($bundled)) { throw 'Bundled gstwebrtc-api\dist directory not found beside the app/script.' }
        Start-Process explorer.exe $bundled | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not open bundled web UI directory: $($_.Exception.Message)", $script:AppName, 'OK', 'Warning') | Out-Null
    }
})

$btnOpenDirectWebRtcViewer.Add_Click({
    try {
        Start-Process (Get-DirectWebRtcViewerUrl) | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not open viewer URL: $($_.Exception.Message)", $script:AppName, 'OK', 'Warning') | Out-Null
    }
})

$cmbDirectWebRtcSmoothnessProfile.Add_SelectedIndexChanged({
    Apply-DirectWebRtcSmoothnessProfile
    Update-DirectWebRtcUi
    Update-CommandPreview
})

foreach ($smoothControl in @($numDirectWebRtcPacingMs, $numDirectWebRtcPlayerJitterMs, $numDirectWebRtcVideoJitterMs, $numJbufMaxMs)) {
    $smoothControl.Add_ValueChanged({
        if (-not $script:ApplyingDirectWebRtcSmoothnessProfile -and $cmbDirectWebRtcSmoothnessProfile.SelectedItem -ne 'Custom') { $cmbDirectWebRtcSmoothnessProfile.SelectedItem = 'Custom' }
        Update-PlayerConfigFromUi
    })
}

foreach ($splitPlayerNumeric in @($numSplitAudioStallSeconds, $numSplitAudioWarmupSeconds, $numSplitAvOffsetBaselineMs, $numSplitAvOffsetWarnMs)) {
    $splitPlayerNumeric.Add_ValueChanged({ Update-PlayerConfigFromUi })
}

$numLiveEdgeGreenMs.Add_ValueChanged({
    if ($numLiveEdgeYellowMs.Value -le $numLiveEdgeGreenMs.Value) {
        $numLiveEdgeYellowMs.Value = [decimal]([Math]::Min([int]$numLiveEdgeYellowMs.Maximum, [int]$numLiveEdgeGreenMs.Value + 1))
    }
})
$numLiveEdgeYellowMs.Add_ValueChanged({
    if ($numLiveEdgeYellowMs.Value -le $numLiveEdgeGreenMs.Value) {
        $numLiveEdgeGreenMs.Value = [decimal]([Math]::Max([int]$numLiveEdgeGreenMs.Minimum, [int]$numLiveEdgeYellowMs.Value - 1))
    }
})

foreach ($playerControl in @($chkPlayerStatsOverlay, $chkPlayerJbufDebug, $chkPlayerUrlOverrides, $chkPlayerSeparateHtmlMediaElements, $cmbDirectWebRtcAvPipelineMode, $cmbSplitPlayerSyncMode, $cmbJbufWatchdogMode)) {
    if ($playerControl -is [System.Windows.Forms.CheckBox]) {
        $playerControl.Add_CheckedChanged({ Update-PlayerConfigFromUi })
    }
    elseif ($playerControl -is [System.Windows.Forms.ComboBox]) {
        $playerControl.Add_SelectedIndexChanged({ Update-PlayerConfigFromUi })
    }
}

$cmbThreadingProfile.Add_SelectedIndexChanged({ Apply-ThreadingProfile; Save-Settings })
$cmbThreadBudget.Add_SelectedIndexChanged({ Apply-ThreadBudget; Save-Settings })
foreach ($budgetControl in @($numCpuWorkerLimit,$chkBudgetCaptureQueue,$chkBudgetSenderQueue,$chkBudgetAudioInputQueue,$chkBudgetAudioFinalQueue)) {
    if ($budgetControl -is [System.Windows.Forms.NumericUpDown]) {
        $budgetControl.Add_ValueChanged({
            if ($script:ApplyingThreadBudget) { return }
            if ($cmbThreadBudget.SelectedItem -ne 'Custom') { $cmbThreadBudget.SelectedItem = 'Custom' }
            Update-CommandPreview
            Save-Settings
        })
    }
    else {
        $budgetControl.Add_CheckedChanged({
            if ($script:ApplyingThreadBudget) { return }
            if ($cmbThreadBudget.SelectedItem -ne 'Custom') { $cmbThreadBudget.SelectedItem = 'Custom' }
            Update-CommandPreview
            Save-Settings
        })
    }
}
foreach ($threadingControl in @($cmbGstProcessPriority, $cmbQueueLeakMode, $numCaptureQueueBuffers, $numAudioQueueBuffers, $numAudioQueueCapMs, $chkBufferLatenessTracer)) {
    if ($threadingControl -is [System.Windows.Forms.ComboBox]) {
        $threadingControl.Add_SelectedIndexChanged({
            if (-not $script:ApplyingThreadingProfile -and $cmbThreadingProfile.SelectedItem -ne 'Custom') { $cmbThreadingProfile.SelectedItem = 'Custom' }
            Update-CommandPreview
        })
    }
    elseif ($threadingControl -is [System.Windows.Forms.NumericUpDown]) {
        $threadingControl.Add_ValueChanged({
            if (-not $script:ApplyingThreadingProfile -and $cmbThreadingProfile.SelectedItem -ne 'Custom') { $cmbThreadingProfile.SelectedItem = 'Custom' }
            Update-CommandPreview
        })
    }
    elseif ($threadingControl -is [System.Windows.Forms.CheckBox]) {
        $threadingControl.Add_CheckedChanged({
            if (-not $script:ApplyingThreadingProfile -and $cmbThreadingProfile.SelectedItem -ne 'Custom') { $cmbThreadingProfile.SelectedItem = 'Custom' }
            Update-CommandPreview
        })
    }
}

$cmbGstDebugMode.Add_SelectedIndexChanged({ Update-GstDebugUi; Save-Settings; Update-CommandPreview })
$txtGstDebugSpec.Add_TextChanged({ Save-Settings; Update-CommandPreview })
$chkGstDebugNoColor.Add_CheckedChanged({ Save-Settings; Update-CommandPreview })

foreach ($smoothCombo in @($cmbWebRtcRecoveryMode, $cmbWebRtcSenderQueueMode)) {
    $smoothCombo.Add_SelectedIndexChanged({
        if (-not $script:ApplyingDirectWebRtcSmoothnessProfile -and $cmbDirectWebRtcSmoothnessProfile.SelectedItem -ne 'Custom') { $cmbDirectWebRtcSmoothnessProfile.SelectedItem = 'Custom' }
        if ($cmbWebRtcRecoveryMode.SelectedItem) { Set-WebRtcRecoveryMode ([string]$cmbWebRtcRecoveryMode.SelectedItem) }
        Update-DirectWebRtcUi
        Update-CommandPreview
    })
}

$btnResetWebRtcSane.Add_Click({ Reset-WebRtcSaneDefaults; Save-Settings; Append-Log 'WebRTC/receiver knobs and Video sender queue reset to sane defaults.' })

$btnCopyDirectWebRtcViewer.Add_Click({
    try {
        [System.Windows.Forms.Clipboard]::SetText((Get-DirectWebRtcViewerUrl))
        Append-Log "Direct WebRTC viewer URL copied: $(Get-DirectWebRtcViewerUrl)"
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not copy viewer URL: $($_.Exception.Message)", $script:AppName, 'OK', 'Warning') | Out-Null
    }
})

$chkRecordingEnabled.Add_CheckedChanged({ Update-RecordingUi })
$txtRecordingDirectory.Add_TextChanged($previewHandler)
$txtRecordingTemplate.Add_TextChanged($previewHandler)
$cmbRecordingEncoder.Add_SelectedIndexChanged({ Update-RecordingUi })
$cmbRecordingPreset.Add_SelectedIndexChanged($previewHandler)
$cmbRecordingProfile.Add_SelectedIndexChanged($previewHandler)
$numRecordingWidth.Add_ValueChanged($previewHandler)
$numRecordingHeight.Add_ValueChanged($previewHandler)
$numRecordingFps.Add_ValueChanged($previewHandler)
$numRecordingVideoBitrate.Add_ValueChanged($previewHandler)
$cmbRecordingRateControl.Add_SelectedIndexChanged({ Update-RecordingUi })
$numRecordingMaxVideoBitrate.Add_ValueChanged($previewHandler)
$numRecordingConstantQp.Add_ValueChanged($previewHandler)
$numRecordingGopSeconds.Add_ValueChanged($previewHandler)
$numRecordingBFrames.Add_ValueChanged({ Update-RecordingUi })
$cmbRecordingTune.Add_SelectedIndexChanged({ Update-RecordingUi })
$cmbRecordingMultipass.Add_SelectedIndexChanged($previewHandler)
$chkRecordingLookAhead.Add_CheckedChanged({ Update-RecordingUi })
$numRecordingLookAheadFrames.Add_ValueChanged($previewHandler)
$chkRecordingSpatialAq.Add_CheckedChanged({ Update-RecordingUi })
$chkRecordingTemporalAq.Add_CheckedChanged({ Update-RecordingUi })
$numRecordingAqStrength.Add_ValueChanged($previewHandler)
$numRecordingVbvBuffer.Add_ValueChanged($previewHandler)
$txtRecordingCustomEncoderOptions.Add_TextChanged($previewHandler)
$chkRecordingDesktopAudio.Add_CheckedChanged({ Update-RecordingUi })
$chkRecordingMic.Add_CheckedChanged({ Update-RecordingUi })
$numRecordingAudioBitrate.Add_ValueChanged($previewHandler)

$chkNetworkTuningEnabled.Add_CheckedChanged({ Update-NetworkUi })
$chkNetworkDscp.Add_CheckedChanged({ Update-NetworkUi })
$cmbNetworkProfile.Add_SelectedIndexChanged({ Apply-NetworkProfileToUi })
$btnRefreshNetworkAdapters.Add_Click({ Refresh-NetworkAdapters })
$btnNetworkSnapshot.Add_Click({
    try {
        Save-NetworkSnapshot | Out-Null
        $lowerTabs.SelectedTab = $tabLog
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not create network snapshot.`r`n`r`n$($_.Exception.Message)", $script:AppName, 'OK', 'Warning') | Out-Null
    }
})
$btnNetworkApply.Add_Click({
    $lowerTabs.SelectedTab = $tabLog
    Apply-NetworkTuningForSession | Out-Null
})
$btnNetworkRestore.Add_Click({
    $lowerTabs.SelectedTab = $tabLog
    Restore-NetworkTuning | Out-Null
})
$btnOpenNetworkRecovery.Add_Click({
    try {
        Ensure-NetworkRecoveryDirectory
        Start-Process -FilePath 'explorer.exe' -ArgumentList @($script:NetworkRecoveryDirectory) | Out-Null
    }
    catch {
        Append-Log "Could not open recovery folder: $($_.Exception.Message)"
    }
})
$btnResetTransport.Add_Click({ Reset-TransportDefaults; Save-Settings })
$btnResetVideo.Add_Click({ Reset-VideoDefaults; Save-Settings })
$btnResetAudio.Add_Click({ Reset-AudioDefaults; Save-Settings })
$btnResetRecording.Add_Click({ Reset-RecordingDefaults; Save-Settings })
$btnResetNetwork.Add_Click({ Reset-NetworkDefaults; Save-Settings })
$btnResetOptions.Add_Click({ Reset-OptionsDefaults; Save-Settings })
$btnExportLabConfig.Add_Click({ Export-LabConfiguration })
$btnResetAll.Add_Click({
    $result = [System.Windows.Forms.MessageBox]::Show(
        'Reset all GStreamer Glass app settings to defaults? This will not restore or delete Windows network snapshots.',
        $script:AppName,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) { Reset-AllAppDefaults }
})

$previewPanel.Add_Resize({
    if ($script:SceneEditorCanvasHostedInPreview) {
        Resize-DynamicScenePreviewCardCanvas
    }
    elseif ($script:PreviewHwnd -ne [IntPtr]::Zero) {
        Set-PreviewVisibility
    }
})

$btnBrowseGst.Add_Click({
    try {
        $selectedPath = [GstExecutableBrowser]::SelectGstLaunch($txtGstPath.Text)
        if (-not [string]::IsNullOrWhiteSpace($selectedPath)) {
            $txtGstPath.Text = $selectedPath
            Append-Log "Selected GStreamer executable: $selectedPath"
            if (Test-GstLaunchPath $selectedPath) {
                Prepare-GStreamerRuntime -GstPath $selectedPath
            }
        }
    }
    catch {
        $message = "Could not open the GStreamer executable browser.`r`n`r`n$($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            $message,
            $script:AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        Append-Log "Executable browser error: $($_.Exception.ToString())"
    }
})

$btnBrowseMediaMtx.Add_Click({
    try {
        $selectedPath =
            [GstExecutableBrowser]::SelectMediaMtx($txtMediaMtxPath.Text)

        if (-not [string]::IsNullOrWhiteSpace($selectedPath)) {
            $txtMediaMtxPath.Text = $selectedPath
            Append-Log "Selected MediaMTX executable: $selectedPath"
        }
    }
    catch {
        $message =
            "Could not open the MediaMTX executable browser.`r`n`r`n" +
            $_.Exception.Message

        [System.Windows.Forms.MessageBox]::Show(
            $message,
            $script:AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null

        Append-Log "MediaMTX browser error: $($_.Exception.ToString())"
    }
})

$btnBrowseRecordingDirectory.Add_Click({
    try {
        $selectedPath = [GstExecutableBrowser]::SelectFolder(
            $txtRecordingDirectory.Text,
            'Select GStreamer Glass recording folder'
        )

        if (-not [string]::IsNullOrWhiteSpace($selectedPath)) {
            $txtRecordingDirectory.Text = $selectedPath
            Append-Log "Selected recording folder: $selectedPath"
        }
    }
    catch {
        $message =
            "Could not open the recording folder browser.`r`n`r`n" +
            $_.Exception.Message

        [System.Windows.Forms.MessageBox]::Show(
            $message,
            $script:AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null

        Append-Log "Recording folder browser error: $($_.Exception.ToString())"
    }
})

$btnDetectGst.Add_Click({
    $detected = Find-GstLaunch
    $txtGstPath.Text = $detected
    Append-Log "Detected GStreamer executable: $detected"
    if (Test-GstLaunchPath $detected) {
        Prepare-GStreamerRuntime -GstPath $detected
    }
})
$btnCheckGst.Add_Click({
    $lowerTabs.SelectedTab = $tabLog
    Test-GStreamerElements
})

$btnStart.Add_Click({
    $lowerTabs.SelectedTab = $tabLog
    Start-GstStream
})

$btnStop.Add_Click({
    $lowerTabs.SelectedTab = $tabLog
    Stop-GstStream
})

$btnRestart.Add_Click({
    $lowerTabs.SelectedTab = $tabLog
    Stop-GstStream -Restart
})
$btnCopyCommand.Add_Click({
    try {
        [System.Windows.Forms.Clipboard]::SetText($txtCommand.Text)
        $lowerTabs.SelectedTab = $tabCommand
        $statusLabel.Text = 'Command copied'
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkBlue
    }
    catch {
        Append-Log "Clipboard error: $($_.Exception.Message)"
    }
})
$btnClearLog.Add_Click({ $txtLog.Clear() })

$btnOpenLogs.Add_Click({
    try {
        if (-not (Test-Path -LiteralPath $script:LogDirectory)) {
            if (-not (Test-ProcessDiskLoggingEnabled)) {
                Append-Log 'No process log folder exists. Disk process logging is disabled.'
                $lowerTabs.SelectedTab = $tabLog
                return
            }

            Ensure-ProcessLogDirectory
        }

        Start-Process `
            -FilePath 'explorer.exe' `
            -ArgumentList @($script:LogDirectory) |
            Out-Null
    }
    catch {
        Append-Log "Could not open log folder: $($_.Exception.Message)"
        $lowerTabs.SelectedTab = $tabLog
    }
})

$notifyIcon.Add_MouseDoubleClick({
    param($sender, $eventArgs)
    if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        Show-MainWindow
    }
})
$trayMenu.Add_Opening({ Update-TrayMenuState })
$trayShowItem.Add_Click({ Show-MainWindow })
$trayStartItem.Add_Click({
    $lowerTabs.SelectedTab = $tabLog
    Start-GstStream
})

$trayStopItem.Add_Click({
    $lowerTabs.SelectedTab = $tabLog
    Stop-GstStream
})

$trayRestartItem.Add_Click({
    $lowerTabs.SelectedTab = $tabLog
    Stop-GstStream -Restart
})
$trayExitItem.Add_Click({
    try {
        $form.ShowInTaskbar = $true
        $form.Show()
    }
    catch {}
    $form.Close()
})

$form.Add_Resize({
    if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
        $script:DynamicPreviewUiReady = $false
    }

    if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized -and $script:PreviewOnlyMode) {
        Sync-StandalonePreviewState
    }

    if (
        $chkMinimizeToTray.Checked -and
        $form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized
    ) {
        if ($script:StartupTrayHidePending) {
            Hide-MainWindowToTray -SuppressBalloon
            $script:StartupTrayHidePending = $false
        }
        else {
            Hide-MainWindowToTray
        }
    }
    elseif ($form.Visible -and $script:GstProcess -and -not $script:GstProcess.HasExited) {
        Set-PreviewVisibility
    }
    elseif (
        $form.Visible -and
        $form.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized -and
        -not ($script:GstProcess -and -not $script:GstProcess.HasExited)
    ) {
        $null = $form.BeginInvoke([Action]{
            try {
                if (
                    $form.Visible -and
                    $form.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized -and
                    -not $script:StartupTrayHidePending -and
                    -not $script:TrayRestoreInProgress
                ) {
                    $script:DynamicPreviewUiReady = $true
                }
                Sync-StandalonePreviewState -Quiet
            }
            catch {}
        })
    }

    if ($script:SceneWorkspaceActive) {
        Invoke-ScenePreviewRedraw -Quiet
    }
})

$form.Add_VisibleChanged({
    if ($form.Visible -and $script:GstProcess -and -not $script:GstProcess.HasExited) {
        $null = $form.BeginInvoke([Action]{
            try {
                if ($script:PreviewParked) {
                    Restore-PreviewWindowFromParking
                }
                Try-AttachPreview
                Set-PreviewVisibility
            }
            catch {}
        })
    }
    elseif ($form.Visible -and -not ($script:GstProcess -and -not $script:GstProcess.HasExited)) {
        $null = $form.BeginInvoke([Action]{
            try {
                if (
                    $form.Visible -and
                    $form.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized -and
                    -not $script:StartupTrayHidePending -and
                    -not $script:TrayRestoreInProgress
                ) {
                    $script:DynamicPreviewUiReady = $true
                }
                Sync-StandalonePreviewState -Quiet
            }
            catch {}
        })
    }
    elseif (-not $form.Visible -and $script:PreviewOnlyMode) {
        Sync-StandalonePreviewState
    }
    elseif (-not $form.Visible -and $script:PreviewHwnd -ne [IntPtr]::Zero) {
        Park-PreviewWindow
    }
})

$pollTimer = New-Object System.Windows.Forms.Timer
$pollTimer.Interval = 400
$pollTimer.Add_Tick({
    # Drain all four log streams, then append once. Four separate Append-Log calls
    # meant four AppendText + trim-check + forced-scroll passes per tick on the UI
    # thread; batching collapses that to one.
    $pending = Drain-ManagedProcessLogs
    if ($pending) { Append-Log $pending }
    Update-GstThreadCountStatus

    Try-AttachPreview

    if ($script:DynamicScenePreviewActive) {
        $controlledTerminal = $null
        try { $controlledTerminal = [GstControlledScenePreview]::PollTerminalMessage() }
        catch { $controlledTerminal = "bus polling failed: $($_.Exception.Message)" }

        if ($controlledTerminal) {
            Append-Log "Controlled scene compositor terminal message: $controlledTerminal"
            Invoke-DynamicScenePreviewFallback -Reason 'reported a terminal pipeline error'
            return
        }
        if (-not [GstControlledScenePreview]::IsRunning) {
            Invoke-DynamicScenePreviewFallback -Reason 'stopped unexpectedly'
            return
        }
    }

    if (
        $script:MediaMtxProcess -and
        $script:MediaMtxProcess.HasExited
    ) {
        $mediaExitCode = $script:MediaMtxProcess.ExitCode
        Append-Log (
            "[$(Get-Date -Format 'HH:mm:ss')] Managed MediaMTX exited " +
            "unexpectedly with code $mediaExitCode."
        )

        try { $script:MediaMtxProcess.Dispose() } catch {}
        $script:MediaMtxProcess = $null
        $script:MediaMtxPathInUse = ''

        if (($script:GstProcess -and -not $script:GstProcess.HasExited) -or $script:ControlledLiveStreamActive) {
            Append-Log (
                'Stopping the stream because its managed MediaMTX server is no ' +
                'longer running.'
            )

            if ($chkAutoRestart.Checked -or (Test-FullscreenCaptureMode)) {
                Stop-GstStream -Restart
            }
            else {
                Stop-GstStream
            }
        }
        else {
            Remove-ActiveProcessState

            # Nothing left running to produce MediaMTX output. Drain the tail, then
            # stop tracking so we do not reopen dead log files on every tick.
            $mediaFinalText = Drain-ManagedProcessLogs
            if ($mediaFinalText) { Append-Log $mediaFinalText }
            $script:MediaMtxStdOutPath = $null
            $script:MediaMtxStdErrPath = $null
            $script:MediaMtxStdOutPosition = [int64]0
            $script:MediaMtxStdErrPosition = [int64]0
        }
    }

    if ((Test-FullscreenCaptureMode) -and $script:GstProcess -and -not $script:GstProcess.HasExited -and (Get-Date) -ge $script:NextFullscreenProbe) {
        $script:NextFullscreenProbe = (Get-Date).AddSeconds(1)

        if ($script:CaptureWindowHwnd -ne [IntPtr]::Zero -and -not [GstPreviewNative]::WindowExists($script:CaptureWindowHwnd)) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Fullscreen application closed; stopping the pipeline and waiting for another fullscreen application."
            $script:CaptureWindowHwnd = [IntPtr]::Zero
            $script:CaptureWindowTitle = ''
            Update-CaptureModeUi
            Stop-GstStream -Restart
        }
        else {
            $captureGstPid = if ((Test-DirectWebRtcUnifiedPublisher) -and $script:GstVideoProcess -and -not $script:GstVideoProcess.HasExited) { $script:GstVideoProcess.Id } else { $script:GstProcess.Id }
            $candidate = [GstPreviewNative]::FindTopmostFullscreenWindow($PID, $captureGstPid)
            if ($candidate -ne [IntPtr]::Zero -and $candidate -ne $script:CaptureWindowHwnd) {
                $newTitle = [GstPreviewNative]::GetWindowTitleSafe($candidate)
                Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Fullscreen application changed to '$newTitle'; rebuilding the pipeline."
                $script:CaptureWindowHwnd = $candidate
                $script:CaptureWindowTitle = $newTitle
                Update-CaptureModeUi
                Stop-GstStream -Restart
            }
        }
    }

    if ($script:GstVideoProcess -and $script:GstVideoProcess.HasExited -and $script:GstProcess -and -not $script:GstProcess.HasExited) {
        $videoExitCode = $script:GstVideoProcess.ExitCode
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Split video bridge exited unexpectedly with code $videoExitCode; stopping the complete topology."
        try { $script:GstVideoProcess.Dispose() } catch {}
        $script:GstVideoProcess = $null
        if ($chkAutoRestart.Checked -or (Test-FullscreenCaptureMode)) { Stop-GstStream -Restart } else { Stop-GstStream }
        return
    }

    if ($script:GstAudioProcess -and $script:GstAudioProcess.HasExited -and $script:GstProcess -and -not $script:GstProcess.HasExited) {
        $audioExitCode = $script:GstAudioProcess.ExitCode
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Split audio pipeline exited unexpectedly with code $audioExitCode; stopping the complete topology."
        try { $script:GstAudioProcess.Dispose() } catch {}
        $script:GstAudioProcess = $null
        if ($chkAutoRestart.Checked -or (Test-FullscreenCaptureMode)) { Stop-GstStream -Restart } else { Stop-GstStream }
        return
    }

    if ($script:GstProcess -and $script:GstProcess.HasExited) {
        $exitCode = $script:GstProcess.ExitCode
        $wasRequested = $script:StopRequested
        $wasPreviewOnly = [bool]$script:PreviewOnlyMode
        $wasControlledLive = [bool]$script:ControlledLiveStreamActive

        if ($wasControlledLive) {
            Close-ControlledLiveWorkerPipe
            $script:ControlledLiveStreamActive = $false
            $script:ControlledLivePreviewSurfaceHwnd = [IntPtr]::Zero
            $script:ControlledLivePreviewAppliedSize = [System.Drawing.Size]::Empty
        }

        if ($script:GstVideoProcess -and -not $script:GstVideoProcess.HasExited) { try { Stop-ProcessTreeById -ProcessId $script:GstVideoProcess.Id } catch {} }
        if ($script:GstAudioProcess -and -not $script:GstAudioProcess.HasExited) { try { Stop-ProcessTreeById -ProcessId $script:GstAudioProcess.Id } catch {} }
        try { if ($script:GstVideoProcess) { $script:GstVideoProcess.Dispose() } } catch {}
        try { if ($script:GstAudioProcess) { $script:GstAudioProcess.Dispose() } } catch {}
        $script:GstVideoProcess = $null
        $script:GstAudioProcess = $null

        try { $script:GstProcess.Dispose() } catch {}
        $script:GstProcess = $null
        Stop-ManagedMediaMtx -Quiet
        Remove-ActiveProcessState

        # Final drain, then stop tracking these logs. The paths were previously left
        # populated after exit, so every subsequent tick reopened and re-seeked four
        # dead files forever at 2.5 Hz.
        $finalText = Drain-ManagedProcessLogs
        if ($finalText) { Append-Log $finalText }
        $script:StdOutPath = $null
        $script:StdErrPath = $null
        $script:StdOutVideoPath = $null
        $script:StdErrVideoPath = $null
        $script:StdOutPosition = [int64]0
        $script:StdErrPosition = [int64]0
        $script:StdOutVideoPosition = [int64]0
        $script:StdErrVideoPosition = [int64]0
        $script:MediaMtxStdOutPath = $null
        $script:MediaMtxStdErrPath = $null
        $script:MediaMtxStdOutPosition = [int64]0
        $script:MediaMtxStdErrPosition = [int64]0

        if ($wasRequested -and $chkNetworkRestoreOnStop.Checked) { Restore-NetworkTuning -Quiet | Out-Null }
        $script:PreviewHwnd = [IntPtr]::Zero
        $script:PreviewOnlyMode = $false
        $script:ForceLocalPreviewMode = $false
        Reset-PreviewAppliedState
        $previewPlaceholder.Visible = $true
        $previewPlaceholder.Text = if ($wasPreviewOnly -and -not $wasRequested) { 'Preview failed' } else { 'Preview stopped' }
        Set-RunState $false

        if ($wasRequested) {
            $statusLabel.Text = 'Stopped'
            $statusLabel.ForeColor = [System.Drawing.Color]::Black
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Pipeline stopped."
            $null = $form.BeginInvoke([Action]{
                try { Sync-StandalonePreviewState -Quiet } catch {}
            })
        }
        elseif ($wasPreviewOnly) {
            $script:RestartAt = $null
            $statusLabel.Text = "Preview exited - code $exitCode"
            $statusLabel.ForeColor = [System.Drawing.Color]::DarkRed
            $lowerTabs.SelectedTab = $tabLog
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Standalone preview exited unexpectedly with code $exitCode; no stream restart will be scheduled for a preview-only failure."
        }
        else {
            $statusLabel.Text = "Pipeline exited - code $exitCode"
            $statusLabel.ForeColor = [System.Drawing.Color]::DarkRed
            $lowerTabs.SelectedTab = $tabLog
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Pipeline exited unexpectedly with code $exitCode."

            if ($wasControlledLive) {
                $script:SuppressControlledLiveStream = $true
                $script:RestartAt = (Get-Date).AddMilliseconds(800)
                Append-Log 'Controlled live worker failure latched; restarting with the legacy external launcher.'
            }
            elseif ((Test-FullscreenCaptureMode) -or $chkAutoRestart.Checked) {
                $script:RestartAt = (Get-Date).AddSeconds(2)
                if (Test-FullscreenCaptureMode) {
                    $script:WaitingForFullscreen = $true
                    Set-WaitingForFullscreenState
                    Append-Log 'Fullscreen capture will retry every 2 seconds until an application is available.'
                }
                else {
                    Append-Log 'Automatic full restart scheduled in 2 seconds.'
                }
            }
        }

        $script:StopRequested = $false
    }

    if (-not $script:GstProcess -and $script:RestartAt -and (Get-Date) -ge $script:RestartAt) {
        $script:RestartAt = $null
        Start-GstStream -Automatic
    }
})
$pollTimer.Start()

$form.Add_Shown({
    Refresh-NetworkAdapters
    Refresh-WebcamDevices
    Load-Settings
    # Repair legacy configs that contain StartMinimized=true alongside
    # MinimizeToTray=false, then write the corrected invariant immediately.
    Enforce-StartMinimizedTrayInvariant -Persist
    Update-GstDebugUi
    Initialize-GstJob
    Stop-StaleManagedProcesses
    if (Test-FullscreenCaptureMode) {
        $null = Resolve-FullscreenCaptureTarget -Quiet
    }
    Update-CaptureModeUi
    Update-TransportUi
    Update-AudioCodecChoices
    Update-AudioTimingOptionUi
    Update-EncoderUi
    Update-RecordingUi
    Update-NetworkUi
    Update-SceneUi
    Update-CommandPreview
    Update-TrayMenuState
    Check-PendingNetworkRecovery
    Append-Log "Application icon: $($script:AppIconSource)"

    if ($chkStartMinimized.Checked) {
        # Do not let dynamic preview processes touch hidden/zero-sized controls
        # during startup. Show-MainWindow enables them after a real restore.
        $script:DynamicPreviewUiReady = $false
        $null = $form.BeginInvoke([Action]{
            Apply-StartMinimized
        })
    }
    elseif ($script:StartupTrayHidePending) {
        $script:StartupTrayHidePending = $false
        $script:DynamicPreviewUiReady = $true
        try {
            $form.Opacity = 1
            $form.ShowInTaskbar = $true
        }
        catch {}
    }
    else {
        $script:DynamicPreviewUiReady = $true
        Sync-StandalonePreviewState -Quiet
    }
})

function Invoke-ApplicationCleanup {
    if ($script:ExitCleanupStarted) {
        return
    }

    $script:ExitCleanupStarted = $true
    $script:WaitingForFullscreen = $false
    $script:RestartAt = $null

    try {
        $chkAutoRestart.Checked = $false
    }
    catch {}

    try {
        if ($script:ControlledLiveStreamActive) {
            $script:ControlledLiveStreamActive = $false
        }
        Stop-DynamicScenePreview -Quiet
    }
    catch {}

    try {
        if ($script:GstVideoProcess -and -not $script:GstVideoProcess.HasExited) {
            Stop-ProcessTreeById -ProcessId $script:GstVideoProcess.Id
            try { $script:GstVideoProcess.WaitForExit(3000) | Out-Null } catch {}
        }
        if ($script:GstAudioProcess -and -not $script:GstAudioProcess.HasExited) {
            Stop-ProcessTreeById -ProcessId $script:GstAudioProcess.Id
            try { $script:GstAudioProcess.WaitForExit(3000) | Out-Null } catch {}
        }
        if ($script:GstProcess -and -not $script:GstProcess.HasExited) {
            Stop-ProcessTreeById -ProcessId $script:GstProcess.Id
            try { $script:GstProcess.WaitForExit(3000) | Out-Null } catch {}
        }
    }
    catch {}

    Close-ControlledLiveWorkerPipe

    try {
        Stop-ManagedMediaMtx -Quiet
    }
    catch {}

    Remove-ActiveProcessState

    try {
        if ($chkNetworkRestoreOnExit -and $chkNetworkRestoreOnExit.Checked) {
            Restore-NetworkTuning -Quiet | Out-Null
        }
    }
    catch {}

    if ($script:JobHandle -ne [IntPtr]::Zero) {
        try {
            # Closing this handle forcibly terminates every process assigned to the job.
            [GstProcessJob]::CloseJob($script:JobHandle)
        }
        catch {}
        $script:JobHandle = [IntPtr]::Zero
    }

    try {
        $notifyIcon.Visible = $false
        $notifyIcon.Dispose()
    }
    catch {}

    try {
        if ($script:PreviewParkForm -and -not $script:PreviewParkForm.IsDisposed) {
            $script:PreviewParkForm.Close()
            $script:PreviewParkForm.Dispose()
        }

        $trayMenu.Dispose()
    }
    catch {}

    try {
        $form.Icon = $null
        if ($script:AppIcon) {
            $script:AppIcon.Dispose()
            $script:AppIcon = $null
        }
    }
    catch {}
}

$form.Add_FormClosing({
    Save-Settings
    $pollTimer.Stop()
    Invoke-ApplicationCleanup
})

# Prepare the initial minimized-to-tray window state before Application.Run()
# makes the form visible. Previously settings were loaded only from the Shown
# event, so Start minimized could briefly paint the main window before hiding it.
# This small pre-read only affects first-paint visibility; Load-Settings still
# remains the full source of truth during Shown.
try {
    $startupStartMinimized = [bool]$chkStartMinimized.Checked

    if (Test-Path -LiteralPath $script:ConfigPath) {
        $startupSettings =
            Get-Content -LiteralPath $script:ConfigPath -Raw |
            ConvertFrom-Json

        if ($null -ne $startupSettings.StartMinimized) {
            $startupStartMinimized = [bool]$startupSettings.StartMinimized
        }
    }

    # Start minimized always means start in tray. Do not consult the legacy
    # MinimizeToTray value here: the historical true/false mismatch let Resize
    # hide the form before Shown finished initializing controls and previews.
    if ($startupStartMinimized) {
        $script:StartupTrayHidePending = $true
        $form.ShowInTaskbar = $false
        $form.Opacity = 0
    }
}
catch {
    # Startup pre-hide is cosmetic only. If it fails, fall back to normal startup.
    try {
        $script:StartupTrayHidePending = $false
        $form.Opacity = 1
        $form.ShowInTaskbar = $true
    }
    catch {}
}

try {
    # ApplicationContext owns the tray-capable message loop. Hiding MainForm
    # leaves the loop alive, while closing MainForm exits it exactly once. Do
    # not call ExitThread from FormClosed: that can recursively re-enter the
    # WinForms shutdown path and terminate with StackOverflowException.
    $applicationContext = New-Object System.Windows.Forms.ApplicationContext
    $applicationContext.MainForm = $form
    [System.Windows.Forms.Application]::Run($applicationContext)
}
finally {
    Invoke-ApplicationCleanup
}
