# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2026-03-05

### Added

- Presets-first ForgeFF macOS app workflow for batch video conversion.
- FFmpeg/FFprobe integration with path auto-detection and onboarding when missing.
- Queue-based conversion engine with progress parsing and per-job status.
- Codec and container support: H.264, HEVC, VP9, AV1, ProRes; MP4, MOV, MKV.
- Subtitle handling modes: keep, remove, add external subtitle file.
- Cleanup controls: remove metadata and chapters.
- Advanced conversion options including resolution/FPS overrides and HDR to SDR.
- App icon source-of-truth in repository root (`app-icon.png`) with generated asset catalog set.
- GitHub Actions CI and release workflow for tagged builds (`v*`) with ZIP + SHA256 artifacts.
