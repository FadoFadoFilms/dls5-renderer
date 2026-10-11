# Automatic renderer download — installer v0.2.0

The Windows installer installs the offline-test harness locally, then offers to **download the newest published complete release** of `2600th/dlss5-video-player` straight from its official GitHub Releases. The button `Download / Update Renderer` and Start Menu shortcut can run the same updater later. This is opt-in at install time, not a silent background service; it never runs the downloaded player automatically.

Close DLSS Video Player before starting an update. The updater refuses to replace the runtime while DLSSVideoPlayer or NeuralWorker is running.

The updater:

1. Lists up to 30 published upstream releases including **pre-releases** (GitHub's `/releases/latest` skips them).
2. Selects the newest release carrying both `dlss5-video-player-vX.Y.Z-win64.zip` and that ZIP's `.sha256` (never the `core`, `source`, or source-code archive).
3. Downloads both from URLs under the official `2600th/dlss5-video-player` GitHub release.
4. Validates its exact named SHA-256, scans ZIP entry names/sizes and blocks symlinks and traversal paths.
5. Extracts into a separate staging folder; requires `DLSSVideoPlayer.exe`, `neural-runtime/NeuralWorker.exe`, `verify_package.ps1`, and `PACKAGE_MANIFEST.txt`.
6. Runs upstream `verify_package.ps1` before activating. If it fails, the previous runtime remains untouched.
7. Moves any current `upstream/` into `upstream-backups/backup-*` (preserves all user files), then swaps the newly verified folder into `upstream/`.
8. Writes a `renderer-version.json` stamp **outside** `upstream/` (to keep upstream package verification valid), plus logs under `update-logs/`.

On an already-current release, the updater skips the download unless deliberately run from PowerShell with `-Force`.

**Trust warning:** The complete package includes a **modified unsigned neural runtime** from a community maintainer; it is not official NVIDIA software. A `.sha256` check proves the downloaded ZIP matches the hash published alongside it, not that the binaries are malware-free. Review the upstream project's third-party notices and release provenance. The installer itself is unsigned and has not been executed on Windows in this build environment.

The updater is deliberately separate from the core `RTX2060-DLSS5-Offline-Test.ps1` runner so compatibility results still work offline and the harness does not silently update immediately before a render.
