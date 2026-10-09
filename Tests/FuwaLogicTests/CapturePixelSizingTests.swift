import FuwaCore

func runCapturePixelSizingTests(runner: inout LogicTestRunner) {
    runner.expect(CaptureQuality.default == .native, "new captures retain native pixels by default")
    for percentage in [25, 37, 50, 75, 100] {
        let quality = CaptureQuality(percentage: percentage)!
        runner.expect(CaptureQuality(rawValue: quality.rawValue) == quality, "arbitrary quality percentages round-trip")
        let expected = PixelDimensions(width: 5_120 * percentage / 100, height: 2_880 * percentage / 100)
        runner.expect(LiveCaptureSizing.fittedDimensions(
            pointWidth: 2_560, pointHeight: 1_440, pointScale: 2, quality: quality
        ) == expected, "Retina capture scales each native axis by \(percentage)%")
    }
    for invalid in [0, 24, 101, Int.max] {
        runner.expect(CaptureQuality(percentage: invalid) == nil, "out-of-range percentages are rejected")
    }
    runner.expect(CaptureQuality(rawValue: "native") == .native, "the existing native preference remains readable")
    runner.expect(CaptureQuality(rawValue: "4mp") == nil, "retired pixel budgets no longer define picture quality")
    runner.expect(LiveCaptureSizing.fittedDimensions(pointWidth: 3_008, pointHeight: 1_692, pointScale: 2)
        == PixelDimensions(width: 6_016, height: 3_384), "native capture keeps 6K pixels beyond old preset limits")
    runner.expect(CapturePixelSizing.fittedDimensions(sourceWidth: .max, sourceHeight: 2) == nil,
                  "overflowing pixel counts are rejected")
    runner.expect(CapturePixelSizing.fittedDimensions(sourceWidth: .max, sourceHeight: 1)?.width == .max,
                  "native sizing preserves valid large integers without floating-point rounding")
    runner.expect(CapturePixelSizing.fittedDimensions(sourceWidth: 1, sourceHeight: 9, quality: CaptureQuality(percentage: 25)!)
        == PixelDimensions(width: 1, height: 2), "very thin images keep at least one pixel on each axis")
    runner.expect(LiveCaptureSizing.fittedDimensions(pointWidth: 1, pointHeight: 9, pointScale: 1, quality: CaptureQuality(percentage: 25)!)
        == PixelDimensions(width: 2, height: 2), "capture streams retain useful non-zero axes")
    runner.expect(CapturePixelSizing.fittedDimensions(sourceWidth: 0, sourceHeight: 1_080) == nil,
                  "invalid source dimensions are rejected")
    for scale in [0.0, -1.0, Double.nan, .infinity] {
        runner.expect(LiveCaptureSizing.fittedDimensions(pointWidth: 1_920, pointHeight: 1_080, pointScale: scale) == nil,
                      "invalid display scales are rejected")
    }
    for width in [0.0, -1.0, Double.nan, .infinity, Double(Int.max)] {
        runner.expect(LiveCaptureSizing.fittedDimensions(pointWidth: width, pointHeight: 1_080, pointScale: 2) == nil,
                      "invalid or overflowing capture geometry is rejected")
    }
}
