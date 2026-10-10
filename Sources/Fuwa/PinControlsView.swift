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
struct PinActionsView: View {
    @ObservedObject var model: AppModel
    let pin: PinSnapshot
    var compact = false
    private var busy: Bool { model.busyPinIDs.contains(pin.id) || model.isClearingAll }

    var body: some View {
        HStack(spacing: 8) {
            PinPlaybackButton(model: model, pin: pin)
            Spacer(minLength: 0)
            Button {
                model.unpin(pin.id)
            } label: {
                if compact {
                    Image(systemName: "pin.slash")
                } else {
                    Label(model.copy.text(.unpin), systemImage: "pin.slash")
                }
            }
            .help(model.copy.text(.removeExplanation))
            .accessibilityLabel(model.copy.text(.unpin))
            .disabled(busy)
        }
        .font(.caption)
        .buttonStyle(FuwaQuietButtonStyle())
    }
}

@MainActor
struct PinControlsView: View {
    @ObservedObject var model: AppModel
    let pinID: UUID
    var maximumHeight: CGFloat = 460
    var initialSection: PinOptionsSection = .picture
    var onHeightChanged: (CGFloat) -> Void = { _ in }
    var onDismiss: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let pin = model.pins.first(where: { $0.id == pinID }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pin.windowTitle).font(.caption.weight(.semibold))
                            .lineLimit(1).truncationMode(.middle)
                            .help(pin.windowTitle)
                        pinStatus(pin)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if model.busyPinIDs.contains(pin.id) || pin.isAwaitingFreshFrame {
                        ProgressView().controlSize(.mini)
                            .accessibilityLabel(model.copy.text(.restoringPicture))
                    }
                    Button {
                        onDismiss()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark").font(.caption.weight(.medium))
                    }
                    .buttonStyle(FuwaQuietButtonStyle())
                    .accessibilityLabel(model.copy.text(.closeControls))
                    .help(model.copy.text(.closeControls))
                }
                PinActionsView(model: model, pin: pin, compact: true)
                Divider().opacity(0.5).padding(.vertical, 4)
                PinReferenceOptionsView(model: model, pin: pin, initialSection: initialSection)
                    .frame(maxHeight: .infinity)
            }
            .padding(12)
            .frame(height: maximumHeight)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChanged($0) }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(FuwaAppearance.border, lineWidth: 1))
            .fuwaLightSurface()
            .accessibilityElement(children: .contain)
        }
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
        dismissControls()
    }

    override func cancelOperation(_ sender: Any?) {
        dismissControls()
    }

    private func dismissControls() {
        parent?.removeChildWindow(self)
        orderOut(nil)
    }
}
