#!/bin/bash
# Build the universal reminders-helper with an embedded Info.plist (usage
# strings for the Calendar privacy prompt) and a stable signing identifier.
set -euo pipefail
cd "$(dirname "$0")/.."
ID=io.github.apple-mcp.reminders-helper
PLIST=(-Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker swift/Info.plist)
mkdir -p build
for arch in arm64 x86_64; do
  swiftc -O -target $arch-apple-macosx13.0 -o build/reminders-helper-$arch \
    swift/RemindersHelper.swift -framework EventKit -framework Foundation "${PLIST[@]}"
done
lipo -create build/reminders-helper-arm64 build/reminders-helper-x86_64 -output build/reminders-helper
rm build/reminders-helper-arm64 build/reminders-helper-x86_64
codesign --force --sign "${CODESIGN_IDENTITY:--}" --identifier "$ID" build/reminders-helper
