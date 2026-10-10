import AppKit
import FuwaCore
import SwiftUI
import Testing
@testable import Fuwa

/// Runs only on explicit request, without visible windows, activation or input events.
@Suite(.serialized)
@MainActor
struct OffscreenPresentationTests {
    @Test func renderNativeViewsWithoutShowingWindows() throws {
        guard let output = ProcessInfo.processInfo.environment["FUWA_OFFSCREEN_OUTPUT"] else { return }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.applicationIconImage = NSImage(contentsOfFile: "Resources/AppIcon.png")
        try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
        let before = app.windows.filter(\.isVisible).count
        for language in FuwaLanguage.allCases {
            let model = AppModel(copy: FuwaCopy(language: language), version: "1.2.0", screenRecordingPermission: .granted)
            try save(SettingsView(model: model).frame(width: 546, height: 520).fuwaLightSurface(), to: "\(output)/\(language)-settings.png")
            try save(SettingsView(model: model).frame(width: 546, height: 600).fuwaLightSurface(), to: "\(output)/\(language)-settings-full.png")
            try save(FuwaHelpExplanation(title: model.copy.text(.notifyWhenIdle), text: model.copy.text(.notifyWhenIdleHelp)),
                to: "\(output)/\(language)-help.png")
            try save(SettingsView(model: model).frame(width: 364, height: 520).fuwaLightSurface(), to: "\(output)/\(language)-settings-compact.png")
            try save(SettingsView(model: model).frame(width: 436, height: 660).environment(\.dynamicTypeSize, .accessibility3).fuwaLightSurface(), to: "\(output)/\(language)-settings-large-text.png")
            let ungranted = AppModel(copy: FuwaCopy(language: language), version: "1.2.0", screenRecordingPermission: .unknown)
            try save(SettingsView(model: ungranted).frame(width: 364, height: 920).fuwaLightSurface(), to: "\(output)/\(language)-permissions-compact.png")
            try save(MainView(model: model).frame(width: 720, height: 540), to: "\(output)/\(language)-empty.png")
            let pin = PinSnapshot(id: UUID(), sourceWindowID: 123, applicationName: "Reference",
                bundleIdentifier: nil, windowTitle: "Notes for today's work", state: .live, errorMessage: nil, captureQuality: CaptureQuality(percentage: 50)!)
            let frozen = PinSnapshot(id: UUID(), sourceWindowID: 124, applicationName: "Preview",
                bundleIdentifier: nil, windowTitle: "A saved reference", state: .frozen(.sourceClosed), errorMessage: nil)
            let paused = PinSnapshot(id: UUID(), sourceWindowID: 125, applicationName: "Preview", bundleIdentifier: nil, windowTitle: "A paused reference", state: .frozen(.manual), errorMessage: nil)
            model.updatePins([pin, paused, frozen])
            try save(MainView(model: model).frame(width: 720, height: 540), to: "\(output)/\(language)-pins.png")
            try save(MainView(model: model).frame(width: 640, height: 460), to: "\(output)/\(language)-pins-compact.png")
            try save(PinControlsView(model: model, pinID: pin.id).frame(width: PinOptionsPopoverLayout.preferredWidth), to: "\(output)/\(language)-controls.png")
            try save(PinControlsView(model: model, pinID: paused.id).frame(width: PinOptionsPopoverLayout.preferredWidth), to: "\(output)/\(language)-paused-controls.png")
            try save(PinControlsView(model: model, pinID: pin.id).frame(width: PinOptionsPopoverLayout.preferredWidth).environment(\.dynamicTypeSize, .accessibility3), to: "\(output)/\(language)-controls-large-text.png")
            var referenceOptions = PinOptions()
            referenceOptions.presentationMode = .reference
            referenceOptions.captureRegion = NormalizedCaptureRegion(x: 0.1, y: 0.1, width: 0.6, height: 0.5)
            referenceOptions.spaceScope = .currentSpace
            referenceOptions.applicationScopeBundleIdentifier = "test.fuwa.editor.with.a.long.application.name"
            referenceOptions.notifiesWhenIdle = true
            let reference = PinSnapshot(id: UUID(), sourceWindowID: 126,
                applicationName: "Reference app with a longer name", bundleIdentifier: nil,
                windowTitle: "A reference window with a long title for layout verification",
                state: .live, errorMessage: nil, options: referenceOptions, isIdle: true)
            model.updatePins([reference, paused])
            try save(PinControlsView(model: model, pinID: reference.id).frame(width: PinOptionsPopoverLayout.preferredWidth), to: "\(output)/\(language)-reference-controls.png")
            try save(PinControlsView(model: model, pinID: reference.id, maximumHeight: 300)
                .frame(width: 320).environment(\.dynamicTypeSize, .accessibility3),
                to: "\(output)/\(language)-reference-controls-small.png")
            for section in [PinOptionsSection.visibility, .performance] {
                try save(PinControlsView(model: model, pinID: reference.id, initialSection: section)
                    .frame(width: PinOptionsPopoverLayout.preferredWidth), to: "\(output)/\(language)-reference-controls-\(section.rawValue).png")
                try save(PinControlsView(model: model, pinID: reference.id, maximumHeight: 300,
                    initialSection: section).frame(width: 320).environment(\.dynamicTypeSize, .accessibility3),
                    to: "\(output)/\(language)-reference-controls-\(section.rawValue)-small.png")
            }
            var restoringReference = reference
            restoringReference.isAwaitingFreshFrame = true
            model.updatePins([restoringReference])
            try save(PinControlsView(model: model, pinID: reference.id).frame(width: PinOptionsPopoverLayout.preferredWidth),
                to: "\(output)/\(language)-reference-controls-restoring.png")
            var hiddenReference = reference
            hiddenReference.isHidden = true
            model.updatePins([hiddenReference, paused])
            model.updatePinsVisibility(true)
            try save(MainView(model: model).frame(width: 640, height: 460), to: "\(output)/\(language)-pins-hidden.png")
            model.updatePins([pin, paused, frozen])
            model.updatePinsVisibility(false)
            model.showSettings()
            try save(MainView(model: model).frame(width: 720, height: 540), to: "\(output)/\(language)-settings-main.png")
            try save(MainView(model: model).frame(width: 720, height: 540).environment(\.colorScheme, .dark), to: "\(output)/\(language)-dark.png")
        }
        #expect(app.windows.filter(\.isVisible).count == before)
        #expect(!app.isActive)
    }

    private func save<V: View>(_ view: V, to path: String) throws {
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        host.layoutSubtreeIfNeeded()
        #expect(!window.isVisible)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: path))
    }
}
