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
                        selectedBundleIdentifier: String?) -> [Self] {
        var names = [String: String]()
        for app in running where !app.bundleIdentifier.isEmpty {
            if names[app.bundleIdentifier] == nil { names[app.bundleIdentifier] = app.name }
        }
        if let sourceBundleIdentifier, names[sourceBundleIdentifier] == nil {
            names[sourceBundleIdentifier] = sourceName
        }
        if let selectedBundleIdentifier, names[selectedBundleIdentifier] == nil {
            names[selectedBundleIdentifier] = selectedBundleIdentifier
        }
        return names.map { Self(bundleIdentifier: $0.key, name: $0.value) }
            .sorted { lhs, rhs in
                let order = lhs.name.localizedStandardCompare(rhs.name)
                return order == .orderedSame ? lhs.bundleIdentifier < rhs.bundleIdentifier : order == .orderedAscending
            }
    }
}

/// Per-pin choices are separate from the source app and never forward input to it.
@MainActor
struct PinReferenceOptionsView: View {
    @ObservedObject var model: AppModel
    let pin: PinSnapshot
    @State private var applications: [PinApplicationChoice] = []

    private var copy: FuwaCopy { model.copy }
    private var busy: Bool { model.busyPinIDs.contains(pin.id) || model.isClearingAll }
    private var canUpdate: Bool { pin.canShowControls && !busy }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            optionRow(title: .presentationMode, help: .presentationModeHelp) {
                choiceMenu(title: .presentationMode,
                    value: copy.text(pin.options.presentationMode == .followSource ? .followOriginal : .referenceWindow)) {
                    ForEach(PinPresentationMode.allCases, id: \.self) { mode in
                        checkedChoice(copy.text(mode == .followSource ? .followOriginal : .referenceWindow),
                                      selected: pin.options.presentationMode == mode) {
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
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(copy.text(pin.options.captureRegion == nil ? .fullWindow : .selectedArea))
                        .font(.caption).foregroundStyle(FuwaAppearance.secondaryText)
                    FuwaHelpIcon(title: copy.text(.chooseArea), text: copy.text(.cropAreaHelp))
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { cropButton; resetCropButton }
                    VStack(alignment: .leading, spacing: 8) { cropButton; resetCropButton }
                }
            }
            Divider().opacity(0.5)
            optionRow(title: .showInSpaces, help: .spaceScopeHelp) {
                choiceMenu(title: .showInSpaces,
                    value: copy.text(pin.options.spaceScope == .allSpaces ? .allSpaces : .currentSpace)) {
                    ForEach(PinSpaceScope.allCases, id: \.self) { scope in
                        checkedChoice(copy.text(scope == .allSpaces ? .allSpaces : .currentSpace),
                                      selected: pin.options.spaceScope == scope) {
                            change { $0.spaceScope = scope }
                        }
                    }
                }
            }
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
            Divider().opacity(0.5)
            optionRow(title: .frameRate, help: .frameRateHelp) {
                choiceMenu(title: .frameRate, value: frameRateTitle(pin.options.frameRate)) {
                    ForEach(PinFrameRate.allCases, id: \.self) { rate in
                        checkedChoice(frameRateTitle(rate), selected: pin.options.frameRate == rate) {
                            change { $0.frameRate = rate }
                        }
                    }
                }
            }
            helpToggle(.reduceRateWhenIdle, help: .reduceRateWhenIdleHelp,
                isOn: Binding(get: { pin.options.reducesFrameRateWhenIdle }, set: { value in
                    change { $0.reducesFrameRateWhenIdle = value }
                }))
            helpToggle(.notifyWhenIdle, help: .notifyWhenIdleHelp,
                isOn: Binding(get: { pin.options.notifiesWhenIdle }, set: { value in
                    change { $0.notifiesWhenIdle = value }
                }))
            Divider().opacity(0.5)
            PinQualityControls(model: model, pin: pin)
        }
        .disabled(!canUpdate)
        .onAppear(perform: refreshApplications)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            refreshApplications()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            refreshApplications()
        }
        .onChange(of: pin.options.applicationScopeBundleIdentifier) { _, _ in refreshApplications() }
    }

    private var cropButton: some View {
        Button { model.beginCropSelection(pin.id) } label: {
            Label(copy.text(.chooseArea), systemImage: "crop")
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(FuwaQuietButtonStyle())
        .disabled(!pin.canChooseArea || busy)
        .help(copy.text(.cropAreaHelp))
    }

    private var resetCropButton: some View {
        Button(copy.text(.resetArea)) { change { $0.captureRegion = nil } }
            .buttonStyle(FuwaPlainButtonStyle())
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
        applications = PinApplicationChoice.choices(
            running: NSWorkspace.shared.runningApplications.compactMap { app in
                guard app.activationPolicy == .regular, !app.isTerminated,
                      let identifier = app.bundleIdentifier, identifier != Bundle.main.bundleIdentifier else { return nil }
                return (identifier, app.localizedName ?? identifier)
            }, sourceBundleIdentifier: pin.bundleIdentifier, sourceName: pin.applicationName,
            selectedBundleIdentifier: pin.options.applicationScopeBundleIdentifier)
    }

    private func optionRow<Content: View>(title: FuwaString, help: FuwaString,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(copy.text(title)).font(.caption.weight(.medium))
                FuwaHelpIcon(title: copy.text(title), text: copy.text(help))
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
}
