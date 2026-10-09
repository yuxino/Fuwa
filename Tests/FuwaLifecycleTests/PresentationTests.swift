import AppKit
import SwiftUI
import Testing
import FuwaCore
@testable import Fuwa

@Suite(.serialized)
@MainActor
struct PresentationTests {
    private func pin(_ state: PinState) -> PinSnapshot {
        PinSnapshot(id: UUID(), sourceWindowID: 100, applicationName: "Preview", bundleIdentifier: nil,
                    windowTitle: "Reference document", state: state, errorMessage: nil)
    }

    @Test func closedSourceCannotResume() {
        let closed = pin(.frozen(.sourceClosed))
        #expect(!closed.canResume)
        #expect(!closed.canFreeze)
        #expect(closed.canShowControls)
        #expect(!pin(.starting).canShowControls)
        #expect(pin(.live).canFreeze)
        #expect(pin(.frozen(.manual)).canResume)
        #expect(pin(.frozen(.captureInterrupted)).canResume)
    }

    @Test func menusExposeAvailabilityAndWindowSpecificActions() throws {
        _ = NSApplication.shared
        let model = AppModel(copy: FuwaCopy(language: .english))
        let controller = StatusBarController(model: model)
        defer { controller.invalidate() }
        let empty = controller.makeQuickMenu()
        #expect(empty.items.first(where: { $0.title == "Unpin All" })?.isEnabled == false)
        #expect(empty.items.contains(where: { $0.title == "Quit Fuwa" && $0.isEnabled }))
        let closed = pin(.frozen(.sourceClosed))
        model.updatePins([closed])
        let submenu = try #require(controller.makeQuickMenu().items.first(where: { $0.submenu != nil })?.submenu)
        #expect(!submenu.items.contains(where: { $0.title == "Go to Original Window" }))
        #expect(submenu.items.contains(where: { $0.title == "Unpin" && $0.isEnabled }))
        #expect(!submenu.items.contains(where: { $0.title == "Resume" }))
        model.updatePins([pin(.live)])
        let liveMenu = try #require(controller.makeQuickMenu().items.first(where: { $0.submenu != nil })?.submenu)
        #expect(liveMenu.items.contains(where: { $0.title == "Pause Picture" && $0.isEnabled }))
        #expect(!liveMenu.items.contains(where: { $0.title == "Go to Original Window" }))
    }

    @Test func clearAllPreventsConcurrentPinCommands() async {
        let model = AppModel()
        model.updatePins([pin(.live)])
        var requestedPin = false
        var actions = FuwaAppActions()
        actions.beginPinFrontWindow = { requestedPin = true; return {} }
        actions.clearAll = { try await Task.sleep(for: .milliseconds(20)) }
        model.configure(actions: actions)
        model.clearAll()
        model.pinFrontWindow()
        #expect(!requestedPin)
        // Wait for completion rather than assuming the main actor has run
        // both tasks within 40 ms on a loaded CI runner.
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while model.isClearingAll && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(!model.isClearingAll)
    }

    @Test func languageSelectionPersistsAndUpdatesExistingMenus() throws {
        _ = NSApplication.shared
        let suite = "FuwaLanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSettingsStore(defaults: defaults)
        #expect(store.language == .system)
        let model = AppModel(languagePreference: store.language)
        model.onLanguageChanged = { store.language = $0 }
        let controller = StatusBarController(model: model)
        defer { controller.invalidate() }
        model.setLanguage(.english)
        #expect(controller.makeQuickMenu().items.contains { $0.title == "Quit Fuwa" })
        model.setLanguage(.simplifiedChinese)
        #expect(model.copy.text(.settings) == "设置")
        #expect(!controller.makeQuickMenu().items.contains { $0.title == "Quit Fuwa" })
        let relaunched = AppModel(languagePreference: AppSettingsStore(defaults: defaults).language)
        #expect(relaunched.copy.language == .simplifiedChinese)
        model.setLanguage(.system)
        #expect(model.copy.language == FuwaLanguage.automatic())
        for preference in FuwaLanguagePreference.allCases {
            model.setLanguage(preference)
            #expect(AppSettingsStore(defaults: defaults).language == preference)
            #expect(controller.makeQuickMenu().items.contains { $0.title == model.copy.text(.quit) })
            let restored = AppModel(languagePreference: AppSettingsStore(defaults: defaults).language)
            #expect(restored.copy.language == preference.resolved)
        }
        defaults.set("invalid", forKey: "language")
        #expect(store.language == .system)
    }

    @Test func closingAndReopeningManagementReportsDockPresence() {
        _ = NSApplication.shared
        var visibility = [Bool]()
        let controller = MainWindowController(model: AppModel()) { visibility.append($0) }
        controller.present()
        controller.window.close()
        controller.present()
        controller.window.close()
        #expect(visibility == [true, false, true, false])
    }

    @Test func qualityChangesOnlyTheRequestedPinAndNewPinsStartAtOriginalQuality() throws {
        let model = AppModel()
        let first = pin(.live)
        let second = pin(.live)
        #expect(first.captureQuality == .native && second.captureQuality == .native)
        model.updatePins([first, second])
        var changedIDs = [UUID]()
        var actions = FuwaAppActions()
        actions.updateCaptureQuality = { id, quality in
            changedIDs.append(id)
            model.updatePins(model.pins.map { snapshot in
                var updated = snapshot
                if snapshot.id == id { updated.captureQuality = quality }
                return updated
            })
        }
        model.configure(actions: actions)
        let reduced = try #require(CaptureQuality(percentage: 50))
        model.setCaptureQuality(reduced, for: first.id)
        model.setCaptureQuality(reduced, for: first.id)
        #expect(changedIDs == [first.id])
        #expect(model.pins[0].captureQuality == reduced)
        #expect(model.pins[1].captureQuality == .native)
        let newlyPinned = pin(.live)
        model.updatePins(model.pins + [newlyPinned])
        #expect(model.pins.last?.captureQuality == .native)
        model.setCaptureQuality(.native, for: first.id)
        #expect(model.pins.allSatisfy { $0.captureQuality == .native })
        #expect(changedIDs == [first.id, first.id])
    }

    @Test func qualityCannotChangeForMissingPausedBusyOrStoppingPins() async throws {
        let model = AppModel()
        var changedIDs = [UUID]()
        var actions = FuwaAppActions()
        actions.updateCaptureQuality = { id, _ in changedIDs.append(id) }
        actions.freeze = { _ in try await Task.sleep(for: .milliseconds(20)) }
        actions.clearAll = { try await Task.sleep(for: .milliseconds(20)) }
        model.configure(actions: actions)
        let reduced = try #require(CaptureQuality(percentage: 50))
        let live = pin(.live)
        let unavailable = [PinState.starting, .frozen(.manual), .frozen(.captureInterrupted),
                           .frozen(.sourceClosed), .failed(.captureFailed), .stopping, .stopped].map(pin)
        model.updatePins([live] + unavailable)
        model.setCaptureQuality(reduced, for: UUID())
        for snapshot in unavailable {
            #expect(!snapshot.canAdjustQuality)
            model.setCaptureQuality(reduced, for: snapshot.id)
        }
        model.freeze(live.id)
        model.setCaptureQuality(reduced, for: live.id)
        model.clearAll()
        model.setCaptureQuality(reduced, for: live.id)
        #expect(changedIDs.isEmpty)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while (model.isClearingAll || !model.busyPinIDs.isEmpty) && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(!model.isClearingAll && model.busyPinIDs.isEmpty)
    }

    @Test func screenRecordingDenialWarnsAboutPinningPermissions() {
        let model = AppModel(screenRecordingPermission: .granted)
        #expect(!model.hasPermissionWarning)
        model.updatePermissions(screenRecording: .denied)
        #expect(model.hasPermissionWarning)
        model.updatePermissions(screenRecording: .unknown)
        #expect(!model.hasPermissionWarning)
    }

    @Test func popoverFitsSmallListsAndKeepsLargeListsBounded() {
        func size(_ count: Int, route: FuwaPopoverRoute = .pins,
                  notice: Bool = false, type: DynamicTypeSize = .large) -> NSSize {
            FuwaPopoverLayout.preferredContentSize(route: route, pinCount: count,
                hasNotice: notice, hasPermissionWarning: false, dynamicTypeSize: type)
        }
        #expect(size(1).height < size(2).height)
        #expect(size(2).height < size(8).height)
        #expect(size(8) == size(12))
        #expect(size(2).height < size(2, route: .settings).height)
        #expect(size(0, route: .settings) == size(8, route: .settings))
        #expect(size(2, notice: true).height > size(2).height)
        #expect(size(2, type: .accessibility3).width > size(2).width)
        #expect(size(2, type: .accessibility3).height > size(2).height)
    }

    @Test func allCopyKeysAndPlaceholdersHaveEveryLanguage() {
        for language in FuwaLanguage.allCases {
            let copy = FuwaCopy(language: language)
            for key in FuwaString.allCases {
                #expect(copy.hasTranslation(for: key), "Missing \(language): \(key)")
                #expect(!copy.text(key).isEmpty)
                func placeholders(_ value: String) -> Set<String> {
                    Set(value.split(separator: "{", omittingEmptySubsequences: false).dropFirst().compactMap { $0.split(separator: "}").first.map(String.init) })
                }
                #expect(placeholders(copy.text(key)) == placeholders(FuwaCopy(language: .english).text(key)))
            }
            #expect(copy.pinsCount(1).contains("1"))
            #expect(copy.pinsCount(3).contains("3"))
            let error = GlobalHotKey.RegistrationError.registerHotKey(-42, "⌥⌘P")
            let message = FuwaErrorMessage.localizedDescription(for: error, language: language)
            #expect(message.contains("-42") && message.contains("⌥⌘P"))
            #expect(!message.contains("{"))
        }
    }

    @Test func systemLanguageMatchesScriptsRegionsAndPreferredOrder() {
        for (identifier, expected) in [("en-US", FuwaLanguage.english), ("zh-CN", .simplifiedChinese),
            ("zh-Hans-TW", .simplifiedChinese), ("zh-Hant-CN", .traditionalChinese),
            ("zh_TW", .traditionalChinese), ("zh-HK", .traditionalChinese), ("zh-MO", .traditionalChinese),
            ("ja-JP", .japanese), ("ko-KR", .korean), ("fr-CA", .french), ("de-AT", .german)] {
            #expect(FuwaLanguage.automatic(preferredLanguages: [identifier]) == expected)
        }
        #expect(FuwaLanguage.automatic(preferredLanguages: ["es-ES", "de-DE"]) == .german)
        #expect(FuwaLanguage.automatic(preferredLanguages: ["unsupported"]) == .english)
        #expect(FuwaLanguage.automatic(preferredLanguages: []) == .english)
    }
}
