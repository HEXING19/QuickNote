import AppKit
import Carbon
import ServiceManagement
import QuickNoteCore

extension NSColor {
    convenience init(hex: UInt32) { self.init(srgbRed: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255, blue: CGFloat(hex & 255)/255, alpha: 1) }
}
let ink = PaperIdentity.ink
let muted = PaperIdentity.muted
let line = PaperIdentity.rule
let chrome = PaperIdentity.paper
func symbol(_ name: String) -> NSImage? { NSImage(systemSymbolName: name, accessibilityDescription: nil) }

final class NotePanel: NSPanel {
    var acceptsEditingFocus = true
    override var canBecomeKey: Bool { acceptsEditingFocus }
    override var canBecomeMain: Bool { false }
}
/// Keep the document and its wrapping container tied to the visible paper width.
final class PaperScrollView: NSScrollView {
    override func tile() {
        super.tile()
        guard let text = documentView as? NSTextView, contentSize.width > 0 else { return }
        let width = contentSize.width
        text.minSize.width = width
        text.maxSize.width = width
        if abs(text.frame.width-width) > 0.5 {
            text.setFrameSize(NSSize(width: width, height: text.frame.height))
        }
        text.textContainer?.containerSize = NSSize(width: max(1, width-2*text.textContainerInset.width), height: .greatestFiniteMagnitude)
        // Earlier versions could leave a horizontal offset in the clip view.
        if contentView.bounds.minX != 0 {
            contentView.scroll(to: NSPoint(x: 0, y: contentView.bounds.minY))
            reflectScrolledClipView(contentView)
        }
    }
}
final class PaperView: FontSizingTextView {
    var escape: (() -> Void)?
    var store: NoteStore?
    var previewImage: ((PaperImage) -> Void)?
    var imagePasteFailed: ((String) -> Void)?
    override func cancelOperation(_ sender: Any?) {
        if hasMarkedText() { super.cancelOperation(sender) } else { escape?() }
    }
    override func paste(_ sender: Any?) {
        if !pasteImage(from: .general) { pasteAsPlainText(sender) }
    }
    @discardableResult func pasteImage(from pasteboard: NSPasteboard) -> Bool {
        guard isEditable, let store, let type = pasteboard.availableType(from: PaperImage.pasteboardTypes) else { return false }
        guard let data = pasteboard.data(forType: type), let thumbnail = PaperImage.thumbnail(from: data) else {
            if pasteboard.string(forType: .string) != nil { return false }
            imagePasteFailed?("剪贴板中的图片无法读取。"); return true
        }
        do {
            let id = try store.storeImage(data)
            let selection = selectedRange()
            let text = string as NSString
            let breaks = CharacterSet.newlines
            let needsBreak = selection.location > 0 && text.rangeOfCharacter(from: breaks, options: [], range: NSRange(location: selection.location - 1, length: 1)).location == NSNotFound
            let insertion = NSMutableAttributedString(string: needsBreak ? "\n" : "", attributes: typingAttributes)
            insertion.append(NSAttributedString(attachment: PaperImage(id: id, thumbnail: thumbnail)))
            insertion.append(NSAttributedString(string: "\n", attributes: typingAttributes))
            breakUndoCoalescing()
            insertText(insertion, replacementRange: selection)
            breakUndoCoalescing()
            undoManager?.setActionName("粘贴图片")
        } catch { imagePasteFailed?(error.localizedDescription) }
        return true
    }
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)), NSPasteboard.general.availableType(from: PaperImage.pasteboardTypes) != nil { return isEditable }
        return super.validateUserInterfaceItem(item)
    }
    var savedImages: [NoteStore.ImageRun] {
        guard let storage = textStorage else { return [] }
        var images: [NoteStore.ImageRun] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let image = value as? PaperImage else { return }
            for location in range.location..<NSMaxRange(range) { images.append(.init(location: location, id: image.id)) }
        }
        return images
    }
    func loadImages(_ images: [NoteStore.ImageRun]) {
        guard let storage = textStorage else { return }
        storage.beginEditing()
        for image in images {
            storage.addAttribute(.attachment, value: PaperImage(id: image.id, data: store?.imageData(for: image.id)), range: NSRange(location: image.location, length: 1))
        }
        storage.endEditing()
    }
    func imageIndex(at point: NSPoint) -> Int? {
        guard let manager = layoutManager, let container = textContainer, let storage = textStorage else { return nil }
        manager.ensureLayout(for: container)
        let origin = textContainerOrigin
        let point = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let glyph = manager.glyphIndex(for: point, in: container)
        guard glyph < manager.numberOfGlyphs,
              manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(point) else { return nil }
        let index = manager.characterIndexForGlyph(at: glyph)
        return storage.attribute(.attachment, at: index, effectiveRange: nil) is PaperImage ? index : nil
    }
    override func mouseDown(with event: NSEvent) {
        if !hasMarkedText(), event.modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty,
           let index = imageIndex(at: convert(event.locationInWindow, from: nil)),
           let image = textStorage?.attribute(.attachment, at: index, effectiveRange: nil) as? PaperImage {
            previewImage?(image); return
        }
        super.mouseDown(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let index = imageIndex(at: convert(event.locationInWindow, from: nil)) else { return super.menu(for: event) }
        let menu = NSMenu()
        for (title, action) in [("复制图片", #selector(copyImageFromMenu)), ("删除图片", #selector(deleteImageFromMenu))] {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self; item.tag = index
            if action == #selector(deleteImageFromMenu), !isEditable { menu.removeItem(item) }
        }
        return menu
    }
    @objc private func copyImageFromMenu(_ sender: NSMenuItem) { _ = copyImage(at: sender.tag) }
    @objc private func deleteImageFromMenu(_ sender: NSMenuItem) {
        guard isEditable, !hasMarkedText(), let storage = textStorage, sender.tag < storage.length,
              storage.attribute(.attachment, at: sender.tag, effectiveRange: nil) is PaperImage else { return }
        let text = string as NSString
        let startsLine = sender.tag == 0 || text.character(at: sender.tag - 1) == 10
        let endsLine = sender.tag + 1 < text.length && text.character(at: sender.tag + 1) == 10
        breakUndoCoalescing()
        insertText("", replacementRange: NSRange(location: sender.tag, length: startsLine && endsLine ? 2 : 1))
        breakUndoCoalescing()
        undoManager?.setActionName("删除图片")
    }
    private func copyImage(at index: Int) -> Bool {
        guard let storage = textStorage, index < storage.length,
              let image = storage.attribute(.attachment, at: index, effectiveRange: nil) as? PaperImage,
              let data = store?.imageData(for: image.id), let bitmap = NSImage(data: data) else { return false }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.writeObjects([bitmap])
    }
    override func copy(_ sender: Any?) {
        let selection = selectedRange()
        let images = savedImages.filter { NSLocationInRange($0.location, selection) }
        guard !images.isEmpty else { super.copy(sender); return }
        if selection.length == 1, copyImage(at: selection.location) { return }
        let text = (string as NSString).substring(with: selection)
        let relative = images.map { NoteStore.ImageRun(location: $0.location - selection.location, id: $0.id) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(NoteStore.plainText(text, images: relative), forType: .string)
    }
    override func cut(_ sender: Any?) {
        let selection = selectedRange()
        guard savedImages.contains(where: { NSLocationInRange($0.location, selection) }) else { super.cut(sender); return }
        guard isEditable, !hasMarkedText() else { return }
        copy(sender)
        breakUndoCoalescing(); insertText("", replacementRange: selection); breakUndoCoalescing()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.option) && !event.modifierFlags.contains(.control) {
            switch event.charactersIgnoringModifiers {
            case "a": selectAll(nil); return true
            case "c": copy(nil); return true
            case "v": paste(nil); return true
            case "x": cut(nil); return true
            case "z": if event.modifierFlags.contains(.shift) { undoManager?.redo() } else { undoManager?.undo() }; return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}
final class HandleView: NSView {
    static let restingWidth: CGFloat = 29.4
    static let expandedWidth: CGFloat = 85.4
    static let paperHeight: CGFloat = 50.4
    var clicked: (() -> Void)?
    var moved: ((CGFloat) -> Void)?
    var finishedDrag: (() -> Void)?
    private var start: NSPoint?
    private var originY: CGFloat = 0
    private var dragging = false
    override init(frame: NSRect) {
        super.init(frame: frame)
        toolTip = "记一下 · 悬停预览，点击落笔，上下拖动"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("记一下，悬停自动展开，点击后编辑，可上下拖动")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func accessibilityPerformPress() -> Bool { clicked?(); return true }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize); needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        // The right edge stays flush with the display; only the left edge moves.
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let scale = NSAffineTransform(); scale.scale(by: 0.7); scale.concat()
        let r = NSRect(x: 0, y: 0, width: bounds.width/0.7, height: bounds.height/0.7)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: r.maxX, y: 0))
        path.line(to: NSPoint(x: 16, y: 0))
        path.curve(to: NSPoint(x: 0, y: 16), controlPoint1: NSPoint(x: 5, y: 0), controlPoint2: NSPoint(x: 0, y: 5))
        path.line(to: NSPoint(x: 0, y: r.height-16))
        path.curve(to: NSPoint(x: 16, y: r.height), controlPoint1: NSPoint(x: 0, y: r.height-5), controlPoint2: NSPoint(x: 5, y: r.height))
        path.line(to: NSPoint(x: r.maxX, y: r.height)); path.close()
        PaperIdentity.paper.setFill(); path.fill()
        let fold = NSBezierPath()
        fold.move(to: NSPoint(x: 1, y: 13)); fold.line(to: NSPoint(x: 11, y: 13))
        fold.curve(to: NSPoint(x: 14, y: 10), controlPoint1: NSPoint(x: 13, y: 13), controlPoint2: NSPoint(x: 14, y: 12))
        fold.line(to: NSPoint(x: 14, y: 1))
        fold.curve(to: NSPoint(x: 1, y: 13), controlPoint1: NSPoint(x: 6, y: 3), controlPoint2: NSPoint(x: 2, y: 7))
        NSColor(srgbRed: 0.88, green: 0.82, blue: 0.70, alpha: 1).setFill(); fold.fill()
        PaperIdentity.drawMark(in: NSRect(x: 11, y: (r.height-23)/2, width: 23, height: 23))
        let progress = max(0, min(1, (bounds.width-Self.restingWidth)/(Self.expandedWidth-Self.restingWidth)))
        if progress > 0 {
            ("记一下" as NSString).draw(at: NSPoint(x: 45, y: (r.height-19)/2), withAttributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: PaperIdentity.ink.withAlphaComponent(progress)
            ])
        }
    }
    override func mouseDown(with event: NSEvent) { start = NSEvent.mouseLocation; originY = window?.frame.minY ?? 0; dragging = false }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let delta = NSEvent.mouseLocation.y - start.y
        if abs(delta) > 4 { dragging = true }
        if dragging { moved?(originY + delta) }
    }
    override func mouseUp(with event: NSEvent) { if dragging { finishedDrag?() } else { clicked?() }; start = nil }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate, NSWindowDelegate, NSMenuDelegate {
    lazy var updater = UpdateController(app: self)
    var settingsController: SettingsWindowController?
    var store: NoteStore?
    let defaults: UserDefaults = {
        if let index = CommandLine.arguments.firstIndex(of: "--data-dir"), index + 1 < CommandLine.arguments.count {
            return UserDefaults(suiteName: "QuickNote.Isolated." + URL(fileURLWithPath: CommandLine.arguments[index + 1]).lastPathComponent)!
        }
        return .standard
    }()
    var panel: NotePanel!
    var handle: NSPanel!
    var handleView: HandleView!
    var editor: PaperView!
    var placeholder: NSTextField!
    var statusLabel: NSTextField!
    var saveIcon: NSImageView!
    var statusItem: NSStatusItem!
    var previousApp: NSRunningApplication?
    var globalMouse: Any?
    var localMouse: Any?
    var localKey: Any?
    var hotKey: EventHotKeyRef?
    var hotHandler: EventHandlerRef?
    var dirty = false
    var inDialog = false
    var imagePreview: PaperImagePreview?
    var saveTimer: Timer?
    var openGeneration = 0
    var drawerInteraction = DrawerInteraction()
    var hoverTimer: Timer?
    var currentScreen: NSScreen { handle?.screen ?? NSScreen.main ?? NSScreen.screens[0] }
    var preview: Bool { CommandLine.arguments.contains("--preview") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !CommandLine.arguments.contains("--data-dir") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { self.updater.check(automatic: true) }
        }
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .aqua)
        buildApplicationMenu()
        let root: URL
        if let index = CommandLine.arguments.firstIndex(of: "--data-dir"), index + 1 < CommandLine.arguments.count {
            root = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        } else {
            root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QuickNote", isDirectory: true)
        }
        do { store = try NoteStore(directory: root) } catch { alert("无法打开记录目录", error.localizedDescription) }
        defaults.removeObject(forKey: "pinned")
        buildPanel(); buildHandle(); buildStatusMenu()
        if !CommandLine.arguments.contains("--settings-preview") && !CommandLine.arguments.contains("--paper-preview") { registerShortcut(defaults.integer(forKey: "shortcut")) }
        if let message = store?.recoveryMessage { statusLabel.stringValue = message; statusLabel.textColor = NSColor(hex: 0x92400e) }
        globalMouse = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.clickedOutside() }
        }
        localMouse = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self {
                if event.window == self.panel { self.commitPreview() }
                else if event.window != self.handle { self.clickedOutside() }
            }
            return event
        }
        localKey = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.window === self.panel, self.panel.isKeyWindow, self.panel.firstResponder === self.editor,
               self.editor.handleFontSizeShortcut(event) { return nil }
            let index = self.defaults.integer(forKey: "shortcut")
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let matches = (index == 0 && event.keyCode == 49 && flags == .option) || (index == 1 && event.keyCode == 38 && flags == [.command, .shift]) || (index == 2 && event.keyCode == 40 && flags == [.command, .shift])
            if matches { DispatchQueue.main.async { self.toggle() }; return nil }
            return event
        }
        if !CommandLine.arguments.contains("--settings-preview") && !CommandLine.arguments.contains("--paper-preview") {
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.checkHover() }
            timer.tolerance = 0.03
            RunLoop.main.add(timer, forMode: .common)
            hoverTimer = timer
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(deactivated), name: NSApplication.didResignActiveNotification, object: nil)
        if preview || !defaults.bool(forKey: "hasLaunched") { showPanel(onPointerScreen: false); defaults.set(true, forKey: "hasLaunched") }
        if CommandLine.arguments.contains("--settings-preview") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.captureSettingsPreview() }
        }
        if CommandLine.arguments.contains("--paper-preview") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.capturePaperPreview() }
        }
        if preview {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.capturePreview() }
        }
    }
    func buildApplicationMenu() {
        let main = NSMenu()
        let app = NSMenuItem(); let appMenu = NSMenu(); app.submenu = appMenu
        appMenu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 QuickNote", action: #selector(quit), keyEquivalent: "q").target = self
        main.addItem(app)
        let edit = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "编辑"); edit.submenu = menu
        for (title, selector, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            menu.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "放大字体", action: #selector(FontSizingTextView.enlargeSelectedText(_:)), keyEquivalent: "+")
        menu.addItem(withTitle: "缩小字体", action: #selector(FontSizingTextView.shrinkSelectedText(_:)), keyEquivalent: "-")
        main.addItem(edit); NSApp.mainMenu = main
    }
    func label(_ text: String, size: CGFloat = 12, color: NSColor = muted) -> NSTextField {
        let v = NSTextField(labelWithString: text); v.font = .systemFont(ofSize: size); v.textColor = color; v.translatesAutoresizingMaskIntoConstraints = false; return v
    }
    func iconButton(_ name: String, title: String, action: Selector) -> NSButton {
        let button = NSButton(image: symbol(name)!, target: self, action: action)
        button.isBordered = false; button.contentTintColor = muted; button.toolTip = title; button.setAccessibilityLabel(title)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([button.widthAnchor.constraint(equalToConstant: 34), button.heightAnchor.constraint(equalToConstant: 34)])
        return button
    }
    func buildPanel() {
        panel = NotePanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 520), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "QuickNote"; panel.identifier = NSUserInterfaceItemIdentifier("QuickNoteEditor")
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.delegate = self
        let root = NSView(); root.wantsLayer = true; root.layer?.backgroundColor = chrome.cgColor; root.layer?.cornerRadius = 16; root.layer?.borderWidth = 0; root.layer?.borderColor = line.cgColor; root.layer?.masksToBounds = true
        root.appearance = NSAppearance(named: .aqua); panel.contentView = root
        let title = label("速记", size: 14, color: ink)
        let close = iconButton("xmark", title: "收起（Esc）", action: #selector(hideAction))
        let topLine = NSView(); topLine.wantsLayer = true; topLine.layer?.backgroundColor = line.cgColor; topLine.translatesAutoresizingMaskIntoConstraints = false
        let scroll = PaperScrollView(); scroll.drawsBackground = true; scroll.backgroundColor = PaperIdentity.paper; scroll.hasHorizontalScroller = false; scroll.horizontalScrollElasticity = .none; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.borderType = .noBorder; scroll.translatesAutoresizingMaskIntoConstraints = false
        editor = PaperView(frame: NSRect(x: 0, y: 0, width: 360, height: 420))
        editor.minSize = NSSize(width: 0, height: 0); editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false; editor.autoresizingMask = [.width]
        editor.textContainer?.containerSize = NSSize(width: 360, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.isRichText = true; editor.importsGraphics = false; editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
        editor.font = .systemFont(ofSize: 14); editor.textColor = ink; editor.insertionPointColor = PaperIdentity.ink
        editor.backgroundColor = PaperIdentity.paper; editor.textContainerInset = NSSize(width: 16, height: 20)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 7; paragraph.lineBreakMode = .byCharWrapping; editor.defaultParagraphStyle = paragraph
        editor.typingAttributes = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: ink, .paragraphStyle: paragraph]
        editor.string = store?.text ?? ""; editor.delegate = self; editor.isEditable = store != nil && store?.isBlocked == false
        editor.loadFontSizes(store?.fontSizes ?? [])
        editor.store = store; editor.loadImages(store?.images ?? [])
        editor.previewImage = { [weak self] image in self?.showImagePreview(image) }
        editor.imagePasteFailed = { [weak self] message in self?.alert("无法粘贴图片", message) }
        editor.escape = { [weak self] in self?.hidePanel(restoreFocus: true) }
        scroll.documentView = editor
        scroll.tile()
        placeholder = label("先记下来…", size: 14, color: NSColor(hex: 0xa1a1aa)); placeholder.isHidden = !editor.string.isEmpty
        statusLabel = label(store == nil ? "存储不可用 · 请先导出文字" : "自动保存", size: 11)
        saveIcon = NSImageView(image: symbol("checkmark.circle")!); saveIcon.contentTintColor = muted; saveIcon.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for v in [title, close, topLine, scroll, placeholder!, saveIcon!, statusLabel!] { root.addSubview(v) }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22), title.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            close.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8), close.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            topLine.topAnchor.constraint(equalTo: root.topAnchor, constant: 48), topLine.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22), topLine.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16), topLine.heightAnchor.constraint(equalToConstant: 0.5),
            scroll.topAnchor.constraint(equalTo: topLine.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 1), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -1), scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -44),
            placeholder.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 21), placeholder.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 20),
            saveIcon.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22), saveIcon.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor), saveIcon.widthAnchor.constraint(equalToConstant: 15), saveIcon.heightAnchor.constraint(equalToConstant: 15),
            statusLabel.leadingAnchor.constraint(equalTo: saveIcon.trailingAnchor, constant: 6), statusLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18), statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -22)
        ])
    }
    func buildHandle() {
        handle = NSPanel(contentRect: NSRect(x: 0, y: 0, width: HandleView.restingWidth, height: HandleView.paperHeight), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        handle.level = .floating; handle.hidesOnDeactivate = false; handle.isOpaque = false; handle.backgroundColor = .clear; handle.hasShadow = false
        handle.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        handleView = HandleView(frame: NSRect(x: 0, y: 0, width: HandleView.restingWidth, height: HandleView.paperHeight)); handle.contentView = handleView
        handleView.clicked = { [weak self] in self?.showPanel(onPointerScreen: false) }
        handleView.moved = { [weak self] y in
            guard let self else { return }; let area = self.currentScreen.visibleFrame
            self.handle.setFrameOrigin(NSPoint(x: area.maxX-self.handle.frame.width, y: min(max(y, area.minY+16), area.maxY-HandleView.paperHeight-16)))
        }
        handleView.finishedDrag = { [weak self] in
            guard let self else { return }; let area = self.currentScreen.visibleFrame
            self.defaults.set((self.handle.frame.midY-area.minY)/area.height, forKey: "handleFraction")
        }
        positionHandle(on: NSScreen.main ?? NSScreen.screens[0]); handle.orderFrontRegardless()
    }
    func positionHandle(on screen: NSScreen) {
        let area = screen.visibleFrame
        let fraction = defaults.object(forKey: "handleFraction") == nil ? 0.5 : defaults.double(forKey: "handleFraction")
        let y = min(max(area.minY + area.height * fraction - HandleView.paperHeight/2, area.minY+16), area.maxY-HandleView.paperHeight-16)
        let width = HandleView.restingWidth
        handle.setFrame(NSRect(x: area.maxX-width, y: y, width: width, height: HandleView.paperHeight), display: true)
    }
    func showPanel(onPointerScreen: Bool = true, asPreview: Bool = false) {
        let opening = !panel.isVisible
        openGeneration += 1
        if !panel.isVisible { previousApp = NSWorkspace.shared.frontmostApplication }
        let screen = onPointerScreen ? (NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? currentScreen) : currentScreen
        positionHandle(on: screen)
        let area = screen.visibleFrame
        let height = min(CGFloat(310), area.height-32), width = min(CGFloat(320), area.width-24)
        let y = min(max(handle.frame.midY-height/2, area.minY+16), area.maxY-height-16)
        let destination = NSRect(x: area.maxX-width, y: y, width: width, height: height)
        let animate = opening && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(animate ? destination.offsetBy(dx: 16, dy: 0) : destination, display: true)
        panel.alphaValue = animate ? 0 : 1
        panel.contentView?.layoutSubtreeIfNeeded()
        editor.enclosingScrollView?.tile()
        handle.orderOut(nil)
        if asPreview {
            panel.acceptsEditingFocus = false
            panel.setAccessibilityHelp("悬停预览，点击后继续编辑")
            editor.isEditable = false
            panel.makeFirstResponder(nil)
            panel.orderFrontRegardless()
        } else {
            drawerInteraction.beginEditing()
            panel.acceptsEditingFocus = true
            panel.setAccessibilityHelp("正在编辑，鼠标移开仍可继续输入")
            editor.isEditable = store != nil && store?.isBlocked == false
            NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(editor)
        }
        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().setFrame(destination, display: true)
                panel.animator().alphaValue = 1
            }
        }
        let location = min(defaults.integer(forKey: "selection"), (editor.string as NSString).length)
        editor.setSelectedRange(NSRange(location: location, length: 0)); editor.scrollRangeToVisible(editor.selectedRange())
    }
    func checkHover() {
        guard !inDialog, imagePreview == nil, settingsController?.window?.isVisible != true else { return }
        let pointer = NSEvent.mouseLocation
        let action = drawerInteraction.update(
            insideHandle: handle.frame.contains(pointer),
            insidePanel: panel.isVisible && panel.frame.contains(pointer),
            buttonDown: NSEvent.pressedMouseButtons != 0,
            now: ProcessInfo.processInfo.systemUptime)
        switch action {
        case .expandHandle: showPanel(onPointerScreen: false, asPreview: true)
        case .collapseHandle: _ = hidePanel(restoreFocus: false)
        case nil: break
        }
    }
    func commitPreview() {
        guard drawerInteraction.state == .hovered else { return }
        drawerInteraction.beginEditing()
        panel.acceptsEditingFocus = true
        editor.isEditable = store != nil && store?.isBlocked == false
        panel.setAccessibilityHelp("正在编辑，鼠标移开仍可继续输入")
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(editor)
    }
    func animateHandle(expanded: Bool, animated: Bool = true) {
        let width = expanded ? HandleView.expandedWidth : HandleView.restingWidth
        let frame = NSRect(x: currentScreen.visibleFrame.maxX-width, y: handle.frame.minY, width: width, height: HandleView.paperHeight)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.18 : 0
            handle.animator().setFrame(frame, display: true)
        }
    }
    @discardableResult func hidePanel(restoreFocus: Bool) -> Bool {
        guard panel.isVisible, !inDialog, imagePreview == nil else { return false }
        if dirty && !persist() { drawerInteraction.beginEditing(); panel.acceptsEditingFocus = true; panel.makeKeyAndOrderFront(nil); return false }
        let hadEditingFocus = drawerInteraction.state == .editing
        drawerInteraction.didHide()
        defaults.set(editor.selectedRange().location, forKey: "selection")
        openGeneration += 1; panel.orderOut(nil); animateHandle(expanded: false, animated: false); handle.orderFrontRegardless()
        if restoreFocus && hadEditingFocus, let app = previousApp, app.processIdentifier != ProcessInfo.processInfo.processIdentifier { app.activate(options: []) }
        return true
    }
    func clickedOutside() { if panel.isVisible && !inDialog { hidePanel(restoreFocus: false) } }
    @objc func deactivated() { imagePreview?.close(); clickedOutside() }
    @objc func hideAction() { hidePanel(restoreFocus: true) }
    @objc func menuToggle() { DispatchQueue.main.async { self.toggle() } }
    @objc func toggle() {
        if let imagePreview { imagePreview.close(); return }
        if drawerInteraction.state == .hovered { showPanel(onPointerScreen: false) }
        else if panel.isVisible { hidePanel(restoreFocus: true) }
        else { showPanel() }
    }
    func textDidChange(_ notification: Notification) {
        placeholder.isHidden = !editor.string.isEmpty
        dirty = true
        // Synchronous durable save per text change: no debounce window before closing.
        _ = persist()
        defaults.set(editor.selectedRange().location, forKey: "selection")
    }
    @discardableResult func persist() -> Bool {
        defer {
            saveIcon.image = symbol(dirty || store == nil || store?.isBlocked == true ? "exclamationmark.circle" : "checkmark.circle")
            saveIcon.contentTintColor = statusLabel.textColor
            settingsController?.refreshStatus()
        }
        guard let store else { statusLabel.stringValue = "无法保存 · 请导出文字"; statusLabel.textColor = .systemRed; return false }
        do {
            try store.save(editor.string, fontSizes: editor.savedFontSizes, images: editor.savedImages); dirty = false
            statusLabel.stringValue = "自动保存"; statusLabel.textColor = muted; statusLabel.toolTip = nil
            saveTimer?.invalidate(); saveTimer = nil
            return true
        } catch {
            statusLabel.stringValue = "未保存 · 正在重试"; statusLabel.textColor = NSColor(hex: 0x881337)
            statusLabel.toolTip = error.localizedDescription
            if saveTimer == nil { saveTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in _ = self?.persist() } }
            return false
        }
    }
    func buildStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = PaperIdentity.image(size: 18, template: true); statusItem.button?.toolTip = "QuickNote"
        statusItem.menu = optionsMenu()
    }
    func item(_ title: String, _ action: Selector) -> NSMenuItem { let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; return item }
    func optionsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(item(panel.isVisible ? "收起 QuickNote" : "打开 QuickNote", #selector(menuToggle)))
        menu.addItem(.separator())
        let settings = item("设置…", #selector(showSettings)); settings.keyEquivalent = ","; menu.addItem(settings)
        menu.addItem(item("检查更新…", #selector(checkForUpdates)))
        menu.addItem(.separator())
        let quitItem = item("退出 QuickNote", #selector(quit)); quitItem.keyEquivalent = "q"; menu.addItem(quitItem)
        return menu
    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.items.first?.title = panel.isVisible ? "收起 QuickNote" : "打开 QuickNote"
    }
    @objc func showSettings() {
        if settingsController == nil { settingsController = SettingsWindowController(app: self) }
        settingsController?.showWindow(nil)
    }
    @objc func checkForUpdates() { updater.check() }
    @objc func retrySave() { _ = persist() }
    @objc func openData() { if let store { NSWorkspace.shared.open(store.directory) } }
    func showImagePreview(_ attachment: PaperImage) {
        guard imagePreview == nil else { return }
        guard let data = store?.imageData(for: attachment.id), let image = NSImage(data: data) else {
            alert("无法打开图片", "原图文件缺失或已损坏，其他笔记内容不受影响。"); return
        }
        let selection = editor.selectedRange()
        let preview = PaperImagePreview(image: image, on: panel.screen ?? currentScreen)
        imagePreview = preview
        preview.onClose = { [weak self] in
            guard let self else { return }
            self.imagePreview = nil
            if self.panel.isVisible && NSApp.isActive {
                self.panel.makeKeyAndOrderFront(nil); self.panel.makeFirstResponder(self.editor)
                self.editor.setSelectedRange(selection)
            }
        }
        preview.makeKeyAndOrderFront(nil)
    }
    @objc func exportText() {
        inDialog = true; defer { inDialog = false }
        let save = NSSavePanel(); save.nameFieldStringValue = "QuickNote.txt"; save.allowedContentTypes = [.plainText]
        if save.runModal() == .OK, let url = save.url {
            do { try NoteStore.plainText(editor.string, images: editor.savedImages).write(to: url, atomically: true, encoding: .utf8) } catch { alert("导出失败", error.localizedDescription) }
        }
    }
    @objc func restoreBackup() {
        guard let store else { return }
        inDialog = true; defer { inDialog = false }
        let open = NSOpenPanel(); open.directoryURL = store.backupDirectory; open.allowedContentTypes = [.json]; open.message = "选择备份；恢复前会保留当前已保存内容。"; open.prompt = "查看备份"
        guard open.runModal() == .OK, let url = open.url else { return }
        do {
            let candidate = try store.backupText(at: url)
            let dialog = NSAlert(); dialog.messageText = "恢复这份备份？"; dialog.informativeText = "当前已保存内容会先备份。\n\n" + String(candidate.prefix(700)); dialog.addButton(withTitle: "恢复"); dialog.addButton(withTitle: "取消")
            guard dialog.runModal() == .alertFirstButtonReturn else { return }
            if dirty && !persist() { alert("当前内容尚未保存", "请先导出当前文字，再恢复备份。"); return }
            editor.string = try store.restore(from: url); editor.loadFontSizes(store.fontSizes); editor.loadImages(store.images); editor.undoManager?.removeAllActions(); editor.isEditable = true
            placeholder.isHidden = !editor.string.isEmpty; statusLabel.stringValue = "已恢复并保存"; statusLabel.textColor = muted
        } catch { alert("恢复失败", error.localizedDescription) }
    }
    @objc func about() { alert("QuickNote " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""), "一张随时续写的草稿纸。") }
    @objc func toggleLogin() {
        do { if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }; statusItem.menu = optionsMenu() }
        catch { alert("无法更改登录启动", error.localizedDescription) }
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if dirty && !persist() { showPanel(); alert("文字尚未保存", "请重试保存或导出文字后再退出。"); return .terminateCancel }
        defaults.set(editor.selectedRange().location, forKey: "selection")
        return .terminateNow
    }
    func alert(_ title: String, _ message: String) {
        let old = inDialog; inDialog = true; defer { inDialog = old }
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message; alert.addButton(withTitle: "好"); alert.runModal()
    }
    @objc func screenChanged() {
        let screen = NSScreen.screens.first { $0.frame.intersects(handle.frame) } ?? NSScreen.main ?? NSScreen.screens[0]
        positionHandle(on: screen)
        if panel.isVisible { showPanel(onPointerScreen: false, asPreview: drawerInteraction.state == .hovered) }
    }
    @objc func changeShortcut(_ sender: NSMenuItem) { registerShortcut(sender.tag); statusItem.menu = optionsMenu() }
    func registerShortcut(_ index: Int) {
        let previousIndex = defaults.integer(forKey: "shortcut")
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if hotHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
                guard let context else { return noErr }
                let app = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async { app.toggle() }; return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &hotHandler)
        }
        let choices: [(UInt32, UInt32)] = [(UInt32(kVK_Space), UInt32(optionKey)), (UInt32(kVK_ANSI_J), UInt32(cmdKey | shiftKey)), (UInt32(kVK_ANSI_K), UInt32(cmdKey | shiftKey))]
        let selected = min(max(index, 0), 2)
        let result = RegisterEventHotKey(choices[selected].0, choices[selected].1, EventHotKeyID(signature: 0x514e4f54, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        if result == noErr { defaults.set(selected, forKey: "shortcut"); handleView?.toolTip = "QuickNote · \(["⌥ Space", "⌘⇧J", "⌘⇧K"][selected]) · 点击落笔，可上下拖动" }
        else {
            let previous = min(max(previousIndex, 0), 2)
            RegisterEventHotKey(choices[previous].0, choices[previous].1, EventHotKeyID(signature: 0x514e4f54, id: 1), GetApplicationEventTarget(), 0, &hotKey)
            alert("快捷键被占用", "请在设置的“通用”页面选择另一组快捷键。侧边入口仍可使用。") }
    }
    func captureSettingsPreview() {
        showSettings()
        guard let controller = settingsController, let root = controller.window?.contentView, let directory = store?.directory else { return }
        for (index, name) in ["general", "data", "about"].enumerated() {
            controller.showPage(index)
            controller.window?.displayIfNeeded()
            guard let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { continue }
            root.cacheDisplay(in: root.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("settings-\(name).png"))
        }
        controller.showPage(1)
        if CommandLine.arguments.contains("--data-dir") { NSApp.terminate(nil) }
    }
    /// Deterministic native rendering and focus/persistence smoke test in an isolated directory.
    func capturePaperPreview() {
        guard CommandLine.arguments.contains("--data-dir"), let directory = store?.directory else { return }
        func capture(_ view: NSView, _ name: String) {
            view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
        }
        _ = hidePanel(restoreFocus: false)
        animateHandle(expanded: false, animated: false)
        capture(handleView, "paper-idle")
        _ = drawerInteraction.update(insideHandle: false, buttonDown: false, now: 0)
        let action = drawerInteraction.update(insideHandle: true, buttonDown: false, now: 1)
        showPanel(onPointerScreen: false, asPreview: true)
        capture(panel.contentView!, "paper-hover")
        let hoverPassed = action == .expandHandle && panel.isVisible && !panel.isKeyWindow && !editor.isEditable
        handleView.clicked?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let focusPassed = self.panel.firstResponder === self.editor && self.editor.isEditable
            self.editor.selectAll(nil)
            self.editor.insertText("这是用来验证自动换行的连续长句，文字超过便签宽度时应该自动换到下一行，最开始的文字始终保留在纸面内。ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", replacementRange: self.editor.selectedRange())
            self.editor.setSelectedRange(NSRange(location: 0, length: 7))
            let enlargeEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0, windowNumber: self.panel.windowNumber, context: nil, characters: "+", charactersIgnoringModifiers: "+", isARepeat: false, keyCode: 24)!
            NSApp.sendEvent(enlargeEvent)
            let selectionEnlarged = self.editor.savedFontSizes == [.init(location: 0, length: 7, size: 16)]
            let caret = NSRange(location: 0, length: 0)
            self.editor.setSelectedRange(caret)
            let shrinkEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: self.panel.windowNumber, context: nil, characters: "-", charactersIgnoringModifiers: "-", isARepeat: false, keyCode: 27)!
            NSApp.sendEvent(shrinkEvent)
            let fontSizesSaved = selectionEnlarged && self.editor.selectedRange() == caret && self.editor.savedFontSizes == [.init(location: 7, length: (self.editor.string as NSString).length - 7, size: 12)] && self.store?.fontSizes == self.editor.savedFontSizes && (try? NoteStore(directory: directory).fontSizes) == self.editor.savedFontSizes
            self.editor.layoutManager?.ensureLayout(for: self.editor.textContainer!)
            capture(self.panel.contentView!, "paper-editor")
            let scroll = self.editor.enclosingScrollView!
            let manager = self.editor.layoutManager!
            let glyphs = manager.glyphRange(for: self.editor.textContainer!)
            var lines = 0
            manager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, _, _ in lines += 1 }
            let wrapped = lines >= 4 && abs(self.editor.frame.width-scroll.contentSize.width) < 1 && abs(scroll.contentView.bounds.minX) < 0.5
            let saved = self.store?.text == self.editor.string && !self.dirty
            _ = self.hidePanel(restoreFocus: false)
            self.showPanel(onPointerScreen: false)
            let restored = self.editor.string == self.store?.text && self.panel.firstResponder === self.editor
            let imageChecks = self.checkImageWorkflow(directory: directory, capture: capture)
            let result = "hoverPreviewNoFocus=\(hoverPassed)\nclickFocus=\(focusPassed)\nsaved=\(saved)\nwrapped=\(wrapped)\nreopen=\(restored)\nfontSizesSaved=\(fontSizesSaved)\n" + imageChecks
            try? result.write(to: directory.appendingPathComponent("paper-smoke.txt"), atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }
    private func checkImageWorkflow(directory: URL, capture: (NSView, String) -> Void) -> String {
        let image = NSImage(size: NSSize(width: 1800, height: 1000), flipped: false) { rect in
            NSColor.systemBlue.setFill(); rect.fill(); return true
        }
        let clipboard = NSPasteboard.withUniqueName()
        defer { clipboard.releaseGlobally() }
        guard clipboard.writeObjects([image]), let manager = editor.layoutManager, let container = editor.textContainer else { return "imagePasted=false\n" }
        let undo = editor.undoManager
        undo?.beginUndoGrouping()
        editor.setSelectedRange(NSRange(location: 6, length: 0))
        let pasted = editor.pasteImage(from: clipboard)
        undo?.endUndoGrouping()
        guard let attachment = editor.savedImages.first else { return "imagePasted=false\n" }
        let persisted = pasted && (try? NoteStore(directory: directory).images) == [attachment]
        undo?.undo()
        let undone = editor.savedImages.isEmpty && store?.images.isEmpty == true
        undo?.redo()
        let redone = editor.savedImages == [attachment] && store?.images == [attachment]
        if let root = panel.contentView { capture(root, "paper-with-image") }
        manager.ensureLayout(for: container)
        let glyphs = manager.glyphRange(forCharacterRange: NSRange(location: attachment.location, length: 1), actualCharacterRange: nil)
        let bounds = manager.boundingRect(forGlyphRange: glyphs, in: container)
        let point = NSPoint(x: bounds.midX + editor.textContainerOrigin.x, y: bounds.midY + editor.textContainerOrigin.y)
        let position = editor.convert(point, to: nil)
        let thumbnailFits = bounds.width > 100 && bounds.width <= container.size.width && editor.imageIndex(at: point) == attachment.location
        let selection = editor.selectedRange()
        if let click = NSEvent.mouseEvent(with: .leftMouseDown, location: position, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { editor.mouseDown(with: click) }
        let opened = imagePreview?.isVisible == true && panel.isVisible
        if let root = imagePreview?.contentView { capture(root, "image-preview") }
        let control = imagePreview?.toolbar?.items.compactMap { $0.view as? NSSegmentedControl }.first
        control?.selectedSegment = 1
        if let control, let action = control.action { _ = NSApp.sendAction(action, to: control.target, from: control) }
        let zoomed = (imagePreview?.contentView as? NSScrollView)?.hasHorizontalScroller == true
        if let preview = imagePreview, let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: preview.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) { preview.sendEvent(escape) }
        let closed = imagePreview == nil && panel.isVisible && panel.firstResponder === editor && editor.selectedRange() == selection
        if let click = NSEvent.mouseEvent(with: .rightMouseDown, location: position, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
           let menu = editor.menu(for: click), let item = menu.items.last, let action = item.action {
            undo?.beginUndoGrouping(); _ = NSApp.sendAction(action, to: item.target, from: item); undo?.endUndoGrouping()
        }
        let deleted = editor.savedImages.isEmpty && store?.images.isEmpty == true
        undo?.undo()
        let restored = editor.savedImages == [attachment] && store?.images == [attachment]
        return "imagePasted=\(persisted)\nimageUndo=\(undone)\nimageRedo=\(redone)\nthumbnailFits=\(thumbnailFits)\nimageOpens=\(opened)\nactualSizeZoom=\(zoomed)\nescapeReturnsToEditor=\(closed)\nimageDeleted=\(deleted)\nimageDeleteUndo=\(restored)\n"
    }
    func capturePreview() {
        guard let root = panel.contentView, let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return }
        root.cacheDisplay(in: root.bounds, to: bitmap)
        let path = store!.directory.appendingPathComponent("preview.png")
        try? bitmap.representation(using: .png, properties: [:])?.write(to: path)
    }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
