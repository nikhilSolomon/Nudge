import AppKit
import SwiftUI

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Spotlight-style floating panel for adding a task from anywhere.
final class QuickAddPanel {
    private let store: TodoStore
    private var panel: NSPanel?
    private var observer: NSObjectProtocol?

    init(store: TodoStore) {
        self.store = store
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible { close() } else { show() }
    }

    func show() {
        if isVisible { panel?.makeKeyAndOrderFront(nil); return }

        let p = panel ?? makePanel()
        panel = p

        // Fresh view each time so the text field starts empty.
        let view = QuickAddView(store: store, onClose: { [weak self] in self?.close() })
        p.contentView = NSHostingView(rootView: view)

        // Show on the screen the mouse is on, so it appears where the user is working.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
        if let screen {
            let size = NSSize(width: 580, height: 96)
            let frame = screen.visibleFrame
            let origin = NSPoint(x: frame.midX - size.width / 2,
                                 y: frame.minY + frame.height * 0.68 - size.height / 2)
            p.setFrame(NSRect(origin: origin, size: size), display: false)
        }

        // Non-activating: the panel takes keyboard focus without switching apps or Spaces.
        p.orderFrontRegardless()
        p.makeKey()
        DispatchQueue.main.async { [weak p] in
            guard let p, let field = Self.firstTextField(in: p.contentView) else { return }
            p.makeFirstResponder(field)
        }

        observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                          object: p, queue: .main) { [weak self] _ in
            self?.close()
        }
    }

    func close() {
        if let o = observer { NotificationCenter.default.removeObserver(o); observer = nil }
        guard let p = panel, p.isVisible else { return }
        p.orderOut(nil)
        p.contentView = nil
    }

    private static func firstTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let tf = view as? NSTextField, tf.isEditable { return tf }
        for sub in view.subviews {
            if let found = firstTextField(in: sub) { return found }
        }
        return nil
    }

    private func makePanel() -> NSPanel {
        let p = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 580, height: 96),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        p.level = .floating
        p.isFloatingPanel = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return p
    }
}

struct QuickAddView: View {
    @ObservedObject var store: TodoStore
    let onClose: () -> Void

    @State private var title = ""
    @State private var reminder: Date? = nil
    @State private var repeatRule: RepeatRule = .none
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.orange)
                TextField("Quick add a task…", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .medium))
                    .focused($focused)
                    .onSubmit(submit)
                ReminderPicker(selection: $reminder, repeatRule: $repeatRule)
            }
            HStack {
                Text("↩ Add")
                Text("·")
                Text("esc Close")
                Spacer()
                if let r = reminder {
                    Label(r.reminderDescription, systemImage: "bell.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.tertiary)
            .padding(.leading, 36)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 580)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onExitCommand(perform: onClose)
    }

    private func submit() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { onClose(); return }
        store.add(title: trimmed, reminderAt: reminder, repeatRule: repeatRule)
        NSSound(named: "Pop")?.play()
        onClose()
    }
}
