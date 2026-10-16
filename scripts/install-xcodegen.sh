#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work/tools
curl --fail --location --retry 2 --max-time 120 \
  https://github.com/yonaskolb/XcodeGen/releases/download/2.44.1/xcodegen.artifactbundle.zip \
  -o work/tools/xcodegen.zip
printf '%s  %s\n' cfa4e1ee82fc4c95bf7bd8f7db1fda6bd073605c76a8d5cbce50c54a81867eb2 work/tools/xcodegen.zip | shasum -a 256 -c -
unzip -q -o work/tools/xcodegen.zip -d work/tools
work/tools/xcodegen.artifactbundle/xcodegen-2.44.1-macosx/bin/xcodegen generate --spec project.yml
