# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed

- Finder `Open With` metadata analysis now works with Homebrew FFprobe builds that load external codec libraries such as `libvmaf`; the desktop target no longer enables App Sandbox, which cannot load those external dynamic libraries.
- Metadata analysis now records a safe success/failure event in the ForgeFF subsystem log without logging media contents or credentials.
- ForgeFF now checks the official GitHub Releases feed at launch and supports user-confirmed checksum-verified in-app updates.

## [2.6.7] - 2026-08-28

### Fixed

- Tests no longer depend on the user's persisted ForgeFF settings.
- Opening multiple media files from Finder with Open With now adds every selected file to the queue.
- The main window and failure inspector adapt better to smaller window sizes instead of forcing content beyond the visible bounds.
- Diagnostic report string construction remains compatible with the Xcode 16 compiler used by CI.

## [2.6.4] - 2026-08-18

### Added

- ForgeFF registers supported video and audio formats with macOS so files can be sent to the app from Finder using Open With.
- Files opened from Finder are added to the queue with the last-used conversion settings, selected automatically, and configured to export beside the source file when macOS grants access to that folder.
- Homebrew FFmpeg detection now checks both standard `bin` symlinks and `opt/ffmpeg/bin` paths on Apple silicon and Intel Macs.

### Changed

- The empty queue now keeps preset selection in the sidebar and presents only clear Add Files and Add Folder actions in the detail area.
- The sandbox remains enabled while read-only exceptions are limited to FFmpeg and FFprobe paths managed by Homebrew.

### Fixed

- Opening About no longer leaves sidebar keyboard-focus outlines visible through the dimmed backdrop.
- Sidebar focus navigation normalizes accidental horizontal scrolling, preventing labels and preset cards from being clipped at the leading edge.

## [2.6.3] - 2026-08-17

### Added

- Failed and cancelled task inspectors can export a complete plain-text diagnostic report with an automatically generated safe filename.
- Diagnostic reports can be copied directly, and an exported report file can be copied for attaching to an issue or message.
- The FFmpeg setup screen now provides explicit Close and Quit ForgeFF actions, including a working `Command-Q` shortcut.
- About ForgeFF now appears as a centered in-app card with a dimmed backdrop, author information, version/build details, and repository links.

### Fixed

- Retrying a task from the failure inspector now closes the inspector first and restores the queue to the full available width.
- Closing the FFmpeg setup screen is no longer blocked when FFmpeg or FFprobe is missing, so the setup prompt cannot trap the application.
- `Command-/` now opens the in-app About presentation instead of creating a separate utility window.

## [2.6.2] - 2026-08-17

### Added

- Average processing FPS is calculated from FFmpeg's encoded frame count and the task's elapsed time, then shown for completed, failed, and cancelled jobs when data is available.
- JSON history records and CSV exports now retain average processing FPS.
- A local release packaging script builds a universal macOS app, applies an ad-hoc hardened-runtime signature with the app's sandbox entitlements, verifies it, and creates a ZIP with a SHA-256 checksum.

### Changed

- Local debug builds are ad-hoc signed before launch or debugging.
- Tagged GitHub releases no longer require an Apple Developer account or repository signing secrets; GitHub Actions now applies an ad-hoc signature to the universal Release app.

### Security

- Ad-hoc signing verifies bundle integrity but does not establish a trusted developer identity or provide Apple notarization. Gatekeeper may still require users to confirm the first launch.

## [2.6.1] - 2026-08-16

### Added

- VP9 and AV1 balanced presets are now available directly in the primary preset list; unavailable encoders are clearly marked and cannot be selected.

### Changed

- `Telegram (Original Resolution)` is now named `Telegram` while continuing to preserve the source resolution and frame rate.
- The compact Telegram-style HEVC preset is now named `Efficient HEVC` and replaces the older primary HEVC card.
- `Editing ProRes` is kept as the final primary preset.

### Fixed

- Selected running queue rows keep readable titles, metadata, badges, and actions on light selection backgrounds by using explicit adaptive macOS label and link colors.

## [2.6.0] - 2026-08-16

### Added

- A compact live queue summary above the job list with running, queued, completed, failed, and current FPS information.
- A dedicated right-side failure inspector for error logs, FFmpeg version details, executed commands, retry actions, and source/output shortcuts.

### Changed

- The toolbar is now the single primary place to add files while a non-empty queue is visible; the empty state keeps its contextual import action.
- `Clear` is now the explicit `Clear Finished` menu, with a separate confirmed action for clearing the entire queue.
- Start and More/Less Settings remain pinned at the bottom of the sidebar while detailed settings scroll independently.
- Primary preset cards are shorter and visually lighter, keeping more of the common workflow visible at once.
- Failed and cancelled queue rows stay compact because verbose diagnostics no longer expand inline.

## [2.5.0] - 2026-08-16

### Added

- Live FFmpeg processing speed in frames per second on running and paused queue rows.
- A `Smallest File / Web Share` HEVC preset that mirrors the Telegram preset's quality, encoder, source resolution/FPS, AAC stereo, 4:2:0, and web-optimization settings.
- `Command-/` opens the About window, and `Command-,` toggles the More Settings section.

### Changed

- The primary `Smallest File / Web Share` card now consistently produces an MP4 HEVC file instead of selecting AV1 or VP9 based on local encoder availability.

### Fixed

- Selected queue rows now use a subtle accent tint with semantic text colors, preventing titles, metadata, FPS, and actions from disappearing when macOS supplies a light or inactive selection background.

## [2.4.0] - 2026-08-16

### Added

- Per-file conversion time on completed, failed, and cancelled queue rows.
- Final output size shown as a percentage of the original input size.

### Improved

- Initial size estimates continue to use codec, quality, resolution, FPS, and source-bitrate characteristics without assuming a fixed correction factor.
- While encoding, ForgeFF progressively refines the predicted final size from FFmpeg's actual bytes written and encoded duration, giving VBR and quality-based jobs a more accurate estimate as they advance.

### Fixed

- Final FFmpeg status lines with `time=N/A` no longer reset progress to 0% during muxing or file finalization.
- Queue progress is monotonic and cannot move backwards after reaching a later stage.

## [2.3.0] - 2026-08-16

### Added

- Live queue admission: files and folders added during a running or paused batch automatically join the active queue.
- Context-aware `Add to Queue…` controls in both the main toolbar and queue header.
- A reproducible build, launch, debug, log, telemetry, and smoke-test script for local development.

### Improved

- FFprobe metadata analysis and FFmpeg version checks now complete asynchronously without blocking the main interface thread.
- FFmpeg and Apple converter progress delivery is rate-limited to reduce UI work during high-throughput encodes.
- ForgeFF waits for newly added files to finish metadata analysis before deciding that the active queue is complete.

### Fixed

- Files added to a selection-scoped run now join that live run instead of remaining outside the active queue.
- The app remains interactive more reliably while FFmpeg is consuming substantial CPU, GPU, memory, or disk resources.

## [2.2.0] - 2026-08-16

### Added

- A dedicated `Telegram (Original Resolution)` preset for camera footage and other large sources.
- Telegram-safe H.264 output with 8-bit 4:2:0 pixels, AAC stereo audio, source resolution/FPS preservation, and MP4 fast-start metadata.

### Improved

- HEVC exports in MP4 and MOV use the broadly compatible `hvc1` codec tag.
- Presets can now carry web-optimization, pixel-format, audio bitrate, and channel defaults as part of their saved configuration.

### Fixed

- Sony and other 4:2:2 camera sources no longer inherit a pixel format that Telegram clients may fail to decode when the Telegram preset is used.
- MP4 outputs created for Telegram can begin playback before the entire file is downloaded.

## [2.1.0] - 2026-04-15

### Added

- Tone-mapping engine selection so HDR to SDR jobs can use Apple VideoToolbox or FFmpeg filters when both are available.
- Release packaging updates for a local `release/ForgeFF-2.1.0-macOS.zip` archive and matching GitHub Release asset naming.

### Improved

- Sidebar helper, warning, and description copy now wraps cleanly instead of truncating in narrow widths.
- Output folder controls are cleaner, with inline source-folder reset and Finder reveal actions beside the default-folder picker.
- README release notes now describe the two tone-mapping engines and the current release archive naming.

### Fixed

- Tone-mapping backend selection now persists without resetting unrelated settings, and unsupported FFmpeg filter builds fall back to Apple with a clear inline explanation.
- The duplicate output heading/path presentation in the sidebar was removed.
- The external audio add button keeps a normal enabled appearance when the app is inactive.
- The rename apply action now matches the rest of the app’s subtler bordered button style.

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
