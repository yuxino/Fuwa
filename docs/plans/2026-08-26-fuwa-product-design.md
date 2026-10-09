# Fuwa 产品设计

## 产品目标

Fuwa 是一个安静、可靠、键盘优先的 macOS 菜单栏工具。用户按 `⌥⌘P`，Fuwa 会优先固定前台 App 中符合意图的最前窗口，跳过已知跨 App 浮层与系统认证窗，并为 Finder Quick Look 保留窄范围例外。它不修改第三方 App 的原始窗口层级，而是使用公开的 ScreenCaptureKit 创建实时镜像。

首个公开版本必须让这件小事做起来足够舒服：触发快、没有黑闪、默认不抢鼠标、不多要权限、窗口关闭后不会突然消失，并且能正确处理 Finder 空格预览等临时窗口。

## 设计原则

- **稳定优先。** 默认观察模式只显示实时镜像，不通过鼠标进入/离开反复切换原窗口。
- **权限渐进。** 启动不请求权限；第一次固定时才请求屏幕录制；第一次使用 Interact 或 Reveal Source 时才请求辅助功能。
- **键盘优先。** 全局快捷键是不激活 Fuwa、也不破坏 Quick Look 的主路径。
- **本地与克制。** 不上传窗口内容、不做分析、不记录窗口标题或像素。
- **公开 API。** 不使用 SkyLight/CGS 私有 API，不注入其他进程，不要求关闭 SIP。
- **独立实现。** 以现有三个 Demo 提交为实现来源，后续依据 Apple 公共 API、自己的设计和测试继续开发，不复制 Topit 的 AGPL 源码、文案、资产或文件结构。

## 核心体验

### 固定当前窗口

1. 用户将目标窗口放到视觉最前方。
2. 按 `⌥⌘P`。
3. Fuwa 立即保存当前 WindowServer 前后顺序，不激活自身。
4. 目标解析器把 CGWindow 清单与 ScreenCaptureKit 可捕获窗口按 window ID 合并。
5. 最前面的合格窗口成为目标；PID 和 layer 只用于诊断，不作为硬过滤条件。
6. 收到第一张完整帧后，镜像才出现，避免黑框闪烁。

如果当前目标已经固定，再按快捷键会取消该目标；否则创建新的 Pin。Fuwa 支持同时保留多个 Pin。

### Finder Quick Look

Finder 空格预览在当前系统实测为 Finder 所有、`layer=3` 的可捕获窗口；`qlmanage -p` 又可能是独立进程的 `layer=0` 窗口。Fuwa 以“前台 App 归属 + CG z-order + SC 可捕获性”为主规则，并只为公开可识别的 Quick Look helper 保留窄范围跨进程例外；不依赖窗口标题、特定 layer 或本地化 AX subrole。

Quick Look 关闭后：

- 已收到完整帧：停止捕获并保留内存中的最后一帧，状态变为 `Frozen`。
- 尚未收到完整帧：明确报告失败，不得悄悄固定下面的 Finder 主窗口。
- 用户取消、退出、锁屏或切换用户：立即清除保存的像素。

### Freeze

用户可以手动 Freeze 一个 live Pin。Freeze 会保留最后一帧并停止对应的 ScreenCaptureKit 流；Resume 只在源窗口仍存在时可用。Frozen Pin 不持续录屏，也不消耗动态捕获资源。

### Interact

默认镜像穿透鼠标。用户显式选择 `Interact` 时，Fuwa 才解释并请求辅助功能权限，然后：

1. 通过 PID 与窗口几何匹配对应 AXWindow。
2. 激活源 App，并对该 AXWindow 执行 Raise。
3. 镜像仍保持鼠标穿透，因此真实输入落到刚刚抬升的源窗口。

Fuwa 不在鼠标 enter/leave 时停启捕获，也不假装可以转发键盘、拖放或菜单事件。AX 匹配失败、源窗口在其他 Space 或系统拒绝控制时，界面明确显示 `View only`，并提供 `Reveal Source`。

## 窗口选择策略

目标解析分为两个阶段：

1. **意图窗口。** 从按前后顺序排列的 CGWindow 清单中，排除自身窗口、桌面元素、明确的系统 UI、透明窗口、过小窗口和完全离屏窗口，取第一个视觉候选。
2. **可捕获确认。** 目标 window ID 必须存在于同次解析取得的 `SCShareableContent.windows` 中。若意图窗口不可捕获或在解析期间消失，返回明确错误，不回退到它下面的普通窗口。

排除规则优先使用进程 bundle identifier 与窗口特征，不依赖本地化 owner 名称。`layer != 0` 本身不是排除理由。

## 架构

```text
GlobalHotKey
    │
    ▼
TargetResolver
 ├─ WindowInventory (z-order, bounds, PID, layer)
 ├─ SCShareableContent (capturable window map)
 └─ SelectionPolicy (self/system/visibility exclusions)
    │
    ▼
PinCoordinator @MainActor
 ├─ PinSession[]
 │   ├─ SCStream lifecycle + generation guard
 │   ├─ CapturePanel + CaptureView
 │   ├─ last complete frame
 │   └─ live/frozen/failed state
 ├─ WindowTracker (one adaptive inventory timer)
 ├─ InteractionCoordinator (single engaged source)
 └─ PermissionCenter
    │
    ▼
AppModel → StatusItem + Native Menu + SwiftUI Main Window
```

纯逻辑放在 `FuwaCore`，AppKit、ScreenCaptureKit、Accessibility 和 SwiftUI 集成放在 `Fuwa` 可执行目标中。所有 UI 与窗口控制在 `MainActor`；每个捕获会话使用 generation 标识拒绝旧流帧、旧错误和迟到的 resize。

## 状态模型

```text
resolving → starting → live
                    ├─ manual/source gone → frozen
                    ├─ error → failed
                    └─ unpin → stopping → stopped

frozen ── resume while source exists → starting
       └─ unpin → stopped
```

任何状态下重复 stop 都必须安全。无 live Pin 时不得保留 SCStream 或几何追踪定时器。

## 界面

Fuwa 常驻菜单栏，可在设置中选择是否显示 Dock 图标。菜单栏按钮使用 template glyph；左右键打开同一个原生快捷菜单。设置和窗口选择都在主窗口打开，菜单、侧边栏与主窗口共用同一个 `AppModel`。

快捷菜单使用系统字体、间距、滚动、子菜单和键盘导航：

- 顶部直接提供固定最前方窗口和选择窗口。
- 已固定窗口以应用名、窗口名列出；子菜单显示当前状态，以及显示控制、暂停/继续和取消固定。
- 设置、关于与退出直接显示，不再藏在省略号内。
- 权限或操作错误有可点击的入口；完整错误在主窗口中显示。
- 菜单中不放设置表单，不在点击设置时扩大成第二个设置页面。

不使用渐变、玻璃拟态、彩色背景、重阴影或卡片墙。状态色只用于错误和权限警告。镜像面板保持无装饰与鼠标穿透，并加入全空间、全屏辅助和 Stage Manager 应用集。

### 品牌资产

Fuwa 与 Kiri、mimi 属于同一产品家族。应用图标与 README 标识沿用这一系列已经形成的圆形人物徽章、轻盈线稿、小写名标和低饱和粉彩语言；Fuwa 以银蓝色原创角色、`F` 发夹和悬浮小窗作为独立识别点，不复刻另外两位角色。系列感只进入品牌资产，不改变工具本身克制的黑白、中性界面，也不替换菜单栏中需要适配深浅模式的 template glyph。

`Resources/AppIcon.png` 是唯一母版，所有 `.icns` 尺寸都由脚本生成并在 CI 中核对。图标必须保留真实透明圆角，在 32 px 下仍能辨认角色轮廓、`F` 与悬浮窗；不得加入第二套 logo、不可读的小字或仅靠颜色成立的含义。

2026-09-08 调整：应用图标与 README 改用已确认的银发人物近景圆形头像，识别点为脸部、`F` 发夹与星形配饰，不再包含悬浮窗或小字。1130 × 1130 RGBA 母版裁自官网原画，圆内保留原白底。

2026-09-18 调整：圆形头像外的真实透明会在启动台被系统铺成灰色底板。母版改为在 n=5 超椭圆圆角方形内铺上与圆内原白底一致的底色，四角仍真实透明；角色、`F` 发夹与星形配饰不变，所有 ICNS 尺寸继续从该母版生成并核验。

2026-10-10 Dock 开关修复：Dock 图标完全由「保留 Dock 图标」设置控制。开启使用 `.regular`，关闭使用 `.accessory`，主窗口打开、关闭或重新打开不会覆盖这项设置。切换时保留当前窗口和焦点，原有设置会保留；菜单栏仍可打开主窗口，关闭主窗口不退出 App。

## 本地化与无障碍

- 首版提供简体中文与英文。
- 所有按钮都有可读标签、tooltip 和 VoiceOver 描述。
- 原生菜单和主窗口支持完整键盘导航。
- Reduce Motion 开启时不使用位移动画。
- 状态不能只靠颜色区分。

## 权限与隐私

- Screen Recording：只在第一次固定时申请。
- Accessibility：只在第一次 Interact 或 Reveal Source 时申请。
- 不申请 Input Monitoring、Automation、相机、麦克风或网络权限。
- `NSScreenCaptureUsageDescription` 明确说明只捕获用户主动选择的窗口、画面只留在本机。
- 锁屏、睡眠、退出时停止全部流；锁屏和用户切换时清除 Frozen 像素。

## 分发

- GitHub：`yuxino/fuwa`，public，MIT。
- 最低系统：macOS 14。
- CI：验证 Swift 包结构、Swift 6 严格 Release 构建、可执行逻辑检查、图标一致性、脚本语法与签名护栏。
- Release：维护者手动生成并验证 universal2 `.app` 压缩包、校验和与签名；仓库当前没有 tag 触发的发布或公证工作流。
- 当前本地候选构建使用持久签名身份，但不是 Developer ID 签名，也未经 Apple 公证。
- v1 不依赖第三方自动更新框架；用户从 GitHub Releases 更新。

## 明确不做

- 真正修改第三方 WindowServer level。
- 私有 API、代码注入、关闭 SIP。
- 输入事件注入、后台键盘转发、跨 App 拖放代理。
- App Store 沙盒版本。
- 自动恢复上次固定的第三方窗口。
- 把源窗口偷偷移动到另一块屏幕或另一个 Space。

## v0.1 验收标准

- `⌥⌘P` 能固定普通窗口、Finder 图片/PDF Quick Look 和 `qlmanage` 窗口。
- layer 不是 0、owner PID 不同的前台可捕获窗口都不会被错误过滤。
- 不可捕获或解析期间消失的目标不会回退固定下面的窗口。
- 第一张完整帧前不显示面板；关闭临时源窗口后转 Frozen。
- 支持多个 Pin、逐个 Freeze/Resume/Unpin 和全部清除。
- 默认只需屏幕录制；Interact 或 Reveal Source 才请求辅助功能。
- 多显示器坐标、缩放、源窗口移动与 Stage Manager 应用集能正确同步。
- 快速 Pin/Unpin、窗口销毁、睡眠唤醒、锁屏和权限撤回不会崩溃或残留面板。
- 中英文界面、VoiceOver 标签、Launch at Login 与可修改快捷键可用。
- `swift run --configuration release FuwaLogicTests`、严格 Release 构建、手动打包验证和 CI 全部通过。
- public GitHub 仓库包含 MIT LICENSE、双语 README、隐私说明、贡献指南、来源说明和首个 Release。
