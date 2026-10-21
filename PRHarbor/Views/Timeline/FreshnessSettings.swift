import SwiftUI
import Defaults

/// Freshness thresholds as a draggable scale, with sample pull requests colored by them.
struct FreshnessSettings: View {
    let store: PullRequestStore
    var usernameOverride: String? = nil
    @Default(.freshnessThresholds) private var thresholds
    private var username: String { store.session.connection?.username ?? "" }
    @Default(.botAccounts) private var bots
    @Default(.ownCommentsCount) private var comments
    private var values: [Int] { TimelinePolicy.validThresholds(thresholds) }
    private func position(_ days: Double) -> Double { log1p(days / 2) / log1p(60 / 2) }
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
        VStack(spacing: 6) {
            GeometryReader { geometry in
                let edges = [0] + values + [60]
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { index in
                            Freshness.allCases[index].color.frame(width: max(0, geometry.size.width * (position(Double(edges[index + 1])) - position(Double(edges[index])))), height: 10)
                        }
                    }.clipShape(Capsule()).offset(y: 28)
                    ForEach(0..<4, id: \.self) { index in
                        Text(Freshness.allCases[index].rawValue).font(.system(size: 11)).foregroundStyle(TimelineStyle.muted)
                            .position(x: geometry.size.width * (position(Double(edges[index])) + position(Double(edges[index + 1]))) / 2, y: 53)
                    }
                    ForEach(0..<3, id: \.self) { index in
                        ZStack {
                            Circle().fill(.white).overlay(Circle().strokeBorder(.black.opacity(0.2), lineWidth: 0.5)).shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                            Text(thresholdLabel(values[index])).font(.system(size: 11, weight: .semibold)).foregroundStyle(TimelineStyle.text).fixedSize().offset(y: -22)
                        }.frame(width: 18, height: 18).position(x: geometry.size.width * position(Double(values[index])), y: 33)
                            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("freshness")).onChanged { value in
                                set(index, days: Int((2 * expm1(min(1, max(0, value.location.x / geometry.size.width)) * log1p(30))).rounded()))
                            })
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(Freshness.allCases[index + 1].rawValue) after")
                            .accessibilityValue("\(values[index]) days")
                            .accessibilityAdjustableAction { direction in set(index, days: values[index] + (direction == .increment ? 1 : -1)) }
                    }
                }.coordinateSpace(name: "freshness")
            }.frame(height: 68).padding(.horizontal, 10)
            ForEach(samples) { item in
                HStack(spacing: 10) {
                    Text(item.title).font(.system(size: 12)).foregroundStyle(TimelineStyle.muted).lineLimit(1).frame(width: 170, alignment: .leading)
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 6).fill(TimelineStyle.track).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(TimelineStyle.line))
                        TimelineHatching(color: item.freshness.color).frame(width: max(6, min(geometry.size.width, geometry.size.width * position(item.quietDays)))).frame(maxWidth: .infinity, alignment: .trailing).padding(3)
                    }.frame(height: 18)
                    Text("\(TimelinePolicy.duration(item.quietDays)) · \(item.freshness.rawValue)").font(.system(size: 12, weight: .semibold)).foregroundStyle(item.freshness.color).frame(width: 92, alignment: .trailing)
                }
            }
        }
        .onChange(of: sampleInput, initial: true) { _, value in samples = makeSamples(value) }
    }
    private func thresholdLabel(_ days: Int) -> String { days >= 14 && days % 7 == 0 ? "\(days / 7)w" : "\(days)d" }
    private func set(_ index: Int, days: Int) {
        var next = values
        next[index] = min(index == 2 ? 60 : next[index + 1] - 1, max(index == 0 ? 1 : next[index - 1] + 1, days))
        if thresholds != next { thresholds = next }
    }
}

struct TimelineHatching: View {
    let color: Color
    var body: some View {
        Canvas { context, size in
            let rect = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4)
            context.fill(rect, with: .color(color.opacity(0.15)))
            context.stroke(rect, with: .color(color.opacity(0.45)), lineWidth: 1)
            context.clip(to: rect)
            for x in stride(from: -size.height, to: size.width + size.height, by: 6 * sqrt(2.0)) {
                var line = Path(); line.move(to: CGPoint(x: x, y: size.height)); line.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(line, with: .color(color.opacity(0.55)), lineWidth: 2)
            }
        }.accessibilityHidden(true)
    }
}
