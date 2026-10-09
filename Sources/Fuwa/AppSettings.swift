import Foundation
import FuwaCore
import ServiceManagement

@MainActor
final class AppSettingsStore {
    private enum Key {
        static let language = "language"
        static let shortcut = "shortcut"
        static let didRequestScreenRecording = "didRequestScreenRecording"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var language: FuwaLanguagePreference {
        get { FuwaLanguagePreference(rawValue: defaults.string(forKey: Key.language) ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Key.language) }
    }

    var shortcut: KeyboardShortcut {
        get {
            guard
                let data = defaults.data(forKey: Key.shortcut),
                let shortcut = try? decoder.decode(KeyboardShortcut.self, from: data),
                shortcut.validationError == nil
            else {
                return .defaultPin
            }
            return shortcut
        }
        set {
            guard newValue.validationError == nil,
                  let data = try? encoder.encode(newValue) else {
                return
            }
            defaults.set(data, forKey: Key.shortcut)
        }
    }

    var didRequestScreenRecording: Bool {
        get { defaults.bool(forKey: Key.didRequestScreenRecording) }
        set { defaults.set(newValue, forKey: Key.didRequestScreenRecording) }
    }
}

enum LaunchAtLoginError: LocalizedError {
    case requiresApproval
    case serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .requiresApproval:
            "macOS needs you to approve Fuwa in System Settings → General → Login Items."
        case .serviceUnavailable:
            "Launch at Login is unavailable for this copy of Fuwa. Move Fuwa to Applications and try again."
        }
    }
}

enum FuwaLaunchAtLoginState: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

@MainActor
final class LaunchAtLoginController {
    var state: FuwaLaunchAtLoginState {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            .disabled
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .unavailable
        @unknown default:
            .unavailable
        }
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) throws -> FuwaLaunchAtLoginState {
        let service = SMAppService.mainApp
        if enabled {
            switch service.status {
            case .enabled:
                return .enabled
            case .requiresApproval:
                return .requiresApproval
            case .notFound:
                throw LaunchAtLoginError.serviceUnavailable
            case .notRegistered:
                try service.register()
            @unknown default:
                throw LaunchAtLoginError.serviceUnavailable
            }
        } else {
            switch service.status {
            case .notRegistered:
                return .disabled
            case .notFound:
                throw LaunchAtLoginError.serviceUnavailable
            case .enabled, .requiresApproval:
                try service.unregister()
            @unknown default:
                throw LaunchAtLoginError.serviceUnavailable
            }
        }

        let refreshedState = state
        if refreshedState == .unavailable {
            throw LaunchAtLoginError.serviceUnavailable
        }
        return refreshedState
    }

    func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
