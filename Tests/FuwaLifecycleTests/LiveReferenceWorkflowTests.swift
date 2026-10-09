import AppKit
import CoreGraphics
import FuwaCore
import ScreenCaptureKit
import Testing
@testable import Fuwa

/// Explicit, permission-preserving native acceptance using only a generated window.
@Suite(.serialized)
@MainActor
struct LiveReferenceWorkflowTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FUWA_REFERENCE_CAPTURE_QA"] == "1"))
    func generatedWindowCropHideRestoreAndIdle() async throws {
        try #require(CGPreflightScreenCaptureAccess(), "An existing recording grant is required; never request it here")
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let fixture = NSWindow(contentRect: CGRect(x: 80, y: 80, width: 640, height: 320),
                               styleMask: [.borderless], backing: .buffered, defer: false)
        fixture.isReleasedWhenClosed = false
        fixture.title = "Fuwa QA generated black-white reference"
        let picture = WorkflowFixturePicture(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
        fixture.contentView = picture
        fixture.orderFrontRegardless()
        defer { fixture.contentView = nil; fixture.close() }
        try await Task.sleep(for: .milliseconds(300))
        let windowID = CGWindowID(fixture.windowNumber)
        let inventory = try WindowInventory.capture()
        let descriptor = try #require(inventory.descriptor(for: windowID))
        let target = try await TargetResolver().resolveExact(matching: descriptor)
        let session = PinSession(target: target)
        do {
            try await session.startInitialCapture(with: target)
            try await wait { session.state == .live }
            let view = try #require(Mirror(reflecting: session).descendant("captureView") as? CaptureView)
            let full = try view.makeFrozenImage()
            try save(full, name: "full-generated-window")
            // Exercise the actual local selection view's pointer path, rather
            // than assigning the region directly to the session.
            session.beginCropSelection()
            let chooser = try #require(Mirror(reflecting: session).descendant("cropPanel") as? CaptureRegionSelectionPanel)
            let selectionView = try #require(chooser.contentView?.subviews.first)
            let imageRect = CaptureReferenceGeometry.aspectFit(
                imageSize: CGSize(width: full.width, height: full.height),
                in: selectionView.bounds.insetBy(dx: 12, dy: 12))
            let start = CGPoint(x: imageRect.minX + imageRect.width * 0.65,
                                y: imageRect.maxY - imageRect.height * 0.9)
            let end = CGPoint(x: imageRect.minX + imageRect.width * 0.9,
                              y: imageRect.maxY - imageRect.height * 0.65)
            func pointer(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
                try #require(NSEvent.mouseEvent(with: type, location: selectionView.convert(point, to: nil),
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: chooser.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            }
            selectionView.mouseDown(with: try pointer(.leftMouseDown, at: start))
            selectionView.mouseDragged(with: try pointer(.leftMouseDragged, at: end))
            selectionView.mouseUp(with: try pointer(.leftMouseUp, at: end))
            #expect(!chooser.isVisible)
            #expect(session.options.presentationMode == .reference)
            let region = try #require(session.options.captureRegion)
            #expect(abs(region.x - 0.65) < 0.001 && abs(region.y - 0.65) < 0.001)
            var options = session.options
            options.frameRate = .fifteen
            options.notifiesWhenIdle = true
            session.setOptions(options)
            try await wait {
                guard let image = try? view.makeFrozenImage() else { return false }
                return image.width < full.width / 2 && image.height < full.height * 3 / 4
            }
            let crop = try view.makeFrozenImage()
            #expect(abs(Double(crop.width) / Double(full.width) - 0.25) < 0.02)
            #expect(abs(Double(crop.height) / Double(full.height) - 0.25) < 0.02)
            #expect(luminance(crop) > 0.85, "Bottom-right crop must contain white pixels, not the upper gray region")
            try save(crop, name: "cropped-generated-window")
            let panel = try #require(Mirror(reflecting: session).descendant("panel") as? NSPanel)
            #expect(!panel.ignoresMouseEvents)
            let independent = panel.frame.offsetBy(dx: 100, dy: 40)
            panel.setFrame(independent, display: true)
            fixture.setFrame(fixture.frame.offsetBy(dx: 30, dy: 20), display: true)
            let movedInventory = try WindowInventory.capture()
            session.reconcile(descriptor: movedInventory.descriptor(for: windowID),
                              coordinateSpace: movedInventory.coordinateSpace)
            #expect(panel.frame == independent)
            try await session.setPresentationSuppressed(true)
            #expect(session.snapshot.isHidden)
            #expect(!panel.isVisible)
            #expect(!hasCaptureStream(session))
            picture.inverted = true
            try await session.setPresentationSuppressed(false)
            try await wait { (try? view.makeFrozenImage()).map { luminance($0) < 0.15 } ?? false }
            #expect(session.state == .live && !session.snapshot.isHidden)
            try await wait(timeout: 19) { session.snapshot.isIdle }
            #expect(Mirror(reflecting: session).descendant("effectiveFrameRate") as? PinFrameRate == .one)
            picture.inverted = false
            try await wait { !session.snapshot.isIdle && ((try? view.makeFrozenImage()).map { luminance($0) > 0.85 } ?? false) }
            #expect(Mirror(reflecting: session).descendant("effectiveFrameRate") as? PinFrameRate == .fifteen)
            try await session.freeze()
            let paused = try #require(view.makeFrozenImage().dataProvider?.data as Data?)
            try await session.setPresentationSuppressed(true)
            picture.inverted = true
            try await session.setPresentationSuppressed(false)
            #expect(session.state == .frozen(.manual))
            #expect(!hasCaptureStream(session))
            #expect(try view.makeFrozenImage().dataProvider?.data as Data? == paused)
            try await session.resume(with: TargetResolver().resolveExact(matching: session.descriptor))
            try await wait { session.state == .live && ((try? view.makeFrozenImage()).map { luminance($0) < 0.15 } ?? false) }
            session.prepareForStop()
            #expect(!panel.isVisible)
            #expect(throws: FrozenFrameError.self) { try view.makeFrozenImage() }
            await session.stop()
        } catch {
            await session.stop()
            throw error
        }
    }

    private func wait(timeout: TimeInterval = 6, until condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end { try await Task.sleep(for: .milliseconds(50)) }
        try #require(condition(), "Generated-window capture did not reach the expected state")
    }

    private func luminance(_ image: CGImage) -> Double {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let color = bitmap.colorAt(x: image.width / 2, y: image.height / 2)?.usingColorSpace(.sRGB)
        return color.map { ($0.redComponent + $0.greenComponent + $0.blueComponent) / 3 } ?? -1
    }

    private func hasCaptureStream(_ session: PinSession) -> Bool {
        guard let optional = Mirror(reflecting: session).descendant("currentCycle") else { return false }
        return !Mirror(reflecting: optional).children.isEmpty
    }

    private func save(_ image: CGImage, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["FUWA_LIVE_REFERENCE_OUTPUT"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: directory.appendingPathComponent(name + ".png"))
    }
}

@MainActor
private final class WorkflowFixturePicture: NSView {
    var inverted = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        (inverted ? NSColor.white : .black).setFill()
        bounds.fill()
        (inverted ? NSColor.black : .white).setFill()
        CGRect(x: bounds.midX, y: 0, width: bounds.width / 2, height: bounds.height / 2).fill()
        NSColor(calibratedWhite: 0.5, alpha: 1).setFill()
        CGRect(x: bounds.midX, y: bounds.midY, width: bounds.width / 2, height: bounds.height / 2).fill()
    }
}
