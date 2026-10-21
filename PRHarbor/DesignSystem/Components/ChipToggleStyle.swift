import SwiftUI

/// A chip that filters the list while it is on.
struct ChipToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Chip(configuration: configuration)
    }

    private struct Chip: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            Button { configuration.isOn.toggle() } label: {
                configuration.label
                    .font(.ui(Typography.callout)).foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, Spacing.m).frame(height: Size.chip)
                    .background { SegmentSurface(isSelected: configuration.isOn, isPressed: false, hovering: hovering && isEnabled) }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isEnabled ? 1 : Opacity.disabled)
            .onHover { hovering = $0 }
            .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
        }
    }
}

extension ToggleStyle where Self == ChipToggleStyle {
    static var chip: ChipToggleStyle { ChipToggleStyle() }
}
