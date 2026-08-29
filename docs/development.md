# Development

## Prerequisites

- macOS 13 or newer
- Xcode with the macOS SDK
- Homebrew FFmpeg and FFprobe for local runtime smoke tests

## Build and run

Use the standard helper:

```bash
./script/build_and_run.sh
```

Useful flags:

- `--verify` — launch smoke test
- `--debug` — launch under LLDB
- `--logs` — stream the ForgeFF app log
- `--telemetry` — stream ForgeFF subsystem events

The helper applies and verifies an ad-hoc signature after each local build.

## Test

```bash
xcodebuild \
  -project ForgeFF.xcodeproj \
  -scheme ForgeFF \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## Package locally

```bash
./script/package_release.sh
```

The archive and checksum are written to the ignored `release/` directory.

## Automatic release

Pushes to `main` are handled by `.github/workflows/auto-release.yml`:

1. macOS CI validates scripts, assets, builds, and tests.
2. The workflow selects the next patch version above the latest GitHub Release.
3. It commits the version and changelog entry back to `main`.
4. It builds and ad-hoc signs an arm64 + x86_64 app.
5. It publishes the ZIP and SHA-256 checksum as a GitHub Release.

Use `[skip release]` in a commit subject when a main-branch change should not create a release. The normal CI workflow still runs.

## Manual release fallback

The manual workflow in `.github/workflows/release.yml` remains available for an explicitly versioned tag:

```bash
git tag -a v2.6.8 -m "ForgeFF 2.6.8"
git push origin v2.6.8
```

The tag must match `MARKETING_VERSION` in the Xcode project.

## Pull requests

Before opening a pull request, run the test command above plus:

```bash
bash -n script/*.sh scripts/*.sh
xmllint --noout docs/forgeff-banner.svg
git diff --check
```

For contribution guidelines, see [CONTRIBUTING.md](../CONTRIBUTING.md).
