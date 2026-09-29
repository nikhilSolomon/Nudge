import AppKit
import SwiftUI

enum AttentionAction {
    case done
    case snooze(TimeInterval)
    case dismiss
}

/// Borderless, non-activating panel that can still take keyboard focus.
/// Non-activating is the key part: activating Nudge as a regular app would make macOS switch
/// to the Space that holds Nudge's main window, so the overlay would end up on the wrong Space
/// (and never over a full-screen app). A panel that never activates the app stays on top of
/// whatever Space and window the user is currently in.
private final class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Covers the screen(s) with a dimmed, always-on-top panel showing the due todo.
final class AttentionOverlay {
    private var windows: [NSWindow] = []
    private var chimeTimer: Timer?
    private let settings = AppSettings.shared

    var isShowing: Bool { !windows.isEmpty }

    func show(todo: Todo, onAction: @escaping (AttentionAction) -> Void) {
        dismiss()

        // The card goes on the screen the user is actually working on: the one under the mouse.
        let mouse = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
        let screens = settings.coverAllScreens ? NSScreen.screens : [activeScreen].compactMap { $0 }

        var keyWindow: NSWindow?
        for screen in screens {
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.becomesKeyOnlyIfNeeded = false
            window.worksWhenModal = true
            window.ignoresMouseEvents = false
            // All Spaces + above full-screen apps, so it appears wherever the user currently is.
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.animationBehavior = .none

            let isActive = screen == activeScreen
            let view = AttentionView(todo: todo, showsCard: isActive,
                                     snoozeMinutes: settings.snoozeMinutes, onAction: onAction)
            window.contentView = NSHostingView(rootView: view)
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            if isActive { keyWindow = window }
            windows.append(window)
        }

        // Take keyboard focus for Return / 1-2-3 / Esc without activating the app.
        keyWindow?.makeKey()

        chime()
        let repeatEvery = settings.chimeRepeatSeconds
        if repeatEvery > 0 {
            let t = Timer(timeInterval: TimeInterval(repeatEvery), repeats: true) { [weak self] _ in self?.chime() }
            RunLoop.main.add(t, forMode: .common)
            chimeTimer = t
        }
    }

    func dismiss() {
        chimeTimer?.invalidate()
        chimeTimer = nil
        for w in windows {
            w.orderOut(nil)
            w.contentView = nil
        }
        windows.removeAll()
    }

    private func chime() {
        NSSound(named: NSSound.Name(settings.chimeSound))?.play()
    }
}

// MARK: - SwiftUI content

struct AttentionView: View {
    let todo: Todo
    let showsCard: Bool
    let snoozeMinutes: [Int]
    let onAction: (AttentionAction) -> Void

    @State private var pulse = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.72))
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { /* swallow clicks so the desktop underneath can't be hit */ }

            if showsCard {
                card
                    .scaleEffect(appeared ? 1 : 0.9)
                    .opacity(appeared ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { appeared = true }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private var card: some View {
        VStack(spacing: 26) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.18))
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulse ? 1.25 : 0.9)
                    .opacity(pulse ? 0.35 : 0.9)
                Circle()
                    .fill(Color.orange.opacity(0.25))
                    .frame(width: 96, height: 96)
                Image(systemName: "bell.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.orange)
                    .rotationEffect(.degrees(pulse ? 12 : -12), anchor: .top)
            }

            VStack(spacing: 10) {
                Text("Reminder")
                    .font(.system(size: 15, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(2)
                    .foregroundStyle(.secondary)

                Text(todo.title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)

                if !todo.notes.isEmpty {
                    Text(todo.notes)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                }

                HStack(spacing: 8) {
                    if let when = todo.reminderAt {
                        Text(when.reminderDescription)
                    }
                    if todo.repeats {
                        Text("·")
                        Label(todo.repeatRule.shortLabel, systemImage: "repeat")
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
            }

            VStack(spacing: 12) {
                Button {
                    onAction(.done)
                } label: {
                    Label(todo.repeats ? "Done · Schedule Next" : "Mark as Done", systemImage: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                HStack(spacing: 10) {
                    ForEach(Array(snoozeMinutes.prefix(3).enumerated()), id: \.offset) { index, minutes in
                        snoozeButton(minutes.minutesLabel, TimeInterval(minutes * 60),
                                     key: KeyEquivalent(Character(String(index + 1))))
                    }
                }

                Button("Dismiss") { onAction(.dismiss) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                    .padding(.top, 4)
            }
        }
        .padding(40)
        .frame(width: 460)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.45), radius: 40, y: 20)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func snoozeButton(_ label: String, _ interval: TimeInterval, key: KeyEquivalent) -> some View {
        Button {
            onAction(.snooze(interval))
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "zzz")
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .keyboardShortcut(key, modifiers: [])
    }
}
