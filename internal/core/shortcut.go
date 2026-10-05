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
	if !strings.EqualFold(preferred, DefaultShortcut) {
		if fallbackErr := b.Register(DefaultShortcut); fallbackErr == nil {
			b.Active = DefaultShortcut
		}
	}
	return err
}

// Replace preserves the working binding until registration and persistence
// both succeed. A failed save removes only the newly acquired binding.
func (b *ShortcutBinding) Replace(value string, save func() bool) bool {
	if strings.EqualFold(value, b.Active) {
		return save()
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
