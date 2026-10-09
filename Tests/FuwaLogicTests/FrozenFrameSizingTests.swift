import FuwaCore

func runFrozenFrameSizingTests(runner: inout LogicTestRunner) {
    runner.expect(
        CaptureQuality.default.maximumPixelCount == 4_000_000,
        "existing users and new installations retain the four-million-pixel default"
    )
    let qualityDimensions: [(CaptureQuality, PixelDimensions)] = [
        (.fourMegapixels, PixelDimensions(width: 2_666, height: 1_500)),
        (.nineMegapixels, PixelDimensions(width: 4_000, height: 2_250)),
        (.sixteenMegapixels, PixelDimensions(width: 5_120, height: 2_880)),
        (.native, PixelDimensions(width: 5_120, height: 2_880))
    ]
    for (quality, expected) in qualityDimensions {
        runner.expect(
            LiveCaptureSizing.fittedDimensions(
                pointWidth: 2_560, pointHeight: 1_440, pointScale: 2,
                maxPixels: quality.maximumPixelCount
            ) == expected,
            "live Retina capture follows the \(quality.rawValue) pixel limit"
        )
        runner.expect(
            FrozenFrameSizing.fittedDimensions(
                sourceWidth: 5_120, sourceHeight: 2_880,
                maxPixels: quality.maximumPixelCount
            ) == expected,
            "frozen capture uses the same \(quality.rawValue) pixel limit"
        )
    }
    runner.expect(
        LiveCaptureSizing.fittedDimensions(
            pointWidth: 1_920, pointHeight: 1_080, pointScale: 2,
            maxPixels: CaptureQuality.nineMegapixels.maximumPixelCount
        ) == PixelDimensions(width: 3_840, height: 2_160),
        "nine million pixels preserve a native 4K surface"
    )
    runner.expect(
        LiveCaptureSizing.fittedDimensions(
            pointWidth: 3_008, pointHeight: 1_692, pointScale: 2,
            maxPixels: CaptureQuality.native.maximumPixelCount
        ) == PixelDimensions(width: 6_016, height: 3_384),
        "native resolution preserves a 6K surface beyond the sixteen-million-pixel preset"
    )
    runner.expect(
        FrozenFrameSizing.fittedDimensions(
            sourceWidth: .max, sourceHeight: 2, maxPixels: nil
        ) == nil,
        "native sizing rejects overflowing pixel counts"
    )
    runner.expect(
        FrozenFrameSizing.fittedDimensions(
            sourceWidth: 1_920,
            sourceHeight: 1_080,
            maxPixels: 4_000_000
        ) == PixelDimensions(width: 1_920, height: 1_080),
        "frozen frames below the pixel budget keep their native dimensions"
    )

    runner.expect(
        FrozenFrameSizing.fittedDimensions(
            sourceWidth: 2_000,
            sourceHeight: 2_000,
            maxPixels: 4_000_000
        ) == PixelDimensions(width: 2_000, height: 2_000),
        "frozen frames exactly at the pixel budget are not resampled"
    )

    let reduced = FrozenFrameSizing.fittedDimensions(
        sourceWidth: 6_000,
        sourceHeight: 4_000,
        maxPixels: 4_000_000
    )
    runner.expect(
        reduced == PixelDimensions(width: 2_449, height: 1_632),
        "oversized frozen frames are reduced proportionally"
    )
    runner.expect(
        (reduced?.pixelCount ?? .max) <= 4_000_000,
        "the reduced frozen frame never exceeds its pixel budget"
    )

    runner.expect(
        FrozenFrameSizing.fittedDimensions(
            sourceWidth: 1,
            sourceHeight: 10_000,
            maxPixels: 1
        ) == PixelDimensions(width: 1, height: 1),
        "extreme aspect ratios retain at least one pixel on each axis"
    )

    runner.expect(
        FrozenFrameSizing.fittedDimensions(
            sourceWidth: 10_000,
            sourceHeight: 1,
            maxPixels: 1
        ) == PixelDimensions(width: 1, height: 1),
        "extreme landscape frames also stay inside the pixel budget"
    )

    runner.expect(
        FrozenFrameSizing.fittedDimensions(
            sourceWidth: 0,
            sourceHeight: 1_080,
            maxPixels: 4_000_000
        ) == nil,
        "invalid source dimensions cannot produce a frozen frame size"
    )

    runner.expect(
        FrozenFrameSizing.fittedDimensions(
            sourceWidth: 1_920,
            sourceHeight: 1_080,
            maxPixels: 0
        ) == nil,
        "a non-positive pixel budget is rejected"
    )

    runner.expect(
        LiveCaptureSizing.fittedDimensions(
            pointWidth: 1_920,
            pointHeight: 1_080,
            pointScale: 1
        ) == PixelDimensions(width: 1_920, height: 1_080),
        "a live capture inside the pixel budget keeps its requested dimensions"
    )

    let reducedLiveCapture = LiveCaptureSizing.fittedDimensions(
        pointWidth: 3_840,
        pointHeight: 2_160,
        pointScale: 2
    )
    runner.expect(
        reducedLiveCapture == PixelDimensions(width: 2_666, height: 1_500),
        "an 8K live capture is reduced proportionally"
    )
    runner.expect(
        (reducedLiveCapture?.pixelCount ?? .max) <= LiveCaptureSizing.maximumPixelCount,
        "a live capture never exceeds the shared four-megapixel budget"
    )

    let extremeLiveCapture = LiveCaptureSizing.fittedDimensions(
        pointWidth: 1,
        pointHeight: 10_000_000,
        pointScale: 2
    )
    runner.expect(
        extremeLiveCapture?.width == 2
            && (extremeLiveCapture?.pixelCount ?? .max)
                <= LiveCaptureSizing.maximumPixelCount,
        "extreme live-capture aspect ratios keep usable axes inside the budget"
    )

    runner.expect(
        LiveCaptureSizing.fittedDimensions(
            pointWidth: .infinity,
            pointHeight: 1_080,
            pointScale: 2
        ) == nil,
        "non-finite live-capture geometry is rejected"
    )
}
