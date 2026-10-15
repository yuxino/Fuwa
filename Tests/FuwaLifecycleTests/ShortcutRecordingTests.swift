import AppKit
import FuwaCore
import Testing
@testable import Fuwa

@Suite(.serialized)
@MainActor
struct ShortcutRecordingTests {
    @Test func recordingConsumesCommandQBeforeItReachesTheQuitMenu() throws {
        _ = NSApplication.shared
        let (window, recorder) = makeRecorder()
        defer { window.contentView = nil; window.close() }
        var captured: KeyboardShortcut?
        recorder.onCapture = { captured = $0 }
        recorder.setRecording(true)
        #expect(window.firstResponder === recorder)

        let event = try keyEvent("q", code: 12, modifiers: .command, window: window)
        #expect(window.performKeyEquivalent(with: event))
        #expect(captured == KeyboardShortcut(keyCode: 12, keyLabel: "Q", modifiers: .command))
    }

    @Test func nonRecordingAndUnfocusedRecordersLeaveKeyEquivalentsAlone() throws {
        _ = NSApplication.shared
        let (window, recorder) = makeRecorder()
        defer { window.contentView = nil; window.close() }
        var captures = 0
        var cancellations = 0
        recorder.onCapture = { _ in captures += 1 }
        recorder.onCancel = { cancellations += 1 }
        let event = try keyEvent("q", code: 12, modifiers: .command, window: window)
        #expect(!recorder.performKeyEquivalent(with: event))

        recorder.setRecording(true)
        #expect(window.makeFirstResponder(nil))
        #expect(cancellations == 1)
        #expect(!recorder.performKeyEquivalent(with: event))
        #expect(captures == 0)
    }

    @Test func recordingPreservesEscapeAndValidationForKeyEquivalents() throws {
        _ = NSApplication.shared
        let (window, recorder) = makeRecorder()
        defer { window.contentView = nil; window.close() }
        var captures = 0
        var invalidInputs = 0
        var cancellations = 0
        recorder.onCapture = { _ in captures += 1 }
        recorder.onInvalid = { invalidInputs += 1 }
        recorder.onCancel = { cancellations += 1 }
        recorder.setRecording(true)

        let unmodified = try keyEvent("q", code: 12, modifiers: [], window: window)
        #expect(recorder.performKeyEquivalent(with: unmodified))
        #expect(invalidInputs == 1 && captures == 0)

        let escape = try keyEvent("\u{1b}", code: 53, modifiers: [], window: window)
        #expect(recorder.performKeyEquivalent(with: escape))
        #expect(cancellations == 1 && captures == 0)
    }

    private func makeRecorder() -> (NSWindow, ShortcutCaptureNSView) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 180, height: 60),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let recorder = ShortcutCaptureNSView(frame: window.contentLayoutRect)
        window.contentView = recorder
        return (window, recorder)
    }

    private func keyEvent(_ characters: String, code: UInt16,
                          modifiers: NSEvent.ModifierFlags, window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code))
    }
}
