#!/bin/bash
# A deliberate mutation verifies the existing regression test, on a runner only.
set -euo pipefail
test "${GITHUB_ACTIONS:-}" = true
test "${RUNNER_OS:-}" = macOS
preferences=MacReceiver/ReceiverPreferences.swift
backup="$RUNNER_TEMP/ReceiverPreferences.original.swift"
log="$RUNNER_TEMP/receiver-preferences-mutation.log"
cp "$preferences" "$backup"
trap 'cp "$backup" "$preferences"' EXIT
python3 - <<'PY'
from pathlib import Path
path = Path("MacReceiver/ReceiverPreferences.swift")
source = path.read_text()
condition = "receiverName.isEmpty ? fallbackName : receiverName"
if source.count(condition) != 1:
    raise RuntimeError("Expected exactly one empty-name fallback condition")
path.write_text(source.replace(condition, "!" + condition))
PY
set +e
xcodebuild test \
  -project OpenSidecar.xcodeproj -scheme OpenSidecarMac \
  -destination 'platform=macOS' \
  -only-testing:OpenSidecarMacTests/ReceiverPreferencesTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  2>&1 | tee "$log"
result=${PIPESTATUS[0]}
set -e
# A build/infrastructure error is not proof that the test detects a regression.
test "$result" -ne 0
grep -E 'Test Case.*testEmptyNameSurvivesRelaunchAndUsesFallbackForService.*failed' "$log"
printf 'Empty-name regression test detected the inverted fallback; original source restored on exit.\n'
