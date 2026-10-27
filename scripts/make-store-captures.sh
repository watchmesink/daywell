#!/bin/bash
# Capture the dashboard, selection editor, and allowance editor in dark and light
# appearance on the iPhone 17 Pro simulator (1206 × 2622) for App Store slides.
# Builds the real App views against scripts/store-preview/Fixture.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
WORK=build/store-preview
OUT=build/store-captures
DEVICE=${DEVICE:-iPhone 17 Pro}

rm -rf "$WORK/src" && mkdir -p "$WORK/src" "$OUT"
cp scripts/store-preview/project.yml "$WORK/"
cp scripts/store-preview/Fixture.swift App/Components.swift App/ContentView.swift \
   App/Editors.swift App/OceanSunsetArtwork.swift App/ShareProblemView.swift \
   App/ProblemReportExporter.swift Shared/ProtectionEnvironment.swift Shared/ReportContext.swift "$WORK/src/"
python3 -I scripts/store-preview/patch.py "$WORK/src"

UDID=$(xcrun simctl list devices available -j | python3 -I -c "
import json, sys
devices = [d for runtime in json.load(sys.stdin)['devices'].values() for d in runtime]
print(next(d['udid'] for d in devices if d['name'] == sys.argv[1]))" "$DEVICE")
(cd "$WORK" && xcodegen generate --quiet)
xcodebuild -quiet -project "$WORK/StorePreview.xcodeproj" -scheme StorePreview \
  -destination "id=$UDID" -derivedDataPath "$WORK/DerivedData" build
APP="$WORK/DerivedData/Build/Products/Debug-iphonesimulator/StorePreview.app"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" >/dev/null
xcrun simctl status_bar "$UDID" override --time 9:41 --dataNetwork wifi --wifiMode active \
  --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
xcrun simctl install "$UDID" "$APP"

for appearance in dark light; do
  xcrun simctl ui "$UDID" appearance "$appearance"
  for screen in dashboard apps allowance; do
    xcrun simctl terminate "$UDID" dev.glebmelnikov.daywell.storepreview 2>/dev/null || true
    xcrun simctl launch "$UDID" dev.glebmelnikov.daywell.storepreview --screen "$screen" >/dev/null
    sleep 4
    xcrun simctl io "$UDID" screenshot --type=png "$OUT/$screen-$appearance.png" >/dev/null 2>&1
    echo "$OUT/$screen-$appearance.png"
  done
done
xcrun simctl status_bar "$UDID" clear
