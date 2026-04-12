#!/bin/bash
# Create a DMG for distribution

set -e

APP_NAME="Display Helper"
DMG_NAME="Display.Helper"
BUILD_DIR="build"
DMG_DIR="${BUILD_DIR}/dmg"
VERSION="1.1.4"

echo "Creating DMG..."

# Build the app first
./build.sh

# Create DMG directory
rm -rf "${DMG_DIR}"
mkdir -p "${DMG_DIR}"

# Copy app to DMG directory
cp -r "${BUILD_DIR}/${APP_NAME}.app" "${DMG_DIR}/"

# Create symlink to Applications
ln -s /Applications "${DMG_DIR}/Applications"

# Create README
cat > "${DMG_DIR}/README.txt" << 'EOF'
Display Helper — Free Software

Unlock crisp HiDPI (Retina) scaling on external displays when
macOS does not offer it natively.

INSTALLATION
1. Drag "Display Helper.app" to the Applications folder
2. Launch from Applications or Spotlight
3. Look for the display icon in your menu bar

FIRST LAUNCH
macOS may block the app. Right-click and select "Open",
then click "Open" in the dialog.

USAGE
1. Click the display icon in your menu bar
2. Select your monitor type
3. Choose a resolution preset
4. Wait a few seconds for configuration

AUTO-START
Enable "Start at Login" from the menu bar icon → Settings.

UNINSTALL
1. Click the menu bar icon and select "Quit"
2. Drag the app from Applications to Trash

More info: https://github.com/aksakalmustafa/HiDPIVirtualDisplay

---
Created with love by AL in Dallas
EOF

# Create the DMG
rm -f "${BUILD_DIR}/${DMG_NAME}.dmg"
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov -format UDZO \
    "${BUILD_DIR}/${DMG_NAME}.dmg"

# Clean up
rm -rf "${DMG_DIR}"

echo "DMG created: ${BUILD_DIR}/${DMG_NAME}.dmg"
echo ""
echo "File size: $(du -h "${BUILD_DIR}/${DMG_NAME}.dmg" | cut -f1)"
