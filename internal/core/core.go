// Package core is the platform-independent policy of Fuwa. It never captures
// pixels, invokes macOS, or chooses a substitute when an intended window fails.
package core

import (
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"strings"
)

const Version = "1.1.0-mygo.2"
const MaxPins = 8
const DefaultShortcut = "Cmd+Alt+P"

var ErrNoWindow = errors.New("no_window")
var ErrClosed = errors.New("source_closed")
var ErrTransition = errors.New("invalid_transition")

type Rect struct{ X, Y, Width, Height float64 }

func (r Rect) Valid() bool {
	for _, n := range []float64{r.X, r.Y, r.Width, r.Height} {
		if math.IsNaN(n) || math.IsInf(n, 0) {
			return false
		}
	}
	return r.Width >= 80 && r.Height >= 50
}
func (r Rect) Intersects(b Rect) bool {
	return r.X < b.X+b.Width && b.X < r.X+r.Width && r.Y < b.Y+b.Height && b.Y < r.Y+r.Height
}

type Window struct {
	ID       uint32  `json:"id"`
	PID      int32   `json:"pid"`
	Birth    float64 `json:"birth"`
	App      string  `json:"app"`
	Bundle   string  `json:"bundle"`
	Title    string  `json:"title"`
	Bounds   Rect    `json:"bounds"`
	Alpha    float64 `json:"alpha"`
	Onscreen bool    `json:"onscreen"`
}

func (w Window) Same(other Window) bool {
	return w.ID == other.ID && w.PID == other.PID && w.Birth == other.Birth
}
func (w Window) Name() string {
	if strings.TrimSpace(w.Title) != "" {
		return w.Title
	}
	return w.App
}

type Inventory struct {
	Self     int32    `json:"self"`
	Front    int32    `json:"front"`
	Windows  []Window `json:"windows"`
	Displays []Rect   `json:"displays"`
}

var systemBundles = []string{
	"com.apple.accessibilityuiserver", "com.apple.characterpaletteim", "com.apple.controlcenter", "com.apple.dock",
	"com.apple.loginwindow", "com.apple.localauthentication", "com.apple.localauthenticationremoteservice",
	"com.apple.notificationcenterui", "com.apple.screencaptureui", "com.apple.securityagent", "com.apple.siri",
	"com.apple.spotlight", "com.apple.systemuiserver", "com.apple.textinputmenuagent", "com.apple.wallpaper",
	"com.apple.windowmanager", "com.openai.sky.cuaservice",
}

func system(bundle string) bool {
	b := strings.ToLower(bundle)
	for _, s := range systemBundles {
		if b == s || strings.HasPrefix(b, s+".") {
			return true
		}
	}
	return false
}
func quickLook(w Window) bool {
	b := strings.ToLower(w.Bundle)
	n := strings.ToLower(w.App)
	return strings.HasPrefix(b, "com.apple.quicklook") || strings.Contains(b, ".quicklook.") || strings.HasPrefix(n, "quicklook") || n == "qlmanage"
}
func Eligible(w Window, inv Inventory) bool {
	b := strings.ToLower(w.Bundle)
	if !w.Onscreen || w.PID == inv.Self || b == "app.yuxino.fuwa" || strings.HasPrefix(b, "app.yuxino.fuwa.") || system(b) || !w.Bounds.Valid() || math.IsNaN(w.Alpha) || math.IsInf(w.Alpha, 0) || w.Alpha <= 0.01 {
		return false
	}
	if len(inv.Displays) == 0 {
		return true
	}
	for _, d := range inv.Displays {
		if w.Bounds.Intersects(d) {
			return true
		}
	}
	return false
}

// Intent runs before permission requests and asynchronous ScreenCaptureKit work.
func Intent(inv Inventory) (Window, error) {
	if inv.Front != inv.Self {
		for _, w := range inv.Windows {
			if w.PID == inv.Front && system(w.Bundle) {
				return Window{}, ErrNoWindow
			}
		}
	}
	for _, w := range inv.Windows {
		if Eligible(w, inv) && (inv.Front == 0 || inv.Front == inv.Self || w.PID == inv.Front || quickLook(w)) {
			return w, nil
		}
	}
	return Window{}, ErrNoWindow
}
func Exact(inv Inventory, source Window) (Window, bool) {
	for _, w := range inv.Windows {
		if w.Same(source) {
			return w, true
		}
	}
	return Window{}, false
}

type State string

const (
	Starting State = "starting"
	Live     State = "live"
	Frozen   State = "frozen"
	Failed   State = "failed"
	Stopped  State = "stopped"
)

type Session struct {
	Token      uint64
	Generation uint64
	Source     Window
	State      State
	HasFrame   bool
	Closed     bool
	Error      string
	Missing    int
}

func NewSession(token uint64, w Window) Session {
	return Session{Token: token, Generation: 1, Source: w, State: Starting}
}

// Action availability is shared by management, the menu bar, and controls.
// Starting captures remain cancellable, but cannot be frozen or manipulated
// as if their first frame had already arrived.
func (s Session) CanFreeze() bool       { return s.State == Live && s.HasFrame && !s.Closed }
func (s Session) CanResume() bool       { return s.State == Frozen && s.HasFrame && !s.Closed }
func (s Session) CanRetry() bool        { return s.State == Failed && !s.Closed }
func (s Session) CanReveal() bool       { return !s.Closed && (s.State == Live || s.State == Frozen) }
func (s Session) CanShowControls() bool { return s.HasFrame && (s.State == Live || s.State == Frozen) }

func (s *Session) ReceiveFrame(g uint64) bool {
	if s.State != Starting || g != s.Generation {
		return false
	}
	s.HasFrame = true
	s.State = Live
	s.Error = ""
	return true
}
func (s *Session) Freeze(message string) error {
	if !s.HasFrame || (s.State != Live && s.State != Starting) {
		return ErrTransition
	}
	s.State = Frozen
	s.Error = message
	return nil
}
func (s *Session) Resume(w Window) error {
	if s.State != Frozen {
		return ErrTransition
	}
	return s.restart(w)
}

// Retry reconnects a failed initial capture to the exact same source. Failed
// attempts keep their token, so retrying neither consumes another pin slot nor
// lets a stale completion from the previous attempt revive the wrong stream.
func (s *Session) Retry(w Window) error {
	if s.State != Failed {
		return ErrTransition
	}
	return s.restart(w)
}

func (s *Session) restart(w Window) error {
	if s.Closed || !s.Source.Same(w) {
		return ErrClosed
	}
	s.Source = w
	s.Generation++
	s.State = Starting
	s.Error = ""
	s.Missing = 0
	return nil
}
func (s *Session) Fail(g uint64, message string) bool {
	if s.Generation != g || s.State == Stopped {
		return false
	}
	s.Error = message
	if s.HasFrame {
		s.State = Frozen
	} else {
		s.State = Failed
	}
	return true
}
func (s *Session) Stop() { s.Generation++; s.State = Stopped; s.HasFrame = false; s.Error = "" }

// Shortcut validation is deliberately stricter than a general accelerator:
// global pin shortcuts must contain a command/control/option modifier.
func ValidateShortcut(value string) error {
	parts := strings.Split(value, "+")
	if len(parts) < 2 {
		return errors.New("invalid_shortcut")
	}
	seen := map[string]bool{}
	strong := false
	for _, p := range parts[:len(parts)-1] {
		p = strings.ToLower(strings.TrimSpace(p))
		switch p {
		case "cmd", "command", "meta", "super":
			p = "cmd"
		case "ctrl", "control":
			p = "ctrl"
		case "alt", "option":
			p = "alt"
		case "shift":
		default:
			return errors.New("invalid_shortcut")
		}
		if seen[p] {
			return errors.New("invalid_shortcut")
		}
		seen[p] = true
		strong = strong || p != "shift"
	}
	k := strings.TrimSpace(parts[len(parts)-1])
	if !strong || k == "" {
		return errors.New("invalid_shortcut")
	}
	if len(k) == 1 && k[0] >= 33 && k[0] <= 126 {
		return nil
	}
	switch strings.ToLower(k) {
	case "space", "enter", "tab", "escape", "backspace", "delete", "up", "down", "left", "right", "home", "end", "pageup", "pagedown", "plus":
		return nil
	}
	for i := 1; i <= 20; i++ {
		if strings.EqualFold(k, fmt.Sprintf("F%d", i)) {
			return nil
		}
	}
	return errors.New("invalid_shortcut")
}

type Settings struct {
	AskedScreen bool   `json:"askedScreen"`
	Language    string `json:"language"`
	KeepDock    bool   `json:"keepDock"`
	Shortcut    string `json:"shortcut"`
}

func Defaults() Settings {
	return Settings{Language: "system", KeepDock: true, Shortcut: DefaultShortcut}
}
func (s Settings) Validate() error {
	if s.Language != "system" && s.Language != "en" && s.Language != "zh-Hans" {
		return errors.New("invalid_language")
	}
	return ValidateShortcut(s.Shortcut)
}
func LoadSettings(path string) (Settings, error) {
	s := Defaults()
	b, e := os.ReadFile(path)
	if os.IsNotExist(e) {
		return s, nil
	}
	if e != nil {
		return s, e
	}
	if len(b) > 65536 {
		return Defaults(), errors.New("settings_too_large")
	}
	if e = json.Unmarshal(b, &s); e != nil {
		return Defaults(), e
	}
	if e = s.Validate(); e != nil {
		return Defaults(), e
	}
	return s, nil
}
func SaveSettings(path string, s Settings) error {
	if err := s.Validate(); err != nil {
		return err
	}
	b, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	if err = os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".settings-*")
	if err != nil {
		return err
	}
	name := f.Name()
	defer os.Remove(name)
	if _, err = f.Write(b); err != nil {
		f.Close()
		return err
	}
	if err = f.Sync(); err != nil {
		f.Close()
		return err
	}
	if err = f.Close(); err != nil {
		return err
	}
	return os.Rename(name, path)
}
