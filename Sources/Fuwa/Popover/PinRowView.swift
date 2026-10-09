import FuwaCore
import SwiftUI

@MainActor
struct PinRowView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var detailsIndent = 36
    let pin: PinSnapshot

    private var copy: FuwaCopy { model.copy }
    private var isBusy: Bool { model.busyPinIDs.contains(pin.id) || model.isClearingAll }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    windowDetails.frame(minWidth: 160, maxWidth: .infinity)
                    actions
                }
                VStack(alignment: .leading, spacing: 8) {
                    windowDetails
                    HStack { Spacer(minLength: 0); actions }
                }
            }
            if let message = pin.errorMessage, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(pin.stateColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, detailsIndent)
            }
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(pin.applicationName), \(pin.windowTitle), \(pin.stateTitle(copy))")
    }

    private var windowDetails: some View {
        HStack(spacing: 10) {
            FuwaApplicationIcon(
                bundleIdentifier: pin.bundleIdentifier,
                applicationName: pin.applicationName,
                size: 28
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
                .font(.callout.weight(.medium))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                .truncationMode(.middle)
                .help("\(copy.text(.showControls)): \(pin.windowTitle)")
                (Text(pin.windowTitle == pin.applicationName ? "" : "\(pin.applicationName) · ")
                    .foregroundColor(FuwaAppearance.secondaryText)
                 + Text(pin.stateTitle(copy)).foregroundColor(pin.stateColor))
                    .font(.caption)
                    .foregroundStyle(pin.stateColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            PinPlaybackButton(model: model, pin: pin)
            FuwaIconButton(symbol: "gearshape", label: copy.text(.captureQuality), isBusy: isBusy) {
                model.showControls(pin.id)
            }
            .disabled(!pin.canShowControls || isBusy)
            .help(copy.text(.captureQualityNote))
            .accessibilityHint(copy.text(.captureQualityNote))
            FuwaIconButton(symbol: "pin.slash", label: copy.text(.unpin), isBusy: isBusy) {
                model.unpin(pin.id)
            }
            .disabled(isBusy)
            .help("\(copy.text(.unpin)) · \(copy.text(.removeExplanation))")
        }
        .fixedSize()
    }

}
