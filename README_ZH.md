<div align="center">
  <img src="docs/images/app-icon.png" width="112" alt="Fuwa 应用图标">
  <h1>Fuwa</h1>
  <p>macOS 窗口置顶工具，把需要的窗口固定在最前面。</p>
  <p>
    <a href="https://fuwa.yuxino.cn"><strong>官方网站</strong></a>
    · <a href="https://github.com/yuxino/fuwa/releases"><strong>查看发布版本</strong></a>
    · <a href="README_EN.md"><strong>English</strong></a>
  </p>
  <p>
    <a href="https://github.com/yuxino/fuwa/releases/latest"><img src="https://img.shields.io/github/v/release/yuxino/fuwa?style=flat&amp;logo=github&amp;logoColor=white" alt="最新版本"></a>
    <a href="https://github.com/yuxino/fuwa/actions/workflows/ci.yml?query=branch%3Amain"><img src="https://img.shields.io/github/actions/workflow/status/yuxino/fuwa/ci.yml?style=flat&amp;logo=githubactions&amp;logoColor=white&amp;branch=main&amp;event=push&amp;label=CI" alt="main 分支 CI 状态"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=flat&amp;logo=opensourceinitiative&amp;logoColor=white" alt="MIT 许可证"></a>
    <a href="https://github.com/yuxino/fuwa/releases/latest"><img src="https://img.shields.io/badge/macOS-14%2B-555?style=flat&amp;logo=apple&amp;logoColor=white" alt="macOS 14+"></a>
  </p>
</div>

Fuwa 是 macOS 窗口置顶工具。把图片、文档或教程窗口固定在最前面，切换到其他应用也能继续查看。置顶画面不会挡住鼠标操作。

## 使用

1. 启动 Fuwa，把目标窗口置于前方。
2. 按 `⌥⌘P` 固定窗口。同一源窗口再次位于前方时，按快捷键即可取消。
3. 从菜单栏管理已固定的窗口，以及实时或冻结状态。

## 功能

- 同时固定多个窗口，支持冻结画面。
- 支持应用窗口，以及图片、文档的系统预览窗口。
- 可自定义快捷键。
- 界面支持简体中文、繁体中文、英语、日语、韩语、法语和德语，可跟随系统或手动切换。
- 可调整画面清晰度：400 万像素（默认）、900 万像素、1600 万像素或原生分辨率；提高上限可保留更多细节，也会使用更多内存。
- 可选择是否保留 Dock 图标。关闭后，仅在主窗口打开时显示图标，仍可从菜单栏打开 Fuwa。
- 镜像始终穿透鼠标；“回到原窗口”只会激活并抬升真实源窗口。
- 窗口画面和元数据只在本机处理，无上传、分析或遥测。
- 用户可在设置中检查、下载并安装经过 Ed25519 签名验证的更新；不在后台自动检查或安装。

## 要求

- macOS 14 或更高版本；发行包包含 arm64（Apple 芯片）和 x86_64（Intel），Intel 真机验收仍待完成。
- 屏幕录制权限，仅在第一次尝试固定时请求。
- 辅助功能权限为可选，仅在使用“回到原窗口”时请求；不开启也能置顶和冻结画面。

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

[隐私](PRIVACY.md) · [贡献](CONTRIBUTING.md) · [安全](SECURITY.md) · [独立实现说明](docs/independent-implementation.md)

## 许可证

[MIT](LICENSE) © 2026 yuxino and Fuwa contributors
