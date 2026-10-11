# Pipeline and data ownership

Film HDRP camera -> before/after-post-process EXR colour captures + camera-resolved VolumeStack JSON per frame (never edit source Volume Profiles). Optional PlayableDirector in manual Update mode sampled per captured frame. Source EXR remains untouched.

FFmpeg bridge -> explicit scene-linear Rec709-primaries assumption -> SDR tone-map -> Rec709 encoded, 10-bit 4:4:4 lossless FFV1 MKV, validated frame count/codec, checksum receipt. Not visually lossless relative to the HDR scene; the SDR transformation changes values by design.

Community DLSS player -> processes RGB-only video, exports a new MKV using Lossless quality. Original input preserved. This is an experimental unsigned third-party neural runtime, not official RTX 2060 support.

Return conversion -> FFmpeg converts Rec709 transfer to sRGB PNG16. EXR Renderer loads frame-specific Volume snapshot as a new HDRP Volume and applies SAFE or FULL per frame before rendering new output EXRs. This stage **does not reconstruct HDR/scene-linear information**. Film project should remain the source of truth for reference images.

All generated files belong to the shot/project output; output names are unique; source volume assets untouched; old v0.1 archive and installer versions unaffected.
