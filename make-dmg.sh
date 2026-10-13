#!/bin/bash
set -euo pipefail

# 构建 SAP Tabs.app 并打包成可分发的 DMG。
# 产物 SAPTabs.dmg 可直接发给同事:双击挂载 → 把 App 拖进 Applications。
#
# ⚠️ 本 App 用自签名/ad-hoc 签名,未经 Apple 公证。同事首次打开需:
#   1. 从 DMG 把 App 拖到「应用程序」
#   2. 右键 App → 打开(或在「系统设置 → 隐私与安全性」里点「仍要打开」)
#   3. 在「隐私与安全性 → 辅助功能」里勾选 SAP Tabs
# DMG 内附带「安装说明.txt」会提示这些步骤。

cd "$(dirname "$0")"

APP_NAME="SAP Tabs"
BUNDLE="${APP_NAME}.app"
DMG_NAME="SAPTabs"
VOL_NAME="SAP Tabs"

# 1) 先构建最新的 .app
echo ">>> 构建 App..."
./build.sh

if [ ! -d "${BUNDLE}" ]; then
    echo "错误:未找到 ${BUNDLE},构建失败" >&2
    exit 1
fi

# 2) 准备 DMG 临时目录(App + Applications 快捷方式 + 安装说明)
echo ">>> 准备 DMG 内容..."
STAGING="$(mktemp -d)"
trap 'rm -rf "${STAGING}"' EXIT

cp -R "${BUNDLE}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

cat > "${STAGING}/安装说明.txt" <<'TXT'
SAP Tabs 安装说明
==================

1. 把左边的「SAP Tabs」图标拖到右边的「Applications」文件夹。

2. 首次打开(重要!本应用未经 Apple 公证,需手动放行):
   - 打开「应用程序」,找到 SAP Tabs
   - 右键点击它 → 选择「打开」→ 在弹窗里再点「打开」
   - 如果仍被拦截:打开「系统设置 → 隐私与安全性」,
     往下找到关于 SAP Tabs 的提示,点「仍要打开」

3. 授予辅助功能权限(必须,否则无法读取/切换 SAP 窗口):
   - 打开「系统设置 → 隐私与安全性 → 辅助功能」
   - 把 SAP Tabs 的开关打开(如列表里没有,点 + 手动添加)

4. 打开 SAP GUI 并登录会话,屏幕顶部即会出现页签条。

说明:本应用在本地运行,不联网、不收集任何数据。
TXT

# 3) 生成 DMG
echo ">>> 生成 ${DMG_NAME}.dmg ..."
rm -f "${DMG_NAME}.dmg"
hdiutil create \
    -volname "${VOL_NAME}" \
    -srcfolder "${STAGING}" \
    -ov \
    -format UDZO \
    "${DMG_NAME}.dmg"

echo ">>> 完成: $(pwd)/${DMG_NAME}.dmg"
echo "    直接把这个 .dmg 发给同事即可。"
