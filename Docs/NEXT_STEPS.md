# Remaining before calling the complete pipeline production-ready

1. **Unity compilation + live QA** against the user's exact Unity 6.4/HDRP package version. Correct any HDRP CustomPass / VolumeManager version issues. Validate paired-frame alignment and EXR orientation.
2. **Colour-chart parity**: scene-linear working primaries, tone-map operator, exposure, Rec.709/sRGB return conversion, exact HDRP colour wheels. Test linear ungraded EXR via FULL replay before neural processing.
3. **Cinemachine / Recorder verification**: sample Timeline in manual mode, check live Cinemachine Brain output and ensure Recorder accumulation is off; check effects which run before post-process.
4. **Depth + motion vectors**: export linear depth (metres, units documented) and native HDRP motion vectors using verified HDRP CustomPass APIs, with known coordinate/motion conventions; QA at 1, 24, 120 frames.
5. **Player adapter**: patch external DLSS renderer to consume actual depth/motion buffers and verify feature receives them; third-party video player's current RGB input does not automatically use AOV files.
6. **Streaming importer**: current replay loads short image sequences into Unity assets, not thousands of 4K frames; stream from disk for production.
7. **Installer update**: existing Windows installer v0.2.0 only manages the neural player/harness, not automatic installation of FadoEXR Unity scripts.

## New priorities after v0.3 Pipeline Manager

8. **Windows GUI acceptance test:** Double-click launcher on user's Windows system. Verify settings persist across Git pulls, preview/backups preserve separate Unity project Git working trees, and UI behaves correctly at 125%-175% DPI.
9. **Unity importer compile and handoff test:** Compile updated `ReplayWindow.cs` in Unity 6.4 HDRP. Capture one frame, start manager watcher, ensure correct `.fadoexr-inbox/latest.json`, and use importer **Load latest Pipeline Manager handoff**. Verify no extra media is automatically imported into Unity Assets.
10. **Player update + render acceptance:** Test PowerShell updater and manifest verification on Windows, lossless FFV1 input, parser of summary.json, and only stage genuine neural output. Compare extracted PNGs to source reference with a colour chart.
11. **Distribution:** Build/code-sign a standalone Windows app/installer after QA (Python 3 is currently required) and consider a supported plugin architecture for optional GUI automation without changing source Unity scenes.
12. **Scale:** Replace 240-frame capped short-shot importer with on-disk streaming, a job queue, progress/pause/retry and editable shot metadata. Add robust handoff-on-export when the app is not open via a user-approved helper service if needed.

8. **Windows dependency bootstrap QA:** run the new setup/check CMD files on the target Windows PC, confirm winget-installed Python 3.13 and full FFmpeg/FFprobe are discoverable immediately, then launch the Tkinter manager. Validate offline/no-winget and existing custom-FFmpeg scenarios. Static source checks do not replace this real Windows test.
