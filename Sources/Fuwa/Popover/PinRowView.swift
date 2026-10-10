import AppKit
import FuwaCore
import SwiftUI

@MainActor
struct PinRowView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var detailsIndent = 36
    let pin: PinSnapshot
    @State private var isShowingOptions = false
    @State private var optionsScreenSize = NSScreen.main?.visibleFrame.size ?? CGSize(width: 420, height: 500)

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
        .accessibilityLabel("\(pin.applicationName), \(pin.windowTitle), \(pin.statusTitle(copy))")
        .background {
            PinOptionsScreenProbe { size in
                if optionsScreenSize != size { optionsScreenSize = size }
            }
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .popover(isPresented: $isShowingOptions, arrowEdge: .trailing) {
            let size = PinOptionsPopoverLayout.size(available: optionsScreenSize)
            PinControlsView(model: model, pinID: pin.id, maximumHeight: size.height)
                .frame(width: size.width)
        }
    }

    private var windowDetails: some View {
        HStack(spacing: 10) {
            FuwaApplicationIcon(
                bundleIdentifier: pin.bundleIdentifier,
                applicationName: pin.applicationName,
                size: 28
            )
            VStack(alignment: .leading, spacing: 4) {
                Button { isShowingOptions = true } label: {
                    Text(pin.windowTitle)
                        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FuwaRowButtonStyle())
                .fuwaLinkCursor()
                .disabled(!pin.canShowControls)
                .accessibilityHint(copy.text(.pinOptions))
                .font(.callout.weight(.medium))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                .truncationMode(.middle)
                .help("\(copy.text(.pinOptions)): \(pin.windowTitle)")
                (Text(pin.windowTitle == pin.applicationName ? "" : "\(pin.applicationName) · ")
                    .foregroundColor(FuwaAppearance.secondaryText)
                 + pin.statusText(copy))
                    .font(.caption)
                    .foregroundStyle(pin.stateColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            PinPlaybackButton(model: model, pin: pin)
            FuwaIconButton(symbol: "gearshape", label: copy.text(.pinOptions), isBusy: isBusy) {
                isShowingOptions = true
            }
            .disabled(!pin.canShowControls || isBusy)
            .help(copy.text(.pinOptionsNote))
            .accessibilityHint(copy.text(.pinOptionsNote))
            FuwaIconButton(symbol: "pin.slash", label: copy.text(.unpin), isBusy: isBusy) {
                model.unpin(pin.id)
            }
            .disabled(isBusy)
            .help("\(copy.text(.unpin)) · \(copy.text(.removeExplanation))")
        }
        .fixedSize()
    }

}

/// Leave room for the popover arrow and AppKit's screen-edge margins.
enum PinOptionsPopoverLayout {
    static let preferredWidth: CGFloat = 320

    static func size(available: CGSize) -> CGSize {
        guard available.width.isFinite, available.height.isFinite,
              available.width > 40, available.height > 40 else {
            return CGSize(width: preferredWidth, height: 460)
        }
        return CGSize(width: min(preferredWidth, available.width - 40), height: min(460, available.height - 40))
    }
}

@MainActor
private struct PinOptionsScreenProbe: NSViewRepresentable {
    let onScreenSize: (CGSize) -> Void

    func makeNSView(context: Context) -> PinOptionsScreenProbeView {
        let view = PinOptionsScreenProbeView()
        view.onScreenSize = onScreenSize
        return view
    }

    func updateNSView(_ view: PinOptionsScreenProbeView, context: Context) {
        view.onScreenSize = onScreenSize
        view.reportScreen()
    }
}

@MainActor
private final class PinOptionsScreenProbeView: NSView {
    var onScreenSize: ((CGSize) -> Void)?
    private var observations: [NSObjectProtocol] = []
    private var lastReportedSize: CGSize?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observations.forEach(NotificationCenter.default.removeObserver)
        observations.removeAll()
        guard let window else { return }
        for name in [NSWindow.didChangeScreenNotification, NSWindow.didMoveNotification,
                     NSApplication.didChangeScreenParametersNotification] {
            let object: Any? = name == NSApplication.didChangeScreenParametersNotification ? nil : window
            observations.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportScreen() }
            })
        }
        reportScreen()
    }

    func reportScreen() {
        guard let size = window?.screen?.visibleFrame.size, size != lastReportedSize else { return }
        lastReportedSize = size
        // SwiftUI may call updateNSView during a layout pass.
        Task { @MainActor [weak self] in self?.onScreenSize?(size) }
    }

    isolated deinit {
        observations.forEach(NotificationCenter.default.removeObserver)
    }
}
