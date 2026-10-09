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
                Text(copy.text(.emptyTitle)).font(.title3.weight(.semibold))
                    .help(copy.text(.noPinsBody))
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text(copy.text(.pins)).font(.caption.weight(.medium))
                    Spacer()
                    Text(copy.pinsCount(model.pins.count))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
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
