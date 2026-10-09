import AppKit
import SwiftUI

/// A persistent management surface opened from the menu bar or the Dock.
/// The menu and window share live pin, navigation and permission state.
@MainActor
final class MainWindowController: NSObject {
    let window: NSWindow
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification, object: NSApp)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification, object: NSApp)

        window.title = model.copy.text(.appName)
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .white
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentMinSize = Self.minimumContentSize
        window.contentMaxSize = NSSize(
            width: Self.maximumContentWidth,
            height: .greatestFiniteMagnitude
        )
        window.contentViewController = NSHostingController(
            rootView: MainView(model: model)
        )
        window.setContentSize(Self.defaultContentSize)
        window.center()
    }

    /// Opens the window and brings Fuwa forward. Called when the Dock icon is
    /// clicked, including relaunches that macOS routes to the running copy.
    func present() {
        if !window.isVisible {
            window.center()
        }
        // Ordering alone cannot lift a normal window above floating mirrors.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        FuwaDockPresence.update(keepInDock: model.keepInDock)
    }

    @objc private func applicationDidBecomeActive() {
        guard window.isVisible else { return }
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    }

    @objc private func applicationDidResignActive() {
        // Management should not stay above other apps after the user leaves Fuwa.
        window.level = .normal
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // Keep enough room for the sidebar, source titles and labeled actions.
    private static let defaultContentSize = NSSize(width: 720, height: 540)
    private static let minimumContentSize = NSSize(width: 640, height: 460)
    private static let maximumContentWidth: CGFloat = 1000
}
