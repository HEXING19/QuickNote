import AppKit
import ImageIO
import UniformTypeIdentifiers

final class PaperImage: NSTextAttachment {
    static let pasteboardTypes: [NSPasteboard.PasteboardType] = [.png, .init("public.jpeg"), .tiff]
    let id: String
    let thumbnail: NSImage?

    convenience init(id: String, data: Data?) {
        self.init(id: id, thumbnail: data.flatMap { Self.thumbnail(from: $0) })
    }

    init(id: String, thumbnail: NSImage?) {
        self.id = id
        self.thumbnail = thumbnail
        super.init(data: nil, ofType: nil)
        let cell = PaperImageCell(imageCell: thumbnail ?? NSImage(systemSymbolName: "photo.badge.exclamationmark", accessibilityDescription: "图片不可用"))
        cell.attachment = self
        attachmentCell = cell
    }

    required init?(coder: NSCoder) { return nil }

    static func quickLookFile(from data: Data) throws -> URL {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source),
              let ext = UTType(identifier as String)?.preferredFilenameExtension else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("QuickNote-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent("便签图片").appendingPathExtension(ext)
        do { try data.write(to: file, options: .atomic) }
        catch { try? FileManager.default.removeItem(at: directory); throw error }
        return file
    }

    static func thumbnail(from data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 640
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

private final class PaperImageCell: NSTextAttachmentCell {
    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect, glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        guard let size = image?.size, size.width > 0, size.height > 0 else { return super.cellFrame(for: textContainer, proposedLineFragment: lineFrag, glyphPosition: position, characterIndex: charIndex) }
        let width = max(1, lineFrag.width - 2 * textContainer.lineFragmentPadding)
        let scale = min(1, width / size.width, 180 / size.height)
        return NSRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int, layoutManager: NSLayoutManager) {
        image?.draw(in: cellFrame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
