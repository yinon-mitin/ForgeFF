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

## Terminal file handoff

The `script/forgeff` helper supports both GUI handoff and a deterministic headless conversion path:

```bash
./script/forgeff add ~/Movies/example.mkv
./script/forgeff add ~/Movies/*.mp4
./script/forgeff convert ~/Movies/example.mkv --preset telegram --output-dir ./out
./script/forgeff convert ~/Movies/example.mkv --audio-codec mp3 --container mkv
```

The CLI conversion path uses the machine's FFmpeg executable and intentionally supports a small explicit option set. See [CLI documentation](cli.md) for the complete argument index and limitations. It does not currently expose every GUI setting or the GUI's Apple `avconvert` HDR pipeline; HDR-to-SDR should be performed through the main app until the conversion engine is shared between both interfaces.

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

## Continuous integration and release

Pushes to `main` and pull requests are validated by `.github/workflows/macos-ci.yml`. This workflow does not modify versions or publish releases.

Releases are published explicitly by `.github/workflows/release.yml` for a version tag:

```bash
git tag -a v2.6.8 -m "ForgeFF 2.6.8"
git push origin v2.6.8
```

The tag must match `MARKETING_VERSION` in the Xcode project. This prevents ordinary commits to `main` from creating unexpected releases.

## Pull requests

Before opening a pull request, run the test command above plus:

```bash
bash -n script/*.sh scripts/*.sh
xmllint --noout docs/forgeff-banner.svg
git diff --check
```

For contribution guidelines, see [CONTRIBUTING.md](../CONTRIBUTING.md).
