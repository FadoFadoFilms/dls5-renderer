# FadoEXR v0.2 QA (11 October 2026)

| Test | Result | Notes |
|---|---|---|
| Python FFmpeg synthetic EXR (3 frames) -> FFV1 10-bit video | PASS | FFprobe codec/count/tag checks |
| EXR original unchanged; re-run refuses overwrite | PASS | Local automated tests |
| EXR missing frame index refused | PASS | Local automated tests |
| C# bracket parsing and component structural tests | PASS | Pygments, not a C# compiler |
| Windows auto-download installer v0.2.0 source static test | PASS | Existing unchanged installer source |
| Unity 6.4 HDRP Editor compile | **NOT RUN** | Unity not installed in this environment |
| HDRP custom pass EXR buffers orientation/color | **NOT RUN** | Needs target Unity project |
| Timeline/Cinemachine exact capture timing | **NOT RUN** | Test camera pan with frame markers |
| All HDRP Volume components resolved & recreated | **NOT RUN** | Requires live HDRP stack/camera |
| Per-frame SAFE grade matched to DLSS image | **NOT RUN** | Verify with animated temperature/contrast |
| Player accepts FFV1 input & DLSS executes | **NOT RUN** | Requires RTX/Windows/upstream runtime |
| Depth/motion-buffer export & injection into DLSS | **NOT IMPLEMENTED** | Separate experimental milestone |
| FFmpeg Rec709->sRGB PNG conversion | FILTER CHECK PASSED | Verify visual colourchart in Unity |

## User QA order

1. Back up original Unity project. Import whole `Assets/FadoEXR` folder; check Console for **zero errors**.
2. Capture **one frame** and verify `Clean`, `Reference`, `Grade` exist.
3. Compare original Reference frame and clean regraded with FULL profile in a managed image viewer. If they don't match, diagnose colour pipeline *before* enabling DLSS.
4. Run 24-frame Timeline pan at 24 FPS. Check each `grade_XXXXXX.json` maps to intended time.
5. Use the EXR->MKV converter, inspect MKV in player, save lossless DLSS output, convert it to 16-bit PNG.
6. Restore SAFE grade for the whole 24-frame shot. Compare original reference vs original->DLSS->SAFE outputs for camera movement, colours, skin tones and contrast.
7. Save Unity Console logs and `capture-report.txt`/`replay-report.txt` when reporting a bug.

**Stop conditions:** compile errors; output count mismatch; sample time mismatch; unexpected frame flip; clipped highlights/tonemapping; DLSS runtime bypass/Feature-18 skipped.

## v0.3 Manager local validation (source only)

- Unit tests: exporter/importer packages remain separate, nested project `Assets/FadoEXR` preview/install, preserved `.meta` and unmanaged user files, app-data backup, and no-op repeat update.
- Unit tests: incomplete/error captures refused; valid grade handoff keeps raw EXRs outside importer project; `.fadoexr-inbox/.gitignore` auto-created.
- Unit tests: processed frame count/name mismatch rejected, repeat handoff refuses overwrite, neural render summary checked for positive Feature 18 evidence.
- Unit tests: linked destination folder refused, C# handoff entrypoint and root ignore rules present.
- **NOT RUN:** GUI on Windows, user-project Git diff validation, Unity 6.4 C# compile/Play Mode, live auto handoff watcher, latest third-party player runtime install and GPU render. Do not label the complete pipeline fully tested.

## v0.3.1 Windows prerequisite setup verification (pending Windows PC)

- **PASS (static, non-Windows):** 6 tests covering package IDs, launcher flags, required codecs/filters, diagnostic modes and safe update constraints.
- **NOT RUN:** Windows PowerShell script execution / WinGet missing-Python 3.13 install / FFmpeg update / PATH refresh / GUI startup.
- On Windows, run `Tools/CHECK-DEPENDENCIES.cmd` first and save status, then run `Tools/SETUP-DEPENDENCIES.cmd` if required. Verify actual `python 3.13`, Tkinter import, FFmpeg version/path, FFprobe path and `zscale/tonemap` presence.
- Re-open `START-FADOEXR-MANAGER.cmd` and confirm the Manager UI starts without a manual Python/FFmpeg PATH change.
- **Stop:** a failed WinGet install, FFprobe mismatch, nonfunctional `zscale`, multiple competing `ffmpeg.exe` commands, or upgrade accidentally altering an existing custom FFmpeg. Preserve logs from `%LOCALAPPDATA%\FadoEXR\PipelineManager\dependency-logs`.
