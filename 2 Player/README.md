# RTX 2060 DLSS 5 experimental video player harness

The `rtx2060-installer-source/` directory contains **source**, launch scripts, the offline test runner, and the automatic upstream release downloader. The generated Win64 `installer.c` is intentionally not committed; generate it using `python3 generate_installer.py`, then use `build.sh` with clang/lld Windows cross-compilation requirements (see `BUILD-INSTALLER.md`).

**Third-party neural runtime is NOT bundled or relicensed.** Download it from the public [`2600th/dlss5-video-player`](https://github.com/2600th/dlss5-video-player) project through the opt-in updater/official releases, not from this GitHub repository. Runtime results on an RTX 2060 do not establish official NVIDIA support.

The previously built v0.2 installer is distributed separately as a binary artifact; source here is the project of record.
