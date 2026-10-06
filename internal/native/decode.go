package native

import (
	"encoding/json"
	"errors"

	"github.com/yuxino/Fuwa/internal/core"
)

type Event struct {
	Token      uint64 `json:"token"`
	Generation uint64 `json:"generation"`
	Kind       string `json:"kind"`
	Message    string `json:"message"`
}

func decodeInventory(data []byte) (core.Inventory, error) {
	var inventory core.Inventory
	if err := json.Unmarshal(data, &inventory); err != nil {
		return inventory, err
	}
	// JSON null unmarshals successfully into a struct. An unavailable Quartz
	// inventory must not masquerade as every source having just disappeared.
	if inventory.Self <= 0 || inventory.Windows == nil || inventory.Displays == nil {
		return inventory, errors.New("capture_unavailable")
	}
	return inventory, nil
}

func decodeEvents(data []byte) ([]Event, error) {
	var events []Event
	if err := json.Unmarshal(data, &events); err != nil {
		return nil, err
	}
	if events == nil {
		return nil, errors.New("capture_unavailable")
	}
	return events, nil
}
