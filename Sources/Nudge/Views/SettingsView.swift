import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    var notifications: NotificationService

    var body: some View {
        TabView {
            GeneralSettings(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            ReminderSettings(settings: settings, notifications: notifications)
                .tabItem { Label("Reminders", systemImage: "bell") }
            QuickAddSettings(settings: settings)
                .tabItem { Label("Quick Add", systemImage: "keyboard") }
        }
        .frame(width: 480, height: 400)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var settings: AppSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch Nudge at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Toggle("Show icon in Dock", isOn: $settings.showDockIcon)
                Text("When off, Nudge lives only in the menu bar. Click its icon there to open the window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("List") {
                Toggle("Group tasks by day (Overdue, Today, Tomorrow…)", isOn: $settings.groupByDate)
                Toggle("Show Completed section", isOn: $settings.showCompletedSection)
            }

            Section("Preset times") {
                Picker("“Tomorrow” reminder time", selection: $settings.morningHour) {
                    ForEach(0..<24, id: \.self) { h in Text(Date.hourLabel(h)).tag(h) }
                }
                Picker("“This evening” reminder time", selection: $settings.eveningHour) {
                    ForEach(0..<24, id: \.self) { h in Text(Date.hourLabel(h)).tag(h) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        loginError = nil
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginError = "Couldn't change login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Reminders

private struct ReminderSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var notifications: NotificationService

    var body: some View {
        Form {
            Section("When a reminder is due") {
                Picker("Show", selection: $settings.reminderStyle) {
                    ForEach(ReminderStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(styleHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.reminderStyle.usesNotification {
                    HStack(spacing: 8) {
                        switch notifications.authorized {
                        case .some(true):
                            Label("Notifications allowed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .some(false):
                            Label("Notifications are blocked for Nudge", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Button("Open System Settings") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        case .none:
                            Label("Permission not asked yet", systemImage: "questionmark.circle")
                                .foregroundStyle(.secondary)
                            Button("Allow Notifications") { notifications.requestAuthorization() }
                        }
                    }
                    .font(.caption)
                    .onAppear { notifications.refreshAuthorization() }
                }
            }

            Section("Screen takeover") {
                Toggle("Cover all displays", isOn: $settings.coverAllScreens)
                Text("When off, only the main display is dimmed. The reminder card always appears on the main display.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sound") {
                HStack {
                    Picker("Chime", selection: $settings.chimeSound) {
                        ForEach(AppSettings.availableSounds, id: \.self) { Text($0).tag($0) }
                    }
                    Button {
                        NSSound(named: NSSound.Name(settings.chimeSound))?.play()
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .help("Preview")
                }
                Picker("Repeat chime while showing", selection: $settings.chimeRepeatSeconds) {
                    ForEach(AppSettings.chimeRepeatChoices, id: \.self) { s in
                        Text(s == 0 ? "Never" : "Every \(s) s").tag(s)
                    }
                }
            }

            Section("Snooze buttons") {
                ForEach(0..<3, id: \.self) { i in
                    Picker("Button \(i + 1)", selection: Binding(
                        get: { settings.snoozeMinutes[i] },
                        set: { v in var m = settings.snoozeMinutes; m[i] = v; settings.snoozeMinutes = m }
                    )) {
                        ForEach(AppSettings.snoozeChoices, id: \.self) { m in
                            Text(m.minutesLabel).tag(m)
                        }
                    }
                }
                Text("Press 1, 2 or 3 on the reminder screen to snooze with these.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var styleHelp: String {
        switch settings.reminderStyle {
        case .overlay: return "Dims the screen and shows the task front and centre until you act on it."
        case .notification: return "A standard macOS banner in the top-right corner, with Done and Snooze buttons. Easy to miss if you're deep in work."
        case .both: return "Banner and screen takeover together. Acting on either one clears the other."
        }
    }
}

// MARK: - Quick Add

private struct QuickAddSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Global shortcut") {
                Toggle("Enable Quick Add shortcut", isOn: $settings.hotkeyEnabled)
                Picker("Shortcut", selection: $settings.hotkey) {
                    ForEach(HotkeyOption.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!settings.hotkeyEnabled)
                Text("Press the shortcut in any app to pop up a small field. Type a task, optionally pick a reminder from the bell, and hit Return.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text(settings.hotkeyEnabled ? settings.hotkey.label : "Shortcut disabled")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .formStyle(.grouped)
    }
}
