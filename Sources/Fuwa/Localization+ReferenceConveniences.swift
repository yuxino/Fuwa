import Foundation

extension FuwaCopy {
    static func referenceConvenienceTranslations(_ language: FuwaLanguage) -> [FuwaString: String] {
        switch language {
        case .english: [
            .openSourceApplication: "Open Source App",
            .openSourceApplicationHelp: "Bring the app behind this picture to the front. If it has several windows, the app chooses which one appears.",
            .hoverPreview: "Enlarge on hover",
            .hoverPreviewHelp: "Point at the reference to see a larger, read-only preview. It follows the picture’s live or paused state. Move the pointer away to dismiss it.",
            .opacity: "Opacity",
            .opacityHelp: "Make this reference more transparent so you can see the work underneath. This does not change the original window or the enlarged preview.",
            .referenceSize: "Reference Size",
            .referenceSizeSmall: "Small", .referenceSizeMedium: "Medium", .referenceSizeLarge: "Large",
            .holdToHide: "Hold ⌃⌥ to hide pictures",
            .holdToHideNote: "Hold Control and Option together to hide all pictures temporarily. Release either key to restore their visibility. Other keyboard actions remain unchanged."
        ]
        case .simplifiedChinese: [
            .openSourceApplication: "打开来源应用",
            .openSourceApplicationHelp: "将这幅画面的来源应用切到前台。如果应用有多个窗口，由应用决定显示哪个窗口。",
            .hoverPreview: "悬停时放大预览",
            .hoverPreviewHelp: "将鼠标放在参考窗上，查看更大的只读预览。预览跟随画面的播放或暂停状态，移开鼠标即可收起。",
            .opacity: "不透明度",
            .opacityHelp: "降低参考窗的不透明度，便于查看下方的工作内容。不会改变原窗口或放大预览。",
            .referenceSize: "参考窗大小",
            .referenceSizeSmall: "小", .referenceSizeMedium: "中", .referenceSizeLarge: "大",
            .holdToHide: "按住 ⌃⌥ 暂时隐藏画面",
            .holdToHideNote: "同时按住 Control 和 Option 暂时隐藏所有画面，松开任一键后恢复原来的显示状态。不会拦截其他键盘操作。"
        ]
        case .traditionalChinese: [
            .openSourceApplication: "開啟來源應用程式",
            .openSourceApplicationHelp: "將這幅畫面的來源應用程式切到前景。如果有多個視窗，由應用程式決定顯示哪個視窗。",
            .hoverPreview: "停留時放大預覽",
            .hoverPreviewHelp: "將滑鼠停在參考視窗上，查看更大的唯讀預覽。預覽會跟隨畫面的播放或暫停狀態，移開滑鼠即可收起。",
            .opacity: "不透明度",
            .opacityHelp: "降低參考視窗的不透明度，以便查看下方的工作內容。不會改變原視窗或放大預覽。",
            .referenceSize: "參考視窗大小",
            .referenceSizeSmall: "小", .referenceSizeMedium: "中", .referenceSizeLarge: "大",
            .holdToHide: "按住 ⌃⌥ 暫時隱藏畫面",
            .holdToHideNote: "同時按住 Control 和 Option 暫時隱藏所有畫面，放開任一鍵後恢復原本的顯示狀態。不會攔截其他鍵盤操作。"
        ]
        case .japanese: [
            .openSourceApplication: "元のアプリを開く",
            .openSourceApplicationHelp: "この映像の元のアプリを最前面に表示します。複数のウィンドウがある場合、どれを表示するかはアプリが決めます。",
            .hoverPreview: "ポインタを重ねて拡大",
            .hoverPreviewHelp: "参考ウィンドウにポインタを重ねると、操作できない拡大プレビューを表示します。映像の再生・一時停止の状態に従います。ポインタを離すと閉じます。",
            .opacity: "不透明度",
            .opacityHelp: "参考ウィンドウを半透明にして、下の作業内容を見やすくします。元のウィンドウと拡大プレビューは変わりません。",
            .referenceSize: "参考ウィンドウのサイズ",
            .referenceSizeSmall: "小", .referenceSizeMedium: "中", .referenceSizeLarge: "大",
            .holdToHide: "⌃⌥ を押している間は映像を隠す",
            .holdToHideNote: "Control と Option を同時に押している間、すべての映像を一時的に隠します。どちらかを離すと元の表示状態に戻ります。ほかのキー操作は妨げません。"
        ]
        case .korean: [
            .openSourceApplication: "원본 앱 열기",
            .openSourceApplicationHelp: "이 화면의 원본 앱을 앞으로 가져옵니다. 창이 여러 개면 어떤 창을 표시할지는 앱에서 결정합니다.",
            .hoverPreview: "마우스를 올리면 확대",
            .hoverPreviewHelp: "참고 창에 마우스를 올리면 조작할 수 없는 확대 미리보기를 표시합니다. 화면의 재생 또는 일시 정지 상태를 따릅니다. 마우스를 떼면 닫힙니다.",
            .opacity: "불투명도",
            .opacityHelp: "참고 창을 반투명하게 하여 아래의 작업 내용을 볼 수 있게 합니다. 원래 창이나 확대 미리보기는 바뀌지 않습니다.",
            .referenceSize: "참고 창 크기",
            .referenceSizeSmall: "작게", .referenceSizeMedium: "중간", .referenceSizeLarge: "크게",
            .holdToHide: "⌃⌥를 누르는 동안 화면 숨기기",
            .holdToHideNote: "Control과 Option을 함께 누르면 모든 화면을 잠시 숨깁니다. 둘 중 하나를 놓으면 이전 표시 상태로 돌아갑니다. 다른 키보드 동작은 차단하지 않습니다."
        ]
        case .french: [
            .openSourceApplication: "Ouvrir l’app source",
            .openSourceApplicationHelp: "Place l’app à l’origine de cette image au premier plan. Si elle a plusieurs fenêtres, l’app choisit celle à afficher.",
            .hoverPreview: "Agrandir au survol",
            .hoverPreviewHelp: "Survolez la référence pour afficher un aperçu agrandi, sans interaction. Il suit l’état de lecture ou de pause de l’image. Éloignez le pointeur pour le fermer.",
            .opacity: "Opacité",
            .opacityHelp: "Rendez la référence plus transparente pour voir votre travail en dessous. La fenêtre d’origine et l’aperçu agrandi ne changent pas.",
            .referenceSize: "Taille de la référence",
            .referenceSizeSmall: "Petite", .referenceSizeMedium: "Moyenne", .referenceSizeLarge: "Grande",
            .holdToHide: "Maintenir ⌃⌥ pour masquer les images",
            .holdToHideNote: "Maintenez Contrôle et Option ensemble pour masquer temporairement toutes les images. Relâchez l’une des touches pour rétablir leur visibilité. Les autres actions du clavier restent disponibles."
        ]
        case .german: [
            .openSourceApplication: "Quell-App öffnen",
            .openSourceApplicationHelp: "Holt die App hinter diesem Bild in den Vordergrund. Bei mehreren Fenstern entscheidet die App, welches angezeigt wird.",
            .hoverPreview: "Beim Darüberfahren vergrößern",
            .hoverPreviewHelp: "Bewegen Sie den Mauszeiger über die Referenz, um eine größere Vorschau ohne Bedienung zu sehen. Sie folgt dem Live- oder Pausenzustand des Bildes. Bewegen Sie den Mauszeiger weg, um sie zu schließen.",
            .opacity: "Deckkraft",
            .opacityHelp: "Machen Sie die Referenz transparenter, um Ihre Arbeit darunter zu sehen. Das Originalfenster und die vergrößerte Vorschau bleiben unverändert.",
            .referenceSize: "Referenzgröße",
            .referenceSizeSmall: "Klein", .referenceSizeMedium: "Mittel", .referenceSizeLarge: "Groß",
            .holdToHide: "⌃⌥ gedrückt halten, um Bilder auszublenden",
            .holdToHideNote: "Halten Sie Control und Option gleichzeitig gedrückt, um alle Bilder vorübergehend auszublenden. Lassen Sie eine Taste los, um die vorherige Sichtbarkeit wiederherzustellen. Andere Tastaturaktionen bleiben unverändert."
        ]
        }
    }
}
