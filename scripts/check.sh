#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

export CLANG_MODULE_CACHE_PATH="$PWD/.build/ClangModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift test --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
xcodebuild -project Daywell.xcodeproj -scheme Daywell \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
