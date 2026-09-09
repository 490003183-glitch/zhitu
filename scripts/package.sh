#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
APP="build/枝图.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
ARCH=$(lipo -archs "$APP/Contents/MacOS/Branch")
NAME="Zhitu-${VERSION}-macOS-${ARCH}"
STAGE=$(mktemp -d /tmp/branch-package.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/payload" dist
ditto --norsrc "$APP" "$STAGE/payload/枝图.app"
cp LICENSE NOTICE INSTALL.txt "$STAGE/payload/"
codesign --verify --deep --strict "$STAGE/payload/枝图.app"
# ZIP and DMG contain the same application and license notices.
python3 - "$STAGE/payload" "$STAGE/$NAME.zip" <<'PY'
from pathlib import Path
import sys, zipfile
root = Path(sys.argv[1])
# zipfile marks Chinese filenames as UTF-8 and retains executable permissions.
with zipfile.ZipFile(sys.argv[2], 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(root.rglob('*')):
        archive.write(path, path.relative_to(root))
PY
ln -s /Applications "$STAGE/payload/Applications"
hdiutil create -volname "枝图 $VERSION" -srcfolder "$STAGE/payload" -format UDZO -ov "$STAGE/$NAME.dmg"
hdiutil verify "$STAGE/$NAME.dmg"
mv "$STAGE/$NAME.dmg" "$STAGE/$NAME.zip" dist/
(cd dist && shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS.txt)
printf 'Packaged dist/%s.dmg and .zip\n' "$NAME"
