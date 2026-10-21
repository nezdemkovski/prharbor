import Defaults
import SwiftUI
import UserNotifications

struct NotificationSettings: View {
    @Default(.notifyReviewRequested) private var review
    @Default(.notifyAssigned) private var assigned
    @Default(.notifyCreated) private var created
    @Default(.notifyRotting) private var rotting
    @Default(.morningSummary) private var morning
    @Default(.morningSummaryMinutes) private var minutes
    @State private var permission = NotificationPermission()
    private var time: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
            })
    }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    switch permission.status {
                    case .notDetermined: Button("Allow…") { Task { await permission.request() } }
                    case .denied: Button("Open System Settings") { permission.openSystemSettings() }
                    case .authorized, .provisional: Button("Send Test") { permission.sendTest() }
                    default: EmptyView()
                    }
                } label: {
                    Text("Notifications")
                    Text(permissionHint)
                }
            }
            Section("Notify me when") {
                Toggle("Someone requests your review", isOn: $review)
                Toggle("You are assigned", isOn: $assigned)
                Toggle("A new pull request of yours appears", isOn: $created)
                Toggle("One of yours starts rotting", isOn: $rotting)
            }
            Section {
                Toggle("Morning summary notification", isOn: $morning)
                if morning {
                    DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Daily summary")
            } footer: {
                Text(
                    "How many pull requests wait for your review and how many of yours are rotting. Notifications appear while PR Harbor is running."
                )
            }
        }
        .task { await permission.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await permission.refresh() }
        }
    }

    private var permissionHint: String {
        switch permission.status {
        case .notDetermined: "PR Harbor has not asked yet."
        case .denied: "Turned off in System Settings. PR Harbor cannot show any notification."
        case .authorized, .provisional: "Allowed."
        default: "Checking…"
        }
    }
}
