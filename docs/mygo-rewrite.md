# MyGo rewrite: implementation and acceptance

Baseline: Fuwa `70c5be75f1f09920de5d650268ba70a9e13e86a4`.
Framework: egoist/mygo `bfb878510ce3e0f7ac684090137d5147ed4421ff`.
Current preview: `1.1.0-mygo.2` (isolated bundle build `2`).
Local upstream patch: [updater cancellation gates](../patches/README.md), applied through a source-hash-checked build overlay.

## English

This branch replaces the Swift app and its build with Go/MyGo plus a new macOS-only Objective-C adapter. The original icon, MIT license, release history and historical design documents are retained. It neither publishes a release nor changes the stable application.

### Implemented paths

| Capability | Implementation | Automated evidence / remaining acceptance |
| --- | --- | --- |
| Exact front-window selection; Quick Look exception; exclude system/Fuwa windows | One-shot prepared result, CG identity, exact SCK ID confirmation; no second selection after permission UI | Policy and coordinator tests; real Quick Look permission flow pending |
| Eight independent click-through, always-on-top mirrors | MyGo windows + SCStream / AVSampleBufferDisplayLayer; first-frame bridge | Owned-window and synthetic-frame QA; real capture and full-screen Spaces pending |
| Freeze/resume/retry/closed source | Independent bounded bitmap, stream-cycle teardown, same identity + generation gates | State and native delayed-completion tests; real ScreenCaptureKit timing pending |
| Source move/resize and multi-display | Shared 250 ms inventory, 100 ms movement burst, 120 ms configuration coalescing; source-owned scale | Geometry, invalid-inventory and synthetic Retina-scale tests; physical display transitions pending |
| Go to original | Public AX matching with PID, launch identity, title, geometry and ambiguity rejection | Compile; interactive AX matching pending |
| Menu bar, main management, searchable picker and pin controls | Native MyGo UI/menus/windows; shared action availability; white/ink appearance | Native ordering/focus checks, headless interactions and fixture renders |
| Shortcut customization with conflict rollback | Register replacement before removing existing binding | Syntax/rollback tests; native startup conflict/fallback; cross-app conflict acceptance pending |
| Dock and login preferences | MyGo activation policy; SMAppService actual approval state | Preferences tests; real login approval pending |
| System/English/Simplified Chinese | Native view text catalogue and localized permissions | Native UI tests; VoiceOver inspection pending |
| Privacy teardown | Hide/clear live, queued and frozen pixels before async stream stop; lock/display-sleep/system-sleep/session/permission handlers | Native lifecycle and event-batch QA; real lock/wake/revocation pending |
| Manual signed updates | MyGo updater plus cancellation patch; fixed repository and `mygo-v` feed; existing public Ed25519 key | Real installer exercised with temporary keys/apps; owner-signed MyGo release round trip pending |
| macOS 14 deployment target and Universal packaging | Both compiler/linker targets constrained; archive contents and both Mach-O slices checked | CI runs natively on arm64 and x86_64, verifies the extracted signature and launches the delivered app |

### Presentation parity regressions

Management stays above floating mirrors while Fuwa is active and returns to normal level when inactive. Pin controls follow their mirror, remain inside the usable screen area, and dismiss on blur, app deactivation or Escape. Frozen mirrors recover into a remaining display without moving the source; live streams no longer freeze solely because WindowServer reports the source offscreen. A conflicting saved shortcut tries `Cmd+Alt+P` as a fallback, and an inactive shortcut can be retried. If both are unavailable, the app reports that the shortcut is inactive. Language changes refresh the native application menu, tray and existing controls.

Run `./scripts/go-mygo.sh test -race -count=1 ./...` and `./scripts/go-mygo.sh vet ./...` for regression coverage. For an opt-in native check, build with `./scripts/go-mygo.sh build -tags fuwa_parity_qa -o build/fuwa-parity-qa .`, then run `FUWA_SMOKE_OUTPUT="$PWD/build/artifacts/parity" build/fuwa-parity-qa --fuwa-parity-smoke`. This creates only this process's own MyGo fixture windows and temporary QA preferences. It exercises actual AppKit ordering, parent relationships, focus/deactivation, native menu language and OS shortcut registration. Display removal is simulated by supplying a smaller work-area inventory; it does not change display settings. The QA-only native inspection code is excluded from ordinary builds.

The same native check now drives the production capture surface and lifecycle with owned `CVPixelBuffer` frames and a stream double whose start/update/stop completions can be delayed. It verifies first-frame presentation, an independent frozen copy after the original buffer changes, old-frame rejection, late start/resize teardown, source scale, the pixel budget, and privacy cleanup. The Go event consumer is also exercised with a frozen-before-live event, a no-frame failure, stale generations and a privacy event in the same batch as live frames. These are real implementation paths with synthetic inputs; they do not start a ScreenCaptureKit stream.

These checks do not request screen or Accessibility access and do not prove real source minimization/Spaces, physical monitor removal or TCC permission lifecycle acceptance. The manual checklist below still applies.

### Update cancellation and package acceptance

The pinned MyGo installer previously continued to replace the app when cancellation arrived in the progress callback for the last downloaded byte. A small patch adds cancellation checks after downloading, after extraction, and after delta application, immediately before replacement. Once the atomic replacement begins, it is allowed to finish rather than reporting cancellation after already changing the app. The wrapper checks the exact upstream version and source SHA-256 before generating the overlay; a changed upstream source is an error, not a best-effort patch.

The opt-in `fuwa_update_qa` program in `scripts/qa/updater` uses the actual MyGo `Updater.Check` and `Update.Install`. It creates a temporary app, a loopback-only update server, and a fresh Ed25519 test key in memory. It checks a valid installation and relaunch, same-length archive tampering, cancellation during download, cancellation at the last byte, offline failure, unchanged original bytes on rejection and cleanup of staging files. On macOS it exercises the `.app` replacement path. It never uses the owner's private key, contacts the production feed, or touches an installed Fuwa app. This does not establish trust continuity with a future owner-signed release.

CI runs tests and native QA on `macos-15` (arm64) and `macos-15-intel` (x86_64). Each artifact includes its exact reviewed head, tree, toolchain, overlay metadata, test logs, package verification and SHA-256. The archive is extracted again before signature verification and startup. Minimum macOS version inspection verifies the load-command contract; it is not a physical macOS 14 acceptance run.

### Explicit differences from the stable app

- The app identity/name/settings are isolated to protect stable installations. Preferences and pins are not imported.
- Main and controls use MyGo's native renderer; the menu bar uses a native menu rather than the SwiftUI popover.
- Shortcut customization accepts an accelerator string rather than a key-capture control.
- Download, verification and installation are one explicit cancellable action rather than separate Sparkle staging screens. There are no background checks.
- Public AX matching is deliberately conservative; indistinguishable candidates fail rather than choosing one.
- Captures target 30 fps. Live and frozen images now use the original Swift implementation's 4,000,000-pixel budget, with an 8192-pixel side limit. The earlier rewrite's 16-megapixel ceiling was removed to restore that resource bound. Pixels remain in native memory; CPU/memory performance has not been benchmarked.

### Manual acceptance before claiming parity

1. Run only the isolated preview. Reject the first Screen Recording prompt and confirm no other window is selected; approve later and pin again. No Accessibility prompt should appear until Go to original.
2. Pin two app windows and Finder Quick Look; interact with the app underneath. Exercise all pin actions from both management surfaces and the independent controls.
3. Freeze, move/resize/close the source, resume where possible; close a source during start and during resume. Confirm no stale stream resurrects a removed pin or substitutes another source.
4. Move sources between 1x/2x displays, a display left of the primary, full-screen Spaces and disconnected displays. Check geometry and image aspect ratio.
5. Lock/sleep/switch sessions/revoke recording permission while both live and frozen pins exist. Confirm pixels disappear immediately and never automatically return.
6. Change shortcuts into a known conflict; the previous binding must remain. Toggle Dock visibility with main open/closed and check login registration/approval/rejection.
7. Exercise English/Chinese and keyboard/VoiceOver navigation, then run the universal binary on a physical Intel Mac.
8. Only after an owner-signed MyGo release exists: valid update, cancellation, modified archive/signature, offline check and app unwritable. The temporary-key CI round trip does not replace this trust-continuity check. The current MyGo tagged-feed resolver ignores GitHub draft/prerelease releases; plan the future channel explicitly before publishing. No unsigned fallback or Swift-package installation is acceptable.

The screenshot artifact is a rendering of the implemented view with fixtures, not proof of capture acceptance. CI must not auto-grant permissions, disable protections, access signing secrets, publish releases, or overwrite `/Applications/Fuwa.app`.

## 中文

本分支以 Go/MyGo 和全新的 macOS Objective-C 适配层替换 Swift 应用及构建，保留原图标、MIT 许可、发布历史与历史设计文档。不发布版本，不改正式版应用。

当前预览版为 `1.1.0-mygo.2`，独立应用构建号为 `2`。代码已实现精确窗口选择及 Quick Look 例外、8 个独立穿透镜像、冻结/恢复/失败重试/关闭源处理、多屏位置及尺寸追踪、保守的公开 AX 原窗口定位、主界面/菜单栏/可搜索选择器/控制面板、自定义快捷键回滚、Dock/登录项/中英文设置、隐私清理和手动验签更新。

**差异须明确：** 预览应用标识与设置独立；菜单栏采用原生菜单而不是 SwiftUI 弹层；快捷键通过组合键文本设置而非录制；下载、验证、安装合为一次可取消操作；AX 匹配更保守。捕获目标 30 fps，实时与冻结图像均恢复原 Swift 版的 4,000,000 像素预算，并保留单边 8192 限制；此前重写版的 1600 万级上限已调整。尚未测量 CPU/内存收益。

**真机验收尚需完成：** 授权拒绝/批准、真实镜像与 Quick Look、冻结和重连竞态、多显示器/Retina/全屏 Spaces、锁屏与权限撤销的即时清屏、与其他应用的快捷键冲突、Dock 与登录项审批、中英文及 VoiceOver、实体 Intel Mac、以及存在签名 MyGo 发布后的完整更新/取消/篡改拒绝流程。

原生界面截图使用测试数据，并非真实捕获已验收的证明。CI 不得自动授权、关闭保护、读取签名私钥、发布版本或覆盖 `/Applications/Fuwa.app`。旧正式版更新源不得接入预览版。

**本次补齐的行为：** Fuwa 激活时管理窗口高于浮动镜像，失去激活后恢复普通层级；控制面板随镜像定位，并在失焦、应用失去激活或按 Escape 后收起；冻结镜像在屏幕移除后回到剩余可见区域，不移动原窗口；源窗口仅变为屏幕外时不再强制冻结；启动快捷键冲突时尝试默认组合键，失效的原组合键可以重试；切换语言会刷新应用菜单、托盘及已有控制面板。

**本轮继续补齐：** 目标选择结果只消费一次，准备失败后再次点击不会改选后方窗口；已经确定的目标在授权期间换 Space 或缩小也不重新筛选。选择器支持按应用名/标题搜索，失败项目可直接重试，连接中的无效动作禁用，满 8 项仍能取消当前目标。恢复白底墨色外观，补权限设置入口及输入框辅助功能名称。窗口列表临时返回失败不会误判所有源关闭；移动时共享追踪切到 100ms，稳定后为 250ms。异步启动/尺寸更新期间取消会等待对应流完成清理，迟到帧不能重新显示；首帧过渡、独立冻结和源窗口 Retina 倍率也有专门处理。锁屏、屏幕/系统睡眠、会话切换和撤权同时清除实时、等待中及冻结图像。

**更新取消修复：** 已用真实 MyGo 安装器复现“最后一个字节下载完后取消仍替换应用”。补丁在下载、解包及增量应用后、真正替换前检查取消；替换事务一旦开始会完成，不会在已换包后误报取消。构建入口先校验固定版本与上游源码 SHA-256，再通过 overlay 应用补丁，不改共享模块缓存。`fuwa_update_qa` 使用临时应用、本机回环服务和内存中新建的 Ed25519 测试密钥，验证真实安装/重启、同长度篡改拒绝、下载中及末字节取消、离线失败、失败后原包不变与暂存目录清理。它不使用现有私钥、不访问正式更新源、不触碰已安装应用，也不能替代未来正式签名身份的更新验收。

**构建验收：** CI 在 arm64 和 x86_64 macOS 环境分别运行，记录精确提交/代码树、工具链和补丁证据；对最终 ZIP 重新解压、校验两片 Mach-O、最低系统版本与签名，并启动解压后的应用。原预览包的实际最低版本为 15.0、却声明 14.0；现已统一编译和链接目标，并用产物检查防止回归。二进制最低版本检查不等于已经在实体 macOS 14 上完成验收。MyGo 当前的标签更新源忽略 GitHub draft/prerelease，未来发布前需要明确更新渠道。

除 race/单元测试与 vet 外，`fuwa_parity_qa` 构建标签提供只用本进程 MyGo 测试窗口和合成像素缓冲区的原生检查，执行命令见英文段落。它验证实际 AppKit 层级、父子窗口、焦点/失活、菜单语言和系统快捷键注册，并通过可延迟完成的模拟流验证生产捕获生命周期、独立冻结、首帧过渡、旧帧拒绝、倍率、像素预算和隐私清理。断屏用较小的测试显示区域模拟，不改系统显示设置。QA 检查代码不进入普通构建，不启动 ScreenCaptureKit，不请求录屏或辅助功能权限，也不能替代真实捕获、最小化/Spaces、物理拔屏及权限生命周期验收。
