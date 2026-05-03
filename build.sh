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

if [ "$SKIP_INSTALL" != "1" ]; then
    echo ""
    echo "=== Instalando en /Applications ==="
    # Matar instancia previa (si está corriendo, ditto puede pisar pero
    # la app vieja queda en RAM hasta que la cierres y reabras).
    if pgrep -x AudioCapture > /dev/null; then
        echo "Cerrando instancia previa..."
        pkill -x AudioCapture
        sleep 1
    fi
    ditto "$BUILD_DIR/AudioCapture.app" /Applications/AudioCapture.app
    INSTALLED_PATH="/Applications/AudioCapture.app"
else
    echo ""
    echo "=== SKIP_INSTALL=1: no se desplegó a /Applications ==="
    INSTALLED_PATH="$BUILD_DIR/AudioCapture.app"
fi

echo ""
echo "=== Build exitoso! ==="
echo ""
echo "Para ejecutar:"
echo "  open $INSTALLED_PATH"
echo ""
echo "La primera vez te pedirá permiso de 'Grabación de pantalla y audio del sistema'"
echo "en Ajustes del Sistema > Privacidad y seguridad."
