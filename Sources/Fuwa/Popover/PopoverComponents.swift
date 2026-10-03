import AppKit
import SwiftUI

struct FuwaPrimaryButtonStyle: ButtonStyle {
    var expands = true
    var compact = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .callout.weight(.medium) : .body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: expands ? .infinity : nil)
            .padding(.vertical, compact ? 7 : 10)
            .padding(.horizontal, 14)
            .background {
                RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
                    .fill(FuwaAppearance.ink)
            }
            .opacity(opacity(isPressed: configuration.isPressed))
            .contentShape(Rectangle())
            .modifier(FuwaKeyboardFocus(cornerRadius: compact ? 7 : 9))
            .onHover { isHovered = $0 }
    }

    private func opacity(isPressed: Bool) -> Double {
        guard isEnabled else { return 0.35 }
        return isPressed ? 0.64 : (isHovered ? 0.82 : 1)
    }
}

/// Shared neutral feedback for actions and selectable navigation/list rows.
/// State is local to each rendered button; disabled controls never highlight.
private struct FuwaButtonFeedback: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    let isPressed: Bool
    let selected: Bool
    let restingOpacity: Double

    private var fillOpacity: Double {
        guard isEnabled else { return selected ? 0.10 : restingOpacity }
        if isPressed { return 0.20 }
        if isHovered { return selected ? 0.16 : 0.11 }
        return selected ? 0.10 : restingOpacity
    }

    func body(content: Content) -> some View {
        content
            .background(Color.primary.opacity(fillOpacity), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Color.primary.opacity(isEnabled && (isHovered || isPressed || selected) ? 0.22 : 0), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .opacity(isEnabled ? 1 : 0.35)
            .modifier(FuwaKeyboardFocus(cornerRadius: 7))
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: isHovered)
    }
}

struct FuwaQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(minHeight: 28)
            .modifier(FuwaButtonFeedback(isPressed: configuration.isPressed, selected: false, restingOpacity: 0.06))
    }
}

/// Borderless actions still need a visible target and pointer/keyboard feedback.
struct FuwaPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 6)
            .frame(minHeight: 28)
            .modifier(FuwaButtonFeedback(isPressed: configuration.isPressed, selected: false, restingOpacity: 0))
    }
}

struct FuwaKeyboardFocus: ViewModifier {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: cornerRadius + 2)
                .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
                .padding(-3)
                .opacity(isFocused && isEnabled ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

struct FuwaRowButtonStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .modifier(FuwaButtonFeedback(isPressed: configuration.isPressed, selected: selected, restingOpacity: 0))
    }
}

struct FuwaIconButton: View {
    @ScaledMetric(relativeTo: .body) private var buttonWidth = 28
    @ScaledMetric(relativeTo: .body) private var buttonHeight = 28

    let symbol: String
    let label: String
    let isBusy: Bool
    let action: () -> Void

    init(
        symbol: String,
        label: String,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.label = label
        self.isBusy = isBusy
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: symbol)
                        .font(.body.weight(.medium))
                }
            }
            .frame(width: buttonWidth, height: buttonHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(FuwaPlainButtonStyle())
        .disabled(isBusy)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct FuwaNoticeView: View {
    @ScaledMetric(relativeTo: .body) private var dismissButtonSize = 24

    let notice: FuwaNotice
    let copy: FuwaCopy
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: notice.kind == .error ? "exclamationmark.circle" : "info.circle")
                .foregroundStyle(notice.kind == .error ? Color.red : Color.secondary)
                .accessibilityHidden(true)

            Text(notice.message)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .frame(width: dismissButtonSize, height: dismissButtonSize)
            }
            .buttonStyle(FuwaPlainButtonStyle())
            .help(copy.text(.dismiss))
            .accessibilityLabel(copy.text(.dismiss))
        }
        .padding(9)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

@MainActor
struct FuwaApplicationIcon: View {
    @ScaledMetric(relativeTo: .body) private var iconSize = 30

    let bundleIdentifier: String?
    let applicationName: String

    init(bundleIdentifier: String?, applicationName: String, size: CGFloat = 30) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        _iconSize = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: iconSize, height: iconSize)
            .accessibilityHidden(true)
    }

    private var icon: NSImage {
        if
            let bundleIdentifier,
            let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            )
        {
            return NSWorkspace.shared.icon(forFile: applicationURL.path)
        }

        if
            let runningIcon = NSWorkspace.shared.runningApplications
                .first(where: { $0.localizedName == applicationName })?
                .icon
        {
            return runningIcon
        }

        return NSImage(
            systemSymbolName: "macwindow",
            accessibilityDescription: applicationName
        ) ?? NSImage(size: NSSize(width: 30, height: 30))
    }
}

struct FuwaPermissionLabel: View {
    let state: FuwaPermissionState
    let copy: FuwaCopy

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(state == .denied ? Color.orange : Color.secondary)
            .accessibilityLabel(title)
    }

    private var title: String {
        switch state {
        case .unknown:
            copy.text(.permissionUnknown)
        case .granted:
            copy.text(.ready)
        case .denied:
            copy.text(.permissionNeeded)
        }
    }

    private var symbol: String {
        switch state {
        case .unknown:
            "minus.circle"
        case .granted:
            "checkmark.circle"
        case .denied:
            "exclamationmark.circle"
        }
    }
}
