import AppKit
import Foundation

@main
struct BackgroundLaunchCheck {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw CheckFailure("usage: BackgroundLaunchCheck <app executable>")
        }

        let executable = URL(fileURLWithPath: CommandLine.arguments[1])
        let appURL = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard let bundleID = Bundle(url: appURL)?.bundleIdentifier else {
            throw CheckFailure("could not read app bundle identifier")
        }
        let defaults = UserDefaults.standard
        let originalDomain = defaults.persistentDomain(forName: bundleID)
        defer {
            if let originalDomain {
                defaults.setPersistentDomain(originalDomain, forName: bundleID)
            } else {
                defaults.removePersistentDomain(forName: bundleID)
            }
        }

        try checkBackgroundLaunch(executable)
        try checkForegroundLaunch(executable, bundleID: bundleID, mode: "menuBar", expectedPolicy: .regular)
        try checkForegroundLaunch(executable, bundleID: bundleID, mode: "dock", expectedPolicy: .regular)
        try checkForegroundLaunch(executable, bundleID: bundleID, mode: "background", expectedPolicy: .regular)
        print("BackgroundLaunchCheck passed")
    }

    private static func checkBackgroundLaunch(_ executable: URL) throws {
        let process = try launch(executable, arguments: ["--background-refresh"])

        var sawRegular = false
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning, Date() < deadline {
            if NSRunningApplication(processIdentifier: process.processIdentifier)?.activationPolicy == .regular {
                sawRegular = true
            }
            Thread.sleep(forTimeInterval: 0.001)
        }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()

        guard !sawRegular else {
            throw CheckFailure("background refresh registered as a regular Dock app")
        }
    }

    private static func checkForegroundLaunch(
        _ executable: URL,
        bundleID: String,
        mode: String,
        expectedPolicy: NSApplication.ActivationPolicy
    ) throws {
        let defaults = UserDefaults.standard
        var domain = defaults.persistentDomain(forName: bundleID) ?? [:]
        domain["CodexUsageMonitor.appPresence"] = mode
        defaults.setPersistentDomain(domain, forName: bundleID)

        let process = try launch(executable, arguments: [])
        let deadline = Date().addingTimeInterval(10)
        var launched = false
        while process.isRunning, Date() < deadline {
            if let app = NSRunningApplication(processIdentifier: process.processIdentifier),
               app.isFinishedLaunching,
               app.activationPolicy == expectedPolicy {
                launched = true
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        guard launched else {
            throw CheckFailure("\(mode) mode did not launch with the expected activation policy")
        }
    }

    private static func launch(_ executable: URL, arguments: [String]) throws -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        try process.run()
        return process
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}
