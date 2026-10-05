// Package view is Fuwa's native MyGo UI. It contains no macOS calls, and can be
// exercised and rendered with ui.NewTester without screen-recording permission.
package view

import (
	"fmt"
	"github.com/egoist/mygo/ui"
	"github.com/yuxino/Fuwa/internal/core"
	"strings"
)

type Action struct {
	Name    string
	Token   uint64
	Window  core.Window
	Value   string
	Enabled bool
}
type Model struct {
	Settings                   core.Settings
	Locale                     string
	Pins                       []core.Session
	Choices                    []core.Window
	Route                      string
	Notice                     string
	Screen, Accessibility      bool
	LoginState                 int
	ShortcutDraft              string
	UpdatePhase, UpdateVersion string
	Progress                   float64
	OnAction                   func(Action)
}

func New(s core.Settings, locale string) *Model {
	return &Model{Settings: s, Locale: locale, Route: "pins", ShortcutDraft: s.Shortcut, UpdatePhase: "idle"}
}
func (m *Model) Chinese() bool {
	return m.Settings.Language == "zh-Hans" || (m.Settings.Language == "system" && strings.HasPrefix(strings.ToLower(m.Locale), "zh"))
}
func (m *Model) T(en, zh string) string {
	if m.Chinese() {
		return zh
	}
	return en
}
func (m *Model) Send(a Action) {
	if m.OnAction != nil {
		m.OnAction(a)
	}
}
func (m *Model) Explain(code string) string {
	messages := map[string][2]string{
		"no_window":                {"Bring the window you want to pin to the front, then press the shortcut.", "请先切到要置顶的窗口，再按快捷键。"},
		"source_closed":            {"The source window has closed. Any previously captured still is kept.", "原窗口已关闭；如果已有冻结画面，会继续保留。"},
		"screen_permission":        {"Screen Recording permission is required. Enable it in System Settings, then pin again.", "需要录屏权限。请在系统设置中允许后重新置顶。"},
		"accessibility_permission": {"Accessibility permission is needed only to go to the original window.", "仅在跳转原窗口时需要辅助功能权限。"},
		"no_complete_frame":        {"A complete frame has not arrived yet.", "尚未收到完整画面。"},
		"capture_unavailable":      {"macOS could not enumerate capturable windows. Try again.", "macOS 暂时无法列出可捕获窗口，请重试。"},
		"not_shareable":            {"macOS does not allow this window to be captured. No other window was selected.", "macOS 不允许捕获这个窗口，未改选其他窗口。"},
		"capture_start_failed":     {"Capture could not start. Check Screen Recording permission and try again.", "捕获启动失败，请检查录屏权限后重试。"},
		"capture_interrupted":      {"Capture was interrupted. Resume to reconnect to the same source.", "捕获中断，恢复后会重新连接同一个原窗口。"},
		"capture_resize_failed":    {"Capture could not follow the new size. The last frame is kept.", "捕获尺寸调整失败，保留最后一帧。"},
		"first_frame_timeout":      {"No complete frame arrived within 8 seconds. The previous still, if any, is kept.", "8 秒内未收到完整画面，已有的冻结画面会保留。"},
		"ambiguous_source":         {"Several windows match. Fuwa will not guess which one to activate.", "有多个窗口符合条件，Fuwa 不会猜测并激活其中一个。"},
		"source_uncontrollable":    {"macOS could not safely identify or raise the original window.", "macOS 无法安全识别或激活原窗口。"},
		"privacy_cleared":          {"Pins were cleared for privacy. Pin again after unlocking or waking.", "已为保护隐私清除置顶。解锁或唤醒后请重新置顶。"},
		"invalid_shortcut":         {"Use a key with Command, Control or Option, for example Cmd+Alt+P.", "请使用带 Command、Control 或 Option 的组合键，例如 Cmd+Alt+P。"},
		"shortcut_conflict":        {"That shortcut is unavailable. Your previous shortcut is still active.", "该快捷键不可用，原快捷键仍然有效。"},
		"shortcut_inactive":        {"The saved shortcut could not be registered. Choose another in Settings.", "保存的快捷键注册失败，请在设置中更换。"},
		"pin_limit":                {"Up to eight windows can be pinned at once.", "最多同时置顶 8 个窗口。"},
		"login_failed":             {"Login registration failed. Move this app to Applications and check Login Items.", "登录启动设置失败。请将应用移到 Applications 并检查登录项。"},
		"preview_updates":          {"Signed MyGo updates are not configured for this preview. It will never install an unsigned package or the Swift release.", "本预览版尚未配置签名的 MyGo 更新，不会安装未签名包或旧 Swift 正式版。"},
		"settings_failed":          {"Preferences could not be saved. Check access to the application support folder.", "偏好设置保存失败，请检查应用支持目录权限。"},
		"settings_reset":           {"Invalid preferences were ignored; defaults are in use.", "偏好设置无效，已使用默认值。"},
		"update_failed":            {"Update failed. The installed application was not relaunched.", "更新失败，未重启应用。"},
	}
	if v, ok := messages[code]; ok {
		return m.T(v[0], v[1])
	}
	return code
}
func (m *Model) state(p core.Session) string {
	if p.Closed {
		if !p.HasFrame {
			return m.T("Source closed", "原窗口已关闭")
		}
		return m.T("Source closed · still kept", "原窗口已关闭 · 保留画面")
	}
	switch p.State {
	case core.Starting:
		return m.T("Connecting…", "正在连接…")
	case core.Live:
		return m.T("Live · clicks pass through", "实时 · 鼠标穿透")
	case core.Frozen:
		return m.T("Frozen", "已冻结")
	case core.Failed:
		return m.T("Capture failed", "捕获失败")
	default:
		return m.T("Stopped", "已停止")
	}
}
func (m *Model) Render(c *ui.Context) {
	ui.Column(c).Fill().Padding(24).Gap(16).Children(func() {
		ui.Row(c).Gap(12).Children(func() {
			ui.Column(c).Gap(3).Grow(1).Children(func() {
				ui.Text(c, "Fuwa").FontSize(30).Bold()
				ui.Text(c, m.T("A little space for what matters.", "给重要的窗口，留一点位置。")).TextColor(c.Theme().TextMuted)
			})
			ui.Text(c, "MyGo preview").FontSize(12).TextColor(c.Theme().TextMuted)
		})
		ui.Row(c).Gap(8).Children(func() {
			for _, tab := range []struct{ id, en, zh string }{{"pins", "Pinned windows", "置顶窗口"}, {"picker", "Choose a window", "选择窗口"}, {"settings", "Settings", "设置"}} {
				if ui.Button(c, m.T(tab.en, tab.zh)).Disabled(m.Route == tab.id).Clicked() {
					m.Route = tab.id
					if tab.id == "picker" {
						m.Send(Action{Name: "refresh"})
					}
				}
			}
		})
		ui.Divider(c)
		ui.Scroll(c).Grow(1).Gap(16).Children(func() {
			if m.Notice != "" {
				ui.Text(c, m.Explain(m.Notice))
				if ui.Button(c, m.T("Dismiss", "关闭提示")).Clicked() {
					m.Notice = ""
				}
			}
			switch m.Route {
			case "settings":
				m.settings(c)
			case "picker":
				m.picker(c)
			default:
				m.pins(c)
			}
		})
		ui.Divider(c)
		ui.Row(c).Gap(12).Children(func() {
			ui.Text(c, m.T("On this Mac only. No uploads or analytics.", "仅在此 Mac 上处理，不上传、不统计。")).FontSize(11).TextColor(c.Theme().TextMuted).Grow(1)
			ui.Text(c, core.Version).FontSize(11).TextColor(c.Theme().TextMuted)
		})
	})
}
func (m *Model) pins(c *ui.Context) {
	ui.Row(c).Gap(8).Children(func() {
		ui.Text(c, m.T("Pinned windows", "置顶窗口")).FontSize(19).Bold().Grow(1)
		ui.Text(c, fmt.Sprintf("%d / %d", len(m.Pins), core.MaxPins)).TextColor(c.Theme().TextMuted)
		if ui.Button(c, m.T("Clear all", "全部取消")).Disabled(len(m.Pins) == 0).Clicked() {
			m.Send(Action{Name: "clear"})
		}
	})
	if len(m.Pins) == 0 {
		ui.Column(c).Padding(28, 8).Gap(12).Children(func() {
			ui.Text(c, m.T("Keep a window in view.", "让一个窗口，一直看得见。")).FontSize(23).Bold()
			ui.Text(c, m.T("Switch to an image, a document, or a tutorial. Press "+m.Settings.Shortcut+" to pin it.", "切换到图片、文档或教程窗口，按 "+m.Settings.Shortcut+" 置顶。"))
			ui.Text(c, m.T("The mirror stays above your work, while clicks reach the app underneath.", "镜像会浮在上方，点击仍然传到下方应用。")).TextColor(c.Theme().TextMuted)
		})
	}
	if ui.PrimaryButton(c, m.T("Pin front window", "置顶前方窗口")).Disabled(len(m.Pins) >= core.MaxPins).Clicked() {
		m.Send(Action{Name: "pin-front"})
	}
	for _, p := range m.Pins {
		ui.Column(c).Key(fmt.Sprint(p.Token)).Gap(8).Padding(12, 0).Children(func() {
			ui.Text(c, p.Source.Name()).FontSize(16).Bold()
			ui.Text(c, p.Source.App+"  ·  "+m.state(p)).TextColor(c.Theme().TextMuted)
			if p.Error != "" {
				ui.Text(c, m.Explain(p.Error)).FontSize(12)
			}
			m.controls(c, p, false)
			ui.Divider(c)
		})
	}
}
func (m *Model) controls(c *ui.Context, p core.Session, compact bool) {
	ui.Row(c).Gap(6).Wrap().Children(func() {
		if p.State == core.Frozen {
			if ui.Button(c, m.T("Resume", "恢复实时")).Disabled(p.Closed).Clicked() {
				m.Send(Action{Name: "resume", Token: p.Token})
			}
		} else {
			if ui.Button(c, m.T("Freeze", "冻结画面")).Disabled(p.State != core.Live).Clicked() {
				m.Send(Action{Name: "freeze", Token: p.Token})
			}
		}
		if ui.Button(c, m.T("Go to original", "跳转原窗口")).Disabled(p.Closed).Clicked() {
			m.Send(Action{Name: "reveal", Token: p.Token})
		}
		if !compact {
			if ui.Button(c, m.T("Controls", "控制面板")).Clicked() {
				m.Send(Action{Name: "controls", Token: p.Token})
			}
		}
		if ui.Button(c, m.T("Unpin", "取消置顶")).Clicked() {
			m.Send(Action{Name: "unpin", Token: p.Token})
		}
	})
}
func (m *Model) Controls(token uint64) func(*ui.Context) {
	return func(c *ui.Context) {
		ui.Column(c).Fill().Padding(12).Gap(10).Children(func() {
			for _, p := range m.Pins {
				if p.Token == token {
					ui.Text(c, p.Source.Name()).Bold().SingleLine()
					m.controls(c, p, true)
					return
				}
			}
			ui.Text(c, m.T("This pin has been removed.", "这个置顶已被移除。"))
		})
	}
}
func (m *Model) picker(c *ui.Context) {
	ui.Row(c).Gap(8).Children(func() {
		ui.Text(c, m.T("Visible windows", "可见窗口")).FontSize(19).Bold().Grow(1)
		if ui.Button(c, m.T("Refresh", "刷新")).Clicked() {
			m.Send(Action{Name: "refresh"})
		}
	})
	ui.Text(c, m.T("Only the window you choose will be captured. A protected window is never replaced with another.", "只捕获你选中的窗口，无法捕获时不会改选后面的窗口。")).TextColor(c.Theme().TextMuted)
	if len(m.Choices) == 0 {
		ui.Text(c, m.T("No eligible windows. Open a window in another app and refresh.", "没有可选窗口。请在其他应用打开窗口后刷新。"))
	}
	for _, w := range m.Choices {
		pinned := false
		for _, p := range m.Pins {
			if p.Source.Same(w) {
				pinned = true
			}
		}
		ui.Row(c).Key(fmt.Sprint(w.ID)).Gap(12).Padding(8, 0).Children(func() {
			ui.Column(c).Grow(1).Gap(4).Children(func() { ui.Text(c, w.Name()).Bold(); ui.Text(c, w.App).TextColor(c.Theme().TextMuted) })
			label := m.T("Pin", "置顶")
			if pinned {
				label = m.T("Pinned", "已置顶")
			}
			if ui.Button(c, label).Disabled(pinned || len(m.Pins) >= core.MaxPins).Clicked() {
				m.Send(Action{Name: "pin", Window: w})
			}
		})
	}
}
func (m *Model) settings(c *ui.Context) {
	ui.Text(c, m.T("Preferences", "偏好设置")).FontSize(19).Bold()
	dock := m.Settings.KeepDock
	if ui.Checkbox(c, &dock, m.T("Keep Fuwa in the Dock", "在 Dock 中保留 Fuwa")).Changed() {
		m.Send(Action{Name: "dock", Enabled: dock})
	}
	login := m.LoginState == 1 || m.LoginState == 2
	if ui.Checkbox(c, &login, m.T("Launch at login", "登录时启动")).Changed() {
		m.Send(Action{Name: "login", Enabled: login})
	}
	if m.LoginState == 2 {
		ui.Text(c, m.T("Approval is required in Login Items.", "需要在系统登录项中批准。"))
		if ui.Button(c, m.T("Open Login Items", "打开登录项")).Clicked() {
			m.Send(Action{Name: "login-settings"})
		}
	}
	if m.LoginState == 3 {
		ui.Text(c, m.T("Move this app to Applications to enable login registration.", "请将应用移到 Applications 后设置登录启动。"))
	}
	ui.Divider(c)
	ui.Text(c, m.T("Pin / unpin shortcut", "置顶 / 取消置顶快捷键")).Bold()
	ui.TextInput(c, &m.ShortcutDraft).Placeholder(core.DefaultShortcut)
	ui.Row(c).Gap(8).Children(func() {
		if ui.Button(c, m.T("Save shortcut", "保存快捷键")).Clicked() {
			m.Send(Action{Name: "shortcut", Value: m.ShortcutDraft})
		}
		if ui.Button(c, m.T("Reset shortcut", "重置快捷键")).Clicked() {
			m.ShortcutDraft = core.DefaultShortcut
			m.Send(Action{Name: "shortcut", Value: core.DefaultShortcut})
		}
	})
	ui.Text(c, m.T("Current: "+m.Settings.Shortcut, "当前："+m.Settings.Shortcut)).FontSize(12).TextColor(c.Theme().TextMuted)
	ui.Divider(c)
	ui.Text(c, m.T("Language", "语言")).Bold()
	ui.Row(c).Gap(8).Children(func() {
		for _, l := range []struct{ id, label string }{{"system", m.T("System", "跟随系统")}, {"en", "English"}, {"zh-Hans", "简体中文"}} {
			if ui.Button(c, l.label).Disabled(m.Settings.Language == l.id).Clicked() {
				m.Send(Action{Name: "language", Value: l.id})
			}
		}
	})
	ui.Divider(c)
	ui.Text(c, m.T("Permissions", "权限")).Bold()
	screen := m.T("Not granted", "未授权")
	if m.Screen {
		screen = m.T("Granted", "已授权")
	}
	ax := m.T("Not granted", "未授权")
	if m.Accessibility {
		ax = m.T("Granted", "已授权")
	}
	ui.Text(c, m.T("Screen Recording: ", "录屏权限：")+screen)
	ui.Text(c, m.T("Accessibility: ", "辅助功能：")+ax)
	ui.Row(c).Gap(8).Children(func() {
		if ui.Button(c, m.T("Screen Recording settings", "录屏权限设置")).Clicked() {
			m.Send(Action{Name: "screen-settings"})
		}
		if ui.Button(c, m.T("Accessibility settings", "辅助功能设置")).Clicked() {
			m.Send(Action{Name: "ax-settings"})
		}
	})
	ui.Divider(c)
	ui.Text(c, m.T("Software updates", "软件更新")).Bold()
	ui.Text(c, m.T("Checks happen only when you ask. Only signed MyGo packages can be installed.", "仅在你点击时检查，只接受签名的 MyGo 更新包。")).TextColor(c.Theme().TextMuted)
	switch m.UpdatePhase {
	case "checking":
		ui.Text(c, m.T("Checking…", "正在检查…"))
	case "current":
		ui.Text(c, m.T("Up to date.", "已是最新版本。"))
	case "unpublished":
		ui.Text(c, m.T("No signed MyGo release has been published yet.", "尚未发布签名的 MyGo 版本。"))
	case "available":
		ui.Text(c, m.T("Available: ", "可更新版本：")+m.UpdateVersion)
	case "installing":
		ui.Text(c, fmt.Sprintf(m.T("Downloading and verifying… %.0f%%", "正在下载并验证… %.0f%%"), m.Progress*100))
	case "cancelling":
		ui.Text(c, m.T("Cancelling…", "正在取消…"))
	case "cancelled":
		ui.Text(c, m.T("Update cancelled.", "更新已取消。"))
	}
	ui.Row(c).Gap(8).Wrap().Children(func() {
		busy := m.UpdatePhase == "checking" || m.UpdatePhase == "installing" || m.UpdatePhase == "cancelling"
		if ui.Button(c, m.T("Check for updates", "检查更新")).Disabled(busy).Clicked() {
			m.Send(Action{Name: "check-update"})
		}
		if m.UpdatePhase == "available" {
			if ui.PrimaryButton(c, m.T("Install and relaunch", "安装并重新启动")).Clicked() {
				m.Send(Action{Name: "install-update"})
			}
		}
		if busy {
			if ui.Button(c, m.T("Cancel update", "取消更新")).Disabled(m.UpdatePhase == "cancelling").Clicked() {
				m.Send(Action{Name: "cancel-update"})
			}
		}
	})
	if ui.Button(c, m.T("About Fuwa", "关于 Fuwa")).Clicked() {
		m.Send(Action{Name: "about"})
	}
}
