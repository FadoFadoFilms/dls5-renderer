# Unity film capture package (v0.2)

Copy this directory's `Assets/FadoEXR` into your **existing Unity 6 HDRP film project**. This folder contains Editor scripts **and** the Runtime frame driver; don't copy Editor alone.

Unity menu: **Tools → Fado Fado → EXR Roundtrip → 1 - Capture film**. Select actual camera, optionally Timeline director, start at one frame for QA. Export saves ungraded/graded EXRs plus a resolved per-frame grading JSON without intentionally changing your original Volume settings.

See root README and `Docs/QA.md`. Unity compile/render QA still required.
