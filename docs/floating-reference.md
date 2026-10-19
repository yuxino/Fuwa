# Floating references / 参考窗口

Reference workflows in Fuwa 1.3.0 / Fuwa 1.3.0 参考窗使用说明。

## English

Pin a window as usual with `⌥⌘P`. The default view follows its original window
and lets clicks pass through. Open its controls from the gear in Fuwa's list or
from the window's menu-bar submenu.
Since 1.2.1, pointing at a visible floating picture and pressing the pin
shortcut removes that picture; elsewhere the shortcut still targets the window
you are using.
The controls group choices into **Picture**, **Visibility** and **Performance**;
playback and group navigation remain visible when the options need scrolling.

- Choose **Reference Window** to move and resize the picture independently.
  Drag the picture to move it and use the lower-right handle to resize. This
  controls the reference, without moving or typing into its source.
  Right-click the reference to open its controls.
- Use **Choose Area** while the picture is live and visible. Drag over the
  captured picture to select a region; Escape cancels. Use Full Window returns to the
  full picture. The selection remains relative to the source window.
  After changing the area or restoring a hidden picture, wait for fresh pixels
  before pausing or selecting another area. Pausing, hiding or changing its
  picture settings cancels any open area selector.
- **Hide All Pictures** temporarily conceals references. **Show All Pictures**
  restores them, preserving manual pause choices. The default shortcut is
  `⌥⇧⌘P`; change it separately from the pin shortcut in Settings. Unpin All
  removes references instead. Adding a new pin reveals the group.
- Choose all Spaces or the Space containing the reference. Application rules
  let you show it only while a selected working app is active. Opening Fuwa's
  controls retains the last working-app context. Global show still respects
  application rules.
- Frame Rate is remembered for new pins from the same source app. Idle reduction
  lowers capture to 1 fps after no significant sampled picture change is detected
  for about 15 seconds; detected changes restore the selected rate. This is a
  picture heuristic, not an application progress signal.
- **Show “Picture unchanged”** displays a status label at the upper left after
  about 15 seconds without detected changes. It disappears when the picture
  changes. Check task progress in the original app.

### Reference controls

In **Reference Window** mode, Visibility controls include **Opacity** (20–100%)
and an optional **Enlarge on hover** setting. Hover for a moment to see a larger
preview beside the reference on the same display; moving away closes it. If
there is no adjacent room, the preview stays closed. Hovering also restores the
reference itself to full opacity until the pointer leaves. The preview follows the
live or paused picture, stays fully opaque, and does not accept clicks or typing.
It uses the existing capture stream and is cleared with the reference at privacy boundaries.

Right-click the reference to choose a small, medium or large size. You can
still drag its corner for an exact size. **Open Source App**, or a double-click
on the picture, brings its application forward. When that app has several
windows, the app decides which appears; Fuwa does not request Accessibility
permission or forward input to a captured window.

**Arrange References**, in the list toolbar or menu bar, places references in
the chosen corner of their current display. Fuwa preserves their order and
proportions, using extra columns or smaller pictures when needed. It does not
move the original windows, reveal hidden pictures, or change pause state.

The window picker includes small, memory-only thumbnails. Closing it, refreshing
the list or crossing a privacy boundary clears those pictures. **Getting Started**
in the sidebar explains the initial permission and capture workflow; new users
can skip it and return later. Existing users keep their normal launch view.

In Settings, optionally enable **Hold ⌃⌥ to hide pictures**. Hold Control and
Option together, with no other modifiers, then release either to restore the
previous visibility. Manual hiding, application rules and pause choices remain
in force. This setting is off by default and does not consume keyboard events;
other apps can still use the same keys. Shortcut recording suspends the gesture.

Hidden live pictures stop capturing; restoring them checks the source again.
A closed source retains its last picture as closed and cannot resume. Lock,
sleep, user switching and revoked recording permission still clear captured
content; pin it again after those privacy boundaries.

## 中文

仍可使用 `⌥⌘P` 固定窗口。默认画面跟随原窗口，并允许鼠标操作穿透。
从 Fuwa 列表中的齿轮或菜单栏的窗口子菜单打开控件。
1.2.1 起，鼠标放在已有浮窗上时，按固定快捷键会取消这个浮窗的置顶。
鼠标在其他位置时，快捷键仍作用于当前正在使用的窗口。
控件分为**画面、显示、性能**三组；选项需要滚动时，播放操作和分组导航
仍保持可见。

- 选择**独立参考窗**后，可独立移动和调整画面大小。拖动画面移动，使用右下角
  手柄调整大小。这些操作只改变参考窗口，不会移动原窗口或向它输入内容。
  右键点击参考窗口也可打开控件。
- 画面正在播放且可见时，使用**选择区域**在捕获画面上拖动框选。Escape 取消，
  “显示完整窗口”恢复完整画面。区域相对原窗口定位。
  切换区域或恢复隐藏的画面后，需要等新画面到达，才能暂停或继续框选。
  暂停、隐藏或改变画面设置会取消已打开的区域选择。
- **隐藏全部画面**暂时收起参考内容，**显示全部画面**恢复，并保留手动暂停
  的选择。默认快捷键是 `⌥⇧⌘P`，可在设置中独立修改。全部取消固定会移除
  参考内容；新增固定窗口会显示这一组画面。
- 选择所有空间或参考窗口所在的空间，也可选择仅在指定工作应用处于前台时
  显示。打开 Fuwa 控件时保留最近的工作应用状态；显示全部画面仍遵守应用规则。
- 帧率会用于同一来源应用的新固定窗口。开启静止降频后，约 15 秒未检测到
  明显的采样画面变化时降至 1 帧／秒；检测到变化时恢复所选帧率。这是画面
  判断，不是应用进度信号。
- 开启**显示画面未变化提示**后，约 15 秒未检测到变化时，浮窗左上角显示
  「画面未变化」。画面变化后提示消失；任务进度请到原应用确认。

### 参考窗控件

在**独立参考窗**模式下，显示控件提供 **20–100% 不透明度**和可选的
**悬停时放大预览**。鼠标停留片刻后，在同一屏幕、参考窗旁边显示更大的预览，
移开后收起；旁边没有足够空间时不弹出。鼠标移入时，参考窗本身也会恢复完全
不透明，移开后回到设定值。
预览跟随画面的播放或暂停状态，始终完全不透明，不接受点击或输入。
它复用当前捕获流，并在隐私边界到来时与参考窗一起清除。

右键点击参考窗可选择小、中、大尺寸，仍可拖动右下角精确调整。
选择**打开来源应用**或双击画面，会将来源应用切到前台。应用有多个窗口时，
由应用决定显示哪个窗口；Fuwa 不请求辅助功能权限，也不向捕获窗口转发输入。

列表工具栏和菜单栏中的**整理参考窗**，可将参考窗排到各自屏幕的指定角落。
保持原有顺序和比例，空间不足时换列或缩小画面，不移动来源窗口，也不改变
隐藏和暂停状态。

选窗列表提供仅保存在内存中的缩略图；关闭列表、刷新或发生隐私边界时清除。
侧栏的**使用指南**说明首次授权和选窗流程，新用户可以跳过、之后再查看；
已经使用过 Fuwa 的用户仍进入原有页面。

设置中可开启**按住 ⌃⌥ 暂时隐藏画面**。同时按住 Control 和 Option，且不按
其他修饰键，即可暂时隐藏；松开任一键后恢复原来的显示状态。手动隐藏、应用
显示规则和暂停状态仍然有效。此项默认关闭，不拦截按键，其他应用仍可使用
相同按键；录制快捷键时会暂停此手势。

隐藏时停止实时捕获，恢复时重新检查来源。原窗口关闭后保留最后画面并标记
为已关闭，不能继续播放。锁屏、睡眠、切换用户和录屏权限被撤销时，仍清除
捕获内容；经过这些隐私边界后需要重新固定。
