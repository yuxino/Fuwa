import AppKit
import SwiftUI

@MainActor
struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var choosingWindow = false
    @State private var settingsSelected = false
    private var copy: FuwaCopy { model.copy }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 30, height: 30)
                        .accessibilityHidden(true)
                    Text("Fuwa").font(.system(size: 18, weight: .semibold))
                }
                VStack(spacing: 4) {
                    navigation(copy.text(.pins), symbol: "pin", selected: !settingsSelected) {
                        settingsSelected = false
                    }
                    navigation(copy.text(.settings), symbol: "gearshape", selected: settingsSelected) {
                        settingsSelected = true
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    Text(copy.pinsCount(model.pins.count))
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(copy.text(.version)) \(model.version)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 22)
            .frame(width: 164)
            .frame(maxHeight: .infinity)
            .background(FuwaAppearance.sidebar)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(copy.text(settingsSelected ? .settings : .manageWindows))
                            .font(.system(size: 18, weight: .semibold))
                        Spacer()
                        if !settingsSelected {
                            Button { choosingWindow = true } label: {
                                Label(copy.text(.chooseWindow), systemImage: "plus")
                            }
                            .buttonStyle(FuwaPrimaryButtonStyle(expands: false))
                            .keyboardShortcut("o", modifiers: .command)
                            .disabled(model.isPinningFrontWindow || model.isClearingAll)
                        }
                    }
                    if !settingsSelected {
                        Text(copy.text(.noPinsBody))
                            .font(.callout).foregroundStyle(.secondary)
                        Text(model.shortcutIsActive ? model.shortcut.displayString : copy.text(.shortcutInactive))
                            .font(.system(.callout, design: .monospaced).weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(FuwaAppearance.sidebar, in: RoundedRectangle(cornerRadius: 6))
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                if let notice = model.notice {
                    FuwaNoticeView(notice: notice, copy: copy, onDismiss: model.dismissNotice)
                        .padding(.horizontal, 24).padding(.bottom, 16)
                }
                Divider()
                if settingsSelected {
                    SettingsView(model: model)
                } else {
                    PinsView(model: model, showsPinAction: false)
                    Spacer(minLength: 0)
                    Divider()
                    HStack {
                        Text(copy.text(.removeExplanation))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(copy.text(.clearAll), action: model.clearAll)
                            .buttonStyle(FuwaQuietButtonStyle())
                            .disabled(model.pins.isEmpty || model.isClearingAll)
                    }
                    .padding(16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .fuwaLightSurface()
        .sheet(isPresented: $choosingWindow) { WindowPickerView(model: model) }
    }

    private func navigation(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .frame(width: 18)
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(FuwaNavigationButtonStyle(selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct FuwaNavigationButtonStyle: ButtonStyle {
    let selected: Bool
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primary)
            .background(
                Color.black.opacity(configuration.isPressed ? 0.10 : isHovered ? 0.075 : selected ? 0.055 : 0),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .modifier(FuwaKeyboardFocus(cornerRadius: 7))
            .onHover { isHovered = $0 }
    }
}
