package view

import (
	"github.com/egoist/mygo/ui"
	"github.com/yuxino/Fuwa/internal/core"
	"image/png"
	"os"
	"path/filepath"
	"testing"
)

func fixture() *Model {
	m := New(core.Defaults(), "en-US")
	m.Screen = true
	m.Pins = []core.Session{
		{Token: 1, Generation: 1, Source: core.Window{ID: 7, PID: 4, App: "Preview", Title: "Layout reference.pdf"}, State: core.Live, HasFrame: true},
		{Token: 2, Generation: 1, Source: core.Window{ID: 8, PID: 5, App: "Safari", Title: "A small guide to making things"}, State: core.Frozen, HasFrame: true},
	}
	return m
}
func TestNoPermissionRequestOnRender(t *testing.T) {
	m := New(core.Defaults(), "en-US")
	calls := 0
	m.OnAction = func(Action) { calls++ }
	tt := ui.NewTester(m.Render, 780, 720)
	if calls != 0 || !tt.HasText("Keep a window in view.") {
		t.Fatalf("unexpected startup: actions=%d texts=%v", calls, tt.Texts())
	}
}
func TestPinActions(t *testing.T) {
	for _, tc := range []struct {
		label, action string
		token         uint64
	}{{"Freeze", "freeze", 1}, {"Resume", "resume", 2}, {"Clear all", "clear", 0}} {
		t.Run(tc.action, func(t *testing.T) {
			m := fixture()
			var got Action
			m.OnAction = func(a Action) { got = a }
			tt := ui.NewTester(m.Render, 780, 800)
			if err := tt.Click(tc.label); err != nil {
				t.Fatal(err)
			}
			if got.Name != tc.action || got.Token != tc.token {
				t.Fatalf("%+v", got)
			}
		})
	}
}
func TestLanguageAndSettings(t *testing.T) {
	m := New(core.Defaults(), "zh-CN")
	tt := ui.NewTester(m.Render, 780, 980)
	if !tt.HasText("让一个窗口，一直看得见。") {
		t.Fatal(tt.Texts())
	}
	if err := tt.Click("设置"); err != nil {
		t.Fatal(err)
	}
	if !tt.HasText("偏好设置") {
		t.Fatal(tt.Texts())
	}
}
func TestNativeScreenshots(t *testing.T) {
	dir := os.Getenv("FUWA_SCREENSHOTS")
	if dir == "" {
		t.Skip("set FUWA_SCREENSHOTS to render fixture snapshots")
	}
	if err := os.MkdirAll(dir, 0755); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"pins-en", "pins-zh", "empty-en", "settings-en"} {
		m := fixture()
		height := 720
		if name == "pins-zh" {
			m.Settings.Language = "zh-Hans"
		}
		if name == "empty-en" {
			m.Pins = nil
		}
		if name == "settings-en" {
			m.Route = "settings"
			height = 1120
		}
		tt := ui.NewTester(m.Render, 780, height)
		f, err := os.Create(filepath.Join(dir, name+".png"))
		if err != nil {
			t.Fatal(err)
		}
		err = png.Encode(f, tt.Image())
		closeErr := f.Close()
		if err != nil {
			t.Fatal(err)
		}
		if closeErr != nil {
			t.Fatal(closeErr)
		}
	}
}
