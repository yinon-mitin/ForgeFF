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
- Do not commit local release archives, DerivedData, xcresults, or other build output.

## Pull Requests

- Keep PRs focused and small when possible.
- Include a short test plan and screenshots for UI changes.
- Update `CHANGELOG.md` for user-facing changes.
- Keep `README.md` accurate when behavior, installation, or release flow changes.
- Ensure local build and tests pass before opening PR.

## Releases

- Keep `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, and the top changelog entry in sync.
- Run `./script/package_release.sh` to test the universal ad-hoc signed package locally.
- Push an annotated `vX.Y.Z` tag only after the matching commit is on `main`; the release workflow needs no Apple signing secrets.
- Ad-hoc builds are not Apple-notarized, so test the documented Gatekeeper first-launch path before publishing.
