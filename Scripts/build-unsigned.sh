#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -d GTAVITimer.xcodeproj ]; then xcodegen generate; fi
xcodebuild build -project GTAVITimer.xcodeproj -scheme GTAVITimer \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO
APP=build/device/Build/Products/Release-iphoneos/GTAVITimer.app
test -d "$APP/PlugIns/TimerWidget.appex"
test -f "$APP/PlugIns/TimerWidget.appex/TimerWidget"
mkdir -p build/package/Payload
cp -R "$APP" build/package/Payload/
(cd build/package && zip -qr ../AnyTimer-unsigned.ipa Payload)
echo 'Created unsigned IPA; requires signing of the app AND its embedded widget before installation.'
