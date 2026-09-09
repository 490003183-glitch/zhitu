#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE=$(mktemp -d /tmp/branch-build.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/枝图.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc Sources/*.swift -target "$(uname -m)-apple-macosx14.0" -o "$APP/Contents/MacOS/Branch" -framework AppKit -framework UniformTypeIdentifiers -O
mkdir -p "$APP/Contents/Resources/scripts"
cp scripts/*.py "$APP/Contents/Resources/scripts/"
cp LICENSE NOTICE README.md "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Branch</string><key>CFBundleIdentifier</key><string>local.branch.mindmap</string><key>CFBundleName</key><string>枝图</string><key>CFBundleShortVersionString</key><string>0.2.2</string><key>CFBundleVersion</key><string>1</string><key>NSHighResolutionCapable</key><true/><key>LSMinimumSystemVersion</key><string>14.0</string><key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>Branch Node</string><key>CFBundleURLSchemes</key><array><string>branch</string></array></dict></array><key>CFBundleDocumentTypes</key><array><dict><key>CFBundleTypeName</key><string>枝图工程</string><key>CFBundleTypeExtensions</key><array><string>branch</string></array><key>CFBundleTypeRole</key><string>Editor</string></dict></array></dict></plist>
PLIST
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
mkdir -p build
# Replace the bundle so obsolete WebKit resources cannot survive migration.
if [ -d "build/枝图.app" ]; then mv "build/枝图.app" "$STAGE/previous.app"; fi
if ! ditto --norsrc "$APP" "build/枝图.app"; then
  if [ -d "$STAGE/previous.app" ]; then mv "$STAGE/previous.app" "build/枝图.app"; fi
  exit 1
fi
printf 'Built build/枝图.app\n'
