import AppKit
import Combine
import Foundation
import FuwaCore

enum FuwaPopoverRoute: Equatable {
    case pins
    case settings
}

enum FuwaPermissionState: Equatable {
    case unknown
    case granted
    case denied
}

enum FuwaInteractionState: Equatable {
    case viewOnly
    case engaged
    case unavailable(String?)
}

struct FuwaNotice: Identifiable, Equatable {
    enum Kind: Equatable {
        case information
        case error
    }

    let id = UUID()
    let kind: Kind
    let message: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.message == rhs.message
    }
}

struct FuwaAppActions {
    typealias PinFrontWindowOperation = @MainActor () async throws -> Void

    /// Synchronously claims the target prepared for this popover, then returns
    /// the asynchronous capture work. Keeping the claim outside `Task` prevents
    /// a close event from discarding an operation the user already started.
    var beginPinFrontWindow: @MainActor () throws -> PinFrontWindowOperation = { {} }
    var showControls: @MainActor (UUID) -> Void = { _ in }
    var pinWindow: @MainActor (FuwaWindowChoice) async throws -> Void = { _ in }
    var freeze: @MainActor (UUID) async throws -> Void = { _ in }
    var resume: @MainActor (UUID) async throws -> Void = { _ in }
    var interact: @MainActor (UUID) async throws -> Void = { _ in }
    var revealSource: @MainActor (UUID) async throws -> Void = { _ in }
    var unpin: @MainActor (UUID) async throws -> Void = { _ in }
    var clearAll: @MainActor () async throws -> Void = {}
    var updateShortcut: @MainActor (KeyboardShortcut) async throws
        -> KeyboardShortcutRegistrationOutcome = { _ in .failed }
    var updateLaunchAtLogin: @MainActor (Bool) async throws
        -> FuwaLaunchAtLoginState = { _ in .disabled }
    var openScreenRecordingSettings: @MainActor () -> Void = {}
    var openAccessibilitySettings: @MainActor () -> Void = {}
    var openLoginItemsSettings: @MainActor () -> Void = {}
    var checkForUpdates: @MainActor () -> Void = {}
    var downloadUpdate: @MainActor () -> Void = {}
    var cancelUpdate: @MainActor () -> Void = {}
    var installAndRelaunchUpdate: @MainActor () -> Void = {}
    var openLatestRelease: @MainActor () -> Void = {}
    var openMainWindow: @MainActor () -> Void = {}
    var showAbout: @MainActor () -> Void = {}
    var quit: @MainActor () -> Void = {}
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var copy: FuwaCopy
    @Published private(set) var languagePreference: FuwaLanguagePreference
    @Published private(set) var keepInDock: Bool
    @Published private(set) var captureQuality: CaptureQuality
    let version: String

    @Published private(set) var pins: [PinSnapshot] = [] {
        didSet { onStatusPresentationChanged?() }
    }
    @Published private(set) var route: FuwaPopoverRoute = .pins
    @Published private(set) var notice: FuwaNotice?
    @Published private(set) var shortcut: KeyboardShortcut {
        didSet { onStatusPresentationChanged?() }
    }
    @Published private(set) var shortcutIsActive: Bool {
        didSet { onStatusPresentationChanged?() }
    }
    @Published private(set) var launchAtLoginState: FuwaLaunchAtLoginState
    @Published private(set) var screenRecordingPermission: FuwaPermissionState
    @Published private(set) var accessibilityPermission: FuwaPermissionState
    @Published private(set) var interactionStates: [UUID: FuwaInteractionState] = [:]
    @Published private(set) var engagedPinID: UUID?
    @Published private(set) var busyPinIDs = Set<UUID>()
    @Published private(set) var isPinningFrontWindow = false
    @Published private(set) var isClearingAll = false
    @Published private(set) var isUpdatingShortcut = false
    @Published private(set) var isUpdatingLaunchAtLogin = false
    @Published private(set) var softwareUpdate: SoftwareUpdateState

    var onKeepInDockChanged: ((Bool) -> Void)?
    var onCaptureQualityChanged: ((CaptureQuality) -> Void)?
    var onLanguageChanged: ((FuwaLanguagePreference) -> Void)?
    var onStatusPresentationChanged: (() -> Void)?
    var onRequestDismissPopover: (() -> Void)?

    private var actions: FuwaAppActions

    init(
        copy: FuwaCopy? = nil,
        languagePreference: FuwaLanguagePreference = .system,
        keepInDock: Bool = true,
        captureQuality: CaptureQuality = .default,
        version: String = "0.1.9",
        shortcut: KeyboardShortcut = .defaultPin,
        shortcutIsActive: Bool = true,
        launchAtLoginState: FuwaLaunchAtLoginState = .disabled,
        screenRecordingPermission: FuwaPermissionState = .unknown,
        accessibilityPermission: FuwaPermissionState = .unknown,
        actions: FuwaAppActions = FuwaAppActions()
    ) {
        self.copy = copy ?? FuwaCopy(language: languagePreference.resolved)
        self.languagePreference = languagePreference
        self.keepInDock = keepInDock
        self.captureQuality = captureQuality
        self.version = version
        self.shortcut = shortcut
        self.shortcutIsActive = shortcutIsActive
        self.launchAtLoginState = launchAtLoginState
        self.screenRecordingPermission = screenRecordingPermission
        self.accessibilityPermission = accessibilityPermission
        softwareUpdate = .idle(currentVersion: version)
        self.actions = actions
    }

    func setLanguage(_ preference: FuwaLanguagePreference) {
        languagePreference = preference
        copy = FuwaCopy(language: preference.resolved)
        onLanguageChanged?(preference)
        onStatusPresentationChanged?()
    }

    func setKeepInDock(_ enabled: Bool) {
        guard enabled != keepInDock else { return }
        keepInDock = enabled
        onKeepInDockChanged?(enabled)
    }

    func setCaptureQuality(_ quality: CaptureQuality) {
        guard quality != captureQuality else { return }
        captureQuality = quality
        onCaptureQualityChanged?(quality)
    }

    var statusItemAccessibilityLabel: String {
        pins.isEmpty ? copy.text(.statusNoPins) : copy.text(.statusPinned)
    }

    var hasPermissionWarning: Bool {
        screenRecordingPermission == .denied
    }

    var launchAtLogin: Bool {
        launchAtLoginState == .enabled || launchAtLoginState == .requiresApproval
    }

    func configure(actions: FuwaAppActions) {
        self.actions = actions
    }

    func updatePins(_ snapshots: [PinSnapshot]) {
        pins = snapshots

        let activeIDs = Set(snapshots.map(\.id))
        interactionStates = interactionStates.filter { activeIDs.contains($0.key) }
        busyPinIDs.formIntersection(activeIDs)

        if let engagedPinID {
            let engagedPin = snapshots.first(where: { $0.id == engagedPinID })
            if engagedPin == nil || !Self.canInteract(with: engagedPin?.state) {
                setEngagedPin(nil)
            }
        }
    }

    func updatePermissions(
        screenRecording: FuwaPermissionState,
        accessibility: FuwaPermissionState
    ) {
        screenRecordingPermission = screenRecording
        accessibilityPermission = accessibility
    }

    func setEngagedPin(_ id: UUID?) {
        if let previous = engagedPinID,
           interactionStates[previous] == .engaged {
            interactionStates[previous] = .viewOnly
        }
        engagedPinID = id
        if let id {
            interactionStates[id] = .engaged
        }
    }

    func disengageInteraction() {
        setEngagedPin(nil)
    }

    func updateLaunchAtLoginState(_ state: FuwaLaunchAtLoginState) {
        launchAtLoginState = state
    }

    func showPins() {
        route = .pins
    }

    func showSettings() {
        route = .settings
    }

    func dismissNotice() {
        notice = nil
    }

    func report(_ error: Error) {
        presentError(error)
    }

    func dismissPopover() {
        onRequestDismissPopover?()
    }

    func openScreenRecordingSettings() {
        actions.openScreenRecordingSettings()
    }

    func openAccessibilitySettings() {
        actions.openAccessibilitySettings()
    }

    func openLoginItemsSettings() {
        actions.openLoginItemsSettings()
    }

    func openLatestRelease() {
        actions.openLatestRelease()
    }

    func setSoftwareUpdateState(_ state: SoftwareUpdateState) {
        let phaseChanged = softwareUpdate.phase != state.phase
        softwareUpdate = state
        if phaseChanged {
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: softwareUpdateAnnouncement,
                    .priority: NSAccessibilityPriorityLevel.medium.rawValue
                ]
            )
        }
    }

    func checkForUpdates() {
        guard !softwareUpdate.isBusy, softwareUpdate.phase != .ready else { return }
        actions.checkForUpdates()
    }

    func downloadUpdate() {
        guard softwareUpdate.phase == .available else { return }
        actions.downloadUpdate()
    }

    func cancelUpdate() {
        guard softwareUpdate.canCancel || softwareUpdate.phase == .available else { return }
        actions.cancelUpdate()
    }

    func installAndRelaunchUpdate() {
        guard softwareUpdate.phase == .ready else { return }
        actions.installAndRelaunchUpdate()
    }

    private var softwareUpdateAnnouncement: String {
        switch softwareUpdate.phase {
        case .idle:
            return "\(copy.text(.version)) \(version)"
        case .checking:
            return copy.text(.checkingForUpdates)
        case .current:
            return copy.text(.upToDate)
        case .available:
            return [copy.text(.updateAvailable), softwareUpdate.availableVersion]
                .compactMap { $0 }
                .joined(separator: " ")
        case .downloading:
            return copy.text(.downloadingUpdate)
        case .extracting:
            return copy.text(.extractingUpdate)
        case .ready:
            return copy.text(.readyToInstall)
        case .installing:
            return copy.text(.installingUpdate)
        case .cancelled:
            return copy.text(.updateCancelled)
        case .failed:
            return softwareUpdate.errorMessage ?? copy.text(.updateFailedMessage)
        }
    }

    func openMainWindow() {
        actions.openMainWindow()
    }

    func showAbout() {
        actions.showAbout()
    }

    func quit() {
        actions.quit()
    }

    func pinFrontWindow() {
        guard !isPinningFrontWindow, !isClearingAll else { return }
        isPinningFrontWindow = true
        notice = nil

        let operation: FuwaAppActions.PinFrontWindowOperation
        do {
            operation = try actions.beginPinFrontWindow()
        } catch {
            isPinningFrontWindow = false
            presentError(error)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isPinningFrontWindow = false }
            do {
                try await operation()
            } catch {
                presentError(error)
            }
        }
    }

    func showControls(_ id: UUID) { actions.showControls(id) }

    func pinWindow(_ choice: FuwaWindowChoice) {
        guard !isPinningFrontWindow, !isClearingAll,
              !pins.contains(where: { $0.sourceWindowID == choice.id }) else { return }
        isPinningFrontWindow = true
        notice = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isPinningFrontWindow = false }
            do { try await actions.pinWindow(choice) }
            catch { presentError(error) }
        }
    }

    func freeze(_ id: UUID) {
        performPinAction(id) { actions in
            try await actions.freeze(id)
        }
    }

    func resume(_ id: UUID) {
        performPinAction(id) { actions in
            try await actions.resume(id)
        }
    }

    func interact(_ id: UUID) {
        performPinAction(id) { [weak self] actions in
            do {
                try await actions.interact(id)
                self?.setEngagedPin(id)
            } catch {
                if let self {
                    interactionStates[id] = .unavailable(
                        FuwaErrorMessage.localizedDescription(
                            for: error,
                            language: copy.language
                        )
                    )
                }
                throw error
            }
        }
    }

    func revealSource(_ id: UUID) {
        performPinAction(id) { [weak self] actions in
            try await actions.revealSource(id)
            self?.interactionStates[id] = .viewOnly
            self?.setEngagedPin(nil)
        }
    }

    func unpin(_ id: UUID) {
        performPinAction(id) { [weak self] actions in
            try await actions.unpin(id)
            if self?.engagedPinID == id {
                self?.setEngagedPin(nil)
            }
        }
    }

    func clearAll() {
        guard !isClearingAll, !pins.isEmpty else { return }
        isClearingAll = true
        notice = nil
        setEngagedPin(nil)

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isClearingAll = false }
            do {
                try await actions.clearAll()
            } catch {
                presentError(error)
            }
        }
    }

    func proposeShortcut(_ proposed: KeyboardShortcut) {
        guard !isUpdatingShortcut else { return }

        let update: KeyboardShortcutUpdate
        do {
            update = try KeyboardShortcutUpdate(previous: shortcut, proposed: proposed)
        } catch {
            notice = FuwaNotice(kind: .error, message: copy.text(.invalidShortcut))
            return
        }

        isUpdatingShortcut = true
        notice = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isUpdatingShortcut = false }

            do {
                let outcome = try await actions.updateShortcut(proposed)
                shortcut = update.resolvedValue(after: outcome)
                switch outcome {
                case .registered:
                    shortcutIsActive = true
                case .conflict:
                    shortcutIsActive = true
                    notice = FuwaNotice(kind: .error, message: copy.text(.shortcutConflict))
                case .failed:
                    shortcutIsActive = true
                    notice = FuwaNotice(kind: .error, message: copy.text(.shortcutFailed))
                case .inactive:
                    shortcutIsActive = false
                    notice = FuwaNotice(kind: .error, message: copy.text(.shortcutInactive))
                }
            } catch {
                shortcut = update.rolledBackValue
                presentError(error)
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard !isUpdatingLaunchAtLogin, enabled != launchAtLogin else { return }
        let previous = launchAtLoginState
        isUpdatingLaunchAtLogin = true
        notice = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isUpdatingLaunchAtLogin = false }
            do {
                let actualState = try await actions.updateLaunchAtLogin(enabled)
                launchAtLoginState = actualState
                if actualState == .requiresApproval {
                    notice = FuwaNotice(
                        kind: .information,
                        message: copy.text(.launchAtLoginApproval)
                    )
                }
            } catch {
                launchAtLoginState = previous
                presentError(error)
            }
        }
    }

    private func performPinAction(
        _ id: UUID,
        operation: @escaping @MainActor (FuwaAppActions) async throws -> Void
    ) {
        guard !isClearingAll, pins.contains(where: { $0.id == id }), !busyPinIDs.contains(id) else { return }
        busyPinIDs.insert(id)
        notice = nil
        let currentActions = actions

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { busyPinIDs.remove(id) }
            do {
                try await operation(currentActions)
            } catch {
                presentError(error)
            }
        }
    }

    private func presentError(_ error: Error) {
        notice = FuwaNotice(
            kind: .error,
            message: FuwaErrorMessage.localizedDescription(
                for: error,
                language: copy.language
            )
        )
    }

    private static func canInteract(with state: PinState?) -> Bool {
        switch state {
        case .live, .frozen(.manual), .frozen(.captureInterrupted):
            true
        case .none, .resolving, .starting, .frozen(.sourceClosed), .failed, .stopping, .stopped:
            false
        }
    }
}
