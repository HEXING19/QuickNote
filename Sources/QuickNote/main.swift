import AppKit
import Carbon
import ServiceManagement
import QuickNoteCore

extension NSColor {
    convenience init(hex: UInt32) { self.init(srgbRed: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255, blue: CGFloat(hex & 255)/255, alpha: 1) }
}
let ink = NSColor(hex: 0x18181b)
let muted = NSColor(hex: 0x71717a)
let line = NSColor(hex: 0xe4e4e7)
let chrome = NSColor(hex: 0xfafbfd)
func symbol(_ name: String) -> NSImage? { NSImage(systemSymbolName: name, accessibilityDescription: nil) }

final class NotePanel: NSPanel { override var canBecomeKey: Bool { true }; override var canBecomeMain: Bool { false } }
final class PaperView: NSTextView {
    var escape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) {
        if hasMarkedText() { super.cancelOperation(sender) } else { escape?() }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.option) && !event.modifierFlags.contains(.control) {
            switch event.charactersIgnoringModifiers {
            case "a": selectAll(nil); return true
            case "c": copy(nil); return true
            case "v": pasteAsPlainText(nil); return true
            case "x": cut(nil); return true
            case "z": if event.modifierFlags.contains(.shift) { undoManager?.redo() } else { undoManager?.undo() }; return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}
final class HandleView: NSView {
    var clicked: (() -> Void)?
    var moved: ((CGFloat) -> Void)?
    var finishedDrag: (() -> Void)?
    private var start: NSPoint?
    private var originY: CGFloat = 0
    private var dragging = false
    private var hovered = false
    override init(frame: NSRect) {
        super.init(frame: frame)
        toolTip = "随手记 · 点击展开，上下拖动"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("打开随手记，可上下拖动")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func accessibilityPerformPress() -> Bool { clicked?(); return true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        (hovered ? NSColor(hex: 0xf0f1f4) : NSColor.white).setFill(); path.fill()
        line.setStroke(); path.lineWidth = 1; path.stroke()
        if let img = symbol("square.and.pencil") {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            let icon = img.withSymbolConfiguration(config) ?? img
            icon.lockFocus(); ink.set(); NSRect(origin: .zero, size: icon.size).fill(using: .sourceAtop); icon.unlockFocus()
            icon.draw(in: NSRect(x: 7, y: (bounds.height-17)/2, width: 17, height: 17))
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate, NSWindowDelegate {
    var store: NoteStore?
    let defaults = UserDefaults.standard
    var panel: NotePanel!
    var handle: NSPanel!
    var handleView: HandleView!
    var editor: PaperView!
    var placeholder: NSTextField!
    var statusLabel: NSTextField!
    var pinButton: NSButton!
    var statusItem: NSStatusItem!
    var previousApp: NSRunningApplication?
    var globalMouse: Any?
    var localMouse: Any?
    var localKey: Any?
    var hotKey: EventHotKeyRef?
    var hotHandler: EventHandlerRef?
    var pinned = false
    var dirty = false
    var inDialog = false
    var saveTimer: Timer?
    var openGeneration = 0
    var currentScreen: NSScreen { handle?.screen ?? NSScreen.main ?? NSScreen.screens[0] }
    var preview: Bool { CommandLine.arguments.contains("--preview") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildApplicationMenu()
        let root: URL
        if let index = CommandLine.arguments.firstIndex(of: "--data-dir"), index + 1 < CommandLine.arguments.count {
            root = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        } else {
            root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QuickNote", isDirectory: true)
        }
        do { store = try NoteStore(directory: root) } catch { alert("无法打开记录目录", error.localizedDescription) }
        pinned = defaults.bool(forKey: "pinned")
        buildPanel(); buildHandle(); buildStatusMenu(); registerShortcut(defaults.integer(forKey: "shortcut"))
        if let message = store?.recoveryMessage { statusLabel.stringValue = message; statusLabel.textColor = NSColor(hex: 0x92400e) }
        globalMouse = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.clickedOutside() }
        }
        localMouse = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, event.window != self.panel && event.window != self.handle { self.clickedOutside() }
            return event
        }
        localKey = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let index = self.defaults.integer(forKey: "shortcut")
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let matches = (index == 0 && event.keyCode == 49 && flags == .option) || (index == 1 && event.keyCode == 38 && flags == [.command, .shift]) || (index == 2 && event.keyCode == 40 && flags == [.command, .shift])
            if matches { DispatchQueue.main.async { self.toggle() }; return nil }
            return event
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(deactivated), name: NSApplication.didResignActiveNotification, object: nil)
        if preview || !defaults.bool(forKey: "hasLaunched") { showPanel(onPointerScreen: false); defaults.set(true, forKey: "hasLaunched") }
        if preview {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.capturePreview() }
        }
    }
    func buildApplicationMenu() {
        let main = NSMenu()
        let app = NSMenuItem(); let appMenu = NSMenu(); app.submenu = appMenu
        appMenu.addItem(withTitle: "退出随手记", action: #selector(quit), keyEquivalent: "q").target = self
        main.addItem(app)
        let edit = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "编辑"); edit.submenu = menu
        for (title, selector, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            menu.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
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
        panel.title = "随手记"; panel.identifier = NSUserInterfaceItemIdentifier("QuickNoteEditor")
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.delegate = self
        let root = NSView(); root.wantsLayer = true; root.layer?.backgroundColor = chrome.cgColor; root.layer?.cornerRadius = 16; root.layer?.borderWidth = 1; root.layer?.borderColor = line.cgColor; root.layer?.masksToBounds = true
        root.appearance = NSAppearance(named: .aqua); panel.contentView = root
        let logo = NSImageView(image: symbol("square.and.pencil")!); logo.contentTintColor = ink; logo.translatesAutoresizingMaskIntoConstraints = false
        let title = label("随手记", size: 15, color: ink); title.font = .systemFont(ofSize: 15, weight: .semibold)
        pinButton = iconButton("pin", title: "固定窗口", action: #selector(togglePin))
        let close = iconButton("chevron.right", title: "收起（Esc）", action: #selector(hideAction))
        let topLine = NSView(); topLine.wantsLayer = true; topLine.layer?.backgroundColor = line.cgColor; topLine.translatesAutoresizingMaskIntoConstraints = false
        let bottomLine = NSView(); bottomLine.wantsLayer = true; bottomLine.layer?.backgroundColor = line.cgColor; bottomLine.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView(); scroll.drawsBackground = true; scroll.backgroundColor = .white; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.borderType = .noBorder; scroll.translatesAutoresizingMaskIntoConstraints = false
        editor = PaperView(frame: NSRect(x: 0, y: 0, width: 360, height: 420))
        editor.minSize = NSSize(width: 0, height: 0); editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false; editor.autoresizingMask = [.width]
        editor.textContainer?.containerSize = NSSize(width: 360, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.isRichText = false; editor.importsGraphics = false; editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
        editor.font = .systemFont(ofSize: 14); editor.textColor = NSColor(hex: 0x27272a); editor.insertionPointColor = NSColor(hex: 0x6366f1)
        editor.backgroundColor = .white; editor.textContainerInset = NSSize(width: 16, height: 20)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 7; editor.defaultParagraphStyle = paragraph
        editor.typingAttributes = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor(hex: 0x27272a), .paragraphStyle: paragraph]
        editor.string = store?.text ?? ""; editor.delegate = self; editor.isEditable = store != nil && store?.isBlocked == false
        editor.escape = { [weak self] in self?.hidePanel(restoreFocus: true) }
        scroll.documentView = editor
        placeholder = label("先记下来…", size: 14, color: NSColor(hex: 0xa1a1aa)); placeholder.isHidden = !editor.string.isEmpty
        statusLabel = label(store == nil ? "存储不可用 · 请先导出文字" : "已保存到本机", size: 11)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let esc = label("Esc 收起", size: 11)
        let more = iconButton("ellipsis", title: "备份、导出与设置", action: #selector(showMore))
        for v in [logo, title, pinButton!, close, topLine, scroll, placeholder!, bottomLine, statusLabel!, esc, more] { root.addSubview(v) }
        NSLayoutConstraint.activate([
            logo.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18), logo.topAnchor.constraint(equalTo: root.topAnchor, constant: 18), logo.widthAnchor.constraint(equalToConstant: 22), logo.heightAnchor.constraint(equalToConstant: 22),
            title.leadingAnchor.constraint(equalTo: logo.trailingAnchor, constant: 8), title.centerYAnchor.constraint(equalTo: logo.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8), close.centerYAnchor.constraint(equalTo: logo.centerYAnchor),
            pinButton.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -2), pinButton.centerYAnchor.constraint(equalTo: logo.centerYAnchor),
            topLine.topAnchor.constraint(equalTo: root.topAnchor, constant: 56), topLine.leadingAnchor.constraint(equalTo: root.leadingAnchor), topLine.trailingAnchor.constraint(equalTo: root.trailingAnchor), topLine.heightAnchor.constraint(equalToConstant: 1),
            scroll.topAnchor.constraint(equalTo: topLine.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 1), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -1), scroll.bottomAnchor.constraint(equalTo: bottomLine.topAnchor),
            placeholder.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 21), placeholder.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 20),
            bottomLine.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -40), bottomLine.leadingAnchor.constraint(equalTo: root.leadingAnchor), bottomLine.trailingAnchor.constraint(equalTo: root.trailingAnchor), bottomLine.heightAnchor.constraint(equalToConstant: 1),
            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16), statusLabel.centerYAnchor.constraint(equalTo: more.centerYAnchor), statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: esc.leadingAnchor, constant: -8),
            more.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6), more.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -3), esc.trailingAnchor.constraint(equalTo: more.leadingAnchor, constant: -4), esc.centerYAnchor.constraint(equalTo: more.centerYAnchor)
        ])
        updatePin()
    }
    func buildHandle() {
        handle = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 30, height: 52), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        handle.level = .floating; handle.hidesOnDeactivate = false; handle.isOpaque = false; handle.backgroundColor = .clear; handle.hasShadow = false
        handle.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        handleView = HandleView(frame: NSRect(x: 0, y: 0, width: 30, height: 52)); handle.contentView = handleView
        handleView.clicked = { [weak self] in self?.showPanel(onPointerScreen: false) }
        handleView.moved = { [weak self] y in
            guard let self else { return }; let area = self.currentScreen.visibleFrame
            self.handle.setFrameOrigin(NSPoint(x: area.maxX-28, y: min(max(y, area.minY+16), area.maxY-68)))
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
        let y = min(max(area.minY + area.height * fraction - 26, area.minY+16), area.maxY-68)
        handle.setFrame(NSRect(x: area.maxX-28, y: y, width: 30, height: 52), display: true)
    }
    func showPanel(onPointerScreen: Bool = true) {
        openGeneration += 1
        if !panel.isVisible { previousApp = NSWorkspace.shared.frontmostApplication }
        let screen = onPointerScreen ? (NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? currentScreen) : currentScreen
        positionHandle(on: screen)
        let area = screen.visibleFrame
        let height = min(CGFloat(520), area.height-32), width = min(CGFloat(360), area.width-24)
        let y = min(max(handle.frame.midY-height/2, area.minY+16), area.maxY-height-16)
        panel.setFrame(NSRect(x: area.maxX-width-2, y: y, width: width, height: height), display: true)
        handle.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(editor)
        let location = min(defaults.integer(forKey: "selection"), (editor.string as NSString).length)
        editor.setSelectedRange(NSRange(location: location, length: 0)); editor.scrollRangeToVisible(editor.selectedRange())
    }
    @discardableResult func hidePanel(restoreFocus: Bool) -> Bool {
        guard panel.isVisible, !inDialog else { return false }
        if dirty && !persist() { panel.makeKeyAndOrderFront(nil); return false }
        defaults.set(editor.selectedRange().location, forKey: "selection")
        openGeneration += 1; panel.orderOut(nil); handle.orderFrontRegardless()
        if restoreFocus, let app = previousApp, app.processIdentifier != ProcessInfo.processInfo.processIdentifier { app.activate(options: []) }
        return true
    }
    func clickedOutside() { if panel.isVisible && !pinned && !inDialog { hidePanel(restoreFocus: false) } }
    @objc func deactivated() { clickedOutside() }
    @objc func hideAction() { hidePanel(restoreFocus: true) }
    @objc func menuToggle() { DispatchQueue.main.async { self.toggle() } }
    @objc func toggle() { if panel.isVisible { hidePanel(restoreFocus: true) } else { showPanel() } }
    @objc func togglePin() { pinned.toggle(); defaults.set(pinned, forKey: "pinned"); updatePin() }
    func updatePin() {
        pinButton.image = symbol(pinned ? "pin.fill" : "pin")
        pinButton.contentTintColor = pinned ? ink : muted
        pinButton.toolTip = pinned ? "取消固定" : "固定窗口"
        pinButton.setAccessibilityLabel(pinButton.toolTip)
        pinButton.setAccessibilityValue(pinned ? "已固定" : "未固定")
    }
    func textDidChange(_ notification: Notification) {
        placeholder.isHidden = !editor.string.isEmpty
        dirty = true
        // Synchronous durable save per text change: no debounce window before closing.
        _ = persist()
        defaults.set(editor.selectedRange().location, forKey: "selection")
    }
    @discardableResult func persist() -> Bool {
        guard let store else { statusLabel.stringValue = "无法保存 · 请导出文字"; statusLabel.textColor = .systemRed; return false }
        do {
            try store.save(editor.string); dirty = false
            statusLabel.stringValue = "已保存到本机"; statusLabel.textColor = muted; statusLabel.toolTip = nil
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
        statusItem.button?.image = symbol("square.and.pencil"); statusItem.button?.toolTip = "随手记"
        statusItem.menu = optionsMenu()
    }
    func item(_ title: String, _ action: Selector) -> NSMenuItem { let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; return item }
    func optionsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("打开 / 收起随手记", #selector(menuToggle)))
        menu.addItem(item("固定 / 取消固定", #selector(togglePin)))
        menu.addItem(.separator())
        menu.addItem(item("导出为文本…", #selector(exportText)))
        menu.addItem(item("从备份恢复…", #selector(restoreBackup)))
        menu.addItem(item("打开数据与备份文件夹", #selector(openData)))
        menu.addItem(item("立即重试保存", #selector(retrySave)))
        let key = NSMenuItem(title: "全局快捷键", action: nil, keyEquivalent: "")
        let shortcuts = NSMenu()
        for (i, title) in ["⌥ Space", "⌘⇧J", "⌘⇧K"].enumerated() {
            let entry = item(title, #selector(changeShortcut(_:))); entry.tag = i; entry.state = defaults.integer(forKey: "shortcut") == i ? .on : .off; shortcuts.addItem(entry)
        }
        key.submenu = shortcuts; menu.addItem(key)
        let login = item("登录时启动", #selector(toggleLogin)); login.state = SMAppService.mainApp.status == .enabled ? .on : .off; menu.addItem(login)
        menu.addItem(.separator()); menu.addItem(item("关于随手记", #selector(about))); menu.addItem(item("退出随手记", #selector(quit)))
        return menu
    }
    @objc func showMore(_ sender: NSButton) {
        inDialog = true
        optionsMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
        inDialog = false
    }
    @objc func retrySave() { _ = persist() }
    @objc func openData() { if let store { NSWorkspace.shared.open(store.directory) } }
    @objc func exportText() {
        inDialog = true; defer { inDialog = false }
        let save = NSSavePanel(); save.nameFieldStringValue = "随手记.txt"; save.allowedContentTypes = [.plainText]
        if save.runModal() == .OK, let url = save.url {
            do { try editor.string.write(to: url, atomically: true, encoding: .utf8) } catch { alert("导出失败", error.localizedDescription) }
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
            editor.string = try store.restore(from: url); editor.undoManager?.removeAllActions(); editor.isEditable = true
            placeholder.isHidden = !editor.string.isEmpty; statusLabel.stringValue = "已恢复并保存"; statusLabel.textColor = muted
        } catch { alert("恢复失败", error.localizedDescription) }
    }
    @objc func about() { alert("随手记 1.0.0", "一张随时续写的草稿纸。\n\n点击右侧入口或使用全局快捷键。输入自动保存在本机，收起后继续保留。\n\n备份用于找回误删内容；退出前会检查保存结果。") }
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
        if panel.isVisible { showPanel(onPointerScreen: false) }
    }
    @objc func changeShortcut(_ sender: NSMenuItem) { registerShortcut(sender.tag); statusItem.menu = optionsMenu() }
    func registerShortcut(_ index: Int) {
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
        if result == noErr { defaults.set(selected, forKey: "shortcut"); handleView?.toolTip = "随手记 · \(["⌥ Space", "⌘⇧J", "⌘⇧K"][selected]) · 可上下拖动" }
        else { alert("快捷键被占用", "请从菜单栏的“全局快捷键”选择另一组。侧边入口仍可使用。") }
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
