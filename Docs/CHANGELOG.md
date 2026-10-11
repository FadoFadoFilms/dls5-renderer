# Change log

## 0.2.0 (2026-10-11)
- Built FFmpeg EXR->Rec709 FFV1 bridge with continuity and output verification, no overwrites.
- Added PlayableDirector manual frame sampling option and start frame in Unity film capture.
- Added automatic per-frame FULL/SAFE Volume creation and aligned replay; refuses grade/frame count mismatch unless explicit static grade confirmation.
- Added native Rec709 transfer -> sRGB 16-bit PNG extraction for Unity texture import.
- Bundled correct RTX2060 AutoLatest player installer v0.2.0 source and unchanged executable.
- Synthetic EXR bridge tests passed; C# only static checks. Unity QA still required.

## 0.1.0
- Initial Clean/Reference EXR HDRP capture, post-processing JSON and static colour replay prototype.

## 2026-10-11 - v0.3 Pipeline Manager (on dev)

- Added first Windows-friendly Python/Tkinter **FadoEXR Pipeline Manager** with persistent local settings, project folder picker, install preview, backups, and safe exporter/importer package updates into separate Unity Git checkouts. No automatic Git commits.
- Added explicit install/update of the newest *complete* third-party community DLSS player using existing release verifier and PowerShell RTX 2060 diagnostic render harness; neural binaries are not bundled.
- Added automatic completed-capture detection and importer handoff: valid per-frame grade JSON staged under `.fadoexr-inbox` outside Unity Assets; generated files ignored by that project's local `.gitignore`.
- Added `Load latest Pipeline Manager handoff` in Unity importer to consume staged grades and optionally processed PNG frames. Clears previously loaded frame list on shot changes to avoid grade/image mismatch; importer-generated Volume/PNG Assets now receive their own nested .gitignore to avoid accidental commit in its independent Git repository.
- Added strict FFV1-to-player and verified-render-to-PNG16 UI steps, with an explicit unverified manual-video override.
- Fixed obsolete `Tools/Install-FadoEXR.ps1` to call the new safe installer with Export/Import roles.
- Local Python regression tests passed. Unity HDRP compile, Windows GUI, live PowerShell player update/render and colour fidelity remain **unverified**.
