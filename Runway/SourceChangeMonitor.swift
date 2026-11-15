import AppKit
import CoreServices
import Darwin
import Foundation

final class SourceChangeMonitor {
    static func isSourceApplication(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == "com.openai.codex" || bundleIdentifier == "com.openai.chat"
    }

    static var isSourceAppRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            !$0.isTerminated && isSourceApplication(bundleIdentifier: $0.bundleIdentifier)
        }
    }

    private var stream: FSEventStreamRef?
    private var debounceWorkItem: DispatchWorkItem?
    private var isRefreshing = false
    private var refreshPending = false
    private let codexDirectory: URL
    private let headroomDirectory: URL
    private let refresh: @MainActor () async -> Void

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         headroomDirectory: URL = HeadroomSavingsCollector().ledgerURL.deletingLastPathComponent(),
         refresh: @escaping @MainActor () async -> Void = { _ = await RefreshCoordinator.shared.refreshAfterSourceChange() }) {
        self.codexDirectory = Self.canonicalDirectory(home.appendingPathComponent(".codex"))
        self.headroomDirectory = Self.canonicalDirectory(headroomDirectory)
        self.refresh = refresh
    }

    func start() {
        guard stream == nil else { return }
        let paths = [
            codexDirectory.path,
            headroomDirectory.path,
        ].filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, count, paths, _, _ in
                guard let info else { return }
                Unmanaged<SourceChangeMonitor>
                    .fromOpaque(info)
                    .takeUnretainedValue()
                    .handleEvents(count: count, paths: paths)
            },
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }
        self.stream = stream
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        refreshPending = false
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func scheduleRefresh() {
        if isRefreshing {
            refreshPending = true
            return
        }
        // Coalesce without postponing forever while Codex continuously writes.
        guard debounceWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.stream != nil else { return }
            self.debounceWorkItem = nil
            self.isRefreshing = true
            Task { @MainActor in
                await self.refresh()
                self.isRefreshing = false
                if self.refreshPending {
                    self.refreshPending = false
                    if self.stream != nil { self.scheduleRefresh() }
                }
            }
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: workItem)
    }

    private func handleEvents(count: Int, paths: UnsafeMutableRawPointer) {
        let paths = paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
        let codex = codexDirectory.path
        let roots = [codex + "/sessions", codex + "/archived_sessions", headroomDirectory.path]
        for index in 0..<count {
            let path = String(cString: paths[index])
            if path == codex || path == codex + "/session_index.jsonl"
                || roots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                scheduleRefresh()
                return
            }
        }
    }

    private static func canonicalDirectory(_ url: URL) -> URL {
        // FSEvents uses real paths, including /private prefixes even after a file is deleted.
        guard let path = realpath(url.path, nil) else { return url.standardizedFileURL }
        defer { free(path) }
        return URL(fileURLWithPath: String(cString: path), isDirectory: true)
    }

    deinit {
        stop()
    }
}
