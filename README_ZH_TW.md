<div align="center">
  <img src="docs/images/app-icon.png" width="112" alt="Fuwa 應用程式圖示">
  <h1>Fuwa</h1>
  <p>macOS 視窗置頂工具，讓需要的視窗保持在最前方。</p>
  <p>
    <a href="https://fuwa.yuxino.cn"><strong>官方網站</strong></a>
    · <a href="https://github.com/yuxino/fuwa/releases"><strong>查看版本</strong></a>
  </p>
  <p>
    <a href="README.md">简体中文</a>
    · <strong>繁體中文</strong>
    · <a href="README_EN.md">English</a>
    · <a href="README_JA.md">日本語</a>
    · <a href="README_KO.md">한국어</a>
    · <a href="README_FR.md">Français</a>
    · <a href="README_DE.md">Deutsch</a>
  </p>
  <p>
    <a href="https://github.com/yuxino/fuwa/releases/latest"><img src="https://img.shields.io/github/v/release/yuxino/fuwa?style=flat&amp;logo=github&amp;logoColor=white" alt="最新版本"></a>
    <a href="https://github.com/yuxino/fuwa/actions/workflows/ci.yml?query=branch%3Amain"><img src="https://img.shields.io/github/actions/workflow/status/yuxino/fuwa/ci.yml?style=flat&amp;logo=githubactions&amp;logoColor=white&amp;branch=main&amp;event=push&amp;label=CI" alt="main 分支 CI 狀態"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=flat&amp;logo=opensourceinitiative&amp;logoColor=white" alt="MIT 授權條款"></a>
    <a href="https://github.com/yuxino/fuwa/releases/latest"><img src="https://img.shields.io/badge/macOS-14%2B-555?style=flat&amp;logo=apple&amp;logoColor=white" alt="macOS 14+"></a>
  </p>
</div>

Fuwa 是 macOS 視窗置頂工具。讓圖片、文件或教學視窗保持在最前方，切換到其他應用程式時也能繼續查看。置頂畫面允許滑鼠操作穿透。

## 使用

1. 啟動 Fuwa，將目標視窗移到最前方。
2. 按 `⌥⌘P` 固定視窗。同一來源視窗再次位於前方時，按快捷鍵即可取消固定。
3. 從選單列管理已固定的視窗，暫停或恢復即時畫面。

## 功能

- 同時固定多個視窗，支援暫停畫面，原始視窗仍正常運作。
- 支援應用程式視窗，以及圖片、文件的系統預覽視窗。
- 可自訂快捷鍵。
- 介面支援簡體中文、繁體中文、英語、日語、韓語、法語和德語，可跟隨系統或在設定中手動切換。
- 每個置頂視窗預設保留原始清晰度。點選該視窗旁的齒輪，可單獨降低清晰度以節省記憶體。
- 選單列直接提供固定視窗、選擇視窗和暫停畫面等操作，設定在主視窗中開啟。
- 可選擇是否顯示 Dock 圖示，開關只影響圖示，不關閉已開啟的視窗。
- 跟隨原始視窗的畫面允許點擊穿透；獨立參考視窗可單獨移動、調整大小或選擇局部畫面。
- 視窗畫面和中繼資料只在本機處理，不上傳，不進行分析或遙測。
- 可在設定中檢查、下載並安裝通過 Ed25519 簽章驗證的更新；不在背景自動檢查或安裝。

## 系統需求

Fuwa 1.2.0 的獨立參考視窗、局部畫面、隱藏／恢復和顯示規則，請見[使用說明（英語／簡體中文）](docs/floating-reference.md)。

- macOS 14 或更新版本；發行套件包含 arm64（Apple 晶片）和 x86_64（Intel），Intel 實機驗收仍待完成。
- 螢幕錄製權限，僅在第一次嘗試固定視窗時請求。

## 安裝

從 [GitHub Releases](https://github.com/yuxino/fuwa/releases) 下載 `Fuwa-<version>.dmg`，開啟後將 `Fuwa.app` 拖到旁邊的 `Applications` 資料夾。每個公開套件都附有 `.sha256` 校驗檔案：

```sh
cd ~/Downloads
shasum -a 256 -c "Fuwa-<version>.dmg.sha256"
```

請將 `<version>` 替換為實際版本號。v0.1.4 及更早版本需要手動安裝 v0.1.5 或更新版本一次，之後可在 Fuwa 設定中點選「檢查更新」。應用程式只接受固定的 GitHub feed 和通過內建公開金鑰驗證的安裝套件；驗證失敗時不會改用未簽章的安裝方式。

macOS 套件使用專案維護的本機簽章身分，未使用 Apple Developer ID 簽章或 Apple 公證。如果 macOS 阻止開啟，請核對來源和 SHA-256，並參考 [Apple 官方說明](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac)，不要關閉系統安全功能。

## 從原始碼建置

Fuwa 使用 Swift、SwiftUI/AppKit、ScreenCaptureKit 和 Sparkle。

```sh
git clone https://github.com/yuxino/fuwa.git
cd fuwa
./scripts/setup-local-signing.sh
./scripts/install-app.sh
```

[隱私](PRIVACY.md) · [貢獻](CONTRIBUTING.md) · [安全](SECURITY.md) · [獨立實作說明](docs/independent-implementation.md)

## 授權條款

[MIT](LICENSE) © 2026 yuxino and Fuwa contributors
