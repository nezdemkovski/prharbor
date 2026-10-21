import SwiftUI

struct TimelineSummary: View {
    let items: [TimelineItem]
    @Binding var zone: Freshness?
    var body: some View {
        HStack(spacing: Spacing.xxl) {
            HStack(spacing: Spacing.xxxs) {
                ForEach(Freshness.allCases) { freshness in
                    let count = items.filter { $0.snoozedUntil == nil && $0.hasKnownQuietPeriod && $0.freshness == freshness }.count
                    Toggle(isOn: Binding(get: { zone == freshness }, set: { zone = $0 ? freshness : nil })) {
                        HStack(spacing: Spacing.xs) {
                            Circle().fill(freshness.fill).frame(width: Size.dot, height: Size.dot)
                            Text(freshness.rawValue)
                            Text("\(count)").fontWeight(.semibold).foregroundStyle(Palette.textPrimary)
                        }
                    }
                    .toggleStyle(.chip)
                    .disabled(count == 0 && zone != freshness)
                }
            }
            .controlTrack()
            let people = Set(items.filter { !$0.isMine && !$0.isBot && $0.reviewRequested && $0.snoozedUntil == nil }.compactMap { $0.pull.author?.login }).count
            if people > 0 {
                Text("blocking **\(people)** \(people == 1 ? "person" : "people")").font(.ui(Typography.callout)).foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .monospacedDigit()
    }
}
