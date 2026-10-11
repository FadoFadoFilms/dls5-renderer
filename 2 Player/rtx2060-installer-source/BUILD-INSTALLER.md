# RTX 2060 DLSS 5 Offline Test — installer v0.2.0

- Builds a Windows x64 GUI per-user installer targeting `%LOCALAPPDATA%\Programs\RTX2060-DLSS5-Offline-Test`.
- All first-party harness files are embedded from `payload/`. There is **no bundled DLSS third-party runtime**.
- Installer optionally launches `RUN-UPDATE-RENDERER.bat` immediately on first install. The downloader obtains the newest published **complete** upstream package from `2600th/dlss5-video-player` GitHub Releases, including prereleases.
- The updated finish window has **Download / Update Renderer**, **Open DLSS Player**, **Run Probe Only**, **Open Runtime Folder**, **Read README**, **Finish**.
- Installs the same actions as Start Menu shortcuts. Update is user-initiated and does not silently run on a schedule.
- Existing `upstream/`, `results/`, `upstream-backups/`, and `update-logs/` survive reinstalls and uninstalls.

To cross-compile on Linux with `clang`, `lld-link`, and Python 3:

```
./build.sh
```

`generate_installer.py` rebuilds payload arrays from `payload/` and recalculates `MANIFEST-SHA256.txt` on each build. Run `./build.sh` after any payload change. Source is in `installer-template.c` rather than editing the embedded-byte generated `installer.c`.

**Validation**: PE x64 and imports can be inspected with `llvm-objdump -p`. This build environment cannot execute the Windows installer or neural runtime; first live validation must be done on Windows.

Static smoke test after build: `python3 tests_static.py`.
