import AppKit
import Darwin
import SwiftUI
import WidgetKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var refreshTimer: Timer?
    private var activationScheduled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.arguments.contains("--background-refresh") {
            NSApp.setActivationPolicy(.prohibited)
            DispatchQueue.global(qos: .utility).async {
                exit(SnapshotRefresh.run() == nil ? EXIT_FAILURE : EXIT_SUCCESS)
            }
            return
        }

        AppPresenceMode.apply(
            UserDefaults.standard.string(forKey: AppPresenceMode.defaultsKey)
                ?? AppPresenceMode.menuBar.rawValue
        )
        _ = AppUpdater.shared
        WidgetRegistration.refresh()
        if OnboardingStateStore.completedCurrentVersion() {
            DispatchQueue.global(qos: .utility).async {
                BackgroundRefreshAgent.installIfEnabled()
            }
        }
        scheduleWidgetRefresh()
        showMainWindowSoon()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindowSoon()
        return true
    }

    func application(_ application: NSApplication, shouldSaveSecureApplicationState coder: NSCoder) -> Bool {
        false
    }

    func application(_ application: NSApplication, shouldRestoreSecureApplicationState coder: NSCoder) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func windowWillClose(_ notification: Notification) {
        let presence = UserDefaults.standard.string(forKey: AppPresenceMode.defaultsKey)
            ?? AppPresenceMode.menuBar.rawValue
        DispatchQueue.main.async {
            AppPresenceMode.apply(presence)
        }
    }

    private func scheduleWidgetRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: BackgroundRefreshAgent.interval, repeats: true) { _ in
            DispatchQueue.global(qos: .utility).async {
                _ = SnapshotRefresh.run()
            }
        }
    }

    private func showMainWindowSoon() {
        showMainWindow()
        guard !activationScheduled else { return }
        activationScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.activationScheduled = false
            self.showMainWindow()
            if !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Codex Usage"
            window.identifier = NSUserInterfaceItemIdentifier("CodexUsageMonitor.MainWindow")
            window.minSize = NSSize(width: 980, height: 660)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: CodexUsageRootView())
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
    }
}

private enum WidgetRegistration {
    static func refresh() {
        let app = Bundle.main.bundleURL.path
        let plugin = Bundle.main.bundleURL
            .appendingPathComponent("Contents/PlugIns/CodexUsageWidget.appex").path
        guard FileManager.default.fileExists(atPath: plugin) else { return }

        DispatchQueue.global(qos: .utility).async {
            run("/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister", ["-f", "-R", "-trusted", app])
            run("/usr/bin/pluginkit", ["-a", plugin])
        }
    }

    private static func run(_ executable: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}

@main
struct CodexUsageMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var menuBarModel = MenuBarSnapshotModel()
    @AppStorage(AppPresenceMode.defaultsKey) private var appPresence = AppPresenceMode.menuBar.rawValue
    @AppStorage("CodexUsageMonitor.menuBarDisplayMode") private var menuBarMode = MenuBarDisplayMode.percentage.rawValue

    var body: some Scene {
        MenuBarExtra(isInserted: menuBarItemIsInserted) {
            CodexMenuBarView(model: menuBarModel)
        } label: {
            CodexMenuBarLabel(model: menuBarModel)
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand()
            }
            CommandGroup(after: .help) {
                Button("Show App Tour") {
                    NotificationCenter.default.post(name: .showCodexUsageTour, object: nil)
                }
            }
        }
    }

    private var menuBarItemIsInserted: Binding<Bool> {
        Binding {
            !ProcessInfo.processInfo.arguments.contains("--background-refresh")
                && showsMenuBarItem
        } set: { isInserted in
            if !isInserted,
               !ProcessInfo.processInfo.arguments.contains("--background-refresh"),
               appPresence == AppPresenceMode.menuBar.rawValue {
                menuBarMode = MenuBarDisplayMode.hidden.rawValue
            }
        }
    }

    private var showsMenuBarItem: Bool {
        appPresence == AppPresenceMode.menuBar.rawValue
            && menuBarMode != MenuBarDisplayMode.hidden.rawValue
    }
}
