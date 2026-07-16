import AppKit
import Foundation

@main
struct BackgroundLaunchCheck {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw CheckFailure("usage: BackgroundLaunchCheck <app executable>")
        }

        let executable = URL(fileURLWithPath: CommandLine.arguments[1])
        try checkBackgroundLaunch(executable)
        try checkForegroundLaunch(executable)
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

    private static func checkForegroundLaunch(_ executable: URL) throws {
        let process = try launch(executable, arguments: [])
        let deadline = Date().addingTimeInterval(10)
        var launched = false
        while process.isRunning, Date() < deadline {
            if let app = NSRunningApplication(processIdentifier: process.processIdentifier),
               app.isFinishedLaunching,
               app.activationPolicy == .regular {
                launched = true
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        guard launched else {
            throw CheckFailure("foreground app did not finish launching responsively")
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
