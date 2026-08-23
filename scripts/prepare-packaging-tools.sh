#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
venv_dir="$project_dir/.build/dmg-venv"
requirements="$project_dir/packaging/dmg/requirements.txt"
macos26_patch="$project_dir/packaging/dmg/dmgbuild-macos26.patch"

python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else "Python 3.9 ou ultérieur est requis pour construire le DMG")'

if [[ ! -x "$venv_dir/bin/python" ]]; then
    python3 -m venv "$venv_dir"
fi

"$venv_dir/bin/python" -m pip install \
    --disable-pip-version-check \
    --require-hashes \
    --requirement "$requirements"

site_packages="$("$venv_dir/bin/python" -c 'import site; print(site.getsitepackages()[0])')"
dmgbuild_core="$site_packages/dmgbuild/core.py"
if grep -q 'pBBk' "$dmgbuild_core"; then
    patch -p1 -d "$site_packages" < "$macos26_patch"
fi

"$venv_dir/bin/python" -c 'import dmgbuild, ds_store, mac_alias'
if grep -Eq 'Bookmark|pBBk' "$dmgbuild_core"; then
    print -u2 "Le correctif dmgbuild pour macOS 26 n’a pas été appliqué"
    exit 1
fi
print "Outils de packaging prêts : $venv_dir"
