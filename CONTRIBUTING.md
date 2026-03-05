# Contributing

Thanks for contributing to ForgeFF.

## Setup

1. Install Xcode 15+.
2. Install FFmpeg: `brew install ffmpeg`.
3. Open `ForgeFF.xcodeproj`.
4. Build and run `ForgeFF` on macOS.

## Development Rules

- Keep target compatibility at macOS 13+.
- Keep the UI presets-first and avoid command-line input features.
- Keep FFmpeg behavior deterministic and covered by unit tests.
- Do not bundle FFmpeg binaries by default.

## Pull Requests

- Keep PRs focused and small when possible.
- Include a short test plan and screenshots for UI changes.
- Update `CHANGELOG.md` for user-facing changes.
- Ensure local build and tests pass before opening PR.
