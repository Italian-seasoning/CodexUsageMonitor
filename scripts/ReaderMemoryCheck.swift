import Darwin
import Foundation

// Builds a synthetic transcript, then measures repeated cold/warm reader refreshes.
// No real prompts, credentials, or session paths are printed.
@main
struct ReaderMemoryCheck {
    static func main() throws {
        let megabytes = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 128
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        if CommandLine.arguments.contains("--live") {
            let reader = CodexUsageReader(cacheURL: root.appendingPathComponent("live-cache.plist"))
            for refresh in 1...2 {
                let snapshot = reader.snapshot()
                print("Live refresh \(refresh): \(snapshot.sessionCount ?? 0) sessions, \(snapshot.turnCount ?? 0) turns")
                printResidentMemory(refresh: refresh)
            }
            return
        }
        let file = root.appendingPathComponent("large.jsonl")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let output = try FileHandle(forWritingTo: file)
        let metadata = "{\"type\":\"session_meta\",\"payload\":{\"id\":\"memory-check\",\"timestamp\":\"2026-10-04T10:00:00Z\"}}\n{\"type\":\"turn_context\",\"payload\":{\"model\":\"gpt-6.1-sol\"}}\n"
        try output.write(contentsOf: Data(metadata.utf8))
        let row = Data(("{\"type\":\"response_item\",\"payload\":{\"content\":\"" + String(repeating: "x", count: 4096) + "\"}}\n").utf8)
        for _ in 0..<(megabytes * 1_048_576 / row.count) {
            try output.write(contentsOf: row)
        }
        let tokenRow = "{\"timestamp\":\"2026-10-04T10:01:00Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":80,\"cached_input_tokens\":20,\"output_tokens\":20,\"total_tokens\":100}}}}"
        try output.write(contentsOf: Data(tokenRow.utf8))
        try output.close()
        let reader = CodexUsageReader(sessionsDirectory: root, cacheURL: root.appendingPathComponent("cache.plist"))
        for refresh in 1...3 {
            if refresh == 3 { try FileManager.default.removeItem(at: root.appendingPathComponent("cache.plist")) }
            let snapshot = reader.snapshot()
            precondition(snapshot.lifetime.total == 100 && snapshot.turnCount == 1)
            precondition(snapshot.unpricedTokens == 0)
            printResidentMemory(refresh: refresh)
        }
    }

    private static func printResidentMemory(refresh: Int) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        print("Refresh \(refresh): \(status == KERN_SUCCESS ? info.resident_size / 1_048_576 : 0) MiB resident")
    }
}
