import AppKit
import Foundation
import FuwaCore
import Testing
@testable import Fuwa

@Suite(.serialized)
@MainActor
struct HoldToHideTests {
    @Test func chordRequiresControlAndOptionWithoutOtherHeldModifiers() {
        #expect(HoldToHideController.shouldHide(for: [.control, .option]))
        #expect(HoldToHideController.shouldHide(for: [.control, .option, .capsLock, .numericPad]))
        for flags: NSEvent.ModifierFlags in [[], .control, .option, .function,
                                             [.control, .option, .shift],
                                             [.control, .option, .command],
                                             [.control, .option, .function]] {
            #expect(!HoldToHideController.shouldHide(for: flags))
        }
    }

    @Test func monitoringRequiresOptInAndPicturesAndReleasesOnStop() {
        var flags: NSEvent.ModifierFlags = [.control, .option]
        var reads = 0
        let controller = HoldToHideController(modifierFlags: { reads += 1; return flags })
        var visibilityChanges: [Bool] = []
        controller.onHiddenChanged = { visibilityChanges.append($0) }
        defer { controller.stop() }

        controller.configure(isEnabled: false, hasPins: true)
        controller.configure(isEnabled: true, hasPins: false)
        controller.refreshModifierState()
        #expect(!controller.isMonitoring)
        #expect(reads == 0)

        controller.configure(isEnabled: true, hasPins: true)
        #expect(controller.isMonitoring)
        #expect(controller.isTemporarilyHidden)
        controller.refreshModifierState()
        #expect(visibilityChanges == [true])

        flags = .control
        controller.refreshModifierState()
        flags = [.control, .option]
        controller.refreshModifierState()
        controller.configure(isEnabled: false, hasPins: true)
        #expect(!controller.isMonitoring)
        #expect(!controller.isTemporarilyHidden)
        #expect(visibilityChanges == [true, false, true, false])

        let stoppedReads = reads
        controller.refreshModifierState()
        #expect(reads == stoppedReads)
        controller.configure(isEnabled: true, hasPins: true)
        controller.configure(isEnabled: true, hasPins: false)
        #expect(!controller.isMonitoring)
        #expect(visibilityChanges == [true, false, true, false, true, false])
    }

    @Test func releasingGesturePreservesManualHideAndLatestApplicationRule() {
        var policy = PinVisibilityPolicy(activeApplicationBundleIdentifier: "org.example.editor", ownBundleIdentifier: "app.fuwa")
        let unbound = PinOptions()
        var scoped = PinOptions()
        scoped.applicationScopeBundleIdentifier = "org.example.editor"
        policy.arePinsHidden = true
        let manualRevision = policy.globalVisibilityRevision
        policy.arePinsTemporarilyHidden = true
        policy.arePinsTemporarilyHidden = false
        #expect(policy.arePinsHidden)
        #expect(policy.globalVisibilityRevision == manualRevision)
        #expect(policy.suppresses(unbound))

        policy.arePinsTemporarilyHidden = true
        policy.arePinsHidden = false
        #expect(policy.suppresses(unbound))
        policy.applicationActivated(bundleIdentifier: "org.example.browser")
        policy.arePinsTemporarilyHidden = false
        #expect(!policy.suppresses(unbound))
        #expect(policy.suppresses(scoped))

        policy.arePinsTemporarilyHidden = true
        policy.applicationActivated(bundleIdentifier: "org.example.editor")
        #expect(policy.suppresses(scoped))
        policy.arePinsTemporarilyHidden = false
        #expect(!policy.suppresses(scoped))
    }

    @Test func recordingShortcutTemporarilySuspendsTheGesture() {
        var isRecording = true
        let controller = HoldToHideController(
            modifierFlags: { [.control, .option] },
            isShortcutRecording: { isRecording }
        )
        defer { controller.stop() }
        var changes: [Bool] = []
        controller.onHiddenChanged = { changes.append($0) }
        controller.configure(isEnabled: true, hasPins: true)
        #expect(!controller.isTemporarilyHidden)
        isRecording = false
        controller.refreshModifierState()
        #expect(controller.isTemporarilyHidden)
        isRecording = true
        controller.refreshModifierState()
        #expect(!controller.isTemporarilyHidden)
        #expect(changes == [true, false])
    }

    @Test func addingPictureWhileHeldDoesNotRevealTheGroupEarly() {
        var policy = PinVisibilityPolicy(activeApplicationBundleIdentifier: nil, ownBundleIdentifier: "app.fuwa")
        policy.arePinsHidden = true
        let requestRevision = policy.globalVisibilityRevision
        policy.arePinsTemporarilyHidden = true
        let revealed = policy.revealAfterAddingPin(ifUnchangedSince: requestRevision)
        #expect(revealed)
        #expect(!policy.arePinsHidden)
        #expect(policy.suppresses(PinOptions()))
        policy.arePinsTemporarilyHidden = false
        #expect(!policy.suppresses(PinOptions()))
    }

    @Test func holdToHideIsOffByDefaultAndPersistsWithoutChangingShortcuts() throws {
        let suite = "FuwaHoldToHide.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSettingsStore(defaults: defaults)
        #expect(!store.holdToHideEnabled)
        store.holdToHideEnabled = true
        let restored = AppSettingsStore(defaults: defaults)
        #expect(restored.holdToHideEnabled)
        #expect(restored.shortcut == .defaultPin)
        #expect(restored.visibilityShortcut == .defaultVisibility)
        restored.holdToHideEnabled = false
        #expect(!store.holdToHideEnabled)
    }

    @Test func settingChangesNotifyOnlyForNewValues() {
        let model = AppModel()
        #expect(!model.holdToHideEnabled)
        var changes: [Bool] = []
        model.onHoldToHideEnabledChanged = { changes.append($0) }
        model.setHoldToHideEnabled(true)
        model.setHoldToHideEnabled(true)
        model.setHoldToHideEnabled(false)
        #expect(changes == [true, false])
        #expect(!model.holdToHideEnabled)
        #expect(AppModel(holdToHideEnabled: true).holdToHideEnabled)
    }
}
