<p align="center" style="text-align: center">
  <img src="https://github.com/user-attachments/assets/69c44ff9-208e-450f-a06f-f080c6028ddb" width="33%"><br/>
</p>

<h1 align="center">ForgeFF</h1>
<p align="center">
  Simple and powerful tool for converting video files.

## Introduction

ForgeFF is a native macOS batch media converter built around practical presets, a reliable queue, and the option to drop into detailed FFmpeg controls only when they are actually needed.

It is designed for people who want FFmpeg power without living in the terminal: drag files in, pick a preset, and convert. Advanced users still get codec, container, quality, subtitle, audio, cleanup, and custom-command controls when the job needs them.

## Demo

https://github.com/user-attachments/assets/de36a472-2231-4c34-a976-35b46f20f5e6

## Side-Bar Screenshots

<img height="335" alt="Settings-Presets" src="https://github.com/yinon-mitin/ForgeFF/blob/c89613d5d0e4f6d97e6b4e24b1817591e68e1421/docs/screenshots/Settings-1.png" /> <img height="335" alt="Settings-Video" src="https://github.com/yinon-mitin/ForgeFF/blob/c89613d5d0e4f6d97e6b4e24b1817591e68e1421/docs/screenshots/Settings-2.png" /> <img height="335" alt="Settings-Audio-and-Subtitles" src="https://github.com/yinon-mitin/ForgeFF/blob/c89613d5d0e4f6d97e6b4e24b1817591e68e1421/docs/screenshots/Settings-3.png" />

<img height="335" alt="Settings-Output-and-Cleanup" src="https://github.com/yinon-mitin/ForgeFF/blob/c89613d5d0e4f6d97e6b4e24b1817591e68e1421/docs/screenshots/Settings-4.png" /> <img height="335" alt="Settings-Advanced" src="https://github.com/yinon-mitin/ForgeFF/blob/c89613d5d0e4f6d97e6b4e24b1817591e68e1421/docs/screenshots/Settings-5.png" />


## Highlights

- Presets-first workflow for the common export paths: Fast MP4, Efficient HEVC, Editing ProRes, and compact web-share output.
- Batch queue with drag-and-drop import, start/pause/cancel/retry controls, per-job progress, and Dock progress.
- Clean default UI with `More Settings` for container, codec, quality, resolution, FPS, audio, subtitles, cleanup, rename tools, and advanced overrides.
- Custom and user presets with consistent selection, customization, import, and export behavior.
- Multiple external audio tracks and multiple external subtitle files with ordered muxing support.
- Output folder controls for defaults, per-selection overrides, and folder drag-and-drop.
- Preview thumbnails, Quick Look for completed outputs, and clearer queue failure details.
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

1. Download the latest `ForgeFF-macos-vX.Y.Z.zip` archive from the repository’s Releases page.
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
- Presets immediately update the underlying conversion configuration.
- If you adjust settings manually, ForgeFF keeps the preset visible and marks it as customized only while the effective settings actually differ.

### Open More Settings when needed

- `More Settings` expands the advanced panel inside the sidebar.
- The default collapsed state keeps the app approachable for non-technical users.
- Advanced controls cover format, codec, quality, encoder behavior, resolution, FPS, audio, subtitles, cleanup, rename tools, and custom FFmpeg overrides.

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
- Pause, resume, cancel, retry failed jobs, reveal completed outputs, or inspect failure details directly from the queue.
- Running jobs keep the settings snapshot they started with, even if you keep editing presets or options while they are processing.

## Updates

ForgeFF’s public builds are currently distributed through GitHub Releases.

- There is no in-app auto-update flow in the current public build.
- To update, download the latest release archive and replace the existing app bundle.
- Checksums are published alongside release archives for verification.

## Development

### Build locally

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
4. Upload `ForgeFF-macos-vX.Y.Z.zip` and its checksum to GitHub Releases.

Required CI secrets are documented in the workflow file. Local release signing and notarization require Apple credentials and certificates that are not stored in this repository.

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
