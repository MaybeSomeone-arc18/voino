#!/bin/sh
# Web build with test-seam separation.
# Production (default): flutter release build, then strip the test-only seams
# from the artifact so no injected global can activate them.
# Local testing: VOINO_KEEP_TEST_SEAMS=1 keeps the seams in build/web; that
# output is a local test artifact and must never be released.
set -e
cd "$(dirname "$0")/.."
flutter build web --release "$@"
if [ "$VOINO_KEEP_TEST_SEAMS" = "1" ]; then
  echo "VOINO_KEEP_TEST_SEAMS=1: test seams kept in build/web (LOCAL TEST ARTIFACT - do not release)"
  exit 0
fi
node tools/strip_test_seams.js build/web/whisper.js
node --check build/web/whisper.js
if grep -q "VOINO TEST SEAM\|voinoSegTest\|__voinoTestAsr\|voinoInitStallMs\|stagelog\|STAGE_LOG\|sendBeacon" build/web/whisper.js; then
  echo "ERROR: test seam identifiers still present in build/web/whisper.js" >&2
  exit 1
fi
echo "build/web: release build complete, test seams stripped and verified absent"
