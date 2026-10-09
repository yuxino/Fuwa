import AppKit

@MainActor
enum FuwaDockPresence {
    static func update(keepInDock: Bool) {
        let policy: NSApplication.ActivationPolicy = keepInDock ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }

        let wasActive = NSApp.isActive
        let wasHidden = NSApp.isHidden
        let keyWindow = NSApp.keyWindow
        let visibleWindows = NSApp.orderedWindows.filter { $0.isVisible && !$0.isMiniaturized }
        let windowStates = visibleWindows.map { ($0, $0.canHide, $0.hidesOnDeactivate) }
        // Changing activation policy can hide or deactivate windows. The Dock
        // preference must leave the user's current presentation untouched.
        for (window, _, _) in windowStates {
            window.canHide = false
            window.hidesOnDeactivate = false
        }
        defer {
            for (window, canHide, hidesOnDeactivate) in windowStates {
                window.canHide = canHide
                window.hidesOnDeactivate = hidesOnDeactivate
            }
        }

        NSApp.setActivationPolicy(policy)
        if !wasHidden && NSApp.isHidden { NSApp.unhideWithoutActivation() }
        if wasActive { NSApp.activate(ignoringOtherApps: true) }
        for window in visibleWindows.reversed() where !window.isVisible {
            window.orderFrontRegardless()
        }
        keyWindow?.makeKey()
    }
}
