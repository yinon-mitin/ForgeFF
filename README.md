<p align="center">
  <img src="https://github.com/user-attachments/assets/69c44ff9-208e-450f-a06f-f080c6028ddb" width="33%" alt="ForgeFF icon">
</p>

<h1 align="center">ForgeFF</h1>
<p align="center">Simple and powerful video conversion for macOS.</p>

## Introduction

ForgeFF is a native macOS batch media converter built around practical presets, a reliable queue, and the option to drop into detailed FFmpeg controls only when they are actually needed.

It is designed for people who want FFmpeg power without living in the terminal: drag files in, pick a preset, and convert. Advanced users still get codec, container, quality, subtitle, audio, cleanup, and custom-command controls when the job needs them.

## Demo

https://github.com/user-attachments/assets/de36a472-2231-4c34-a976-35b46f20f5e6

## Sidebar Screenshots

<img height="335" alt="Preset settings" src="https://github.com/yinon-mitin/ForgeFF/blob/main/docs/screenshots/Settings-1.png"> <img height="335" alt="Video settings" src="https://github.com/yinon-mitin/ForgeFF/blob/main/docs/screenshots/Settings-2.png"> <img height="335" alt="Audio and subtitle settings" src="https://github.com/yinon-mitin/ForgeFF/blob/main/docs/screenshots/Settings-3.png">

<img height="335" alt="Output and cleanup settings" src="https://github.com/yinon-mitin/ForgeFF/blob/main/docs/screenshots/Settings-4.png"> <img height="335" alt="Advanced settings" src="https://github.com/yinon-mitin/ForgeFF/blob/main/docs/screenshots/Settings-5.png">

## Highlights

- Presets-first workflow for the common export paths: Telegram, Fast MP4, Efficient HEVC, VP9, AV1, and Editing ProRes.
- Live batch queue that accepts new files and folders while conversion is running, with start/pause/cancel/retry controls, per-job progress, and Dock progress.
- Clean default UI with compact presets and pinned Start/More Settings controls; detailed options scroll independently.
- Custom and user presets with consistent selection, customization, import, and export behavior.
- Multiple external audio tracks and multiple external subtitle files with ordered muxing support.
- Output folder controls for defaults, per-selection overrides, and folder drag-and-drop.
- HDR to SDR tone mapping with a selectable Apple VideoToolbox or FFmpeg backend when the Mac supports both paths.
- Preview thumbnails, Quick Look for completed outputs, and a dedicated right-side inspector for failure details.
- Native macOS presentation in dark mode with keyboard-reachable controls across the main workflow.

## Installation

ForgeFF requires:

- macOS 13 or newer
- FFmpeg and FFprobe available on the machine

ForgeFF does not bundle FFmpeg. The app will auto-detect common install locations on launch and will prompt for manual selection if it cannot find the binaries.

Install FFmpeg with Homebrew:

```bash
brew install ffmpeg
```

Download ForgeFF from GitHub Releases:

1. Download the latest `ForgeFF-X.Y.Z-macOS.zip` archive from the repository’s Releases page.
2. Unzip the archive and drag `ForgeFF.app` into `/Applications`.
3. Launch the app.
4. If Gatekeeper blocks first run, right-click the app, choose `Open`, and confirm.

## Usage

### Add media

- Drag files or folders into the queue.
- Use the toolbar `Add…` menu to import files or folders manually.
- Select one or more queue items to apply settings to a subset of the queue.

### Pick a preset

- Start with one of the primary preset cards in the sidebar.
- Use `Telegram` for reliable in-chat playback while keeping the source dimensions and frame rate. It exports MP4 with H.264 8-bit 4:2:0 video, AAC stereo audio, and fast-start metadata; the tradeoff is a larger file than HEVC.
- Use `Efficient HEVC` for the same source-resolution, FPS, quality, AAC stereo, and streaming-friendly settings with a smaller HEVC video.
- Use the VP9 or AV1 cards for modern MKV compression when the corresponding encoder is available in the detected FFmpeg build. Editing ProRes stays last because it is the specialized finishing workflow.
- Presets immediately update the underlying conversion configuration.
- If you adjust settings manually, ForgeFF keeps the preset visible and marks it as customized only while the effective settings actually differ.

### Open More Settings when needed

- `More Settings` expands the advanced panel inside the sidebar while its toggle and Start remain pinned at the bottom.
- The default collapsed state keeps the app approachable for non-technical users.
- Advanced controls cover format, codec, quality, encoder behavior, resolution, FPS, audio, subtitles, cleanup, rename tools, and custom FFmpeg overrides.
- When HDR to SDR is enabled, use the tone-mapping engine selector to choose Apple VideoToolbox or FFmpeg filters.

### Choose output behavior

- Set a default output folder for new exports.
- Override the output folder for the current selection only when needed.
- Drag a Finder folder directly onto the output controls if that is faster than opening the picker.

### Manage external media

- Add one or more external audio tracks when you want to replace source audio.
- Add one or more external subtitle files and set language codes per track.
- Track order in the sidebar is preserved for muxing.

### Run the queue

- Use `Start` to process the whole queue or the current selection.
- While conversion is running or paused, use the single `Add to Queue…` toolbar menu to append more files. Newly added media is analyzed in the background and then processed after the jobs already ahead of it.
- The compact summary above the queue shows active and waiting counts plus live FPS without duplicating the full footer.
- Pause, resume, cancel, retry failed jobs, or reveal completed outputs directly from the queue. `Details` opens failed and cancelled diagnostics in a separate right-side inspector without expanding the row.
- Use `Clear Finished` for completed, failed, and cancelled results; its menu also exposes a confirmed full-queue clear.
- Completed rows show actual conversion time and the output size as a percentage of the original input size.
- Output-size estimates start from the selected codec and quality settings, then become more accurate during conversion by using the bytes FFmpeg has actually written and the encoded duration.
- Running queue rows show FFmpeg's current processing speed in frames per second.
- `Efficient HEVC` keeps the Telegram preset's source resolution, FPS, quality, AAC stereo, and streaming-friendly MP4 settings while using HEVC for a smaller file.
- Press `Command-/` to open About ForgeFF, or `Command-,` to toggle More Settings.
- Running jobs keep the settings snapshot they started with, even if you keep editing presets or options while they are processing.
- FFmpeg and FFprobe run outside the UI path, and progress updates are rate-limited so the app stays responsive during demanding encodes. ForgeFF intentionally runs one conversion job at a time to avoid multiplying CPU, GPU, memory, and disk pressure.

## Updates

ForgeFF’s public builds are currently distributed through GitHub Releases.

- There is no in-app auto-update flow in the current public build.
- To update, download the latest release archive and replace the existing app bundle.
- Checksums are published alongside release archives for verification.

## Development

### Build locally

For the standard build-and-launch loop, use:

```bash
./script/build_and_run.sh
```

Pass `--verify` for a launch smoke test, `--debug` for LLDB, `--logs` for the live app log, or `--telemetry` for ForgeFF subsystem events.

The equivalent direct build command is:

```bash
xcodebuild \
  -project ForgeFF.xcodeproj \
  -scheme ForgeFF \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Run the built app:

```bash
open ".build/DerivedData/Build/Products/Debug/ForgeFF.app"
```

### Test locally

```bash
xcodebuild \
  -project ForgeFF.xcodeproj \
  -scheme ForgeFF \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

### Release packaging

The repository includes `.github/workflows/release.yml` for tagged macOS releases. The intended release flow is:

1. Build a Release archive.
2. Sign it with a Developer ID Application certificate.
3. Notarize the archive with Apple.
4. Upload `ForgeFF-X.Y.Z-macOS.zip` and its checksum to GitHub Releases.

Required CI secrets are documented in the workflow file. Local release signing and notarization require Apple credentials and certificates that are not stored in this repository.
For local smoke-test releases without signing, build `Release` with `CODE_SIGNING_ALLOWED=NO` and package the resulting `ForgeFF.app` into `release/ForgeFF-X.Y.Z-macOS.zip`.

Configure these GitHub Actions repository secrets before pushing a release tag:

- `APPLE_TEAM_ID`
- `BUILD_KEYCHAIN_PASSWORD`
- `APPLE_DEVELOPER_ID_APPLICATION_P12_BASE64`
- `APPLE_DEVELOPER_ID_APPLICATION_P12_PASSWORD`
- `APPLE_NOTARY_API_KEY_ID`
- `APPLE_NOTARY_API_ISSUER_ID`
- `APPLE_NOTARY_API_PRIVATE_KEY_P8_BASE64`

To publish a release, ensure `MARKETING_VERSION` matches the intended tag, push the main branch, then push an annotated tag such as `v2.6.1`. The workflow runs the test suite, signs and notarizes the app, staples the notarization ticket, and creates the GitHub Release with its ZIP and SHA-256 file.

## Repository Notes

- Canonical icon source: `forgeFF-icon-v2.png`
- Generated app icons: `ForgeFF/Assets.xcassets/AppIcon.appiconset/`
- Regenerate icon renditions with:

```bash
./scripts/generate_appiconset.sh
```

## License

ForgeFF is released under the MIT License. See [LICENSE](LICENSE).

### FFmpeg licensing

ForgeFF invokes user-installed FFmpeg and FFprobe. FFmpeg licensing remains separate from ForgeFF itself, so anyone redistributing FFmpeg binaries is responsible for complying with FFmpeg’s licensing terms.
