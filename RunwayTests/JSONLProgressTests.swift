import CryptoKit
import Foundation
import Testing
@testable import Runway

@Test("Verified JSONL resumes after an exact prefix across UTF-8 and row boundaries", arguments: [1, 7, 65_536])
func jsonlVerifiedSuffix(chunkSize: Int) throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let prefix = Data("\n{\"id\":1,\"text\":\"héllo 🚆\"}\r\n".utf8)
    try prefix.write(to: url)
    var ids: [Int] = []
    let first = try JSONLFileReader.forEachRow(at: url, chunkSize: chunkSize) {
        ids.append($0["id"] as! Int)
    }
    #expect(ids == [1])
    #expect(first.bytesRead == UInt64(prefix.count))
    #expect(first.prefixDigest == Data(SHA256.hash(data: prefix)))
    #expect(first.endedWithNewline)
    let largeText = String(repeating: "🚆", count: chunkSize == 1 ? 40 : 20_000)
    var suffix = Data("malformed\n{\"truncated\":\n".utf8)
    suffix.append(try JSONSerialization.data(withJSONObject: ["id": 2, "text": largeText]))
    suffix.append(Data("\r\n{\"id\":3}".utf8))
    let writer = try FileHandle(forWritingTo: url)
    try writer.seekToEnd()
    try writer.write(contentsOf: suffix)
    try writer.close()
    ids = []
    let progress = try JSONLFileReader.forEachRow(at: url, chunkSize: chunkSize,
        offset: first.bytesRead, expectedPrefixDigest: first.prefixDigest, expectedIdentity: first.identity) {
        ids.append($0["id"] as! Int)
        if $0["id"] as? Int == 2 { #expect($0["text"] as? String == largeText) }
    }
    let full = prefix + suffix
    #expect(ids == [2, 3])
    #expect(progress.bytesRead == UInt64(full.count))
    #expect(progress.prefixDigest == Data(SHA256.hash(data: full)))
    #expect(!progress.endedWithNewline)
    #expect(progress.identity == first.identity)
    #expect(try JSONDecoder().decode(JSONLFileReader.ReadProgress.self,
        from: JSONEncoder().encode(progress)) == progress)
}

@Test("Verified JSONL rejects an in-place middle rewrite before any suffix callbacks")
func jsonlRejectsRewrittenPrefix() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let original = Data("{\"id\":1}\n{\"id\":2,\"text\":\"middle\"}\n{\"id\":3}\n".utf8)
    try original.write(to: url)
    let first = try JSONLFileReader.forEachRow(at: url, chunkSize: 7) { _ in }
    var rewritten = original
    rewritten.replaceSubrange(rewritten.range(of: Data("middle".utf8))!, with: Data("MIDDLE".utf8))
    rewritten.append(Data("{\"id\":4}\n".utf8))
    let writer = try FileHandle(forWritingTo: url)
    try writer.write(contentsOf: rewritten)
    try writer.close()
    var callbacks = 0
    #expect(throws: JSONLFileReader.ReadError.prefixMismatch) {
        try JSONLFileReader.forEachRow(at: url, chunkSize: 7, offset: first.bytesRead,
            expectedPrefixDigest: first.prefixDigest, expectedIdentity: first.identity) { _ in callbacks += 1 }
    }
    #expect(callbacks == 0)
}

@Test("Verified JSONL rejects replacement, truncation and mid-row offsets")
func jsonlRejectsInvalidSources() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let original = Data("{\"id\":1}\n{\"id\":2}\n".utf8)
    try original.write(to: url)
    let first = try JSONLFileReader.forEachRow(at: url) { _ in }
    try original.write(to: url, options: .atomic)
    var callbacks = 0
    #expect(throws: JSONLFileReader.ReadError.sourceReplaced) {
        try JSONLFileReader.forEachRow(at: url, offset: first.bytesRead,
            expectedPrefixDigest: first.prefixDigest, expectedIdentity: first.identity) { _ in callbacks += 1 }
    }
    let replacement = try JSONLFileReader.forEachRow(at: url) { _ in }
    #expect(throws: JSONLFileReader.ReadError.invalidOffset) {
        try JSONLFileReader.forEachRow(at: url, offset: 1) { _ in callbacks += 1 }
    }
    let writer = try FileHandle(forWritingTo: url)
    try writer.truncate(atOffset: 2)
    try writer.close()
    #expect(throws: JSONLFileReader.ReadError.invalidOffset) {
        try JSONLFileReader.forEachRow(at: url, offset: replacement.bytesRead,
            expectedPrefixDigest: replacement.prefixDigest, expectedIdentity: replacement.identity) { _ in callbacks += 1 }
    }
    #expect(callbacks == 0)
}

@Test("Verified JSONL bounds reads and rejects a visitor appending to the source")
func jsonlRejectsConcurrentAppend() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("{\"id\":1}\n{\"id\":2}\n".utf8).write(to: url)
    var ids: [Int] = []
    var mutationError: Error?
    #expect(throws: JSONLFileReader.ReadError.sourceChanged) {
        try JSONLFileReader.forEachRow(at: url, chunkSize: 7) { row in
            ids.append(row["id"] as! Int)
            guard ids.count == 1 else { return }
            do {
                let writer = try FileHandle(forWritingTo: url)
                try writer.seekToEnd()
                try writer.write(contentsOf: Data("{\"id\":3}\n".utf8))
                try writer.close()
            } catch { mutationError = error }
        }
    }
    #expect(mutationError == nil)
    #expect(ids == [1, 2])
}

@Test("Verified JSONL reports empty files and exact EOF without replaying rows")
func jsonlEmptyAndUnchanged() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data().write(to: url)
    var callbacks = 0
    let empty = try JSONLFileReader.forEachRow(at: url, chunkSize: 1) { _ in callbacks += 1 }
    #expect(empty.bytesRead == 0)
    #expect(empty.prefixDigest == Data(SHA256.hash(data: Data())))
    #expect(empty.endedWithNewline)
    try Data("{\"id\":1}\n".utf8).write(to: url)
    let first = try JSONLFileReader.forEachRow(at: url) { _ in }
    let unchanged = try JSONLFileReader.forEachRow(at: url, chunkSize: 1, offset: first.bytesRead,
        expectedPrefixDigest: first.prefixDigest, expectedIdentity: first.identity) { _ in callbacks += 1 }
    #expect(unchanged == first)
    #expect(callbacks == 0)
}
