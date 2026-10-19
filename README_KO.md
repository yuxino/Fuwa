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

Fuwa는 macOS용 창 고정 앱입니다. 이미지, 문서, 튜토리얼을 곁에 두고 다른 앱에서 작업하면서 계속 볼 수 있습니다. 화면이 원본 창을 따라가게 하거나, 독립된 참조 창으로 원하는 곳에 둘 수 있습니다.

## 사용 방법

1. Fuwa를 실행하고 사용 안내에 따라 화면 기록 권한을 허용합니다. 안내는 건너뛰고 나중에 사이드바에서 다시 열 수 있습니다.
2. 썸네일이 있는 목록에서 창을 선택하거나, 대상 창을 맨 앞으로 가져온 뒤 `⌥⌘P`를 눌러 고정합니다.
3. 메뉴 막대에서 화면을 관리하고 일시 정지하거나 다시 재생합니다. 톱니바퀴 제어판에서 독립된 참조 창으로 전환할 수 있습니다.

## 기능

- 여러 앱 창이나 이미지·문서의 시스템 미리보기를 고정할 수 있습니다. 화면을 일시 정지해도 원본 창은 계속 작동합니다.
- 원본 창을 따라가는 화면은 클릭을 통과시킵니다. 독립된 참조 창은 이동, 크기 조절, 영역 선택이 가능하며 각 화면의 모서리에 정렬할 수 있습니다.
- 참조 창의 불투명도를 조절할 수 있으며 포인터를 올리면 완전히 불투명해집니다. 마우스를 올릴 때 확대하는 설정을 켜면 옆에 공간이 충분할 때 더 큰 미리보기가 나타납니다.
- 모든 화면을 한 번에 숨기거나 다시 표시할 수 있습니다. 설정에서 ‘⌃⌥를 누르는 동안 화면 숨기기’를 켜면 키를 놓을 때 이전 표시 상태로 돌아갑니다. 이 설정은 기본적으로 꺼져 있습니다.
- 창 고정과 화면 숨기기·표시하기의 단축키를 각각 변경할 수 있습니다.
- 인터페이스는 중국어 간체, 중국어 번체, 영어, 일본어, 한국어, 프랑스어, 독일어를 지원합니다. 시스템 언어를 따르거나 설정에서 직접 선택할 수 있습니다.
- 각 창은 원본 화질로 고정됩니다. 창 옆의 톱니바퀴를 클릭하여 해당 창의 화질을 낮추고 메모리 사용량을 줄일 수 있습니다.
- 자주 쓰는 동작은 메뉴 막대에서 실행하고 설정은 메인 창에서 엽니다. 열린 창을 닫지 않고 Dock 아이콘 표시 여부를 선택할 수 있습니다.
- 창의 화면과 메타데이터는 이 컴퓨터에서만 처리합니다. 업로드, 분석, 원격 측정은 하지 않으며 손쉬운 사용 권한도 필요하지 않습니다.
- 설정에서 업데이트를 확인·다운로드하고 Ed25519 서명을 검증한 후 설치할 수 있습니다. 백그라운드에서 자동으로 확인하거나 설치하지 않습니다.

참조 창 크기, 두 번 클릭하여 원본 앱으로 돌아가기, 표시 조건 등은 [사용 안내(영어·중국어 간체)](docs/floating-reference.md)를 참고하세요.

## 요구 사항

- macOS 14 이상. 배포 패키지는 arm64(Apple Silicon)와 x86_64(Intel)를 포함합니다. 실제 Intel Mac에서의 검증은 아직 완료되지 않았습니다.
- 화면 기록 권한. 사용 안내에서 허용을 선택하거나 처음 창 고정을 시도할 때 요청합니다. 앱을 실행하는 것만으로는 권한 요청이 표시되지 않습니다.

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
