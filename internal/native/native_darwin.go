// Package native contains only the macOS capabilities MyGo does not expose.
// The app, UI, state machine, menus, shortcuts, and windows are owned by Go.
package native

/*
#cgo CFLAGS: -x objective-c -fobjc-arc -fblocks -mmacosx-version-min=14.0
#cgo LDFLAGS: -lobjc
#cgo LDFLAGS: -framework Cocoa -framework ScreenCaptureKit -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework CoreGraphics -framework ApplicationServices -framework QuartzCore -framework ServiceManagement
#include "bridge_darwin.h"
#include <stdlib.h>
*/
import "C"
import (
	"encoding/json"
	"errors"
	"github.com/yuxino/Fuwa/internal/core"
	"unsafe"
)

type Event struct {
	Token      uint64 `json:"token"`
	Generation uint64 `json:"generation"`
	Kind       string `json:"kind"`
	Message    string `json:"message"`
}

func take(p *C.char) string {
	if p == nil {
		return ""
	}
	defer C.free(unsafe.Pointer(p))
	return C.GoString(p)
}
func Initialize() { C.fw_initialize() }
func Inventory() (core.Inventory, error) {
	var v core.Inventory
	err := json.Unmarshal([]byte(take(C.fw_inventory())), &v)
	return v, err
}
func Events() ([]Event, error) {
	var v []Event
	err := json.Unmarshal([]byte(take(C.fw_events())), &v)
	return v, err
}
func ScreenAllowed() bool        { return C.fw_screen_allowed() != 0 }
func RequestScreen() bool        { return C.fw_request_screen() != 0 }
func AccessibilityAllowed() bool { return C.fw_ax_allowed() != 0 }
func ManagementActive(host uintptr, active bool) {
	v := 0
	if active {
		v = 1
	}
	C.fw_management_active(C.uintptr_t(host), C.int(v))
}
func Start(token, generation uint64, w core.Window, host uintptr) {
	C.fw_start(C.uint64_t(token), C.uint64_t(generation), C.uint32_t(w.ID), C.int32_t(w.PID), C.double(w.Birth), C.uintptr_t(host))
}
func Freeze(token uint64) error {
	if s := take(C.fw_freeze(C.uint64_t(token))); s != "" {
		return errors.New(s)
	}
	return nil
}
func Stop(token uint64) { C.fw_stop(C.uint64_t(token)) }
func Resize(token uint64, r core.Rect, scale float64) {
	C.fw_resize(C.uint64_t(token), C.double(r.Width), C.double(r.Height), C.double(scale))
}
func Reveal(w core.Window) error {
	if s := take(C.fw_reveal(C.uint32_t(w.ID), C.int32_t(w.PID), C.double(w.Birth))); s != "" {
		return errors.New(s)
	}
	return nil
}

// 0 disabled, 1 enabled, 2 requires approval, 3 unavailable.
func LoginState() int { return int(C.fw_login_state()) }
func SetLogin(enabled bool) error {
	v := 0
	if enabled {
		v = 1
	}
	if s := take(C.fw_set_login(C.int(v))); s != "" {
		return errors.New(s)
	}
	return nil
}
