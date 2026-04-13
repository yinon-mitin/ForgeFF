# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2.0.0] - 2026-04-13

### Added

- Primary preset cards for the common export paths, including Fast MP4, Efficient HEVC, Editing ProRes, and compact web-share presets.
- Multiple external audio tracks with ordered add, review, clear, and remove behavior.
- Multiple external subtitle files with per-track language fields and ordered muxing support.
- Queue percentages, Dock progress, richer output previews, and Quick Look access for completed items.
- Output-folder drag-and-drop for default output and selection-scoped output overrides.
- Sidebar-wide keyboard routing that reaches preset cards, advanced controls, toolbar actions, queue actions, and the About window.

### Improved

- The sidebar now defaults to a cleaner presets-first workflow with advanced controls tucked behind `More Settings`.
- Audio and subtitles are now separate, clearer advanced sections with less visual noise.
- Custom and user presets now behave like first-class presets with cleaner highlighting, status, import/export, and reset behavior.
- Queue rows now expose clearer progress, better failure details, more reliable preview thumbnails, and cleaner completed-output actions.
- The About window and public-release presentation were cleaned up around version/build visibility and GitHub Releases distribution.

### Changed

- Preset customization state is now derived from the effective conversion settings instead of sticky UI flags.
- Running jobs now use a resolved settings snapshot and ignore later preset changes.
- Manual advanced overrides remain available, but the default path no longer exposes codec-heavy controls up front.
- Release packaging now centers on versioned GitHub Release archives and checksums instead of repository-stored binary artifacts.

### Fixed

- `Customized` and `Modified` indicators now clear when settings return to the selected preset or the active default state.
- Custom FFmpeg command state only counts as active when enabled, and `Insert Example` no longer causes sidebar jumpiness.
- Focus order, Tab/Shift-Tab behavior, and scroll stability across the current UI now match the visible layout.
- Converted outputs now generate previews from the produced file instead of falling back to stale or generic icons.
- Preset handling, queue execution, and manual-override logic now stay consistent when switching between presets, custom settings, and running jobs.


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

- Presets-first ForgeFF macOS app workflow for batch video conversion.
- FFmpeg/FFprobe integration with path auto-detection and onboarding when missing.
- Queue-based conversion engine with progress parsing and per-job status.
- Codec and container support: H.264, HEVC, VP9, AV1, ProRes; MP4, MOV, MKV.
- Subtitle handling modes: keep, remove, add external subtitle file.
- Cleanup controls: remove metadata and chapters.
- Advanced conversion options including resolution/FPS overrides and HDR to SDR.
- App icon source asset in the repository root with generated asset catalog set.
