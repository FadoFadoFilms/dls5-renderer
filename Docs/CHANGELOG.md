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
