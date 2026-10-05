package main

import (
	"bytes"
	"fmt"
	"image/png"
	"os"
	"path/filepath"
	"time"

	"github.com/egoist/mygo"
)

// This optional CI mode renders only this app's own empty main view. It never
// pins another process, requests TCC approval, changes login items or checks
// updates. Ordinary launches do not register this listener or write screenshots.
func init() {
	if len(os.Args) != 2 || os.Args[1] != "--fuwa-smoke" {
		return
	}
	dir := os.Getenv("FUWA_SMOKE_OUTPUT")
	if dir == "" {
		fmt.Fprintln(os.Stderr, "--fuwa-smoke requires FUWA_SMOKE_OUTPUT")
		os.Exit(2)
	}
	mygo.App.OnReady(func() {
		go func() {
			time.Sleep(3 * time.Second)
			windows := mygo.Windows()
			if len(windows) != 1 || windows[0].NativeHandle() == 0 || windows[0].Page() != nil || !windows[0].IsVisible() {
				smokeFail("native main window was not ready")
				return
			}
			data, err := windows[0].CapturePage()
			if err != nil {
				smokeFail("native main view capture failed: " + err.Error())
				return
			}
			config, err := png.DecodeConfig(bytes.NewReader(data))
			if err != nil || config.Width < 600 || config.Height < 400 {
				smokeFail("invalid native main view image")
				return
			}
			if err := os.MkdirAll(dir, 0755); err != nil {
				smokeFail("cannot create smoke output directory")
				return
			}
			if err := os.WriteFile(filepath.Join(dir, "native-startup.png"), data, 0600); err != nil {
				smokeFail("cannot write own-window screenshot")
				return
			}
			fmt.Printf("PASS native startup: %dx%d; native UI, no web page; no pin requested\n", config.Width, config.Height)
			mygo.App.Quit()
		}()
	})
}

func smokeFail(message string) {
	fmt.Fprintln(os.Stderr, "FAIL "+message)
	mygo.App.Exit(1)
}
