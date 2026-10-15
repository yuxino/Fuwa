import Foundation
import FuwaCore
import Sparkle
import Testing
@testable import Fuwa

@Suite(.serialized)
@MainActor
struct SoftwareUpdateControllerTests {
    @Test func currentVersionReasonsConfirmUpToDate() async {
        for reason in [SPUNoUpdateFoundReason.onLatestVersion, .onNewerThanLatestVersion] {
            let model = AppModel()
            let driver = FuwaUpdateUserDriver(model: model)
            await driver.showUpdateNotFoundWithError(noUpdateError(reason))
            #expect(model.softwareUpdate.phase == .current)
            #expect(model.softwareUpdate.errorMessage == nil)
        }
    }

    @Test func incompatibleUpdateDoesNotReportUpToDate() async {
        for reason in [SPUNoUpdateFoundReason.systemIsTooOld, .systemIsTooNew,
                       .hardwareDoesNotSupportARM64] {
            let model = AppModel()
            let driver = FuwaUpdateUserDriver(model: model)
            let suggestion = "This update requires a supported macOS version or Mac."
            await driver.showUpdateNotFoundWithError(noUpdateError(reason, suggestion: suggestion))
            #expect(model.softwareUpdate.phase == .failed)
            #expect(model.softwareUpdate.errorMessage == suggestion)
            #expect(model.softwareUpdate.canRetry)
        }
    }

    @Test func missingOrUnknownReasonDoesNotConfirmCurrentVersion() async {
        let model = AppModel()
        let driver = FuwaUpdateUserDriver(model: model)
        for error in [noUpdateError(.unknown), NSError(domain: "SUSparkleErrorDomain", code: 1001)] {
            await driver.showUpdateNotFoundWithError(error)
            #expect(model.softwareUpdate.phase == .failed)
            #expect(model.softwareUpdate.errorMessage == model.copy.text(.updateFailedMessage))
        }
    }

    private func noUpdateError(
        _ reason: SPUNoUpdateFoundReason,
        suggestion: String? = nil
    ) -> NSError {
        var userInfo: [String: Any] = [SPUNoUpdateFoundReasonKey: NSNumber(value: reason.rawValue)]
        if let suggestion {
            userInfo[NSLocalizedRecoverySuggestionErrorKey] = suggestion
        }
        return NSError(domain: "SUSparkleErrorDomain", code: 1001, userInfo: userInfo)
    }
}
