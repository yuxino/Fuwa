package core

import "strings"

// ShortcutBinding keeps OS registration separate from the saved preference:
// an unavailable saved shortcut must still be retryable without changing it.
type ShortcutBinding struct {
	Active     string
	Register   func(string) error
	Unregister func(string)
}

func (b *ShortcutBinding) Start(preferred string) error {
	err := b.Register(preferred)
	if err == nil {
		b.Active = preferred
		return nil
	}
	if !sameShortcut(preferred, DefaultShortcut) {
		if fallbackErr := b.Register(DefaultShortcut); fallbackErr == nil {
			b.Active = DefaultShortcut
		}
	}
	return err
}

// Replace preserves the working binding until registration and persistence
// both succeed. A failed save removes only the newly acquired binding.
func (b *ShortcutBinding) Replace(value string, save func() bool) bool {
	if sameShortcut(value, b.Active) {
		if !save() {
			return false
		}
		b.Active = value
		return true
	}
	if err := b.Register(value); err != nil {
		return false
	}
	if !save() {
		b.Unregister(value)
		return false
	}
	previous := b.Active
	b.Active = value
	if previous != "" {
		b.Unregister(previous)
	}
	return true
}

// MyGo registers accelerators by physical modifier/key combination. Alternate
// spelling or modifier order must not try to register the already active key
// again, or a harmless edit is incorrectly reported as a system-wide conflict.
func sameShortcut(a, b string) bool {
	key := func(value string) string {
		if ValidateShortcut(value) != nil {
			return ""
		}
		parts := strings.Split(value, "+")
		mods := map[string]bool{}
		for _, part := range parts[:len(parts)-1] {
			switch strings.ToLower(strings.TrimSpace(part)) {
			case "cmd", "command", "meta", "super":
				mods["cmd"] = true
			case "ctrl", "control":
				mods["ctrl"] = true
			case "alt", "option":
				mods["alt"] = true
			case "shift":
				mods["shift"] = true
			}
		}
		var normalized []string
		for _, mod := range []string{"cmd", "ctrl", "alt", "shift"} {
			if mods[mod] {
				normalized = append(normalized, mod)
			}
		}
		return strings.Join(append(normalized, strings.ToLower(strings.TrimSpace(parts[len(parts)-1]))), "+")
	}
	first := key(a)
	return first != "" && first == key(b)
}
