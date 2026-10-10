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

# 用本地自签名证书签名(稳定身份,TCC 授权永久保持,重建不失效)
# 若证书不存在则回退到 ad-hoc(授权会在重建后失效,需重新授权)
echo ">>> 代码签名..."
if security find-certificate -c "SAPTabs-SelfSign" >/dev/null 2>&1; then
    codesign --force --sign "SAPTabs-SelfSign" --identifier local.saptabs "${BUNDLE}"
    echo "    已用 SAPTabs-SelfSign 证书签名"
else
    codesign --force --sign - --identifier local.saptabs "${BUNDLE}" 2>/dev/null || true
    echo "    [警告] 未找到 SAPTabs-SelfSign 证书,回退 ad-hoc 签名(授权可能需重授)"
fi

echo ">>> 完成: $(pwd)/${BUNDLE}"
