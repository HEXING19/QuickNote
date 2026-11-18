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
    public struct ImageRun: Codable, Equatable {
        public let location: Int
        public let id: String
        public init(location: Int, id: String) {
            self.location = location; self.id = id
        }
    }
    public static let imageMarker = "\u{FFFC}"
    struct Envelope: Codable {
        let version: Int
        let text: String
        let digest: String
        let updated: Date
        var fontSizes: [FontSizeRun]? = nil
        var images: [ImageRun]? = nil
    }
    public let directory: URL
    public private(set) var text = ""
    public private(set) var fontSizes: [FontSizeRun] = []
    public private(set) var images: [ImageRun] = []
    public private(set) var recoveryMessage: String?
    public private(set) var isBlocked = false
    private var lastSnapshot = Date.distantPast
    private let fm = FileManager.default
    public var primary: URL { directory.appendingPathComponent("scratchpad.json") }
    private var previous: URL { directory.appendingPathComponent("previous.json") }
    public var backupDirectory: URL { directory.appendingPathComponent("Backups", isDirectory: true) }
    private var imageDirectory: URL { directory.appendingPathComponent("Images", isDirectory: true) }
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
    private func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private func digest(_ text: String, images: [ImageRun]) -> String {
        let textHash = hash(Data(text.utf8))
        guard !images.isEmpty else { return textHash }
        return hash(Data(([textHash] + images.map { "\($0.location):\($0.id)" }).joined(separator: "\n").utf8))
    }
    private func validID(_ id: String) -> Bool {
        id.utf8.count == 64 && id.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private func validImages(_ images: [ImageRun], in text: NSString) -> Bool {
        var previous = -1
        for image in images {
            guard image.location > previous, image.location < text.length,
                  text.character(at: image.location) == 0xFFFC, validID(image.id) else { return false }
            previous = image.location
        }
        return true
    }
    public func storeImage(_ data: Data) throws -> String {
        guard !isBlocked else { throw StoreError.blocked }
        let id = hash(data)
        try fm.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        if imageData(for: id) == nil { try durableWrite(data, to: imageDirectory.appendingPathComponent(id)) }
        return id
    }
    public func imageData(for id: String) -> Data? {
        guard validID(id), let data = try? Data(contentsOf: imageDirectory.appendingPathComponent(id)), hash(data) == id else { return nil }
        return data
    }
    public static func plainText(_ text: String, images: [ImageRun]) -> String {
        let result = NSMutableString(string: text)
        for image in images.reversed() where image.location >= 0 && image.location < result.length && result.character(at: image.location) == 0xFFFC {
            result.replaceCharacters(in: NSRange(location: image.location, length: 1), with: "[图片]")
        }
        return result as String
    }
    private func apply(_ record: Envelope) {
        text = record.text
        fontSizes = record.fontSizes ?? []
        images = record.images ?? []
    }
    private func read(_ url: URL) throws -> Envelope {
        let record = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url))
        let images = record.images ?? []
        guard record.version == (images.isEmpty ? 1 : 2), validImages(images, in: record.text as NSString),
              record.digest == digest(record.text, images: images) else { throw StoreError.invalid }
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
    public func save(_ value: String, fontSizes: [FontSizeRun] = [], images: [ImageRun] = [], forceSnapshot: Bool = false) throws {
        guard !isBlocked else { throw StoreError.blocked }
        guard validImages(images, in: value as NSString) else { throw StoreError.invalid }
        if fm.fileExists(atPath: primary.path), let existing = try? Data(contentsOf: primary), (try? read(primary)) != nil {
            try durableWrite(existing, to: previous)
            if forceSnapshot || Date().timeIntervalSince(lastSnapshot) >= 60 {
                try durableWrite(existing, to: backupDirectory.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(6)).json"))
                lastSnapshot = Date()
            }
        }
        let record = Envelope(version: images.isEmpty ? 1 : 2, text: value, digest: digest(value, images: images), updated: Date(), fontSizes: fontSizes.isEmpty ? nil : fontSizes, images: images.isEmpty ? nil : images)
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
    public func backupText(at url: URL) throws -> String {
        let record = try read(url)
        return Self.plainText(record.text, images: record.images ?? [])
    }
    public func restore(from url: URL) throws -> String {
        let recovered = try read(url)
        let blocked = isBlocked
        isBlocked = false
        do { try save(recovered.text, fontSizes: recovered.fontSizes ?? [], images: recovered.images ?? [], forceSnapshot: true) }
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
