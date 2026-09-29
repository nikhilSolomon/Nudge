import SwiftUI

struct TodoRow: View {
    @ObservedObject var store: TodoStore
    let todo: Todo

    @State private var hovering = false
    @State private var editing = false

    private var reminderBinding: Binding<Date?> {
        Binding(
            get: { todo.reminderAt },
            set: { store.setReminder(todo.id, to: $0) }
        )
    }

    private var repeatBinding: Binding<RepeatRule> {
        Binding(
            get: { todo.repeatRule },
            set: { store.setRepeat(todo.id, to: $0) }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                withAnimation(.snappy) { store.toggleDone(todo.id) }
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(todo.isDone ? Color.green : Color.secondary.opacity(0.7))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(todo.repeats && !todo.isDone ? "Complete and schedule the next occurrence" : "")

            VStack(alignment: .leading, spacing: 3) {
                Text(todo.title)
                    .font(.system(size: 15))
                    .strikethrough(todo.isDone, color: .secondary)
                    .foregroundStyle(todo.isDone ? .secondary : .primary)
                    .lineLimit(2)

                if !todo.notes.isEmpty {
                    Text(todo.notes)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let when = todo.reminderAt, !todo.isDone {
                    HStack(spacing: 6) {
                        Label(when.reminderDescription, systemImage: todo.isOverdue ? "bell.badge.fill" : "bell")
                            .foregroundStyle(todo.isOverdue ? Color.red : Color.secondary)
                        if todo.repeats {
                            Label(todo.repeatRule.shortLabel, systemImage: "repeat")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { editing = true }

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                if !todo.isDone {
                    ReminderPicker(selection: reminderBinding, repeatRule: repeatBinding, compact: true)
                        .opacity(hovering || todo.hasReminder ? 1 : 0)
                }

                Button {
                    editing = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(5)
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0)
                .help("Edit details")
                .popover(isPresented: $editing, arrowEdge: .trailing) {
                    TodoEditor(store: store, todo: todo) { editing = false }
                }

                Button {
                    withAnimation(.snappy) { store.delete(todo.id) }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(5)
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0)
                .help("Delete")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button(todo.isDone ? "Mark as Not Done" : (todo.repeats ? "Complete · Schedule Next" : "Mark as Done")) {
                store.toggleDone(todo.id)
            }
            Button("Edit Details…") { editing = true }
            Divider()
            Button("Delete", role: .destructive) { store.delete(todo.id) }
        }
    }
}
