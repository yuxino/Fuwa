import AppKit
import FuwaCore
import Testing
@testable import Fuwa

@Suite(.serialized)
@MainActor
struct GettingStartedTests {
    @Test func guideNavigationDoesNotRequestPermissionUntilTheExplicitAction() {
        var permissionRequests = 0
        var settingsOpens = 0
        var actions = FuwaAppActions()
        actions.requestScreenRecordingPermission = { permissionRequests += 1 }
        actions.openScreenRecordingSettings = { settingsOpens += 1 }
        let model = AppModel(screenRecordingPermission: .unknown, actions: actions)
        model.showGuide()
        #expect(permissionRequests == 0 && settingsOpens == 0)
        model.requestScreenRecordingPermission()
        #expect(permissionRequests == 1 && settingsOpens == 0)
        // Sending a request does not itself prove that macOS granted access.
        #expect(model.screenRecordingPermission == .unknown)
        model.showPins()
        model.showGuide()
        #expect(permissionRequests == 1 && settingsOpens == 0)
        model.openScreenRecordingSettings()
        #expect(permissionRequests == 1 && settingsOpens == 1)
        model.updatePermissions(screenRecording: .granted)
        model.requestScreenRecordingPermission()
        #expect(permissionRequests == 1)
    }

    @Test func dismissingGuidePersistsWithoutChangingExistingPreferences() throws {
        let suite = "FuwaGettingStarted.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSettingsStore(defaults: defaults)
        #expect(!store.hasSeenGuide)
        store.didRequestScreenRecording = true
        store.language = .japanese
        store.holdToHideEnabled = true
        let model = AppModel()
        var dismissals = 0
        model.onGuideDismissed = { store.hasSeenGuide = true; dismissals += 1 }
        model.showGuide()
        model.showGuide()
        #expect(!store.hasSeenGuide && dismissals == 0)
        model.showSettings()
        #expect(model.route == .settings)
        #expect(dismissals == 1)
        model.showPins()
        #expect(dismissals == 1)
        let restored = AppSettingsStore(defaults: defaults)
        #expect(restored.hasSeenGuide)
        #expect(restored.didRequestScreenRecording)
        #expect(restored.language == .japanese)
        #expect(restored.holdToHideEnabled)
        model.showGuide()
        #expect(model.route == .guide)
        #expect(dismissals == 1)
    }

    @Test func choosingFromGuideCompletesItAndReopeningClosesThePicker() {
        var windowOpens = 0
        var dismissals = 0
        var actions = FuwaAppActions()
        actions.openMainWindow = { windowOpens += 1 }
        let model = AppModel(screenRecordingPermission: .granted, actions: actions)
        model.onGuideDismissed = { dismissals += 1 }
        model.showGuide()
        model.chooseWindow()
        #expect(model.route == .pins && model.isChoosingWindow)
        #expect(dismissals == 1 && windowOpens == 1)
        model.showGuide()
        #expect(model.route == .guide && !model.isChoosingWindow)
        #expect(dismissals == 1 && windowOpens == 1)
        model.showPins()
        #expect(dismissals == 2)
    }

    @Test func menuCanReopenTheGuideInEveryLanguage() throws {
        _ = NSApplication.shared
        for language in FuwaLanguage.allCases {
            var opened = 0
            var actions = FuwaAppActions()
            actions.openMainWindow = { opened += 1 }
            let model = AppModel(copy: FuwaCopy(language: language), actions: actions)
            let controller = StatusBarController(model: model, statusItem: nil)
            defer { controller.invalidate() }
            model.showGuide()
            model.showPins()
            let menu = controller.makeMenu()
            let index = try #require(menu.items.firstIndex {
                $0.identifier?.rawValue == FuwaString.gettingStarted.rawValue
            })
            #expect(menu.items[index].isEnabled)
            #expect(menu.items[index].title == model.copy.text(.gettingStarted))
            menu.performActionForItem(at: index)
            #expect(model.route == .guide)
            #expect(opened == 1)
        }
    }

    @Test func arrangementOnlyAppearsForReferencesAndPreservesPlaybackAndVisibility() {
        var corners: [ReferenceArrangementCorner] = []
        var optionsChanges = 0
        var actions = FuwaAppActions()
        actions.arrangeReferences = { corners.append($0) }
        actions.updatePinOptions = { _, _ in optionsChanges += 1 }
        let model = AppModel(actions: actions)
        #expect(!model.canArrangeReferences)
        var referenceOptions = PinOptions()
        referenceOptions.presentationMode = .reference
        let reference = PinSnapshot(id: UUID(), sourceWindowID: 901, applicationName: "Preview",
            bundleIdentifier: nil, windowTitle: "Paused reference", state: .frozen(.manual),
            errorMessage: nil, options: referenceOptions, isHidden: true)
        let following = PinSnapshot(id: UUID(), sourceWindowID: 902, applicationName: "Editor",
            bundleIdentifier: nil, windowTitle: "Following picture", state: .live, errorMessage: nil,
            isHidden: true)
        model.updatePins([following, reference])
        model.updatePinsVisibility(true)
        #expect(model.canArrangeReferences)
        for corner in ReferenceArrangementCorner.allCases { model.arrangeReferences(in: corner) }
        #expect(corners == ReferenceArrangementCorner.allCases)
        #expect(optionsChanges == 0)
        #expect(model.pins == [following, reference])
        #expect(model.arePinsHidden)
        model.updatePins([following])
        #expect(!model.canArrangeReferences)
        model.arrangeReferences(in: .topRight)
        #expect(corners.count == 4)
        #expect(model.pins == [following])
    }

    @Test func clearingPinsBlocksArrangement() async {
        var options = PinOptions()
        options.presentationMode = .reference
        let model = AppModel()
        model.updatePins([PinSnapshot(id: UUID(), sourceWindowID: 903, applicationName: "Preview",
            bundleIdentifier: nil, windowTitle: "Reference", state: .live, errorMessage: nil, options: options)])
        var arranged = 0
        var actions = FuwaAppActions()
        actions.arrangeReferences = { _ in arranged += 1 }
        actions.clearAll = {}
        model.configure(actions: actions)
        model.clearAll()
        #expect(!model.canArrangeReferences)
        model.arrangeReferences(in: .bottomLeft)
        #expect(arranged == 0)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while model.isClearingAll && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(!model.isClearingAll)
    }
}
