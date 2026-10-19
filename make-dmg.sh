#!/bin/bash
set -euo pipefail

# 构建 SAP GUI Tabs.app 并打包成可分发的 DMG。
# 产物 SAPGUITabs.dmg 可直接发给同事:双击挂载 → 把 App 拖进 Applications。
#
# ⚠️ 本 App 用自签名/ad-hoc 签名,未经 Apple 公证。同事首次打开需:
#   1. 从 DMG 把 App 拖到「应用程序」
#   2. 右键 App → 打开(或在「系统设置 → 隐私与安全性」里点「仍要打开」)
#   3. 在「隐私与安全性 → 辅助功能」里勾选 SAP GUI Tabs
# DMG 内附带「安装和使用说明.txt」会提示这些步骤并介绍功能用法。

cd "$(dirname "$0")"

APP_NAME="SAP GUI Tabs"
BUNDLE="${APP_NAME}.app"
DMG_NAME="SAPGUITabs"
VOL_NAME="SAP GUI Tabs"

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

cat > "${STAGING}/安装和使用说明.txt" <<'TXT'
SAP GUI Tabs 安装和使用说明
========================

这是什么?
----------
一个 macOS 小工具:在屏幕顶部浮一条浏览器式页签栏,把你打开的所有
SAP GUI 会话窗口聚合成页签,点一下即可切换,不用再在一堆长得一样的
SAP 窗口里挨个翻找。


软件功能
--------
- 浮动页签栏:常驻屏幕顶部、水平居中;仅在 SAP GUI 处于前台时自动
  显示,切到别的应用就隐藏,不打扰。
- 一眼看清所有会话:同一系统的会话自动归为一组,组首显示系统 ID
  (如 DWC),组内各页签显示当前事务码(如 /SCWM/MON)。
- 组内按事务码字母排序,位置可预期、好找。
- 单击秒切:点页签立刻把对应 SAP 窗口抬到最前,且不抢占焦点。
- 当前窗口高亮:当前聚焦的会话页签高亮;即便多个窗口标题完全相同
  也不会误高亮。
- 放不下自动收纳:页签过多时,放不下的收进右端下拉菜单。
- 右键关闭:在页签上右键即可关闭对应 SAP 会话窗口。
- TCode 收藏菜单:页签栏最左侧的菜单按钮,收藏常用事务码,支持多级
  文件夹分组,点一下即可在当前会话里打开对应事务。
- 字段默认值自动填充:为「系统+事务码+字段」配好默认值后,窗口进入
  该事务码时自动把空字段填上(如登录屏自动填用户名/语言)。
- 极轻量:原生应用,无后台服务、不联网、不收集任何数据,仅通过系统
  辅助功能 API 读取窗口信息。

环境要求:macOS 13 (Ventura) 或更高;已安装 SAP GUI for Java 8.10。


安装步骤
--------
1. 把左边的「SAP GUI Tabs」图标拖到右边的「Applications」文件夹。

2. 首次打开(重要!本应用未经 Apple 公证,需手动放行):
   - 打开「应用程序」,找到 SAP GUI Tabs
   - 右键点击它 → 选择「打开」→ 在弹窗里再点「打开」
   - 如果仍被拦截:打开「系统设置 → 隐私与安全性」,
     往下找到关于 SAP GUI Tabs 的提示,点「仍要打开」

3. 授予辅助功能权限(必须,否则无法读取/切换 SAP 窗口):
   - 打开「系统设置 → 隐私与安全性 → 辅助功能」
   - 把 SAP GUI Tabs 的开关打开(如列表里没有,点 + 手动添加)

4. 打开 SAP GUI 并登录会话,屏幕顶部即会出现页签条。


怎么用
------
- 打开任意 SAP GUI 会话,页签栏自动出现在屏幕顶部;切到非 SAP 应用
  时自动隐藏,切回时再次出现。
- 单击页签 → 切到对应会话窗口。
- 右键页签 → 关闭该会话。
- 页签放不下时,点右端下拉菜单查看被收纳的页签。

TCode 收藏菜单(页签栏最左侧的菜单按钮):
- 点某个事务码:默认用 /o 前缀(另开一个新窗口打开该事务);
  按住 Option(Alt)再点则用 /n 前缀(在当前窗口切换到该事务)——
  按住 Alt 时菜单里每个事务码前会实时显示 /n 作提示。
- Add TCode:在该级菜单手工输入事务码加入(自动转大写保存)。
- Add Folder:在该级新建子文件夹,给事务码分组。
- Delete:列出本级所有事务码与文件夹,点即删(删文件夹会弹确认框)。
- 收藏数据保存在你的主目录 ~/.sapguitabs_tcodes.json。

字段默认值自动填充:
- 配置文件在你的主目录 ~/.sapguitabs_defaults.conf(首次运行自动生成,
  内含注释示例)。
- 每行一条规则,格式:系统ID,Tcode,字段ID = 默认值
    系统ID = 窗口标题前三个字符(如 SWA、DWC),不区分大小写
    Tcode  = 事务码(如 SE16、SE38);登录屏用 S000
    字段ID = 字段左边的标签文字(如 User、Password、Table Name),照屏幕
             上显示的写
    默认值 = 要自动填入的内容
- 某会话窗口首次进入对应事务码时,若该字段当前为空,就自动填入默认值;
  已有值不会被覆盖。填入发生在该 SAP 窗口处于前台时(需要键盘焦点)。
- 改完配置,点菜单栏图标 →「重新加载默认值配置」即可生效,无需重启。
- 注意:密码等敏感内容以明文存在配置文件里,请自行权衡安全。


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
