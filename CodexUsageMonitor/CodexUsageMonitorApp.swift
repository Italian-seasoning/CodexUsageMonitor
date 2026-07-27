import AppKit
import Darwin
import SwiftUI
import WidgetKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var refreshTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var dataAccessObserver: NSObjectProtocol?
    private let sourceChangeMonitor = SourceChangeMonitor()
    private var activationScheduled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.arguments.contains("--background-refresh") {
            NSApp.setActivationPolicy(.prohibited)
            Task.detached(priority: .utility) {
                let result = await RefreshCoordinator.shared.refresh(trigger: .backgroundAgent)
                exit(result.outcome == .failed ? EXIT_FAILURE : EXIT_SUCCESS)
            }
            return
        }

        AppPresenceMode.apply(
            CodexUsageMonitorApp.sharedSettingsModel.settings.appPresence
        )
        _ = AppUpdater.shared
        if BackgroundRefreshAgent.isStableInstall {
            WidgetRegistration.refresh()
        }
        let hasCurrentAccess = OnboardingStateStore.hasCurrentCodexDataAccess()
        if OnboardingStateStore.completedCurrentVersion() {
            DispatchQueue.global(qos: .utility).async {
                BackgroundRefreshAgent.installIfEnabled()
            }
        } else {
            DispatchQueue.global(qos: .utility).async {
                _ = BackgroundRefreshAgent.uninstall()
            }
        }
        if hasCurrentAccess {
            sourceChangeMonitor.start()
        }
        dataAccessObserver = NotificationCenter.default.addObserver(
            forName: .codexDataAccessApproved,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sourceChangeMonitor.start()
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { _ = await RefreshCoordinator.shared.refresh(trigger: .wake) }
        }
        scheduleWidgetRefresh()
        requestRefresh(.launch)
        showMainWindowSoon()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard !ProcessInfo.processInfo.arguments.contains("--background-refresh") else { return }
        requestRefresh(.foreground)
    }

    func applicationWillTerminate(_ notification: Notification) {
        sourceChangeMonitor.stop()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let dataAccessObserver {
            NotificationCenter.default.removeObserver(dataAccessObserver)
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

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            AppPresenceMode.apply(CodexUsageMonitorApp.sharedSettingsModel.settings.appPresence)
        }
    }

    private func scheduleWidgetRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: BackgroundRefreshAgent.interval, repeats: true) { _ in
            Task { _ = await RefreshCoordinator.shared.refresh(trigger: .fallbackTimer) }
        }
    }

    private func requestRefresh(_ trigger: RefreshTrigger) {
        Task { _ = await RefreshCoordinator.shared.refresh(trigger: trigger) }
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
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
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
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.delegate = self
            window.contentView = NSHostingView(
                rootView: CodexUsageRootView()
                    .environmentObject(CodexUsageMonitorApp.sharedSettingsModel)
            )
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
    static let sharedSettingsModel = CodexUsageSettingsModel()

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var menuBarModel = MenuBarSnapshotModel()
    @StateObject private var settingsModel = sharedSettingsModel

    var body: some Scene {
        MenuBarExtra(isInserted: menuBarItemIsInserted) {
            CodexMenuBarView(model: menuBarModel)
                .environmentObject(settingsModel)
        } label: {
            CodexMenuBarLabel(model: menuBarModel)
                .environmentObject(settingsModel)
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand()
            }
            CommandGroup(after: .help) {
                Button("Run Setup") {
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
               settingsModel.settings.appPresence == .menuBar {
                settingsModel.settings.menuBarDisplayMode = .hidden
            }
        }
    }

    private var showsMenuBarItem: Bool {
        settingsModel.settings.appPresence == .menuBar
            && settingsModel.settings.menuBarDisplayMode != .hidden
    }
}
