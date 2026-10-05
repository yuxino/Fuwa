# Contributing to the MyGo rewrite

This is `rewrite/mygo`, an experimental macOS branch. Do not merge or publish it without explicit review and the acceptance checks in [docs/mygo-rewrite.md](docs/mygo-rewrite.md).

Use Go 1.27.1+ and Xcode Command Line Tools. Run `go mod tidy`, `gofmt -w main_darwin.go internal/`, `go test -race ./...`, `go vet ./...`, then `./scripts/build-mygo.sh` on macOS. Set `FUWA_SCREENSHOTS` to an absolute output folder to render native UI fixtures. Pure policy tests can run in `internal/core` with `GO111MODULE=off go test -race` where a suitable Go toolchain is available.

Keep UI/state in Go and MyGo. The native adapter is only for missing platform APIs; never reintroduce the Swift app as a helper. All native entry points and app state are main-thread confined. Preserve exact source identity, bounded frame queues, independent frozen pixels, and synchronous privacy teardown before asynchronous stream cleanup. Never log or persist captured content.

Updates must stay manual, use the owner-controlled public Ed25519 key, and target the isolated MyGo feed. Do not add signing secrets or publish from preview CI. Follow AGENTS.md for English-first / Simplified-Chinese release notes. Keep README.md and README_ZH.md aligned and distinguish compilation, fixture tests and real-device acceptance.

## 中文

这是独立实验分支，不得未经明确审阅及真机验收就合并或发布。使用 Go 1.27.1+ 与 Xcode Command Line Tools，运行上述格式检查、测试和构建命令。界面与状态留在 Go/MyGo，原生层只补充框架尚未提供的平台接口。必须保留精确窗口身份、限量帧队列、独立冻结画面及先清屏后异步停止的隐私边界。不记录或持久化捕获内容，不接入正式版更新源，不在预览 CI 使用签名私钥或发布版本。
