# EXR Renderer — Unity import/regrade package (v0.2)

Create a separate Unity 6 HDRP project **matching the film project's HDRP version**, and copy this directory's **entire** `Assets/FadoEXR` into it, including `Editor`, `Runtime`, and `Shaders`.

Unity menu: **Tools → Fado Fado → EXR Roundtrip → 2 - Restore in EXR Renderer**. Create replay camera, import all grade JSONs (and referenced asset packages if present), create FULL/SAFE Volume Profiles, import 16-bit PNG frames, and render to new EXR sequence. For SDR neural output, start with the SAFE profile and verify no double tonemapping.

See root README and `Docs/QA.md`; fidelity remains unverified in real Unity.
