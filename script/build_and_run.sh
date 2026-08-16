#!/usr/bin/env bash

set -euo pipefail

mode="${1:-run}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data="$repo_root/.build/DerivedData"
app_bundle="$derived_data/Build/Products/Debug/ForgeFF.app"
app_binary="$app_bundle/Contents/MacOS/ForgeFF"

stop_running_app() {
    /usr/bin/pkill -x ForgeFF >/dev/null 2>&1 || true
}

build_app() {
    /usr/bin/xcodebuild \
        -project "$repo_root/ForgeFF.xcodeproj" \
        -scheme ForgeFF \
        -destination 'platform=macOS' \
        -derivedDataPath "$derived_data" \
        CODE_SIGNING_ALLOWED=NO \
        build
}

launch_app() {
    /usr/bin/open -n "$app_bundle"
}

case "$mode" in
    run)
        stop_running_app
        build_app
        launch_app
        ;;
    --verify|verify)
        stop_running_app
        build_app
        launch_app
        /bin/sleep 2
        /usr/bin/pgrep -x ForgeFF >/dev/null
        ;;
    --debug|debug)
        stop_running_app
        build_app
        /usr/bin/lldb -- "$app_binary"
        ;;
    --logs|logs)
        stop_running_app
        build_app
        launch_app
        /usr/bin/log stream --info --style compact --predicate 'process == "ForgeFF"'
        ;;
    --telemetry|telemetry)
        stop_running_app
        build_app
        launch_app
        /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.yinonmitin.ForgeFF"'
        ;;
    *)
        echo "Usage: $0 [run|--verify|--debug|--logs|--telemetry]" >&2
        exit 64
        ;;
esac
