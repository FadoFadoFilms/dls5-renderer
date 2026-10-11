# FadoEXR Pipeline Manager (experimental v0.3)

This is the **first central desktop application** for the three existing components. It is not the Unity Editor, and is not yet a packaged Windows `.exe`/installer.

## Start on Windows

1. Clone the complete [FadoFadoFilms/dls5-renderer](https://github.com/FadoFadoFilms/dls5-renderer) repository, selecting the `dev` branch while QA is underway.
2. Double-click **`START-FADOEXR-MANAGER.cmd`** at the repository root. The launcher checks for Python **3.13** (and Tkinter) plus FFmpeg/FFprobe with EXR, FFV1, zscale and tonemap support. If something is missing, it installs official WinGet packages, then launches the GUI.
3. For manual setup or a forced FFmpeg update check, double-click **`Tools/SETUP-DEPENDENCIES.cmd`**. To see versions/status **without installing**, use **`Tools/CHECK-DEPENDENCIES.cmd`**. Requires `winget` (Microsoft App Installer) to install missing components. Logs are in `%LOCALAPPDATA%\FadoEXR\PipelineManager\dependency-logs`. See [Windows setup](../Tools/README-WINDOWS-SETUP.md).
4. Choose the **root** of the existing Unity HDRP film project, **root** of the separate EXR Renderer Unity project, the capture output root used inside the FadoEXR capture window, and the desired managed player installation directory. Click **Save paths**.
5. **Preview** and then **Update** each project's `Assets/FadoEXR`. The manager does not edit scenes or other project assets. Close/save Unity before copying scripts and reopen/allow compilation afterward.
6. Click **Download / update renderer** to explicitly fetch the newest complete community player with the existing verified installer updater. No third-party renderer binaries are bundled with this public repository.
7. In your film Unity Editor use `Tools > Fado Fado > EXR Roundtrip > 1 - Capture film`. Point its capture output root to the directory selected in the manager. Enable **Automatically stage grade data** while the manager is running, or use **Stage selected shot now**.
8. In EXR Renderer Unity Editor use `Tools > Fado Fado > EXR Roundtrip > 2 - Restore in EXR Renderer`, then **Load latest Pipeline Manager handoff**. This loads per-frame grade JSON; if processed frames have been staged it asks whether to import them. You still create profiles and start replay in Unity.
9. For a full short test, select the captured shot and click **EXR -> lossless player video**, then **Run DLSS + stage result**. The latter runs the existing PowerShell diagnostic/render harness, insists on a verified neural output, makes PNG16 images and hands them to the importer. You can launch the player UI separately. Manual video import deliberately warns that the output isn't verified.

## Safeguards

- Unity package updates *preview changes*, back up the existing `Assets/FadoEXR` to the user's app data (outside either Git repository), preserve other package files and Unity `.meta` GUIDs, and stage/swap files to prevent partially-written packages. **They do not commit or push to either Unity project's Git repository.** Check your Unity projects' local Git diffs and commit only if satisfied.
- The two Unity projects must be separate. Only `Assets/FadoEXR` is updated. No scene, Timeline, rendering, grading or engine preferences are automatically changed.
- An export handoff happens only if `capture-report.txt` says **Completed**, reports zero errors, and has all expected Clean, Reference and Grade frames. It copies **grade JSON**, **not raw EXRs**, to `<import Unity project>/.fadoexr-inbox/jobs/...`; this folder has its own `.gitignore` ignoring captured data so it won't be accidentally committed.
- The Unity importer reads a `<import Unity project>/.fadoexr-inbox/latest.json` pointer and loads the matching grade. If processed media is staged, it prompts before copying it into `Assets/FadoEXRImported`; generated frames and profiles get their own nested `.gitignore` in the separate Unity repository.
- The Auto handoff watcher only runs when this desktop application is open, **Auto handoff** is enabled, and Unity has completed a capture. There is no permanent background service.
- Each processed render must have the same frame count as its source; existing `ProcessedFrames` are never overwritten. Rerendering a shot requires a new shot ID or deliberately archiving old output first.
- The automatic render path requires `PASS_FULL_RENDER`, unchanged input, and evidence of Feature 18 operation in the existing harness summary. A rendered MKV by itself does **not** prove DLSS neural execution.
- Settings and player installation remain in local app data and configured player directory, so Git updates don't erase them.

## Data vs Git

The manager's `Manager/` source, scripts and docs belong in this umbrella repository. The user's original film Unity project and EXR Renderer Unity project can stay in their **own Git repositories**. Generated EXRs and media should remain **outside** their tracked `Assets` directories. Use appropriate Unity `.gitignore` rules for any project independently; our umbrella `.gitignore` cannot control another repository.

**Limitations:** Unity HDRP/C# compile is not yet checked on the user's machine. The current Unity importer imports PNG frames into Unity Assets for short shots (up to 240 frames and a conservative VRAM limit). It is not yet a production-grade streaming renderer. The player/FFV1 and colour-restoration path still require real-world QA. No automatic Unity application launch/scene modification is attempted.

## Scriptable CLI (optional)

```powershell
py -3.13 Manager/fadoexr_manager.py preview export 'D:\MyFilmUnity'
py -3.13 Manager/fadoexr_manager.py install export 'D:\MyFilmUnity'
py -3.13 Manager/fadoexr_manager.py install import 'D:\EXRRendererUnity'
py -3.13 Manager/fadoexr_manager.py handoff 'D:\FadoEXR_TestShots\Shot1' 'D:\EXRRendererUnity'
py -3.13 Manager/fadoexr_manager.py convert-exr 'D:\FadoEXR_TestShots\Shot1' --fps 24
```

`Tools/Install-FadoEXR.ps1` now calls the manager's safe install command as a compatibility wrapper; use `-Role Import` for the importer.
