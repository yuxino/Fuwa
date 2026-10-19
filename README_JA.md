<div align="center">
  <img src="docs/images/app-icon.png" width="112" alt="Fuwa アプリアイコン">
  <h1>Fuwa</h1>
  <p>Mac のウインドウを最前面に固定。</p>
  <p>
    <a href="https://fuwa.yuxino.cn"><strong>公式サイト</strong></a>
    · <a href="https://github.com/yuxino/fuwa/releases"><strong>リリース一覧</strong></a>
  </p>
  <p>
    <a href="README.md">简体中文</a>
    · <a href="README_ZH_TW.md">繁體中文</a>
    · <a href="README_EN.md">English</a>
    · <strong>日本語</strong>
    · <a href="README_KO.md">한국어</a>
    · <a href="README_FR.md">Français</a>
    · <a href="README_DE.md">Deutsch</a>
  </p>
  <p>
    <a href="https://github.com/yuxino/fuwa/releases/latest"><img src="https://img.shields.io/github/v/release/yuxino/fuwa?style=flat&amp;logo=github&amp;logoColor=white" alt="最新バージョン"></a>
    <a href="https://github.com/yuxino/fuwa/actions/workflows/ci.yml?query=branch%3Amain"><img src="https://img.shields.io/github/actions/workflow/status/yuxino/fuwa/ci.yml?style=flat&amp;logo=githubactions&amp;logoColor=white&amp;branch=main&amp;event=push&amp;label=CI" alt="main ブランチの CI ステータス"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=flat&amp;logo=opensourceinitiative&amp;logoColor=white" alt="MIT ライセンス"></a>
    <a href="https://github.com/yuxino/fuwa/releases/latest"><img src="https://img.shields.io/badge/macOS-14%2B-555?style=flat&amp;logo=apple&amp;logoColor=white" alt="macOS 14+"></a>
  </p>
</div>

Fuwa は macOS 用のウインドウ固定アプリです。画像、書類、チュートリアルを手元に表示して、別のアプリで作業しながら参照できます。映像を元のウインドウに追従させることも、独立した参照ウインドウとして好きな場所に置くこともできます。

## 使い方

1. Fuwa を起動し、「使い方」に沿って画面収録を許可します。ガイドはスキップでき、後からサイドバーで開けます。
2. サムネイル付きの一覧からウインドウを選ぶか、対象のウインドウを最前面にして `⌥⌘P` で固定します。
3. メニューバーから映像を管理し、一時停止・再開できます。歯車の操作パネルで独立した参照ウインドウに切り替えられます。

## 機能

- 複数のアプリウインドウや、画像・書類のシステムプレビューを固定できます。映像を一時停止しても、元のウインドウは動作し続けます。
- 元のウインドウに追従する表示はクリックを通します。独立した参照ウインドウは移動・サイズ変更・範囲選択ができ、それぞれの画面の隅に整列できます。
- 参照ウインドウの不透明度を調整でき、ポインタを重ねると完全に不透明になります。ホバーでの拡大を有効にすると、隣に十分な空きがある場合に大きなプレビューを表示します。
- すべての映像をまとめて非表示・再表示できます。設定で「⌃⌥ を押している間、映像を隠す」を有効にすると、キーを離したときに元の表示状態に戻ります。この設定は初期状態ではオフです。
- 固定用と、映像の非表示・再表示用のショートカットを変更できます。
- 表示言語は簡体字中国語、繁体字中国語、英語、日本語、韓国語、フランス語、ドイツ語に対応。システムの言語に合わせるか、設定で選択できます。
- 各ウインドウは元の画質で固定されます。横の歯車から個別に画質を下げ、メモリ使用量を抑えられます。
- よく使う操作はメニューバーから利用でき、設定はメインウインドウで開きます。開いているウインドウを閉じずに Dock アイコンの表示を切り替えられます。
- ウインドウの映像とメタデータはこの Mac 内で処理されます。アップロード、分析、テレメトリーは行わず、アクセシビリティ権限も不要です。
- 設定から更新を確認・ダウンロードし、Ed25519 署名の検証後にインストールできます。バックグラウンドでの自動確認や自動インストールは行いません。

参照ウインドウのサイズ、ダブルクリックで元のアプリに戻る操作、表示条件などは、[使い方ガイド（英語・簡体字中国語）](docs/floating-reference.md)をご覧ください。

## 動作要件

- macOS 14 以降。配布パッケージには arm64（Apple シリコン）と x86_64（Intel）が含まれます。Intel Mac 実機での動作検証は未完了です。
- 画面収録の権限。「使い方」で許可を選んだとき、または初めて固定を試みたときに要求します。起動だけでは権限の要求は表示しません。

## インストール

[GitHub Releases](https://github.com/yuxino/fuwa/releases) から `Fuwa-<version>.dmg` をダウンロードして開き、`Fuwa.app` を隣の `Applications` フォルダへドラッグしてください。各公開パッケージには `.sha256` チェックサムファイルが付属します。

```sh
cd ~/Downloads
shasum -a 256 -c "Fuwa-<version>.dmg.sha256"
```

`<version>` を実際のバージョン番号に置き換えてください。v0.1.4 以前は、一度手動で v0.1.5 以降に更新する必要があります。その後は Fuwa の設定で「更新を確認」を選べます。アプリは固定の GitHub フィードと、内蔵の公開鍵で検証されたパッケージのみを受け付けます。検証に失敗した場合、未署名のパッケージはインストールしません。

macOS パッケージにはプロジェクトが管理するローカルの署名 ID を使用しており、Apple Developer ID による署名や Apple の公証は行っていません。macOS によって起動がブロックされた場合は、配布元と SHA-256 を確認し、[Apple の案内](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac)に従ってください。システムのセキュリティ機能は無効にしないでください。

## ソースからビルド

Fuwa は Swift、SwiftUI/AppKit、ScreenCaptureKit、Sparkle を使用しています。

```sh
git clone https://github.com/yuxino/fuwa.git
cd fuwa
./scripts/setup-local-signing.sh
./scripts/install-app.sh
```

[プライバシー](PRIVACY.md) · [貢献](CONTRIBUTING.md) · [セキュリティ](SECURITY.md) · [独立した実装について](docs/independent-implementation.md)

## ライセンス

[MIT](LICENSE) © 2026 yuxino and Fuwa contributors
