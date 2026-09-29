import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = TodoStore()
    private let settings = AppSettings.shared
    private var scheduler: ReminderScheduler!
    private var quickAdd: QuickAddPanel!
    private let hotkeys = HotkeyManager()
    private var window: NSWindow?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: icon) {
            NSApp.applicationIconImage = image
        }

        buildMainMenu()
        buildStatusItem()
        applyDockPolicy()

        scheduler = ReminderScheduler(store: store)
        scheduler.onOpenRequested = { [weak self] in self?.showMainWindow() }
        scheduler.start()

        settings.$reminderStyle
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] style in
                if style.usesNotification { self?.scheduler.notifications.requestAuthorization() }
            }
            .store(in: &cancellables)

        quickAdd = QuickAddPanel(store: store)
        hotkeys.onTrigger = { [weak self] in self?.quickAdd.toggle() }
        applyHotkey()

        showMainWindow()
        NSApp.activate(ignoringOtherApps: true)

        store.$todos
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusItem() }
            .store(in: &cancellables)

        settings.$showDockIcon
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyDockPolicy() }
            .store(in: &cancellables)

        Publishers.CombineLatest(settings.$hotkeyEnabled, settings.$hotkey)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyHotkey() }
            .store(in: &cancellables)
    }

    /// Keep running in the menu bar so reminders still fire after the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    // MARK: Settings-driven behaviour

    private func applyDockPolicy() {
        NSApp.setActivationPolicy(settings.showDockIcon ? .regular : .accessory)
        if settings.showDockIcon == false {
            // Accessory apps lose key status when switching policy; bring the window back.
            window?.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyHotkey() {
        if settings.hotkeyEnabled {
            hotkeys.register(settings.hotkey)
        } else {
            hotkeys.unregister()
        }
        refreshStatusItem()
    }

    // MARK: Windows

    @objc func showMainWindow() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = "Nudge"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 380, height: 440)
            w.contentView = NSHostingView(rootView: ContentView(store: store, openSettings: { [weak self] in
                self?.showSettings()
            }))
            w.setFrameAutosaveName("NudgeMainWindow")
            if !w.setFrameUsingName("NudgeMainWindow") {
                w.center()
            }
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "Nudge Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(notifications: scheduler.notifications))
            w.center()
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showQuickAdd() {
        quickAdd.show()
    }

    // MARK: Status item

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Nudge")
        item.button?.imagePosition = .imageLeading
        item.menu = NSMenu()
        statusItem = item
        refreshStatusItem()
    }

    private func refreshStatusItem() {
        let count = store.pending.count
        statusItem?.button?.title = count > 0 ? " \(count)" : ""

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Nudge", action: #selector(showMainWindow), keyEquivalent: "")
        let quick = NSMenuItem(title: "Quick Add…", action: #selector(showQuickAdd), keyEquivalent: "")
        if settings.hotkeyEnabled {
            quick.title = "Quick Add…  \(settings.hotkey.label)"
        }
        menu.addItem(quick)

        let overdue = store.pending.filter { $0.isOverdue }
        let upcoming = store.pending.filter { $0.hasReminder && !$0.isOverdue }.prefix(5)
        if !overdue.isEmpty || !upcoming.isEmpty {
            menu.addItem(.separator())
            for todo in overdue.prefix(5) {
                let mi = NSMenuItem(title: "⚠︎ \(todo.title)", action: #selector(showMainWindow), keyEquivalent: "")
                menu.addItem(mi)
            }
            for todo in upcoming {
                let mi = NSMenuItem(title: "\(todo.title) — \(todo.reminderAt!.reminderDescription)",
                                    action: #selector(showMainWindow), keyEquivalent: "")
                menu.addItem(mi)
            }
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: "")
        menu.addItem(withTitle: "Quit Nudge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem?.menu = menu
    }

    // MARK: Main menu (needed for ⌘C/⌘V/⌘Q etc.)

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Nudge", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Nudge", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Nudge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Quick Add…", action: #selector(showQuickAdd), keyEquivalent: "n")
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Show Nudge", action: #selector(showMainWindow), keyEquivalent: "0")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }
}
