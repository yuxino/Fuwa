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
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
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
                Text(copy.text(.mirrorExplanation))
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label(copy.text(.emptyTitle), systemImage: "macwindow.on.rectangle")
                    .font(.headline)
                Text(copy.text(.noPinsBody))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(copy.text(.mirrorExplanation))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
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
                Text(copy.pinsCount(model.pins.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider().opacity(0.5)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.pins.enumerated()), id: \.element.id) { index, pin in
                        PinRowView(model: model, pin: pin)
                            .padding(.horizontal, 16)

                        if index < model.pins.count - 1 {
                            Divider().opacity(0.5)
                                .padding(.leading, rowDividerIndent)
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
