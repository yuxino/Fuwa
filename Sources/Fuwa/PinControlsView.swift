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
        switch state {
        case .live: FuwaAppearance.success
        case .frozen(.sourceClosed), .frozen(.captureInterrupted): FuwaAppearance.warning
        case .failed: FuwaAppearance.error
        default: FuwaAppearance.secondaryText
        }
    }

    func stateTitle(_ copy: FuwaCopy) -> String {
        switch state {
        case .resolving: copy.text(.resolving)
        case .starting: copy.text(.starting)
        case .live: copy.text(.live)
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
            .disabled(model.busyPinIDs.contains(pin.id) || model.isClearingAll)
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
                    Image(systemName: "xmark")
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
    var onHeightChanged: (CGFloat) -> Void = { _ in }

    var body: some View {
        if let pin = model.pins.first(where: { $0.id == pinID }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: pin.canFreeze ? "pin.fill" : "pause.circle")
                    Text(pin.windowTitle).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    if model.busyPinIDs.contains(pin.id) { ProgressView().controlSize(.mini) }
                    Text(pin.stateTitle(model.copy)).foregroundStyle(pin.stateColor)
                }
                .font(.caption.weight(.medium))
                PinActionsView(model: model, pin: pin, compact: true)
                Divider().opacity(0.5).padding(.vertical, 4)
                PinQualityControls(model: model, pin: pin)
            }
            .padding(12)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChanged($0) }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(FuwaAppearance.border, lineWidth: 1))
            .fuwaLightSurface()
            .accessibilityElement(children: .contain)
        }
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
