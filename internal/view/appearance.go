package view

import "github.com/egoist/mygo/ui"

// The Swift app keeps an opaque white surface and an ink-colored tint even in
// Dark Mode. Keep that appearance while retaining the desktop's text sizing and
// increased-contrast preference.
func applyAppearance(c *ui.Context) {
	theme := ui.LightTheme()
	theme.Font, theme.FontSize = c.Theme().Font, c.Theme().FontSize
	theme.Text = ui.Hex("#1f1f1f")
	theme.TextMuted = ui.Hex("#666666")
	theme.Accent = theme.Text
	theme.AccentHover = ui.Hex("#363636")
	theme.AccentPressed = ui.Hex("#111111")
	theme.Selection = ui.RGBA(31, 31, 31, 0.18)
	theme.Focus = ui.RGBA(31, 31, 31, 0.6)
	if c.Preferences().HighContrast {
		theme.Border = ui.Hex("#777777")
		theme.TextMuted = ui.Hex("#333333")
		theme.Focus = theme.Text
		theme.Scrollbar = ui.Hex("#666666")
	}
	c.SetTheme(theme)
}
