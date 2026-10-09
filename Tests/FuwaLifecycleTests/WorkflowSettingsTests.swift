import Foundation
import FuwaCore
import Testing
@testable import Fuwa

@Suite(.serialized)
@MainActor
struct WorkflowSettingsTests {
    @Test func visibilityShortcutAndApplicationRatesPersistIndependently() throws {
        let suite = "FuwaWorkflowSettings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSettingsStore(defaults: defaults)
        #expect(store.visibilityShortcut == .defaultVisibility)
        #expect(store.frameRate(for: "org.example.editor") == .thirty)
        let shortcut = KeyboardShortcut(keyCode: 4, keyLabel: "H", modifiers: [.control, .option])
        store.visibilityShortcut = shortcut
        store.setFrameRate(.five, for: "org.example.editor")
        store.setFrameRate(.sixty, for: "org.example.video")
        let restored = AppSettingsStore(defaults: defaults)
        #expect(restored.visibilityShortcut == shortcut)
        #expect(restored.shortcut == .defaultPin)
        #expect(restored.frameRate(for: "org.example.editor") == .five)
        #expect(restored.frameRate(for: "org.example.video") == .sixty)
        #expect(restored.frameRate(for: nil) == .thirty)
        defaults.set(["org.example.editor": 999], forKey: "applicationFrameRates")
        defaults.set(Data("invalid".utf8), forKey: "visibilityShortcut")
        #expect(restored.frameRate(for: "org.example.editor") == .thirty)
        #expect(restored.visibilityShortcut == .defaultVisibility)
    }

    @Test func physicalShortcutComparisonIgnoresDisplayLabel() {
        let alias = KeyboardShortcut(keyCode: 35, keyLabel: "p", modifiers: [.option, .command])
        #expect(alias.hasSameKeyCombination(as: .defaultPin))
        #expect(!alias.hasSameKeyCombination(as: .defaultVisibility))
    }

    @Test func pinShortcutConflictPreservesAnInactiveRegistration() async {
        var actions = FuwaAppActions()
        actions.updateShortcut = { _ in .conflict }
        let model = AppModel(shortcutIsActive: false, actions: actions)
        model.proposeShortcut(.defaultVisibility)
        await settle { !model.isUpdatingShortcut }
        #expect(!model.shortcutIsActive)
        #expect(model.shortcut == .defaultPin)
        #expect(model.notice?.kind == .error)
    }

    @Test func failedVisibilityShortcutDoesNotInventAnActiveRegistration() async {
        var actions = FuwaAppActions()
        actions.updateVisibilityShortcut = { _ in .failed }
        let model = AppModel(visibilityShortcutIsActive: false, actions: actions)
        let proposed = KeyboardShortcut(keyCode: 4, keyLabel: "H", modifiers: [.control, .option])
        model.updateVisibilityShortcut(proposed)
        await settle { !model.isUpdatingVisibilityShortcut }
        #expect(!model.visibilityShortcutIsActive)
        #expect(model.visibilityShortcut == .defaultVisibility)
        #expect(model.notice?.kind == .error)
    }

    @Test func hideActionRetainsPinsAndManualPlaybackState() async {
        let pin = PinSnapshot(id: UUID(), sourceWindowID: 901, applicationName: "Preview",
                              bundleIdentifier: "com.apple.Preview", windowTitle: "Reference",
                              state: .frozen(.manual), errorMessage: nil)
        let model = AppModel()
        model.updatePins([pin])
        var toggles = 0
        var clearCalls = 0
        var actions = FuwaAppActions()
        actions.togglePinsVisibility = { toggles += 1; model.updatePinsVisibility(true) }
        actions.clearAll = { clearCalls += 1 }
        model.configure(actions: actions)
        model.togglePinsVisibility()
        await settle { !model.isTogglingVisibility }
        #expect(toggles == 1)
        #expect(clearCalls == 0)
        #expect(model.arePinsHidden)
        #expect(model.pins == [pin])
        model.updatePins([])
        #expect(!model.arePinsHidden)
    }

    @Test func visibilityCanBeHiddenAgainWhileEarlierRestoreIsSuspended() async {
        let model = AppModel()
        let pin = PinSnapshot(id: UUID(), sourceWindowID: 903, applicationName: "Preview",
                              bundleIdentifier: nil, windowTitle: "Reference", state: .live, errorMessage: nil)
        model.updatePins([pin])
        model.updatePinsVisibility(true)
        var calls = 0
        var firstOperation: CheckedContinuation<Void, Never>?
        var actions = FuwaAppActions()
        actions.togglePinsVisibility = {
            calls += 1
            model.updatePinsVisibility(!model.arePinsHidden)
            if calls == 1 { await withCheckedContinuation { firstOperation = $0 } }
        }
        model.configure(actions: actions)
        model.togglePinsVisibility()
        await settle { calls >= 1 }
        model.togglePinsVisibility()
        await settle { calls >= 2 }
        #expect(model.arePinsHidden)
        #expect(model.isTogglingVisibility)
        firstOperation?.resume()
        await settle { !model.isTogglingVisibility }
        #expect(model.pins == [pin])
    }

    @Test func normalVisibilityCancellationDoesNotShowAnError() async {
        let model = AppModel()
        model.updatePins([PinSnapshot(id: UUID(), sourceWindowID: 904, applicationName: "Preview",
            bundleIdentifier: nil, windowTitle: "Reference", state: .live, errorMessage: nil)])
        var actions = FuwaAppActions()
        actions.togglePinsVisibility = { throw CancellationError() }
        model.configure(actions: actions)
        model.togglePinsVisibility()
        await settle { !model.isTogglingVisibility }
        #expect(model.notice == nil)
    }

    @Test func hiddenPinsCanBeConfiguredButDoNotBeginCropSelection() {
        let id = UUID()
        let pin = PinSnapshot(id: id, sourceWindowID: 902, applicationName: "Preview",
                              bundleIdentifier: "com.apple.Preview", windowTitle: "Reference",
                              state: .live, errorMessage: nil, isHidden: true)
        let model = AppModel()
        model.updatePins([pin])
        var crops = 0
        var changedOptions: PinOptions?
        var actions = FuwaAppActions()
        actions.beginCropSelection = { _ in crops += 1 }
        actions.updatePinOptions = { pinID, options in
            #expect(pinID == id)
            changedOptions = options
        }
        model.configure(actions: actions)
        model.beginCropSelection(id)
        var options = PinOptions()
        options.frameRate = .five
        model.setPinOptions(options, for: id)
        #expect(crops == 0)
        #expect(changedOptions?.frameRate == .five)
    }

    private func settle(until condition: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }
}
