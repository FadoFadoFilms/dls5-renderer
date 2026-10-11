# Source-fork shape for the RTX 2060 offline experiment

The quickest usable test in this package deliberately drives the upstream v0.26.2 command-line renderer instead of rebuilding the GUI player. That keeps the exact public neural-validation path and separately supplied runtime intact.

If this experiment becomes a maintained source fork, the clean target is a console-only `DLSS5Offline.exe` rather than another media player.

## Keep

Media/input:

- `VideoDecoder`
- `HdrToneMapGpu`
- `MediaSource`
- `MediaPipeline`

D3D12 / DLSS / encode:

- `D3D12Renderer`
- `DLSSBackend`
- `TemporalGuides`
- `OpticalFlowNvof` where the guide path requires it
- `NvencDirect` and its policy
- `RuntimePolicy`

Neural/offline:

- `OfflineNeuralRenderer`
- `NeuralWorker`
- `NeuralPreflight`
- `RuntimeLock`
- `NeuralCache` / receipt-validation types required by the worker
- `ReShadeConfig`

Support:

- logging, platform paths, settings/receipt serialization, FFmpeg process helpers, GPU preference/export hints, and package/runtime verification code used by those modules.

## Drop from the user-facing target

- Win32 playback/player UI
- comparison views, loupe, split/wipe/difference presentation
- toolbar/menu/hotkeys
- YouTube discovery/playback UX
- subtitles as a viewing feature
- live seeking/session retargeting UI
- recent-video history UI
- frame-generation controls for this experiment
- VSR/live playback upscaling controls

The console should expose only: input, output, range, neural preset/processing scale, probe-only, log directory, and a machine-readable result.

## Per-frame native timing patch

`patches/0001-rtx2060-native-per-frame-timing.patch` is an optional v0.26.2 source patch. Upstream already collects one timing sample per captured frame but normally logs/receipts aggregate that data. The patch emits one `RTX2060_FRAME_TIMING ...` log line per captured frame and avoids sorting the original GPU-timing vector in place.

Apply it from an upstream source checkout:

```powershell
git apply path\to\0001-rtx2060-native-per-frame-timing.patch
```

Then build the upstream worker/player using the project's documented Windows/CMake process. Point this harness at that built package with `-PlayerRoot`. The harness will still perform source hashing, VRAM sampling, capability probes and final classification.

## Why the distributed ZIP is a harness rather than a rebuilt binary

The source repository is open source, but the experimental neural runtime is a separate, modified unsigned runtime and is not part of GitHub's source ZIP. Repackaging that runtime into an independently built binary would add provenance and licensing ambiguity without helping answer the first question: **can the RTX 2060 6 GB execute the existing experimental neural path at all?**
