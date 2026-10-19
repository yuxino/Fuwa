import AppKit
import Foundation
import FuwaCore
import SwiftUI
import Testing
@testable import Fuwa

@Suite(.serialized)
@MainActor
struct ReferenceConvenienceOptionsTests {
    @Test func legacyOptionsKeepThePreviousPresentationDefaults() throws {
        let legacy = Data(#"{"presentationMode":"reference","captureRegion":{"x":0.1,"y":0.2,"width":0.5,"height":0.4},"spaceScope":"currentSpace","applicationScopeBundleIdentifier":"test.editor","frameRate":15,"reducesFrameRateWhenIdle":false,"notifiesWhenIdle":true}"#.utf8)
        let options = try JSONDecoder().decode(PinOptions.self, from: legacy)
        #expect(options.presentationMode == .reference)
        #expect(options.captureRegion == NormalizedCaptureRegion(x: 0.1, y: 0.2, width: 0.5, height: 0.4))
        #expect(options.spaceScope == .currentSpace)
        #expect(options.applicationScopeBundleIdentifier == "test.editor")
        #expect(options.frameRate == .fifteen)
        #expect(!options.reducesFrameRateWhenIdle && options.notifiesWhenIdle)
        #expect(options.opacity == 1)
        #expect(!options.previewsOnHover)
        #expect(try JSONDecoder().decode(PinOptions.self, from: Data("{}".utf8)) == PinOptions())
    }

    @Test func opacityAlwaysKeepsTheReferenceVisibleAndRejectsNonFiniteValues() throws {
        var options = PinOptions()
        for (input, expected) in [(0.0, 0.2), (-1, 0.2), (0.65, 0.65), (2, 1), (.infinity, 1), (-.infinity, 1), (.nan, 1)] {
            options.opacity = input
            #expect(options.opacity == expected)
        }
        let low = try JSONDecoder().decode(PinOptions.self, from: Data(#"{"opacity":-10}"#.utf8))
        let high = try JSONDecoder().decode(PinOptions.self, from: Data(#"{"opacity":5}"#.utf8))
        #expect(low.opacity == 0.2)
        #expect(high.opacity == 1)
        options.opacity = 0.55
        options.previewsOnHover = true
        let restored = try JSONDecoder().decode(PinOptions.self, from: JSONEncoder().encode(options))
        #expect(restored == options)
    }

    @Test func convenienceCopyIsCompleteInAllSevenLanguages() {
        let keys: [FuwaString] = [.openSourceApplication, .openSourceApplicationHelp, .hoverPreview, .hoverPreviewHelp,
                                  .opacity, .opacityHelp, .referenceSize, .referenceSizeSmall,
                                  .referenceSizeMedium, .referenceSizeLarge, .holdToHide, .holdToHideNote]
        for language in FuwaLanguage.allCases {
            let copy = FuwaCopy(language: language)
            for key in keys {
                #expect(copy.hasTranslation(for: key))
                #expect(!copy.text(key).isEmpty && copy.text(key) != key.rawValue)
            }
        }
    }

    @Test func referenceConveniencesRemainBoundedForLongCopyAndSmallScreens() {
        _ = NSApplication.shared
        for language in FuwaLanguage.allCases {
            let model = AppModel(copy: FuwaCopy(language: language))
            var options = PinOptions()
            options.presentationMode = .reference
            options.opacity = 0.65
            options.previewsOnHover = true
            let pin = PinSnapshot(id: UUID(), sourceWindowID: 100, applicationName: "Reference",
                bundleIdentifier: nil, windowTitle: String(repeating: "Reference window ", count: 10),
                state: .live, errorMessage: nil, options: options)
            model.updatePins([pin])
            for (width, height) in [(CGFloat(320), CGFloat(460)), (280, 300)] {
                let host = NSHostingView(rootView: PinControlsView(model: model, pinID: pin.id, maximumHeight: height,
                    initialSection: .visibility)
                    .frame(width: width).environment(\.dynamicTypeSize, .accessibility3))
                #expect(host.fittingSize.height <= height + 1)
                #expect(abs(host.fittingSize.width - width) <= 1)
            }
        }
    }
}
