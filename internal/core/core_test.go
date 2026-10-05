package core

import (
	"errors"
	"math"
	"os"
	"path/filepath"
	"testing"
)

func sample(id uint32, pid int32) Window {
	return Window{ID: id, PID: pid, Birth: 1, App: "Editor", Bundle: "test.editor", Bounds: Rect{X: 20, Y: 20, Width: 800, Height: 600}, Onscreen: true, Alpha: 1}
}
func TestIntent(t *testing.T) {
	target := sample(10, 20)
	overlay := sample(11, 21)
	cases := []struct {
		name string
		inv  Inventory
		want uint32
	}{
		{"foreground wins over floating overlay", Inventory{Self: 1, Front: 20, Windows: []Window{overlay, target}}, 10},
		{"self menu targets underneath", Inventory{Self: 1, Front: 1, Windows: []Window{sample(12, 1), target}}, 10},
		{"no fallback to another app", Inventory{Self: 1, Front: 22, Windows: []Window{target}}, 0},
		{"preserve frontmost within application", Inventory{Self: 1, Front: 20, Windows: []Window{sample(13, 20), target}}, 13},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, err := Intent(c.inv)
			if got.ID != c.want || (c.want == 0 && !errors.Is(err, ErrNoWindow)) {
				t.Fatalf("got %v %v", got, err)
			}
		})
	}
}
func TestPrivacyFilters(t *testing.T) {
	for _, b := range []string{"com.apple.securityagent", "com.apple.controlcenter", "com.apple.dock", "com.apple.loginwindow", "app.yuxino.fuwa", "app.yuxino.fuwa.mygo"} {
		t.Run(b, func(t *testing.T) {
			w := sample(1, 2)
			w.Bundle = b
			if Eligible(w, Inventory{Self: 9}) {
				t.Fatal("private/system surface eligible")
			}
		})
	}
	w := sample(1, 2)
	w.Bundle = "com.apple.controlcenter"
	_, err := Intent(Inventory{Self: 9, Front: 2, Windows: []Window{w, sample(2, 3)}})
	if err == nil {
		t.Fatal("fell through system foreground")
	}
}
func TestQuickLook(t *testing.T) {
	w := sample(1, 2)
	w.Bundle = "com.apple.quicklook.QuickLookUIService"
	w.App = "QuickLookUIService"
	got, e := Intent(Inventory{Self: 9, Front: 3, Windows: []Window{w, sample(2, 3)}})
	if e != nil || got.ID != 1 {
		t.Fatal(got, e)
	}
}
func TestGeometry(t *testing.T) {
	for _, n := range []float64{math.NaN(), math.Inf(1), math.Inf(-1)} {
		w := sample(1, 2)
		w.Bounds.X = n
		if Eligible(w, Inventory{Self: 9}) {
			t.Fatal("nonfinite geometry")
		}
	}
	w := sample(1, 2)
	w.Bounds.X = 2000
	if Eligible(w, Inventory{Self: 9, Displays: []Rect{{Width: 1000, Height: 1000}}}) {
		t.Fatal("offscreen")
	}
	w.Bounds.X = -500
	if !Eligible(w, Inventory{Self: 9, Displays: []Rect{{X: -1000, Width: 1000, Height: 1000}}}) {
		t.Fatal("left display")
	}
}
func TestExactIdentity(t *testing.T) {
	w := sample(1, 2)
	other := w
	other.Birth++
	if _, ok := Exact(Inventory{Windows: []Window{other}}, w); ok {
		t.Fatal("reused process identity accepted")
	}
	other = w
	other.PID++
	if _, ok := Exact(Inventory{Windows: []Window{other}}, w); ok {
		t.Fatal("wrong pid accepted")
	}
}
func TestSessionLifecycle(t *testing.T) {
	w := sample(1, 2)
	s := NewSession(1, w)
	if s.ReceiveFrame(0) {
		t.Fatal("stale frame")
	}
	if !s.ReceiveFrame(1) || s.State != Live {
		t.Fatal(s)
	}
	if e := s.Freeze(""); e != nil {
		t.Fatal(e)
	}
	if e := s.Resume(w); e != nil {
		t.Fatal(e)
	}
	if s.ReceiveFrame(1) {
		t.Fatal("previous cycle accepted")
	}
	if !s.Fail(2, "timeout") || s.State != Frozen || !s.HasFrame {
		t.Fatal("failed resume lost snapshot", s)
	}
	s.Stop()
	if s.ReceiveFrame(3) || s.Fail(2, "late") {
		t.Fatal("resurrected stopped session")
	}
}
func TestClosedSource(t *testing.T) {
	w := sample(1, 2)
	s := NewSession(1, w)
	s.ReceiveFrame(1)
	s.Freeze("")
	s.Closed = true
	if !errors.Is(s.Resume(w), ErrClosed) {
		t.Fatal("closed resumed")
	}
}
func TestSettings(t *testing.T) {
	p := filepath.Join(t.TempDir(), "settings.json")
	s, e := LoadSettings(p)
	if e != nil || s != Defaults() {
		t.Fatal(s, e)
	}
	s.KeepDock = false
	s.Language = "zh-Hans"
	if e = SaveSettings(p, s); e != nil {
		t.Fatal(e)
	}
	got, e := LoadSettings(p)
	if e != nil || got != s {
		t.Fatal(got, e)
	}
	info, _ := os.Stat(p)
	if info.Mode().Perm() != 0600 {
		t.Fatal("settings not private")
	}
	os.WriteFile(p, []byte("{"), 0600)
	got, e = LoadSettings(p)
	if e == nil || got != Defaults() {
		t.Fatal("corruption not reported")
	}
}
func TestShortcuts(t *testing.T) {
	for _, s := range []string{"Cmd+Alt+P", "Control+Shift+Space", "Alt+F12", "Cmd+Plus"} {
		if e := ValidateShortcut(s); e != nil {
			t.Fatal(s, e)
		}
	}
	for _, s := range []string{"P", "Shift+P", "Cmd+Cmd+P", "Cmd+", "Fn+P", "Cmd+banana", "Cmd+Alt+P+Q"} {
		if ValidateShortcut(s) == nil {
			t.Fatal("accepted", s)
		}
	}
}
