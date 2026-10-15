import Foundation
import FuwaCore
import Testing
@testable import Fuwa

@Suite(.serialized)
@MainActor
struct OperationCancellationPresentationTests {
    @Test(arguments: [false, true])
    func clearingPinsWhileResumeWaitsDoesNotReportAFailure(taskCancellation: Bool) async {
        let model = AppModel()
        let pin = PinSnapshot(id: UUID(), sourceWindowID: 905, applicationName: "Preview",
                              bundleIdentifier: nil, windowTitle: "Reference",
                              state: .frozen(.manual), errorMessage: nil)
        model.updatePins([pin])
        var finishResume: CheckedContinuation<Void, Never>?
        var resumeFinished = false
        var actions = FuwaAppActions()
        actions.resume = { _ in
            defer { resumeFinished = true }
            await withCheckedContinuation { finishResume = $0 }
            if taskCancellation { throw CancellationError() }
            throw PinCoordinatorError.operationCancelled
        }
        actions.clearAll = { model.updatePins([]) }
        model.configure(actions: actions)

        model.resume(pin.id)
        await settle { finishResume != nil }
        #expect(model.busyPinIDs.contains(pin.id))
        model.clearAll()
        await settle { !model.isClearingAll }
        finishResume?.resume()
        await settle { resumeFinished }

        #expect(model.pins.isEmpty)
        #expect(model.busyPinIDs.isEmpty)
        #expect(model.notice == nil)
    }

    @Test(arguments: [false, true])
    func cancelledPinDoesNotReplaceANewerPermissionFailure(taskCancellation: Bool) async {
        let model = AppModel(copy: FuwaCopy(language: .english))
        var finishPin: CheckedContinuation<Void, Never>?
        var actions = FuwaAppActions()
        actions.beginPinFrontWindow = {
            return {
                await withCheckedContinuation { finishPin = $0 }
                if taskCancellation { throw CancellationError() }
                throw PinCoordinatorError.operationCancelled
            }
        }
        model.configure(actions: actions)
        model.pinFrontWindow()
        await settle { finishPin != nil }
        model.report(TargetResolutionError.screenRecordingPermissionDenied)
        let permissionNotice = model.notice
        #expect(permissionNotice?.kind == .error)

        finishPin?.resume()
        await settle { !model.isPinningFrontWindow }
        #expect(model.notice == permissionNotice)
    }

    @Test func actualResumeFailureStillReportsAnError() async {
        let model = AppModel(copy: FuwaCopy(language: .english))
        let pin = PinSnapshot(id: UUID(), sourceWindowID: 906, applicationName: "Preview",
                              bundleIdentifier: nil, windowTitle: "Reference",
                              state: .frozen(.manual), errorMessage: nil)
        model.updatePins([pin])
        var actions = FuwaAppActions()
        actions.resume = { _ in throw TargetResolutionError.screenRecordingPermissionDenied }
        model.configure(actions: actions)
        model.resume(pin.id)
        await settle { model.busyPinIDs.isEmpty }
        #expect(model.notice?.kind == .error)
        #expect(model.notice?.message == model.copy.text(.errorRecordingDenied))
    }

    private func settle(until condition: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }
}
