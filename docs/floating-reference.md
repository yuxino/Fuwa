# Floating references / 参考窗口

These workflows are in development and have not been published in a release.

## English

Pin a window as usual with `⌥⌘P`. The default view follows its original window
and lets clicks pass through. Open its controls from the gear in Fuwa's list or
from the window's menu-bar submenu.

- Choose **Reference Window** to move and resize the picture independently.
  Drag the picture to move it and use the lower-right handle to resize. This
  controls the reference, without moving or typing into its source.
- Use **Choose Area** while the picture is live and visible. Drag over the
  captured picture to select a region; Escape cancels. Use Full Window returns to the
  full picture. The selection remains relative to the source window.
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
- The optional inactivity indicator reports that the picture stopped changing.
  It does not distinguish completion, errors, or waiting for input.

Hidden live pictures stop capturing; restoring them checks the source again.
A closed source retains its last picture as closed and cannot resume. Lock,
sleep, user switching and revoked recording permission still clear captured
content; pin it again after those privacy boundaries.

## 中文

仍可使用 `⌥⌘P` 固定窗口。默认画面跟随原窗口，并允许鼠标操作穿透。
从 Fuwa 列表中的齿轮或菜单栏的窗口子菜单打开控件。

- 选择**参考窗口**后，可独立移动和调整画面大小。拖动画面移动，使用右下角
  手柄调整大小。这些操作只改变参考窗口，不会移动原窗口或向它输入内容。
- 画面正在播放且可见时，使用**选择区域**在捕获画面上拖动框选。Escape 取消，
  “显示完整窗口”恢复完整画面。区域相对原窗口定位。
- **隐藏全部画面**暂时收起参考内容，**显示全部画面**恢复，并保留手动暂停
  的选择。默认快捷键是 `⌥⇧⌘P`，可在设置中独立修改。全部取消固定会移除
  参考内容；新增固定窗口会显示这一组画面。
- 选择所有空间或参考窗口所在的空间，也可选择仅在指定工作应用处于前台时
  显示。打开 Fuwa 控件时保留最近的工作应用状态；显示全部画面仍遵守应用规则。
- 帧率会用于同一来源应用的新固定窗口。开启静止降频后，约 15 秒未检测到
  明显的采样画面变化时降至 1 帧／秒；检测到变化时恢复所选帧率。这是画面
  判断，不是应用进度信号。
- 可选的静止提示表示画面停止变化，不区分完成、出错或等待输入。

隐藏时停止实时捕获，恢复时重新检查来源。原窗口关闭后保留最后画面并标记
为已关闭，不能继续播放。锁屏、睡眠、切换用户和录屏权限被撤销时，仍清除
捕获内容；经过这些隐私边界后需要重新固定。
