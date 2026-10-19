import AppKit

/// Samples public modifier state only while the optional gesture can affect a
/// picture. It never installs an event tap or consumes a keyboard event.
@MainActor
final class HoldToHideController {
    var onHiddenChanged: ((Bool) -> Void)?

    private let modifierFlags: () -> NSEvent.ModifierFlags
    private let isShortcutRecording: () -> Bool
    private var timer: Timer?
    private(set) var isTemporarilyHidden = false

    init(
        modifierFlags: @escaping () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags },
        isShortcutRecording: @escaping () -> Bool = { false }
    ) {
        self.modifierFlags = modifierFlags
        self.isShortcutRecording = isShortcutRecording
    }

    isolated deinit {
        timer?.invalidate()
    }

    var isMonitoring: Bool { timer != nil }

    func configure(isEnabled: Bool, hasPins: Bool) {
        guard isEnabled, hasPins else {
            stop()
            return
        }
        if timer == nil {
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshModifierState() }
            }
            timer.tolerance = 0.01
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        refreshModifierState()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        setTemporarilyHidden(false)
    }

    func refreshModifierState() {
        guard isMonitoring else { return }
        setTemporarilyHidden(!isShortcutRecording() && Self.shouldHide(for: modifierFlags()))
    }

    static func shouldHide(for flags: NSEvent.ModifierFlags) -> Bool {
        // Caps Lock and the numeric keypad are independent of the held chord.
        // Additional modifiers, including Shift and Command, opt out so a
        // different shortcut does not inherit this gesture.
        let modifiers = flags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad])
        return modifiers == [.control, .option]
    }

    private func setTemporarilyHidden(_ hidden: Bool) {
        guard isTemporarilyHidden != hidden else { return }
        isTemporarilyHidden = hidden
        onHiddenChanged?(hidden)
    }
}
