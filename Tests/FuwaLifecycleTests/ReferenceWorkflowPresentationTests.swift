import AppKit
import FuwaCore
import SwiftUI
import Testing
@testable import Fuwa

@Suite(.serialized)
@MainActor
struct ReferenceWorkflowPresentationTests {
    private func pin(state: PinState = .live, hidden: Bool = false, idle: Bool = false,
                     notify: Bool = false) -> PinSnapshot {
        var options = PinOptions()
        options.notifiesWhenIdle = notify
        return PinSnapshot(id: UUID(), sourceWindowID: 100, applicationName: "Reference",
                           bundleIdentifier: "test.fuwa.reference", windowTitle: "A reference window",
                           state: state, errorMessage: nil, options: options, isHidden: hidden, isIdle: idle)
    }

    @Test func hiddenPinsKeepTheirStateAndIdleMarkerIsOptIn() {
        for language in FuwaLanguage.allCases {
            let copy = FuwaCopy(language: language)
            let paused = pin(state: .frozen(.manual), hidden: true, idle: true, notify: true)
            #expect(paused.statusTitle(copy).contains(copy.text(.frozen)))
            #expect(paused.statusTitle(copy).contains(copy.text(.hidden)))
            #expect(!paused.statusTitle(copy).contains(copy.text(.pictureIdle)))
            #expect(!paused.canChooseArea)
            #expect(paused.canShowControls)
            #expect(!pin(hidden: true).canChooseArea)
            #expect(pin().canChooseArea)
            #expect(!pin(idle: true).statusTitle(copy).contains(copy.text(.pictureIdle)))
            #expect(pin(idle: true, notify: true).statusTitle(copy).contains(copy.text(.pictureIdle)))
            #expect(copy.formatted(.frameRateValue, values: ["count": "15"]).contains("15"))
        }
    }

    @Test func restoredPinWaitsForFreshPixelsBeforeOfferingAnArea() {
        var restoring = pin(idle: true, notify: true)
        restoring.isAwaitingFreshFrame = true
        for language in FuwaLanguage.allCases {
            let copy = FuwaCopy(language: language)
            #expect(restoring.stateTitle(copy) == copy.text(.restoringPicture))
            #expect(!restoring.statusTitle(copy).contains(copy.text(.pictureIdle)))
            #expect(!restoring.canChooseArea)
            #expect(restoring.canShowControls)
        }
    }

    @Test func popoverLeavesRoomForScreenEdgesAndUsesTheAvailableDisplay() {
        #expect(PinOptionsPopoverLayout.size(available: CGSize(width: 1512, height: 900)) == CGSize(width: 380, height: 460))
        let small = PinOptionsPopoverLayout.size(available: CGSize(width: 320, height: 300))
        #expect(small.width <= 280 && small.height <= 260)
        let short = PinOptionsPopoverLayout.size(available: CGSize(width: 1200, height: 340))
        #expect(short.width == 380 && short.height == 300)
        #expect(PinOptionsPopoverLayout.size(available: .zero) == CGSize(width: 380, height: 460))
    }

    @Test func appChoicesPreserveSourceAndSelectedAppsAndDeduplicateBundleIDs() {
        let choices = PinApplicationChoice.choices(
            running: [("app.editor", "Editor"), ("app.editor", "Editor (other process)"), ("", "Helper")],
            sourceBundleIdentifier: "app.source", sourceName: "Source",
            selectedBundleIdentifier: "app.closed")
        #expect(choices.count == 3)
        #expect(choices.first(where: { $0.bundleIdentifier == "app.editor" })?.name == "Editor")
        #expect(choices.first(where: { $0.bundleIdentifier == "app.source" })?.name == "Source")
        #expect(choices.contains(where: { $0.bundleIdentifier == "app.closed" }))
        let remembered = PinApplicationChoice.choices(running: [], sourceBundleIdentifier: nil,
            sourceName: "Source", selectedBundleIdentifier: "app.closed", selectedName: "Working Editor")
        #expect(remembered.first?.name == "Working Editor")
    }

    @Test func hideAndRestoreNativeMenuRemainSeparateFromRemovingPins() async throws {
        let app = NSApplication.shared
        let model = AppModel(copy: FuwaCopy(language: .english))
        let snapshots = [pin(), pin(state: .frozen(.manual))]
        model.updatePins(snapshots)
        var visibilityCalls = 0
        var unpinCalls = 0
        var actions = FuwaAppActions()
        actions.togglePinsVisibility = {
            visibilityCalls += 1
            model.updatePinsVisibility(!model.arePinsHidden)
        }
        actions.clearAll = { unpinCalls += 1 }
        model.configure(actions: actions)
        let controller = StatusBarController(model: model, statusItem: nil)
        defer { controller.invalidate() }
        for key in [FuwaString.hideAllPins, .showAllPins] {
            let menu = controller.makeMenu()
            let item = try #require(menu.items.first(where: { $0.identifier?.rawValue == key.rawValue }))
            #expect(item.isEnabled)
            #expect(item.keyEquivalent.isEmpty)
            #expect(menu.items.contains(where: { $0.identifier?.rawValue == FuwaString.clearAll.rawValue }))
            app.sendAction(try #require(item.action), to: controller, from: item)
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while model.isTogglingVisibility, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(5))
            }
            #expect(!model.isTogglingVisibility)
            #expect(model.pins == snapshots)
        }
        #expect(visibilityCalls == 2)
        #expect(unpinCalls == 0)
        #expect(!model.arePinsHidden)
    }

    @Test func controlsStayBoundedForSmallScreensLongTitlesAndAllLanguages() {
        let app = NSApplication.shared
        let visibleWindows = app.windows.filter(\.isVisible).count
        for language in FuwaLanguage.allCases {
            let model = AppModel(copy: FuwaCopy(language: language))
            var options = PinOptions()
            options.notifiesWhenIdle = true
            var snapshot = PinSnapshot(id: UUID(), sourceWindowID: 100,
                applicationName: String(repeating: "Reference App ", count: 8),
                bundleIdentifier: "test.fuwa.reference",
                windowTitle: String(repeating: "窗口の長いタイトル Reference ", count: 12),
                state: .live, errorMessage: nil, options: options, isHidden: true, isIdle: true)
            snapshot.options.presentationMode = .reference
            snapshot.options.applicationScopeBundleIdentifier = "test.fuwa.reference"
            model.updatePins([snapshot])
            for section in PinOptionsSection.allCases {
                for (width, height) in [(CGFloat(380), CGFloat(460)), (320, 300)] {
                    let host = NSHostingView(rootView: PinControlsView(model: model, pinID: snapshot.id,
                        maximumHeight: height, initialSection: section).frame(width: width)
                        .environment(\.dynamicTypeSize, .accessibility3))
                    #expect(abs(host.fittingSize.height - height) <= 1)
                    #expect(abs(host.fittingSize.width - width) <= 1)
                }
            }
        }
        #expect(app.windows.filter(\.isVisible).count == visibleWindows)
    }
}
