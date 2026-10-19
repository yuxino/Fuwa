import SwiftUI

/// A task-oriented first run page, also available from the sidebar at any time.
@MainActor
struct GettingStartedView: View {
    @ObservedObject var model: AppModel
    private var copy: FuwaCopy { model.copy }
    private var permissionReady: Bool { model.screenRecordingPermission == .granted }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(copy.text(.guideTitle))
                            .font(.system(size: 22, weight: .semibold))
                        Text(copy.text(.guideIntroduction))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    GuidePictureIllustration().frame(height: 62)

                    VStack(spacing: 14) {
                        step(1, title: .guidePermissionTitle, body: .guidePermissionBody) {
                            if permissionReady {
                                Label(copy.text(.ready), systemImage: "checkmark")
                                    .font(.caption.weight(.medium))
                            } else {
                                Button(copy.text(model.screenRecordingPermission == .unknown ? .allowScreenRecording : .openSettings),
                                       action: model.requestScreenRecordingPermission)
                                    .buttonStyle(FuwaPlainButtonStyle())
                            }
                        }
                        step(2, title: .guideChooseTitle, body: .guideChooseBody) {
                            if model.shortcutIsActive {
                                Text(model.shortcut.displayString)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .help(copy.text(.shortcutNote))
                            }
                        }
                        step(3, title: .guideReferenceTitle, body: .guideReferenceBody) {
                            EmptyView()
                        }
                    }

                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .scrollIndicatorsFlash(onAppear: true)
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { chooseButton; laterButton; Spacer(minLength: 0) }
                VStack(alignment: .leading, spacing: 12) { chooseButton; laterButton }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
        }
    }

    private var chooseButton: some View {
        Button(action: model.chooseWindow) {
            Label(copy.text(.chooseWindow), systemImage: "plus")
        }
        .buttonStyle(FuwaPrimaryButtonStyle(expands: false))
        .disabled(!permissionReady || model.isPinningFrontWindow || model.isClearingAll)
    }

    private var laterButton: some View {
        Button(copy.text(permissionReady ? .guideDone : .guideLater), action: model.showPins)
            .buttonStyle(FuwaPlainButtonStyle())
            .help(copy.text(.guideReturnHint))
    }

    private func step<Accessory: View>(_ number: Int, title: FuwaString, body: FuwaString,
                                      @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(number)).font(.system(.caption, design: .monospaced).weight(.medium))
                .frame(width: 22, height: 22)
                .background(Color.black.opacity(0.045), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(copy.text(title)).font(.body.weight(.medium))
                Text(copy.text(body)).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                accessory()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Original, deliberately minimal diagram; no captured windows or external assets.
private struct GuidePictureIllustration: View {
    var body: some View {
        HStack(spacing: 18) {
            picture(width: 108, height: 60)
            Image(systemName: "arrow.right").font(.system(size: 15, weight: .light))
                .foregroundStyle(.secondary)
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(FuwaAppearance.border, lineWidth: 1)
                    .frame(width: 108, height: 60)
                picture(width: 60, height: 38).padding(5)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func picture(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(0..<3) { _ in Circle().fill(Color.black.opacity(0.25)).frame(width: 3, height: 3) }
            }
            Divider()
            RoundedRectangle(cornerRadius: 1).fill(Color.black.opacity(0.16)).frame(width: width * 0.55, height: 3)
            RoundedRectangle(cornerRadius: 1).fill(Color.black.opacity(0.08)).frame(width: width * 0.38, height: 3)
            Spacer(minLength: 0)
        }
        .padding(8).frame(width: width, height: height)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.5), lineWidth: 1))
    }
}
