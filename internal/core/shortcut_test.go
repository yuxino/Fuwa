package core

import (
	"errors"
	"reflect"
	"testing"
)

func TestShortcutStartupFallbackAndRetry(t *testing.T) {
	const preferred = "Cmd+Alt+K"
	blocked := map[string]bool{preferred: true}
	var calls []string
	b := ShortcutBinding{Register: func(value string) error {
		calls = append(calls, value)
		if blocked[value] {
			return errors.New("conflict")
		}
		return nil
	}, Unregister: func(string) {}}
	if b.Start(preferred) == nil || b.Active != DefaultShortcut || !reflect.DeepEqual(calls, []string{preferred, DefaultShortcut}) {
		t.Fatal("failed to recover default shortcut", b.Active, calls)
	}
	blocked[DefaultShortcut] = true
	b.Active = ""
	if b.Start(preferred) == nil || b.Active != "" {
		t.Fatal("claimed unavailable shortcut was active")
	}
	delete(blocked, preferred)
	if !b.Replace(preferred, func() bool { return true }) || b.Active != preferred {
		t.Fatal("could not retry unchanged preference after conflict ended")
	}
}

func TestShortcutReplacementRollback(t *testing.T) {
	old, next := DefaultShortcut, "Cmd+Alt+K"
	registered := map[string]bool{old: true}
	b := ShortcutBinding{Active: old, Register: func(value string) error {
		if registered[value] {
			return errors.New("conflict")
		}
		registered[value] = true
		return nil
	}, Unregister: func(value string) { delete(registered, value) }}
	if b.Replace(next, func() bool { return false }) || !registered[old] || registered[next] || b.Active != old {
		t.Fatal("failed save lost original binding")
	}
	if !b.Replace(next, func() bool {
		if !registered[old] || !registered[next] {
			t.Fatal("old shortcut removed before saving")
		}
		return true
	}) || registered[old] || !registered[next] || b.Active != next {
		t.Fatal("replacement not committed")
	}
	if !b.Replace(next, func() bool { return true }) || !registered[next] {
		t.Fatal("reapplying an active shortcut removed it")
	}
}
