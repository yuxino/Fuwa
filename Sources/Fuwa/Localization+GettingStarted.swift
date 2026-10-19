import FuwaCore

extension FuwaCopy {
    func arrangementTitle(_ corner: ReferenceArrangementCorner) -> String {
        let key: FuwaString = switch corner {
        case .topLeft: .arrangeTopLeft
        case .topRight: .arrangeTopRight
        case .bottomLeft: .arrangeBottomLeft
        case .bottomRight: .arrangeBottomRight
        }
        return text(key)
    }

    static func gettingStartedTranslations(_ language: FuwaLanguage) -> [FuwaString: String] {
        switch language {
        case .english: [
            .allowScreenRecording: "Allow Screen Recording",
            .gettingStarted: "Getting Started", .guideTitle: "Keep what matters in view.",
            .guideIntroduction: "Choose a window, then decide how it stays with you.",
            .guidePermissionTitle: "Allow the picture",
            .guidePermissionBody: "Enable Screen Recording for Fuwa in System Settings. Pictures stay on your Mac; Accessibility permission is not needed.",
            .guideChooseTitle: "Choose a window",
            .guideChooseBody: "Pick a window from the list, or use the shortcut while it is in front. The floating picture initially follows the original.",
            .guideReferenceTitle: "Make room for your work",
            .guideReferenceBody: "Open floating controls → Picture → Reference Window to move and resize it freely. Choose Area keeps just the part you need. Double-click a reference to return to its app.",
            .guideDone: "Go to My Windows", .guideLater: "Set Up Later",
            .guideReturnHint: "You can reopen this guide from the sidebar at any time.",
            .arrangeReferences: "Arrange References", .arrangeTopLeft: "Top Left", .arrangeTopRight: "Top Right",
            .arrangeBottomLeft: "Bottom Left", .arrangeBottomRight: "Bottom Right"
        ]
        case .simplifiedChinese: [
            .allowScreenRecording: "允许屏幕录制",
            .gettingStarted: "使用指南", .guideTitle: "把需要的画面留在眼前。",
            .guideIntroduction: "选一个窗口，再决定怎么看。",
            .guidePermissionTitle: "允许显示画面",
            .guidePermissionBody: "在系统设置中为 Fuwa 开启屏幕录制。画面只留在这台 Mac 上，无需辅助功能权限。",
            .guideChooseTitle: "选一个窗口",
            .guideChooseBody: "从列表中选择，或在目标窗口位于前台时按快捷键。新画面默认跟随原窗口的位置。",
            .guideReferenceTitle: "给工作腾出空间",
            .guideReferenceBody: "打开浮窗控制 → 画面 → 独立参考窗，即可自由移动和缩放。「选择区域」能只保留需要的部分。双击参考窗可回到来源应用。",
            .guideDone: "进入窗口列表", .guideLater: "稍后设置",
            .guideReturnHint: "随时可以从侧栏重新打开使用指南。",
            .arrangeReferences: "整理参考窗", .arrangeTopLeft: "左上角", .arrangeTopRight: "右上角",
            .arrangeBottomLeft: "左下角", .arrangeBottomRight: "右下角"
        ]
        case .traditionalChinese: [
            .allowScreenRecording: "允許螢幕錄製",
            .gettingStarted: "使用指南", .guideTitle: "把需要的畫面留在眼前。",
            .guideIntroduction: "選一個視窗，再決定怎麼看。",
            .guidePermissionTitle: "允許顯示畫面",
            .guidePermissionBody: "在系統設定中為 Fuwa 開啟螢幕錄製。畫面只留在這台 Mac 上，無需輔助使用權限。",
            .guideChooseTitle: "選一個視窗",
            .guideChooseBody: "從清單中選擇，或在目標視窗位於前景時按快捷鍵。新畫面預設跟隨原視窗的位置。",
            .guideReferenceTitle: "為工作騰出空間",
            .guideReferenceBody: "開啟浮窗控制 → 畫面 → 獨立參考視窗，即可自由移動和縮放。「選擇區域」能只保留需要的部分。按兩下參考視窗可回到來源應用程式。",
            .guideDone: "進入視窗清單", .guideLater: "稍後設定",
            .guideReturnHint: "隨時可以從側邊欄重新開啟使用指南。",
            .arrangeReferences: "整理參考視窗", .arrangeTopLeft: "左上角", .arrangeTopRight: "右上角",
            .arrangeBottomLeft: "左下角", .arrangeBottomRight: "右下角"
        ]
        case .japanese: [
            .allowScreenRecording: "画面収録を許可",
            .gettingStarted: "使い方", .guideTitle: "見たい画面を、手元に。",
            .guideIntroduction: "ウィンドウを選んで、見やすい表示に。",
            .guidePermissionTitle: "画面の表示を許可",
            .guidePermissionBody: "システム設定で Fuwa の画面収録を許可します。映像はこの Mac 内だけで扱われ、アクセシビリティ権限は不要です。",
            .guideChooseTitle: "ウィンドウを選ぶ",
            .guideChooseBody: "一覧から選ぶか、対象のウィンドウが最前面のときにショートカットを押します。最初は元のウィンドウの位置に追従します。",
            .guideReferenceTitle: "作業のために場所を空ける",
            .guideReferenceBody: "フローティング操作 → 映像 → 独立した参考ウィンドウで、自由に移動・拡大縮小できます。「範囲を選択」で必要な部分だけ表示。ダブルクリックで元のアプリに戻れます。",
            .guideDone: "ウィンドウ一覧へ", .guideLater: "後で設定",
            .guideReturnHint: "使い方はサイドバーからいつでも開けます。",
            .arrangeReferences: "参考ウィンドウを整列", .arrangeTopLeft: "左上", .arrangeTopRight: "右上",
            .arrangeBottomLeft: "左下", .arrangeBottomRight: "右下"
        ]
        case .korean: [
            .allowScreenRecording: "화면 기록 허용",
            .gettingStarted: "사용 안내", .guideTitle: "필요한 화면을 곁에 두세요.",
            .guideIntroduction: "창을 선택한 다음 보기 방식을 정하세요.",
            .guidePermissionTitle: "화면 표시 허용",
            .guidePermissionBody: "시스템 설정에서 Fuwa의 화면 기록을 허용하세요. 화면은 이 Mac 안에서만 처리되며 손쉬운 사용 권한은 필요하지 않습니다.",
            .guideChooseTitle: "창 선택",
            .guideChooseBody: "목록에서 선택하거나 대상 창이 맨 앞에 있을 때 단축키를 누르세요. 처음에는 원래 창의 위치를 따라갑니다.",
            .guideReferenceTitle: "작업 공간 확보",
            .guideReferenceBody: "플로팅 제어 → 화면 → 독립 참고 창에서 자유롭게 이동하고 크기를 바꿀 수 있습니다. ‘영역 선택’으로 필요한 부분만 남기세요. 두 번 클릭하면 원본 앱으로 돌아갑니다.",
            .guideDone: "창 목록으로", .guideLater: "나중에 설정",
            .guideReturnHint: "언제든 사이드바에서 사용 안내를 다시 열 수 있습니다.",
            .arrangeReferences: "참고 창 정렬", .arrangeTopLeft: "왼쪽 위", .arrangeTopRight: "오른쪽 위",
            .arrangeBottomLeft: "왼쪽 아래", .arrangeBottomRight: "오른쪽 아래"
        ]
        case .french: [
            .allowScreenRecording: "Autoriser l’enregistrement de l’écran",
            .gettingStarted: "Premiers pas", .guideTitle: "Gardez l’essentiel en vue.",
            .guideIntroduction: "Choisissez une fenêtre, puis sa façon de vous accompagner.",
            .guidePermissionTitle: "Autoriser l’affichage",
            .guidePermissionBody: "Autorisez l’enregistrement de l’écran pour Fuwa dans Réglages Système. Les images restent sur ce Mac, sans autorisation d’accessibilité.",
            .guideChooseTitle: "Choisir une fenêtre",
            .guideChooseBody: "Choisissez dans la liste ou utilisez le raccourci quand la fenêtre est au premier plan. L’image suit d’abord la position de l’original.",
            .guideReferenceTitle: "Faire de la place",
            .guideReferenceBody: "Commandes flottantes → Image → Fenêtre de référence permet de déplacer et redimensionner l’image. « Choisir une zone » garde la partie utile. Double-cliquez pour revenir à l’app source.",
            .guideDone: "Voir mes fenêtres", .guideLater: "Configurer plus tard",
            .guideReturnHint: "Ce guide reste accessible dans la barre latérale.",
            .arrangeReferences: "Ranger les références", .arrangeTopLeft: "En haut à gauche", .arrangeTopRight: "En haut à droite",
            .arrangeBottomLeft: "En bas à gauche", .arrangeBottomRight: "En bas à droite"
        ]
        case .german: [
            .allowScreenRecording: "Bildschirmaufnahme erlauben",
            .gettingStarted: "Erste Schritte", .guideTitle: "Das Wichtige im Blick.",
            .guideIntroduction: "Wählen Sie ein Fenster und die passende Darstellung.",
            .guidePermissionTitle: "Bildanzeige erlauben",
            .guidePermissionBody: "Erlauben Sie Fuwa die Bildschirmaufnahme in den Systemeinstellungen. Bilder bleiben auf diesem Mac; Bedienungshilfen sind nicht erforderlich.",
            .guideChooseTitle: "Ein Fenster auswählen",
            .guideChooseBody: "Wählen Sie aus der Liste oder drücken Sie den Kurzbefehl, wenn das Fenster im Vordergrund ist. Das Bild folgt zunächst der Position des Originals.",
            .guideReferenceTitle: "Platz zum Arbeiten",
            .guideReferenceBody: "Schwebende Steuerelemente → Bild → Referenzfenster erlaubt freies Verschieben und Skalieren. „Bereich wählen“ zeigt nur den benötigten Teil. Ein Doppelklick öffnet die Quell-App.",
            .guideDone: "Zu meinen Fenstern", .guideLater: "Später einrichten",
            .guideReturnHint: "Diese Anleitung ist jederzeit über die Seitenleiste erreichbar.",
            .arrangeReferences: "Referenzen anordnen", .arrangeTopLeft: "Oben links", .arrangeTopRight: "Oben rechts",
            .arrangeBottomLeft: "Unten links", .arrangeBottomRight: "Unten rechts"
        ]
        }
    }
}
