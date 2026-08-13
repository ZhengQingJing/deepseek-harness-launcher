#!/bin/bash
#
# DS-H Launcher build script — compiles a universal (arm64 + x86_64) .app,
# ad-hoc signs it, and packages it into a distributable zip.
#
# Usage:
#   ./build.sh               # build with version 1.0.0
#   VERSION=1.2.0 ./build.sh # override version
#
set -euo pipefail

APP_NAME="DS-H 启动器"
BIN_NAME="DS-H-Launcher"
VERSION="${VERSION:-1.0.0}"
OUT_DIR="dist"
BUNDLE="$OUT_DIR/$APP_NAME.app"
ZIP_NAME="DS-H-Launcher-${VERSION}-macos-universal.zip"

echo "==> 清理旧构建..."
rm -rf "$OUT_DIR"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

echo "==> 编译 (arm64)..."
xcrun swiftc -O -target arm64-apple-macos13.0 \
    src/main.swift -o "$OUT_DIR/arm64" -framework Cocoa

echo "==> 编译 (x86_64)..."
xcrun swiftc -O -target x86_64-apple-macos13.0 \
    src/main.swift -o "$OUT_DIR/x86_64" -framework Cocoa

echo "==> 合并为 universal binary..."
xcrun lipo -create "$OUT_DIR/arm64" "$OUT_DIR/x86_64" \
    -output "$BUNDLE/Contents/MacOS/$BIN_NAME"
rm -f "$OUT_DIR/arm64" "$OUT_DIR/x86_64"
chmod +x "$BUNDLE/Contents/MacOS/$BIN_NAME"

echo "==> 组装 app bundle..."
cp Info.plist "$BUNDLE/Contents/Info.plist"
cp assets/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"

echo "==> ad-hoc 代码签名..."
codesign --force --deep --sign - "$BUNDLE"

echo "==> 打包 zip..."
ditto -c -k --keepParent "$BUNDLE" "$OUT_DIR/$ZIP_NAME"

echo ""
echo "构建完成 ✓"
echo "  App : $BUNDLE"
echo "  Zip : $OUT_DIR/$ZIP_NAME"
echo "  架构: universal (arm64 + x86_64)"
