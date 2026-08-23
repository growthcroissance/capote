#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
fallback_sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
build_dir="$(mktemp -d /private/tmp/capote-dmg-background.XXXXXX)"
output_path="${1:-$project_dir/packaging/dmg/background.png}"

trap 'rm -rf "$build_dir"' EXIT

if [[ -n "${CAPOTE_SDKROOT:-}" ]]; then
    capote_sdk="$CAPOTE_SDKROOT"
elif [[ -d "$fallback_sdk" ]]; then
    capote_sdk="$fallback_sdk"
else
    capote_sdk="$(xcrun --sdk macosx --show-sdk-path)"
fi

mkdir -p "$project_dir/.build/clang-module-cache"
swiftc \
    -sdk "$capote_sdk" \
    -module-cache-path "$project_dir/.build/clang-module-cache" \
    "$project_dir/scripts/render-dmg-background.swift" \
    -o "$build_dir/render-dmg-background"

"$build_dir/render-dmg-background" "$output_path"
