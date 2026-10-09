import Foundation

/// Map typed failures once; every supported language supplies the same messages.
enum FuwaErrorMessage {
    static func localizedDescription(for error: Error, language: FuwaLanguage) -> String {
        let copy = FuwaCopy(language: language)
        if let error = error as? FuwaApplicationError {
            switch error {
            case .unavailable: return copy.text(.errorUnavailable)
            case .pinIntentUnavailable: return copy.text(.errorPinIntentUnavailable)
            }
        }
        if let error = error as? GlobalHotKey.RegistrationError {
            switch error {
            case .installHandler(let status):
                return copy.formatted(.errorShortcutStart, values: ["code": String(status)])
            case .registerHotKey(let status, let shortcut):
                return copy.formatted(.errorShortcutRegister, values: ["code": String(status), "shortcut": shortcut])
            }
        }
        if let error = error as? LaunchAtLoginError {
            switch error {
            case .requiresApproval: return copy.text(.launchAtLoginApproval)
            case .serviceUnavailable: return copy.text(.errorLoginUnavailable)
            }
        }
        if let error = error as? PinCoordinatorError {
            switch error {
            case .pinNotFound: return copy.text(.errorPinMissing)
            case .operationCancelled: return copy.text(.errorPinCancelled)
            case .pinLimitReached(let maximum):
                return copy.formatted(.errorPinLimit, values: ["count": String(maximum)])
            case .screenRecordingRevoked: return copy.text(.errorRecordingRevoked)
            }
        }
        if let error = error as? TargetResolutionError {
            switch error {
            case .inventoryUnavailable: return copy.text(.errorInventory)
            case .noEligibleIntent: return copy.text(.errorNoEligibleWindow)
            case .screenRecordingPermissionDenied: return copy.text(.errorRecordingDenied)
            case .shareableContentUnavailable: return copy.text(.errorShareableContent)
            case .intentDisappeared: return copy.text(.errorSourceClosed)
            case .intentNotShareable: return copy.text(.errorNotShareable)
            }
        }
        if let error = error as? InteractionError {
            switch error {
            case .viewOnly(let reason): return interactionDescription(reason, copy: copy)
            }
        }
        if error is AccessibilityWindowResolutionError { return copy.text(.errorWindowMatch) }
        if let error = error as? PinSessionError {
            switch error {
            case .invalidTransition: return copy.text(.errorPinState)
            case .captureStartFailed: return copy.text(.errorCaptureStart)
            case .captureStartInterrupted: return copy.text(.errorCaptureInterrupted)
            case .captureFailed: return copy.text(.errorCaptureStopped)
            case .captureResumeTimedOut: return copy.text(.errorCaptureResume)
            case .freezeFailed: return copy.text(.errorFreeze)
            }
        }
        if error is FrozenFrameError { return copy.text(.errorFrameMissing) }
        if error is WindowInventoryError { return copy.text(.errorDisplayInventory) }
        return copy.text(.errorUnknown)
    }

    private static func interactionDescription(_ reason: InteractionViewOnlyReason, copy: FuwaCopy) -> String {
        switch reason {
        case .accessibilityPermissionRequired: copy.text(.errorAccessibilityRequired)
        case .sourceApplicationUnavailable: copy.text(.errorSourceAppMissing)
        case .sourceWindowUnavailable: copy.text(.errorSourceWindowMissing)
        case .sourceWindowAmbiguous: copy.text(.errorSourceAmbiguous)
        case .sourceActivationRejected: copy.text(.errorActivationRejected)
        case .sourceActivationTimedOut: copy.text(.errorActivationTimeout)
        case .sourceRestoreUnsupported: copy.text(.errorRestoreUnsupported)
        case .sourceRestoreFailed(let code): copy.formatted(.errorRestoreFailed, values: ["code": String(code)])
        case .raiseUnsupported: copy.text(.errorRaiseUnsupported)
        case .raiseFailed(let code): copy.formatted(.errorRaiseFailed, values: ["code": String(code)])
        }
    }
}
