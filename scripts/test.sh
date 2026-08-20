#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
fallback_sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
test_binary="$project_dir/.build/manual-tests/CapoteTests"
helper_binary="$project_dir/.build/manual-tests/CapoteSession"

cd "$project_dir"

if [[ -n "${CAPOTE_SDKROOT:-}" ]]; then
    capote_sdk="$CAPOTE_SDKROOT"
elif [[ -d "$fallback_sdk" ]]; then
    capote_sdk="$fallback_sdk"
else
    capote_sdk="$(xcrun --sdk macosx --show-sdk-path)"
fi

mkdir -p "${test_binary:h}" "$project_dir/.build/clang-module-cache"

swiftc \
    -sdk "$capote_sdk" \
    -module-cache-path "$project_dir/.build/clang-module-cache" \
    -target arm64-apple-macosx14.0 \
    -swift-version 5 \
    -parse-as-library \
    "$project_dir/Sources/Capote/SleepControlController.swift" \
    "$project_dir/Tests/ManualTestRunner.swift" \
    -o "$test_binary"

"$test_binary"

swiftc \
    -sdk "$capote_sdk" \
    -module-cache-path "$project_dir/.build/clang-module-cache" \
    -target arm64-apple-macosx14.0 \
    -swift-version 5 \
    -parse-as-library \
    "$project_dir/Sources/CapoteSessionHelper/main.swift" \
    -o "$helper_binary"

"$helper_binary" \
    --cancel-base64 L3ByaXZhdGUvdG1wL2ZyLmJlbmphbWluZmFycnVkamEuY2Fwb3RlLXRlc3QuY2FuY2Vs \
    --mode duration \
    --seconds 0.1 \
    --dry-run

print "Helper de session testé"
