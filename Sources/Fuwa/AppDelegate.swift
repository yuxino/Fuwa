import AppKit
import CoreGraphics
import FuwaCore

enum FuwaApplicationError: LocalizedError {
    case unavailable
    case pinIntentUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Fuwa is not available right now."
        case .pinIntentUnavailable:
            "Reopen Fuwa while the window you want to pin is still visible."
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let pinCoordinator = PinCoordinator()
    private let privacyLifecycle = PrivacyLifecycle()
    private let settingsStore = AppSettingsStore()
    private let launchAtLoginController = LaunchAtLoginController()

    private var hotKey: GlobalHotKey?
    private var visibilityHotKey: GlobalHotKey?
    private var model: AppModel?
    private var statusBarController: StatusBarController?
    private var mainWindowController: MainWindowController?
    private var softwareUpdateController: SoftwareUpdateController?
    private var isTerminating = false
    private var preparedMenuIntent = PreparedIntentSlot<
        Result<TargetIntentSnapshot, Error>
    >()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let requestedShortcut = settingsStore.shortcut
        let hotKey = GlobalHotKey { [weak self] in
            self?.handleGlobalShortcut()
        }
        self.hotKey = hotKey

        var activeShortcut = requestedShortcut
        var shortcutLaunchError: Error?
        do {
            try hotKey.start(shortcut: requestedShortcut)
        } catch {
            shortcutLaunchError = error
            if requestedShortcut != .defaultPin {
                do {
                    try hotKey.start(shortcut: .defaultPin)
                    activeShortcut = .defaultPin
                    settingsStore.shortcut = .defaultPin
                } catch {
                    shortcutLaunchError = error
                }
            }
        }

        let visibilityHotKey = GlobalHotKey(identifier: 2) { [weak self] in
            guard let self, !isTerminating else { return }
            self.model?.togglePinsVisibility()
        }
        self.visibilityHotKey = visibilityHotKey
        var activeVisibilityShortcut = settingsStore.visibilityShortcut
        var visibilityShortcutLaunchError: Error?
        do {
            try visibilityHotKey.start(shortcut: activeVisibilityShortcut)
        } catch {
            visibilityShortcutLaunchError = error
            if activeVisibilityShortcut != .defaultVisibility {
                do {
                    try visibilityHotKey.start(shortcut: .defaultVisibility)
                    activeVisibilityShortcut = .defaultVisibility
                    settingsStore.visibilityShortcut = .defaultVisibility
                } catch {
                    visibilityShortcutLaunchError = error
                }
            }
        }

        let model = AppModel(
            languagePreference: settingsStore.language,
            keepInDock: settingsStore.keepInDock,
            version: Self.version,
            shortcut: activeShortcut,
            shortcutIsActive: hotKey.currentShortcut != nil,
            visibilityShortcut: activeVisibilityShortcut,
            visibilityShortcutIsActive: visibilityHotKey.currentShortcut != nil,
            launchAtLoginState: launchAtLoginController.state,
            screenRecordingPermission: screenRecordingPermissionState
        )
        self.model = model
        model.onLanguageChanged = { [weak self, weak model] preference in
            self?.settingsStore.language = preference
            self?.pinCoordinator.refreshPresentationCopy()
            guard let model else { return }
            NSApp.mainMenu = FuwaApplicationMenu.make(quitTitle: model.copy.text(.quit))
        }
        model.onKeepInDockChanged = { [weak self] enabled in
            guard let self else { return }
            settingsStore.keepInDock = enabled
            updateDockPresence()
        }
        pinCoordinator.presentationModel = model
        pinCoordinator.frameRateForApplication = { [weak self] bundleIdentifier in
            self?.settingsStore.frameRate(for: bundleIdentifier) ?? .thirty
        }
        pinCoordinator.onOptionsChanged = { [weak self] pin in
            self?.settingsStore.setFrameRate(pin.options.frameRate, for: pin.bundleIdentifier)
        }
        NSApp.mainMenu = FuwaApplicationMenu.make(quitTitle: model.copy.text(.quit))
        do {
            softwareUpdateController = try SoftwareUpdateController(model: model)
        } catch {
            model.setSoftwareUpdateState(
                SoftwareUpdateState(
                    phase: .failed,
                    currentVersion: Self.version,
                    errorMessage: model.copy.text(.updateFailedMessage)
                )
            )
        }
        model.configure(actions: makeActions())
        configureCoordinatorCallbacks(model: model)
        configurePrivacyLifecycle()
        refreshPermissions()

        let statusBarController = StatusBarController(
            model: model,
            onWillShowMenu: { [weak self] in
                self?.prepareMenuIntent()
            },
            onDidCloseMenu: { [weak self] in
                self?.discardMenuIntent()
            }
        )
        self.statusBarController = statusBarController
        mainWindowController = MainWindowController(model: model)
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
            == keyAELaunchedAsLogInItem
        if !launchedAtLogin { mainWindowController?.present() }
        privacyLifecycle.start()

        if let shortcutLaunchError {
            model.report(shortcutLaunchError)
        }
        if let visibilityShortcutLaunchError { model.report(visibilityShortcutLaunchError) }
    }

    private func updateDockPresence() {
        FuwaDockPresence.update(keepInDock: settingsStore.keepInDock)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Launch Services may promote a reopened regular bundle into the Dock.
        updateDockPresence()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        prepareForTermination()
        return .terminateNow
    }

    /// The Dock icon is Fuwa's second entry point: reopening the app brings
    /// the mirror list and settings forward in a regular window.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        mainWindowController?.present()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        prepareForTermination()
    }

    private func prepareForTermination() {
        guard !isTerminating else { return }
        isTerminating = true
        discardMenuIntent()
        hotKey?.stop()
        visibilityHotKey?.stop()
        privacyLifecycle.stop()
        pinCoordinator.clearAllImmediately()
        statusBarController?.invalidate()
        statusBarController = nil
        // Include the main window, About, and any presentation no
        // longer owned by a pin session. Hide synchronously before AppKit tears
        // down the app; never wait for ScreenCaptureKit's asynchronous stream
        // shutdown. Iterate a copy: closing a window mutates `NSApp.windows`.
        for window in Array(NSApp.windows) {
            window.orderOut(nil)
            window.close()
        }
    }

    private func makeActions() -> FuwaAppActions {
        FuwaAppActions(
            beginPinFrontWindow: { [weak self] in
                guard let self else { throw FuwaApplicationError.unavailable }
                let intent = try takePreparedMenuIntent()
                return { [weak self] in
                    guard let self else { throw FuwaApplicationError.unavailable }
                    try await toggle(intent)
                }
            },
            showControls: { [weak self] id in self?.pinCoordinator.focusControls(id) },
            pinWindow: { [weak self] choice in
                guard let self else { throw FuwaApplicationError.unavailable }
                let refreshed = try TargetResolver().snapshotExactWindow(matching: choice.intent.descriptor)
                // A picker is an add action, never a toggle on a stale row.
                guard !pinCoordinator.snapshots.contains(where: { $0.sourceWindowID == choice.id }) else { return }
                try await toggle(refreshed)
            },
            freeze: { [weak self] id in
                guard let self else { throw FuwaApplicationError.unavailable }
                try await pinCoordinator.freeze(id)
            },
            resume: { [weak self] id in
                guard let self else { throw FuwaApplicationError.unavailable }
                try await pinCoordinator.resume(id)
            },
            updateCaptureQuality: { [weak self] id, quality in
                self?.pinCoordinator.setCaptureQuality(quality, for: id)
            },
            updatePinOptions: { [weak self] id, options in
                self?.pinCoordinator.setOptions(options, for: id)
            },
            beginCropSelection: { [weak self] id in
                self?.pinCoordinator.beginCropSelection(id)
            },
            togglePinsVisibility: { [weak self] in
                guard let self else { throw FuwaApplicationError.unavailable }
                try await pinCoordinator.togglePinsVisibility()
            },
            unpin: { [weak self] id in
                guard let self else { throw FuwaApplicationError.unavailable }
                await pinCoordinator.unpin(id)
            },
            clearAll: { [weak self] in
                guard let self else { throw FuwaApplicationError.unavailable }
                await pinCoordinator.clearAll()
            },
            updateShortcut: { [weak self] shortcut in
                guard let self else { throw FuwaApplicationError.unavailable }
                guard let hotKey else { throw FuwaApplicationError.unavailable }
                if let other = visibilityHotKey?.currentShortcut,
                   shortcut.hasSameKeyCombination(as: other) { return .conflict }
                let outcome = try hotKey.update(to: shortcut)
                if outcome == .registered {
                    settingsStore.shortcut = shortcut
                }
                return outcome
            },
            updateVisibilityShortcut: { [weak self] shortcut in
                guard let self, let visibilityHotKey else { throw FuwaApplicationError.unavailable }
                if let other = hotKey?.currentShortcut,
                   shortcut.hasSameKeyCombination(as: other) { return .conflict }
                let outcome = try visibilityHotKey.update(to: shortcut)
                if outcome == .registered { settingsStore.visibilityShortcut = shortcut }
                return outcome
            },
            updateLaunchAtLogin: { [weak self] enabled in
                guard let self else { throw FuwaApplicationError.unavailable }
                return try launchAtLoginController.setEnabled(enabled)
            },
            openScreenRecordingSettings: { [weak self] in
                self?.openPrivacySettings(anchor: "Privacy_ScreenCapture")
            },
            openLoginItemsSettings: { [weak self] in
                self?.launchAtLoginController.openSettings()
            },
            checkForUpdates: { [weak self] in
                self?.softwareUpdateController?.checkForUpdates()
            },
            downloadUpdate: { [weak self] in
                self?.softwareUpdateController?.downloadUpdate()
            },
            cancelUpdate: { [weak self] in
                self?.softwareUpdateController?.cancelUpdate()
            },
            installAndRelaunchUpdate: { [weak self] in
                self?.softwareUpdateController?.installAndRelaunch()
            },
            openLatestRelease: { [weak self] in
                self?.openLatestRelease()
            },
            openMainWindow: { [weak self] in
                self?.mainWindowController?.present()
            },
            showAbout: { [weak self] in
                self?.showAboutPanel()
            },
            quit: {
                NSApp.terminate(nil)
            }
        )
    }

    /// The hotkey path snapshots visual intent synchronously before creating a
    /// Task. This is what keeps Finder Quick Look and other transient windows
    /// from disappearing between user input and target selection.
    private func handleGlobalShortcut() {
        guard !isTerminating else { return }
        discardMenuIntent()
        let intent: TargetIntentSnapshot
        do {
            intent = try pinCoordinator.snapshotFrontmostIntent()
        } catch {
            model?.report(error)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await toggle(intent)
            } catch PinCoordinatorError.operationCancelled {
                return
            } catch {
                model?.report(error)
            }
        }
    }

    private func takePreparedMenuIntent() throws -> TargetIntentSnapshot {
        guard let preparedIntent = preparedMenuIntent.consume() else {
            throw FuwaApplicationError.pinIntentUnavailable
        }
        return try preparedIntent.get()
    }

    /// The menu opens without activating a management window. Preserve
    /// both success and failure so the later button action never rescans behind
    /// a transient Quick Look panel that may already have disappeared.
    private func prepareMenuIntent() {
        preparedMenuIntent.replace(
            with: Result {
                try pinCoordinator.snapshotFrontmostIntent()
            }
        )
    }

    private func discardMenuIntent() {
        preparedMenuIntent.clear()
    }

    private func toggle(_ intent: TargetIntentSnapshot) async throws {
        // A shortcut task may have been queued before shutdown began.
        guard !isTerminating else { throw PinCoordinatorError.operationCancelled }
        do {
            try await pinCoordinator.toggle(intent)
        } catch TargetResolutionError.screenRecordingPermissionDenied {
            let requestAction = SystemPermissionRequestPolicy.action(
                hasRequestedBefore: settingsStore.didRequestScreenRecording
            )
            var shouldRetryOriginalIntent = false
            if requestAction == .requestSystemPrompt {
                settingsStore.didRequestScreenRecording = true
                let requestReturnedGranted = CGRequestScreenCaptureAccess()
                shouldRetryOriginalIntent = SystemPermissionRequestPolicy.shouldRetryAfterRequest(
                    requestReturnedGranted: requestReturnedGranted,
                    preflightGranted: CGPreflightScreenCaptureAccess()
                )
            }
            refreshPermissions()
            if shouldRetryOriginalIntent {
                try await pinCoordinator.toggle(intent)
                return
            }
            throw TargetResolutionError.screenRecordingPermissionDenied
        }
    }

    private func configureCoordinatorCallbacks(model: AppModel) {
        pinCoordinator.onPinsChanged = { [weak model] snapshots in
            model?.updatePins(snapshots)
        }
        pinCoordinator.onFailure = { [weak model] error in
            model?.report(error)
        }
        pinCoordinator.onVisibilityChanged = { [weak model] hidden in
            model?.updatePinsVisibility(hidden)
        }
        model.updatePins(pinCoordinator.snapshots)
        model.updatePinsVisibility(pinCoordinator.arePinsHidden)
    }

    private func configurePrivacyLifecycle() {
        privacyLifecycle.onPrivacyBoundary = { [weak self] _ in
            self?.discardMenuIntent()
            self?.pinCoordinator.clearAllImmediately()
        }
        privacyLifecycle.onEnvironmentRefresh = { [weak self] in
            self?.refreshPermissions()
        }
    }

    private func refreshPermissions() {
        let screenRecordingGranted = CGPreflightScreenCaptureAccess()
        if !screenRecordingGranted, pinCoordinator.pinCount > 0 {
            pinCoordinator.clearAllImmediately()
        }

        model?.updatePermissions(
            screenRecording: screenRecordingPermissionState
        )
        model?.updateLaunchAtLoginState(launchAtLoginController.state)
    }

    private var screenRecordingPermissionState: FuwaPermissionState {
        if CGPreflightScreenCaptureAccess() { return .granted }
        return settingsStore.didRequestScreenRecording ? .denied : .unknown
    }

    private func openPrivacySettings(anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openLatestRelease() {
        guard let url = URL(string: "https://github.com/yuxino/fuwa/releases/latest") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func showAboutPanel() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Fuwa",
            .applicationVersion: Self.version,
            .credits: NSAttributedString(
                string: "A quiet, local window pin for macOS.\nMIT License · github.com/yuxino/fuwa"
            )
        ])
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.1.9"
    }
}
