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

$script:AppVersion = '3.8.3a'
$script:AppName = "GStreamer Glass v$($script:AppVersion)"
$script:ConfigDirectory = Join-Path $env:APPDATA 'GStreamerBasicWhipStreamer'
$script:ConfigPath = Join-Path $script:ConfigDirectory 'settings.json'
$script:LogDirectory = Join-Path $env:LOCALAPPDATA 'GStreamerBasicWhipStreamer\Logs'
$script:ProcessStatePath = Join-Path $script:ConfigDirectory 'active-gstreamer-process.json'
$script:ProfilesDirectory = Join-Path $script:ConfigDirectory 'Profiles'
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
$script:DefaultDirectWebRtcSmoothnessProfile = 'Sane defaults'
$script:DefaultDirectWebRtcStartBitrateKbps = 0
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


