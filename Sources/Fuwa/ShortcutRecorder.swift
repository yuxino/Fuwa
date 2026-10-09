import AppKit
import FuwaCore
import SwiftUI

@MainActor
struct ShortcutRecorder: View {
    enum Purpose { case pin, visibility }
    @ObservedObject var model: AppModel
    var purpose: Purpose = .pin
    @State private var isRecording = false
    @State private var hasInvalidInput = false

    private var copy: FuwaCopy { model.copy }
    private var isUpdating: Bool { purpose == .pin ? model.isUpdatingShortcut : model.isUpdatingVisibilityShortcut }
    private var shortcut: FuwaCore.KeyboardShortcut { purpose == .pin ? model.shortcut : model.visibilityShortcut }
    private var titleKey: FuwaString { purpose == .pin ? .shortcut : .visibilityShortcut }

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Button {
                if isRecording {
                    isRecording = false
                } else {
                    hasInvalidInput = false
                    isRecording = true
                }
            } label: {
                HStack(spacing: 7) {
                    if isUpdating {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: isRecording ? "keyboard.fill" : "keyboard")
                            .accessibilityHidden(true)
                    }

                    Text(displayTitle)
                        .font(.system(.callout, design: .monospaced).weight(.medium))
                        .monospacedDigit()

                    if !isRecording && !isUpdating {
                        Text(copy.text(.recordShortcut))
                            .font(.callout)
                            .foregroundStyle(FuwaAppearance.secondaryText)
                    }
                }
                .frame(minWidth: 92)
            }
            .buttonStyle(FuwaQuietButtonStyle())
            .disabled(isUpdating)
            .help(isRecording ? copy.text(.cancel) : copy.text(.recordShortcut))
            .accessibilityLabel(accessibilityTitle)

            if hasInvalidInput {
                Text(copy.text(.invalidShortcut))
                    .font(.system(size: 10))
                    .foregroundStyle(FuwaAppearance.error)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background {
            ShortcutCaptureHost(
                isRecording: isRecording,
                onCapture: { shortcut in
                    isRecording = false
                    hasInvalidInput = false
                    if purpose == .pin {
                        model.proposeShortcut(shortcut)
                    } else {
                        model.updateVisibilityShortcut(shortcut)
                    }
                },
                onInvalid: {
                    hasInvalidInput = true
                },
                onCancel: {
                    isRecording = false
                    hasInvalidInput = false
                }
            )
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .onDisappear {
            isRecording = false
            hasInvalidInput = false
        }
    }

    private var displayTitle: String {
        if isRecording {
            return copy.text(.pressShortcut)
        }
        return shortcut.displayString
    }

    private var accessibilityTitle: String {
        if isRecording {
            return copy.text(.pressShortcut)
        }
        return "\(copy.text(titleKey)): \(shortcut.displayString)"
    }
}

private struct ShortcutCaptureHost: NSViewRepresentable {
    let isRecording: Bool
    let onCapture: (FuwaCore.KeyboardShortcut) -> Void
    let onInvalid: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        update(nsView)
    }

    private func update(_ view: ShortcutCaptureNSView) {
        view.onCapture = onCapture
        view.onInvalid = onInvalid
        view.onCancel = onCancel
        view.setRecording(isRecording)
    }
}

@MainActor
private final class ShortcutCaptureNSView: NSView {
    var onCapture: ((FuwaCore.KeyboardShortcut) -> Void)?
    var onInvalid: (() -> Void)?
    var onCancel: (() -> Void)?

    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    func setRecording(_ recording: Bool) {
        guard isRecording != recording else { return }
        isRecording = recording
        if recording {
            window?.makeFirstResponder(self)
        } else if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if isRecording {
            window?.makeFirstResponder(self)
        }
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign, isRecording {
            isRecording = false
            onCancel?()
        }
        return didResign
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording, !event.isARepeat else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 {
            onCancel?()
            return
        }

        guard !Self.modifierOnlyKeyCodes.contains(event.keyCode) else { return }

        let shortcut = FuwaCore.KeyboardShortcut(
            keyCode: UInt32(event.keyCode),
            keyLabel: Self.keyLabel(for: event),
            modifiers: Self.modifiers(for: event.modifierFlags)
        )

        do {
            try shortcut.validate()
            onCapture?(shortcut)
        } catch {
            NSSound.beep()
            onInvalid?()
        }
    }

    private static let modifierOnlyKeyCodes: Set<UInt16> = [
        54, 55, 56, 57, 58, 59, 60, 61, 62
    ]

    private static func modifiers(
        for flags: NSEvent.ModifierFlags
    ) -> FuwaCore.KeyboardShortcut.Modifiers {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var modifiers: FuwaCore.KeyboardShortcut.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }

    private static func keyLabel(for event: NSEvent) -> String {
        switch event.keyCode {
        case 36, 76: "↩"
        case 48: "⇥"
        case 49: "Space"
        case 51: "⌫"
        case 117: "⌦"
        case 123: "←"
        case 124: "→"
        case 125: "↓"
        case 126: "↑"
        case 122: "F1"
        case 120: "F2"
        case 99: "F3"
        case 118: "F4"
        case 96: "F5"
        case 97: "F6"
        case 98: "F7"
        case 100: "F8"
        case 101: "F9"
        case 109: "F10"
        case 103: "F11"
        case 111: "F12"
        default:
            event.charactersIgnoringModifiers?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ?? ""
        }
    }
}
