import Foundation
import FuwaCore

enum FuwaLanguage: String, CaseIterable, Sendable {
    case english, simplifiedChinese, traditionalChinese, japanese, korean, french, german

    var nativeName: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .french: "Français"
        case .german: "Deutsch"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        case .traditionalChinese: "zh-Hant"
        case .japanese: "ja"
        case .korean: "ko"
        case .french: "fr"
        case .german: "de"
        }
    }

    static func automatic(preferredLanguages: [String] = Locale.preferredLanguages) -> Self {
        for identifier in preferredLanguages {
            let parts = identifier.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-")
            switch parts.first {
            case "zh":
                if parts.contains("hant") { return .traditionalChinese }
                if parts.contains("hans") { return .simplifiedChinese }
                return parts.contains(where: { ["tw", "hk", "mo"].contains($0) })
                    ? .traditionalChinese : .simplifiedChinese
            case "en": return .english
            case "ja": return .japanese
            case "ko": return .korean
            case "fr": return .french
            case "de": return .german
            default: continue
            }
        }
        return .english
    }
}

enum FuwaLanguagePreference: String, CaseIterable, Sendable {
    // Keep existing saved values stable when adding languages.
    case system, english, simplifiedChinese, traditionalChinese, japanese, korean, french, german

    var resolved: FuwaLanguage {
        switch self {
        case .system: .automatic()
        case .english: .english
        case .simplifiedChinese: .simplifiedChinese
        case .traditionalChinese: .traditionalChinese
        case .japanese: .japanese
        case .korean: .korean
        case .french: .french
        case .german: .german
        }
    }
}

enum FuwaString: String, CaseIterable, Sendable {
    case appName
    case language
    case systemLanguage
    case showControls
    case chooseWindow
    case searchWindows
    case refreshWindows
    case noWindowsFound
    case openFuwa
    case emptyTitle
    case removeExplanation
    case manageWindows
    case appTagline
    case pinFrontWindow
    case pins
    case noPinsBody
    case live
    case starting
    case resolving
    case frozen
    case sourceClosed
    case captureInterrupted
    case failed
    case stopping
    case freeze
    case freezeNote
    case resume
    case resumeNote
    case unpin
    case clearAll
    case settings
    case general
    case permissions
    case screenRecording
    case ready
    case permissionNeeded
    case permissionUnknown
    case permissionNotEnabled
    case openSettings
    case screenRecordingNote
    case keepInDock
    case keepInDockNote
    case captureQuality
    case captureQualityNote
    case captureQualityHelp
    case qualityNative
    case qualityLower
    case qualityHigher
    case launchAtLogin
    case launchAtLoginApproval
    case openLoginItems
    case shortcut
    case shortcutNote
    case shortcutInactive
    case recordShortcut
    case pressShortcut
    case shortcutConflict
    case shortcutFailed
    case invalidShortcut
    case softwareUpdate
    case checkForUpdates
    case checkingForUpdates
    case upToDate
    case updateAvailable
    case downloadUpdate
    case downloadingUpdate
    case extractingUpdate
    case readyToInstall
    case restartAndUpdate
    case installingUpdate
    case updateCancelled
    case updateFailedMessage
    case retryUpdate
    case releaseNotes
    case openReleasePage
    case releaseRecoveryHint
    case viewLatestRelease
    case viewLatestReleaseHint
    case about
    case quit
    case version
    case dismiss
    case cancel
    case statusPinned
    case statusNoPins
    case permissionAttention
    case pinCountOne, pinCountMany
    case errorUnavailable, errorPinIntentUnavailable, errorShortcutStart, errorShortcutRegister
    case errorLoginUnavailable, errorPinMissing, errorPinCancelled, errorPinLimit, errorRecordingRevoked
    case errorInventory, errorNoEligibleWindow, errorRecordingDenied, errorShareableContent
    case errorSourceClosed, errorNotShareable
    case errorPinState, errorCaptureStart, errorCaptureInterrupted, errorCaptureStopped
    case errorCaptureResume, errorFreeze, errorFrameMissing, errorDisplayInventory, errorUnknown
}
struct FuwaCopy: Sendable {
    let language: FuwaLanguage

    init(language: FuwaLanguage = .automatic()) {
        self.language = language
    }

    private var translations: [FuwaString: String] {
        switch language {
        case .english: Self.english
        case .simplifiedChinese: Self.simplifiedChinese
        case .traditionalChinese: Self.traditionalChinese
        case .japanese: Self.japanese
        case .korean: Self.korean
        case .french: Self.french
        case .german: Self.german
        }
    }

    func hasTranslation(for key: FuwaString) -> Bool { translations[key] != nil }

    func text(_ key: FuwaString) -> String { translations[key] ?? key.rawValue }

    func formatted(_ key: FuwaString, values: [String: String]) -> String {
        values.reduce(text(key)) { result, value in
            result.replacingOccurrences(of: "{\(value.key)}", with: value.value)
        }
    }

    func pinsCount(_ count: Int) -> String {
        formatted(count == 1 ? .pinCountOne : .pinCountMany, values: ["count": String(count)])
    }

    func captureQualityLabel(_ quality: CaptureQuality) -> String {
        quality == .native ? text(.qualityNative) : "\(quality.percentage)%"
    }

    private static let english: [FuwaString: String] = [
        .language: "Language",
        .systemLanguage: "Follow System",
        .appName: "Fuwa",
        .showControls: "Show Floating Controls",
        .chooseWindow: "Choose a Window",
        .searchWindows: "Search apps and windows",
        .refreshWindows: "Refresh Windows",
        .noWindowsFound: "No matching windows. Open a window, then refresh.",
        .openFuwa: "Open Fuwa",
        .emptyTitle: "No pinned windows",
        .removeExplanation: "Removing a pin leaves the original window open.",
        .manageWindows: "Your windows",
        .appTagline: "Keep the window you need on top.",
        .pinFrontWindow: "Pin Front Window",
        .pins: "Pins",
        .noPinsBody: "Open a reference or tutorial window, then press the shortcut to keep it on top.",
        .live: "Live",
        .starting: "Starting…",
        .resolving: "Finding window…",
        .frozen: "Paused",
        .sourceClosed: "Source closed",
        .captureInterrupted: "Capture paused",
        .failed: "Failed",
        .stopping: "Removing…",
        .freeze: "Pause Picture",
        .freezeNote: "Keep this picture still. The original window keeps running.",
        .resume: "Resume",
        .resumeNote: "Show live updates from the original window again.",
        .unpin: "Unpin",
        .clearAll: "Unpin All",
        .settings: "Settings",
        .general: "General",
        .permissions: "Permissions",
        .screenRecording: "Screen Recording",
        .ready: "Allowed",
        .permissionNeeded: "Permission needed",
        .permissionUnknown: "Not used yet",
        .permissionNotEnabled: "Not enabled",
        .openSettings: "Open Settings",
        .screenRecordingNote: "Fuwa needs to read a window’s picture to show it in a pinned view. Pictures stay on this Mac.",
        .keepInDock: "Keep in Dock",
        .keepInDockNote: "When off, Fuwa’s Dock icon is hidden. You can still open Fuwa from the menu bar.",
        .captureQuality: "Picture Quality",
        .captureQualityNote: "Adjust the picture quality of this pinned window.",
        .captureQualityHelp: "Each newly pinned window starts at original quality. Lowering it affects only this window and uses less memory, but may blur text and details. Resume a paused picture before adjusting.",
        .qualityNative: "Original (100%)",
        .qualityLower: "Less memory",
        .qualityHigher: "Clearer picture",
        .launchAtLogin: "Launch at Login",
        .launchAtLoginApproval: "Approve Fuwa in System Settings → General → Login Items.",
        .openLoginItems: "Open Login Items",
        .shortcut: "Global Shortcut",
        .shortcutNote: "Pin or unpin the front window, even while Fuwa is in the background.",
        .shortcutInactive: "The global shortcut is currently inactive. Record a new shortcut to turn it back on.",
        .recordShortcut: "Change",
        .pressShortcut: "Press a new shortcut…",
        .shortcutConflict: "That shortcut is already used. The previous shortcut is still active.",
        .shortcutFailed: "The shortcut could not be changed. The previous shortcut is still active.",
        .invalidShortcut: "Include Command, Option, or Control with a key.",
        .softwareUpdate: "Software Update",
        .checkForUpdates: "Check for Updates",
        .checkingForUpdates: "Checking for updates…",
        .upToDate: "Fuwa is up to date.",
        .updateAvailable: "A new Fuwa version is available.",
        .downloadUpdate: "Download Update",
        .downloadingUpdate: "Downloading update…",
        .extractingUpdate: "Verifying and extracting update…",
        .readyToInstall: "The verified update is ready.",
        .restartAndUpdate: "Restart and Complete Update",
        .installingUpdate: "Installing update…",
        .updateCancelled: "Update cancelled. You can try again.",
        .updateFailedMessage: "The update could not be verified or completed. Fuwa was not changed.",
        .retryUpdate: "Try Again",
        .releaseNotes: "Release Notes",
        .openReleasePage: "Open GitHub Releases",
        .releaseRecoveryHint: "Use GitHub Releases only if the in-app update keeps failing.",
        .viewLatestRelease: "View Latest Release",
        .viewLatestReleaseHint: "Opens the latest Fuwa release in your browser.",
        .about: "About Fuwa",
        .quit: "Quit Fuwa",
        .version: "Version",
        .dismiss: "Dismiss",
        .cancel: "Cancel",
        .statusPinned: "Fuwa has pinned windows",
        .statusNoPins: "Fuwa, no pinned windows",
        .permissionAttention: "Permission needs attention",
        .errorUnavailable: "Fuwa is temporarily unavailable. Try again.",
        .errorPinIntentUnavailable: "Reopen Fuwa while the target window is still visible, then try again.",
        .errorShortcutStart: "Fuwa could not start the global shortcut ({code}).",
        .errorShortcutRegister: "Fuwa could not register {shortcut} ({code}). It may conflict with another app.",
        .errorLoginUnavailable: "Launch at Login is unavailable for this copy. Move Fuwa to Applications and try again.",
        .errorPinMissing: "This pinned window is no longer available.",
        .errorPinCancelled: "The pin operation was cancelled.",
        .errorPinLimit: "Fuwa can pin up to {count} windows. Remove one before adding another.",
        .errorRecordingRevoked: "Screen Recording permission was removed, so Fuwa cleared all captured frames.",
        .errorInventory: "Fuwa cannot read the current window list right now.",
        .errorNoEligibleWindow: "No pinnable window is visible in front.",
        .errorRecordingDenied: "Enable Screen Recording permission before Fuwa can pin this window.",
        .errorShareableContent: "macOS did not provide a capturable window list. Try again.",
        .errorSourceClosed: "The front window closed before capture began.",
        .errorNotShareable: "This window is visible, but macOS does not allow it to be captured.",
        .errorPinState: "This pinned window changed state. Try again.",
        .errorCaptureStart: "Fuwa could not start capturing this window.",
        .errorCaptureInterrupted: "Capture stopped while Fuwa was starting it.",
        .errorCaptureStopped: "Window capture stopped, so Fuwa stopped displaying that frame.",
        .errorCaptureResume: "Fuwa could not resume live updates. The paused picture is still visible.",
        .errorFreeze: "Fuwa could not preserve the last frame.",
        .errorFrameMissing: "No complete picture is available to pause yet.",
        .errorDisplayInventory: "Fuwa cannot read the current windows or display arrangement right now.",
        .errorUnknown: "Fuwa could not complete this action. Try again.",
        .pinCountOne: "{count} pin",
        .pinCountMany: "{count} pins",
    ]

    private static let simplifiedChinese: [FuwaString: String] = [
        .language: "语言",
        .systemLanguage: "跟随系统",
        .appName: "Fuwa",
        .showControls: "显示浮窗控制",
        .chooseWindow: "选择窗口",
        .searchWindows: "搜索应用和窗口",
        .refreshWindows: "刷新窗口列表",
        .noWindowsFound: "没有匹配的窗口。打开窗口后刷新列表。",
        .openFuwa: "打开 Fuwa",
        .emptyTitle: "暂无固定窗口",
        .removeExplanation: "取消固定不会关闭原窗口。",
        .manageWindows: "你的窗口",
        .appTagline: "把需要的窗口置顶，方便随时查看。",
        .pinFrontWindow: "固定最前方窗口",
        .pins: "已固定",
        .noPinsBody: "打开要参考的图片、文档或教程窗口，再按快捷键置顶。",
        .live: "实时画面",
        .starting: "正在启动…",
        .resolving: "正在查找窗口…",
        .frozen: "已暂停",
        .sourceClosed: "源窗口已关闭",
        .captureInterrupted: "捕获已暂停",
        .failed: "失败",
        .stopping: "正在移除…",
        .freeze: "暂停画面",
        .freezeNote: "让置顶画面停在这一刻，原窗口仍正常运行。",
        .resume: "取消暂停",
        .resumeNote: "让置顶画面重新跟随原窗口变化。",
        .unpin: "取消固定",
        .clearAll: "全部取消固定",
        .settings: "设置",
        .general: "通用",
        .permissions: "权限",
        .screenRecording: "屏幕录制",
        .ready: "已授权",
        .permissionNeeded: "需要授权",
        .permissionUnknown: "尚未使用",
        .permissionNotEnabled: "未开启",
        .openSettings: "打开设置",
        .screenRecordingNote: "Fuwa 需要读取窗口画面，才能显示置顶浮窗。画面只在本机处理。",
        .keepInDock: "保留 Dock 图标",
        .keepInDockNote: "关闭后隐藏 Dock 图标，仍可从菜单栏打开 Fuwa。",
        .captureQuality: "画面清晰度",
        .captureQualityNote: "调整这个置顶窗口的清晰度。",
        .captureQualityHelp: "每个新置顶的窗口默认保留原始画面。调低只影响这个窗口，可节省内存，但文字和细节可能变模糊。暂停画面时，需先取消暂停才能调整。",
        .qualityNative: "原始（100%）",
        .qualityLower: "更省内存",
        .qualityHigher: "更清晰",
        .launchAtLogin: "开机启动",
        .launchAtLoginApproval: "需要在“系统设置 → 通用 → 登录项”中批准 Fuwa。",
        .openLoginItems: "打开登录项",
        .shortcut: "全局快捷键",
        .shortcutNote: "固定或取消固定最前方的窗口，Fuwa 在后台时也可使用。",
        .shortcutInactive: "全局快捷键当前未启用。请录制一个新快捷键以重新启用。",
        .recordShortcut: "更改",
        .pressShortcut: "请按新的快捷键…",
        .shortcutConflict: "这个快捷键已被占用，原快捷键仍然有效。",
        .shortcutFailed: "无法更改快捷键，原快捷键仍然有效。",
        .invalidShortcut: "请同时按下 Command、Option 或 Control。",
        .softwareUpdate: "软件更新",
        .checkForUpdates: "检查更新",
        .checkingForUpdates: "正在检查更新…",
        .upToDate: "Fuwa 已是最新版本。",
        .updateAvailable: "发现新的 Fuwa 版本。",
        .downloadUpdate: "下载更新",
        .downloadingUpdate: "正在下载更新…",
        .extractingUpdate: "正在验证并解压更新…",
        .readyToInstall: "已验证更新，可以安装。",
        .restartAndUpdate: "重启并完成更新",
        .installingUpdate: "正在安装更新…",
        .updateCancelled: "更新已取消，可以重新尝试。",
        .updateFailedMessage: "无法验证或完成更新，Fuwa 未被修改。",
        .retryUpdate: "重试",
        .releaseNotes: "版本说明",
        .openReleasePage: "打开 GitHub Releases",
        .releaseRecoveryHint: "仅当应用内更新持续失败时，才使用 GitHub Releases。",
        .viewLatestRelease: "查看最新版本",
        .viewLatestReleaseHint: "在浏览器中打开 Fuwa 最新版本页面。",
        .about: "关于 Fuwa",
        .quit: "退出 Fuwa",
        .version: "版本",
        .dismiss: "关闭",
        .cancel: "取消",
        .statusPinned: "Fuwa 有已固定窗口",
        .statusNoPins: "Fuwa，没有固定窗口",
        .permissionAttention: "权限需要处理",
        .errorUnavailable: "Fuwa 暂时不可用，请再试一次。",
        .errorPinIntentUnavailable: "请在目标窗口仍可见时重新打开 Fuwa，再试一次。",
        .errorShortcutStart: "Fuwa 无法启动全局快捷键（{code}）。",
        .errorShortcutRegister: "Fuwa 无法注册 {shortcut}（{code}），可能与其他软件冲突。",
        .errorLoginUnavailable: "当前这份 Fuwa 无法设置开机启动。请先将它移到“应用程序”文件夹。",
        .errorPinMissing: "这个固定窗口已经不存在。",
        .errorPinCancelled: "这次固定操作已取消。",
        .errorPinLimit: "Fuwa 最多同时固定 {count} 个窗口，请先移除一个。",
        .errorRecordingRevoked: "屏幕录制权限已被关闭，Fuwa 已清除所有捕获画面。",
        .errorInventory: "Fuwa 暂时无法读取当前窗口列表。",
        .errorNoEligibleWindow: "没有找到可以固定的前方窗口。",
        .errorRecordingDenied: "需要开启屏幕录制权限，Fuwa 才能固定这个窗口。",
        .errorShareableContent: "macOS 暂时没有提供可捕获的窗口列表。",
        .errorSourceClosed: "前方窗口在捕获开始前已经关闭。",
        .errorNotShareable: "这个窗口可见，但 macOS 不允许捕获它。",
        .errorPinState: "这个固定窗口的状态已经变化，请再试一次。",
        .errorCaptureStart: "Fuwa 无法开始捕获这个窗口。",
        .errorCaptureInterrupted: "捕获在启动过程中被中断。",
        .errorCaptureStopped: "窗口捕获已中断，Fuwa 已停止显示相关画面。",
        .errorCaptureResume: "暂时无法取消暂停，仍显示暂停时的画面。",
        .errorFreeze: "Fuwa 无法保留最后一帧画面。",
        .errorFrameMissing: "还没有完整画面可以暂停。",
        .errorDisplayInventory: "Fuwa 暂时无法读取窗口或显示器信息。",
        .errorUnknown: "Fuwa 无法完成这次操作，请再试一次。",
        .pinCountOne: "{count} 个固定窗口",
        .pinCountMany: "{count} 个固定窗口",
    ]
}
