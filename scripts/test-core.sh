#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Scratch/cache stays in the repository; no Xcode/simulator installation.
mkdir -p work/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/work/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/work/module-cache"
args=(--disable-xctest --scratch-path work/build)
if [[ "$(xcode-select -p)" == */CommandLineTools ]]; then
  frameworks="$(xcode-select -p)/Library/Developer/Frameworks"
  args+=(-Xswiftc "-F$frameworks" -Xlinker -rpath -Xlinker "$frameworks")
fi
swift test "${args[@]}" "$@"
