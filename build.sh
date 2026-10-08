#!/bin/bash
# Compile Kapte.app (universelle : Apple Silicon + Intel) et prépare build/Kapte.zip,
# le fichier publié dans les releases GitHub (app + installateur + README).
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${KAPTE_VERSION:-$(cat VERSION)}"
BUILD=build
APP="$BUILD/Kapte.app"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS"

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" \
    -o "$BUILD/Kapte-$arch" App/*.swift
done
lipo -create -output "$APP/Contents/MacOS/Kapte" "$BUILD/Kapte-arm64" "$BUILD/Kapte-x86_64"
rm "$BUILD/Kapte-arm64" "$BUILD/Kapte-x86_64"

sed "s/__VERSION__/$VERSION/g" App/Info.plist > "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"  # signature locale, obligatoire sur Apple Silicon

PKG="$BUILD/Kapte"
mkdir -p "$PKG"
cp -R "$APP" "$PKG/"
cp "Installer Kapte.command" "Desinstaller Kapte.command" README.md "$PKG/"
chmod +x "$PKG/"*.command
(cd "$BUILD" && ditto -c -k --norsrc --noextattr --keepParent Kapte Kapte.zip)

echo "✅ $BUILD/Kapte.zip (v$VERSION)"
