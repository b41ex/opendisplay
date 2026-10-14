#!/bin/bash
# Run exclusively on a GitHub macos-15-intel runner, never on the test iMac.
set -euo pipefail

test "${GITHUB_ACTIONS:-}" = true
test "${RUNNER_OS:-}" = macOS
evidence="$PWD/build/receiver-evidence"
mkdir -p "$evidence"
# Capture setup failures as well as compiler output in the downloadable logs.
exec > >(tee "$evidence/build.log") 2>&1
trap 'status=$?; printf "%s\n" "$status" > "$evidence/exit-status.txt"' EXIT

test "$(uname -m)" = x86_64
test "$DEVELOPER_DIR" = /Applications/Xcode_16.4.app/Contents/Developer
xcodebuild -version | tee "$evidence/xcode.txt"
grep -qx 'Xcode 16.4' "$evidence/xcode.txt"
xcrun swift --version
xcrun --sdk macosx --show-sdk-version
sw_vers
xcodegen --version
xcodegen generate

args=(
  -project OpenSidecar.xcodeproj -scheme OpenSidecarMacReceiver
  -configuration "$CONFIGURATION" -destination 'generic/platform=macOS'
  -derivedDataPath build/receiver "ARCHS=${ARCHITECTURES:-x86_64}" ONLY_ACTIVE_ARCH=NO
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 'CODE_SIGN_IDENTITY='
)
if [[ -n "${DIAGNOSTIC_TARGET:-}" ]]; then
  args+=("MACOSX_DEPLOYMENT_TARGET=$DIAGNOSTIC_TARGET")
fi
printf 'commit=%s\nrun=%s/%s/actions/runs/%s\nconfiguration=%s\ndiagnostic_override=%s\nsigning=disabled\n' \
  "$GITHUB_SHA" "$GITHUB_SERVER_URL" "$GITHUB_REPOSITORY" "$GITHUB_RUN_ID" \
  "$CONFIGURATION" "${DIAGNOSTIC_TARGET:-none}" > "$evidence/manifest.txt"
printf 'runner_image=%s\nrunner_image_version=%s\n' \
  "${ImageOS:-unknown}" "${ImageVersion:-unknown}" >> "$evidence/manifest.txt"
xcodebuild -resolvePackageDependencies "${args[@]}"
resolved=OpenSidecar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
cp "$resolved" "$evidence/Package.resolved"
# Assert the actual resolved dependency, not just the declared project pin.
jq -e '[.pins[] | select(.identity == "sparkle") | .state.version] == ["2.9.6"]' "$resolved"
xcodebuild -showBuildSettings "${args[@]}" > "$evidence/build-settings.txt"
xcodebuild build "${args[@]}"

if [[ "$CONFIGURATION" = Debug ]]; then
  product='OpenDisplay Receiver Dev'
  bundle_id=com.peetzweg.opensidecar.mac.receiver.debug
else
  product='OpenDisplay Receiver'
  bundle_id=com.peetzweg.opensidecar.mac.receiver
fi
app="$PWD/build/receiver/Build/Products/$CONFIGURATION/$product.app"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" = "$bundle_id"
printf 'bundle_id=%s\nminimum_os=%s\n' "$bundle_id" \
  "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist")" >> "$evidence/manifest.txt"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist")" = 10.15.7
python3 scripts/ci/verify-receiver-artifact.py bundle "$app" "$evidence/bundle-manifest.json"
# Record every embedded Mach-O (Sparkle helpers and Swift runtime included).
while IFS= read -r -d '' binary; do
  if file -b "$binary" | grep -q 'Mach-O'; then
    printf '\n%s\n' "${binary#"$app/"}"
    lipo -archs "$binary"
    xcrun vtool -show-build "$binary"
  fi
done < <(find "$app" -type f -print0) > "$evidence/macho-manifest.txt"

# ZIP the app on macOS before artifact upload to preserve modes and symlinks.
# https://docs.github.com/en/actions/tutorials/store-and-share-data
zip_path="$evidence/receiver-${ARCHITECTURE_LABEL:-x86_64}-$CONFIGURATION.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip_path"
(cd "$evidence" && shasum -a 256 "$(basename "$zip_path")" > SHA256SUMS)
python3 scripts/ci/verify-receiver-artifact.py zip "$zip_path" "$evidence/bundle-manifest.json"
