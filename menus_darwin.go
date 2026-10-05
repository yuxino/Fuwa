package main

import "github.com/egoist/mygo"

func (a *application) updateMenus() { mygo.App.SetMenu(mygo.NewMenu(a.menuItems())) }

// Explicit labels let Fuwa's language preference control its menus, while
// native roles retain their standard actions and keyboard accelerators.
func (a *application) menuItems() []*mygo.MenuItem {
	m := a.model
	role := func(r mygo.MenuRole, en, zh string) *mygo.MenuItem {
		return &mygo.MenuItem{Role: r, Label: m.T(en, zh)}
	}
	return []*mygo.MenuItem{
		{Role: mygo.RoleAppMenu, Label: "Fuwa", Submenu: []*mygo.MenuItem{
			role(mygo.RoleAbout, "About Fuwa", "关于 Fuwa"), mygo.Separator(),
			role(mygo.RoleServices, "Services", "服务"), mygo.Separator(),
			role(mygo.RoleHide, "Hide Fuwa", "隐藏 Fuwa"),
			role(mygo.RoleHideOthers, "Hide Others", "隐藏其他"),
			role(mygo.RoleUnhide, "Show All", "显示全部"), mygo.Separator(),
			role(mygo.RoleQuit, "Quit Fuwa", "退出 Fuwa"),
		}},
		{Label: "Fuwa", Submenu: []*mygo.MenuItem{
			a.item(m.T("Show Fuwa", "显示 Fuwa"), a.showMain),
			a.item(m.T("Pin front window", "置顶前方窗口"), func() { a.front(false) }),
			a.item(m.T("Clear all pins", "全部取消置顶"), func() { a.clear(); a.publish() }),
		}},
		{Role: mygo.RoleEditMenu, Label: m.T("Edit", "编辑"), Submenu: []*mygo.MenuItem{
			role(mygo.RoleUndo, "Undo", "撤销"), role(mygo.RoleRedo, "Redo", "重做"), mygo.Separator(),
			role(mygo.RoleCut, "Cut", "剪切"), role(mygo.RoleCopy, "Copy", "复制"), role(mygo.RolePaste, "Paste", "粘贴"),
			role(mygo.RolePasteAndMatchStyle, "Paste and Match Style", "粘贴并匹配样式"),
			role(mygo.RoleDelete, "Delete", "删除"), role(mygo.RoleSelectAll, "Select All", "全选"), mygo.Separator(),
			{Label: m.T("Speech", "语音"), Submenu: []*mygo.MenuItem{
				role(mygo.RoleStartSpeaking, "Start Speaking", "开始朗读"), role(mygo.RoleStopSpeaking, "Stop Speaking", "停止朗读"),
			}},
		}},
		{Role: mygo.RoleWindowMenu, Label: m.T("Window", "窗口"), Submenu: []*mygo.MenuItem{
			role(mygo.RoleMinimize, "Minimize", "最小化"), role(mygo.RoleZoom, "Zoom", "缩放"),
			mygo.Separator(), role(mygo.RoleFront, "Bring All to Front", "全部前置"),
		}},
	}
}
