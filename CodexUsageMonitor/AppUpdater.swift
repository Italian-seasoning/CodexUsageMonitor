import AppKit
import Sparkle

@MainActor
final class AppUpdater {
    static let shared = AppUpdater()

    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.automaticallyChecksForUpdates = true
        controller.updater.automaticallyDownloadsUpdates = true
        controller.updater.updateCheckInterval = 24 * 60 * 60
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
