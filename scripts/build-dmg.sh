#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
source_app="$project_dir/dist/Capote.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/packaging/Info.plist")"
dmg_path="$project_dir/dist/Capote-$version.dmg"
checksum_path="$dmg_path.sha256"
build_dir="$(mktemp -d /private/tmp/capote-dmg.XXXXXX)"
mount_dir=""
background="$project_dir/packaging/dmg/background.png"
settings="$project_dir/packaging/dmg/settings.py"
dmgbuild_python="$project_dir/.build/dmg-venv/bin/python"
documentation="$build_dir/Documentation"
mounted=false

cleanup() {
    if [[ "$mounted" == true && -n "$mount_dir" ]]; then
        hdiutil detach "$mount_dir" -quiet || true
    fi
    rm -rf "$build_dir"
}

trap cleanup EXIT

if [[ ! -d "$source_app" ]]; then
    print -u2 "Application absente : exécutez d’abord ./scripts/build-app.sh"
    exit 1
fi

if [[ ! -f "$background" || ! -f "$settings" ]]; then
    print -u2 "Ressources du DMG absentes dans packaging/dmg"
    exit 1
fi

if [[ ! -x "$dmgbuild_python" ]]; then
    print -u2 "Outils de packaging absents : exécutez d’abord ./scripts/prepare-packaging-tools.sh"
    exit 1
fi

codesign --verify --deep --strict "$source_app"

mkdir -p "$documentation"
cp "$project_dir/packaging/LISEZ-MOI.txt" "$documentation/LISEZ-MOI.txt"
cp "$project_dir/LICENSE.md" "$documentation/LICENSE.md"

rm -f "$dmg_path" "$checksum_path"
"$dmgbuild_python" -m dmgbuild \
    -s "$settings" \
    -D "app=$source_app" \
    -D "documentation=$documentation" \
    -D "background=$background" \
    "Capote" \
    "$dmg_path"

attach_output="$(hdiutil attach \
    -readonly \
    -nobrowse \
    "$dmg_path")"
mount_dir="$(print -r -- "$attach_output" | awk -F '\t' 'NF >= 3 && $NF ~ /^\// { path = $NF } END { print path }')"
[[ -n "$mount_dir" && -d "$mount_dir" ]]
mounted=true

codesign --verify --deep --strict "$mount_dir/Capote.app"
[[ -f "$mount_dir/.background.png" ]]
[[ -f "$mount_dir/Documentation/LISEZ-MOI.txt" ]]
[[ -f "$mount_dir/Documentation/LICENSE.md" ]]
[[ -L "$mount_dir/Applications" ]]
[[ "$(readlink "$mount_dir/Applications")" == "/Applications" ]]
[[ -f "$mount_dir/.DS_Store" ]]

hdiutil detach "$mount_dir" -quiet
mounted=false
mount_dir=""

dmg_digest="$(shasum -a 256 "$dmg_path" | awk '{print $1}')"
print "$dmg_digest  ${dmg_path:t}" > "$checksum_path"

print "Image disque créée : $dmg_path"
print "Somme de contrôle : $checksum_path"
