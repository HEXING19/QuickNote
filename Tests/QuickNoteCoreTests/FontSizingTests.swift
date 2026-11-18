import AppKit
import XCTest
@testable import QuickNoteCore

final class FontSizingTests: XCTestCase {
    func testInsertionPointSizeMatchesBodyTextOnEmptyLines() {
        _ = NSApplication.shared
        let editor = FontSizingTextView()
        editor.isRichText = true
        editor.string = "文字\n\n文字\n"
        let normalLineRect = NSRect(x: 5, y: 0, width: 1, height: 24)
        let emptyLineRect = NSRect(x: 5, y: 24, width: 1, height: 12)

        editor.setSelectedRange(NSRange(location: 1, length: 0))
        editor.typingAttributes = [.font: NSFont.systemFont(ofSize: 14)]
        let bodyCaretSize = editor.visibleInsertionPointRect(normalLineRect).size
        XCTAssertEqual(bodyCaretSize, NSSize(width: 1, height: 14))

        for location in [3, 7] {
            editor.setSelectedRange(NSRange(location: location, length: 0))
            editor.typingAttributes = [.font: NSFont.systemFont(ofSize: 28)]
            XCTAssertEqual(editor.visibleInsertionPointRect(emptyLineRect).size, bodyCaretSize)
            XCTAssertEqual((editor.typingAttributes[.font] as? NSFont)?.pointSize, 28)
        }

        editor.string = ""
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertEqual(editor.visibleInsertionPointRect(emptyLineRect).size, bodyCaretSize)

        editor.string = "大字"
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        editor.typingAttributes = [.font: NSFont.systemFont(ofSize: 28)]
        XCTAssertEqual(editor.visibleInsertionPointRect(normalLineRect).height, 28)
    }

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

    func testCaretShortcutResizesWholeNoteAndPreservesMixedSizeDifference() {
        _ = NSApplication.shared
        let editor = FontSizingTextView()
        editor.isRichText = true
        editor.string = "大小"
        editor.loadFontSizes([.init(location: 0, length: 1, size: 20)])
        let caret = NSRange(location: 1, length: 0)
        editor.setSelectedRange(caret)
        let enlarge = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil, characters: "=", charactersIgnoringModifiers: "=", isARepeat: false, keyCode: 24)!
        let shrink = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil, characters: "-", charactersIgnoringModifiers: "-", isARepeat: false, keyCode: 27)!
        XCTAssertTrue(editor.handleFontSizeShortcut(enlarge))
        XCTAssertEqual(editor.savedFontSizes, [.init(location: 0, length: 1, size: 22), .init(location: 1, length: 1, size: 16)])
        XCTAssertTrue(editor.handleFontSizeShortcut(shrink))
        XCTAssertEqual(editor.savedFontSizes, [.init(location: 0, length: 1, size: 20)])
        XCTAssertEqual(editor.selectedRange(), caret)
    }
}
