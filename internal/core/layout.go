package core

import "math"

// Presentation geometry uses the top-left screen coordinates used by MyGo and
// Quartz. Work areas exclude the Dock and menu bar, including on secondary screens.
func presentationDisplay(source Rect, visible []Rect) (Rect, bool) {
	best, area, distance := Rect{}, -1.0, math.Inf(1)
	for _, screen := range visible {
		if screen.Width <= 0 || screen.Height <= 0 {
			continue
		}
		width := math.Max(0, math.Min(source.X+source.Width, screen.X+screen.Width)-math.Max(source.X, screen.X))
		height := math.Max(0, math.Min(source.Y+source.Height, screen.Y+screen.Height)-math.Max(source.Y, screen.Y))
		dx := source.X + source.Width/2 - screen.X - screen.Width/2
		dy := source.Y + source.Height/2 - screen.Y - screen.Height/2
		d := dx*dx + dy*dy
		if width*height > area || (width*height == area && d < distance) {
			best, area, distance = screen, width*height, d
		}
	}
	return best, area >= 0
}

// RecoverFrozenBounds moves only wholly invisible stills, preserving their
// aspect ratio when the remaining screen is smaller. It never moves the source.
func RecoverFrozenBounds(source Rect, visible []Rect) Rect {
	if source.Width <= 0 || source.Height <= 0 {
		return source
	}
	for _, screen := range visible {
		if source.Intersects(screen) {
			return source
		}
	}
	screen, ok := presentationDisplay(source, visible)
	if !ok {
		return source
	}
	scale := math.Min(1, math.Min(screen.Width/source.Width, screen.Height/source.Height))
	source.Width *= scale
	source.Height *= scale
	source.X = math.Max(screen.X, math.Min(source.X, screen.X+screen.Width-source.Width))
	source.Y = math.Max(screen.Y, math.Min(source.Y, screen.Y+screen.Height-source.Height))
	return source
}

// ControlsBounds places controls above the mirror when there is room, below
// otherwise, and clamps them to the most relevant display's usable area.
func ControlsBounds(source Rect, width, height float64, visible []Rect) Rect {
	screen, ok := presentationDisplay(source, visible)
	if !ok {
		return Rect{X: source.X, Y: source.Y, Width: width, Height: height}
	}
	width, height = math.Min(width, screen.Width), math.Min(height, screen.Height)
	y := source.Y - height
	if y < screen.Y {
		y = source.Y + source.Height
	}
	return Rect{
		X: math.Max(screen.X, math.Min(source.X+source.Width-width, screen.X+screen.Width-width)),
		Y: math.Max(screen.Y, math.Min(y, screen.Y+screen.Height-height)), Width: width, Height: height,
	}
}
