import Carbon.HIToolbox
import Foundation
import FuwaCore

@MainActor
final class GlobalHotKey {
    enum RegistrationError: LocalizedError {
        case installHandler(OSStatus)
        case registerHotKey(OSStatus, String)

        var errorDescription: String? {
            switch self {
            case .installHandler(let status):
                "无法安装快捷键事件处理器（\(status)）"
            case .registerHotKey(let status, let shortcut):
                "无法注册 \(shortcut)（\(status)），可能与其他软件冲突"
            }
        }
    }

    private static let signature: OSType = 0x4655_5741 // FUWA
    private let identifier: UInt32

    private let action: () -> Void
    private var hotKeyReference: EventHotKeyRef?
    private var handlerReference: EventHandlerRef?
    private(set) var currentShortcut: KeyboardShortcut?

    init(identifier: UInt32 = 1, action: @escaping () -> Void) {
        self.identifier = identifier
        self.action = action
    }

    func start(shortcut: KeyboardShortcut = .defaultPin) throws {
        try shortcut.validate()
        guard hotKeyReference == nil else { return }

        try installHandlerIfNeeded()
        let status = register(shortcut)
        guard status == noErr else {
            stop()
            throw RegistrationError.registerHotKey(status, shortcut.displayString)
        }
        currentShortcut = shortcut
    }

    /// Re-registers the global shortcut and restores the previous registration
    /// immediately if Carbon reports a conflict or another failure. If Carbon
    /// rejects both registrations, `.inactive` makes that loss explicit to the
    /// UI instead of claiming the old shortcut is still active.
    func update(to proposed: KeyboardShortcut) throws -> KeyboardShortcutRegistrationOutcome {
        try proposed.validate()
        try installHandlerIfNeeded()
        guard proposed != currentShortcut else { return .registered }

        let previous = currentShortcut
        unregisterHotKeyOnly()
        let proposedStatus = register(proposed)
        if proposedStatus == noErr {
            currentShortcut = proposed
            return .registered
        }

        if let previous {
            let rollbackStatus = register(previous)
            if rollbackStatus == noErr {
                currentShortcut = previous
            } else {
                currentShortcut = nil
                return .inactive
            }
        } else {
            currentShortcut = nil
            return .inactive
        }

        return proposedStatus == eventHotKeyExistsErr ? .conflict : .failed
    }

    private func installHandlerIfNeeded() throws {
        guard handlerReference == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }

                var identifier = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )

                let hotKey = Unmanaged<GlobalHotKey>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                guard
                    parameterStatus == noErr,
                    identifier.signature == GlobalHotKey.signature,
                    identifier.id == hotKey.identifier
                else {
                    return OSStatus(eventNotHandledErr)
                }

                MainActor.assumeIsolated {
                    hotKey.action()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerReference
        )

        guard handlerStatus == noErr else {
            throw RegistrationError.installHandler(handlerStatus)
        }

    }

    private func register(_ shortcut: KeyboardShortcut) -> OSStatus {
        let identifier = EventHotKeyID(
            signature: Self.signature,
            id: self.identifier
        )
        return RegisterEventHotKey(
            shortcut.keyCode,
            carbonModifiers(for: shortcut.modifiers),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
    }

    private func carbonModifiers(for modifiers: KeyboardShortcut.Modifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    private func unregisterHotKeyOnly() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
    }

    func stop() {
        unregisterHotKeyOnly()
        currentShortcut = nil
        if let handlerReference {
            RemoveEventHandler(handlerReference)
            self.handlerReference = nil
        }
    }

    isolated deinit {
        stop()
    }
}
