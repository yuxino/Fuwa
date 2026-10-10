import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import Fuwa

/// Explicit native WindowServer acceptance. Uses generated surfaces only;
/// does not move the pointer, send keys, request permission or change real pins.
@Suite(.serialized)
@MainActor
struct PinShortcutIntentTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FUWA_SHORTCUT_WINDOW_QA"] == "1"))
    func clickThroughPictureTakesPriorityWithoutActivation() throws {
        let screen = try #require(NSScreen.screens.first)
        let frame = CGRect(x: screen.visibleFrame.midX - 160,
                           y: screen.visibleFrame.midY - 100,
                           width: 320, height: 200)
        func panel(level: Int) -> NSPanel {
            let result = NSPanel(contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            result.isReleasedWhenClosed = false
            result.backgroundColor = .white
            result.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + level)
            result.ignoresMouseEvents = true
            return result
        }
        let first = panel(level: 10)
        let second = panel(level: 11)
        let blocker = panel(level: 12)
        defer { blocker.close(); second.close(); first.close() }
        let originalFrontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let firstID = UUID()
        let secondID = UUID()
        let resolver = TargetResolver()
        first.orderFrontRegardless()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        let overlays: [CGWindowID: UUID] = [CGWindowID(first.windowNumber): firstID,
                                          CGWindowID(second.windowNumber): secondID]
        let point = CGPoint(x: frame.midX, y: frame.midY)
        func selectedPin() throws -> UUID? {
            switch try resolver.snapshotShortcutIntent(at: point, overlayPinIDs: overlays) {
            case .unpin(let id): return id
            case .toggle: return nil
            }
        }
        #expect(first.ignoresMouseEvents)
        #expect(try selectedPin() == firstID)
        second.orderFrontRegardless()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        #expect(try selectedPin() == secondID)
        blocker.orderFrontRegardless()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        // Ordinary foreground surfaces block references behind them. The
        // existing front-window fallback may be unavailable in a test runner.
        do { #expect(try selectedPin() == nil) }
        catch TargetResolutionError.noEligibleIntent { }
        blocker.orderOut(nil)
        second.orderOut(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        #expect(try selectedPin() == firstID)
        first.orderOut(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        do { #expect(try selectedPin() == nil) }
        catch TargetResolutionError.noEligibleIntent { }
        #expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == originalFrontPID)
    }
}
