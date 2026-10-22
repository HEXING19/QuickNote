import AppKit
import XCTest
@testable import QuickNoteCore

final class FontSizingTests: XCTestCase {
    func testSelectionShortcutUndoAndPersistence() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        let editor = FontSizingTextView(frame: window.contentView!.bounds)
        editor.isRichText = true; editor.allowsUndo = true
        window.contentView!.addSubview(editor)
        window.makeFirstResponder(editor)
        editor.font = .systemFont(ofSize: 14)
        editor.string = "前📝放大后"
        let selection = NSRange(location: 3, length: 2)
        editor.setSelectedRange(selection)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "+", charactersIgnoringModifiers: "+", isARepeat: false, keyCode: 24)!
        editor.undoManager?.beginUndoGrouping()
        XCTAssertTrue(editor.performKeyEquivalent(with: event))
        editor.undoManager?.endUndoGrouping()
        XCTAssertEqual(editor.selectedRange(), selection)
        XCTAssertEqual(editor.savedFontSizes, [.init(location: 3, length: 2, size: 16)])
        XCTAssertEqual((editor.textStorage!.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize, 14)
        editor.undoManager?.undo()
        XCTAssertTrue(editor.savedFontSizes.isEmpty)
        editor.undoManager?.redo()
        XCTAssertEqual(editor.savedFontSizes.first?.size, 16)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try NoteStore(directory: directory)
        try store.save(editor.string, fontSizes: editor.savedFontSizes)
        let reopened = try NoteStore(directory: directory)
        editor.string = reopened.text
        editor.loadFontSizes(reopened.fontSizes)
        XCTAssertEqual(editor.savedFontSizes, [.init(location: 3, length: 2, size: 16)])
        try store.save("替换内容", forceSnapshot: true)
        let backup = try XCTUnwrap(store.backups().first)
        _ = try store.restore(from: backup)
        XCTAssertEqual(store.fontSizes, reopened.fontSizes)
        window.orderOut(nil)
    }

    func testEmptySelectionDoesNotResizeAndMixedSizesKeepDifference() {
        _ = NSApplication.shared
        let editor = FontSizingTextView()
        editor.isRichText = true
        editor.string = "大小"
        editor.loadFontSizes([.init(location: 0, length: 1, size: 20)])
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        editor.enlargeSelectedText(nil)
        XCTAssertEqual(editor.savedFontSizes, [.init(location: 0, length: 1, size: 20)])
        editor.selectAll(nil)
        editor.enlargeSelectedText(nil)
        XCTAssertEqual(editor.savedFontSizes, [.init(location: 0, length: 1, size: 22), .init(location: 1, length: 1, size: 16)])
    }
}
