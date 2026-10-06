# MyGo updater cancellation patch

This directory contains a small MIT-licensed patch to the pinned upstream updater:

- Repository: [egoist/mygo](https://github.com/egoist/mygo).
- Commit: [`bfb878510ce3e0f7ac684090137d5147ed4421ff`](https://github.com/egoist/mygo/commit/bfb878510ce3e0f7ac684090137d5147ed4421ff).
- Source: [`updater.go`](https://github.com/egoist/mygo/blob/bfb878510ce3e0f7ac684090137d5147ed4421ff/updater.go).
- Module version: `v0.0.0-20261005151153-bfb878510ce3`.
- Original source SHA-256: `c00462ba30aca5f74c80d962f261a9d1c740d76b7cd61b5a974de80fb80a4141`.
- Patched source SHA-256: `e3ccb6fb3cc46982a7e495f7d32af48edf75832462ed47c55cdd646a9091ad1d`.

## Why it is needed

The upstream updater can finish a successful HTTP read even when its progress callback cancels the context on the final byte. It then extracts and replaces the application without checking the cancelled context. Archive extraction and delta application also run synchronously without accepting a context, so cancellation during those operations needs to be checked before replacement.

The patch adds cancellation checks before installation starts, after each download, after full archive extraction, and after delta application before the installed app is replaced. Cancellation returns the original context error, so `errors.Is(err, context.Canceled)` continues to work. Temporary staging files are removed by the upstream cleanup. Cancellation during a failed delta attempt stops the operation rather than initiating a full archive download.

The replacement transaction itself completes once it starts. The patch does not report cancellation after changing the installed app, modify signature verification, accept unsigned archives, or introduce another update feed. Extraction and delta application are not interrupted halfway through; a cancellation received during either is honored when that staging operation returns, before replacement begins.

## Build integration

Use `scripts/go-mygo.sh` for Fuwa's Go builds and tests. It prepares the overlay and passes it through `GOFLAGS`, including to the temporary updater QA child build. The lower-level interface is:

```sh
python3 scripts/prepare-mygo-overlay.py
```

The command prints the complete `-modfile=... -overlay=...` argument fragment to standard output, ready to append to `GOFLAGS`. Both flags are required. The default output directory is `build/mygo-overlay`. It contains temporary `fuwa.mod` and `fuwa.sum` files, the replacement source as `updater.go.patched`, the overlay map, `metadata.json` with source and patch hashes, and the upstream MIT license. Keeping the replacement file's suffix different from `.go` prevents Go from treating the generated build directory as another Fuwa package.

Go prohibits overlays that replace files inside its module cache. The script therefore copies the pinned MyGo source into a hidden directory under `build/mygo-overlay/.modules`, verifies the entire copied tree, and selects it through the temporary modfile. The overlay replaces only `updater.go` in that copy. Copies are named by version and source fingerprint and published atomically, so concurrent preparation does not modify source used by another build. A repository-relative replacement path keeps local home directory names out of executable build information. Neither the committed `go.mod`/`go.sum` nor the global module cache is changed.

`--go` selects the Go executable, `--output` selects a different output directory, and `--module-dir` permits an explicit upstream source directory for controlled QA. The source and license checks also apply to that explicit directory.

The preparation script verifies the pinned module version, original source SHA-256, every patch hunk at its exact source position, patched source SHA-256, and MIT license. A mismatch is a build error. It uses Python's standard library and does not alter the global Go module cache or vendor the framework.

## Verification and maintenance

`scripts/qa/updater/main.go` exercises the actual MyGo `Check` and `Install` APIs with generated signing keys and temporary fixture applications. Its `cancel-final-byte` case reproduces the upstream bug without this overlay and must leave the original installed tree unchanged with the overlay. The same suite checks ordinary successful installation, signature tampering, cancellation during download, and offline behavior.

When updating MyGo, inspect the upstream updater first. Remove this overlay if the upstream release already contains the fix. Otherwise review the new source and patch together, update the pinned version and both source hashes in `scripts/prepare-mygo-overlay.py`, then rerun updater acceptance. Do not relax the hash or patch-position checks to accommodate an upgrade.

The original copyright notice and license are retained in `MyGo-LICENSE`; the patch is distributed under those same MIT terms.

## 中文

锁定的 MyGo 更新器在下载最后一批字节的回调中收到取消时，HTTP 读取仍可能成功，随后继续解包并替换应用。补丁在下载、解包和增量包处理之后、替换应用之前检查取消状态；收到取消后保留原安装，返回可被 `errors.Is` 识别的 context 错误。真正开始替换后的事务会继续完成，避免出现已经换包却报告取消的结果。

构建通过临时 modfile 指向校验后的 MyGo 源码副本，再用 Go overlay 只替换这一份源文件。这是因为 Go 禁止直接 overlay 模块缓存中的文件。所有生成文件放在 `build/mygo-overlay`，不改仓库原有 `go.mod`/`go.sum` 或全局模块缓存，也不会把整个框架提交到仓库。源码副本采用版本和目录指纹命名、原子生成，复用时会核对完整内容；构建信息使用仓库内相对路径，避免把本机用户目录写入交付包。脚本严格核对原始与修改后的 SHA-256、补丁位置、依赖版本和 MIT 许可，任一不符都会停止构建。升级 MyGo 时需要重新审查，或在上游已修复后删除此补丁。真实更新器 QA 使用临时应用和临时测试密钥，覆盖成功更新、篡改拒绝、下载中取消、最后字节取消和离线失败。
