import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let onWillShowPopover: @MainActor () -> Void
    private let onDidClosePopover: @MainActor () -> Void
    private var preparedIntentForPendingClick = false

    init(
        model: AppModel,
        onWillShowPopover: @escaping @MainActor () -> Void = {},
        onDidClosePopover: @escaping @MainActor () -> Void = {}
    ) {
        self.model = model
        self.onWillShowPopover = onWillShowPopover
        self.onDidClosePopover = onDidClosePopover
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()

        configureStatusItem()
        configurePopover()
        model.onStatusPresentationChanged = { [weak self] in
            self?.refreshStatusItem()
        }
        model.onRequestDismissPopover = { [weak self] in
            self?.closePopover()
        }
        refreshStatusItem()
    }

    func invalidate() {
        closePopover()
        model.onStatusPresentationChanged = nil
        model.onRequestDismissPopover = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func handleStatusItemAction() {
        switch NSApp.currentEvent?.type {
        case .rightMouseDown:
            closePopover()
            onWillShowPopover()
            preparedIntentForPendingClick = true
        case .rightMouseUp:
            if !preparedIntentForPendingClick { onWillShowPopover() }
            if let button = statusItem.button {
                makeQuickMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
            }
            preparedIntentForPendingClick = false
            onDidClosePopover()
        case .leftMouseDown:
            guard !popover.isShown else { return }
            onWillShowPopover()
            preparedIntentForPendingClick = true
        case .leftMouseUp:
            togglePopover(preparingIntentIfNeeded: !preparedIntentForPendingClick)
            preparedIntentForPendingClick = false
        default:
            // Keyboard and accessibility activation do not have a mouse-down
            // phase, so preserve the target in the action itself.
            togglePopover(preparingIntentIfNeeded: true)
        }
    }

    private func togglePopover(preparingIntentIfNeeded: Bool) {
        if popover.isShown {
            closePopover()
        } else {
            showPopover(preparingIntentIfNeeded: preparingIntentIfNeeded)
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleStatusItemAction)
        button.sendAction(on: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp])
        button.imagePosition = .imageLeading
    }

    private func configurePopover() {
        popover.appearance = NSAppearance(named: .aqua)
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentSize = FuwaPopoverLayout.preferredContentSize(
            route: model.route,
            pinCount: model.pins.count,
            actionRowCount: FuwaPopoverLayout.actionRowCount(in: model.pins),
            hasNotice: model.notice != nil,
            hasPermissionWarning: model.hasPermissionWarning,
            dynamicTypeSize: .large
        )
        popover.contentViewController = NSHostingController(
            rootView: FuwaPopoverView(
                model: model,
                onPreferredContentSizeChange: { [weak self] preferredSize in
                    self?.applyPreferredContentSize(preferredSize)
                }
            )
        )
        popover.delegate = self
    }

    private func applyPreferredContentSize(_ preferredSize: NSSize) {
        let visibleSize = statusItem.button?.window?.screen?.visibleFrame.size
            ?? NSScreen.main?.visibleFrame.size

        let targetSize: NSSize
        if let visibleSize {
            // Leave room for the menu bar, popover arrow and screen edges.
            // Content remains scrollable if an accessibility size exceeds the
            // display.
            let maximumWidth = max(320, visibleSize.width - 32)
            let maximumHeight = max(360, visibleSize.height - 64)
            targetSize = NSSize(
                width: min(preferredSize.width, maximumWidth),
                height: min(preferredSize.height, maximumHeight)
            )
        } else {
            targetSize = preferredSize
        }

        guard popover.contentSize != targetSize else { return }
        popover.contentSize = targetSize
    }

    private func showPopover(preparingIntentIfNeeded: Bool) {
        guard let button = statusItem.button else { return }
        if preparingIntentIfNeeded {
            onWillShowPopover()
        }
        applyPreferredContentSize(
            FuwaPopoverLayout.preferredContentSize(
                route: model.route,
                pinCount: model.pins.count,
                actionRowCount: FuwaPopoverLayout.actionRowCount(in: model.pins),
                hasNotice: model.notice != nil,
                hasPermissionWarning: model.hasPermissionWarning,
                dynamicTypeSize: .large
            )
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() {
        popover.performClose(nil)
    }

    private func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        let hasPins = !model.pins.isEmpty
        let image = NSImage(
            systemSymbolName: hasPins ? "pin.fill" : "pin",
            accessibilityDescription: model.statusItemAccessibilityLabel
        )
        image?.isTemplate = true
        button.image = image
        button.title = hasPins ? " \(model.pins.count)" : ""
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        if model.shortcutIsActive {
            button.toolTip = "\(model.copy.text(.appName)) · \(model.shortcut.displayString)"
        } else {
            button.toolTip = "\(model.copy.text(.appName)) · \(model.copy.text(.shortcutInactive))"
        }
        button.setAccessibilityLabel(model.statusItemAccessibilityLabel)
        button.setAccessibilityHelp(
            model.shortcutIsActive
                ? model.copy.text(.appTagline)
                : model.copy.text(.shortcutInactive)
        )
    }

    func makeQuickMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        func item(_ key: FuwaString, _ selector: Selector, enabled: Bool = true, id: UUID? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: model.copy.text(key), action: selector, keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled
            item.representedObject = id
            return item
        }
        let heading = NSMenuItem(title: "Fuwa · \(model.copy.pinsCount(model.pins.count))", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(item(.pinFrontWindow, #selector(quickPin), enabled: !model.isPinningFrontWindow && !model.isClearingAll))
        menu.addItem(item(.openFuwa, #selector(quickOpen)))
        menu.addItem(.separator())
        for pin in model.pins {
            let row = NSMenuItem(title: "\(pin.applicationName) — \(pin.windowTitle)", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            let state = NSMenuItem(title: pin.stateTitle(model.copy), action: nil, keyEquivalent: "")
            state.isEnabled = false
            submenu.addItem(state)
            submenu.addItem(item(.showControls, #selector(quickControls(_:)), enabled: pin.canShowControls, id: pin.id))
            let available = !model.busyPinIDs.contains(pin.id) && !model.isClearingAll
            if pin.canFreeze { submenu.addItem(item(.freeze, #selector(quickFreeze(_:)), enabled: available, id: pin.id)) }
            if pin.canResume { submenu.addItem(item(.resume, #selector(quickResume(_:)), enabled: available, id: pin.id)) }
            submenu.addItem(item(.revealSource, #selector(quickReveal(_:)), enabled: available && pin.canUseSource, id: pin.id))
            submenu.addItem(.separator())
            submenu.addItem(item(.unpin, #selector(quickUnpin(_:)), enabled: available, id: pin.id))
            row.submenu = submenu
            menu.addItem(row)
        }
        menu.addItem(item(.clearAll, #selector(quickClear), enabled: !model.pins.isEmpty && !model.isClearingAll))
        menu.addItem(.separator())
        menu.addItem(item(.settings, #selector(quickSettings)))
        menu.addItem(item(.quit, #selector(quickQuit)))
        return menu
    }

    @objc private func quickPin() { model.pinFrontWindow() }
    @objc private func quickOpen() { model.openMainWindow() }
    @objc private func quickClear() { model.clearAll() }
    @objc private func quickQuit() { model.quit() }
    @objc private func quickSettings() {
        model.showSettings()
        showPopover(preparingIntentIfNeeded: false)
    }
    @objc private func quickControls(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { model.showControls(id) }
    }
    @objc private func quickFreeze(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { model.freeze(id) }
    }
    @objc private func quickResume(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { model.resume(id) }
    }
    @objc private func quickReveal(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { model.revealSource(id) }
    }
    @objc private func quickUnpin(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { model.unpin(id) }
    }

    func popoverDidClose(_ notification: Notification) {
        guard !popover.isShown else { return }
        preparedIntentForPendingClick = false
        onDidClosePopover()
        model.showPins()
    }
}
