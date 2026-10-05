package main

import (
	"context"
	"errors"
	"math"
	"strings"
	"time"

	"github.com/egoist/mygo"
)

func (a *application) checkUpdate() {
	if a.updateCancel != nil {
		return
	}
	if !mygo.Updater.Enabled() {
		a.model.Notice = "preview_updates"
		return
	}
	a.updateSerial++
	serial := a.updateSerial
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	a.updateCancel = cancel
	a.model.UpdatePhase = "checking"
	a.model.Notice = ""
	a.updater = nil
	go func() {
		defer cancel()
		up, err := mygo.Updater.Check(ctx)
		mygo.RunOnMain(func() {
			if serial != a.updateSerial || a.quitting {
				return
			}
			a.updateCancel = nil
			switch {
			case errors.Is(err, context.Canceled):
				a.model.UpdatePhase = "cancelled"
			case err != nil && strings.Contains(err.Error(), "no release is published"):
				a.model.UpdatePhase = "unpublished"
			case err != nil:
				a.model.UpdatePhase = "idle"
				a.model.Notice = "update_failed"
			case up == nil:
				a.model.UpdatePhase = "current"
			default:
				a.updater = up
				a.model.UpdatePhase = "available"
				a.model.UpdateVersion = up.Version
			}
			a.publish()
		})
	}()
}
func (a *application) installUpdate() {
	if a.updateCancel != nil || a.updater == nil || a.model.UpdatePhase != "available" {
		return
	}
	up := a.updater
	a.updateSerial++
	serial := a.updateSerial
	ctx, cancel := context.WithCancel(context.Background())
	a.updateCancel = cancel
	a.model.UpdatePhase = "installing"
	a.model.Progress = 0
	go func() {
		defer cancel()
		err := up.Install(ctx, func(n, total int64) {
			mygo.RunOnMain(func() {
				if serial == a.updateSerial && total > 0 && !a.quitting && a.model.UpdatePhase == "installing" {
					a.model.Progress = math.Min(1, float64(n)/float64(total))
					a.main.Invalidate()
				}
			})
		})
		mygo.RunOnMain(func() {
			if serial != a.updateSerial || a.quitting {
				return
			}
			a.updateCancel = nil
			if errors.Is(err, context.Canceled) {
				a.model.UpdatePhase = "cancelled"
			} else if err != nil {
				a.model.UpdatePhase = "available"
				a.model.Notice = "update_failed"
			} else {
				a.clear()
				mygo.App.Relaunch()
			}
			a.publish()
		})
	}()
}

// Keep the operation busy until its worker acknowledges cancellation. Starting
// another update while an installation is winding down could race replacement.
func (a *application) cancelUpdate() {
	if a.updateCancel == nil || a.model.UpdatePhase == "cancelling" {
		return
	}
	a.model.UpdatePhase = "cancelling"
	a.updateCancel()
}
