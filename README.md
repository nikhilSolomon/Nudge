# Nudge

A small native macOS todo app whose reminders take over the screen.

## Build & run

```bash
./build.sh
open "build/Nudge.app"
```

Requires Xcode command line tools (Swift 5.9+, macOS 14+). No Xcode project; it's a Swift Package.
Regenerate the icon with `swift Tools/make-icon.swift && iconutil -c icns App/AppIcon.iconset -o App/AppIcon.icns`.

## Features

- **Todos with details**: title plus optional notes. Double-click a row or hover → ⓘ to edit.
- **Reminders**: bell menu with presets (10 min, 30 min, 1 h, 3 h, this evening, tomorrow) or a custom date & time.
- **Repeating reminders**: daily, weekdays, weekly, every 2 weeks, monthly. Checking off a repeating task
  rolls it forward to the next occurrence instead of completing it.
- **Day grouping**: Overdue · Today · Tomorrow · Next 7 days · Later · No date (toggle in Settings).
- **Screen takeover**: when a reminder is due, a dimmed, always-on-top panel covers the screen(s) with the task,
  its notes, and a chime. Keys: `Return` = Done, `1/2/3` = snooze, `Esc` = dismiss.
- **Quick Add**: global shortcut (default ⌥⌘N) pops a Spotlight-style field from any app. Return adds, Esc closes.
- **Menu bar**: pending count, overdue/upcoming list, Quick Add, Settings, Quit. Closing the window keeps the app alive.
- **Settings (⌘,)**: launch at login, Dock icon on/off, grouping, preset times, cover all displays, chime sound
  and repeat interval, the three snooze durations, Quick Add shortcut.

Data lives in `~/Library/Application Support/Nudge/todos.json`; preferences in UserDefaults.

## Layout

```
Sources/Nudge/
  main.swift                        App entry
  App/AppDelegate.swift             Windows, menu bar item, main menu, hotkey wiring
  Models/Todo.swift                 Todo, RepeatRule, DayGroup
  Models/AppSettings.swift          UserDefaults-backed preferences, HotkeyOption
  Models/DateFormatting.swift       "Today 3:45 PM" helpers, presets
  Services/TodoStore.swift          Persistence, mutations, grouping
  Services/ReminderScheduler.swift  1 s poll that fires due reminders
  Services/AttentionOverlay.swift   Full-screen overlay window + SwiftUI card
  Services/HotkeyManager.swift      Carbon global hotkey
  Services/QuickAddPanel.swift      Floating quick-add panel
  Views/ContentView.swift           Main window (add bar, grouped list)
  Views/TodoRow.swift               List row
  Views/TodoEditor.swift            Title / notes / reminder / repeat popover
  Views/ReminderPicker.swift        Bell menu + custom date/time popover + repeat
  Views/SettingsView.swift          Settings tabs
Tools/make-icon.swift               Renders App/AppIcon.icns
```
