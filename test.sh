#!/bin/zsh
set -euo pipefail

task_source="${0:A:h}"
task_build="$task_source/.build"
mkdir -p "$task_build/module-cache" "$task_build/test-tmp"

/usr/bin/xcrun swiftc -swift-version 5 -module-cache-path "$task_build/module-cache" \
  "$task_source/Sources/DisplayModel.swift" "$task_source/Sources/SettingsStore.swift" \
  "$task_source/Tests/DomainTests.swift" -o "$task_build/domain-tests"
"$task_build/domain-tests" "$task_build/test-tmp"

if [[ "${1:-}" == "--shortcut" ]]; then
  /usr/bin/xcrun swiftc -swift-version 5 -module-cache-path "$task_build/module-cache" \
    "$task_source/Sources/DisplayModel.swift" "$task_source/Sources/GlobalShortcut.swift" \
    "$task_source/Tests/ShortcutTests.swift" -o "$task_build/shortcut-tests"
  "$task_build/shortcut-tests"
fi
