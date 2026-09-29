import SwiftUI

/// Popover editor for a single todo: title, notes, reminder, repeat.
struct TodoEditor: View {
    @ObservedObject var store: TodoStore
    let todoID: UUID
    let onClose: () -> Void

    @State private var draft: Todo
    @FocusState private var titleFocused: Bool

    init(store: TodoStore, todo: Todo, onClose: @escaping () -> Void) {
        self.store = store
        self.todoID = todo.id
        self.onClose = onClose
        _draft = State(initialValue: todo)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Title", text: $draft.title)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .semibold))
                .focused($titleFocused)
                .onSubmit(save)

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $draft.notes)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 80, maxHeight: 140)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Reminder")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    ReminderPicker(selection: $draft.reminderAt, repeatRule: $draft.repeatRule)
                }
                if draft.reminderAt != nil {
                    HStack {
                        Text("Repeat")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: $draft.repeatRule) {
                            ForEach(RepeatRule.allCases) { rule in
                                Text(rule.label).tag(rule)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                }
            }

            Divider()

            HStack {
                Button(role: .destructive) {
                    store.delete(todoID)
                    onClose()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)

                Spacer()

                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 340)
        .onAppear { DispatchQueue.main.async { titleFocused = true } }
    }

    private func save() {
        guard !draft.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        store.replace(draft)
        onClose()
    }
}
