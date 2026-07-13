import AppKit
import Darwin
import SwiftUI
import WidgetKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        LegacyRefreshAgentCleaner.removeIfPresent()
        _ = AppUpdater.shared
        WidgetRegistration.refresh()
        scheduleWidgetRefresh()
        showMainWindowSoon()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if window?.isVisible != true {
            showMainWindowSoon()
        }
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

    private func scheduleWidgetRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            DispatchQueue.global(qos: .utility).async {
                _ = BackgroundSnapshotRefresh.run()
            }
        }
    }

    private func showMainWindowSoon() {
        showMainWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.showMainWindow()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showMainWindow() {
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
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.contentView = NSHostingView(rootView: CodexUsageRootView())
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
    }
}

private enum LegacyRefreshAgentCleaner {
    private static let identifier = "com.nolankrahn.CodexUsageMonitor.refresh"

    static func removeIfPresent() {
        let plistURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(identifier).plist")
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())", plistURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        try? FileManager.default.removeItem(at: plistURL)
    }
}

private enum BackgroundSnapshotRefresh {
    static func run() -> Bool {
        let previous = CodexUsageSnapshotStore.load()
        let snapshot = CodexUsageReader().snapshot(headroomActivity: previous?.cachedHeadroomActivity)

        if snapshot.hasUsage || previous == nil {
            CodexUsageSnapshotStore.save(snapshot)
        }
        CodexUsageSnapshotStore.saveAllSettings(CodexUsageSnapshotStore.loadAllSettings())
        WidgetCenter.shared.reloadTimelines(ofKind: "CodexUsageWidget")

        guard snapshot.hasUsage || previous == nil else { return true }
        return CodexUsageSnapshotStore.load()?.generatedAt == snapshot.generatedAt
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

    var body: some Scene {
        Settings {
            EmptyView()
        }
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
}
