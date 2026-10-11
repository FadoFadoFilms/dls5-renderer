# Source / design notes

This harness was designed against the public `2600th/dlss5-video-player` state visible on 2026-09-28, especially release v0.26.2 and its public documentation.

Relevant upstream behavior used here:

- `DLSSVideoPlayer.exe --render <input> --stages nr --processing-scale ... --range ... --out ...`
- offline worker processes frames sequentially and supports preroll for ranges;
- a short Feature-18 preflight occurs before neural render work;
- successful neural jobs require neural evidence rather than accepting NGX initialization alone;
- timestamp queries around DLSS evaluation and per-frame local-VRAM samples feed upstream receipts;
- player, worker and ReShade logs are appended rather than truncated;
- upstream says a complete package needs `neural-runtime/` beside the executable;
- driver 610.47+ is currently required by the upstream experimental path;
- RTX 20/30 hardware was explicitly described upstream as untested and expected to be slower due to lack of native FP8.

Why the harness uses the upstream executable rather than copying the neural runtime:

1. The source project is MIT, but the experimental neural runtime contains separately licensed/modified third-party binaries.
2. The upstream project itself hash-locks that runtime and warns that it is unsigned.
3. Reusing the upstream executable keeps the test on the same validation path as the public project instead of creating an unverifiable parallel implementation.
4. The goal here is the RTX 2060 compatibility experiment, not maintaining a second media player.

The harness adds only orchestration and diagnostics around that existing renderer.
