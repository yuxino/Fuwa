package view

import (
	"testing"

	"github.com/egoist/mygo/ui"
	"github.com/yuxino/Fuwa/internal/core"
)

func TestClosedWithoutFrameDoesNotClaimAStill(t *testing.T) {
	m := New(core.Defaults(), "en")
	p := core.Session{Closed: true, State: core.Failed}
	if got := m.state(p); got != "Source closed" {
		t.Fatal(got)
	}
	p.HasFrame = true
	if got := m.state(p); got != "Source closed · still kept" {
		t.Fatal(got)
	}
}

func TestCancellingUpdateCannotStartAnother(t *testing.T) {
	m := New(core.Defaults(), "en")
	m.Route, m.UpdatePhase = "settings", "cancelling"
	calls := 0
	m.OnAction = func(Action) { calls++ }
	tt := ui.NewTester(m.Render, 780, 1120)
	_ = tt.Click("Check for updates")
	_ = tt.Click("Cancel update")
	if calls != 0 || !tt.HasText("Cancelling…") {
		t.Fatal("cancelling UI admitted another operation")
	}
}
