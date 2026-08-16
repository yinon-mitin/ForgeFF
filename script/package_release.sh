#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data="$repo_root/.build/ReleaseDerivedData"
release_dir="$repo_root/release"

project_version="$({
    /usr/bin/xcodebuild \
        -project "$repo_root/ForgeFF.xcodeproj" \
        -scheme ForgeFF \
        -configuration Release \
        -showBuildSettings
} | /usr/bin/awk -F ' = ' '/MARKETING_VERSION =/ { print $2; exit }')"

version="${1:-$project_version}"
if [[ "$version" != "$project_version" ]]; then
    echo "Requested version $version does not match MARKETING_VERSION $project_version." >&2
    exit 64
fi

app_bundle="$derived_data/Build/Products/Release/ForgeFF.app"
archive="$release_dir/ForgeFF-${version}-macOS.zip"
checksum="$archive.sha256"

/usr/bin/xcodebuild \
    -project "$repo_root/ForgeFF.xcodeproj" \
    -scheme ForgeFF \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$derived_data" \
    ARCHS='arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY='' \
    build

/usr/bin/codesign \
    --force \
    --deep \
    --sign - \
    --timestamp=none \
    --options runtime \
    --entitlements "$repo_root/ForgeFF/ForgeFF.entitlements" \
    "$app_bundle"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_bundle"

/bin/mkdir -p "$release_dir"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$archive"
(
    cd "$release_dir"
    /usr/bin/shasum -a 256 "$(/usr/bin/basename "$archive")" > "$(/usr/bin/basename "$checksum")"
)

echo "Created $archive"
echo "Created $checksum"
