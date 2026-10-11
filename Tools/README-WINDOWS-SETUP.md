# Windows dependencies for FadoEXR Pipeline Manager

**Requires Windows 10/11 x64 and internet access for installing missing tools.**

The root `START-FADOEXR-MANAGER.cmd` now invokes `Tools/Ensure-Windows-Dependencies.ps1` before opening the manager. You no longer need to install Python or FFmpeg by hand if Windows Package Manager (`winget`) is available.

## One-time setup or diagnosis

- Double-click `Tools/SETUP-DEPENDENCIES.cmd` to immediately check **and install** missing dependencies and check for an FFmpeg package update.
- Double-click `Tools/CHECK-DEPENDENCIES.cmd` for a **read-only** check, with no downloads or upgrades.
- Or just open `START-FADOEXR-MANAGER.cmd`: the same check runs automatically, installs anything missing, and starts the GUI. This checks for an update of a **winget-managed** FFmpeg no more than once per 7 days. The separate setup shortcut forces a fresh upgrade check.

Versions are resolved and validated **after** installation, so the manager uses the correct FFmpeg/FFprobe pair even if this terminal was started before Windows updated PATH. If the installation is discoverable only after a new Windows session, setup stops with an instruction to restart the terminal and rerun. It never claims an unavailable dependency installed correctly.

### Packages managed

| Dependency | Windows Package Manager ID | Why |
|---|---|---|
| Python **3.13.x** | `Python.Python.3.13` | Tkinter desktop GUI. Python 3.12/3.14 alone does not satisfy this explicit version requirement. |
| FFmpeg full (stable WinGet package) | `Gyan.FFmpeg` | Includes `ffmpeg.exe`, `ffprobe.exe`, FFV1 encoder, EXR decoder, `zscale` and `tonemap` filters required by the current interchange pipeline. |

Python is installed side-by-side; other Python versions and their existing defaults are not uninstalled or overwritten. The script upgrades FFmpeg **only if WinGet identifies an existing `Gyan.FFmpeg` installation**. A working custom FFmpeg build is left intact, rather than replaced without notice. "Latest" means the newest stable version currently available for that package in your WinGet source, not a nightly snapshot.

If you already have FFmpeg but lack `ffprobe`, `zscale`, `tonemap`, the FFV1 encoder or EXR decoder, a **full** FFmpeg build is installed in addition. The manager's process PATH is adjusted to use the verified pair without persisting changes to machine/user PATH.

**Note:** Installing missing prerequisites and upgrading a managed FFmpeg are explicitly authorised by running the launcher or setup command. WinGet may ask Windows for elevation, and package downloads require internet. Installation failures leave pre-existing installations untouched where possible.

## Diagnostics

Dependency logs are saved outside Git at:

`%LOCALAPPDATA%\FadoEXR\PipelineManager\dependency-logs\`

The last successful FFmpeg upgrade check time is saved in:

`%LOCALAPPDATA%\FadoEXR\PipelineManager\ffmpeg-last-upgrade-check.utc`

Manual PowerShell commands:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Tools\Ensure-Windows-Dependencies.ps1 -CheckOnly
powershell -NoProfile -ExecutionPolicy Bypass -File .\Tools\Ensure-Windows-Dependencies.ps1 -InstallMissing -UpgradeFFmpeg -ForceUpgradeCheck
```

If `winget` cannot be found, install Microsoft's **App Installer** from Microsoft Store or use the official installers for Python 3.13 and the Gyan FFmpeg full build; reopen Windows Terminal afterwards. The script will not execute unverified download URLs or bypass WinGet's package hashes. `-CheckOnly` does not require WinGet if both tools are already available.

## QA limitation

These scripts are prepared and statically checked in the GitHub repo; we **have not remotely verified the installations on your actual PC**. Please run `Tools/SETUP-DEPENDENCIES.cmd` once, and share its final READY/ERROR line if anything fails. Unity 6.4 HDRP compile and end-to-end neural rendering remain separate QA steps.
