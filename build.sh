#!/bin/bash
set -euo pipefail

# 构建并打包 SAP Tabs 为可双击运行的 .app
cd "$(dirname "$0")"

APP_NAME="SAP Tabs"
BUNDLE="${APP_NAME}.app"
BIN_NAME="SAPTabs"

echo ">>> 编译 release..."
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${BIN_NAME}"

echo ">>> 组装 ${BUNDLE} ..."
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"

cp "${BIN_PATH}" "${BUNDLE}/Contents/MacOS/${BIN_NAME}"

cat > "${BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${BIN_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>local.saptabs</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>需要控制 SAP GUI 窗口以实现页签切换。</string>
</dict>
</plist>
PLIST

# ad-hoc 签名,避免 Gatekeeper/辅助功能权限反复失效
echo ">>> ad-hoc 签名..."
codesign --force --deep --sign - "${BUNDLE}" 2>/dev/null || true

echo ">>> 完成: $(pwd)/${BUNDLE}"
