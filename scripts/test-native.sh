#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE=$(mktemp -d /tmp/branch-tests.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
SOURCES=()
for SOURCE in Sources/*.swift; do
  if [[ "$SOURCE" != Sources/main.swift ]]; then SOURCES+=("$SOURCE"); fi
done
swiftc "${SOURCES[@]}" tests/native/main.swift -o "$STAGE/native-tests" -framework AppKit -framework UniformTypeIdentifiers -framework PDFKit -O
"$STAGE/native-tests"
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 -m unittest discover -s tests -v
