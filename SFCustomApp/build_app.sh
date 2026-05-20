#!/usr/bin/env bash
# Build SF Custom into a proper macOS .app bundle.
#
# Usage:  ./build_app.sh [release|debug]   (default: release)
#
# Output: ./build/SF Custom.app
set -euo pipefail

CONFIG="${1:-release}"
APP_BUNDLE="SFCustomApp"          # filename on disk (no spaces — keeps Dock bookmarks stable)
APP_DISPLAY_NAME="SF Custom"      # what Finder / Dock label show users
EXEC_NAME="SFCustomApp"
BUNDLE_ID="com.impalastudios.SFCustom"
VERSION="1.0.0"
BUILD_NUMBER="1"

cd "$(dirname "$0")"

echo "→ swift build -c ${CONFIG}"
swift build -c "${CONFIG}"

BUILD_DIR=".build/${CONFIG}"
APP_DIR="build/${APP_BUNDLE}.app"

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/${EXEC_NAME}" "${APP_DIR}/Contents/MacOS/${EXEC_NAME}"

# SPM bundles resources as a .bundle next to the binary.
BUNDLE_NAME="${EXEC_NAME}_${EXEC_NAME}.bundle"
if [[ -d "${BUILD_DIR}/${BUNDLE_NAME}" ]]; then
  cp -R "${BUILD_DIR}/${BUNDLE_NAME}" "${APP_DIR}/Contents/Resources/${BUNDLE_NAME}"
fi

# Render AppIcon.icns from the Icon Composer source if present.
ICON_SOURCE="SFCustom.icon"
if [[ -d "${ICON_SOURCE}" ]]; then
  echo "→ rendering ${ICON_SOURCE} → AppIcon.icns"
  ICON_OUT=".build/icon"
  rm -rf "${ICON_OUT}"
  mkdir -p "${ICON_OUT}"
  swift tools/render_icon.swift "${ICON_SOURCE}" "${ICON_OUT}" > /dev/null
  if [[ -f "${ICON_OUT}/AppIcon.icns" ]]; then
    cp "${ICON_OUT}/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
  else
    echo "  warning: render_icon.swift did not produce AppIcon.icns"
  fi
fi

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>           <string>en</string>
    <key>CFBundleExecutable</key>                  <string>${EXEC_NAME}</string>
    <key>CFBundleIconFile</key>                    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>                  <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>       <string>6.0</string>
    <key>CFBundleName</key>                        <string>${APP_DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key>                 <string>${APP_DISPLAY_NAME}</string>
    <key>CFBundlePackageType</key>                 <string>APPL</string>
    <key>CFBundleShortVersionString</key>          <string>${VERSION}</string>
    <key>CFBundleVersion</key>                     <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>              <string>14.0</string>
    <key>NSHighResolutionCapable</key>             <true/>
    <key>NSPrincipalClass</key>                    <string>NSApplication</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
    <key>CFBundleDocumentTypes</key>
    <array>
      <dict>
        <key>CFBundleTypeName</key>          <string>SVG Image</string>
        <key>CFBundleTypeRole</key>          <string>Viewer</string>
        <key>LSHandlerRank</key>             <string>Alternate</string>
        <key>LSItemContentTypes</key>
        <array><string>public.svg-image</string></array>
      </dict>
    </array>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>  <true/>
    </dict>
</dict>
</plist>
PLIST

# Ad-hoc codesign so Gatekeeper at least lets the user double-click it.
codesign --force --deep --sign - "${APP_DIR}" 2>&1 | sed 's/^/  /'

echo "✓ Built ${APP_DIR}"
