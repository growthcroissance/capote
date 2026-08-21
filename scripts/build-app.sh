#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
output_app_dir="$project_dir/dist/Capote.app"
build_dir="$(mktemp -d /private/tmp/capote-build.XXXXXX)"
app_dir="$build_dir/Capote.app"
contents_dir="$app_dir/Contents"
fallback_sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/packaging/Info.plist")"
archive_name="Capote-$version"
archive_path="$project_dir/dist/$archive_name.zip"
checksum_path="$archive_path.sha256"

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

for capote_arch in arm64 x86_64; do
    swiftc \
        -sdk "$capote_sdk" \
        -module-cache-path "$project_dir/.build/clang-module-cache" \
        -target "$capote_arch-apple-macosx14.0" \
        -swift-version 5 \
        -parse-as-library \
        -O \
        "$project_dir/Sources/Capote/AppUpdateCore.swift" \
        "$project_dir/Sources/Capote/AppUpdater.swift" \
        "$project_dir/Sources/Capote/CapoteApp.swift" \
        "$project_dir/Sources/Capote/SleepControlController.swift" \
        -o "$build_dir/Capote-$capote_arch"

    swiftc \
        -sdk "$capote_sdk" \
        -module-cache-path "$project_dir/.build/clang-module-cache" \
        -target "$capote_arch-apple-macosx14.0" \
        -swift-version 5 \
        -parse-as-library \
        -O \
        "$project_dir/Sources/CapoteSessionHelper/main.swift" \
        -o "$build_dir/CapoteSession-$capote_arch"
done

lipo -create "$build_dir/Capote-arm64" "$build_dir/Capote-x86_64" -output "$contents_dir/MacOS/Capote"
lipo \
    -create \
    "$build_dir/CapoteSession-arm64" \
    "$build_dir/CapoteSession-x86_64" \
    -output "$contents_dir/Helpers/CapoteSession"

cp "$project_dir/packaging/Info.plist" "$contents_dir/Info.plist"

xattr -cr "$app_dir"
codesign --force --sign - "$contents_dir/Helpers/CapoteSession"
xattr -cr "$app_dir"
codesign --force --sign - "$app_dir"
xattr -cr "$app_dir"
codesign --verify --deep --strict "$app_dir"

mkdir -p "$project_dir/dist"
package_dir="$build_dir/$archive_name"
mkdir -p "$package_dir"
cp -R "$app_dir" "$package_dir/Capote.app"
cp "$project_dir/packaging/LISEZ-MOI.txt" "$package_dir/LISEZ-MOI.txt"
cp "$project_dir/LICENSE.md" "$package_dir/LICENSE.md"
ditto \
    -c \
    -k \
    --norsrc \
    --noextattr \
    --noqtn \
    --noacl \
    --keepParent \
    "$package_dir" \
    "$archive_path"
archive_digest="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
print "$archive_digest  ${archive_path:t}" > "$checksum_path"

mkdir -p "$build_dir/archive-check"
ditto -x -k "$archive_path" "$build_dir/archive-check"
codesign --verify --deep --strict "$build_dir/archive-check/$archive_name/Capote.app"

if [[ -e "$output_app_dir" ]]; then
    mv "$output_app_dir" "$build_dir/previous-Capote.app"
fi

mv "$app_dir" "$output_app_dir"
xattr -cr "$output_app_dir"
codesign --verify --deep --strict "$output_app_dir"

print "Application créée : $output_app_dir"
print "Archive de partage : $archive_path"
print "Somme de contrôle : $checksum_path"
