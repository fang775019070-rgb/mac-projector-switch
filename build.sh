#!/bin/zsh
set -euo pipefail

task_source="${0:A:h}"
task_output="${1:-$task_source/dist/苹果电脑投影开关.app}"
task_cache="$task_source/.build/module-cache"

if [[ "$(/usr/bin/uname -s)" != "Darwin" ]]; then
  print -u2 "Build this macOS application on a Mac."
  exit 1
fi

mkdir -p "$task_output/Contents/MacOS" "$task_output/Contents/Resources" "$task_cache"
/usr/bin/xcrun swiftc -O -swift-version 5 -module-cache-path "$task_cache" \
  -target arm64-apple-macos13.0 "$task_source"/Sources/*.swift \
  -o "$task_output/Contents/MacOS/ProjectorSwitch"
cp "$task_source/Info.plist" "$task_output/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$task_output"
/usr/bin/codesign --verify --strict "$task_output"
print "Built: $task_output"
