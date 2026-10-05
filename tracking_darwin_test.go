package main

import (
	"testing"

	"github.com/yuxino/Fuwa/internal/core"
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
