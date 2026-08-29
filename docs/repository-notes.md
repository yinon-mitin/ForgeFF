# Repository Notes

This document contains repository-maintainer notes that are intentionally kept out of the public-facing README.

## Visual assets

- Canonical icon source: `forgeFF-icon-v2.png`
- Generated app icons: `ForgeFF/Assets.xcassets/AppIcon.appiconset/`
- Local README banner: `docs/forgeff-banner.svg`

Regenerate icon renditions with:

```bash
./scripts/generate_appiconset.sh
```

## Release model

Every push to `main` is validated by macOS CI. The automatic release workflow then creates the next patch version, commits the version change, builds a universal macOS app, and publishes a GitHub Release containing:

- `ForgeFF-X.Y.Z-macOS.zip`
- `ForgeFF-X.Y.Z-macOS.zip.sha256`

The in-app updater consumes only these official stable Releases.

For the manual fallback flow, see [Development](development.md#manual-release-fallback).

## Security boundary

ForgeFF is intentionally non-sandboxed because it executes the user's external Homebrew FFmpeg/FFprobe binaries and their dynamic codec libraries. Release artifacts use ad-hoc signing in CI; this verifies bundle integrity but is not developer identity or Apple notarization.
