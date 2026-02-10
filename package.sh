#!/bin/bash
set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────
APP_NAME="Time Awareness"
BUNDLE_ID="com.timeawareness.app"
EXECUTABLE_NAME="TimeAwareness"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/release"
APP_BUNDLE="$SCRIPT_DIR/${APP_NAME}.app"
ICON_SOURCE="$SCRIPT_DIR/Resources/AppIcon.icns"

# ─── Build ───────────────────────────────────────────────────────
echo "🔨 Building ${APP_NAME} (release)..."
cd "$SCRIPT_DIR"
swift build -c release 2>&1

if [ ! -f "$BUILD_DIR/$EXECUTABLE_NAME" ]; then
    echo "❌ Build failed: executable not found at $BUILD_DIR/$EXECUTABLE_NAME"
    exit 1
fi

echo "✅ Build succeeded."

# ─── Create .app Bundle ─────────────────────────────────────────
echo "📦 Creating ${APP_NAME}.app bundle..."

# Clean previous bundle
rm -rf "$APP_BUNDLE"

# Create structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

# Copy icon if it exists
if [ -f "$ICON_SOURCE" ]; then
    cp "$ICON_SOURCE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "🎨 App icon copied."
else
    echo "⚠️  No AppIcon.icns found at $ICON_SOURCE, skipping icon."
fi

# ─── Generate Info.plist ─────────────────────────────────────────
cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

echo "✅ ${APP_NAME}.app created at: $APP_BUNDLE"
echo ""
echo "🚀 To launch: open \"$APP_BUNDLE\""
