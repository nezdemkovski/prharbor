import SwiftUI

struct TimelineSummary: View {
    let items: [TimelineItem]
    @Binding var zone: Freshness?
    var body: some View {
        HStack(spacing: Spacing.xxl) {
            HStack(spacing: Spacing.xxxs) {
                ForEach(Freshness.allCases) { freshness in
                    let count = items.filter { $0.snoozedUntil == nil && $0.hasKnownQuietPeriod && $0.freshness == freshness }.count
                    Button {
                        zone = zone == freshness ? nil : freshness
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Circle().fill(freshness.fill).frame(width: Size.dot, height: Size.dot)
                            Text(freshness.rawValue)
                            Text("\(count)").fontWeight(.semibold).foregroundStyle(Palette.textPrimary)
                        }
                        .font(.ui(Typography.callout)).foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.xxs).frame(height: Size.chip)
                        .background(zone == freshness ? Palette.raised : .clear, in: RoundedRectangle(cornerRadius: Radius.s))
                        .overlay { if zone == freshness { RoundedRectangle(cornerRadius: Radius.s).strokeBorder(Palette.strong) } }
                    }
                    .buttonStyle(.plain)
                    .disabled(count == 0 && zone != freshness).opacity(count == 0 ? 0.45 : 1)
                    .accessibilityAddTraits(zone == freshness ? [.isSelected] : [])
                }
            }
            .padding(Spacing.xxs).background(Palette.track, in: RoundedRectangle(cornerRadius: Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Palette.line))
            let people = Set(items.filter { !$0.isMine && !$0.isBot && $0.reviewRequested && $0.snoozedUntil == nil }.compactMap { $0.pull.author?.login }).count
            if people > 0 {
                Text("blocking **\(people)** \(people == 1 ? "person" : "people")").font(.ui(Typography.callout)).foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .monospacedDigit()
    }
}
