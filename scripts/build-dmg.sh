#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
source_app="$project_dir/dist/Capote.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/packaging/Info.plist")"
dmg_path="$project_dir/dist/Capote-$version.dmg"
checksum_path="$dmg_path.sha256"
build_dir="$(mktemp -d /private/tmp/capote-dmg.XXXXXX)"
volume_dir="$build_dir/volume"
mount_dir="$build_dir/mount"
mounted=false

cleanup() {
    if [[ "$mounted" == true ]]; then
        hdiutil detach "$mount_dir" -quiet || true
    fi
    rm -rf "$build_dir"
}

trap cleanup EXIT

if [[ ! -d "$source_app" ]]; then
    print -u2 "Application absente : exécutez d’abord ./scripts/build-app.sh"
    exit 1
fi

codesign --verify --deep --strict "$source_app"

mkdir -p "$volume_dir" "$mount_dir"
cp -R "$source_app" "$volume_dir/Capote.app"
cp "$project_dir/packaging/LISEZ-MOI.txt" "$volume_dir/LISEZ-MOI.txt"
cp "$project_dir/LICENSE.md" "$volume_dir/LICENSE.md"
ln -s /Applications "$volume_dir/Applications"

rm -f "$dmg_path" "$checksum_path"
hdiutil create \
    -volname "Capote" \
    -srcfolder "$volume_dir" \
    -format UDZO \
    -ov \
    "$dmg_path"

hdiutil attach \
    -readonly \
    -nobrowse \
    -mountpoint "$mount_dir" \
    "$dmg_path" \
    -quiet
mounted=true

codesign --verify --deep --strict "$mount_dir/Capote.app"
[[ -f "$mount_dir/LISEZ-MOI.txt" ]]
[[ -f "$mount_dir/LICENSE.md" ]]
[[ -L "$mount_dir/Applications" ]]
[[ "$(readlink "$mount_dir/Applications")" == "/Applications" ]]

hdiutil detach "$mount_dir" -quiet
mounted=false

dmg_digest="$(shasum -a 256 "$dmg_path" | awk '{print $1}')"
print "$dmg_digest  ${dmg_path:t}" > "$checksum_path"

print "Image disque créée : $dmg_path"
print "Somme de contrôle : $checksum_path"
