package main

import (
	"bytes"
	"context"
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
	model               *view.Model
	main                *mygo.Window
	tray                *mygo.Tray
	pins                []*pin
	next                uint64
	settingsPath        string
	prepared            core.PreparedIntentSlot
	lastInventory       time.Time
	lastPermissions     time.Time
	fastTrackingUntil   time.Time
	operationGeneration uint64
	updater             *mygo.Update
	updateCancel        context.CancelFunc
	updateSerial        uint64
	done                chan struct{}
	quitting            bool
	binding             core.ShortcutBinding
}

func main() {
	mygo.App.SetName("Fuwa MyGo")
	mygo.App.SetVersion(core.Version)
	mygo.Theme.SetSource(mygo.ThemeLight)
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
	a.main.OnHide(func() { a.prepared.Clear(); a.managementActive(false); a.dock() })
	mygo.App.OnDidBecomeActive(func() { a.managementActive(true) })
	mygo.App.OnDidResignActive(func() {
		a.prepared.Clear()
		a.managementActive(false)
		for _, p := range a.pins {
			if p.controls != nil {
				p.controls.Hide()
			}
		}
	})
	a.updateMenus()
	var err error
	a.tray, err = mygo.NewTray(mygo.TrayOptions{Icon: trayIcon(), IconIsTemplate: true, ToolTip: "Fuwa MyGo"})
	if err != nil {
		a.model.Notice = a.model.T("The menu bar icon could not be created. Keep this window open.", "菜单栏图标创建失败，请保留此窗口。")
	}
	a.binding = core.ShortcutBinding{
		Register:   func(value string) error { return mygo.GlobalShortcut.Register(value, func() { a.front(false) }) },
		Unregister: mygo.GlobalShortcut.Unregister,
	}
	if err = a.binding.Start(a.model.Settings.Shortcut); err != nil {
		a.model.Notice = "shortcut_inactive"
		if a.binding.Active != "" {
			a.model.Notice = "shortcut_fallback"
			s := a.model.Settings
			s.Shortcut = a.binding.Active
			a.save(s)
			// The fallback is active in this process even if persistence failed.
			a.model.Settings = s
			a.model.ShortcutDraft = s.Shortcut
		}
	}
	mygo.Power.OnSuspend(func() { a.privacy() })
	mygo.Power.OnLockScreen(func() { a.privacy() })
	mygo.Screen.OnDisplaysChanged(func() {
		a.reconcileDisplays(workAreas())
		a.lastInventory = time.Time{}
		a.fastTrackingUntil = time.Now().Add(400 * time.Millisecond)
		a.tick()
	})
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
	if inv, err := native.Inventory(); err != nil {
		a.prepared.Replace(core.Window{}, fmt.Errorf("capture_unavailable"))
	} else if inv.Front != inv.Self {
		w, intentErr := core.Intent(inv)
		a.prepared.Replace(w, intentErr)
	}
	mygo.App.SetActivationPolicy(mygo.ActivationPolicyRegular)
	a.main.Show()
	a.managementActive(true)
	a.main.Focus()
	a.permissions()
	a.publish()
}
func (a *application) managementActive(active bool) {
	if a.main != nil {
		native.ManagementActive(uintptr(a.main.NativeHandle()), active)
	}
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
		disabled := !p.CanFreeze()
		if p.State == core.Frozen {
			mode = m.T("Resume", "恢复实时")
			action = "resume"
			disabled = !p.CanResume()
		} else if p.State == core.Failed {
			mode = m.T("Retry capture", "重试捕获")
			action = "retry"
			disabled = !p.CanRetry()
		}
		control := a.item(mode, func() { a.act(view.Action{Name: action, Token: token}) })
		control.Disabled = disabled
		reveal := a.item(m.T("Go to original", "跳转原窗口"), func() { a.act(view.Action{Name: "reveal", Token: token}) })
		reveal.Disabled = !p.CanReveal()
		controls := a.item(m.T("Controls", "控制面板"), func() { a.act(view.Action{Name: "controls", Token: token}) })
		controls.Disabled = !p.CanShowControls()
		items = append(items, &mygo.MenuItem{Label: p.Source.App + " — " + p.Source.Name(), Submenu: []*mygo.MenuItem{control, reveal, controls, a.item(m.T("Unpin", "取消置顶"), func() { a.act(view.Action{Name: "unpin", Token: token}) })}})
	}
	if len(a.pins) > 0 {
		items = append(items, a.item(m.T("Clear all", "全部取消"), func() { a.clear(); a.publish() }))
	}
	items = append(items, mygo.Separator(), a.item(m.T("Settings…", "设置…"), func() { m.Route = "settings"; a.showMain() }), &mygo.MenuItem{Role: mygo.RoleQuit, Label: m.T("Quit Fuwa", "退出 Fuwa")})
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
	if a.quitting {
		return
	}
	// Claim before any permission UI can change focus or close management.
	prepared, preparedErr, hasPrepared := a.prepared.Consume()
	var w core.Window
	var err error
	if usePrepared {
		if !hasPrepared {
			err = core.ErrNoWindow
		} else {
			w, err = prepared, preparedErr
		}
	} else {
		inv, inventoryErr := native.Inventory()
		if inventoryErr != nil {
			a.model.Notice = "capture_unavailable"
			a.publish()
			return
		}
		w, err = core.Intent(inv)
	}
	if err != nil {
		a.model.Notice = err.Error()
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
	if a.quitting {
		return
	}
	a.prepared.Clear()
	operation := a.operationGeneration
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
			// Remember the request in this process even when the settings file
			// could not be saved, so repeated clicks do not repeat the prompt.
			a.model.Settings.AskedScreen = true
			native.RequestScreen()
		}
		if !native.ScreenAllowed() {
			a.model.Notice = "screen_permission"
			a.permissions()
			a.publish()
			return
		}
	}
	if a.quitting || operation != a.operationGeneration {
		return
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
	// Eligibility selected the visual target before permission UI appeared.
	// Revalidate its identity and geometry, without selecting again or rejecting
	// the same window solely because it moved to another Space in the meantime.
	if !captureBoundsValid(current.Bounds) {
		a.model.Notice = "capture_unavailable"
		a.publish()
		return
	}
	// A native permission dialog may run a nested event loop. Recheck the
	// reservation after it closes, including clears/quits during that dialog.
	if a.quitting || operation != a.operationGeneration {
		return
	}
	for _, existing := range a.pins {
		if existing.Source.Same(current) {
			return
		}
	}
	if len(a.pins) >= core.MaxPins {
		a.model.Notice = "pin_limit"
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
	a.fastTrackingUntil = time.Now().Add(400 * time.Millisecond)
	a.publish()
}
func rect(r core.Rect) mygo.Rectangle {
	return mygo.Rectangle{X: int(math.Round(r.X)), Y: int(math.Round(r.Y)), Width: int(math.Round(r.Width)), Height: int(math.Round(r.Height))}
}
func coreRect(r mygo.Rectangle) core.Rect {
	return core.Rect{X: float64(r.X), Y: float64(r.Y), Width: float64(r.Width), Height: float64(r.Height)}
}
func workAreas() []core.Rect {
	var areas []core.Rect
	for _, display := range mygo.Screen.Displays() {
		areas = append(areas, coreRect(display.WorkArea))
	}
	return areas
}
func (a *application) reconcileDisplays(areas []core.Rect) {
	for _, p := range a.pins {
		if p.State == core.Frozen {
			bounds := p.mirror.Bounds()
			if recovered := rect(core.RecoverFrozenBounds(coreRect(bounds), areas)); recovered != bounds {
				p.mirror.SetBounds(recovered)
			}
		}
		a.positionControls(p, areas)
	}
}
func (a *application) positionControls(p *pin, areas []core.Rect) {
	if p.controls != nil {
		bounds := rect(core.ControlsBounds(coreRect(p.mirror.Bounds()), 450, 130, areas))
		if p.controls.Bounds() != bounds {
			p.controls.SetBounds(bounds)
		}
	}
}
func (a *application) scale(r core.Rect) float64 {
	scale := float64(mygo.Screen.DisplayMatching(rect(r)).ScaleFactor)
	if math.IsNaN(scale) || math.IsInf(scale, 0) || scale < 1 {
		return 1
	}
	return scale
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
	a.operationGeneration++
	a.prepared.Clear()
	for len(a.pins) > 0 {
		a.unpin(a.pins[len(a.pins)-1].Token)
	}
}
func (a *application) privacy() {
	a.clear()
	a.model.Choices = nil
	a.model.Notice = "privacy_cleared"
	a.publish()
}
func (a *application) freeze(p *pin) {
	if p == nil || !p.CanFreeze() {
		return
	}
	if err := native.Freeze(p.Token); err != nil {
		a.model.Notice = err.Error()
		return
	}
	_ = p.Freeze("")
}
func (a *application) resume(p *pin) {
	if p == nil || !p.CanResume() {
		return
	}
	a.restart(p, false)
}
func (a *application) retry(p *pin) {
	if p == nil || !p.CanRetry() {
		return
	}
	a.restart(p, true)
}
func (a *application) restart(p *pin, retry bool) {
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
	if !captureBoundsValid(w.Bounds) {
		p.Error = "capture_unavailable"
		return
	}
	// An exact source on another Space or minimized is still eligible for
	// desktop-independent capture. ScreenCaptureKit confirms shareability.
	if retry {
		err = p.Retry(w)
	} else {
		err = p.Resume(w)
	}
	if err != nil {
		a.model.Notice = err.Error()
		return
	}
	p.mirror.SetBounds(rect(w.Bounds))
	p.scale = a.scale(w.Bounds)
	native.Start(p.Token, p.Generation, w, uintptr(p.mirror.NativeHandle()))
	native.Resize(p.Token, w.Bounds, p.scale)
	a.lastInventory = time.Time{}
	a.fastTrackingUntil = time.Now().Add(400 * time.Millisecond)
	a.model.Notice = ""
}
func (a *application) controls(p *pin) {
	if p == nil || !p.mirror.IsVisible() {
		return
	}
	if p.controls == nil {
		controls := mygo.NewWindow(mygo.WindowOptions{Title: a.model.T("Pin controls", "置顶控制"), Content: ui.View(a.model.Controls(p.Token)), Width: 450, Height: 130, Hidden: true, AlwaysOnTop: true, DisableResize: true, Parent: p.mirror})
		p.controls = controls
		controls.SetContentProtection(true)
		controls.SetVisibleOnAllWorkspaces(true)
		controls.OnBlur(controls.Hide)
		controls.OnClosed(func() { p.controls = nil })
	}
	a.reconcileDisplays(workAreas())
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
	s := a.model.Settings
	s.Shortcut = value
	a.model.Notice = ""
	if !a.binding.Replace(value, func() bool { return a.save(s) }) {
		if a.model.Notice == "" {
			a.model.Notice = "shortcut_conflict"
			if a.binding.Active == "" {
				a.model.Notice = "shortcut_inactive"
			}
		}
		return
	}
	a.model.ShortcutDraft = value
	a.model.Notice = ""
}
func (a *application) act(action view.Action) {
	if a.quitting {
		return
	}
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
	case "retry":
		a.retry(p)
	case "controls":
		a.controls(p)
	case "hide-controls":
		if p != nil && p.controls != nil {
			p.controls.Hide()
		}
	case "reveal":
		if p != nil && p.CanReveal() {
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
		if a.save(s) {
			a.updateMenus()
			for _, p := range a.pins {
				if p.controls != nil {
					p.controls.SetTitle(a.model.T("Pin controls", "置顶控制"))
				}
			}
		}
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
		mygo.App.ShowAboutPanel(mygo.AboutPanelOptions{})
	case "check-update":
		a.checkUpdate()
	case "install-update":
		a.installUpdate()
	case "cancel-update":
		a.cancelUpdate()
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
	dirty, cleared := a.consumeEvents(list)
	if cleared {
		return
	}
	if err != nil && a.model.Notice != "capture_unavailable" {
		a.model.Notice = "capture_unavailable"
		dirty = true
	}
	now := time.Now()
	if now.Sub(a.lastPermissions) >= 500*time.Millisecond {
		a.lastPermissions = now
		dirty = a.permissions() || dirty
		if len(a.pins) > 0 && !a.model.Screen {
			a.privacy()
			a.model.Notice = "screen_permission"
			a.publish()
			return
		}
	}
	if a.needsTracking() && now.Sub(a.lastInventory) >= a.inventoryInterval(now) {
		a.lastInventory = now
		inv, err := native.Inventory()
		if err != nil {
			// An unavailable inventory is not an empty one. Keep every exact
			// source alive until WindowServer can provide a real observation.
			if a.model.Notice != "capture_unavailable" {
				a.model.Notice = "capture_unavailable"
				dirty = true
			}
		} else {
			for _, p := range a.pins {
				if p.State != core.Live && p.State != core.Starting {
					continue
				}
				w, ok := core.Exact(inv, p.Source)
				if !ok {
					p.Missing++
					if p.Missing >= 2 {
						a.sourceClosed(p)
						dirty = true
					}
					continue
				}
				scale := p.scale
				if captureBoundsValid(w.Bounds) {
					scale = a.scale(w.Bounds)
				}
				dirty = a.trackWindow(p, w, scale) || dirty
			}
		}
	}
	if dirty {
		a.publish()
	}
}

// consumeEvents is shared by the real native event pump and owned-window QA.
// Native frame ownership is authoritative; Go controls only presentation/state.
func (a *application) consumeEvents(list []native.Event) (dirty, cleared bool) {
	// A privacy event dominates older queued live events: never re-show a cleared mirror.
	for _, e := range list {
		if e.Kind == "privacy" || e.Message == "screen_permission" {
			a.privacy()
			if e.Message == "screen_permission" {
				a.model.Notice = "screen_permission"
				a.publish()
			}
			return true, true
		}
	}
	for _, e := range list {
		p := a.find(e.Token)
		if p == nil || p.Generation != e.Generation || p.State == core.Stopped {
			continue
		}
		switch e.Kind {
		case "live":
			if p.ReceiveFrame(e.Generation) {
				p.mirror.ShowInactive()
				native.Presented(p.Token, p.Generation)
				dirty = true
			}
		case "failed", "frozen":
			p.HasFrame = e.Kind == "frozen"
			if p.Fail(e.Generation, e.Message) {
				dirty = true
				if e.Message == "source_closed" {
					p.Closed = true
				}
				if p.HasFrame {
					// A source can close between the native first frame and Go's
					// first live event. Its independent still must remain visible.
					p.mirror.ShowInactive()
				} else {
					p.mirror.Hide()
					if p.controls != nil {
						p.controls.Hide()
					}
				}
			}
		}
	}
	return dirty, false
}

func (a *application) sourceClosed(p *pin) {
	if p.HasFrame && native.Freeze(p.Token) == nil {
		_ = p.Freeze("source_closed")
		p.mirror.ShowInactive()
	} else {
		native.Stop(p.Token)
		p.HasFrame = false
		p.Fail(p.Generation, "source_closed")
		p.mirror.Hide()
		if p.controls != nil {
			p.controls.Hide()
		}
	}
	p.Closed = true
}

func (a *application) needsTracking() bool {
	for _, p := range a.pins {
		if p.State == core.Starting || p.State == core.Live {
			return true
		}
	}
	return false
}
func (a *application) inventoryInterval(now time.Time) time.Duration {
	if now.Before(a.fastTrackingUntil) {
		return 100 * time.Millisecond
	}
	return 250 * time.Millisecond
}
func captureBoundsValid(r core.Rect) bool {
	for _, value := range []float64{r.X, r.Y, r.Width, r.Height} {
		if math.IsNaN(value) || math.IsInf(value, 0) {
			return false
		}
	}
	return r.Width > 0 && r.Height > 0
}

// Visibility is not liveness: moving to another Space or minimizing a source
// must not turn a healthy desktop-independent capture into a manual freeze.
func (a *application) trackWindow(p *pin, w core.Window, scale float64) bool {
	if !p.Source.Same(w) {
		return false
	}
	p.Missing = 0
	dirty := w.Title != p.Source.Title || w.App != p.Source.App
	if !captureBoundsValid(w.Bounds) {
		w.Bounds = p.Source.Bounds
		scale = p.scale
	}
	if math.IsNaN(scale) || math.IsInf(scale, 0) || scale < 1 {
		scale = p.scale
	}
	if w.Bounds != p.Source.Bounds || scale != p.scale {
		p.mirror.SetBounds(rect(w.Bounds))
		a.positionControls(p, workAreas())
		native.Resize(p.Token, w.Bounds, scale)
		p.scale = scale
		a.fastTrackingUntil = time.Now().Add(400 * time.Millisecond)
	}
	p.Source = w
	return dirty
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
