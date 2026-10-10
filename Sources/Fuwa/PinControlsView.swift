import AppKit
import SwiftUI
import FuwaCore

extension PinSnapshot {
    var canShowControls: Bool {
        switch state {
        case .live, .frozen: true
        default: false
        }
    }

    var stateColor: Color {
        if isAwaitingFreshFrame { return FuwaAppearance.secondaryText }
        return switch state {
        case .live: FuwaAppearance.success
        case .frozen(.sourceClosed), .frozen(.captureInterrupted): FuwaAppearance.warning
        case .failed: FuwaAppearance.error
        default: FuwaAppearance.secondaryText
        }
    }

    func statusTitle(_ copy: FuwaCopy) -> String {
        var parts = [stateTitle(copy)]
        if isHidden { parts.append(copy.text(.hidden)) }
        if state == .live, !isAwaitingFreshFrame, options.notifiesWhenIdle, isIdle { parts.append(copy.text(.pictureIdle)) }
        return parts.joined(separator: " · ")
    }

    func statusText(_ copy: FuwaCopy) -> Text {
        var text = Text(stateTitle(copy)).foregroundColor(stateColor)
        if isHidden { text = text + Text(" · \(copy.text(.hidden))").foregroundColor(FuwaAppearance.secondaryText) }
        if state == .live, !isAwaitingFreshFrame, options.notifiesWhenIdle, isIdle {
            text = text + Text(" · \(copy.text(.pictureIdle))").foregroundColor(FuwaAppearance.secondaryText)
        }
        return text
    }

    func stateTitle(_ copy: FuwaCopy) -> String {
        switch state {
        case .resolving: copy.text(.resolving)
        case .starting: copy.text(.starting)
        case .live: copy.text(isAwaitingFreshFrame ? .restoringPicture : .live)
        case .frozen(.manual): copy.text(.frozen)
        case .frozen(.sourceClosed): copy.text(.sourceClosed)
        case .frozen(.captureInterrupted): copy.text(.captureInterrupted)
        case .failed: copy.text(.failed)
        case .stopping, .stopped: copy.text(.stopping)
        }
    }
}

@MainActor
struct PinPlaybackButton: View {
    @ObservedObject var model: AppModel
    let pin: PinSnapshot

    var body: some View {
        if pin.canFreeze || pin.canResume {
            Button {
                if pin.canFreeze { model.freeze(pin.id) } else { model.resume(pin.id) }
            } label: {
                Label(model.copy.text(pin.canFreeze ? .freeze : .resume),
                      systemImage: pin.canFreeze ? "pause" : "play")
                    .fixedSize()
            }
            .font(.caption)
            .buttonStyle(FuwaQuietButtonStyle(focusColor: FuwaAppearance.ink.opacity(0.4)))
            .disabled(model.busyPinIDs.contains(pin.id) || model.isClearingAll || pin.isAwaitingFreshFrame)
            .help(model.copy.text(pin.canFreeze ? .freezeNote : .resumeNote))
            .accessibilityHint(model.copy.text(pin.canFreeze ? .freezeNote : .resumeNote))
        }
    }
}

@MainActor
struct PinControlsView: View {
    @ObservedObject var model: AppModel
    let pinID: UUID
    var maximumHeight: CGFloat = 460
    var onHeightChanged: (CGFloat) -> Void = { _ in }
    var onDismiss: () -> Void = {}
    @State private var section: PinOptionsSection
    @State private var headerHeight: CGFloat = 48
    @State private var footerHeight: CGFloat = 28
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, pinID: UUID, maximumHeight: CGFloat = 460,
         initialSection: PinOptionsSection = .picture,
         onHeightChanged: @escaping (CGFloat) -> Void = { _ in },
         onDismiss: @escaping () -> Void = {}) {
        self.model = model
        self.pinID = pinID
        self.maximumHeight = maximumHeight
        self.onHeightChanged = onHeightChanged
        self.onDismiss = onDismiss
        _section = State(initialValue: initialSection)
    }

    var body: some View {
        if let pin = model.pins.first(where: { $0.id == pinID }) {
            VStack(alignment: .leading, spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 10) {
                        windowDetails(pin)
                        PinPlaybackButton(model: model, pin: pin)
                        dismissButton
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            windowDetails(pin)
                            dismissButton
                        }
                        PinPlaybackButton(model: model, pin: pin)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                Divider().opacity(0.5).padding(.vertical, 12)
                PinReferenceOptionsView(model: model, pin: pin, section: $section,
                    maximumHeight: max(24, maximumHeight - headerHeight - footerHeight - 74))
                Divider().opacity(0.5).padding(.top, 12)
                HStack {
                    Button { model.unpin(pin.id) } label: {
                        Label(model.copy.text(.unpin), systemImage: "pin.slash")
                    }
                    .buttonStyle(FuwaPlainButtonStyle())
                    .fuwaLinkCursor()
                    .disabled(model.busyPinIDs.contains(pin.id) || model.isClearingAll)
                    .help(model.copy.text(.removeExplanation))
                    .accessibilityHint(model.copy.text(.removeExplanation))
                    Spacer(minLength: 0)
                }
                .padding(.top, 8)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 - 8 }
            }
            .padding(14)
            .frame(maxHeight: maximumHeight, alignment: .top)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChanged($0) }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(FuwaAppearance.border, lineWidth: 1))
            .fuwaLightSurface()
            .accessibilityElement(children: .contain)
        }
    }

    private var dismissButton: some View {
        Button {
            onDismiss()
            dismiss()
        } label: {
            Image(systemName: "xmark").font(.caption.weight(.medium))
        }
        .buttonStyle(FuwaPlainButtonStyle())
        .fuwaLinkCursor()
        .accessibilityLabel(model.copy.text(.closeControls))
        .help(model.copy.text(.closeControls))
    }

    private func windowDetails(_ pin: PinSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pin.windowTitle).font(.callout.weight(.semibold))
                .lineLimit(1).truncationMode(.middle)
                .help(pin.windowTitle)
            HStack(spacing: 6) {
                if pin.applicationName != pin.windowTitle {
                    Text(pin.applicationName)
                        .font(.caption2).foregroundStyle(FuwaAppearance.secondaryText)
                        .lineLimit(1).truncationMode(.middle)
                }
                pinStatus(pin)
                if model.busyPinIDs.contains(pin.id) || pin.isAwaitingFreshFrame {
                    ProgressView().controlSize(.mini)
                        .accessibilityLabel(model.copy.text(.restoringPicture))
                }
            }
        }
        .frame(minWidth: 80, maxWidth: .infinity, alignment: .leading)
    }
    private func pinStatus(_ pin: PinSnapshot) -> some View {
        pin.statusText(model.copy)
            .font(.caption2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(pin.statusTitle(model.copy))
    }
}

/// Borderless controls still need keyboard focus for Tab/Space and VoiceOver.
final class PinControlsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        // A transient help popover can briefly own key focus. Keep its anchor alive.
        if FuwaHelpButton.openHelp(in: contentView) == nil { dismissControls() }
    }

    override func cancelOperation(_ sender: Any?) {
        if let button = FuwaHelpButton.openHelp(in: contentView) {
            button.closeHelp()
            makeKey()
            makeFirstResponder(button)
        } else {
            dismissControls()
        }
    }

    func finishHelpInteraction() {
        if !isKeyWindow { dismissControls() }
    }

    private func dismissControls() {
        parent?.removeChildWindow(self)
        orderOut(nil)
    }
}
