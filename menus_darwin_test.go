package main

import (
	"testing"

	"github.com/egoist/mygo"
	"github.com/yuxino/Fuwa/internal/core"
	"github.com/yuxino/Fuwa/internal/view"
)

func TestMenuLanguageAndRoles(t *testing.T) {
	a := &application{model: view.New(core.Defaults(), "en")}
	for _, tc := range []struct{ language, edit, quit, pin string }{{"en", "Edit", "Quit Fuwa", "Pin front window"}, {"zh-Hans", "编辑", "退出 Fuwa", "置顶前方窗口"}, {"en", "Edit", "Quit Fuwa", "Pin front window"}} {
		a.model.Settings.Language = tc.language
		items := mygo.NewMenu(a.menuItems()).Items()
		if items[2].Label != tc.edit || items[1].Submenu[1].Label != tc.pin {
			t.Fatal("stale menu language", tc.language)
		}
		app := items[0].Submenu
		quit := app[len(app)-1]
		if quit.Label != tc.quit || quit.Role != mygo.RoleQuit || quit.Accelerator != "Cmd+Q" {
			t.Fatal("localized quit lost native action or shortcut", quit)
		}
	}
}
