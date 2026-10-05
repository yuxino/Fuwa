package main

import (
	"context"
	"testing"

	"github.com/yuxino/Fuwa/internal/core"
	"github.com/yuxino/Fuwa/internal/view"
)

func TestUpdateCancellationRemainsBusy(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	m := view.New(core.Defaults(), "en")
	m.UpdatePhase = "installing"
	a := &application{model: m, updateCancel: cancel, updateSerial: 3}
	a.cancelUpdate()
	if ctx.Err() != context.Canceled || m.UpdatePhase != "cancelling" || a.updateCancel == nil {
		t.Fatal("cancellation was advertised as complete before worker acknowledgement")
	}
	// Neither entry point may contact the updater or replace its operation.
	a.checkUpdate()
	a.installUpdate()
	a.cancelUpdate()
	if a.updateSerial != 3 || m.UpdatePhase != "cancelling" {
		t.Fatal("an overlapping operation was admitted")
	}
}
