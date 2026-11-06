#!/bin/bash
# Build the universal calendar-helper with an embedded Info.plist (usage
# strings for the Calendar privacy prompt) and a stable signing identifier.
set -euo pipefail
cd "$(dirname "$0")/.."
ID=io.github.apple-mcp.calendar-helper
PLIST=(-Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker swift/Info.plist)
mkdir -p build
for arch in arm64 x86_64; do
  swiftc -O -target $arch-apple-macosx13.0 -o build/calendar-helper-$arch \
    swift/CalendarHelper.swift -framework EventKit -framework Foundation "${PLIST[@]}"
done
lipo -create build/calendar-helper-arm64 build/calendar-helper-x86_64 -output build/calendar-helper
rm build/calendar-helper-arm64 build/calendar-helper-x86_64
codesign --force --sign "${CODESIGN_IDENTITY:--}" --identifier "$ID" build/calendar-helper
