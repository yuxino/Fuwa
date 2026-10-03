<div align="center">
  <img src="docs/images/app-icon.png" width="112" alt="Fuwa 应用图标">
  <h1>Fuwa</h1>
  <p>把需要的窗口留在最前面。</p>
  <p>
    <a href="https://fuwa.yuxino.cn"><strong>官方网站</strong></a>
    · <a href="https://github.com/yuxino/fuwa/releases"><strong>查看发布版本</strong></a>
    · <a href="README.md">English</a>
  </p>
  <p>
    <a href="https://github.com/yuxino/fuwa/releases/latest"><img src="https://img.shields.io/github/v/release/yuxino/fuwa?style=flat&amp;logo=github&amp;logoColor=white" alt="最新版本"></a>
    <a href="https://github.com/yuxino/fuwa/actions/workflows/ci.yml?query=branch%3Amain"><img src="https://img.shields.io/github/actions/workflow/status/yuxino/fuwa/ci.yml?style=flat&amp;logo=githubactions&amp;logoColor=white&amp;branch=main&amp;event=push&amp;label=CI" alt="main 分支 CI 状态"></a>
    <a href="LICENSE"><img src="https://img.shields.io/github/license/yuxino/fuwa?style=flat&amp;logo=opensourceinitiative&amp;logoColor=white" alt="MIT 许可证"></a>
  </p>
  <p>
    <a href="https://github.com/yuxino/fuwa/releases/latest"><img src="https://img.shields.io/badge/macOS-14%2B-555?style=flat&amp;logo=apple&amp;logoColor=white" alt="macOS 14+"></a>
  </p>
</div>

Fuwa 是 macOS 窗口置顶工具。把参考图片、文档或教程窗口放在最上方，回到其他应用后也能继续查看，不用反复切换窗口。置顶画面不拦截鼠标，你可以照常操作下方的应用。

## 完整功能演示

109 秒 · 4K · 60 帧 · 中文女声旁白。对照要求写拍摄清单、保留教程参数、同时查阅多份资料，以及看参考图写设计说明。

https://github.com/user-attachments/assets/8a218239-7d7c-4585-b7d6-33f57094e961

实际录制英文界面的 Fuwa 和公开示例文档，分别配有中英文旁白及字幕，访达控件保留系统中文。[录制说明](docs/demos/fuwa-full-tour-provenance.json)列出了录制副本的调整；也可以[观看英文版](README.md#full-feature-tour)。

## 使用

1. 启动 Fuwa，把目标窗口置于前方。
2. 按 `⌥⌘P` 固定窗口。同一源窗口再次位于前方时，按快捷键即可取消。
3. 从菜单栏管理已固定的窗口，以及实时或冻结状态。

## 功能

- 同时固定多个窗口，支持冻结画面。
- 支持应用窗口，以及图片、文档的系统预览窗口。
- 可自定义快捷键。
- 可选择是否保留 Dock 图标。关闭后，仅在主窗口打开时显示图标，仍可从菜单栏打开 Fuwa。
- 镜像始终穿透鼠标；“显示源窗口”只会激活并抬升真实源窗口。
- 窗口画面和元数据只在本机处理，无上传、分析或遥测。
- 用户可在设置中检查、下载并安装经过 Ed25519 签名验证的更新；不在后台自动检查或安装。

## 要求

- macOS 14 或更高版本；发行包包含 arm64（Apple 芯片）和 x86_64（Intel），Intel 真机验收仍待完成。
- 屏幕录制权限，仅在第一次尝试固定时请求。
- 辅助功能权限，仅在使用“显示源窗口”时请求。

## 安装

从 [GitHub Releases](https://github.com/yuxino/fuwa/releases) 下载 `Fuwa-<版本>.zip`，解压后把 `Fuwa.app` 移到 `/Applications`。每个公开包都附有 `.sha256` 校验文件：

```sh
cd ~/Downloads
shasum -a 256 -c "Fuwa-<版本>.zip.sha256"
```

请将 `<版本>` 替换为实际版本号。v0.1.4 及更早版本需要手动安装 v0.1.5 或更高版本一次，之后可在 Fuwa 设置中点击“检查更新”。应用只接受内置公钥验证通过的固定 GitHub feed 和安装包，失败时不会降级为未签名安装。

macOS 包使用项目维护的本地签名身份，未使用 Apple Developer ID 签名或 Apple 公证。如果 macOS 阻止打开，请核对来源和 SHA-256，并参考 [Apple 官方说明](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac)，不要关闭系统安全功能。

## 从源码构建

Fuwa 使用 Swift、SwiftUI/AppKit、ScreenCaptureKit 和 Sparkle。

```sh
git clone https://github.com/yuxino/fuwa.git
cd fuwa
./scripts/setup-local-signing.sh
./scripts/install-app.sh
```

## 平台范围

Fuwa 现只维护 macOS，不再开发或发布 Windows 版本。旧 Windows 发布文件和 Git 历史保留供存档，不代表仍受支持；后续 macOS 发布不再提供 Windows 安装包或更新 feed。

Fuwa 显示的是镜像，不会修改其他 App 的真实窗口层级，也不会绕过系统安全边界或受保护内容的限制。

[隐私](PRIVACY.md) · [贡献](CONTRIBUTING.md) · [安全](SECURITY.md) · [独立实现说明](docs/independent-implementation.md)

## 许可证

[MIT](LICENSE) © 2026 yuxino and Fuwa contributors
