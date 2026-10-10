import FuwaCore
import SwiftUI

@MainActor
struct PinQualityControls: View {
    @ObservedObject var model: AppModel
    let pin: PinSnapshot

    private var copy: FuwaCopy { model.copy }
    private var canAdjust: Bool {
        pin.canAdjustQuality && !model.busyPinIDs.contains(pin.id) && !model.isClearingAll
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    qualityHeading
                    Spacer(minLength: 6)
                    qualityValue
                }
                VStack(alignment: .leading, spacing: 4) {
                    qualityHeading
                    qualityValue
                }
            }
            Slider(value: Binding(
                get: { Double(pin.captureQuality.percentage) },
                set: { value in
                    if let quality = CaptureQuality(percentage: Int(value.rounded())) {
                        model.setCaptureQuality(quality, for: pin.id)
                    }
                }
            ), in: Double(CaptureQuality.minimumPercentage)...100)
            .tint(FuwaAppearance.ink)
            .disabled(!canAdjust)
            .accessibilityLabel(copy.text(.captureQuality))
            .accessibilityValue(copy.captureQualityLabel(pin.captureQuality))
            .accessibilityHint(copy.text(.captureQualityHelp))
            .help(copy.text(.captureQualityHelp))
            HStack {
                Text(copy.text(.qualityLower))
                Spacer(minLength: 6)
                Text(copy.text(.qualityHigher))
            }
            .font(.caption2)
            .foregroundStyle(FuwaAppearance.secondaryText)
            .accessibilityHidden(true)
        }
    }

    private var qualityHeading: some View {
        HStack(spacing: 4) {
            Text(copy.text(.captureQuality)).font(.caption.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            FuwaHelpIcon(title: copy.text(.captureQuality), text: copy.text(.captureQualityHelp))
        }
    }

    private var qualityValue: some View {
        Text(copy.captureQualityLabel(pin.captureQuality))
            .font(.caption).monospacedDigit()
            .foregroundStyle(FuwaAppearance.secondaryText)
            .fixedSize()
    }
}
