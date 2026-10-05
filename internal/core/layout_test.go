package core

import (
	"math"
	"testing"
)

func contains(outer, inner Rect) bool {
	const epsilon = 0.000001
	return inner.X >= outer.X-epsilon && inner.Y >= outer.Y-epsilon && inner.X+inner.Width <= outer.X+outer.Width+epsilon && inner.Y+inner.Height <= outer.Y+outer.Height+epsilon
}

func TestFrozenDisplayRecovery(t *testing.T) {
	screen := Rect{X: 0, Y: 24, Width: 1512, Height: 869}
	for _, source := range []Rect{
		{X: -1700, Y: 200, Width: 800, Height: 600}, {X: 1800, Y: 200, Width: 800, Height: 600},
		{X: 100, Y: -1200, Width: 800, Height: 600}, {X: 100, Y: 1000, Width: 800, Height: 600},
		{X: 2000, Width: 3840, Height: 2160},
	} {
		got := RecoverFrozenBounds(source, []Rect{screen})
		if !contains(screen, got) || math.Abs(got.Width/got.Height-source.Width/source.Height) > 0.000001 {
			t.Fatalf("invalid recovery: %v -> %v", source, got)
		}
		if RecoverFrozenBounds(got, []Rect{screen}) != got {
			t.Fatal("repeated display notification moved a visible still")
		}
	}
	source := Rect{X: -100, Y: 200, Width: 800, Height: 600}
	if RecoverFrozenBounds(source, []Rect{screen}) != source || RecoverFrozenBounds(source, nil) != source {
		t.Fatal("partly visible still or empty display inventory changed position")
	}
	left := Rect{X: -1920, Width: 1920, Height: 1080}
	if got := RecoverFrozenBounds(Rect{X: -3000, Width: 800, Height: 600}, []Rect{screen, left}); !contains(left, got) {
		t.Fatal("did not recover onto nearest display", got)
	}
}

func TestControlsStayInWorkArea(t *testing.T) {
	for _, screen := range []Rect{{Y: 24, Width: 1512, Height: 900}, {X: -1920, Width: 1920, Height: 1080}, {Y: -1000, Width: 1440, Height: 900}, {Width: 320, Height: 100}} {
		for _, x := range []float64{screen.X - 200, screen.X, screen.X + screen.Width - 50, screen.X + screen.Width + 200} {
			for _, y := range []float64{screen.Y - 200, screen.Y, screen.Y + screen.Height - 50, screen.Y + screen.Height + 200} {
				if got := ControlsBounds(Rect{X: x, Y: y, Width: 800, Height: 600}, 450, 130, []Rect{screen}); !contains(screen, got) {
					t.Fatalf("controls outside %v: %v", screen, got)
				}
			}
		}
	}
	screen := Rect{Width: 1400, Height: 1000}
	if got := ControlsBounds(Rect{X: 100, Y: 300, Width: 800, Height: 600}, 450, 130, []Rect{screen}); got.Y != 170 {
		t.Fatal("controls should fit immediately above source", got)
	}
	if got := ControlsBounds(Rect{X: 100, Y: 30, Width: 800, Height: 600}, 450, 130, []Rect{screen}); got.Y != 630 {
		t.Fatal("controls should fit immediately below source", got)
	}
}
