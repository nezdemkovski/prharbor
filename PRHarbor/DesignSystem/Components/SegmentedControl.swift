import SwiftUI

/// One option of a `SegmentedControl`.
struct SegmentButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Segment(configuration: configuration, isSelected: isSelected)
    }

    private struct Segment: View {
        let configuration: Configuration
        let isSelected: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.ui(Typography.callout, .medium))
                .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                .padding(.horizontal, Spacing.l).frame(height: Size.control)
                .background { SegmentSurface(isSelected: isSelected, isPressed: configuration.isPressed, hovering: hovering) }
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

/// A row of mutually exclusive options in a track. A count follows the title in a quieter color.
struct SegmentedControl<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [(value: Value, title: String, count: Int?)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = selection == option.value
                Button { selection = option.value } label: {
                    HStack(spacing: Spacing.xs) {
                        Text(option.title)
                        if let count = option.count { Text("\(count)").foregroundStyle(Palette.textTertiary) }
                    }
                }
                .buttonStyle(SegmentButtonStyle(isSelected: isSelected))
                .accessibilityLabel(option.title + (option.count.map { ", \($0) pull requests" } ?? ""))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .controlTrack()
        .accessibilityElement(children: .contain).accessibilityLabel(label)
        .fixedSize()
    }
}
