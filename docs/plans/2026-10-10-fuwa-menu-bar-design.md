# Menu bar interactions

The menu bar is a quick-action surface. Language, startup, Dock visibility,
permissions and updates belong in the existing main Settings window.

Clicking either mouse button opens the same native menu. Pin Front Window and
Choose a Window come first, followed by pinned windows and their state-aware
submenus. Open Fuwa, Settings, About and Quit are always directly available.
Empty lists omit Unpin All. Long window titles are shortened in the menu and
remain available in tooltips. All seven existing languages use the same layout.

Settings selects the main window's Settings page; Choose a Window opens its
picker. Both use model state rather than separate local navigation state. Menu
closing never resets the selected page. Opening a menu prepares the front-window
intent; selected actions claim it synchronously before deferred cleanup. Cancelled
menus discard that intent, and cleanup from an earlier menu cannot clear a newer
menu's target. Errors remain accessible through the menu and the main window.

The Dock preference changes activation policy without closing, centering or
resizing windows. Visible windows are protected from hiding during the change,
and the current key window and active state are restored. Opening the main
window and Launch Services activation reapply the saved preference.

Verification covers menu actions, state availability, translated labels,
navigation, selected-action/cancellation ordering and preference persistence.
Visible-window regressions can be excluded with `FUWA_HEADLESS_TESTS=1` while
someone is using the desktop. Native menu tracking, Quick Look pinning, Dock
focus, restart and submenu actions still require testing on a dedicated desktop.
Build/install evidence is recorded separately from that interaction acceptance.
