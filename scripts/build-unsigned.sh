#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs
xcodebuild -version | tee build/logs/xcode.txt
swift --version | tee build/logs/swift.txt
xcodebuild -project HeadLink.xcodeproj -scheme HeadLink \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData -resultBundlePath build/device-build.xcresult \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" build | tee build/logs/device-build.log
python3 scripts/package-ipa.py build/DerivedData/Build/Products/Release-iphoneos/HeadLink.app build
