import AppKit
import AVFoundation
import FuwaCore
import ScreenCaptureKit
import Testing
@testable import Fuwa

@MainActor
struct CaptureQualityTests {
    @Test func streamConfigurationScalesNativePixels() throws {
        for percentage in [25, 37, 50, 75, 100] {
            let quality = try #require(CaptureQuality(percentage: percentage))
            let configuration = PinSession.makeConfiguration(
                pointSize: CGSize(width: 2_560, height: 1_440), pointScale: 2,
                captureQuality: quality
            )
            #expect(configuration.width == 5_120 * percentage / 100)
            #expect(configuration.height == 2_880 * percentage / 100)
            #expect(configuration.queueDepth == 3)
            #expect(configuration.minimumFrameInterval == CMTime(value: 1, timescale: 30))
            if quality == .native { #expect(configuration.captureResolution == .best) }
        }
    }

    @Test func pausedImageCopiesCapturedPixelsWithoutFurtherReduction() throws {
        _ = NSApplication.shared
        var pixelBuffer: CVPixelBuffer?
        #expect(CVPixelBufferCreate(nil, 3_840, 2_160, kCVPixelFormatType_32BGRA,
                                  nil, &pixelBuffer) == kCVReturnSuccess)
        let pixels = try #require(pixelBuffer)
        var format: CMVideoFormatDescription?
        #expect(CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil, imageBuffer: pixels, formatDescriptionOut: &format
        ) == noErr)
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid
        )
        #expect(CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil, imageBuffer: pixels, formatDescription: try #require(format),
            sampleTiming: &timing, sampleBufferOut: &sample
        ) == noErr)
        let buffer = try #require(sample)
        let attachments = try #require(CMSampleBufferGetSampleAttachmentsArray(
            buffer, createIfNecessary: true
        ))
        let metadata = unsafeBitCast(
            CFArrayGetValueAtIndex(attachments, 0), to: NSMutableDictionary.self
        )
        metadata[SCStreamFrameInfo.status.rawValue] = SCFrameStatus.complete.rawValue
        let view = CaptureView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        defer { view.clearAllPixels() }
        #expect(view.consume(buffer) != nil)
        let defaultImage = try view.makeFrozenImage()
        #expect(defaultImage.width == 3_840 && defaultImage.height == 2_160)
    }
}
