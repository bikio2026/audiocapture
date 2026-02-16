#!/bin/bash
set -e

cd "$(dirname "$0")"

SDK=$(xcrun --show-sdk-path)
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/AudioCapture.app/Contents"

# Collect all Swift source files
SOURCES=$(find Sources -name "*.swift" | tr '\n' ' ')

echo "=== Compilando AudioCapture ==="
echo "SDK: $SDK"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

swiftc \
    -sdk "$SDK" \
    -target arm64-apple-macosx13.0 \
    -O \
    -framework ScreenCaptureKit \
    -framework AVFoundation \
    -framework AppKit \
    -framework CoreMedia \
    -framework SwiftUI \
    $SOURCES \
    -o "$BUILD_DIR/AudioCapture" \
    2>&1

echo ""
echo "=== Creando .app bundle ==="
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"

cp "$BUILD_DIR/AudioCapture" "$APP_DIR/MacOS/AudioCapture"
cp Info.plist "$APP_DIR/Info.plist"
echo -n "APPL????" > "$APP_DIR/PkgInfo"

echo ""
echo "=== Firmando app (ad-hoc) ==="
codesign --force --sign - --entitlements AudioCapture.entitlements \
    --deep "$BUILD_DIR/AudioCapture.app"

echo ""
echo "=== Build exitoso! ==="
echo "App: $BUILD_DIR/AudioCapture.app"
echo ""
echo "Para ejecutar:"
echo "  open $BUILD_DIR/AudioCapture.app"
echo ""
echo "La primera vez te pedirá permiso de 'Grabación de pantalla y audio del sistema'"
echo "en Ajustes del Sistema > Privacidad y seguridad."
