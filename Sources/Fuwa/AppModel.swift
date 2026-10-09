import AppKit
import Combine
import Foundation
import FuwaCore

enum FuwaMainRoute: Equatable {
    case pins
    case settings
}

enum FuwaPermissionState: Equatable {
    case unknown
    case granted
    case denied
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

    /// Synchronously claims the target prepared for the menu, then returns
    /// the asynchronous capture work. Keeping the claim outside `Task` prevents
    /// a close event from discarding an operation the user already started.
    var beginPinFrontWindow: @MainActor () throws -> PinFrontWindowOperation = { {} }
    var showControls: @MainActor (UUID) -> Void = { _ in }
    var pinWindow: @MainActor (FuwaWindowChoice) async throws -> Void = { _ in }
    var freeze: @MainActor (UUID) async throws -> Void = { _ in }
    var resume: @MainActor (UUID) async throws -> Void = { _ in }
    var updateCaptureQuality: @MainActor (UUID, CaptureQuality) -> Void = { _, _ in }
    var updatePinOptions: @MainActor (UUID, PinOptions) -> Void = { _, _ in }
    var beginCropSelection: @MainActor (UUID) -> Void = { _ in }
    var togglePinsVisibility: @MainActor () async throws -> Void = {}
    var unpin: @MainActor (UUID) async throws -> Void = { _ in }
    var clearAll: @MainActor () async throws -> Void = {}
    var updateShortcut: @MainActor (KeyboardShortcut) async throws
        -> KeyboardShortcutRegistrationOutcome = { _ in .failed }
    var updateVisibilityShortcut: @MainActor (KeyboardShortcut) async throws
        -> KeyboardShortcutRegistrationOutcome = { _ in .failed }
    var updateLaunchAtLogin: @MainActor (Bool) async throws
        -> FuwaLaunchAtLoginState = { _ in .disabled }
    var openScreenRecordingSettings: @MainActor () -> Void = {}
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
    let version: String

    @Published private(set) var pins: [PinSnapshot] = [] {
        didSet { onStatusPresentationChanged?() }
    }
    @Published private(set) var route: FuwaMainRoute = .pins
    @Published private(set) var isChoosingWindow = false
    @Published private(set) var notice: FuwaNotice? {
        didSet { onStatusPresentationChanged?() }
    }
    @Published private(set) var shortcut: KeyboardShortcut {
        didSet { onStatusPresentationChanged?() }
    }
    @Published private(set) var shortcutIsActive: Bool {
        didSet { onStatusPresentationChanged?() }
    }
    @Published private(set) var visibilityShortcut: KeyboardShortcut {
        didSet { onStatusPresentationChanged?() }
    }
    @Published private(set) var visibilityShortcutIsActive: Bool {
        didSet { onStatusPresentationChanged?() }
    }
    @Published private(set) var arePinsHidden = false {
        didSet { onStatusPresentationChanged?() }
    }
    @Published private(set) var isTogglingVisibility = false
    @Published private(set) var isUpdatingVisibilityShortcut = false
    @Published private(set) var launchAtLoginState: FuwaLaunchAtLoginState
    @Published private(set) var screenRecordingPermission: FuwaPermissionState {
        didSet { onStatusPresentationChanged?() }
    }
    @Published private(set) var busyPinIDs = Set<UUID>()
    @Published private(set) var isPinningFrontWindow = false
    @Published private(set) var isClearingAll = false
    @Published private(set) var isUpdatingShortcut = false
    @Published private(set) var isUpdatingLaunchAtLogin = false
    @Published private(set) var softwareUpdate: SoftwareUpdateState

    var onKeepInDockChanged: ((Bool) -> Void)?
    var onLanguageChanged: ((FuwaLanguagePreference) -> Void)?
    var onStatusPresentationChanged: (() -> Void)?

    private var actions: FuwaAppActions
    private var visibilityOperationCount = 0

    init(
        copy: FuwaCopy? = nil,
        languagePreference: FuwaLanguagePreference = .system,
        keepInDock: Bool = true,
        version: String = "0.1.9",
        shortcut: KeyboardShortcut = .defaultPin,
        shortcutIsActive: Bool = true,
        visibilityShortcut: KeyboardShortcut = .defaultVisibility,
        visibilityShortcutIsActive: Bool = true,
        launchAtLoginState: FuwaLaunchAtLoginState = .disabled,
        screenRecordingPermission: FuwaPermissionState = .unknown,
        actions: FuwaAppActions = FuwaAppActions()
    ) {
        self.copy = copy ?? FuwaCopy(language: languagePreference.resolved)
        self.languagePreference = languagePreference
        self.keepInDock = keepInDock
        self.version = version
        self.shortcut = shortcut
        self.shortcutIsActive = shortcutIsActive
        self.visibilityShortcut = visibilityShortcut
        self.visibilityShortcutIsActive = visibilityShortcutIsActive
        self.launchAtLoginState = launchAtLoginState
        self.screenRecordingPermission = screenRecordingPermission
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

    func setCaptureQuality(_ quality: CaptureQuality, for id: UUID) {
        guard !isClearingAll, !busyPinIDs.contains(id),
              let pin = pins.first(where: { $0.id == id }),
              pin.canAdjustQuality, pin.captureQuality != quality else { return }
        actions.updateCaptureQuality(id, quality)
    }

    func setPinOptions(_ options: PinOptions, for id: UUID) {
        guard !isClearingAll, !busyPinIDs.contains(id),
              let pin = pins.first(where: { $0.id == id }), pin.options != options else { return }
        actions.updatePinOptions(id, options)
    }

    func beginCropSelection(_ id: UUID) {
        guard !isClearingAll, !busyPinIDs.contains(id),
              let pin = pins.first(where: { $0.id == id }),
              pin.state == .live, !pin.isHidden else { return }
        actions.beginCropSelection(id)
    }

    func updatePinsVisibility(_ hidden: Bool) { arePinsHidden = hidden }

    func togglePinsVisibility() {
        guard !pins.isEmpty, !isClearingAll else { return }
        visibilityOperationCount += 1
        isTogglingVisibility = true
        notice = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                visibilityOperationCount -= 1
                isTogglingVisibility = visibilityOperationCount > 0
            }
            do { try await actions.togglePinsVisibility() }
            catch is CancellationError { return }
            catch PinCoordinatorError.operationCancelled { return }
            catch { presentError(error) }
        }
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
        if snapshots.isEmpty { arePinsHidden = false }

        let activeIDs = Set(snapshots.map(\.id))
        busyPinIDs.formIntersection(activeIDs)
    }

    func updatePermissions(
        screenRecording: FuwaPermissionState
    ) {
        screenRecordingPermission = screenRecording
    }

    func updateLaunchAtLoginState(_ state: FuwaLaunchAtLoginState) {
        launchAtLoginState = state
    }

    func showPins() {
        route = .pins
    }

    func showSettings() {
        isChoosingWindow = false
        route = .settings
    }

    func dismissNotice() {
        notice = nil
    }

    func report(_ error: Error) {
        presentError(error)
    }

    func chooseWindow() {
        guard !isPinningFrontWindow, !isClearingAll else { return }
        showPins()
        isChoosingWindow = true
        openMainWindow()
    }

    func setWindowPickerPresented(_ presented: Bool) {
        isChoosingWindow = presented
    }

    func openScreenRecordingSettings() {
        actions.openScreenRecordingSettings()
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

    func unpin(_ id: UUID) {
        performPinAction(id) { actions in
            try await actions.unpin(id)
        }
    }

    func clearAll() {
        guard !isClearingAll, !pins.isEmpty else { return }
        isClearingAll = true
        notice = nil

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
                    notice = FuwaNotice(kind: .error, message: copy.text(.shortcutConflict))
                case .failed:
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

    func updateVisibilityShortcut(_ proposed: KeyboardShortcut) {
        guard !isUpdatingVisibilityShortcut else { return }
        let update: KeyboardShortcutUpdate
        do {
            update = try KeyboardShortcutUpdate(previous: visibilityShortcut, proposed: proposed)
        } catch {
            notice = FuwaNotice(kind: .error, message: copy.text(.invalidShortcut))
            return
        }
        isUpdatingVisibilityShortcut = true
        notice = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isUpdatingVisibilityShortcut = false }
            do {
                let outcome = try await actions.updateVisibilityShortcut(proposed)
                visibilityShortcut = update.resolvedValue(after: outcome)
                switch outcome {
                case .registered: visibilityShortcutIsActive = true
                case .conflict:
                    notice = FuwaNotice(kind: .error, message: copy.text(.shortcutConflict))
                case .failed:
                    notice = FuwaNotice(kind: .error, message: copy.text(.shortcutFailed))
                case .inactive:
                    visibilityShortcutIsActive = false
                    notice = FuwaNotice(kind: .error, message: copy.text(.shortcutInactive))
                }
            } catch {
                visibilityShortcut = update.rolledBackValue
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
}
