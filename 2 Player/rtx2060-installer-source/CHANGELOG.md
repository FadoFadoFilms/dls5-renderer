# RTX2060 DLSS Offline Test Installer — Change log

## v0.2.0 — 2026-10-11

- Added first-install **Download newest complete renderer** prompt, with a clearly disclosed community unsigned runtime and estimated download size.
- Added Start Menu launchers for **Download or Update Renderer** and **Open DLSS Video Player**.
- Added a 6-action installer completion UI; kept the larger fixed-window completion layout.
- Added a Windows PowerShell 5.1 updater that queries GitHub releases, including pre-releases, for the newest published complete Windows archive and matching SHA-256 asset.
- SHA-256 checks, ZIP traversal/size/symlink checks, upstream package verification, staging-before-replacement, rollback and per-run logs.
- Previous player directories go to `upstream-backups/` rather than being overwritten. Results are never modified by updater.
- Version metadata stored **outside** the upstream folder so `verify_package.ps1` can still validate the package unchanged.
- Guards concurrent updates and refuses to replace a runtime while DLSSVideoPlayer / NeuralWorker is running.
- Remains per-user, no elevation, no silent background update and no bundled neural binaries.

### Validation in this build environment

- Linux cross-compiled with `clang` + `lld-link` to Windows x64 PE GUI executable.
- Inspected import table and PE architecture; confirmed 15 installer files are embedded in PE byte-for-byte.
- Static source/payload/PowerShell sanity tests passed.
- Windows install, downloader network flow, and native neural rendering **not run here**. Test once on a Windows PC before wide distribution.

## v0.1.1

- Fixed clipped installer completion screen; preserved existing runtime/results.
