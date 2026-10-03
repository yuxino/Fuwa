import Foundation

/// Keeps user-visible failures in the same automatically selected language as
/// the popover. Underlying errors remain typed and keep their diagnostic text;
/// this layer only decides what is appropriate to show in a compact notice.
enum FuwaErrorMessage {
    static func localizedDescription(
        for error: Error,
        language: FuwaLanguage
    ) -> String {
        switch language {
        case .english:
            englishDescription(for: error)
        case .simplifiedChinese:
            simplifiedChineseDescription(for: error)
        }
    }

    private static func englishDescription(for error: Error) -> String {
        if let error = error as? FuwaApplicationError {
            switch error {
            case .unavailable:
                return "Fuwa is temporarily unavailable. Try again."
            case .pinIntentUnavailable:
                return "Reopen Fuwa while the target window is still visible, then try again."
            }
        }
        if let error = error as? GlobalHotKey.RegistrationError {
            switch error {
            case .installHandler(let status):
                return "Fuwa could not start the global shortcut (\(status))."
            case .registerHotKey(let status, let shortcut):
                return "Fuwa could not register \(shortcut) (\(status)). It may conflict with another app."
            }
        }
        if let error = error as? LaunchAtLoginError {
            switch error {
            case .requiresApproval:
                return "Approve Fuwa in System Settings → General → Login Items."
            case .serviceUnavailable:
                return "Launch at Login is unavailable for this copy. Move Fuwa to Applications and try again."
            }
        }
        if let error = error as? PinCoordinatorError {
            switch error {
            case .pinNotFound:
                return "This pinned window is no longer available."
            case .operationCancelled:
                return "The pin operation was cancelled."
            case .pinLimitReached(let maximum):
                return "Fuwa can pin up to \(maximum) windows. Remove one before adding another."
            case .screenRecordingRevoked:
                return "Screen Recording permission was removed, so Fuwa cleared all captured frames."
            }
        }
        if let error = error as? TargetResolutionError {
            switch error {
            case .inventoryUnavailable:
                return "Fuwa cannot read the current window list right now."
            case .noEligibleIntent:
                return "No pinnable window is visible in front."
            case .screenRecordingPermissionDenied:
                return "Enable Screen Recording permission before Fuwa can pin this window."
            case .shareableContentUnavailable:
                return "macOS did not provide a capturable window list. Try again."
            case .intentDisappeared:
                return "The front window closed before capture began."
            case .intentNotShareable:
                return "This window is visible, but macOS does not allow it to be captured."
            }
        }
        if let error = error as? InteractionError {
            switch error {
            case .viewOnly(let reason):
                return englishInteractionDescription(reason)
            }
        }
        if error is AccessibilityWindowResolutionError {
            return "Fuwa could not safely confirm the source window, so the pin remains view-only."
        }
        if let error = error as? PinSessionError {
            switch error {
            case .invalidTransition:
                return "This pinned window changed state. Try again."
            case .captureStartFailed:
                return "Fuwa could not start capturing this window."
            case .captureStartInterrupted:
                return "Capture stopped while Fuwa was starting it."
            case .captureFailed:
                return "Window capture stopped, so Fuwa stopped displaying that frame."
            case .captureResumeTimedOut:
                return "Fuwa could not resume live capture. The previous frozen frame is still visible."
            case .freezeFailed:
                return "Fuwa could not preserve the last frame."
            }
        }
        if error is FrozenFrameError {
            return "Fuwa has not received a complete frame to freeze yet."
        }
        if error is WindowInventoryError {
            return "Fuwa cannot read the current windows or display arrangement right now."
        }
        return "Fuwa could not complete this action. Try again."
    }

    private static func simplifiedChineseDescription(for error: Error) -> String {
        if let error = error as? FuwaApplicationError {
            switch error {
            case .unavailable:
                return "Fuwa 暂时不可用，请再试一次。"
            case .pinIntentUnavailable:
                return "请在目标窗口仍可见时重新打开 Fuwa，再试一次。"
            }
        }
        if let error = error as? GlobalHotKey.RegistrationError {
            switch error {
            case .installHandler(let status):
                return "Fuwa 无法启动全局快捷键（\(status)）。"
            case .registerHotKey(let status, let shortcut):
                return "Fuwa 无法注册 \(shortcut)（\(status)），可能与其他软件冲突。"
            }
        }
        if let error = error as? LaunchAtLoginError {
            switch error {
            case .requiresApproval:
                return "请在“系统设置 → 通用 → 登录项”中批准 Fuwa。"
            case .serviceUnavailable:
                return "当前这份 Fuwa 无法设置开机启动。请先将它移到“应用程序”文件夹。"
            }
        }
        if let error = error as? PinCoordinatorError {
            switch error {
            case .pinNotFound:
                return "这个固定窗口已经不存在。"
            case .operationCancelled:
                return "这次固定操作已取消。"
            case .pinLimitReached(let maximum):
                return "Fuwa 最多同时固定 \(maximum) 个窗口，请先移除一个。"
            case .screenRecordingRevoked:
                return "屏幕录制权限已被关闭，Fuwa 已清除所有捕获画面。"
            }
        }
        if let error = error as? TargetResolutionError {
            switch error {
            case .inventoryUnavailable:
                return "Fuwa 暂时无法读取当前窗口列表。"
            case .noEligibleIntent:
                return "没有找到可以固定的前方窗口。"
            case .screenRecordingPermissionDenied:
                return "需要开启屏幕录制权限，Fuwa 才能固定这个窗口。"
            case .shareableContentUnavailable:
                return "macOS 暂时没有提供可捕获的窗口列表。"
            case .intentDisappeared:
                return "前方窗口在捕获开始前已经关闭。"
            case .intentNotShareable:
                return "这个窗口可见，但 macOS 不允许捕获它。"
            }
        }
        if let error = error as? InteractionError {
            switch error {
            case .viewOnly(let reason):
                return interactionDescription(reason)
            }
        }
        if error is AccessibilityWindowResolutionError {
            return "Fuwa 无法安全地确认真实源窗口，因此保留为仅查看。"
        }
        if let error = error as? PinSessionError {
            switch error {
            case .invalidTransition:
                return "这个固定窗口的状态已经变化，请再试一次。"
            case .captureStartFailed:
                return "Fuwa 无法开始捕获这个窗口。"
            case .captureStartInterrupted:
                return "捕获在启动过程中被中断。"
            case .captureFailed:
                return "窗口捕获已中断，Fuwa 已停止显示相关画面。"
            case .captureResumeTimedOut:
                return "Fuwa 无法恢复实时捕获，之前的冻结画面仍然保留。"
            case .freezeFailed:
                return "Fuwa 无法保留最后一帧画面。"
            }
        }
        if error is FrozenFrameError {
            return "Fuwa 还没有收到可以冻结的完整画面。"
        }
        if error is WindowInventoryError {
            return "Fuwa 暂时无法读取窗口或显示器信息。"
        }
        return "Fuwa 无法完成这次操作，请再试一次。"
    }

    private static func interactionDescription(_ reason: InteractionViewOnlyReason) -> String {
        switch reason {
        case .accessibilityPermissionRequired:
            return "需要开启辅助功能权限，才能显示并操作真实源窗口。"
        case .sourceApplicationUnavailable:
            return "源应用已经退出，这个画面会保持仅查看。"
        case .sourceWindowUnavailable:
            return "没有找到原来的源窗口，这个画面会保持仅查看。"
        case .sourceWindowAmbiguous:
            return "有多个相似窗口，Fuwa 无法安全确认原窗口，因此没有切换。"
        case .sourceActivationRejected:
            return "macOS 没有允许 Fuwa 激活源应用。"
        case .sourceActivationTimedOut:
            return "源应用未能及时切换到前台，这个画面会保持仅查看。"
        case .sourceRestoreUnsupported:
            return "这个最小化的源窗口不支持通过辅助功能恢复。"
        case .sourceRestoreFailed(let code):
            return "macOS 无法恢复最小化的源窗口（辅助功能错误 \(code)）。"
        case .raiseUnsupported:
            return "这个源窗口不支持通过辅助功能显示。"
        case .raiseFailed(let code):
            return "macOS 无法切换到原窗口（辅助功能错误 \(code)）。"
        }
    }

    private static func englishInteractionDescription(
        _ reason: InteractionViewOnlyReason
    ) -> String {
        switch reason {
        case .accessibilityPermissionRequired:
            return "Enable Accessibility permission to reveal and use the source window."
        case .sourceApplicationUnavailable:
            return "The source app has quit, so this pin remains view-only."
        case .sourceWindowUnavailable:
            return "Fuwa could not find the original source window, so this pin remains view-only."
        case .sourceWindowAmbiguous:
            return "Several windows look alike, so Fuwa did not switch to a possibly wrong source."
        case .sourceActivationRejected:
            return "macOS did not allow Fuwa to activate the source app."
        case .sourceActivationTimedOut:
            return "The source app did not become active in time, so this pin remains view-only."
        case .sourceRestoreUnsupported:
            return "This minimized source window cannot be restored through Accessibility."
        case .sourceRestoreFailed(let code):
            return "macOS could not restore the minimized source window (Accessibility error \(code))."
        case .raiseUnsupported:
            return "This source window cannot be revealed through Accessibility."
        case .raiseFailed(let code):
            return "macOS could not reveal the source window (Accessibility error \(code))."
        }
    }
}
