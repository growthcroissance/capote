#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
output_app_dir="$project_dir/dist/Capote.app"
archive_path="$project_dir/dist/Capote-0.5.0.zip"
build_dir="$(mktemp -d /private/tmp/capote-build.XXXXXX)"
app_dir="$build_dir/Capote.app"
contents_dir="$app_dir/Contents"
fallback_sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"

trap 'rm -rf "$build_dir"' EXIT

cd "$project_dir"

if [[ -n "${CAPOTE_SDKROOT:-}" ]]; then
    capote_sdk="$CAPOTE_SDKROOT"
elif [[ -d "$fallback_sdk" ]]; then
    capote_sdk="$fallback_sdk"
else
    capote_sdk="$(xcrun --sdk macosx --show-sdk-path)"
fi

mkdir -p "$contents_dir/MacOS"
mkdir -p "$contents_dir/Helpers"
mkdir -p "$project_dir/.build/clang-module-cache"

swiftc \
    -sdk "$capote_sdk" \
    -module-cache-path "$project_dir/.build/clang-module-cache" \
    -target arm64-apple-macosx14.0 \
    -swift-version 5 \
    -parse-as-library \
    -O \
    "$project_dir/Sources/Capote/CapoteApp.swift" \
    "$project_dir/Sources/Capote/SleepControlController.swift" \
    -o "$contents_dir/MacOS/Capote"

swiftc \
    -sdk "$capote_sdk" \
    -module-cache-path "$project_dir/.build/clang-module-cache" \
    -target arm64-apple-macosx14.0 \
    -swift-version 5 \
    -parse-as-library \
    -O \
    "$project_dir/Sources/CapoteSessionHelper/main.swift" \
    -o "$contents_dir/Helpers/CapoteSession"

cp "$project_dir/packaging/Info.plist" "$contents_dir/Info.plist"

xattr -cr "$app_dir"
codesign --force --sign - "$contents_dir/Helpers/CapoteSession"
xattr -cr "$app_dir"
codesign --force --sign - "$app_dir"
xattr -cr "$app_dir"
codesign --verify --deep --strict "$app_dir"

mkdir -p "$project_dir/dist"
ditto -c -k --keepParent "$app_dir" "$archive_path"

mkdir -p "$build_dir/archive-check"
ditto -x -k "$archive_path" "$build_dir/archive-check"
codesign --verify --deep --strict "$build_dir/archive-check/Capote.app"

if [[ -e "$output_app_dir" ]]; then
    mv "$output_app_dir" "$build_dir/previous-Capote.app"
fi

mv "$app_dir" "$output_app_dir"
xattr -cr "$output_app_dir"
codesign --verify --deep --strict "$output_app_dir"

print "Application créée : $output_app_dir"
print "Archive de mise à jour : $archive_path"
