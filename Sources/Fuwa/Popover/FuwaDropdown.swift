import AppKit
import SwiftUI

private struct FuwaDropdownPresentation {
    let id: UUID
    let anchor: Anchor<CGRect>
    let content: AnyView
    let height: CGFloat
    let minimumWidth: CGFloat
    let dismiss: () -> Void
}

private struct FuwaDropdownPreference: PreferenceKey {
    static var defaultValue: [FuwaDropdownPresentation] { [] }

    static func reduce(value: inout [FuwaDropdownPresentation], nextValue: () -> [FuwaDropdownPresentation]) {
        value.append(contentsOf: nextValue())
    }
}

/// A neutral dropdown shared by settings, presented above the scroll view.
struct FuwaDropdown<Option: Hashable>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    let optionLabel: (Option) -> String
    var help = ""
    var minimumWidth: CGFloat = 240

    @State private var id = UUID()
    @State private var isShowing = false
    @FocusState private var focusedOption: Option?
    @FocusState private var triggerIsFocused: Bool
    @ScaledMetric(relativeTo: .callout) private var rowHeight = 30

    var body: some View {
        Button { isShowing.toggle() } label: {
            HStack(spacing: 10) {
                Text(optionLabel(selection))
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(minWidth: 162)
        }
        .buttonStyle(FuwaQuietButtonStyle(focusColor: FuwaAppearance.ink.opacity(0.4)))
        .focusable()
        .focusEffectDisabled()
        .focused($triggerIsFocused)
        .anchorPreference(key: FuwaDropdownPreference.self, value: .bounds) { anchor in
            isShowing ? [FuwaDropdownPresentation(id: id, anchor: anchor,
                content: AnyView(choices), height: rowHeight * CGFloat(options.count) + 8,
                minimumWidth: minimumWidth, dismiss: { isShowing = false })] : []
        }
        .help(help)
        .accessibilityLabel(title)
        .accessibilityValue(optionLabel(selection))
        .accessibilityHint(help)
        .onDisappear { isShowing = false }
        .onChange(of: isShowing) { _, showing in
            if !showing {
                focusedOption = nil
                triggerIsFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            isShowing = false
        }
    }

    private var choices: some View {
        VStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let selected = selection == option
                Button {
                    selection = option
                    isShowing = false
                } label: {
                    HStack(spacing: 10) {
                        Text(optionLabel(option))
                            .font(.callout.weight(selected ? .medium : .regular))
                        Spacer(minLength: 0)
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.semibold))
                            .opacity(selected ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(FuwaRowButtonStyle(selected: selected, focusColor: FuwaAppearance.ink.opacity(0.4)))
                .focusable()
                .focusEffectDisabled()
                .focused($focusedOption, equals: option)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(FuwaAppearance.canvas, in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .onAppear { focusedOption = selection }
        .onKeyPress(.downArrow) { moveFocus(by: 1); return .handled }
        .onKeyPress(.upArrow) { moveFocus(by: -1); return .handled }
        .onKeyPress(.return) {
            if let focusedOption { selection = focusedOption }
            isShowing = false
            return .handled
        }
        .onKeyPress(.escape) { isShowing = false; return .handled }
    }

    private func moveFocus(by offset: Int) {
        guard !options.isEmpty else { return }
        let current = options.firstIndex(of: focusedOption ?? selection) ?? 0
        focusedOption = options[(current + offset + options.count) % options.count]
    }
}

private struct FuwaDropdownHost: ViewModifier {
    func body(content: Content) -> some View {
        content.overlayPreferenceValue(FuwaDropdownPreference.self) { presentations in
            if let presentation = presentations.last {
                GeometryReader { geometry in
                    let bounds = geometry[presentation.anchor]
                    let width = min(max(bounds.width, presentation.minimumWidth), geometry.size.width - 16)
                    let below = bounds.maxY + 4
                    let y = below + presentation.height <= geometry.size.height - 8
                        ? below : max(8, bounds.minY - presentation.height - 4)

                    Color.clear.contentShape(Rectangle())
                        .onTapGesture(perform: presentation.dismiss)
                        .accessibilityHidden(true)
                    presentation.content
                        .id(presentation.id)
                        .frame(width: width)
                        .offset(x: max(8, min(bounds.maxX - width, geometry.size.width - width - 8)), y: y)
                }
            }
        }
    }
}

extension View {
    func fuwaDropdowns() -> some View { modifier(FuwaDropdownHost()) }
}
