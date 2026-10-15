import Foundation
import FuwaCore
import Sparkle

@MainActor
final class SoftwareUpdateController {
    private let userDriver: FuwaUpdateUserDriver
    private let updater: SPUUpdater

    init(model: AppModel) throws {
        let userDriver = FuwaUpdateUserDriver(model: model)
        self.userDriver = userDriver
        updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: nil
        )
        try updater.start()
    }

    func checkForUpdates() {
        guard updater.canCheckForUpdates else {
            userDriver.showUpdateInFocus()
            return
        }
        updater.checkForUpdates()
    }

    func downloadUpdate() {
        userDriver.chooseInstall()
    }

    func cancelUpdate() {
        userDriver.cancelCurrentOperation()
    }

    func installAndRelaunch() {
        userDriver.chooseInstall()
    }
}

@MainActor
final class FuwaUpdateUserDriver: NSObject, SPUUserDriver {
    private weak var model: AppModel?
    private var cancellation: (() -> Void)?
    private var choiceContinuation: CheckedContinuation<SPUUserUpdateChoice, Never>?
    private var expectedBytes: UInt64?
    private var receivedBytes: UInt64 = 0

    init(model: AppModel) {
        self.model = model
    }

    func show(_ request: SPUUpdatePermissionRequest) async -> SUUpdatePermissionResponse {
        SUUpdatePermissionResponse(
            automaticUpdateChecks: false,
            automaticUpdateDownloading: false,
            sendSystemProfile: false
        )
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        guard let model else { return }
        model.setSoftwareUpdateState(
            SoftwareUpdateState(
                phase: .checking,
                currentVersion: model.version
            )
        )
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) async -> SPUUserUpdateChoice {
        cancellation = nil
        expectedBytes = nil
        receivedBytes = 0
        guard let model else { return .dismiss }

        model.setSoftwareUpdateState(
            SoftwareUpdateState(
                phase: .available,
                currentVersion: model.version,
                availableVersion: appcastItem.displayVersionString,
                releaseNotes: normalizedNotes(appcastItem.itemDescription)
            )
        )

        return await withCheckedContinuation { continuation in
            replaceChoiceContinuation(with: continuation)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        guard
            let model,
            let text = String(
                data: downloadData.data,
                encoding: textEncoding(downloadData.textEncodingName)
            )
        else { return }
        var state = model.softwareUpdate
        state.releaseNotes = normalizedNotes(text)
        model.setSoftwareUpdateState(state)
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        // The signed feed embeds Fuwa's release notes. An external note failure
        // is therefore non-fatal and must not weaken update verification.
    }

    func showUpdateNotFoundWithError(_ error: any Error) async {
        cancellation = nil
        guard let model else { return }
        let error = error as NSError
        let reason = (error.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.int32Value
        let isCurrent = reason == SPUNoUpdateFoundReason.onLatestVersion.rawValue
            || reason == SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue
        let isIncompatible = reason == SPUNoUpdateFoundReason.systemIsTooOld.rawValue
            || reason == SPUNoUpdateFoundReason.systemIsTooNew.rawValue
            || reason == SPUNoUpdateFoundReason.hardwareDoesNotSupportARM64.rawValue
        // Sparkle also reports incompatible updates through this callback. Only
        // an explicit current-version reason confirms that Fuwa is up to date.
        let errorMessage: String? = if isCurrent {
            nil
        } else if isIncompatible {
            error.localizedRecoverySuggestion ?? error.localizedDescription
        } else {
            model.copy.text(.updateFailedMessage)
        }
        model.setSoftwareUpdateState(
            SoftwareUpdateState(
                phase: isCurrent ? .current : .failed,
                currentVersion: model.version,
                errorMessage: errorMessage
            )
        )
    }

    func showUpdaterError(_ error: any Error) async {
        cancellation = nil
        resumeChoice(.dismiss)
        guard let model else { return }
        model.setSoftwareUpdateState(
            SoftwareUpdateState(
                phase: .failed,
                currentVersion: model.version,
                availableVersion: model.softwareUpdate.availableVersion,
                releaseNotes: model.softwareUpdate.releaseNotes,
                errorMessage: model.copy.text(.updateFailedMessage)
            )
        )
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        expectedBytes = nil
        receivedBytes = 0
        guard let model else { return }
        model.setSoftwareUpdateState(
            SoftwareUpdateState(
                phase: .downloading,
                currentVersion: model.version,
                availableVersion: model.softwareUpdate.availableVersion,
                releaseNotes: model.softwareUpdate.releaseNotes
            )
        )
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedBytes = expectedContentLength > 0 ? expectedContentLength : nil
        publishDownloadProgress()
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        let (sum, overflow) = receivedBytes.addingReportingOverflow(length)
        receivedBytes = overflow ? .max : sum
        publishDownloadProgress()
    }

    func showDownloadDidStartExtractingUpdate() {
        cancellation = nil
        guard let model else { return }
        model.setSoftwareUpdateState(
            SoftwareUpdateState(
                phase: .extracting,
                currentVersion: model.version,
                availableVersion: model.softwareUpdate.availableVersion,
                releaseNotes: model.softwareUpdate.releaseNotes
            )
        )
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        guard let model else { return }
        var state = model.softwareUpdate
        state.phase = .extracting
        state.extractionProgress = progress
        model.setSoftwareUpdateState(state)
    }

    func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
        guard let model else { return .dismiss }
        var state = model.softwareUpdate
        state.phase = .ready
        state.extractionProgress = 1
        model.setSoftwareUpdateState(state)
        return await withCheckedContinuation { continuation in
            replaceChoiceContinuation(with: continuation)
        }
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        guard let model else { return }
        var state = model.softwareUpdate
        state.phase = .installing
        model.setSoftwareUpdateState(state)
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool) async {
        guard let model else { return }
        model.setSoftwareUpdateState(.idle(currentVersion: model.version))
    }

    func dismissUpdateInstallation() {
        cancellation = nil
        resumeChoice(.dismiss)
    }

    func showUpdateInFocus() {
        model?.showSettings()
    }

    func chooseInstall() {
        resumeChoice(.install)
    }

    func cancelCurrentOperation() {
        if let cancellation {
            self.cancellation = nil
            cancellation()
        } else {
            resumeChoice(.dismiss)
        }
        guard let model else { return }
        model.setSoftwareUpdateState(
            SoftwareUpdateState(
                phase: .cancelled,
                currentVersion: model.version,
                availableVersion: model.softwareUpdate.availableVersion,
                releaseNotes: model.softwareUpdate.releaseNotes
            )
        )
    }

    private func publishDownloadProgress() {
        guard let model else { return }
        var state = model.softwareUpdate
        state.phase = .downloading
        state.expectedBytes = expectedBytes
        state.receivedBytes = receivedBytes
        model.setSoftwareUpdateState(state)
    }

    private func replaceChoiceContinuation(
        with continuation: CheckedContinuation<SPUUserUpdateChoice, Never>
    ) {
        choiceContinuation?.resume(returning: .dismiss)
        choiceContinuation = continuation
    }

    private func resumeChoice(_ choice: SPUUserUpdateChoice) {
        guard let continuation = choiceContinuation else { return }
        choiceContinuation = nil
        continuation.resume(returning: choice)
    }

    private func normalizedNotes(_ notes: String?) -> String? {
        guard let notes else { return nil }
        let normalized = notes
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func textEncoding(_ name: String?) -> String.Encoding {
        guard let name else { return .utf8 }
        let converted = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard converted != kCFStringEncodingInvalidId else { return .utf8 }
        return String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(converted)
        )
    }
}
