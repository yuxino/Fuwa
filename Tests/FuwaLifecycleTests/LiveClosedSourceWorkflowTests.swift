import AppKit
import CoreGraphics
import Darwin
import Foundation
import FuwaCore
import Testing
@testable import Fuwa

extension LiveReferenceWorkflowTests {
    /// A separate process makes source destruction independent of AppKit's
    /// retention of closed windows in the test runner's own application.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FUWA_REFERENCE_CAPTURE_QA"] == "1"))
    @MainActor
    func generatedChildSourceClosurePreservesFrameUntilUnpin() async throws {
        try #require(CGPreflightScreenCaptureAccess(), "An existing recording grant is required; never request it here")
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        child.arguments = ["-e", Self.closedSourceFixtureScript]
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        var didLaunch = false
        var session: PinSession?
        defer {
            // Both success and throwing paths await stop below. This synchronous
            // backstop also prevents pixels or a fixture process surviving cleanup.
            session?.prepareForStop()
            if didLaunch, child.isRunning {
                child.terminate()
                _ = Darwin.kill(child.processIdentifier, SIGKILL)
            }
        }

        do {
            try child.run()
            didLaunch = true
            let childPID = child.processIdentifier
            let deadline = Date().addingTimeInterval(10)
            var descriptor: WindowDescriptor?
            try await waitForClosedSourceFixture(until: deadline) {
                guard child.isRunning,
                      let inventory = try? WindowInventory.capture() else { return false }
                descriptor = inventory.orderedWindows.first {
                    $0.ownerPID == childPID && $0.layer == 0 &&
                    $0.bounds.width >= 600 && $0.bounds.height >= 300
                }
                return descriptor != nil
            }
            let source = try #require(descriptor, "Only the generated child process's window may be captured")
            #expect(source.ownerPID == childPID)
            let target = try await TargetResolver().resolveExact(matching: source)
            let pin = PinSession(target: target)
            session = pin
            try await pin.startInitialCapture(with: target)
            try await waitForClosedSourceFixture(until: deadline) { pin.state == .live }
            let view = try #require(Mirror(reflecting: pin).descendant("captureView") as? CaptureView)
            let panel = try #require(Mirror(reflecting: pin).descendant("panel") as? NSPanel)
            let first = try view.makeFrozenImage()
            #expect(closedSourceLuminance(first, xFraction: 0.25) < 0.15)
            #expect(closedSourceLuminance(first, xFraction: 0.75) > 0.85)

            try await pin.setPresentationSuppressed(true)
            #expect(pin.snapshot.isHidden)
            #expect(!panel.isVisible)
            #expect(!closedSourceHasCaptureStream(pin))
            let retained = try #require(view.makeFrozenImage().dataProvider?.data as Data?)
            child.terminate()
            try await waitForClosedSourceFixture(until: deadline) { !child.isRunning }
            try await waitForClosedSourceFixture(until: deadline) {
                WindowInventory.currentDescriptor(for: source.id, ownerPID: childPID) == nil
            }

            do {
                try await pin.setPresentationSuppressed(false)
                Issue.record("Restoring a destroyed source must report its exact identity as disappeared")
            } catch TargetResolutionError.intentDisappeared(let windowID) {
                #expect(windowID == source.id)
            }
            #expect(pin.state == .frozen(.sourceClosed))
            #expect(!pin.snapshot.isHidden)
            #expect(!closedSourceHasCaptureStream(pin))
            #expect(try view.makeFrozenImage().dataProvider?.data as Data? == retained,
                    "The last generated frame remains available after source destruction")
            pin.prepareForStop()
            #expect(!panel.isVisible)
            #expect(throws: FrozenFrameError.self) { try view.makeFrozenImage() }
            await pin.stop()
            #expect(pin.state == .stopped)
        } catch {
            session?.prepareForStop()
            if let session { await session.stop() }
            throw error
        }
    }

    @MainActor
    private func waitForClosedSourceFixture(until deadline: Date, condition: () -> Bool) async throws {
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(condition(), "The generated child-window workflow exceeded its 10-second deadline")
    }

    @MainActor
    private func closedSourceLuminance(_ image: CGImage, xFraction: Double) -> Double {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let color = bitmap.colorAt(x: Int(Double(image.width) * xFraction), y: image.height / 2)?.usingColorSpace(.sRGB)
        return color.map { ($0.redComponent + $0.greenComponent + $0.blueComponent) / 3 } ?? -1
    }

    @MainActor
    private func closedSourceHasCaptureStream(_ session: PinSession) -> Bool {
        guard let optional = Mirror(reflecting: session).descendant("currentCycle") else { return false }
        return !Mirror(reflecting: optional).children.isEmpty
    }

    private static let closedSourceFixtureScript = #"""
    import AppKit
    final class GeneratedReference: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSColor.black.setFill()
            bounds.fill()
            NSColor.white.setFill()
            NSRect(x: bounds.midX, y: 0, width: bounds.width / 2, height: bounds.height).fill()
        }
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 640, height: 320),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.title = "Fuwa QA generated child black-white reference"
    window.contentView = GeneratedReference(frame: NSRect(x: 0, y: 0, width: 640, height: 320))
    window.orderFrontRegardless()
    app.run()
    """#
}
