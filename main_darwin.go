package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"log"
	"math"
	"path/filepath"
	"strings"
	"time"

	"github.com/egoist/mygo"
	"github.com/egoist/mygo/ui"
	"github.com/yuxino/Fuwa/internal/core"
	"github.com/yuxino/Fuwa/internal/native"
	"github.com/yuxino/Fuwa/internal/view"
)

type pin struct {
	core.Session
	mirror, controls *mygo.Window
	scale            float64
}
type application struct {
	model         *view.Model
	main          *mygo.Window
	tray          *mygo.Tray
	pins          []*pin
	next          uint64
	settingsPath  string
	prepared      *core.Window
	lastInventory time.Time
	updater       *mygo.Update
	updateCancel  context.CancelFunc
	updateSerial  uint64
	done          chan struct{}
	quitting      bool
}

func main() {
	mygo.App.SetName("Fuwa MyGo")
	mygo.App.SetVersion(core.Version)
	path, err := mygo.App.Path(mygo.PathUserData)
	if err != nil {
		log.Fatal("Cannot open Fuwa MyGo preferences directory")
	}
	settingsPath := filepath.Join(path, "settings.json")
	settings, settingsErr := core.LoadSettings(settingsPath)
	a := &application{model: view.New(settings, mygo.App.Locale()), settingsPath: settingsPath, done: make(chan struct{})}
	if settingsErr != nil {
		a.model.Notice = "settings_reset"
	}
	a.model.OnAction = a.act
	if !mygo.App.RequestSingleInstanceLock() {
		return
	}
	if !settings.KeepDock {
		mygo.App.SetActivationPolicy(mygo.ActivationPolicyAccessory)
	}
	mygo.App.OnWindowAllClosed(func() {})
	mygo.App.OnActivate(func(bool) { a.showMain() })
	mygo.App.OnSecondInstance(func([]string, string) { a.showMain() })
	mygo.App.OnBeforeQuit(func(e *mygo.QuitEvent) {
		a.quitting = true
		a.clear()
		if a.updateCancel != nil {
			a.updateCancel()
		}
	})
	mygo.App.OnQuit(func() { close(a.done) })
	mygo.App.WhenReady(func() { a.ready() })
	if err := mygo.App.Run(); err != nil {
		log.Fatal(err)
	}
}
func (a *application) ready() {
	native.Initialize()
	a.main = mygo.NewWindow(mygo.WindowOptions{Title: "Fuwa MyGo", Content: ui.View(a.model.Render), Width: 780, Height: 720, MinWidth: 660, MinHeight: 520, Hidden: true, StateKey: "main"})
	a.main.OnClose(func(e *mygo.CloseEvent) {
		if !a.quitting {
			e.PreventDefault()
			a.main.Hide()
			a.dock()
		}
	})
	a.main.OnHide(a.dock)
	mygo.App.SetMenu(mygo.NewMenu([]*mygo.MenuItem{
		{Role: mygo.RoleAppMenu},
		{Label: "Fuwa", Submenu: []*mygo.MenuItem{
			a.item(a.model.T("Show Fuwa", "显示 Fuwa"), func() { a.showMain() }),
			a.item(a.model.T("Pin front window", "置顶前方窗口"), func() { a.front(false) }),
			a.item(a.model.T("Clear all pins", "全部取消置顶"), func() { a.clear(); a.publish() }),
		}},
		{Role: mygo.RoleEditMenu}, {Role: mygo.RoleWindowMenu},
	}))
	var err error
	a.tray, err = mygo.NewTray(mygo.TrayOptions{Icon: trayIcon(), IconIsTemplate: true, ToolTip: "Fuwa MyGo"})
	if err != nil {
		a.model.Notice = a.model.T("The menu bar icon could not be created. Keep this window open.", "菜单栏图标创建失败，请保留此窗口。")
	}
	if err = mygo.GlobalShortcut.Register(a.model.Settings.Shortcut, func() { a.front(false) }); err != nil {
		a.model.Notice = "shortcut_inactive"
	}
	mygo.Power.OnSuspend(func() { a.privacy() })
	mygo.Power.OnLockScreen(func() { a.privacy() })
	mygo.Screen.OnDisplaysChanged(func() { a.lastInventory = time.Time{}; a.tick() })
	a.permissions()
	a.publish()
	if !mygo.App.WasOpenedAtLogin() || a.tray == nil {
		a.showMain()
	} else {
		a.dock()
	}
	go func() {
		ticker := time.NewTicker(100 * time.Millisecond)
		defer ticker.Stop()
		for {
			select {
			case <-a.done:
				return
			case <-ticker.C:
				mygo.RunOnMain(a.tick)
			}
		}
	}()
}
func (a *application) item(label string, fn func()) *mygo.MenuItem {
	return &mygo.MenuItem{Label: label, Click: func(*mygo.MenuItem, *mygo.Window) { fn() }}
}
func (a *application) showMain() {
	if a.main == nil || a.quitting {
		return
	}
	if inv, err := native.Inventory(); err == nil && inv.Front != inv.Self {
		if w, e := core.Intent(inv); e == nil {
			a.prepared = &w
		} else {
			a.prepared = nil
		}
	}
	mygo.App.SetActivationPolicy(mygo.ActivationPolicyRegular)
	a.main.Show()
	a.main.Focus()
	a.permissions()
	a.publish()
}
func (a *application) dock() {
	regular := a.model.Settings.KeepDock || (a.main != nil && a.main.IsVisible())
	if regular {
		mygo.App.SetActivationPolicy(mygo.ActivationPolicyRegular)
	} else {
		mygo.App.SetActivationPolicy(mygo.ActivationPolicyAccessory)
	}
}
func (a *application) permissions() bool {
	screen, ax, login := native.ScreenAllowed(), native.AccessibilityAllowed(), native.LoginState()
	changed := a.model.Screen != screen || a.model.Accessibility != ax || a.model.LoginState != login
	a.model.Screen = screen
	a.model.Accessibility = ax
	a.model.LoginState = login
	return changed
}
func (a *application) publish() {
	a.model.Pins = make([]core.Session, 0, len(a.pins))
	for _, p := range a.pins {
		a.model.Pins = append(a.model.Pins, p.Session)
		if p.controls != nil {
			p.controls.Invalidate()
		}
	}
	if a.main != nil {
		a.main.Invalidate()
	}
	if a.tray == nil {
		return
	}
	m := a.model
	items := []*mygo.MenuItem{a.item(m.T("Open Fuwa", "打开 Fuwa"), a.showMain), a.item(m.T("Pin front window", "置顶前方窗口")+"  "+m.Settings.Shortcut, func() { a.front(false) }), mygo.Separator()}
	for _, p := range a.pins {
		token := p.Token
		mode := m.T("Freeze", "冻结画面")
		action := "freeze"
		disabled := p.State != core.Live
		if p.State == core.Frozen {
			mode = m.T("Resume", "恢复实时")
			action = "resume"
			disabled = p.Closed
		}
		control := a.item(mode, func() { a.act(view.Action{Name: action, Token: token}) })
		control.Disabled = disabled
		reveal := a.item(m.T("Go to original", "跳转原窗口"), func() { a.act(view.Action{Name: "reveal", Token: token}) })
		reveal.Disabled = p.Closed
		items = append(items, &mygo.MenuItem{Label: p.Source.App + " — " + p.Source.Name(), Submenu: []*mygo.MenuItem{control, reveal, a.item(m.T("Controls", "控制面板"), func() { a.act(view.Action{Name: "controls", Token: token}) }), a.item(m.T("Unpin", "取消置顶"), func() { a.act(view.Action{Name: "unpin", Token: token}) })}})
	}
	if len(a.pins) > 0 {
		items = append(items, a.item(m.T("Clear all", "全部取消"), func() { a.clear(); a.publish() }))
	}
	items = append(items, mygo.Separator(), a.item(m.T("Settings…", "设置…"), func() { m.Route = "settings"; a.showMain() }), &mygo.MenuItem{Role: mygo.RoleQuit})
	a.tray.SetMenu(mygo.NewMenu(items))
	a.tray.SetToolTip(fmt.Sprintf("Fuwa MyGo · %d", len(a.pins)))
}
func (a *application) save(s core.Settings) bool {
	if err := core.SaveSettings(a.settingsPath, s); err != nil {
		a.model.Notice = "settings_failed"
		return false
	}
	a.model.Settings = s
	return true
}
func (a *application) front(usePrepared bool) {
	inv, err := native.Inventory()
	if err != nil {
		a.model.Notice = "capture_unavailable"
		a.publish()
		return
	}
	var w core.Window
	if usePrepared && inv.Front == inv.Self && a.prepared != nil {
		w = *a.prepared
	} else {
		w, err = core.Intent(inv)
	}
	if err != nil {
		a.model.Notice = "no_window"
		a.publish()
		return
	}
	// Visual intent is already immutable before asking for any permission.
	for _, p := range a.pins {
		if p.Source.Same(w) {
			a.unpin(p.Token)
			a.publish()
			return
		}
	}
	a.add(w)
}
func (a *application) add(w core.Window) {
	if len(a.pins) >= core.MaxPins {
		a.model.Notice = "pin_limit"
		a.publish()
		return
	}
	for _, p := range a.pins {
		if p.Source.Same(w) {
			return
		}
	}
	if !native.ScreenAllowed() {
		if !a.model.Settings.AskedScreen {
			s := a.model.Settings
			s.AskedScreen = true
			a.save(s)
			native.RequestScreen()
		}
		if !native.ScreenAllowed() {
			a.model.Notice = "screen_permission"
			a.permissions()
			a.publish()
			return
		}
	}
	inv, err := native.Inventory()
	if err != nil {
		a.model.Notice = "capture_unavailable"
		a.publish()
		return
	}
	current, ok := core.Exact(inv, w)
	if !ok {
		a.model.Notice = "source_closed"
		a.publish()
		return
	}
	if !core.Eligible(current, inv) {
		a.model.Notice = "no_window"
		a.publish()
		return
	}
	a.next++
	p := &pin{Session: core.NewSession(a.next, current)}
	r := current.Bounds
	p.mirror = mygo.NewWindow(mygo.WindowOptions{Title: "Fuwa mirror", Content: ui.View(func(*ui.Context) {}), Width: int(r.Width), Height: int(r.Height), Hidden: true, Frameless: true, Transparent: true, AlwaysOnTop: true, DisableResize: true, DisableMove: true, DisableMinimize: true, DisableMaximize: true, DisableFullScreen: true, DisableShadow: true})
	p.mirror.SetIgnoreMouseEvents(true)
	p.mirror.SetContentProtection(true)
	p.mirror.SetVisibleOnAllWorkspaces(true)
	p.mirror.SetBounds(rect(r))
	p.scale = a.scale(r)
	a.pins = append(a.pins, p)
	a.model.Notice = ""
	native.Start(p.Token, p.Generation, p.Source, uintptr(p.mirror.NativeHandle()))
	native.Resize(p.Token, r, p.scale)
	a.lastInventory = time.Time{}
	a.publish()
}
func rect(r core.Rect) mygo.Rectangle {
	return mygo.Rectangle{X: int(math.Round(r.X)), Y: int(math.Round(r.Y)), Width: int(math.Round(r.Width)), Height: int(math.Round(r.Height))}
}
func (a *application) scale(r core.Rect) float64 {
	return float64(mygo.Screen.DisplayMatching(rect(r)).ScaleFactor)
}
func (a *application) find(token uint64) *pin {
	for _, p := range a.pins {
		if p.Token == token {
			return p
		}
	}
	return nil
}
func (a *application) unpin(token uint64) {
	for i, p := range a.pins {
		if p.Token != token {
			continue
		}
		p.Stop()
		native.Stop(token)
		if p.controls != nil {
			p.controls.Destroy()
		}
		p.mirror.Destroy()
		a.pins = append(a.pins[:i], a.pins[i+1:]...)
		return
	}
}
func (a *application) clear() {
	for len(a.pins) > 0 {
		a.unpin(a.pins[len(a.pins)-1].Token)
	}
}
func (a *application) privacy() { a.clear(); a.model.Notice = "privacy_cleared"; a.publish() }
func (a *application) freeze(p *pin) {
	if p == nil || p.State != core.Live {
		return
	}
	if err := native.Freeze(p.Token); err != nil {
		a.model.Notice = err.Error()
		return
	}
	_ = p.Freeze("")
}
func (a *application) resume(p *pin) {
	if p == nil || p.State != core.Frozen || p.Closed {
		return
	}
	if !native.ScreenAllowed() {
		a.privacy()
		a.model.Notice = "screen_permission"
		return
	}
	inv, err := native.Inventory()
	if err != nil {
		a.model.Notice = "capture_unavailable"
		return
	}
	w, ok := core.Exact(inv, p.Source)
	if !ok {
		p.Closed = true
		p.Error = "source_closed"
		return
	}
	if !w.Onscreen {
		p.Error = "no_window"
		return
	}
	if err := p.Resume(w); err != nil {
		a.model.Notice = err.Error()
		return
	}
	p.mirror.SetBounds(rect(w.Bounds))
	p.scale = a.scale(w.Bounds)
	native.Start(p.Token, p.Generation, w, uintptr(p.mirror.NativeHandle()))
	native.Resize(p.Token, w.Bounds, p.scale)
}
func (a *application) controls(p *pin) {
	if p == nil {
		return
	}
	if p.controls == nil {
		p.controls = mygo.NewWindow(mygo.WindowOptions{Title: a.model.T("Pin controls", "置顶控制"), Content: ui.View(a.model.Controls(p.Token)), Width: 450, Height: 130, Hidden: true, AlwaysOnTop: true, DisableResize: true})
		p.controls.OnClosed(func() { p.controls = nil })
	}
	p.controls.Show()
	p.controls.Focus()
}
func (a *application) refresh() {
	inv, err := native.Inventory()
	if err != nil {
		a.model.Notice = "capture_unavailable"
		return
	}
	a.model.Choices = nil
	for _, w := range inv.Windows {
		if core.Eligible(w, inv) {
			a.model.Choices = append(a.model.Choices, w)
		}
	}
}
func (a *application) shortcut(value string) {
	value = strings.TrimSpace(value)
	if err := core.ValidateShortcut(value); err != nil {
		a.model.Notice = "invalid_shortcut"
		return
	}
	previous := a.model.Settings.Shortcut
	if strings.EqualFold(value, previous) {
		return
	}
	if err := mygo.GlobalShortcut.Register(value, func() { a.front(false) }); err != nil {
		a.model.Notice = "shortcut_conflict"
		return
	}
	s := a.model.Settings
	s.Shortcut = value
	if !a.save(s) {
		mygo.GlobalShortcut.Unregister(value)
		return
	}
	mygo.GlobalShortcut.Unregister(previous)
	a.model.ShortcutDraft = value
	a.model.Notice = ""
}
func (a *application) act(action view.Action) {
	p := a.find(action.Token)
	switch action.Name {
	case "pin-front":
		a.front(true)
	case "pin":
		a.add(action.Window)
	case "refresh":
		a.refresh()
	case "unpin":
		a.unpin(action.Token)
	case "clear":
		a.clear()
	case "freeze":
		a.freeze(p)
	case "resume":
		a.resume(p)
	case "controls":
		a.controls(p)
	case "reveal":
		if p != nil && !p.Closed {
			if err := native.Reveal(p.Source); err != nil {
				a.model.Notice = err.Error()
			}
			a.permissions()
		}
	case "dock":
		s := a.model.Settings
		s.KeepDock = action.Enabled
		if a.save(s) {
			a.dock()
		}
	case "language":
		s := a.model.Settings
		s.Language = action.Value
		a.save(s)
	case "shortcut":
		a.shortcut(action.Value)
	case "login":
		if err := native.SetLogin(action.Enabled); err != nil {
			a.model.Notice = err.Error()
		}
		a.permissions()
	case "screen-settings":
		a.open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
	case "ax-settings":
		a.open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
	case "login-settings":
		a.open("x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
	case "about":
		mygo.App.ShowAboutPanel()
	case "check-update":
		a.checkUpdate()
	case "install-update":
		a.installUpdate()
	case "cancel-update":
		if a.updateCancel != nil {
			a.updateCancel()
		}
		a.model.UpdatePhase = "cancelled"
	}
	a.publish()
}
func (a *application) open(url string) {
	if err := mygo.Shell.OpenExternal(url); err != nil {
		a.model.Notice = a.model.T("System Settings could not be opened.", "无法打开系统设置。")
	}
}
func (a *application) tick() {
	if a.quitting {
		return
	}
	list, err := native.Events()
	if err != nil {
		return
	}
	// A privacy event dominates older queued live events: never re-show a cleared mirror.
	for _, e := range list {
		if e.Kind == "privacy" || e.Message == "screen_permission" {
			a.privacy()
			if e.Message == "screen_permission" {
				a.model.Notice = "screen_permission"
				a.publish()
			}
			return
		}
	}
	dirty := false
	for _, e := range list {
		p := a.find(e.Token)
		if p == nil || p.Generation != e.Generation {
			continue
		}
		switch e.Kind {
		case "live":
			if p.ReceiveFrame(e.Generation) {
				p.mirror.ShowInactive()
				dirty = true
			}
		case "failed", "frozen":
			if p.Fail(e.Generation, e.Message) {
				dirty = true
				if e.Message == "source_closed" {
					p.Closed = true
				}
			}
		}
	}
	if time.Since(a.lastInventory) >= 500*time.Millisecond {
		a.lastInventory = time.Now()
		dirty = a.permissions() || dirty
		if len(a.pins) > 0 && !a.model.Screen {
			a.privacy()
			a.model.Notice = "screen_permission"
			a.publish()
			return
		}
		tracking := false
		for _, p := range a.pins {
			if p.State == core.Live || p.State == core.Starting {
				tracking = true
				break
			}
		}
		if tracking {
			inv, err := native.Inventory()
			if err == nil {
				for _, p := range a.pins {
					if p.State != core.Live && p.State != core.Starting {
						continue
					}
					w, ok := core.Exact(inv, p.Source)
					if !ok {
						p.Missing++
						if p.Missing < 2 {
							continue
						}
						if p.HasFrame {
							if err := native.Freeze(p.Token); err == nil {
								_ = p.Freeze("source_closed")
							} else {
								native.Stop(p.Token)
								p.Fail(p.Generation, "source_closed")
							}
						}
						if !p.HasFrame {
							native.Stop(p.Token)
							p.Fail(p.Generation, "source_closed")
						}
						p.Closed = true
						dirty = true
						continue
					}
					p.Missing = 0
					if !w.Onscreen && p.State == core.Live {
						a.freeze(p)
						p.Error = "capture_interrupted"
						dirty = true
						continue
					}
					if w.Title != p.Source.Title {
						dirty = true
					}
					scale := a.scale(w.Bounds)
					if w.Bounds != p.Source.Bounds || scale != p.scale {
						p.mirror.SetBounds(rect(w.Bounds))
						native.Resize(p.Token, w.Bounds, scale)
						p.scale = scale
					}
					p.Source = w
				}
			}
		}
	}
	if dirty {
		a.publish()
	}
}
func (a *application) checkUpdate() {
	if a.model.UpdatePhase == "checking" || a.model.UpdatePhase == "installing" {
		return
	}
	if !mygo.Updater.Enabled() {
		a.model.Notice = "preview_updates"
		return
	}
	a.updateSerial++
	serial := a.updateSerial
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	a.updateCancel = cancel
	a.model.UpdatePhase = "checking"
	a.model.Notice = ""
	a.updater = nil
	go func() {
		defer cancel()
		up, err := mygo.Updater.Check(ctx)
		mygo.RunOnMain(func() {
			if serial != a.updateSerial || a.quitting {
				return
			}
			a.updateCancel = nil
			switch {
			case errors.Is(err, context.Canceled):
				a.model.UpdatePhase = "cancelled"
			case err != nil && strings.Contains(err.Error(), "no release is published"):
				a.model.UpdatePhase = "unpublished"
			case err != nil:
				a.model.UpdatePhase = "idle"
				a.model.Notice = "update_failed"
			case up == nil:
				a.model.UpdatePhase = "current"
			default:
				a.updater = up
				a.model.UpdatePhase = "available"
				a.model.UpdateVersion = up.Version
			}
			a.publish()
		})
	}()
}
func (a *application) installUpdate() {
	if a.updater == nil || a.model.UpdatePhase != "available" {
		return
	}
	up := a.updater
	a.updateSerial++
	serial := a.updateSerial
	ctx, cancel := context.WithCancel(context.Background())
	a.updateCancel = cancel
	a.model.UpdatePhase = "installing"
	a.model.Progress = 0
	go func() {
		defer cancel()
		err := up.Install(ctx, func(n, total int64) {
			mygo.RunOnMain(func() {
				if serial == a.updateSerial && total > 0 && !a.quitting {
					a.model.Progress = math.Min(1, float64(n)/float64(total))
					a.main.Invalidate()
				}
			})
		})
		mygo.RunOnMain(func() {
			if serial != a.updateSerial || a.quitting {
				return
			}
			a.updateCancel = nil
			if errors.Is(err, context.Canceled) {
				a.model.UpdatePhase = "cancelled"
			} else if err != nil {
				a.model.UpdatePhase = "available"
				a.model.Notice = "update_failed"
			} else {
				a.clear()
				mygo.App.Relaunch()
			}
			a.publish()
		})
	}()
}
func trayIcon() []byte {
	img := image.NewNRGBA(image.Rect(0, 0, 32, 32))
	black := color.NRGBA{A: 255}
	for y := 4; y < 29; y++ {
		for x := 6; x < 26; x++ {
			if (y <= 8 && x >= 9 && x <= 23) || (y > 8 && y < 18 && x >= 12 && x <= 20) || (y >= 18 && y <= 21) || (y > 21 && x >= 15 && x <= 17) {
				img.SetNRGBA(x, y, black)
			}
		}
	}
	var b bytes.Buffer
	_ = png.Encode(&b, img)
	return b.Bytes()
}
