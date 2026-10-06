package main

import (
	"math"
	"testing"

	"github.com/yuxino/Fuwa/internal/core"
	"github.com/yuxino/Fuwa/internal/native"
	"github.com/yuxino/Fuwa/internal/view"
)

func TestOffscreenSourceKeepsLiveSession(t *testing.T) {
	source := core.Window{ID: 42, PID: 7, Birth: 1, Onscreen: true, Bounds: core.Rect{Width: 800, Height: 600}}
	p := &pin{Session: core.NewSession(1, source), scale: 2}
	p.ReceiveFrame(1)
	p.Missing = 1
	a := &application{}
	for _, onscreen := range []bool{false, true, false} {
		current := source
		current.Onscreen = onscreen
		a.trackWindow(p, current, 2)
		if p.State != core.Live || !p.HasFrame || p.Generation != 1 || p.Closed || p.Missing != 0 || p.Source.Onscreen != onscreen {
			t.Fatal("visibility change interrupted the existing stream", p.Session)
		}
	}
}

func TestPreparedFrontNeverFallsBackAfterFailure(t *testing.T) {
	a := &application{model: view.New(core.Defaults(), "en")}
	a.prepared.Replace(core.Window{}, core.ErrNoWindow)
	for i := 0; i < 2; i++ {
		// This must return before touching WindowServer or asking permission.
		// A second click after a denied visual target cannot capture a window
		// behind the dialog now that Fuwa itself has become the front app.
		a.front(true)
		if a.model.Notice != "no_window" || len(a.pins) != 0 {
			t.Fatal("a consumed/failed intent fell through to a new selection")
		}
	}
}

func TestTrackingRejectsReusedIdentityAndInvalidGeometry(t *testing.T) {
	source := core.Window{ID: 42, PID: 7, Birth: 1, Title: "Original", Onscreen: true, Bounds: core.Rect{Width: 800, Height: 600}}
	p := &pin{Session: core.NewSession(1, source), scale: 2}
	p.ReceiveFrame(1)
	a := &application{}
	reused := source
	reused.Birth++
	reused.Bounds.Width += 100
	if a.trackWindow(p, reused, 2) || p.Source != source {
		t.Fatal("a reused WindowServer ID changed the original mirror")
	}
	invalid := source
	invalid.Bounds.Width = math.NaN()
	invalid.Title = "Renamed"
	if !a.trackWindow(p, invalid, math.NaN()) || p.Source.Bounds != source.Bounds || p.Source.Title != invalid.Title || p.scale != 2 || p.State != core.Live {
		t.Fatal("transient invalid geometry damaged a live source", p.Session)
	}
	invalid.Title = "Renamed again"
	if !a.trackWindow(p, invalid, 1) || p.Source.Bounds != source.Bounds || p.scale != 2 {
		t.Fatal("an invalid rectangle changed the capture scale to a fallback display")
	}
	// An existing source can shrink below the minimum size used for picking
	// a new window. It must still be tracked and capturable.
	if !captureBoundsValid(core.Rect{X: -600, Y: -80, Width: 40, Height: 30}) || captureBoundsValid(core.Rect{Width: math.Inf(1), Height: 600}) {
		t.Fatal("tracking confused eligibility limits with valid capture geometry")
	}
}

func TestNativeEventsCannotResurrectOldOrStoppedGeneration(t *testing.T) {
	source := core.Window{ID: 42, PID: 7, Birth: 1, Bounds: core.Rect{Width: 800, Height: 600}}
	p := &pin{Session: core.NewSession(1, source)}
	p.Generation = 4
	a := &application{pins: []*pin{p}}
	before := p.Session
	dirty, cleared := a.consumeEvents([]native.Event{
		{Token: 1, Generation: 3, Kind: "live"},
		{Token: 1, Generation: 3, Kind: "frozen", Message: "capture_interrupted"},
		{Token: 99, Generation: 4, Kind: "live"},
	})
	if dirty || cleared || p.Session != before {
		t.Fatal("a stale capture event modified the current generation", p.Session)
	}
	p.Stop()
	before = p.Session
	dirty, cleared = a.consumeEvents([]native.Event{{Token: 1, Generation: p.Generation, Kind: "frozen"}})
	if dirty || cleared || p.Session != before {
		t.Fatal("a stopped session acquired pixels from a late event", p.Session)
	}
}
