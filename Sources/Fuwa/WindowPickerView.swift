import AppKit
import FuwaCore
import ScreenCaptureKit
import SwiftUI

struct FuwaWindowChoice: Identifiable, Sendable {
    var id: CGWindowID { intent.descriptor.id }
    let title: String
    let applicationName: String
    let bundleIdentifier: String?
    let intent: TargetIntentSnapshot

    @MainActor
    static func available() async throws -> [Self] {
        guard CGPreflightScreenCaptureAccess() else {
            throw TargetResolutionError.screenRecordingPermissionDenied
        }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        guard CGPreflightScreenCaptureAccess() else {
            throw TargetResolutionError.screenRecordingPermissionDenied
        }
        let inventory = try WindowInventory.capture()
        let context = SelectionContext(selfProcessID: ProcessInfo.processInfo.processIdentifier,
                                       displayBounds: inventory.activeDisplayBounds)
        let byID = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        return inventory.orderedWindows.compactMap { descriptor in
            guard SelectionPolicy.intentWindow(in: [descriptor], context: context) != nil,
                  let window = byID[descriptor.id] else { return nil }
            let app = window.owningApplication?.applicationName ?? descriptor.ownerName ?? "App"
            let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Self(title: title.isEmpty ? app : title, applicationName: app,
                        bundleIdentifier: descriptor.ownerBundleIdentifier,
                        intent: TargetIntentSnapshot(descriptor: descriptor, coordinateSpace: inventory.coordinateSpace))
        }
    }
}

@MainActor
struct WindowPickerView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var choices: [FuwaWindowChoice] = []
    @State private var loading = true
    @State private var search = ""
    @State private var error: String?
    @ObservedObject private var thumbnails: WindowThumbnailController
    @State private var refreshTask: Task<Void, Never>?
    @State private var refreshRevision = UUID()
    @FocusState private var searchFocused: Bool
    private var copy: FuwaCopy { model.copy }

    init(model: AppModel) {
        self.model = model
        self.thumbnails = model.windowThumbnails
    }

    private var filtered: [FuwaWindowChoice] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return choices.filter { query.isEmpty || "\($0.applicationName) \($0.title)".localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(copy.text(.chooseWindow)).font(.title3.weight(.semibold))
                Spacer()
                Button(copy.text(.cancel)) { stopPickerWork(); dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            TextField(copy.text(.searchWindows), text: $search)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                VStack(alignment: .leading, spacing: 12) {
                    Text(error).foregroundStyle(.secondary)
                    if model.screenRecordingPermission != .granted {
                        Button(copy.text(.openSettings), action: model.openScreenRecordingSettings)
                    }
                    Button(copy.text(.refreshWindows), action: refresh)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { choice in
                            let pinned = model.pins.contains { $0.sourceWindowID == choice.id }
                            Button {
                                stopPickerWork()
                                model.pinWindow(choice)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        FuwaApplicationIcon(bundleIdentifier: choice.bundleIdentifier, applicationName: choice.applicationName, size: 24)
                                        WindowThumbnailView(controller: thumbnails, descriptor: choice.intent.descriptor)
                                    }
                                    .frame(width: 96, height: 60)
                                    .background(FuwaAppearance.sidebar)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(FuwaAppearance.border))
                                    .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(choice.title).font(.body.weight(.medium)).lineLimit(1)
                                        Text(choice.applicationName).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: pinned ? "checkmark" : "plus")
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(FuwaRowButtonStyle(selected: pinned))
                            .accessibilityAddTraits(pinned ? .isSelected : [])
                            .disabled(pinned || model.isPinningFrontWindow || model.isClearingAll)
                            .onAppear { thumbnails.request(choice.intent.descriptor) }
                            .onDisappear { thumbnails.release(choice.intent.descriptor) }
                            Divider()
                        }
                        if filtered.isEmpty {
                            Text(copy.text(.noWindowsFound)).foregroundStyle(.secondary).padding(.vertical, 24)
                        }
                    }
                }
                Button(copy.text(.refreshWindows), action: refresh)
            }
        }
        .padding(24)
        .frame(width: 480, height: 400)
        .fuwaLightSurface()
        .onAppear {
            searchFocused = true
            thumbnails.start()
            refresh()
        }
        .onDisappear(perform: stopPickerWork)
        .onChange(of: thumbnails.privacyInvalidated) { _, invalidated in
            if invalidated { stopPickerWork(); dismiss() }
        }
    }

    private func refresh() {
        guard thumbnails.isActive else { return }
        refreshTask?.cancel()
        let revision = UUID()
        refreshRevision = revision
        thumbnails.reset()
        choices = []
        loading = true
        error = nil
        refreshTask = Task { @MainActor in
            defer { if refreshRevision == revision { loading = false } }
            do {
                let result = try await FuwaWindowChoice.available()
                guard !Task.isCancelled, thumbnails.isActive, refreshRevision == revision else { return }
                choices = result
            } catch {
                guard !Task.isCancelled, thumbnails.isActive, refreshRevision == revision else { return }
                self.error = FuwaErrorMessage.localizedDescription(for: error, language: copy.language)
            }
        }
    }

    private func stopPickerWork() {
        refreshRevision = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        thumbnails.stop()
        choices = []
    }
}
