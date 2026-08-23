#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
fallback_sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
test_binary="$project_dir/.build/manual-tests/CapoteTests"
helper_binary="$project_dir/.build/manual-tests/CapoteSession"
test_uid="$(id -u)"
test_token="test-$$"
cancel_path="/private/tmp/fr.benjaminfarrudja.capote-$test_uid-$test_token.cancel"
result_path="/private/tmp/fr.benjaminfarrudja.capote-$test_uid-$test_token.result"
second_cancel_path="/private/tmp/fr.benjaminfarrudja.capote-$test_uid-$test_token-second.cancel"
second_result_path="/private/tmp/fr.benjaminfarrudja.capote-$test_uid-$test_token-second.result"
lock_test_pid=""

cleanup() {
    if [[ -n "$lock_test_pid" ]]; then
        kill -TERM "$lock_test_pid" 2>/dev/null || true
        wait "$lock_test_pid" 2>/dev/null || true
    fi
    rm -f "$cancel_path" "$result_path"
    rm -f "$second_cancel_path" "$second_result_path"
}

trap cleanup EXIT

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
    "$project_dir/Sources/CapoteRemoteCore/RemoteControlProtocol.swift" \
    "$project_dir/Sources/CapoteRemoteCore/RemoteControlCrypto.swift" \
    "$project_dir/Sources/CapoteRemoteCore/RemoteFrameCodec.swift" \
    "$project_dir/Sources/CapoteRemoteCore/PrivilegedRemoteProtocol.swift" \
    "$project_dir/Sources/Capote/AppUpdateCore.swift" \
    "$project_dir/Sources/Capote/LaunchAtLoginController.swift" \
    "$project_dir/Sources/Capote/PrivilegedRemoteClient.swift" \
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

: > "$result_path"
cancel_base64="$(printf %s "$cancel_path" | base64)"
result_base64="$(printf %s "$result_path" | base64)"

"$helper_binary" \
    --user-uid "$test_uid" \
    --cancel-base64 "$cancel_base64" \
    --result-base64 "$result_base64" \
    --mode duration \
    --seconds 5 \
    --simulate-thermal serious \
    --dry-run

if [[ "$(<"$result_path")" != "thermal-serious" ]]; then
    print -u2 "Échec : le helper n’a pas enregistré l’arrêt thermique simulé"
    exit 1
fi

print "Helper de session testé en mode thermique simulé"

: > "$result_path"
: > "$second_result_path"
second_cancel_base64="$(printf %s "$second_cancel_path" | base64)"
second_result_base64="$(printf %s "$second_result_path" | base64)"

"$helper_binary" \
    --user-uid "$test_uid" \
    --cancel-base64 "$cancel_base64" \
    --result-base64 "$result_base64" \
    --mode duration \
    --seconds 30 \
    --dry-run &
lock_test_pid=$!
sleep 1

if "$helper_binary" \
    --user-uid "$test_uid" \
    --cancel-base64 "$second_cancel_base64" \
    --result-base64 "$second_result_base64" \
    --mode duration \
    --seconds 1 \
    --dry-run; then
    print -u2 "Échec : deux helpers ont acquis le verrou de session"
    exit 1
fi

kill -TERM "$lock_test_pid"
wait "$lock_test_pid"
lock_test_pid=""

"$helper_binary" \
    --user-uid "$test_uid" \
    --cancel-base64 "$second_cancel_base64" \
    --result-base64 "$second_result_base64" \
    --mode duration \
    --seconds 5 \
    --simulate-thermal critical \
    --dry-run

if [[ "$(<"$second_result_path")" != "thermal-critical" ]]; then
    print -u2 "Échec : le verrou de session n’a pas été libéré"
    exit 1
fi

print "Exclusion des sessions simultanées testée en mode sec"
