import SwiftUI

/// The recessed track that holds segments or chips.
struct ControlTrack: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Spacing.xxs)
            .background(Palette.track, in: RoundedRectangle(cornerRadius: Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Palette.line))
    }
}

extension View {
    func controlTrack() -> some View { modifier(ControlTrack()) }
}

/// The raised surface of a selected segment or chip, and the pointer highlight of the others.
struct SegmentSurface: View {
    let isSelected: Bool
    let isPressed: Bool
    let hovering: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.s)
        if isSelected {
            shape.fill(Palette.raised)
                .shadow(color: Palette.shadow.opacity(Opacity.shadowSoft), radius: 1, y: 1)
                .overlay(shape.strokeBorder(Palette.strong, lineWidth: 1))
        } else if isPressed || hovering {
            shape.fill(isPressed ? Palette.active : Palette.hover)
        }
    }
}

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
