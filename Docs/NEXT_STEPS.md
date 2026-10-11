# Remaining before calling the complete pipeline production-ready

1. **Unity compilation + live QA** against the user's exact Unity 6.4/HDRP package version. Correct any HDRP CustomPass / VolumeManager version issues. Validate paired-frame alignment and EXR orientation.
2. **Colour-chart parity**: scene-linear working primaries, tone-map operator, exposure, Rec.709/sRGB return conversion, exact HDRP colour wheels. Test linear ungraded EXR via FULL replay before neural processing.
3. **Cinemachine / Recorder verification**: sample Timeline in manual mode, check live Cinemachine Brain output and ensure Recorder accumulation is off; check effects which run before post-process.
4. **Depth + motion vectors**: export linear depth (metres, units documented) and native HDRP motion vectors using verified HDRP CustomPass APIs, with known coordinate/motion conventions; QA at 1, 24, 120 frames.
5. **Player adapter**: patch external DLSS renderer to consume actual depth/motion buffers and verify feature receives them; third-party video player's current RGB input does not automatically use AOV files.
6. **Streaming importer**: current replay loads short image sequences into Unity assets, not thousands of 4K frames; stream from disk for production.
7. **Installer update**: existing Windows installer v0.2.0 only manages the neural player/harness, not automatic installation of FadoEXR Unity scripts.
