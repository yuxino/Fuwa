import AppKit
import SwiftUI
import FuwaCore

enum FuwaPopoverLayout {
    static func isCompactEmpty(
        route: FuwaPopoverRoute,
        hasPins: Bool
    ) -> Bool {
        route == .pins && !hasPins
    }

    static func preferredContentSize(
        route: FuwaPopoverRoute,
        pinCount: Int,
        hasNotice: Bool,
        hasPermissionWarning: Bool,
        dynamicTypeSize: DynamicTypeSize
    ) -> NSSize {
        let metrics: (width: CGFloat, empty: CGFloat, chrome: CGFloat, row: CGFloat,
                      maximum: CGFloat, notice: CGFloat, warning: CGFloat)
        if dynamicTypeSize >= .accessibility3 {
            metrics = (472, 540, 240, 130, 720, 160, 40)
        } else if dynamicTypeSize.isAccessibilitySize {
            metrics = (436, 460, 210, 116, 660, 140, 28)
        } else if dynamicTypeSize >= .xxLarge {
            metrics = (396, 360, 180, 96, 600, 120, 16)
        } else {
            metrics = (364, 148, 128, 76, 480, 104, 24)
        }

        if route == .settings {
            return NSSize(width: max(364, metrics.width), height: max(520, metrics.maximum))
        }
        let baseHeight = pinCount <= 0 ? metrics.empty
            : min(metrics.maximum, metrics.chrome + CGFloat(pinCount) * metrics.row)
        return NSSize(
            width: metrics.width,
            height: baseHeight + (hasNotice ? metrics.notice : 0)
                + (hasPermissionWarning ? metrics.warning : 0)
        )
    }
}

private struct FuwaPopoverLayoutSignature: Equatable {
    let route: FuwaPopoverRoute
    let pinCount: Int
    let noticeID: UUID?
    let hasPermissionWarning: Bool
    let dynamicTypeSize: DynamicTypeSize
}

@MainActor
struct FuwaPopoverView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var headerTitleSize = 13
    @ScaledMetric(relativeTo: .body) private var navigationButtonSize = 24
    @ScaledMetric(relativeTo: .body) private var moreButtonWidth = 24
    @ScaledMetric(relativeTo: .body) private var moreButtonHeight = 20

    let onPreferredContentSizeChange: @MainActor (NSSize) -> Void

    private var copy: FuwaCopy { model.copy }

    init(
        model: AppModel,
        onPreferredContentSizeChange: @escaping @MainActor (NSSize) -> Void = { _ in }
    ) {
        _model = ObservedObject(wrappedValue: model)
        self.onPreferredContentSizeChange = onPreferredContentSizeChange
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if let notice = model.notice {
                FuwaNoticeView(
                    notice: notice,
                    copy: copy,
                    onDismiss: model.dismissNotice
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                .transition(reduceMotion ? .identity : .opacity)
            }

            Group {
                switch model.route {
                case .pins:
                    PinsView(model: model)
                case .settings:
                    SettingsView(model: model)
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: isCompactEmpty ? nil : .infinity
            )

            if model.route == .pins {
                Divider()
                footer
            }
        }
        .frame(
            minWidth: 280,
            idealWidth: preferredContentSize.width,
            maxWidth: .infinity,
            minHeight: model.route == .settings ? 240 : 0,
            idealHeight: preferredContentSize.height,
            maxHeight: .infinity,
            // Keep the header and primary action at the top when the view is
            // shown in a window taller than the popover's ideal height. The
            // flexible Pins group above the footer absorbs the extra space.
            alignment: .top
        )
        .fuwaLightSurface()
        .environment(\.locale, Locale(identifier: model.copy.language.localeIdentifier))
        .onExitCommand(perform: model.dismissPopover)
        .onAppear(perform: reportPreferredContentSize)
        .onChange(of: layoutSignature) { _, _ in
            reportPreferredContentSize()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(copy.text(.appName))
    }

    private var header: some View {
        HStack(spacing: 10) {
            if model.route == .settings {
                Button(action: model.showPins) {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.semibold))
                        .frame(width: navigationButtonSize, height: navigationButtonSize)
                }
                .buttonStyle(FuwaPlainButtonStyle())
                .help(copy.text(.back))
                .accessibilityLabel(copy.text(.back))
            }

            Text(model.route == .pins ? copy.text(.appName) : copy.text(.settings))
                .font(.system(size: headerTitleSize, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: model.showSettings) {
                HStack(spacing: 5) {
                    Image(
                        systemName: model.hasPermissionWarning
                            ? "exclamationmark.circle"
                            : "gearshape"
                    )
                    Text(
                        model.hasPermissionWarning
                            ? copy.text(.permissionAttention)
                            : copy.text(.settings)
                    )
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(model.hasPermissionWarning ? Color.orange : Color.secondary)
            }
            .buttonStyle(FuwaPlainButtonStyle())
            .help(settingsButtonLabel)
            .accessibilityLabel(settingsButtonLabel)

            Spacer()

            if !model.pins.isEmpty {
                Button(action: model.clearAll) {
                    if model.isClearingAll {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Text(copy.text(.clearAll))
                            .font(.caption.weight(.medium))
                    }
                }
                .buttonStyle(FuwaPlainButtonStyle())
                .disabled(model.isClearingAll)
                .help(copy.text(.clearAll))
                .accessibilityLabel(copy.text(.clearAll))
            }

            Menu {
                Button(copy.text(.about), action: model.showAbout)
                Divider()
                Button(copy.text(.quit), action: model.quit)
                    .keyboardShortcut("q", modifiers: .command)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: moreButtonWidth, height: moreButtonHeight)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(copy.text(.moreActions))
            .accessibilityLabel(copy.text(.moreActions))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .frame(minHeight: 32)
    }

    private var settingsButtonLabel: String {
        model.hasPermissionWarning
            ? copy.text(.permissionAttention)
            : copy.text(.settings)
    }

    private var preferredContentSize: NSSize {
        FuwaPopoverLayout.preferredContentSize(
            route: model.route,
            pinCount: model.pins.count,
            hasNotice: model.notice != nil,
            hasPermissionWarning: model.hasPermissionWarning,
            dynamicTypeSize: dynamicTypeSize
        )
    }

    private var isCompactEmpty: Bool {
        FuwaPopoverLayout.isCompactEmpty(
            route: model.route,
            hasPins: !model.pins.isEmpty
        )
    }

    private var layoutSignature: FuwaPopoverLayoutSignature {
        FuwaPopoverLayoutSignature(
            route: model.route,
            pinCount: model.pins.count,
            noticeID: model.notice?.id,
            hasPermissionWarning: model.hasPermissionWarning,
            dynamicTypeSize: dynamicTypeSize
        )
    }

    private func reportPreferredContentSize() {
        onPreferredContentSizeChange(preferredContentSize)
    }
}
