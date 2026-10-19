import AppKit
import CoreGraphics
import FuwaCore
import Testing
@testable import Fuwa

@Suite(.serialized)
@MainActor
struct ReferenceInteractionTests {
    @Test func referenceMenuOffersSizeAndSourceWithoutForwardingInput() throws {
        let app = NSApplication.shared
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        let view = CaptureView(frame: panel.contentLayoutRect)
        panel.contentView = view
        defer { view.clearAllPixels(); panel.contentView = nil; panel.close() }
        view.isReferencePresentation = true
        view.controlsTitle = "Picture Options"
        view.referenceSizeTitle = "Size"
        view.referenceSizeTitles = ["Small", "Medium", "Large"]
        view.sourceApplicationTitle = "Open Source App"
        var controls = 0, source = 0
        var sizes: [CGFloat] = []
        var hover: [Bool] = []
        view.onRequestControls = { controls += 1 }
        view.onOpenSourceApplication = { source += 1 }
        view.onReferenceSizeSelected = { sizes.append($0) }
        view.onReferenceHoverChanged = { hover.append($0) }
        let click = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: CGPoint(x: 100, y: 100),
            modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1))
        let menu = try #require(view.menu(for: click))
        #expect(menu.items.map(\.title) == ["Picture Options", "Size", "", "Open Source App"])
        menu.performActionForItem(at: 0)
        let submenu = try #require(menu.items[1].submenu)
        for index in 0..<3 { submenu.performActionForItem(at: index) }
        menu.performActionForItem(at: 3)
        #expect(controls == 1 && source == 1)
        #expect(sizes == [0.2, 0.35, 0.5])
        #expect(hover.last == false)
        let doubleClick = try #require(NSEvent.mouseEvent(with: .leftMouseDown,
            location: CGPoint(x: 100, y: 100), modifierFlags: [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, eventNumber: 2, clickCount: 2, pressure: 1))
        view.mouseDown(with: doubleClick)
        #expect(source == 2)
        view.canOpenSourceApplication = false
        let unavailableMenu = try #require(view.menu(for: click))
        #expect(!unavailableMenu.items[3].isEnabled)
        #expect(!panel.isVisible)
        #expect(app.keyWindow !== panel)
    }

    @Test func dismissedPreviewClearsPixelsAndCannotCaptureInput() throws {
        _ = NSApplication.shared
        let context = try #require(CGContext(data: nil, width: 80, height: 60,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
        let preview = ReferencePreviewController(image: try #require(context.makeImage()),
            frame: CGRect(x: 0, y: 0, width: 480, height: 360), collectionBehavior: [.canJoinAllSpaces])
        let view = try #require(preview.panel.contentView as? CaptureView)
        #expect(try view.makeFrozenImage().width == 80)
        #expect(preview.panel.ignoresMouseEvents)
        #expect(preview.panel.sharingType == .none)
        #expect(preview.panel.alphaValue == 1)
        preview.dismiss()
        #expect(!preview.panel.isVisible)
        #expect(preview.panel.contentView == nil)
        #expect(throws: FrozenFrameError.self) { try view.makeFrozenImage() }
        preview.dismiss()
    }
}
