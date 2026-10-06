# Fuwa · MyGo 重写版

使用 [egoist/mygo](https://github.com/egoist/mygo) 完整替换 Swift 应用的独立实验分支：**`rewrite/mygo`，不是正式版。** [English](README.md)

应用生命周期、原生 Go 界面、窗口、菜单、全局快捷键和更新由 MyGo 管理。新写的 Objective-C 适配层提供 ScreenCaptureKit、公开的辅助功能窗口匹配和登录项注册。没有网页前端，也不会把旧 Swift 应用作为辅助进程启动。

## 运行

需要 macOS 14+、Go 1.27.1+ 和 Xcode Command Line Tools：

```sh
git clone --branch rewrite/mygo https://github.com/yuxino/Fuwa.git Fuwa-MyGo
cd Fuwa-MyGo
go mod tidy
./scripts/go-mygo.sh test -race ./...
./scripts/build-mygo.sh
open 'build/Fuwa MyGo.app'
```

GitHub Actions 的 **MyGo rewrite** 工作流在 Apple Silicon 和 Intel macOS 环境分别运行。`Fuwa-MyGo-preview-arm64` 与 `Fuwa-MyGo-preview-amd64` 两个产物都包含 Universal 应用 ZIP、SHA-256、原生界面截图、测试记录及构建来源。CI 还会解压最终 ZIP，核对两种架构及最低 macOS 版本，验证解压后的签名，并启动这个实际交付的应用。截图使用本进程的测试窗口，**不能视为实时捕获已经验收的证据**。

应用名 **Fuwa MyGo**，标识 `app.yuxino.fuwa.mygo`，设置和权限与正式版独立。不覆盖、不迁移现有 Fuwa。预览包仅为临时签名，未做 Developer ID 签名或公证；不要关闭 Gatekeeper 或系统安全保护。

## 使用

切到目标窗口，按 **⌥⌘P** 置顶；同一原窗口再次按下则取消。镜像鼠标穿透，可从菜单栏、主窗口或独立控制面板管理。最多同时置顶 8 个窗口，支持冻结、恢复实时和跳转原窗口。原窗口关闭或捕获中断时，保留最后一帧。

**选择窗口**支持按应用名或窗口标题搜索。尚未收到第一帧就失败的项目，可以直接点**重试捕获**。关闭管理窗口或切到其他应用会清除之前准备的目标；请在目标窗口上使用快捷键，或重新从选择器选择。

设置包含自定义快捷键、Dock 显示、登录启动、跟随系统/英文/简体中文、权限状态及手动签名更新。关闭主窗口后菜单栏继续运行；关闭常驻 Dock 后，仅在主窗口打开时显示 Dock 图标。

仅在尝试置顶时请求录屏权限，仅在跳转原窗口时请求辅助功能权限。画面及窗口信息不落盘、不上传。睡眠、会话切换、锁屏及权限撤销都会清除置顶，唤醒后不会自动恢复。

## 验证边界

详见[功能及验收清单](docs/mygo-rewrite.md)。CI 覆盖两种 CPU 架构、应用自己的原生窗口、合成捕获帧及临时更新应用。真实录屏授权、ScreenCaptureKit 捕获、Quick Look、Spaces、物理显示器/Retina 切换、VoiceOver、登录项批准和实体 Intel 硬件仍需交互验收，尚未测量 CPU/内存收益。

手动更新使用 MyGo 的 Ed25519 验证与安装能力，沿用已有的**公开**验证密钥，但只读取独立的 `mygo-v` 发布前缀，不读取正式版 Swift/Sparkle 更新源。本分支及 CI 不发布版本；有签名的 MyGo 发布前，检查更新会明确提示尚未发布。下载与安装合并为一次由用户发起、可取消的操作，不沿用 Sparkle 分离的下载暂存界面。

## 结构

`internal/core`：窗口选择、身份匹配、状态机、原子设置及测试。`internal/native`：新写的 macOS 适配层、限量最新帧队列及独立冻结图像。`internal/view`：MyGo 原生界面及无窗口测试。`main_darwin.go`：应用调度、共享追踪、隐私生命周期、菜单、快捷键和手动更新。

请使用仓库内的构建脚本：MyGo CLI 强制关闭 cgo，而本应用的 ScreenCaptureKit 适配层需要 cgo。MyGo 固定在 `bfb878510ce3e0f7ac684090137d5147ed4421ff`；随仓库提供的 Go 包装脚本会校验上游源码哈希，再通过构建 overlay 应用很小的更新取消补丁，不改动共享模块缓存。维护方式见[补丁说明](patches/README.md)。构建及更新验收请使用这个入口，确保包含已经验证的取消处理。

`docs/` 保留旧版历史文档，不代表此分支的构建方式。稳定版源码仍在 `main` 和 Git 历史中。

MIT · yuxino 和 Fuwa 贡献者
