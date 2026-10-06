//go:build fuwa_parity_qa

package native

/*
#cgo CFLAGS: -DFUWA_PARITY_QA=1
#include "bridge_darwin.h"
*/
import "C"

import "encoding/json"

type CaptureQAResult struct {
	Name string `json:"name"`
	OK   bool   `json:"ok"`
}

// QACaptureLifecycle exercises the real native capture/surface lifecycle using
// pixels allocated by this process and deferred mock stream completions. Call
// on MyGo's main thread while there are no real native captures.
func QACaptureLifecycle() []CaptureQAResult {
	var results []CaptureQAResult
	if err := json.Unmarshal([]byte(take(C.fw_qa_capture_lifecycle())), &results); err != nil {
		panic(err)
	}
	return results
}
