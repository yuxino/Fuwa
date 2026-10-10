import Foundation

extension FuwaCopy {
    static func settingsInteractionTranslations(_ language: FuwaLanguage) -> [FuwaString: String] {
        switch language {
        case .english: [
            .keyboardShortcuts: "Keyboard Shortcuts",
            .startupAndDock: "Startup & Dock"
        ]
        case .simplifiedChinese: [
            .keyboardShortcuts: "快捷键",
            .startupAndDock: "启动与 Dock"
        ]
        case .traditionalChinese: [
            .keyboardShortcuts: "快捷鍵",
            .startupAndDock: "啟動與 Dock"
        ]
        case .japanese: [
            .keyboardShortcuts: "キーボードショートカット",
            .startupAndDock: "起動と Dock"
        ]
        case .korean: [
            .keyboardShortcuts: "키보드 단축키",
            .startupAndDock: "시작 및 Dock"
        ]
        case .french: [
            .keyboardShortcuts: "Raccourcis clavier",
            .startupAndDock: "Démarrage et Dock"
        ]
        case .german: [
            .keyboardShortcuts: "Tastaturkurzbefehle",
            .startupAndDock: "Start und Dock"
        ]
        }
    }
}
