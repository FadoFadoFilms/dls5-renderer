# Pipeline and data ownership

Film HDRP camera -> before/after-post-process EXR colour captures + camera-resolved VolumeStack JSON per frame (never edit source Volume Profiles). Optional PlayableDirector in manual Update mode sampled per captured frame. Source EXR remains untouched.

FFmpeg bridge -> explicit scene-linear Rec709-primaries assumption -> SDR tone-map -> Rec709 encoded, 10-bit 4:4:4 lossless FFV1 MKV, validated frame count/codec, checksum receipt. Not visually lossless relative to the HDR scene; the SDR transformation changes values by design.

Community DLSS player -> processes RGB-only video, exports a new MKV using Lossless quality. Original input preserved. This is an experimental unsigned third-party neural runtime, not official RTX 2060 support.

Return conversion -> FFmpeg converts Rec709 transfer to sRGB PNG16. EXR Renderer loads frame-specific Volume snapshot as a new HDRP Volume and applies SAFE or FULL per frame before rendering new output EXRs. This stage **does not reconstruct HDR/scene-linear information**. Film project should remain the source of truth for reference images.

All generated files belong to the shot/project output; output names are unique; source volume assets untouched; old v0.1 archive and installer versions unaffected.

## Pipeline Manager (v0.3 source; experimental)

`START-FADOEXR-MANAGER.cmd` -> `Manager/fadoexr_manager.py` (Tkinter UI and CLI) -> `Manager/pipeline_core.py` (project sync, capture validation, inbox handoff, renderer invocation).

Unity film project and Unity importer project are separate external Git checkouts. The manager copies only the corresponding `Assets/FadoEXR` source package, preserving existing `.meta` files and backing up the folder outside the repos before updates; it does **not** run git commits/pushes in those checkouts.

`FilmCapture.Stop` produces `capture-report.txt` after all requested async readbacks are resolved. Manager checks report reason, error count, counts and frame presence before transferring per-frame grade JSON to the import project `.fadoexr-inbox/jobs/<stable-id>/Grade`. It atomically writes `handoff.json` and `latest.json` and intentionally does not duplicate large raw Clean/Reference EXRs. This staging folder is outside Assets and has a nested `.gitignore` to protect private shot data in the import project's Git repo.

The existing upstream player downloader is invoked via PowerShell **only after user confirmation**, with the updater's SHA256 + upstream package-verifier safety gates. Existing RTX2060 diagnostic harness processes FFV1 clip and generates `Player_Output/<session>/summary.json`. Pipeline Manager only automatically converts/stages output when verdict is `PASS_FULL_RENDER` with Feature-18 evidence and unchanged source input. Processed PNG16 frames are copied into the importer `.fadoexr-inbox` when verified or explicitly approved via the manual-video path.

In Unity's EXR Replay window, the new **Load latest Pipeline Manager handoff** button loads the saved grade sequence from the inbox, offers to import its PNGs into Assets only after approval, and requires manual profile/render setup. GUI-only app exit stops the watcher. None of the steps edit the source film's Timeline, HDRP settings or source Volumes.
