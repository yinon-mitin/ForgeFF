# ForgeFF

ForgeFF is a native macOS 13+ video converter built with SwiftUI and powered by FFmpeg/FFprobe. It is a presets-first desktop app for batch conversion, designed to stay beginner-friendly while still exposing practical controls for quality, codec, subtitles, cleanup, and HDR to SDR conversion.

ForgeFF does not bundle FFmpeg by default. Users install FFmpeg separately and the app auto-detects binaries at startup, with an Advanced override when needed.

## Key Features

- Native macOS app (SwiftUI) with drag-and-drop batch queue.
- Preset-first workflow for H.264, HEVC, VP9, AV1, and ProRes.
- FFprobe metadata analysis with codec/resolution/HDR information.
- Reliable sequential queue with start/pause/cancel/retry and per-job progress.
- Subtitle handling: keep, remove, or add external subtitle file.
- Cleanup tools: remove metadata and remove chapters.
- Optional HDR -> SDR tone mapping.
- Output naming templates and safe overwrite behavior.

## Requirements

- macOS 13 or newer.
- Xcode 15+ for local development.
- FFmpeg and FFprobe installed on the machine.

Install FFmpeg with Homebrew:

```bash
brew install ffmpeg
```

## Install ForgeFF (From GitHub Releases)

1. Download `ForgeFF-macos-vX.Y.Z.zip` from the latest Release.
2. Unzip and drag `ForgeFF.app` into `/Applications`.
3. Launch the app.
4. If Gatekeeper blocks first run, right click the app and choose `Open`, then confirm `Open`.

## FFmpeg Path Setup

- On launch, ForgeFF auto-detects common FFmpeg/FFprobe paths (`/opt/homebrew/bin`, `/usr/local/bin`, etc.).
- If missing, an onboarding modal prompts installation help or manual selection.
- Manual overrides are available in the sidebar `Advanced` section:
  - detected path display
  - `Change...`
  - `Reset to Auto`

## Known Limitations

- AV1/VP9 availability depends on your FFmpeg build (`libsvtav1`, `libaom-av1`, `libvpx-vp9` encoders).
- External subtitle muxing support varies by container and subtitle format.
  - MKV has the broadest compatibility.
  - MP4/MOV may require specific subtitle formats (typically `srt`/`mov_text` paths).
- Notarization is not included in this repository’s default release process.

## Troubleshooting

- **FFmpeg not found**: install via `brew install ffmpeg`, then relaunch ForgeFF or use `Advanced > Change...`.
- **Permissions errors**: select files/folders through app dialogs so macOS grants access.
- **Output not overwritten**: ensure `Allow overwrite` is enabled; otherwise ForgeFF uses safe no-overwrite behavior.
- **Codec option disabled**: your FFmpeg build likely lacks that encoder; verify with `ffmpeg -encoders`.

## Build From Source

```bash
xcodebuild \
  -project ForgeFF.xcodeproj \
  -scheme ForgeFF \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Run the built app:

```bash
open ".build/DerivedData/Build/Products/Debug/ForgeFF.app"
```

## Release Artifact (Local)

```bash
xcodebuild \
  -project ForgeFF.xcodeproj \
  -scheme ForgeFF \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  clean build

cd .build/DerivedData/Build/Products/Release
ditto -c -k --sequesterRsrc --keepParent ForgeFF.app ForgeFF-macos-v1.0.0.zip
shasum -a 256 ForgeFF-macos-v1.0.0.zip > ForgeFF-macos-v1.0.0.zip.sha256
```

## App Icon Source

- Canonical icon source: `./app-icon.png` (1024x1024).
- Generated icon assets: `ForgeFF/Assets.xcassets/AppIcon.appiconset/`.
- Regenerate icon renditions:

```bash
./scripts/generate_appiconset.sh
```

## License

This project is licensed under the MIT License. See `LICENSE`.

### FFmpeg Licensing Note

ForgeFF invokes user-installed FFmpeg/FFprobe and does not redistribute FFmpeg binaries by default. FFmpeg licensing (LGPL/GPL and codec-specific implications) is separate; users and distributors are responsible for complying with FFmpeg’s terms when distributing binaries.
