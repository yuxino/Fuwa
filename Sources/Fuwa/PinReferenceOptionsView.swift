import AppKit
import FuwaCore
import SwiftUI

struct PinApplicationChoice: Equatable, Identifiable {
    let bundleIdentifier: String
    let name: String
    var id: String { bundleIdentifier }

    /// Include a selected or source app even if it has exited while controls are open.
    static func choices(running: [(bundleIdentifier: String, name: String)],
                        sourceBundleIdentifier: String?, sourceName: String,
                        selectedBundleIdentifier: String?, selectedName: String? = nil) -> [Self] {
        var names = [String: String]()
        for app in running where !app.bundleIdentifier.isEmpty {
            if names[app.bundleIdentifier] == nil { names[app.bundleIdentifier] = app.name }
        }
        if let sourceBundleIdentifier, names[sourceBundleIdentifier] == nil {
            names[sourceBundleIdentifier] = sourceName
        }
        if let selectedBundleIdentifier, names[selectedBundleIdentifier] == nil {
            names[selectedBundleIdentifier] = selectedName ?? selectedBundleIdentifier
        }
        return names.map { Self(bundleIdentifier: $0.key, name: $0.value) }
            .sorted { lhs, rhs in
                let order = lhs.name.localizedStandardCompare(rhs.name)
                return order == .orderedSame ? lhs.bundleIdentifier < rhs.bundleIdentifier : order == .orderedAscending
            }
    }
}

enum PinOptionsSection: String, CaseIterable, Identifiable {
    case picture, visibility, performance
    var id: Self { self }
    var titleKey: FuwaString {
        switch self {
        case .picture: .pictureOptions
        case .visibility: .visibilityOptions
        case .performance: .performanceOptions
        }
    }
}

/// Per-pin choices are separate from the source app and never forward input to it.
@MainActor
struct PinReferenceOptionsView: View {
    @ObservedObject var model: AppModel
    let pin: PinSnapshot
    @State private var applications: [PinApplicationChoice] = []
    @Binding var section: PinOptionsSection
    let maximumHeight: CGFloat
    @State private var tabsHeight: CGFloat = 30

    init(model: AppModel, pin: PinSnapshot, section: Binding<PinOptionsSection>, maximumHeight: CGFloat) {
        self.model = model
        self.pin = pin
        _section = section
        self.maximumHeight = maximumHeight
    }

    private var copy: FuwaCopy { model.copy }
    private var busy: Bool { model.busyPinIDs.contains(pin.id) || model.isClearingAll }
    private var canUpdate: Bool { pin.canShowControls && !busy }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 3) {
                ForEach(PinOptionsSection.allCases) { item in
                    Button { section = item } label: {
                        Text(copy.text(item.titleKey))
                            .font(.caption.weight(section == item ? .semibold : .medium))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(FuwaRowButtonStyle(selected: section == item))
                    .fuwaLinkCursor()
                    .accessibilityAddTraits(section == item ? .isSelected : [])
                    .accessibilityIdentifier("pin-options-section-\(item.rawValue)")
                }
            }
            .padding(3)
            .background(FuwaAppearance.sidebar, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(FuwaAppearance.border.opacity(0.7)))
            .accessibilityIdentifier("pin-options-sections")
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tabsHeight = $0 }
            // Use each section's natural height when it fits. Only the options
            // scroll on short screens; tabs and playback stay reachable.
            ViewThatFits(in: .vertical) {
                sectionContent.fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    sectionContent
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, 3)
                }
                .scrollIndicators(.visible)
            }
            .frame(maxHeight: max(0, maximumHeight - tabsHeight - 12))
        }
        .onAppear(perform: refreshApplications)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            refreshApplications()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            refreshApplications()
        }
        .onChange(of: pin.options.applicationScopeBundleIdentifier) { _, _ in refreshApplications() }
    }

    private var sectionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch section {
            case .picture: pictureOptions
            case .visibility: visibilityOptions
            case .performance: performanceOptions
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .disabled(!canUpdate)
    }

    private var pictureOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            optionRow(title: .presentationMode, help: .presentationModeHelp) {
                HStack(spacing: 5) {
                    ForEach(PinPresentationMode.allCases, id: \.self) { mode in
                        selectableChoice(copy.text(mode == .followSource ? .followOriginal : .referenceWindow),
                                         selected: pin.options.presentationMode == mode) {
                            guard pin.options.presentationMode != mode else { return }
                            change {
                                $0.presentationMode = mode
                                if mode == .followSource { $0.captureRegion = nil }
                            }
                        }
                        .disabled(mode == .followSource && pin.options.captureRegion != nil && !pin.canChooseArea)
                        .help(copy.text(mode == .followSource && pin.options.captureRegion != nil ? .cropAreaHelp : .presentationModeHelp))
                    }
                }
            }
            Divider().opacity(0.5)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(copy.text(.captureArea)).font(.caption.weight(.medium))
                    FuwaHelpIcon(title: copy.text(.captureArea), text: copy.text(.cropAreaHelp))
                    Spacer(minLength: 6)
                    Text(copy.text(pin.options.captureRegion == nil ? .fullWindow : .selectedArea))
                        .font(.caption).foregroundStyle(FuwaAppearance.secondaryText)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { cropButton; if pin.options.captureRegion != nil { resetCropButton } }
                    VStack(alignment: .leading, spacing: 8) { cropButton; if pin.options.captureRegion != nil { resetCropButton } }
                }
            }
            Divider().opacity(0.5)
            PinQualityControls(model: model, pin: pin)
        }
    }

    private var visibilityOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            optionRow(title: .showInSpaces, help: .spaceScopeHelp) {
                HStack(spacing: 5) {
                    ForEach(PinSpaceScope.allCases, id: \.self) { scope in
                        selectableChoice(copy.text(scope == .allSpaces ? .allSpaces : .currentSpace),
                                         selected: pin.options.spaceScope == scope) {
                            change { $0.spaceScope = scope }
                        }
                    }
                }
            }
            Divider().opacity(0.5)
            VStack(alignment: .leading, spacing: 7) {
                helpToggle(.onlyWhenAppActive, help: .applicationScopeHelp, isOn: Binding(
                    get: { pin.options.applicationScopeBundleIdentifier != nil },
                    set: { enabled in
                        change {
                            $0.applicationScopeBundleIdentifier = enabled
                                ? pin.bundleIdentifier ?? applications.first?.bundleIdentifier : nil
                        }
                    }
                ))
                .disabled(!canUpdate || (pin.options.applicationScopeBundleIdentifier == nil && applications.isEmpty))
                if let selected = pin.options.applicationScopeBundleIdentifier {
                    choiceMenu(title: .activeApplication,
                        value: applications.first(where: { $0.bundleIdentifier == selected })?.name ?? selected) {
                        ForEach(applications) { app in
                            checkedChoice(app.name, selected: selected == app.bundleIdentifier) {
                                change { $0.applicationScopeBundleIdentifier = app.bundleIdentifier }
                            }
                        }
                    }
                }
            }
        }
    }

    private var performanceOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            optionRow(title: .frameRate, help: .frameRateHelp, value: frameRateTitle(pin.options.frameRate)) {
                HStack(spacing: 3) {
                    ForEach(PinFrameRate.allCases, id: \.self) { rate in
                        selectableChoice(String(rate.rawValue), selected: pin.options.frameRate == rate) {
                            change { $0.frameRate = rate }
                        }
                        .accessibilityLabel(frameRateTitle(rate))
                    }
                }
            }
            Divider().opacity(0.5)
            helpToggle(.reduceRateWhenIdle, help: .reduceRateWhenIdleHelp,
                isOn: Binding(get: { pin.options.reducesFrameRateWhenIdle }, set: { value in
                    change { $0.reducesFrameRateWhenIdle = value }
                }))
            helpToggle(.notifyWhenIdle, help: .notifyWhenIdleHelp,
                isOn: Binding(get: { pin.options.notifiesWhenIdle }, set: { value in
                    change { $0.notifiesWhenIdle = value }
                }))
        }
    }

    private var cropButton: some View {
        Button { model.beginCropSelection(pin.id) } label: {
            Label(copy.text(pin.options.captureRegion == nil ? .chooseArea : .rechooseArea), systemImage: "crop")
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(FuwaQuietButtonStyle())
        .fuwaLinkCursor()
        .disabled(!pin.canChooseArea || busy)
        .help(copy.text(.cropAreaHelp))
    }

    private var resetCropButton: some View {
        Button(copy.text(.resetArea)) { change { $0.captureRegion = nil } }
            .buttonStyle(FuwaPlainButtonStyle())
            .fuwaLinkCursor()
            .disabled(pin.options.captureRegion == nil || !pin.canChooseArea || busy)
    }

    private func change(_ update: (inout PinOptions) -> Void) {
        var options = pin.options
        update(&options)
        model.setPinOptions(options, for: pin.id)
    }

    private func frameRateTitle(_ rate: PinFrameRate) -> String {
        copy.formatted(.frameRateValue, values: ["count": String(rate.rawValue)])
    }

    private func refreshApplications() {
        let selectedIdentifier = pin.options.applicationScopeBundleIdentifier
        let knownName = applications.first(where: { $0.bundleIdentifier == selectedIdentifier })?.name
        let installedName = selectedIdentifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .map { (FileManager.default.displayName(atPath: $0.path) as NSString).deletingPathExtension }
        applications = PinApplicationChoice.choices(
            running: NSWorkspace.shared.runningApplications.compactMap { app in
                guard app.activationPolicy == .regular, !app.isTerminated,
                      let identifier = app.bundleIdentifier, identifier != Bundle.main.bundleIdentifier else { return nil }
                return (identifier, app.localizedName ?? identifier)
            }, sourceBundleIdentifier: pin.bundleIdentifier, sourceName: pin.applicationName,
            selectedBundleIdentifier: selectedIdentifier, selectedName: knownName ?? installedName)
    }

    private func optionRow<Content: View>(title: FuwaString, help: FuwaString, value: String? = nil,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(copy.text(title)).font(.caption.weight(.medium))
                FuwaHelpIcon(title: copy.text(title), text: copy.text(help))
                if let value {
                    Spacer(minLength: 6)
                    Text(value).font(.caption).monospacedDigit()
                        .foregroundStyle(FuwaAppearance.secondaryText)
                }
            }
            content()
        }
    }

    private func helpToggle(_ title: FuwaString, help: FuwaString, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Toggle(isOn: isOn) {
                Text(copy.text(title)).font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHint(copy.text(help))
            FuwaHelpIcon(title: copy.text(title), text: copy.text(help))
        }
    }

    private func choiceMenu<Content: View>(title: FuwaString, value: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        Menu(content: content) {
            Text(value).font(.caption)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(FuwaAppearance.canvas, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(FuwaAppearance.border))
        .accessibilityLabel(copy.text(title))
        .accessibilityValue(value)
        .disabled(!canUpdate)
    }

    private func checkedChoice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if selected { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    private func selectableChoice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption.weight(selected ? .semibold : .regular)).monospacedDigit()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6).padding(.vertical, 7)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(FuwaRowButtonStyle(selected: selected))
        .fuwaLinkCursor()
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(FuwaAppearance.border.opacity(selected ? 1 : 0.6)))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
