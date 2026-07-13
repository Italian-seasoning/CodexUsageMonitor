import AppKit
import Darwin
import SwiftUI
import WidgetKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.arguments.contains("--background-refresh") {
            NSApp.setActivationPolicy(.prohibited)
            DispatchQueue.global(qos: .utility).async {
                exit(BackgroundSnapshotRefresh.run() ? EXIT_SUCCESS : EXIT_FAILURE)
            }
            return
        }

        NSApp.setActivationPolicy(.regular)
        _ = AppUpdater.shared
        WidgetRegistration.refresh()
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "CodexUsageMonitor.hasRequestedCodexAccess")
            || defaults.bool(forKey: "CodexUsageMonitor.hasCompletedOnboarding") {
            RefreshAgentInstaller.installIfBundled()
        }
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

enum RefreshAgentInstaller {
    private static let identifier = "com.nolankrahn.CodexUsageMonitor.refresh"

    static func installIfBundled() {
        guard let executable = Bundle.main.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path)
        else { return }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let agentsDirectory = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let logsDirectory = home.appendingPathComponent("Library/Logs/CodexUsageMonitor", isDirectory: true)
        let plistURL = agentsDirectory.appendingPathComponent("\(identifier).plist")
        let uid = getuid()
        let domain = "gui/\(uid)"
        let service = "\(domain)/\(identifier)"

        let plist: [String: Any] = [
            "Label": identifier,
            "ProgramArguments": [executable.path, "--background-refresh"],
            "RunAtLoad": true,
            "StartInterval": 300,
            "StandardErrorPath": logsDirectory.appendingPathComponent("refresh.err.log").path
        ]

        do {
            try FileManager.default.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            let existing = try? Data(contentsOf: plistURL)
            let isLoaded = runLaunchctl(["print", service]) == 0
            if existing == data, isLoaded { return }

            if isLoaded {
                _ = runLaunchctl(["bootout", domain, plistURL.path])
            }
            try data.write(to: plistURL, options: .atomic)
            _ = runLaunchctl(["bootstrap", domain, plistURL.path])
            _ = runLaunchctl(["kickstart", "-k", service])
        } catch {
            // The app still refreshes while open. Installation can be retried next launch.
        }
    }

    private static func runLaunchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
