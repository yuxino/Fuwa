import SwiftUI

@MainActor
struct PinsView: View {
    @ObservedObject var model: AppModel
    @ScaledMetric(relativeTo: .body) private var rowDividerIndent = 52
    private var copy: FuwaCopy { model.copy }

    var body: some View {
        if model.pins.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 42, weight: .ultraLight))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text(copy.text(.emptyTitle)).font(.title3.weight(.semibold))
                    Text(copy.text(.noPinsBody)).font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(action: model.chooseWindow) {
                    Label(copy.text(.chooseWindow), systemImage: "plus")
                }
                .buttonStyle(FuwaPrimaryButtonStyle(expands: false))
                .keyboardShortcut("o", modifiers: .command)
                .disabled(model.isPinningFrontWindow || model.isClearingAll)
                Text(model.shortcutIsActive ? model.shortcut.displayString : copy.text(.shortcutInactive))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .help(copy.text(.shortcutNote))
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(copy.pinsCount(model.pins.count))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(action: model.togglePinsVisibility) {
                            Label(copy.text(model.arePinsHidden ? .showAllPins : .hideAllPins),
                                  systemImage: model.arePinsHidden ? "eye" : "eye.slash")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .buttonStyle(FuwaPlainButtonStyle())
                        .disabled(model.isClearingAll || model.isTogglingVisibility)
                        .help(copy.text(.visibilityShortcutNote))
                    }
                    if model.arePinsHidden {
                        Text(copy.text(.pinsHiddenNote)).font(.caption)
                            .foregroundStyle(FuwaAppearance.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 8)
                Divider().opacity(0.5)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.pins.enumerated()), id: \.element.id) { index, pin in
                            PinRowView(model: model, pin: pin).padding(.horizontal, 16)
                            if index < model.pins.count - 1 {
                                Divider().opacity(0.5).padding(.leading, rowDividerIndent)
                            }
                        }
                    }
                }
                .scrollIndicators(.automatic)
            }
        }
    }
}
