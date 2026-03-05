# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.1.0] - 2026-03-05

### Added

- Presets-first single-window UX with a compact sidebar workflow and queue-first main view.
- Built-in curated presets for H.264, HEVC, VP9, AV1, and ProRes with practical defaults.
- User presets support: save current settings and delete saved presets.
- Automatic switch to `Custom` preset when preset-controlled options are manually changed.
- Encoder availability detection from `ffmpeg -encoders` with AV1/VP9 capability-aware UI.
- Expanded import support for common video/audio containers and ffprobe-first validation.
- External subtitle workflow improvements with persisted selection and clear state transitions.
- Expandable per-job error details with full stderr log, command line, and copy actions.
- Keyboard navigation overhaul for sidebar controls:
  - global Tab/Shift+Tab traversal
  - arrow-key handling for pill groups
  - cyclic traversal and deterministic focus routing
  - snap-to-center focus scrolling
- Selection-aware queue operations (start/cancel/remove/output-folder assignment).
- Per-row and aggregate input file size display in queue/footer.
- About window refresh with icon, version/build metadata, repository link, and author link.

### Changed

- Sidebar options were simplified and organized around beginner-friendly essentials and collapsed advanced controls.
- Queue behavior now uses clearer run-scope semantics (`all` vs selected items) for start/resume.
- Toolbar workflow streamlined around Add, output folder, queue controls, and clear actions.
- Resolution/FPS/audio/subtitle controls aligned to consistent pill-style interaction patterns.
- Rename flow simplified with live preview and safer shared sanitization rules.
- Output overwrite handling made explicit and deterministic (`-y` when enabled; safe naming path when disabled).
- FFmpeg/FFprobe path discovery and onboarding guidance tightened for first-run reliability.

### Fixed

- Drag-and-drop file accessibility failures by applying security-scoped bookmark handling consistently.
- Queue state-machine edge cases after cancel/clear/remove that could leave Start/Resume stuck.
- Start/Resume/Cmd+Enter/Cmd+P inconsistencies by routing through shared runnable-scope logic.
- Subtitle mode regression where Add External could revert incorrectly after picker interactions.
- Duplicate/ambiguous option controls and conflicting command mappings in generated FFmpeg arguments.
- Focus traversal regressions across dynamic sidebar controls (custom resolution/FPS fields, tone-map gating, audio keep gating).
- Preset application consistency by resetting preset-controlled fields and preventing stale inherited values.

### Removed

- Legacy complex inspector/dashboard flows from pre-simplified UI.
- Terminal-like direct command-entry mode from user-facing workflow.
- Debug-only focus/scroll diagnostics and temporary troubleshooting logs from sidebar navigation code.

## [1.0.0] - 2026-03-05

### Added

- Initial release.

