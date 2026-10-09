import CoreGraphics
import FuwaCore
import Testing

struct FloatingControlsLayoutTests {
    @Test func controlsStayInsideEveryDisplayArrangement() {
        let displays = [
            CGRect(x: 0, y: 80, width: 1512, height: 869),
            CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            CGRect(x: 100, y: 982, width: 1280, height: 800),
            CGRect(x: 1512, y: -500, width: 1440, height: 900)
        ]
        for display in displays {
            for x in [display.minX - 200, display.minX, display.midX, display.maxX - 50, display.maxX + 200] {
                for y in [display.minY - 200, display.minY, display.midY, display.maxY - 50, display.maxY + 200] {
                    let result = FloatingControlsLayout.frame(source: CGRect(x: x, y: y, width: 600, height: 400), visible: display)
                    #expect(display.contains(result))
                    #expect(result.size == CGSize(width: 380, height: 164))
                }
            }
        }
    }

    @Test func screenSelectionUsesOverlapAndThenNearestDisplay() {
        let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: -1920, y: 0, width: 1920, height: 1080)]
        #expect(FloatingControlsLayout.screenIndex(source: CGRect(x: -1600, y: 100, width: 800, height: 600), screens: screens) == 1)
        #expect(FloatingControlsLayout.screenIndex(source: CGRect(x: -100, y: 100, width: 800, height: 600), screens: screens) == 0)
        #expect(FloatingControlsLayout.screenIndex(source: CGRect(x: -3000, y: 100, width: 600, height: 400), screens: screens) == 1)
        #expect(FloatingControlsLayout.screenIndex(source: .zero, screens: []) == nil)
    }

    @Test func disconnectedFrozenViewsReturnToRemainingDisplay() {
        let remaining = CGRect(x: 0, y: 80, width: 1512, height: 869)
        let disconnected = [
            CGRect(x: -1700, y: 200, width: 800, height: 600),
            CGRect(x: 1800, y: 200, width: 800, height: 600),
            CGRect(x: 100, y: 1200, width: 800, height: 600),
            CGRect(x: 100, y: -900, width: 800, height: 600),
            CGRect(x: 2000, y: 0, width: 3840, height: 2160)
        ]
        for source in disconnected {
            let result = FloatingControlsLayout.recoveredFrame(source: source, visibleScreens: [remaining])
            #expect(remaining.contains(result))
            #expect(abs(result.width / result.height - source.width / source.height) < 0.00001)
            #expect(FloatingControlsLayout.recoveredFrame(source: result, visibleScreens: [remaining]) == result)
        }
    }

    @Test func visibleAndCrossScreenFrozenViewsKeepTheirPosition() {
        let screens = [CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                       CGRect(x: 0, y: 80, width: 1512, height: 869)]
        for source in [CGRect(x: -1700, y: 100, width: 800, height: 600),
                       CGRect(x: -100, y: 100, width: 800, height: 600)] {
            #expect(FloatingControlsLayout.recoveredFrame(source: source, visibleScreens: screens) == source)
        }
        let source = CGRect(x: 4000, y: 0, width: 800, height: 600)
        #expect(FloatingControlsLayout.recoveredFrame(source: source, visibleScreens: []) == source)
        let leftOnly = [screens[0]]
        #expect(screens[0].contains(FloatingControlsLayout.recoveredFrame(source: source, visibleScreens: leftOnly)))
    }

}
