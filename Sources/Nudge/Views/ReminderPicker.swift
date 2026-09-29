import SwiftUI

/// Bell button + menu of quick presets, with a popover for a custom date/time.
/// Optionally exposes a Repeat submenu when a `repeatRule` binding is supplied.
struct ReminderPicker: View {
    @Binding var selection: Date?
    var repeatRule: Binding<RepeatRule>? = nil
    var compact = false

    @ObservedObject private var settings = AppSettings.shared
    @State private var showCustom = false
    @State private var draft = Date.roundedUpToNextFiveMinutes()

    var body: some View {
        Menu {
            Button("In 10 minutes") { selection = Date().addingTimeInterval(10 * 60) }
            Button("In 30 minutes") { selection = Date().addingTimeInterval(30 * 60) }
            Button("In 1 hour") { selection = Date().addingTimeInterval(60 * 60) }
            Button("In 3 hours") { selection = Date().addingTimeInterval(3 * 60 * 60) }
            Divider()
            Button("This evening · \(Date.hourLabel(settings.eveningHour))") {
                selection = .nextOccurrence(hour: settings.eveningHour)
            }
            Button("Tomorrow · \(Date.hourLabel(settings.morningHour))") {
                selection = .tomorrow(hour: settings.morningHour)
            }
            Divider()
            Button("Pick date & time…") {
                draft = selection ?? .roundedUpToNextFiveMinutes()
                showCustom = true
            }
            if let repeatRule, selection != nil {
                Divider()
                Picker("Repeat", selection: repeatRule) {
                    ForEach(RepeatRule.allCases) { rule in
                        Text(rule.label).tag(rule)
                    }
                }
                .pickerStyle(.menu)
            }
            if selection != nil {
                Divider()
                Button("Remove reminder", role: .destructive) {
                    selection = nil
                    repeatRule?.wrappedValue = .none
                }
            }
        } label: {
            label
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(selection.map { "Reminder: \($0.reminderDescription)" } ?? "Add a reminder")
        .popover(isPresented: $showCustom, arrowEdge: .bottom) {
            customPicker
        }
    }

    @ViewBuilder
    private var label: some View {
        if let date = selection {
            HStack(spacing: 4) {
                Image(systemName: "bell.fill")
                if !compact {
                    Text(date.reminderDescription)
                }
                if let rule = repeatRule?.wrappedValue, rule != .none {
                    Image(systemName: "repeat")
                }
            }
            .font(.system(size: compact ? 12 : 13, weight: .medium))
            .foregroundStyle(.orange)
            .padding(.horizontal, compact ? 6 : 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.orange.opacity(0.15)))
        } else {
            Image(systemName: "bell")
                .font(.system(size: compact ? 13 : 15))
                .foregroundStyle(.secondary)
                .padding(compact ? 5 : 7)
        }
    }

    private var customPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Remind me at")
                .font(.headline)
            DatePicker(
                "",
                selection: $draft,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.stepperField)
            .labelsHidden()
            HStack {
                Button("Cancel") { showCustom = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Set Reminder") {
                    selection = draft
                    showCustom = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}
