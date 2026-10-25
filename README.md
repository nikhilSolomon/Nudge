# Nudge

A small todo app whose reminders take over the screen. Native macOS app (SwiftUI/AppKit) and a
native Android app (Kotlin/Jetpack Compose) that sync through a free Supabase project.

## Mac: build & run

```bash
./build.sh
open "build/Nudge.app"
```

Requires Xcode command line tools (Swift 5.9+, macOS 14+). No Xcode project; it's a Swift Package.
Regenerate the icon with `swift Tools/make-icon.swift && iconutil -c icns App/AppIcon.iconset -o App/AppIcon.icns`.

## Android: build & run

```bash
cd android && ./gradlew installDebug
```

Requires the Android SDK (API 36) and JDK 17+. Gradle 9.1 + AGP 9.0 with built-in Kotlin; no Room/KSP,
todos are a JSON file like on the Mac. On first launch grant the permissions the app asks for under
Settings → Permissions: notifications, exact alarms, full-screen reminders, display over other apps.
"Display over other apps" is what lets the reminder page take over while you're using another app;
without it Android shows a heads-up notification instead when the phone is unlocked, and the full-screen
page only when the screen is off or locked.

## Sync between devices

Both apps sign in to the same free Supabase project and merge changes with last-write-wins. One-time
setup (about 5 minutes) is in [docs/SYNC.md](docs/SYNC.md); the database schema is
[supabase/schema.sql](supabase/schema.sql).

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

Mac data lives in `~/Library/Application Support/Nudge/todos.json`; preferences in UserDefaults.
Android data lives in the app's private `files/todos.json`.

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
  Services/SystemStateMonitor.swift Lock / sleep / screensaver detection
  Services/SupabaseClient.swift     Auth + PostgREST over URLSession
  Services/SyncService.swift        Pull-merge-push sync
  Services/Keychain.swift           Session storage
  Views/ContentView.swift           Main window (add bar, grouped list)
  Views/TodoRow.swift               List row
  Views/TodoEditor.swift            Title / notes / reminder / repeat popover
  Views/ReminderPicker.swift        Bell menu + custom date/time popover + repeat
  Views/SettingsView.swift          Settings tabs
Tools/make-icon.swift               Renders App/AppIcon.icns

android/app/src/main/java/dev/nudge/android/
  NudgeApp.kt                       Application + service locator
  data/                             Todo, RepeatRule, DayGroup, repository (JSON file), settings
  reminders/                        AlarmManager scheduler, receivers, notification, full-screen ReminderActivity
  sync/                             Supabase client (OkHttp), SyncManager, periodic SyncWorker
  ui/                               Compose screens: list, editor, reminder picker, settings, account
supabase/schema.sql                 Table + row-level security
docs/SYNC.md                        Setup guide
```
