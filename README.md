<div align="center">
  <img src="docs/images/app-icon.png" width="112" alt="Fuwa 应用图标">
  <h1>Fuwa</h1>
  <p>macOS 窗口置顶工具，把需要的窗口固定在最前面。</p>
  <p>
    <a href="https://fuwa.yuxino.cn"><strong>官方网站</strong></a>
    · <a href="https://github.com/yuxino/fuwa/releases"><strong>查看发布版本</strong></a>
  </p>
  <p>
    <strong>简体中文</strong>
    · <a href="README_ZH_TW.md">繁體中文</a>
    · <a href="README_EN.md">English</a>
    · <a href="README_JA.md">日本語</a>
    · <a href="README_KO.md">한국어</a>
    · <a href="README_FR.md">Français</a>
    · <a href="README_DE.md">Deutsch</a>
  </p>
  <p>
    <a href="https://github.com/yuxino/fuwa/releases/latest"><img src="https://img.shields.io/github/v/release/yuxino/fuwa?style=flat&amp;logo=github&amp;logoColor=white" alt="最新版本"></a>
    <a href="https://github.com/yuxino/fuwa/actions/workflows/ci.yml?query=branch%3Amain"><img src="https://img.shields.io/github/actions/workflow/status/yuxino/fuwa/ci.yml?style=flat&amp;logo=githubactions&amp;logoColor=white&amp;branch=main&amp;event=push&amp;label=CI" alt="main 分支 CI 状态"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=flat&amp;logo=opensourceinitiative&amp;logoColor=white" alt="MIT 许可证"></a>
    <a href="https://github.com/yuxino/fuwa/releases/latest"><img src="https://img.shields.io/badge/macOS-14%2B-555?style=flat&amp;logo=apple&amp;logoColor=white" alt="macOS 14+"></a>
  </p>
</div>

Fuwa 是 macOS 窗口置顶工具。把图片、文档或教程留在眼前，切换到其他应用也能继续查看。画面可以跟随原窗口，也可以作为独立参考窗放在顺手的位置。

## 使用

1. 启动 Fuwa，按使用指南开启屏幕录制权限。指南可以跳过，之后从侧栏重新打开。
2. 从带缩略图的列表中选择窗口，或把目标窗口置于前方，按 `⌥⌘P` 固定。
3. 从菜单栏管理画面，暂停或恢复播放；打开齿轮控件，将画面切换为独立参考窗。

## 功能

- 同时固定多个应用窗口或图片、文档的系统预览；暂停画面时，原窗口仍正常运行。
- 跟随原窗口的画面允许点击穿透；独立参考窗可移动、调整大小、选择局部画面，也可整理到各自屏幕的角落。
- 参考窗可调节不透明度，鼠标移入时恢复清晰显示；开启悬停放大后，旁边有足够空间时会显示更大的预览。
- 随时隐藏或恢复全部画面，也可在设置中开启“按住 ⌃⌥ 暂时隐藏画面”，松开后恢复先前的显示状态。此项默认关闭。
- 可自定义固定窗口与隐藏／恢复画面的快捷键。
- 界面支持简体中文、繁体中文、英语、日语、韩语、法语和德语，可跟随系统或手动切换。
- 每个置顶窗口默认保留原始清晰度。点击该窗口旁的齿轮，可单独调低清晰度以节省内存。
- 菜单栏提供常用操作，设置在主窗口中打开。可选择是否显示 Dock 图标，不影响已打开的窗口。
- 窗口画面和元数据只在本机处理，无上传、分析或遥测，也无需辅助功能权限。
- 用户可在设置中检查、下载并安装经过 Ed25519 签名验证的更新；不在后台自动检查或安装。

参考窗的尺寸、双击返回来源应用、显示规则等操作见[使用说明](docs/floating-reference.md)。

## 要求

- macOS 14 或更高版本；发行包包含 arm64（Apple 芯片）和 x86_64（Intel），Intel 真机验收仍待完成。
- 屏幕录制权限。在使用指南中主动授权或首次尝试固定时请求，启动时不会自动弹出权限请求。

## 安装

从 [GitHub Releases](https://github.com/yuxino/fuwa/releases) 下载 `Fuwa-<版本>.dmg`，打开后把 `Fuwa.app` 拖到旁边的 `Applications` 文件夹。每个公开包都附有 `.sha256` 校验文件：

```sh
cd ~/Downloads
shasum -a 256 -c "Fuwa-<版本>.dmg.sha256"
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

## 社区

[LINUX DO](https://linux.do) · 技术交流社区。

## 许可证

[MIT](LICENSE) © 2026 yuxino and Fuwa contributors
