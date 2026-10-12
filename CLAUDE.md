# SAP Tabs

macOS 菜单栏小工具:在屏幕顶部浮一条页签,列出所有打开的 SAP GUI 会话窗口,点击即可切换。Swift + SwiftUI + AppKit,靠 Accessibility API(AXUIElement)读写窗口。

> 本文件只记"读代码不易看出、改需求时必须知道"的约束与陷阱。文件结构、函数职责请直接看源码(就三个文件,都有中文注释)。

## 构建与运行

- **改完代码必须用 `./build.sh` 打包成 `.app` 再运行**,不能只 `swift build`。原因见下方「权限」。
- 典型重启流程:`pkill -x SAPTabs; ./build.sh; open "SAP Tabs.app"`。
- `build.sh` 用本地自签名证书 `SAPTabs-SelfSign` 签名,目的是让 TCC(辅助功能)授权在重建后**永久保持**。若该证书不存在会回退 ad-hoc 签名,届时每次重建都要重新授权。
- 产物 `SAP Tabs.app/`、`.build/` 已在 .gitignore,提交时只会有 `Sources/`。

## 权限(Accessibility / TCC)

- 整个应用依赖辅助功能权限(`AXIsProcessTrusted`),**权限是按"签名身份 + 可执行文件"授予的**。
- 写一次性 AX 探测脚本时(`swiftc xxx.swift -o probe && ./probe`),它继承的是**当前终端**的辅助功能授权,不是 app 的。若终端已授权即可直接跑,无需给 probe 单独授权——调试 AX 行为时这个办法很快。

## 两个"SAP 标识"不要混淆

- **进程名 `SAPGUI`**:枚举窗口时用它过滤 `NSWorkspace.runningApplications`(见 SAPWindowManager)。
- **bundle id `com.sap.platin`**:判断 SAP 是否在前台、决定浮条显隐时用它(见 main.swift `updatePanelVisibility`)。
- 这是 SAP GUI for Java 8.10;换版本/换 SAP GUI for HTML 前要先确认这两个值还对不对。

## 会话窗口的识别(纯靠标题正则,无 SAP API)

- 会话窗口标题形如 `DWC (1) (010)` = 系统ID + 会话号 + client号。
- 判定正则:`\(\d+\) \(\d+\)$`(SAPWindowManager `isSessionWindow`)。弹窗、连接管理器因不符合此格式被自动过滤——它们的 AX role/subrole/modal 和会话窗口**完全一样,无法用 AX 属性区分**,只能靠标题格式。
- 系统ID = 标题前 3 字符。

## ⚠️ 身份与显示必须严格分离(踩过坑)

曾出现"两个页签同时高亮 / 焦点混淆"的 bug,根因是用显示文本做了身份判断。现有机制,改动显示相关代码时**不得破坏**:

- **窗口稳定 id** = `pid-完整title@位置#区分号`,基于**完整原始标题**+屏幕位置+锚定 AX 元素身份的区分号。位置不随 z-order 变,区分号同一元素跨刷新恒定——所以点击置顶不会让页签重排。
- **焦点高亮**用 `CFEqual(focusedElement, win)` 比较 **AX 元素身份**,绝不比标题。否则同标题窗口会一起高亮。
- **页签上显示的文字(系统ID、TCode)只能用于显示**,绝不能混入 id 生成或焦点匹配。因此哪怕两个页签显示文本完全相同(如都是 `DWC /SCWM/MON`),身份与焦点仍互相独立。
- `SAPWindow.==` 只比 `id`,不比 title/tcode。

## TCode 读取的性能陷阱(踩过坑)

页签要显示当前事务码,数据来自状态栏那个系统信息下拉。实现时注意:

- SAP 会话窗口的 AX 树**极大**,主数据区字段子树单窗口可达近 2 万节点。**绝不能遍历整棵树找 TCode**——实测全量 BFS 一轮要 >1.5 秒,会卡死每秒刷新。
- 正确做法(SAPWindowManager `readTransactionCode`):TCode 所在的信息下拉是**窗口的直接子节点**,特征 `AXComboBox` + `desc="Show menu"`;先定位它,**只扫它那棵很小的子树**。全部窗口一轮约 22ms。
- 事务码在 `AXRow` 的 `desc`,形如 `"Transaction /SCWM/MON"`;有时 ComboBox 的 `value` 直接就是 `"Transaction SE38"`(已做快速路径)。
- 登录屏/主屏/弹窗态读到的是 `"Transaction "`(空码),按 nil 处理,页签回退只显系统ID。
- 刷新频率:TCode 跟 title 一起每秒刷(定时器 1s,见 `start()`)。

## 浮条行为(main.swift)

- 仅在 SAPGUI 处于前台时显示,切走即隐藏;菜单可手动停用自动显示(`manuallyHidden`)。
- 位置固定:主屏可见区宽度 90%、水平居中、紧贴顶部;高度 28(与 SAP 窗口标题栏那行等高)。屏幕参数变化会重新定位。
- 面板是 `.nonactivatingPanel` + `.floating`,点击切换窗口时不抢焦点。

## 其它环境约束

- **CommandLineTools 工具链缺少 SwiftUIMacros 插件**,`@State` 宏无法展开。所以组件内的局部状态(如悬停)用 `ObservableObject`(见 `HoverState`/`OverflowState`)代替 `@State`。新增视图状态时沿用此模式。
- 浮条的溢出布局(页签放不下时收进右端下拉)是自定义 `Layout`(`OverflowTabsLayout`),带滞回去抖,改页签尺寸/间距时留意别破坏它的宽度计算。
