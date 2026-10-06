package core

import (
	"errors"
	"testing"
)

func TestPreparedIntentIsConsumedOnce(t *testing.T) {
	var slot PreparedIntentSlot
	if _, _, prepared := slot.Consume(); prepared {
		t.Fatal("empty slot reported a selection")
	}
	w := sample(7, 23)
	slot.Replace(w, nil)
	got, err, prepared := slot.Consume()
	if !prepared || err != nil || got != w {
		t.Fatal("prepared target was not retained", got, err, prepared)
	}
	if _, _, prepared := slot.Consume(); prepared {
		t.Fatal("a second click could reuse a consumed target")
	}
}

func TestPreparedFailureDoesNotBecomeAnEmptySlot(t *testing.T) {
	var slot PreparedIntentSlot
	slot.Replace(Window{}, ErrNoWindow)
	w, err, prepared := slot.Consume()
	if !prepared || !errors.Is(err, ErrNoWindow) || w != (Window{}) {
		t.Fatal("failed selection could fall through to a background window", w, err, prepared)
	}
	if _, _, prepared := slot.Consume(); prepared {
		t.Fatal("prepared failure was not consumed")
	}
}

func TestPreparedIntentReplacedAndClearedWithLifecycle(t *testing.T) {
	var slot PreparedIntentSlot
	slot.Replace(sample(1, 20), nil)
	slot.Replace(sample(2, 21), nil)
	if got, _, ok := slot.Consume(); !ok || got.ID != 2 {
		t.Fatal("reopening management retained the earlier target", got, ok)
	}
	slot.Replace(sample(1, 20), nil)
	slot.Clear()
	if got, err, ok := slot.Consume(); ok || err != nil || got != (Window{}) {
		t.Fatal("hidden management retained its target", got, err, ok)
	}
}
