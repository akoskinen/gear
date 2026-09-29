#!/bin/bash
# Builds "eFoil Racing Live.saver" (universal: Apple Silicon + Intel).
# Needs the Xcode command line tools: xcode-select --install
set -euo pipefail
cd "$(dirname "$0")"

NAME="eFoil Racing Live"
BUILD=build
SAVER="$BUILD/$NAME.saver"
MIN_MACOS=12.0

rm -rf "$BUILD"
mkdir -p "$SAVER/Contents/MacOS" "$SAVER/Contents/Resources"

for arch in arm64 x86_64; do
  swiftc Sources/*.swift \
    -O -parse-as-library -emit-library \
    -module-name EfoilLive \
    -target "$arch-apple-macos$MIN_MACOS" \
    -framework ScreenSaver -framework WebKit -framework AppKit \
    -o "$BUILD/EfoilLive-$arch"
done

lipo -create "$BUILD/EfoilLive-arm64" "$BUILD/EfoilLive-x86_64" -output "$SAVER/Contents/MacOS/EfoilLive"
rm "$BUILD"/EfoilLive-*
cp Info.plist "$SAVER/Contents/Info.plist"

# Ad-hoc signature so Apple Silicon Macs will load it.
codesign --force --deep --sign - "$SAVER"

echo "Built $SAVER"
if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Library/Screen Savers"
  rm -rf "$HOME/Library/Screen Savers/$NAME.saver"
  cp -R "$SAVER" "$HOME/Library/Screen Savers/"
  echo "Installed to ~/Library/Screen Savers — pick it in System Settings → Screen Saver."
fi
