; SPDX-License-Identifier: AGPL-3.0-only

; GStreamer Glass installer

#define MyAppName "GStreamer Glass"
; build.ps1 passes the real version via /DMyAppVersion=...; this is only a
; fallback so `ISCC build.iss` still compiles standalone.
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#define ProjectRoot "C:\Users\geofferey\Downloads\GStreamer-Glass"
#define BuildDir ProjectRoot + "\out"
#define InstallerDir ProjectRoot + "\out"

[Setup]
AppId={{0D039513-087B-4898-A887-029F19194805}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}

AppPublisher=NETLABWORK
AppPublisherURL=https://github.com/geofferey/GStreamer-Glass/
AppSupportURL=https://github.com/geofferey/GStreamer-Glass/
AppUpdatesURL=https://github.com/geofferey/GStreamer-Glass/

DefaultDirName={autopf}\{#MyAppName}
UninstallDisplayIcon={app}\GStreamer Glass.exe
DisableProgramGroupPage=yes

OutputDir={#InstallerDir}
OutputBaseFilename=GStreamer-Glass-Setup-v{#MyAppVersion}
SetupIconFile={#ProjectRoot}\icons\Glass2Glass-Streamer.ico

SolidCompression=yes
WizardStyle=modern dynamic

ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BuildDir}\GStreamer Glass.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#ProjectRoot}\gstwebrtc-api\*"; DestDir: "{app}\gstwebrtc-api"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\GStreamer Glass.exe"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\GStreamer Glass.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\GStreamer Glass.exe"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

