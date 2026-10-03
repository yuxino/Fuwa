import FuwaCore
import SwiftUI

@MainActor
struct PinRowView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var detailsIndent = 36
    let pin: PinSnapshot
    var compact = false

    private var copy: FuwaCopy { model.copy }
    private var isBusy: Bool { model.busyPinIDs.contains(pin.id) || model.isClearingAll }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: compact ? 8 : 10) {
                FuwaApplicationIcon(
                    bundleIdentifier: pin.bundleIdentifier,
                    applicationName: pin.applicationName,
                    size: compact ? 22 : 26
                )

                VStack(alignment: .leading, spacing: compact ? 1 : 3) {
                    Button { model.showControls(pin.id) } label: {
                        Text(pin.windowTitle)
                            .frame(maxWidth: .infinity, minHeight: compact ? 18 : 22, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(FuwaRowButtonStyle())
                    .fuwaLinkCursor()
                    .disabled(!pin.canShowControls)
                    .accessibilityHint(copy.text(.showControls))
                    .font(compact ? .caption.weight(.medium) : .callout.weight(.medium))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .truncationMode(.middle)
                    .help("\(copy.text(.showControls)): \(pin.windowTitle)")

                    HStack(spacing: 5) {
                        if pin.windowTitle != pin.applicationName {
                            Text(pin.applicationName)
                            Text("·").accessibilityHidden(true)
                        }
                        Text(pin.stateTitle(copy))
                    }
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(stateIsFailure ? Color.red : Color.secondary)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                FuwaIconButton(
                    symbol: "pin.slash",
                    label: copy.text(.unpin),
                    isBusy: isBusy
                ) { model.unpin(pin.id) }
                .disabled(isBusy)
                .help("\(copy.text(.unpin)) · \(copy.text(.removeExplanation))")
            }

            if pin.canFreeze || pin.canResume || pin.canUseSource {
                HStack(spacing: 6) {
                    if pin.canFreeze || pin.canResume {
                        Button {
                            if pin.canFreeze { model.freeze(pin.id) } else { model.resume(pin.id) }
                        } label: {
                            Label(copy.text(pin.canFreeze ? .freeze : .resume),
                                  systemImage: pin.canFreeze ? "pause" : "play")
                        }
                    }
                    if pin.canUseSource {
                        Button { model.revealSource(pin.id) } label: {
                            Label(copy.text(.revealSource), systemImage: "arrow.up.forward.app")
                        }
                    }
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .buttonStyle(FuwaPlainButtonStyle())
                .disabled(isBusy)
                .padding(.leading, detailsIndent - (compact ? 12 : 6))
            }

            if let detailMessage {
                Text(detailMessage)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(stateIsFailure ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, detailsIndent - (compact ? 6 : 0))
            }
        }
        .padding(.vertical, compact ? 6 : 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(pin.applicationName), \(pin.windowTitle), \(pin.stateTitle(copy))")
    }

    private var stateIsFailure: Bool {
        if case .failed = pin.state { return true }
        return false
    }

    private var detailMessage: String? {
        if let errorMessage = pin.errorMessage, !errorMessage.isEmpty { return errorMessage }
        if case .unavailable(let message) = model.interactionStates[pin.id] { return message }
        return nil
    }
}
