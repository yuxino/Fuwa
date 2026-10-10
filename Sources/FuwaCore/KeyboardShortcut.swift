import Foundation

/// A persistable physical-key shortcut, independent of AppKit and Carbon.
///
/// `keyCode` is the macOS virtual key code used by the integration layer. `keyLabel`
/// is presentation metadata captured at recording time, so Fuwa does not need to guess
/// the user's keyboard layout while rendering settings.
public struct KeyboardShortcut: Codable, Equatable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Equatable, Hashable, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let command = Self(rawValue: 1 << 0)
        public static let option = Self(rawValue: 1 << 1)
        public static let control = Self(rawValue: 1 << 2)
        public static let shift = Self(rawValue: 1 << 3)

        public static let supported: Self = [.command, .option, .control, .shift]

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.init(rawValue: try container.decode(UInt8.self))
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    public enum ValidationError: Error, Equatable, Hashable, Sendable {
        case keyCodeOutOfRange(UInt32)
        case emptyKeyLabel
        case keyLabelTooLong
        case unsupportedModifiers(rawValue: UInt8)
        case requiresPrimaryModifier
    }

    /// `kVK_ANSI_P` is 35. Keeping that platform detail at the integration boundary
    /// would force FuwaCore to import Carbon, so the stable virtual key value lives here.
    public static let defaultPin = Self(
        keyCode: 35,
        keyLabel: "P",
        modifiers: [.option, .command]
    )

    public static let defaultVisibility = Self(
        keyCode: 35, keyLabel: "P", modifiers: [.option, .shift, .command]
    )

    public func hasSameKeyCombination(as other: Self) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }

    public let keyCode: UInt32
    public let keyLabel: String
    public let modifiers: Modifiers

    public init(keyCode: UInt32, keyLabel: String, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.keyLabel = keyLabel
        self.modifiers = modifiers
    }

    /// A compact, deterministic representation suitable for menus and tooltips.
    public var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result + keyLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var validationError: ValidationError? {
        do {
            try validate()
            return nil
        } catch let error as ValidationError {
            return error
        } catch {
            assertionFailure("KeyboardShortcut.validate() returned an unexpected error: \(error)")
            return .requiresPrimaryModifier
        }
    }

    public func validate() throws {
        // macOS virtual key codes occupy the lower seven bits. This includes arrows,
        // function keys, and JIS-specific keys without importing Carbon into FuwaCore.
        guard keyCode <= 127 else {
            throw ValidationError.keyCodeOutOfRange(keyCode)
        }

        let trimmedLabel = keyLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty else {
            throw ValidationError.emptyKeyLabel
        }
        guard trimmedLabel.count <= 12 else {
            throw ValidationError.keyLabelTooLong
        }

        let unsupportedRawValue = modifiers.rawValue & ~Modifiers.supported.rawValue
        guard unsupportedRawValue == 0 else {
            throw ValidationError.unsupportedModifiers(rawValue: unsupportedRawValue)
        }

        let primaryModifiers: Modifiers = [.command, .option, .control]
        guard !modifiers.intersection(primaryModifiers).isEmpty else {
            throw ValidationError.requiresPrimaryModifier
        }
    }
}

/// The result of attempting to register a proposed global shortcut.
public enum KeyboardShortcutRegistrationOutcome: Equatable, Hashable, Sendable {
    case registered
    case conflict
    case failed
    /// The proposed shortcut failed and Fuwa could not keep a previous
    /// registration active. The UI must not present any shortcut as active.
    case inactive
}

/// An immutable shortcut edit transaction.
///
/// The settings layer keeps this value until Carbon registration completes. Success
/// yields `proposed`; conflicts and other failures yield the exact old value, making
/// persistence and UI rollback a single value assignment rather than compensating edits.
public struct KeyboardShortcutUpdate: Equatable, Hashable, Sendable {
    public let previous: KeyboardShortcut
    public let proposed: KeyboardShortcut

    public init(previous: KeyboardShortcut, proposed: KeyboardShortcut) throws {
        try previous.validate()
        try proposed.validate()
        self.previous = previous
        self.proposed = proposed
    }

    public var committedValue: KeyboardShortcut {
        proposed
    }

    public var rolledBackValue: KeyboardShortcut {
        previous
    }

    public func resolvedValue(after outcome: KeyboardShortcutRegistrationOutcome) -> KeyboardShortcut {
        switch outcome {
        case .registered:
            proposed
        case .conflict, .failed, .inactive:
            previous
        }
    }
}
