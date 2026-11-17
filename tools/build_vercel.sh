#!/bin/sh
# Vercel's buildCommand has a length limit; keep the release steps here.
set -e
if [ ! -d flutter ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 flutter
fi
flutter/bin/flutter config --enable-web
flutter/bin/flutter build web --release
node tools/strip_test_seams.js build/web/whisper.js
node --check build/web/whisper.js
