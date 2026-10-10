<div align="center">
  <img src="docs/images/app-icon.png" width="112" alt="Fuwa 앱 아이콘">
  <h1>Fuwa</h1>
  <p>Mac의 창을 항상 맨 위에 고정하세요.</p>
  <p>
    <a href="https://fuwa.yuxino.cn"><strong>공식 웹사이트</strong></a>
    · <a href="https://github.com/yuxino/fuwa/releases"><strong>릴리스 보기</strong></a>
  </p>
  <p>
    <a href="README.md">简体中文</a>
    · <a href="README_ZH_TW.md">繁體中文</a>
    · <a href="README_EN.md">English</a>
    · <a href="README_JA.md">日本語</a>
    · <strong>한국어</strong>
    · <a href="README_FR.md">Français</a>
    · <a href="README_DE.md">Deutsch</a>
  </p>
  <p>
    <a href="https://github.com/yuxino/fuwa/releases/latest"><img src="https://img.shields.io/github/v/release/yuxino/fuwa?style=flat&amp;logo=github&amp;logoColor=white" alt="최신 버전"></a>
    <a href="https://github.com/yuxino/fuwa/actions/workflows/ci.yml?query=branch%3Amain"><img src="https://img.shields.io/github/actions/workflow/status/yuxino/fuwa/ci.yml?style=flat&amp;logo=githubactions&amp;logoColor=white&amp;branch=main&amp;event=push&amp;label=CI" alt="main 브랜치 CI 상태"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=flat&amp;logo=opensourceinitiative&amp;logoColor=white" alt="MIT 라이선스"></a>
    <a href="https://github.com/yuxino/fuwa/releases/latest"><img src="https://img.shields.io/badge/macOS-14%2B-555?style=flat&amp;logo=apple&amp;logoColor=white" alt="macOS 14+"></a>
  </p>
</div>

Fuwa는 macOS용 창 고정 앱입니다. 이미지, 문서, 튜토리얼 창의 실시간 화면을 맨 위에 표시하여 다른 앱에서 작업하면서 계속 볼 수 있습니다. 고정된 화면을 통과해 아래에 있는 앱을 클릭할 수 있습니다.

## 사용 방법

1. Fuwa를 실행하고 대상 창을 맨 앞으로 가져옵니다.
2. `⌥⌘P`를 눌러 고정합니다. 같은 원본 창이 맨 앞에 있을 때 단축키를 다시 누르면 고정이 해제됩니다.
3. 메뉴 막대에서 고정된 창을 관리하고 화면을 일시 정지하거나 다시 재생합니다.

## 기능

- 여러 창을 동시에 고정할 수 있습니다. 화면을 일시 정지해도 원본 창은 계속 작동합니다.
- 앱 창과 이미지·문서의 시스템 미리보기 창을 지원합니다.
- 키보드 단축키를 변경할 수 있습니다.
- 인터페이스는 중국어 간체, 중국어 번체, 영어, 일본어, 한국어, 프랑스어, 독일어를 지원합니다. 시스템 언어를 따르거나 설정에서 직접 선택할 수 있습니다.
- 각 창은 원본 화질로 고정됩니다. 창 옆의 톱니바퀴를 클릭하여 해당 창의 화질을 낮추고 메모리 사용량을 줄일 수 있습니다.
- 메뉴 막대에서 창을 고정·선택하거나 화면을 일시 정지할 수 있습니다. 설정은 메인 창에서 열립니다.
- Dock 아이콘 표시 여부를 선택할 수 있습니다. 이 설정은 아이콘만 바꾸며 열려 있는 창을 닫지 않습니다.
- 원본 창을 따라가는 화면은 클릭을 통과시킵니다. 독립된 참조 창은 따로 이동하거나 크기를 조절하고 일부 영역을 선택할 수 있습니다.
- 창의 화면과 메타데이터는 이 컴퓨터에서만 처리합니다. 업로드, 분석, 원격 측정은 하지 않습니다.
- 설정에서 업데이트를 확인·다운로드하고 Ed25519 서명을 검증한 후 설치할 수 있습니다. 백그라운드에서 자동으로 확인하거나 설치하지 않습니다.

## 요구 사항

Fuwa 1.2.0의 독립된 참조 창, 영역 선택, 숨기기·표시하기, 표시 조건은 [사용 안내(영어·중국어 간체)](docs/floating-reference.md)를 참고하세요.

- macOS 14 이상. 배포 패키지는 arm64(Apple Silicon)와 x86_64(Intel)를 포함합니다. 실제 Intel Mac에서의 검증은 아직 완료되지 않았습니다.
- 화면 기록 권한. 처음 창 고정을 시도할 때만 요청합니다.

## 설치

[GitHub Releases](https://github.com/yuxino/fuwa/releases)에서 `Fuwa-<version>.dmg`를 다운로드하여 연 뒤, `Fuwa.app`을 옆의 `Applications` 폴더로 드래그하세요. 모든 공개 패키지에는 `.sha256` 체크섬 파일이 함께 제공됩니다.

```sh
cd ~/Downloads
shasum -a 256 -c "Fuwa-<version>.dmg.sha256"
```

`<version>`을 실제 버전 번호로 바꾸세요. v0.1.4 이하에서는 먼저 v0.1.5 이상으로 한 번 수동 업데이트해야 합니다. 이후에는 Fuwa 설정에서 “업데이트 확인”을 선택할 수 있습니다. 앱은 지정된 GitHub 피드와 내장 공개 키로 검증된 패키지만 허용합니다. 검증에 실패하면 서명되지 않은 패키지를 설치하지 않습니다.

macOS 패키지는 프로젝트에서 관리하는 로컬 서명 ID를 사용하며, Apple Developer ID 서명이나 Apple 공증을 받지 않았습니다. macOS가 실행을 차단하면 배포 출처와 SHA-256을 확인하고 [Apple 안내](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac)를 따르세요. 시스템 보안 기능을 끄지 마세요.

## 소스에서 빌드

Fuwa는 Swift, SwiftUI/AppKit, ScreenCaptureKit, Sparkle을 사용합니다.

```sh
git clone https://github.com/yuxino/fuwa.git
cd fuwa
./scripts/setup-local-signing.sh
./scripts/install-app.sh
```

[개인정보 보호](PRIVACY.md) · [기여](CONTRIBUTING.md) · [보안](SECURITY.md) · [독립 구현 안내](docs/independent-implementation.md)

## 라이선스

[MIT](LICENSE) © 2026 yuxino and Fuwa contributors
