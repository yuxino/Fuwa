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
        #expect(empty.items.first(where: { $0.title == "Clear All" })?.isEnabled == false)
        #expect(empty.items.contains(where: { $0.title == "Quit Fuwa" && $0.isEnabled }))
        let closed = pin(.frozen(.sourceClosed))
        model.updatePins([closed])
        let submenu = try #require(controller.makeQuickMenu().items.first(where: { $0.submenu != nil })?.submenu)
        #expect(submenu.items.first(where: { $0.title == "Reveal Source" })?.isEnabled == false)
        #expect(submenu.items.contains(where: { $0.title == "Unpin" && $0.isEnabled }))
        #expect(!submenu.items.contains(where: { $0.title == "Resume" }))
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

    @Test func allCopyKeysHaveBothLanguages() {
        for language in [FuwaLanguage.english, .simplifiedChinese] {
            let copy = FuwaCopy(language: language)
            for key in FuwaString.allCases { #expect(copy.text(key) != key.rawValue) }
        }
    }
}
