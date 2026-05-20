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

# Build AppIcon.icns from either a pre-rendered 1024×1024 PNG (preferred —
# preserves Icon Composer's glass / specular / shadow effects) or, as a
# fallback, by compositing the layered SVGs in SFCustom.icon.
RENDERED_ICON="SFCustomIcon.png"
ICON_SOURCE="SFCustom.icon"
ICON_OUT=".build/icon"
ICONSET="${ICON_OUT}/AppIcon.iconset"

if [[ -f "${RENDERED_ICON}" ]]; then
  echo "→ packaging ${RENDERED_ICON} → AppIcon.icns"
  rm -rf "${ICON_OUT}"
  mkdir -p "${ICONSET}"

  for spec in 16:icon_16x16.png 32:icon_16x16@2x.png 32:icon_32x32.png \
              64:icon_32x32@2x.png 128:icon_128x128.png 256:icon_128x128@2x.png \
              256:icon_256x256.png 512:icon_256x256@2x.png \
              512:icon_512x512.png 1024:icon_512x512@2x.png; do
    SIZE="${spec%%:*}"
    NAME="${spec#*:}"
    sips -z "${SIZE}" "${SIZE}" "${RENDERED_ICON}" --out "${ICONSET}/${NAME}" > /dev/null
  done
  iconutil -c icns "${ICONSET}" -o "${ICON_OUT}/AppIcon.icns"
  cp "${ICON_OUT}/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"

elif [[ -d "${ICON_SOURCE}" ]]; then
  echo "→ rendering ${ICON_SOURCE} → AppIcon.icns (fallback, no glass effects)"
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
