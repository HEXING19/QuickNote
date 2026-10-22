import AppKit
import ServiceManagement

private final class SettingsSurface: NSView {
    override var isFlipped: Bool { true }
    init(_ color: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
    }
    required init?(coder: NSCoder) { fatalError() }
}

private final class PaperActionCell: NSButtonCell {
    override func drawBezel(withFrame frame: NSRect, in view: NSView) {
        (isHighlighted ? PaperIdentity.selected : PaperIdentity.sidebar).setFill()
        NSBezierPath(roundedRect: frame.insetBy(dx: 1, dy: 3), xRadius: 6, yRadius: 6).fill()
    }
    override func drawInterior(withFrame frame: NSRect, in view: NSView) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: isEnabled ? PaperIdentity.ink : PaperIdentity.muted]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: NSPoint(x: frame.midX-size.width/2, y: frame.midY-size.height/2), withAttributes: attributes)
    }

}

private final class PaperPopupCell: NSPopUpButtonCell {
    override func draw(withFrame frame: NSRect, in view: NSView) {
        (isHighlighted ? PaperIdentity.selected : PaperIdentity.sidebar).setFill()
        NSBezierPath(roundedRect: frame.insetBy(dx: 1, dy: 2), xRadius: 6, yRadius: 6).fill()
        (titleOfSelectedItem ?? "").draw(at: NSPoint(x: frame.minX+10, y: frame.midY-8), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: PaperIdentity.ink])
        symbol("chevron.down")?.draw(in: NSRect(x: frame.maxX-20, y: frame.midY-5, width: 10, height: 10))
    }
}

private final class PaperSwitchCell: NSButtonCell {
    override func draw(withFrame frame: NSRect, in view: NSView) {
        let track = NSRect(x: frame.minX+2, y: frame.midY-11, width: 38, height: 22)
        (state == .on ? PaperIdentity.accent : PaperIdentity.rule).setFill()
        NSBezierPath(roundedRect: track, xRadius: 11, yRadius: 11).fill()
        PaperIdentity.paper.setFill()
        NSBezierPath(ovalIn: NSRect(x: track.minX + (state == .on ? 18 : 2), y: track.minY+2, width: 18, height: 18)).fill()
    }
}

private final class SettingsNavigationCell: NSButtonCell {
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: cellFrame.insetBy(dx: 12, dy: 2), in: controlView)
    }
}

/// A single retained, light-only settings window. Actions use the existing note workflows.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    weak var app: AppDelegate?
    private let sidebar = SettingsSurface(PaperIdentity.sidebar)
    private let content = SettingsSurface(PaperIdentity.paper)
    private var navigation: [NSButton] = []
    private var page = 0
    private var saveStatus: NSTextField?
    private var retryButton: NSButton?

    init(app: AppDelegate) {
        self.app = app
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 500), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "QuickNote 设置"
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = PaperIdentity.paper
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        let root = SettingsSurface(PaperIdentity.paper)
        window.contentView = root
        sidebar.frame = NSRect(x: 0, y: 0, width: 180, height: 500)
        content.frame = NSRect(x: 181, y: 0, width: 579, height: 500)
        root.addSubview(sidebar); root.addSubview(content)
        let border = SettingsSurface(line); border.frame = NSRect(x: 180, y: 0, width: 1, height: 500); root.addSubview(border)
        for (index, entry) in [("通用", "gearshape"), ("数据与备份", "externaldrive"), ("关于", "info.circle")].enumerated() {
            let button = NSButton()
            button.cell = SettingsNavigationCell(textCell: "  " + entry.0)
            button.target = self; button.action = #selector(selectPage(_:))
            button.image = symbol(entry.1); button.imagePosition = .imageLeading
            button.alignment = .left; button.isBordered = false
            button.font = .systemFont(ofSize: 14, weight: .medium)
            button.tag = index; button.setAccessibilityLabel(entry.0)
            button.frame = NSRect(x: 12, y: 24 + index * 52, width: 156, height: 44)
            button.wantsLayer = true; button.layer?.cornerRadius = 7
            sidebar.addSubview(button); navigation.append(button)
        }
        showPage(0)
        window.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func showWindow(_ sender: Any?) {
        showPage(page)
        NSApp.activate(ignoringOtherApps: true)
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }
    func windowDidBecomeKey(_ notification: Notification) { refreshStatus() }
    @objc private func selectPage(_ sender: NSButton) { showPage(sender.tag) }

    private func text(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat = 13, color: NSColor = ink, weight: NSFont.Weight = .regular, in host: NSView? = nil) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.font = .systemFont(ofSize: size, weight: weight); label.textColor = color
        label.frame = NSRect(x: x, y: y, width: width, height: size + 9)
        (host ?? content).addSubview(label)
        return label
    }
    private func button(_ title: String, y: CGFloat, action: Selector, in host: NSView) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.cell = PaperActionCell(textCell: title)
        button.target = self; button.action = action
        button.bezelStyle = .rounded; button.bezelColor = PaperIdentity.sidebar; button.contentTintColor = ink; button.font = .systemFont(ofSize: 13)
        button.frame = NSRect(x: 336, y: y, width: 158, height: 32)
        host.addSubview(button)
        return button
    }
    private func group(height: CGFloat) -> SettingsSurface {
        let group = SettingsSurface(PaperIdentity.paper)
        group.frame = NSRect(x: 32, y: 94, width: 515, height: height)
        group.layer?.cornerRadius = 10
        group.layer?.borderWidth = 1; group.layer?.borderColor = PaperIdentity.rule.cgColor
        content.addSubview(group)
        return group
    }
    private func divider(y: CGFloat, in host: NSView) {
        let view = SettingsSurface(line)
        view.frame = NSRect(x: 20, y: y, width: 475, height: 1); host.addSubview(view)
    }
    func showPage(_ index: Int) {
        page = index
        content.subviews.forEach { $0.removeFromSuperview() }
        saveStatus = nil; retryButton = nil
        for (i, button) in navigation.enumerated() {
            button.layer?.backgroundColor = (i == page ? PaperIdentity.selected : .clear).cgColor
            button.contentTintColor = ink
            button.setAccessibilityValue(i == page ? "已选择" : "未选择")
        }
        _ = text(["通用", "数据与备份", "关于 QuickNote"][page], x: 32, y: 32, width: 480, size: 24, weight: .semibold)
        switch page {
        case 0:
            let card = group(height: 184)
            _ = text("全局快捷键", x: 20, y: 24, width: 280, size: 14, weight: .medium, in: card)
            _ = text("打开或收起 QuickNote", x: 20, y: 49, width: 280, color: muted, in: card)
            let picker = NSPopUpButton(frame: NSRect(x: 336, y: 28, width: 158, height: 30), pullsDown: false)
            picker.cell = PaperPopupCell(textCell: "", pullsDown: false)
            picker.contentTintColor = ink
            picker.addItems(withTitles: ["⌥ Space", "⌘⇧J", "⌘⇧K"])
            picker.selectItem(at: min(max(app?.defaults.integer(forKey: "shortcut") ?? 0, 0), 2))
            picker.target = self; picker.action = #selector(shortcutChanged(_:)); picker.setAccessibilityLabel("全局快捷键")
            card.addSubview(picker); divider(y: 91, in: card)
            _ = text("登录时启动", x: 20, y: 115, width: 280, size: 14, weight: .medium, in: card)
            _ = text("登录 Mac 时自动启动 QuickNote", x: 20, y: 140, width: 300, color: muted, in: card)
            let toggle = NSButton(frame: NSRect(x: 451, y: 118, width: 44, height: 26))
            toggle.cell = PaperSwitchCell(textCell: "")
            toggle.setButtonType(.switch)
            toggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
            toggle.target = self; toggle.action = #selector(loginChanged(_:)); toggle.setAccessibilityLabel("登录时启动")
            card.addSubview(toggle)
        case 1:
            let card = group(height: 330)
            let rows: [(String, String, String, Selector)] = [
                ("导出笔记", "将当前内容导出为纯文本文件。", "导出文本…", #selector(exportNote)),
                ("恢复内容", "选择备份，预览后再确认恢复。", "选择备份…", #selector(restoreNote)),
                ("本机文件", "查看笔记数据与备份文件。", "打开文件夹", #selector(openFolder))
            ]
            for (i, row) in rows.enumerated() {
                let y = CGFloat(i * 88)
                _ = text(row.0, x: 20, y: y + 19, width: 300, size: 14, weight: .medium, in: card)
                _ = text(row.1, x: 20, y: y + 45, width: 310, color: muted, in: card)
                let action = button(row.2, y: y + 25, action: row.3, in: card)
                action.isEnabled = i == 0 || app?.store != nil
                if i < rows.count - 1 { divider(y: y + 87, in: card) }
            }
            saveStatus = text("", x: 20, y: 287, width: 305, color: muted, in: card)
            retryButton = button("立即重试保存", y: 280, action: #selector(retrySave), in: card)
            refreshStatus()
        default:
            let icon = NSImageView(frame: NSRect(x: 32, y: 106, width: 56, height: 56))
            icon.image = PaperIdentity.image(size: 64); content.addSubview(icon)
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
            _ = text("QuickNote \(version)", x: 106, y: 109, width: 400, size: 19, weight: .semibold)
            _ = text("随手记录，随时续写。", x: 106, y: 140, width: 400, color: muted)
        }
    }
    func refreshStatus() {
        let failed = app?.dirty == true || app?.store == nil || app?.store?.isBlocked == true
        saveStatus?.stringValue = failed ? "未保存 · 请重试或导出文字" : ""
        saveStatus?.textColor = failed ? NSColor(hex: 0x92400e) : muted
        saveStatus?.isHidden = !failed
        saveStatus?.superview?.setFrameSize(NSSize(width: 515, height: failed ? 330 : 264))
        retryButton?.isHidden = !failed
    }
    @objc private func shortcutChanged(_ sender: NSPopUpButton) {
        app?.registerShortcut(sender.indexOfSelectedItem)
        sender.selectItem(at: app?.defaults.integer(forKey: "shortcut") ?? 0)
    }
    @objc private func loginChanged(_ sender: NSButton) {
        app?.toggleLogin()
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
        if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }
    @objc private func exportNote() { app?.exportText() }
    @objc private func restoreNote() { app?.restoreBackup(); refreshStatus() }
    @objc private func openFolder() { app?.openData() }
    @objc private func retrySave() { app?.retrySave(); refreshStatus() }
}
