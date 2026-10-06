package native

import "testing"

func TestUnavailableInventoryCannotLookLikeClosedSources(t *testing.T) {
	for _, data := range []string{"", "null", "{}", `{"self":42}`, `{"self":42,"windows":null,"displays":[]}`, `{"self":0,"windows":[],"displays":[]}`} {
		if _, err := decodeInventory([]byte(data)); err == nil {
			t.Errorf("unavailable inventory %q must fail instead of closing tracked sources", data)
		}
	}
	// A successful, empty enumeration is different: it can confirm source loss.
	if inventory, err := decodeInventory([]byte(`{"self":42,"front":0,"windows":[],"displays":[]}`)); err != nil || inventory.Self != 42 || len(inventory.Windows) != 0 {
		t.Fatalf("valid empty inventory: %+v, %v", inventory, err)
	}
}

func TestNativeEventEnvelopeRejectsUnavailableData(t *testing.T) {
	for _, data := range []string{"", "null", "{}", "["} {
		if _, err := decodeEvents([]byte(data)); err == nil {
			t.Errorf("invalid event envelope %q must be reported", data)
		}
	}
	events, err := decodeEvents([]byte(`[{"token":7,"generation":3,"kind":"live","message":""}]`))
	if err != nil || len(events) != 1 || events[0].Token != 7 || events[0].Generation != 3 || events[0].Kind != "live" {
		t.Fatalf("generation identity must survive the native event boundary: %+v, %v", events, err)
	}
	if events, err = decodeEvents([]byte("[]")); err != nil || len(events) != 0 {
		t.Fatalf("empty event queue is valid: %+v, %v", events, err)
	}
}
