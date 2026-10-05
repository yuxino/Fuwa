# MyGo rewrite: implementation and acceptance

Baseline: Fuwa `70c5be75f1f09920de5d650268ba70a9e13e86a4`.
Framework: egoist/mygo `bfb878510ce3e0f7ac684090137d5147ed4421ff`.

## English

This branch replaces the Swift app and its build with Go/MyGo plus a new macOS-only Objective-C adapter. The original icon, MIT license, release history and historical design documents are retained. It neither publishes a release nor changes the stable application.

### Implemented paths

| Capability | Implementation | Automated evidence / remaining acceptance |
| --- | --- | --- |
| Exact front-window selection; Quick Look exception; exclude system/Fuwa windows | `core.Intent`, CG inventory, exact SCK ID confirmation | Unit tests; real Quick Look permission flow pending |
| Eight independent click-through, always-on-top mirrors | MyGo windows + SCStream / AVSampleBufferDisplayLayer | Compile; real capture and full-screen Spaces pending |
| Freeze/resume/closed source | Independent pixel copy before stream stop; same identity + generation gates | State tests; real stream timing pending |
| Source move/resize and multi-display | Shared 500 ms inventory, MyGo bounds, coalesced stream configuration | Geometry tests; Retina transitions pending |
| Go to original | Public AX matching with PID, launch identity, title, geometry and ambiguity rejection | Compile; interactive AX matching pending |
| Menu bar, main management, window picker and pin controls | Native MyGo UI/menus/windows | Headless native UI tests and fixture renders |
| Shortcut customization with conflict rollback | Register replacement before removing existing binding | Syntax tests; OS conflict behavior pending |
| Dock and login preferences | MyGo activation policy; SMAppService actual approval state | Preferences tests; real login approval pending |
| System/English/Simplified Chinese | Native view text catalogue and localized permissions | Native UI tests; VoiceOver inspection pending |
| Privacy teardown | Hide/clear native surfaces before async stream stop; lock/sleep/session/permission handlers | State tests; interactive lock/wake pending |
| Manual signed updates | MyGo updater, fixed repository and `mygo-v` feed, existing public Ed25519 key | No signed MyGo release published; end-to-end update pending |

### Explicit differences from the stable app

- The app identity/name/settings are isolated to protect stable installations. Preferences and pins are not imported.
- Main and controls use MyGo's native renderer; the menu bar uses a native menu rather than the SwiftUI popover.
- Shortcut customization accepts an accelerator string rather than a key-capture control.
- Download, verification and installation are one explicit cancellable action rather than separate Sparkle staging screens. There are no background checks.
- Public AX matching is deliberately conservative; indistinguishable candidates fail rather than choosing one.
- Captures target 30 fps, bounded at 8192 pixels per side and 16 megapixels; pixels remain in native memory. Performance is not yet benchmarked.

### Manual acceptance before claiming parity

1. Run only the isolated preview. Reject the first Screen Recording prompt and confirm no other window is selected; approve later and pin again. No Accessibility prompt should appear until Go to original.
2. Pin two app windows and Finder Quick Look; interact with the app underneath. Exercise all pin actions from both management surfaces and the independent controls.
3. Freeze, move/resize/close the source, resume where possible; close a source during start and during resume. Confirm no stale stream resurrects a removed pin or substitutes another source.
4. Move sources between 1x/2x displays, a display left of the primary, full-screen Spaces and disconnected displays. Check geometry and image aspect ratio.
5. Lock/sleep/switch sessions/revoke recording permission while both live and frozen pins exist. Confirm pixels disappear immediately and never automatically return.
6. Change shortcuts into a known conflict; the previous binding must remain. Toggle Dock visibility with main open/closed and check login registration/approval/rejection.
7. Exercise English/Chinese and keyboard/VoiceOver navigation, then run the universal binary on a physical Intel Mac.
8. Only after an owner-signed MyGo release exists: valid update, cancellation, modified archive/signature, offline check and app unwritable. No unsigned fallback or Swift-package installation is acceptable.

The screenshot artifact is a rendering of the implemented view with fixtures, not proof of capture acceptance. CI must not auto-grant permissions, disable protections, access signing secrets, publish releases, or overwrite `/Applications/Fuwa.app`.

## 中文

本分支以 Go/MyGo 和全新的 macOS Objective-C 适配层替换 Swift 应用及构建，保留原图标、MIT 许可、发布历史与历史设计文档。不发布版本，不改正式版应用。

代码已实现精确窗口选择及 Quick Look 例外、8 个独立穿透镜像、冻结/恢复/关闭源处理、多屏位置及尺寸追踪、保守的公开 AX 原窗口定位、主界面/菜单栏/选择器/控制面板、自定义快捷键回滚、Dock/登录项/中英文设置、隐私清理和手动验签更新。

**差异须明确：** 预览应用标识与设置独立；菜单栏采用原生菜单而不是 SwiftUI 弹层；快捷键通过组合键文本设置而非录制；下载、验证、安装合为一次可取消操作；AX 匹配更保守；捕获目标 30 fps、单边最多 8192 像素、最多 1600 万级像素。尚未测量性能收益。

**真机验收尚需完成：** 授权拒绝/批准、真实镜像与 Quick Look、冻结和重连竞态、多显示器/Retina/全屏 Spaces、锁屏与权限撤销的即时清屏、快捷键冲突、Dock 与登录项审批、中英文及 VoiceOver、实体 Intel Mac、以及存在签名 MyGo 发布后的完整更新/取消/篡改拒绝流程。

原生界面截图使用测试数据，并非真实捕获已验收的证明。CI 不得自动授权、关闭保护、读取签名私钥、发布版本或覆盖 `/Applications/Fuwa.app`。旧正式版更新源不得接入预览版。
