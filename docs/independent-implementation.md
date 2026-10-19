# Independent Implementation Statement

Fuwa is an original, independently implemented macOS application distributed under the MIT License.

## Implementation sources

Fuwa's implementation is based on:

- Apple's public macOS frameworks and documentation, including ScreenCaptureKit, AppKit, Core Graphics, and Accessibility;
- original product design, architecture, source code, tests, copy, and visual assets created for this repository;
- behavior observed through ordinary use of macOS and the project's own test fixtures.

Fuwa does not use private WindowServer APIs, copy code from another application, inject code into other processes, or require changes to operating-system security.

## Relationship to Topit

Topit was considered only as a product-research reference for the broad user need of keeping window content visible. Topit is AGPL-licensed. No Topit source code has been copied, translated, adapted, linked, or incorporated into Fuwa. Fuwa also does not copy Topit's assets, text, tests, file structure, or non-public implementation details.

The projects have different implementation boundaries: Fuwa uses public ScreenCaptureKit APIs for macOS mirror panels. Source-reveal actions use public platform activation APIs; they do not inject input or modify the source window's actual level.

Topit and its authors do not sponsor, endorse, or participate in Fuwa.

## Other product research

PipNow's public website, complete two-minute promotional video, and ordinary
trial-app onboarding were also reviewed as product research for reference-window
conveniences. Fuwa's implementation, tests,
wording and controls were written for this repository. No PipNow source code,
assets or branding were used. Fuwa keeps its existing shortcuts and uses an
optional Control–Option hold gesture, without interactive input forwarding.

## Contributor requirements

Contributors must submit work they have the right to license under MIT. Do not consult and reproduce AGPL-covered implementation details for a Fuwa change, and do not paste third-party source, assets, copy, or tests into issues or pull requests. A contribution inspired by general product behavior must be implemented from public API documentation, independently written specifications, and original tests.

If provenance is uncertain, stop and discuss it with the maintainers before submitting the change.

---

## 独立实现说明

Fuwa 是一款原创、独立实现并以 MIT 许可证发布的 macOS 应用。其代码依据 Apple 公开 API 和文档、项目原创设计和测试编写。

Topit 仅用于了解“让窗口内容保持可见”这一通用产品需求。Topit 采用 AGPL 许可证；Fuwa 未复制、翻译、改写、链接或合并 Topit 的源码，也未复制其资产、文案、测试、文件结构或非公开实现细节。贡献者同样不得将这些内容带入 Fuwa。

Fuwa 在 macOS 通过公开 ScreenCaptureKit API 创建自有镜像面板；显示源窗口的操作只调用公开的平台激活 API，不注入输入，也不改变源窗口的真实层级。Topit 及其作者不赞助、背书或参与 Fuwa。

PipNow 的公开官网、完整两分钟宣传视频及试用版的普通新人引导，也用于参考窗
便利功能的产品研究。相关实现、测试、
文案和控件均为本项目独立编写，未使用 PipNow 的源码、素材或品牌元素。
Fuwa 保留原有快捷键，以可选的 Control–Option 按住手势暂时隐藏画面，不转发输入。
