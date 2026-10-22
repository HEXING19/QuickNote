import Foundation
import CryptoKit

public final class NoteStore {
    public struct FontSizeRun: Codable, Equatable {
        public let location: Int
        public let length: Int
        public let size: Double
        public init(location: Int, length: Int, size: Double) {
            self.location = location; self.length = length; self.size = size
        }
    }
    struct Envelope: Codable {
        let version: Int
        let text: String
        let digest: String
        let updated: Date
        var fontSizes: [FontSizeRun]? = nil
    }
    public let directory: URL
    public private(set) var text = ""
    public private(set) var fontSizes: [FontSizeRun] = []
    public private(set) var recoveryMessage: String?
    public private(set) var isBlocked = false
    private var lastSnapshot = Date.distantPast
    private let fm = FileManager.default
    public var primary: URL { directory.appendingPathComponent("scratchpad.json") }
    private var previous: URL { directory.appendingPathComponent("previous.json") }
    public var backupDirectory: URL { directory.appendingPathComponent("Backups", isDirectory: true) }
    public init(directory: URL) throws {
        self.directory = directory
        try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        if fm.fileExists(atPath: primary.path) {
            do { apply(try read(primary)); return }
            catch {
                // Preserve the unreadable original before any future write.
                try fm.copyItem(at: primary, to: directory.appendingPathComponent("unreadable-\(UUID().uuidString).json"))
                for candidate in [previous] + backups() {
                    if let recovered = try? read(candidate) {
                        apply(recovered)
                        recoveryMessage = "已从备份恢复，请检查内容。"
                        return
                    }
                }
                isBlocked = true
                recoveryMessage = "记录文件无法读取，原文件已保留。请通过备份恢复。"
            }
        } else {
            // A missing main file must not silently ignore surviving backups.
            for candidate in [previous] + backups() {
                if let recovered = try? read(candidate) {
                    apply(recovered)
                    recoveryMessage = "已从备份找回记录。"
                    return
                }
            }
        }
    }
    private func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func apply(_ record: Envelope) {
        text = record.text
        fontSizes = record.fontSizes ?? []
    }
    private func read(_ url: URL) throws -> Envelope {
        let record = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url))
        guard record.version == 1, record.digest == digest(record.text) else { throw StoreError.invalid }
        let length = (record.text as NSString).length
        guard (record.fontSizes ?? []).allSatisfy({
            $0.location >= 0 && $0.length > 0 && $0.location <= length &&
            $0.length <= length - $0.location && $0.size.isFinite && (8...96).contains($0.size)
        }) else { throw StoreError.invalid }
        return record
    }
    private func durableWrite(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }
    public func save(_ value: String, fontSizes: [FontSizeRun] = [], forceSnapshot: Bool = false) throws {
        guard !isBlocked else { throw StoreError.blocked }
        if fm.fileExists(atPath: primary.path), let existing = try? Data(contentsOf: primary), (try? read(primary)) != nil {
            try durableWrite(existing, to: previous)
            if forceSnapshot || Date().timeIntervalSince(lastSnapshot) >= 60 {
                try durableWrite(existing, to: backupDirectory.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(6)).json"))
                lastSnapshot = Date()
            }
        }
        let record = Envelope(version: 1, text: value, digest: digest(value), updated: Date(), fontSizes: fontSizes.isEmpty ? nil : fontSizes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try durableWrite(encoder.encode(record), to: primary)
        apply(record)
        let old = backups().dropFirst(100)
        for url in old { try? fm.removeItem(at: url) }
    }
    public func backups() -> [URL] {
        ((try? fm.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
    public func backupText(at url: URL) throws -> String { try read(url).text }
    public func restore(from url: URL) throws -> String {
        let recovered = try read(url)
        let blocked = isBlocked
        isBlocked = false
        do { try save(recovered.text, fontSizes: recovered.fontSizes ?? [], forceSnapshot: true) }
        catch { isBlocked = blocked; throw error }
        recoveryMessage = nil
        return recovered.text
    }
    public enum StoreError: LocalizedError {
        case invalid, blocked
        public var errorDescription: String? {
            switch self {
            case .invalid: return "文件校验失败，不能恢复这份备份。"
            case .blocked: return "原记录无法读取，请先恢复备份，避免覆盖原文件。"
            }
        }
    }
}
