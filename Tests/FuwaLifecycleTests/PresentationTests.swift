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

    @Test func closedSourceCannotResumeOrReveal() {
        let closed = pin(.frozen(.sourceClosed))
        #expect(!closed.canResume)
        #expect(!closed.canUseSource)
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
        #expect(liveMenu.items.contains(where: { $0.title == "Go to Original Window" && $0.isEnabled }))
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

    @Test func dockPreferencePersistsAndKeepsTheDefaultForExistingUsers() throws {
        let suite = "FuwaDockTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSettingsStore(defaults: defaults)
        #expect(store.keepInDock)
        let model = AppModel(keepInDock: store.keepInDock)
        var changes = [Bool]()
        model.onKeepInDockChanged = { store.keepInDock = $0; changes.append($0) }
        model.setKeepInDock(false)
        model.setKeepInDock(false)
        #expect(changes == [false])
        let relaunched = AppModel(keepInDock: AppSettingsStore(defaults: defaults).keepInDock)
        #expect(!relaunched.keepInDock)
        model.setKeepInDock(true)
        #expect(AppSettingsStore(defaults: defaults).keepInDock)
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

    @Test func captureQualityPersistsAndDefaultsToFourMillionPixels() throws {
        let suite = "FuwaCaptureQualityTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSettingsStore(defaults: defaults)
        #expect(store.captureQuality == .fourMegapixels)
        let model = AppModel(captureQuality: store.captureQuality)
        var changes = [CaptureQuality]()
        model.onCaptureQualityChanged = { store.captureQuality = $0; changes.append($0) }
        for quality in CaptureQuality.allCases {
            model.setCaptureQuality(quality)
            model.setCaptureQuality(quality)
            #expect(AppSettingsStore(defaults: defaults).captureQuality == quality)
        }
        #expect(changes == [.nineMegapixels, .sixteenMegapixels, .native])
        let relaunched = AppModel(captureQuality: AppSettingsStore(defaults: defaults).captureQuality)
        #expect(relaunched.captureQuality == .native)
        defaults.set("invalid", forKey: "captureQuality")
        #expect(store.captureQuality == .fourMegapixels)
    }

    @Test func optionalAccessibilityDoesNotWarnAboutPinningPermissions() {
        let model = AppModel(screenRecordingPermission: .granted, accessibilityPermission: .denied)
        #expect(!model.hasPermissionWarning)
        model.updatePermissions(screenRecording: .denied, accessibility: .granted)
        #expect(model.hasPermissionWarning)
        model.updatePermissions(screenRecording: .unknown, accessibility: .unknown)
        #expect(!model.hasPermissionWarning)
    }

    @Test func popoverFitsSmallListsAndKeepsLargeListsBounded() {
        func size(_ count: Int, route: FuwaPopoverRoute = .pins,
                  notice: Bool = false, type: DynamicTypeSize = .large, actions: Int = 0) -> NSSize {
            FuwaPopoverLayout.preferredContentSize(route: route, pinCount: count, actionRowCount: actions,
                hasNotice: notice, hasPermissionWarning: false, dynamicTypeSize: type)
        }
        #expect(size(2, actions: 2).height > size(2).height)
        #expect(size(8, actions: 8) == size(12, actions: 12))
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
