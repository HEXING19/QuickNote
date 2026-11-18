import AppKit
import ImageIO
import QuickNoteCore

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

final class PaperImagePreview: NSPanel, NSWindowDelegate {
    private let scroll = NSScrollView()
    private let canvas = NSView()
    private let imageView = NSImageView()
    private let pixelSize: NSSize
    private let zoom = NSSegmentedControl(labels: ["适应窗口", "100%"], trackingMode: .selectOne, target: nil, action: nil)
    var onClose: (() -> Void)?

    init(image: NSImage, on screen: NSScreen) {
        pixelSize = image.representations.first.map { NSSize(width: $0.pixelsWide, height: $0.pixelsHigh) } ?? image.size
        let area = screen.visibleFrame
        let size = NSSize(width: min(920, area.width * 0.85), height: min(700, area.height * 0.85))
        super.init(contentRect: NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        title = "图片预览"
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        minSize = NSSize(width: 280, height: 200)
        delegate = self
        let toolbar = NSToolbar(identifier: "QuickNoteImagePreview")
        toolbar.delegate = self
        self.toolbar = toolbar
        zoom.selectedSegment = 0
        zoom.target = self; zoom.action = #selector(changeZoom)
        scroll.drawsBackground = true; scroll.backgroundColor = NSColor.windowBackgroundColor
        scroll.autohidesScrollers = true
        scroll.documentView = canvas
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        imageView.setAccessibilityLabel("便签原图")
        canvas.addSubview(imageView)
        contentView = scroll
        setFrameOrigin(NSPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2))
        layoutImage()
    }

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown && event.keyCode == 53 { close(); return }
        super.sendEvent(event)
    }

    func windowDidResize(_ notification: Notification) { layoutImage() }
    func windowWillClose(_ notification: Notification) { onClose?() }
    @objc private func changeZoom() { layoutImage(center: true) }

    private func layoutImage(center: Bool = false) {
        let actual = zoom.selectedSegment == 1
        scroll.hasHorizontalScroller = actual; scroll.hasVerticalScroller = actual
        let viewport = scroll.contentSize
        let actualScale = 1 / backingScaleFactor
        let scale = actual ? actualScale : min(actualScale, max(1, viewport.width - 40) / max(1, pixelSize.width), max(1, viewport.height - 40) / max(1, pixelSize.height))
        let size = NSSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
        let canvasSize = NSSize(width: max(viewport.width, size.width), height: max(viewport.height, size.height))
        canvas.setFrameSize(canvasSize)
        imageView.frame = NSRect(x: (canvasSize.width - size.width) / 2, y: (canvasSize.height - size.height) / 2, width: size.width, height: size.height)
        if center {
            scroll.contentView.scroll(to: NSPoint(x: (canvasSize.width - viewport.width) / 2, y: (canvasSize.height - viewport.height) / 2))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}

extension PaperImagePreview: NSToolbarDelegate {
    private static let zoomItem = NSToolbarItem.Identifier("imageZoom")
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, Self.zoomItem] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, Self.zoomItem] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard identifier == Self.zoomItem else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "缩放"; item.view = zoom
        return item
    }
}
