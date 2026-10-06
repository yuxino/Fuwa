package view

import (
	"testing"

	"github.com/egoist/mygo/ui"
	"github.com/yuxino/Fuwa/internal/core"
)

func TestPickerSearchPinsTheVisibleMatch(t *testing.T) {
	m := New(core.Defaults(), "en")
	m.Route, m.Screen = "picker", true
	m.Choices = []core.Window{
		{ID: 1, PID: 20, App: "Safari", Title: "A tutorial"},
		{ID: 2, PID: 21, App: "Preview", Title: "Design reference.pdf"},
		{ID: 3, PID: 22, App: "Notes", Title: "Reading list"},
	}
	var got Action
	m.OnAction = func(a Action) { got = a }
	tt := ui.NewTester(m.Render, 780, 800)
	if err := tt.Click("Search windows"); err != nil {
		t.Fatal(err)
	}
	tt.Type("  REFERENCE  ")
	if !tt.HasText("Design reference.pdf") || tt.HasText("A tutorial") || tt.HasText("Reading list") {
		t.Fatal("window search did not filter by title", tt.Texts())
	}
	if err := tt.Click("Pin"); err != nil {
		t.Fatal(err)
	}
	if got.Name != "pin" || !got.Window.Same(m.Choices[1]) {
		t.Fatal("search pinned an earlier unfiltered row", got)
	}
}

func TestPickerSearchClearsWithoutRefreshingOrCapturing(t *testing.T) {
	m := New(core.Defaults(), "zh-CN")
	m.Route, m.Screen, m.Search = "picker", true, "missing"
	m.Choices = []core.Window{{ID: 1, PID: 2, App: "预览", Title: "设计参考"}}
	calls := 0
	m.OnAction = func(Action) { calls++ }
	tt := ui.NewTester(m.Render, 780, 800)
	if !tt.HasText("没有符合搜索条件的窗口。") {
		t.Fatal(tt.Texts())
	}
	if err := tt.Click("清除搜索"); err != nil {
		t.Fatal(err)
	}
	tt.Frame()
	if calls != 0 || m.Search != "" || !tt.HasText("设计参考") {
		t.Fatal("clearing search performed an unrelated action", calls, m.Search, tt.Texts())
	}
}

func TestPickerSearchMatchesApplicationAndRetainsOrder(t *testing.T) {
	m := New(core.Defaults(), "en")
	m.Choices = []core.Window{
		{ID: 1, App: "Preview", Title: "Second document"},
		{ID: 2, App: "Safari", Title: "Tutorial"},
		{ID: 3, App: "Preview", Title: "First document"},
	}
	m.Search = "pReViEw"
	got := m.filteredChoices()
	if len(got) != 2 || got[0].ID != 1 || got[1].ID != 3 {
		t.Fatal("application search changed WindowServer order", got)
	}
}

func TestPermissionRecoveryIsExplicitAndLocalized(t *testing.T) {
	for _, tc := range []struct{ locale, notice, label, action string }{
		{"en", "screen_permission", "Screen Recording settings", "screen-settings"},
		{"zh-CN", "screen_permission", "录屏权限设置", "screen-settings"},
		{"en", "accessibility_permission", "Accessibility settings", "ax-settings"},
		{"zh-CN", "accessibility_permission", "辅助功能设置", "ax-settings"},
	} {
		t.Run(tc.locale+tc.notice, func(t *testing.T) {
			m := New(core.Defaults(), tc.locale)
			m.Notice = tc.notice
			var actions []Action
			m.OnAction = func(a Action) { actions = append(actions, a) }
			tt := ui.NewTester(m.Render, 780, 800)
			if len(actions) != 0 {
				t.Fatal("render requested a permission")
			}
			if err := tt.Click(tc.label); err != nil {
				t.Fatal(err)
			}
			if len(actions) != 1 || actions[0].Name != tc.action {
				t.Fatal("permission recovery did not open the correct settings", actions)
			}
		})
	}
}

func TestFailedPinRetriesOnlyTheSameSession(t *testing.T) {
	m := fixture()
	m.Pins = m.Pins[:1]
	m.Pins[0].State, m.Pins[0].HasFrame = core.Failed, false
	var got Action
	m.OnAction = func(a Action) { got = a }
	tt := ui.NewTester(m.Render, 780, 800)
	if err := tt.Click("Retry capture"); err != nil {
		t.Fatal(err)
	}
	if got.Name != "retry" || got.Token != m.Pins[0].Token {
		t.Fatal("retry selected a new front window", got)
	}
	m.Pins[0].Closed = true
	got = Action{}
	tt.Frame()
	_ = tt.Click("Retry capture")
	if got.Name != "" {
		t.Fatal("closed source allowed retry", got)
	}
}

func TestStartingPinDoesNotOfferUnavailableActions(t *testing.T) {
	m := fixture()
	m.Pins = m.Pins[:1]
	m.Pins[0].State, m.Pins[0].HasFrame = core.Starting, false
	var got Action
	m.OnAction = func(a Action) { got = a }
	tt := ui.NewTester(m.Render, 780, 800)
	for _, label := range []string{"Freeze", "Go to original", "Controls"} {
		_ = tt.Click(label)
		if got.Name != "" {
			t.Fatal("starting capture allowed unavailable action", got)
		}
	}
	if err := tt.Click("Unpin"); err != nil {
		t.Fatal(err)
	}
	if got.Name != "unpin" || got.Token != 1 {
		t.Fatal("starting capture could not be cancelled", got)
	}
}

func TestFullPinListStillAllowsFrontWindowToggle(t *testing.T) {
	m := fixture()
	for len(m.Pins) < core.MaxPins {
		p := m.Pins[0]
		p.Token = uint64(len(m.Pins) + 1)
		m.Pins = append(m.Pins, p)
	}
	var got Action
	m.OnAction = func(a Action) { got = a }
	tt := ui.NewTester(m.Render, 780, 800)
	if err := tt.Click("Pin front window"); err != nil {
		t.Fatal(err)
	}
	if got.Name != "pin-front" {
		t.Fatal("full pin list disabled unpinning the current target", got)
	}
}

func TestControlsShowCaptureState(t *testing.T) {
	m := fixture()
	m.Pins[1].Error = "capture_interrupted"
	tt := ui.NewTester(m.Controls(2), 450, 130)
	if !tt.HasText("Capture interrupted · still kept") {
		t.Fatal("controls do not explain why a still stopped updating", tt.Texts())
	}
	if _, ok := tt.Find("Unpin"); !ok {
		t.Fatal("state displaced the unpin action")
	}
}
