import XCTest
@testable import QuickNoteCore
final class NoteStoreTests: XCTestCase {
    func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testUnicodeSurvivesReopenAndEmptyEdits() throws {
        let dir = try temporary()
        let store = try NoteStore(directory: dir)
        try store.save("随手记录\n第二行 📝")
        XCTAssertEqual(try NoteStore(directory: dir).text, "随手记录\n第二行 📝")
        try store.save("")
        XCTAssertEqual(try NoteStore(directory: dir).text, "")
        XCTAssertFalse(store.backups().isEmpty)
    }
    func testCorruptionRecoversPreviousAndPreservesOriginal() throws {
        let dir = try temporary()
        let store = try NoteStore(directory: dir)
        try store.save("上一份完整记录")
        try store.save("最新记录")
        try Data("corrupt".utf8).write(to: store.primary)
        let reopened = try NoteStore(directory: dir)
        XCTAssertEqual(reopened.text, "上一份完整记录")
        XCTAssertNotNil(reopened.recoveryMessage)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.hasPrefix("unreadable-") })
    }
    func testUnrecoverableFileCannotBeOverwritten() throws {
        let dir = try temporary()
        let primary = dir.appendingPathComponent("scratchpad.json")
        try Data("broken".utf8).write(to: primary)
        let store = try NoteStore(directory: dir)
        XCTAssertTrue(store.isBlocked)
        XCTAssertThrowsError(try store.save(""))
        XCTAssertEqual(try String(contentsOf: primary, encoding: .utf8), "broken")
    }
    func testRestoreProtectsCurrentText() throws {
        let store = try NoteStore(directory: temporary())
        try store.save("要找回的内容")
        try store.save("后来误删", forceSnapshot: true)
        let backup = try XCTUnwrap(store.backups().first)
        XCTAssertEqual(try store.restore(from: backup), "要找回的内容")
        XCTAssertEqual(try NoteStore(directory: store.directory).text, "要找回的内容")
        XCTAssertTrue(try store.backups().contains { try store.backupText(at: $0) == "后来误删" })
    }
    func testWriteFailureLeavesPriorText() throws {
        let store = try NoteStore(directory: temporary())
        try store.save("已保存")
        try FileManager.default.removeItem(at: store.primary)
        try FileManager.default.createDirectory(at: store.primary, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.save("尚未保存"))
        XCTAssertEqual(store.text, "已保存")
    }

    func testImageSurvivesReopenDeletionAndBackupRestore() throws {
        let store = try NoteStore(directory: temporary())
        try store.save("原有文字 📝")
        let bytes = Data([18, 54, 62])
        let id = try store.storeImage(bytes)
        XCTAssertEqual(try store.storeImage(bytes), id)
        let text = "原有文字 📝\n\(NoteStore.imageMarker)\n继续写"
        let image = NoteStore.ImageRun(location: ("原有文字 📝\n" as NSString).length, id: id)
        try store.save(text, images: [image])
        let reopened = try NoteStore(directory: store.directory)
        XCTAssertEqual(reopened.images, [image])
        XCTAssertEqual(reopened.imageData(for: id), bytes)
        try reopened.save("删除图片", forceSnapshot: true)
        let backup = try XCTUnwrap(reopened.backups().first { (try? reopened.backupText(at: $0)) == "原有文字 📝\n[图片]\n继续写" })
        XCTAssertEqual(try reopened.restore(from: backup), text)
        XCTAssertEqual(reopened.images, [image])
        XCTAssertEqual(reopened.imageData(for: id), bytes)
    }

    func testMissingImageDoesNotDiscardTextOrImageReference() throws {
        let directory = try temporary()
        let store = try NoteStore(directory: directory)
        let id = try store.storeImage(Data([123]))
        let image = NoteStore.ImageRun(location: 0, id: id)
        let text = "\(NoteStore.imageMarker)\n仍需保留的文字"
        try store.save(text, images: [image])
        try FileManager.default.removeItem(at: directory.appendingPathComponent("Images"))
        let reopened = try NoteStore(directory: directory)
        XCTAssertEqual(reopened.text, text)
        XCTAssertEqual(reopened.images, [image])
        XCTAssertNil(reopened.imageData(for: id))
        XCTAssertThrowsError(try store.save("普通文字", images: [image]))
        XCTAssertThrowsError(try store.save(text, images: [image, image]))
        XCTAssertThrowsError(try store.save(text, images: [.init(location: 0, id: "../previous.json")]))
    }
}
