import Foundation

extension FuwaCopy {
    static func pinInteractionTranslations(_ language: FuwaLanguage) -> [FuwaString: String] {
        switch language {
        case .english: [.captureArea: "Picture Area", .rechooseArea: "Choose Again"]
        case .simplifiedChinese: [.captureArea: "画面范围", .rechooseArea: "重新选择"]
        case .traditionalChinese: [.captureArea: "畫面範圍", .rechooseArea: "重新選擇"]
        case .japanese: [.captureArea: "表示範囲", .rechooseArea: "範囲を選び直す"]
        case .korean: [.captureArea: "표시 영역", .rechooseArea: "영역 다시 선택"]
        case .french: [.captureArea: "Zone affichée", .rechooseArea: "Choisir à nouveau"]
        case .german: [.captureArea: "Bildbereich", .rechooseArea: "Neu auswählen"]
        }
    }
}
