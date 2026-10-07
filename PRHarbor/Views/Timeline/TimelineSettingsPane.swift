import SwiftUI
import Defaults
import LaunchAtLogin

struct TimelineSettingsPane: View {
    let destination: SettingsDestination
    @ObservedObject var store: PullRequestStore
    var usernameOverride: String? = nil
    @Default(.showRequested) private var requested
    @Default(.showAssigned) private var assigned
    @Default(.showCreated) private var created
    @Default(.hideDrafts) private var hideDrafts
    @Default(.sortOrder) private var sort
    @Default(.buildType) private var buildType
    @Default(.timelineRange) private var range
    @Default(.ownCommentsCount) private var comments
    @Default(.mergedLayersStyle) private var merged
    @Default(.wakeOnComment) private var wake
    @Default(.counterType) private var counter
    @Default(.refreshRate) private var refresh
    @Default(.notifyReviewRequested) private var notifyReview
    @Default(.notifyAssigned) private var notifyAssigned
    @Default(.notifyCreated) private var notifyCreated
    private var createdSort: Binding<Bool> { Binding(get: { sort == .createdNewest || sort == .createdOldest }, set: { sort = $0 ? .createdNewest : .updatedNewest }) }
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                switch destination {
                case .pulls:
                    settingsToggle("Review requested", hint: "Pull requests waiting for your review", value: $requested)
                    settingsToggle("Assigned to me", value: $assigned)
                    settingsToggle("My pull requests", value: $created)
                    settingsToggle("Hide drafts", value: $hideDrafts)
                    TimelineSettingsRow("Sort inside a repository") { TimelineSegment(label: "Sort", selection: createdSort, options: [(false, "Updated", nil), (true, "Created", nil)]) }
                    TimelineSettingsRow("Checks from") { Picker("Checks from", selection: $buildType) { ForEach(BuildType.allCases) { Text($0.description).tag($0) } }.labelsHidden().fixedSize() }
                case .timeline:
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Freshness").font(.system(size: 13))
                        Text("How long a pull request can sit quietly before it changes color. Drag the handles.").font(.system(size: 11.5)).foregroundStyle(TimelineStyle.muted).padding(.top, 1)
                        FreshnessSettings(store: store, usernameOverride: usernameOverride)
                    }.padding(.horizontal, 14).padding(.vertical, 10)
                    TimelineSettingsRow("Default range") { TimelineSegment(label: "Default range", selection: $range, options: [(14, "2W", nil), (30, "1M", nil), (90, "3M", nil), (182, "6M", nil)]) }
                    settingsToggle("My own comments count as activity", hint: "Off: only commits reset the quiet time on your pull requests", value: $comments)
                case .stacks:
                    TimelineSettingsRow("Merged layers", hint: "Shown next to the branch at the bottom of a stack") { TimelineSegment(label: "Merged layers", selection: $merged, options: [(0, "Count", nil), (1, "Numbers", nil), (2, "Hide", nil)]) }
                case .bots:
                    BotAccountSettings(store: store).padding(14)
                case .snooze:
                    TimelineSettingsRow("Quick options") { Text("Tomorrow · In 3 days · Next week").font(.system(size: 12)).foregroundStyle(TimelineStyle.muted) }
                    settingsToggle("Wake up when someone comments", value: $wake)
                case .menubar:
                    TimelineSettingsRow("Counter") { Picker("Counter", selection: $counter) { ForEach(CounterType.allCases) { Text($0.description).tag($0) } }.labelsHidden().fixedSize() }
                    TimelineSettingsRow("Refresh every") { Picker("Refresh every", selection: $refresh) { ForEach([1, 5, 10, 15, 30], id: \.self) { Text("\($0) min").tag($0) } }.labelsHidden().fixedSize() }
                    TimelineSettingsRow("Open at login") { LaunchAtLogin.Toggle("").labelsHidden().toggleStyle(TimelineSwitchStyle()) }
                case .notifications:
                    settingsToggle("Someone requests your review", value: $notifyReview)
                    settingsToggle("You are assigned", value: $notifyAssigned)
                    settingsToggle("A new pull request of yours appears", value: $notifyCreated)
                    TimelineNotificationSettings()
                case .intelligence: IntelligenceSettings()
                case .account: EmptyView()
                }
            }.background(TimelineStyle.track, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(TimelineStyle.line)).clipShape(RoundedRectangle(cornerRadius: 12))
        }.scrollIndicators(.automatic)
    }
    private func settingsToggle(_ title: String, hint: String? = nil, value: Binding<Bool>) -> some View {
        TimelineSettingsRow(title, hint: hint) { Toggle(title, isOn: value).labelsHidden().toggleStyle(TimelineSwitchStyle()) }
    }
}

struct TimelineSettingsRow<Content: View>: View {
    let title: String
    let hint: String?
    let content: Content
    init(_ title: String, hint: String? = nil, @ViewBuilder content: () -> Content) { self.title = title; self.hint = hint; self.content = content() }
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13))
                if let hint { Text(hint).font(.system(size: 11.5)).foregroundStyle(TimelineStyle.muted) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            content
        }.padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 44)
            .overlay(alignment: .top) { Rectangle().fill(TimelineStyle.line).frame(height: 1) }
    }
}

struct TimelineSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule().fill(configuration.isOn ? TimelineStyle.accent : TimelineStyle.active).frame(width: 34, height: 20)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 16, height: 16).shadow(color: .black.opacity(0.25), radius: 1, y: 1).padding(2)
                }
        }.buttonStyle(.plain)
            .accessibilityRepresentation { Toggle(isOn: Binding(get: { configuration.isOn }, set: { configuration.isOn = $0 })) { configuration.label }.toggleStyle(.switch) }
    }
}

struct FreshnessSettings: View {
    @ObservedObject var store: PullRequestStore
    var usernameOverride: String? = nil
    @Default(.freshnessThresholds) private var thresholds
    @Default(.githubUsername) private var username
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

struct BotAccountSettings: View {
    @ObservedObject var store: PullRequestStore
    @Default(.botAccounts) private var bots
    @State private var login = ""
    private let defaults = ["dependabot", "github-actions", "renovate", "greptile-apps", "*[bot]"]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bot accounts").font(.system(size: 13))
            Text("Their pull requests are grouped under Bots, and they don't count as reviewers. Use * as a wildcard.").font(.system(size: 11.5)).foregroundStyle(TimelineStyle.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(bots, id: \.self) { bot in
                    HStack(spacing: 6) {
                        Text(bot).font(.system(size: 12, weight: .medium, design: .monospaced)).lineLimit(1)
                        Spacer(minLength: 0)
                        Button { bots.removeAll { $0 == bot } } label: { Image(systemName: "xmark").font(.system(size: 9)).frame(width: 18, height: 18).foregroundStyle(TimelineStyle.muted) }
                            .buttonStyle(.plain).help("Remove \(bot)").accessibilityLabel("Remove \(bot)")
                    }.padding(.leading, 9).padding(.trailing, 4).padding(.vertical, 3)
                        .background(TimelineStyle.track, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(TimelineStyle.strong))
                }
            }
            HStack(spacing: 6) {
                TextField("Add a login, e.g. snyk-bot", text: $login).textFieldStyle(.plain).font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 10).frame(height: 32).background(TimelineStyle.track, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(TimelineStyle.strong)).onSubmit(add)
                Button("Add", action: add).buttonStyle(.plain).padding(.horizontal, 12).frame(height: 32).foregroundStyle(TimelineStyle.muted)
                    .disabled(login.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack { Spacer(); Button("Reset to defaults") { bots = defaults }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(TimelineStyle.muted).padding(.horizontal, 12).frame(height: 28) }
        }
    }

    private func add() {
        let value = login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if !bots.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) { bots.append(value) }
        login = ""
    }
}

struct TimelineNotificationSettings: View {
    @Default(.notifyRotting) private var rotting
    @Default(.morningSummary) private var morning
    @Default(.morningSummaryMinutes) private var minutes
    private var time: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            minutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
        })
    }
    var body: some View {
        TimelineSettingsRow("One of yours starts rotting") { Toggle("One of yours starts rotting", isOn: $rotting).labelsHidden().toggleStyle(TimelineSwitchStyle()) }
        TimelineSettingsRow("Morning summary") { Toggle("Morning summary", isOn: $morning).labelsHidden().toggleStyle(TimelineSwitchStyle()) }
        if morning { TimelineSettingsRow("Summary time") { DatePicker("Summary time", selection: time, displayedComponents: .hourAndMinute).labelsHidden() } }

    }
}
