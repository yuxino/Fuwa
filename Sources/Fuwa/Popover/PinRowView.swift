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
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    windowDetails.frame(minWidth: compact ? 110 : 160, maxWidth: .infinity)
                    actions
                }
                VStack(alignment: .leading, spacing: 8) {
                    windowDetails
                    HStack { Spacer(minLength: 0); actions }
                }
            }
            if let message = pin.errorMessage, !message.isEmpty {
                Text(message)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(stateIsFailure ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, detailsIndent)
            }
        }
        .padding(.vertical, compact ? 10 : 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(pin.applicationName), \(pin.windowTitle), \(pin.stateTitle(copy))")
    }

    private var windowDetails: some View {
        HStack(spacing: 10) {
            FuwaApplicationIcon(
                bundleIdentifier: pin.bundleIdentifier,
                applicationName: pin.applicationName,
                size: compact ? 24 : 28
            )
            VStack(alignment: .leading, spacing: 4) {
                Button { model.showControls(pin.id) } label: {
                    Text(pin.windowTitle)
                        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FuwaRowButtonStyle())
                .fuwaLinkCursor()
                .disabled(!pin.canShowControls)
                .accessibilityHint(copy.text(.showControls))
                .font(compact ? .caption.weight(.medium) : .callout.weight(.medium))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                .truncationMode(.middle)
                .help("\(copy.text(.showControls)): \(pin.windowTitle)")
                Text(pin.windowTitle == pin.applicationName
                     ? pin.stateTitle(copy)
                     : "\(pin.applicationName) · \(pin.stateTitle(copy))")
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(stateIsFailure ? Color.red : Color.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            PinPlaybackButton(model: model, pin: pin)
            FuwaIconButton(symbol: "pin.slash", label: copy.text(.unpin), isBusy: isBusy) {
                model.unpin(pin.id)
            }
            .disabled(isBusy)
            .help("\(copy.text(.unpin)) · \(copy.text(.removeExplanation))")
        }
        .fixedSize()
    }

    private var stateIsFailure: Bool {
        if case .failed = pin.state { return true }
        return false
    }
}
