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
    private var model: AppModel?
    private var statusBarController: StatusBarController?
    private var mainWindowController: MainWindowController?
    private var softwareUpdateController: SoftwareUpdateController?
    private var isTerminating = false
    private var mainWindowPresented = false
    private var preparedPopoverIntent = PreparedIntentSlot<
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

        let model = AppModel(
            languagePreference: settingsStore.language,
            version: Self.version,
            shortcut: activeShortcut,
            shortcutIsActive: hotKey.currentShortcut != nil,
            launchAtLoginState: launchAtLoginController.state,
            screenRecordingPermission: screenRecordingPermissionState
        )
        self.model = model
        model.onLanguageChanged = { [weak self, weak model] preference in
            self?.settingsStore.language = preference
            guard let model else { return }
            NSApp.mainMenu = FuwaApplicationMenu.make(quitTitle: model.copy.text(.quit))
        }
        pinCoordinator.presentationModel = model
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
            onWillShowPopover: { [weak self] in
                self?.preparePopoverIntent()
            },
            onDidClosePopover: { [weak self] in
                self?.discardPopoverIntent()
            }
        )
        self.statusBarController = statusBarController
        mainWindowController = MainWindowController(model: model) { [weak self] presented in
            guard let self else { return }
            mainWindowPresented = presented
            updateDockPresence()
        }
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
            == keyAELaunchedAsLogInItem
        if !launchedAtLogin { mainWindowController?.present() }
        privacyLifecycle.start()

        if let shortcutLaunchError {
            model.report(shortcutLaunchError)
        }
    }

    private func updateDockPresence() {
        let policy: NSApplication.ActivationPolicy = mainWindowPresented ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
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
        discardPopoverIntent()
        hotKey?.stop()
        privacyLifecycle.stop()
        pinCoordinator.clearAllImmediately()
        statusBarController?.invalidate()
        statusBarController = nil
        // Include popovers, the main window, About, and any presentation no
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
                let intent = try takePreparedPopoverIntent()
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
                let outcome = try hotKey.update(to: shortcut)
                if outcome == .registered {
                    settingsStore.shortcut = shortcut
                }
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
        discardPopoverIntent()
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

    private func takePreparedPopoverIntent() throws -> TargetIntentSnapshot {
        guard let preparedIntent = preparedPopoverIntent.consume() else {
            throw FuwaApplicationError.pinIntentUnavailable
        }
        return try preparedIntent.get()
    }

    /// The status-item action runs before the popover becomes key. Preserve
    /// both success and failure so the later button action never rescans behind
    /// a transient Quick Look panel that may already have disappeared.
    private func preparePopoverIntent() {
        preparedPopoverIntent.replace(
            with: Result {
                try pinCoordinator.snapshotFrontmostIntent()
            }
        )
    }

    private func discardPopoverIntent() {
        preparedPopoverIntent.clear()
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
        model.updatePins(pinCoordinator.snapshots)
    }

    private func configurePrivacyLifecycle() {
        privacyLifecycle.onPrivacyBoundary = { [weak self] _ in
            self?.discardPopoverIntent()
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
