# Fuwa：macOS 窗口置顶需求与产品设计研究

评审稿 · 2026-10-10。范围限定为 **macOS**。整理了 28 条来源、13 个产品，包含用户讨论、产品文档和对 Fuwa 当前实现的检查。

先看“结论”和“建议顺序”即可了解本轮判断；后文保留具体案例、产品比较、源码依据及全部来源。本稿用于产品讨论，尚未实施应用改动。

## 结论

Fuwa 值得继续围绕一个明确任务发展：用户把现有应用里需要持续看到的内容留下来，再继续操作其他应用。

现有资料支持把需求分成三类：保留参考信息、观察持续更新的状态、直接操作一个小窗口。这三类对输入、清晰度、位置和权限的要求不同。截图、实时镜像和可交互窗口不能放在同一条功能榜上比较。

本轮最明确的近期机会是 **暂时隐藏与恢复**。更值得探索的新方向是 **局部裁剪与独立摆放**，以及 **只在相关应用或 Space 显示**。这两个方向分别解决屏幕占用和无关时的遮挡。长时间运行、跨 Space、原生全屏和混合缩放属于交付质量要求。

## 建议顺序

以下优先级是结合公开证据与 Fuwa 当前实现的判断，不是用户需求频率排名；具体工作量尚未估算。

| 顺序 | 候选 | 用户完成后的体验 |
| --- | --- | --- |
| 近期 | 暂时隐藏／恢复全部浮窗 | 挡住工作时按一下收起，需要时按一下恢复；来源与原来的暂停状态仍在 |
| 优先探索 | 局部裁剪＋独立参考模式 | 把终端输出、文档一段或一个状态区域放到角落；小面积里仍能读清文字 |
| 随后 | 按前台应用／Space 显示 | 进入相关工作时参考内容出现，离开后收起 |
| 随后 | 场景帧率与静止降频 | 看日志和看视频采用适合的更新策略；持续使用时减少资源消耗 |
| 小规模试验 | 内容停止变化提示 | 观察进度时获得提示；提示只表示画面静止，不直接判断成功或完成 |
| 单独决定 | 完整交互、精确返回原窗口、虚拟显示器 | 在浮窗里输入或拖放；需先明确权限、原窗口位置和焦点行为 |

每个方向都要通过真实 Mac 使用验收：来源关闭或最小化、Spaces 与全屏切换、物理多屏、混合缩放、长时间运行。现有测试记录可以继续使用，缺少的情境单独补齐。

## 最值得借鉴的四个细节

1. **收起后能原样恢复。** [ScreenFloat](https://www.eternalstorms.at/ScreenFloat/) 与 [Snipaste](https://github.com/Snipaste/feedback/wiki/Getting-Started) 把显隐做成明确操作。Fuwa 的“取消全部置顶”目前会清除会话，需要另设临时隐藏语义。
2. **小窗里的内容要读得清。** [Pipiri](https://www.lowtechguys.com/pipiri/) 提供区域、缩放和平移；[MyWindowPip](https://github.com/ljzxzxl/my-window-pip/blob/main/README.md) 在捕获端裁剪。对 Fuwa 而言，独立参考模式比仅把整窗缩小更值得探索。
3. **显示范围由工作决定。** [ScreenFloat](https://www.eternalstorms.at/ScreenFloat/) 支持指定应用或 Space；[独立用户评论](https://www.reddit.com/r/macapps/comments/198s2lp/screenfloat_2_power_up_your_screenshots/) 也肯定了这一点。
4. **常用动作就近完成。** [Shottr](https://shottr.cc/kb/startguide) 的缩略入口直接完成复制、保存和置顶；[Meet PiP](https://support.google.com/meet/answer/13665919?hl=en) 保留会议必要操作。Fuwa 可以据此检查选择、置顶、暂停、收起与恢复是否足够直接。

## Mac 用户到底想完成什么

| 任务 | 公开证据 | 对 Fuwa 的含义 | 证据强度与限制 |
| --- | --- | --- | --- |
| 看课、开会时记笔记，减少来回切换 | [Mac 笔记置顶请求](https://www.reddit.com/r/macapps/comments/1eqffmf/note_taking_app_which_always_stays_on_the_top/)，[V2EX 上课与记笔记](https://www.v2ex.com/t/1077366) | 参考内容持续可见，主应用继续接收输入；小窗口要可读且易收起 | 两个社区里的独立任务描述；不能推算人群占比 |
| 把任意已有应用留下来，而非只支持网页视频 | [轻量置顶工具请求](https://www.reddit.com/r/macapps/comments/1skntmh/lightweight_alwaysontop_app/)，[V2EX 任意窗口与快捷键](https://www.v2ex.com/t/1112109) | 选择与置顶路径要短；不同应用的窗口都能识别；设置负担小 | 近期独立需求。V2EX 对 Topit 的评价是当时个体体验，不是当前产品结论 |
| 在其他工作上保留视频或直播 | [Jellyfin／Chrome 视频请求](https://www.reddit.com/r/macapps/comments/1alpafj/is_there_a_mac_app_that_will_allow_me_to_keep_any/)，[德语 Mac 直播讨论](https://www.macuser.de/threads/fenster-immer-im-vordergrund-halten-geht-das-always-on-top-beim-macbook.911369/) | 任意窗口捕获能覆盖部分没有原生 PiP 的来源；控制与字幕会影响体验 | 跨语言重复任务；视频已有专用替代品，不能直接视为 Fuwa 的独占机会 |
| 盯终端、构建、日志、AI agent 进度 | [Pipiri 官方用途](https://www.lowtechguys.com/pipiri/)，[Pipiri 发布帖及用户反馈](https://www.reddit.com/r/macapps/comments/1r9bm3z/pipiri_pictureinpicture_any_macos_window/) | 局部可读、低更新成本、暂停与恢复；停止变化提示可作为试验 | 产品与开发者证据较多，独立反馈较少；尚不足以称为最高频场景 |
| 在编辑器或创作工具里参考截图、图片、短文字 | [ScreenFloat 用户反馈](https://www.reddit.com/r/macapps/comments/198s2lp/screenfloat_2_power_up_your_screenshots/)，[ScreenFloat](https://www.eternalstorms.at/ScreenFloat/)，[PureRef](https://www.pureref.com/handbook/features/) | 静止画面不必一直捕获；透明度、点击穿透与快速恢复重要 | ScreenFloat 的用户评论肯定按当前应用显示与收放；发布帖主体来自开发者 |
| Finder 拖文件到工作应用，或在置顶笔记里直接输入 | [MacOS 用户明确说明 Finder／FL Studio 场景](https://www.reddit.com/r/MacOS/comments/1ese6mw/how_do_i_make_windows_stay_on_top/) | 可读镜像不能完整满足直接拖放和编辑；必须区分“看”与“操作原窗口” | 具体独立场景，不能把它解释为所有用户都需要完整输入转发 |
| 主应用全屏时，小窗口仍可用 | [Mac 全屏置顶请求](https://www.reddit.com/r/macapps/comments/195k6tr)，[Topit 全屏问题](https://github.com/lihaoyun6/Topit/issues/30) | 要验证显示、焦点、点击与 Space 跳转的完整过程 | 请求与缺陷报告支持验收必要性；不据历史 issue 判断当前版本全部失效 |
| 无关时不挡住屏幕，相关时自动出现 | [ScreenFloat 独立用户评论](https://www.reddit.com/r/macapps/comments/198s2lp/screenfloat_2_power_up_your_screenshots/) | “按前台应用／Space 显示”可能比永久悬浮更适合参考工作流 | 一条有具体使用细节的正面评价；仍需 Fuwa 用户验证 |
| 清楚理解屏幕录制权限 | [WindowPin 权限疑问](https://www.reddit.com/r/MacOS/comments/1ese6mw/how_do_i_make_windows_stay_on_top/) | 授权时讲清捕获对象、用途与数据去向，安装和更新后保持身份稳定 | 用户问了屏幕与音频录制权限；没有证据证明其因此卸载或拒绝授权 |

## 优秀 Mac 产品中可借鉴的设计

| 产品 | 实际类别 | 文档可核实的好设计 | 对 Fuwa 的取舍 |
| --- | --- | --- | --- |
| [Pipiri](https://www.lowtechguys.com/pipiri/) | 实时窗口／区域 PiP | 区域选择、缩放和平移；独立等比调整；按应用帧率；隐藏时暂停流；内容停止变化的提醒 | 小画面可读性与更新成本值得学习。其隐藏 60 秒后自动关闭的规则不适合直接作为 Fuwa 的恢复语义 |
| [MyWindowPip](https://github.com/ljzxzxl/my-window-pip/blob/main/README.md) | 实时窗口／区域 PiP | 捕获端裁剪；位置记忆；帧率与静止降频；自动避让时保留可操作顶栏；精确返回原窗口使用可选辅助功能权限 | 浮窗与控制入口分开考虑。Chromium 兼容方案要重启来源应用，属于有成本的取舍，不是普遍保证 |
| [ScreenFloat](https://www.eternalstorms.at/ScreenFloat/) | 浮动截图／录制内容 | 临时隐藏后恢复；绑定指定 Space，或只在指定应用位于前台时显示；OCR 提取与遮盖 | 优先借鉴显示规则和状态语义。它不等于持续镜像任意应用窗口；图库与编辑套件不是 Fuwa 当前必要范围 |
| [Snipaste](https://github.com/Snipaste/feedback/wiki/Getting-Started)（[Mac 下载](https://www.snipaste.com/download.html)） | 浮动截图 | 隐藏、关闭、销毁有不同语义；全部收放；点击穿透有全局快捷键恢复路径 | 暂时收起不应丢失置顶集合。不要照搬通用文档里的默认按键作为 Mac 已验证快捷键 |
| [PureRef](https://www.pureref.com/handbook/features/) | 图片参考画布 | 锁定位置；透明度与点击穿透；激活应用或全局快捷键可退出穿透；可只置于选定应用之上 | 穿透模式必须有稳定退出入口。其“置于某应用之上”不应等同于 ScreenFloat 的“仅在该应用前台时显示” |
| [CleanShot X](https://cleanshot.com/features) | 截图与录屏工具 | 截图浮窗调整大小和透明度；键盘精细定位；Lock Mode 允许操作下方应用；快速操作入口 | 完成最常用动作不必进入完整编辑器；参考内容本身应占主要空间 |
| [Shottr](https://shottr.cc/kb/startguide) | Mac 截图工具 | 缩略入口直接复制、保存、提取文字或置顶；编辑器按需打开并记忆偏好 | 置顶完成后的流程要短。官方启动指南也说明菜单栏图标可能因刘海或拥挤不可见，后台工具需要可发现的入口 |
| [SideNotes](https://www.apptorium.com/sidenotes/features) | 自有笔记侧栏 | 屏幕边缘快速收放；热键／菜单入口；折叠长笔记；边缘拖放触发可以关闭 | 用可逆的显隐缩短流程。边缘或悬停触发应可选，避免干扰拖放与常规鼠标操作 |
| [Apple 便笺](https://support.apple.com/zh-cn/guide/stickies/welcome/10.3/mac/15.0) | 系统自有笔记 | 浮动、半透明、折叠与自动保存 | 单纯把短笔记留在前台已有系统路径。Fuwa 更有价值的范围是用户现有的第三方内容 |
| [Firefox PiP](https://support.mozilla.org/en-US/kb/about-picture-picture-firefox) | 网页视频 PiP | 独立移动／缩放、多视频、播放与静音控制、支持来源的字幕 | 小窗要完成核心任务。视频控制有来源知识，不能假设任意窗口镜像都能直接获得同等控制 |
| [Google Meet PiP](https://support.google.com/meet/answer/13665919?hl=en) | 会议专用 PiP | 切标签或共享时的可选自动显示；摄像头、麦克风、举手、聊天与字幕；返回会议标签 | 小窗保留必要操作，其他操作回完整界面。官方文档仍提示其他窗口最大化会隐藏 PiP，不能据此承诺所有 Mac 全屏情境 |
| [PiPanel](https://github.com/Lyle-xub/PiPanel) | 可交互实时窗口镜像 | 官方列出点击、滚动、拖动与输入；直接在浮窗处理任务 | 能满足另一类工作流，但需要屏幕录制与辅助功能；仓库声明 macOS 14+、Apple Silicon。不是 Fuwa 当前轻量查看路径的低成本增项 |
| [PIPin](https://pipin.jylljy.top/) | 虚拟显示器上的窗口镜像 | 将来源移到虚拟显示器以保持其绘制，再镜像到用户所在桌面 | 研究背景绘制的替代思路。它会移动真实窗口且需要辅助功能；官网的唯一性和竞品冻结比例没有独立证实，不用于结论 |

## 对 Fuwa 当前实现的映射

本地基线：1.1.1；研究开始时工作区为干净的 `main`。这里依据本地源码和 changelog，不代表重新验证了 GitHub Release 或所有机器上的行为。

| 当前事实 | 本地依据 | 研究含义 |
| --- | --- | --- |
| 1.1.1 使用原生菜单，已有暂停、恢复、取消置顶；移除了返回原窗口及辅助功能需求 | [CHANGELOG.md](../../CHANGELOG.md) 1.1.1 | 不把已有暂停能力列成新功能；重新加入输入或返回原窗口需要明确用途 |
| Live 浮窗跟随来源几何，`isMovable = false`，默认点击穿透 | [PinSession.swift](../../Sources/Fuwa/PinSession.swift) `createPresentationIfNeeded`、`updatePanelFrame` 与实时同步路径 | 独立移动、缩放、区域裁剪应是一种明确的参考模式，而非仅改几个按钮 |
| 面板声明加入所有 Spaces 与全屏辅助窗口集合 | [PinSession.swift](../../Sources/Fuwa/PinSession.swift) 面板配置 | 声明不能替代 Mission Control、原生全屏、焦点切换和物理多屏验收 |
| 暂停保留静止帧并停止捕获；`clearAll` 移除会话与追踪 | [PinSession.swift](../../Sources/Fuwa/PinSession.swift) `freeze`；[PinCoordinator.swift](../../Sources/Fuwa/PinCoordinator.swift) `prepareToClearAll` | “暂时隐藏”须是独立状态，不能用取消全部置顶伪装成可恢复收起 |
| 捕获配置的最小帧间隔为 1/30 秒 | [PinSession.swift](../../Sources/Fuwa/PinSession.swift) `makeConfiguration` | 这是配置上限线索，不证明空闲时持续产生 30 帧或资源泄漏。可研究按场景帧率与静止降频 |
| 锁屏、睡眠等隐私边界会清除第三方捕获；解锁后要求用户重新置顶 | [PrivacyLifecycle.swift](../../Sources/Fuwa/PrivacyLifecycle.swift) 类注释及观察器 | 普通隐藏后可以恢复；锁屏后仍由用户重新置顶，两种规则必须区分 |
| 已有 2× Retina 与 1× 虚拟显示器的真实捕获证据，物理外屏、Intel 和全部布局仍有边界 | [混合缩放验收记录](../qa/mixed-scale-0.1.17/README.md) | 沿用已有证据，再补实际未覆盖的使用情境；不把已有证据说成没有测试 |

## 下一步候选与优先级

这些是研究判断，尚未实施产品改动。

### 近期候选：暂时隐藏／恢复

一个菜单动作和可配置快捷键收起全部浮窗，再次操作恢复。保留来源、顺序、显示配置，以及用户原先的 Live／暂停选择。隐藏期间停止不必要捕获；恢复时重新解析来源，关闭的窗口不产生假画面。用户在隐藏期间重新置顶时，也要有明确规则。

隐藏必须同时移除画面和可点击区域。点击穿透状态不能让用户失去控制入口。不要设置未明确说明的短时间自动取消，也不要跨锁屏恢复敏感内容。

判断依据：Snipaste 的显隐语义、ScreenFloat 的恢复与用户评价、多个实时 PiP 产品的避让入口。实现范围相对集中，具体工作量仍需代码设计。

### 优先探索：局部裁剪＋独立参考模式

现有的跟随原窗口置顶继续服务原有任务；新模式允许把一个区域独立放到角落，调整尺寸和缩放，保留可读文字。区域相对来源窗口定位，来源移动时不用重新框选；清晰度优先采用捕获端像素而非放大小缩略图。

这是本轮相比前一轮提高关注度的方向。Pipiri 与 MyWindowPip 提供具体设计依据；“只需要小块内容”的 Mac 独立需求证据仍弱于“任意窗口可见”，不能宣称它已是最高频用户要求。独立窗口几何也会扩大 Fuwa 的验收范围。

### 中期候选：按场景显示与更新

- 指定前台应用／Space 显示：参考资料进入相关工作时出现，离开时收起；先采用用户显式绑定，避免标题规则和复杂自动匹配。
- 场景帧率与静止降频：日志／笔记与视频选择不同策略；先测同一台机器、相同来源和窗口尺寸的资源基线，再决定默认值。
- 内容停止变化提示：适合观察构建或 agent 的小规模试验。静止不等于任务完成，错误、等输入和成功都可能停止变化；不要命名为自动识别完成。

### 单独评估：交互、返回来源与虚拟显示器

Finder 拖文件和编辑文字确实需要操作能力。完整输入转发、辅助功能精确定位以及移动来源到虚拟显示器，会带来权限、坐标、焦点与来源生命周期的新责任。它们需要独立产品决定，不与“轻量看一眼”合并推进。

Mac 更新、签名和权限的稳定性同样重要。此次权限评论只能证明疑问存在，不能量化转化损失。

## 应如何验证候选

采用可比较的真实 Mac 任务：看课记笔记、编辑器旁参考图、终端构建、浏览器 dashboard、Finder 拖放。每次记录从选择来源到开始工作、暂时收起、再次恢复的动作与失败点。

验收覆盖原生全屏、Spaces 切换、Mission Control、物理外屏接入／拔出和混合缩放；来源最小化、关闭、重启与不同后台绘制行为单独记录。用真实日志和视频跑持续会话，观察 CPU、内存趋势、恢复延迟和文字清晰度。必须区分“来源不绘制”和“Fuwa 捕获失效”。

界面沿用 Fuwa 现有视觉规范，让内容占主要空间，控制只保留必要动作，快捷键之外提供可发现的菜单入口。本研究没有直接生成新的 UI、默认配色或实施计划。

## 来源记录

能力描述以第一方资料为依据，使用评价以独立用户原文为依据。下列资料查阅时间均为 2026-10-10；社区日期为原帖日期，不把后来评论自动视作同一天。

本研究的边界：

- 英语与中文社区提供了主要的近期反馈；德语和法语 Mac 社区补充历史场景。此次没有找到足够可靠的日语 Mac 用户材料，不能据此比较各地区的需求强弱。
- 社区样本用于发现任务与失败情境，不代表总体用户分布、市场规模、付费意愿或功能使用频率。开发者发布帖单独标注。
- “做得好”指文档可核实的设计选择。本轮没有安装竞品、测量资源消耗或验证所有全屏行为；开发者的性能数字没有用来排名。
- 云端对话 `6ac902b3-8844-83ec-b3bc-f5a2da2c8ab3`（《置顶窗口问题分析》）提供研究起点；其提到的 82 条资料和表格附件没有在本轮逐条审计，不计作本轮已核实来源。

| 编号 | 来源 | 时间／类型 | 本轮读取与用途 |
| --- | --- | --- | --- |
| D01 | [Lightweight always-on-top app](https://www.reddit.com/r/macapps/comments/1skntmh/lightweight_alwaysontop_app/) | 2026-04-13，Mac 用户请求 | 搜索返回原帖与评论正文；轻量、任意应用需求 |
| D02 | [Keep any window on top](https://www.reddit.com/r/macapps/comments/1alpafj/is_there_a_mac_app_that_will_allow_me_to_keep_any/) | 2024-02-08，Mac 用户请求 | 返回原帖与评论正文；视频／Jellyfin 与配置负担 |
| D03 | [Note taking app always on top](https://www.reddit.com/r/macapps/comments/1eqffmf/note_taking_app_which_always_stays_on_the_top/) | 2024-08-12，Mac 用户请求 | 返回原帖正文；webinar 与笔记 |
| D04 | [Mac 上课记笔记](https://www.v2ex.com/t/1077366) | 2024-10-02，中文 Mac 社区 | 帖子与评论正文；频繁切换和直接输入需求 |
| D05 | [窗口置顶软件，一个能打的都没有？](https://www.v2ex.com/t/1112109) | 2025-02-17，中文 Mac 社区 | 帖子与评论正文；任意窗口与热键；未把猜测的工具冲突当事实 |
| D06 | [How do I make windows stay on top?](https://www.reddit.com/r/MacOS/comments/1ese6mw/how_do_i_make_windows_stay_on_top/) | 2024-08-14，Mac 用户讨论 | 搜索返回完整讨论；Finder 任务与后来权限疑问；用户推荐中的能力另查官方 |
| D07 | [全屏应用上方浮窗](https://www.reddit.com/r/macapps/comments/195k6tr) | 2024-01-13，Mac 用户请求 | 返回原帖与评论正文；未把评论脚本视作验证通过的方案 |
| D08 | [ScreenFloat 2 讨论](https://www.reddit.com/r/macapps/comments/198s2lp/screenfloat_2_power_up_your_screenshots/) | 2024-01-17，开发者发布帖／用户评论 | 页面正文；独立用户 `msucorey` 肯定相关应用显示与收放；主体是宣传来源 |
| D09 | [Pipiri 讨论](https://www.reddit.com/r/macapps/comments/1r9bm3z/pipiri_pictureinpicture_any_macos_window/) | 2026-02-19，开发者发布帖／用户评论 | 返回正文；终端观察用途及有限用户兴趣，未当作大规模需求 |
| D10 | [MacBook always on top](https://www.macuser.de/threads/fenster-immer-im-vordergrund-halten-geht-das-always-on-top-beim-macbook.911369/) | 2022-11-20，德语 Mac 用户请求 | 页面原帖；直播与其他工作，历史场景 |
| D11 | [Garder une fenêtre au premier plan](https://forums.macg.co/threads/garder-une-fenetre-au-premier-plan.189905/) | 2007-10-11，法语 Mac 用户请求 | 页面原帖；聊天保持可见，仅历史存在性证据 |
| D12 | [Topit #30](https://github.com/lihaoyun6/Topit/issues/30) | 2025-03-19，用户缺陷报告 | issue 正文；全屏下操作导致切回桌面的个案，非当前版本通用结论 |
| P01 | [Pipiri](https://www.lowtechguys.com/pipiri/) | 官方产品页 | 浏览器／网页正文；区域、帧率、显隐、停止变化提醒 |
| P02 | [MyWindowPip](https://github.com/ljzxzxl/my-window-pip/blob/main/README.md) | 官方仓库 README | 网页正文；裁剪、控制入口、资源策略与兼容取舍 |
| P03 | [ScreenFloat](https://www.eternalstorms.at/ScreenFloat/) | 官方产品页 | 浏览器正文；截图与录制类型，按应用／Space 显示 |
| P04 | [Snipaste 入门](https://github.com/Snipaste/feedback/wiki/Getting-Started) | 官方文档 | 浏览器正文；隐藏／关闭／销毁与穿透退出 |
| P05 | [Snipaste 下载](https://www.snipaste.com/download.html) | 官方下载页 | 网页正文；确认存在 macOS Universal 版本 |
| P06 | [PureRef 手册](https://www.pureref.com/handbook/features/) | 官方文档 | 浏览器正文；参考图、锁定与穿透恢复 |
| P07 | [CleanShot X 功能](https://cleanshot.com/features) | 官方产品页 | 浏览器正文；浮图、定位、Lock Mode 与快速操作 |
| P08 | [Shottr 入门](https://shottr.cc/kb/startguide) | 官方文档 | 浏览器正文；缩略入口与可选编辑器 |
| P09 | [SideNotes 功能](https://www.apptorium.com/sidenotes/features) | 官方产品页 | 浏览器正文；边缘显示与折叠笔记 |
| P10 | [关闭 SideNotes 边缘拖放](https://www.apptorium.com/sidenotes/tips/how-to-disable-dnd-on-sceen-edge) | 官方说明 | 返回正文；自动触发应提供关闭路径 |
| P11 | [Apple 便笺指南](https://support.apple.com/zh-cn/guide/stickies/welcome/10.3/mac/15.0) | 官方 Mac 文档 | 返回正文；浮动、透明、折叠；不混同 Notes 列表置顶 |
| P12 | [Firefox PiP](https://support.mozilla.org/en-US/kb/about-picture-picture-firefox) | 官方支持文档 | 网页正文；视频控制、多 PiP 与字幕条件 |
| P13 | [Google Meet PiP](https://support.google.com/meet/answer/13665919?hl=en) | 官方支持文档 | 网页正文；核心任务控制、触发设置与最大化限制 |
| P14 | [Meet 快捷键](https://support.google.com/a/users/answer/9896256?hl=en) | 官方支持文档 | 返回正文；确认 Mac 桌面使用路径 |
| P15 | [PiPanel](https://github.com/Lyle-xub/PiPanel) | 官方仓库 | README 正文；输入转发与平台、权限要求 |
| P16 | [PIPin](https://pipin.jylljy.top/) | 官方产品页 | 浏览器正文；虚拟显示器与来源移动；未采用唯一性宣传 |

未纳入：仅适用于 Windows／Linux 的讨论，操作系统不明确的参考图需求，日语 SEO 汇总，以及未追溯到第一方资料的用户推荐。产品功能会变化；若决定实施某个方向，再核对相应项目的当前代码与许可，保持独立实现。
