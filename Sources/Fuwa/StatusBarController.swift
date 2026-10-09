import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem?
    private let menu = NSMenu()
    private let onWillShowMenu: @MainActor () -> Void
    private let onDidCloseMenu: @MainActor () -> Void
    private var menuSession: UUID?

    init(model: AppModel,
         statusItem: NSStatusItem? = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength),
         onWillShowMenu: @escaping @MainActor () -> Void = {},
         onDidCloseMenu: @escaping @MainActor () -> Void = {}) {
        self.model = model
        self.statusItem = statusItem
        self.onWillShowMenu = onWillShowMenu
        self.onDidCloseMenu = onDidCloseMenu
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.minimumWidth = 240
        statusItem?.menu = menu
        statusItem?.button?.imagePosition = .imageLeading
        model.onStatusPresentationChanged = { [weak self] in self?.refreshStatusItem() }
        refreshStatusItem()
    }

    func invalidate() {
        menu.cancelTracking()
        menu.delegate = nil
        menuSession = nil
        onDidCloseMenu()
        model.onStatusPresentationChanged = nil
        if let statusItem {
            statusItem.menu = nil
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        let hasPins = !model.pins.isEmpty
        let attention = model.notice?.kind == .error || model.hasPermissionWarning
        let image = NSImage(systemSymbolName: attention ? "exclamationmark.circle" : hasPins ? "pin.fill" : "pin",
                            accessibilityDescription: model.statusItemAccessibilityLabel)
        image?.isTemplate = true
        button.image = image
        button.title = hasPins ? " \(model.pins.count)" : ""
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.toolTip = model.notice?.message ?? "\(model.copy.text(.appName)) · \(model.shortcutIsActive ? model.shortcut.displayString : model.copy.text(.shortcutInactive))"
        button.setAccessibilityLabel(model.statusItemAccessibilityLabel)
        button.setAccessibilityHelp(model.copy.text(.appTagline))
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: model.copy.text(.appName))
        menu.autoenablesItems = false
        menu.minimumWidth = 240
        func item(_ key: FuwaString, _ selector: Selector, enabled: Bool = true, id: UUID? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: model.copy.text(key), action: selector, keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled
            item.representedObject = id
            item.identifier = NSUserInterfaceItemIdentifier(key.rawValue)
            return item
        }
        func heading(_ title: String) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        }
        func shortened(_ title: String) -> String {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 0)]
            if (title as NSString).size(withAttributes: attributes).width <= 320 { return title }
            let characters = Array(title)
            for count in stride(from: min(characters.count - 1, 51), through: 0, by: -1) {
                let value = String(characters.prefix((count + 1) / 2)) + "…" + String(characters.suffix(count / 2))
                if (value as NSString).size(withAttributes: attributes).width <= 320 { return value }
            }
            return "…"
        }
        if let notice = model.notice {
            let row = NSMenuItem(title: shortened(notice.message), action: #selector(openNotice), keyEquivalent: "")
            row.target = self
            row.toolTip = notice.message
            if notice.kind == .error { row.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil) }
            menu.addItem(row)
            menu.addItem(.separator())
        } else if model.hasPermissionWarning {
            menu.addItem(item(.permissionAttention, #selector(openSettings)))
            menu.addItem(.separator())
        }
        let pin = item(.pinFrontWindow, #selector(pinFrontWindow), enabled: !model.isPinningFrontWindow && !model.isClearingAll)
        // Display the shortcut here; the existing Carbon handler owns it.
        if model.shortcutIsActive { pin.title += "  \(model.shortcut.displayString)" }
        pin.toolTip = model.shortcutIsActive ? model.shortcut.displayString : model.copy.text(.shortcutInactive)
        menu.addItem(pin)
        let choose = item(.chooseWindow, #selector(chooseWindow), enabled: !model.isPinningFrontWindow && !model.isClearingAll)
        choose.title += "…"
        menu.addItem(choose)
        menu.addItem(.separator())
        menu.addItem(heading(model.pins.isEmpty ? model.copy.text(.emptyTitle) : model.copy.pinsCount(model.pins.count)))
        for pin in model.pins {
            let title = "\(pin.applicationName) — \(pin.windowTitle)"
            let row = NSMenuItem(title: shortened(title), action: nil, keyEquivalent: "")
            row.toolTip = title
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            submenu.addItem(heading(pin.stateTitle(model.copy)))
            submenu.addItem(item(.showControls, #selector(showControls(_:)), enabled: pin.canShowControls, id: pin.id))
            let available = !model.busyPinIDs.contains(pin.id) && !model.isClearingAll
            if pin.canFreeze { submenu.addItem(item(.freeze, #selector(pause(_:)), enabled: available, id: pin.id)) }
            if pin.canResume { submenu.addItem(item(.resume, #selector(resume(_:)), enabled: available, id: pin.id)) }
            submenu.addItem(.separator())
            submenu.addItem(item(.unpin, #selector(unpin(_:)), enabled: available, id: pin.id))
            row.submenu = submenu
            menu.addItem(row)
        }
        if !model.pins.isEmpty { menu.addItem(item(.clearAll, #selector(clearAll), enabled: !model.isClearingAll)) }
        menu.addItem(.separator())
        menu.addItem(item(.openFuwa, #selector(openFuwa)))
        let settings = item(.settings, #selector(openSettings))
        settings.title += "…"
        settings.keyEquivalent = ","
        settings.keyEquivalentModifierMask = .command
        menu.addItem(settings)
        menu.addItem(item(.about, #selector(about)))
        menu.addItem(.separator())
        let quit = item(.quit, #selector(quit))
        quit.keyEquivalent = "q"
        quit.keyEquivalentModifierMask = .command
        menu.addItem(quit)
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let contents = makeMenu()
        for item in Array(contents.items) { contents.removeItem(item); menu.addItem(item) }
    }
    func menuWillOpen(_ menu: NSMenu) { menuSession = UUID(); onWillShowMenu() }
    func menuDidClose(_ menu: NSMenu) {
        let session = menuSession
        // AppKit can close a menu before sending its selected action. Allow the
        // action to claim the prepared window before discarding the snapshot.
        DispatchQueue.main.async { [weak self] in
            guard let self, let session, menuSession == session else { return }
            menuSession = nil
            onDidCloseMenu()
        }
    }
    @objc private func pinFrontWindow() { model.pinFrontWindow() }
    @objc private func chooseWindow() { model.chooseWindow() }
    @objc private func openFuwa() { model.showPins(); model.openMainWindow() }
    @objc private func openSettings() { model.showSettings(); model.openMainWindow() }
    @objc private func openNotice() { model.openMainWindow() }
    @objc private func about() { model.showAbout() }
    @objc private func clearAll() { model.clearAll() }
    @objc private func quit() { model.quit() }
    @objc private func showControls(_ sender: NSMenuItem) { if let id = sender.representedObject as? UUID { model.showControls(id) } }
    @objc private func pause(_ sender: NSMenuItem) { if let id = sender.representedObject as? UUID { model.freeze(id) } }
    @objc private func resume(_ sender: NSMenuItem) { if let id = sender.representedObject as? UUID { model.resume(id) } }
    @objc private func unpin(_ sender: NSMenuItem) { if let id = sender.representedObject as? UUID { model.unpin(id) } }
}
