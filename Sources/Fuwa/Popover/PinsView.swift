import SwiftUI

@MainActor
struct PinsView: View {
    @ObservedObject var model: AppModel
    var showsPinAction = true
    @FocusState private var pinButtonFocused: Bool
    @ScaledMetric(relativeTo: .body) private var rowDividerIndent = 52

    private var copy: FuwaCopy { model.copy }

    var body: some View {
        VStack(spacing: 0) {
            if showsPinAction {
                pinButton
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }

            if !model.pins.isEmpty {
                pinsList
            } else {
                emptyState
            }
        }
        .onAppear {
            pinButtonFocused = true
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !showsPinAction {
            VStack(spacing: 16) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 42, weight: .ultraLight))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(copy.text(.emptyTitle)).font(.title3.weight(.semibold))
                    .help(copy.text(.noPinsBody))
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text(copy.text(.emptyTitle))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .help(copy.text(.noPinsBody))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
        }
    }

    private var pinButton: some View {
        Button(action: model.pinFrontWindow) {
            HStack(spacing: 7) {
                if model.isPinningFrontWindow {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color(nsColor: .windowBackgroundColor))
                } else {
                    Image(systemName: "pin")
                        .accessibilityHidden(true)
                }

                Text(pinButtonTitle)

                Spacer(minLength: 8)

                Text(model.shortcut.displayString)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .opacity(model.shortcutIsActive ? 0.72 : 0.35)
            }
        }
        .buttonStyle(FuwaPrimaryButtonStyle(compact: true))
        .disabled(model.isPinningFrontWindow || model.isClearingAll)
        .focused($pinButtonFocused)
        .help(pinButtonHint)
        .accessibilityLabel(pinButtonTitle)
        .accessibilityValue(
            model.shortcutIsActive
                ? model.shortcut.displayString
                : copy.text(.shortcutInactive)
        )
        .accessibilityHint(pinButtonHint)
    }

    private var pinsList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(copy.text(.pins))
                    .font(.caption.weight(.medium))
                Spacer()
                Text(showsPinAction ? String(model.pins.count) : copy.pinsCount(model.pins.count))
                    .accessibilityLabel(copy.pinsCount(model.pins.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, showsPinAction ? 12 : 16)
            .padding(.vertical, showsPinAction ? 5 : 8)

            Divider().opacity(0.5)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.pins.enumerated()), id: \.element.id) { index, pin in
                        PinRowView(model: model, pin: pin, compact: showsPinAction)
                            .padding(.horizontal, showsPinAction ? 12 : 16)

                        if index < model.pins.count - 1 {
                            Divider().opacity(0.5)
                                .padding(.leading, showsPinAction ? rowDividerIndent - 10 : rowDividerIndent)
                        }
                    }
                }
            }
            .scrollIndicators(.automatic)
        }
    }

    private var pinButtonTitle: String {
        model.isPinningFrontWindow ? copy.text(.pinning) : copy.text(.pinFrontWindow)
    }

    private var pinButtonHint: String {
        model.shortcutIsActive ? copy.text(.noPinsBody) : copy.text(.shortcutInactive)
    }
}
