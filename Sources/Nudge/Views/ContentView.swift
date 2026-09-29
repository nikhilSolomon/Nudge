import SwiftUI

struct ContentView: View {
    @ObservedObject var store: TodoStore
    @ObservedObject var settings = AppSettings.shared
    var openSettings: () -> Void = {}

    @State private var newTitle = ""
    @State private var newNotes = ""
    @State private var showNotesField = false
    @State private var newReminder: Date? = nil
    @State private var newRepeat: RepeatRule = .none
    @State private var showCompleted = true
    @State private var now = Date()
    @FocusState private var inputFocused: Bool

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            addBar
            Divider()
            list
        }
        .frame(minWidth: 380, minHeight: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { inputFocused = true }
        .onReceive(clock) { now = $0 }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Nudge")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Spacer()
            let count = store.pending.count
            Text(count == 0 ? "All clear" : "\(count) to do")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // MARK: Add bar

    private var addBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .foregroundStyle(.secondary)
                TextField("What needs doing?", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($inputFocused)
                    .onSubmit(add)

                Button {
                    withAnimation(.snappy) { showNotesField.toggle() }
                } label: {
                    Image(systemName: showNotesField || !newNotes.isEmpty ? "text.alignleft" : "text.alignleft")
                        .font(.system(size: 14))
                        .foregroundStyle(showNotesField || !newNotes.isEmpty ? Color.accentColor : Color.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .help("Add details")

                ReminderPicker(selection: $newReminder, repeatRule: $newRepeat)

                Button("Add", action: add)
                    .buttonStyle(.borderedProminent)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if showNotesField {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "text.alignleft")
                        .foregroundStyle(.clear)
                    TextField("Details (optional)", text: $newNotes, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .lineLimit(1...4)
                        .onSubmit(add)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        withAnimation(.snappy) {
            store.add(title: title, notes: newNotes, reminderAt: newReminder, repeatRule: newRepeat)
        }
        newTitle = ""
        newNotes = ""
        newReminder = nil
        newRepeat = .none
        showNotesField = false
        inputFocused = true
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        let pending = store.pending
        let completed = store.completed

        if pending.isEmpty && completed.isEmpty {
            emptyState
        } else {
            List {
                if settings.groupByDate {
                    ForEach(store.groupedPending(now: now), id: \.group) { entry in
                        Section {
                            ForEach(entry.todos) { todo in
                                TodoRow(store: store, todo: todo)
                            }
                        } header: {
                            groupHeader(entry.group, count: entry.todos.count)
                        }
                    }
                } else if !pending.isEmpty {
                    Section {
                        ForEach(pending) { todo in
                            TodoRow(store: store, todo: todo)
                        }
                    }
                }

                if settings.showCompletedSection && !completed.isEmpty {
                    Section {
                        if showCompleted {
                            ForEach(completed) { todo in
                                TodoRow(store: store, todo: todo)
                            }
                        }
                    } header: {
                        completedHeader(count: completed.count)
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private func groupHeader(_ group: DayGroup, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: group.symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(group.title)
            Text("\(count)")
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(group == .overdue ? Color.red : Color.secondary)
        .textCase(nil)
        .padding(.top, 4)
    }

    private func completedHeader(count: Int) -> some View {
        HStack {
            Button {
                withAnimation(.snappy) { showCompleted.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(showCompleted ? 90 : 0))
                    Text("Completed · \(count)")
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button("Clear") {
                withAnimation(.snappy) { store.clearCompleted() }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .textCase(nil)
        .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary.opacity(0.6))
            Text("Nothing to do")
                .font(.system(size: 17, weight: .semibold))
            Text("Add a task above. Set a reminder and Nudge will\ntake over the screen when it's time.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if settings.hotkeyEnabled {
                Text("Quick add from anywhere: \(settings.hotkey.label)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }
}
