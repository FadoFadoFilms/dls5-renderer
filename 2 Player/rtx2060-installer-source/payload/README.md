# RTX 2060 DLSS 5 Offline Video Test

A deliberately stripped-down Windows harness for testing the public `2600th/dlss5-video-player` experimental neural-rendering path on an RTX 2060 6 GB.

This is **not** a second DLSS implementation. It drives the upstream project's own offline renderer and its locked experimental neural runtime, then adds test-oriented orchestration around it: source-file integrity checks, short capability probes, optional isolated one-frame timing probes, GPU/VRAM telemetry, copied upstream logs, failure classification, and a final offline export.

## One-click download of the latest complete renderer (installer v0.2.0)

After installation, agree to the optional automatic download, or use **Start → RTX 2060 DLSS 5 Offline Test → Download / Update Renderer**. This fetches the newest **published complete Windows package**, including the neural runtime, from the original `2600th/dlss5-video-player` GitHub Releases page (including pre-releases). It checks the released `.sha256`, validates the ZIP, runs the upstream manifest verifier, and installs into `upstream\`. The old renderer is moved to `upstream-backups\` instead of being overwritten. Output `results\` stays untouched.

You can launch the player using **Open DLSS Player** in the Start Menu. Existing manual installs still work; the updater is optional. See `UPDATER-NOTES.md` for security and rollback details.

## Why this shape

The current upstream project already has the important renderer work we originally wanted to build:

- command-line offline rendering via `DLSSVideoPlayer.exe --render`;
- sequential `OfflineNeuralRenderer` processing, with preroll and temporal history;
- a Feature-18 neural preflight;
- render receipts/timing and local-VRAM measurement inside the renderer;
- logs from the player, worker and ReShade/RenoDX runtime;
- MKV/MP4 export while preserving the source file.

The missing piece for this experiment is a focused **"does an RTX 2060 6 GB execute this at all?"** harness that does not care about real-time playback.

## Upstream version targeted

- Repository: `https://github.com/2600th/dlss5-video-player`
- Originally developed with `v0.26.2` (2026-09-26); the installer can now fetch the latest complete published release. The installed runtime may have newer rendering settings and requirements.
- Upstream states that neural rendering needs an NVIDIA RTX GPU and driver **610.47 or newer**.
- Upstream currently reports hardware verification on RTX 4080 SUPER and RTX 5090, and says RTX 20/30 cards lack native FP8 and are expected to be several times slower but are untested.

## Important runtime note

The upstream neural runtime is a **modified, unsigned community build**, not an official NVIDIA DLSS 5 SDK package. This ZIP intentionally does **not** redistribute those third-party binaries.

With the v0.2.0 installer, the runtime can be downloaded and verified automatically after explicit consent. For a manual install, download the **complete** upstream Windows package yourself, verify it using `verify_package.ps1`, and extract it into this harness's `upstream\` folder. The main test also runs `verify_package.ps1` automatically when it is present unless `-SkipPackageVerify` is supplied.

Expected layout:

```text
rtx2060-dlss5-offline-test\
  RTX2060-DLSS5-Offline-Test.ps1
  RUN-DROP-VIDEO-HERE.bat
  upstream\
    DLSSVideoPlayer.exe
    verify_package.ps1
    neural-runtime\
      NeuralWorker.exe
      ReShade.ini
      dxgi.dll
      renodx-dlss5.addon64
      nvngx_dlssnr.dll
      ...
```

## Fastest way to run it

1. Update the NVIDIA driver to at least the upstream floor of **610.47**.
2. Put the complete upstream package into `upstream\`.
3. Drag a short normal video onto `RUN-DROP-VIDEO-HERE.bat`.
4. Read the generated `results\<video>-<timestamp>\REPORT.md`.

The default run does this:

1. hashes the input and records its size;
2. checks the GPU, the 610.47 driver floor, and available VRAM with `nvidia-smi`;
3. checks for the expected neural-runtime layout;
4. runs the upstream package verifier when present;
5. starts GPU sampling every 500 ms;
6. tries a short neural capability render at 100% processing scale;
7. if it cannot run, retries at 75%, then 50% unless `-NoScaleFallback` is set;
8. renders five isolated one-frame probes for worst-case wall-clock frame timing;
9. if the capability probe worked, renders the entire input offline using the upstream sequential renderer;
10. re-hashes the source and verifies that it is byte-for-byte unchanged;
11. copies upstream logs and recent `receipt.json`/manifest evidence from the neural cache, records whether the DLSSNR D3D12 runtime-initialized marker appeared, extracts the adapter name that actually created the D3D12 device when available, and writes `summary.json` plus `REPORT.md`.

## Output

A successful run contains:

```text
results\<video>-<timestamp>\
  REPORT.md
  summary.json
  events.csv
  gpu-samples.csv
  frame-probes.csv
  capability-probe-100pct.mkv
  <video>-dlss5-neural.mkv
  logs\
    receipts\
      receipt-001.json
      manifest-001.json
    capability-probe-100pct.log
    frame-000000.log
    ...
    full-render.log
    upstream-DLSSVideoPlayer.log
    upstream-NeuralWorker.log
    upstream-ReShade.log
```

## Verdicts

- `PASS_FULL_RENDER` — the validated upstream neural path produced a full output and the original file hash stayed unchanged.
- `PASS_CAPABILITY_PROBE` — probe succeeded and full render was intentionally skipped.
- `FAIL_DRIVER_TOO_OLD` — the NVIDIA driver is below the upstream 610.47 neural-runtime floor.
- `FAIL_RUNTIME_MISSING` — expected runtime files are absent.
- `FAIL_NEURAL_RUNTIME` — Feature 18/runtime-lock failure evidence was found.
- `FAIL_VRAM_OR_ALLOCATION` — out-of-memory/allocation evidence was found.
- `FAIL_DEVICE_REMOVED` — D3D12 device removal/hang evidence was found.
- `FAIL_RENDER` — generic render failure; inspect the copied logs.
- `FAIL_ORIGINAL_CHANGED` — source hash/size changed, which should never happen.

## Useful command-line variants

Probe only, no full-film render:

```powershell
powershell -ExecutionPolicy Bypass -File .\RTX2060-DLSS5-Offline-Test.ps1 -InputVideo "D:\video\clip.mp4" -ProbeOnly
```

Use an upstream package somewhere else:

```powershell
powershell -ExecutionPolicy Bypass -File .\RTX2060-DLSS5-Offline-Test.ps1 `
  -InputVideo "D:\video\clip.mp4" `
  -PlayerRoot "D:\Tools\dlss5-video-player-v0.26.2"
```

Only test source-resolution processing; do not fall back to 75%/50%:

```powershell
powershell -ExecutionPolicy Bypass -File .\RTX2060-DLSS5-Offline-Test.ps1 `
  -InputVideo "D:\video\clip.mp4" `
  -NoScaleFallback
```

Increase isolated one-frame timing probes:

```powershell
powershell -ExecutionPolicy Bypass -File .\RTX2060-DLSS5-Offline-Test.ps1 `
  -InputVideo "D:\video\clip.mp4" `
  -FrameProbeCount 30
```

## How to interpret timing

`frame-probes.csv` is deliberately pessimistic. Each row launches a separate upstream render for one frame, so it includes process startup, runtime initialization, preroll, neural evaluation, capture and encoder finalization. That answers the compatibility question — **can the card execute a neural frame at all, even very slowly?** — but it is not the steady-state neural kernel time.

The full export is the meaningful end-to-end test. It lets the upstream renderer keep its temporal state and process decoded frames sequentially. The harness also copies upstream render receipts created during the run when it can locate the cache; upstream collects per-captured-frame timing samples internally and records its native timing/VRAM evidence in the receipt, while `frame-probes.csv` gives explicit per-frame wall-clock probes.

## What counts as an RTX 2060 success

For this experiment, the strongest useful result is:

- RTX 2060 is the adapter actually used;
- driver passes the upstream minimum;
- upstream package verification passes;
- the runtime-initialized marker is recorded when present;
- capability probe creates a real neural output;
- no Feature-18 failure, runtime-lock failure, OOM or device-removal evidence appears;
- the full offline render completes;
- the original input SHA-256 is identical before and after.

That would demonstrate **practical compatibility of this specific community runtime on this exact RTX 2060/driver combination**. It would not turn it into official NVIDIA support.

## Safety / provenance

The harness itself does not patch drivers, modify the source video, or replace upstream runtime files. It only launches the upstream command-line renderer and reads diagnostics. Review the upstream project's third-party notices and unsigned-runtime warning before running it.

## RTX 2060 identity check

The final report records both the adapter reported by `nvidia-smi` and, when present, the adapter named by the upstream D3D12 device-creation log. That matters on multi-GPU systems: the helper process is the process that actually executes the neural render. `nvidia-smi` telemetry fields that return `N/A` are tolerated rather than aborting the run.

## Optional true source instrumentation

For a rebuilt source fork, see `SOURCE-FORK.md` and `patches/0001-rtx2060-native-per-frame-timing.patch`. The patch makes the upstream worker emit its native captured-frame timing samples one frame at a time. When those lines are present, the harness automatically writes `native-frame-timings.csv` in addition to the isolated wall-clock `frame-probes.csv`.
