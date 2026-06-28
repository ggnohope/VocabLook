import SwiftUI

struct SettingsView: View {
    @State private var reminder = Calendar.current.date(
        from: DateComponents(hour: Settings.reminderHour, minute: Settings.reminderMinute)) ?? Date()
    @State private var dailyGoal = Double(Settings.dailyGoal)
    @State private var pronounce = Settings.pronounceOnReveal
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            LabeledContent("Capture shortcut") {
                Text("⌃⌘D").font(.system(.body, design: .monospaced))
                    .help("Mirrors the macOS Look Up shortcut — observe only")
            }
            DatePicker("Daily reminder", selection: $reminder, displayedComponents: .hourAndMinute)
                .onChange(of: reminder) { _, newValue in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                    Settings.reminderHour = c.hour ?? 20
                    Settings.reminderMinute = c.minute ?? 30
                    Reminder.shared.reschedule()
                }
            VStack(alignment: .leading) {
                Text("New cards per day: \(Int(dailyGoal))")
                Slider(value: $dailyGoal, in: 5...100, step: 5)
                    .onChange(of: dailyGoal) { _, v in Settings.dailyGoal = Int(v) }
            }
            Toggle("Pronounce on reveal", isOn: $pronounce)
                .onChange(of: pronounce) { _, v in Settings.pronounceOnReveal = v }
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, v in LaunchAtLogin.set(v) }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 460)
    }
}
