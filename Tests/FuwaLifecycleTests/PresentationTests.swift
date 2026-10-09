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
        let controller = StatusBarController(model: model, statusItem: nil)
        defer { controller.invalidate() }
        let empty = controller.makeMenu()
        #expect(!empty.items.contains(where: { $0.identifier?.rawValue == "clearAll" }))
        #expect(empty.items.contains(where: { $0.title == "Quit Fuwa" && $0.isEnabled }))
        let closed = pin(.frozen(.sourceClosed))
        model.updatePins([closed])
        let submenu = try #require(controller.makeMenu().items.first(where: { $0.submenu != nil })?.submenu)
        #expect(!submenu.items.contains(where: { $0.title == "Go to Original Window" }))
        #expect(submenu.items.contains(where: { $0.title == "Unpin" && $0.isEnabled }))
        #expect(!submenu.items.contains(where: { $0.title == "Resume" }))
        model.updatePins([pin(.live)])
        let liveMenu = try #require(controller.makeMenu().items.first(where: { $0.submenu != nil })?.submenu)
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
        let controller = StatusBarController(model: model, statusItem: nil)
        defer { controller.invalidate() }
        model.setLanguage(.english)
        #expect(controller.makeMenu().items.contains { $0.title == "Quit Fuwa" })
        model.setLanguage(.simplifiedChinese)
        #expect(model.copy.text(.settings) == "设置")
        #expect(!controller.makeMenu().items.contains { $0.title == "Quit Fuwa" })
        let relaunched = AppModel(languagePreference: AppSettingsStore(defaults: defaults).language)
        #expect(relaunched.copy.language == .simplifiedChinese)
        model.setLanguage(.system)
        #expect(model.copy.language == FuwaLanguage.automatic())
        for preference in FuwaLanguagePreference.allCases {
            model.setLanguage(preference)
            #expect(AppSettingsStore(defaults: defaults).language == preference)
            #expect(controller.makeMenu().items.contains { $0.title == model.copy.text(.quit) })
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

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FUWA_HEADLESS_TESTS"] != "1",
                  "Visible window verification requires a dedicated desktop"))
    func dockToggleChangesPolicyWithMainWindowOpenAndSurvivesReopening() {
        let app = NSApplication.shared
        let previousPolicy = app.activationPolicy()
        let model = AppModel(keepInDock: true)
        model.onKeepInDockChanged = { FuwaDockPresence.update(keepInDock: $0) }
        let controller = MainWindowController(model: model)
        let mirror = NSPanel(contentRect: NSRect(x: 80, y: 80, width: 160, height: 100),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        mirror.isReleasedWhenClosed = false
        mirror.hidesOnDeactivate = false
        mirror.level = .floating
        let closedWindow = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        closedWindow.isReleasedWhenClosed = false
        defer {
            controller.window.close()
            mirror.close()
            closedWindow.close()
            app.setActivationPolicy(previousPolicy)
        }
        func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2)) }
        FuwaDockPresence.update(keepInDock: model.keepInDock)
        controller.present()
        mirror.orderFrontRegardless()
        settle()
        let mainFrame = controller.window.frame
        let mirrorFrame = mirror.frame
        let mainCanHide = controller.window.canHide
        #expect(app.activationPolicy() == .regular)
        #expect(controller.window.isVisible)

        model.setKeepInDock(false)
        settle()
        #expect(app.activationPolicy() == .accessory)
        #expect(!app.isHidden)
        #expect(controller.window.isVisible)
        #expect(controller.window.frame == mainFrame)
        #expect(controller.window.canHide == mainCanHide)
        #expect(mirror.isVisible && mirror.frame == mirrorFrame && mirror.level == .floating)
        #expect(!mirror.hidesOnDeactivate)
        #expect(!closedWindow.isVisible)
        controller.window.close()
        // Simulate Launch Services promoting the app when it is reopened.
        app.setActivationPolicy(.regular)
        controller.present()
        settle()
        #expect(app.activationPolicy() == .accessory)
        #expect(controller.window.isVisible)

        model.setKeepInDock(true)
        settle()
        #expect(app.activationPolicy() == .regular)
        #expect(!app.isHidden)
        #expect(controller.window.isVisible)
        #expect(mirror.isVisible && mirror.frame == mirrorFrame)
        #expect(!closedWindow.isVisible)
        controller.window.close()
        #expect(app.activationPolicy() == .regular)
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

    @Test func menuActionsNavigateTheSharedWindowAndExposeEveryLanguage() throws {
        let app = NSApplication.shared
        for language in FuwaLanguage.allCases {
            let model = AppModel(copy: FuwaCopy(language: language))
            var opened = 0
            var actions = FuwaAppActions()
            actions.openMainWindow = { opened += 1 }
            model.configure(actions: actions)
            let controller = StatusBarController(model: model, statusItem: nil)
            defer { controller.invalidate() }
            let menu = controller.makeMenu()
            func select(_ key: FuwaString) throws {
                let index = try #require(menu.items.firstIndex { $0.identifier?.rawValue == key.rawValue })
                app.sendAction(try #require(menu.items[index].action), to: controller, from: menu.items[index])
            }
            try select(.chooseWindow)
            #expect(model.route == .pins && model.isChoosingWindow && opened == 1)
            try select(.settings)
            #expect(model.route == .settings && !model.isChoosingWindow && opened == 2)
            controller.menuWillOpen(menu)
            controller.menuDidClose(menu)
            #expect(model.route == .settings)
            try select(.openFuwa)
            #expect(model.route == .pins && opened == 3)
            #expect(menu.items.first?.title.hasPrefix(model.copy.text(.pinFrontWindow)) == true)
            #expect(menu.items.filter { $0.identifier?.rawValue == "settings" }.count == 1)
            #expect(menu.items.contains { $0.title == model.copy.text(.emptyTitle) && !$0.isEnabled })
            #expect(menu.items.contains { $0.title == model.copy.text(.about) })
            let longTitle = String(repeating: "窗口の長いタイトル", count: 12)
            model.updatePins([PinSnapshot(id: UUID(), sourceWindowID: 100, applicationName: "Preview",
                bundleIdentifier: nil, windowTitle: longTitle, state: .live, errorMessage: nil)])
            let row = try #require(controller.makeMenu().items.first { $0.submenu != nil })
            #expect(row.toolTip == "Preview — \(longTitle)")
            #expect(row.title.contains("…"))
            #expect((row.title as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width <= 320)
        }
    }

    @Test func menuClosingLetsTheSelectedActionClaimItsTargetAndDoesNotClearANewerMenu() async throws {
        _ = NSApplication.shared
        let model = AppModel()
        var prepared = false
        var claimed = false
        var discarded = 0
        var actions = FuwaAppActions()
        actions.beginPinFrontWindow = {
            #expect(prepared)
            prepared = false
            claimed = true
            return {}
        }
        model.configure(actions: actions)
        let controller = StatusBarController(model: model, statusItem: nil,
            onWillShowMenu: { prepared = true },
            onDidCloseMenu: { prepared = false; discarded += 1 })
        defer { controller.invalidate() }
        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        controller.menuDidClose(menu)
        let pinItem = try #require(menu.items.first { $0.identifier?.rawValue == "pinFrontWindow" })
        NSApp.sendAction(try #require(pinItem.action), to: controller, from: pinItem)
        #expect(claimed)
        try await Task.sleep(for: .milliseconds(30))
        #expect(!prepared && discarded == 1)

        controller.menuWillOpen(menu)
        controller.menuDidClose(menu)
        controller.menuWillOpen(menu)
        try await Task.sleep(for: .milliseconds(30))
        #expect(prepared && discarded == 1)
        controller.menuDidClose(menu)
        try await Task.sleep(for: .milliseconds(30))
        #expect(!prepared && discarded == 2)
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
