import FuwaCore
import SwiftUI

private struct CaptureQualityAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

@MainActor
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var showingCaptureQualityChoices = false
    @FocusState private var focusedCaptureQuality: CaptureQuality?
    @FocusState private var captureQualityPickerIsFocused: Bool
    @ScaledMetric(relativeTo: .callout) private var captureQualityRowHeight = 30

    private var copy: FuwaCopy { model.copy }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionTitle(copy.text(.general))

                languageControls
                    .padding(.vertical, 12)

                Divider().opacity(0.5)

                captureQualityControls
                    .padding(.vertical, 12)

                Divider().opacity(0.5)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        shortcutDescription
                        Spacer(minLength: 10)
                        ShortcutRecorder(model: model)
                            .frame(maxWidth: 170, alignment: .trailing)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        shortcutDescription
                        ShortcutRecorder(model: model)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 12)

                Divider().opacity(0.5)

                launchAtLoginControls
                .padding(.vertical, 12)

                Divider().opacity(0.5)

                HStack(spacing: 12) {
                    Text(copy.text(.keepInDock))
                        .font(FuwaTypography.settingTitle)
                    Spacer(minLength: 8)
                    Toggle(copy.text(.keepInDock), isOn: Binding(
                        get: { model.keepInDock },
                        set: { model.setKeepInDock($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help(copy.text(.keepInDockNote))
                    .accessibilityHint(copy.text(.keepInDockNote))
                }
                .padding(.vertical, 12)

                sectionDivider
                sectionTitle(copy.text(.permissions))

                PermissionSettingsRow(
                    title: copy.text(.screenRecording),
                    note: copy.text(.screenRecordingNote),
                    required: true,
                    state: model.screenRecordingPermission,
                    copy: copy,
                    openSettings: model.openScreenRecordingSettings
                )

                Divider().opacity(0.5)

                PermissionSettingsRow(
                    title: copy.text(.accessibility),
                    note: copy.text(.accessibilityNote),
                    required: false,
                    state: model.accessibilityPermission,
                    copy: copy,
                    openSettings: model.openAccessibilitySettings
                )

                sectionDivider
                sectionTitle(copy.text(.softwareUpdate))
                softwareUpdateControls
                    .padding(.vertical, 12)

                sectionDivider

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        appName
                        Spacer(minLength: 8)
                        aboutButton
                        quitButton
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        appName

                        HStack(spacing: 12) {
                            Spacer()
                            aboutButton
                            quitButton
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.automatic)
        .overlayPreferenceValue(CaptureQualityAnchor.self) { anchor in
            if showingCaptureQualityChoices, let anchor {
                GeometryReader { geometry in
                    let bounds = geometry[anchor]
                    let width = min(max(bounds.width, 184), geometry.size.width - 16)
                    let height = captureQualityRowHeight * CGFloat(CaptureQuality.allCases.count) + 8
                    let below = bounds.maxY + 4
                    let y = below + height <= geometry.size.height - 8
                        ? below : max(8, bounds.minY - height - 4)

                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { showingCaptureQualityChoices = false }
                        .accessibilityHidden(true)

                    captureQualityChoices
                        .frame(width: width)
                        .offset(x: max(8, min(bounds.maxX - width, geometry.size.width - width - 8)), y: y)
                }
            }
        }
        .onDisappear { showingCaptureQualityChoices = false }
        .onChange(of: showingCaptureQualityChoices) { _, isShowing in
            if !isShowing {
                focusedCaptureQuality = nil
                captureQualityPickerIsFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            showingCaptureQualityChoices = false
        }
    }

    private var languageControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                Text(copy.text(.language)).font(FuwaTypography.settingTitle)
                Spacer(minLength: 12)
                languageChoices
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(copy.text(.language)).font(FuwaTypography.settingTitle)
                languageChoices
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var captureQualityControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Text(copy.text(.captureQuality)).font(FuwaTypography.settingTitle)
                    Spacer(minLength: 8)
                    captureQualityPicker.fixedSize()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(copy.text(.captureQuality)).font(FuwaTypography.settingTitle)
                    captureQualityPicker
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            Text(copy.text(.captureQualityNote))
                .font(FuwaTypography.explanation)
                .foregroundStyle(FuwaAppearance.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var captureQualityPicker: some View {
        Button {
            showingCaptureQualityChoices.toggle()
        } label: {
            HStack(spacing: 10) {
                Text(copy.captureQualityLabel(model.captureQuality))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(FuwaQuietButtonStyle())
        .focusable()
        .focused($captureQualityPickerIsFocused)
        .anchorPreference(key: CaptureQualityAnchor.self, value: .bounds) { $0 }
        .help(copy.text(.captureQualityHelp))
        .accessibilityLabel(copy.text(.captureQuality))
        .accessibilityValue(copy.captureQualityLabel(model.captureQuality))
        .accessibilityHint(copy.text(.captureQualityHelp))
    }

    private var captureQualityChoices: some View {
        VStack(spacing: 0) {
            ForEach(CaptureQuality.allCases, id: \.self) { quality in
                let selected = model.captureQuality == quality
                Button {
                    model.setCaptureQuality(quality)
                    showingCaptureQualityChoices = false
                } label: {
                    HStack(spacing: 10) {
                        Text(copy.captureQualityLabel(quality))
                            .font(.callout.weight(selected ? .medium : .regular))
                        Spacer(minLength: 0)
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.semibold))
                            .opacity(selected ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: captureQualityRowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(FuwaRowButtonStyle(selected: selected))
                .focusable()
                .focused($focusedCaptureQuality, equals: quality)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(FuwaAppearance.canvas, in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(copy.text(.captureQuality))
        .onAppear { focusedCaptureQuality = model.captureQuality }
        .onKeyPress(.downArrow) { moveCaptureQualityFocus(by: 1); return .handled }
        .onKeyPress(.upArrow) { moveCaptureQualityFocus(by: -1); return .handled }
        .onKeyPress(.return) {
            if let focusedCaptureQuality { model.setCaptureQuality(focusedCaptureQuality) }
            showingCaptureQualityChoices = false
            return .handled
        }
        .onKeyPress(.escape) {
            showingCaptureQualityChoices = false
            return .handled
        }
    }

    private func moveCaptureQualityFocus(by offset: Int) {
        let choices = CaptureQuality.allCases
        let current = choices.firstIndex(of: focusedCaptureQuality ?? model.captureQuality) ?? 0
        focusedCaptureQuality = choices[(current + offset + choices.count) % choices.count]
    }

    private var languageChoices: some View {
        HStack(spacing: 2) {
            languageChoice(.system, title: copy.text(.systemLanguage))
            languageChoice(.simplifiedChinese, title: "简体中文")
            languageChoice(.english, title: "English")
        }
        .fixedSize()
        .padding(3)
        .background(FuwaAppearance.sidebar, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(copy.text(.language))
    }

    private func languageChoice(_ preference: FuwaLanguagePreference, title: String) -> some View {
        let selected = model.languagePreference == preference
        return Button { model.setLanguage(preference) } label: {
            Text(title)
                .font(.caption.weight(selected ? .medium : .regular))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(selected ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.black.opacity(selected ? 0.08 : 0), lineWidth: 1)
                }
        }
        .buttonStyle(FuwaRowButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel("\(copy.text(.language)): \(title)")
    }

    private var appName: some View {
        Text(copy.text(.appName))
            .font(FuwaTypography.settingTitle)
    }

    @ViewBuilder
    private var softwareUpdateControls: some View {
        let state = model.softwareUpdate
        VStack(alignment: .leading, spacing: 9) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    updateStatus(state)
                    Spacer(minLength: 8)
                    updateActions(state)
                }
                VStack(alignment: .leading, spacing: 10) {
                    updateStatus(state)
                    updateActions(state)
                }
            }

            if let notes = state.releaseNotes,
               state.phase == .available || state.phase == .ready {
                VStack(alignment: .leading, spacing: 4) {
                    Text(copy.text(.releaseNotes))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(notes)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 112)
                }
            }

            updateProgress(state)
        }
        .accessibilityElement(children: .contain)
    }

    private func updateStatus(_ state: SoftwareUpdateState) -> some View {
        Text(updateStatusText(state))
            .font(FuwaTypography.settingTitle)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(updateStatusText(state))
    }

    private func updateActions(_ state: SoftwareUpdateState) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                updatePrimaryAction(state)
                updateSecondaryActions(state)
            }
            VStack(alignment: .leading, spacing: 8) {
                updatePrimaryAction(state)
                updateSecondaryActions(state)
            }
        }
    }

    @ViewBuilder
    private func updateProgress(_ state: SoftwareUpdateState) -> some View {
        switch state.phase {
        case .checking, .installing:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(updateStatusText(state))
        case .downloading:
            if let progress = state.downloadProgress {
                ProgressView(value: progress)
                    .accessibilityValue(Text(progress.formatted(.percent.precision(.fractionLength(0)))))
            } else {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(copy.text(.downloadingUpdate))
            }
        case .extracting:
            if let progress = state.normalizedExtractionProgress {
                ProgressView(value: progress)
                    .accessibilityValue(Text(progress.formatted(.percent.precision(.fractionLength(0)))))
            } else {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(copy.text(.extractingUpdate))
            }
        case .idle, .current, .available, .ready, .cancelled, .failed:
            EmptyView()
        }
    }

    @ViewBuilder
    private func updatePrimaryAction(_ state: SoftwareUpdateState) -> some View {
        switch state.phase {
        case .idle, .current:
            Button(copy.text(.checkForUpdates), action: model.checkForUpdates)
                .buttonStyle(FuwaQuietButtonStyle())
        case .available:
            Button(copy.text(.downloadUpdate), action: model.downloadUpdate)
                .buttonStyle(FuwaQuietButtonStyle())
        case .ready:
            Button(copy.text(.restartAndUpdate), action: model.installAndRelaunchUpdate)
                .buttonStyle(FuwaQuietButtonStyle())
                .keyboardShortcut(.defaultAction)
        case .cancelled, .failed:
            Button(copy.text(.retryUpdate), action: model.checkForUpdates)
                .buttonStyle(FuwaQuietButtonStyle())
        case .checking, .downloading, .extracting, .installing:
            EmptyView()
        }
    }

    @ViewBuilder
    private func updateSecondaryActions(_ state: SoftwareUpdateState) -> some View {
        if state.canCancel || state.phase == .available {
            Button(copy.text(.cancel), action: model.cancelUpdate)
                .buttonStyle(FuwaPlainButtonStyle())
        }
        if state.phase == .failed {
            Button(action: model.openLatestRelease) {
                Label(copy.text(.openReleasePage), systemImage: "arrow.up.right")
            }
            .buttonStyle(FuwaPlainButtonStyle())
            .fuwaLinkCursor()
            .help(copy.text(.releaseRecoveryHint))
            .accessibilityHint(copy.text(.releaseRecoveryHint))
        }
    }

    private func updateStatusText(_ state: SoftwareUpdateState) -> String {
        switch state.phase {
        case .idle:
            return "\(copy.text(.version)) \(state.currentVersion)"
        case .checking:
            return copy.text(.checkingForUpdates)
        case .current:
            return "\(copy.text(.upToDate)) \(copy.text(.version)) \(state.currentVersion)."
        case .available:
            return [copy.text(.updateAvailable), state.availableVersion]
                .compactMap { $0 }
                .joined(separator: " ")
        case .downloading:
            if let progress = state.downloadProgress {
                return "\(copy.text(.downloadingUpdate)) \(progress.formatted(.percent.precision(.fractionLength(0))))"
            }
            return copy.text(.downloadingUpdate)
        case .extracting:
            return copy.text(.extractingUpdate)
        case .ready:
            return copy.text(.readyToInstall)
        case .installing:
            return copy.text(.installingUpdate)
        case .cancelled:
            return copy.text(.updateCancelled)
        case .failed:
            return state.errorMessage ?? copy.text(.updateFailedMessage)
        }
    }

    private var aboutButton: some View {
        Button(copy.text(.about), action: model.showAbout)
            .buttonStyle(FuwaPlainButtonStyle())
    }

    private var quitButton: some View {
        Button(copy.text(.quit), action: model.quit)
            .buttonStyle(FuwaPlainButtonStyle())
            .keyboardShortcut("q", modifiers: .command)
    }

    private var shortcutDescription: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(copy.text(.shortcut))
                .font(FuwaTypography.settingTitle)

            Text(copy.text(.shortcutNote))
                .font(FuwaTypography.explanation)
                .foregroundStyle(FuwaAppearance.secondaryText)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)

            if !model.shortcutIsActive {
                Label(copy.text(.shortcutInactive), systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
            }
        }
    }

    private var launchAtLoginControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                Text(copy.text(.launchAtLogin))
                    .font(FuwaTypography.settingTitle)
                Spacer(minLength: 8)
                launchAtLoginToggle
            }

            if model.launchAtLoginState == .requiresApproval {
                Text(copy.text(.launchAtLoginApproval))
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    openLoginItemsButton
                }
            }
        }
    }

    private var launchAtLoginToggle: some View {
        Toggle(
            copy.text(.launchAtLogin),
            isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            )
        )
        .labelsHidden()
        .toggleStyle(.switch)
        .font(FuwaTypography.settingTitle)
        .controlSize(.small)
        .disabled(model.isUpdatingLaunchAtLogin)
    }

    private var openLoginItemsButton: some View {
        Button(copy.text(.openLoginItems), action: model.openLoginItemsSettings)
            .buttonStyle(FuwaQuietButtonStyle())
            .help(copy.text(.openLoginItems))
            .accessibilityHint(copy.text(.launchAtLoginApproval))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(FuwaTypography.sectionTitle)
            .foregroundStyle(FuwaAppearance.secondaryText)
            .padding(.top, 14)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }

    private var sectionDivider: some View {
        Divider()
            .opacity(0.5)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .accessibilityHidden(true)
    }
}

private struct PermissionSettingsRow: View {
    let title: String
    let note: String
    let required: Bool
    let state: FuwaPermissionState
    let copy: FuwaCopy
    let openSettings: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                permissionDescription
                Spacer(minLength: 12)
                permissionControls
            }

            VStack(alignment: .leading, spacing: 9) {
                permissionDescription
                permissionControls
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }

    private var permissionDescription: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(FuwaTypography.settingTitle)
                Text(copy.text(required ? .permissionRequired : .permissionOptional))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(note)
                .font(FuwaTypography.explanation)
                .foregroundStyle(FuwaAppearance.secondaryText)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissionControls: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Label(copy.text(state == .granted ? .ready : .permissionNotEnabled),
                  systemImage: state == .granted ? "checkmark.circle" : "minus.circle")
                .font(.caption)
                .foregroundStyle(state == .denied && required ? Color.orange : Color.secondary)
            if state != .granted {
                openSettingsButton
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var openSettingsButton: some View {
        Button(copy.text(.openSettings), action: openSettings)
            .buttonStyle(FuwaQuietButtonStyle())
            .help(copy.text(.openSettings))
            .accessibilityHint(note)
    }
}
