# GStreamer Glass

GStreamer Glass is a Windows PowerShell WinForms frontend for building, inspecting, and running low-latency GStreamer streaming pipelines.

The project is designed to make advanced real-time streaming workflows easier to configure without hiding the underlying GStreamer pipeline. It focuses on low latency, direct control over pipeline behavior, and exposing settings that would otherwise require manually authoring long `gst-launch-1.0` command lines.

## Project Capabilities

- Build and run low-latency desktop, display, camera, audio, and scene-composition pipelines.
- Configure hardware and software video encoders, including codec, bitrate, rate control, GOP, latency, and recovery-related options.
- Stream through supported GStreamer transports such as direct WebRTC, WHIP, SRT, and RTSP.
- Configure unified or split audio and video pipelines and signaling paths.
- Preview capture sources and composed scenes before or during streaming.
- Record streams independently using configurable recording settings.
- Generate and inspect the resulting GStreamer command line before launch.
- Override the generated pipeline using validated custom `gst-launch-1.0` arguments.
- Configure capture devices, network adapters, WebRTC signaling, STUN and TURN behavior, retransmission, FEC, and related transport settings.
- Serve a browser-based WebRTC player with playback controls, connection diagnostics, stream statistics, PWA support, and configurable latency-management behavior.
- Support local, proxied, and authenticated signaling deployments.
- Preserve explicit control over active pipeline options: disabled settings should not silently modify the generated command line.

## Build Requirements

Building GStreamer Glass requires:

- A Windows x64-compatible system.
- PowerShell.
- The [`ps12exe`](https://www.powershellgallery.com/packages/ps12exe) PowerShell module.
- Inno Setup 6 or 7.
- A local clone of this repository.

Install `ps12exe` for the current user:

```powershell
Install-Module ps12exe -Scope CurrentUser
```

Before building, open `build.iss` and update `ProjectRoot` to the full path of the local repository clone:

```iss
#define ProjectRoot "C:\Path\To\GStreamer-Glass"
```

Run the complete build from the repository root:

```powershell
.\build.ps1
```

The build process:

1. Reassembles the modular files under `src/` into `out/GStreamer-Glass.ps1`.
2. Compiles the generated PowerShell script into `out/GStreamer Glass.exe`.
3. Runs `build.iss` through the Inno Setup command-line compiler.
4. Writes the versioned installer to the `out/` directory.

The application version is read from `$script:AppVersion` in `src/00-Setup.ps1`. The installer configuration, included files, installation paths, shortcuts, and output filename remain managed by `build.iss`.

### Repository Build Files

- `src/` — active modular PowerShell source.
- `tools/build-monolith.ps1` — combines the modular source into the generated monolithic script.
- `build.ps1` — performs the complete application and installer build.
- `build.iss` — Inno Setup installer definition.
- `gstwebrtc-api/` — browser-based WebRTC player assets included with the installer.
- `icons/` — application and installer icon assets.
- `out/` — generated scripts, executables, and installer output.

## Project History

- This repository was initially seeded from recovered project snapshots.
- Older point releases are preserved as a best-effort linear Git history.
- Later releases are preserved as a linear Git history.
- Historical releases and experimental checkpoints are retained to document the evolution of the application and its streaming behavior.

## Development Model

GStreamer Glass is a human-architected, AI-assisted project.

Project direction, design, integration, testing, review, and release decisions are performed by a human maintainer. AI assistance is reviewed and credited in applicable commit metadata for full transparency.

## License

GStreamer Glass is licensed under the GNU Affero General Public License version 3 only (`AGPL-3.0-only`).

Modifications and redistributed versions must comply with the license, including the source-availability requirements that apply when modified versions are distributed or made available for users to interact with over a network.

GStreamer and other third-party components remain subject to their respective licenses.
