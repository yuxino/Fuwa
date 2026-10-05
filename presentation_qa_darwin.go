//go:build fuwa_parity_qa

package main

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"time"

	"github.com/egoist/mygo"
	"github.com/egoist/mygo/ui"
	"github.com/yuxino/Fuwa/internal/core"
	"github.com/yuxino/Fuwa/internal/native"
	"github.com/yuxino/Fuwa/internal/view"
)

// Opt-in native presentation test. No ScreenCaptureKit stream, permissions,
// login settings, update feed or existing preferences are touched. The fixture
// mirror is a MyGo view owned by this process, not captured desktop content.
func init() {
	if len(os.Args) != 2 || os.Args[1] != "--fuwa-parity-smoke" {
		return
	}
	dir := os.Getenv("FUWA_SMOKE_OUTPUT")
	if dir == "" {
		panic("--fuwa-parity-smoke requires FUWA_SMOKE_OUTPUT")
	}
	mygo.App.SetName("Fuwa MyGo Parity QA")
	mygo.App.SetVersion(core.Version)
	settings := core.Defaults()
	settings.Language = "en"
	settings.Shortcut = "Cmd+Alt+Shift+F19"
	a := &application{model: view.New(settings, "en"), settingsPath: filepath.Join(dir, "qa-settings.json"), done: make(chan struct{})}
	a.model.OnAction = a.act
	mygo.App.OnWindowAllClosed(func() {})
	mygo.App.OnBeforeQuit(func(*mygo.QuitEvent) { a.quitting = true; a.clear() })
	mygo.App.WhenReady(func() {
		// A conflict owned by this QA process exercises the actual OS path.
		qaRequire(mygo.GlobalShortcut.Register(settings.Shortcut, func() {}) == nil, "reserve QA shortcut")
		a.ready()
		close(a.done) // Fixture pins are reconciled explicitly, never against other apps.
		go a.presentationQA(dir)
	})
	if err := mygo.App.Run(); err != nil {
		panic(err)
	}
	os.Exit(0)
}

func qaRequire(ok bool, name string) {
	if !ok {
		panic("FAIL native parity: " + name)
	}
	fmt.Println("PASS native parity:", name)
}

func (a *application) presentationQA(dir string) {
	step := func(fn func()) {
		// Let AppKit deliver focus/deactivation events between actions.
		time.Sleep(250 * time.Millisecond)
		done := make(chan struct{})
		mygo.RunOnMain(func() { defer close(done); fn() })
		<-done
	}
	var p *pin
	step(func() {
		qaRequire(a.binding.Active == core.DefaultShortcut && a.model.Settings.Shortcut == core.DefaultShortcut, "OS shortcut conflict falls back to default")
		bounds := a.main.Bounds()
		p = &pin{Session: core.NewSession(1, core.Window{ID: 1, Title: "Presentation QA fixture", App: "Fuwa QA", Bounds: coreRect(bounds)})}
		p.State, p.HasFrame = core.Frozen, true
		p.mirror = mygo.NewWindow(mygo.WindowOptions{Title: "Fuwa QA fixture", Width: 500, Height: 320, Hidden: true, Frameless: true, AlwaysOnTop: true,
			Content: ui.View(func(c *ui.Context) { ui.Text(c, "Owned QA fixture — no screen capture") })})
		p.mirror.SetIgnoreMouseEvents(true)
		p.mirror.SetBounds(mygo.Rectangle{X: bounds.X + 40, Y: bounds.Y + 60, Width: 500, Height: 320})
		a.pins = append(a.pins, p)
		a.publish()
		p.mirror.ShowInactive()
		a.showMain()
	})
	step(func() {
		p.mirror.ShowInactive() // Reordering a mirror must not cover management.
		main, mirror := native.QAPresentation(uintptr(a.main.NativeHandle())), native.QAPresentation(uintptr(p.mirror.NativeHandle()))
		qaRequire(main.Level > mirror.Level && main.Order >= 0 && mirror.Order > main.Order, "management remains above reordered floating mirror")
		mygo.App.Hide()
	})
	step(func() {
		qaRequire(native.QAPresentation(uintptr(a.main.NativeHandle())).Level == 0, "deactivation restores normal management level")
		mygo.App.Show()
		a.showMain()
		p.mirror.ShowInactive()
		a.controls(p)
		qaRequire(p.controls != nil, "controls created for visible mirror")
	})
	step(func() {
		state := native.QAPresentation(uintptr(p.controls.NativeHandle()))
		qaRequire(state.Visible && state.Parent == uintptr(p.mirror.NativeHandle()), "controls are a visible native child of their mirror")
		bounds := p.mirror.Bounds()
		bounds.X += 70
		p.mirror.SetBounds(bounds)
		a.positionControls(p, workAreas())
		want := rect(core.ControlsBounds(coreRect(bounds), 450, 130, workAreas()))
		qaRequire(p.controls.Bounds() == want, "controls follow mirror inside work area")
		a.main.Focus()
	})
	step(func() {
		qaRequire(!p.controls.IsVisible(), "controls dismiss on blur")
		p.mirror.ShowInactive()
		qaRequire(!p.controls.IsVisible(), "mirror reorder does not reopen dismissed controls")
		a.controls(p)
		mygo.App.Hide()
	})
	step(func() {
		qaRequire(!p.controls.IsVisible(), "controls dismiss when application deactivates")
		mygo.App.Show()
		a.showMain()
		p.mirror.ShowInactive()
		// MyGo keeps at least a strip of a window on a real display. Simulate
		// removal by shrinking the supplied work-area inventory instead.
		area := workAreas()[0]
		bounds := p.mirror.Bounds()
		bounds.X = int(area.X + area.Width - float64(bounds.Width))
		p.mirror.SetBounds(bounds)
		before := p.mirror.Bounds()
		area.Width /= 2
		areas := []core.Rect{area}
		qaRequire(!coreRect(before).Intersects(area), "fixture lies outside simulated remaining display")
		source := p.Source
		a.reconcileDisplays(areas)
		qaRequire(p.mirror.Bounds() == rect(core.RecoverFrozenBounds(coreRect(before), areas)) && p.Source == source, "frozen mirror recovers without moving or replacing source")
		a.act(view.Action{Name: "language", Value: "zh-Hans"})
	})
	step(func() {
		titles := native.QAMenuTitles()
		qaRequire(slices.Contains(titles, "编辑") && slices.Contains(titles, "退出 Fuwa") && !slices.Contains(titles, "Edit"), "native menu switches to Chinese immediately")
		qaRequire(p.controls.Title() == "置顶控制", "existing controls title changes language")
		a.act(view.Action{Name: "language", Value: "en"})
	})
	step(func() {
		titles := native.QAMenuTitles()
		qaRequire(slices.Contains(titles, "Edit") && slices.Contains(titles, "Quit Fuwa") && !slices.Contains(titles, "编辑"), "native menu switches back to English")
		a.clear()
		a.publish()
		a.main.Hide()
		a.managementActive(true)
		state := native.QAPresentation(uintptr(a.main.NativeHandle()))
		qaRequire(!state.Visible && state.Level == 0, "hidden management stays hidden and normal")
		a.showMain()
	})
	step(func() {
		data, err := a.main.CapturePage()
		qaRequire(err == nil && len(data) > 0, "capture only QA app's own native UI")
		qaRequire(os.WriteFile(filepath.Join(dir, "native-parity.png"), data, 0600) == nil, "write own-window evidence")
		fmt.Println("PASS native parity complete: no screen capture or permissions requested")
		mygo.App.Quit()
	})
}
