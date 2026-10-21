import Defaults
import SwiftUI

/// Freshness thresholds as a draggable scale, with sample pull requests colored by them.
struct FreshnessSettings: View {
    /// The threshold scale: a colored bar with zone names under it and draggable handles on it.
    private enum Scale {
        static let maximumDays = 60
        static let barY: CGFloat = 28
        static let barHeight: CGFloat = 10
        static let handleY: CGFloat = 33
        static let handleLabelOffset: CGFloat = -22
        static let zoneLabelY: CGFloat = 53
    }
    let store: PullRequestStore
    var usernameOverride: String? = nil
    @Default(.freshnessThresholds) private var thresholds
    private var username: String { store.session.connection?.username ?? "" }
    @Default(.botAccounts) private var bots
    @Default(.ownCommentsCount) private var comments
    private var values: [Int] { TimelinePolicy.validThresholds(thresholds) }
    private func position(_ days: Double) -> Double { log1p(days / 2) / log1p(Double(Scale.maximumDays) / 2) }
    @State private var samples: [TimelineItem] = []
    private var sampleInput: TimelineInput {
        store.timelineInput(now: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 60) * 60), thresholds: values, bots: bots, ownComments: comments, snoozed: [:], username: usernameOverride ?? username)
    }
    private func makeSamples(_ input: TimelineInput) -> [TimelineItem] {
        let all = input.makeItems().filter { !$0.isBot && $0.hasKnownQuietPeriod }.sorted { $0.quietDays < $1.quietDays }
        guard !all.isEmpty else { return [] }
        var seen = Set<String>()
        return [0.0, 0.25, 0.5, 0.75, 0.98].compactMap { fraction in
            let item = all[Int(fraction * Double(all.count - 1))]
            return seen.insert(item.id).inserted ? item : nil
        }
    }
    var body: some View {
        VStack(spacing: Spacing.s) {
            GeometryReader { geometry in
                let edges = [0] + values + [Scale.maximumDays]
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { index in
                            Freshness.allCases[index].fill.frame(width: max(0, geometry.size.width * (position(Double(edges[index + 1])) - position(Double(edges[index])))), height: Scale.barHeight)
                        }
                    }.clipShape(Capsule()).offset(y: Scale.barY)
                    ForEach(0..<4, id: \.self) { index in
                        Text(Freshness.allCases[index].rawValue).font(.ui(Typography.footnote)).foregroundStyle(Palette.textSecondary)
                            .position(x: geometry.size.width * (position(Double(edges[index])) + position(Double(edges[index + 1]))) / 2, y: Scale.zoneLabelY)
                    }
                    ForEach(0..<3, id: \.self) { index in
                        ZStack {
                            Circle().fill(Palette.onAccent).overlay(Circle().strokeBorder(Palette.shadow.opacity(Opacity.outline), lineWidth: Stroke.fine)).shadow(color: Palette.shadow.opacity(Opacity.shadowStrong), radius: 2, y: 1)
                            Text(thresholdLabel(values[index])).font(.ui(Typography.footnote, .semibold)).foregroundStyle(Palette.textPrimary).fixedSize().offset(y: Scale.handleLabelOffset)
                        }.frame(width: Size.handle, height: Size.handle).position(x: geometry.size.width * position(Double(values[index])), y: Scale.handleY)
                            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("freshness")).onChanged { value in
                                set(index, days: Int((2 * expm1(min(1, max(0, value.location.x / geometry.size.width)) * log1p(30))).rounded()))
                            })
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(Freshness.allCases[index + 1].rawValue) after")
                            .accessibilityValue("\(values[index]) days")
                            .accessibilityAdjustableAction { direction in set(index, days: values[index] + (direction == .increment ? 1 : -1)) }
                    }
                }.coordinateSpace(name: "freshness")
            }.frame(height: Layout.freshnessScaleHeight).padding(.horizontal, Spacing.l)
            ForEach(samples) { item in
                HStack(spacing: Spacing.l) {
                    Text(item.title).font(.ui(Typography.callout)).foregroundStyle(Palette.textSecondary).lineLimit(1).frame(width: Layout.freshnessSampleTitleWidth, alignment: .leading)
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: Radius.s).fill(Palette.track).overlay(RoundedRectangle(cornerRadius: Radius.s).strokeBorder(Palette.line))
                        TimelineHatching(color: item.freshness.fill).frame(width: max(6, min(geometry.size.width, geometry.size.width * position(item.quietDays)))).frame(maxWidth: .infinity, alignment: .trailing).padding(Spacing.xxs)
                    }.frame(height: Layout.freshnessSampleHeight)
                    Text("\(TimelinePolicy.duration(item.quietDays)) · \(item.freshness.rawValue)").font(.ui(Typography.callout, .semibold)).foregroundStyle(item.freshness.label).frame(width: 92, alignment: .trailing)
                }
            }
        }
        .onChange(of: sampleInput, initial: true) { _, value in samples = makeSamples(value) }
    }
    private func thresholdLabel(_ days: Int) -> String { days >= 14 && days % 7 == 0 ? "\(days / 7)w" : "\(days)d" }
    private func set(_ index: Int, days: Int) {
        var next = values
        next[index] = min(index == 2 ? Scale.maximumDays : next[index + 1] - 1, max(index == 0 ? 1 : next[index - 1] + 1, days))
        if thresholds != next { thresholds = next }
    }
}
