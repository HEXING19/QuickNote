import XCTest
@testable import QuickNoteCore

final class DrawerInteractionTests: XCTestCase {
    func testHoverShowsPreviewAndLeavingClosesAfterGracePeriod() {
        var state = DrawerInteraction()
        XCTAssertEqual(state.update(insideHandle: true, buttonDown: false, now: 0), .expandHandle)
        XCTAssertEqual(state.state, .hovered)
        XCTAssertNil(state.update(insideHandle: false, buttonDown: false, now: 1))
        XCTAssertNil(state.update(insideHandle: false, buttonDown: false, now: 1.1))
        XCTAssertEqual(state.update(insideHandle: false, buttonDown: false, now: 1.3), .collapseHandle)
    }
    func testPointerInsideExpandedHandleKeepsItOpen() {
        var state = DrawerInteraction()
        _ = state.update(insideHandle: true, buttonDown: false, now: 0)
        _ = state.update(insideHandle: false, buttonDown: false, now: 1)
        XCTAssertNil(state.update(insideHandle: true, buttonDown: false, now: 1.1))
        XCTAssertNil(state.update(insideHandle: true, buttonDown: false, now: 5))
        XCTAssertEqual(state.state, .hovered)
    }
    func testCollapseCanExpandAgainAndDoesNotRepeatCollapse() {
        var state = DrawerInteraction()
        _ = state.update(insideHandle: true, buttonDown: false, now: 0)
        _ = state.update(insideHandle: false, buttonDown: false, now: 1)
        XCTAssertEqual(state.update(insideHandle: false, buttonDown: false, now: 2), .collapseHandle)
        XCTAssertEqual(state.state, .hidden)
        XCTAssertNil(state.update(insideHandle: false, buttonDown: false, now: 3))
        XCTAssertEqual(state.update(insideHandle: true, buttonDown: false, now: 4), .expandHandle)
    }
    func testDragKeepsExpandedHandleStable() {
        var state = DrawerInteraction()
        _ = state.update(insideHandle: true, buttonDown: false, now: 0)
        XCTAssertNil(state.update(insideHandle: false, buttonDown: true, now: 10))
        XCTAssertNil(state.update(insideHandle: false, buttonDown: true, now: 20))
        XCTAssertEqual(state.state, .hovered)
    }
    func testMovingFromHandleIntoNoteKeepsPreviewOpen() {
        var state = DrawerInteraction()
        XCTAssertEqual(state.update(insideHandle: true, buttonDown: false, now: 0), .expandHandle)
        _ = state.update(insideHandle: false, buttonDown: false, now: 1)
        XCTAssertNil(state.update(insideHandle: false, insidePanel: true, buttonDown: false, now: 1.1))
        XCTAssertNil(state.update(insideHandle: false, insidePanel: true, buttonDown: false, now: 5))
        XCTAssertEqual(state.state, .hovered)
    }
    func testClickedEditorNeverHidesOnPointerLeave() {
        var state = DrawerInteraction()
        _ = state.update(insideHandle: true, buttonDown: false, now: 0); state.beginEditing()
        XCTAssertNil(state.update(insideHandle: false, buttonDown: false, now: 100))
        XCTAssertEqual(state.state, .editing)
    }
    func testManualHideDoesNotImmediatelyReopenUnderStationaryPointer() {
        var state = DrawerInteraction()
        state.beginEditing(); state.didHide()
        XCTAssertNil(state.update(insideHandle: true, buttonDown: false, now: 0))
        _ = state.update(insideHandle: false, buttonDown: false, now: 1)
        XCTAssertEqual(state.update(insideHandle: true, buttonDown: false, now: 2), .expandHandle)
    }
    func testDraggingOverHandleDoesNotOpenUntilReleased() {
        var state = DrawerInteraction()
        XCTAssertNil(state.update(insideHandle: true, buttonDown: true, now: 0))
        XCTAssertEqual(state.update(insideHandle: true, buttonDown: false, now: 1), .expandHandle)
    }
}
