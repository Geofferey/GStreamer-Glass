#requires -Version 5.1
<#
.SYNOPSIS
    Basic Windows GUI wrapper for low-latency GStreamer desktop streaming.

.DESCRIPTION
    Captures a Windows desktop through D3D11, encodes through a selectable
    hardware or software encoder, and publishes through WHIP, SRT, RTMP, or
    RTSP. Desktop loopback audio and the
    default microphone can be enabled independently. Optional fullscreen-app
    capture targets a topmost fullscreen HWND through Windows Graphics Capture.

    The optional preview uses a leaky GPU-side tee and d3d11videosink. The GUI
    attempts to re-parent the GStreamer preview window into the form. This is an
    experimental convenience layer; streaming does not depend on preview.

    Designed to run as a PS2EXE/PS12EXE no-console application. All GStreamer
    output is redirected to the in-app log and per-run log files.
#>

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

$script:AppVersion = '3.6.7'
$script:AppName = "GStreamer Glass v$($script:AppVersion)"
$script:ConfigDirectory = Join-Path $env:APPDATA 'GStreamerBasicWhipStreamer'
$script:ConfigPath = Join-Path $script:ConfigDirectory 'settings.json'
$script:LogDirectory = Join-Path $env:LOCALAPPDATA 'GStreamerBasicWhipStreamer\Logs'
$script:ProcessStatePath = Join-Path $script:ConfigDirectory 'active-gstreamer-process.json'

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
$script:MediaMtxProcess = $null
$script:MediaMtxPathInUse = ''
$script:StopRequested = $false
$script:RestartAt = $null
$script:StdOutPath = $null
$script:StdErrPath = $null
$script:StdOutPosition = [int64]0
$script:StdErrPosition = [int64]0
$script:MediaMtxStdOutPath = $null
$script:MediaMtxStdErrPath = $null
$script:MediaMtxStdOutPosition = [int64]0
$script:MediaMtxStdErrPosition = [int64]0
$script:PreviewHwnd = [IntPtr]::Zero
$script:PreviewParkForm = $null
$script:PreviewParked = $false
$script:CaptureWindowHwnd = [IntPtr]::Zero
$script:CaptureWindowTitle = ''
$script:NextFullscreenProbe = [datetime]::MinValue
$script:WaitingForFullscreen = $false
$script:JobHandle = [IntPtr]::Zero
$script:ExitCleanupStarted = $false
$script:SuppressProtocolChange = $false
$script:TrayHintShown = $false
$script:LastProtocol = 'WHIP'
$script:ProtocolDestinations = [ordered]@{
    WHIP = 'http://10.0.0.25:8889/live/whip'
    SRT  = 'srt://10.0.0.25:8890?mode=caller&streamid=publish:live'
    RTMP = 'rtmp://10.0.0.25/live'
    RTSP = 'rtsp://10.0.0.25:8554/live'
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

$script:AudioCodecCatalog = [ordered]@{
    'Opus' = [ordered]@{
        Codec = 'OPUS'; Element = 'opusenc'; Parser = ''; Family = 'OPUS'
        Protocols = @('WHIP', 'SRT', 'RTSP')
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
    SRT  = 'Opus'
    RTMP = 'AAC (Media Foundation)'
    RTSP = 'Opus'
}

$script:ProtocolAudioCodecs = [ordered]@{
    WHIP = 'Opus'
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

function Find-GstLaunch {
    # Strom's bundled runtime is preferred when present because it is known to
    # include the plugin set used successfully by this application.
    $stromCandidates = @(Get-StromGstLaunchCandidates)
    if ($stromCandidates.Count -gt 0) {
        return [string]$stromCandidates[0]
    }

    $official = Join-Path $env:SystemDrive 'gstreamer\1.0\msvc_x86_64\bin\gst-launch-1.0.exe'
    if (Test-Path -LiteralPath $official) {
        return $official
    }

    if ($env:GSTREAMER_ROOT_X86_64) {
        $fromEnvironment = Join-Path $env:GSTREAMER_ROOT_X86_64 'bin\gst-launch-1.0.exe'
        if (Test-Path -LiteralPath $fromEnvironment) {
            return $fromEnvironment
        }
    }

    $command = Get-Command 'gst-launch-1.0.exe' -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = @(
        (Join-Path $env:SystemDrive 'gstreamer\1.0\mingw_x86_64\bin\gst-launch-1.0.exe'),
        (Join-Path $env:ProgramFiles 'gstreamer\1.0\msvc_x86_64\bin\gst-launch-1.0.exe'),
        (Join-Path $env:ProgramFiles 'gstreamer\1.0\mingw_x86_64\bin\gst-launch-1.0.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'gstreamer\1.0\msvc_x86_64\bin\gst-launch-1.0.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'gstreamer\1.0\mingw_x86_64\bin\gst-launch-1.0.exe')
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    return $official
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

function Prepare-GStreamerRuntime {
    param([Parameter(Mandatory)][string]$GstPath)

    $binDirectory = Split-Path -Parent $GstPath
    $runtimeRoot = Split-Path -Parent $binDirectory
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
        $env:GST_PLUGIN_PATH_1_0 = $pluginPath
        $env:GST_PLUGIN_SYSTEM_PATH_1_0 = $pluginPath
    }
    else {
        [Environment]::SetEnvironmentVariable('GST_PLUGIN_PATH_1_0', $null, 'Process')
        [Environment]::SetEnvironmentVariable('GST_PLUGIN_SYSTEM_PATH_1_0', $null, 'Process')
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
        $env:GST_PLUGIN_SCANNER_1_0 = $scanner
        $env:GST_PLUGIN_SCANNER = $scanner
    }
    else {
        [Environment]::SetEnvironmentVariable('GST_PLUGIN_SCANNER_1_0', $null, 'Process')
        [Environment]::SetEnvironmentVariable('GST_PLUGIN_SCANNER', $null, 'Process')
    }

    if (-not (Test-Path -LiteralPath $script:ConfigDirectory)) {
        $null = New-Item -ItemType Directory -Path $script:ConfigDirectory -Force
    }

    $runtimeHash = Get-PathHash -Value ([System.IO.Path]::GetFullPath($GstPath))
    $env:GST_REGISTRY_1_0 = Join-Path $script:ConfigDirectory "gstreamer-registry-$runtimeHash.bin"

    Append-Log "GStreamer runtime: $GstPath"
    if ($pluginDirectories.Count -gt 0) {
        Append-Log "Plugin path: $($pluginDirectories -join ';')"
    }
    if ($scanner) {
        Append-Log "Plugin scanner: $scanner"
    }
    Append-Log "Isolated registry: $($env:GST_REGISTRY_1_0)"
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
$form.Size = New-Object System.Drawing.Size(1220, 900)
$form.MinimumSize = New-Object System.Drawing.Size(1000, 720)
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
$toolTip.SetToolTip($txtGstPath, 'Fresh installs prefer Strom bundled GStreamer when found. Each selected runtime receives isolated plugin paths and registry cache.')

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
$null = $cmbProtocol.Items.AddRange(@('WHIP', 'SRT', 'RTMP', 'RTSP'))
$cmbProtocol.SelectedItem = 'WHIP'
$settingsGroup.Controls.Add($cmbProtocol)

$lblDestination = Add-Label $settingsGroup 'WHIP endpoint' 200 60 100
$txtDestination = New-Object System.Windows.Forms.TextBox
$txtDestination.Location = New-Object System.Drawing.Point(300, 60)
$txtDestination.Size = New-Object System.Drawing.Size(418, 23)
$txtDestination.Text = $script:ProtocolDestinations.WHIP
$settingsGroup.Controls.Add($txtDestination)

$chkFullscreenApp = New-Object System.Windows.Forms.CheckBox
$chkFullscreenApp.Text = 'Only capture fullscreen app (WGC)'
$chkFullscreenApp.Location = New-Object System.Drawing.Point(15, 96)
$chkFullscreenApp.Size = New-Object System.Drawing.Size(245, 25)
$chkFullscreenApp.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$chkFullscreenApp.Checked = $false
$settingsGroup.Controls.Add($chkFullscreenApp)
$toolTip.SetToolTip($chkFullscreenApp, 'When enabled, captures only the topmost visible fullscreen application window through Windows Graphics Capture. The pipeline is rebuilt automatically when the fullscreen app changes.')

$lblCaptureModeStatus = New-Object System.Windows.Forms.Label
$lblCaptureModeStatus.Text = 'Monitor capture active'
$lblCaptureModeStatus.Location = New-Object System.Drawing.Point(275, 96)
$lblCaptureModeStatus.Size = New-Object System.Drawing.Size(443, 25)
$lblCaptureModeStatus.TextAlign = 'MiddleLeft'
$lblCaptureModeStatus.ForeColor = [System.Drawing.Color]::DimGray
$settingsGroup.Controls.Add($lblCaptureModeStatus)

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

$chkPreview = New-Object System.Windows.Forms.CheckBox
$chkPreview.Text = 'Show Preview'
$chkPreview.Location = New-Object System.Drawing.Point(235, 130)
$chkPreview.Size = New-Object System.Drawing.Size(80, 23)
$chkPreview.Checked = $false
$settingsGroup.Controls.Add($chkPreview)
$toolTip.SetToolTip($chkPreview, 'Shows or hides the local preview while streaming. The one-frame leaky preview branch is kept available so toggling does not restart the stream.')

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

$chkMinimizeToTray = New-Object System.Windows.Forms.CheckBox
$chkMinimizeToTray.Text = 'Minimize to tray'
$chkMinimizeToTray.Location = New-Object System.Drawing.Point(600, 130)
$chkMinimizeToTray.Size = New-Object System.Drawing.Size(120, 23)
$chkMinimizeToTray.Checked = $true
$settingsGroup.Controls.Add($chkMinimizeToTray)
$toolTip.SetToolTip($chkMinimizeToTray, 'Hides the main window in the notification area when minimized. Closing the window still exits and terminates GStreamer.')

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
$lblEncoderStatus.Text = 'H.264 • Hardware • D3D11'
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
$chkAdaptiveQuantization.Text = 'Adaptive quantization'
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

$audioNote = New-Object System.Windows.Forms.Label
$audioNote.Text = 'Desktop audio uses WASAPI loopback; microphone uses the default device. Video-only WHIP automatically adds a muted Opus/WASAPI clock track for timestamp stability.'
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
$previewPlaceholder.Text = 'Preview hidden — stream can keep running'
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

$txtCommand = New-Object System.Windows.Forms.TextBox
$txtCommand.Multiline = $true
$txtCommand.ScrollBars = 'Vertical'
$txtCommand.WordWrap = $true
$txtCommand.ReadOnly = $true
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
    "Opens the persistent log folder: $script:LogDirectory"
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
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$txtLog.Dock = 'Fill'
$tabLog.Controls.Add($txtLog)

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

        $mediaRunning =
            $script:MediaMtxProcess -and
            -not $script:MediaMtxProcess.HasExited

        if (-not $gstRunning -and -not $mediaRunning) {
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
            $state.GstExecutablePath = [System.IO.Path]::GetFullPath(
                $txtGstPath.Text.Trim()
            )
            $state.GstStartTimeUtc   =
                $script:GstProcess.StartTime.ToUniversalTime().ToString('o')

            # Keep the older field names for backward compatibility with state
            # files written by pre-v3.4 builds.
            $state.ProcessId      = $state.GstProcessId
            $state.ExecutablePath = $state.GstExecutablePath
            $state.StartTimeUtc   = $state.GstStartTimeUtc
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
            -Label 'GStreamer'

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
        $running = $script:GstProcess -and -not $script:GstProcess.HasExited
        $waiting = [bool]$script:WaitingForFullscreen

        $trayStartItem.Enabled = -not $running -and -not $waiting
        $trayStopItem.Enabled = $running -or $waiting
        $trayRestartItem.Enabled = $running

        if ($running) {
            $notifyIcon.Text = "GStreamer Streamer - $([string]$cmbProtocol.SelectedItem) running"
        }
        elseif ($waiting) {
            $notifyIcon.Text = 'GStreamer Streamer - waiting for fullscreen app'
        }
        else {
            $notifyIcon.Text = 'GStreamer Streamer - stopped'
        }
    }
    catch {
        # Tray state is non-critical and must never affect streaming.
    }
}

function Show-MainWindow {
    try {
        $form.ShowInTaskbar = $true
        $form.Show()
        if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
            $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        }
        $form.BringToFront()
        $form.Activate()

        # Tray restore can leave the embedded d3d11videosink HWND alive but not
        # painting. Re-seat/show it on the UI thread without touching the stream.
        if ($script:GstProcess -and -not $script:GstProcess.HasExited) {
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
    }
    catch {}
}

function Hide-MainWindowToTray {
    if (-not $chkMinimizeToTray.Checked -or $script:ExitCleanupStarted) {
        return
    }

    try {
        if ($script:PreviewHwnd -ne [IntPtr]::Zero) {
            Park-PreviewWindow
        }

        $previewPlaceholder.Visible = $true
        $previewPlaceholder.Text = 'Preview parked while app is in tray'

        $form.ShowInTaskbar = $false
        $form.Hide()

        if (-not $script:TrayHintShown) {
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

function Append-Log {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return
    }

    $txtLog.AppendText($Text)
    if (-not $Text.EndsWith([Environment]::NewLine)) {
        $txtLog.AppendText([Environment]::NewLine)
    }

    if ($txtLog.TextLength -gt 250000) {
        $txtLog.Text = $txtLog.Text.Substring($txtLog.TextLength - 180000)
    }

    $txtLog.SelectionStart = $txtLog.TextLength
    $txtLog.ScrollToCaret()
}

function Set-RunState {
    param([bool]$Running)

    $btnStart.Enabled = -not $Running
    $btnStop.Enabled = $Running
    $btnRestart.Enabled = $Running
    Update-TrayMenuState
}

function Update-MediaMtxUi {
    $enabled = $chkStartMediaMtx.Checked
    $txtMediaMtxPath.Enabled = $enabled
    $btnBrowseMediaMtx.Enabled = $enabled
}

function Update-CaptureModeUi {
    $numMonitor.Enabled = -not $chkFullscreenApp.Checked

    if ($chkFullscreenApp.Checked) {
        if ($script:CaptureWindowHwnd -ne [IntPtr]::Zero -and $script:CaptureWindowTitle) {
            $lblCaptureModeStatus.Text = "Fullscreen target: $($script:CaptureWindowTitle)"
            $lblCaptureModeStatus.ForeColor = [System.Drawing.Color]::DarkGreen
        }
        else {
            $lblCaptureModeStatus.Text = 'Fullscreen-only capture enabled — waiting starts automatically'
            $lblCaptureModeStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        }
    }
    else {
        $lblCaptureModeStatus.Text = "Monitor capture active (index $([int]$numMonitor.Value))"
        $lblCaptureModeStatus.ForeColor = [System.Drawing.Color]::DimGray
    }
}

function Resolve-FullscreenCaptureTarget {
    param([switch]$Quiet)

    if (-not $chkFullscreenApp.Checked) {
        $script:CaptureWindowHwnd = [IntPtr]::Zero
        $script:CaptureWindowTitle = ''
        Update-CaptureModeUi
        return $true
    }

    $gstPid = 0
    if ($script:GstProcess -and -not $script:GstProcess.HasExited) {
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

function Build-RawAudioChain {
    $desktopEnabled = $chkDesktopAudio.Checked
    $micEnabled = $chkMic.Checked

    if (-not $desktopEnabled -and -not $micEnabled) {
        return $null
    }

    $desktopVolume = Format-InvariantNumber ([double]$numDesktopVolume.Value / 100.0)
    $micVolume = Format-InvariantNumber ([double]$numMicVolume.Value / 100.0)

    if ($desktopEnabled -and -not $micEnabled) {
        return @(
            'wasapi2src'
            'loopback=true'
            'low-latency=true'
            'buffer-time=20000'
            'latency-time=10000'
            '!'
            'queue'
            'max-size-buffers=4'
            'max-size-bytes=0'
            'max-size-time=0'
            'leaky=downstream'
            '!'
            'audioconvert'
            '!'
            'audioresample'
            '!'
            '"audio/x-raw,format=S16LE,rate=48000,channels=2"'
            '!'
            'volume'
            "volume=$desktopVolume"
        ) -join ' '
    }

    if (-not $desktopEnabled -and $micEnabled) {
        return @(
            'wasapi2src'
            'low-latency=true'
            'buffer-time=20000'
            'latency-time=10000'
            '!'
            'queue'
            'max-size-buffers=4'
            'max-size-bytes=0'
            'max-size-time=0'
            'leaky=downstream'
            '!'
            'audioconvert'
            '!'
            'audioresample'
            '!'
            '"audio/x-raw,format=S16LE,rate=48000,channels=2"'
            '!'
            'volume'
            "volume=$micVolume"
        ) -join ' '
    }

    $desktopMixBranch = @(
        'wasapi2src'
        'loopback=true'
        'low-latency=true'
        'buffer-time=20000'
        'latency-time=10000'
        '!'
        'queue'
        'max-size-buffers=8'
        'max-size-bytes=0'
        'max-size-time=0'
        'leaky=downstream'
        '!'
        'audioconvert'
        '!'
        'audioresample'
        '!'
        '"audio/x-raw,format=F32LE,rate=48000,channels=2"'
        '!'
        'volume'
        "volume=$desktopVolume"
        '!'
        'mix.'
    ) -join ' '

    $micMixBranch = @(
        'wasapi2src'
        'low-latency=true'
        'buffer-time=20000'
        'latency-time=10000'
        '!'
        'queue'
        'max-size-buffers=8'
        'max-size-bytes=0'
        'max-size-time=0'
        'leaky=downstream'
        '!'
        'audioconvert'
        '!'
        'audioresample'
        '!'
        '"audio/x-raw,format=F32LE,rate=48000,channels=2"'
        '!'
        'volume'
        "volume=$micVolume"
        '!'
        'mix.'
    ) -join ' '

    $mixOutput = @(
        'mix.'
        '!'
        'queue'
        'max-size-buffers=8'
        'max-size-bytes=0'
        'max-size-time=0'
        'leaky=downstream'
        '!'
        'audioconvert'
        '!'
        '"audio/x-raw,format=S16LE,rate=48000,channels=2"'
    ) -join ' '

    return "audiomixer name=mix $desktopMixBranch $micMixBranch $mixOutput"
}


function Build-WhipSilentClockAudioChain {
    # MediaMTX/GStreamer testing showed that video-only WHIP selects
    # GstSystemClock and eventually develops a small backward DTS step. A muted
    # WASAPI loopback source makes the pipeline use GstAudioSrcClock, matching
    # the stable desktop-audio path while emitting no audible sound.
    return @(
        'wasapi2src'
        'loopback=true'
        'low-latency=true'
        'buffer-time=20000'
        'latency-time=10000'
        '!'
        'queue'
        'max-size-buffers=4'
        'max-size-bytes=0'
        'max-size-time=0'
        'leaky=downstream'
        '!'
        'audioconvert'
        '!'
        'audioresample'
        '!'
        '"audio/x-raw,format=S16LE,rate=48000,channels=2"'
        '!'
        'volume'
        'volume=0.0'
    ) -join ' '
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
        if (
            $protocol -eq 'WHIP' -and
            -not $chkDesktopAudio.Checked -and
            -not $chkMic.Checked
        ) {
            $lblAudioCodecStatus.Text = 'WHIP • muted Opus clock track (automatic)'
            $lblAudioCodecStatus.ForeColor = [System.Drawing.Color]::DarkSlateBlue
        }
        else {
            $lblAudioCodecStatus.Text =
                "$protocol compatible • $([string]$script:AudioCodecCatalog[$selected].Codec)"
            $lblAudioCodecStatus.ForeColor = [System.Drawing.Color]::DimGray
        }
    }

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
            return "audioconvert ! `"audio/x-raw,format=F32LE,rate=48000,channels=2`" ! avenc_aac bitrate=$bitrateBps ! aacparse ! `"audio/mpeg,mpegversion=4,stream-format=$format,framed=true`""
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
            return "audioconvert ! `"audio/x-raw,format=F32LE,rate=48000,channels=2`" ! avenc_ac3 bitrate=$bitrateBps ! ac3parse ! `"audio/x-ac3,framed=true`""
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
            return "video/x-h264,profile=$profile,stream-format=$streamFormat,alignment=au"
        }
        'H265' {
            $streamFormat = if ($Protocol -eq 'RTMP') { 'hvc1' } else { 'byte-stream' }
            return "video/x-h265,profile=main,stream-format=$streamFormat,alignment=au"
        }
        'AV1' {
            $alignment = if ($Protocol -eq 'SRT') { 'frame' } else { 'tu' }
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
    $gopSize = [Math]::Max(1, $fps * [int]$numGopSeconds.Value)
    $preset = [string]$cmbPreset.SelectedItem
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
    $aqEnabled =
        $controlSupport.AdaptiveQuantization -and
        $chkAdaptiveQuantization.Checked
    $aqStrength = [int]$numAqStrength.Value
    $aqStrengthFloat = ($aqStrength / 8.0).ToString(
        '0.###',
        [System.Globalization.CultureInfo]::InvariantCulture
    )

    $parts = New-Object System.Collections.Generic.List[string]

    $parts.Add('queue')
    $parts.Add('max-size-buffers=2')
    $parts.Add('max-size-bytes=0')
    $parts.Add('max-size-time=0')
    $parts.Add('leaky=downstream')
    $parts.Add('!')

    if ($inputType -eq 'I420') {
        $parts.Add('d3d11download')
        $parts.Add('!')
        $parts.Add('videoconvert')
        $parts.Add('!')
        $parts.Add(
            "`"video/x-raw,format=I420,width=$width,height=$height,framerate=$fps/1`""
        )
        $parts.Add('!')
    }

    $parts.Add($element)

    switch ($family) {
        'NVENC' {
            $zeroLatency = ($bFrames -eq 0 -and $lookAheadFrames -eq 0)
            $parts.Add("bitrate=$videoBitrateKbps")
            $parts.Add('rc-mode=cbr')
            $parts.Add("preset=$preset")
            $parts.Add('tune=ultra-low-latency')
            $parts.Add("zerolatency=$($zeroLatency.ToString().ToLowerInvariant())")
            $parts.Add("bframes=$bFrames")
            $parts.Add(
                "b-adapt=$((($bFrames -gt 0) -and ($lookAheadFrames -gt 0)).ToString().ToLowerInvariant())"
            )
            $parts.Add("gop-size=$gopSize")
            $parts.Add("rc-lookahead=$lookAheadFrames")
            $parts.Add("spatial-aq=$($aqEnabled.ToString().ToLowerInvariant())")
            $parts.Add("temporal-aq=$($aqEnabled.ToString().ToLowerInvariant())")
            if ($aqEnabled) {
                $parts.Add("aq-strength=$aqStrength")
            }
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
            $parts.Add("bitrate=$videoBitrateKbps")
            if ($lookAheadFrames -gt 0 -and $codec -in @('H264', 'H265')) {
                $parts.Add('rate-control=la-hrd')
                $parts.Add("rc-lookahead=$lookAheadFrames")
            }
            else {
                $parts.Add('rate-control=cbr')
                if ($codec -in @('H264', 'H265')) {
                    $parts.Add('rc-lookahead=0')
                }
            }
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
            $parts.Add("bitrate=$videoBitrateKbps")
            $parts.Add('speed-preset=ultrafast')
            $parts.Add('tune=zerolatency')
            $parts.Add("key-int-max=$gopSize")
            $parts.Add("bframes=$bFrames")
            $parts.Add(
                "b-adapt=$((($bFrames -gt 0) -and ($lookAheadFrames -gt 0)).ToString().ToLowerInvariant())"
            )
            $parts.Add("rc-lookahead=$lookAheadFrames")
            $parts.Add('sync-lookahead=0')
            $parts.Add("mb-tree=$($aqEnabled.ToString().ToLowerInvariant())")
            $x264AqOptions = if ($aqEnabled) {
                "aq-mode=2:aq-strength=$aqStrengthFloat"
            }
            else {
                'aq-mode=0'
            }
            $parts.Add("option-string=$x264AqOptions")
            $parts.Add('sliced-threads=true')
            $parts.Add('byte-stream=true')
            $parts.Add('aud=true')
        }
        'X265' {
            $parts.Add("bitrate=$videoBitrateKbps")
            $parts.Add('speed-preset=ultrafast')
            $parts.Add('tune=zerolatency')
            $parts.Add("key-int-max=$gopSize")
            $x265Options = New-Object System.Collections.Generic.List[string]
            $x265Options.Add("bframes=$bFrames")
            $x265Options.Add("rc-lookahead=$lookAheadFrames")
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

    if (-not [string]::IsNullOrWhiteSpace($parser)) {
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

    $cmbPreset.Enabled = ($family -eq 'NVENC')
    $cmbProfile.Enabled = ($codec -eq 'H264')

    $controlSupport = Get-EncoderControlSupport
    $numBFrames.Enabled = $controlSupport.BFrames
    $chkLookAhead.Enabled = $controlSupport.LookAhead
    $numLookAheadFrames.Enabled =
        $controlSupport.LookAhead -and $chkLookAhead.Checked
    $chkAdaptiveQuantization.Enabled =
        $controlSupport.AdaptiveQuantization
    $numAqStrength.Enabled =
        $controlSupport.AdaptiveQuantization -and
        $chkAdaptiveQuantization.Checked

    $memoryLabel = if ($inputType -eq 'D3D11') { 'D3D11 zero-copy path' } else { 'CPU/system-memory path' }
    $latencyFlags = New-Object System.Collections.Generic.List[string]
    if ($numBFrames.Enabled -and [int]$numBFrames.Value -gt 0) {
        $latencyFlags.Add("B=$([int]$numBFrames.Value)")
    }
    if ($chkLookAhead.Enabled -and $chkLookAhead.Checked) {
        $latencyFlags.Add("LA=$([int]$numLookAheadFrames.Value)")
    }
    if ($chkAdaptiveQuantization.Enabled -and $chkAdaptiveQuantization.Checked) {
        $latencyFlags.Add('AQ')
    }

    $flagText = if ($latencyFlags.Count -gt 0) {
        ' • ' + ($latencyFlags -join ', ')
    }
    else {
        ''
    }
    $lblEncoderStatus.Text = "$codec • $kind • $memoryLabel$flagText"

    if ($protocol) {
        $compatible = Test-CodecProtocolCompatibility -Codec $codec -Protocol $protocol
        $lblEncoderStatus.ForeColor = if ($compatible) {
            [System.Drawing.Color]::DimGray
        }
        else {
            [System.Drawing.Color]::DarkRed
        }
    }

    Update-CommandPreview
}

function Build-VideoBranch {
    param([Parameter(Mandatory)][string]$Protocol)

    $monitor = [int]$numMonitor.Value
    $cursor = if ($chkCursor.Checked) { 'true' } else { 'false' }
    $width = [int]$numWidth.Value
    $height = [int]$numHeight.Value
    $fps = [int]$numFps.Value

    if ($chkFullscreenApp.Checked) {
        $windowHandle = if ($script:CaptureWindowHwnd -ne [IntPtr]::Zero) {
            [uint64]$script:CaptureWindowHwnd.ToInt64()
        }
        else {
            [uint64]0
        }

        $capture = @(
            'd3d11screencapturesrc'
            'capture-api=wgc'
            "window-handle=$windowHandle"
            'window-capture-mode=default'
            'show-border=false'
            "show-cursor=$cursor"
            '!'
            "`"video/x-raw(memory:D3D11Memory),framerate=$fps/1`""
            '!'
            'd3d11convert'
            '!'
            "`"video/x-raw(memory:D3D11Memory),format=NV12,width=$width,height=$height,framerate=$fps/1`""
        ) -join ' '
    }
    else {
        $capture = @(
            'd3d11screencapturesrc'
            "monitor-index=$monitor"
            "show-cursor=$cursor"
            '!'
            "`"video/x-raw(memory:D3D11Memory),framerate=$fps/1`""
            '!'
            'd3d11convert'
            '!'
            "`"video/x-raw(memory:D3D11Memory),format=NV12,width=$width,height=$height,framerate=$fps/1`""
        ) -join ' '
    }

    $encoder = Get-EncoderElementChain -Protocol $Protocol

    # Runtime-toggleable preview:
    # gst-launch pipelines are static after launch, so the preview branch must
    # exist from the beginning. The checkbox only shows/hides the embedded
    # d3d11videosink window; it does not rebuild the streaming pipeline.
    $previewBranch = @(
        'tee'
        'name=rawtee'
        'rawtee.'
        '!'
        'queue'
        'max-size-buffers=1'
        'max-size-bytes=0'
        'max-size-time=0'
        'leaky=downstream'
        '!'
        'd3d11videosink'
        'name=localpreview'
        'sync=false'
        'force-aspect-ratio=true'
        'rawtee.'
        '!'
        $encoder
    ) -join ' '

    return "$capture ! $previewBranch"

}

function Build-GstArguments {
    $protocol = [string]$cmbProtocol.SelectedItem
    $destination = $txtDestination.Text.Trim()
    $quotedDestination = Quote-GstValue $destination
    $definition = Get-SelectedEncoderDefinition
    $codec = [string]$definition.Codec
    $mediaType = Get-CodecMediaType -Codec $codec
    $userAudioEnabled =
        $chkDesktopAudio.Checked -or
        $chkMic.Checked

    $audioRaw = Build-RawAudioChain
    $usingWhipSilentClockAudio = $false

    if (
        $protocol -eq 'WHIP' -and
        [string]::IsNullOrWhiteSpace($audioRaw)
    ) {
        $audioRaw = Build-WhipSilentClockAudioChain
        $usingWhipSilentClockAudio = $true
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
    $video = Build-VideoBranch -Protocol $protocol

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
            if ($hasAudio) {
                $pipeline = "whipclientsink name=out video-caps=`"$mediaType`" audio-caps=`"$audioMediaType`" signaller::whip-endpoint=$quotedDestination $video ! out.video_0 $audioRaw ! $audioEncoded ! out.audio_0"
            }
            else {
                $pipeline = "$video ! whipclientsink video-caps=`"$mediaType`" signaller::whip-endpoint=$quotedDestination"
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
                "$video ! mux.sink_256"

            if ($hasAudio) {
                $pipeline +=
                    " $audioRaw ! $audioEncoded ! mux.sink_257"
            }
        }

        'RTMP' {
            if ($codec -eq 'H264') {
                $pipeline = "flvmux name=mux streamable=true ! rtmp2sink location=$quotedDestination async-connect=true $video ! mux."
                if ($hasAudio) {
                    $pipeline += " $audioRaw ! $audioEncoded ! mux."
                }
            }
            else {
                $pipeline = "eflvmux name=mux streamable=true ! rtmp2sink location=$quotedDestination async-connect=true $video ! mux.video"
                if ($hasAudio) {
                    $pipeline += " $audioRaw ! $audioEncoded ! mux.audio"
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
            $pipeline = "rtspclientsink name=out location=$quotedDestination protocols=$transport latency=0 rtx-time=0 $video ! out.sink_0"
            if ($hasAudio) {
                $pipeline += " $audioRaw ! $audioEncoded ! out.sink_1"
            }
        }

        default {
            throw "Unsupported protocol: $protocol"
        }
    }

    $flags = '-e'
    if ($chkVerbose.Checked) {
        $flags += ' -v'
    }

    return "$flags $pipeline"
}

function Update-CommandPreview {
    try {
        $gstPath = $txtGstPath.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($gstPath)) {
            $gstPath = 'gst-launch-1.0.exe'
        }

        $txtCommand.Text = '& ' + (Quote-GstValue $gstPath) + ' ' + (Build-GstArguments)
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
    $lblDestination.Text = "$protocol destination"
    $numSrtLatency.Enabled = ($protocol -eq 'SRT')
    $cmbRtspTransport.Enabled = ($protocol -eq 'RTSP')

    switch ($protocol) {
        'WHIP' { $toolTip.SetToolTip($txtDestination, 'Example: http://server:8889/live/whip') }
        'SRT'  { $toolTip.SetToolTip($txtDestination, 'Example: srt://server:8890?mode=caller&streamid=publish:live') }
        'RTMP' { $toolTip.SetToolTip($txtDestination, 'Example: rtmp://server/live') }
        'RTSP' { $toolTip.SetToolTip($txtDestination, 'Example: rtsp://server:8554/live') }
    }

    Update-AudioCodecChoices
    Update-EncoderUi
}

function Save-Settings {
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
            Protocol          = $protocol
            WhipUrl           = $script:ProtocolDestinations.WHIP
            SrtUrl            = $script:ProtocolDestinations.SRT
            RtmpUrl           = $script:ProtocolDestinations.RTMP
            RtspUrl           = $script:ProtocolDestinations.RTSP
            SrtLatency        = [int]$numSrtLatency.Value
            RtspTransport     = [string]$cmbRtspTransport.SelectedItem
            MonitorIndex      = [int]$numMonitor.Value
            ShowCursor        = $chkCursor.Checked
            FullscreenApp     = $chkFullscreenApp.Checked
            Preview           = $chkPreview.Checked
            AutoRestart       = $chkAutoRestart.Checked
            Verbose           = $chkVerbose.Checked
            MinimizeToTray    = $chkMinimizeToTray.Checked
            Width             = [int]$numWidth.Value
            Height            = [int]$numHeight.Value
            Fps               = [int]$numFps.Value
            VideoBitrateKbps  = [int]$numVideoBitrate.Value
            GopSeconds        = [int]$numGopSeconds.Value
            Encoder           = [string]$cmbEncoder.SelectedItem
            Preset            = [string]$cmbPreset.SelectedItem
            Profile           = [string]$cmbProfile.SelectedItem
            BFrames           = [int]$numBFrames.Value
            LookAhead         = $chkLookAhead.Checked
            LookAheadFrames   = [int]$numLookAheadFrames.Value
            AdaptiveQuantization = $chkAdaptiveQuantization.Checked
            AqStrength        = [int]$numAqStrength.Value
            WhipAudioCodec    = [string]$script:ProtocolAudioCodecs.WHIP
            SrtAudioCodec     = [string]$script:ProtocolAudioCodecs.SRT
            RtmpAudioCodec    = [string]$script:ProtocolAudioCodecs.RTMP
            RtspAudioCodec    = [string]$script:ProtocolAudioCodecs.RTSP
            DesktopAudio      = $chkDesktopAudio.Checked
            DesktopVolume     = [int]$numDesktopVolume.Value
            Microphone        = $chkMic.Checked
            MicrophoneVolume  = [int]$numMicVolume.Value
            AudioBitrateKbps  = [int]$numAudioBitrate.Value
        }

        $settings | ConvertTo-Json | Set-Content -LiteralPath $script:ConfigPath -Encoding UTF8
    }
    catch {
        Append-Log "Could not save settings: $($_.Exception.Message)"
    }
}

function Load-Settings {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
        return
    }

    try {
        $settings = Get-Content -LiteralPath $script:ConfigPath -Raw | ConvertFrom-Json
        $script:SuppressProtocolChange = $true

        if ($settings.GstPath) { $txtGstPath.Text = [string]$settings.GstPath }
        if ($settings.MediaMtxPath) {
            $txtMediaMtxPath.Text = [string]$settings.MediaMtxPath
        }
        if ($null -ne $settings.StartMediaMtx) {
            $chkStartMediaMtx.Checked = [bool]$settings.StartMediaMtx
        }
        if ($settings.WhipUrl) { $script:ProtocolDestinations.WHIP = [string]$settings.WhipUrl }
        if ($settings.SrtUrl) { $script:ProtocolDestinations.SRT = [string]$settings.SrtUrl }
        if ($settings.RtmpUrl) { $script:ProtocolDestinations.RTMP = [string]$settings.RtmpUrl }
        if ($settings.RtspUrl) { $script:ProtocolDestinations.RTSP = [string]$settings.RtspUrl }
        if ($null -ne $settings.SrtLatency) { $numSrtLatency.Value = [decimal]$settings.SrtLatency }
        if ($settings.RtspTransport -and $cmbRtspTransport.Items.Contains([string]$settings.RtspTransport)) { $cmbRtspTransport.SelectedItem = [string]$settings.RtspTransport }
        if ($null -ne $settings.MonitorIndex) { $numMonitor.Value = [decimal]$settings.MonitorIndex }
        if ($null -ne $settings.ShowCursor) { $chkCursor.Checked = [bool]$settings.ShowCursor }
        if ($null -ne $settings.FullscreenApp) { $chkFullscreenApp.Checked = [bool]$settings.FullscreenApp }
        if ($null -ne $settings.Preview) { $chkPreview.Checked = [bool]$settings.Preview }
        if ($null -ne $settings.AutoRestart) { $chkAutoRestart.Checked = [bool]$settings.AutoRestart }
        if ($null -ne $settings.Verbose) { $chkVerbose.Checked = [bool]$settings.Verbose }
        if ($null -ne $settings.MinimizeToTray) { $chkMinimizeToTray.Checked = [bool]$settings.MinimizeToTray }
        if ($settings.Width) { $numWidth.Value = [decimal]$settings.Width }
        if ($settings.Height) { $numHeight.Value = [decimal]$settings.Height }
        if ($settings.Fps) { $numFps.Value = [decimal]$settings.Fps }
        if ($settings.VideoBitrateKbps) { $numVideoBitrate.Value = [decimal]$settings.VideoBitrateKbps }
        if ($settings.GopSeconds) { $numGopSeconds.Value = [decimal]$settings.GopSeconds }
        if ($settings.Encoder -and $cmbEncoder.Items.Contains([string]$settings.Encoder)) {
            $cmbEncoder.SelectedItem = [string]$settings.Encoder
        }
        if ($settings.Preset -and $cmbPreset.Items.Contains([string]$settings.Preset)) { $cmbPreset.SelectedItem = [string]$settings.Preset }
        if ($settings.Profile -and $cmbProfile.Items.Contains([string]$settings.Profile)) { $cmbProfile.SelectedItem = [string]$settings.Profile }
        if ($null -ne $settings.BFrames) { $numBFrames.Value = [decimal]$settings.BFrames }
        if ($null -ne $settings.LookAhead) { $chkLookAhead.Checked = [bool]$settings.LookAhead }
        if ($settings.LookAheadFrames) { $numLookAheadFrames.Value = [decimal]$settings.LookAheadFrames }
        if ($null -ne $settings.AdaptiveQuantization) {
            $chkAdaptiveQuantization.Checked = [bool]$settings.AdaptiveQuantization
        }
        if ($settings.AqStrength) { $numAqStrength.Value = [decimal]$settings.AqStrength }

        foreach ($audioSetting in @(
            @('WhipAudioCodec', 'WHIP'),
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

        if ($null -ne $settings.DesktopAudio) { $chkDesktopAudio.Checked = [bool]$settings.DesktopAudio }
        if ($null -ne $settings.DesktopVolume) { $numDesktopVolume.Value = [decimal]$settings.DesktopVolume }
        if ($null -ne $settings.Microphone) { $chkMic.Checked = [bool]$settings.Microphone }
        if ($null -ne $settings.MicrophoneVolume) { $numMicVolume.Value = [decimal]$settings.MicrophoneVolume }
        if ($settings.AudioBitrateKbps) { $numAudioBitrate.Value = [decimal]$settings.AudioBitrateKbps }

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
        Update-MediaMtxUi
        Update-ProtocolUi
        Update-EncoderUi
    }
}

function Validate-Configuration {
    $gstPath = $txtGstPath.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($gstPath) -or -not (Test-Path -LiteralPath $gstPath)) {
        [System.Windows.Forms.MessageBox]::Show(
            'Select a valid gst-launch-1.0.exe path.',
            $script:AppName,
            'OK',
            'Warning'
        ) | Out-Null
        return $false
    }

    if ($chkStartMediaMtx.Checked) {
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

    $protocol = [string]$cmbProtocol.SelectedItem
    $destination = $txtDestination.Text.Trim()
    $valid = switch ($protocol) {
        'WHIP' { $destination -match '^https?://' }
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
        $protocol -eq 'WHIP' -and
        $codec -eq 'H264' -and
        $numBFrames.Enabled -and
        [int]$numBFrames.Value -gt 0
    ) {
        [System.Windows.Forms.MessageBox]::Show(
            'H.264 B-frames are not compatible with normal WebRTC playback. Set B-frames to 0 for WHIP.',
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
            $chkPreview.Checked
        )
        $script:PreviewParked = $false
    }
    catch {}
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
        elseif ($chkPreview.Checked) {
            'Preview starting...'
        }
        else {
            'Preview hidden — stream still running'
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

    if ($chkPreview.Checked) {
        [GstPreviewNative]::ResizeEmbeddedWindow(
            $script:PreviewHwnd,
            $previewPanel.ClientSize.Width,
            $previewPanel.ClientSize.Height
        )
        [GstPreviewNative]::SetWindowVisible($script:PreviewHwnd, $true)
        $previewPlaceholder.Visible = $false
    }
    else {
        [GstPreviewNative]::SetWindowVisible($script:PreviewHwnd, $false)
        $previewPlaceholder.Visible = $true
        $previewPlaceholder.Text = 'Preview hidden — stream still running'
    }
}

function Try-AttachPreview {
    if (-not $script:GstProcess -or $script:GstProcess.HasExited) {
        return
    }

    if ($script:PreviewHwnd -eq [IntPtr]::Zero) {
        $candidate = [GstPreviewNative]::FindPreviewWindow($script:GstProcess.Id)
        if ($candidate -ne [IntPtr]::Zero) {
            if ([GstPreviewNative]::EmbedWindow($candidate, $previewPanel.Handle, $previewPanel.ClientSize.Width, $previewPanel.ClientSize.Height)) {
                $script:PreviewHwnd = $candidate
                $script:PreviewParked = $false
                Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Preview window embedded for runtime toggle."
            }
        }
    }

    Set-PreviewVisibility
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
    if (-not $chkStartMediaMtx.Checked) {
        return $true
    }

    if ($script:MediaMtxProcess -and -not $script:MediaMtxProcess.HasExited) {
        return $true
    }

    $mediaMtxPath = $txtMediaMtxPath.Text.Trim()
    $script:MediaMtxPathInUse = [System.IO.Path]::GetFullPath($mediaMtxPath)

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $script:MediaMtxStdOutPath =
        Join-Path $script:LogDirectory "mediamtx-$stamp-out.log"
    $script:MediaMtxStdErrPath =
        Join-Path $script:LogDirectory "mediamtx-$stamp-err.log"
    $script:MediaMtxStdOutPosition = [int64]0
    $script:MediaMtxStdErrPosition = [int64]0

    $workingDirectory = Split-Path -Parent $script:MediaMtxPathInUse

    Append-Log (
        "[$(Get-Date -Format 'HH:mm:ss')] Starting managed MediaMTX..."
    )
    Append-Log "MediaMTX executable: $($script:MediaMtxPathInUse)"
    Append-Log "MediaMTX working directory: $workingDirectory"

    try {
        $script:MediaMtxProcess = Start-Process `
            -FilePath $script:MediaMtxPathInUse `
            -WorkingDirectory $workingDirectory `
            -RedirectStandardOutput $script:MediaMtxStdOutPath `
            -RedirectStandardError $script:MediaMtxStdErrPath `
            -WindowStyle Hidden `
            -PassThru

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

        Read-MediaMtxStartupLogs

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
            "MediaMTX is running — PID $($script:MediaMtxProcess.Id)."
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
                "process tree — PID $($script:MediaMtxProcess.Id)..."
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
    param([switch]$Automatic)

    if ($script:GstProcess -and -not $script:GstProcess.HasExited) {
        return
    }

    if (-not (Validate-Configuration)) {
        $script:WaitingForFullscreen = $false
        $script:RestartAt = $null
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
        return
    }

    if ($script:WaitingForFullscreen) {
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Fullscreen application detected: '$($script:CaptureWindowTitle)'."
    }
    $script:WaitingForFullscreen = $false

    Save-Settings

    if (-not (Test-Path -LiteralPath $script:LogDirectory)) {
        $null = New-Item -ItemType Directory -Path $script:LogDirectory -Force
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $script:StdOutPath = Join-Path $script:LogDirectory "gst-$stamp-out.log"
    $script:StdErrPath = Join-Path $script:LogDirectory "gst-$stamp-err.log"
    $script:StdOutPosition = [int64]0
    $script:StdErrPosition = [int64]0
    $script:StopRequested = $false
    $script:RestartAt = $null
    $script:PreviewHwnd = [IntPtr]::Zero
    $script:PreviewParked = $false
    $previewPlaceholder.Visible = $true
    $previewPlaceholder.Text = if ($chkPreview.Checked) { 'Starting preview...' } else { 'Preview hidden — stream still running' }

    $gstPath = $txtGstPath.Text.Trim()
    Prepare-GStreamerRuntime -GstPath $gstPath
    Initialize-GstJob

    if (-not (Start-ManagedMediaMtx)) {
        $statusLabel.Text = 'MediaMTX start failed'
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkRed
        Set-RunState $false
        return
    }

    $arguments = Build-GstArguments

    Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Starting full GStreamer pipeline..."
    Append-Log "Protocol: $([string]$cmbProtocol.SelectedItem)"

    if ([string]$cmbProtocol.SelectedItem -eq 'SRT') {
        $srtTracks = if ($chkDesktopAudio.Checked -or $chkMic.Checked) {
            'video PID 256 + audio PID 257, both in program 1'
        }
        else {
            'video PID 256 in program 1'
        }

        Append-Log "SRT MPEG-TS mapping: $srtTracks"
        Append-Log 'SRT low-latency mux profile: mux latency 2.9 ms, PAT/PMT 600, pkt_size 1316, Opus preferred'
    }
    if ($chkFullscreenApp.Checked) {
        Append-Log "Fullscreen capture target: $($script:CaptureWindowTitle) (HWND $([uint64]$script:CaptureWindowHwnd.ToInt64()))"
    }
    Append-Log "Executable: $gstPath"
    Append-Log "Arguments: $arguments"

    try {
        $script:GstProcess = Start-Process -FilePath $gstPath -ArgumentList $arguments -RedirectStandardOutput $script:StdOutPath -RedirectStandardError $script:StdErrPath -WindowStyle Hidden -PassThru

        if ($script:JobHandle -ne [IntPtr]::Zero) {
            try {
                [GstProcessJob]::AssignProcess($script:JobHandle, $script:GstProcess.Handle)
            }
            catch {
                Append-Log "WARNING: GStreamer could not be assigned to the kill-on-close job: $($_.Exception.Message)"
            }
        }

        Save-ActiveProcessState

        $targetSuffix = if ($chkFullscreenApp.Checked -and $script:CaptureWindowTitle) { " — $($script:CaptureWindowTitle)" } else { '' }
        $mediaSuffix = if (
            $script:MediaMtxProcess -and
            -not $script:MediaMtxProcess.HasExited
        ) {
            " + MediaMTX PID $($script:MediaMtxProcess.Id)"
        }
        else {
            ''
        }
        $statusLabel.Text = "$([string]$cmbProtocol.SelectedItem) streaming — GST PID $($script:GstProcess.Id)$mediaSuffix$targetSuffix"
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkGreen
        Set-RunState $true
    }
    catch {
        $script:GstProcess = $null
        Stop-ManagedMediaMtx -Quiet
        Remove-ActiveProcessState
        $statusLabel.Text = 'Start failed'
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkRed
        Set-RunState $false
        Append-Log "START ERROR: $($_.Exception.Message)"
    }
}
function Stop-GstStream {
    param([switch]$Restart)

    $script:StopRequested = $true
    $script:WaitingForFullscreen = $false

    if ($Restart) {
        $script:RestartAt = (Get-Date).AddMilliseconds(800)
    }
    else {
        $script:RestartAt = $null
    }

    $script:PreviewHwnd = [IntPtr]::Zero
    $previewPlaceholder.Visible = $true
    $previewPlaceholder.Text = 'Preview stopped'

    $hadGst =
        $script:GstProcess -and
        -not $script:GstProcess.HasExited

    $hadMedia =
        $script:MediaMtxProcess -and
        -not $script:MediaMtxProcess.HasExited

    if ($hadGst -or $hadMedia) {
        $statusLabel.Text = 'Stopping...'
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
    }

    # Stop the publisher first so MediaMTX sees a clean publisher disconnect,
    # then stop the managed server itself.
    if ($hadGst) {
        Append-Log (
            "[$(Get-Date -Format 'HH:mm:ss')] Stopping complete GStreamer " +
            "process tree — PID $($script:GstProcess.Id)..."
        )
        Stop-ProcessTreeById -ProcessId $script:GstProcess.Id

        try {
            $script:GstProcess.WaitForExit(3000) | Out-Null
        }
        catch {}
    }

    try {
        if ($script:GstProcess) {
            $script:GstProcess.Dispose()
        }
    }
    catch {}
    $script:GstProcess = $null

    Stop-ManagedMediaMtx

    Remove-ActiveProcessState

    if (-not $Restart) {
        $statusLabel.Text = 'Stopped'
        $statusLabel.ForeColor = [System.Drawing.Color]::Black
        Set-RunState $false
        $script:StopRequested = $false
    }
    else {
        Set-RunState $false
    }
}

function Test-GStreamerElements {
    $gstPath = $txtGstPath.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($gstPath) -or -not (Test-Path -LiteralPath $gstPath)) {
        [System.Windows.Forms.MessageBox]::Show('Select a valid gst-launch-1.0.exe first.', $script:AppName, 'OK', 'Warning') | Out-Null
        return
    }

    Prepare-GStreamerRuntime -GstPath $gstPath
    $inspectPath = Join-Path (Split-Path -Parent $gstPath) 'gst-inspect-1.0.exe'
    if (-not (Test-Path -LiteralPath $inspectPath)) {
        [System.Windows.Forms.MessageBox]::Show('gst-inspect-1.0.exe was not found beside gst-launch-1.0.exe.', $script:AppName, 'OK', 'Warning') | Out-Null
        return
    }

    $definition = Get-SelectedEncoderDefinition
    $codec = [string]$definition.Codec
    $protocol = [string]$cmbProtocol.SelectedItem

    $elements = New-Object System.Collections.Generic.List[string]
    foreach ($element in @(
        'd3d11screencapturesrc',
        'd3d11convert',
        [string]$definition.Element
    )) {
        $elements.Add($element)
    }

    if ([string]$definition.Input -eq 'I420') {
        $elements.Add('d3d11download')
        $elements.Add('videoconvert')
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$definition.Parser)) {
        $elements.Add([string]$definition.Parser)
    }

    # Preview branch is always present so it can be shown/hidden live.
    $elements.Add('tee')
    $elements.Add('d3d11videosink')

    $userAudioEnabled =
        $chkDesktopAudio.Checked -or
        $chkMic.Checked

    $usingWhipSilentClockAudio =
        $protocol -eq 'WHIP' -and
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
    if (-not (Test-CodecProtocolCompatibility -Codec $codec -Protocol $protocol)) {
        $compatibilityWarning = "$codec is not supported by the $protocol pipeline template."
    }
    elseif (
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
                "`r`n`r`nVideo: $([string]$definition.Element) ($codec)" +
                "`r`nAudio: $audioSummary"
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

$txtGstPath.Add_TextChanged($previewHandler)
$txtDestination.Add_TextChanged({
    $protocol = [string]$cmbProtocol.SelectedItem
    if ($protocol -and -not $script:SuppressProtocolChange) {
        $script:ProtocolDestinations[$protocol] = $txtDestination.Text
    }
    Update-CommandPreview
})
$cmbProtocol.Add_SelectedIndexChanged({ Update-ProtocolUi })
$cmbEncoder.Add_SelectedIndexChanged({ Update-EncoderUi })
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
$chkFullscreenApp.Add_CheckedChanged({
    if ($chkFullscreenApp.Checked) {
        $null = Resolve-FullscreenCaptureTarget -Quiet
    }
    else {
        $script:CaptureWindowHwnd = [IntPtr]::Zero
        $script:CaptureWindowTitle = ''
        Update-CaptureModeUi
    }
    Update-CommandPreview
})
$chkPreview.Add_CheckedChanged({
    if ($script:GstProcess -and -not $script:GstProcess.HasExited) {
        Set-PreviewVisibility
        $previewState = if ($chkPreview.Checked) { 'on' } else { 'off' }
        Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Preview toggled $previewState without restarting stream."
    }
    else {
        $previewPlaceholder.Text = if ($chkPreview.Checked) {
            'Preview will show when stream starts'
        }
        else {
            'Preview hidden — stream can keep running'
        }
    }

    Update-CommandPreview
})
$chkAutoRestart.Add_CheckedChanged($previewHandler)
$chkVerbose.Add_CheckedChanged($previewHandler)
$numWidth.Add_ValueChanged($previewHandler)
$numHeight.Add_ValueChanged($previewHandler)
$numFps.Add_ValueChanged($previewHandler)
$numVideoBitrate.Add_ValueChanged($previewHandler)
$numGopSeconds.Add_ValueChanged($previewHandler)
$cmbPreset.Add_SelectedIndexChanged($previewHandler)
$cmbProfile.Add_SelectedIndexChanged($previewHandler)
$numBFrames.Add_ValueChanged({ Update-EncoderUi })
$chkLookAhead.Add_CheckedChanged({ Update-EncoderUi })
$numLookAheadFrames.Add_ValueChanged({ Update-EncoderUi })
$chkAdaptiveQuantization.Add_CheckedChanged({ Update-EncoderUi })
$numAqStrength.Add_ValueChanged({ Update-EncoderUi })
$numSrtLatency.Add_ValueChanged($previewHandler)
$cmbRtspTransport.Add_SelectedIndexChanged($previewHandler)
$chkDesktopAudio.Add_CheckedChanged({
    Update-AudioCodecChoices -PreserveCurrent
})
$numDesktopVolume.Add_ValueChanged($previewHandler)
$chkMic.Add_CheckedChanged({
    Update-AudioCodecChoices -PreserveCurrent
})
$numMicVolume.Add_ValueChanged($previewHandler)
$numAudioBitrate.Add_ValueChanged($previewHandler)
$chkStartMediaMtx.Add_CheckedChanged({
    Update-MediaMtxUi
})

$previewPanel.Add_Resize({
    if ($script:PreviewHwnd -ne [IntPtr]::Zero) {
        Set-PreviewVisibility
    }
})

$btnBrowseGst.Add_Click({
    try {
        $selectedPath = [GstExecutableBrowser]::SelectGstLaunch($txtGstPath.Text)
        if (-not [string]::IsNullOrWhiteSpace($selectedPath)) {
            $txtGstPath.Text = $selectedPath
            Append-Log "Selected GStreamer executable: $selectedPath"
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

$btnDetectGst.Add_Click({
    $detected = Find-GstLaunch
    $txtGstPath.Text = $detected
    Append-Log "Detected GStreamer executable: $detected"
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
            $null = New-Item `
                -ItemType Directory `
                -Path $script:LogDirectory `
                -Force
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

$notifyIcon.Add_DoubleClick({ Show-MainWindow })
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
    if (
        $chkMinimizeToTray.Checked -and
        $form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized
    ) {
        Hide-MainWindowToTray
    }
    elseif ($form.Visible -and $script:GstProcess -and -not $script:GstProcess.HasExited) {
        Set-PreviewVisibility
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
    elseif (-not $form.Visible -and $script:PreviewHwnd -ne [IntPtr]::Zero) {
        Park-PreviewWindow
    }
})

$pollTimer = New-Object System.Windows.Forms.Timer
$pollTimer.Interval = 400
$pollTimer.Add_Tick({
    $stdoutText = Read-NewLogText -Path $script:StdOutPath -Position ([ref]$script:StdOutPosition)
    if ($stdoutText) { Append-Log $stdoutText }

    $stderrText = Read-NewLogText -Path $script:StdErrPath -Position ([ref]$script:StdErrPosition)
    if ($stderrText) { Append-Log $stderrText }

    $mediaStdoutText = Read-NewLogText `
        -Path $script:MediaMtxStdOutPath `
        -Position ([ref]$script:MediaMtxStdOutPosition)
    if ($mediaStdoutText) { Append-Log $mediaStdoutText }

    $mediaStderrText = Read-NewLogText `
        -Path $script:MediaMtxStdErrPath `
        -Position ([ref]$script:MediaMtxStdErrPosition)
    if ($mediaStderrText) { Append-Log $mediaStderrText }

    Try-AttachPreview

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

        if ($script:GstProcess -and -not $script:GstProcess.HasExited) {
            Append-Log (
                'Stopping the stream because its managed MediaMTX server is no ' +
                'longer running.'
            )

            if ($chkAutoRestart.Checked -or $chkFullscreenApp.Checked) {
                Stop-GstStream -Restart
            }
            else {
                Stop-GstStream
            }
        }
        else {
            Remove-ActiveProcessState
        }
    }

    if ($chkFullscreenApp.Checked -and $script:GstProcess -and -not $script:GstProcess.HasExited -and (Get-Date) -ge $script:NextFullscreenProbe) {
        $script:NextFullscreenProbe = (Get-Date).AddSeconds(1)

        if ($script:CaptureWindowHwnd -ne [IntPtr]::Zero -and -not [GstPreviewNative]::WindowExists($script:CaptureWindowHwnd)) {
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Fullscreen application closed; stopping the pipeline and waiting for another fullscreen application."
            $script:CaptureWindowHwnd = [IntPtr]::Zero
            $script:CaptureWindowTitle = ''
            Update-CaptureModeUi
            Stop-GstStream -Restart
        }
        else {
            $candidate = [GstPreviewNative]::FindTopmostFullscreenWindow($PID, $script:GstProcess.Id)
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

    if ($script:GstProcess -and $script:GstProcess.HasExited) {
        $exitCode = $script:GstProcess.ExitCode
        $wasRequested = $script:StopRequested

        try { $script:GstProcess.Dispose() } catch {}
        $script:GstProcess = $null
        Stop-ManagedMediaMtx -Quiet
        Remove-ActiveProcessState
        $script:PreviewHwnd = [IntPtr]::Zero
        $previewPlaceholder.Visible = $true
        $previewPlaceholder.Text = 'Preview stopped'
        Set-RunState $false

        if ($wasRequested) {
            $statusLabel.Text = 'Stopped'
            $statusLabel.ForeColor = [System.Drawing.Color]::Black
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Pipeline stopped."
        }
        else {
            $statusLabel.Text = "Pipeline exited — code $exitCode"
            $statusLabel.ForeColor = [System.Drawing.Color]::DarkRed
            $lowerTabs.SelectedTab = $tabLog
            Append-Log "[$(Get-Date -Format 'HH:mm:ss')] Pipeline exited unexpectedly with code $exitCode."

            if ($chkFullscreenApp.Checked -or $chkAutoRestart.Checked) {
                $script:RestartAt = (Get-Date).AddSeconds(2)
                if ($chkFullscreenApp.Checked) {
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
    Load-Settings
    Initialize-GstJob
    Stop-StaleManagedProcesses
    if ($chkFullscreenApp.Checked) {
        $null = Resolve-FullscreenCaptureTarget -Quiet
    }
    Update-CaptureModeUi
    Update-MediaMtxUi
    Update-ProtocolUi
    Update-AudioCodecChoices
    Update-EncoderUi
    Update-CommandPreview
    Update-TrayMenuState
    Append-Log "Application icon: $($script:AppIconSource)"
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
        if ($script:GstProcess -and -not $script:GstProcess.HasExited) {
            Stop-ProcessTreeById -ProcessId $script:GstProcess.Id
            try { $script:GstProcess.WaitForExit(3000) | Out-Null } catch {}
        }
    }
    catch {}

    try {
        Stop-ManagedMediaMtx -Quiet
    }
    catch {}

    Remove-ActiveProcessState

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

try {
    # Use a normal WinForms application message loop instead of ShowDialog().
    # A modal ShowDialog() can return when the form is hidden, which made
    # minimize-to-tray look like an application crash and triggered cleanup.
    [System.Windows.Forms.Application]::Run($form)
}
finally {
    Invoke-ApplicationCleanup
}
